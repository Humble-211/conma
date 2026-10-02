import SwiftUI
import DesignSystem

public struct ProjectsPlaceholderView: View {
    public init() {}
    public var body: some View {
        EmptyState(systemImage: "folder", title: "projects.empty.title", message: "projects.empty.message")
            .background(DSColor.background)
            .navigationTitle("projects.title")
    }
}
