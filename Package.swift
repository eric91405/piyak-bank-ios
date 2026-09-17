// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PiyakCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "PiyakCore", targets: ["PiyakCore"])],
    targets: [
        .target(name: "PiyakCore", path: "PiyakBank", exclude: [
            "App/PiyakBankApp.swift", "App/PiyakChatView.swift", "Views", "Watch", "Widget", "Assets.xcassets", "Info.plist", "PiyakBank.entitlements",
            "Services/NotificationScheduler.swift", "Services/WatchSync.swift",
            "PrivacyInfo.xcprivacy", "Shared/DesignTokens.swift"
        ], sources: ["Shared/AppConfig.swift", "Shared/EarningsCalculator.swift", "Shared/Economy.swift", "Shared/PiyakActivityPlan.swift", "Shared/PiyakConversation.swift",
                     "Services/WorkSession.swift", "Services/SessionController.swift", "App/PiyakAI.swift"]),
        .testTarget(name: "PiyakCoreTests", dependencies: ["PiyakCore"], path: "Tests/PiyakCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
