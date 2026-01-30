import SwiftUI

// MARK: - Cross-platform system background colors

extension Color {
    #if os(iOS)
    static let systemGroupedBg = Color(uiColor: .systemGroupedBackground)
    static let secondarySystemGroupedBg = Color(uiColor: .secondarySystemGroupedBackground)
    static let tertiarySystemGroupedBg = Color(uiColor: .tertiarySystemGroupedBackground)
    #elseif os(macOS)
    static let systemGroupedBg = Color(nsColor: .controlBackgroundColor)
    static let secondarySystemGroupedBg = Color(nsColor: .windowBackgroundColor)
    static let tertiarySystemGroupedBg = Color(nsColor: .underPageBackgroundColor)
    #endif
}

// MARK: - Cross-platform clipboard

enum PlatformPasteboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

// MARK: - Cross-platform View modifiers

extension View {
    /// `.navigationBarTitleDisplayMode(.inline)` — no-op on macOS.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// `.keyboardType(...)` — no-op on macOS.
    @ViewBuilder
    func mobileKeyboard(_ type: MobileKeyboardType) -> some View {
        #if os(iOS)
        switch type {
        case .numberPad:    self.keyboardType(.numberPad)
        case .decimalPad:   self.keyboardType(.decimalPad)
        case .phonePad:     self.keyboardType(.phonePad)
        case .emailAddress: self.keyboardType(.emailAddress)
        }
        #else
        self
        #endif
    }

    /// `.textInputAutocapitalization(...)` — no-op on macOS.
    @ViewBuilder
    func mobileAutocapitalization(_ style: MobileAutocapStyle) -> some View {
        #if os(iOS)
        switch style {
        case .never:      self.textInputAutocapitalization(.never)
        case .characters: self.textInputAutocapitalization(.characters)
        }
        #else
        self
        #endif
    }
}

enum MobileKeyboardType {
    case numberPad, decimalPad, phonePad, emailAddress
}

enum MobileAutocapStyle {
    case never, characters
}
