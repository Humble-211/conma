import Foundation

public enum ProgressCalculator {
    /// completed / total, rounded half-up to a whole percent. Manual progress overrides.
    public static func percent(tasks: [ProjectTask], manualProgress: Int?) -> Int {
        if let manual = manualProgress { return min(max(manual, 0), 100) }
        let live = tasks.filter { !$0.isDeleted }
        guard !live.isEmpty else { return 0 }
        let completed = live.filter { $0.status == .completed }.count
        let ratio = Decimal(completed) / Decimal(live.count) * 100
        return NSDecimalNumber(decimal: Money.rounded(ratio, scale: 0)).intValue
    }
}
