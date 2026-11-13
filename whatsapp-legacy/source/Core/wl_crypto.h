#ifndef WL_CRYPTO_H
#define WL_CRYPTO_H
#include <stdint.h>
#include <stddef.h>
void wl_clear(void *p,size_t n);
int wl_sha256(const void *p,size_t n,uint8_t out[32]);
int wl_hkdf(const uint8_t *ikm,size_t n,const uint8_t salt[32],uint8_t out[64]);
int wl_public(const uint8_t private_key[32],uint8_t public_key[32]);
int wl_dh(const uint8_t private_key[32],const uint8_t public_key[32],uint8_t out[32]);
int wl_sign(const uint8_t private_key[32],const uint8_t *message,size_t n,const uint8_t random[64],uint8_t signature[64]);
int wl_verify(const uint8_t public_key[32],const uint8_t *message,size_t n,const uint8_t signature[64]);
/* out must have n+16 bytes for seal, n-16 for open. Returns 0 on success. */
int wl_gcm_seal(const uint8_t key[32],uint32_t counter,const uint8_t *aad,size_t aad_n,const uint8_t *input,size_t n,uint8_t *out);
int wl_gcm_open(const uint8_t key[32],uint32_t counter,const uint8_t *aad,size_t aad_n,const uint8_t *input,size_t n,uint8_t *out);
#endif
