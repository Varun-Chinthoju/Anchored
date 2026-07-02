import SwiftUI

struct OnboardingView: View {
    @State private var currentStep = 0
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Neon ambient dark background with tap-to-continue gesture
            OnboardingBackground()
                .onTapGesture {
                    handleBackgroundTap()
                }
            
            VStack {
                // Header / Step dots
                if currentStep > 0 {
                    HStack(spacing: 8) {
                        ForEach(0..<5) { index in
                            Circle()
                                .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 40)
                }
                
                // Active Card content with simple slide transitions
                Group {
                    switch currentStep {
                    case 0:
                        WelcomeStepView(onNext: nextStep)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 1:
                        HowItWorksStepView(onNext: nextStep)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 2:
                        FocusSelectorView(onNext: nextStep)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 3:
                        DistractionSelectorView(onNext: nextStep)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 4:
                        PreferencesStepView(onComplete: onComplete)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    default:
                        EmptyView()
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentStep)
                
                Spacer()
                
                // Click-anywhere helper hint
                Text(currentStep < 4 ? "Click anywhere on the background to continue" : "Click anywhere on the background to save & launch")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .opacity(0.4)
                    .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func nextStep() {
        if currentStep < 4 {
            currentStep += 1
        }
    }
    
    private func handleBackgroundTap() {
        AudioEngine.shared.play(.tick)
        if currentStep < 4 {
            nextStep()
        } else {
            AudioEngine.shared.play(.chime)
            onComplete()
        }
    }
}
