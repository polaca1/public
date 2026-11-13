#ifndef WL_SIGNAL_H
#define WL_SIGNAL_H
#include "wl_proto.h"
#include <sqlite3.h>
typedef struct wl_signal wl_signal;
typedef int (*wl_rng)(uint8_t *,size_t,void *);
/* caller serializes all access and owns protected DB. No library logging enabled. */
int wl_signal_open(wl_signal **out,sqlite3 *db,const uint8_t identity[32],uint32_t registration,wl_rng rng,void *rng_ctx);
void wl_signal_close(wl_signal *s);
int wl_signal_prekey(wl_signal *s,uint32_t id,const uint8_t private_key[32],int signed_key,const uint8_t signature[64]);
int wl_signal_contains(wl_signal *s,const char *name,int device);
int wl_signal_bundle(wl_signal *s,const char *name,int device,uint32_t registration,const uint8_t identity[32],uint32_t signed_id,const uint8_t signed_pub[32],const uint8_t signature[64],uint32_t one_id,const uint8_t *one_pub);
/* output is allocated by library, free with wl_signal_free. type: 3=pkmsg,2=msg */
int wl_signal_encrypt(wl_signal *s,const char *name,int device,wl_bytes plain,uint8_t **out,size_t *n,int *type);
int wl_signal_decrypt(wl_signal *s,const char *name,int device,int type,wl_bytes cipher,uint8_t **out,size_t *n);
void wl_signal_free(uint8_t *p,size_t n);
#endif
