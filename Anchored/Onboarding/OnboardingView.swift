import SwiftUI

struct OnboardingView: View {
    let windowWidth: CGFloat
    let windowHeight: CGFloat
    
    @State private var currentStep = 0
    let onComplete: () -> Void
    @ObservedObject private var langManager = LanguageManager.shared
    
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
                        ForEach(0..<8) { index in
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
                        LanguageStepView(windowHeight: windowHeight, onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 1:
                        WelcomeStepView(onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleBackgroundTap()
                            }
                    case 2:
                        HowItWorksStepView(onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleBackgroundTap()
                            }
                    case 3:
                        FocusSelectorView(windowHeight: windowHeight, onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 4:
                        DistractionSelectorView(windowHeight: windowHeight, onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 5:
                        PreferencesStepView(onComplete: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 6:
                        PermissionStepView(windowHeight: windowHeight, onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 7:
                        SetSailStepView(onComplete: { self.onComplete() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    default:
                        EmptyView()
                    }
                }
                .frame(width: windowWidth, height: windowHeight - 120)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentStep)
                
                // Click-anywhere helper hint (only shown for non-interactive pages)
                if currentStep == 1 || currentStep == 2 {
                    Text(t("how_btn")) // Standard prompt
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
        .preferredColorScheme(.dark)
    }
    
    private func nextStep() {
        if currentStep < 7 {
            currentStep += 1
        }
    }
    
    private func handleBackgroundTap() {
        if currentStep == 1 || currentStep == 2 {
            AudioEngine.shared.play(.tick)
            nextStep()
        }
    }
}
