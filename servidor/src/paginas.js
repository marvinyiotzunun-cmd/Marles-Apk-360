// Páginas que ve el invitado. Colores y lema de MarLes.

const LEMA = 'Somos parte de sus mejores momentos';
const LIMITE_COMPARTIR = 60 * 1024 * 1024; // más grande que esto, se comparte el enlace

const escapar = (t) =>
  String(t ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function base(titulo, cuerpo, script = '') {
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${escapar(titulo)}</title>
<meta property="og:title" content="${escapar(titulo)}">
<meta property="og:description" content="${LEMA}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;700&display=swap">
<style>
:root{--rojo:#d03a3b;--turq:#5dc5be;--turq-prof:#1f7a75;--turq-pal:#dff3f1;--crema:#fffaf4;--tinta:#1c1a1a;--suave:#5f5a58;--amarillo:#f3e07a}
*{box-sizing:border-box;margin:0}
body{font-family:Poppins,system-ui,sans-serif;background:var(--crema);color:var(--tinta);min-height:100vh;display:flex;flex-direction:column;align-items:center}
.franja{width:100%;height:14px;background:var(--rojo);background-image:radial-gradient(circle,var(--amarillo) 2.5px,transparent 3px);background-size:22px 14px}
header{padding:20px 16px 8px;text-align:center}
.marca{font-weight:700;font-size:22px;letter-spacing:-.02em}.marca span{color:var(--rojo)}
.evento{color:var(--suave);font-size:15px;margin-top:2px}
main{width:100%;max-width:480px;padding:8px 16px 24px;flex:1}
video{width:100%;border-radius:16px;background:#000;display:block}
.botones{display:grid;gap:10px;margin-top:16px}
.btn{display:flex;align-items:center;justify-content:center;gap:10px;border:0;border-radius:14px;padding:16px;font:600 17px Poppins,system-ui,sans-serif;text-decoration:none;cursor:pointer}
.wa{background:#25d366;color:#fff}.dl{background:var(--rojo);color:#fff}.sec{background:var(--turq-pal);color:var(--turq-prof)}
.btn[aria-busy=true]{opacity:.7}
.nota{color:var(--suave);font-size:13px;text-align:center;margin-top:10px}
footer{padding:16px;text-align:center;color:var(--turq-prof);font-size:14px;font-weight:500}
.carrusel{display:flex;gap:12px;overflow-x:auto;scroll-snap-type:x mandatory;padding-bottom:8px}
.carrusel video{flex:0 0 78%;scroll-snap-align:center}
.rejilla{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;margin-top:16px}
.rejilla a{display:block;aspect-ratio:9/16;border-radius:8px;overflow:hidden;background:#000}
.rejilla video{height:100%;object-fit:cover;border-radius:0}
h2{font-size:17px;margin:20px 0 8px}
</style>
</head>
<body>
<div class="franja"></div>
${cuerpo}
<footer>${LEMA}</footer>
<div class="franja"></div>
${script}
</body>
</html>`;
}

const cabecera = (nombre) =>
  `<header><div class="marca">Mar<span>Les</span> 360</div>${nombre ? `<div class="evento">${escapar(nombre)}</div>` : ''}</header>`;

const iconoWa =
  '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2Zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2Zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8-.2-.1-.4-.1-.6.1l-.8 1c-.1.2-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.2-.4.2-.4.7-1.3.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.8 11.9 11.9 0 0 0 4.6 4c1.7.7 2.4.8 3.2.7.5-.1 1.5-.6 1.7-1.2.2-.6.2-1.1.2-1.2-.1-.1-.3-.2-.5-.3Z"/></svg>';

export function paginaVideo({ evento, id, nombre }) {
  const src = `/f/${evento}/${id}.mp4`;
  const cuerpo = `${cabecera(nombre)}
<main>
  <video src="${src}" controls autoplay muted loop playsinline preload="auto"></video>
  <div class="botones">
    <button class="btn wa" id="wa" aria-busy="true">${iconoWa}Enviar por WhatsApp</button>
    <a class="btn dl" href="${src}?descargar" download="marles360-${id}.mp4">Descargar video</a>
    ${nombre ? `<a class="btn sec" href="/e/${evento}">Ver todos los videos del evento</a>` : ''}
  </div>
  <p class="nota" id="nota">El video estará disponible durante 30 días.</p>
</main>`;
  const script = `<script>
(() => {
  const src = ${JSON.stringify(src)};
  const boton = document.getElementById('wa');
  let archivo = null;
  // Se descarga el video en segundo plano para poder compartirlo como archivo.
  fetch(src).then(r => {
    const tam = Number(r.headers.get('content-length') || 0);
    if (!r.ok || tam > ${LIMITE_COMPARTIR}) throw new Error('grande');
    return r.blob();
  }).then(b => {
    const f = new File([b], 'marles360-${id}.mp4', { type: 'video/mp4' });
    if (navigator.canShare && navigator.canShare({ files: [f] })) archivo = f;
  }).catch(() => {}).finally(() => boton.setAttribute('aria-busy', 'false'));

  boton.addEventListener('click', async () => {
    if (archivo) {
      try { await navigator.share({ files: [archivo] }); return; }
      catch (e) { if (e.name === 'AbortError') return; }
    }
    location.href = 'https://wa.me/?text=' + encodeURIComponent('Mi video 360 de MarLes: ' + location.href);
  });
})();
</script>`;
  return base(nombre ? `Tu video 360 · ${nombre}` : 'Tu video 360 · MarLes', cuerpo, script);
}

export function paginaEvento({ evento, nombre, videos }) {
  const fuente = (v) => `/f/${evento}/${v.id}.mp4`;
  const destacados = videos.slice(0, 8);
  const cuerpo = `${cabecera(nombre)}
<main>
  <div class="carrusel">
    ${destacados.map((v) => `<video src="${fuente(v)}#t=0.1" muted loop playsinline preload="metadata"></video>`).join('')}
  </div>
  <h2>${videos.length} videos</h2>
  <div class="rejilla">
    ${videos.map((v) => `<a href="/v/${evento}/${v.id}"><video src="${fuente(v)}#t=0.1" muted playsinline preload="metadata"></video></a>`).join('')}
  </div>
</main>`;
  const script = `<script>
(() => {
  // Reproduce solo el video del carrusel que está a la vista.
  const obs = new IntersectionObserver(es => es.forEach(e => e.isIntersecting ? e.target.play().catch(() => {}) : e.target.pause()), { threshold: 0.6 });
  document.querySelectorAll('.carrusel video').forEach(v => obs.observe(v));
})();
</script>`;
  return base(nombre ? `${nombre} · MarLes 360` : 'Galería · MarLes 360', cuerpo, script);
}

export function paginaNoEncontrado() {
  return base(
    'Video no disponible · MarLes 360',
    `${cabecera()}<main><p class="nota" style="font-size:16px;margin-top:40px">Este video ya no está disponible. Los videos se guardan durante 30 días.</p></main>`,
  );
}
