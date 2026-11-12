#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <sqlite3.h>
#import "SRWebSocket.h"

// Diagnostic build: never represents a WebSocket open as a WhatsApp login.
@interface WLApp : UIResponder <UIApplicationDelegate, SRWebSocketDelegate, UITableViewDataSource, UITableViewDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) SRWebSocket *socket;
@property(nonatomic,strong) NSArray *chats;
@property(nonatomic,assign) sqlite3 *database;
@end
@implementation WLApp
- (UIViewController *)page:(NSString *)title text:(NSString *)text {
    UIViewController *vc=[UIViewController new]; vc.title=title; vc.view.backgroundColor=[UIColor whiteColor];
    UITextView *body=[[UITextView alloc] initWithFrame:CGRectZero]; body.editable=NO; body.text=text; body.font=[UIFont systemFontOfSize:17];
    body.translatesAutoresizingMaskIntoConstraints=NO; [vc.view addSubview:body];
    [NSLayoutConstraint activateConstraints:@[[body.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:12],[body.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-12],[body.topAnchor constraintEqualToAnchor:vc.topLayoutGuide.bottomAnchor constant:12],[body.bottomAnchor constraintEqualToAnchor:vc.bottomLayoutGuide.topAnchor constant:-12]]];
    return vc;
}
- (BOOL)openStore {
    NSFileManager *fm=[NSFileManager defaultManager]; NSURL *dir=[[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject]; dir=[dir URLByAppendingPathComponent:@"WhatsAppLegacy" isDirectory:YES];
    NSError *error=nil;
    if (![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication,NSFilePosixPermissions:@0700} error:&error]) return NO;
    if (![dir setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error]) return NO;
    NSString *path=[[dir URLByAppendingPathComponent:@"messages.sqlite"] path]; sqlite3 *db=NULL;
    if (sqlite3_open_v2(path.UTF8String,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX,NULL)!=SQLITE_OK) { if(db)sqlite3_close(db); return NO; }
    self.database=db; sqlite3_busy_timeout(db,3000);
    const char *schema="PRAGMA foreign_keys=ON; BEGIN; CREATE TABLE IF NOT EXISTS chats(id TEXT PRIMARY KEY,title TEXT NOT NULL); CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,chat_id TEXT NOT NULL REFERENCES chats(id),body TEXT NOT NULL,outgoing INTEGER NOT NULL CHECK(outgoing IN(0,1)),timestamp INTEGER NOT NULL,status TEXT NOT NULL); CREATE INDEX IF NOT EXISTS message_order ON messages(chat_id,timestamp); CREATE TABLE IF NOT EXISTS contacts(id TEXT PRIMARY KEY,name TEXT NOT NULL); PRAGMA user_version=1; COMMIT;";
    if(sqlite3_exec(db,schema,NULL,NULL,NULL)!=SQLITE_OK) {sqlite3_exec(db,"ROLLBACK",NULL,NULL,NULL); return NO;}
    if (![fm setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication,NSFilePosixPermissions:@0600} ofItemAtPath:path error:&error]) return NO;
    NSMutableArray *rows=[NSMutableArray array]; sqlite3_stmt *s=NULL;
    if(sqlite3_prepare_v2(db,"SELECT id,title FROM chats ORDER BY title",-1,&s,NULL)!=SQLITE_OK)return NO;
    int rc; while((rc=sqlite3_step(s))==SQLITE_ROW) { const char *i=(const char *)sqlite3_column_text(s,0), *t=(const char *)sqlite3_column_text(s,1); if(i&&t)[rows addObject:@{@"id":@(i),@"title":@(t)}]; }
    sqlite3_finalize(s); self.chats=rows; return rc==SQLITE_DONE;
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    BOOL stored=[self openStore];
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UITabBarController *tabs=[UITabBarController new];
    UITableViewController *chats=[[UITableViewController alloc] initWithStyle:UITableViewStylePlain]; chats.title=@"Chats"; chats.tableView.dataSource=self; chats.tableView.delegate=self;
    if(!self.chats.count){UILabel *empty=[UILabel new]; empty.text=@"Sin conversaciones. Vinculación pendiente.";empty.textAlignment=NSTextAlignmentCenter;empty.numberOfLines=0;chats.tableView.backgroundView=empty;}
    UIViewController *contacts=[self page:@"Contactos" text:@"No hay contactos sincronizados. La sincronización necesita autenticación WhatsApp, todavía no implementada."];
    UIViewController *link=[self page:@"Vinculación" text:@"Build experimental 0.1.0.\n\nNo se puede vincular todavía. Faltan Noise, validación de certificados del protocolo, QR real y sesiones Signal.\n\nLa prueba de transporte abre una conexión TLS/WebSocket directa; no autentica ni envía mensajes."];
    link.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Probar WSS" style:UIBarButtonItemStylePlain target:self action:@selector(connect)];
    UIViewController *settings=[self page:@"Ajustes" text:stored?@"SQLite local preparado, sin datos de ejemplo.\n\nNo se han generado credenciales. No se registran cargas útiles ni secretos.\n\nSin servidor intermedio. Mensajería y funcionamiento en un iPhone físico: no verificados.":@"Error preparando SQLite. No uses este build para guardar conversaciones."];
    self.status=[[UILabel alloc] initWithFrame:CGRectMake(0,0,300,55)]; self.status.numberOfLines=0;self.status.font=[UIFont systemFontOfSize:12];self.status.textAlignment=NSTextAlignmentCenter;self.status.text=@"Sin conexión • Sin autenticación";
    link.navigationItem.titleView=self.status;
    NSMutableArray *controllers=[NSMutableArray array]; for(UIViewController *vc in @[chats,contacts,link,settings]){UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:vc];nav.tabBarItem.title=vc.title;[controllers addObject:nav];}
    tabs.viewControllers=controllers;self.window.rootViewController=tabs;[self.window makeKeyAndVisible]; return YES;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return self.chats.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];cell.textLabel.text=self.chats[indexPath.row][@"title"];return cell;}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Mensajería pendiente" message:@"Este build no puede enviar ni recibir mensajes." preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"Aceptar" style:UIAlertActionStyleDefault handler:nil]];[self.window.rootViewController presentViewController:alert animated:YES completion:nil];}
