// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PivotCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "PivotCore", targets: ["PivotCore"])],
    targets: [
        .target(name: "PivotCore", path: "Core"),
        .testTarget(name: "PivotCoreTests", dependencies: ["PivotCore"], path: "Tests/PivotCoreTests")
    ]
)
