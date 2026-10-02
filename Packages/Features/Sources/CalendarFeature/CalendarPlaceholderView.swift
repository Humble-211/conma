import SwiftUI
import DesignSystem

public struct CalendarPlaceholderView: View {
    public init() {}
    public var body: some View {
        EmptyState(systemImage: "calendar", title: "calendar.empty.title", message: "calendar.empty.message")
            .background(DSColor.background)
            .navigationTitle("calendar.title")
    }
}
