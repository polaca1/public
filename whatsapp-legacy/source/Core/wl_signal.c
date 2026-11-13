#include "wl_signal.h"
#include "wl_crypto.h"
#include "signal_protocol.h"
#include "session_builder.h"
#include "session_cipher.h"
#include "session_pre_key.h"
#include "protocol.h"
#include "curve.h"
#include "mbedtls/md.h"
#include "mbedtls/sha512.h"
#include "mbedtls/cipher.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
struct wl_signal {sqlite3 *db;signal_context *ctx;signal_protocol_store_context *store;uint8_t identity[32];uint32_t registration;wl_rng rng;void *rng_ctx;};
void wl_signal_free(uint8_t *p,size_t n){if(p){wl_clear(p,n);free(p);}}
static int rnd(uint8_t *p,size_t n,void *u){wl_signal *s=u;return s->rng(p,n,s->rng_ctx);}
static int hi(void **out,const uint8_t *key,size_t n,void *u){(void)u;mbedtls_md_context_t *c=calloc(1,sizeof(*c));if(!c)return -1;mbedtls_md_init(c);int rc=mbedtls_md_setup(c,mbedtls_md_info_from_type(MBEDTLS_MD_SHA256),1);if(!rc)rc=mbedtls_md_hmac_starts(c,key,n);if(rc){mbedtls_md_free(c);free(c);return -1;}*out=c;return 0;}
static int hu(void *c,const uint8_t *p,size_t n,void *u){(void)u;return mbedtls_md_hmac_update(c,p,n);}
static int hf(void *c,signal_buffer **out,void *u){(void)u;uint8_t p[32];int rc=mbedtls_md_hmac_finish(c,p);if(!rc){*out=signal_buffer_create(p,32);if(!*out)rc=-1;}wl_clear(p,32);return rc;}
static void hc(void *c,void *u){(void)u;mbedtls_md_free(c);free(c);}
static int si(void **out,void *u){(void)u;mbedtls_sha512_context *c=calloc(1,sizeof(*c));if(!c)return -1;mbedtls_sha512_init(c);int rc=mbedtls_sha512_starts_ret(c,0);if(rc){free(c);return rc;}*out=c;return 0;}
static int su(void *c,const uint8_t *p,size_t n,void *u){(void)u;return mbedtls_sha512_update_ret(c,p,n);}
static int sf(void *c,signal_buffer **out,void *u){(void)u;uint8_t p[64];int rc=mbedtls_sha512_finish_ret(c,p);if(!rc){*out=signal_buffer_create(p,64);if(!*out)rc=-1;}if(!rc)rc=mbedtls_sha512_starts_ret(c,0);wl_clear(p,64);return rc;}
static void sc(void *c,void *u){(void)u;mbedtls_sha512_free(c);free(c);}
static int wl_crypt(int enc,signal_buffer **out,int mode,const uint8_t *key,size_t kn,const uint8_t *iv,size_t ivn,const uint8_t *p,size_t n){
 if(n>1024*1024||ivn!=16||(kn!=16&&kn!=24&&kn!=32))return -1;
 const mbedtls_cipher_info_t *info=mbedtls_cipher_info_from_values(MBEDTLS_CIPHER_ID_AES,(int)kn*8,mode==SG_CIPHER_AES_CBC_PKCS5?MBEDTLS_MODE_CBC:mode==SG_CIPHER_AES_CTR_NOPADDING?MBEDTLS_MODE_CTR:MBEDTLS_MODE_NONE);if(!info)return -1;
 mbedtls_cipher_context_t c;mbedtls_cipher_init(&c);int rc=mbedtls_cipher_setup(&c,info);if(!rc)rc=mbedtls_cipher_setkey(&c,key,(int)kn*8,enc?MBEDTLS_ENCRYPT:MBEDTLS_DECRYPT);
 uint8_t *buf=malloc(n+32);size_t written=0;if(!buf){mbedtls_cipher_free(&c);return -1;}if(!rc)rc=mbedtls_cipher_crypt(&c,iv,ivn,p,n,buf,&written);if(!rc){*out=signal_buffer_create(buf,written);if(!*out)rc=-1;}wl_signal_free(buf,n+32);mbedtls_cipher_free(&c);return rc;
}
static int en(signal_buffer **o,int mode,const uint8_t *k,size_t kn,const uint8_t *iv,size_t ivn,const uint8_t *p,size_t n,void *u){(void)u;return wl_crypt(1,o,mode,k,kn,iv,ivn,p,n);}
static int de(signal_buffer **o,int mode,const uint8_t *k,size_t kn,const uint8_t *iv,size_t ivn,const uint8_t *p,size_t n,void *u){(void)u;return wl_crypt(0,o,mode,k,kn,iv,ivn,p,n);}
static char *addr(const signal_protocol_address *a){if(a->name_len>255||memchr(a->name,'|',a->name_len))return NULL;char *p=malloc(a->name_len+32);if(p)snprintf(p,a->name_len+32,"%.*s|%d",(int)a->name_len,a->name,a->device_id);return p;}
static int get(wl_signal *s,int kind,const char *key,signal_buffer **out){sqlite3_stmt *q=NULL;*out=NULL;if(sqlite3_prepare_v2(s->db,"SELECT value FROM signal_records WHERE kind=? AND key=?",-1,&q,NULL)!=SQLITE_OK)return -1;sqlite3_bind_int(q,1,kind);sqlite3_bind_text(q,2,key,-1,SQLITE_TRANSIENT);int rc=sqlite3_step(q),result=0;if(rc==SQLITE_ROW){*out=signal_buffer_create(sqlite3_column_blob(q,0),sqlite3_column_bytes(q,0));result=*out?1:-1;}else if(rc!=SQLITE_DONE)result=-1;sqlite3_finalize(q);return result;}
static int put(wl_signal *s,int kind,const char *key,const uint8_t *p,size_t n){if(n>1024*1024)return -1;sqlite3_stmt *q=NULL;const char *sql=p?"INSERT OR REPLACE INTO signal_records(kind,key,value) VALUES(?,?,?)":"DELETE FROM signal_records WHERE kind=? AND key=?";if(sqlite3_prepare_v2(s->db,sql,-1,&q,NULL)!=SQLITE_OK)return -1;sqlite3_bind_int(q,1,kind);sqlite3_bind_text(q,2,key,-1,SQLITE_TRANSIENT);if(p)sqlite3_bind_blob(q,3,p,(int)n,SQLITE_TRANSIENT);int rc=sqlite3_step(q);sqlite3_finalize(q);return rc==SQLITE_DONE?0:-1;}
static int load_session(signal_buffer **r,signal_buffer **u,const signal_protocol_address *a,void *ctx){*u=NULL;char *k=addr(a);if(!k)return -1;int rc=get(ctx,0,k,r);free(k);return rc;}
static int save_session(const signal_protocol_address *a,uint8_t *r,size_t n,uint8_t *ur,size_t un,void *ctx){(void)ur;(void)un;char *k=addr(a);if(!k)return -1;int rc=put(ctx,0,k,r,n);free(k);return rc;}
static int has_session(const signal_protocol_address *a,void *ctx){signal_buffer *r=NULL,*u=NULL;int rc=load_session(&r,&u,a,ctx);signal_buffer_bzero_free(r);return rc;}
static int del_session(const signal_protocol_address *a,void *ctx){char *k=addr(a);if(!k)return -1;int exists=has_session(a,ctx);int rc=put(ctx,0,k,NULL,0);free(k);return rc?rc:exists;}
static int subdevices(signal_int_list **out,const char *name,size_t nn,void *ctx){wl_signal *s=ctx;*out=signal_int_list_alloc();if(!*out)return -1;sqlite3_stmt *q=NULL;if(sqlite3_prepare_v2(s->db,"SELECT key FROM signal_records WHERE kind=0",-1,&q,NULL)!=SQLITE_OK)return -1;int count=0,rc;while((rc=sqlite3_step(q))==SQLITE_ROW){const char *key=(const char *)sqlite3_column_text(q,0);if(strlen(key)>nn&&key[nn]=='|'&&!memcmp(key,name,nn)){if(signal_int_list_push_back(*out,atoi(key+nn+1))<0){sqlite3_finalize(q);return -1;}count++;}}sqlite3_finalize(q);return rc==SQLITE_DONE?count:-1;}
static int del_all(const char *name,size_t n,void *ctx){signal_int_list *list=NULL;int count=subdevices(&list,name,n,ctx);if(count<0){signal_int_list_free(list);return count;}for(int i=0;i<count;i++){signal_protocol_address a={name,n,signal_int_list_at(list,i)};if(del_session(&a,ctx)<0){signal_int_list_free(list);return -1;}}signal_int_list_free(list);return count;}
#define KEY_STORE(SUFFIX,KIND) \
static int load_##SUFFIX(signal_buffer **r,uint32_t id,void *ctx){char k[16];snprintf(k,sizeof(k),"%u",id);int rc=get(ctx,KIND,k,r);return rc==1?0:rc<0?rc:SG_ERR_INVALID_KEY_ID;} \
static int store_##SUFFIX(uint32_t id,uint8_t *r,size_t n,void *ctx){char k[16];snprintf(k,sizeof(k),"%u",id);return put(ctx,KIND,k,r,n);} \
static int has_##SUFFIX(uint32_t id,void *ctx){signal_buffer *r=NULL;int rc=load_##SUFFIX(&r,id,ctx);signal_buffer_bzero_free(r);return rc==0?1:rc==SG_ERR_INVALID_KEY_ID?0:rc;} \
static int remove_##SUFFIX(uint32_t id,void *ctx){char k[16];snprintf(k,sizeof(k),"%u",id);return put(ctx,KIND,k,NULL,0);}
KEY_STORE(pre,1)
KEY_STORE(signed,2)
static int identity_pair(signal_buffer **pub,signal_buffer **priv,void *ctx){wl_signal *s=ctx;uint8_t p[33]={5};if(wl_public(s->identity,p+1))return -1;*pub=signal_buffer_create(p,33);*priv=signal_buffer_create(s->identity,32);return *pub&&*priv?0:-1;}
static int registration(void *ctx,uint32_t *id){*id=((wl_signal *)ctx)->registration;return 0;}
static int trust(const signal_protocol_address *a,uint8_t *p,size_t n,void *ctx){char *key=addr(a);if(!key)return -1;signal_buffer *r=NULL;int rc=get(ctx,3,key,&r);free(key);if(rc==0)return 1;if(rc<0)return rc;unsigned v=signal_buffer_len(r)!=n;const uint8_t *known=signal_buffer_const_data(r);if(!v)for(size_t i=0;i<n;i++)v|=known[i]^p[i];signal_buffer_bzero_free(r);return v?0:1;}
static int save_identity(const signal_protocol_address *a,uint8_t *p,size_t n,void *ctx){if(p&&trust(a,p,n,ctx)!=1)return SG_ERR_UNTRUSTED_IDENTITY;char *k=addr(a);if(!k)return -1;int rc=put(ctx,3,k,p,n);free(k);return rc;}
int wl_signal_open(wl_signal **out,sqlite3 *db,const uint8_t identity[32],uint32_t reg,wl_rng rng,void *rng_ctx){
 *out=NULL;if(!db||!rng)return -1;wl_signal *s=calloc(1,sizeof(*s));if(!s)return -1;s->db=db;s->rng=rng;s->rng_ctx=rng_ctx;s->registration=reg;memcpy(s->identity,identity,32);
 if(sqlite3_exec(db,"CREATE TABLE IF NOT EXISTS signal_records(kind INTEGER NOT NULL,key TEXT NOT NULL,value BLOB NOT NULL,PRIMARY KEY(kind,key))",NULL,NULL,NULL)!=SQLITE_OK)goto err;
 if(signal_context_create(&s->ctx,s)<0)goto err;
 signal_crypto_provider crypto={rnd,hi,hu,hf,hc,si,su,sf,sc,en,de,s};if(signal_context_set_crypto_provider(s->ctx,&crypto)<0||signal_protocol_store_context_create(&s->store,s->ctx)<0)goto err;
 signal_protocol_session_store sessions={load_session,subdevices,save_session,has_session,del_session,del_all,NULL,s};
 signal_protocol_pre_key_store pre={load_pre,store_pre,has_pre,remove_pre,NULL,s};
 signal_protocol_signed_pre_key_store signed_store={load_signed,store_signed,has_signed,remove_signed,NULL,s};
 signal_protocol_identity_key_store identities={identity_pair,registration,save_identity,trust,NULL,s};
 if(signal_protocol_store_context_set_session_store(s->store,&sessions)<0||signal_protocol_store_context_set_pre_key_store(s->store,&pre)<0||signal_protocol_store_context_set_signed_pre_key_store(s->store,&signed_store)<0||signal_protocol_store_context_set_identity_key_store(s->store,&identities)<0)goto err;
 *out=s;return 0;
 err:wl_signal_close(s);return -1;
}
void wl_signal_close(wl_signal *s){if(!s)return;if(s->store)signal_protocol_store_context_destroy(s->store);if(s->ctx)signal_context_destroy(s->ctx);wl_clear(s,sizeof(*s));free(s);}
static int public_decode(wl_signal *s,const uint8_t pub[32],ec_public_key **out){uint8_t p[33]={5};memcpy(p+1,pub,32);return curve_decode_point(out,p,33,s->ctx);}
int wl_signal_prekey(wl_signal *s,uint32_t id,const uint8_t priv[32],int signed_key,const uint8_t signature[64]){
 ec_public_key *pub=NULL;ec_private_key *private=NULL;ec_key_pair *pair=NULL;session_pre_key *pre=NULL;session_signed_pre_key *sp=NULL;signal_buffer *r=NULL;uint8_t p[32];int rc=-1;
 if(wl_public(priv,p)||public_decode(s,p,&pub)<0||curve_decode_private_point(&private,priv,32,s->ctx)<0||ec_key_pair_create(&pair,pub,private)<0)goto end;
 if(signed_key){if(!signature||session_signed_pre_key_create(&sp,id,0,pair,signature,64)<0||session_signed_pre_key_serialize(&r,sp)<0)goto end;rc=store_signed(id,signal_buffer_data(r),signal_buffer_len(r),s);}
 else{if(session_pre_key_create(&pre,id,pair)<0||session_pre_key_serialize(&r,pre)<0)goto end;rc=store_pre(id,signal_buffer_data(r),signal_buffer_len(r),s);}
 end:SIGNAL_UNREF(pub);SIGNAL_UNREF(private);SIGNAL_UNREF(pair);SIGNAL_UNREF(pre);SIGNAL_UNREF(sp);signal_buffer_bzero_free(r);return rc;
}
int wl_signal_contains(wl_signal *s,const char *name,int device){signal_protocol_address a={name,strlen(name),device};return has_session(&a,s);}
int wl_signal_bundle(wl_signal *s,const char *name,int device,uint32_t reg,const uint8_t ident[32],uint32_t signed_id,const uint8_t signed_pub[32],const uint8_t sig[64],uint32_t one_id,const uint8_t *one_pub){
 ec_public_key *identity=NULL,*sp=NULL,*op=NULL;session_pre_key_bundle *bundle=NULL;session_builder *builder=NULL;int rc=-1;
 if(public_decode(s,ident,&identity)<0||public_decode(s,signed_pub,&sp)<0||(one_pub&&public_decode(s,one_pub,&op)<0))goto end;
 if(session_pre_key_bundle_create(&bundle,reg,device,one_id,op,signed_id,sp,sig,64,identity)<0)goto end;
 signal_protocol_address a={name,strlen(name),device};if(session_builder_create(&builder,s->store,&a,s->ctx)<0)goto end;rc=session_builder_process_pre_key_bundle(builder,bundle);
 end:session_builder_free(builder);SIGNAL_UNREF(bundle);SIGNAL_UNREF(identity);SIGNAL_UNREF(sp);SIGNAL_UNREF(op);return rc;
}
static int copy_output(signal_buffer *r,uint8_t **out,size_t *n){*n=signal_buffer_len(r);*out=malloc(*n?*n:1);if(!*out)return -1;memcpy(*out,signal_buffer_const_data(r),*n);return 0;}
int wl_signal_encrypt(wl_signal *s,const char *name,int device,wl_bytes p,uint8_t **out,size_t *n,int *type){*out=NULL;*n=0;if(p.n>1024*1024)return -1;session_cipher *cipher=NULL;ciphertext_message *msg=NULL;signal_protocol_address a={name,strlen(name),device};int rc=session_cipher_create(&cipher,s->store,&a,s->ctx);if(rc<0)return rc;rc=session_cipher_encrypt(cipher,p.p,p.n,&msg);if(!rc){*type=ciphertext_message_get_type(msg);rc=copy_output(ciphertext_message_get_serialized(msg),out,n);}SIGNAL_UNREF(msg);session_cipher_free(cipher);return rc;}
int wl_signal_decrypt(wl_signal *s,const char *name,int device,int type,wl_bytes p,uint8_t **out,size_t *n){*out=NULL;*n=0;if(p.n>1024*1024)return -1;session_cipher *cipher=NULL;signal_buffer *plain=NULL;signal_protocol_address a={name,strlen(name),device};int rc=session_cipher_create(&cipher,s->store,&a,s->ctx);if(rc<0)return rc;
 if(type==3){pre_key_signal_message *msg=NULL;rc=pre_key_signal_message_deserialize(&msg,p.p,p.n,s->ctx);if(!rc)rc=session_cipher_decrypt_pre_key_signal_message(cipher,msg,NULL,&plain);SIGNAL_UNREF(msg);}
 else if(type==2){signal_message *msg=NULL;rc=signal_message_deserialize(&msg,p.p,p.n,s->ctx);if(!rc)rc=session_cipher_decrypt_signal_message(cipher,msg,NULL,&plain);SIGNAL_UNREF(msg);}else rc=-1;
 if(!rc)rc=copy_output(plain,out,n);signal_buffer_bzero_free(plain);session_cipher_free(cipher);return rc;
}
