//
//  PrivilegedHelperManager.swift
//  DNS Easy Switcher
//

import Foundation
import ServiceManagement

extension Notification.Name {
    static let privilegedHelperStatusDidChange = Notification.Name("DNSEasySwitcherPrivilegedHelperStatusDidChange")
}

enum PrivilegedHelperCommandResult: Equatable {
    case success(String?)
    case unavailable(String)
    case failure(String)

    var succeeded: Bool {
        if case .success = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .success(let message):
            return message
        case .unavailable(let message), .failure(let message):
            return message
        }
    }
}

struct PrivilegedHelperStatusSnapshot: Equatable {
    var title: String
    var detail: String
    var isEnabled: Bool
    var requiresApproval: Bool
}

final class PrivilegedHelperManager {
    static let shared = PrivilegedHelperManager()

    static let plistName = "com.linfordsoftware.dnseasyswitcher.helper.plist"
    static let machServiceName = "com.linfordsoftware.dnseasyswitcher.helper"
    static let operationTimeout = PrivilegedHelperOperationTimeoutPolicy.defaultTimeout

    private let service = SMAppService.daemon(plistName: PrivilegedHelperManager.plistName)
    private let registrationQueue = DispatchQueue(label: "com.linfordsoftware.dnseasyswitcher.helper.registration")
    private var isRepairingRegistration = false

    private init() {}

    var statusSnapshot: PrivilegedHelperStatusSnapshot {
        switch service.status {
        case .enabled:
            return PrivilegedHelperStatusSnapshot(
                title: "Privileged helper installed",
                detail: "DNS changes will run without repeated administrator prompts.",
                isEnabled: true,
                requiresApproval: false
            )
        case .requiresApproval:
            return PrivilegedHelperStatusSnapshot(
                title: "Privileged helper needs approval",
                detail: "Approve DNS Easy Switcher in System Settings to stop repeated administrator prompts.",
                isEnabled: false,
                requiresApproval: true
            )
        case .notRegistered:
            return PrivilegedHelperStatusSnapshot(
                title: "Privileged helper not installed",
                detail: "Install it once to avoid administrator prompts on every DNS change.",
                isEnabled: false,
                requiresApproval: false
            )
        case .notFound:
            return PrivilegedHelperStatusSnapshot(
                title: "Privileged helper missing from app bundle",
                detail: "Rebuild or reinstall the app; the bundled helper executable was not found.",
                isEnabled: false,
                requiresApproval: false
            )
        @unknown default:
            return PrivilegedHelperStatusSnapshot(
                title: "Privileged helper status unknown",
                detail: "The current macOS version returned an unknown helper status.",
                isEnabled: false,
                requiresApproval: false
            )
        }
    }

    func prepareAtLaunch() {
        let snapshot = statusSnapshot
        let launchState = PrivilegedHelperLaunchState(
            isEnabled: snapshot.isEnabled,
            requiresApproval: snapshot.requiresApproval
        )

        switch PrivilegedHelperLaunchPolicy.action(for: launchState) {
        case .none:
            verifyEnabledHelperAtLaunch()
            return
        case .openApprovalSettings:
            notifyStatusChanged()
            openSystemSettingsForApproval()
            return
        case .register:
            break
        }

        register { success, message in
            let currentStatus = PrivilegedHelperLaunchState(
                isEnabled: self.statusSnapshot.isEnabled,
                requiresApproval: self.statusSnapshot.requiresApproval
            )
            if PrivilegedHelperLaunchPolicy.shouldOpenApprovalAfterRegistration(currentStatus) {
                self.openSystemSettingsForApproval()
            }

            if !success {
                print("Privileged helper was not registered at launch: \(message)")
            }
        }
    }

    private func verifyEnabledHelperAtLaunch() {
        helperVersion { [weak self] result in
            guard let self else { return }
            guard !result.succeeded else { return }

            print("Privileged helper health check failed at launch: \(result.message ?? "Unknown error")")
            repairRegistrationAfterHealthCheck()
        }
    }

