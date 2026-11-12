#include "wl_frame.h"
#include <assert.h>
int main(void){
    uint8_t p[4];size_t n;
    assert(wl_write_length(0x1000000,p)==-1);
    assert(wl_read_frame(NULL,0,1024,&n)==0);
    assert(wl_read_frame(NULL,1,1024,&n)==-1);
    assert(wl_write_length(1,p)==0);p[3]=42;
    assert(wl_read_frame(p,3,1024,&n)==0);
    assert(wl_read_frame(p,4,1024,&n)==1&&n==1);
    assert(wl_read_frame(p,4,0,&n)==-1);
    assert(wl_write_length(0,p)==0);
    assert(wl_read_frame(p,3,1024,&n)==1&&n==0);
    for(uint32_t i=0;i<=0xffffff;i+=4093){assert(wl_write_length(i,p)==0);assert((((uint32_t)p[0]<<16)|((uint32_t)p[1]<<8)|p[2])==i);}
    return 0;
}
