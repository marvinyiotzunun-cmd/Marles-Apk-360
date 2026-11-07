// Opciones de Miniflare para correr el servidor en la computadora, con el mismo
// motor de Cloudflare (workerd) y un R2 en memoria. Las usan las pruebas y
// herramientas/servir.mjs.
import { fileURLToPath } from 'node:url';
import { convertV4MiniflareOptions } from 'miniflare';

const ruta = (r) => fileURLToPath(new URL(r, import.meta.url));

export function opcionesServidor({ clave, puerto } = {}) {
  // Miniflare 5 trae otro formato de opciones; convertV4MiniflareOptions acepta el clásico.
  return convertV4MiniflareOptions({
    name: 'marles360',
    modulesRoot: ruta('..'),
    modules: [
      { type: 'ESModule', path: ruta('../src/index.js') },
      { type: 'ESModule', path: ruta('../src/paginas.js') },
    ],
    compatibilityDate: '2026-09-01',
    r2Buckets: ['VIDEOS'],
    bindings: { CLAVE: clave },
    ...(puerto ? { host: '127.0.0.1', port: puerto } : {}),
  });
}
