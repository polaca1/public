#include "wl_proto.h"
#include <string.h>
static int varint(wl_bytes *in,uint64_t *v){*v=0;for(unsigned i=0;i<10;i++){if(!in->n)return -1;uint8_t c=*in->p++;in->n--;if(i==9&&(c&254))return -1;*v|=(uint64_t)(c&127)<<(7*i);if(!(c&128))return 0;}return -1;}
static int find(wl_bytes in,unsigned want,unsigned type,wl_bytes *bytes,uint64_t *number){
 unsigned seen=0;while(in.n){uint64_t key,v=0;if(varint(&in,&key)||key>>3==0||key>>3>0x1fffffff)return -1;unsigned wire=key&7;wl_bytes b={0};
 if(wire==0){if(varint(&in,&v))return -1;}
 else if(wire==1||wire==5){size_t size=wire==1?8:4;if(in.n<size)return -1;in.p+=size;in.n-=size;}
 else if(wire==2){if(varint(&in,&v)||v>in.n)return -1;b.p=in.p;b.n=(size_t)v;in.p+=b.n;in.n-=b.n;}
 else return -1;
 if((key>>3)==want){if(wire!=type||seen++)return -1;if(bytes)*bytes=b;if(number)*number=v;}
 }return seen?0:1;
}
int wl_pb_bytes(wl_bytes in,unsigned f,wl_bytes *out){if(!out||!f)return -1;out->p=NULL;out->n=0;return find(in,f,2,out,NULL);}
int wl_pb_uint(wl_bytes in,unsigned f,uint64_t *out){if(!out||!f)return -1;*out=0;return find(in,f,0,NULL,out);}
static int put(uint8_t *out,size_t cap,size_t *n,uint64_t v){do{if(*n>=cap)return -1;out[(*n)++]=(v&127)|(v>=128?128:0);v>>=7;}while(v);return 0;}
int wl_pb_write_bytes(uint8_t *out,size_t cap,size_t *used,unsigned f,wl_bytes v){if(!out||!used||!f||f>0x1fffffff||(!v.p&&v.n))return -1;size_t n=*used;if(n>cap||put(out,cap,&n,((uint64_t)f<<3)|2)||put(out,cap,&n,v.n)||v.n>cap-n)return -1;if(v.n)memcpy(out+n,v.p,v.n);*used=n+v.n;return 0;}
