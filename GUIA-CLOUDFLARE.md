# Conectar la nube (Cloudflare) — una sola vez

Cloudflare guarda los videos 30 días y muestra la página de descarga. El plan gratuito incluye 10 GB (unos 900 videos cortos al mes).

## 1. Crear la cuenta

1. Entra a <https://dash.cloudflare.com/sign-up> y crea una cuenta gratuita.
2. En el menú de la izquierda abre **Workers y Pages**. La primera vez te pide elegir un subdominio (por ejemplo `marles`). Tu servidor quedará en `https://marles360.marles.workers.dev`.
3. En el menú abre **R2** y activa el plan gratuito. Cloudflare pide una tarjeta para activarlo, pero no cobra mientras no pases de 10 GB.
4. Copia tu **Account ID**: está en la columna derecha de la página de **Workers y Pages**.

## 2. Crear el permiso para GitHub

1. Arriba a la derecha: tu perfil → **Mi perfil** → **Tokens de API** → **Crear token**.
2. Usa la plantilla **Editar Cloudflare Workers** (Edit Cloudflare Workers).
3. En "Recursos de cuenta" elige tu cuenta. Crea el token y cópialo (solo se muestra una vez).

## 3. Guardar los datos en GitHub

En el repositorio `marles-apk-360`: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Crea tres:

| Nombre | Valor |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | El token del paso 2 |
| `CLOUDFLARE_ACCOUNT_ID` | El Account ID del paso 1 |
| `MARLES_CLAVE` | Una clave que tú inventes, larga, sin espacios. Es la que pondrás en la app |

## 4. Publicar el servidor

1. En el repositorio: **Actions** → **Servidor Cloudflare** → **Run workflow**.
2. Cuando termine en verde, abre el paso **Publicar**: ahí aparece la dirección `https://marles360.<tu-subdominio>.workers.dev`.

## 5. Conectar la app

En la app: **Ajustes** → pega la dirección y tu `MARLES_CLAVE` → **Guardar y probar**. Debe decir "Conexión correcta".
