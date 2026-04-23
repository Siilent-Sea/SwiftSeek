// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftSeek",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SwiftSeek", targets: ["SwiftSeek"]),
        .executable(name: "SwiftSeekIndex", targets: ["SwiftSeekIndex"]),
        .executable(name: "SwiftSeekSearch", targets: ["SwiftSeekSearch"]),
        .executable(name: "SwiftSeekSmokeTest", targets: ["SwiftSeekSmokeTest"]),
        .executable(name: "SwiftSeekStartup", targets: ["SwiftSeekStartup"]),
        .library(name: "SwiftSeekCore", targets: ["SwiftSeekCore"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "SwiftSeekCore",
            dependencies: ["CSQLite"],
            path: "Sources/SwiftSeekCore"
        ),
        .executableTarget(
            name: "SwiftSeek",
            dependencies: ["SwiftSeekCore"],
            path: "Sources/SwiftSeek"
        ),
        .executableTarget(
            name: "SwiftSeekIndex",
            dependencies: ["SwiftSeekCore"],
            path: "Sources/SwiftSeekIndex"
        ),
        .executableTarget(
            name: "SwiftSeekSearch",
            dependencies: ["SwiftSeekCore"],
            path: "Sources/SwiftSeekSearch"
        ),
        .executableTarget(
            name: "SwiftSeekSmokeTest",
            dependencies: ["SwiftSeekCore"],
            path: "Sources/SwiftSeekSmokeTest"
        ),
        .executableTarget(
            name: "SwiftSeekStartup",
            dependencies: ["SwiftSeekCore"],
            path: "Sources/SwiftSeekStartup"
        )
    ]
)
