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
  const html = paginaVideo({ evento: 'abc123', id: 'v1v1v1v1', nombre: '<script>alert(1)</script>' });
  assert.ok(!html.includes('<script>alert(1)'));
  assert.ok(html.includes('&lt;script&gt;'));
});
