import SwiftUI

public extension View {
    /// Навігація в застосунку — власна (макети мають свою шапку).
    /// Модифікатори системного навбару доступні лише на iOS, тому загорнуті.
    @ViewBuilder
    func wtHideNavigationBar() -> some View {
        #if os(iOS)
        self
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
