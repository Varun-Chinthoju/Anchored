import SwiftUI

struct OnboardingView: View {
    let windowWidth: CGFloat
    let windowHeight: CGFloat
    
    @AppStorage("onboardingCurrentStep") private var currentStep = 0
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
                // Header / Step progress
                if currentStep > 0 {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(0..<6) { index in
                                Circle()
                                    .fill(index == currentStep ? PirateTheme.gold : PirateTheme.separator.opacity(0.8))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        Text("Step \(currentStep + 1) of 6")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(PirateTheme.parchment.opacity(0.65))
                    }
                    .padding(.top, 34)
                }
                
                // Active Card content with simple slide transitions
                Group {
                    switch currentStep {
                    case 0:
                        WelcomeStepView(onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleBackgroundTap()
                            }
                    case 1:
                        HowItWorksStepView(onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleBackgroundTap()
                            }
                    case 2:
                        DistractionSelectorView(windowHeight: windowHeight, onNext: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 3:
                        PreferencesStepView(onComplete: { self.nextStep() })
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 4:
                        PermissionStepView(windowHeight: windowHeight, onNext: { self.nextStep() })
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
                if currentStep == 0 || currentStep == 1 {
                    Text(t("how_btn")) // Standard prompt
                        .font(.system(size: 11, weight: .medium, design: .rounded))
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
        if currentStep < 5 {
            currentStep += 1
        }
    }
    
    private func handleBackgroundTap() {
        if currentStep == 0 || currentStep == 1 {
            AudioEngine.shared.play(.tick)
            nextStep()
        }
    }
}
