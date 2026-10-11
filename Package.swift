// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LightTranslate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LightTranslate", targets: ["LightTranslate"]),
        .executable(name: "TranslationEval", targets: ["TranslationEval"])
    ],
    targets: [
        .binaryTarget(name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959"),
        .target(name: "TranslationCore", resources: [.process("Resources")]),
        .executableTarget(name: "LightTranslate", dependencies: ["TranslationCore", "Sparkle"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "TranslationEval", dependencies: ["TranslationCore"]),
        .executableTarget(name: "TranslationChecks", dependencies: ["TranslationCore"], path: "Tests/TranslationCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
