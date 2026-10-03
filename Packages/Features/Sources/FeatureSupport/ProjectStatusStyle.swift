import SwiftUI
import Domain
import DesignSystem

public extension ProjectStatus {
    var titleKey: LocalizedStringKey { LocalizedStringKey("status." + rawValue) }

    /// One-line explanation shown in the status picker (`status.<raw>.hint`).
    var hintKey: LocalizedStringKey { LocalizedStringKey("status." + rawValue + ".hint") }

    var tone: DSTone {
        switch self {
        case .estimate, .awaitingApproval: return .neutral
        case .awaitingDeposit, .awaitingFinalPayment: return .warning
        case .scheduled: return .info
        case .inProgress: return .accent
        case .onHold, .waitingForInspection, .waitingForMaterial, .waitingForClient: return .warning
        case .completed, .closed: return .success
        case .cancelled: return .danger
        }
    }
}
