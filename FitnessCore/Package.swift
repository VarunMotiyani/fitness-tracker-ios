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
        .library(name: "Metrics", targets: ["Metrics"]),
        .library(name: "CoachMemory", targets: ["CoachMemory"]),
    ],
    targets: [
        .target(name: "FitnessDomain"),
        .target(name: "ExerciseCatalog", dependencies: ["FitnessDomain"]),
        .target(name: "RuleEngine", dependencies: ["FitnessDomain", "ExerciseCatalog"]),
        .target(name: "PlanValidation", dependencies: ["FitnessDomain", "ExerciseCatalog", "RuleEngine"]),
        .target(name: "LLMKit", dependencies: ["FitnessDomain"]),
        .target(name: "Metrics", dependencies: ["FitnessDomain", "ExerciseCatalog"]),
        .target(name: "CoachMemory", dependencies: ["FitnessDomain"]),
        .testTarget(name: "FitnessDomainTests", dependencies: ["FitnessDomain"]),
        .testTarget(name: "ExerciseCatalogTests", dependencies: ["ExerciseCatalog"]),
        .testTarget(name: "RuleEngineTests", dependencies: ["RuleEngine", "ExerciseCatalog"]),
        .testTarget(name: "PlanValidationTests", dependencies: ["PlanValidation"]),
        .testTarget(name: "LLMKitTests", dependencies: ["LLMKit"]),
        .testTarget(name: "MetricsTests", dependencies: ["Metrics", "FitnessDomain", "ExerciseCatalog"]),
        .testTarget(name: "CoachMemoryTests", dependencies: ["CoachMemory", "FitnessDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
