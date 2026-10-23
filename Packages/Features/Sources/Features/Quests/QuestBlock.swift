import Foundation
import Gamification

/// Що показує блок «ЗАВДАННЯ» головного (SPEC-QUESTS §9.1, варіант A) на цю мить — чиста функція від дошки, часу,
/// свята й перемикача «Виконані · N». Окремо від екрана: правила порожніх станів легко переплутати, а тут їх видно
/// тестам.
struct QuestBlock: Equatable {
    struct Section: Equatable {
        var rows: [QuestSnapshot]
        /// Замість рядків: «Усе на сьогодні 🎉», «Тиждень закрито 🎉», «Тижневі завдання — з понеділка».
        var empty: String?
    }

    /// `nil` — секції «Сьогодні» немає: щоденних ще не видано або вони зникли за дедлайном, хоч одне не виконано.
    /// «Провалено» не кажемо, виконане лежить у «Виконані · N».
    var today: Section?
    var week: Section?
    /// «· ЩЕ 5 ДН.» у підписі тижня — лише коли тижневі є.
    var weekDaysLeft: Int?
    var completedCount: Int

    /// Без жодного рядка й без виконаних блоку немає зовсім, разом із заголовком.
    var isEmpty: Bool { today == nil && week == nil && completedCount == 0 }

    static let empty = QuestBlock(today: nil, week: nil, weekDaysLeft: nil, completedCount: 0)

    /// - Parameters:
    ///   - now: дошку зібрано в `reload()`, а дедлайн може минути, поки екран відкритий, — тож живі рядки
    ///     відсіюються ще раз на цю хвилину.
    ///   - celebrating: щойно виконані дією — ще в списку, поки святкують (§9.2), або чекають вікна досягнення.
    static func make(board: QuestBoard, now: Date, celebrating: Set<UUID>, showCompleted: Bool) -> QuestBlock {
        let visible = { (quest: QuestSnapshot) in !quest.isDone || showCompleted || celebrating.contains(quest.id) }

        let daily = board.daily.filter { $0.isDone || ($0.deadline.map { $0 > now } ?? true) }
        let expired = board.expiredDaily + (board.daily.count - daily.count)
        let dailyRows = daily.filter(visible)
        let today: Section?
        if !dailyRows.isEmpty {
            today = Section(rows: dailyRows)
        } else if !daily.isEmpty, expired == 0 {
            // Рядків немає, а невиконаних не буває невидимими — отже, виконано все.
            today = Section(rows: [], empty: QuestPresenter.allDailyDone)
        } else {
            today = nil
        }

        let week: Section?
        if board.weekly.isEmpty {
            week = board.weeklyStartsMonday ? Section(rows: [], empty: QuestPresenter.weeklyFromMonday) : nil
        } else {
            let rows = board.weekly.filter(visible)
            week = Section(rows: rows, empty: rows.isEmpty ? QuestPresenter.weekClosed : nil)
        }

        return QuestBlock(
            today: today, week: week,
            weekDaysLeft: board.weekly.isEmpty ? nil : board.weekDaysLeft,
            completedCount: daily.filter(\.isDone).count + board.weekly.filter(\.isDone).count
        )
    }
}

extension QuestBlock.Section {
    init(rows: [QuestSnapshot]) { self.init(rows: rows, empty: nil) }
}
