import SwiftUI
import DesignSystem

public struct ExpensesPlaceholderView: View {
    public init() {}
    public var body: some View {
        EmptyState(systemImage: "receipt", title: "expenses.empty.title", message: "expenses.empty.message")
            .background(DSColor.background)
            .navigationTitle("expenses.title")
    }
}
