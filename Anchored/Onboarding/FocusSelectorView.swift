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
                        .fill(PirateTheme.gold.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "anchor")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(PirateTheme.gold)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: "Focus Vessels",
                        font: .system(size: 36, weight: .bold, design: .serif),
                        colors: [PirateTheme.gold, PirateTheme.parchment]
                    )
                    
                    Text("Only selected applications count as active voyages. Neutral and background apps won't accumulate focus progress, keeping your journey steady.")
                        .font(.system(size: 14, design: .serif))
                        .foregroundColor(PirateTheme.parchment.opacity(0.8))
                        .lineSpacing(4)
                }
                
                // Add Custom App button
                Button(action: {
                    AudioEngine.shared.play(.tick)
                    selectCustomApp()
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Commission Custom Vessel...")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundColor(PirateTheme.gold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(PirateTheme.gold.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(PirateTheme.gold.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
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
                            Text("Secure the Rigging")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundColor(PirateTheme.darkWood)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                        .shadow(color: PirateTheme.gold.opacity(0.3), radius: 10, x: 0, y: 5)
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
                        Text("ACTIVE FOCUS VESSELS")
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundColor(PirateTheme.gold.opacity(0.8))
                            .tracking(1.0)
                        
                        if focusApps.isEmpty {
                            Text("No focus vessels chartered. Select recommendations below or commission a custom app.")
                                .font(.system(size: 12, design: .serif))
                                .foregroundColor(PirateTheme.parchment.opacity(0.6))
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(PirateTheme.darkWood.opacity(0.3))
                                .cornerRadius(10)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(focusApps, id: \.self) { bundleID in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(PirateTheme.gold)
                                            .font(.system(size: 13))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(getAppName(for: bundleID))
                                                .font(.system(size: 12, weight: .bold, design: .serif))
                                                .foregroundColor(PirateTheme.parchment)
                                            Text(bundleID)
                                                .font(.system(size: 9))
                                                .foregroundColor(PirateTheme.parchment.opacity(0.5))
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
                                    .background(PirateTheme.darkWood.opacity(0.4))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(PirateTheme.gold.opacity(0.15), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    
                    // Scanned Installed Recommendations
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SUGGESTED VESSELS (INSTALLED)")
                                .font(.system(size: 11, weight: .bold, design: .serif))
                                .foregroundColor(PirateTheme.gold.opacity(0.8))
                                .tracking(1.0)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(suggestions, id: \.bundleID) { bundleID, name in
                                    Button(action: {
                                        AudioEngine.shared.play(.tick)
                                        addApp(bundleID)
                                    }) {
                                        HStack {
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(PirateTheme.gold)
                                                .font(.system(size: 13))
                                            
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(name)
                                                    .font(.system(size: 12, weight: .semibold, design: .serif))
                                                    .foregroundColor(PirateTheme.parchment)
                                                Text(bundleID)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(PirateTheme.parchment.opacity(0.5))
                                                    .lineLimit(1)
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(PirateTheme.gold.opacity(0.05))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(PirateTheme.gold.opacity(0.2), lineWidth: 1)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
