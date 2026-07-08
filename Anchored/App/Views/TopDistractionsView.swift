import SwiftUI
import AppKit

struct TopDistractionsView: View {
    let distractions: [DistractionRank]
    @ObservedObject private var prefs = PreferencesManager.shared

    private var themeAccent: Color {
        prefs.selectedThemePalette.accentColor
    }

    private var themeAccentSecondary: Color {
        prefs.selectedThemePalette.surfaceRaisedColor
    }

    private var themeSurface: Color {
        prefs.selectedThemePalette.surfaceColor
    }

    private var themeBorder: Color {
        prefs.selectedThemePalette.borderColor
    }

    private var themeTextSecondary: Color {
        prefs.selectedThemePalette.textSecondaryColor
    }

    private func readableForeground(for color: Color) -> Color {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.white
        let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent + 0.0722 * resolved.blueComponent
        return luminance > 0.66 ? .black : .white
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                if distractions.isEmpty {
                    Spacer()
                    Text("No distractions recorded")
                        .font(.system(size: 11))
                        .foregroundColor(themeTextSecondary)
                        .padding(.vertical, 40)
                    Spacer()
                } else {
                    ForEach(0..<min(5, distractions.count), id: \.self) { index in
                        let rank = distractions[index]
                        HStack(spacing: 12) {
                            // Badge with initial
                            let isDomain = rank.domain != nil
                            let initial = String(rank.name.prefix(1)).uppercased()
                            
                            Text(initial)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(readableForeground(for: isDomain ? themeAccent : themeAccentSecondary))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(isDomain ? themeAccent.opacity(0.55) : themeAccentSecondary.opacity(0.65))
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rank.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Text(isDomain ? "Website" : "Application")
                                    .font(.system(size: 10))
                                    .foregroundColor(themeTextSecondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatDuration(TimeInterval(rank.totalDurationSeconds)))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Text("\(rank.count) interrupt\(rank.count == 1 ? "" : "s")")
                                    .font(.system(size: 9))
                                    .foregroundColor(themeTextSecondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(themeSurface.opacity(0.65))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(themeBorder, lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }
                }
            }
        }
        .frame(height: 160)
        .accentColor(themeAccent)
        .tint(themeAccent)
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
