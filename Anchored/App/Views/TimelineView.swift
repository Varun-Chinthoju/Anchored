import SwiftUI

struct TimelineView: View {
    let blocks: [TimelineBlock]
    @Binding var hoveredBlock: TimelineBlock?
    
    var body: some View {
        GeometryReader { geometry in
            if blocks.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.02))
                    .overlay(
                        Text("No session activity tracked today")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    )
            } else {
                let earliest = blocks.first?.startDate ?? Date()
                let latest = blocks.last?.endDate ?? Date()
                let totalDuration = max(1.0, latest.timeIntervalSince(earliest))
                
                ZStack(alignment: .leading) {
                    // Base background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                    
                    // Render blocks
                    ForEach(0..<blocks.count, id: \.self) { index in
                        let block = blocks[index]
                        let startOffset = block.startDate.timeIntervalSince(earliest)
                        let blockDuration = block.endDate.timeIntervalSince(block.startDate)
                        
                        let relativeStart = startOffset / totalDuration
                        let relativeWidth = blockDuration / totalDuration
                        
                        let width = max(3.0, CGFloat(relativeWidth) * geometry.size.width)
                        let xOffset = CGFloat(relativeStart) * geometry.size.width
                        
                        let isHovered = hoveredBlock == block
                        
                        let gradientColor = block.type == .focus ?
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(gradientColor)
                            .scaleEffect(isHovered ? 1.05 : 1.0)
                            .shadow(color: isHovered ? (block.type == .focus ? Color.green : Color.red).opacity(0.5) : Color.clear, radius: 4)
                            .frame(width: width, height: geometry.size.height - 12)
                            .offset(x: xOffset, y: 6)
                            .contentShape(Rectangle())
                            .onHover { isHovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isHovering {
                                        hoveredBlock = block
                                    } else if hoveredBlock == block {
                                        hoveredBlock = nil
                                    }
                                }
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
            }
        }
    }
}
