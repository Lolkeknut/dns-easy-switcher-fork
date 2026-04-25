//
//  MenuBarController.swift
//  DNS Easy Switcher
//
//  Created by Gregory LINFORD on 23/02/2025.
//

import Foundation
import AppKit
import SwiftData
import SwiftUI

extension Notification.Name {
    static let dnsSettingsDidChange = Notification.Name("DNSEasySwitcherSettingsDidChange")
}

@MainActor
class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var modelContainer: ModelContainer?
    private var isTogglingSelectedProfile = false
    private var longPressTimer: Timer?
    private var didOpenMenuFromLongPress = false
    private var settingsObserver: NSObjectProtocol?

    override init() {
        super.init()
        // Hide the dock icon
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func configure(modelContainer: ModelContainer) {
        guard statusItem == nil else { return }

        self.modelContainer = modelContainer

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseUp])
        self.statusItem = statusItem
        updateStatusIcon(isEnabled: currentSettings()?.isDNSOverrideEnabled == true)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environment(\.modelContext, modelContainer.mainContext)
                .frame(width: 420)
        )
        self.popover = popover

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .dnsSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let isEnabled = notification.userInfo?["isEnabled"] as? Bool
            Task { @MainActor in
                let currentEnabled = self?.currentSettings()?.isDNSOverrideEnabled == true
                self?.updateStatusIcon(isEnabled: isEnabled ?? currentEnabled)
            }
        }

        DNSManager.shared.preparePrivilegedHelperAtLaunch()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApplication.shared.currentEvent else {
            openPopover(relativeTo: sender)
            return
        }

        if event.type == .rightMouseUp {
            cancelLongPressTimer()
            openPopover(relativeTo: sender)
            return
        }

        switch event.type {
        case .leftMouseDown:
            didOpenMenuFromLongPress = false
            cancelLongPressTimer()
            longPressTimer = Timer.scheduledTimer(withTimeInterval: MenuBarStatusItemPolicy.longPressThreshold, repeats: false) { [weak self, weak sender] _ in
                guard let self, let sender else { return }
                Task { @MainActor in
                    self.didOpenMenuFromLongPress = true
                    self.openPopover(relativeTo: sender)
                }
            }
        case .leftMouseUp:
            cancelLongPressTimer()
            guard let settings = currentSettings() else { return }
            let mouseDecision = MenuBarStatusItemPolicy.mouseUpDecision(
                state: settings.profileSelectionState,
                didOpenMenuFromLongPress: didOpenMenuFromLongPress
            )
            didOpenMenuFromLongPress = false

            guard mouseDecision == .toggleSelectedProfile else { return }
            applySelectedProfileToggleDecision(MenuBarStatusItemPolicy.toggleDecision(for: settings.profileSelectionState))
        default:
            break
        }
    }

    private func openPopover(relativeTo button: NSStatusBarButton) {
        guard let popover else { return }

        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func cancelLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func applySelectedProfileToggleDecision(_ decision: DNSProfileToggleDecision) {
        switch decision {
        case .noAction:
            break
        case .enable(let profileID):
            toggleSelectedProfile(profileID: profileID, enable: true)
            popover?.performClose(nil)
        case .disable(let profileID):
            toggleSelectedProfile(profileID: profileID, enable: false)
            popover?.performClose(nil)
        }
    }

    private func toggleSelectedProfile(profileID: String, enable: Bool) {
        guard !isTogglingSelectedProfile else { return }
        guard let modelContainer else { return }

        let context = modelContainer.mainContext
        isTogglingSelectedProfile = true

        if enable {
            guard let profile = fetchProfile(id: profileID, context: context) else {
                print("Menu bar click ignored: selected DNS profile '\(profileID)' was not found.")
                isTogglingSelectedProfile = false
                return
            }

            DNSManager.shared.setDNSProfile(profile.profileSnapshot) { [weak self] success in
                Task { @MainActor in
                    if success {
                        self?.markProfile(profileID, enabled: true, context: context)
                    }
                    self?.isTogglingSelectedProfile = false
                }
            }
        } else {
            DNSManager.shared.disableDNS(profileID: profileID) { [weak self] success in
                Task { @MainActor in
                    if success {
                        self?.markProfile(profileID, enabled: false, context: context)
                    }
                    self?.isTogglingSelectedProfile = false
                }
            }
        }
    }

    private func markProfile(_ profileID: String, enabled: Bool, context: ModelContext) {
        guard let settings = currentSettings() else { return }

        settings.isCloudflareEnabled = false
        settings.isQuad9Enabled = false
        settings.isAdGuardEnabled = false
        settings.activeGetFlixLocation = nil
        settings.selectedCustomDNSID = profileID
        settings.activeCustomDNSID = enabled ? profileID : nil
        settings.isSelectedProfileEnabled = enabled
        settings.timestamp = Date()
        try? context.save()
        updateStatusIcon(isEnabled: enabled)
        NotificationCenter.default.post(name: .dnsSettingsDidChange, object: nil, userInfo: ["isEnabled": enabled])
    }

    private func updateStatusIcon(isEnabled: Bool) {
        let symbolName = DNSStatusIconPolicy.symbolName(isEnabled: isEnabled)
        let description = isEnabled ? "DNS enabled" : "DNS Switcher"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    private func currentSettings() -> DNSSettings? {
        guard let modelContainer else { return nil }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<DNSSettings>(sortBy: [SortDescriptor(\.timestamp)])

        if let settings = try? context.fetch(descriptor).first {
            if settings.selectedCustomDNSID == nil, let activeCustomDNSID = settings.activeCustomDNSID {
                settings.selectedCustomDNSID = activeCustomDNSID
                settings.isSelectedProfileEnabled = true
                try? context.save()
            }
            return settings
        }

        let settings = DNSSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    private func fetchProfile(id: String, context: ModelContext) -> CustomDNSServer? {
        let descriptor = FetchDescriptor<CustomDNSServer>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor))?.first { $0.id == id }
    }
}
