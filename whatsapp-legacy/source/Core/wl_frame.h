#ifndef WL_FRAME_H
#define WL_FRAME_H
#include <stddef.h>
#include <stdint.h>
/* WhatsApp connection.py/noise.py uses WA 06 03, not framing.py's default 00. */
static const uint8_t wl_intro[4] = {87,65,6,3};
int wl_write_length(uint32_t length, uint8_t out[3]);
/* 0=incomplete, 1=complete, -1=invalid or above caller's memory limit. */
int wl_read_frame(const uint8_t *bytes,size_t size,uint32_t limit,size_t *payload_size);
#endif
