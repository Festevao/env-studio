// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EnvStudio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EnvStudio", targets: ["EnvStudio"]),
        .executable(name: "EnvStudioCoreVerify", targets: ["EnvStudioCoreVerify"]),
    ],
    targets: [
        .target(name: "EnvStudioCore", path: "Sources/EnvStudioCore"),
        .executableTarget(
            name: "EnvStudioCoreVerify",
            dependencies: ["EnvStudioCore", "EnvStudioConnectivity"],
            path: "Sources/EnvStudioCoreVerify"
        ),
        .executableTarget(
            name: "EnvStudio",
            dependencies: ["EnvStudioCore", "EnvStudioConnectivity"],
            path: "Sources/EnvStudio"
        ),
        .target(
            name: "EnvStudioConnectivity",
            path: "Sources/EnvStudioConnectivity"
        ),
        .testTarget(
            name: "EnvStudioTests",
            dependencies: ["EnvStudioCore", "EnvStudioConnectivity"],
            path: "Tests/EnvStudioTests"
        ),
    ]
)