import Foundation

/// Opens the payment form (a sheet) from project detail, a schedule row or Home's attention row.
public enum PaymentFormRequest: Identifiable, Hashable {
    /// `scheduleItemId` nil = "Record payment" (default stage, empty focused amount); set = that stage with its remaining amount.
    case create(projectId: UUID, scheduleItemId: UUID?)
    case edit(UUID)

    public var id: String {
        switch self {
        case .create(let projectId, let item): return "create:" + projectId.uuidString + ":" + (item?.uuidString ?? "")
        case .edit(let id): return "edit:" + id.uuidString
        }
    }
}

/// Opens the labour form (a sheet) from the project's Labour card or list.
public enum LabourFormRequest: Identifiable, Hashable {
    case create(projectId: UUID)
    case edit(UUID)

    public var id: String {
        switch self {
        case .create(let projectId): return "create:" + projectId.uuidString
        case .edit(let id): return "edit:" + id.uuidString
        }
    }
}
