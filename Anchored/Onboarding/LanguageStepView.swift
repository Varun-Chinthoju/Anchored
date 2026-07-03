import SwiftUI

struct LanguageStepView: View {
    let windowHeight: CGFloat
    let onNext: () -> Void
    
    @ObservedObject private var langManager = LanguageManager.shared
    
    @State private var titleIndex = 0
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Details)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(PirateTheme.gold.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    SafeSystemImage(systemName: "character.bubble.fill", size: 32)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: langManager.translate("lang_title", for: AppLanguage.allCases[titleIndex]),
                        font: .system(size: 36, weight: .bold, design: .serif),
                        colors: [PirateTheme.gold, PirateTheme.parchment]
                    )
                    .frame(height: 96, alignment: .topLeading)
                    .id(titleIndex)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .opacity.combined(with: .offset(y: -10))
                    ))
                    
                    Text(langManager.translate("lang_desc", for: AppLanguage.allCases[titleIndex]))
                        .font(.system(size: 14, design: .serif))
                        .foregroundColor(PirateTheme.parchment.opacity(0.8))
                        .lineSpacing(4)
                        .frame(height: 90, alignment: .topLeading)
                        .id(titleIndex)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 10)),
                            removal: .opacity.combined(with: .offset(y: -10))
                        ))
                }
                .onReceive(timer) { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        titleIndex = (titleIndex + 1) % AppLanguage.allCases.count
                    }
                }
                
                Spacer()
                
                Button(action: {
                    AudioEngine.shared.play(.tick)
                    onNext()
                }) {
                    HStack {
                        Spacer()
                        Text(langManager.translate("lang_btn", for: AppLanguage.allCases[titleIndex]))
                            .id(titleIndex)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 5)),
                                removal: .opacity.combined(with: .offset(y: -5))
                            ))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundColor(PirateTheme.darkWood)
                    .frame(width: 200)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                    .shadow(color: PirateTheme.gold.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 320, alignment: .leading)
            
            // Right Column (Languages selection)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(AppLanguage.allCases) { language in
                        Button(action: {
                            AudioEngine.shared.play(.tick)
                            langManager.currentLanguage = language
                        }) {
                            HStack {
                                Text(language.displayName)
                                    .font(.system(size: 13, weight: .semibold, design: .serif))
                                    .foregroundColor(langManager.currentLanguage == language ? PirateTheme.darkWood : PirateTheme.parchment)
                                Spacer()
                                if langManager.currentLanguage == language {
                                    SafeSystemImage(systemName: "checkmark", size: 12, color: langManager.currentLanguage == language ? PirateTheme.darkWood : PirateTheme.gold)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                langManager.currentLanguage == language ?
                                AnyShapeStyle(LinearGradient(
                                    gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )) : AnyShapeStyle(Color.clear)
                            )
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(langManager.currentLanguage == language ? PirateTheme.gold : PirateTheme.gold.opacity(0.15), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(300, windowHeight - 280))
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
