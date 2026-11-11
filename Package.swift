// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Stoker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Stoker",
            path: "Sources/Stoker",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SpriteKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
