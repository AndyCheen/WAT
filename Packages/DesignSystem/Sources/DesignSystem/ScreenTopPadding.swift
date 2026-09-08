import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public extension View {
    /// Верхній відступ екрана — `WTSpacing.screenTop` від фізичного верху кадру,
    /// як у макетах (там немає системного статус-бару).
    ///
    /// Навмисно НЕ через `ScrollView.ignoresSafeArea()`: SwiftUI тоді змінює лише
    /// лейаут, а `UIScrollView` під капотом усе одно рахує власний `contentInset`
    /// від safe area. Після bounce скрол «осідає» на цьому internal inset, і
    /// відступ після відпускання подвоюється (WAT-31). Тому ScrollView лишається
    /// повністю дефолтним — safe area читаємо напряму з key window (GeometryReader
    /// для цього ненадійний: залежно від контейнера — NavigationStack тощо —
    /// `safeAreaInsets` у ньому мовчки повертає 0) і просто зменшуємо явний
    /// padding на її висоту.
    func wtScreenTopPadding() -> some View {
        padding(.top, max(0, WTSpacing.screenTop - Self.wtKeyWindowSafeAreaTop))
    }

    private static var wtKeyWindowSafeAreaTop: CGFloat {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
        #else
        0
        #endif
    }
}
