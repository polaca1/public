"""C Signal vs piwapp interoperability, persistence, replay and identity checks."""
import ctypes as C,os,tempfile
from test_native_noise import lib,Bytes,view,k,out,test_crypto,test_noise
from piwapp.auth.creds import AuthenticationCreds
from piwapp.crypto.signal_store import SignalStore
from piwapp.crypto.double_ratchet import SessionBuilder,SessionCipher
from piwapp.crypto.pre_keys import make_pre_key
from piwapp.crypto import signal_curve as curve
RNG=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_size_t,C.c_void_p)
@RNG
def rng(p,n,ctx):C.memmove(p,os.urandom(n),n);return 0
lib.wl_signal_open.argtypes=[C.POINTER(C.c_void_p),C.c_void_p,C.c_char_p,C.c_uint32,RNG,C.c_void_p]
lib.wl_signal_prekey.argtypes=[C.c_void_p,C.c_uint32,C.c_char_p,C.c_int,C.c_char_p]
lib.wl_signal_bundle.argtypes=[C.c_void_p,C.c_char_p,C.c_int,C.c_uint32,C.c_char_p,C.c_uint32,C.c_char_p,C.c_char_p,C.c_uint32,C.c_char_p]
lib.wl_signal_encrypt.argtypes=[C.c_void_p,C.c_char_p,C.c_int,Bytes,C.POINTER(C.c_void_p),C.POINTER(C.c_size_t),C.POINTER(C.c_int)]
lib.wl_signal_decrypt.argtypes=[C.c_void_p,C.c_char_p,C.c_int,C.c_int,Bytes,C.POINTER(C.c_void_p),C.POINTER(C.c_size_t)]
lib.wl_signal_close.argtypes=[C.c_void_p]
lib.wl_signal_free.argtypes=[C.c_void_p,C.c_size_t]
lib.sqlite3_close.argtypes=[C.c_void_p]
def native_open(creds,path):
 db=C.c_void_p();s=C.c_void_p();assert lib.sqlite3_open(path.encode(),C.byref(db))==0
 assert lib.wl_signal_open(C.byref(s),db,creds.signed_identity_key.private,creds.registration_id,rng,None)==0
 sp=creds.signed_pre_key
 assert lib.wl_signal_prekey(s,sp.key_id,sp.key_pair.private,1,sp.signature)==0
 return db,s
def encrypt(s,p):
 o=C.c_void_p();n=C.c_size_t();t=C.c_int();assert lib.wl_signal_encrypt(s,b'peer',1,view(p),C.byref(o),C.byref(n),C.byref(t))==0
 data=C.string_at(o,n.value);lib.wl_signal_free(o,n);return t.value,data
def decrypt(s,t,p):
 o=C.c_void_p();n=C.c_size_t();rc=lib.wl_signal_decrypt(s,b'peer',1,3 if t==3 else 2,view(p),C.byref(o),C.byref(n))
 data=C.string_at(o,n.value) if o.value else None
 lib.wl_signal_free(o,n);return rc,data

def test_interop():
 for initiator in ('native','python'):
  a,b=AuthenticationCreds.initial(),AuthenticationCreds.initial();bs=SignalStore.from_creds(b);cipher=SessionCipher(bs,'native')
  with tempfile.TemporaryDirectory() as tmp:
   path=tmp+'/keys.sqlite';db,s=native_open(a,path)
   if initiator=='native':
    pk=make_pre_key(123);bs.add_pre_key_from_keypair(pk.key_id,pk.key_pair)
    assert lib.wl_signal_bundle(s,b'peer',1,b.registration_id,b.signed_identity_key.public,b.signed_pre_key.key_id,b.signed_pre_key.key_pair.public,b.signed_pre_key.signature,123,pk.key_pair.public)==0
   else:
    pk=make_pre_key(123);assert lib.wl_signal_prekey(s,123,pk.key_pair.private,0,None)==0
    SessionBuilder(bs,'native').init_outgoing({'identityKey':curve.prefix(a.signed_identity_key.public),'registrationId':a.registration_id,'signedPreKey':{'keyId':a.signed_pre_key.key_id,'publicKey':curve.prefix(a.signed_pre_key.key_pair.public),'signature':a.signed_pre_key.signature},'preKey':{'keyId':123,'publicKey':curve.prefix(pk.key_pair.public)}})
    t,p=cipher.encrypt(b'python initiated');assert decrypt(s,t,p)==(0,b'python initiated')
   for i in range(10):
    t,p=encrypt(s,f'native {i}'.encode());assert (cipher.decrypt_prekey_message(p) if t==3 else cipher.decrypt_message(p))==f'native {i}'.encode()
    t,p=cipher.encrypt(f'python {i}'.encode());tampered=p[:-1]+bytes([p[-1]^1]);assert decrypt(s,t,tampered)[0]<0;assert decrypt(s,t,p)==(0,f'python {i}'.encode())
    assert decrypt(s,t,p)[0]<0 # replay rejected
   lib.wl_signal_close(s);lib.sqlite3_close(db)
   db,s=native_open(a,path)
   t,p=cipher.encrypt(b'after reopen');assert decrypt(s,t,p)==(0,b'after reopen')
   t,p=encrypt(s,b'persisted reply');assert (cipher.decrypt_prekey_message(p) if t==3 else cipher.decrypt_message(p))==b'persisted reply'
   lib.wl_signal_close(s);lib.sqlite3_close(db)
if __name__=='__main__':test_crypto();test_noise();test_interop();print('PASS C Signal <-> piwapp bidirectional, both initiation directions, replay rejection and SQLite restart')
