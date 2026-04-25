//
//  EditCustomDNSView.swift
//  DNS Easy Switcher
//
//  Created by Gregory LINFORD on 25/02/2025.
//

import SwiftUI

struct EditCustomDNSView: View {
    let server: CustomDNSServer
    var onComplete: (CustomDNSServer?) -> Void
    
    @State private var name: String
    @State private var primaryIPv4: String
    @State private var secondaryIPv4: String
    @State private var dnsOverHttps: String
    @State private var validationErrors: [DNSProfileValidationError] = []
    
    init(server: CustomDNSServer, onComplete: @escaping (CustomDNSServer?) -> Void) {
        self.server = server
        self.onComplete = onComplete
        _name = State(initialValue: server.name)
        _primaryIPv4 = State(initialValue: server.primaryIPv4)
        _secondaryIPv4 = State(initialValue: server.secondaryIPv4)
        _dnsOverHttps = State(initialValue: server.dnsOverHttps)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name (e.g. Work DNS)", text: $name)
                .textFieldStyle(.roundedBorder)
            
            TextField("Primary IPv4 (e.g. 8.8.8.8)", text: $primaryIPv4)
                .textFieldStyle(.roundedBorder)
                .help("Enter a plain IPv4 address.")

            TextField("Secondary IPv4 (e.g. 8.8.4.4)", text: $secondaryIPv4)
                .textFieldStyle(.roundedBorder)
                .help("Enter a plain IPv4 address.")

            TextField("DNS-over-HTTPS URL (e.g. https://dns.google/dns-query)", text: $dnsOverHttps)
                .textFieldStyle(.roundedBorder)
                .help("Enter an HTTPS URL for this profile's DoH resolver.")

            if !validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationErrors.map(\.localizedDescription), id: \.self) { message in
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            HStack {
                Button("Cancel") {
                    onComplete(nil)
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") {
                    let snapshot = DNSProfileSnapshot(
                        id: server.id,
                        name: name,
                        primaryIPv4: primaryIPv4,
                        secondaryIPv4: secondaryIPv4,
                        dnsOverHttps: dnsOverHttps
                    )
                    let errors = DNSProfileValidator.validationErrors(for: snapshot)
                    validationErrors = errors
                    guard errors.isEmpty else { return }

                    let normalized = DNSProfileValidator.normalized(snapshot)
                    let updatedServer = CustomDNSServer(
                        id: server.id,
                        name: normalized.name,
                        primaryIPv4: normalized.primaryIPv4,
                        secondaryIPv4: normalized.secondaryIPv4,
                        dnsOverHttps: normalized.dnsOverHttps,
                        timestamp: server.timestamp
                    )
                    onComplete(updatedServer)
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 420)
    }
}
