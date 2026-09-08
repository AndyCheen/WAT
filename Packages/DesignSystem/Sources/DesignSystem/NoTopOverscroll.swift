import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public extension View {
    /// Забороняє bounce (гумовий відтяг) у верхній частині скролу — можна було
    /// відтягнути вниз і "провалитись" у порожнечу над контентом, навіть коли
    /// там більше нічого немає. Bounce знизу (коли контент довший за екран)
    /// лишається звичайним.
    ///
    /// SwiftUI не дає модифікатора для одного краю окремо — `scrollBounceBehavior`
    /// керує обома одразу. Тому чіпляємось напряму до нативного `UIScrollView`,
    /// який `ScrollView` ховає під капотом (view-ієрархія — крихкий, але
    /// єдиний доступний спосіб), і в делегаті обрізаємо `contentOffset.y`
    /// знизу нулем.
    func wtNoTopOverscroll() -> some View {
        background(WTTopOverscrollClamp())
    }
}

#if canImport(UIKit)
private struct WTTopOverscrollClamp: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        probe.isHidden = true
        // ScrollView ще не встиг вставити цей probe у власну view-ієрархію
        // синхронно — шукаємо предка на наступному тіку runloop.
        DispatchQueue.main.async { [weak probe] in
            guard let probe else { return }
            context.coordinator.attach(near: probe)
        }
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private weak var scrollView: UIScrollView?
        private weak var previousDelegate: UIScrollViewDelegate?

        func attach(near view: UIView) {
            guard scrollView == nil else { return }
            var current = view.superview
            while let candidate = current {
                if let found = candidate as? UIScrollView {
                    scrollView = found
                    previousDelegate = found.delegate
                    found.delegate = self
                    return
                }
                current = candidate.superview
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Стан спокою — це НЕ 0, а -adjustedContentInset.top (тут ~59pt
            // safe area). Обрізати до 0 стягує контент угору й ховає шапку
            // під статус-бар/Dynamic Island замість заборони bounce.
            let minOffsetY = -scrollView.adjustedContentInset.top
            if scrollView.contentOffset.y < minOffsetY {
                scrollView.contentOffset.y = minOffsetY
            }
            previousDelegate?.scrollViewDidScroll?(scrollView)
        }
    }
}
#else
private struct WTTopOverscrollClamp: View {
    var body: some View { Color.clear }
}
#endif
