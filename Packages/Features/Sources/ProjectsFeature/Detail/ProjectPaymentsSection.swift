import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Project detail's Payments card (spec §5.3): every live payment newest first, "Record payment", not-linked total.
struct ProjectPaymentsSection: View {
    let list: ProjectPaymentList?
    let onAdd: () -> Void
    let onEdit: (UUID) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("detail.payments.title").font(DSTypography.headline)
                    Spacer()
                    Button(action: onAdd) { Label("detail.payments.add", systemImage: "plus") }
                        .font(DSTypography.callout)
                        .frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("detail_payments_add")
                }
                if let list {
                    if list.rows.isEmpty {
                        Text("detail.payments.empty")
                            .font(DSTypography.callout)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityIdentifier("detail_payments_empty")
                    } else {
                        ForEach(Array(list.rows.enumerated()), id: \.element.id) { index, row in
                            Button { onEdit(row.id) } label: { PaymentRowView(row: row) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("detail_payment_row_\(index)")
                        }
                        if list.unallocated.amount > 0 {
                            Text("detail.payments.unallocated \(MoneyFormat.string(list.unallocated.amount, currencyCode: list.unallocated.currency.rawValue, locale: locale))")
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColor.textSecondary)
                                .accessibilityIdentifier("detail_payments_unallocated")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_payments")
    }
}

/// Stage (or "Not linked to a stage"), date · method, amount.
struct PaymentRowView: View {
    let row: PaymentRow
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "banknote").frame(width: 32, height: 32).foregroundStyle(DSColor.success)
            VStack(alignment: .leading, spacing: 2) {
                (row.itemLabel.map { RowLabel.text($0) } ?? Text("detail.payments.notLinked"))
                    .font(DSTypography.callout).foregroundStyle(DSColor.textPrimary).lineLimit(1)
                HStack(spacing: DSSpacing.xs) {
                    DateLabel(row.payment.paidOn.noonDate(in: timeZone))
                    Text(verbatim: "·")
                    Text(row.payment.method.titleKey)
                }
                .font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
            }
            Spacer()
            MoneyText(amount: row.payment.amount.amount, currencyCode: row.payment.amount.currency.rawValue, style: .callout)
                .foregroundStyle(DSColor.textPrimary)
        }
        .frame(minHeight: DSSpacing.minTouch)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
