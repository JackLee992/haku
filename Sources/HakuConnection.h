#import <Foundation/Foundation.h>
extern const NSUInteger HakuDefaultServerPort;
BOOL HakuParseServerPort(NSString *text, NSUInteger *port, NSError **error);
NSString *HakuServerAddress(NSUInteger port);
NSUInteger HakuConfiguredServerPort(void);
BOOL HakuSaveServerPort(NSString *text, NSError **error);
