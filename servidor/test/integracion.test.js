// Pruebas del servidor completo dentro de workerd (el mismo motor de
// Cloudflare), con un R2 simulado en memoria. Cubren la subida, las páginas,
// la descarga por partes y los intentos de abuso.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare } from 'miniflare';
import { opcionesServidor } from '../herramientas/opciones.mjs';

const CLAVE = 'una-clave-larga-de-prueba';
let mf;

before(async () => {
  mf = new Miniflare(opcionesServidor({ clave: CLAVE }));
  await mf.ready;
});

after(async () => {
  await mf?.dispose();
});

const auth = { Authorization: `Bearer ${CLAVE}` };
const pedir = (ruta, init = {}) => mf.dispatchFetch(`http://localhost${ruta}`, init);
const bytes = (n, semilla = 1) => Uint8Array.from({ length: n }, (_, i) => (i * 31 + semilla) % 251);

async function subir(evento, id, datos) {
  const r = await pedir(`/api/subir/${evento}/${id}`, {
    method: 'PUT',
    headers: { ...auth, 'content-type': 'video/mp4' },
    body: datos,
  });
  assert.equal(r.status, 200, await r.text());
}

test('ping con la clave correcta, 401 con otra o sin ella', async () => {
  assert.equal((await pedir('/api/ping', { headers: auth })).status, 200);
  assert.equal((await pedir('/api/ping', { headers: { Authorization: 'Bearer casi' } })).status, 401);
  assert.equal((await pedir('/api/ping')).status, 401);
  assert.equal((await pedir('/api/ping', { headers: { Authorization: CLAVE } })).status, 401);
});

test('subir, ver la página, descargar y pedir partes del video', async () => {
  const video = bytes(5000);
  await subir('boda24', 'vid1abcd', video);

  const pagina = await pedir('/v/boda24/vid1abcd');
  assert.equal(pagina.status, 200);
  const html = await pagina.text();
  assert.match(html, /Enviar por WhatsApp/);
  assert.match(html, /\/f\/boda24\/vid1abcd\.mp4/);

  const completo = await pedir('/f/boda24/vid1abcd.mp4');
  assert.equal(completo.status, 200);
  assert.equal(completo.headers.get('content-type'), 'video/mp4');
  assert.deepEqual(new Uint8Array(await completo.arrayBuffer()), video);

  const parte = await pedir('/f/boda24/vid1abcd.mp4', { headers: { range: 'bytes=100-199' } });
  assert.equal(parte.status, 206);
  assert.equal(parte.headers.get('content-range'), 'bytes 100-199/5000');
  assert.deepEqual(new Uint8Array(await parte.arrayBuffer()), video.slice(100, 200));

  const final = await pedir('/f/boda24/vid1abcd.mp4', { headers: { range: 'bytes=-50' } });
  assert.equal(final.status, 206);
  assert.equal(final.headers.get('content-range'), 'bytes 4950-4999/5000');
  assert.deepEqual(new Uint8Array(await final.arrayBuffer()), video.slice(4950));

  // Lo primero que pide Chrome al abrir un video: desde el byte 0 hasta el final.
  const desdeCero = await pedir('/f/boda24/vid1abcd.mp4', { headers: { range: 'bytes=0-' } });
  assert.equal(desdeCero.status, 206);
  assert.equal(desdeCero.headers.get('content-range'), 'bytes 0-4999/5000');
  assert.equal(desdeCero.headers.get('content-length'), '5000');
  assert.deepEqual(new Uint8Array(await desdeCero.arrayBuffer()), video);

  const hastaElFinal = await pedir('/f/boda24/vid1abcd.mp4', { headers: { range: 'bytes=4990-' } });
  assert.equal(hastaElFinal.status, 206);
  assert.equal(hastaElFinal.headers.get('content-range'), 'bytes 4990-4999/5000');
  assert.deepEqual(new Uint8Array(await hastaElFinal.arrayBuffer()), video.slice(4990));

  const fuera = await pedir('/f/boda24/vid1abcd.mp4', { headers: { range: 'bytes=99999-' } });
  assert.equal(fuera.status, 416);
  await fuera.text();

  const cabeza = await pedir('/f/boda24/vid1abcd.mp4', { method: 'HEAD' });
  assert.equal(cabeza.status, 200);
  assert.equal(cabeza.headers.get('content-length'), '5000');
  assert.equal((await cabeza.arrayBuffer()).byteLength, 0);

  const etag = completo.headers.get('etag');
  const igual = await pedir('/f/boda24/vid1abcd.mp4', { headers: { 'if-none-match': etag } });
  assert.equal(igual.status, 304);

  const descarga = await pedir('/f/boda24/vid1abcd.mp4?descargar');
  assert.match(descarga.headers.get('content-disposition'), /attachment; filename="marles360-vid1abcd\.mp4"/);
  await descarga.arrayBuffer();
});

test('la galería lista los videos del evento con su nombre escapado', async () => {
  const r = await pedir('/api/evento/xv2026', {
    method: 'PUT',
    headers: { ...auth, 'content-type': 'application/json' },
    body: JSON.stringify({ nombre: 'XV de <b>Sofía</b> "la reina"', fecha: '2026-11-14T00:00:00.000' }),
  });
  assert.equal(r.status, 200);
  await subir('xv2026', 'aaaa1111', bytes(100));
  await subir('xv2026', 'bbbb2222', bytes(100, 2));

  const galeria = await pedir('/e/xv2026');
  assert.equal(galeria.status, 200);
  const html = await galeria.text();
  assert.match(html, /2 videos/);
  assert.match(html, /XV de &lt;b&gt;Sofía&lt;\/b&gt; &quot;la reina&quot;/);
  assert.ok(!html.includes('<b>Sofía'));
  assert.match(html, /\/v\/xv2026\/aaaa1111/);
});

