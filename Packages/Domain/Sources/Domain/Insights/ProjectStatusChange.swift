import Foundation

public struct StatusChangeOutcome: Hashable, Sendable {
    public let project: Project
    public let suggestProgress100: Bool
    public let requiresConfirmation: Bool
}

public enum ProjectStatusChange {
    public static func apply(_ project: Project, to status: ProjectStatus) -> StatusChangeOutcome {
        var p = project; p.status = status
        let workDone = status == .completed || status == .awaitingFinalPayment
        return StatusChangeOutcome(project: p, suggestProgress100: workDone && project.manualProgress == nil, requiresConfirmation: status == .closed || status == .cancelled)
    }
    public static func setManualProgress(_ project: Project, to value: Int?) throws -> Project {
        if let v = value, !(0...100).contains(v) { throw DomainError.invalidProgress }
        var p = project; p.manualProgress = value; return p
    }
}
