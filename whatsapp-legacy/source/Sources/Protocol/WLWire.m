// WABinary port from piwapp, MIT Copyright (c) 2026 N92.
#import "WLWire.h"
#import "wl_proto.h"
#include <zlib.h>
static void bad(void){@throw [NSException exceptionWithName:@"WLWire" reason:@"Invalid protocol data" userInfo:nil];}
NSDictionary *WLNode(NSString *tag,NSDictionary *attrs,id content){return @{@"tag":tag,@"attrs":attrs?:@{},@"content":content?:[NSNull null]};}
NSArray *WLChildren(NSDictionary *n){return [n[@"content"] isKindOfClass:[NSArray class]]?n[@"content"]:@[];}
NSDictionary *WLChild(NSDictionary *n,NSString *tag){for(NSDictionary *c in WLChildren(n))if([c[@"tag"] isEqual:tag])return c;return nil;}
static void byte(NSMutableData *d,uint8_t b){[d appendBytes:&b length:1];}
static void integer(NSMutableData *d,uint64_t v){do{byte(d,(v&127)|(v>=128?128:0));v>>=7;}while(v);}
NSData *WLPB(NSDictionary<NSNumber *,id> *fields){NSMutableData *d=[NSMutableData data];for(NSNumber *key in [[fields allKeys] sortedArrayUsingSelector:@selector(compare:)]){id v=fields[key];if([v isKindOfClass:[NSNumber class]]){integer(d,key.unsignedIntValue<<3);integer(d,[v unsignedLongLongValue]);}else{NSData *p=[v isKindOfClass:[NSString class]]?[v dataUsingEncoding:NSUTF8StringEncoding]:v;if(![p isKindOfClass:[NSData class]])bad();integer(d,(key.unsignedIntValue<<3)|2);integer(d,p.length);[d appendData:p];}}return d;}
NSData *WLField(NSData *d,unsigned f){wl_bytes out;int rc=wl_pb_bytes((wl_bytes){d.bytes,d.length},f,&out);if(rc<0)bad();return rc?nil:[NSData dataWithBytes:out.p length:out.n];}
uint64_t WLNumber(NSData *d,unsigned f){uint64_t v;int rc=wl_pb_uint((wl_bytes){d.bytes,d.length},f,&v);if(rc<0)bad();return v;}
static NSArray *tokens(void){static NSArray *t;static dispatch_once_t once;dispatch_once(&once,^{NSData *d=[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"tokens" ofType:@"json"]];t=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;});if(!t)bad();return t;}
static void raw(NSMutableData *d,NSData *s){NSUInteger n=s.length;if(n>1024*1024)bad();if(n<256){byte(d,252);byte(d,n);}else if(n<(1<<20)){byte(d,253);byte(d,(n>>16)&15);byte(d,n>>8);byte(d,n);}else{byte(d,254);for(int i=3;i>=0;i--)byte(d,n>>(8*i));}[d appendData:s];}
static void string(NSMutableData *d,NSString *s){
 if(!s){byte(d,0);return;}
 NSRange at=[s rangeOfString:@"@" options:NSBackwardsSearch];
 if(at.location!=NSNotFound){NSString *user=[s substringToIndex:at.location],*server=[s substringFromIndex:at.location+1];NSRange colon=[user rangeOfString:@":" options:NSBackwardsSearch];
 if(colon.location!=NSNotFound&&[@[@"s.whatsapp.net",@"lid",@"hosted",@"hosted.lid"] containsObject:server]){unsigned device=[[user substringFromIndex:colon.location+1] intValue];if(device>255)bad();byte(d,247);byte(d,[@{@"s.whatsapp.net":@0,@"lid":@1,@"hosted":@128,@"hosted.lid":@129}[server] unsignedCharValue]);byte(d,device);string(d,[user substringToIndex:colon.location]);}
 else{byte(d,250);if(user.length)string(d,user);else byte(d,0);string(d,server);}return;}
 // Raw UTF-8 is valid without token/nibble compression.
 raw(d,[s dataUsingEncoding:NSUTF8StringEncoding]);
}
static void list(NSMutableData *d,NSUInteger n){if(n>65535)bad();if(!n)byte(d,0);else if(n<256){byte(d,248);byte(d,n);}else{byte(d,249);byte(d,n>>8);byte(d,n);}}
static void enc(NSMutableData *d,NSDictionary *n,unsigned depth){if(depth>32||![n[@"tag"] length])bad();NSDictionary *attrs=n[@"attrs"];id c=n[@"content"];BOOL has=c&&c!=[NSNull null];list(d,1+attrs.count*2+has);string(d,n[@"tag"]);for(NSString *k in [[attrs allKeys] sortedArrayUsingSelector:@selector(compare:)]){if(![attrs[k] isKindOfClass:[NSString class]])bad();string(d,k);string(d,attrs[k]);}if([c isKindOfClass:[NSArray class]]){list(d,[c count]);for(id child in c)enc(d,child,depth+1);}else if([c isKindOfClass:[NSData class]])raw(d,c);else if([c isKindOfClass:[NSString class]])string(d,c);else if(has)bad();}
NSData *WLEncodeNode(NSDictionary *n,NSError **error){@try{NSMutableData *d=[NSMutableData data];byte(d,0);enc(d,n,0);if(d.length>1024*1024)bad();return d;}@catch(NSException *e){if(error)*error=[NSError errorWithDomain:@"WLWire" code:1 userInfo:nil];return nil;}}
@interface WLReader:NSObject
@property(nonatomic,strong) NSData *data;
@property(nonatomic) NSUInteger offset;
- (unsigned)b;
- (NSData *)take:(NSUInteger)n;
- (uint32_t)number:(unsigned)n;
- (NSString *)str:(unsigned)tag depth:(unsigned)depth;
- (NSDictionary *)node:(unsigned)depth;
@end
@implementation WLReader
- (unsigned)b{if(self.offset>=self.data.length)bad();return ((const uint8_t *)self.data.bytes)[self.offset++];}
- (NSData *)take:(NSUInteger)n{if(n>self.data.length-self.offset)bad();NSData *d=[self.data subdataWithRange:NSMakeRange(self.offset,n)];self.offset+=n;return d;}
- (uint32_t)number:(unsigned)n{uint32_t v=0;while(n--)v=(v<<8)|[self b];return v;}
- (unsigned)list:(unsigned)t{if(t==0)return 0;if(t==248)return [self b];if(t==249)return [self number:2];bad();return 0;}
- (NSUInteger)len:(unsigned)t{if(t==252)return [self b];if(t==253)return (([self b]&15)<<16)|[self number:2];if(t==254)return [self number:4];bad();return 0;}
- (NSString *)str:(unsigned)t depth:(unsigned)depth {
 if(depth>32)bad();NSArray *single=tokens()[0],*dbl=tokens()[1];
 if(t>0&&t<single.count)return single[t];
 if(t>=236&&t<=239){unsigned i=[self b];NSArray *a=dbl[t-236];if(i>=a.count)bad();return a[i];}
 if(t==0)return @"";
 if(t==252||t==253||t==254){NSString *s=[[NSString alloc] initWithData:[self take:[self len:t]] encoding:NSUTF8StringEncoding];if(!s)bad();return s;}
 if(t==250){NSString *u=[self str:[self b] depth:depth+1],*s=[self str:[self b] depth:depth+1];if(!s.length)bad();return [NSString stringWithFormat:@"%@@%@",u,s];}
 if(t==247){unsigned domain=[self b],device=[self b];NSString *user=[self str:[self b] depth:depth+1];NSString *server=@{@0:@"s.whatsapp.net",@1:@"lid",@128:@"hosted",@129:@"hosted.lid"}[@(domain)];if(!server)bad();return [NSString stringWithFormat:@"%@:%u@%@",user,device,server];}
 if(t==246){NSString *u=[self str:[self b] depth:depth+1];unsigned device=[self number:2];NSString *server=[self str:[self b] depth:depth+1];return [NSString stringWithFormat:@"%@:%u@%@",u,device,server];}
 if(t==251||t==255){unsigned size=[self b];NSMutableString *s=[NSMutableString string];const char *map=t==251?"0123456789ABCDEF":"0123456789-.???\0";for(unsigned i=0;i<(size&127);i++){unsigned pair=[self b];unsigned a=pair>>4,b=pair&15;if(t==255&&(a>11||((b>11)&&!(i+1==(size&127)&&(size&128)&&b==15))))bad();[s appendFormat:@"%c",map[a]];if(!(i+1==(size&127)&&(size&128)))[s appendFormat:@"%c",map[b]];}return s;}
 bad();return nil;
}
- (NSDictionary *)node:(unsigned)depth{if(depth>32)bad();unsigned n=[self list:[self b]];if(!n||n>2048)bad();NSString *tag=[self str:[self b] depth:0];if(!tag.length)bad();NSMutableDictionary *attrs=[NSMutableDictionary dictionary];for(unsigned i=0;i<(n-1)/2;i++){NSString *key=[self str:[self b] depth:0],*value=[self str:[self b] depth:0];if(attrs[key])bad();attrs[key]=value;}id c=nil;if(!(n%2)){unsigned t=[self b];if(t==0||t==248||t==249){unsigned count=[self list:t];if(count>4096)bad();NSMutableArray *children=[NSMutableArray array];while(count--)[children addObject:[self node:depth+1]];c=children;}else if(t==252||t==253||t==254)c=[self take:[self len:t]];else c=[self str:t depth:0];}return WLNode(tag,attrs,c);}
@end
NSDictionary *WLDecodeNode(NSData *data,NSError **error){@try{
 if(!data.length||data.length>1024*1024)bad();const uint8_t *p=data.bytes;NSData *body=[data subdataWithRange:NSMakeRange(1,data.length-1)];
 if(p[0]&2){NSMutableData *expanded=[NSMutableData dataWithLength:1024*1024];uLongf n=expanded.length;int rc=uncompress(expanded.mutableBytes,&n,body.bytes,body.length);if(rc!=Z_OK)bad();expanded.length=n;body=expanded;}
 WLReader *r=[WLReader new];r.data=body;NSDictionary *node=[r node:0];if(r.offset!=body.length)bad();return node;
 }@catch(NSException *e){if(error)*error=[NSError errorWithDomain:@"WLWire" code:2 userInfo:nil];return nil;}}
