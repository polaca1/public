/* Derived from piwapp transport framing; MIT, Copyright (c) 2026 N92. */
#include "wl_frame.h"
int wl_write_length(uint32_t n,uint8_t out[3]) {
    if(!out || n>0xffffff) return -1;
    out[0]=(uint8_t)(n>>16);out[1]=(uint8_t)(n>>8);out[2]=(uint8_t)n;return 0;
}
int wl_read_frame(const uint8_t *p,size_t count,uint32_t limit,size_t *length){
    if(!length || (!p&&count))return -1;
    *length=0;if(count<3)return 0;
    uint32_t n=((uint32_t)p[0]<<16)|((uint32_t)p[1]<<8)|p[2];
    if(n>limit)return -1;
    if(count-3<n)return 0;
    *length=n;return 1;
}
