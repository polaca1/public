#import "WLChatEngine.h"
#import "WLSession.h"
#import "WLWire.h"
#import <Security/Security.h>
#include "wl_signal.h"
#include "wl_crypto.h"
static int rng(uint8_t *p,size_t n,void *u){return SecRandomCopyBytes(kSecRandomDefault,n,p)==errSecSuccess?0:-1;}
static NSData *randbytes(NSUInteger n){NSMutableData *d=[NSMutableData dataWithLength:n];if(rng(d.mutableBytes,n,NULL))@throw [NSException exceptionWithName:@"WLRNG" reason:@"Random failed" userInfo:nil];return d;}
static NSData *pub(NSData *priv){uint8_t p[32];if(priv.length!=32||wl_public(priv.bytes,p))return nil;return [NSData dataWithBytes:p length:32];}
static NSData *be(uint32_t v,unsigned n){uint8_t p[4];for(unsigned i=0;i<n;i++)p[i]=v>>(8*(n-1-i));return [NSData dataWithBytes:p length:n];}
static uint32_t uintnode(NSDictionary *node){NSData *d=node[@"content"];if(![d isKindOfClass:[NSData class]]||d.length>4)return 0;const uint8_t *p=d.bytes;uint32_t v=0;for(NSUInteger i=0;i<d.length;i++)v=(v<<8)|p[i];return v;}
static NSString *baseJID(NSString *jid){NSArray *a=[jid componentsSeparatedByString:@"@"];if(a.count!=2)return nil;return [NSString stringWithFormat:@"%@@%@",[a[0] componentsSeparatedByString:@":"].firstObject,a[1]];}
static int deviceID(NSString *jid){NSArray *a=[[[jid componentsSeparatedByString:@"@"] firstObject] componentsSeparatedByString:@":"];return a.count>1?[a[1] intValue]:0;}
static NSString *normalized(NSString *jid){NSString *base=baseJID(jid);NSArray *a=[base componentsSeparatedByString:@"@"];if(a.count!=2)return nil;return [NSString stringWithFormat:@"%@:%d@%@",a[0],deviceID(jid),a[1]];}
@interface WLChatEngine(){sqlite3 *_db;wl_signal *_signal;}
@property(nonatomic,strong) WLSession *session;
@property(nonatomic,strong) NSMutableDictionary *pending;
@property(nonatomic) BOOL ready;
@end
@implementation WLChatEngine
- (instancetype)initWithDatabase:(sqlite3 *)db{if((self=[super init])){_db=db;self.pending=[NSMutableDictionary dictionary];self.session=[WLSession new];__weak WLChatEngine *weak=self;self.session.onNode=^(NSDictionary *n){[weak handle:n];};if(sqlite3_exec(db,"CREATE TABLE IF NOT EXISTS outbox(id TEXT PRIMARY KEY,packet BLOB NOT NULL);CREATE TABLE IF NOT EXISTS inbound_ids(id TEXT PRIMARY KEY);CREATE TABLE IF NOT EXISTS upload_keys(id INTEGER PRIMARY KEY,public BLOB NOT NULL);",NULL,NULL,NULL)!=SQLITE_OK)return nil;}return self;}
- (void)error:(NSString *)s{if(self.onError)self.onError(s);}
- (BOOL)sql:(const char *)sql{return sqlite3_exec(_db,sql,NULL,NULL,NULL)==SQLITE_OK;}
- (void)change{if(self.onChange)self.onChange();}
- (BOOL)writeMessage:(NSString *)id chat:(NSString *)chat text:(NSString *)text outgoing:(BOOL)outgoing time:(int64_t)time status:(NSString *)status{
 sqlite3_stmt *q=NULL;if(sqlite3_prepare_v2(_db,"INSERT OR IGNORE INTO chats(id,title) VALUES(?,?)",-1,&q,NULL)!=SQLITE_OK)return NO;sqlite3_bind_text(q,1,chat.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_text(q,2,chat.UTF8String,-1,SQLITE_TRANSIENT);int rc=sqlite3_step(q);sqlite3_finalize(q);if(rc!=SQLITE_DONE)return NO;
 if(sqlite3_prepare_v2(_db,"INSERT OR IGNORE INTO messages(id,chat_id,body,outgoing,timestamp,status) VALUES(?,?,?,?,?,?)",-1,&q,NULL)!=SQLITE_OK)return NO;
 sqlite3_bind_text(q,1,id.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_text(q,2,chat.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_text(q,3,text.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_int(q,4,outgoing);sqlite3_bind_int64(q,5,time);sqlite3_bind_text(q,6,status.UTF8String,-1,SQLITE_TRANSIENT);rc=sqlite3_step(q);sqlite3_finalize(q);return rc==SQLITE_DONE;
}
- (BOOL)seen:(NSString *)id {sqlite3_stmt *q=NULL;if(sqlite3_prepare_v2(_db,"SELECT 1 FROM (SELECT id FROM messages UNION ALL SELECT id FROM inbound_ids) WHERE id=?",-1,&q,NULL)!=SQLITE_OK)return NO;sqlite3_bind_text(q,1,id.UTF8String,-1,SQLITE_TRANSIENT);BOOL found=sqlite3_step(q)==SQLITE_ROW;sqlite3_finalize(q);return found;}
- (void)query:(NSDictionary *)n completion:(void (^)(NSDictionary *))completion {
 NSString *id=n[@"attrs"][@"id"]?:[NSUUID UUID].UUIDString;NSMutableDictionary *attrs=[n[@"attrs"] mutableCopy];attrs[@"id"]=id;
 self.pending[id]=[completion copy];if(![self.session sendNode:WLNode(n[@"tag"],attrs,n[@"content"])]){[self.pending removeObjectForKey:id];completion(nil);return;}
 [NSTimer scheduledTimerWithTimeInterval:25 target:self selector:@selector(expire:) userInfo:id repeats:NO];
}
- (void)expire:(NSTimer *)timer{NSString *id=timer.userInfo;void (^block)(NSDictionary *)=self.pending[id];if(block){[self.pending removeObjectForKey:id];block(nil);}}
- (void)ack:(NSDictionary *)n{NSDictionary *a=n[@"attrs"];NSMutableDictionary *attrs=[@{@"id":a[@"id"]?:@"",@"to":a[@"from"]?:@"@s.whatsapp.net",@"class":n[@"tag"]} mutableCopy];for(NSString *key in @[@"participant",@"type",@"recipient"])if(a[key])attrs[key]=a[key];[self.session sendNode:WLNode(@"ack",attrs,nil)];}
- (void)handle:(NSDictionary *)n {
 @try{NSString *tag=n[@"tag"],*id=n[@"attrs"][@"id"];void (^block)(NSDictionary *)=id?self.pending[id]:nil;if([tag isEqual:@"iq"]&&block){[self.pending removeObjectForKey:id];block([n[@"attrs"][@"type"] isEqual:@"error"]?nil:n);return;}
 if([tag isEqual:@"success"]){[self start];return;}
 if([tag isEqual:@"message"]){[self receive:n];return;}
 if([tag isEqual:@"ack"]&&[n[@"attrs"][@"class"] isEqual:@"message"]){[self update:id status:n[@"attrs"][@"error"]?@"rechazado":@"aceptado por servidor"];sqlite3_stmt *q=NULL;if(sqlite3_prepare_v2(_db,"DELETE FROM outbox WHERE id=?",-1,&q,NULL)==SQLITE_OK){sqlite3_bind_text(q,1,id.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_step(q);sqlite3_finalize(q);}return;}
 if([tag isEqual:@"receipt"]){[self update:id status:[n[@"attrs"][@"type"] isEqual:@"read"]?@"leído":@"entregado"];[self ack:n];return;}
 if([tag isEqual:@"notification"]){[self ack:n];return;}
 if([tag isEqual:@"ib"]&&WLChild(n,@"offline_preview")){[self.session sendNode:WLNode(@"ib",nil,@[WLNode(@"offline_batch",@{@"count":@"100"},nil)])];return;}
 }@catch(NSException *e){[self sql:"ROLLBACK"];[self error:@"Se rechazaron datos de protocolo inválidos"];} }
- (void)update:(NSString *)id status:(NSString *)status{if(!id)return;sqlite3_stmt *q=NULL;if(sqlite3_prepare_v2(_db,"UPDATE messages SET status=? WHERE id=? AND outgoing=1",-1,&q,NULL)!=SQLITE_OK)return;sqlite3_bind_text(q,1,status.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_text(q,2,id.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_step(q);sqlite3_finalize(q);[self change];}
- (void)start{
 self.ready=NO;if(_signal){wl_signal_close(_signal);_signal=NULL;}NSDictionary *c=self.session.credentials;
 if(wl_signal_open(&_signal,_db,[c[@"identity"] bytes],[c[@"registration"] unsignedIntValue],rng,NULL)||wl_signal_prekey(_signal,1,[c[@"signed"] bytes],1,[c[@"signature"] bytes])){[self error:@"Error preparando sesiones Signal"];return;}
 __weak WLChatEngine *weak=self;
 [self query:WLNode(@"iq",@{@"to":@"@s.whatsapp.net",@"type":@"get",@"xmlns":@"encrypt"},@[WLNode(@"count",nil,nil)]) completion:^(NSDictionary *response){WLChatEngine *s=weak;if(!s)return;if(!response){[s error:@"WhatsApp no respondió a la consulta de preclaves"];return;}
 unsigned count=[WLChild(response,@"count")[@"attrs"][@"value"] intValue];sqlite3_stmt *local=NULL;int held=0;if(sqlite3_prepare_v2(s->_db,"SELECT COUNT(*) FROM signal_records WHERE kind=1",-1,&local,NULL)==SQLITE_OK){if(sqlite3_step(local)==SQLITE_ROW)held=sqlite3_column_int(local,0);sqlite3_finalize(local);}if(count<5||held==0)[s upload];else [s activate];}];
}
- (void)upload{
 NSDictionary *c=self.session.credentials;NSMutableArray *keys=[NSMutableArray array];sqlite3_stmt *q=NULL;unsigned start=1;
 if(sqlite3_prepare_v2(_db,"SELECT COALESCE(MAX(id),0)+1 FROM upload_keys",-1,&q,NULL)!=SQLITE_OK)return;if(sqlite3_step(q)==SQLITE_ROW)start=sqlite3_column_int(q,0);sqlite3_finalize(q);
 if(start>0xffff00||![self sql:"BEGIN IMMEDIATE"]){[self error:@"No se pueden generar preclaves"];return;}
 BOOL ok=YES;for(unsigned i=start;i<start+30;i++){NSMutableData *priv=[randbytes(32) mutableCopy];uint8_t *p=priv.mutableBytes;p[0]&=248;p[31]&=127;p[31]|=64;NSData *public=pub(priv);if(wl_signal_prekey(_signal,i,priv.bytes,0,NULL)){ok=NO;break;}
 if(sqlite3_prepare_v2(_db,"INSERT INTO upload_keys(id,public) VALUES(?,?)",-1,&q,NULL)!=SQLITE_OK){ok=NO;break;}sqlite3_bind_int(q,1,i);sqlite3_bind_blob(q,2,public.bytes,(int)public.length,SQLITE_TRANSIENT);int rc=sqlite3_step(q);sqlite3_finalize(q);if(rc!=SQLITE_DONE){ok=NO;break;}[keys addObject:WLNode(@"key",nil,@[WLNode(@"id",nil,be(i,3)),WLNode(@"value",nil,public)])];wl_clear(priv.mutableBytes,priv.length);}
 if(!ok||![self sql:"COMMIT"]){[self sql:"ROLLBACK"];[self error:@"No se pudieron guardar las preclaves"];return;}
 NSDictionary *skey=WLNode(@"skey",nil,@[WLNode(@"id",nil,be(1,3)),WLNode(@"value",nil,pub(c[@"signed"])),WLNode(@"signature",nil,c[@"signature"])]);
 __weak WLChatEngine *weak=self;[self query:WLNode(@"iq",@{@"to":@"@s.whatsapp.net",@"xmlns":@"encrypt",@"type":@"set"},@[WLNode(@"registration",nil,be([c[@"registration"] unsignedIntValue],4)),WLNode(@"type",nil,[NSData dataWithBytes:"\5" length:1]),WLNode(@"identity",nil,pub(c[@"identity"])),WLNode(@"list",nil,keys),skey]) completion:^(NSDictionary *r){if(r)[weak activate];else [weak error:@"WhatsApp no confirmó la subida de preclaves"];}];
}
- (void)activate{__weak WLChatEngine *weak=self;[self query:WLNode(@"iq",@{@"to":@"@s.whatsapp.net",@"xmlns":@"passive",@"type":@"set"},@[WLNode(@"active",nil,nil)]) completion:^(NSDictionary *r){if(!r){[weak error:@"WhatsApp no activó el dispositivo"];return;}weak.ready=YES;[weak flush];[weak change];}];}
- (void)flush{sqlite3_stmt *q=NULL;if(sqlite3_prepare_v2(_db,"SELECT packet FROM outbox ORDER BY rowid",-1,&q,NULL)!=SQLITE_OK)return;while(sqlite3_step(q)==SQLITE_ROW){NSData *data=[NSData dataWithBytes:sqlite3_column_blob(q,0) length:sqlite3_column_bytes(q,0)];NSDictionary *node=[NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];if(node)[self.session sendNode:node];}sqlite3_finalize(q);}
- (void)sendText:(NSString *)text to:(NSString *)jid {
 if(!self.session.authenticated||!self.ready||!_signal){[self error:@"Vincula el dispositivo y espera a que termine la preparación"];return;}
 NSString *recipient=baseJID(jid);if(!recipient||![recipient hasSuffix:@"@s.whatsapp.net"]||!text.length||[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>32000){[self error:@"Destinatario o texto no válido"];return;}
 NSString *me=baseJID(self.session.credentials[@"me"]),*sid=[NSUUID UUID].UUIDString;
 NSDictionary *query=WLNode(@"usync",@{@"sid":sid,@"mode":@"query",@"last":@"true",@"index":@"0",@"context":@"message"},@[WLNode(@"query",nil,@[WLNode(@"devices",@{@"version":@"2"},nil)]),WLNode(@"list",nil,@[WLNode(@"user",@{@"jid":me},nil),WLNode(@"user",@{@"jid":recipient},nil)])]);
 __weak WLChatEngine *weak=self;[self query:WLNode(@"iq",@{@"to":@"@s.whatsapp.net",@"type":@"get",@"xmlns":@"usync",@"id":sid},@[query]) completion:^(NSDictionary *r){if(!r){[weak error:@"No se pudieron consultar los dispositivos"];return;}NSMutableOrderedSet *devices=[NSMutableOrderedSet orderedSet];BOOL recipientFound=NO;
 for(NSDictionary *user in WLChildren(WLChild(WLChild(r,@"usync"),@"list"))){NSString *base=baseJID(user[@"attrs"][@"jid"]);if(![base isEqual:me]&&![base isEqual:recipient])continue;NSArray *a=[base componentsSeparatedByString:@"@"];NSArray *list=WLChildren(WLChild(WLChild(user,@"devices"),@"device-list"));if(!list.count)list=@[WLNode(@"device",@{@"id":@"0"},nil)];for(NSDictionary *d in list){unsigned id=[d[@"attrs"][@"id"] intValue];if(id>255||id==99)continue;NSString *target=[NSString stringWithFormat:@"%@:%u@%@",a[0],id,a[1]];if([base isEqual:recipient])recipientFound=YES;if(![target isEqual:normalized(weak.session.credentials[@"me"])])[devices addObject:target];}}
 if(!recipientFound||!devices.count){[weak error:@"WhatsApp no devolvió dispositivos para el destinatario"];return;}[weak ensure:devices.array text:text recipient:recipient];}];
}
- (void)ensure:(NSArray *)devices text:(NSString *)text recipient:(NSString *)recipient{
 NSMutableArray *missing=[NSMutableArray array];for(NSString *jid in devices){int rc=wl_signal_contains(_signal,baseJID(jid).UTF8String,deviceID(jid));if(rc<0){[self error:@"Error leyendo sesiones Signal"];return;}if(!rc)[missing addObject:WLNode(@"user",@{@"jid":jid},nil)];}
 if(!missing.count){[self encrypt:devices text:text recipient:recipient];return;}
 __weak WLChatEngine *weak=self;[self query:WLNode(@"iq",@{@"to":@"@s.whatsapp.net",@"type":@"get",@"xmlns":@"encrypt"},@[WLNode(@"key",nil,missing)]) completion:^(NSDictionary *r){WLChatEngine *s=weak;if(!s||!r){[s error:@"No se recibieron claves de los dispositivos"];return;}BOOL ok=[s sql:"BEGIN IMMEDIATE"];if(!ok)return;
 for(NSDictionary *user in WLChildren(WLChild(r,@"list"))){NSString *jid=user[@"attrs"][@"jid"];if(![devices containsObject:normalized(jid)])continue;NSDictionary *sk=WLChild(user,@"skey"),*pk=WLChild(user,@"key");NSData *identity=WLChild(user,@"identity")[@"content"],*signedPub=WLChild(sk,@"value")[@"content"],*signature=WLChild(sk,@"signature")[@"content"],*one=WLChild(pk,@"value")[@"content"];
 if(identity.length!=32||signedPub.length!=32||signature.length!=64||(one&&one.length!=32)||wl_signal_bundle(s->_signal,baseJID(jid).UTF8String,deviceID(jid),uintnode(WLChild(user,@"registration")),identity.bytes,uintnode(WLChild(sk,@"id")),signedPub.bytes,signature.bytes,uintnode(WLChild(pk,@"id")),one.bytes)){ok=NO;break;}}
 for(NSString *jid in devices)if(wl_signal_contains(s->_signal,baseJID(jid).UTF8String,deviceID(jid))!=1)ok=NO;
 if(!ok||![s sql:"COMMIT"]){[s sql:"ROLLBACK"];[s error:@"No se pudieron verificar las sesiones Signal. No se envió el mensaje."];return;}[s encrypt:devices text:text recipient:recipient];}];
}
- (void)encrypt:(NSArray *)devices text:(NSString *)text recipient:(NSString *)recipient {
 if(![self sql:"BEGIN IMMEDIATE"])return;BOOL ok=YES,identityNeeded=NO;NSMutableArray *parts=[NSMutableArray array];NSString *me=baseJID(self.session.credentials[@"me"]);
 NSData *message=WLPB(@{@1:text});for(NSString *jid in devices){NSData *body=[baseJID(jid) isEqual:me]?WLPB(@{@31:WLPB(@{@1:recipient,@2:message})}):message;NSMutableData *padded=[body mutableCopy];uint8_t pad=(((const uint8_t *)randbytes(1).bytes)[0]&15)+1;for(unsigned i=0;i<pad;i++)[padded appendBytes:&pad length:1];uint8_t *cipher=NULL;size_t n=0;int type;
 if(wl_signal_encrypt(_signal,baseJID(jid).UTF8String,deviceID(jid),(wl_bytes){padded.bytes,padded.length},&cipher,&n,&type)){ok=NO;break;}NSData *ct=[NSData dataWithBytes:cipher length:n];wl_signal_free(cipher,n);wl_clear(padded.mutableBytes,padded.length);identityNeeded|=type==3;[parts addObject:WLNode(@"to",@{@"jid":jid},@[WLNode(@"enc",@{@"v":@"2",@"type":type==3?@"pkmsg":@"msg"},ct)])];}
 NSMutableString *id=[NSMutableString stringWithString:@"3EB0"];NSData *random=randbytes(18);for(unsigned i=0;i<18;i++)[id appendFormat:@"%02X",((const uint8_t *)random.bytes)[i]];
 NSMutableArray *content=[NSMutableArray arrayWithObject:WLNode(@"participants",nil,parts)];if(identityNeeded){NSData *account=self.session.credentials[@"account"];if(account)[content addObject:WLNode(@"device-identity",nil,account)];else ok=NO;}
 NSDictionary *node=WLNode(@"message",@{@"id":id,@"to":recipient,@"type":@"text"},content);NSData *packet=[NSPropertyListSerialization dataWithPropertyList:node format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];sqlite3_stmt *q=NULL;
 if(ok&&packet&&sqlite3_prepare_v2(_db,"INSERT INTO outbox(id,packet) VALUES(?,?)",-1,&q,NULL)==SQLITE_OK){sqlite3_bind_text(q,1,id.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_blob(q,2,packet.bytes,(int)packet.length,SQLITE_TRANSIENT);ok=sqlite3_step(q)==SQLITE_DONE;sqlite3_finalize(q);}else ok=NO;
 if(ok)ok=[self writeMessage:id chat:recipient text:text outgoing:YES time:(int64_t)[NSDate date].timeIntervalSince1970 status:@"en cola"];
 if(!ok||![self sql:"COMMIT"]){[self sql:"ROLLBACK"];[self error:@"No se pudo guardar el mensaje cifrado"];return;}[self.session sendNode:node];if(self.onQueued)self.onQueued(text);[self change];
}
- (void)receive:(NSDictionary *)node {
 NSDictionary *attrs=node[@"attrs"],*enc=WLChild(node,@"enc");NSString *id=attrs[@"id"],*from=attrs[@"from"],*sender=attrs[@"participant"]?:from,*type=enc[@"attrs"][@"type"];NSData *cipher=enc[@"content"];
 if(!id.length||!sender.length||!_signal)return;
 if([self seen:id]){[self ack:node];return;}
 if(![type isEqual:@"pkmsg"]&&![type isEqual:@"msg"]){[self error:@"Mensaje recibido de un tipo todavía no compatible"];return;}
 if(![cipher isKindOfClass:[NSData class]]||![self sql:"BEGIN IMMEDIATE"])return;uint8_t *plain=NULL;size_t n=0;
 int rc=wl_signal_decrypt(_signal,baseJID(sender).UTF8String,deviceID(sender),[type isEqual:@"pkmsg"]?3:2,(wl_bytes){cipher.bytes,cipher.length},&plain,&n);if(rc||!n){[self sql:"ROLLBACK"];[self error:[NSString stringWithFormat:@"No se pudo descifrar el mensaje (Signal %d)",rc]];return;}
 unsigned pad=plain[n-1];BOOL valid=pad>=1&&pad<=16&&pad<=n;for(unsigned i=0;valid&&i<pad;i++)if(plain[n-1-i]!=pad)valid=NO;
 if(!valid){wl_signal_free(plain,n);[self sql:"ROLLBACK"];[self error:@"Padding de mensaje incorrecto"];return;}
 NSData *message=[NSData dataWithBytes:plain length:n-pad];wl_signal_free(plain,n);BOOL outgoing=NO;NSString *chat=baseJID(from);NSData *dsm=WLField(message,31);
 if(dsm){outgoing=YES;chat=[[NSString alloc] initWithData:WLField(dsm,1) encoding:NSUTF8StringEncoding];message=WLField(dsm,2);}
 NSData *textBytes=WLField(message,1);if(!textBytes){NSData *extended=WLField(message,6);if(extended)textBytes=WLField(extended,1);}NSString *text=textBytes?[[NSString alloc] initWithData:textBytes encoding:NSUTF8StringEncoding]:nil;
 if(!chat.length){[self sql:"ROLLBACK"];return;}
 BOOL ok=YES;if(text)ok=[self writeMessage:id chat:chat text:text outgoing:outgoing time:[attrs[@"t"] longLongValue] status:@"recibido"];
 sqlite3_stmt *mark=NULL;if(sqlite3_prepare_v2(_db,"INSERT OR IGNORE INTO inbound_ids(id) VALUES(?)",-1,&mark,NULL)==SQLITE_OK){sqlite3_bind_text(mark,1,id.UTF8String,-1,SQLITE_TRANSIENT);ok=ok&&sqlite3_step(mark)==SQLITE_DONE;sqlite3_finalize(mark);}else ok=NO;
 // Non-text payloads still advance the authenticated ratchet, without fake chat content.
 if(!ok||![self sql:"COMMIT"]){[self sql:"ROLLBACK"];[self error:@"No se pudo guardar el mensaje recibido"];return;}
 [self ack:node];NSMutableDictionary *receipt=[@{@"id":id,@"to":from} mutableCopy];if(attrs[@"participant"])receipt[@"participant"]=attrs[@"participant"];[self.session sendNode:WLNode(@"receipt",receipt,nil)];[self change];
}
- (void)dealloc{if(_signal)wl_signal_close(_signal);}
@end
