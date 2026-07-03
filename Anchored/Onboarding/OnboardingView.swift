import SwiftUI

struct OnboardingView: View {
    let windowWidth: CGFloat
    let windowHeight: CGFloat
    
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
                        ForEach(0..<6) { index in
                            Circle()
                                .fill(index == currentStep ? PirateTheme.gold : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 40)
                }
                
                // Active Card content with simple slide transitions
                Group {
                    switch currentStep {
                    case 0:
                        WelcomeStepView(onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 1:
                        HowItWorksStepView(onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 2:
                        FocusSelectorView(windowHeight: windowHeight, onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 3:
                        DistractionSelectorView(windowHeight: windowHeight, onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 4:
                        PreferencesStepView(onComplete: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 5:
                        SetSailStepView(onComplete: { self.onComplete() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    default:
                        EmptyView()
                    }
                }
                .frame(width: windowWidth, height: windowHeight - 120)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentStep)
                
                // Click-anywhere helper hint (only shown for non-interactive pages)
                if currentStep < 2 {
                    Text("Click the deep ocean deck to continue your voyage")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundColor(PirateTheme.parchment)
                        .opacity(0.4)
                        .padding(.bottom, 32)
                } else {
                    Spacer()
                        .frame(height: 32)
                }
            }
            .frame(width: windowWidth, height: windowHeight)
        }
        .frame(width: windowWidth, height: windowHeight)
    }
    
    private func nextStep() {
        if currentStep < 5 {
            currentStep += 1
        }
    }
    
    private func handleBackgroundTap() {
        if currentStep < 2 {
            AudioEngine.shared.play(.tick)
            nextStep()
        }
    }
}
