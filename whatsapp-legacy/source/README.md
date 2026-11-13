# WhatsApp Legacy 0.2.0 — experimental

Cliente independiente Objective-C/UIKit para iPhone 5c ARMv7 de 32 bits, mínimo iOS 10.0. Implementa conexión directa a WhatsApp, Noise, QR real, verificación de vinculación, credenciales Keychain, Signal, mensajes individuales de texto y SQLite local. **El flujo completo aún no está verificado en un iPhone físico. No se afirma mensajería funcional comprobada en ese dispositivo.**

## Instalar y vincular
Fuente plana para Zebra/Cydia: `https://raw.githubusercontent.com/polaca1/public/main/whatsapp-legacy/apt/`.

Actualiza las fuentes e instala/actualiza **WhatsApp Legacy (Experimental)** a 0.2.0. Fuente HTTPS sin firma GPG: el gestor puede advertirlo. Abre Vinculación > Conectar; escanea el QR desde WhatsApp del teléfono principal > Dispositivos vinculados. El QR procede de una referencia real del servidor. Tras vincular, se guarda la identidad en Keychain y se reconecta cuando el servidor solicita reinicio 515. Espera a que se preparen las preclaves. Chats > Nuevo abre un destinatario por número internacional (sin + ni espacios). Los mensajes salen como «en cola»; sólo el ack del servidor los marca aceptados. Entrega/lectura dependen de receipts reales.

Mantén la aplicación abierta. Al perder el primer plano se desconecta para ocultar el QR y proteger la pantalla de sesión; Conectar restablece la sesión. No hay multimedia, grupos, importación de historial, sincronización de agenda, soporte completo de LID/hosted ni notificaciones permanentes. Los mensajes no compatibles se indican; no se inventan conversaciones.

## Evidencia de pruebas
- Cross-compilación del binario final ARMv7 de 32 bits, mínimo iOS 10.0, firma ad hoc, dependencias de sistema y .deb: comprobados.
- X25519/XEdDSA C frente a piwapp; handshake Noise con responder Python independiente; transporte en ambas direcciones; rechazo de modificaciones: comprobados.
- Signal C frente a piwapp, con iniciador en ambos extremos, diez intercambios en cada prueba, rechazo de repetición/modificación y reinicio SQLite: comprobados.
- Parser protobuf: límites, duplicados, overflow y 100.000 entradas pseudoaleatorias con ASan/UBSan; encuadre: comprobados.
- Servicio real: QR recibido con el motor C de Noise y validación de raíz WhatsApp, fechas y enlace de clave estática. Esta prueba usa un harness Python en Linux para WebSocket, protobuf y registro; **no prueba el UIKit/SocketRocket del iPhone**. No guarda ni imprime QR, claves o sesiones.
- Instalación, arranque, Keychain del jailbreak, QR escaneado y envío/recepción de WhatsApp desde un iPhone físico: **pendientes**.

La versión inicial de piwapp fue rechazada con 405. El QR real se obtuvo con versión Web 2.3000.1043857760, tomada de Baileys. Es una configuración que WhatsApp puede volver a invalidar. No hay servidor propio, Beeper, proxy de aplicación ni Python en el teléfono.

## Construcción
Linux x86_64: git, curl, xz, Python 3, cc, dpkg-deb; para pruebas host, sqlite3 development headers y Python 3.12.
```
bash scripts/test.sh
bash scripts/bootstrap.sh
WL_TOOLCHAIN="$PWD/.tools/toolchain" WL_SDK="$PWD/.tools/patched.sdk" bash scripts/build.sh
```
La compilación de la app sólo usa C/Objective-C. Para pruebas host de interoperabilidad clona piwapp en el commit indicado, instala sus dependencias en un venv Python 3.12 y ejecuta `PIWAPP_SOURCE=/ruta/piwapp bash scripts/test-native.sh`. La prueba real es opt-in: `WL_TEST_REAL=1 python3 tests/live_native_handshake.py`. No vincula una cuenta; sólo solicita un QR temporal, que no muestra.

GitHub Actions compila y sube el .deb como artifact. El repositorio conserva el resto del contenido del usuario. Makefile Theos alternativo: ARCHS=armv7, SDK 9.3, deployment target 10.0, entitlements Keychain y recursos. La ruta verificada es scripts/build.sh.

