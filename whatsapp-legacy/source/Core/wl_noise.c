/* Port of piwapp Noise_XX_25519_AESGCM_SHA256. MIT, Copyright (c) 2026 N92. */
#include "wl_noise.h"
#include <string.h>
#include <stdlib.h>
static int fail(wl_noise *s){wl_noise_destroy(s);s->phase=-1;return -1;}
void wl_noise_destroy(wl_noise *s){if(s)wl_clear(s,sizeof(*s));}
static int hash(wl_noise *s,wl_bytes b){uint8_t *p=malloc(32+b.n);if(!p)return -1;memcpy(p,s->hash,32);if(b.n)memcpy(p+32,b.p,b.n);int rc=wl_sha256(p,32+b.n,s->hash);wl_clear(p,32+b.n);free(p);return rc;}
static int mix(wl_noise *s,const uint8_t dh[32]){uint8_t k[64];int rc=wl_hkdf(dh,32,s->salt,k);if(!rc){memcpy(s->salt,k,32);memcpy(s->key,k+32,32);s->counter=0;}wl_clear(k,64);return rc;}
static int seal(wl_noise *s,wl_bytes p,uint8_t *out){if(s->counter>UINT32_MAX)return -1;int rc=wl_gcm_seal(s->key,(uint32_t)s->counter++,s->hash,32,p.p,p.n,out);if(!rc)rc=hash(s,(wl_bytes){out,p.n+16});return rc;}
static int open_cipher(wl_noise *s,wl_bytes p,uint8_t *out){if(s->counter>UINT32_MAX)return -1;int rc=wl_gcm_open(s->key,(uint32_t)s->counter++,s->hash,32,p.p,p.n,out);if(!rc)rc=hash(s,p);return rc;}
int wl_noise_init(wl_noise *s,const uint8_t priv[32]){
 if(!s||!priv)return -1;memset(s,0,sizeof(*s));memcpy(s->private_key,priv,32);
 static const uint8_t mode[32]="Noise_XX_25519_AESGCM_SHA256\0\0\0\0";
 static const uint8_t header[4]={87,65,6,3};
 memcpy(s->hash,mode,32);memcpy(s->salt,mode,32);memcpy(s->key,mode,32);
 if(wl_public(priv,s->public_key)||hash(s,(wl_bytes){header,4})||hash(s,(wl_bytes){s->public_key,32}))return fail(s);
 s->phase=1;return 0;
}
int wl_noise_hello(wl_noise *s,uint8_t *out,size_t cap,size_t *n){if(!s||s->phase!=1||!out||!n||cap<36)return -1;uint8_t inner[34];size_t used=0;*n=0;if(wl_pb_write_bytes(inner,sizeof(inner),&used,1,(wl_bytes){s->public_key,32}))return -1;return wl_pb_write_bytes(out,cap,n,2,(wl_bytes){inner,used});}
int wl_noise_server(wl_noise *s,wl_bytes input,const uint8_t priv[32],wl_certificate_verifier verify,void *ctx,uint8_t enc_static[48]){
 if(!s||s->phase!=1||!verify||!priv||!enc_static||input.n>65536)return s?fail(s):-1;
 wl_bytes sh,e,st,payload;uint8_t dh[32]={0},remote[32]={0},local[32]={0};uint8_t *cert=NULL;int rc=-1;
 if(wl_pb_bytes(input,3,&sh)||wl_pb_bytes(sh,1,&e)||e.n!=32||wl_pb_bytes(sh,2,&st)||st.n!=48||wl_pb_bytes(sh,3,&payload)||payload.n<16||payload.n>8192)goto end;
 cert=malloc(payload.n);if(!cert)goto end;
 if(hash(s,e)||wl_dh(s->private_key,e.p,dh)||mix(s,dh)||open_cipher(s,st,remote)||wl_dh(s->private_key,remote,dh)||mix(s,dh)||open_cipher(s,payload,cert))goto end;
 if(verify((wl_bytes){cert,payload.n-16},remote,ctx))goto end;
 if(wl_public(priv,local)||seal(s,(wl_bytes){local,32},enc_static)||wl_dh(priv,e.p,dh)||mix(s,dh))goto end;
 s->phase=2;rc=0;
 end: wl_clear(dh,32);wl_clear(remote,32);wl_clear(local,32);if(cert){wl_clear(cert,payload.n);free(cert);}if(rc){wl_clear(enc_static,48);return fail(s);}return 0;
}
int wl_noise_finish(wl_noise *s,wl_bytes p,uint8_t *out,size_t cap){if(!s||s->phase!=2||!out||p.n>65536||cap<16||p.n>cap-16)return s?fail(s):-1;
 uint8_t keys[64];if(seal(s,p,out)||wl_hkdf(NULL,0,s->salt,keys))return fail(s);
 memcpy(s->write_key,keys,32);memcpy(s->read_key,keys+32,32);wl_clear(keys,64);wl_clear(s->private_key,32);wl_clear(s->key,32);wl_clear(s->salt,32);s->phase=3;return 0;
}
int wl_noise_encrypt(wl_noise *s,wl_bytes p,uint8_t *out,size_t cap){if(!s||s->phase!=3||!out||p.n>0xffffff-16||cap<16||p.n>cap-16||s->write_counter>UINT32_MAX)return s?fail(s):-1;
 if(wl_gcm_seal(s->write_key,(uint32_t)s->write_counter++,NULL,0,p.p,p.n,out))return fail(s);return 0;}
