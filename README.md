# Marles APK 360

App para grabar videos en el Photo Booth 360 de MarLes y entregarlos al invitado por QR (descarga o WhatsApp).

- `lib/`: la app (Flutter). Android primero; el mismo código servirá para iPhone.
- `servidor/`: servidor gratuito en Cloudflare (videos en R2 y páginas de descarga).
- `.github/workflows/apk.yml`: compila el APK en cada cambio y lo publica en **Releases**.
- `.github/workflows/servidor.yml`: publica el servidor en Cloudflare.

## Instalar la app en el Xiaomi

1. Desde el celular, abre la página **Releases** de este repositorio y descarga el `.apk` más reciente.
2. Ábrelo. Si Android pregunta, permite "instalar apps de esta fuente" y toca **Instalar de todos modos**.
3. Las versiones nuevas se instalan encima de la anterior sin perder eventos, marcos ni música.

## Conectar la nube

Sigue [GUIA-CLOUDFLARE.md](GUIA-CLOUDFLARE.md). Se hace una sola vez.

## Cómo se usa

1. **Marcos y música** (icono de galería): importa tus marcos PNG verticales 1080 x 1920 con el centro transparente y tus canciones.
2. **Nuevo evento**: nombre, fecha, marco, canción, duración (5 s a 3 min), modo botón o temporizador y cuenta regresiva.
3. **Abrir cámara**: graba con el botón rojo, el control Bluetooth o los botones de volumen.
4. Revisa la vista previa, toca **Aceptar** y el invitado escanea el QR.
5. Sin señal, el video queda guardado y se sube solo cuando vuelve el internet. Mientras tanto puedes compartirlo por Bluetooth o Quick Share.
