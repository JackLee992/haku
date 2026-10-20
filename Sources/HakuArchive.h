#import <Foundation/Foundation.h>
BOOL HakuCreateArchive(NSString *payload, NSString *destination, NSError **error);
BOOL HakuVerifyArchive(NSString *path, NSError **error);
BOOL HakuCreateArchiveWithCancellation(NSString *payload, NSString *destination, BOOL (^cancelled)(void), NSError **error);
BOOL HakuVerifyArchiveWithCancellation(NSString *path, BOOL (^cancelled)(void), NSError **error);
