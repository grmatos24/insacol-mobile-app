import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// Apply a keyboard type only on platforms where it's supported (iOS, visionOS).
    /// No-op on macOS.
    @ViewBuilder
    func appKeyboard(_ type: AppKeyboardType) -> some View {
        #if os(iOS) || os(visionOS)
        self.keyboardType(type.uiKeyboardType)
        #else
        self
        #endif
    }
}

enum AppKeyboardType {
    case `default`
    case decimal
    case numberPad
    case numbersAndPunctuation
    case email

    #if os(iOS) || os(visionOS)
    var uiKeyboardType: UIKeyboardType {
        switch self {
        case .default: .default
        case .decimal: .decimalPad
        case .numberPad: .numberPad
        case .numbersAndPunctuation: .numbersAndPunctuation
        case .email: .emailAddress
        }
    }
    #endif
}
