import json,os,pathlib,subprocess,shlex,sys
root=pathlib.Path(__file__).resolve().parent.parent
os.chdir(root)
files=json.loads(pathlib.Path('scripts/crypto-sources.json').read_text())+['Core/wl_crypto.c','Core/wl_proto.c','Core/wl_noise.c','Core/wl_signal.c']
incs=['Core','Vendor/SignalProtocol','Vendor/SignalProtocol/protobuf-c','Vendor/MbedTLS/include','Vendor/MbedTLS/library','Vendor/SignalCurve','Vendor/SignalCurve/ed25519','Vendor/SignalCurve/ed25519/additions','Vendor/SignalCurve/ed25519/additions/generalized','Vendor/SignalCurve/ed25519/nacl_includes','Vendor/SignalCurve/ed25519/sha512']
flags=['-std=gnu99','-O2','-fPIC','-DMBEDTLS_CONFIG_FILE="wl_crypto_config.h"']+['-I'+i for i in incs]
subprocess.run(shlex.split(os.environ.get('CC','cc'))+flags+shlex.split(os.environ.get('CFLAGS',''))+files+sys.argv[1:],check=True)
