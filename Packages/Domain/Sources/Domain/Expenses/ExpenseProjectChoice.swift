import Foundation

public enum ExpenseProjectChoice {
    private static func rank(_ phase: ProjectPhase) -> Int {
        switch phase {
        case .inWork: return 0
        case .preStart: return 1
        case .workDone: return 2
        case .terminal: return 3
        }
    }

    /// Live projects for the picker: inWork, preStart, workDone, terminal; then by name.
    public static func ordered(_ projects: [Project]) -> [Project] {
        projects.filter { !$0.isDeleted }.sorted { a, b in
            let ra = rank(a.status.phase), rb = rank(b.status.phase)
            if ra != rb { return ra < rb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Spec §2 "Project mặc định": project of the most recently created live expense if it is live and not terminal;
    /// else the inWork project updated most recently; else nil.
    public static func defaultProject(expenses: [Expense], projects: [Project]) -> UUID? {
        let selectable = Set(projects.filter { !$0.isDeleted && $0.status.phase != .terminal }.map(\.id))
        let latest = expenses.filter { !$0.isDeleted }.max { ($0.createdAt, $0.spentOn) < ($1.createdAt, $1.spentOn) }
        if let latest, selectable.contains(latest.projectId) { return latest.projectId }
        return projects.filter { !$0.isDeleted && $0.status.phase == .inWork }.max { $0.updatedAt < $1.updatedAt }?.id
    }
}
