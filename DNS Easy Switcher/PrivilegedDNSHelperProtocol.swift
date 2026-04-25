//
//  PrivilegedDNSHelperProtocol.swift
//  DNS Easy Switcher
//

import Foundation

@objc(DNSEasySwitcherPrivilegedHelperProtocol)
protocol PrivilegedDNSHelperProtocol {
    func helperVersion(withReply reply: @escaping (String) -> Void)
    func setDNS(servers: [String], forServices services: [String], withReply reply: @escaping (Bool, String?) -> Void)
    func resetDNS(forServices services: [String], withReply reply: @escaping (Bool, String?) -> Void)
    func writeCustomResolver(_ content: String, withReply reply: @escaping (Bool, String?) -> Void)
    func removeCustomResolver(withReply reply: @escaping (Bool, String?) -> Void)
    func clearDNSCache(withReply reply: @escaping (Bool, String?) -> Void)
}