    private func repairRegistrationAfterHealthCheck() {
        registrationQueue.async {
            guard !self.isRepairingRegistration else { return }
            self.isRepairingRegistration = true
            defer { self.isRepairingRegistration = false }

            do {
                try self.service.unregister()
            } catch {
                print("Privileged helper unregister during repair failed: \(error.localizedDescription)")
            }

            do {
                try self.service.register()
            } catch {
                print("Privileged helper repair registration failed: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .privilegedHelperStatusDidChange, object: nil)

                let snapshot = self.statusSnapshot
                if snapshot.requiresApproval || !snapshot.isEnabled {
                    self.openSystemSettingsForApproval()
                }
            }
        }
    }

    func register(completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.service.register()
                let snapshot = self.statusSnapshot
                let success = snapshot.isEnabled
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .privilegedHelperStatusDidChange, object: nil)
                    completion(success, snapshot.detail)
                }
            } catch {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .privilegedHelperStatusDidChange, object: nil)
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func openSystemSettingsForApproval() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func helperVersion(completion: @escaping (PrivilegedHelperCommandResult) -> Void) {
        withHelperProxy { proxy, finish in
            proxy.helperVersion { version in
                finish(.success(version))
            }
        } completion: {
            completion($0)
        }
    }

    func setDNS(servers: [String], services: [String], completion: @escaping (PrivilegedHelperCommandResult) -> Void) {
        withHelperProxy { proxy, finish in
            proxy.setDNS(servers: servers, forServices: services) { success, message in
                finish(success ? .success(message) : .failure(message ?? "The privileged helper failed to set DNS."))
            }
        } completion: {
            completion($0)
        }
    }

    func resetDNS(services: [String], completion: @escaping (PrivilegedHelperCommandResult) -> Void) {
        withHelperProxy { proxy, finish in
            proxy.resetDNS(forServices: services) { success, message in
                finish(success ? .success(message) : .failure(message ?? "The privileged helper failed to reset DNS."))
            }
        } completion: {
            completion($0)
        }
    }

    func writeCustomResolver(content: String, completion: @escaping (PrivilegedHelperCommandResult) -> Void) {
        withHelperProxy { proxy, finish in
            proxy.writeCustomResolver(content) { success, message in
                finish(success ? .success(message) : .failure(message ?? "The privileged helper failed to write resolver settings."))
            }
        } completion: {
            completion($0)
        }
    }

    func removeCustomResolver(completion: @escaping (PrivilegedHelperCommandResult) -> Void) {
        withHelperProxy { proxy, finish in
            proxy.removeCustomResolver { success, message in
                finish(success ? .success(message) : .failure(message ?? "The privileged helper failed to remove resolver settings."))
            }
        } completion: {
            completion($0)
        }
    }

    func clearDNSCache(completion: @escaping (PrivilegedHelperCommandResult) -> Void) {
        withHelperProxy { proxy, finish in
            proxy.clearDNSCache { success, message in
                finish(success ? .success(message) : .failure(message ?? "The privileged helper failed to clear DNS cache."))
            }
        } completion: {
            completion($0)
        }
    }

    private func withHelperProxy(
        operation: @escaping (PrivilegedDNSHelperProtocol, @escaping (PrivilegedHelperCommandResult) -> Void) -> Void,
        completion: @escaping (PrivilegedHelperCommandResult) -> Void
    ) {
        guard statusSnapshot.isEnabled else {
            completion(.unavailable(statusSnapshot.detail))
            return
        }

        let connection = NSXPCConnection(
            machServiceName: Self.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedDNSHelperProtocol.self)

        let finishQueue = DispatchQueue(label: "com.linfordsoftware.dnseasyswitcher.helper.finish")
        var didComplete = false
        var timeoutWorkItem: DispatchWorkItem?
        let finish: (PrivilegedHelperCommandResult) -> Void = { result in
            finishQueue.async {
                guard !didComplete else { return }
                didComplete = true
                timeoutWorkItem?.cancel()
                connection.invalidate()
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }

        connection.invalidationHandler = {
            finish(.unavailable("Could not connect to the privileged helper."))
        }
        connection.interruptionHandler = {
            finish(.unavailable("The privileged helper connection was interrupted."))
        }

        connection.resume()

        let workItem = DispatchWorkItem {
            finish(.unavailable("Timed out while waiting for the privileged helper."))
        }
        timeoutWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + Self.operationTimeout,
            execute: workItem
        )

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            finish(.unavailable(error.localizedDescription))
        }) as? PrivilegedDNSHelperProtocol else {
            finish(.unavailable("Could not create a privileged helper proxy."))
            return
        }

        operation(proxy, finish)
    }

    private func notifyStatusChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .privilegedHelperStatusDidChange, object: nil)
        }
    }
}
