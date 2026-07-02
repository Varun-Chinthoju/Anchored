import SwiftUI
import AppKit

struct FocusSelectorView: View {
    let onNext: (() -> Void)?
    let showContinueButton: Bool
    
    init(onNext: (() -> Void)? = nil, showContinueButton: Bool = true) {
        self.onNext = onNext
        self.showContinueButton = showContinueButton
    }
    
    @State private var focusManager = FocusListManager.shared
    @State private var focusApps: [String] = []
    @State private var suggestions: [(bundleID: String, name: String)] = []
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Setup Details)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "target")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: "Focus Apps",
                        font: .system(size: 36, weight: .bold, design: .rounded),
                        colors: [.green, .emeraldGreen]
                    )
                    
                    Text("Only the selected applications will accumulate focus progress. Secondary/neutral apps won't build focus, resolving window switching assumptions.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                
                // Add Custom App button
                Button(action: {
                    AudioEngine.shared.play(.tick)
                    selectCustomApp()
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Custom Application...")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                
                Spacer()
                
                if showContinueButton {
                    Button(action: {
                        AudioEngine.shared.play(.tick)
                        onNext?()
                    }) {
                        HStack {
                            Text("Continue")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 320, alignment: .leading)
            
            // Right Column (Lists of Apps)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Active Focus Apps Grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACTIVE FOCUS APPS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(1.0)
                        
                        if focusApps.isEmpty {
                            Text("No focus apps selected. Select suggestions below or add a custom app.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color.primary.opacity(0.02))
                                .cornerRadius(10)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(focusApps, id: \.self) { bundleID in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 13))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(getAppName(for: bundleID))
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.primary)
                                            Text(bundleID)
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            AudioEngine.shared.play(.tick)
                                            removeApp(bundleID)
                                        }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.primary.opacity(0.02))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    
                    // Scanned Installed Recommendations
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SUGGESTED PRODUCTIVITY TOOLS (INSTALLED)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(1.0)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(suggestions, id: \.bundleID) { bundleID, name in
                                    Button(action: {
                                        AudioEngine.shared.play(.tick)
                                        addApp(bundleID)
                                    }) {
                                        HStack {
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(.accentColor)
                                                .font(.system(size: 13))
                                            
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(name)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                Text(bundleID)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.accentColor.opacity(0.04))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshLists()
        }
    }
    
    private func refreshLists() {
        focusApps = focusManager.allFocusApps
        suggestions = focusManager.installedSuggestions
    }
    
    private func addApp(_ bundleID: String) {
        focusManager.add(bundleID)
        refreshLists()
    }
    
    private func removeApp(_ bundleID: String) {
        focusManager.remove(bundleID)
        refreshLists()
    }
    
    private func selectCustomApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                addApp(bundleID)
            } else {
                let infoPath = url.appendingPathComponent("Contents/Info.plist")
                if let dict = NSDictionary(contentsOf: infoPath),
                   let bundleID = dict["CFBundleIdentifier"] as? String {
                    addApp(bundleID)
                }
            }
        }
    }
    
    private func getAppName(for bundleID: String) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return appURL.deletingPathExtension().lastPathComponent
        }
        return bundleID.split(separator: ".").last.map(String.init)?.capitalized ?? bundleID
    }
}

extension Color {
    static let emeraldGreen = Color(red: 0.1, green: 0.8, blue: 0.5)
}
