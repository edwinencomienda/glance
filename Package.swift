// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Glance",
            path: "Sources/Glance"
        )
    ]
)
