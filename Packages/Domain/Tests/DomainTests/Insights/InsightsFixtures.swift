// Packages/Domain/Tests/DomainTests/Insights/InsightsFixtures.swift
import Foundation
@testable import Domain

enum Fx {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let today = CalendarDate(storage: "2026-10-03")!
    static let companyId = UUID()
    static let cad = CurrencyCode.cad

    static func day(_ offset: Int) -> CalendarDate { today.adding(days: offset) }
    static func money(_ v: Int, _ c: CurrencyCode = .cad) -> Money { Money(Decimal(v), c) }
    static func moneyS(_ s: String, _ c: CurrencyCode = .cad) -> Money { Money(Decimal(string: s)!, c) }

    static func customer(_ name: String) -> Customer {
        Customer(id: UUID(), companyId: companyId, name: name, phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    static func project(_ name: String, customer: Customer, status: ProjectStatus, contract: Int, progress: Int?, start: Int?, end: Int?, currency: CurrencyCode = .cad, updatedAt: Date = now) -> Project {
        Project(id: UUID(), companyId: companyId, customerId: customer.id, name: name, jobType: .kitchen, customJobType: nil, status: status,
                address: Address(line: name, unit: nil, city: nil, region: nil, postalCode: nil), scopeDescription: nil, scopeFields: [],
                startDate: start.map(day), estimatedCompletionDate: end.map(day), workingDays: nil, hoursPerDay: nil, workersPerDay: nil,
                contractValue: money(contract, currency), manualProgress: progress, depositRequiredToStart: false, createdAt: now, updatedAt: updatedAt, deletedAt: nil)
    }
    static func line(_ p: Project, _ group: CostGroup, _ amount: Int, order: Int = 0) -> ProjectEstimateLine {
        ProjectEstimateLine(id: UUID(), companyId: companyId, projectId: p.id, costGroup: group, label: "\(group)", amount: money(amount), quantity: nil, unitRate: nil, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    static func item(_ p: Project, _ label: String, _ amount: Int, due: Int?, deposit: Bool = false, order: Int = 0, deletedAt: Date? = nil) -> PaymentScheduleItem {
        PaymentScheduleItem(id: UUID(), companyId: companyId, projectId: p.id, label: label, amount: money(amount), percentage: nil, dueDate: due.map(day), triggerText: nil, isDeposit: deposit, notes: nil, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: deletedAt)
    }
    static func expense(_ p: Project, _ group: CostGroup, amount: Int, tax: Int, deletedAt: Date? = nil) -> Expense {
        Expense(id: UUID(), companyId: companyId, projectId: p.id, category: .materials, customCategoryId: nil, costGroup: group, vendorName: nil, amount: money(amount), tax: money(tax), spentOn: today, paymentMethod: nil, notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: deletedAt)
    }
    static func labour(_ p: Project, days: Int, rate: Int) -> LabourEntry {
        LabourEntry(id: UUID(), companyId: companyId, projectId: p.id, employeeId: UUID(), workDate: today, days: Decimal(days), dailyRate: money(rate), notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    static func payment(_ p: Project, _ amount: Int, item: UUID?, deletedAt: Date? = nil) -> Payment {
        Payment(id: UUID(), companyId: companyId, projectId: p.id, scheduleItemId: item, amount: money(amount), paidOn: today, method: .eTransfer, notes: nil, createdAt: now, updatedAt: now, deletedAt: deletedAt)
    }

    /// Spec §4 Basement: contract 38,000; estimates 6,000/7,900/900; expenses 2,400+312, 1,500+195 (material), 600+78 (other); labour 8×250, 10×220, 7×200; deposit 7,600 paid; stage2 11,400 overdue 5 days.
    struct Basement {
        let customer = Fx.customer("Ann Lee")
        let project: Project
        let lines: [ProjectEstimateLine]
        let items: [PaymentScheduleItem]
        let expenses: [Expense]
        let labour: [LabourEntry]
        let payments: [Payment]
        init() {
            project = Fx.project("Basement Renovation", customer: customer, status: .inProgress, contract: 38_000, progress: 65, start: -18, end: 27)
            lines = [Fx.line(project, .labour, 2000), Fx.line(project, .labour, 2200, order: 1), Fx.line(project, .labour, 1800, order: 2),
                     Fx.line(project, .material, 2500), Fx.line(project, .material, 1600, order: 1), Fx.line(project, .material, 3000, order: 2), Fx.line(project, .material, 800, order: 3),
                     Fx.line(project, .other, 600), Fx.line(project, .other, 300, order: 1)]
            let deposit = Fx.item(project, "schedule.row.deposit", 7600, due: -20, deposit: true, order: 0)
            items = [deposit, Fx.item(project, "schedule.row.stage2", 11_400, due: -5, order: 1), Fx.item(project, "schedule.row.stage3", 11_400, due: 10, order: 2), Fx.item(project, "schedule.row.final", 7600, due: nil, order: 3)]
            expenses = [Fx.expense(project, .material, amount: 2400, tax: 312), Fx.expense(project, .material, amount: 1500, tax: 195), Fx.expense(project, .other, amount: 600, tax: 78)]
            labour = [Fx.labour(project, days: 8, rate: 250), Fx.labour(project, days: 10, rate: 220), Fx.labour(project, days: 7, rate: 200)]
            payments = [Fx.payment(project, 7600, item: deposit.id)]
        }
        var inputs: ProjectInsightsInputs {
            ProjectInsightsInputs(project: project, estimateLines: lines, scheduleItems: items, expenses: expenses, labourEntries: labour, payments: payments, today: Fx.today)
        }
    }
}
