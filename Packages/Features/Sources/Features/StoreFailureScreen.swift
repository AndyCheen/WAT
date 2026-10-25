import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Persistence
import DesignSystem

/// Сховище не відкрилося (WAT-67): замість тихої бази в пам'яті, де людина побачила б онбординг і порожню історію,
/// а все записане зникло б із перезапуском, — чесне вікно. Файли сховища на місці, а перед відкриттям новою схемою
/// лишилась копія (`Database.backupIfSchemaChanged`), тож оновлена збірка їх підхопить.
///
/// Тема — системна: профіль у сховищі, якого не відкрили.
public struct StoreFailureScreen: View {
    private let details: String
    @State private var copied = false

    public init(details: String) {
        self.details = details
    }

    public var body: some View {
        WTThemedContainer(mode: .system) {
            StoreFailureContent(details: details, copied: $copied)
        }
    }
}

private struct StoreFailureContent: View {
    @Environment(\.wtTheme) private var theme
    let details: String
    @Binding var copied: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            WTGlyphBadge("🗄️")
                .padding(.bottom, 22)
            Text("Не вдалося відкрити твої записи")
                .font(WTFont.display(28, .bold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("storeFailure.title")
            Text("Вони на місці — застосунок нічого не видаляв і нового не пише. Онови застосунок або надішли подробиці розробнику.")
                .font(WTFont.text(15, .bold))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Text(details)
                .font(WTFont.text(12, .semibold))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.leading)
                .lineLimit(6)
                .padding(.vertical, WTSpacing.cardPaddingV)
                .padding(.horizontal, WTSpacing.cardPaddingH)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.card, style: .continuous))
                .padding(.top, 24)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            WTPrimaryButton(copied ? "Скопійовано" : "Скопіювати подробиці") {
                #if canImport(UIKit)
                UIPasteboard.general.string = details
                #endif
                copied = true
            }
            .accessibilityIdentifier("storeFailure.copy")
        }
        .padding(.horizontal, WTSpacing.screenSideHome)
        .padding(.bottom, WTSpacing.screenBottom)
    }
}
