import Foundation
import Observation
import SwiftUI
import DesignSystem

/// Бібліотека «Знань»: «Продовжити» й полиці обкладинок (SPEC-LEARN §3, §6).
@MainActor
@Observable
final class LearnLibraryModel {
    struct Entry: Identifiable, Equatable {
        let story: LearnStory
        let badge: WTLearnBadge
        var id: String { story.id }
    }

    struct Shelf: Identifiable, Equatable {
        let shelf: LearnShelf
        let entries: [Entry]
        var id: String { shelf.rawValue }
        var readCount: Int { entries.filter { $0.badge == .read }.count }
    }

    private let services: AppServices
    private(set) var shelves: [Shelf] = []
    /// Незакінчена історія — картка «Продовжити».
    private(set) var resume: (story: LearnStory, slide: Int, count: Int)?

    init(services: AppServices) {
        self.services = services
    }

    /// Лише з `onAppear`, не з `init`: позначка «бачено» знімає «Нове», і друге читання вже не бачило б
    /// нових (CLAUDE.md, WAT-23).
    func reload() {
        let store = services.learn
        let visitedBefore = store.hasVisited
        let presenter = LearnPresenter(context: services.learnContext())
        resume = nil
        shelves = LearnShelf.allCases.map { shelf in
            Shelf(shelf: shelf, entries: LearnCatalog.stories(in: shelf).map { story in
                let progress = store.progress(story.id)
                let count = presenter.slides(for: story).count + 1
                let badge: WTLearnBadge
                if progress?.isCompleted == true {
                    badge = .read
                } else if let slide = progress?.lastSlide, slide > 0 {
                    badge = .progress(Double(slide) / Double(count - 1))
                    if resume == nil { resume = (story, slide, count) }
                } else if visitedBefore, progress == nil {
                    // До першого відкриття розділу «Нове» горіло б на всіх 12 — це шум, а не новина.
                    badge = .new
                } else {
                    badge = .none
                }
                return Entry(story: story, badge: badge)
            })
        }
        store.markSeen(LearnCatalog.stories.map(\.id), at: services.calendar.now)
    }
}

/// Одна історія: слайди, поточний слайд, відповіді вікторини, фініш.
@MainActor
@Observable
final class LearnStoryModel {
    let services: AppServices
    private(set) var story: LearnStory
    private(set) var slides: [LearnSlide] = []
    /// Відповідь на слайд вікторини: `true` — «Правда».
    private(set) var answers: [Int: Bool] = [:]
    var slideIndex = 0 {
        didSet { noteSlide() }
    }
    private var finished = false

    init(services: AppServices, storyId: String, startSlide: Int? = nil) {
        self.services = services
        story = LearnCatalog.story(storyId) ?? LearnCatalog.stories[0]
        load(startSlide: startSlide)
    }

    /// Слайди історії плюс службовий фініш.
    var count: Int { slides.count + 1 }
    var isFinish: Bool { slideIndex == slides.count }
    var next: LearnStory { LearnCatalog.next(after: story) }

    func style(at index: Int) -> WTStoryStyle {
        slides.indices.contains(index) ? slides[index].style : .plain
    }

    var quizCount: Int {
        slides.filter { if case .quiz = $0.kind { return true } else { return false } }.count
    }

    var correctAnswers: Int {
        answers.filter { index, answer in
            if case .quiz(let isTrue, _) = slides[index].kind { return answer == isTrue }
            return false
        }.count
    }

    func answer(_ value: Bool, at index: Int) {
        guard answers[index] == nil else { return }
        answers[index] = value
    }

    /// Кнопка «Що з цим робити» теж означає «дочитано»: далі людина вже в застосунку.
    func finish() {
        guard !finished else { return }
        finished = true
        services.finishLearnStory(story)
    }

    /// «Далі» на фініші — наступна історія в тому самому програвачі.
    func open(_ next: LearnStory) {
        withAnimation(WTAnimation.fade) {
            story = next
            answers = [:]
            finished = false
            load(startSlide: 0)
        }
    }

    func announceUnlocks() {
        services.announceUnlocks()
    }

    private func load(startSlide: Int?) {
        slides = LearnPresenter(context: services.learnContext()).slides(for: story)
        let progress = services.learn.progress(story.id)
        // Незакінчена відкривається з того слайда, де зупинилась; прочитана — з початку (§6).
        let resume = progress?.isCompleted == true ? 0 : progress?.lastSlide ?? 0
        slideIndex = min(max(0, startSlide ?? resume), slides.count)
    }

    private func noteSlide() {
        if isFinish {
            finish()
        } else if !finished {
            services.learn.saveSlide(slideIndex, of: story.id, at: services.calendar.now)
        }
    }
}
