#import "HakuConnection.h"
int main(int argc,char **argv) {
    @autoreleasepool {
        NSUInteger port=HakuDefaultServerPort;NSError *error=nil;
        if(argc>1 && !HakuParseServerPort(@(argv[1]),&port,&error)) {fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 2;}
        puts(HakuServerAddress(port).UTF8String);return 0;
    }
}
