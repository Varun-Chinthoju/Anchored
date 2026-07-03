import SwiftUI
import AppKit

struct DistractionSelectorView: View {
    let windowHeight: CGFloat
    let onNext: (() -> Void)?
    let showContinueButton: Bool
    
    init(windowHeight: CGFloat, onNext: (() -> Void)? = nil, showContinueButton: Bool = true) {
        self.windowHeight = windowHeight
        self.onNext = onNext
        self.showContinueButton = showContinueButton
    }
    
    @State private var distractionManager = DistractionListManager.shared
    @State private var distractions: [String] = []
    @ObservedObject private var langManager = LanguageManager.shared
    
    // Mapping of popular distraction bundle IDs to display names and SF icons
    private let defaultApps = [
        ("com.hnc.Discord", "Discord", "bubble.left.and.bubble.right"),
        ("com.tinyspeck.slackmacgap", "Slack", "message"),
        ("ru.keepcoder.Telegram", "Telegram", "paperplane"),
        ("com.apple.MobileSMS", "Messages", "message.fill"),
        ("com.spotify.client", "Spotify", "music.note"),
        ("com.apple.Music", "Music", "music.note.list"),
        ("com.atebits.Tweetie2", "Twitter/X", "arrow.up.right.video"),
        ("com.valvesoftware.steam", "Steam", "gamecontroller")
    ]
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Details)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(PirateTheme.gold.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    SafeSystemImage(systemName: "hand.raised.fill", size: 32)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: t("dist_title"),
                        font: .system(size: 36, weight: .bold, design: .serif),
                        colors: [PirateTheme.gold, PirateTheme.parchment]
                    )
                    
                    Text(t("dist_desc"))
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
                        Text(t("dist_custom_btn"))
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
                            Text(t("dist_btn"))
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
            
            // Right Column (Apps selection)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Default Distraction Grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("dist_active_title"))
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundColor(PirateTheme.gold.opacity(0.8))
                            .tracking(1.0)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(defaultApps, id: \.0) { bundleID, name, icon in
                                let isSelected = distractions.contains(bundleID)
                                
                                Button(action: {
                                    AudioEngine.shared.play(.tick)
                                    toggleApp(bundleID)
                                }) {
                                    HStack {
                                        SafeSystemImage(systemName: icon, size: 14, color: isSelected ? PirateTheme.gold : PirateTheme.parchment.opacity(0.5))
                                        Text(name)
                                            .font(.system(size: 12, weight: .semibold, design: .serif))
                                            .foregroundColor(isSelected ? PirateTheme.gold : PirateTheme.parchment)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundColor(PirateTheme.gold)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? PirateTheme.gold.opacity(0.12) : PirateTheme.darkWood.opacity(0.4))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected ? PirateTheme.gold : PirateTheme.gold.opacity(0.15), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Added custom apps list
                    let customApps = distractions.filter { !defaultApps.map(\.0).contains($0) }
                    if !customApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(t("dist_active_title"))
                                .font(.system(size: 11, weight: .bold, design: .serif))
                                .foregroundColor(PirateTheme.gold.opacity(0.8))
                                .tracking(1.0)
                            
                            ForEach(customApps, id: \.self) { bundleID in
                                HStack {
                                    Text(getAppName(for: bundleID))
                                        .font(.system(size: 12, weight: .semibold, design: .serif))
                                        .foregroundColor(PirateTheme.parchment)
                                    Spacer()
                                    Text(bundleID)
                                        .font(.system(size: 10))
                                        .foregroundColor(PirateTheme.parchment.opacity(0.5))
                                    Button(action: {
                                        AudioEngine.shared.play(.tick)
                                        toggleApp(bundleID)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(PirateTheme.gold.opacity(0.8))
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
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(300, windowHeight - 280))
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            distractions = distractionManager.allDistractions
        }
    }
    
    private func toggleApp(_ bundleID: String) {
        if distractions.contains(bundleID) {
            distractionManager.remove(bundleID)
        } else {
            distractionManager.add(bundleID)
        }
        distractions = distractionManager.allDistractions
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
                distractionManager.add(bundleID)
                distractions = distractionManager.allDistractions
            } else {
                let infoPath = url.appendingPathComponent("Contents/Info.plist")
                if let dict = NSDictionary(contentsOf: infoPath),
                   let bundleID = dict["CFBundleIdentifier"] as? String {
                    distractionManager.add(bundleID)
                    distractions = distractionManager.allDistractions
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
