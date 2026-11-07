// Servidor de Marles 360: guarda los videos en R2 y muestra las páginas
// de descarga (un video) y de galería (todo el evento).
import { paginaVideo, paginaEvento, paginaNoEncontrado } from './paginas.js';

// Identificadores que genera la app (letras minúsculas y números). Todo lo que
// llega por la dirección se valida con esto antes de tocar el almacenamiento.
const ID = /^[a-z0-9]{4,16}$/;

// Cloudflare no acepta envíos de más de 100 MB en el plan gratuito.
const MAX_ENVIO = 100 * 1024 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const partes = url.pathname.split('/').filter(Boolean);
    try {
      if (partes[0] === 'api') return await api(request, env, url, partes.slice(1));
      if (request.method !== 'GET' && request.method !== 'HEAD') return texto('Método no permitido', 405);

      const [tipo, evento, archivo, ...sobra] = partes;
      if (sobra.length > 0) return html(paginaNoEncontrado(), 404);
      if (tipo === 'v' && ID.test(evento ?? '') && ID.test(archivo ?? '')) {
        const existe = await env.VIDEOS.head(claveVideo(evento, archivo));
        if (!existe) return html(paginaNoEncontrado(), 404);
        const datos = await datosEvento(env, evento);
        return html(paginaVideo({ evento, id: archivo, nombre: datos?.nombre }));
      }
      if (tipo === 'e' && ID.test(evento ?? '') && archivo === undefined) {
        const videos = await listarVideos(env, evento);
        if (videos.length === 0) {
          return html(paginaNoEncontrado('Esta galería aún no tiene videos, o ya pasaron los 30 días en que se guardan.'), 404);
        }
        const datos = await datosEvento(env, evento);
        return html(paginaEvento({ evento, nombre: datos?.nombre, videos }));
      }
      if (tipo === 'f' && ID.test(evento ?? '') && /^[a-z0-9]{4,16}\.mp4$/.test(archivo ?? '')) {
        return await servirVideo(request, env, evento, archivo.slice(0, -4), url.searchParams.has('descargar'));
      }
      return html(paginaNoEncontrado(), 404);
    } catch (err) {
      if (err instanceof PeticionInvalida) return texto(err.message, 400);
      console.error(err);
      return texto('Error del servidor', 500);
    }
  },
};

class PeticionInvalida extends Error {}

async function api(request, env, url, partes) {
  if (!(await claveCorrecta(request, env))) return texto('Clave incorrecta', 401);
  const [accion, ...resto] = partes;

  if (accion === 'ping' && request.method === 'GET') return json({ ok: true });

  if (accion === 'evento' && request.method === 'PUT' && ID.test(resto[0] ?? '') && resto.length === 1) {
    const { nombre, fecha } = await leerJson(request);
    const datos = { nombre: String(nombre ?? '').slice(0, 120) };
    // La fecha solo se guarda si es una fecha de verdad.
    if (typeof fecha === 'string' && fecha.length <= 40 && !Number.isNaN(Date.parse(fecha))) datos.fecha = fecha;
    await env.VIDEOS.put(`e/${resto[0]}.json`, JSON.stringify(datos), {
      httpMetadata: { contentType: 'application/json' },
    });
    return json({ ok: true });
  }

  if (accion === 'subir' && request.method === 'PUT') {
    const clave = rutaValida(resto);
    if (!clave) return texto('Ruta inválida', 400);
    const error = revisarTamano(request);
    if (error) return error;
    await env.VIDEOS.put(clave, request.body, { httpMetadata: { contentType: 'video/mp4' } });
    return json({ ok: true });
  }

  // Un invitado pidió que su video no quede publicado.
  if (accion === 'video' && request.method === 'DELETE') {
    const clave = rutaValida(resto);
    if (!clave) return texto('Ruta inválida', 400);
    if (!(await env.VIDEOS.head(clave))) return texto('No encontrado', 404);
    await env.VIDEOS.delete(clave);
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
      const error = revisarTamano(request);
      if (error) return error;
      const parte = await env.VIDEOS.resumeMultipartUpload(clave, uploadId).uploadPart(n, request.body);
      return json({ partNumber: parte.partNumber, etag: parte.etag });
    }
    if (paso === 'completar' && request.method === 'POST' && uploadId) {
      const { partes: lista } = await leerJson(request);
      const valida =
        Array.isArray(lista) &&
        lista.length > 0 &&
        lista.length <= 10000 &&
        lista.every((p) => Number.isInteger(p?.partNumber) && typeof p?.etag === 'string');
      if (!valida) return texto('Partes inválidas', 400);
      const partesR2 = lista.map(({ partNumber, etag }) => ({ partNumber, etag }));
      await env.VIDEOS.resumeMultipartUpload(clave, uploadId).complete(partesR2);
      return json({ ok: true });
    }
  }
  return texto('No encontrado', 404);
}

// Compara la clave en tiempo constante (sin dar pistas por lo que tarda en responder).
async function claveCorrecta(request, env) {
  if (!env.CLAVE) return false;
  const dada = request.headers.get('Authorization') ?? '';
  const [a, b] = await Promise.all([resumen(dada), resumen(`Bearer ${env.CLAVE}`)]);
  let diferencia = 0;
  for (let i = 0; i < a.length; i++) diferencia |= a[i] ^ b[i];
  return diferencia === 0;
}

