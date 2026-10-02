// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DelugeRemote",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DelugeRemoteCore", targets: ["DelugeRemoteCore"]),
        .executable(name: "DelugeRemote", targets: ["DelugeRemote"])
    ],
    targets: [
        .target(name: "DelugeRemoteCore"),
        .executableTarget(
            name: "DelugeRemote",
            dependencies: ["DelugeRemoteCore"]
        ),
        .testTarget(
            name: "DelugeRemoteTests",
            dependencies: ["DelugeRemoteCore"]
        )
    ]
)
