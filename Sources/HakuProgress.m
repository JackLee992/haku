#import "HakuProgress.h"

NSString *HakuFormatCapturedBytes(uint64_t bytes) {
    if(bytes<1024)return [NSString stringWithFormat:@"%llu %@",(unsigned long long)bytes,bytes==1?@"byte":@"bytes"];
    double divisor=1024.0;NSString *unit=@"KiB";
    if(bytes>=1073741824ULL) { divisor=1073741824.0;unit=@"GiB"; }
    else if(bytes>=1048576ULL) { divisor=1048576.0;unit=@"MiB"; }
    return [NSString stringWithFormat:@"%.1f %@ (%llu bytes)",bytes/divisor,unit,(unsigned long long)bytes];
}
