import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var prefs = PreferencesManager.shared
    @State private var showStartForm = false

    private var themeAccent: Color {
        prefs.selectedThemePalette.accentColor
    }

    private var themeSurface: Color {
        prefs.selectedThemePalette.surfaceColor
    }

    private var themeSurfaceRaised: Color {
        prefs.selectedThemePalette.surfaceRaisedColor
    }

    private var themeSurfaceSubtle: Color {
        prefs.selectedThemePalette.surfaceSubtleColor
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
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("⚓ Anchored")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                
                Spacer()
                
                Menu {
                    ForEach(profileManager.profiles) { profile in
                        Button(action: {
                            profileManager.switchProfile(to: profile.name)
                        }) {
                            if profile.id == profileManager.activeProfile.id {
                                Text("✓ \(profile.name)")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                } label: {
                    let split = profileManager.activeProfile.name.splitEmojiAndText()
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 12))
                        if let emoji = split.emoji {
                            HStack(alignment: .center, spacing: 2) {
                                Text(emoji)
                                    .font(.system(size: 12))
                                Text(split.text)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                        } else {
                            Text(profileManager.activeProfile.name)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(themeSurfaceSubtle)
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                if viewModel.activeSession != nil {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(themeAccent)
                            .frame(width: 8, height: 8)
                        Text("Active")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(themeAccent)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(themeAccent.opacity(0.15))
                    .cornerRadius(12)
                } else {
                    Text("Idle")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(themeTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(themeSurfaceRaised.opacity(0.45))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 4)
            
            // Session Status Card
            VStack(spacing: 0) {
                if let session = viewModel.activeSession {
                    VStack(spacing: 12) {
                        VStack(spacing: 4) {
                            if let goal = session.goal {
                                Text(goal)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .multilineTextAlignment(.center)
                                HStack(spacing: 4) {
                                    Text("Focusing in")
                                    Text(session.category ?? profileManager.activeProfile.name)
                                        .bold()
                                    Text("via \(session.appName)")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(themeTextSecondary)
                            } else {
                                Text("Focusing on")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(themeTextSecondary)
                                Text(session.appName)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                            }
                        }
                        
                        Text(viewModel.remainingTimeFormatted)
                            .font(.system(size: 42, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.vertical, 4)
                        
                        // Progress Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                    .fill(themeSurfaceRaised.opacity(0.55))
                                    .frame(height: 6)
                                
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * CGFloat(viewModel.progress), height: 6)
                            }
                        }
                        .frame(height: 6)
                        .padding(.horizontal, 8)
                        
                        Button(action: {
                            viewModel.endSession()
                        }) {
                            Text("End Session")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(themeTextPrimary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(themeSurfaceSubtle)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
                    .background(themeSurface.opacity(0.78))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(themeBorder, lineWidth: 1)
                    )
                } else {
                    if showStartForm {
                        StartSessionFormView(viewModel: viewModel, isPresented: $showStartForm)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "bolt.shield")
                                .font(.system(size: 28))
                                .foregroundColor(themeTextSecondary)
                            
                            Text("Ready to Anchor")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            
                            Text("Focused time is tracked automatically.\nWork in a productive app to trigger a focus block.")
                                .font(.system(size: 11))
                                .foregroundColor(themeTextSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                            
                            Button(action: {
                                showStartForm = true
                            }) {
                                Text("Start Focus Session...")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(themeTextPrimary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(themeAccent)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(themeSurface.opacity(0.65))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(themeBorder, lineWidth: 1)
                        )
                    }
                }
            }
            
            // Stats Row
            HStack(spacing: 8) {
                StatCard(
                    title: "Focus Time",
                    value: formatDuration(viewModel.stats.focusedTimeToday),
                    icon: "timer"
                )
                StatCard(
                    title: "Sessions",
                    value: "\(viewModel.stats.sessionCountToday)",
                    icon: "checkmark.circle"
                )
                StatCard(
                    title: "Streak",
                    value: "\(viewModel.stats.streakDays) \(viewModel.stats.streakDays == 1 ? "day" : "days")",
                    icon: "flame"
                )
            }
            
            // Recent History List
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Sessions")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(themeTextSecondary)
                    .padding(.horizontal, 4)
                
                VStack(spacing: 8) {
                    if viewModel.recentSessions.isEmpty {
                        Text("No sessions logged today")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(themeTextSecondary)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(themeSurface.opacity(0.55))
                            .cornerRadius(8)
                    } else {
                        ForEach(viewModel.recentSessions, id: \.id) { session in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(themeAccent)
                                    .font(.system(size: 12))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.appName)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(formatTime(session.timestamp))
                                        .font(.system(size: 10))
                                        .foregroundColor(themeTextSecondary)
                                }
                                
                                Spacer()
                                
                                Text(formatDuration(Double(session.sessionDurationSeconds ?? 0)))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(themeTextSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(themeSurface.opacity(0.65))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(
            LinearGradient(
                colors: [PirateTheme.canvas, themeSurface.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            viewModel.refresh()
        }
        .accentColor(themeAccent)
        .tint(themeAccent)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 1 {
            return "\(Int(seconds))s"
        }
        return "\(minutes)m"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(PirateTheme.gold)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(PirateTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(PirateTheme.surface.opacity(0.68))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PirateTheme.border, lineWidth: 1)
        )
    }
}

struct StartSessionFormView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var prefs = PreferencesManager.shared
    @Binding var isPresented: Bool
    
    @State private var minutes: Int = 25
    @State private var selectedProfileID: UUID
    @State private var goal: String = ""

    private var themeAccent: Color {
        prefs.selectedThemePalette.accentColor
    }

    private var themeSurface: Color {
        prefs.selectedThemePalette.surfaceColor
    }

    private var themeSurfaceRaised: Color {
        prefs.selectedThemePalette.surfaceRaisedColor
    }

    private var themeTextPrimary: Color {
        prefs.selectedThemePalette.textPrimaryColor
    }

    private var themeTextSecondary: Color {
        prefs.selectedThemePalette.textSecondaryColor
    }
    
    init(viewModel: MenuBarViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        let activeProfile = ProfileManager.shared.activeProfile
        self._selectedProfileID = State(initialValue: activeProfile.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start Focus Session")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(themeTextPrimary)
                .padding(.bottom, 2)
            
            // Duration Selection
            VStack(alignment: .leading, spacing: 4) {
                Text("Duration")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeTextSecondary)
                
                HStack(spacing: 6) {
                    ForEach([15, 25, 45, 60], id: \.self) { min in
                        Button(action: {
                            minutes = min
                        }) {
                            Text("\(min)m")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(themeTextPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(minutes == min ? themeAccent : themeSurfaceRaised.opacity(0.45))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(minutes) },
                        set: { minutes = Int($0) }
                    ), in: 5...120, step: 5)
                    
                    Text("\(minutes) min")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.top, 2)
            }
            
            // Profile / Category Selection
            VStack(alignment: .leading, spacing: 4) {
                Text("Category (Profile)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeTextSecondary)
                
                Picker("", selection: $selectedProfileID) {
                    ForEach(profileManager.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            
            // Goal / Goal Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Goal / Name")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeTextSecondary)
                
                TextField("e.g. Code database migrations...", text: $goal)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(6)
                    .background(themeSurfaceRaised.opacity(0.45))
                    .cornerRadius(6)
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: {
                    isPresented = false
                }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(themeSurfaceRaised.opacity(0.5))
                        .cornerRadius(6)
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
                    viewModel.focusEngine.anchorSession(duration: durationSeconds, category: profileName, goal: goal.isEmpty ? nil : goal)
                    
                    isPresented = false
                }) {
                    Text("Start")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(themeTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(themeAccent)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [themeSurface.opacity(0.92), themeSurfaceRaised.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PirateTheme.border, lineWidth: 1)
        )
        .accentColor(themeAccent)
        .tint(themeAccent)
    }
}
