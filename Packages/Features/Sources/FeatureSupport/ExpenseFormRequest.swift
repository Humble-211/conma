import Foundation

/// Opens the expense flow from Home, the Expenses tab or a project (presented with `fullScreenCover(item:)`).
public enum ExpenseFormRequest: Identifiable, Hashable {
    case create(projectId: UUID?)
    case edit(UUID)

    public var id: String {
        switch self {
        case .create(let projectId): return "create:" + (projectId?.uuidString ?? "")
        case .edit(let id): return "edit:" + id.uuidString
        }
    }
}
