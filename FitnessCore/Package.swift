// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FitnessCore",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "FitnessDomain", targets: ["FitnessDomain"]),
        .library(name: "ExerciseCatalog", targets: ["ExerciseCatalog"]),
        .library(name: "RuleEngine", targets: ["RuleEngine"]),
        .library(name: "PlanValidation", targets: ["PlanValidation"]),
        .library(name: "LLMKit", targets: ["LLMKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.0.0"),
    ],
    targets: [
        .target(name: "FitnessDomain"),
        .target(name: "ExerciseCatalog", dependencies: ["FitnessDomain"]),
        .target(name: "RuleEngine", dependencies: ["FitnessDomain", "ExerciseCatalog"]),
        .target(name: "PlanValidation", dependencies: ["FitnessDomain", "ExerciseCatalog", "RuleEngine"]),
        .target(name: "LLMKit", dependencies: ["FitnessDomain"]),
        .testTarget(name: "FitnessDomainTests", dependencies: ["FitnessDomain", .product(name: "Testing", package: "swift-testing")]),
        .testTarget(name: "ExerciseCatalogTests", dependencies: ["ExerciseCatalog", .product(name: "Testing", package: "swift-testing")]),
        .testTarget(name: "RuleEngineTests", dependencies: ["RuleEngine", "ExerciseCatalog", .product(name: "Testing", package: "swift-testing")]),
        .testTarget(name: "PlanValidationTests", dependencies: ["PlanValidation", .product(name: "Testing", package: "swift-testing")]),
        .testTarget(name: "LLMKitTests", dependencies: ["LLMKit", .product(name: "Testing", package: "swift-testing")]),
    ],
    swiftLanguageModes: [.v6]
)
