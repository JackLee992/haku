#import <Foundation/Foundation.h>
#include <sys/types.h>

// Called only for the explicitly selected app or the process spawned by this run.
BOOL HakuEnsureProcessStopped(pid_t pid, NSError **error);
