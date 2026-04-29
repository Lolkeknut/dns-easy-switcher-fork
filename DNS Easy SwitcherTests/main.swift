import Foundation
import DNSEasySwitcherCore

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TestFailure(description: "\(message). Expected \(expected), got \(actual)")
    }
}

let tests: [(String, () throws -> Void)] = [
    ("creates profile with linked DNS fields", {
        let profile = DNSProfileSnapshot(
            name: "Work",
            primaryIPv4: "1.1.1.1",
            secondaryIPv4: "1.0.0.1",
            dnsOverHttps: "https://cloudflare-dns.com/dns-query"
        )

        try expectEqual(profile.name, "Work", "name")
        try expectEqual(profile.primaryIPv4, "1.1.1.1", "primary IPv4")
        try expectEqual(profile.secondaryIPv4, "1.0.0.1", "secondary IPv4")
        try expectEqual(profile.dnsOverHttps, "https://cloudflare-dns.com/dns-query", "DoH")
        try expect(DNSProfileValidator.isValid(profile), "profile should be valid")
    }),
    ("validates IPv4 addresses", {
        try expect(DNSProfileValidator.isValidIPv4("8.8.8.8"), "8.8.8.8 should be valid")
        try expect(DNSProfileValidator.isValidIPv4("0.0.0.0"), "0.0.0.0 should be valid")
        try expect(DNSProfileValidator.isValidIPv4("255.255.255.255"), "255.255.255.255 should be valid")

        try expect(!DNSProfileValidator.isValidIPv4("8.8.8"), "short IPv4 should fail")
        try expect(!DNSProfileValidator.isValidIPv4("8.8.8.256"), "out of range octet should fail")
        try expect(!DNSProfileValidator.isValidIPv4("08.8.8.8"), "leading zero should fail")
        try expect(!DNSProfileValidator.isValidIPv4("2001:4860:4860::8888"), "IPv6 should fail")
        try expect(!DNSProfileValidator.isValidIPv4("127.0.0.1:5353"), "IPv4 with port should fail")
    }),
    ("validates DNS-over-HTTPS URLs", {
        try expect(DNSProfileValidator.isValidDNSOverHTTPSURL("https://dns.google/dns-query"), "Google DoH URL should be valid")
        try expect(DNSProfileValidator.isValidDNSOverHTTPSURL("https://cloudflare-dns.com/dns-query"), "Cloudflare DoH URL should be valid")

        try expect(!DNSProfileValidator.isValidDNSOverHTTPSURL("http://dns.google/dns-query"), "http URL should fail")
        try expect(!DNSProfileValidator.isValidDNSOverHTTPSURL("https://"), "missing host should fail")
        try expect(!DNSProfileValidator.isValidDNSOverHTTPSURL("dns.google/dns-query"), "missing scheme should fail")
    }),
    ("reports profile validation errors", {
        let profile = DNSProfileSnapshot(
            name: "",
            primaryIPv4: "999.1.1.1",
            secondaryIPv4: "",
            dnsOverHttps: "http://dns.google/dns-query"
        )

        try expectEqual(
            DNSProfileValidator.validationErrors(for: profile),
            [
                .missingName,
                .invalidPrimaryIPv4("999.1.1.1"),
                .missingSecondaryIPv4,
                .invalidDNSOverHTTPS("http://dns.google/dns-query")
            ],
            "validation errors"
        )
    }),
    ("serializes and deserializes profile", {
        let profile = DNSProfileSnapshot(
            id: "profile-1",
            name: "Home",
            primaryIPv4: "9.9.9.9",
            secondaryIPv4: "149.112.112.112",
            dnsOverHttps: "https://dns.quad9.net/dns-query"
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(DNSProfileSnapshot.self, from: data)

        try expectEqual(decoded, profile, "decoded profile")
    }),
    ("decodes legacy profile fields", {
        let data = """
        {
            "id": "legacy-1",
            "name": "Legacy",
            "primaryDNS": "8.8.8.8",
            "secondaryDNS": "8.8.4.4"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DNSProfileSnapshot.self, from: data)

        try expectEqual(decoded.id, "legacy-1", "legacy id")
        try expectEqual(decoded.name, "Legacy", "legacy name")
        try expectEqual(decoded.primaryIPv4, "8.8.8.8", "legacy primary")
        try expectEqual(decoded.secondaryIPv4, "8.8.4.4", "legacy secondary")
        try expectEqual(decoded.dnsOverHttps, "", "legacy DoH default")
        try expect(DNSProfileValidator.isValid(decoded, requireDNSOverHTTPS: false), "legacy profile should validate without DoH")
    }),
    ("menu bar click toggles disabled selected profile on", {
        let state = DNSProfileSelectionState(
            selectedProfileID: "profile-1",
            activeProfileID: nil,
            isSelectedProfileEnabled: false
        )

        try expectEqual(
            MenuBarStatusItemPolicy.mouseUpDecision(state: state, didOpenMenuFromLongPress: false),
            .toggleSelectedProfile,
            "single click should toggle selected profile"
        )
        try expectEqual(
            MenuBarStatusItemPolicy.toggleDecision(for: state),
            .enable(profileID: "profile-1"),
            "click enable decision"
        )
    }),
    ("menu bar click toggles enabled selected profile off", {
        let state = DNSProfileSelectionState(
            selectedProfileID: "profile-1",
            activeProfileID: "profile-1",
            isSelectedProfileEnabled: true
        )

        try expectEqual(
            MenuBarStatusItemPolicy.toggleDecision(for: state),
            .disable(profileID: "profile-1"),
            "click disable decision"
        )
    }),
    ("menu bar click is safe without a selected profile", {
        let missingProfile = DNSProfileSelectionState(
            selectedProfileID: nil,
            activeProfileID: nil,
            isSelectedProfileEnabled: false
        )

        try expectEqual(
            MenuBarStatusItemPolicy.mouseUpDecision(state: missingProfile, didOpenMenuFromLongPress: false),
            .noAction,
            "missing profile should not toggle"
        )
        try expectEqual(MenuBarStatusItemPolicy.toggleDecision(for: missingProfile), .noAction, "missing profile toggle")
    }),
    ("long press opens menu and suppresses click toggle", {
        let state = DNSProfileSelectionState(
            selectedProfileID: "profile-1",
            activeProfileID: nil,
            isSelectedProfileEnabled: false
        )

        try expect(MenuBarStatusItemPolicy.shouldOpenMenu(pressDuration: MenuBarStatusItemPolicy.longPressThreshold), "threshold opens menu")
        try expect(!MenuBarStatusItemPolicy.shouldOpenMenu(pressDuration: MenuBarStatusItemPolicy.longPressThreshold - 0.01), "short press does not open menu")
        try expectEqual(
            MenuBarStatusItemPolicy.mouseUpDecision(state: state, didOpenMenuFromLongPress: true),
            .noAction,
            "long press mouse up should not toggle"
        )
    }),
    ("status icon reflects DNS enabled state", {
        try expectEqual(DNSStatusIconPolicy.symbolName(isEnabled: true), "circle.fill", "enabled icon")
        try expectEqual(DNSStatusIconPolicy.symbolName(isEnabled: false), "network", "disabled icon")
    }),
    ("privileged helper launch policy requests approval or registration", {
        try expectEqual(
            PrivilegedHelperLaunchPolicy.action(for: PrivilegedHelperLaunchState(isEnabled: true, requiresApproval: false)),
            .none,
            "enabled helper should not prompt"
        )
        try expectEqual(
            PrivilegedHelperLaunchPolicy.action(for: PrivilegedHelperLaunchState(isEnabled: false, requiresApproval: true)),
            .openApprovalSettings,
            "approval should open system settings"
        )
        try expectEqual(
            PrivilegedHelperLaunchPolicy.action(for: PrivilegedHelperLaunchState(isEnabled: false, requiresApproval: false)),
            .register,
            "missing helper should be registered"
        )
        try expect(
            PrivilegedHelperLaunchPolicy.shouldOpenApprovalAfterRegistration(
                PrivilegedHelperLaunchState(isEnabled: false, requiresApproval: true)
            ),
            "approval should open after registration"
        )
    }),
    ("privileged helper operation timeout policy prevents endless loading", {
        try expect(
            PrivilegedHelperOperationTimeoutPolicy.didTimeOut(elapsed: PrivilegedHelperOperationTimeoutPolicy.defaultTimeout),
            "default timeout threshold should time out"
        )
        try expect(
            !PrivilegedHelperOperationTimeoutPolicy.didTimeOut(elapsed: PrivilegedHelperOperationTimeoutPolicy.defaultTimeout - 0.1),
            "operation should not time out before threshold"
        )
    })
]

var failures: [String] = []

for (name, test) in tests {
    do {
        try test()
        print("PASS: \(name)")
    } catch {
        failures.append("FAIL: \(name): \(error)")
    }
}

if failures.isEmpty {
    print("All \(tests.count) DNS profile core tests passed.")
} else {
    failures.forEach { print($0) }
    exit(1)
}
