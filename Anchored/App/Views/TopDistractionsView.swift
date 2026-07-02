import SwiftUI

struct TopDistractionsView: View {
    let distractions: [DistractionRank]
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                if distractions.isEmpty {
                    Spacer()
                    Text("No distractions recorded")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
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
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(isDomain ? Color.blue.opacity(0.6) : Color.red.opacity(0.6))
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rank.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Text(isDomain ? "Website" : "Application")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatDuration(TimeInterval(rank.totalDurationSeconds)))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Text("\(rank.count) interrupt\(rank.count == 1 ? "" : "s")")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .frame(height: 160)
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
