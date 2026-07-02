import SwiftUI

struct WeeklyHistoryView: View {
    let history: [(date: Date, focusTime: TimeInterval)]
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            if history.isEmpty {
                Spacer()
                Text("No data available")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
                                            colors: [.green.opacity(0.8), .mint.opacity(0.5)],
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
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 2)
                                                    .background(Color.black.opacity(0.6))
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
                            .foregroundColor(.secondary)
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
