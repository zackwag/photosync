// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PhotoSync",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "SkylightClient"),
        .target(
            name: "State",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "SyncEngine", dependencies: ["State"]),
        .target(name: "Config", dependencies: ["SkylightClient"]),
        .target(name: "PhotoReader"),
        .target(name: "Notify"),
        .executableTarget(
            name: "PhotoSyncCLI",
            dependencies: [
                "SkylightClient",
                "SyncEngine",
                "State",
                "Config",
                "PhotoReader",
                "Notify",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "SkylightClientTests", dependencies: ["SkylightClient"]),
        .testTarget(name: "SyncEngineTests", dependencies: ["SyncEngine"]),
        .testTarget(name: "StateTests", dependencies: ["State"]),
        .testTarget(name: "ConfigTests", dependencies: ["Config"]),
        .testTarget(name: "PhotoReaderTests", dependencies: ["PhotoReader"]),
    ]
)
