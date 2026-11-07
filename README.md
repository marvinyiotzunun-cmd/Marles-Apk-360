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

## Firma del APK (una sola vez)

Cada APK sale firmado para que el Xiaomi lo acepte como actualización de la misma app. La llave
(`android/app/marles360-firma.p12`) está cifrada; su contraseña va en el secreto `MARLES_FIRMA` de
GitHub (**Settings** → **Secrets and variables** → **Actions** → **New repository secret**). Sin ese
secreto, GitHub no publica versiones nuevas. No compartas esa contraseña: con ella alguien podría hacer
un APK falso que el celular aceptaría como actualización.

## Conectar la nube

Sigue [GUIA-CLOUDFLARE.md](GUIA-CLOUDFLARE.md). Se hace una sola vez.

## Cómo se usa

1. **Marcos y música** (icono de galería): importa tus marcos PNG verticales 1080 x 1920 con el centro transparente y tus canciones.
2. **Nuevo evento**: nombre, fecha, marco, canción, duración (5 s a 3 min), modo botón o temporizador y cuenta regresiva.
3. **Abrir cámara**: graba con el botón rojo, el control Bluetooth o los botones de volumen.
4. Revisa la vista previa, toca **Aceptar** y el invitado escanea el QR.
5. Sin señal, el video queda guardado y se sube solo cuando vuelve el internet. Mientras tanto puedes compartirlo por Bluetooth o Quick Share.
6. Los videos ya subidos se borran del celular a los 30 días, igual que en la nube. Los que siguen pendientes de subir nunca se borran solos.

## Pruebas

GitHub las corre antes de cada versión; también se pueden correr a mano:

- `flutter test`: cada pantalla en un celular chico, en el Xiaomi 13 Ultra y en una tableta, con letra
  normal, grande y la más grande de Android. Falla si algo se corta, se encima, parte una palabra, es
  muy chico para tocarlo o no dice qué es (TalkBack). Para ver capturas:
  `CAPTURAS=/carpeta flutter test test/pantallas_test.dart`.
- `cd servidor && npm test`: el servidor completo dentro del mismo motor de Cloudflare, con subidas,
  descargas por partes (como las pide el navegador al adelantar el video) e intentos de abuso.
