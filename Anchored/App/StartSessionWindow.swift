import AppKit
import SwiftUI

class StartSessionWindow: NSWindow {
    
    init(focusEngine: FocusEngine) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 744, height: 466),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Start Focus Session"
        self.isReleasedWhenClosed = false
        self.isOpaque = true
        self.hasShadow = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.appearance = NSAppearance(named: .vibrantDark)
        self.minSize = NSSize(width: 700, height: 430)
        self.maxSize = NSSize(width: 780, height: 500)
        
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
    private let durationPresets = [15, 25, 45, 60]
    private static let customDurationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.generatesDecimalNumbers = false
        return formatter
    }()
    
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var prefs = PreferencesManager.shared
    
    @State private var durationMinutes: Int = 25
    @State private var customDurationMinutes: Int = 25
    @State private var isCustomDurationSelected = false
    @State private var selectedProfileID: UUID
    @State private var goal: String = ""
    @State private var isGoalFieldFocused = false
    
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
            headerRow

            Divider()
                .overlay(themeBorder.opacity(0.4))

            VStack(alignment: .leading, spacing: 14) {
                goalSection
                profileSection
                durationSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .overlay(themeBorder.opacity(0.4))

            footerRow
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            themeSurface.opacity(0.76),
                            themeSurfaceElevated.opacity(0.62),
                            Color.black.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(themeBorder.opacity(0.42), lineWidth: 1)
                )
        )
        .padding(12)
        .accentColor(themeAccent)
        .tint(themeAccent)
        .frame(width: 744, height: 466)
        .background(ControlRoomShellBackground(palette: prefs.selectedThemePalette))
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Start Focus Session")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(themeTextPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are you working on?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(themeTextPrimary)

            GoalTextField(
                text: $goal,
                isFocused: $isGoalFieldFocused,
                placeholder: "Describe your focus task",
                requestInitialFocus: true,
                selectAllOnFocus: true,
                onCommit: commitSession
            )
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(themeTextPrimary)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(themeSurface.opacity(0.24))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isGoalFieldFocused ? themeAccent.opacity(0.86) : themeBorder.opacity(0.38), lineWidth: isGoalFieldFocused ? 1.4 : 1)
            )
        }
    }

    private var profileSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(themeTextPrimary)
                .frame(width: 78, alignment: .leading)

            Picker("", selection: $selectedProfileID) {
                ForEach(profileManager.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 138, alignment: .trailing)

            Spacer(minLength: 0)
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Duration")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(themeTextPrimary)

            HStack(spacing: 8) {
                ForEach(durationPresets, id: \.self) { minute in
                    durationPresetButton(minutes: minute)
                }

                Button(action: selectCustomDuration) {
                    Text("Custom")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isCustomDurationSelected ? readableForeground(for: themeAccent) : themeTextPrimary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(isCustomDurationSelected ? themeAccent : themeSurface.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isCustomDurationSelected ? Color.clear : themeBorder.opacity(0.45), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            if isCustomDurationSelected {
                HStack(spacing: 10) {
                    Text("Custom")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeTextSecondary)

                    TextField("", value: $customDurationMinutes, formatter: Self.customDurationFormatter)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(themeSurface.opacity(0.36))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(themeBorder.opacity(0.55), lineWidth: 1)
                        )
                        .onChange(of: customDurationMinutes) { newValue in
                            durationMinutes = newValue
                        }

                    Text("min")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeTextSecondary)

                    Stepper("", value: $customDurationMinutes, in: 5...180, step: 5)
                        .labelsHidden()
                        .onChange(of: customDurationMinutes) { newValue in
                            durationMinutes = newValue
                        }
                }
                .padding(.top, 2)
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                keycap("Tab")
                Text("moves between fields")
                    .font(.system(size: 11))
                    .foregroundColor(themeTextSecondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: {
                    window?.close()
                }) {
                    HStack(spacing: 6) {
                        keycap("Esc")
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .foregroundColor(themeTextSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button(action: commitSession) {
                    HStack(spacing: 6) {
                        Text("Start Focus")
                            .font(.system(size: 12, weight: .semibold))
                        keycap("↩")
                    }
                    .foregroundColor(readableForeground(for: themeAccent))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 12)
                    .background(themeAccent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func durationPresetButton(minutes: Int) -> some View {
        let isSelected = !isCustomDurationSelected && durationMinutes == minutes

        return Button(action: {
            selectDurationPreset(minutes)
        }) {
            Text("\(minutes) min")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? readableForeground(for: themeAccent) : themeTextPrimary)
                .padding(.vertical, 7)
                .padding(.horizontal, 11)
                .background(isSelected ? themeAccent : themeSurface.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.clear : themeBorder.opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(themeTextSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(themeSurface.opacity(0.52))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(themeBorder.opacity(0.45), lineWidth: 1)
            )
    }

    private func selectDurationPreset(_ minutes: Int) {
        durationMinutes = minutes
        isCustomDurationSelected = false
    }

    private func selectCustomDuration() {
        if !isCustomDurationSelected {
            isCustomDurationSelected = true
            durationMinutes = customDurationMinutes
        }
    }

    private func commitSession() {
        let targetProfile = profileManager.profiles.first { $0.id == selectedProfileID }
        let profileName = targetProfile?.name ?? profileManager.activeProfile.name
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitGoal = trimmedGoal.isEmpty || trimmedGoal == suggestedGoal ? nil : trimmedGoal

        if selectedProfileID != profileManager.activeProfile.id {
            profileManager.switchProfile(to: profileName)
        }

        focusEngine.anchorSession(
            duration: TimeInterval(durationMinutes * 60),
            category: profileName,
            goal: explicitGoal
        )

        window?.close()
    }
}

private struct GoalTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let requestInitialFocus: Bool
    let selectAllOnFocus: Bool
    let onCommit: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: GoalTextField
        var didRequestInitialFocus = false

        init(parent: GoalTextField) {
            self.parent = parent
        }

        @objc func commit(_ sender: Any?) {
            parent.onCommit()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true

            guard parent.selectAllOnFocus,
                  let textField = notification.object as? NSTextField else {
                return
            }

            DispatchQueue.main.async {
                textField.currentEditor()?.selectAll(nil)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.commit(_:))
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 16, weight: .regular)
        textField.placeholderString = placeholder
        textField.isEditable = true
        textField.isSelectable = true
        textField.allowsEditingTextAttributes = false
        requestFocusIfNeeded(textField, coordinator: context.coordinator)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        nsView.placeholderString = placeholder
        requestFocusIfNeeded(nsView, coordinator: context.coordinator)
    }

    private func requestFocusIfNeeded(_ textField: NSTextField, coordinator: Coordinator) {
        guard requestInitialFocus, !coordinator.didRequestInitialFocus else { return }

        DispatchQueue.main.async {
            guard let window = textField.window else { return }
            coordinator.didRequestInitialFocus = true
            window.makeFirstResponder(textField)
            if self.selectAllOnFocus {
                textField.currentEditor()?.selectAll(nil)
            }
        }
    }
}
