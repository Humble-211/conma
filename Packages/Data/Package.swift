// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Data",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Data", targets: ["Data"])],
    dependencies: [
        .package(path: "../Domain"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "Data", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")], path: "Sources/Data"),
        .testTarget(name: "DataTests", dependencies: ["Data"], path: "Tests/DataTests"),
    ]
)
