#import <Foundation/Foundation.h>
#import <sqlite3.h>
@class WLSession;
@interface WLChatEngine:NSObject
@property(nonatomic,readonly) WLSession *session;
@property(nonatomic,copy) void (^onChange)(void);
@property(nonatomic,copy) void (^onQueued)(NSString *text);
@property(nonatomic,copy) void (^onError)(NSString *message);
- (instancetype)initWithDatabase:(sqlite3 *)db;
- (void)sendText:(NSString *)text to:(NSString *)jid;
@end
