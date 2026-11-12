# WhatsApp Legacy — build de investigación 0.1.0

**No permite vincular una cuenta ni enviar/recibir WhatsApp.** Paquete experimental con UIKit, SQLite vacío y diagnóstico TLS/WebSocket directo. Binario ARMv7 de 32 bits con target iOS 10.0. Arranque en hardware sin comprobar. El iPhone 5c llega oficialmente a iOS 10.3.3 (10.3.4 corresponde al iPhone 5).

## Instalación
En Zebra/Cydia añade `https://raw.githubusercontent.com/polaca1/public/main/whatsapp-legacy/apt/` e instala **WhatsApp Legacy (Experimental)**. Es una fuente APT plana, sin firma GPG, alojada por HTTPS; Zebra puede mostrar una advertencia. No hay una cuenta WhatsApp detrás de los chats vacíos. La prueba WSS se cierra a los 15 segundos o al entrar en segundo plano.

## Estado comprobado
- Compilación y enlace Mach-O ARMv7, PIE, deployment target 10.0, firma ad hoc y empaquetado .deb: comprobados en Linux.
- Dependencias de ejecución: frameworks y bibliotecas de sistema; SocketRocket incluido estáticamente.
- Pruebas de longitud de tramas con ASan/UBSan: pasadas.
- Instalación, arranque en iOS 10, conexión WSS desde iPhone, autenticación y mensajería: NO verificados.
- Noise, XEdDSA/certificados WhatsApp, QR, Signal, gestión de identidades/preclaves, restauración de sesiones, conversación, contactos sincronizados y reconexión: pendientes. No se generan ni almacenan claves todavía.

## Compilar
En Linux x86_64 con git, curl, xz, cc y dpkg-deb:
```
bash scripts/test.sh
bash scripts/bootstrap.sh
WL_TOOLCHAIN="$PWD/.tools/toolchain" WL_SDK="$PWD/.tools/patched.sdk" bash scripts/build.sh
```
El workflow publica el paquete como artifact. Makefile Theos alternativo: `ARCHS=armv7`, SDK 9.3, deployment target 10.0. Requiere rsync y un SDK con stubs corregidos. La ruta de compilación reproducida aquí es scripts/build.sh.

El SDK comunitario 10.3 tiene stubs incompletos para ARMv7. Se usa 9.3 con APIs disponibles desde iOS 9 y mínimo 10.0, reparando dos stubs: referencia ausente a liblaunch y exportación memset. El enlazador avisa de stubs etiquetados como simulador; la inspección confirma CPU ARMv7 y LC_VERSION_MIN_IPHONEOS, pero esto no sustituye una prueba física. No se modifican bibliotecas del dispositivo.

## Arquitectura y continuación
Sources/App.m contiene la base UIKit y persistencia; Core/wl_frame implementa encuadre acotado derivado de piwapp. Vendor/SocketRocket implementa TLS/WebSocket; no hay backend o proxy propio. Próximos pasos: separar almacenamiento/transporte/UI; evaluar criptografía C con X25519, AES-GCM, HKDF y XEdDSA; portar protobuf/binario; Noise con verificación estricta de certificados; QR real; Signal y mensajes. No aceptar certificados arbitrarios ni usar Ed25519 como sustituto de XEdDSA.

## Depuración
Si no aparece el icono, ejecutar `uicache` después de instalar. Examinar Settings > Privacy > Analytics o /var/mobile/Library/Logs/CrashReporter según jailbreak. Compartir únicamente informes revisados sin tokens, números ni claves. No se registran cargas útiles WebSocket. El código numérico de error de transporte aparece en Vinculación. Para eliminar: desinstalar el paquete; los datos en Application Support pueden persistir. No contiene credenciales.

## Referencias y licencias
piwapp MIT: commit 5f45e6124991212aedb13fc0fb59f28b8dd012ed. Requiere Python >=3.12 y websockets, cryptography, PyNaCl, protobuf y ORM modernos; no son importables directamente desde Objective-C/ARMv7. Se conserva docs/PIWAPP-LICENSE. Flujo inspeccionado: transport/noise.py, socket/connection.py, auth/qr.py y crypto/. El encabezado real Noise es WA 06 03. El QR depende de un intercambio autenticado y no se fabrica en este build.

SocketRocket 0.5.1, commit 36e68c11ab131747c401728e79b110e98d98a70f, Apache-2.0, licencia en Vendor/SocketRocket/LICENSE. Fuentes nuevas bajo MIT (LICENSE). Cliente independiente, no afiliado a WhatsApp.
