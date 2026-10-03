import SwiftUI
import Domain

public extension OtherCostKind {
    var labelKeyString: String { "otherCost." + rawValue } // lint:allow-string
    var titleKey: LocalizedStringKey { LocalizedStringKey(labelKeyString) }
}
public extension PaymentScheduleTemplate { var titleKey: LocalizedStringKey { LocalizedStringKey("schedule.template." + rawValue) } }

public enum RowLabel {
    /// Labels starting with `schedule.row.` or `otherCost.` are catalog keys; anything else is user text.
    public static func text(_ label: String) -> Text {
        let isKey = label.hasPrefix("schedule.row.") || label.hasPrefix("otherCost.") // lint:allow-string
        return isKey ? Text(LocalizedStringKey(label)) : Text(verbatim: label)
    }
}

public extension DraftScheduleRow { var displayLabel: Text { RowLabel.text(label) } }
public extension ProjectEstimateLine { var displayLabel: Text { RowLabel.text(label) } }
