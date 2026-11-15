// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ServerApp",
    platforms: [.iOS(.v15)],
    products: [
        .executable(name: "ServerApp", targets: ["ServerApp"])
    ],
    targets: [
        .executableTarget(
            name: "ServerApp",
            path: "."
        )
    ]
)
