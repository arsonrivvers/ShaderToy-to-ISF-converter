import Foundation
import Darwin

/// Best-effort hard-crash capture. Signal handlers delegate to the async-signal-safe C writer
/// (`tisf_write_signal_record`); the uncaught-exception handler uses ordinary I/O (it is NOT a signal
/// context). Both leave a pending record that `CrashLog` ingests on next launch. Handlers restore the
/// default disposition and re-raise so the OS crash reporter still fires.
enum CrashReporter {
    /// strdup'd at install so the signal handler can read it without allocating.
    private static var pendingPathC: UnsafeMutablePointer<CChar>?
    private static var pendingPathSwift = ""

    static func install(pendingURL: URL) {
        let path = pendingURL.path
        pendingPathSwift = path
        pendingPathC = strdup(path)

        NSSetUncaughtExceptionHandler { exception in
            let name = exception.name.rawValue
            let reason = exception.reason ?? "no reason"
            let stack = exception.callStackSymbols.joined(separator: "\n")
            let record = "EXCEPTION \(name) \(Int(Date().timeIntervalSince1970))\n\(reason)\n\(stack)"
            try? record.write(toFile: CrashReporter.pendingPathSwift, atomically: true, encoding: .utf8)
        }

        for sig in [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig, CrashReporter.handler)
        }
    }

    // C-convention signal handler — async-signal-safe work only (delegated to C), then re-raise.
    private static let handler: @convention(c) (Int32) -> Void = { sig in
        if let p = CrashReporter.pendingPathC {
            tisf_write_signal_record(p, sig)
        }
        signal(sig, SIG_DFL)
        raise(sig)
    }
}
