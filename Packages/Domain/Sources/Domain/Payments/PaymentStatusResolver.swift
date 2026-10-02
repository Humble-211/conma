public enum PaymentStatus: String, Sendable, Hashable, CaseIterable {
    case upcoming, dueSoon, dueToday, overdue, partiallyPaid, paid
}

public enum PaymentStatusResolver {
    /// Spec 5.4 table, evaluated top to bottom; the first matching row wins.
    public static func status(item: PaymentScheduleItem, paidForItem: Money, today: CalendarDate) -> PaymentStatus {
        if paidForItem.amount >= item.amount.amount { return .paid }
        if let due = item.dueDate, today > due { return .overdue }
        if paidForItem.amount > 0 { return .partiallyPaid }
        guard let due = item.dueDate else { return .upcoming }
        let daysLeft = today.daysUntil(due)
        if daysLeft == 0 { return .dueToday }
        if (1...3).contains(daysLeft) { return .dueSoon }
        return .upcoming
    }
}
