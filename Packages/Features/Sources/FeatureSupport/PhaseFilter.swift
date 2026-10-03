import SwiftUI
import Domain

public enum PhaseFilter: String, CaseIterable, Sendable {
    case all, inWork, preStart, workDone, terminal
    public var titleKey: LocalizedStringKey { LocalizedStringKey("projects.filter." + rawValue) }
    public func matches(_ status: ProjectStatus) -> Bool {
        switch self {
        case .all: return true
        case .inWork: return status.phase == .inWork
        case .preStart: return status.phase == .preStart
        case .workDone: return status.phase == .workDone
        case .terminal: return status.phase == .terminal
        }
    }
}
