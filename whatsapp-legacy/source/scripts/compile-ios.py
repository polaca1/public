import json,os,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parent.parent
os.chdir(root)
clang=os.environ['WL_TOOLCHAIN']+'/bin/clang'
sdk=os.environ['WL_SDK']
incs=['Core','Sources/Protocol','Vendor/SocketRocket','Vendor/SignalProtocol','Vendor/SignalProtocol/protobuf-c','Vendor/MbedTLS/include','Vendor/MbedTLS/library','Vendor/SignalCurve','Vendor/SignalCurve/ed25519','Vendor/SignalCurve/ed25519/additions','Vendor/SignalCurve/ed25519/additions/generalized','Vendor/SignalCurve/ed25519/nacl_includes','Vendor/SignalCurve/ed25519/sha512']
files=json.loads(pathlib.Path('scripts/crypto-sources.json').read_text())+[str(p) for p in pathlib.Path('Core').glob('*.c')]+[str(p) for p in pathlib.Path('Sources').rglob('*.m')]+['Vendor/SocketRocket/SRWebSocket.m']
flags=['-target','armv7-apple-ios10.0','-isysroot',sdk,'-fobjc-arc','-O2','-DMBEDTLS_CONFIG_FILE="wl_crypto_config.h"']+['-I'+p for p in incs]
subprocess.run([clang]+flags+files+['-framework','UIKit','-framework','CoreGraphics','-framework','CoreImage','-framework','QuartzCore','-framework','Foundation','-framework','Security','-framework','CFNetwork','-lsqlite3','-licucore','-lz','-o','build/root/Applications/WhatsAppLegacy.app/WhatsAppLegacy'],check=True)
