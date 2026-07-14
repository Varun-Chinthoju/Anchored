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
        
        let themeAccent = PreferencesManager.shared.selectedThemePalette.accentColor
        let view = StartSessionWindowFormView(focusEngine: focusEngine, window: self)
            .preferredColorScheme(.dark)
            .accentColor(themeAccent)
            .tint(themeAccent)
        self.contentView = NSHostingView(rootView: view)
        self.center()
    }
}

struct StartSessionWindowFormView: View {
    let focusEngine: FocusEngine
    weak var window: NSWindow?
    private let suggestedGoal: String?
    
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var prefs = PreferencesManager.shared
    
    @State private var minutes: Int = 25
    @State private var selectedProfileID: UUID
    @State private var goal: String = ""
    
    private var themeAccent: Color {
        prefs.selectedThemePalette.accentColor
    }

    private var themeSurface: Color {
        prefs.selectedThemePalette.surfaceColor
    }

    private var themeSurfaceElevated: Color {
        prefs.selectedThemePalette.surfaceRaisedColor
    }

    private var themeBorder: Color {
        prefs.selectedThemePalette.borderColor
    }

    private var themeTextPrimary: Color {
        prefs.selectedThemePalette.textPrimaryColor
    }

    private var themeTextSecondary: Color {
        prefs.selectedThemePalette.textSecondaryColor
    }

    private func readableForeground(for color: Color) -> Color {
        let resolved = color.nsColor.usingColorSpace(.deviceRGB) ?? NSColor.white
        let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent + 0.0722 * resolved.blueComponent
        return luminance > 0.66 ? .black : .white
    }
    
    init(focusEngine: FocusEngine, window: NSWindow?) {
        self.focusEngine = focusEngine
        self.window = window
        self.suggestedGoal = focusEngine.suggestedSessionGoal()
        let suggestedProfile = focusEngine.suggestedSessionProfile()
        self._selectedProfileID = State(initialValue: suggestedProfile.id)
        self._goal = State(initialValue: suggestedGoal ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title & Search-style Goal Input
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("PLOT VOYAGE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(themeAccent)
                        .tracking(1.5)
                    Spacer()
                }
                
                // Goal Text Field (Looks like Raycast Search input)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(themeAccent)
                    
                    TextField("What is yer loot goal for this voyage, Cap'n?", text: $goal)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(themeTextPrimary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    LinearGradient(
                        colors: [ControlRoomTheme.cardTop.opacity(0.9), ControlRoomTheme.cardBottom.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(themeBorder.opacity(0.9), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
                .background(themeBorder.opacity(0.6))
            
            // Configuration List Rows
            ScrollView {
                VStack(spacing: 16) {
                    // Duration Row
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Voyage Duration")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(themeTextPrimary)
                            Spacer()
                            Text("\(minutes) Leagues (min)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(themeAccent)
                        }
                        
                        // Presets
                        HStack(spacing: 8) {
                            ForEach([15, 25, 45, 60], id: \.self) { min in
                                Button(action: {
                                    minutes = min
                                }) {
                                    Text("\(min) Bells")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(minutes == min ? readableForeground(for: themeAccent) : themeTextPrimary)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(minutes == min ? themeAccent : ControlRoomTheme.footer.opacity(0.4))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(minutes == min ? Color.clear : themeBorder.opacity(0.7), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Slider(value: Binding(
                            get: { Double(minutes) },
                            set: { minutes = Int($0) }
                        ), in: 5...120, step: 5)
                        .accentColor(themeAccent)
                    }
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [ControlRoomTheme.cardTop.opacity(0.9), ControlRoomTheme.cardBottom.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(themeBorder.opacity(0.9), lineWidth: 1)
                    )
                    
                    // Profile Row
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active Profile")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(themeTextPrimary)
                        
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
                    .background(
                        LinearGradient(
                            colors: [ControlRoomTheme.cardTop.opacity(0.9), ControlRoomTheme.cardBottom.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(themeBorder.opacity(0.9), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            
            Divider()
                .background(themeBorder.opacity(0.6))
            
            // Raycast-style Action Bar at the bottom
            HStack {
                HStack(spacing: 4) {
                    Text("Tab")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(ControlRoomTheme.footer.opacity(0.5))
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(themeBorder.opacity(0.7), lineWidth: 1))
                    Text("to navigate")
                        .font(.system(size: 11))
                        .foregroundColor(themeTextSecondary)
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
                                .background(ControlRoomTheme.footer.opacity(0.5))
                                .cornerRadius(3)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(themeBorder.opacity(0.7), lineWidth: 1))
                            Text("Abandon")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(themeTextSecondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)
                    
                    // Start
                    Button(action: {
                    let targetProfile = profileManager.profiles.first { $0.id == selectedProfileID }
                    let profileName = targetProfile?.name ?? profileManager.activeProfile.name
                    let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
                    let explicitGoal = trimmedGoal.isEmpty || trimmedGoal == suggestedGoal ? nil : trimmedGoal
                    
                    if selectedProfileID != profileManager.activeProfile.id {
                        profileManager.switchProfile(to: profileName)
                    }
                    
                    let durationSeconds = TimeInterval(minutes * 60)
                    focusEngine.anchorSession(duration: durationSeconds, category: profileName, goal: explicitGoal)
                    
                    window?.close()
                }) {
                        HStack(spacing: 4) {
                            Text("↵")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(ControlRoomTheme.footer.opacity(0.3))
                                .cornerRadius(3)
                            Text("Set Sail")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(readableForeground(for: themeAccent))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(themeAccent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(ControlRoomTheme.footer.opacity(0.85))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(themeBorder.opacity(0.5)),
                alignment: .top
            )
        }
        .accentColor(themeAccent)
        .tint(themeAccent)
        .frame(width: 544, height: 544)
        .background(ControlRoomShellBackground(palette: prefs.selectedThemePalette))
    }
}
