#include "wl_crypto.h"
#include <string.h>
#include <limits.h>
#include "mbedtls/gcm.h"
#include "mbedtls/sha256.h"
#include "mbedtls/hkdf.h"
#include "mbedtls/platform_util.h"
#include "curve25519-donna.h"
#include "xeddsa.h"
void wl_clear(void *p,size_t n){mbedtls_platform_zeroize(p,n);}
int wl_sha256(const void *p,size_t n,uint8_t out[32]){return mbedtls_sha256_ret(p,n,out,0);}
int wl_hkdf(const uint8_t *ikm,size_t n,const uint8_t salt[32],uint8_t out[64]){return mbedtls_hkdf(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256),salt,32,ikm,n,NULL,0,out,64);}
int wl_public(const uint8_t priv[32],uint8_t pub[32]){const uint8_t base[32]={9};return curve25519_donna(pub,priv,base);}
int wl_dh(const uint8_t priv[32],const uint8_t pub[32],uint8_t out[32]){int rc=curve25519_donna(out,priv,pub);unsigned v=0;for(size_t i=0;i<32;i++)v|=out[i];if(rc||!v){wl_clear(out,32);return -1;}return 0;}
int wl_sign(const uint8_t priv[32],const uint8_t *p,size_t n,const uint8_t random[64],uint8_t sig[64]){if(n>256)return -1;return xed25519_sign(sig,priv,p,(unsigned long)n,random);}
int wl_verify(const uint8_t pub[32],const uint8_t *p,size_t n,const uint8_t sig[64]){if(n>256)return -1;return xed25519_verify(sig,pub,p,(unsigned long)n);}
static void iv_for(uint32_t counter,uint8_t iv[12]){memset(iv,0,12);iv[8]=counter>>24;iv[9]=counter>>16;iv[10]=counter>>8;iv[11]=counter;}
int wl_gcm_seal(const uint8_t key[32],uint32_t counter,const uint8_t *aad,size_t aad_n,const uint8_t *p,size_t n,uint8_t *out){
    mbedtls_gcm_context ctx;mbedtls_gcm_init(&ctx);uint8_t iv[12];iv_for(counter,iv);
    int rc=mbedtls_gcm_setkey(&ctx,MBEDTLS_CIPHER_ID_AES,key,256);
    if(!rc)rc=mbedtls_gcm_crypt_and_tag(&ctx,MBEDTLS_GCM_ENCRYPT,n,iv,12,aad,aad_n,p,out,16,out+n);
    mbedtls_gcm_free(&ctx);return rc;
}
int wl_gcm_open(const uint8_t key[32],uint32_t counter,const uint8_t *aad,size_t aad_n,const uint8_t *p,size_t n,uint8_t *out){
    if(n<16)return -1;
    mbedtls_gcm_context ctx;mbedtls_gcm_init(&ctx);uint8_t iv[12];iv_for(counter,iv);
    int rc=mbedtls_gcm_setkey(&ctx,MBEDTLS_CIPHER_ID_AES,key,256);
    if(!rc)rc=mbedtls_gcm_auth_decrypt(&ctx,n-16,iv,12,aad,aad_n,p+n-16,16,p,out);
    if(rc)wl_clear(out,n-16);
    mbedtls_gcm_free(&ctx);return rc;
}
