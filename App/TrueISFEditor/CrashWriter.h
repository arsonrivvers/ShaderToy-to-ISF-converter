#ifndef CrashWriter_h
#define CrashWriter_h

/// Async-signal-safe: writes "SIGNAL <name> <epoch>\n<backtrace>" to `path`. Pure C, no malloc.
/// Safe to call from a signal handler.
void tisf_write_signal_record(const char *path, int sig);

#endif /* CrashWriter_h */
