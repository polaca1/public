"""Opt-in: native C Noise with host-only piwapp WebSocket/registration harness.
No QR/keys/session saved or printed. Does NOT test an iPhone or messaging.
"""
import os,asyncio,ctypes as C,time
if os.environ.get('WL_TEST_REAL')!='1':raise SystemExit('Set WL_TEST_REAL=1 explicitly')
from test_native_noise import lib,State,Bytes,Verifier,view,out
from piwapp import proto
from piwapp.auth.creds import AuthenticationCreds
from piwapp.config import ConnectionConfig
from piwapp.socket.connection import Connection
from piwapp.transport.noise import DEFAULT_NOISE_HEADER
lib.wl_verify_wa_certificate.argtypes=[Bytes,C.c_void_p,C.c_void_p]
class NativeNoise:
 def __init__(self,e):
  self.s=State();self.first=True;self.buffer=bytearray()
  assert lib.wl_noise_init(C.byref(self.s),e.private)==0
 def process_handshake(self,sh,key,**kwargs):
  p=proto.HandshakeMessage(serverHello=proto.HandshakeMessage.ServerHello(ephemeral=sh.ephemeral,static=sh.static,payload=sh.payload)).SerializeToString()
  now=C.c_uint64(int(time.time()))
  @Verifier
  def verify(cert,remote,ctx):return lib.wl_verify_wa_certificate(cert,remote,C.byref(now))
  result=out(48)
  if lib.wl_noise_server(C.byref(self.s),view(p),key.private,verify,None,result):raise RuntimeError('Native Noise / strict certificate validation failed')
  return result.raw
 def encrypt(self,p):
  o=out(len(p)+16)
  assert lib.wl_noise_finish(C.byref(self.s),view(p),o,len(o))==0
  return o.raw
 def finish_init(self):assert self.s.phase==3
 def encode_frame(self,p):
  # ClientFinish was already encrypted above; C transitions before envelope write.
  if getattr(self,'transport_sent',False):
   o=out(len(p)+16);assert lib.wl_noise_encrypt(C.byref(self.s),view(p),o,len(o))==0;p=o.raw
  if self.s.phase==3:self.transport_sent=True
  intro=DEFAULT_NOISE_HEADER if self.first else b'';self.first=False
  return intro+len(p).to_bytes(3,'big')+p
 def decode_frames(self,data):
  self.buffer.extend(data)
  while len(self.buffer)>=3:
   n=int.from_bytes(self.buffer[:3],'big')
   if n>1024*1024:raise RuntimeError('Frame above host test limit')
   if len(self.buffer)<n+3:return
   p=bytes(self.buffer[3:3+n]);del self.buffer[:3+n]
   if self.s.phase==3:
    o=out(n-16);assert lib.wl_noise_decrypt(C.byref(self.s),view(p),o,len(o))==0;p=o.raw
   yield p
async def main():
 c=Connection(AuthenticationCreds.initial(),ConnectionConfig(version=(2,3000,1043857760)))
 c._noise=NativeNoise(c._ephemeral);got=asyncio.Event()
 async def update(s):
  if s.get('qr'):got.set()
 c.ev.on('connection.update',update)
 try:
  await asyncio.wait_for(c.connect(),25)
  await asyncio.wait_for(got.wait(),25)
  print('PASS real WhatsApp QR received with native C Noise and fixed-root certificate + static-key binding checks. No login or messaging tested.')
 finally:await c.close()
asyncio.run(main())
