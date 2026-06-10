#include "CrashWriter.h"
#include <fcntl.h>
#include <unistd.h>
#include <execinfo.h>
#include <time.h>
#include <stdio.h>
#include <signal.h>
#include <stddef.h>

void tisf_write_signal_record(const char *path, int sig) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    const char *name;
    switch (sig) {
        case SIGSEGV: name = "SIGSEGV"; break;
        case SIGABRT: name = "SIGABRT"; break;
        case SIGBUS:  name = "SIGBUS";  break;
        case SIGILL:  name = "SIGILL";  break;
        case SIGFPE:  name = "SIGFPE";  break;
        case SIGTRAP: name = "SIGTRAP"; break;
        default:      name = "SIGNAL";  break;
    }
    char hdr[128];
    int len = snprintf(hdr, sizeof(hdr), "SIGNAL %s %ld\n", name, (long)time(NULL));
    if (len > 0) write(fd, hdr, (size_t)len);
    void *frames[64];
    int n = backtrace(frames, 64);
    backtrace_symbols_fd(frames, n, fd);
    close(fd);
}
