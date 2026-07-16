import SwiftUI

struct LanguageStepView: View {
    let windowHeight: CGFloat
    let onNext: () -> Void
    
    @ObservedObject private var langManager = LanguageManager.shared
    
    @State private var titleIndex = 0
    @State private var hasSelected = false
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
                        text: hasSelected ? langManager.translate("lang_title") : langManager.translate("lang_title", for: AppLanguage.allCases[titleIndex]),
                        font: .system(size: 36, weight: .bold, design: .serif),
                        colors: [PirateTheme.gold, PirateTheme.parchment]
                    )
                    .frame(height: 96, alignment: .topLeading)
                    .id(hasSelected ? 999 : titleIndex)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .opacity.combined(with: .offset(y: -10))
                    ))
                    
                    Text(hasSelected ? langManager.translate("lang_desc") : langManager.translate("lang_desc", for: AppLanguage.allCases[titleIndex]))
                        .font(.system(size: 14, design: .serif))
                        .foregroundColor(PirateTheme.parchment.opacity(0.8))
                        .lineSpacing(4)
                        .frame(height: 90, alignment: .topLeading)
                        .id(hasSelected ? 999 : titleIndex)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 10)),
                            removal: .opacity.combined(with: .offset(y: -10))
                        ))
                }
                .onReceive(timer) { _ in
                    if !hasSelected {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            titleIndex = (titleIndex + 1) % AppLanguage.allCases.count
                        }
                    }
                }
                
                Spacer()
                
                Button(action: {
                    AudioEngine.shared.play(.tick)
                    onNext()
                }) {
                    HStack {
                        Spacer()
                        Text(hasSelected ? langManager.translate("lang_btn") : langManager.translate("lang_btn", for: AppLanguage.allCases[titleIndex]))
                            .id(hasSelected ? 999 : titleIndex)
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
                VStack(alignment: .leading, spacing: 28) {
                    // Row 1: The Fun Route (Pirate Speak)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            SafeSystemImage(systemName: "flag.and.flag.filled.crossed", size: 16, color: PirateTheme.gold)
                            Text(langManager.translate("lang_fun_route"))
                                .font(.system(size: 14, weight: .bold, design: .serif))
                                .foregroundColor(PirateTheme.gold)
                        }
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(AppLanguage.allCases) { language in
                                if language != .english && language != .pirate {
                                    let isSelected = langManager.currentLanguage == language
                                    Button(action: {
                                        AudioEngine.shared.play(.tick)
                                        langManager.setLanguage(language, isPirateMode: false)
                                        hasSelected = true
                                    }) {
                                        HStack {
                                            Text(language.displayName)
                                                .font(.system(size: 12, weight: .semibold, design: .serif))
                                                .foregroundColor(isSelected ? PirateTheme.darkWood : PirateTheme.parchment)
                                            Spacer()
                                            if isSelected {
                                                SafeSystemImage(systemName: "checkmark", size: 11, color: PirateTheme.darkWood)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            isSelected ?
                                            AnyShapeStyle(LinearGradient(
                                                gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )) : AnyShapeStyle(PirateTheme.darkWood.opacity(0.4))
                                        )
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? PirateTheme.gold : PirateTheme.gold.opacity(0.15), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Row 2: The Boring Side (Standard)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            SafeSystemImage(systemName: "briefcase.fill", size: 14, color: PirateTheme.parchment.opacity(0.6))
                            Text(langManager.translate("lang_boring_side"))
                                .font(.system(size: 14, weight: .bold, design: .serif))
                                .foregroundColor(PirateTheme.parchment.opacity(0.8))
                        }
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(AppLanguage.allCases) { language in
                                if language != .pirate {
                                    let isSelected = langManager.currentLanguage == language
                                    Button(action: {
                                        AudioEngine.shared.play(.tick)
                                        langManager.setLanguage(language, isPirateMode: false)
                                        hasSelected = true
                                    }) {
                                        HStack {
                                            Text(language.displayName)
                                                .font(.system(size: 12, weight: .semibold, design: .serif))
                                                .foregroundColor(isSelected ? PirateTheme.darkWood : PirateTheme.parchment)
                                            Spacer()
                                            if isSelected {
                                                SafeSystemImage(systemName: "checkmark", size: 11, color: PirateTheme.darkWood)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            isSelected ?
                                            AnyShapeStyle(LinearGradient(
                                                gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )) : AnyShapeStyle(PirateTheme.darkWood.opacity(0.4))
                                        )
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? PirateTheme.gold : PirateTheme.gold.opacity(0.15), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
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
