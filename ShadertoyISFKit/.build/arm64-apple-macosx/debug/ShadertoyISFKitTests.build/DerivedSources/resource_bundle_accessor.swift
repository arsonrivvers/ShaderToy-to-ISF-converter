import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("ShadertoyISFKit_ShadertoyISFKitTests.bundle").path
        let buildPath = "/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/ShadertoyISFKit/.build/arm64-apple-macosx/debug/ShadertoyISFKit_ShadertoyISFKitTests.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}