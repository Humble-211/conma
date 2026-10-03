import SwiftUI
import Domain

public extension OtherCostKind { var titleKey: LocalizedStringKey { LocalizedStringKey("otherCost." + rawValue) } }
public extension PaymentScheduleTemplate { var titleKey: LocalizedStringKey { LocalizedStringKey("schedule.template." + rawValue) } }

public enum RowLabel {
    /// Labels starting with `schedule.row.` are catalog keys; anything else is user text.
    public static func text(_ label: String) -> Text {
        label.hasPrefix("schedule.row.") ? Text(LocalizedStringKey(label)) : Text(verbatim: label)
    }
}

public extension DraftScheduleRow { var displayLabel: Text { RowLabel.text(label) } }
public extension ProjectEstimateLine { var displayLabel: Text { RowLabel.text(label) } }
