/// Wizard step 8 "Other costs" kinds (spec 3.1) mapped onto the single cost taxonomy.
public enum OtherCostKind: String, Codable, Sendable, CaseIterable, Hashable {
    case subcontractors, equipmentRental, toolRental, permits, inspectionFees
    case dumpster, delivery, parking, gas, wasteDisposal, other

    public var costGroup: CostGroup {
        switch self {
        case .subcontractors: return .subcontractor
        case .equipmentRental, .toolRental: return .equipment
        case .permits, .inspectionFees: return .permit
        case .dumpster, .delivery, .parking, .gas, .wasteDisposal, .other: return .other
        }
    }
}
