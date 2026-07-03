import SwiftUI

struct DomainNode: Identifiable {
    let id = UUID()
    let domain: String
    let duration: TimeInterval
}

struct AppNode: Identifiable {
    let id = UUID()
    let bundleID: String
    let name: String
    let duration: TimeInterval
    let domains: [DomainNode]
}

struct NodeView: View {
    let title: String
    let subtitle: String
    let x: CGFloat
    let y: CGFloat
    let isHub: Bool
    var isDomain: Bool = false
    
    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(isHub ? PirateTheme.gold : (isDomain ? PirateTheme.parchment.opacity(0.8) : PirateTheme.gold.opacity(0.8)))
                .frame(width: isHub ? 14 : 10, height: isHub ? 14 : 10)
                .overlay(
                    Circle()
                        .stroke(PirateTheme.gold.opacity(0.4), lineWidth: 1.5)
                        .scaleEffect(isHub ? 1.3 : 1.15)
                )
                .shadow(color: PirateTheme.gold.opacity(0.4), radius: 3)
            
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundColor(PirateTheme.parchment)
                .lineLimit(1)
                .frame(width: 90)
                .multilineTextAlignment(.center)
            
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .position(x: x, y: y)
    }
}

struct FleetTreeSpreadmapView: View {
    @State private var apps: [AppNode] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fleet Tree (Voyage Spread)")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundColor(PirateTheme.gold)
                .padding(.horizontal, 4)
            
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                
                if apps.isEmpty {
                    VStack {
                        Image(systemName: "circle.grid.cross")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(.bottom, 4)
                        Text("No active fleet registered on this voyage.")
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: width, height: height)
                } else {
                    let centerX: CGFloat = 60
                    let centerY: CGFloat = height / 2
                    
                    let appX: CGFloat = width * 0.42
                    let domainX: CGFloat = width * 0.78
                    
                    let appSpacing = height / CGFloat(apps.count + 1)
                    
                    ZStack {
                        // Drawing Connections
                        Path { path in
                            for (aIndex, app) in apps.enumerated() {
                                let appY = appSpacing * CGFloat(aIndex + 1)
                                
                                // Connect Hub to App Node
                                path.move(to: CGPoint(x: centerX, y: centerY))
                                path.addCurve(
                                    to: CGPoint(x: appX, y: appY),
                                    control1: CGPoint(x: (centerX + appX) / 2, y: centerY),
                                    control2: CGPoint(x: (centerX + appX) / 2, y: appY)
                                )
                                
                                // Connect App Node to its Domain Nodes
                                let isBrowser = app.bundleID.contains("safari") || app.bundleID.contains("chrome") || app.bundleID.contains("firefox") || app.bundleID.contains("arc") || app.bundleID.contains("brave") || app.bundleID.contains("opera")
                                
                                if isBrowser && !app.domains.isEmpty {
                                    let domSpacing = height / CGFloat(app.domains.count + 1)
                                    for (dIndex, _) in app.domains.enumerated() {
                                        let domY = domSpacing * CGFloat(dIndex + 1)
                                        path.move(to: CGPoint(x: appX, y: appY))
                                        path.addCurve(
                                            to: CGPoint(x: domainX, y: domY),
                                            control1: CGPoint(x: (appX + domainX) / 2, y: appY),
                                            control2: CGPoint(x: (appX + domainX) / 2, y: domY)
                                        )
                                    }
                                }
                            }
                        }
                        .stroke(PirateTheme.gold.opacity(0.18), lineWidth: 1.5)
                        
                        // Voyage Hub Node
                        NodeView(title: "Voyage Hub", subtitle: "Core", x: centerX, y: centerY, isHub: true)
                        
                        // App Nodes
                        ForEach(0..<apps.count, id: \.self) { aIndex in
                            let app = apps[aIndex]
                            let appY = appSpacing * CGFloat(aIndex + 1)
                            
                            NodeView(
                                title: app.name,
                                subtitle: formatDuration(app.duration),
                                x: appX,
                                y: appY,
                                isHub: false
                            )
                            
                            // Domain Nodes
                            let isBrowser = app.bundleID.contains("safari") || app.bundleID.contains("chrome") || app.bundleID.contains("firefox") || app.bundleID.contains("arc") || app.bundleID.contains("brave") || app.bundleID.contains("opera")
                            
                            if isBrowser && !app.domains.isEmpty {
                                let domSpacing = height / CGFloat(app.domains.count + 1)
                                ForEach(0..<app.domains.count, id: \.self) { dIndex in
                                    let dom = app.domains[dIndex]
                                    let domY = domSpacing * CGFloat(dIndex + 1)
                                    
                                    NodeView(
                                        title: dom.domain,
                                        subtitle: formatDuration(dom.duration),
                                        x: domainX,
                                        y: domY,
                                        isHub: false,
                                        isDomain: true
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 240)
            .padding(16)
            .background(PirateTheme.darkWood.opacity(0.4))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PirateTheme.gold.opacity(0.15), lineWidth: 1)
            )
        }
        .onAppear {
            loadDistribution()
        }
    }
    
    private func loadDistribution() {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
        let rawDist = SQLiteSessionStore.shared.appDomainFocusDistribution(since: start, to: now)
        
        let sortedApps = rawDist.sorted { $0.value.duration > $1.value.duration }
        var topApps: [AppNode] = []
        
        for (bundleID, data) in sortedApps.prefix(4) {
            let sortedDomains = data.domains.sorted { $0.value > $1.value }
            let domainsList = sortedDomains.prefix(3).map { DomainNode(domain: $0.key, duration: $0.value) }
            
            topApps.append(AppNode(
                bundleID: bundleID,
                name: data.appName,
                duration: data.duration,
                domains: domainsList
            ))
        }
        self.apps = topApps
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        } else {
            return "\(m)m"
        }
    }
}
