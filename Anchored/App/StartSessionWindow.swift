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
        
        self.title = "Start Focus Session"
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
    
    init(focusEngine: FocusEngine, window: NSWindow?) {
        self.focusEngine = focusEngine
        self.window = window
        let activeProfile = ProfileManager.shared.activeProfile
        self._selectedProfileID = State(initialValue: activeProfile.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Configure Focus Session")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.bottom, 4)
            
            // Duration Selection
            VStack(alignment: .leading, spacing: 10) {
                Text("Duration")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    ForEach([15, 25, 45, 60], id: \.self) { min in
                        Button(action: {
                            minutes = min
                        }) {
                            Text("\(min)m")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(minutes == min ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(minutes == min ? Color.accentColor : Color.primary.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                HStack(spacing: 12) {
                    Slider(value: Binding(
                        get: { Double(minutes) },
                        set: { minutes = Int($0) }
                    ), in: 5...120, step: 5)
                    
                    Text("\(minutes) min")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.top, 4)
            }
            
            // Profile / Category Selection
            VStack(alignment: .leading, spacing: 10) {
                Text("Category (Profile)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $selectedProfileID) {
                    ForEach(profileManager.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .scaleEffect(1.1)
            }
            
            // Goal / Goal Title
            VStack(alignment: .leading, spacing: 10) {
                Text("Goal / Name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                TextField("e.g. Code database migrations...", text: $goal)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(12)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
            }
            
            Spacer()
            
            // Buttons
            HStack(spacing: 16) {
                Button(action: {
                    window?.close()
                }) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.12))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    let targetProfile = profileManager.profiles.first { $0.id == selectedProfileID }
                    let profileName = targetProfile?.name ?? profileManager.activeProfile.name
                    
                    // Switch profile if needed
                    if selectedProfileID != profileManager.activeProfile.id {
                        profileManager.switchProfile(to: profileName)
                    }
                    
                    // Start focus session
                    let durationSeconds = TimeInterval(minutes * 60)
                    focusEngine.anchorSession(duration: durationSeconds, category: profileName, goal: goal.isEmpty ? nil : goal)
                    
                    window?.close()
                }) {
                    Text("Start")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .frame(width: 544, height: 544)
    }
}
