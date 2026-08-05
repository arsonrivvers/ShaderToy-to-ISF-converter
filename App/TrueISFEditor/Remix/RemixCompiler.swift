import Foundation
import Metal

struct RemixCompileResult: Sendable, Equatable {
    let isValid: Bool
    let diagnostic: String?
    let errorLine: Int?
}

@MainActor
protocol RemixCompiling {
    func compile(_ source: String) async -> RemixCompileResult
}

@MainActor
final class NativeRemixCompiler: RemixCompiling {
    typealias LoaderOperation = @Sendable (String) -> RemixCompileResult

    private let compileQueue: DispatchQueue
    private let loaderOperation: LoaderOperation

    init() {
        let device = MTLCreateSystemDefaultDevice()
        self.compileQueue = Self.makeCompileQueue()
        self.loaderOperation = Self.nativeLoader(device: device)
    }

    /// Deterministic no-device seam; production uses `init()` so Metal discovery happens once.
    init(device: MTLDevice?) {
        self.compileQueue = Self.makeCompileQueue()
        self.loaderOperation = Self.nativeLoader(device: device)
    }

    /// Keeps queue orchestration real while tests replace only the blocking loader operation.
    init(loaderOperation: @escaping LoaderOperation) {
        self.compileQueue = Self.makeCompileQueue()
        self.loaderOperation = loaderOperation
    }

    func compile(_ source: String) async -> RemixCompileResult {
        let compileQueue = self.compileQueue
        let loaderOperation = self.loaderOperation
        return await withCheckedContinuation { continuation in
            compileQueue.async {
                continuation.resume(returning: loaderOperation(source))
            }
        }
    }

    private static func makeCompileQueue() -> DispatchQueue {
        DispatchQueue(label: "remix.native-compiler", qos: .userInitiated)
    }

    private static func nativeLoader(device: MTLDevice?) -> LoaderOperation {
        { source in
            guard let device else {
                return RemixCompileResult(
                    isValid: false,
                    diagnostic: "No Metal device is available.",
                    errorLine: nil
                )
            }

            let result = ISFSceneLoader.load(source: source, device: device)
            return RemixCompileResult(
                isValid: result.isValid,
                diagnostic: result.errorMessage,
                errorLine: result.errorLine
            )
        }
    }
}
