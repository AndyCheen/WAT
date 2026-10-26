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

public extension View {
    /// Цифрова клавіатура (точний ввід у «Інше», WAT-50). `keyboardType` є лише на iOS, а пакети
    /// тестуються й на macOS.
    @ViewBuilder
    func wtNumberPad() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }
}

public extension View {
    /// Поле ключа чи пошуку — без великої літери й автозаміни (режим розробника, WAT-68). Як і `keyboardType`,
    /// `textInputAutocapitalization` є лише на iOS.
    @ViewBuilder
    func wtPlainTextInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}
