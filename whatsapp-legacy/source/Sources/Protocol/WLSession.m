#import "WLSession.h"
#import "WLWire.h"
#import "SRWebSocket.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#include "wl_noise.h"
#include "wl_frame.h"
static NSData *randomData(NSUInteger n){NSMutableData *d=[NSMutableData dataWithLength:n];if(SecRandomCopyBytes(kSecRandomDefault,n,d.mutableBytes))@throw [NSException exceptionWithName:@"WLCrypto" reason:@"Random source failed" userInfo:nil];return d;}
static NSData *privateKey(void){NSMutableData *d=[randomData(32) mutableCopy];uint8_t *b=d.mutableBytes;b[0]&=248;b[31]&=127;b[31]|=64;return d;}
static NSData *publicKey(NSData *d){if(d.length!=32)@throw [NSException exceptionWithName:@"WLKey" reason:@"Invalid key length" userInfo:nil];uint8_t p[32];if(wl_public(d.bytes,p))return nil;return [NSData dataWithBytes:p length:32];}
static NSData *be(uint32_t v,unsigned size){uint8_t b[4];for(unsigned i=0;i<size;i++)b[i]=v>>(8*(size-1-i));return [NSData dataWithBytes:b length:size];}
static NSData *join(NSArray *values){NSMutableData *d=[NSMutableData data];for(NSData *v in values)[d appendData:v];return d;}
static BOOL same(NSData *a,NSData *b){if(a.length!=b.length)return NO;const uint8_t *x=a.bytes,*y=b.bytes;unsigned v=0;for(NSUInteger i=0;i<a.length;i++)v|=x[i]^y[i];return v==0;}
@interface WLSession()<SRWebSocketDelegate>{wl_noise _noise;}
@property(nonatomic,strong) SRWebSocket *socket;
@property(nonatomic,strong) NSMutableData *input;
@property(nonatomic,strong) NSMutableDictionary *creds;
@property(nonatomic,strong) NSData *encryptedStatic;
@property(nonatomic,strong) NSTimer *ping;
@property(nonatomic,strong) NSTimer *qrTimer;
@property(nonatomic,strong) NSMutableArray *refs;
@property(nonatomic) BOOL authenticated;
@property(nonatomic) BOOL desired;
@property(nonatomic) BOOL sentFinish;
@property(nonatomic) unsigned retries;
@end
@implementation WLSession
- (NSDictionary *)credentials{return self.creds;}
- (void)status:(NSString *)s{if(self.onStatus)self.onStatus(s);}
- (NSDictionary *)keychainQuery{return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"com.polaca1.whatsapplegacy",(__bridge id)kSecAttrAccount:@"linked-device-v1"};}
- (BOOL)save {
 NSError *error=nil;NSData *data=[NSPropertyListSerialization dataWithPropertyList:self.creds format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];if(!data)return NO;
 NSDictionary *attributes=@{(__bridge id)kSecValueData:data,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
 OSStatus rc=SecItemUpdate((__bridge CFDictionaryRef)[self keychainQuery],(__bridge CFDictionaryRef)attributes);
 if(rc==errSecItemNotFound){NSMutableDictionary *q=[[self keychainQuery] mutableCopy];[q addEntriesFromDictionary:attributes];rc=SecItemAdd((__bridge CFDictionaryRef)q,NULL);}return rc==errSecSuccess;
}
- (BOOL)load {
 NSMutableDictionary *q=[[self keychainQuery] mutableCopy];q[(__bridge id)kSecReturnData]=@YES;CFTypeRef result=NULL;OSStatus rc=SecItemCopyMatching((__bridge CFDictionaryRef)q,&result);
 if(rc==errSecSuccess){NSData *data=CFBridgingRelease(result);id c=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:NULL];if(![c isKindOfClass:[NSMutableDictionary class]])return NO;self.creds=c;for(NSString *key in @[@"noise",@"identity",@"signed",@"adv"])if([c[key] length]!=32)return NO;return [c[@"signature"] length]==64;}
 if(rc!=errSecItemNotFound)return NO;
 self.creds=[@{@"noise":privateKey(),@"identity":privateKey(),@"signed":privateKey(),@"adv":randomData(32),@"nextPreKey":@1} mutableCopy];
 uint8_t sig[64];NSData *pub=publicKey(self.creds[@"signed"]),*prefixed=join(@[[NSData dataWithBytes:"\5" length:1],pub]);NSData *nonce=randomData(64);
 if(wl_sign([self.creds[@"identity"] bytes],prefixed.bytes,prefixed.length,nonce.bytes,sig))return NO;
 self.creds[@"signature"]=[NSData dataWithBytes:sig length:64];wl_clear(sig,64);
 NSData *r=randomData(2);const uint8_t *bytes=r.bytes;self.creds[@"registration"]=@((((unsigned)bytes[0]<<8)|bytes[1])&0x3fff);
 return [self save];
}
- (NSData *)payload {
 NSData *version=WLPB(@{@1:@2,@2:@3000,@3:@1043857760});
 NSData *ua=WLPB(@{@1:@14,@2:version,@3:@"000",@4:@"000",@5:@"0.1",@7:@"Desktop",@8:@"0.1",@10:@0,@11:@"en",@12:@"US"});
 NSMutableDictionary *p=[@{@5:ua,@6:WLPB(@{@4:@0}),@12:@1,@13:@1} mutableCopy];NSString *me=self.creds[@"me"];
 if(me.length){NSArray *parts=[[[me componentsSeparatedByString:@"@"] firstObject] componentsSeparatedByString:@":"];if(parts.count!=2)@throw [NSException exceptionWithName:@"WLJID" reason:@"Invalid linked JID" userInfo:nil];p[@1]=@([parts[0] longLongValue]);p[@18]=@([parts[1] intValue]);p[@3]=@YES;p[@33]=@YES;}
 else {NSString *v=@"2.3000.1043857760";NSData *vdata=[v dataUsingEncoding:NSUTF8StringEncoding];uint8_t md[CC_MD5_DIGEST_LENGTH];CC_MD5(vdata.bytes,(CC_LONG)vdata.length,md);
 NSData *props=WLPB(@{@1:@"Mac OS",@2:WLPB(@{@1:@10,@2:@15,@3:@7}),@3:@1,@4:@NO});
 p[@19]=WLPB(@{@1:be([self.creds[@"registration"] unsignedIntValue],4),@2:[NSData dataWithBytes:"\5" length:1],@3:publicKey(self.creds[@"identity"]),@4:be(1,3),@5:publicKey(self.creds[@"signed"]),@6:self.creds[@"signature"],@7:[NSData dataWithBytes:md length:sizeof(md)],@8:props});p[@3]=@NO;p[@33]=@NO;}
 return WLPB(p);
}
- (void)connect {
 [self disconnect];self.desired=YES;self.retries=0;[self attempt];
}
- (void)attempt {
 if(!self.desired)return;
 @try{if(!self.creds&&![self load]){self.desired=NO;[self status:@"Error de Keychain. Credenciales conservadas."];return;}
 self.input=[NSMutableData data];self.sentFinish=NO;self.authenticated=NO;wl_noise_destroy(&_noise);NSData *e=privateKey();if(wl_noise_init(&_noise,e.bytes)){[self fail:@"Error iniciando Noise" retry:NO];return;}
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"wss://web.whatsapp.com/ws/chat"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25];[r setValue:@"https://web.whatsapp.com" forHTTPHeaderField:@"Origin"];
 self.socket=[[SRWebSocket alloc] initWithURLRequest:r];self.socket.delegate=self;[self status:@"Conectando con WhatsApp…"];[self.socket open];[self performSelector:@selector(deadline) withObject:nil afterDelay:35];
 }@catch(NSException *e){[self fail:@"Error local de credenciales o protocolo" retry:NO];}
}
- (void)deadline{if(!self.authenticated&&!self.refs.count)[self fail:@"Tiempo de conexión agotado" retry:YES];}
- (void)webSocketDidOpen:(SRWebSocket *)ws {if(ws!=self.socket)return;uint8_t hello[64];size_t n;if(wl_noise_hello(&_noise,hello,sizeof(hello),&n)){[self fail:@"Error ClientHello" retry:NO];return;}[self frame:[NSData dataWithBytes:hello length:n] intro:YES];[self status:@"Verificando servidor WhatsApp…"];}
- (void)frame:(NSData *)d intro:(BOOL)intro {if(d.length>1024*1024)@throw [NSException exceptionWithName:@"WLFrame" reason:@"Frame too large" userInfo:nil];uint8_t prefix[3];wl_write_length((uint32_t)d.length,prefix);NSMutableData *out=[NSMutableData data];if(intro)[out appendBytes:wl_intro length:4];[out appendBytes:prefix length:3];[out appendData:d];[self.socket send:out];}
- (BOOL)sendNode:(NSDictionary *)node {if(_noise.phase!=3||!self.sentFinish)return NO;NSError *err=nil;NSData *data=WLEncodeNode(node,&err);if(!data)return NO;NSMutableData *ct=[NSMutableData dataWithLength:data.length+16];if(wl_noise_encrypt(&_noise,(wl_bytes){data.bytes,data.length},ct.mutableBytes,ct.length)){[self fail:@"Error de cifrado de transporte" retry:NO];return NO;}[self frame:ct intro:NO];return YES;}
- (void)webSocket:(SRWebSocket *)ws didReceiveMessage:(id)message {
 if(ws!=self.socket)return;
 @try{if(![message isKindOfClass:[NSData class]]){[self fail:@"Trama WebSocket inválida" retry:NO];return;}
 NSData *data=message;if(data.length>1024*1024||self.input.length>2*1024*1024-data.length){[self fail:@"Límite de recepción" retry:NO];return;}[self.input appendData:data];
 while(self.input.length>=3){size_t n;int rc=wl_read_frame(self.input.bytes,self.input.length,1024*1024,&n);if(rc<0){[self fail:@"Longitud de trama inválida" retry:NO];return;}if(rc==0)return;NSData *body=[self.input subdataWithRange:NSMakeRange(3,n)];[self.input replaceBytesInRange:NSMakeRange(0,n+3) withBytes:NULL length:0];
 if(!self.sentFinish){uint64_t now=(uint64_t)[[NSDate date] timeIntervalSince1970];uint8_t enc[48];if(wl_noise_server(&_noise,(wl_bytes){body.bytes,body.length},[self.creds[@"noise"] bytes],wl_verify_wa_certificate,&now,enc)){[self fail:@"Servidor rechazado: Noise/certificados" retry:NO];return;}
 NSData *payload=[self payload];NSMutableData *encrypted=[NSMutableData dataWithLength:payload.length+16];if(wl_noise_finish(&_noise,(wl_bytes){payload.bytes,payload.length},encrypted.mutableBytes,encrypted.length)){[self fail:@"Error ClientFinish" retry:NO];return;}
 NSData *finish=WLPB(@{@4:WLPB(@{@1:[NSData dataWithBytes:enc length:48],@2:encrypted})});wl_clear(enc,48);[self frame:finish intro:NO];self.sentFinish=YES;[self status:@"Solicitando vinculación…"];
 }else {if(body.length<16){[self fail:@"Trama cifrada inválida" retry:NO];return;}NSMutableData *plain=[NSMutableData dataWithLength:body.length-16];if(wl_noise_decrypt(&_noise,(wl_bytes){body.bytes,body.length},plain.mutableBytes,plain.length)){[self fail:@"Integridad de transporte incorrecta" retry:NO];return;}NSError *error=nil;NSDictionary *node=WLDecodeNode(plain,&error);if(!node){[self fail:@"Formato de protocolo no compatible" retry:NO];return;}[self node:node];}
 if(!self.socket)return;
 }
 }@catch(NSException *e){[self fail:@"Datos de protocolo rechazados" retry:NO];}
}
- (void)node:(NSDictionary *)n {
 NSString *tag=n[@"tag"];NSDictionary *a=n[@"attrs"];
 if([tag isEqual:@"iq"]&&WLChild(n,@"pair-device")){
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(deadline) object:nil];[self sendNode:WLNode(@"iq",@{@"id":a[@"id"]?:@"",@"to":@"@s.whatsapp.net",@"type":@"result"},nil)];self.refs=[NSMutableArray array];for(NSDictionary *ref in WLChildren(WLChild(n,@"pair-device"))){if([ref[@"tag"] isEqual:@"ref"]&&[ref[@"content"] isKindOfClass:[NSData class]]){NSString *s=[[NSString alloc] initWithData:ref[@"content"] encoding:NSUTF8StringEncoding];if(s)[self.refs addObject:s];}}[self nextQR];return;
 }
 if([tag isEqual:@"iq"]&&WLChild(n,@"pair-success")){[self pair:n];return;}
 if([tag isEqual:@"success"]){self.authenticated=YES;self.retries=0;[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(deadline) object:nil];[self.qrTimer invalidate];if(self.onQR)self.onQR(nil);[self status:@"Autenticado en WhatsApp"];self.ping=[NSTimer scheduledTimerWithTimeInterval:20 target:self selector:@selector(keepalive) userInfo:nil repeats:YES];if(self.onNode)self.onNode(n);return;}
 if([tag isEqual:@"failure"]||[tag isEqual:@"stream:error"]){NSInteger reason=[a[@"reason"]?:a[@"code"] integerValue];BOOL restart=reason==515;[self fail:[NSString stringWithFormat:@"WhatsApp cerró la conexión (%ld)",(long)reason] retry:restart||reason==408||reason==503];return;}
 if([tag isEqual:@"iq"]&&[a[@"type"] isEqual:@"get"]&&([a[@"xmlns"] isEqual:@"urn:xmpp:ping"]||WLChild(n,@"ping")))[self sendNode:WLNode(@"iq",@{@"to":@"@s.whatsapp.net",@"id":a[@"id"]?:@"",@"type":@"result"},nil)];
 if(self.onNode)self.onNode(n);
}
- (void)nextQR{[self.qrTimer invalidate];if(!self.refs.count){[self fail:@"QR caducado. Vuelve a conectar." retry:NO];return;}NSString *ref=self.refs.firstObject;[self.refs removeObjectAtIndex:0];NSArray *parts=@[ref,[publicKey(self.creds[@"noise"]) base64EncodedStringWithOptions:0],[publicKey(self.creds[@"identity"]) base64EncodedStringWithOptions:0],[self.creds[@"adv"] base64EncodedStringWithOptions:0]];if(self.onQR)self.onQR([parts componentsJoinedByString:@","]);[self status:@"Escanea desde WhatsApp > Dispositivos vinculados"];self.qrTimer=[NSTimer scheduledTimerWithTimeInterval:45 target:self selector:@selector(nextQR) userInfo:nil repeats:NO];}
- (void)pair:(NSDictionary *)n {
 NSDictionary *pair=WLChild(n,@"pair-success"),*device=WLChild(pair,@"device"),*identity=WLChild(pair,@"device-identity");NSData *wrapped=identity[@"content"];if(![wrapped isKindOfClass:[NSData class]]){[self fail:@"Identidad de vinculación ausente" retry:NO];return;}
 NSData *account=WLField(wrapped,1),*mac=WLField(wrapped,2);uint8_t check[32];NSData *adv=self.creds[@"adv"];CCHmac(kCCHmacAlgSHA256,adv.bytes,adv.length,account.bytes,account.length,check);BOOL valid=same(mac,[NSData dataWithBytes:check length:32]);wl_clear(check,32);if(!valid){[self fail:@"HMAC de vinculación incorrecto" retry:NO];return;}
 NSData *details=WLField(account,1),*key=WLField(account,2),*sig=WLField(account,3);if(key.length==33&&((const uint8_t *)key.bytes)[0]==5)key=[key subdataWithRange:NSMakeRange(1,32)];NSData *pub=publicKey(self.creds[@"identity"]);NSData *signedMessage=join(@[[NSData dataWithBytes:"\6\0" length:2],details?:[NSData data],pub]);if(key.length!=32||sig.length!=64||wl_verify(key.bytes,signedMessage.bytes,signedMessage.length,sig.bytes)){[self fail:@"Firma de cuenta incorrecta" retry:NO];return;}
 NSData *originalKey=WLField(account,2);NSData *deviceMessage=join(@[[NSData dataWithBytes:"\6\1" length:2],details,pub,originalKey]);NSData *nonce=randomData(64);uint8_t signature[64];if(wl_sign([self.creds[@"identity"] bytes],deviceMessage.bytes,deviceMessage.length,nonce.bytes,signature)){[self fail:@"Error firmando dispositivo" retry:NO];return;}
 NSData *devSig=[NSData dataWithBytes:signature length:64];wl_clear(signature,64);NSData *reply=WLPB(@{@1:details,@3:sig,@4:devSig});NSString *me=device[@"attrs"][@"jid"];if(!me.length){[self fail:@"Identificador de dispositivo ausente" retry:NO];return;}
 self.creds[@"account"]=WLPB(@{@1:details,@2:originalKey,@3:sig,@4:devSig});self.creds[@"me"]=me;if(device[@"attrs"][@"lid"])self.creds[@"lid"]=device[@"attrs"][@"lid"];
 if(![self save]){[self fail:@"No se pudo guardar la sesión en Keychain" retry:NO];return;}
 [self sendNode:WLNode(@"iq",@{@"to":@"@s.whatsapp.net",@"id":n[@"attrs"][@"id"]?:@"",@"type":@"result"},@[WLNode(@"pair-device-sign",nil,@[WLNode(@"device-identity",@{@"key-index":[NSString stringWithFormat:@"%llu",(unsigned long long)WLNumber(details,3)]},reply)])])];[self.qrTimer invalidate];if(self.onQR)self.onQR(nil);[self status:@"Dispositivo vinculado. Esperando reconexión…"];
}
- (void)keepalive{[self sendNode:WLNode(@"iq",@{@"to":@"@s.whatsapp.net",@"type":@"get",@"xmlns":@"w:p",@"id":[NSUUID UUID].UUIDString},@[WLNode(@"ping",nil,nil)])];}
- (void)stopSocket {[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(deadline) object:nil];[self.ping invalidate];self.ping=nil;[self.qrTimer invalidate];self.qrTimer=nil;self.refs=nil;self.socket.delegate=nil;[self.socket close];self.socket=nil;self.authenticated=NO;wl_noise_destroy(&_noise);if(self.onQR)self.onQR(nil);}
- (void)fail:(NSString *)message retry:(BOOL)retry{[self stopSocket];[self status:message];if(retry&&self.desired&&self.retries<8){unsigned delay=MIN(60,1u<<self.retries++);[self performSelector:@selector(attempt) withObject:nil afterDelay:delay+arc4random_uniform(1000)/1000.0];}else self.desired=NO;}
- (void)disconnect{self.desired=NO;[NSObject cancelPreviousPerformRequestsWithTarget:self];[self stopSocket];[self status:@"Desconectado"];}
- (void)webSocket:(SRWebSocket *)ws didFailWithError:(NSError *)error{if(ws==self.socket)[self fail:[NSString stringWithFormat:@"Error de transporte (%ld)",(long)error.code] retry:YES];}
- (void)webSocket:(SRWebSocket *)ws didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)clean{if(ws==self.socket)[self fail:[NSString stringWithFormat:@"WebSocket cerrado (%ld)",(long)code] retry:YES];}
- (void)dealloc{wl_noise_destroy(&_noise);}
@end
