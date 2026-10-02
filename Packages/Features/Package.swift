// swift-tools-version: 5.9
import PackageDescription

let featureDeps: [Target.Dependency] = ["FeatureSupport", .product(name: "Domain", package: "Domain"), .product(name: "DesignSystem", package: "DesignSystem")]

let package = Package(
    name: "Features",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Features", targets: ["FeatureSupport", "SetupFeature", "HomeFeature", "ProjectsFeature", "CalendarFeature", "ExpensesFeature", "MoreFeature"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "FeatureSupport", dependencies: [.product(name: "Domain", package: "Domain"), .product(name: "DesignSystem", package: "DesignSystem")], path: "Sources/FeatureSupport"),
        .target(name: "SetupFeature", dependencies: featureDeps, path: "Sources/SetupFeature"),
        .target(name: "HomeFeature", dependencies: featureDeps, path: "Sources/HomeFeature"),
        .target(name: "ProjectsFeature", dependencies: featureDeps, path: "Sources/ProjectsFeature"),
        .target(name: "CalendarFeature", dependencies: featureDeps, path: "Sources/CalendarFeature"),
        .target(name: "ExpensesFeature", dependencies: featureDeps, path: "Sources/ExpensesFeature"),
        .target(name: "MoreFeature", dependencies: featureDeps, path: "Sources/MoreFeature"),
    ]
)
