#import "HakuEngine.h"
#import "HakuArchive.h"
#import "HakuMachO.h"
#include "frida-core.h"
#include <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/utsname.h>

static NSError *HakuError(NSString *message) {
    return [NSError errorWithDomain:@"Haku" code:1 userInfo:@{NSLocalizedDescriptionKey:message ?: @"Capture failed"}];
}
static NSString *sha256(NSData *data) {
    CC_SHA256_CTX context;CC_SHA256_Init(&context);
    const uint8_t *bytes=data.bytes;NSUInteger at=0;
    while(at<data.length) { CC_LONG count=(CC_LONG)MIN(1024*1024,data.length-at);CC_SHA256_Update(&context,bytes+at,count);at+=count; }
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(digest,&context);
    NSMutableString *result=[NSMutableString string];for(unsigned i=0;i<sizeof(digest);i++)[result appendFormat:@"%02x",digest[i]];
    return result;
}
static NSData *mapped(NSString *path) {
    NSError *error=nil;NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:&error];
    if(!data) @throw (error ?: HakuError(@"Cannot read binary"));return data;
}
static NSString *canonical(NSString *path) { return path.stringByResolvingSymlinksInPath.stringByStandardizingPath; }
static BOOL under(NSString *path,NSString *root) { return [canonical(path) hasPrefix:[canonical(root) stringByAppendingString:@"/"]]; }
static NSString *uuidFor(const HakuSlice *slice) { char text[33];haku_uuid_string(slice->uuid,text);return @(text); }

