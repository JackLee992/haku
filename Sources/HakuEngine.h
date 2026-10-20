#import <Foundation/Foundation.h>
typedef void (^HakuProgress)(NSString *message);
@interface HakuEngine : NSObject
@property(nonatomic,copy) HakuProgress progress;
@property(nonatomic) NSUInteger serverPort;
- (NSArray<NSDictionary *> *)applications:(NSError **)error;
- (NSDictionary *)captureBundle:(NSString *)bundle output:(NSString *)directory keepAlive:(BOOL)keepAlive error:(NSError **)error;
- (void)cancel;
@end
