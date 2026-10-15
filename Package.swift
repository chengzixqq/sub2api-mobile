// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Sub2Core",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Sub2Core", targets: ["Sub2Core"])],
    targets: [
        .target(name: "Sub2Core"),
        .testTarget(name: "Sub2CoreTests", dependencies: ["Sub2Core"])
    ],
    swiftLanguageModes: [.v6]
)
