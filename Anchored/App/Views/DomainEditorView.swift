import SwiftUI

struct DomainEditorView: View {
    @ObservedObject var profileManager: ProfileManager
    let profile: WorkProfile

    @State private var newDistractionDomain = ""
    @State private var newAllowedDomain = ""
    @State private var distractionError: String? = nil
    @State private var allowedError: String? = nil

    private var sortedDistractionDomains: [String] {
        profile.distractionDomains.sorted()
    }

    private var sortedAllowedDomains: [String] {
        profile.allowedDomains.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Distraction Domains Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Blocked Domains (Distractions)")
                    .font(.system(size: 13, weight: .bold))
                
                Text("Visiting these websites during a focus session under this profile will trigger the dimming overlay.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("Add domain (e.g. facebook.com)", text: $newDistractionDomain)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addDistractionDomain() }
                        .onChange(of: newDistractionDomain) { _ in distractionError = nil }
                        .frame(maxWidth: 300)
                    
                    Button("Add") {
                        addDistractionDomain()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if let error = distractionError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                
                if sortedDistractionDomains.isEmpty {
                    emptyState("No distraction domains added yet.")
                } else {
                    SettingsGroup {
                        ForEach(sortedDistractionDomains.indices, id: \.self) { i in
                            let domain = sortedDistractionDomains[i]
                            HStack {
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                                Text(domain)
                                    .font(.system(size: 13))
                                Spacer()
                                Button {
                                    removeDistractionDomain(domain)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            if i < sortedDistractionDomains.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 10)

            // Allowed Domains Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Allowed Domains")
                    .font(.system(size: 13, weight: .bold))
                
                Text("These websites will bypass the distraction warning or blocker and are always permitted.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("Add domain (e.g. github.com)", text: $newAllowedDomain)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addAllowedDomain() }
                        .onChange(of: newAllowedDomain) { _ in allowedError = nil }
                        .frame(maxWidth: 300)
                    
                    Button("Add") {
                        addAllowedDomain()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if let error = allowedError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                
                if sortedAllowedDomains.isEmpty {
                    emptyState("No allowed domains added yet.")
                } else {
                    SettingsGroup {
                        ForEach(sortedAllowedDomains.indices, id: \.self) { i in
                            let domain = sortedAllowedDomains[i]
                            HStack {
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                                Text(domain)
                                    .font(.system(size: 13))
                                Spacer()
                                Button {
                                    removeAllowedDomain(domain)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            if i < sortedAllowedDomains.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Validation Helpers

    private func isValidDomain(_ domain: String) -> Bool {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(".") else { return false }
        guard !trimmed.contains(" ") else { return false }
        guard !trimmed.hasPrefix(".") && !trimmed.hasSuffix(".") else { return false }
        return trimmed.count >= 3
    }

    // MARK: - Domain Management Operations

    private func addDistractionDomain() {
        let domain = newDistractionDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !domain.isEmpty else { return }

        if !isValidDomain(domain) {
            distractionError = "Invalid domain format (e.g. website.com)."
            return
        }

        if profile.distractionDomains.contains(domain) {
            distractionError = "Domain is already in the distraction list."
            return
        }

        if profile.allowedDomains.contains(domain) {
            distractionError = "Domain is already in the allowed list."
            return
        }

        distractionError = nil
        var updated = profile
        updated.distractionDomains.append(domain)
        profileManager.updateProfile(updated)
        newDistractionDomain = ""
    }

    private func removeDistractionDomain(_ domain: String) {
        var updated = profile
        updated.distractionDomains.removeAll { $0 == domain }
        profileManager.updateProfile(updated)
    }

    private func addAllowedDomain() {
        let domain = newAllowedDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !domain.isEmpty else { return }

        if !isValidDomain(domain) {
            allowedError = "Invalid domain format (e.g. website.com)."
            return
        }

        if profile.allowedDomains.contains(domain) {
            allowedError = "Domain is already in the allowed list."
            return
        }

        if profile.distractionDomains.contains(domain) {
            allowedError = "Domain is already in the distraction list."
            return
        }

        allowedError = nil
        var updated = profile
        updated.allowedDomains.append(domain)
        profileManager.updateProfile(updated)
        newAllowedDomain = ""
    }

    private func removeAllowedDomain(_ domain: String) {
        var updated = profile
        updated.allowedDomains.removeAll { $0 == domain }
        profileManager.updateProfile(updated)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}
