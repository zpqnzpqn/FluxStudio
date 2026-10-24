// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FluxStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FluxStudio", targets: ["FluxStudio"])
    ],
    targets: [
        .executableTarget(
            name: "FluxStudio",
            path: "Sources/FluxStudio"
        )
    ]
)
