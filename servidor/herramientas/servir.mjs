// Levanta el servidor en http://127.0.0.1:8787 (R2 en memoria) para probar la
// app contra el servidor de verdad:
//   node herramientas/servir.mjs
//   MARLES_E2E_URL=http://127.0.0.1:8787 MARLES_E2E_CLAVE=clave-de-prueba-local flutter test test/nube_e2e_test.dart
import { Miniflare } from 'miniflare';
import { opcionesServidor } from './opciones.mjs';

const clave = process.env.CLAVE ?? 'clave-de-prueba-local';
const puerto = Number(process.env.PUERTO ?? 8787);
const mf = new Miniflare(opcionesServidor({ clave, puerto }));
console.log(`Servidor listo en ${await mf.ready}`);
