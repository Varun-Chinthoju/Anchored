import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

public struct ExitTriggerView: View {
    let formattedDuration: String
    let appName: String
    let onAnchor: (TimeInterval) -> Void
    let onDismiss: () -> Void
    
    public init(
        formattedDuration: String,
        appName: String,
        onAnchor: @escaping (TimeInterval) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.formattedDuration = formattedDuration
        self.appName = appName
        self.onAnchor = onAnchor
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                // macOS Application Icon
                Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 48, height: 48)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protect Focus Momentum")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("You just locked in \(formattedDuration) of focused time in \(appName). Want to protect this momentum?")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            HStack {
                Button("Taking a Break", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("15m") {
                        onAnchor(900)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button("25m") {
                        onAnchor(1500)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button("45m") {
                        onAnchor(2700)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(VisualEffectView().cornerRadius(12))
        .shadow(color: Color.black.opacity(0.3), radius: 16, x: 0, y: 8)
    }
}
