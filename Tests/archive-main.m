#import "HakuArchive.h"
int main(int argc,char **argv) {
    @autoreleasepool {
        NSError *error=nil;BOOL ok=NO;
        if(argc==4 && !strcmp(argv[1],"create"))ok=HakuCreateArchive(@(argv[2]),@(argv[3]),&error);
        else if(argc==4 && !strcmp(argv[1],"cancel"))ok=HakuCreateArchiveWithCancellation(@(argv[2]),@(argv[3]),^BOOL {return YES;},&error);
        else if(argc==3 && !strcmp(argv[1],"verify"))ok=HakuVerifyArchive(@(argv[2]),&error);
        if(!ok)fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);
        return ok?0:1;
    }
}