int wl_noise_decrypt(wl_noise *s,wl_bytes p,uint8_t *out,size_t cap){if(!s||s->phase!=3||!out||p.n<16||p.n>0xffffff||p.n-16>cap||s->read_counter>UINT32_MAX)return s?fail(s):-1;
 if(wl_gcm_open(s->read_key,(uint32_t)s->read_counter++,NULL,0,p.p,p.n,out))return fail(s);return 0;}
static int equal32(const uint8_t *a,const uint8_t *b){unsigned v=0;for(unsigned i=0;i<32;i++)v|=a[i]^b[i];return v==0;}
static int valid_details(wl_bytes d,uint64_t now,wl_bytes *key,uint64_t *serial,uint64_t *issuer){uint64_t before,after;
 if(wl_pb_bytes(d,3,key)||key->n!=32||wl_pb_uint(d,1,serial)||wl_pb_uint(d,2,issuer)||wl_pb_uint(d,4,&before)||wl_pb_uint(d,5,&after))return -1;
 return before<=now&&now<after?0:-1;
}
int wl_verify_wa_certificate(wl_bytes cert,const uint8_t remote[32],void *now_ptr){
 static const uint8_t root[32]={0x14,0x23,0x75,0x57,0x4d,0x0a,0x58,0x71,0x66,0xaa,0xe7,0x1e,0xbe,0x51,0x64,0x37,0xc4,0xa2,0x8b,0x73,0xe3,0x69,0x5c,0x6c,0xe1,0xf7,0xf9,0x54,0x5d,0xa8,0xee,0x6b};
 if(!now_ptr)return -1;uint64_t now=*(const uint64_t *)now_ptr,serial,issuer,leaf_serial,leaf_issuer;
 wl_bytes leaf,inter,ld,ls,id,is,ik,lk;
 if(wl_pb_bytes(cert,1,&leaf)||wl_pb_bytes(cert,2,&inter)||wl_pb_bytes(leaf,1,&ld)||wl_pb_bytes(leaf,2,&ls)||ls.n!=64||wl_pb_bytes(inter,1,&id)||wl_pb_bytes(inter,2,&is)||is.n!=64)return -1;
 if(valid_details(id,now,&ik,&serial,&issuer)||issuer!=0||valid_details(ld,now,&lk,&leaf_serial,&leaf_issuer)||leaf_issuer!=serial||!equal32(lk.p,remote))return -1;
 return wl_verify(root,id.p,id.n,is.p)||wl_verify(ik.p,ld.p,ld.n,ls.p)?-1:0;
}
