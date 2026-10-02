public enum ProjectPhase: Sendable, Hashable { case preStart, inWork, workDone, terminal }

public enum ProjectStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case estimate, awaitingApproval, awaitingDeposit
    case scheduled, inProgress, onHold, waitingForInspection, waitingForMaterial, waitingForClient
    case completed, awaitingFinalPayment
    case closed, cancelled

    public var phase: ProjectPhase {
        switch self {
        case .estimate, .awaitingApproval, .awaitingDeposit: return .preStart
        case .scheduled, .inProgress, .onHold, .waitingForInspection, .waitingForMaterial, .waitingForClient: return .inWork
        case .completed, .awaitingFinalPayment: return .workDone
        case .closed, .cancelled: return .terminal
        }
    }
}

public enum TaskStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case notStarted, scheduled, inProgress, blocked, waiting, completed
}

public enum PaymentMethod: String, Codable, Sendable, CaseIterable, Hashable {
    case cash, cheque, eTransfer, creditCard, bankTransfer, other
}

public enum PhotoCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case before, progress, issues, inspection, completed, receipts
}

public enum JobType: String, Codable, Sendable, CaseIterable, Hashable {
    case generalRenovation, basementRenovation, kitchen, bathroom, landscaping
    case roofing, plumbing, electrical, hvac, flooring, painting, drywall, concrete
    case deckFence, framing, windowsDoors, exterior, demolition, commercial, other
}

/// The single cost taxonomy shared by estimates, actual cost and budget alerts.
public enum CostGroup: String, Codable, Sendable, CaseIterable, Hashable {
    case material, labour, subcontractor, equipment, permit, other
}

public enum ExpenseCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case materials, labour, subcontractor, equipmentRental, toolPurchase, permit, inspection
    case delivery, fuel, wasteDisposal, parking, office, other
    case custom

    /// Spec 5.2 mapping table. `nil` for `custom`: the group comes from the custom category.
    public var defaultCostGroup: CostGroup? {
        switch self {
        case .materials: return .material
        case .labour: return .labour
        case .subcontractor: return .subcontractor
        case .equipmentRental, .toolPurchase: return .equipment
        case .permit, .inspection: return .permit
        case .delivery, .fuel, .wasteDisposal, .parking, .office, .other: return .other
        case .custom: return nil
        }
    }
}

public enum ContactMethod: String, Codable, Sendable, CaseIterable, Hashable { case phone, text, email }
public enum UserRole: String, Codable, Sendable, CaseIterable, Hashable { case owner }
public enum SyncState: String, Codable, Sendable, CaseIterable, Hashable { case pending, synced }
