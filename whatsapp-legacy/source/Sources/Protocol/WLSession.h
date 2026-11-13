#import <Foundation/Foundation.h>
@interface WLSession : NSObject
@property(nonatomic,copy) void (^onStatus)(NSString *status);
@property(nonatomic,copy) void (^onQR)(NSString *payload);
@property(nonatomic,copy) void (^onNode)(NSDictionary *node);
@property(nonatomic,readonly) BOOL authenticated;
@property(nonatomic,readonly) NSDictionary *credentials;
- (void)connect;
- (void)disconnect;
- (BOOL)sendNode:(NSDictionary *)node;
@end
