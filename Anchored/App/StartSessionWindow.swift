import AppKit
import SwiftUI

class StartSessionWindow: NSWindow {
    
    init(focusEngine: FocusEngine) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 544, height: 544),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Plot Yer Voyage"
        self.isReleasedWhenClosed = false
        self.isOpaque = true
        self.hasShadow = true
        self.titlebarAppearsTransparent = true
        self.appearance = NSAppearance(named: .vibrantDark)
        self.minSize = NSSize(width: 544, height: 544)
        self.maxSize = NSSize(width: 544, height: 544)
        
        let view = StartSessionWindowFormView(focusEngine: focusEngine, window: self)
            .preferredColorScheme(.dark)
        self.contentView = NSHostingView(rootView: view)
        self.center()
    }
}

struct StartSessionWindowFormView: View {
    let focusEngine: FocusEngine
    weak var window: NSWindow?
    
    @ObservedObject private var profileManager = ProfileManager.shared
    
    @State private var minutes: Int = 25
    @State private var selectedProfileID: UUID
    @State private var goal: String = ""
    
    // Raycast-style Pirate Dark Theme Colors
    private let raycastBlack = Color(red: 0.07, green: 0.07, blue: 0.08)       // #121214
    private let raycastRowBg = Color(red: 0.11, green: 0.11, blue: 0.12)       // #1C1C1E
    private let raycastBorder = Color(red: 0.18, green: 0.18, blue: 0.20)      // #2E2E33
    private let goldColor = Color(red: 0.9, green: 0.75, blue: 0.3)            // #E5C158
    private let textPrimary = Color(red: 0.95, green: 0.95, blue: 0.96)        // #F2F2F7
    private let textSecondary = Color(red: 0.55, green: 0.55, blue: 0.6)       // #8E8E93
    
    init(focusEngine: FocusEngine, window: NSWindow?) {
        self.focusEngine = focusEngine
        self.window = window
        let activeProfile = ProfileManager.shared.activeProfile
        self._selectedProfileID = State(initialValue: activeProfile.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title & Search-style Goal Input
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("PLOT VOYAGE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(goldColor)
                        .tracking(1.5)
                    Spacer()
                }
                
                // Goal Text Field (Looks like Raycast Search input)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(goldColor)
                    
                    TextField("What is yer loot goal for this voyage, Cap'n?", text: $goal)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(textPrimary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(raycastRowBg)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(raycastBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
                .background(raycastBorder)
            
            // Configuration List Rows
            ScrollView {
                VStack(spacing: 16) {
                    // Duration Row
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Voyage Duration")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(textPrimary)
                            Spacer()
                            Text("\(minutes) Leagues (min)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(goldColor)
                        }
                        
                        // Presets
                        HStack(spacing: 8) {
                            ForEach([15, 25, 45, 60], id: \.self) { min in
                                Button(action: {
                                    minutes = min
                                }) {
                                    Text("\(min) Bells")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(minutes == min ? raycastBlack : textPrimary)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(minutes == min ? goldColor : raycastBlack.opacity(0.4))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(minutes == min ? Color.clear : raycastBorder, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Slider(value: Binding(
                            get: { Double(minutes) },
                            set: { minutes = Int($0) }
                        ), in: 5...120, step: 5)
                        .accentColor(goldColor)
                    }
                    .padding(16)
                    .background(raycastRowBg)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(raycastBorder, lineWidth: 1)
                    )
                    
                    // Profile Row
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active Flagship (Profile)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(textPrimary)
                        
                        Picker("", selection: $selectedProfileID) {
                            ForEach(profileManager.profiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                    .background(raycastRowBg)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(raycastBorder, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            
            Divider()
                .background(raycastBorder)
            
            // Raycast-style Action Bar at the bottom
            HStack {
                HStack(spacing: 4) {
                    Text("Tab")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(raycastRowBg)
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(raycastBorder, lineWidth: 1))
                    Text("to navigate")
                        .font(.system(size: 11))
                        .foregroundColor(textSecondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Cancel
                    Button(action: {
                        window?.close()
                    }) {
                        HStack(spacing: 4) {
                            Text("Esc")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(raycastRowBg)
                                .cornerRadius(3)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(raycastBorder, lineWidth: 1))
                            Text("Abandon")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(textSecondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)
                    
                    // Start
                    Button(action: {
                        let targetProfile = profileManager.profiles.first { $0.id == selectedProfileID }
                        let profileName = targetProfile?.name ?? profileManager.activeProfile.name
                        
                        if selectedProfileID != profileManager.activeProfile.id {
                            profileManager.switchProfile(to: profileName)
                        }
                        
                        let durationSeconds = TimeInterval(minutes * 60)
                        focusEngine.anchorSession(duration: durationSeconds, category: profileName, goal: goal.isEmpty ? nil : goal)
                        
                        window?.close()
                    }) {
                        HStack(spacing: 4) {
                            Text("↵")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(3)
                            Text("Set Sail")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(raycastBlack)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(goldColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(raycastBlack.opacity(0.5))
        }
        .frame(width: 544, height: 544)
        .background(raycastBlack)
    }
}
