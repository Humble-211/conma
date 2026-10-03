import Foundation

public enum ActivityDetail: Hashable, Sendable {
    case statusChanged(from: ProjectStatus, to: ProjectStatus)
    case progressChanged(from: Int?, to: Int?)
    case contractValueChanged(from: String, to: String)
    case estimateChanged(group: CostGroup?, from: String, to: String)
    case scheduleChanged(from: String, to: String)
    case customerChanged(fromName: String, toName: String)
    case plain(ActivityAction)
}

public enum ActivityDescription {
    public static func detail(for entry: ActivityLogEntry) -> ActivityDetail {
        guard let data = entry.detailsJSON.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .plain(entry.action) }
        func s(_ k: String) -> String? { obj[k] as? String }
        switch entry.action {
        case .statusChanged:
            guard let f = s("from").flatMap(ProjectStatus.init(rawValue:)), let t = s("to").flatMap(ProjectStatus.init(rawValue:)) else { return .plain(entry.action) }
            return .statusChanged(from: f, to: t)
        case .progressChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .progressChanged(from: f.isEmpty ? nil : Int(f), to: t.isEmpty ? nil : Int(t))
        case .contractValueChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .contractValueChanged(from: f, to: t)
        case .estimateChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .estimateChanged(group: s("group").flatMap(CostGroup.init(rawValue:)), from: f, to: t)
        case .scheduleChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .scheduleChanged(from: f, to: t)
        case .customerChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .customerChanged(fromName: f, toName: t)
        default: return .plain(entry.action)
        }
    }
}
