import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("⚓ Anchored")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                if viewModel.activeSession != nil {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Active")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(12)
                } else {
                    Text("Idle")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 4)
            
            // Session Status Card
            VStack(spacing: 0) {
                if let session = viewModel.activeSession {
                    VStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text("Focusing on")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(session.appName)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                        }
                        
                        Text(viewModel.remainingTimeFormatted)
                            .font(.system(size: 42, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.vertical, 4)
                        
                        // Progress Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.2))
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
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.85))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "bolt.shield")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        
                        Text("Ready to Anchor")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        
                        Text("Focused time is tracked automatically.\nWork in a productive app to trigger a focus block.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                }
            }
            
            // Stats Row
            HStack(spacing: 8) {
                StatCard(
                    title: "Focus Time",
                    value: formatDuration(viewModel.stats.focusedTimeToday),
                    icon: "hourglass"
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
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                VStack(spacing: 8) {
                    if viewModel.recentSessions.isEmpty {
                        Text("No sessions logged today")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.primary.opacity(0.01))
                            .cornerRadius(8)
                    } else {
                        ForEach(viewModel.recentSessions, id: \.id) { session in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green.opacity(0.8))
                                    .font(.system(size: 12))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.appName)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(formatTime(session.timestamp))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(formatDuration(Double(session.sessionDurationSeconds ?? 0)))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.02))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            viewModel.refresh()
        }
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
                .foregroundColor(.accentColor)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}
