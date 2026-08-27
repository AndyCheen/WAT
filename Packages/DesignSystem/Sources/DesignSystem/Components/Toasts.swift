import SwiftUI

/// Тост із необовʼязковою дією — «Порцію видалено · Скасувати».
///
/// У макетах його немає: там видалення безповоротне, хоча в базі це `soft delete`.
/// Дає користувачу шлях назад і не потребує окремого екрана.
public struct WTToast: View {
    @Environment(\.wtTheme) private var theme
    private let message: String
    private let actionTitle: String?
    private let duration: Double
    private let onAction: (() -> Void)?
    private let onDismiss: () -> Void

    public init(
        _ message: String,
        actionTitle: String? = nil,
        // Тост зі скасуванням треба встигнути прочитати й натиснути.
        duration: Double = 5,
        onAction: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.duration = duration
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(WTFont.text(14, .bold))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("toast.message")

            if let actionTitle, let onAction {
                Button {
                    onAction()
                    onDismiss()
                } label: {
                    Text(actionTitle)
                        .font(WTFont.display(14, .semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WTPressStyle(scale: 0.94))
                .accessibilityIdentifier("toast.action")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, actionTitle == nil ? 16 : 4)
        .padding(.vertical, actionTitle == nil ? 14 : 6)
        .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous))
        .wtShadow(.card)
        .overlay(
            RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        // Ідентифікатора на контейнері тут свідомо немає: він успадковується дочірніми
        // й перекриває їхні власні — на цьому вже спотикались шторки (PLAN.md, §«Що зʼясувалося»).
        // `.task(id:)` знімається разом зі зникненням тоста, тож повторний показ
        // не тягне за собою «хвіст» від попереднього таймера.
        .task(id: message) {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
