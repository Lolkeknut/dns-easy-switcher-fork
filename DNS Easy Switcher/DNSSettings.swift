//
//  DNSSettings.swift
//  DNS Easy Switcher
//
//  Created by Gregory LINFORD on 23/02/2025.
//

import Foundation
import SwiftData

@Model
final class CustomDNSServer: Identifiable {
    var id: String
    var name: String
    @Attribute(originalName: "primaryDNS") var primaryIPv4: String
    @Attribute(originalName: "secondaryDNS") var secondaryIPv4: String
    var dnsOverHttps: String = ""
    var timestamp: Date
    
    init(id: String = UUID().uuidString,
         name: String,
         primaryIPv4: String,
         secondaryIPv4: String,
         dnsOverHttps: String = "",
         timestamp: Date = Date()) {
        self.id = id
        self.name = name
        self.primaryIPv4 = primaryIPv4
        self.secondaryIPv4 = secondaryIPv4
        self.dnsOverHttps = dnsOverHttps
        self.timestamp = timestamp
    }
}

@Model
final class DNSSettings {
    @Attribute(.unique) var id: String
    var isCloudflareEnabled: Bool
    var isQuad9Enabled: Bool
    var activeCustomDNSID: String?
    var selectedCustomDNSID: String?
    var isSelectedProfileEnabled: Bool = false
    var doubleClickMenuBarIconTogglesSelectedProfile: Bool = false
    var timestamp: Date
    var activeGetFlixLocation: String?
    var isAdGuardEnabled: Bool?
    
    init(id: String = UUID().uuidString,
         isCloudflareEnabled: Bool = false,
         isQuad9Enabled: Bool = false,
         activeCustomDNSID: String? = nil,
         selectedCustomDNSID: String? = nil,
         isSelectedProfileEnabled: Bool = false,
         doubleClickMenuBarIconTogglesSelectedProfile: Bool = false,
         timestamp: Date = Date(),
         isAdGuardEnabled: Bool? = false,
         activeGetFlixLocation: String? = nil) {
        self.id = id
        self.isCloudflareEnabled = isCloudflareEnabled
        self.isQuad9Enabled = isQuad9Enabled
        self.activeCustomDNSID = activeCustomDNSID
        self.selectedCustomDNSID = selectedCustomDNSID
        self.isSelectedProfileEnabled = isSelectedProfileEnabled
        self.doubleClickMenuBarIconTogglesSelectedProfile = doubleClickMenuBarIconTogglesSelectedProfile
        self.timestamp = timestamp
        self.isAdGuardEnabled = isAdGuardEnabled
        self.activeGetFlixLocation = activeGetFlixLocation
    }
}

extension CustomDNSServer {
    var profileSnapshot: DNSProfileSnapshot {
        DNSProfileSnapshot(
            id: id,
            name: name,
            primaryIPv4: primaryIPv4,
            secondaryIPv4: secondaryIPv4,
            dnsOverHttps: dnsOverHttps
        )
    }

    /// Returns this profile's IPv4 DNS entries as one linked configuration.
    var dnsEntries: [String] {
        [primaryIPv4, secondaryIPv4]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var profileSummary: String {
        let dohSummary = dnsOverHttps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "DoH not set" : "DoH configured"
        return "\(primaryIPv4), \(secondaryIPv4) | \(dohSummary)"
    }
}

extension DNSSettings {
    var selectedProfileID: String? {
        selectedCustomDNSID ?? activeCustomDNSID
    }

    var isDNSOverrideEnabled: Bool {
        isCloudflareEnabled
            || isQuad9Enabled
            || (isAdGuardEnabled ?? false)
            || activeGetFlixLocation != nil
            || isSelectedProfileEnabled
    }

    var profileSelectionState: DNSProfileSelectionState {
        DNSProfileSelectionState(
            selectedProfileID: selectedProfileID,
            activeProfileID: activeCustomDNSID,
            isSelectedProfileEnabled: isSelectedProfileEnabled,
            doubleClickMenuBarIconTogglesSelectedProfile: doubleClickMenuBarIconTogglesSelectedProfile
        )
    }
}
