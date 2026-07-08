import SwiftUI

struct WeeklyHistoryView: View {
    let history: [(date: Date, focusTime: TimeInterval)]
    @ObservedObject private var prefs = PreferencesManager.shared

    private var themeAccent: Color {
        prefs.selectedThemePalette.accentColor
    }

    private var themeSurface: Color {
        prefs.selectedThemePalette.surfaceColor
    }

    private var themeSurfaceRaised: Color {
        prefs.selectedThemePalette.surfaceRaisedColor
    }

    private var themeTextSecondary: Color {
        prefs.selectedThemePalette.textSecondaryColor
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            if history.isEmpty {
                Spacer()
                Text("No data available")
                    .font(.system(size: 11))
                    .foregroundColor(themeTextSecondary)
                Spacer()
            } else {
                let maxTime = max(60.0, history.map { $0.focusTime }.max() ?? 0.0)
                
                ForEach(0..<history.count, id: \.self) { index in
                    let item = history[index]
                    VStack(spacing: 8) {
                        let heightPercent = CGFloat(item.focusTime / maxTime)
                        
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                Spacer()
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [themeAccent.opacity(0.85), themeSurfaceRaised.opacity(0.7)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: max(4.0, heightPercent * geometry.size.height))
                                    .overlay(
                                        VStack {
                                            if item.focusTime > 0 {
                                                Text(formatShortDuration(item.focusTime))
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(themeTextSecondary)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 2)
                                                    .background(themeSurface.opacity(0.85))
                                                    .cornerRadius(3)
                                                    .offset(y: -14)
                                            }
                                        },
                                        alignment: .top
                                    )
                            }
                        }
                        
                        Text(dayOfWeek(item.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(themeTextSecondary)
                    }
                }
            }
        }
        .frame(height: 160)
        .padding(.vertical, 8)
    }
    
    private func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(1))
    }
    
    private func formatShortDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}
