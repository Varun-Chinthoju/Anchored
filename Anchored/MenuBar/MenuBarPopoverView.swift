import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var prefs = PreferencesManager.shared
    @State private var showStartForm = false
    @State private var showBreakComposer = false
    @State private var showSummaryComposer = false
    @State private var breakIntention = ""
    @State private var summaryText = ""
    @State private var showBreakRefusal = false
    @State private var editingSummaryID: UUID?

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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anchored")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(themeTextPrimary)
                    Text("A compact control surface for the session you are in right now.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(themeTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
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
                        HStack(spacing: 5) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 12))
                            if let emoji = split.emoji {
                                HStack(alignment: .center, spacing: 2) {
                                    Text(emoji)
                                        .font(.system(size: 11))
                                    Text(split.text)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                }
                            } else {
                                Text(profileManager.activeProfile.name)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(themeTextPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(themeSurfaceSubtle.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(themeBorder.opacity(0.55), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.activeSession != nil ? themeAccent : themeTextSecondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(viewModel.activeSession != nil ? "Session active" : "Idle")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(viewModel.activeSession != nil ? themeAccent : themeTextSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(themeSurfaceRaised.opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(themeBorder.opacity(0.4), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 2)
            
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
                                Text("via \(session.displayName)")
                            }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(themeTextSecondary)
                            } else {
                                Text("Focusing on")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(themeTextSecondary)
                                Text(session.displayName)
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
                        
                        if viewModel.breakState == .breakActive {
                            HStack {
                                Text("Break active • \(viewModel.breakRemainingTimeFormatted)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(themeAccent)
                                Spacer()
                                Button("Return to Work") {
                                    viewModel.resumeAfterBreakReview()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.top, 4)
                        } else if viewModel.breakState == .breakReview {
                            Button("Return to Work") {
                                viewModel.resumeAfterBreakReview()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            HStack(spacing: 10) {
                                Button("Break") {
                                    breakIntention = ""
                                    showBreakComposer = true
                                }
                                .buttonStyle(.bordered)

                                Button("Done") {
                                    if prefs.sessionSummaryPromptEnabled {
                                        summaryText = ""
                                        showSummaryComposer = true
                                    } else {
                                        viewModel.endSession()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
                    .background(themeSurface.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(themeBorder.opacity(0.72), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    if showStartForm {
                        StartSessionFormView(viewModel: viewModel, isPresented: $showStartForm)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "bolt.shield")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(themeAccent)
                                    .frame(width: 32, height: 32)
                                    .background(themeAccent.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(themeAccent.opacity(0.2), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Ready to Anchor")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(themeTextPrimary)
                                    Text("Start a session manually, or let the engine anchor one when focus thresholds are met.")
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundColor(themeTextSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Button(action: {
                                showStartForm = true
                            }) {
                                Text("Start Focus Session")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(themeTextPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(themeAccent)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 18)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(themeSurface.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(themeBorder.opacity(0.72), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }

            ClassificationExplanationCard(
                decision: viewModel.currentClassification,
                hasCurrentDomain: viewModel.focusEngine.currentURL?.host != nil,
                hasActiveSession: viewModel.activeSession != nil,
                onCorrection: { correction in
                    viewModel.focusEngine.applyCorrection(correction)
                }
            )
            
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
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(themeTextSecondary)
                    .tracking(1.1)
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
                                    Text(session.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(formatTime(session.timestamp))
                                        .font(.system(size: 10))
                                        .foregroundColor(themeTextSecondary)
                                    if let summary = session.sessionSummary {
                                        Text(summary)
                                            .font(.system(size: 10))
                                            .foregroundColor(themeTextSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                
                                Spacer()
                                
                                    Text(formatDuration(Double(session.sessionDurationSeconds ?? 0)))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(themeTextSecondary)
                            }
                            .contextMenu {
                                if session.sessionSummary != nil {
                                    Button("Edit Summary") {
                                        editingSummaryID = session.id
                                        summaryText = session.sessionSummary ?? ""
                                        showSummaryComposer = true
                                    }
                                    Button("Delete Summary", role: .destructive) {
                                        viewModel.updateSummary(id: session.id, summary: nil)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(ControlRoomTheme.footer.opacity(0.75))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(themeBorder.opacity(0.55), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(ControlRoomShellBackground(palette: prefs.selectedThemePalette))
        .onAppear {
            viewModel.refresh()
        }
        .sheet(isPresented: $showBreakComposer) {
            BreakIntentionSheet(intention: $breakIntention) {
                showBreakComposer = false
                let result = viewModel.requestBreak(intention: breakIntention)
                if result == .refusedUnderMinimum {
                    showBreakRefusal = true
                }
            } onCancel: {
                showBreakComposer = false
            }
        }
        .sheet(isPresented: $showSummaryComposer) {
            SessionSummarySheet(summary: $summaryText) {
                showSummaryComposer = false
                if let editingSummaryID {
                    viewModel.updateSummary(id: editingSummaryID, summary: summaryText) {
                        self.editingSummaryID = nil
                    }
                } else {
                    viewModel.endSession(summary: summaryText)
                }
            } onSkip: {
                showSummaryComposer = false
                if let editingSummaryID {
                    viewModel.updateSummary(id: editingSummaryID, summary: nil) {
                        self.editingSummaryID = nil
                    }
                } else {
                    viewModel.endSession(summary: nil)
                }
            }
        }
        .alert("Nice try", isPresented: $showBreakRefusal) {
            Button("Keep Focusing", role: .cancel) {}
        } message: {
            Text("Breaks unlock after 30 minutes of net focused time.")
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

private struct BreakIntentionSheet: View {
    @Binding var intention: String
    let onAccept: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Commit to a two-minute break")
                .font(.headline)
            Text("What will you do during the break?")
                .foregroundColor(.secondary)
            TextField("Stretch, get water…", text: $intention)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Start Break", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .disabled(intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}

private struct SessionSummarySheet: View {
    @Binding var summary: String
    let onDone: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session summary")
                .font(.headline)
            Text("Capture what you finished. This stays on this Mac.")
                .foregroundColor(.secondary)
            TextEditor(text: $summary)
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)))
            HStack {
                Button("Skip", action: onSkip)
                Spacer()
                Button("Save", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct ClassificationExplanationCard: View {
    let decision: ClassificationDecision
    let hasCurrentDomain: Bool
    let hasActiveSession: Bool
    let onCorrection: (ClassificationCorrection) -> Void

    private var labelText: String {
        switch decision.label {
        case .productive: return "Productive"
        case .distracting: return "Distracting"
        case .neutral: return "Neutral"
        }
    }

    private var reasonText: String {
        switch decision.reason {
        case .explicitAllowRule: return "An explicit allow rule matched."
        case .explicitBlockRule: return "An explicit block rule matched."
        case .deterministicRule: return "A deterministic rule matched."
        case .deterministicHeuristic: return "A strong local pattern matched."
        case .modelEvidence: return "Optional evidence supports this context."
        case .intentRelated: return "The current context matches the active task intent."
        case .intentEntertainment: return "The current context looks like entertainment."
        case .intentUnrelated: return "The current context does not match the task."
        case .intentUncertain: return "The current intent signal is too weak to enforce."
        case .conflictingEvidence: return "Signals conflict, so no action is taken."
        case .lowConfidence: return "Trusted evidence is not strong enough yet."
        case .optionalDistractionIsNonEnforcing: return "Optional distraction evidence remains non-enforcing."
        case .neutralFallback: return "No trusted rule matched this context."
        }
    }

    private var sourceText: String {
        switch decision.source {
        case .explicitDomainRule: return "Domain rule"
        case .explicitAppRule: return "App rule"
        case .deterministicRule: return "Deterministic rule"
        case .heuristic: return "Local heuristic"
        case .localModel: return "Local model"
        case .cloudModel: return "Cloud model"
        case .visualFallback: return "Visual fallback"
        case .neutralFallback: return "Neutral fallback"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Current Classification", systemImage: "text.magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(labelText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(decision.label == .distracting ? .orange : .accentColor)
            }

            Text(reasonText)
                .font(.system(size: 11))
                .foregroundColor(PirateTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(sourceText)
                Text("•")
                Text("Confidence \(Int(decision.confidence * 100))%")
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(PirateTheme.textSecondary)

            HStack(spacing: 6) {
                correctionButton("Allow App", .allowApp)
                correctionButton("Block App", .blockApp)
                if hasCurrentDomain {
                    correctionButton("Allow Site", .allowDomain)
                    correctionButton("Block Site", .blockDomain)
                }
                if hasActiveSession {
                    correctionButton("Mark Session Productive", .markSessionProductive)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(ControlRoomTheme.footer.opacity(0.72))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PirateTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private func correctionButton(_ title: String, _ correction: ClassificationCorrection) -> some View {
        Button(title) {
            onCorrection(correction)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(PirateTheme.gold)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PirateTheme.gold)
                    .frame(width: 24, height: 24)
                    .background(PirateTheme.gold.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(PirateTheme.border.opacity(0.45), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
            }

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(PirateTheme.parchment)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundColor(PirateTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PirateTheme.darkWood.opacity(0.34))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PirateTheme.border.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StartSessionFormView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var prefs = PreferencesManager.shared
    @Binding var isPresented: Bool
    private let suggestedGoal: String?
    
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

    private var themeBorder: Color {
        prefs.selectedThemePalette.borderColor
    }
    
    init(viewModel: MenuBarViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        self.suggestedGoal = viewModel.focusEngine.suggestedSessionGoal()
        let suggestedProfile = viewModel.focusEngine.suggestedSessionProfile()
        self._selectedProfileID = State(initialValue: suggestedProfile.id)
        self._goal = State(initialValue: suggestedGoal ?? "")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ControlRoomSectionHeader(
                eyebrow: "Session",
                title: "Start Focus Session",
                subtitle: "Choose a duration, category, and optional goal before you go.",
                accent: themeAccent
            )
            
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
                    .background(ControlRoomTheme.footer.opacity(0.5))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(themeBorder.opacity(0.7), lineWidth: 1)
                    )
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: {
                    isPresented = false
                }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(themeTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(themeSurfaceRaised.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(themeBorder.opacity(0.55), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    let targetProfile = profileManager.profiles.first { $0.id == selectedProfileID }
                    let profileName = targetProfile?.name ?? profileManager.activeProfile.name
                    let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
                    let explicitGoal = trimmedGoal.isEmpty || trimmedGoal == suggestedGoal ? nil : trimmedGoal
                    
                    // Switch profile if needed
                    if selectedProfileID != profileManager.activeProfile.id {
                        profileManager.switchProfile(to: profileName)
                    }
                    
                    // Start focus session
                    let durationSeconds = TimeInterval(minutes * 60)
                    viewModel.focusEngine.anchorSession(duration: durationSeconds, category: profileName, goal: explicitGoal)
                    
                    isPresented = false
                }) {
                    Text("Start")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(themeTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(themeAccent)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            themeSurface.opacity(0.92)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeBorder.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accentColor(themeAccent)
        .tint(themeAccent)
    }
}
