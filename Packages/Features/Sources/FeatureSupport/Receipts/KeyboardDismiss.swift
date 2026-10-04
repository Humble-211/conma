import UIKit

public enum KeyboardDismiss {
    @MainActor public static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
