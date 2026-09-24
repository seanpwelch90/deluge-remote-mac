// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DelugeRemote",
    platforms: [.macOS(.v14)],
    products: [
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
