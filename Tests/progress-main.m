#import "HakuProgress.h"
#include <stdlib.h>
#include <stdio.h>

int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;
        puts(HakuFormatCapturedBytes(strtoull(argv[1],NULL,10)).UTF8String);
        return 0;
    }
}
