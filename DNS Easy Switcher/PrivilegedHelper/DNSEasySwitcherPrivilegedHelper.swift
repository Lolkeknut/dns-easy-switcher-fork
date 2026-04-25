//
//  DNSEasySwitcherPrivilegedHelper.swift
//  DNS Easy Switcher
//

import Foundation

private let helperMachServiceName = "com.linfordsoftware.dnseasyswitcher.helper"

final class PrivilegedDNSHelper: NSObject, PrivilegedDNSHelperProtocol {
    func helperVersion(withReply reply: @escaping (String) -> Void) {
        reply("1.0")
    }

    func setDNS(servers: [String], forServices services: [String], withReply reply: @escaping (Bool, String?) -> Void) {
        let cleanedServices = services.map(trimmed).filter { !$0.isEmpty }
        let cleanedServers = servers.map(trimmed).filter { !$0.isEmpty }

        guard !cleanedServices.isEmpty else {
            reply(false, "No active network services were found.")
            return
        }

        guard !cleanedServers.isEmpty else {
            reply(false, "No DNS servers were provided.")
            return
        }

        let result = applyToServices(cleanedServices) { service in
            [
                runNetworkSetup(["-setdnsservers", service] + cleanedServers),
                runNetworkSetup(["-setv6off", service]),
                runNetworkSetup(["-setv6automatic", service])
            ]
        }

        reply(result.success, result.message)
    }

    func resetDNS(forServices services: [String], withReply reply: @escaping (Bool, String?) -> Void) {
        let cleanedServices = services.map(trimmed).filter { !$0.isEmpty }

        guard !cleanedServices.isEmpty else {
            reply(false, "No active network services were found.")
            return
        }

        _ = removeResolverFile()

        let result = applyToServices(cleanedServices) { service in
            [runNetworkSetup(["-setdnsservers", service, "empty"])]
        }

        reply(result.success, result.message)
    }

    func writeCustomResolver(_ content: String, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            let resolverDirectory = URL(fileURLWithPath: "/etc/resolver", isDirectory: true)
            try FileManager.default.createDirectory(at: resolverDirectory, withIntermediateDirectories: true)

            let resolverURL = resolverDirectory.appendingPathComponent("custom")
            try content.write(to: resolverURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: resolverURL.path)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func removeCustomResolver(withReply reply: @escaping (Bool, String?) -> Void) {
        let result = removeResolverFile()
        reply(result.success, result.message)
    }

    func clearDNSCache(withReply reply: @escaping (Bool, String?) -> Void) {
        let results = [
            runProcess("/usr/bin/dscacheutil", ["-flushcache"]),
            runProcess("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        ]

        let failures = results.filter { !$0.success }
        if failures.isEmpty {
            reply(true, nil)
        } else {
            reply(false, failures.map { $0.message ?? "Unknown error" }.joined(separator: "\n"))
        }
    }

    private func applyToServices(
        _ services: [String],
        operations: (String) -> [CommandResult]
    ) -> (success: Bool, message: String?) {
        var failures: [String] = []

        for service in services {
            let results = operations(service)
            failures += results
                .filter { !$0.success }
                .map { "\(service): \($0.message ?? "Unknown error")" }
        }

        return failures.isEmpty ? (true, nil) : (false, failures.joined(separator: "\n"))
    }

    private func removeResolverFile() -> CommandResult {
        let path = "/etc/resolver/custom"
        guard FileManager.default.fileExists(atPath: path) else {
            return CommandResult(success: true, message: nil)
        }

        do {
            try FileManager.default.removeItem(atPath: path)
            return CommandResult(success: true, message: nil)
        } catch {
            return CommandResult(success: false, message: error.localizedDescription)
        }
    }

    private func runNetworkSetup(_ arguments: [String]) -> CommandResult {
        runProcess("/usr/sbin/networksetup", arguments)
    }

    private func runProcess(_ executablePath: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let message = [output, error]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            return CommandResult(
                success: process.terminationStatus == 0,
                message: message.isEmpty ? nil : message
            )
        } catch {
            return CommandResult(success: false, message: error.localizedDescription)
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CommandResult {
    var success: Bool
    var message: String?
}

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let helper = PrivilegedDNSHelper()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.setCodeSigningRequirement("identifier \"com.linfordsoftware.dnseasyswitcher\"")
        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedDNSHelperProtocol.self)
        newConnection.exportedObject = helper
        newConnection.resume()
        return true
    }
}

@main
struct DNSEasySwitcherPrivilegedHelperMain {
    static func main() {
        let delegate = HelperListenerDelegate()
        let listener = NSXPCListener(machServiceName: helperMachServiceName)
        listener.delegate = delegate
        listener.resume()
        RunLoop.main.run()
    }
}
