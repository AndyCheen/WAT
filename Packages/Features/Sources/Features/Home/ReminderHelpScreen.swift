import SwiftUI
import Notifications
import DesignSystem

/// Тексти вікна «Нагадувань забагато?» (WAT-67, SPEC-NOTIFICATIONS §32): на «ти», без роду (§14.1).
enum ReminderHelpPresenter {
    static let glyph = "🔕"
    static let title = "Нагадувань забагато?"
    static let subtitle = "За тиждень вони майже не допомагали — воду ти записуєш і без них. Залишимо лише потрібне?"
    static let rarer = "Рідше й без повторних"
    static let checkpointsOnly = "Лише чекпоінти й вечір"
    static let keep = "Лишити як є"

    static func toast(_ choice: NotificationService.ReminderHelpChoice) -> String? {
        switch choice {
        case .rarer: return "Нагадування — рідше й без повторних"
        case .checkpointsOnly: return "Лишились чекпоінти й вечірній підсумок"
        case .keep: return nil
        }
    }
}

/// Разове питання, коли нагадування за тиждень майже не допомагали (WAT-67, SPEC-NOTIFICATIONS §32).
///
/// На весь екран і мінімум усього, як «Графік дня»: питання, одне речення, три відповіді. Рідшають нагадування
/// й без відповіді — питання, щоб людина вирішила сама; ✕ — те саме, що «Лишити як є» без відмови від адаптації.
struct ReminderHelpScreen: View {
    @Environment(\.wtTheme) private var theme
    let model: HomeViewModel

    var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()
            WTBubbles().ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    WTCircleButton(action: { model.dismissSheet() }) {
                        WTIcons.close(color: theme.accent)
                    }
                    .accessibilityLabel("Закрити")
                    .accessibilityIdentifier("reminderHelp.close")
                    Spacer()
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    WTGlyphBadge(ReminderHelpPresenter.glyph)
                        .padding(.bottom, 22)
                        .wtStoryAppear(pop: true)
                    Text(ReminderHelpPresenter.title)
                        .font(WTFont.display(28, .bold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("reminderHelp.title")
                        .wtStoryAppear(delay: 0.1)
                    Text(ReminderHelpPresenter.subtitle)
                        .font(WTFont.text(15, .bold))
                        .foregroundStyle(theme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .wtStoryAppear(delay: 0.18)
                }
                Spacer(minLength: 0)
                VStack(spacing: 16) {
                    WTPrimaryButton(ReminderHelpPresenter.rarer) { model.answerReminderHelp(.rarer) }
                        .accessibilityIdentifier("reminderHelp.rarer")
                    HStack(spacing: 28) {
                        Button(ReminderHelpPresenter.checkpointsOnly) { model.answerReminderHelp(.checkpointsOnly) }
                            .foregroundStyle(theme.textButton)
                            .accessibilityIdentifier("reminderHelp.checkpointsOnly")
                        Button(ReminderHelpPresenter.keep) { model.answerReminderHelp(.keep) }
                            .foregroundStyle(theme.textMuted)
                            .accessibilityIdentifier("reminderHelp.keep")
                    }
                    .font(WTFont.text(15, .heavy))
                    .buttonStyle(WTPressStyle(scale: 0.96))
                }
            }
            .padding(.horizontal, WTSpacing.screenSideHome)
            .padding(.bottom, WTSpacing.screenBottom)
        }
    }
}
