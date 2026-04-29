//
//  DNSManager.swift
//  DNS Easy Switcher
//
//  Created by Gregory LINFORD on 23/02/2025.
//

import Foundation

class DNSManager {
    static let shared = DNSManager()
    private let privilegedHelper = PrivilegedHelperManager.shared
    
    let cloudflareServers = [
        "1.1.1.1",           // IPv4 Primary
        "1.0.0.1",           // IPv4 Secondary
        "2606:4700:4700::1111",  // IPv6 Primary
        "2606:4700:4700::1001"   // IPv6 Secondary
    ]
    
    let quad9Servers = [
        "9.9.9.9",              // IPv4 Primary
        "149.112.112.112",      // IPv4 Secondary
        "2620:fe::fe",          // IPv6 Primary
        "2620:fe::9"            // IPv6 Secondary
    ]
    
    let adguardServers = [
        "94.140.14.14",       // IPv4 Primary
        "94.140.15.15",       // IPv4 Secondary
        "2a10:50c0::ad1:ff",  // IPv6 Primary
        "2a10:50c0::ad2:ff"   // IPv6 Secondary
    ]
    
    let getflixServers: [String: String] = [
        "Australia — Melbourne": "118.127.62.178",
        "Australia — Perth": "45.248.78.99",
        "Australia — Sydney 1": "54.252.183.4",
        "Australia — Sydney 2": "54.252.183.5",
        "Brazil — São Paulo": "54.94.175.250",
        "Canada — Toronto": "169.53.182.124",
        "Denmark — Copenhagen": "82.103.129.240",
        "Germany — Frankfurt": "54.93.169.181",
        "Great Britain — London": "212.71.249.225",
        "Hong Kong": "119.9.73.44",
        "India — Mumbai": "103.13.112.251",
        "Ireland — Dublin": "54.72.70.84",
        "Italy — Milan": "95.141.39.238",
        "Japan — Tokyo": "172.104.90.123",
        "Netherlands — Amsterdam": "46.166.189.67",
        "New Zealand — Auckland 1": "120.138.27.84",
        "New Zealand — Auckland 2": "120.138.22.174",
        "Singapore": "54.251.190.247",
        "South Africa — Johannesburg": "102.130.116.140",
        "Spain — Madrid": "185.93.3.168",
        "Sweden — Stockholm": "46.246.29.68",
        "Turkey — Istanbul": "212.68.53.190",
        "United States — Dallas (Central)": "169.55.51.86",
        "United States — Oregon (West)": "54.187.61.200",
        "United States — Virginia (East)": "54.164.176.2"
    ]
    
