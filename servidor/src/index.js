// Servidor de Marles 360: guarda los videos en R2 y muestra las páginas
// de descarga (un video) y de galería (todo el evento).
import { paginaVideo, paginaEvento, paginaNoEncontrado } from './paginas.js';

const ID = /^[a-z0-9]{4,16}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const partes = url.pathname.split('/').filter(Boolean);
    try {
      if (partes[0] === 'api') return await api(request, env, url, partes.slice(1));
      if (request.method !== 'GET' && request.method !== 'HEAD') return texto('Método no permitido', 405);

      const [tipo, evento, archivo] = partes;
      if (tipo === 'v' && ID.test(evento ?? '') && ID.test(archivo ?? '')) {
        const existe = await env.VIDEOS.head(claveVideo(evento, archivo));
        if (!existe) return html(paginaNoEncontrado(), 404);
        const datos = await datosEvento(env, evento);
        return html(paginaVideo({ evento, id: archivo, nombre: datos?.nombre }));
      }
      if (tipo === 'e' && ID.test(evento ?? '')) {
        const videos = await listarVideos(env, evento);
        if (videos.length === 0) return html(paginaNoEncontrado(), 404);
        const datos = await datosEvento(env, evento);
        return html(paginaEvento({ evento, nombre: datos?.nombre, videos }));
      }
      if (tipo === 'f' && ID.test(evento ?? '') && /^[a-z0-9]{4,16}\.mp4$/.test(archivo ?? '')) {
        return await servirVideo(request, env, evento, archivo.slice(0, -4), url.searchParams.has('descargar'));
      }
      return html(paginaNoEncontrado(), 404);
    } catch (err) {
      console.error(err);
      return texto('Error del servidor', 500);
    }
  },
};

async function api(request, env, url, partes) {
  if (!env.CLAVE || request.headers.get('Authorization') !== `Bearer ${env.CLAVE}`) {
    return texto('Clave incorrecta', 401);
  }
  const [accion, ...resto] = partes;

  if (accion === 'ping' && request.method === 'GET') return json({ ok: true });

  if (accion === 'evento' && request.method === 'PUT' && ID.test(resto[0] ?? '')) {
    const { nombre, fecha } = await request.json();
    await env.VIDEOS.put(`e/${resto[0]}.json`, JSON.stringify({ nombre: String(nombre ?? '').slice(0, 120), fecha }), {
      httpMetadata: { contentType: 'application/json' },
    });
    return json({ ok: true });
  }

  if (accion === 'subir' && request.method === 'PUT') {
    const clave = rutaValida(resto);
    if (!clave) return texto('Ruta inválida', 400);
    await env.VIDEOS.put(clave, request.body, { httpMetadata: { contentType: 'video/mp4' } });
    return json({ ok: true });
  }

  // Subida por partes, para videos de más de 90 MB.
  if (accion === 'mpu') {
    const [paso, ...ruta] = resto;
    const clave = rutaValida(ruta);
    if (!clave) return texto('Ruta inválida', 400);
    const uploadId = url.searchParams.get('uploadId');

    if (paso === 'crear' && request.method === 'POST') {
      const mpu = await env.VIDEOS.createMultipartUpload(clave, { httpMetadata: { contentType: 'video/mp4' } });
      return json({ uploadId: mpu.uploadId });
    }
    if (paso === 'parte' && request.method === 'PUT' && uploadId) {
      const n = Number(url.searchParams.get('n'));
      if (!Number.isInteger(n) || n < 1 || n > 10000) return texto('Parte inválida', 400);
      const parte = await env.VIDEOS.resumeMultipartUpload(clave, uploadId).uploadPart(n, request.body);
      return json({ partNumber: parte.partNumber, etag: parte.etag });
    }
    if (paso === 'completar' && request.method === 'POST' && uploadId) {
      const { partes } = await request.json();
      await env.VIDEOS.resumeMultipartUpload(clave, uploadId).complete(partes);
      return json({ ok: true });
    }
  }
  return texto('No encontrado', 404);
}

function rutaValida([evento, id] = []) {
  return ID.test(evento ?? '') && ID.test(id ?? '') ? claveVideo(evento, id) : null;
}

const claveVideo = (evento, id) => `v/${evento}/${id}.mp4`;

async function datosEvento(env, evento) {
  const obj = await env.VIDEOS.get(`e/${evento}.json`);
  return obj ? obj.json() : null;
}

async function listarVideos(env, evento) {
  const videos = [];
  let cursor;
  do {
    const r = await env.VIDEOS.list({ prefix: `v/${evento}/`, cursor });
    for (const o of r.objects) videos.push({ id: o.key.split('/').pop().slice(0, -4), subido: o.uploaded });
    cursor = r.truncated ? r.cursor : undefined;
  } while (cursor);
  return videos.sort((a, b) => b.subido - a.subido);
}

async function servirVideo(request, env, evento, id, descargar) {
  const obj = await env.VIDEOS.get(claveVideo(evento, id), { range: request.headers, onlyIf: request.headers });
  if (!obj) return texto('Video no encontrado', 404);
  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set('etag', obj.httpEtag);
  headers.set('accept-ranges', 'bytes');
  headers.set('cache-control', 'public, max-age=86400');
  if (descargar) headers.set('content-disposition', `attachment; filename="marles360-${id}.mp4"`);
  if (!('body' in obj)) return new Response(null, { status: 304, headers });

  let status = 200;
  if (obj.range && request.headers.has('range')) {
    const inicio = obj.range.offset ?? 0;
    const largo = obj.range.length ?? obj.size - inicio;
    headers.set('content-range', `bytes ${inicio}-${inicio + largo - 1}/${obj.size}`);
    headers.set('content-length', String(largo));
    status = 206;
  } else {
    headers.set('content-length', String(obj.size));
  }
  return new Response(request.method === 'HEAD' ? null : obj.body, { status, headers });
}

const html = (cuerpo, status = 200) =>
  new Response(cuerpo, { status, headers: { 'content-type': 'text/html; charset=utf-8' } });
const json = (datos, status = 200) =>
  new Response(JSON.stringify(datos), { status, headers: { 'content-type': 'application/json' } });
const texto = (t, status) => new Response(t, { status, headers: { 'content-type': 'text/plain; charset=utf-8' } });
