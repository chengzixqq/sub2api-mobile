// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Sub2Core",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "Sub2Core", targets: ["Sub2Core"])],
    targets: [
        .target(name: "Sub2Core"),
        .testTarget(name: "Sub2CoreTests", dependencies: ["Sub2Core"]),
        // Compile the same credential coordination used by the app; Linux tests use memoryOnly.
        .target(name: "NativeSessionSupport", dependencies: ["Sub2Core"], path: "NativeApp/Session", exclude: [
            // 阶段 0
            "AppModel.swift",
            "AppModel+Pending.swift",
            "AppModel+Security.swift",
            "AppModel+Session.swift",
            "DemoData.swift",
            // 阶段 1
            // 阶段 2
            "AppModel+Accounts.swift",
            "DemoData+Accounts.swift",
            "DemoData+AccountCredentials.swift",
            "DemoData+AccountNew.swift",
            "DemoData+AccountReauth.swift",
            "DemoData+AccountTests.swift",
            "DemoData+ScheduledTests.swift",
            // 阶段 3
            "AppModel+BalanceReconcile.swift",
            "AppModel+Users.swift",
            "DemoData+Users.swift",
            // 阶段 4
            // 阶段 5
            // 阶段 6
        ]),
        .testTarget(name: "NativeSessionTests", dependencies: ["Sub2Core", "NativeSessionSupport"])
    ],
    swiftLanguageModes: [.v6]
)
