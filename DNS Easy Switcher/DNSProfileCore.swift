//
//  DNSProfileCore.swift
//  DNS Easy Switcher
//

import Foundation

public struct DNSProfileSnapshot: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var primaryIPv4: String
    public var secondaryIPv4: String
    public var dnsOverHttps: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        primaryIPv4: String,
        secondaryIPv4: String,
        dnsOverHttps: String
    ) {
        self.id = id
        self.name = name
        self.primaryIPv4 = primaryIPv4
        self.secondaryIPv4 = secondaryIPv4
        self.dnsOverHttps = dnsOverHttps
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case primaryIPv4
        case secondaryIPv4
        case dnsOverHttps
        case primaryDNS
        case secondaryDNS
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        primaryIPv4 = try container.decodeIfPresent(String.self, forKey: .primaryIPv4)
            ?? container.decodeIfPresent(String.self, forKey: .primaryDNS)
            ?? ""
        secondaryIPv4 = try container.decodeIfPresent(String.self, forKey: .secondaryIPv4)
            ?? container.decodeIfPresent(String.self, forKey: .secondaryDNS)
            ?? ""
        dnsOverHttps = try container.decodeIfPresent(String.self, forKey: .dnsOverHttps) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(primaryIPv4, forKey: .primaryIPv4)
        try container.encode(secondaryIPv4, forKey: .secondaryIPv4)
        try container.encode(dnsOverHttps, forKey: .dnsOverHttps)
    }
}

public enum DNSProfileValidationError: LocalizedError, Equatable {
    case missingName
    case missingPrimaryIPv4
    case invalidPrimaryIPv4(String)
    case missingSecondaryIPv4
    case invalidSecondaryIPv4(String)
    case missingDNSOverHTTPS
    case invalidDNSOverHTTPS(String)

    public var errorDescription: String? {
        switch self {
        case .missingName:
            return "Profile name is required."
        case .missingPrimaryIPv4:
            return "Primary IPv4 address is required."
        case .invalidPrimaryIPv4(let value):
            return "'\(value)' is not a valid primary IPv4 address."
        case .missingSecondaryIPv4:
            return "Secondary IPv4 address is required."
        case .invalidSecondaryIPv4(let value):
            return "'\(value)' is not a valid secondary IPv4 address."
        case .missingDNSOverHTTPS:
            return "DNS-over-HTTPS URL is required."
        case .invalidDNSOverHTTPS(let value):
            return "'\(value)' is not a valid DNS-over-HTTPS URL."
        }
    }
}

public struct DNSProfileValidator {
    public static func normalized(_ profile: DNSProfileSnapshot) -> DNSProfileSnapshot {
        DNSProfileSnapshot(
            id: profile.id,
            name: profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryIPv4: profile.primaryIPv4.trimmingCharacters(in: .whitespacesAndNewlines),
            secondaryIPv4: profile.secondaryIPv4.trimmingCharacters(in: .whitespacesAndNewlines),
            dnsOverHttps: profile.dnsOverHttps.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public static func validationErrors(for profile: DNSProfileSnapshot, requireDNSOverHTTPS: Bool = true) -> [DNSProfileValidationError] {
        let profile = normalized(profile)
        var errors: [DNSProfileValidationError] = []

        if profile.name.isEmpty {
            errors.append(.missingName)
        }

        if profile.primaryIPv4.isEmpty {
            errors.append(.missingPrimaryIPv4)
        } else if !isValidIPv4(profile.primaryIPv4) {
            errors.append(.invalidPrimaryIPv4(profile.primaryIPv4))
        }

        if profile.secondaryIPv4.isEmpty {
            errors.append(.missingSecondaryIPv4)
        } else if !isValidIPv4(profile.secondaryIPv4) {
            errors.append(.invalidSecondaryIPv4(profile.secondaryIPv4))
        }

        if profile.dnsOverHttps.isEmpty {
            if requireDNSOverHTTPS {
                errors.append(.missingDNSOverHTTPS)
            }
        } else if !isValidDNSOverHTTPSURL(profile.dnsOverHttps) {
            errors.append(.invalidDNSOverHTTPS(profile.dnsOverHttps))
        }

        return errors
    }

    public static func isValid(_ profile: DNSProfileSnapshot, requireDNSOverHTTPS: Bool = true) -> Bool {
        validationErrors(for: profile, requireDNSOverHTTPS: requireDNSOverHTTPS).isEmpty
    }

    public static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }

        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let octet = Int(part), (0...255).contains(octet) else {
                return false
            }

            if part.count > 1 && part.first == "0" {
                return false
            }
        }

        return true
    }

    public static func isValidDNSOverHTTPSURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }

        return components.path.isEmpty == false || components.queryItems?.isEmpty == false
    }
}

public struct DNSProfileSelectionState: Codable, Equatable {
    public var selectedProfileID: String?
    public var activeProfileID: String?
    public var isSelectedProfileEnabled: Bool
    public var doubleClickMenuBarIconTogglesSelectedProfile: Bool

    public init(
        selectedProfileID: String? = nil,
        activeProfileID: String? = nil,
        isSelectedProfileEnabled: Bool = false,
        doubleClickMenuBarIconTogglesSelectedProfile: Bool = false
    ) {
        self.selectedProfileID = selectedProfileID
        self.activeProfileID = activeProfileID
        self.isSelectedProfileEnabled = isSelectedProfileEnabled
        self.doubleClickMenuBarIconTogglesSelectedProfile = doubleClickMenuBarIconTogglesSelectedProfile
    }
}

public enum DNSProfileToggleDecision: Equatable {
    case noAction
    case enable(profileID: String)
    case disable(profileID: String)
}

public struct MenuBarDoubleClickTogglePolicy {
    public static func decision(for state: DNSProfileSelectionState, clickCount: Int) -> DNSProfileToggleDecision {
        guard clickCount >= 2,
              state.doubleClickMenuBarIconTogglesSelectedProfile,
              let selectedProfileID = state.selectedProfileID,
              !selectedProfileID.isEmpty else {
            return .noAction
        }

        if state.isSelectedProfileEnabled && state.activeProfileID == selectedProfileID {
            return .disable(profileID: selectedProfileID)
        }

        return .enable(profileID: selectedProfileID)
    }
}

public enum DNSStatusItemMouseUpDecision: Equatable {
    case noAction
    case openMenu
    case toggleSelectedProfile
}

public struct MenuBarStatusItemPolicy {
    public static let longPressThreshold: TimeInterval = 0.45

    public static func mouseUpDecision(state: DNSProfileSelectionState, didOpenMenuFromLongPress: Bool) -> DNSStatusItemMouseUpDecision {
        guard !didOpenMenuFromLongPress else { return .noAction }
        guard let selectedProfileID = state.selectedProfileID, !selectedProfileID.isEmpty else { return .noAction }
        return .toggleSelectedProfile
    }

    public static func toggleDecision(for state: DNSProfileSelectionState) -> DNSProfileToggleDecision {
        guard let selectedProfileID = state.selectedProfileID, !selectedProfileID.isEmpty else {
            return .noAction
        }

        if state.isSelectedProfileEnabled && state.activeProfileID == selectedProfileID {
            return .disable(profileID: selectedProfileID)
        }

        return .enable(profileID: selectedProfileID)
    }

    public static func shouldOpenMenu(pressDuration: TimeInterval) -> Bool {
        pressDuration >= longPressThreshold
    }
}

public struct DNSStatusIconPolicy {
    public static func symbolName(isEnabled: Bool) -> String {
        isEnabled ? "circle.fill" : "network"
    }
}
