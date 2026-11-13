#include "wl_proto.h"
#include <assert.h>
#include <stdlib.h>
int main(void){
 uint8_t valid[]={0x0a,2,42,43};wl_bytes b;uint64_t v;
 assert(wl_pb_bytes((wl_bytes){valid,4},1,&b)==0&&b.n==2&&b.p[0]==42);
 assert(wl_pb_bytes((wl_bytes){valid,3},1,&b)<0);
 uint8_t duplicate[]={0x0a,0,0x0a,0};assert(wl_pb_bytes((wl_bytes){duplicate,4},1,&b)<0);
 uint8_t overflow[]={8,255,255,255,255,255,255,255,255,255,2};assert(wl_pb_uint((wl_bytes){overflow,sizeof(overflow)},1,&v)<0);
 uint8_t out[16];size_t n=0;assert(wl_pb_write_bytes(out,sizeof(out),&n,2,(wl_bytes){valid,4})==0);assert(wl_pb_bytes((wl_bytes){out,n},2,&b)==0&&b.n==4);
 uint8_t random[128];srand(1);for(unsigned i=0;i<100000;i++){size_t length=rand()%sizeof(random);for(size_t j=0;j<length;j++)random[j]=rand();wl_pb_bytes((wl_bytes){random,length},1,&b);wl_pb_uint((wl_bytes){random,length},1,&v);}
 return 0;
}