@interface HakuEngine () {
    FridaDeviceManager *_manager;
    FridaDevice *_device;
    FridaSession *_session;
    FridaScript *_script;
    GCancellable *_cancellable;
    guint _pid;
    BOOL _cleaning,_complete;
    atomic_bool _cancelled;
    NSDictionary *_inventory;
    NSString *_failure,*_directory,*_stage;
    NSMutableArray *_records,*_files,*_requests;
    NSMutableDictionary *_report;
    uint64_t _bytesReceived,_lastProgress;
    gint64 _lastActivity;
}
- (void)message:(const gchar *)message data:(GBytes *)data;
- (void)detached;
@end
static void onMessage(FridaScript *script,const gchar *message,GBytes *data,gpointer context) {
    @autoreleasepool { [(__bridge HakuEngine *)context message:message data:data]; }
}
static void onDetached(FridaSession *session,FridaSessionDetachReason reason,FridaCrash *crash,gpointer context) {
    [(__bridge HakuEngine *)context detached];
}
@implementation HakuEngine
- (instancetype)init { if((self=[super init])) { atomic_init(&_cancelled,false);static dispatch_once_t once;dispatch_once(&once,^{frida_init();}); }return self; }
- (void)emit:(NSString *)message { if(self.progress)self.progress(message); }
- (void)cancel { atomic_store(&_cancelled,true);@synchronized(self) { if(_cancellable)g_cancellable_cancel(_cancellable); } }
- (void)check {
    if(atomic_load(&_cancelled)) @throw HakuError(@"Cancelled; partial evidence has been retained");
    if(_failure) @throw HakuError(_failure);
}
- (void)checkGError:(GError *)error {
    if(error) { NSString *message=@(error->message);g_error_free(error);@throw HakuError(message); }
    [self check];
}
- (void)connect {
    _failure=nil;_cleaning=NO;_complete=NO;_inventory=nil;_pid=0;[self check];
    @synchronized(self) { _cancellable=g_cancellable_new(); }
    GError *error=NULL;_manager=frida_device_manager_new();
    _device=frida_device_manager_add_remote_device_sync(_manager,"127.0.0.1:27042",NULL,_cancellable,&error);
    [self checkGError:error];
    if(!_device) @throw HakuError(@"Frida is unavailable. Install Frida 17.24.3 and activate the jailbreak.");
}
- (NSArray<NSDictionary *> *)readApplications {
    GError *error=NULL;FridaApplicationQueryOptions *options=frida_application_query_options_new();
    frida_application_query_options_set_scope(options,FRIDA_SCOPE_FULL);
    FridaApplicationList *list=frida_device_enumerate_applications_sync(_device,options,_cancellable,&error);
    g_object_unref(options);[self checkGError:error];
    NSMutableArray *apps=[NSMutableArray array];
    if(list) {
        for(gint i=0;i<frida_application_list_size(list);i++) {
            FridaApplication *app=frida_application_list_get(list,i);
            NSString *identifier=@(frida_application_get_identifier(app));
            if(![identifier hasPrefix:@"com.apple."] && ![identifier isEqualToString:@"com.jacklee.haku"]) {
                GHashTable *parameters=frida_application_get_parameters(app);
                GVariant *path=g_hash_table_lookup(parameters,"path");
                NSString *installedPath=path && g_variant_is_of_type(path,G_VARIANT_TYPE_STRING)?canonical(@(g_variant_get_string(path,NULL))):@"";
                if(![installedPath hasPrefix:@"/private/var/containers/Bundle/Application/"] && ![installedPath hasPrefix:@"/var/containers/Bundle/Application/"]) { g_object_unref(app);continue; }
                GVariant *version=g_hash_table_lookup(parameters,"version");
                NSString *v=version && g_variant_is_of_type(version,G_VARIANT_TYPE_STRING)?@(g_variant_get_string(version,NULL)):@"";
                [apps addObject:@{@"bundle":identifier,@"name":@(frida_application_get_name(app)),@"version":v,@"pid":@(frida_application_get_pid(app))}];
            }
            g_object_unref(app);
        }
        g_object_unref(list);
    }
    return [apps sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
}
- (void)cleanup {
    _cleaning=YES;
    for(NSMutableDictionary *r in _requests) { int fd=[r[@"fd"] intValue];if(fd>=0) { close(fd);r[@"fd"]=@(-1); } }
    if(_pid && _device) { GError *error=NULL;frida_device_kill_sync(_device,_pid,NULL,&error);if(error)g_error_free(error);_pid=0; }
    if(_script) { g_signal_handlers_disconnect_by_data(_script,(__bridge void *)self);g_object_unref(_script);_script=NULL; }
    if(_session) { g_signal_handlers_disconnect_by_data(_session,(__bridge void *)self);frida_session_detach_sync(_session,NULL,NULL);g_object_unref(_session);_session=NULL; }
    if(_device) { g_object_unref(_device);_device=NULL; }
    if(_manager) { frida_device_manager_close_sync(_manager,NULL,NULL);g_object_unref(_manager);_manager=NULL; }
    @synchronized(self) { if(_cancellable) { g_object_unref(_cancellable);_cancellable=NULL; } }
}
- (NSArray<NSDictionary *> *)applications:(NSError **)error {
    NSArray *result=nil;@try { [self connect];result=[self readApplications]; }
    @catch(NSError *failure) { if(error)*error=failure; }
    @finally { [self cleanup]; }return result;
}
- (void)post:(NSDictionary *)value {
    NSError *error=nil;NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
    if(!data) @throw error;
    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];frida_script_post(_script,text.UTF8String,NULL);
}
- (void)waitForInventory:(BOOL)inventory {
    _lastActivity=g_get_monotonic_time();
    while(inventory?!_inventory:!_complete) {
        [self check];
        while(g_main_context_iteration(NULL,FALSE)) { [self check]; }
        if(g_get_monotonic_time()-_lastActivity>60*G_USEC_PER_SEC) @throw HakuError(@"No capture progress for 60 seconds");
        g_usleep(5000);
    }
    [self check];
}
- (void)detached { if(!_cleaning && !_complete)_failure=@"The selected capture process exited before capture finished"; }
- (void)message:(const gchar *)text data:(GBytes *)data {
    @try {
        NSDictionary *message=[NSJSONSerialization JSONObjectWithData:[@(text) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if([message[@"type"] isEqual:@"error"]) @throw HakuError(message[@"description"] ?: @"Frida agent failed");
        if(![message[@"type"] isEqual:@"send"]) return;
        NSDictionary *payload=message[@"payload"];NSString *kind=payload[@"kind"];
        _lastActivity=g_get_monotonic_time();
        if([kind isEqual:@"inventory"]) { if(_inventory)@throw HakuError(@"Duplicate capture inventory");_inventory=payload; }
        else if([kind isEqual:@"failure"]) @throw HakuError(payload[@"error"]);
        else if([kind isEqual:@"chunk"]) {
            NSUInteger index=[payload[@"id"] unsignedIntegerValue];
            if(index>=_requests.count || !data) @throw HakuError(@"Unknown capture request");
            NSMutableDictionary *request=_requests[index];gsize length=0;const void *bytes=g_bytes_get_data(data,&length);
            uint64_t at=[request[@"received"] unsignedLongLongValue],total=[request[@"size"] unsignedLongLongValue];
            if([payload[@"offset"] unsignedLongLongValue]!=at || !length || length>256*1024 || length!=[payload[@"size"] unsignedLongLongValue] || at>total || length>total-at)
                @throw HakuError(@"Missing, duplicate, or oversized capture chunk");
            size_t done=0;
            while(done<length) {
                ssize_t n=pwrite([request[@"fd"] intValue],(const uint8_t *)bytes+done,length-done,(off_t)([request[@"absolute"] unsignedLongLongValue]+at+done));
                if(n<0 && errno==EINTR)continue;if(n<=0)@throw HakuError(@"Capture write failed; check storage");done+=(size_t)n;
            }
            request[@"received"]=@(at+length);_bytesReceived+=length;
            if(_bytesReceived-_lastProgress>=4*1024*1024 || at+length==total) {
                [self emit:[NSString stringWithFormat:@"Captured %.1f MiB · %@",_bytesReceived/1048576.0,request[@"relative"]]];_lastProgress=_bytesReceived;
            }
            [self post:@{@"type":@"ack",@"payload":@{@"id":@(index),@"offset":@(at)}}];
        } else if([kind isEqual:@"complete"]) _complete=YES;
        else @throw HakuError(@"Unknown capture-agent event");
    } @catch(NSError *error) { _failure=error.localizedDescription; }
}
- (void)saveReport {
    if(!_report || !_directory)return;
    _report[@"images"]=_records ?: @[];
    NSData *data=[NSJSONSerialization dataWithJSONObject:_report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    if(data) [data writeToFile:[_directory stringByAppendingPathComponent:@"report.json"] options:NSDataWritingAtomic error:nil];
}
- (NSDictionary *)captureBundle:(NSString *)bundle output:(NSString *)directory keepAlive:(BOOL)keepAlive error:(NSError **)error {
    NSDictionary *result=nil;_directory=nil;_report=nil;_records=[NSMutableArray array];_files=[NSMutableArray array];_requests=[NSMutableArray array];_bytesReceived=0;_lastProgress=0;
    @try {
        NSFileManager *fm=NSFileManager.defaultManager;
        if(!bundle.length || [bundle hasPrefix:@"com.apple."] || [bundle isEqual:@"com.jacklee.haku"]) @throw HakuError(@"Choose an installed user application");
        if(!directory.isAbsolutePath || [fm fileExistsAtPath:directory]) @throw HakuError(@"Export folder must be a new absolute path");
        NSError *io=nil;
        if(![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&io]) @throw io;
        _directory=directory;_stage=[directory stringByAppendingPathComponent:@"Work"];
        struct utsname machine;uname(&machine);
        _report=[@{@"schema":@"haku-capture-v1",@"haku_version":@"0.1.0",@"frida_version":@(frida_version_string()),@"bundle":bundle,@"run_id":NSUUID.UUID.UUIDString,@"started_at":[NSISO8601DateFormatter.new stringFromDate:NSDate.date],@"device_model":@(machine.machine),@"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"keep_alive":@(keepAlive),@"main_verified":@NO,@"fully_verified":@NO,@"zip_verified":@NO,@"signed":@NO,@"installed":@NO,@"ordinary_launch_tested":@NO,@"functional_tested":@NO} mutableCopy];
        _report[@"source_sha256"]=[NSBundle.mainBundle objectForInfoDictionaryKey:@"HakuSourceSHA256"] ?: @"unknown";
        _report[@"source_revision"]=[NSBundle.mainBundle objectForInfoDictionaryKey:@"HakuSourceRevision"] ?: @"unknown";
        _report[@"status"]=@"capturing";[self saveReport];
        [self emit:@"Connecting to Frida on this phone…"];[self connect];
        NSDictionary *selected=nil;for(NSDictionary *app in [self readApplications])if([app[@"bundle"] isEqual:bundle])selected=app;
        if(!selected)@throw HakuError(@"The selected application is no longer installed");
        if([selected[@"pid"] unsignedIntValue]) {
            [self emit:@"Restarting the selected application for capture…"];GError *e=NULL;
            frida_device_kill_sync(_device,[selected[@"pid"] unsignedIntValue],_cancellable,&e);[self checkGError:e];
        }
        GError *e=NULL;_pid=frida_device_spawn_sync(_device,bundle.UTF8String,NULL,_cancellable,&e);[self checkGError:e];
        _session=frida_device_attach_sync(_device,_pid,NULL,_cancellable,&e);[self checkGError:e];
        g_signal_connect(_session,"detached",G_CALLBACK(onDetached),(__bridge void *)self);
        NSString *agent=[NSString stringWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"capture.js"] encoding:NSUTF8StringEncoding error:&io];
        if(!agent)@throw (io ?: HakuError(@"Capture agent is missing"));
        agent=[agent stringByReplacingOccurrencesOfString:@"__HAKU_KEEP_ALIVE__" withString:keepAlive?@"true":@"false"];
        FridaScriptOptions *options=frida_script_options_new();frida_script_options_set_runtime(options,FRIDA_SCRIPT_RUNTIME_QJS);frida_script_options_set_name(options,"haku-capture");
        _script=frida_session_create_script_sync(_session,agent.UTF8String,options,_cancellable,&e);g_object_unref(options);[self checkGError:e];
        g_signal_connect(_script,"message",G_CALLBACK(onMessage),(__bridge void *)self);
        frida_script_load_sync(_script,_cancellable,&e);[self checkGError:e];[self waitForInventory:YES];
        NSString *app=canonical(_inventory[@"appPath"]);
        if(![app hasPrefix:@"/private/var/containers/Bundle/Application/"] && ![app hasPrefix:@"/var/containers/Bundle/Application/"]) @throw HakuError(@"Capture source is not an installed user bundle");
        NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Info.plist"]];
        NSString *executable=info[@"CFBundleExecutable"];
        if(![info[@"CFBundleIdentifier"] isEqual:bundle] || !executable.length || ![executable.lastPathComponent isEqual:executable]) @throw HakuError(@"Selected application identity does not match the runtime bundle");
        NSString *main=canonical([app stringByAppendingPathComponent:executable]);
        if(![main isEqual:canonical(_inventory[@"mainPath"])])@throw HakuError(@"Main executable path does not match");
        _report[@"version"]=info[@"CFBundleShortVersionString"] ?: @"";_report[@"build"]=info[@"CFBundleVersion"] ?: @"";
        uint64_t bundleSize=0;NSArray *members=[fm subpathsOfDirectoryAtPath:app error:&io];if(!members)@throw io;
        for(NSString *relative in members) { struct stat st;if(!lstat([app stringByAppendingPathComponent:relative].fileSystemRepresentation,&st) && S_ISREG(st.st_mode))bundleSize+=st.st_size; }
        struct statfs fs;if(!statfs(directory.fileSystemRepresentation,&fs) && (uint64_t)fs.f_bavail*fs.f_bsize<bundleSize*2+64*1024*1024) @throw HakuError(@"Not enough free storage for the bundle copy and IPA");
        NSString *payload=[_stage stringByAppendingPathComponent:@"Payload"],*destination=[payload stringByAppendingPathComponent:app.lastPathComponent];
        [self emit:@"Copying the application bundle into a private export folder…"];
        if(![fm createDirectoryAtPath:payload withIntermediateDirectories:YES attributes:nil error:&io] || ![fm copyItemAtPath:app toPath:destination error:&io])@throw io;
        for(NSString *relative in members) {
            @autoreleasepool {
                [self check];NSString *source=[app stringByAppendingPathComponent:relative];struct stat st;
                if(lstat(source.fileSystemRepresentation,&st) || !S_ISREG(st.st_mode) || st.st_size<4)continue;
                uint32_t magic=0;int probe=open(source.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);if(probe<0)@throw HakuError(@"Cannot inspect bundle file");ssize_t got=read(probe,&magic,4);close(probe);if(got!=4)@throw HakuError(@"Truncated bundle member");
                if(magic!=0xfeedfacf && magic!=0xfeedface && magic!=0xbebafeca && magic!=0xbfbafeca)continue;
                NSMutableDictionary *record=[@{@"path":relative,@"status":@"pending"} mutableCopy];[_records addObject:record];
                NSData *original=mapped(source);record[@"original_sha256"]=sha256(original);
                HakuMachO macho;char why[256];
                if(!haku_parse_macho(original.bytes,original.length,&macho,why,sizeof(why))) {record[@"status"]=@"unsupported";record[@"reason"]=@(why);if([source isEqual:main])@throw HakuError(@(why));continue;}
                NSDictionary *runtime=nil;for(NSDictionary *image in _inventory[@"images"])if([canonical(image[@"path"]) isEqual:canonical(source)])runtime=image;
                NSMutableArray *ranges=[NSMutableArray array];BOOL encrypted=NO,canCapture=YES;
                for(unsigned i=0;i<macho.count;i++) {
                    HakuSlice *slice=&macho.slices[i];NSString *uuid=uuidFor(slice);
                    for(unsigned j=0;j<slice->range_count;j++) {
                        HakuCryptRange *range=&slice->ranges[j];if(!range->cryptid || !range->size)continue;encrypted=YES;
                        if(!slice->has_uuid || ![runtime[@"uuid"] isEqual:uuid] || [runtime[@"cpuType"] unsignedIntValue]!=slice->cpu_type || [runtime[@"cpuSubtype"] unsignedIntValue]!=slice->cpu_subtype)canCapture=NO;
                        [ranges addObject:@{@"uuid":uuid,@"offset":@(range->offset),@"size":@(range->size),@"absolute":@(slice->offset+range->offset),@"cryptid_offset":@(slice->offset+range->cryptid_offset),@"original_range_sha256":sha256([NSData dataWithBytesNoCopy:(uint8_t *)original.bytes+slice->offset+range->offset length:(NSUInteger)range->size freeWhenDone:NO])}];
                    }
                }
                record[@"ranges"]=ranges;
                if(!encrypted) { record[@"status"]=@"already_clear";record[@"derived_sha256"]=record[@"original_sha256"]; }
                else if(!canCapture) { record[@"status"]=runtime?@"unsupported_slice":@"not_loaded"; }
                NSString *dest=[destination stringByAppendingPathComponent:relative];
                if(!under(dest,destination))@throw HakuError(@"Unsafe copied binary path");
                NSMutableDictionary *file=[@{@"source":source,@"destination":dest,@"record":record,@"main":@([source isEqual:main])} mutableCopy];[_files addObject:file];
                if(encrypted && canCapture) {
                    for(NSDictionary *range in ranges) {
                        int fd=open(dest.fileSystemRepresentation,O_RDWR|O_NOFOLLOW);if(fd<0)@throw HakuError(@"Cannot patch copied binary");
                        NSNumber *index=@(_requests.count);
                        NSDictionary *wire=@{@"id":index,@"path":runtime[@"path"],@"uuid":range[@"uuid"],@"offset":range[@"offset"],@"size":range[@"size"]};
                        [_requests addObject:[@{@"wire":wire,@"relative":relative,@"absolute":range[@"absolute"],@"cryptid_offset":range[@"cryptid_offset"],@"size":range[@"size"],@"received":@0,@"fd":@(fd)} mutableCopy]];
                    }
                }
            }
        }
        [self emit:@"Capturing loaded encrypted ranges while the target stays suspended…"];
        [self post:@{@"type":@"capture",@"payload":@{@"requests":[_requests valueForKey:@"wire"],@"keepAlive":@(keepAlive)}}];[self waitForInventory:NO];
        for(NSMutableDictionary *request in _requests) {
            if(![request[@"received"] isEqual:request[@"size"]])@throw HakuError(@"Capture completed with missing bytes");
            int fd=[request[@"fd"] intValue];uint32_t zero=0;
            if(pwrite(fd,&zero,4,[request[@"cryptid_offset"] longLongValue])!=4 || fsync(fd))@throw HakuError(@"Cannot finalize copied Mach-O");
            close(fd);request[@"fd"]=@(-1);
        }
        // End only the process created by this run, before ZIP compression.
        frida_device_kill_sync(_device,_pid,NULL,&e);if(e) {g_error_free(e);e=NULL;} _pid=0;
        BOOL mainPassed=NO,full=YES,mainWasEncrypted=NO;
        for(NSDictionary *file in _files) {
            @autoreleasepool {
                [self check];NSMutableDictionary *record=file[@"record"];
                if([record[@"status"] isEqual:@"pending"] || [record[@"status"] isEqual:@"already_clear"]) {
                    NSData *a=mapped(file[@"source"]),*b=mapped(file[@"destination"]);char why[256];
                    snprintf(why,sizeof(why),"Original binary changed during capture");
                    if(a.length!=b.length || ![sha256(a) isEqual:record[@"original_sha256"]] || !haku_validate_transition(a.bytes,b.bytes,a.length,why,sizeof(why))) {
                        record[@"status"]=@"validation_failed";record[@"reason"]=a.length==b.length?@(why):@"File size changed";
                    } else {
                        record[@"derived_sha256"]=sha256(b);
                        if([record[@"status"] isEqual:@"pending"]) record[@"status"]=@"verified";
                        NSMutableArray *updated=[NSMutableArray array];
                        for(NSDictionary *range in record[@"ranges"]) { NSMutableDictionary *r=range.mutableCopy;r[@"derived_range_sha256"]=sha256([NSData dataWithBytesNoCopy:(uint8_t *)b.bytes+[range[@"absolute"] unsignedLongLongValue] length:[range[@"size"] unsignedIntegerValue] freeWhenDone:NO]);[r removeObjectForKey:@"absolute"];[r removeObjectForKey:@"cryptid_offset"];[updated addObject:r]; }
                        record[@"ranges"]=updated;
                    }
                }
                BOOL verified=[record[@"status"] isEqual:@"verified"] || [record[@"status"] isEqual:@"already_clear"];
                if(!verified)full=NO;
                if([file[@"main"] boolValue]) {mainPassed=verified;mainWasEncrypted=[record[@"status"] isEqual:@"verified"];}
                [self emit:[NSString stringWithFormat:@"%@ · %@",record[@"status"],record[@"path"]]];
            }
        }
        for(NSDictionary *record in _records)if([record[@"status"] isEqual:@"unsupported"])full=NO;
        _report[@"main_verified"]=@(mainPassed);_report[@"main_decrypted"]=@(mainWasEncrypted);_report[@"fully_verified"]=(full && mainPassed)?@YES:@NO;_report[@"captured_bytes"]=@(_bytesReceived);
        if(!mainPassed)@throw HakuError(@"Main executable did not pass validation; no IPA was exported");
        _report[@"status"]=@"packaging";[self saveReport];
        [self emit:@"Compressing and checking the IPA…"];
        NSString *temporary=[directory stringByAppendingPathComponent:@"export.ipa.partial"],*ipa=[directory stringByAppendingPathComponent:@"export.ipa"];
        BOOL (^cancelled)(void)=^BOOL { return atomic_load(&self->_cancelled); };
        if(!HakuCreateArchiveWithCancellation(payload,temporary,cancelled,&io) || !HakuVerifyArchiveWithCancellation(temporary,cancelled,&io))@throw io;
        if(![fm moveItemAtPath:temporary toPath:ipa error:&io])@throw io;
        _report[@"zip_verified"]=@YES;_report[@"ipa"]=@"export.ipa";_report[@"ipa_sha256"]=sha256(mapped(ipa));_report[@"status"]=full?@"verified":@"partial";
        _report[@"completed_at"]=[NSISO8601DateFormatter.new stringFromDate:NSDate.date];[self saveReport];
        [fm removeItemAtPath:_stage error:nil];result=_report.copy;
        [self emit:full?@"Export verified. IPA and report are ready.":@"Main verified. Some native images remain incomplete; see the report."];
    } @catch(NSError *failure) {
        _report[@"status"]=atomic_load(&_cancelled)?@"cancelled":@"failed";_report[@"error"]=failure.localizedDescription;[self saveReport];if(error)*error=failure;
    } @finally { [self cleanup]; }
    return result;
}
@end
