"""Host-only interoperability with independent Python crypto / upstream responder."""
import ctypes as C,os,sys
from pathlib import Path
from piwapp.crypto import key_utils as k
from piwapp import proto
# Use upstream's independent server emulator, never our C handshake as both peers.
sys.path.insert(0,os.environ.get('PIWAPP_SOURCE','/workspace/piwapp'))
from tests.unit.test_noise import _ResponderMirror
lib=C.CDLL(str(Path(__file__).resolve().parents[1]/'build/libwlcrypto.so'))
class Bytes(C.Structure):_fields_=[('p',C.c_void_p),('n',C.c_size_t)]
class State(C.Structure):_fields_=[(n,C.c_ubyte*32) for n in ('private','public','hash','salt','key','read_key','write_key')]+[(n,C.c_uint64) for n in ('counter','read_counter','write_counter')]+[('phase',C.c_int)]
Verifier=C.CFUNCTYPE(C.c_int,Bytes,C.c_void_p,C.c_void_p)
def view(b):return Bytes(C.cast(C.c_char_p(b),C.c_void_p),len(b))
def out(n):return C.create_string_buffer(n)
lib.wl_noise_server.argtypes=[C.POINTER(State),Bytes,C.c_char_p,Verifier,C.c_void_p,C.c_void_p]
lib.wl_noise_init.argtypes=[C.POINTER(State),C.c_char_p]
lib.wl_noise_finish.argtypes=[C.POINTER(State),Bytes,C.c_void_p,C.c_size_t]
lib.wl_noise_encrypt.argtypes=lib.wl_noise_decrypt.argtypes=lib.wl_noise_finish.argtypes

def test_crypto():
 for _ in range(20):
  a,b=k.generate_key_pair(),k.generate_key_pair();o=out(32)
  assert lib.wl_public(a.private,o)==0 and o.raw==a.public
  assert lib.wl_dh(a.private,b.public,o)==0 and o.raw==k.shared_secret(a.private,b.public)
  sig=out(64);m=os.urandom(100)
  assert lib.wl_sign(a.private,m,len(m),os.urandom(64),sig)==0
  assert k.xeddsa_verify(a.public,m,sig.raw)
  py_sig=k.xeddsa_sign(a.private,m)
  assert lib.wl_verify(a.public,m,len(m),py_sig)==0
  assert lib.wl_verify(a.public,m+b'x',len(m)+1,py_sig)!=0
 assert lib.wl_dh(a.private,b'\0'*32,out(32))!=0

def test_noise():
 for reject in (False,True):
  a,b=k.generate_key_pair(),k.generate_key_pair();s=State();assert lib.wl_noise_init(C.byref(s),a.private)==0
  server=_ResponderMirror(a.public,b'WA\x06\x03');hello=server.build_server_hello(a.public,b'public-test-certificate')
  packet=proto.HandshakeMessage(serverHello=proto.HandshakeMessage.ServerHello(ephemeral=hello.ephemeral,static=hello.static,payload=hello.payload)).SerializeToString()
  @Verifier
  def verify(cert,remote,ctx):return -1 if reject or C.string_at(cert.p,cert.n)!=b'public-test-certificate' or C.string_at(remote,32)!=server.server_s.public else 0
  enc=out(48);rc=lib.wl_noise_server(C.byref(s),view(packet),b.private,verify,None,enc)
  if reject:
   assert rc!=0 and s.phase==-1 and bytes(s.private)==b'\0'*32
   continue
  assert rc==0 and server.process_client_finish(enc.raw)==b.public
  payload=b'registration-test';encrypted=out(len(payload)+16)
  assert lib.wl_noise_finish(C.byref(s),view(payload),encrypted,len(encrypted))==0
  assert server._decrypt(encrypted.raw)==payload
  server.finish_init()
  for i in range(10):
   text=f'outgoing {i}'.encode();o=out(len(text)+16)
   assert lib.wl_noise_encrypt(C.byref(s),view(text),o,len(o))==0
   assert server.transport_decrypt(o.raw)==text
   incoming=f'incoming {i}'.encode();ct=server.transport_encrypt(incoming);o=out(len(incoming))
   assert lib.wl_noise_decrypt(C.byref(s),view(ct),o,len(o))==0 and o.raw==incoming
  ct=bytearray(server.transport_encrypt(b'bad tag'));ct[-1]^=1;o=out(7)
  assert lib.wl_noise_decrypt(C.byref(s),view(bytes(ct)),o,len(o))!=0 and s.phase==-1 and o.raw==b'\0'*7
if __name__=='__main__':test_crypto();test_noise();print('PASS native X25519/XEdDSA and complete Noise handshake, bidirectional transport and tamper rejection')
