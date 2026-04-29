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
    var isBusy: Bool = false
    var actionTitle: String? = nil
}

private enum PrivilegedHelperRuntimeState: Equatable {
    case idle
    case registering
    case checking
    case repairing
    case ready
    case unavailable(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .registering, .checking, .repairing:
            return true
        case .idle, .ready, .unavailable:
            return false
        }
    }
}

final class PrivilegedHelperManager {
    static let shared = PrivilegedHelperManager()

    static let plistName = "com.linfordsoftware.dnseasyswitcher.helper.plist"
    static let machServiceName = "com.linfordsoftware.dnseasyswitcher.helper"
    static let operationTimeout = PrivilegedHelperOperationTimeoutPolicy.defaultTimeout

    private let service = SMAppService.daemon(plistName: PrivilegedHelperManager.plistName)
    private let registrationQueue = DispatchQueue(label: "com.linfordsoftware.dnseasyswitcher.helper.registration")
    private let runtimeLock = NSLock()
    private var runtimeState: PrivilegedHelperRuntimeState = .idle
    private var didStartAutomaticPreparation = false
    private var isRegistrationInProgress = false
    private var isRepairingRegistration = false

    private init() {}

    var statusSnapshot: PrivilegedHelperStatusSnapshot {
        let runtimeState = currentRuntimeState()

        switch runtimeState {
        case .registering:
            return PrivilegedHelperStatusSnapshot(
                title: "Installing privileged helper",
                detail: "macOS is registering the helper. Approve it if System Settings asks.",
                isEnabled: false,
                requiresApproval: false,
                isBusy: true
            )
        case .checking:
            return PrivilegedHelperStatusSnapshot(
                title: "Checking privileged helper",
                detail: "Verifying that the installed helper can answer XPC requests.",
                isEnabled: false,
                requiresApproval: false,
                isBusy: true
            )
        case .repairing:
            return PrivilegedHelperStatusSnapshot(
                title: "Repairing privileged helper",
                detail: "The registered helper did not answer, so the app is re-registering it.",
                isEnabled: false,
                requiresApproval: false,
                isBusy: true
            )
        case .ready:
            if serviceIsEnabled {
                return PrivilegedHelperStatusSnapshot(
                    title: "Privileged helper ready",
                    detail: "DNS changes will run without repeated administrator prompts.",
                    isEnabled: true,
                    requiresApproval: false
                )
            }
        case .unavailable(let message):
            if serviceIsEnabled {
                return PrivilegedHelperStatusSnapshot(
                    title: "Privileged helper not responding",
                    detail: message,
                    isEnabled: false,
                    requiresApproval: false,
                    actionTitle: "Repair Helper"
                )
            }
        case .idle:
            break
        }

        switch service.status {
        case .enabled:
            return PrivilegedHelperStatusSnapshot(
                title: "Privileged helper installed",
                detail: "Waiting for the launch check to verify the helper before DNS changes are enabled.",
                isEnabled: false,
                requiresApproval: false
            )
        case .requiresApproval:
            return PrivilegedHelperStatusSnapshot(
                title: "Privileged helper needs approval",
                detail: "Approve DNS Easy Switcher in System Settings. After approval, DNS changes run without repeated prompts.",
                isEnabled: false,
                requiresApproval: true,
                actionTitle: "Open System Settings"
            )
        case .notRegistered:
            return PrivilegedHelperStatusSnapshot(
                title: "Privileged helper not installed",
                detail: "The app will install it once at launch so DNS changes do not ask every time.",
                isEnabled: false,
                requiresApproval: false,
                actionTitle: "Install Helper"
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

    private var serviceIsEnabled: Bool {
        if case .enabled = service.status { return true }
        return false
    }

    private func currentRuntimeState() -> PrivilegedHelperRuntimeState {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        return runtimeState
    }

    private func setRuntimeState(_ state: PrivilegedHelperRuntimeState) {
        runtimeLock.lock()
        let didChange = runtimeState != state
        runtimeState = state
        runtimeLock.unlock()

        if didChange {
            notifyStatusChanged()
        }
    }

    private func markAutomaticPreparationStartedIfNeeded() -> Bool {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }

        guard PrivilegedHelperReadinessPolicy.shouldStartAutomaticPreparation(
            hasAlreadyStarted: didStartAutomaticPreparation
        ) else {
            return false
        }

        didStartAutomaticPreparation = true
        return true
    }

    private func beginRegistrationIfNeeded() -> Bool {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }

        guard !isRegistrationInProgress else { return false }
        isRegistrationInProgress = true
        return true
    }

    private func endRegistration() {
        runtimeLock.lock()
        isRegistrationInProgress = false
        runtimeLock.unlock()
    }

    func prepareAtLaunch() {
        guard markAutomaticPreparationStartedIfNeeded() else {
            refreshAfterExternalStatusChange()
            return
        }

        let snapshot = statusSnapshot
        let launchState = PrivilegedHelperLaunchState(
            isEnabled: serviceIsEnabled,
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

        register(openApprovalIfRequired: true) { success, message in
            if !success {
                print("Privileged helper was not registered at launch: \(message)")
            }
        }
    }

    private func verifyEnabledHelperAtLaunch() {
        verifyEnabledHelper { [weak self] result in
            guard let self else { return }
            if result.succeeded {
                return
            }

            print("Privileged helper health check failed at launch: \(result.message ?? "Unknown error")")
            repairRegistrationAfterHealthCheck()
        }
    }

    private func repairRegistrationAfterHealthCheck() {
        registrationQueue.async {
            guard !self.isRepairingRegistration else { return }
            self.isRepairingRegistration = true
            self.setRuntimeState(.repairing)
            defer { self.isRepairingRegistration = false }

            do {
                try self.service.unregister()
            } catch {
                print("Privileged helper unregister during repair failed: \(error.localizedDescription)")
            }

            do {
                try self.service.register()
            } catch {
                let message = error.localizedDescription
                self.setRuntimeState(.unavailable(message))
                print("Privileged helper repair registration failed: \(message)")
                return
            }

            switch self.service.status {
            case .enabled:
                self.verifyEnabledHelper { result in
                    if !result.succeeded {
                        let message = result.message ?? "The privileged helper did not respond after repair."
                        self.setRuntimeState(.unavailable(message))
                        print("Privileged helper repair health check failed: \(message)")
                    }
                }
            case .requiresApproval:
                self.setRuntimeState(.idle)
                DispatchQueue.main.async {
                    self.openSystemSettingsForApproval()
                }
            default:
                self.setRuntimeState(.unavailable(self.statusSnapshot.detail))
            }
        }
    }

    func register(completion: @escaping (Bool, String) -> Void) {
        register(openApprovalIfRequired: true, completion: completion)
    }

    func refreshAfterExternalStatusChange() {
        switch service.status {
        case .enabled:
            let state = currentRuntimeState()
            if state == .idle {
                verifyEnabledHelper { _ in }
            }
        case .requiresApproval, .notRegistered, .notFound:
            if currentRuntimeState() != .idle {
                setRuntimeState(.idle)
            }
        @unknown default:
            break
        }
    }

    private func register(openApprovalIfRequired: Bool, completion: @escaping (Bool, String) -> Void) {
        registrationQueue.async {
            if self.serviceIsEnabled {
                self.verifyEnabledHelper { result in
                    if result.succeeded {
                        completion(true, self.statusSnapshot.detail)
                    } else {
                        self.repairRegistrationAfterHealthCheck()
                        completion(false, result.message ?? self.statusSnapshot.detail)
                    }
                }
                return
            }

            guard self.beginRegistrationIfNeeded() else {
                DispatchQueue.main.async {
                    completion(false, "Privileged helper registration is already in progress.")
                }
                return
            }

            self.setRuntimeState(.registering)
            defer { self.endRegistration() }

            do {
                try self.service.register()
            } catch {
                let message = error.localizedDescription
                self.setRuntimeState(.unavailable(message))
                DispatchQueue.main.async {
                    completion(false, message)
                }
                return
            }

            switch self.service.status {
            case .enabled:
                self.verifyEnabledHelper { result in
                    completion(result.succeeded, result.message ?? self.statusSnapshot.detail)
                }
            case .requiresApproval:
                self.setRuntimeState(.idle)
                if openApprovalIfRequired {
                    DispatchQueue.main.async {
                        self.openSystemSettingsForApproval()
                    }
                }
                DispatchQueue.main.async {
                    completion(false, self.statusSnapshot.detail)
                }
            default:
                self.setRuntimeState(.idle)
                DispatchQueue.main.async {
                    completion(false, self.statusSnapshot.detail)
                }
            }
        }
    }

    private func verifyEnabledHelper(completion: @escaping (PrivilegedHelperCommandResult) -> Void) {
        guard serviceIsEnabled else {
            setRuntimeState(.idle)
            DispatchQueue.main.async {
                completion(.unavailable(self.statusSnapshot.detail))
            }
            return
        }

        setRuntimeState(.checking)
        helperVersion { [weak self] result in
            guard let self else { return }

            if result.succeeded {
                self.setRuntimeState(.ready)
            } else {
                self.setRuntimeState(.unavailable(result.message ?? "The privileged helper did not respond."))
            }

            completion(result)
        }
    }

    func openSystemSettingsForApproval() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func helperVersion(completion: @escaping (PrivilegedHelperCommandResult) -> Void) {
        withHelperProxy(requireReady: false) { proxy, finish in
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
        requireReady: Bool = true,
        operation: @escaping (PrivilegedDNSHelperProtocol, @escaping (PrivilegedHelperCommandResult) -> Void) -> Void,
        completion: @escaping (PrivilegedHelperCommandResult) -> Void
    ) {
        guard serviceIsEnabled else {
            completion(.unavailable(statusSnapshot.detail))
            return
        }

        if requireReady, !PrivilegedHelperReadinessPolicy.canRunDNSMutation(
            isServiceEnabled: true,
            isXPCVerified: currentRuntimeState().isReady
        ) {
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