El SDK comunitario 10.3 tiene stubs incompletos ARMv7. Se usan cabeceras 9.3 con mínimo 10.0; scripts/patch-sdk.py repara la referencia ausente a liblaunch y exportaciones estándar libc ausentes. No modifica bibliotecas del dispositivo. El enlazador emite advertencias de stubs etiquetados como simulador: la inspección confirma CPU ARMv7 y LC_VERSION_MIN_IPHONEOS, sin sustituir la prueba física. El iPhone 5c admite oficialmente hasta iOS 10.3.3; 10.3.4 corresponde al iPhone 5.

## Módulos y persistencia
- Core/wl_crypto: X25519, XEdDSA, HKDF-SHA256 y AES-GCM con fuentes C fijadas.
- Core/wl_noise: estados estrictos, certificado obligatorio y contadores que no se reutilizan. Los errores de integridad borran las claves de transporte.
- Core/wl_proto y wl_frame: parsing acotado, protobuf y longitudes de 24 bits.
- Core/wl_signal: libsignal-protocol-c, proveedor criptográfico y almacenes SQLite. Confianza inicial por TOFU; rechaza cambios de identidad sin consentimiento. Sin log de biblioteca.
- Sources/Protocol/WLWire: WABinary, tokens, JID y descompresión acotada.
- WLSession: SocketRocket, registro, QR, HMAC/firma de vinculación, Keychain y reconexión con espera creciente.
- WLChatEngine: USync, bundles, fan-out cifrado, carga de preclaves, cola de salida, recepción, recibos y deduplicación.
- Sources/App: chats/conversación, entrada de texto, ajustes y QR UIKit/CoreImage.

Credenciales en Keychain AfterFirstUnlockThisDeviceOnly. Conversaciones y registros Signal en directorio SQLite con protección CompleteUntilFirstUserAuthentication y permisos privados, excluido de backups. Cifrado de mensajes y Noise ejecutados localmente. Actualización de ratchet y mensaje/cola en la misma transacción. Los errores de descifrado no se presentan como entrega correcta. No se envían claves privadas al servicio ni a un intermediario.

## Depuración en dispositivo
Si el icono no aparece, ejecutar `uicache`. Anota el estado numérico mostrado en la aplicación, versión de iOS y jailbreak. Para crash reports: /var/mobile/Library/Logs/CrashReporter o la sección de análisis de Ajustes. Revisa los informes antes de compartirlos; no compartas QR ni Keychain ni messages.sqlite. Si falla Keychain, conserva la sesión: no la sobrescribe automáticamente. Los entitlements de grupo Keychain requieren la aceptación del jailbreak y siguen sin comprobar en hardware. La validación TLS no se desactiva siquiera en DEBUG; un almacén raíz iOS 10 obsoleto puede impedir conectar. Las claves Signal cambiadas producen error, sin confiar automáticamente en la nueva identidad.

Para revocar, elimina el dispositivo desde WhatsApp principal. Desinstalar el .deb puede conservar datos y Keychain. Este build no incluye función de borrado/revinculación local: esa gestión sigue pendiente.

## Licencias / versiones
El conjunto se distribuye bajo GPLv3 por libsignal-protocol-c. Se incluyen las fuentes correspondientes completas y licencias; componentes conservan sus licencias originales.
- piwapp MIT, commit 5f45e6124991212aedb13fc0fb59f28b8dd012ed; avisos en docs/PIWAPP-LICENSE. Referencia para protocolos, no runtime iOS. Requiere Python >=3.12 con dependencias modernas que no se importan en Objective-C.
- libsignal-protocol-c v2.3.3, commit 3a83a4f4ed2302ff6e68ab569c88793b50c22d28, GPLv3. Includes de curve.c adaptados al árbol vendorizado; sin cambiar su algoritmo. Protobuf-c conserva su aviso BSD.
- Mbed TLS v2.28.10, commit 2fc8413bfcb51354c8e679141b17b3f1a5942561, Apache-2.0; configuración mínima C sin ensamblador.
- SocketRocket 0.5.1, commit 36e68c11ab131747c401728e79b110e98d98a70f, Apache-2.0. Parches locales: fallo cerrado de RNG, validación TLS obligatoria, logs de payload desactivados y límite de mensaje de 1 MiB.
- Archivos nuevos y puertos de piwapp: MIT; licencia original del proyecto en docs/LEGACY-MIT-LICENSE. Distribución agregada GPLv3 compatible con esas licencias.

Cliente independiente, no afiliado a WhatsApp.
