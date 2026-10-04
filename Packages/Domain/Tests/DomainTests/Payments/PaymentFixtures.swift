import Foundation
@testable import Domain

enum Pay {
    static func payment(_ project: Project, _ amount: String, item: UUID?, on day: String = "2026-10-03", method: PaymentMethod = .eTransfer,
                        createdAt: Date = Fx.now, deletedAt: Date? = nil) -> Payment {
        Payment(id: UUID(), companyId: Fx.companyId, projectId: project.id, scheduleItemId: item, amount: Fx.moneyS(amount),
                paidOn: CalendarDate(storage: day)!, method: method, notes: nil, createdAt: createdAt, updatedAt: createdAt, deletedAt: deletedAt)
    }
}
