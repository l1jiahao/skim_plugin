// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SkimLLMSidebar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SkimLLMSidebar", targets: ["SkimLLMSidebar"]),
        .library(name: "SkimLLMCore", targets: ["SkimLLMCore"])
    ],
    targets: [
        .target(
            name: "CSQLite",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SkimLLMCore",
            dependencies: ["CSQLite"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "SkimLLMSidebar",
            dependencies: ["SkimLLMCore"]
        ),
        .testTarget(
            name: "SkimLLMCoreTests",
            dependencies: ["SkimLLMCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