    private func getNetworkServices() -> [String] {
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-listallnetworkservices"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let services = String(data: data, encoding: .utf8) {
                return services.components(separatedBy: .newlines)
                    .dropFirst() // Drop the header line
                    .filter { !$0.isEmpty && !$0.hasPrefix("*") } // Remove empty lines and disabled services
            }
        } catch {
            print("Error getting network services: \(error)")
        }
        return []
    }
    
    private func findActiveServices() -> [String] {
        let services = getNetworkServices()
        let activeServices = services.filter {
            $0.lowercased().contains("wi-fi") || $0.lowercased().contains("ethernet")
        }
        return activeServices.isEmpty ? [services.first].compactMap { $0 } : activeServices
    }
    
    var privilegedHelperStatusSnapshot: PrivilegedHelperStatusSnapshot {
        privilegedHelper.statusSnapshot
    }

    func preparePrivilegedHelperAtLaunch() {
        privilegedHelper.prepareAtLaunch()
    }

    func installPrivilegedHelper(completion: @escaping (Bool, String) -> Void) {
        privilegedHelper.register(completion: completion)
    }

    func openPrivilegedHelperApprovalSettings() {
        privilegedHelper.openSystemSettingsForApproval()
    }

    func setPredefinedDNS(dnsServers: [String], completion: @escaping (Bool) -> Void) {
        let services = findActiveServices()
        guard !services.isEmpty else {
            completion(false)
            return
        }

        setStandardDNS(services: services, servers: dnsServers, completion: completion)
    }
        
    func setCustomDNS(servers rawServers: [String], completion: @escaping (Bool) -> Void) {
        let services = findActiveServices()
        // Allow comma-separated entries in any slot
        let flattenedServers = rawServers
            .flatMap { entry in
                entry
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .filter { !$0.isEmpty }
        let parsedServers = flattenedServers.compactMap(parseDNSServer)
        
        guard !services.isEmpty, !parsedServers.isEmpty else {
            completion(false)
            return
        }
        
        let hasCustomPorts = parsedServers.contains { $0.port != nil }
        
        // If no custom ports are specified, use the standard network setup method
        if !hasCustomPorts {
            let servers = parsedServers.map { $0.address }
            setStandardDNS(services: services, servers: servers, completion: completion)
            return
        }
        
        // For DNS servers with custom ports, we need to modify the resolver configuration
        let resolverContent = createResolverContent(parsedServers)
        
        privilegedHelper.writeCustomResolver(content: resolverContent) { result in
            if result.succeeded {
                let standardServers = parsedServers.map { $0.address }
                self.setStandardDNS(services: services, servers: standardServers, completion: completion)
                return
            }

            guard result.isUnavailable else {
                print("Failed to write resolver configuration: \(result.message ?? "Unknown error")")
                completion(false)
                return
            }

            print("Privileged helper is required to write resolver configuration: \(result.message ?? "Unknown error")")
            completion(false)
        }
    }

    func setDNSProfile(_ profile: DNSProfileSnapshot, completion: @escaping (Bool) -> Void) {
        let normalized = DNSProfileValidator.normalized(profile)
        let errors = DNSProfileValidator.validationErrors(for: normalized, requireDNSOverHTTPS: false)
        guard errors.isEmpty else {
            print("DNS profile '\(profile.name)' was not applied: \(errors.map(\.localizedDescription).joined(separator: " "))")
            completion(false)
            return
        }

        if normalized.dnsOverHttps.isEmpty {
            print("DNS-over-HTTPS is not configured for profile '\(normalized.name)'. Applying IPv4 DNS only.")
        } else {
            print("DNS-over-HTTPS URL '\(normalized.dnsOverHttps)' is stored with profile '\(normalized.name)', but this app currently applies system DNS through networksetup, which does not configure encrypted DNS profiles. Applying IPv4 DNS only.")
        }

        let services = findActiveServices()
        guard !services.isEmpty else {
            completion(false)
            return
        }

        setStandardDNS(services: services, servers: [normalized.primaryIPv4, normalized.secondaryIPv4], completion: completion)
    }

    private func createResolverContent(_ servers: [(address: String, port: Int?)]) -> String {
        var resolverContent = "# Custom DNS configuration with port\n"
        
        for server in servers {
            resolverContent += "nameserver \(server.address)\n"
            if let port = server.port {
                resolverContent += "port \(port)\n"
            }
        }
        
        return resolverContent
    }

    private func parseDNSServer(_ input: String) -> (address: String, port: Int?)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Support IPv6 with explicit port using bracket notation: [addr]:port
        if trimmed.hasPrefix("["), let closingBracket = trimmed.firstIndex(of: "]") {
            let address = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingBracket])
            let remainder = trimmed[trimmed.index(after: closingBracket)..<trimmed.endIndex]
            if remainder.hasPrefix(":") {
                let portString = remainder.dropFirst()
                if let port = Int(portString) {
                    return (address, port)
                }
            }
            return (address, nil)
        }
        
        // IPv4 with port (single colon, numeric suffix)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2,
           let port = Int(parts[1]),
           !parts[0].contains(":") {
            return (String(parts[0]), port)
        }
        
        // IPv6 or plain address with no port
        return (trimmed, nil)
    }

    func disableDNS(profileID: String? = nil, completion: @escaping (Bool) -> Void) {
        let services = findActiveServices()
        guard !services.isEmpty else {
            completion(false)
            return
        }
        
        privilegedHelper.resetDNS(services: services) { result in
            if result.succeeded {
                completion(true)
                return
            }

            guard result.isUnavailable else {
                print("Failed to disable DNS through privileged helper: \(result.message ?? "Unknown error")")
                completion(false)
                return
            }

            print("Privileged helper is required to disable DNS without repeated administrator prompts: \(result.message ?? "Unknown error")")
            completion(false)
        }
    }

    // Helper method to set standard DNS settings
    private func setStandardDNS(services: [String], servers: [String], completion: @escaping (Bool) -> Void) {
        let cleanedServers = servers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedServers.isEmpty else {
            completion(false)
            return
        }

        privilegedHelper.setDNS(servers: cleanedServers, services: services) { result in
            if result.succeeded {
                completion(true)
                return
            }

            guard result.isUnavailable else {
                print("Failed to set DNS through privileged helper: \(result.message ?? "Unknown error")")
                completion(false)
                return
            }

            print("Privileged helper is required to set DNS without repeated administrator prompts: \(result.message ?? "Unknown error")")
            completion(false)
        }
    }

    func clearDNSCache(completion: @escaping (Bool) -> Void) {
        privilegedHelper.clearDNSCache { result in
            if result.succeeded {
                completion(true)
                return
            }

            guard result.isUnavailable else {
                print("Failed to clear DNS cache through privileged helper: \(result.message ?? "Unknown error")")
                completion(false)
                return
            }

            print("Privileged helper is required to clear DNS cache without repeated administrator prompts: \(result.message ?? "Unknown error")")
            completion(false)
        }
    }
}
