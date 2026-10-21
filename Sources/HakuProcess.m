#import "HakuProcess.h"
#include <errno.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

BOOL HakuEnsureProcessStopped(pid_t pid, NSError **error) {
    NSString *failure=nil;
    if(pid<=0 || pid==getpid()) failure=@"The capture worker cannot terminate itself or a process group";
    else if(kill(pid,0)<0 && errno==ESRCH) return YES;
    else if(kill(pid,SIGKILL)<0 && errno!=ESRCH) failure=[NSString stringWithFormat:@"Cannot stop the selected process: %s",strerror(errno)];
    else {
        NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+3;
        do {
            // Reap a direct child in host tests; app processes normally belong to launchd.
            if(waitpid(pid,NULL,WNOHANG)==pid) return YES;
            if(kill(pid,0)<0 && errno==ESRCH) return YES;
            usleep(25000);
        } while(NSProcessInfo.processInfo.systemUptime<deadline);
        failure=@"The selected process did not exit within 3 seconds";
    }
    if(error)*error=[NSError errorWithDomain:@"HakuProcess" code:1 userInfo:@{NSLocalizedDescriptionKey:failure}];
    return NO;
}
