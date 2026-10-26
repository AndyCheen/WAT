import SwiftUI
import DesignSystem

/// Каркас сторінок режиму розробника: верстка «Налаштувань» — він відкривається звідти й має виглядати рідним.
struct DeveloperPageLayout<Content: View>: View {
    @Environment(\.wtTheme) private var theme
    let title: String
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WTSpacing.cardGap) {
                    WTNavBar(title: title, onBack: onBack)
                    content()
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

/// Секція з підписом над карткою — як у «Налаштуваннях».
struct DeveloperSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WTSectionLabel(title)
            WTCard {
                VStack(alignment: .leading, spacing: 0) { content() }
            }
        }
    }
}

/// Рядок «назва — значення» без дії.
struct DeveloperValueRow: View {
    @Environment(\.wtTheme) private var theme
    let title: String
    let value: String
    var identifier: String?

    var body: some View {
        WTSettingRow(title) {
            Text(value)
                .font(WTFont.text(15, .bold))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier ?? "")
        }
    }
}

/// Чип дії режиму розробника — у рядок, що переноситься.
struct DeveloperChip: Identifiable {
    let id: String
    let title: String
    var isSelected = false
    let action: () -> Void
}

struct DeveloperChips: View {
    let chips: [DeveloperChip]

    var body: some View {
        WTFlowLayout(spacing: 8, alignment: .leading) {
            ForEach(chips) { chip in
                WTChip(chip.title, isSelected: chip.isSelected, action: chip.action)
                    .accessibilityIdentifier(chip.id)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Приглушене пояснення під рядком чи над карткою.
struct DeveloperNote: View {
    @Environment(\.wtTheme) private var theme
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(WTFont.text(13, .semibold))
            .foregroundStyle(theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }
}
