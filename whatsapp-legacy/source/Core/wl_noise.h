#ifndef WL_NOISE_H
#define WL_NOISE_H
#include "wl_crypto.h"
#include "wl_proto.h"
typedef struct {
 uint8_t private_key[32],public_key[32],hash[32],salt[32],key[32],read_key[32],write_key[32];
 uint64_t counter,read_counter,write_counter;
 int phase; /* 1 awaiting server, 2 verified server, 3 transport, -1 failed */
} wl_noise;
/* verifier MUST verify chain and bind leaf key to remote_static; no NULL verifier. */
typedef int (*wl_certificate_verifier)(wl_bytes certificate,const uint8_t remote_static[32],void *ctx);
int wl_noise_init(wl_noise *state,const uint8_t ephemeral_private[32]);
int wl_noise_hello(wl_noise *state,uint8_t *out,size_t cap,size_t *written);
int wl_noise_server(wl_noise *state,wl_bytes server_hello,const uint8_t static_private[32],wl_certificate_verifier verify,void *ctx,uint8_t encrypted_static[48]);
int wl_noise_finish(wl_noise *state,wl_bytes payload,uint8_t *encrypted,size_t cap);
int wl_noise_encrypt(wl_noise *state,wl_bytes input,uint8_t *out,size_t cap);
int wl_noise_decrypt(wl_noise *state,wl_bytes input,uint8_t *out,size_t cap);
void wl_noise_destroy(wl_noise *state);
/* Strict production verifier, root fixed to inspected WhatsApp public key. now=Unix seconds. */
int wl_verify_wa_certificate(wl_bytes certificate,const uint8_t remote_static[32],void *now);
#endif
