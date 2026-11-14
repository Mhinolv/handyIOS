// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HandyKit",
    platforms: [.iOS("26.0"), .macOS(.v13)],
    products: [.library(name: "HandyKit", targets: ["HandyKit"])],
    targets: [
        .target(name: "HandyKit"),
        .testTarget(name: "HandyKitTests", dependencies: ["HandyKit"])
    ]
)
