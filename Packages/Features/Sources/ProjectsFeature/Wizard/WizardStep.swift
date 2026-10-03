import SwiftUI
import Domain

public enum WizardStep: Int, CaseIterable, Sendable {
    case jobType = 1, customer, location, scope, timeline, labour, material, otherCosts, price, deposit, schedule, review

    public var titleKey: LocalizedStringKey {
        switch self {
        case .jobType: return "wizard.step.jobType"
        case .customer: return "wizard.step.customer"
        case .location: return "wizard.step.location"
        case .scope: return "wizard.step.scope"
        case .timeline: return "wizard.step.timeline"
        case .labour: return "wizard.step.labour"
        case .material: return "wizard.step.material"
        case .otherCosts: return "wizard.step.otherCosts"
        case .price: return "wizard.step.price"
        case .deposit: return "wizard.step.deposit"
        case .schedule: return "wizard.step.schedule"
        case .review: return "wizard.step.review"
        }
    }

    public var isRequired: Bool { [.jobType, .customer, .location, .price].contains(self) }

    public var requiredFields: Set<DraftField> {
        switch self {
        case .jobType: return [.jobType, .customJobType]
        case .customer: return [.customer]
        case .location: return [.addressLine]
        case .price: return [.contractValue]
        default: return []
        }
    }

    public static let total = WizardStep.allCases.count
    public var next: WizardStep? { WizardStep(rawValue: rawValue + 1) }
    public var previous: WizardStep? { WizardStep(rawValue: rawValue - 1) }

    /// The step that owns a missing field (for "Fix" buttons on Review).
    public static func owning(_ field: DraftField) -> WizardStep {
        switch field {
        case .jobType, .customJobType: return .jobType
        case .customer: return .customer
        case .addressLine: return .location
        case .contractValue: return .price
        }
    }
}
