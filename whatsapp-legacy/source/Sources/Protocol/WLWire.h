#import <Foundation/Foundation.h>
NSDictionary *WLNode(NSString *tag, NSDictionary *attrs, id content);
NSDictionary *WLChild(NSDictionary *node, NSString *tag);
NSArray *WLChildren(NSDictionary *node);
NSData *WLEncodeNode(NSDictionary *node, NSError **error);
NSDictionary *WLDecodeNode(NSData *data, NSError **error);
NSData *WLPB(NSDictionary<NSNumber *,id> *fields);
NSData *WLField(NSData *data, unsigned field);
uint64_t WLNumber(NSData *data, unsigned field);
