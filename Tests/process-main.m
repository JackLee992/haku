#import "HakuProcess.h"
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;
        NSString *mode=@(argv[1]);NSError *error=nil;
        if([mode isEqual:@"self"])return HakuEnsureProcessStopped(getpid(),&error)?1:0;
        if([mode isEqual:@"invalid"])return HakuEnsureProcessStopped(0,&error) || HakuEnsureProcessStopped(-1,&error)?1:0;
        BOOL alreadyExited=[mode isEqual:@"already-exited"];
        int ready[2];if(pipe(ready))return 2;
        pid_t child=fork();if(child<0)return 2;
        if(!child) {
            close(ready[0]);signal(SIGTERM,SIG_IGN);write(ready[1],"x",1);close(ready[1]);
            if(alreadyExited)_exit(0);
            for(;;)pause();
        }
        close(ready[1]);char byte;read(ready[0],&byte,1);close(ready[0]);
        if([mode isEqual:@"already-exited"])waitpid(child,NULL,0);
        BOOL stopped=HakuEnsureProcessStopped(child,&error);
        BOOL gone=kill(child,0)<0;
        if(!gone) {kill(child,SIGKILL);waitpid(child,NULL,0);}
        if(!stopped)fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);
        return stopped && gone?0:1;
    }
}
