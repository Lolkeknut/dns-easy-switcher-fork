//
//  MenuBarView.swift
//  DNS Easy Switcher
//
//  Created by Gregory LINFORD on 23/02/2025.
//
import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DNSSettings.timestamp) private var dnsSettings: [DNSSettings]
    @Query(sort: \CustomDNSServer.name) private var customServers: [CustomDNSServer]
    @State private var isUpdating = false
    @State private var isSpeedTesting = false
    @State private var pingResults: [DNSSpeedTester.PingResult] = []
    @State private var showingAddDNS = false
    @State private var showingManageDNS = false
    @State private var aboutWindowController: CustomSheetWindowController?
    @State private var selectedServer: CustomDNSServer?
    @State private var windowController: CustomSheetWindowController?
    @State private var helperStatus = DNSManager.shared.privilegedHelperStatusSnapshot
    @State private var isInstallingHelper = false
    @State private var helperInstallMessage: String?
    
    var body: some View {
        Group {
            VStack {
                // Cloudflare DNS
                Toggle(getLabelWithPing("Cloudflare DNS", dnsType: .cloudflare), isOn: Binding(
                    get: { dnsSettings.first?.isCloudflareEnabled ?? false },
                    set: { newValue in
                        if newValue && !isUpdating {
                            activateDNS(type: .cloudflare)
                        }
                    }
                ))
                .padding(.horizontal)
                .disabled(dnsActionsDisabled)
                .overlay(alignment: .trailing) {
                    if isSpeedTesting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                            .padding(.trailing, 8)
                    }
                }
                
                // Quad9 DNS
                Toggle(getLabelWithPing("Quad9 DNS", dnsType: .quad9), isOn: Binding(
                    get: { dnsSettings.first?.isQuad9Enabled ?? false },
                    set: { newValue in
                        if newValue && !isUpdating {
                            activateDNS(type: .quad9)
                        }
                    }
                ))
                .padding(.horizontal)
                .disabled(dnsActionsDisabled)
                .overlay(alignment: .trailing) {
                    if isSpeedTesting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                            .padding(.trailing, 8)
                    }
                }
                
                // AdGuard DNS
                Toggle(getLabelWithPing("AdGuard DNS", dnsType: .adguard), isOn: Binding(
                    get: { dnsSettings.first?.isAdGuardEnabled ?? false },
                    set: { newValue in
                        if newValue && !isUpdating {
                            activateDNS(type: .adguard)
                        }
                    }
                ))
                .padding(.horizontal)
                .disabled(dnsActionsDisabled)
                .overlay(alignment: .trailing) {
                    if isSpeedTesting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                            .padding(.trailing, 8)
                    }
                }
                
                // GetFlix DNS Menu
                Menu {
                    ForEach(Array(DNSManager.shared.getflixServers.keys.sorted()), id: \.self) { location in
                        Button(action: {
                            activateDNS(type: .getflix(location))
                        }) {
                            HStack {
                                Text(getGetflixLabelWithPing(location))
                                Spacer()
                                if dnsSettings.first?.activeGetFlixLocation == location {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("GetFlix DNS")
                        Spacer()
                        if dnsSettings.first?.activeGetFlixLocation != nil {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                        if isSpeedTesting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                                .padding(.trailing, 4)
                        }
                    }
                }
                .padding(.horizontal)
                .disabled(dnsActionsDisabled)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("User Profiles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if isSpeedTesting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        }
                    }
                    .padding(.horizontal)

                    if customServers.isEmpty {
                        Text("No user profiles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    } else {
                        ForEach(customServers) { server in
                            Button(action: {
                                activateDNS(type: .custom(server))
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: isActiveProfile(server) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isActiveProfile(server) ? .green : .secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(getCustomDNSLabelWithPing(server))
                                            .fontWeight(isSelectedProfile(server) ? .semibold : .regular)
                                        Text(server.profileSummary)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .disabled(dnsActionsDisabled)
                        }
                    }
                }

                if !customServers.isEmpty {
                    Button(action: {
                        showManageCustomDNSSheet()
                    }) {
                        Text("Manage DNS Profiles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                    .disabled(isSpeedTesting)
                }
                
                Button(action: {
                    showAddCustomDNSSheet()
                }) {
                    Text("Add DNS Profile")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.vertical, 5)
                .disabled(isSpeedTesting)

                privilegedHelperSection

                Divider()
                
                Button("Disable DNS Override") {
                    if !isUpdating && !isSpeedTesting {
                        isUpdating = true
                        DNSManager.shared.disableDNS(profileID: dnsSettings.first?.selectedProfileID) { success in
                            if success {
                                Task { @MainActor in
                                    deactivateSelectedProfile()
                                }
                            }
                            isUpdating = false
                        }
                    }
                }
                .padding(.vertical, 5)
                .disabled(dnsActionsDisabled)
                
                // Speed Test Button
                Button(action: {
                    runSpeedTest()
                }) {
                    HStack {
                        Text("Run Speed Test")
                        if isSpeedTesting {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.vertical, 5)
                .disabled(isUpdating || isSpeedTesting)
                
                Button(action: {
                    clearDNSCache()
                }) {
                    HStack {
                        Text("Clear DNS Cache")
                        if isUpdating {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.vertical, 5)
                .disabled(dnsActionsDisabled)
                
                Divider()

                Button("About") {
                    showAboutSheet()
                }
                .padding(.vertical, 5)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .padding(.vertical, 5)
            }
            .padding(.vertical, 5)
        }
        .onAppear {
            ensureSettingsExist()
            refreshPrivilegedHelperStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .privilegedHelperStatusDidChange)) { _ in
            refreshPrivilegedHelperStatus()
        }
    }

    private var privilegedHelperSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: helperStatus.isEnabled ? "lock.open.fill" : "lock.fill")
                    .foregroundColor(helperStatus.isEnabled ? .green : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(helperStatus.title)
                        .font(.caption)
                    Text(helperInstallMessage ?? helperStatus.detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }

                Spacer()

                if isInstallingHelper {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                }
            }

            if !helperStatus.isEnabled {
                Button(helperStatus.requiresApproval ? "Open System Settings" : "Install Helper") {
                    if helperStatus.requiresApproval {
                        DNSManager.shared.openPrivilegedHelperApprovalSettings()
                    } else {
                        installPrivilegedHelper()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isInstallingHelper)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var dnsActionsDisabled: Bool {
        isUpdating || isSpeedTesting || !helperStatus.isEnabled
    }
    
    // Helper methods for getting ping results
    private func getLabelWithPing(_ baseLabel: String, dnsType: DNSType) -> String {
        guard !pingResults.isEmpty else { return baseLabel }
        
        switch dnsType {
        case .cloudflare:
            if let result = pingResults.first(where: { $0.dnsName == "Cloudflare" }) {
                return "\(baseLabel) (\(Int(result.responseTime))ms)"
            }
        case .quad9:
            if let result = pingResults.first(where: { $0.dnsName == "Quad9" }) {
                return "\(baseLabel) (\(Int(result.responseTime))ms)"
            }
        case .adguard:
            if let result = pingResults.first(where: { $0.dnsName == "AdGuard" }) {
                return "\(baseLabel) (\(Int(result.responseTime))ms)"
            }
        default:
            break
        }
        
        return baseLabel
    }
    
    private func getGetflixLabelWithPing(_ location: String) -> String {
        guard !pingResults.isEmpty else { return location }
        
        if let result = pingResults.first(where: { $0.dnsName == "Getflix: \(location)" }) {
            return "\(location) (\(Int(result.responseTime))ms)"
        }
        
        return location
    }
    
    private func getCustomDNSLabelWithPing(_ server: CustomDNSServer) -> String {
        guard !pingResults.isEmpty else { return server.name }
        
        if let result = pingResults.first(where: { $0.isCustom && $0.customID == server.id }) {
            return "\(server.name) (\(Int(result.responseTime))ms)"
        }
        
        return server.name
    }

    private func isSelectedProfile(_ server: CustomDNSServer) -> Bool {
        dnsSettings.first?.selectedProfileID == server.id
    }

    private func isActiveProfile(_ server: CustomDNSServer) -> Bool {
        dnsSettings.first?.activeCustomDNSID == server.id && dnsSettings.first?.isSelectedProfileEnabled == true
    }
    
    // Run DNS speed test
    private func runSpeedTest() {
        guard !isSpeedTesting else { return }
        
        isSpeedTesting = true
        pingResults = []
        
        DNSSpeedTester.shared.testAllDNS(customServers: customServers) { results in
            self.pingResults = results
            self.isSpeedTesting = false
        }
    }
    
    private func showAddCustomDNSSheet() {
        let addView = AddCustomDNSView { newServer in
            if let newServer = newServer {
                modelContext.insert(newServer)
                try? modelContext.save()
                // Automatically activate the new DNS
                activateDNS(type: .custom(newServer))
            }
            windowController?.close()
            windowController = nil
        }
        
        windowController = CustomSheetWindowController(view: addView, title: "Add DNS Profile")
        windowController?.window?.level = .floating
        windowController?.showWindow(nil)
        
        // Position the window relative to the menu bar
        if let window = windowController?.window,
           let screenFrame = NSScreen.main?.frame {
            let windowFrame = window.frame
            let newOrigin = NSPoint(
                x: screenFrame.width - windowFrame.width - 20,
                y: screenFrame.height - 40 - windowFrame.height
            )
            window.setFrameTopLeftPoint(newOrigin)
        }
    }
    
    private func showManageCustomDNSSheet() {
        let manageView = CustomDNSManagerView(customServers: customServers, onAction: { action, server in
            switch action {
            case .edit:
                editCustomDNS(server)
            case .delete:
                modelContext.delete(server)
                try? modelContext.save()
                
                // If this was the active server, disable DNS
                if dnsSettings.first?.activeCustomDNSID == server.id || dnsSettings.first?.selectedCustomDNSID == server.id {
                    isUpdating = true
                    DNSManager.shared.disableDNS(profileID: server.id) { success in
                        if success {
                            Task { @MainActor in
                                clearDeletedProfile(server.id)
                            }
                        }
                        isUpdating = false
                    }
                }
            case .use:
                activateDNS(type: .custom(server))
            }
            
            // Don't close the window for .use or .edit actions
            if action == .delete {
                windowController?.close()
                windowController = nil
            }
        }, onClose: {
            windowController?.close()
            windowController = nil
        })
        
        windowController = CustomSheetWindowController(view: manageView, title: "Manage DNS Profiles")
        windowController?.window?.level = .floating
        windowController?.showWindow(nil)
        
        // Position the window relative to the menu bar
        if let window = windowController?.window,
           let screenFrame = NSScreen.main?.frame {
            let windowFrame = window.frame
            let newOrigin = NSPoint(
                x: screenFrame.width - windowFrame.width - 20,
                y: screenFrame.height - 40 - windowFrame.height
            )
            window.setFrameTopLeftPoint(newOrigin)
        }
    }
    
    private func showAboutSheet() {
        let aboutView = AboutView {
            aboutWindowController?.close()
            aboutWindowController = nil
        }
        
        aboutWindowController?.close()
        aboutWindowController = CustomSheetWindowController(view: aboutView, title: "About")
        aboutWindowController?.window?.level = .floating
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.center()
    }
    
    private func editCustomDNS(_ server: CustomDNSServer) {
        let editView = EditCustomDNSView(server: server) { updatedServer in
            if let updatedServer = updatedServer {
                // Update existing server properties
                server.name = updatedServer.name
                server.primaryIPv4 = updatedServer.primaryIPv4
                server.secondaryIPv4 = updatedServer.secondaryIPv4
                server.dnsOverHttps = updatedServer.dnsOverHttps
                try? modelContext.save()
                
                // If this was the active server, update DNS settings
                if dnsSettings.first?.activeCustomDNSID == server.id && dnsSettings.first?.isSelectedProfileEnabled == true {
                    activateDNS(type: .custom(server))
                }
            }
            
            windowController?.close()
            windowController = nil
        }
        
        windowController?.close()
        
        windowController = CustomSheetWindowController(view: editView, title: "Edit DNS Profile")
        windowController?.window?.level = .floating
        windowController?.showWindow(nil)
        
        // Position the window relative to the menu bar
        if let window = windowController?.window,
           let screenFrame = NSScreen.main?.frame {
            let windowFrame = window.frame
            let newOrigin = NSPoint(
                x: screenFrame.width - windowFrame.width - 20,
                y: screenFrame.height - 40 - windowFrame.height
            )
            window.setFrameTopLeftPoint(newOrigin)
        }
    }
    
    enum DNSType: Equatable {
        case none
        case cloudflare
        case quad9
        case adguard
        case custom(CustomDNSServer)
        case getflix(String)
        
        static func == (lhs: DNSType, rhs: DNSType) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case (.cloudflare, .cloudflare):
                return true
            case (.quad9, .quad9):
                return true
            case (.adguard, .adguard):
                return true
            case (.custom(let lServer), .custom(let rServer)):
                return lServer.id == rServer.id
            case (.getflix(let lLocation), .getflix(let rLocation)):
                return lLocation == rLocation
            default:
                return false
            }
        }
    }
    
    private func activateDNS(type: DNSType) {
        isUpdating = true
        
        switch type {
        case .cloudflare:
            DNSManager.shared.setPredefinedDNS(dnsServers: DNSManager.shared.cloudflareServers) { success in
                if success {
                    Task { @MainActor in
                        updateSettings(type: type)
                    }
                }
                isUpdating = false
            }
        case .quad9:
            DNSManager.shared.setPredefinedDNS(dnsServers: DNSManager.shared.quad9Servers) { success in
                if success {
                    Task { @MainActor in
                        updateSettings(type: type)
                    }
                }
                isUpdating = false
            }
        case .adguard:
            DNSManager.shared.setPredefinedDNS(dnsServers: DNSManager.shared.adguardServers) { success in
                if success {
                    Task { @MainActor in
                        updateSettings(type: type)
                    }
                }
                isUpdating = false
            }
        case .custom(let server):
            DNSManager.shared.setDNSProfile(server.profileSnapshot) { success in
                if success {
                    Task { @MainActor in
                        updateSettings(type: type)
                    }
                }
                isUpdating = false
            }
        case .getflix(let location):
            if let dnsServer = DNSManager.shared.getflixServers[location] {
                DNSManager.shared.setCustomDNS(servers: [dnsServer]) { success in
                    if success {
                        Task { @MainActor in
                            updateSettings(type: type)
                        }
                    }
                    isUpdating = false
                }
            }
        case .none:
            updateSettings(type: type)
            isUpdating = false
        }
    }
    
    private func updateSettings(type: DNSType) {
        if let settings = dnsSettings.first {
            settings.isCloudflareEnabled = (type == .cloudflare)
            settings.isQuad9Enabled = (type == .quad9)
            settings.isAdGuardEnabled = type == .adguard ? true : nil
            
            if case .getflix(let location) = type {
                settings.activeGetFlixLocation = location
            } else {
                settings.activeGetFlixLocation = nil
            }
            
            if case .custom(let server) = type {
                settings.activeCustomDNSID = server.id
                settings.selectedCustomDNSID = server.id
                settings.isSelectedProfileEnabled = true
            } else {
                settings.activeCustomDNSID = nil
                settings.isSelectedProfileEnabled = false
            }
            
            settings.timestamp = Date()
            try? modelContext.save()
            NotificationCenter.default.post(
                name: .dnsSettingsDidChange,
                object: nil,
                userInfo: ["isEnabled": settings.isDNSOverrideEnabled]
            )
        }
    }

    private func deactivateSelectedProfile() {
        if let settings = dnsSettings.first {
            settings.isCloudflareEnabled = false
            settings.isQuad9Enabled = false
            settings.isAdGuardEnabled = false
            settings.activeGetFlixLocation = nil
            settings.activeCustomDNSID = nil
            settings.isSelectedProfileEnabled = false
            settings.timestamp = Date()
            try? modelContext.save()
            NotificationCenter.default.post(name: .dnsSettingsDidChange, object: nil, userInfo: ["isEnabled": false])
        }
    }

    private func clearDeletedProfile(_ profileID: String) {
        if let settings = dnsSettings.first {
            settings.isCloudflareEnabled = false
            settings.isQuad9Enabled = false
            settings.isAdGuardEnabled = false
            settings.activeGetFlixLocation = nil
            if settings.activeCustomDNSID == profileID {
                settings.activeCustomDNSID = nil
            }
            if settings.selectedCustomDNSID == profileID {
                settings.selectedCustomDNSID = nil
            }
            settings.isSelectedProfileEnabled = false
            settings.timestamp = Date()
            try? modelContext.save()
            NotificationCenter.default.post(name: .dnsSettingsDidChange, object: nil, userInfo: ["isEnabled": false])
        }
    }
    
    private func ensureSettingsExist() {
        if dnsSettings.isEmpty {
            modelContext.insert(DNSSettings())
            try? modelContext.save()
        }
    }
    
    private func clearDNSCache() {
        if !isUpdating && !isSpeedTesting {
            isUpdating = true
            DNSManager.shared.clearDNSCache { success in
                DispatchQueue.main.async {
                    self.isUpdating = false
                }
            }
        }
    }

    private func refreshPrivilegedHelperStatus() {
        helperStatus = DNSManager.shared.privilegedHelperStatusSnapshot
    }

    private func installPrivilegedHelper() {
        isInstallingHelper = true
        helperInstallMessage = nil

        DNSManager.shared.installPrivilegedHelper { success, message in
            helperInstallMessage = success ? "Helper installed. DNS changes will no longer ask for admin rights." : message
            refreshPrivilegedHelperStatus()
            isInstallingHelper = false
        }
    }
}
