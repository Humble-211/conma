import Combine
import SwiftUI
import UIKit
import DesignSystem

/// Lifts a bottom bar (a form's Save button in `safeAreaInset`) clear of the keyboard toolbar while the keyboard is up.
/// From iOS 26 the toolbar's "Done" is a floating pill drawn over the content just above the keyboard,
/// so without this it covers the right end of the Save bar. Earlier systems draw a full-width bar that
/// already pushes the inset up, so nothing changes there.
private struct KeyboardToolbarClearance: ViewModifier {
    @State private var keyboardUp = false

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardUp ? DSSpacing.minTouch : 0)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if #available(iOS 26, *) { keyboardUp = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
    }
}

public extension View {
    func keyboardToolbarClearance() -> some View { modifier(KeyboardToolbarClearance()) }
}