async function resumen(texto) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto)));
}

function revisarTamano(request) {
  const largo = Number(request.headers.get('content-length'));
  if (!request.body || !Number.isFinite(largo) || largo <= 0) return texto('Falta el tamaño del archivo', 411);
  if (largo > MAX_ENVIO) return texto('Archivo demasiado grande', 413);
  return null;
}

async function leerJson(request) {
  try {
    const datos = await request.json();
    if (datos && typeof datos === 'object') return datos;
  } catch {
    // Se responde 400 abajo.
  }
  throw new PeticionInvalida('JSON inválido');
}

function rutaValida([evento, id, ...sobra] = []) {
  return sobra.length === 0 && ID.test(evento ?? '') && ID.test(id ?? '') ? claveVideo(evento, id) : null;
}

const claveVideo = (evento, id) => `v/${evento}/${id}.mp4`;

async function datosEvento(env, evento) {
  const obj = await env.VIDEOS.get(`e/${evento}.json`);
  if (!obj) return null;
  try {
    return await obj.json();
  } catch {
    return null;
  }
}

async function listarVideos(env, evento) {
  const videos = [];
  let cursor;
  do {
    const r = await env.VIDEOS.list({ prefix: `v/${evento}/`, cursor });
    for (const o of r.objects) {
      const id = o.key.split('/').pop().slice(0, -4);
      if (ID.test(id)) videos.push({ id, subido: o.uploaded });
    }
    cursor = r.truncated ? r.cursor : undefined;
  } while (cursor);
  return videos.sort((a, b) => b.subido - a.subido);
}

async function servirVideo(request, env, evento, id, descargar) {
  let obj;
  try {
    obj = await env.VIDEOS.get(claveVideo(evento, id), { range: request.headers, onlyIf: request.headers });
  } catch (err) {
    // Un rango fuera del archivo (por ejemplo bytes=99999999-).
    if (String(err).includes('range')) return texto('Rango inválido', 416);
    throw err;
  }
  if (!obj) return texto('Video no encontrado', 404);
  const headers = new Headers(SEGURIDAD);
  obj.writeHttpMetadata(headers);
  headers.set('etag', obj.httpEtag);
  headers.set('accept-ranges', 'bytes');
  headers.set('cache-control', 'public, max-age=86400');
  if (descargar) headers.set('content-disposition', `attachment; filename="marles360-${id}.mp4"`);
  if (!('body' in obj)) return new Response(null, { status: 304, headers });

  // Un pedido que empieza después del final del archivo. R2 en ese caso a veces
  // manda el archivo entero; lo correcto es avisar que el rango no existe.
  const desde = /^bytes=(\d+)-/.exec(request.headers.get('range') ?? '');
  if (desde && Number(desde[1]) >= obj.size) {
    await obj.body.cancel();
    return new Response(null, { status: 416, headers: { ...SEGURIDAD, 'content-range': `bytes */${obj.size}` } });
  }

  let status = 200;
  if (obj.range && request.headers.has('range')) {
    // R2 devuelve {offset, length} o {suffix} (los últimos N bytes, como pide Safari).
    // Las claves que no aplican pueden venir presentes pero vacías, por eso se
    // revisa que sean números (con 'suffix' in r salía "bytes NaN-NaN").
    const r = obj.range;
    const numero = (x) => typeof x === 'number' && Number.isFinite(x);
    const inicio = numero(r.suffix) ? Math.max(0, obj.size - r.suffix) : numero(r.offset) ? r.offset : 0;
    const largo = numero(r.length) && !numero(r.suffix) ? Math.min(r.length, obj.size - inicio) : obj.size - inicio;
    headers.set('content-range', `bytes ${inicio}-${inicio + largo - 1}/${obj.size}`);
    headers.set('content-length', String(largo));
    status = 206;
  } else {
    headers.set('content-length', String(obj.size));
  }
  return new Response(request.method === 'HEAD' ? null : obj.body, { status, headers });
}

// Cabeceras de seguridad para todo lo que responde el servidor.
const SEGURIDAD = {
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
};

const html = ({ cuerpo, nonce }, status = 200) =>
  new Response(cuerpo, {
    status,
    headers: {
      ...SEGURIDAD,
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-cache',
      // Solo se ejecuta el script propio de la página (con su nonce) y solo se
      // cargan videos de este mismo servidor y la letra de Google Fonts.
      'content-security-policy': [
        "default-src 'none'",
        `script-src 'nonce-${nonce}'`,
        "style-src 'unsafe-inline' https://fonts.googleapis.com",
        'font-src https://fonts.gstatic.com',
        "media-src 'self' blob:",
        "img-src 'self' data:",
        "connect-src 'self'",
        "base-uri 'none'",
        "form-action 'none'",
        "frame-ancestors 'none'",
      ].join('; '),
    },
  });
const json = (datos, status = 200) =>
  new Response(JSON.stringify(datos), { status, headers: { ...SEGURIDAD, 'content-type': 'application/json' } });
const texto = (t, status) =>
  new Response(t, { status, headers: { ...SEGURIDAD, 'content-type': 'text/plain; charset=utf-8' } });
