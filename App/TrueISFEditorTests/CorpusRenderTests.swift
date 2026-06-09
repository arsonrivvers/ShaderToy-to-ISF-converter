import XCTest

/// Acceptance harness for P1.5: loads every AR_*.fs in /Library/Graphics/ISF through the native
/// MetalPreviewController and records compile/render pass/fail. Opt-in (slow, ~1057 files):
///   CORPUS=1 [CORPUS_LIMIT=N] xcodebuild test ... -only-testing:TrueISFEditorTests/CorpusRenderTests
/// WebKit/WebGL cannot load in a bare xctest process, so this measures the Metal engine only —
/// the WebKit/WebGL1 ES3-rejection baseline is already known (that's why P1.5 exists).
@MainActor
final class CorpusRenderTests: XCTestCase {
    // File-sentinel gated (env vars don't reliably reach the xctest runner process):
    //   echo ""  > /tmp/trueisf-corpus.run   # full corpus
    //   echo 20  > /tmp/trueisf-corpus.run   # first 20 files (the file's integer contents = limit)
    func testCorpusCompilePassRate() async throws {
        let sentinel = "/tmp/trueisf-corpus.run"
        guard FileManager.default.fileExists(atPath: sentinel) else {
            throw XCTSkip("Create \(sentinel) to run the corpus render-test")
        }
        let limit = (try? String(contentsOfFile: sentinel, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let dir = URL(fileURLWithPath: "/Library/Graphics/ISF")
        var files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("AR_") && $0.pathExtension == "fs" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let lim = limit { files = Array(files.prefix(lim)) }
        XCTAssertGreaterThan(files.count, 0, "no AR_*.fs found in /Library/Graphics/ISF")

        let controller = MetalPreviewController()
        var pass = 0
        var failures: [(String, String)] = []
        var i = 0
        for f in files {
            i += 1
            guard let src = try? String(contentsOf: f, encoding: .utf8) else {
                failures.append((f.lastPathComponent, "unreadable")); continue
            }
            controller.load(isf: src)  // load() resets compile state synchronously
            // Wait for GENUINE completion: the transpile queue is serial, so a too-short wait makes
            // the *next* shaders queue behind a slow one and falsely time out (cascade). 20s is the
            // safety cap for a single pathological transpile; almost all finish in well under 1s.
            let ok = await pollCompile(controller, timeout: 20)
            if ok { pass += 1 }
            else { failures.append((f.lastPathComponent, controller.compileError ?? "no-compile (timeout/unknown)")) }
            if i % 100 == 0 { print("CORPUS progress: \(i)/\(files.count) — pass \(pass), fail \(failures.count)") }
        }

        let report = """
        === CORPUS RESULT — Metal (ISFMSLKit) engine ===
        total: \(files.count)  pass: \(pass)  fail: \(failures.count)  rate: \(String(format: "%.1f", Double(pass)/Double(files.count)*100))%
        --- failures (\(failures.count)) ---
        \(failures.map { "\($0.0): \($0.1.replacingOccurrences(of: "\n", with: " ⏎ "))" }.joined(separator: "\n"))
        """
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("corpus-report.txt")
        try? report.write(to: out, atomically: true, encoding: .utf8)
        print(report)
        print("CORPUS report written: \(out.path)")

        // First run is exploratory; don't fail the build on the rate. Re-tighten after triage.
        // (Assertion intentionally lenient — the report is the deliverable.)
        XCTAssertGreaterThan(pass, 0)
    }

    private func pollCompile(_ c: MetalPreviewController, timeout: TimeInterval) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if c.compileValid { return true }
            if c.compileError != nil { return false }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }
}
