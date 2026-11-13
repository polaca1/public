#ifndef WL_PROTO_H
#define WL_PROTO_H
#include <stdint.h>
#include <stddef.h>
typedef struct { const uint8_t *p; size_t n; } wl_bytes;
/* Strict, bounded protobuf walker; rejects malformed fields and duplicate requested fields. */
int wl_pb_bytes(wl_bytes input,unsigned field,wl_bytes *out);
int wl_pb_uint(wl_bytes input,unsigned field,uint64_t *out);
int wl_pb_write_bytes(uint8_t *out,size_t cap,size_t *used,unsigned field,wl_bytes value);
#endif
