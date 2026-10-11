# WhatsAuto · fuente de SideStore

En SideStore abre **Fuentes → +** y añade:

```text
https://raw.githubusercontent.com/polaca1/public/main/source.json
```

[Descargar WhatsAuto.ipa](https://raw.githubusercontent.com/polaca1/public/main/WhatsAuto.ipa)

Compilada para iPhone arm64 con **Xcode 27 y SDK iOS 27**, Liquid Glass nativo en controles y compatibilidad con iOS 17 o posterior. SideStore firma el IPA al instalar.

## Configuración

La app necesita un servidor WhatsAuto encendido: introduce su URL HTTPS y el token ADMIN_TOKEN, vincula WhatsApp por QR o código y activa las respuestas. Las claves Gemini permanecen en tu servidor. Esta distribución no contiene claves ni conversaciones.

Funciones: Gemini 3.8 Flash, cambio de clave por cuota, modelo económico opcional, tono natural, indicador de escritura, contexto separado por chat y archivo de conversaciones descargable en el iPhone.

[Servidor e instrucciones](https://github.com/polaca1/Whatsapp_responder_2) · [Compilación verificada](https://github.com/polaca1/Whatsapp_responder_2/actions/runs/38148158771)

SHA-256 del IPA: `35f39ae9187670cded8557314ca2b8f7b8467ccba65bcb1452b3e94bd29f2036`.

La conexión con WhatsApp personal es no oficial. Dos claves del mismo proyecto de Google comparten la cuota. El archivo incluye los mensajes capturados y el historial que WhatsApp entregue; no se garantiza todo el historial antiguo.
