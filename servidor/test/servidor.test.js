import { test } from 'node:test';
import assert from 'node:assert/strict';
import servidor from '../src/index.js';
import { paginaVideo } from '../src/paginas.js';

const env = { CLAVE: 'secreta', VIDEOS: {} };
const pedir = (ruta, init) => servidor.fetch(new Request(`https://x.dev${ruta}`, init), env);

test('la API rechaza una clave incorrecta', async () => {
  const r = await pedir('/api/ping', { headers: { Authorization: 'Bearer otra' } });
  assert.equal(r.status, 401);
});

test('la API acepta la clave correcta', async () => {
  const r = await pedir('/api/ping', { headers: { Authorization: 'Bearer secreta' } });
  assert.equal(r.status, 200);
});

test('rutas con caracteres raros no llegan al almacenamiento', async () => {
  const r = await pedir('/api/subir/../otro', { method: 'PUT', headers: { Authorization: 'Bearer secreta' }, body: 'x' });
  assert.notEqual(r.status, 200);
});

test('el nombre del evento se escapa en la página', () => {
  const { cuerpo: html } = paginaVideo({ evento: 'abc123', id: 'v1v1v1v1', nombre: '<script>alert(1)</script>' });
  assert.ok(!html.includes('<script>alert(1)'));
  assert.ok(html.includes('&lt;script&gt;'));
});

test('un rango "últimos N bytes" se responde con la parte correcta', async () => {
  const cuerpo = new Uint8Array(1000);
  const envR = {
    CLAVE: 'x',
    VIDEOS: { get: async () => ({ size: 1000, range: { suffix: 100 }, body: cuerpo.slice(900), httpEtag: '"e"', writeHttpMetadata() {} }) },
  };
  const r = await servidor.fetch(new Request('https://x.dev/f/abc123/v1v1v1v1.mp4', { headers: { range: 'bytes=-100' } }), envR);
  assert.equal(r.status, 206);
  assert.equal(r.headers.get('content-range'), 'bytes 900-999/1000');
  assert.equal(r.headers.get('content-length'), '100');
});

test('una galería vacía no dice que el video expiró', async () => {
  const envG = { CLAVE: 'x', VIDEOS: { list: async () => ({ objects: [], truncated: false }) } };
  const r = await servidor.fetch(new Request('https://x.dev/e/abc123'), envG);
  assert.equal(r.status, 404);
  assert.match(await r.text(), /aún no tiene videos/);
});

// Una petición hecha a mano, para probar cabeceras que fetch no deja poner.
const peticion = (ruta, { method = 'PUT', headers = {}, body = 'x' } = {}) => ({
  url: `https://x.dev${ruta}`,
  method,
  body,
  headers: new Headers({ Authorization: 'Bearer secreta', ...headers }),
});

test('una subida sin tamaño se rechaza (R2 lo necesita)', async () => {
  const r = await servidor.fetch(peticion('/api/subir/abc123/v1v1v1v1', { headers: {} }), env);
  assert.equal(r.status, 411);
});

test('una subida de más de 100 MB se rechaza', async () => {
  const r = await servidor.fetch(peticion('/api/subir/abc123/v1v1v1v1', { headers: { 'content-length': String(200 * 1024 * 1024) } }), env);
  assert.equal(r.status, 413);
});

test('sin clave configurada en el servidor, nadie puede subir', async () => {
  const r = await servidor.fetch(peticion('/api/ping', { method: 'GET' }), { VIDEOS: {} });
  assert.equal(r.status, 401);
});
