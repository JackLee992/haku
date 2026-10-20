#import "HakuArchive.h"
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

static NSError *zipError(NSString *message) {
    return [NSError errorWithDomain:@"HakuArchive" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static void u16(FILE *f, uint16_t x) { uint8_t b[]={x,x>>8}; if(fwrite(b,1,2,f)!=2) @throw zipError(@"Archive write failed"); }
static void u32(FILE *f, uint32_t x) { u16(f,x);u16(f,x>>16); }
static uint16_t r16(const uint8_t *p) { return p[0]|(uint16_t)p[1]<<8; }
static uint32_t r32(const uint8_t *p) { return r16(p)|(uint32_t)r16(p+2)<<16; }
static void readAt(FILE *f, uint64_t at, void *b, size_t n) {
    if(fseeko(f,(off_t)at,SEEK_SET)||fread(b,1,n,f)!=n) @throw zipError(@"Archive is truncated");
}
static uint32_t position(FILE *f) {
    off_t n=ftello(f);
    if(n<0 || (uint64_t)n>=UINT32_MAX) @throw zipError(@"ZIP64 exports are not supported in this version (4 GiB limit)");
    return (uint32_t)n;
}
static void writeData(FILE *f, const void *b, size_t n) {
    if(fwrite(b,1,n,f)!=n) @throw zipError(@"Archive write failed; check free space");
}
BOOL HakuCreateArchive(NSString *payload, NSString *destination, NSError **error) {
    return HakuCreateArchiveWithCancellation(payload,destination,nil,error);
}
BOOL HakuCreateArchiveWithCancellation(NSString *payload, NSString *destination, BOOL (^cancelled)(void), NSError **error) {
    FILE *out=NULL;
    @try {
        out=fopen(destination.fileSystemRepresentation,"wx");
        if(!out) @throw zipError(@"Cannot create a new archive");
        NSFileManager *fm=NSFileManager.defaultManager;
        NSArray *children=[[fm subpathsOfDirectoryAtPath:payload error:error] sortedArrayUsingSelector:@selector(compare:)];
        if(!children) @throw ((error ? *error : nil) ?: zipError(@"Cannot enumerate Payload"));
        NSMutableArray *entries=[NSMutableArray array];
        for(NSString *relative in [@[@""] arrayByAddingObjectsFromArray:children]) {
            @autoreleasepool {
                if(cancelled && cancelled()) @throw zipError(@"Cancelled; partial archive retained");
                NSString *path=[payload stringByAppendingPathComponent:relative];
                struct stat st;
                if(lstat(path.fileSystemRepresentation,&st)) @throw zipError(@"Cannot read an archive member");
                BOOL directory=S_ISDIR(st.st_mode), link=S_ISLNK(st.st_mode);
                if(!directory && !link && !S_ISREG(st.st_mode)) @throw zipError(@"Unsupported special file in bundle");
                NSString *name=relative.length?[@"Payload/" stringByAppendingString:relative]:@"Payload";
                if(directory) name=[name stringByAppendingString:@"/"];
                NSData *nameBytes=[name dataUsingEncoding:NSUTF8StringEncoding];
                if(nameBytes.length>UINT16_MAX || entries.count>=UINT16_MAX) @throw zipError(@"ZIP entry limit exceeded");
                NSData *linkData=link?[[fm destinationOfSymbolicLinkAtPath:path error:error] dataUsingEncoding:NSUTF8StringEncoding]:nil;
                if(link && !linkData) @throw zipError(@"Cannot read symbolic link");
                uint32_t local=position(out);
                u32(out,0x04034b50);u16(out,20);u16(out,0x808);u16(out,8);u16(out,0);u16(out,0);
                u32(out,0);u32(out,0);u32(out,0);u16(out,nameBytes.length);u16(out,0);
                writeData(out,nameBytes.bytes,nameBytes.length);
                uint32_t start=position(out),crc=crc32(0,NULL,0);
                uint64_t raw=0;
                z_stream stream={0};
                if(deflateInit2(&stream,Z_DEFAULT_COMPRESSION,Z_DEFLATED,-MAX_WBITS,8,Z_DEFAULT_STRATEGY)!=Z_OK) @throw zipError(@"Cannot initialize ZIP compression");
                FILE *in=(!directory && !link)?fopen(path.fileSystemRepresentation,"rb"):NULL;
                if(!directory && !link && !in) { deflateEnd(&stream); @throw zipError(@"Cannot open archive source"); }
                @try {
                    uint8_t input[65536],compressed[65536];
                    BOOL last=NO,linkSent=NO;
                    while(!last) {
                        if(cancelled && cancelled()) @throw zipError(@"Cancelled; partial archive retained");
                        size_t got;
                        if(directory) got=0;
                        else if(link) { got=linkSent?0:linkData.length; if(got>sizeof(input)) @throw zipError(@"Symbolic link is too long"); if(got)memcpy(input,linkData.bytes,got);linkSent=YES; }
                        else { got=fread(input,1,sizeof(input),in);if(ferror(in))@throw zipError(@"Archive source read failed"); }
                        last=got==0;raw+=got;
                        if(raw>=UINT32_MAX) @throw zipError(@"ZIP64 member is not supported");
                        crc=crc32(crc,input,(uInt)got);stream.next_in=input;stream.avail_in=(uInt)got;
                        int result;
                        do {
                            stream.next_out=compressed;stream.avail_out=sizeof(compressed);
                            result=deflate(&stream,last?Z_FINISH:Z_NO_FLUSH);
                            if(result!=Z_OK && result!=Z_STREAM_END) @throw zipError(@"ZIP compression failed");
                            writeData(out,compressed,sizeof(compressed)-stream.avail_out);
                        } while(stream.avail_out==0 || (last && result!=Z_STREAM_END));
                    }
                } @finally { if(in)fclose(in);deflateEnd(&stream); }
                uint32_t packed=position(out)-start;
                u32(out,0x08074b50);u32(out,crc);u32(out,packed);u32(out,(uint32_t)raw);
                [entries addObject:@{ @"name":nameBytes,@"local":@(local),@"crc":@(crc),@"packed":@(packed),@"raw":@(raw),@"mode":@(st.st_mode)}];
            }
        }
        uint32_t central=position(out);
        for(NSDictionary *e in entries) {
            NSData *name=e[@"name"];
            u32(out,0x02014b50);u16(out,0x0314);u16(out,20);u16(out,0x808);u16(out,8);u16(out,0);u16(out,0);
            u32(out,[e[@"crc"] unsignedIntValue]);u32(out,[e[@"packed"] unsignedIntValue]);u32(out,[e[@"raw"] unsignedIntValue]);
            u16(out,name.length);u16(out,0);u16(out,0);u16(out,0);u16(out,0);u32(out,[e[@"mode"] unsignedIntValue]<<16);u32(out,[e[@"local"] unsignedIntValue]);
            writeData(out,name.bytes,name.length);
        }
        uint32_t size=position(out)-central;
        u32(out,0x06054b50);u16(out,0);u16(out,0);u16(out,entries.count);u16(out,entries.count);u32(out,size);u32(out,central);u16(out,0);
        if(fflush(out) || fsync(fileno(out))) @throw zipError(@"Cannot flush archive");
        fclose(out);out=NULL;
        return YES;
    } @catch(NSError *failure) { if(out)fclose(out);if(error)*error=failure;return NO; }
}
BOOL HakuVerifyArchive(NSString *path, NSError **error) {
    return HakuVerifyArchiveWithCancellation(path,nil,error);
}
BOOL HakuVerifyArchiveWithCancellation(NSString *path, BOOL (^cancelled)(void), NSError **error) {
    FILE *f=fopen(path.fileSystemRepresentation,"rb");
    @try {
        if(!f) @throw zipError(@"Cannot open archive for verification");
        if(fseeko(f,0,SEEK_END)) @throw zipError(@"Cannot seek archive");
        off_t length=ftello(f);
        if(length<22) @throw zipError(@"Truncated ZIP end record");
        uint8_t end[22];readAt(f,length-22,end,22);
        uint32_t central=r32(end+16),size=r32(end+12);
        unsigned count=r16(end+10);
        if(r32(end)!=0x06054b50 || r16(end+4) || r16(end+6) || r16(end+8)!=count || r16(end+20) || (uint64_t)central+size!=(uint64_t)length-22)
            @throw zipError(@"Invalid ZIP directory");
        NSMutableSet *names=[NSMutableSet set];
        uint64_t next=central,localEnd=0;
        for(unsigned i=0;i<count;i++) {
            if(cancelled && cancelled()) @throw zipError(@"Cancelled; archive retained");
            uint8_t c[46],local[30];readAt(f,next,c,46);
            unsigned nameLength=r16(c+28),extra=r16(c+30),comment=r16(c+32);
            uint32_t packed=r32(c+20),raw=r32(c+24),offset=r32(c+42);
            if(r32(c)!=0x02014b50 || r16(c+8)!=0x808 || r16(c+10)!=8 || !nameLength || offset!=localEnd || (uint64_t)offset+30+nameLength+packed+16>central || next+46+nameLength+extra+comment>(uint64_t)central+size)
                @throw zipError(@"Invalid ZIP member bounds");
            NSMutableData *nameBytes=[NSMutableData dataWithLength:nameLength];readAt(f,next+46,nameBytes.mutableBytes,nameLength);
            NSString *name=[[NSString alloc] initWithData:nameBytes encoding:NSUTF8StringEncoding];
            if(!name || [names containsObject:name] || ![name hasPrefix:@"Payload/"] || [name.pathComponents containsObject:@".."])
                @throw zipError(@"Invalid or duplicate ZIP member name");
            [names addObject:name];
            readAt(f,offset,local,30);
            if(r32(local)!=0x04034b50 || r16(local+6)!=0x808 || r16(local+8)!=8 || r16(local+26)!=nameLength || r16(local+28))
                @throw zipError(@"ZIP local header mismatch");
            NSMutableData *localName=[NSMutableData dataWithLength:nameLength];readAt(f,offset+30,localName.mutableBytes,nameLength);
            if(![localName isEqualToData:nameBytes]) @throw zipError(@"ZIP local member name mismatch");
            z_stream stream={0};
            if(inflateInit2(&stream,-MAX_WBITS)!=Z_OK) @throw zipError(@"Cannot initialize ZIP verification");
            uint64_t consumed=0,produced=0;uint32_t crc=crc32(0,NULL,0);int result=Z_OK;
            @try {
                uint8_t input[65536],output[65536];
                while(consumed<packed) {
                    if(cancelled && cancelled()) @throw zipError(@"Cancelled; archive retained");
                    size_t n=(size_t)MIN(sizeof(input),packed-consumed);
                    readAt(f,(uint64_t)offset+30+nameLength+consumed,input,n);consumed+=n;
                    stream.next_in=input;stream.avail_in=(uInt)n;
                    do {
                        stream.next_out=output;stream.avail_out=sizeof(output);
                        result=inflate(&stream,Z_NO_FLUSH);
                        if(result!=Z_OK && result!=Z_STREAM_END) @throw zipError(@"ZIP member decompression failed");
                        size_t nout=sizeof(output)-stream.avail_out;produced+=nout;
                        if(produced>raw) @throw zipError(@"ZIP expanded size mismatch");
                        crc=crc32(crc,output,(uInt)nout);
                        if(result==Z_STREAM_END) break;
                    } while(stream.avail_in || stream.avail_out==0);
                    if(result==Z_STREAM_END && (consumed!=packed || stream.avail_in)) @throw zipError(@"Trailing ZIP compressed bytes");
                }
            } @finally { inflateEnd(&stream); }
            if(result!=Z_STREAM_END || produced!=raw || crc!=r32(c+16)) @throw zipError(@"ZIP member CRC/size mismatch");
            uint8_t descriptor[16];readAt(f,(uint64_t)offset+30+nameLength+packed,descriptor,16);
            if(r32(descriptor)!=0x08074b50 || r32(descriptor+4)!=crc || r32(descriptor+8)!=packed || r32(descriptor+12)!=raw) @throw zipError(@"ZIP data descriptor mismatch");
            localEnd=(uint64_t)offset+30+nameLength+packed+16;
            next+=46+nameLength+extra+comment;
        }
        if(!count || next!=(uint64_t)central+size || localEnd!=central) @throw zipError(@"ZIP inventory mismatch");
        fclose(f);return YES;
    } @catch(NSError *failure) { if(f)fclose(f);if(error)*error=failure;return NO; }
}
