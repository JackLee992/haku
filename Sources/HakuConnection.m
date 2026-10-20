#import "HakuConnection.h"
const NSUInteger HakuDefaultServerPort=57042;
static NSString * const HakuServerPortKey=@"HakuServerPort";
BOOL HakuParseServerPort(NSString *text, NSUInteger *port, NSError **error) {
    NSUInteger value=0;BOOL valid=text.length>0 && text.length<=5;
    for(NSUInteger i=0;valid && i<text.length;i++) {
        unichar c=[text characterAtIndex:i];
        if(c<'0' || c>'9')valid=NO;
        else value=value*10+(c-'0');
    }
    valid=valid && value>=1 && value<=65535 && value!=27042 && value!=27043;
    if(!valid) {
        if(error)*error=[NSError errorWithDomain:@"HakuConnection" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Enter a port from 1 to 65535, different from Frida ports 27042 and 27043."}];
        return NO;
    }
    if(port)*port=value;return YES;
}
NSString *HakuServerAddress(NSUInteger port) { return [NSString stringWithFormat:@"127.0.0.1:%lu",(unsigned long)port]; }
NSUInteger HakuConfiguredServerPort(void) {
    id stored=[NSUserDefaults.standardUserDefaults objectForKey:HakuServerPortKey];
    NSUInteger port=HakuDefaultServerPort;
    if(stored)HakuParseServerPort([stored description],&port,nil);
    return port;
}
BOOL HakuSaveServerPort(NSString *text,NSError **error) {
    NSUInteger port;
    if(!HakuParseServerPort(text,&port,error))return NO;
    [NSUserDefaults.standardUserDefaults setInteger:port forKey:HakuServerPortKey];
    [NSUserDefaults.standardUserDefaults synchronize];return YES;
}