- (void)connect {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(disconnect) object:nil];
    if(self.socket) {self.socket.delegate=nil;[self.socket close];self.socket=nil;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"wss://web.whatsapp.com/ws/chat"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [request setValue:@"https://web.whatsapp.com" forHTTPHeaderField:@"Origin"];
    self.status.text=@"Conectando TLS/WebSocket…"; self.socket=[[SRWebSocket alloc] initWithURLRequest:request];self.socket.delegate=self;[self.socket open];
}
- (void)webSocketDidOpen:(SRWebSocket *)webSocket {if(webSocket==self.socket){self.status.text=@"WebSocket abierto • Sin autenticar";[self performSelector:@selector(disconnect) withObject:nil afterDelay:15];}}
- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {if(webSocket==self.socket){self.status.text=[NSString stringWithFormat:@"Error transporte (%ld) • Sin autenticar",(long)error.code];self.socket=nil;}}
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message { /* Do not log untrusted payloads or imply authentication. */ }
- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)clean {if(webSocket==self.socket){self.status.text=[NSString stringWithFormat:@"Desconectado (%ld) • Sin autenticar",(long)code];self.socket=nil;}}
- (void)disconnect {[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(disconnect) object:nil];self.socket.delegate=nil;[self.socket close];self.socket=nil;self.status.text=@"Sin conexión • Sin autenticación";}
- (void)applicationDidEnterBackground:(UIApplication *)application {[self disconnect];}
- (void)dealloc {if(_database)sqlite3_close(_database);}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass([WLApp class]));}}
