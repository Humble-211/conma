import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Category icon, vendor (or category name), project, total and the receipt marker.
struct ExpenseRowView: View {
    let row: ExpenseRow

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: row.choice.systemImage).frame(width: 32, height: 32).foregroundStyle(DSColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                title.font(DSTypography.callout).foregroundStyle(DSColor.textPrimary).lineLimit(1)
                Text(verbatim: row.projectName).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(amount: row.total.amount, currencyCode: row.total.currency.rawValue, style: .callout)
                    .foregroundStyle(DSColor.textPrimary)
                if row.receiptCount > 0 {
                    Label { Text("expenses.receipts \(row.receiptCount)") } icon: { Image(systemName: "paperclip") }
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .frame(minHeight: DSSpacing.minTouch)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        if let vendor = row.expense.vendorName, !vendor.isEmpty { return Text(verbatim: vendor) }
        return row.choice.title(customName: row.customCategoryName)
    }
}