test('las páginas llevan cabeceras de seguridad y el script su nonce', async () => {
  await subir('segur1', 'cccc3333', bytes(10));
  const r = await pedir('/v/segur1/cccc3333');
  const csp = r.headers.get('content-security-policy');
  assert.ok(csp, 'falta Content-Security-Policy');
  const nonce = /script-src 'nonce-([^']+)'/.exec(csp)?.[1];
  assert.ok(nonce, 'el CSP no tiene nonce');
  const html = await r.text();
  assert.ok(html.includes(`<script nonce="${nonce}">`), 'el script no lleva el nonce');
  assert.ok(!/<script>/.test(html), 'hay un script sin nonce');
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(r.headers.get('x-frame-options'), 'DENY');

  const otra = await pedir('/v/segur1/cccc3333');
  assert.notEqual(/nonce-([^']+)/.exec(otra.headers.get('content-security-policy'))[1], nonce);
  await otra.text();
});

test('subida por partes (videos de más de 90 MB)', async () => {
  const MB = 1024 * 1024;
  const video = bytes(11 * MB, 3);
  const crear = await pedir('/api/mpu/crear/grande/gggg4444', { method: 'POST', headers: auth });
  assert.equal(crear.status, 200);
  const { uploadId } = await crear.json();
  const partes = [];
  for (let n = 1, inicio = 0; inicio < video.length; n++, inicio += 5 * MB) {
    const r = await pedir(`/api/mpu/parte/grande/gggg4444?uploadId=${encodeURIComponent(uploadId)}&n=${n}`, {
      method: 'PUT',
      headers: auth,
      body: video.slice(inicio, inicio + 5 * MB),
    });
    assert.equal(r.status, 200, await r.clone().text());
    partes.push(await r.json());
  }
  const completar = await pedir(`/api/mpu/completar/grande/gggg4444?uploadId=${encodeURIComponent(uploadId)}`, {
    method: 'POST',
    headers: { ...auth, 'content-type': 'application/json' },
    body: JSON.stringify({ partes }),
  });
  assert.equal(completar.status, 200, await completar.clone().text());
  const r = await pedir('/f/grande/gggg4444.mp4');
  const recibido = new Uint8Array(await r.arrayBuffer());
  assert.equal(recibido.length, video.length);
  assert.deepEqual(recibido.slice(-1000), video.slice(-1000));
});

test('borrar un video lo quita de la página y del archivo', async () => {
  await subir('borrar', 'dddd5555', bytes(10));
  const sinClave = await pedir('/api/video/borrar/dddd5555', { method: 'DELETE' });
  assert.equal(sinClave.status, 401);
  const r = await pedir('/api/video/borrar/dddd5555', { method: 'DELETE', headers: auth });
  assert.equal(r.status, 200);
  assert.equal((await pedir('/v/borrar/dddd5555')).status, 404);
  assert.equal((await pedir('/f/borrar/dddd5555.mp4')).status, 404);
  assert.equal((await pedir('/api/video/borrar/dddd5555', { method: 'DELETE', headers: auth })).status, 404);
});

test('intentos de abuso no llegan al almacenamiento', async () => {
  const casos = [
    ['/api/subir/../../e/x', 'PUT'],
    ['/api/subir/ABC123/v1v1v1v1', 'PUT'],
    ['/api/subir/abc123/v1v1v1v1/extra', 'PUT'],
    ['/api/subir/abc123/v1%2F..%2Fx', 'PUT'],
    ['/api/subir/abc/v1v1v1v1', 'PUT'],
    ['/api/subir/abc123/' + 'a'.repeat(40), 'PUT'],
    ['/api/video/abc123', 'DELETE'],
  ];
  for (const [ruta, method] of casos) {
    const r = await pedir(ruta, { method, headers: auth, body: method === 'PUT' ? 'x' : undefined });
    assert.ok(r.status >= 400, `${method} ${ruta} respondió ${r.status}`);
    await r.text();
  }
  for (const ruta of ['/v/../e/x', '/f/abc123/v1v1v1v1.MP4', '/f/abc123/v1v1v1v1.mp4.html', '/e/abc123/extra', '/x']) {
    const r = await pedir(ruta);
    assert.equal(r.status, 404, ruta);
    await r.text();
  }
  const post = await pedir('/v/abc123/v1v1v1v1', { method: 'POST' });
  assert.equal(post.status, 405);
  await post.text();
});

test('JSON roto o partes falsas responden 400, no 500', async () => {
  const roto = await pedir('/api/evento/abc123', { method: 'PUT', headers: auth, body: '{no es json' });
  assert.equal(roto.status, 400);
  await roto.text();
  const falso = await pedir('/api/mpu/completar/abc123/v1v1v1v1?uploadId=x', {
    method: 'POST',
    headers: auth,
    body: JSON.stringify({ partes: [{ partNumber: 'uno' }] }),
  });
  assert.equal(falso.status, 400);
  await falso.text();
});

test('una fecha que no es fecha no se guarda', async () => {
  const r = await pedir('/api/evento/fecha1', {
    method: 'PUT',
    headers: auth,
    body: JSON.stringify({ nombre: 'Prueba', fecha: '<script>' }),
  });
  assert.equal(r.status, 200);
  await r.text();
});

test('una galería vacía responde 404 con un mensaje claro', async () => {
  const r = await pedir('/e/vacio99');
  assert.equal(r.status, 404);
  assert.match(await r.text(), /aún no tiene videos/);
});
