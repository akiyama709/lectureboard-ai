// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LectureBoardCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "LectureBoardCore", targets: ["LectureBoardCore"])
    ],
    targets: [
        .target(name: "LectureBoardCore"),
        .testTarget(
            name: "LectureBoardCoreTests",
            dependencies: ["LectureBoardCore"]
        )
    ]
)
