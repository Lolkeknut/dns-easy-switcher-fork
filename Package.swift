// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DNSEasySwitcherCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DNSEasySwitcherCore", targets: ["DNSEasySwitcherCore"])
    ],
    targets: [
        .target(
            name: "DNSEasySwitcherCore",
            path: "DNS Easy Switcher",
            exclude: [
                "AboutView.swift",
                "AddCustomDNSView.swift",
                "Assets.xcassets",
                "CustomDNSManagerView.swift",
                "CustomSheet.swift",
                "DNSSpeedTester.swift",
                "DNSManager.swift",
                "DNSSettings.swift",
                "DNS_Easy_Switcher.entitlements",
                "DNS_Easy_SwitcherApp.swift",
                "EditCustomDNSView.swift",
                "MenuBarController.swift",
                "MenuBarView.swift",
                "PrivilegedDNSHelperProtocol.swift",
                "PrivilegedHelper",
                "PrivilegedHelperManager.swift",
                "Preview Content"
            ],
            sources: ["DNSProfileCore.swift"]
        ),
        .executableTarget(
            name: "DNSEasySwitcherCoreTestRunner",
            dependencies: ["DNSEasySwitcherCore"],
            path: "DNS Easy SwitcherTests"
        )
    ]
)
