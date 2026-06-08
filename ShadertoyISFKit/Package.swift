// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShadertoyISFKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShadertoyISFKit", targets: ["ShadertoyISFKit"])
    ],
    targets: [
        .target(name: "ShadertoyISFKit"),
        .testTarget(
            name: "ShadertoyISFKitTests",
            dependencies: ["ShadertoyISFKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
