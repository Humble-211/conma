# Sub-project 2b — Dashboard & detail full — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home dashboard (attention, company totals, project cards with money + health), project detail with Financial summary / Health / Timeline / Activity, manual status & progress, change customer, delete project — on top of 2a data, reading the (still empty) expenses/labour/payments tables.

**Architecture:** One GRDB `ValueObservation` per screen emits a `Snapshot` of every related table; the VM attaches `today` and runs a pure Domain composer (`DashboardComposer`, `ProjectInsightsComposer`) that reuses the Foundation rules (`FinancialCalculator`, `BudgetAlertRule`, `PaymentStatusResolver`, `ProjectHealthEvaluator`, `ProgressCalculator`). Writes go through three new `ProjectRepository` methods that log activity in the same transaction. UI renders only.

**Tech Stack:** Swift 6 toolchain / Swift 5 mode, iOS 17+, SwiftUI + Observation, GRDB 7, XCTest/XCUITest, XcodeGen, GitHub Actions (macos-15 verifies Data/Features/App; Domain tests run on Linux and locally on Windows).

**Spec:** `docs/superpowers/specs/2026-10-03-dashboard-detail-design.md` (binding). Foundation rules: `docs/superpowers/specs/2026-10-02-foundation-design.md` §5.3–5.4.

## Global Constraints

- Domain imports Foundation only; Features never imports Data; DesignSystem never imports Domain. `scripts/lint_sources.py` must pass (no `Double`/`Float` in Domain/Data; no `try!`/`as!`/`fatalError` in production).
- Money is `Money` (Decimal, 2 dp, `Money.rounded` half-away-from-zero); percentages are `Percentage`. Domain never calls `Date()`; `today: CalendarDate` is always passed in.
- Soft-deleted records never take part in any calculation (`deleted_at IS NULL` in every query; composers also filter `isDeleted`).
- All user-visible strings are keys in `App/Resources/Localizable.xcstrings` with `en` + `vi`; data is rendered with `Text(verbatim:)`. Trade terms stay English in vi (Deposit, Cash position → "Dòng tiền hiện tại" per Foundation). `python scripts/check_localization.py` must report 0 errors.
- Activity `detailsJSON` for `progressChanged` uses `""` for nil (existing `GRDBProjectRepository.save` convention) — the spec's `null` is superseded by this plan.
- Every VM is `@Observable @MainActor`, owned by an `@State` wrapper in `App/Screens.swift`, never constructed in `body`.
- Accessibility identifiers exactly as listed in spec §5 and the UI-test task.
- Commits: `type(scope): summary`, English, **no trailers** (no Co-Authored-By).
- CI: `ios.yml` is the verifier for Data/Features/App. Known flake: Foundation `testLanguageSwitchUpdatesOpenScreenAndTabsImmediately` / screenshot launch timeout → rerun failed jobs once.

## Review Focus

1. A project whose contract currency differs from the company's (corrupt data) — Home totals must exclude it and say so, detail must show "—" with a warning, and no action may crash. (Task 2 `testExcludesForeignCurrencyProject`, Task 1 `testCurrencyMismatchYieldsNilFinancials`.)
2. A payment that references a schedule item which was later soft-deleted — it must still count in `collected` but not in any item's `paid`. (Task 1 `testPaymentOnDeletedItemIsUnallocated`.)
3. Opening the app after midnight with a stale `today` — the composer must be re-run from the same snapshot when `today` changes without a DB emission. (Task 9 `HomeViewModel.update(today:)` + Task 13 scenePhase; Task 1 `testTimelineRecomputesWithNewToday`.)
4. Changing status to the same status, or progress to the same value — no activity row must be written. (Task 5 `testChangeStatusSameStatusWritesNoActivity`, `testSetProgressSameValueWritesNoActivity`.)
5. Deleting the project while its detail is open, then tapping Edit/Status — the stream emits nil, the view shows "no longer exists", and any late write fails with `notFound` mapped to `error.projectGone`, never a crash. (Task 10 `ProjectDetailViewModel` error mapping; Task 14 test (e) asserts the list no longer shows the project.)

---

### Task 1: Domain — `ProjectInsights` + `ProjectInsightsComposer`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Insights/ProjectInsights.swift`
- Create: `Packages/Domain/Sources/Domain/Insights/ProjectInsightsComposer.swift`
- Create: `Packages/Domain/Tests/DomainTests/Insights/ProjectInsightsComposerTests.swift`
- Create: `Packages/Domain/Tests/DomainTests/Insights/InsightsFixtures.swift`

**Interfaces:**
- Consumes (Foundation): `FinancialCalculator.compute(FinancialInputs) throws -> ProjectFinancials`, `BudgetAlertRule.alerts(for:) throws -> [BudgetAlert]`, `PaymentStatusResolver.status(item:paidForItem:today:)`, `ProgressCalculator.percent(tasks:manualProgress:)`, `ProjectHealthEvaluator.evaluate(HealthInputs) -> ProjectHealth?`, `CalendarDate.daysUntil(_:)`, `Money.sum(_:currency:)`, `LabourEntry.cost`.
- Produces: `ProjectInsightsInputs` (+ `.Snapshot`, `with(today:)`), `PaymentItemInsight`, `TimelineInsight`, `ProjectInsights`, `ProjectInsightsComposer.compose(_:) -> ProjectInsights`. Task 2, 9, 10, 11 depend on these names.

- [ ] **Step 1: Fixtures shared by Insights tests**

```swift
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
```

- [ ] **Step 2: Failing tests**

```swift
// Packages/Domain/Tests/DomainTests/Insights/ProjectInsightsComposerTests.swift
import XCTest
@testable import Domain

final class ProjectInsightsComposerTests: XCTestCase {
    func testBasementSpecNumbers() throws {
        let b = Fx.Basement()
        let i = ProjectInsightsComposer.compose(b.inputs)
        let f = try XCTUnwrap(i.financials)
        XCTAssertEqual(f.estimatedCost, Fx.money(14_800))
        XCTAssertEqual(f.projectedProfit, Fx.money(23_200))
        XCTAssertEqual(f.projectedMargin?.points, Decimal(string: "61.1"))
        XCTAssertEqual(f.spentSoFar, Fx.money(10_685))
        XCTAssertEqual(f.collected, Fx.money(7600))
        XCTAssertEqual(f.outstandingBalance, Fx.money(30_400))
        XCTAssertEqual(f.cashPosition, Fx.money(-3085))
        XCTAssertEqual(f.actualProfit, Fx.money(27_315))
        XCTAssertEqual(f.profitLabel, .projectedAtCurrentSpending)
        XCTAssertEqual(i.budgetAlerts.map(\.group), [.labour])
        XCTAssertEqual(i.budgetAlerts.first?.level, .nearLimit)
        XCTAssertEqual(i.budgetAlerts.first?.percentUsed?.points, Decimal(string: "93.3"))
        XCTAssertEqual(i.payments.map(\.status), [.paid, .overdue, .upcoming, .upcoming])
        XCTAssertEqual(i.payments[0].paid, Fx.money(7600)); XCTAssertEqual(i.payments[0].remaining, .zero(.cad))
        XCTAssertEqual(i.payments[1].remaining, Fx.money(11_400))
        XCTAssertEqual(i.unallocatedCollected, .zero(.cad))
        XCTAssertEqual(i.progress, 65)
        XCTAssertEqual(i.health?.status, .paymentRisk)
        XCTAssertEqual(i.health?.reasons.count, 2)
        XCTAssertEqual(i.timeline.daysElapsed, 18); XCTAssertEqual(i.timeline.daysRemaining, 27)
        XCTAssertEqual(i.timeline.totalDays, 45); XCTAssertEqual(i.timeline.expectedProgress, 40)
    }

    func testFoundationExample() throws {
        let c = Fx.customer("X")
        let p = Fx.project("F", customer: c, status: .inProgress, contract: 30_000, progress: nil, start: nil, end: nil)
        let inputs = ProjectInsightsInputs(project: p, estimateLines: [], scheduleItems: [],
                                           expenses: [Fx.expense(p, .material, amount: 6000, tax: 0), Fx.expense(p, .other, amount: 1000, tax: 0)],
                                           labourEntries: [Fx.labour(p, days: 30, rate: 250)], payments: [Fx.payment(p, 5000, item: nil), Fx.payment(p, 15_000, item: nil)], today: Fx.today)
        let f = try XCTUnwrap(ProjectInsightsComposer.compose(inputs).financials)
        XCTAssertEqual(f.totalCost, Fx.money(14_500)); XCTAssertEqual(f.actualProfit, Fx.money(15_500))
        XCTAssertEqual(f.actualMargin?.points, Decimal(string: "51.7")); XCTAssertEqual(f.outstandingBalance, Fx.money(10_000))
        XCTAssertEqual(ProjectInsightsComposer.compose(inputs).unallocatedCollected, Fx.money(20_000))
    }

    func testCurrencyMismatchYieldsNilFinancials() {
        let c = Fx.customer("X")
        let p = Fx.project("U", customer: c, status: .inProgress, contract: 1000, progress: 10, start: -10, end: -1, currency: .usd)
        let inputs = ProjectInsightsInputs(project: p, estimateLines: [Fx.line(p, .material, 100)], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        let i = ProjectInsightsComposer.compose(inputs)
        XCTAssertNil(i.financials); XCTAssertEqual(i.budgetAlerts, [])
        XCTAssertEqual(i.health?.status, .delayed)           // date rules still run
        XCTAssertEqual(i.timeline.daysRemaining, -1)
    }

    func testPaymentOnDeletedItemIsUnallocated() throws {
        let c = Fx.customer("X")
        let p = Fx.project("D", customer: c, status: .inProgress, contract: 1000, progress: nil, start: nil, end: nil)
        let gone = Fx.item(p, "x", 500, due: nil, deletedAt: Fx.now)
        let live = Fx.item(p, "y", 500, due: nil, order: 1)
        let inputs = ProjectInsightsInputs(project: p, estimateLines: [], scheduleItems: [gone, live], expenses: [], labourEntries: [], payments: [Fx.payment(p, 500, item: gone.id)], today: Fx.today)
        let i = ProjectInsightsComposer.compose(inputs)
        XCTAssertEqual(i.payments.map(\.item.id), [live.id])
        XCTAssertEqual(i.payments[0].paid, .zero(.cad))
        XCTAssertEqual(i.unallocatedCollected, Fx.money(500))
        XCTAssertEqual(try XCTUnwrap(i.financials).collected, Fx.money(500))
    }

    func testDeletedExpenseAndPaymentIgnored() throws {
        let c = Fx.customer("X")
        let p = Fx.project("D", customer: c, status: .inProgress, contract: 1000, progress: nil, start: nil, end: nil)
        let inputs = ProjectInsightsInputs(project: p, estimateLines: [], scheduleItems: [], expenses: [Fx.expense(p, .material, amount: 100, tax: 0, deletedAt: Fx.now)], labourEntries: [], payments: [Fx.payment(p, 100, item: nil, deletedAt: Fx.now)], today: Fx.today)
        let f = try XCTUnwrap(ProjectInsightsComposer.compose(inputs).financials)
        XCTAssertEqual(f.spentSoFar, .zero(.cad)); XCTAssertEqual(f.collected, .zero(.cad))
    }

    func testTimelineEdges() {
        let c = Fx.customer("X")
        func tl(start: Int?, end: Int?, today: Int = 0) -> TimelineInsight {
            let p = Fx.project("T", customer: c, status: .inProgress, contract: 1, progress: nil, start: start, end: end)
            return ProjectInsightsComposer.compose(ProjectInsightsInputs(project: p, estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.day(today))).timeline
        }
        XCTAssertEqual(tl(start: 0, end: 0).totalDays, 0); XCTAssertEqual(tl(start: 0, end: 0).expectedProgress, 100)
        XCTAssertEqual(tl(start: 5, end: 10).daysElapsed, 0); XCTAssertEqual(tl(start: 5, end: 10).expectedProgress, 0)
        XCTAssertEqual(tl(start: -10, end: -2).daysRemaining, -2); XCTAssertEqual(tl(start: -10, end: -2).expectedProgress, 100)
        XCTAssertNil(tl(start: nil, end: 3).daysElapsed); XCTAssertEqual(tl(start: nil, end: 3).daysRemaining, 3); XCTAssertNil(tl(start: nil, end: 3).expectedProgress)
        XCTAssertNil(tl(start: -3, end: nil).daysRemaining); XCTAssertEqual(tl(start: -3, end: nil).daysElapsed, 3)
        XCTAssertEqual(tl(start: -1, end: 2).expectedProgress, 33)   // 1/3 → 33
    }

    func testTimelineRecomputesWithNewToday() {
        let b = Fx.Basement()
        let later = b.inputs.snapshot.with(today: Fx.day(30))
        let i = ProjectInsightsComposer.compose(later)
        XCTAssertEqual(i.timeline.daysRemaining, -3)
        XCTAssertEqual(i.health?.status, .paymentRisk)   // paymentRisk outranks delayed
        XCTAssertTrue(i.health?.reasons.contains(.pastCompletionDate(daysLate: 3)) ?? false)
    }
}
```

- [ ] **Step 3: Run tests — expect compile failure (types missing)**

Run: `swift test --package-path Packages/Domain --filter ProjectInsightsComposerTests`

- [ ] **Step 4: Implement types**

```swift
// Packages/Domain/Sources/Domain/Insights/ProjectInsights.swift
import Foundation

public struct PaymentItemInsight: Hashable, Sendable, Identifiable {
    public let item: PaymentScheduleItem
    public let paid: Money
    public let remaining: Money
    public let status: PaymentStatus
    public var id: UUID { item.id }
    public init(item: PaymentScheduleItem, paid: Money, remaining: Money, status: PaymentStatus) { self.item = item; self.paid = paid; self.remaining = remaining; self.status = status }
}

public struct TimelineInsight: Hashable, Sendable {
    public let startDate: CalendarDate?
    public let estimatedCompletionDate: CalendarDate?
    public let daysElapsed: Int?
    public let daysRemaining: Int?
    public let totalDays: Int?
    public let expectedProgress: Int?

    public init(startDate: CalendarDate?, estimatedCompletionDate: CalendarDate?, daysElapsed: Int?, daysRemaining: Int?, totalDays: Int?, expectedProgress: Int?) {
        self.startDate = startDate; self.estimatedCompletionDate = estimatedCompletionDate; self.daysElapsed = daysElapsed
        self.daysRemaining = daysRemaining; self.totalDays = totalDays; self.expectedProgress = expectedProgress
    }

    /// Spec §3.1: elapsed = max(0, start→today); remaining = today→completion (negative = late);
    /// expected = round(elapsed/total×100) clamped 0…100; total 0 → 100 when today ≥ completion else 0.
    public static func make(start: CalendarDate?, completion: CalendarDate?, today: CalendarDate) -> TimelineInsight {
        let elapsed = start.map { max(0, $0.daysUntil(today)) }
        let remaining = completion.map { today.daysUntil($0) }
        var total: Int?
        if let start, let completion { total = start.daysUntil(completion) }
        var expected: Int?
        if let total, let elapsed {
            if total <= 0 { expected = (remaining ?? 0) <= 0 ? 100 : 0 }
            else {
                let ratio = Decimal(elapsed) * 100 / Decimal(total)
                var rounded = Decimal(); var source = ratio
                NSDecimalRound(&rounded, &source, 0, .plain)
                expected = min(100, max(0, NSDecimalNumber(decimal: rounded).intValue))
            }
        }
        return TimelineInsight(startDate: start, estimatedCompletionDate: completion, daysElapsed: elapsed, daysRemaining: remaining, totalDays: total, expectedProgress: expected)
    }
}

public struct ProjectInsights: Hashable, Sendable {
    public let projectId: UUID
    public let financials: ProjectFinancials?
    public let budgetAlerts: [BudgetAlert]
    public let payments: [PaymentItemInsight]
    public let unallocatedCollected: Money
    public let progress: Int
    public let health: ProjectHealth?
    public let timeline: TimelineInsight
    public init(projectId: UUID, financials: ProjectFinancials?, budgetAlerts: [BudgetAlert], payments: [PaymentItemInsight], unallocatedCollected: Money, progress: Int, health: ProjectHealth?, timeline: TimelineInsight) {
        self.projectId = projectId; self.financials = financials; self.budgetAlerts = budgetAlerts; self.payments = payments
        self.unallocatedCollected = unallocatedCollected; self.progress = progress; self.health = health; self.timeline = timeline
    }
}

public struct ProjectInsightsInputs: Sendable {
    public struct Snapshot: Sendable, Equatable {
        public var project: Project
        public var estimateLines: [ProjectEstimateLine]
        public var scheduleItems: [PaymentScheduleItem]
        public var expenses: [Expense]
        public var labourEntries: [LabourEntry]
        public var payments: [Payment]
        public init(project: Project, estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment]) {
            self.project = project; self.estimateLines = estimateLines; self.scheduleItems = scheduleItems; self.expenses = expenses; self.labourEntries = labourEntries; self.payments = payments
        }
        public func with(today: CalendarDate) -> ProjectInsightsInputs {
            ProjectInsightsInputs(project: project, estimateLines: estimateLines, scheduleItems: scheduleItems, expenses: expenses, labourEntries: labourEntries, payments: payments, today: today)
        }
    }
    public var project: Project
    public var estimateLines: [ProjectEstimateLine]
    public var scheduleItems: [PaymentScheduleItem]
    public var expenses: [Expense]
    public var labourEntries: [LabourEntry]
    public var payments: [Payment]
    public var today: CalendarDate
    public init(project: Project, estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment], today: CalendarDate) {
        self.project = project; self.estimateLines = estimateLines; self.scheduleItems = scheduleItems; self.expenses = expenses; self.labourEntries = labourEntries; self.payments = payments; self.today = today
    }
    public var snapshot: Snapshot { Snapshot(project: project, estimateLines: estimateLines, scheduleItems: scheduleItems, expenses: expenses, labourEntries: labourEntries, payments: payments) }
}
```

If `Project`/`Expense`/… are not already `Equatable`, make `Snapshot` conform only to `Sendable` and drop `Equatable` (nothing in 2b relies on it).

```swift
// Packages/Domain/Sources/Domain/Insights/ProjectInsightsComposer.swift
import Foundation

public enum ProjectInsightsComposer {
    public static func compose(_ inputs: ProjectInsightsInputs) -> ProjectInsights {
        let project = inputs.project
        let currency = project.contractValue.currency
        let zero = Money.zero(currency)
        let items = inputs.scheduleItems.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
        let payments = inputs.payments.filter { !$0.isDeleted }

        let financials = try? FinancialCalculator.compute(FinancialInputs(project: project, estimateLines: inputs.estimateLines, expenses: inputs.expenses,
                                                                           labourEntries: inputs.labourEntries, payments: payments, approvedChangeOrders: zero))
        let alerts = financials.flatMap { try? BudgetAlertRule.alerts(for: $0) } ?? []

        let liveIds = Set(items.map(\.id))
        var paidByItem: [UUID: Money] = [:]
        var unallocated = zero
        for p in payments {
            if let id = p.scheduleItemId, liveIds.contains(id), let sum = try? (paidByItem[id] ?? zero).adding(p.amount) { paidByItem[id] = sum }
            else if let sum = try? unallocated.adding(p.amount) { unallocated = sum }
        }
        let paymentInsights = items.map { item -> PaymentItemInsight in
            let paid = paidByItem[item.id] ?? zero
            let remaining = (try? item.amount.subtracting(paid)).map { $0.isNegative ? zero : $0 } ?? zero
            return PaymentItemInsight(item: item, paid: paid, remaining: remaining, status: PaymentStatusResolver.status(item: item, paidForItem: paid, today: inputs.today))
        }

        let progress = ProgressCalculator.percent(tasks: [], manualProgress: project.manualProgress)
        let health = ProjectHealthEvaluator.evaluate(HealthInputs(status: project.status, estimatedCompletionDate: project.estimatedCompletionDate, progress: progress,
                                                                  budgetAlerts: alerts, paymentStatuses: paymentInsights.map(\.status), today: inputs.today))
        let timeline = TimelineInsight.make(start: project.startDate, completion: project.estimatedCompletionDate, today: inputs.today)
        return ProjectInsights(projectId: project.id, financials: financials, budgetAlerts: alerts, payments: paymentInsights,
                               unallocatedCollected: unallocated, progress: progress, health: health, timeline: timeline)
    }
}
```

Check `Expense`/`Payment`/`PaymentScheduleItem` expose `isDeleted` (they conform to `CompanyScoped`; `FinancialCalculator` already uses `!$0.isDeleted`). `Percentage.points` is `Decimal`.

- [ ] **Step 5: Run tests — all green**

Run: `swift test --package-path Packages/Domain --filter ProjectInsightsComposerTests`
If `testBasementSpecNumbers` margin assertion fails on `61.1` vs `61.05…`, the rule is `Percentage.ratio` 1 dp half-away — verify `Percentage.ratio` rounds, not truncates; fix the test expectation only if the Foundation rule says otherwise (it says 1 dp).

- [ ] **Step 6: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add ProjectInsightsComposer and timeline insight"
```

---

### Task 2: Domain — `Dashboard` + `DashboardComposer`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Insights/Dashboard.swift`
- Create: `Packages/Domain/Sources/Domain/Insights/DashboardComposer.swift`
- Create: `Packages/Domain/Tests/DomainTests/Insights/DashboardComposerTests.swift`

**Interfaces:**
- Consumes: Task 1 types; `HealthStatus` (Comparable: onTrack < atRisk < delayed < paymentRisk < overBudget), `HealthReason`.
- Produces: `DashboardInputs` (+ `.Snapshot`, `with(today:)`), `AttentionKind`, `AttentionItem`, `CompanyTotals`, `CardGroup`, `ProjectCard`, `Dashboard`, `DashboardComposer.compose(_:) -> Dashboard`.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import Domain

final class DashboardComposerTests: XCTestCase {
    let company = Company(id: Fx.companyId, name: "N", currencyCode: .cad, createdAt: Fx.now, updatedAt: Fx.now, deletedAt: nil)

    /// Spec §4 seed: Basement + Kitchen (awaitingDeposit, starts today, deposit 5,000 due +7) + Roof (completed, 18,500 unallocated payment).
    func seed() -> (DashboardInputs, basement: Fx.Basement, kitchen: Project, roof: Project) {
        let b = Fx.Basement()
        let david = Fx.customer("David Nguyen"), maria = Fx.customer("Maria Santos")
        let kitchen = Fx.project("Kitchen Renovation", customer: david, status: .awaitingDeposit, contract: 25_000, progress: nil, start: 0, end: 34)
        let roof = Fx.project("Roof Replacement", customer: maria, status: .completed, contract: 18_500, progress: 100, start: -63, end: -44)
        let inputs = DashboardInputs(company: company, projects: [b.project, kitchen, roof], customers: [b.customer, david, maria], estimateLines: b.lines,
                                     scheduleItems: b.items + [Fx.item(kitchen, "schedule.row.deposit", 5000, due: 7, deposit: true)],
                                     expenses: b.expenses, labourEntries: b.labour, payments: b.payments + [Fx.payment(roof, 18_500, item: nil)], today: Fx.today)
        return (inputs, b, kitchen, roof)
    }

    func testTotalsMatchSpec() {
        let d = DashboardComposer.compose(seed().0)
        XCTAssertEqual(d.totals.activeJobs, 1)
        XCTAssertEqual(d.totals.outstanding, Fx.money(55_400))
        XCTAssertEqual(d.totals.collected, Fx.money(26_100))
        XCTAssertEqual(d.totals.spent, Fx.money(10_685))
        XCTAssertEqual(d.totals.cashPosition, Fx.money(15_415))
        XCTAssertEqual(d.totals.excludedCount, 0)
    }

    func testAttentionOrderMatchesSpec() {
        let (inputs, b, kitchen, _) = seed()
        let a = DashboardComposer.compose(inputs).attention
        XCTAssertEqual(a.count, 3)
        guard case .health(let pid, let status, _) = a[0] else { return XCTFail("\(a[0])") }
        XCTAssertEqual(pid, b.project.id); XCTAssertEqual(status, .paymentRisk)
        guard case .paymentOverdue(let pid2, _, let label, let remaining, let daysLate) = a[1] else { return XCTFail("\(a[1])") }
        XCTAssertEqual(pid2, b.project.id); XCTAssertEqual(label, "schedule.row.stage2"); XCTAssertEqual(remaining, Fx.money(11_400)); XCTAssertEqual(daysLate, 5)
        XCTAssertEqual(a[2], .startsToday(projectId: kitchen.id))
        XCTAssertEqual(a.map(\.kind), [.paymentRisk, .paymentOverdue, .startsToday])
    }

    func testCardsGroupedAndTerminalHidden() {
        var (inputs, b, kitchen, roof) = seed()
        let c = Fx.customer("Z")
        let closed = Fx.project("Closed", customer: c, status: .closed, contract: 100, progress: nil, start: nil, end: nil)
        inputs.projects.append(closed); inputs.customers.append(c)
        let d = DashboardComposer.compose(inputs)
        XCTAssertEqual(d.cards.map(\.id), [b.project.id, kitchen.id, roof.id])
        XCTAssertEqual(d.cards.map(\.group), [.inWork, .preStart, .workDone])
        XCTAssertEqual(d.cards[0].customerName, "Ann Lee")
        XCTAssertEqual(d.totals.outstanding, Fx.money(55_400))   // closed project not in totals
    }

    func testInWorkOrderedBySeverityThenUpdatedAt() {
        let c = Fx.customer("X")
        let ok = Fx.project("ok", customer: c, status: .inProgress, contract: 100, progress: nil, start: nil, end: nil, updatedAt: Fx.now.addingTimeInterval(100))
        let late = Fx.project("late", customer: c, status: .inProgress, contract: 100, progress: nil, start: -10, end: -1)
        let inputs = DashboardInputs(company: company, projects: [ok, late], customers: [c], estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        XCTAssertEqual(DashboardComposer.compose(inputs).cards.map(\.id), [late.id, ok.id])
    }

    func testExcludesForeignCurrencyProject() {
        let c = Fx.customer("X")
        let usd = Fx.project("usd", customer: c, status: .inProgress, contract: 999, progress: nil, start: nil, end: nil, currency: .usd)
        let cad = Fx.project("cad", customer: c, status: .scheduled, contract: 100, progress: nil, start: nil, end: nil)
        let inputs = DashboardInputs(company: company, projects: [usd, cad], customers: [c], estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        let d = DashboardComposer.compose(inputs)
        XCTAssertEqual(d.totals.excludedCount, 1)
        XCTAssertEqual(d.totals.outstanding, Fx.money(100))
        XCTAssertEqual(d.totals.activeJobs, 1)                     // usd project still counts as a job
        XCTAssertEqual(d.cards.count, 2)                           // still shown as a card
        XCTAssertNil(d.cards.first { $0.id == usd.id }?.insights.financials)
    }

    func testOverdueProjectYieldsSingleDelayedItem() {
        let c = Fx.customer("X")
        let late = Fx.project("late", customer: c, status: .inProgress, contract: 100, progress: nil, start: -10, end: -1)
        let inputs = DashboardInputs(company: company, projects: [late], customers: [c], estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        let a = DashboardComposer.compose(inputs).attention
        XCTAssertEqual(a.count, 1); XCTAssertEqual(a[0].kind, .delayed)
    }

    func testDueTodayAndKindOrdering() {
        let c = Fx.customer("X")
        let p = Fx.project("p", customer: c, status: .inProgress, contract: 100, progress: nil, start: nil, end: nil)
        let q = Fx.project("q", customer: c, status: .scheduled, contract: 100, progress: nil, start: 0, end: nil)
        let inputs = DashboardInputs(company: company, projects: [p, q], customers: [c], estimateLines: [Fx.line(p, .material, 10)], scheduleItems: [Fx.item(p, "due", 50, due: 0)],
                                     expenses: [Fx.expense(p, .material, amount: 11, tax: 0)], labourEntries: [], payments: [], today: Fx.today)
        let a = DashboardComposer.compose(inputs).attention
        XCTAssertEqual(a.map(\.kind), [.overBudget, .dueToday, .startsToday])
    }

    func testMissingCustomerGivesEmptyName() {
        let c = Fx.customer("X")
        let p = Fx.project("p", customer: c, status: .inProgress, contract: 100, progress: nil, start: nil, end: nil)
        let inputs = DashboardInputs(company: company, projects: [p], customers: [], estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        XCTAssertEqual(DashboardComposer.compose(inputs).cards[0].customerName, "")
    }
}
```

- [ ] **Step 2: Run — compile failure expected**

- [ ] **Step 3: Implement**

```swift
// Packages/Domain/Sources/Domain/Insights/Dashboard.swift
import Foundation

public struct DashboardInputs: Sendable {
    public struct Snapshot: Sendable {
        public var company: Company
        public var projects: [Project]
        public var customers: [Customer]
        public var estimateLines: [ProjectEstimateLine]
        public var scheduleItems: [PaymentScheduleItem]
        public var expenses: [Expense]
        public var labourEntries: [LabourEntry]
        public var payments: [Payment]
        public init(company: Company, projects: [Project], customers: [Customer], estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment]) {
            self.company = company; self.projects = projects; self.customers = customers; self.estimateLines = estimateLines
            self.scheduleItems = scheduleItems; self.expenses = expenses; self.labourEntries = labourEntries; self.payments = payments
        }
        public func with(today: CalendarDate) -> DashboardInputs {
            DashboardInputs(company: company, projects: projects, customers: customers, estimateLines: estimateLines, scheduleItems: scheduleItems, expenses: expenses, labourEntries: labourEntries, payments: payments, today: today)
        }
    }
    public var company: Company
    public var projects: [Project]
    public var customers: [Customer]
    public var estimateLines: [ProjectEstimateLine]
    public var scheduleItems: [PaymentScheduleItem]
    public var expenses: [Expense]
    public var labourEntries: [LabourEntry]
    public var payments: [Payment]
    public var today: CalendarDate
    public init(company: Company, projects: [Project], customers: [Customer], estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment], today: CalendarDate) {
        self.company = company; self.projects = projects; self.customers = customers; self.estimateLines = estimateLines
        self.scheduleItems = scheduleItems; self.expenses = expenses; self.labourEntries = labourEntries; self.payments = payments; self.today = today
    }
}

public enum AttentionKind: Int, Comparable, Sendable, Hashable {
    case overBudget = 0, paymentOverdue, paymentRisk, delayed, dueToday, startsToday, atRisk
    public static func < (l: AttentionKind, r: AttentionKind) -> Bool { l.rawValue < r.rawValue }
}

public enum AttentionItem: Hashable, Sendable, Identifiable {
    case health(projectId: UUID, status: HealthStatus, reason: HealthReason)
    case paymentOverdue(projectId: UUID, itemId: UUID, label: String, remaining: Money, daysLate: Int)
    case paymentDueToday(projectId: UUID, itemId: UUID, label: String, remaining: Money)
    case startsToday(projectId: UUID)

    public var kind: AttentionKind {
        switch self {
        case .health(_, let status, _):
            switch status {
            case .overBudget: return .overBudget
            case .paymentRisk: return .paymentRisk
            case .delayed: return .delayed
            case .atRisk, .onTrack: return .atRisk
            }
        case .paymentOverdue: return .paymentOverdue
        case .paymentDueToday: return .dueToday
        case .startsToday: return .startsToday
        }
    }
    public var projectId: UUID {
        switch self {
        case .health(let id, _, _), .paymentOverdue(let id, _, _, _, _), .paymentDueToday(let id, _, _, _), .startsToday(let id): return id
        }
    }
    public var id: String {
        switch self {
        case .paymentOverdue(_, let item, _, _, _), .paymentDueToday(_, let item, _, _): return "\(kind.rawValue):\(projectId.uuidString):\(item.uuidString)"
        default: return "\(kind.rawValue):\(projectId.uuidString)"
        }
    }
    /// Sort weight after kind: larger money first.
    var amountWeight: Decimal {
        switch self {
        case .health(_, _, let reason):
            if case .budgetExceeded(_, let over) = reason { return over.amount }
            return 0
        case .paymentOverdue(_, _, _, let m, _), .paymentDueToday(_, _, _, let m): return m.amount
        case .startsToday: return 0
        }
    }
}

public struct CompanyTotals: Hashable, Sendable {
    public let currency: CurrencyCode
    public let activeJobs: Int
    public let outstanding: Money
    public let collected: Money
    public let spent: Money
    public let cashPosition: Money
    public let excludedCount: Int
    public init(currency: CurrencyCode, activeJobs: Int, outstanding: Money, collected: Money, spent: Money, cashPosition: Money, excludedCount: Int) {
        self.currency = currency; self.activeJobs = activeJobs; self.outstanding = outstanding; self.collected = collected; self.spent = spent; self.cashPosition = cashPosition; self.excludedCount = excludedCount
    }
}

public enum CardGroup: Int, Comparable, Sendable, Hashable, CaseIterable {
    case inWork = 0, preStart, workDone
    public static func < (l: CardGroup, r: CardGroup) -> Bool { l.rawValue < r.rawValue }
}

public struct ProjectCard: Hashable, Sendable, Identifiable {
    public let project: Project
    public let customerName: String
    public let insights: ProjectInsights
    public let group: CardGroup
    public var id: UUID { project.id }
    public init(project: Project, customerName: String, insights: ProjectInsights, group: CardGroup) { self.project = project; self.customerName = customerName; self.insights = insights; self.group = group }
}

public struct Dashboard: Hashable, Sendable {
    public let totals: CompanyTotals
    public let attention: [AttentionItem]
    public let cards: [ProjectCard]
    public init(totals: CompanyTotals, attention: [AttentionItem], cards: [ProjectCard]) { self.totals = totals; self.attention = attention; self.cards = cards }
}
```

```swift
// Packages/Domain/Sources/Domain/Insights/DashboardComposer.swift
import Foundation

public enum DashboardComposer {
    public static func compose(_ inputs: DashboardInputs) -> Dashboard {
        let currency = inputs.company.currencyCode
        let zero = Money.zero(currency)
        let names = Dictionary(inputs.customers.filter { !$0.isDeleted }.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let linesBy = Dictionary(grouping: inputs.estimateLines, by: \.projectId)
        let itemsBy = Dictionary(grouping: inputs.scheduleItems, by: \.projectId)
        let expensesBy = Dictionary(grouping: inputs.expenses, by: \.projectId)
        let labourBy = Dictionary(grouping: inputs.labourEntries, by: \.projectId)
        let paymentsBy = Dictionary(grouping: inputs.payments, by: \.projectId)

        var cards: [ProjectCard] = []
        var attention: [AttentionItem] = []
        var activeJobs = 0, excluded = 0
        var outstanding = zero, collected = zero, spent = zero

        for project in inputs.projects where !project.isDeleted {
            let phase = project.status.phase
            if phase == .terminal { continue }
            let insights = ProjectInsightsComposer.compose(ProjectInsightsInputs(
                project: project, estimateLines: linesBy[project.id] ?? [], scheduleItems: itemsBy[project.id] ?? [], expenses: expensesBy[project.id] ?? [],
                labourEntries: labourBy[project.id] ?? [], payments: paymentsBy[project.id] ?? [], today: inputs.today))
            if phase == .inWork { activeJobs += 1 }
            if let f = insights.financials, project.contractValue.currency == currency,
               let o = try? outstanding.adding(f.outstandingBalance), let c = try? collected.adding(f.collected), let s = try? spent.adding(f.spentSoFar) {
                outstanding = o; collected = c; spent = s
            } else { excluded += 1 }

            let group: CardGroup = phase == .inWork ? .inWork : (phase == .preStart ? .preStart : .workDone)
            cards.append(ProjectCard(project: project, customerName: names[project.customerId] ?? "", insights: insights, group: group))

            if let h = insights.health, h.status != .onTrack, let reason = h.reasons.first {
                attention.append(.health(projectId: project.id, status: h.status, reason: reason))
            }
            for p in insights.payments {
                switch p.status {
                case .overdue:
                    let late = p.item.dueDate.map { $0.daysUntil(inputs.today) } ?? 0
                    attention.append(.paymentOverdue(projectId: project.id, itemId: p.item.id, label: p.item.label, remaining: p.remaining, daysLate: late))
                case .dueToday:
                    attention.append(.paymentDueToday(projectId: project.id, itemId: p.item.id, label: p.item.label, remaining: p.remaining))
                default: break
                }
            }
            if project.startDate == inputs.today, phase == .preStart || project.status == .scheduled {
                attention.append(.startsToday(projectId: project.id))
            }
        }

        let nameOf: (UUID) -> String = { id in inputs.projects.first { $0.id == id }?.name ?? "" }
        attention.sort { a, b in
            if a.kind != b.kind { return a.kind < b.kind }
            if a.amountWeight != b.amountWeight { return a.amountWeight > b.amountWeight }
            return nameOf(a.projectId) < nameOf(b.projectId)
        }
        cards.sort { a, b in
            if a.group != b.group { return a.group < b.group }
            switch a.group {
            case .inWork:
                let ha = a.insights.health?.status ?? .onTrack, hb = b.insights.health?.status ?? .onTrack
                if ha != hb { return ha > hb }
                return a.project.updatedAt > b.project.updatedAt
            case .preStart:
                switch (a.project.startDate, b.project.startDate) {
                case let (x?, y?) where x != y: return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.project.updatedAt > b.project.updatedAt
                }
            case .workDone: return a.project.updatedAt > b.project.updatedAt
            }
        }
        let cash = (try? collected.subtracting(spent)) ?? zero
        let totals = CompanyTotals(currency: currency, activeJobs: activeJobs, outstanding: outstanding, collected: collected, spent: spent, cashPosition: cash, excludedCount: excluded)
        return Dashboard(totals: totals, attention: attention, cards: cards)
    }
}
```

- [ ] **Step 4: Run tests — green**

Run: `swift test --package-path Packages/Domain --filter DashboardComposerTests`

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add DashboardComposer with attention, totals and cards"
```

---

### Task 3: Domain — status change, timeline validator, activity description, protocols

**Files:**
- Create: `Packages/Domain/Sources/Domain/Insights/ProjectStatusChange.swift`
- Create: `Packages/Domain/Sources/Domain/Drafts/TimelineValidator.swift`
- Create: `Packages/Domain/Sources/Domain/Insights/ActivityDescription.swift`
- Create: `Packages/Domain/Sources/Domain/Repositories/InsightsRepository.swift`
- Create: `Packages/Domain/Sources/Domain/Repositories/ActivityLogRepository.swift`
- Modify: `Packages/Domain/Sources/Domain/Entities/ActivityLog.swift` (add `customerChanged`), `Packages/Domain/Sources/Domain/DomainError.swift` (add `customerDeleted`, `crossCompany`, `notFound`), `Packages/Domain/Sources/Domain/Drafts/ProjectDraft.swift` (`DraftError.invalidTimeline([TimelineError])`), `Packages/Domain/Sources/Domain/Drafts/ProjectDraftAssembler.swift:81-84`, `Packages/Domain/Sources/Domain/Repositories/ProjectRepository.swift`
- Test: `Packages/Domain/Tests/DomainTests/Insights/ProjectStatusChangeTests.swift`, `…/Drafts/TimelineValidatorTests.swift`, `…/Insights/ActivityDescriptionTests.swift`

**Interfaces:**
- Produces: `ProjectStatusChange.apply(_:to:) -> StatusChangeOutcome`, `ProjectStatusChange.setManualProgress(_:to:) throws -> Project`, `TimelineError`, `TimelineValidator.validate(start:completion:workingDays:hoursPerDay:workersPerDay:) -> [TimelineError]`, `ActivityDetail`, `ActivityDescription.detail(for:) -> ActivityDetail`, `InsightsRepository`, `ActivityLogRepository`, `ProjectRepository.changeStatus/setManualProgress/changeCustomer`, `ActivityAction.customerChanged`, `DomainError.customerDeleted/crossCompany/notFound`.

- [ ] **Step 1: Failing tests**

```swift
// ProjectStatusChangeTests.swift
import XCTest
@testable import Domain

final class ProjectStatusChangeTests: XCTestCase {
    let c = Fx.customer("X")
    func p(_ s: ProjectStatus, progress: Int?) -> Project { Fx.project("p", customer: c, status: s, contract: 1, progress: progress, start: nil, end: nil) }

    func testSuggestsProgress100OnlyForWorkDoneWithoutManualProgress() {
        XCTAssertTrue(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .completed).suggestProgress100)
        XCTAssertTrue(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .awaitingFinalPayment).suggestProgress100)
        XCTAssertFalse(ProjectStatusChange.apply(p(.inProgress, progress: 40), to: .completed).suggestProgress100)
        XCTAssertFalse(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .onHold).suggestProgress100)
    }
    func testRequiresConfirmationForTerminal() {
        XCTAssertTrue(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .closed).requiresConfirmation)
        XCTAssertTrue(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .cancelled).requiresConfirmation)
        XCTAssertFalse(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .completed).requiresConfirmation)
    }
    func testApplySetsStatus() {
        let o = ProjectStatusChange.apply(p(.estimate, progress: nil), to: .scheduled)
        XCTAssertEqual(o.project.status, .scheduled)
    }
    func testManualProgressRange() throws {
        XCTAssertEqual(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: nil), to: 0).manualProgress, 0)
        XCTAssertEqual(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: nil), to: 100).manualProgress, 100)
        XCTAssertNil(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: 5), to: nil).manualProgress)
        XCTAssertThrowsError(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: nil), to: -1)) { XCTAssertEqual($0 as? DomainError, .invalidProgress) }
        XCTAssertThrowsError(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: nil), to: 101))
    }
}
```

```swift
// TimelineValidatorTests.swift
import XCTest
@testable import Domain

final class TimelineValidatorTests: XCTestCase {
    let d0 = CalendarDate(storage: "2026-10-03")!, d1 = CalendarDate(storage: "2026-10-04")!
    func testValid() { XCTAssertEqual(TimelineValidator.validate(start: d0, completion: d1, workingDays: 5, hoursPerDay: 24, workersPerDay: 0), []) }
    func testNilsAreValid() { XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil), []) }
    func testSameDayValid() { XCTAssertEqual(TimelineValidator.validate(start: d0, completion: d0, workingDays: nil, hoursPerDay: nil, workersPerDay: nil), []) }
    func testEachError() {
        XCTAssertEqual(TimelineValidator.validate(start: d1, completion: d0, workingDays: nil, hoursPerDay: nil, workersPerDay: nil), [.completionBeforeStart])
        XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: nil, hoursPerDay: 0, workersPerDay: nil), [.hoursPerDayOutOfRange])
        XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: nil, hoursPerDay: Decimal(string: "24.5"), workersPerDay: nil), [.hoursPerDayOutOfRange])
        XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: -1, hoursPerDay: nil, workersPerDay: nil), [.workingDaysNegative])
        XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: -3), [.workersPerDayNegative])
    }
    func testCombinedOrder() {
        XCTAssertEqual(TimelineValidator.validate(start: d1, completion: d0, workingDays: -1, hoursPerDay: 30, workersPerDay: -1),
                       [.completionBeforeStart, .hoursPerDayOutOfRange, .workingDaysNegative, .workersPerDayNegative])
    }
    func testAssemblerReportsTimelineErrors() {
        var draft = ProjectDraft(); draft.jobType = .kitchen; draft.customer = .existing(UUID()); draft.address = Address(line: "1 A", unit: nil, city: nil, region: nil, postalCode: nil)
        draft.contractValue = Money(1000, .cad); draft.hoursPerDay = 30; draft.workingDays = -2
        XCTAssertThrowsError(try ProjectDraftAssembler.assemble(draft, companyId: UUID(), currency: .cad, now: Fx.now)) { error in
            XCTAssertEqual(error as? DraftError, .invalidTimeline([.hoursPerDayOutOfRange, .workingDaysNegative]))
        }
    }
}
```

Check the real `ProjectDraftAssembler.assemble` signature and `CustomerChoice` case names before writing `testAssemblerReportsTimelineErrors`; adapt the call, not the assertion.

```swift
// ActivityDescriptionTests.swift
import XCTest
@testable import Domain

final class ActivityDescriptionTests: XCTestCase {
    func entry(_ action: ActivityAction, _ json: String) -> ActivityLogEntry {
        ActivityLogEntry(id: UUID(), companyId: Fx.companyId, userId: nil, actorName: "Duc", action: action, entityType: "project", entityId: UUID(), projectId: UUID(), detailsJSON: json, occurredAt: Fx.now, createdAt: Fx.now, updatedAt: Fx.now, deletedAt: nil)
    }
    func testStatus() { XCTAssertEqual(ActivityDescription.detail(for: entry(.statusChanged, #"{"from":"estimate","to":"inProgress"}"#)), .statusChanged(from: .estimate, to: .inProgress)) }
    func testProgressWithEmptyFrom() { XCTAssertEqual(ActivityDescription.detail(for: entry(.progressChanged, #"{"from":"","to":"60"}"#)), .progressChanged(from: nil, to: 60)) }
    func testContract() { XCTAssertEqual(ActivityDescription.detail(for: entry(.contractValueChanged, #"{"from":"30000.00","to":"32000.00"}"#)), .contractValueChanged(from: "30000.00", to: "32000.00")) }
    func testEstimateWithGroup() { XCTAssertEqual(ActivityDescription.detail(for: entry(.estimateChanged, #"{"group":"material","from":"0.00","to":"7900.00"}"#)), .estimateChanged(group: .material, from: "0.00", to: "7900.00")) }
    func testSchedule() { XCTAssertEqual(ActivityDescription.detail(for: entry(.scheduleChanged, #"{"from":"0.00","to":"38000.00"}"#)), .scheduleChanged(from: "0.00", to: "38000.00")) }
    func testCustomer() { XCTAssertEqual(ActivityDescription.detail(for: entry(.customerChanged, #"{"from":"Ann","to":"Bob","fromId":"x","toId":"y"}"#)), .customerChanged(fromName: "Ann", toName: "Bob")) }
    func testPlainAndCorrupt() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.projectCreated, #"{"name":"K"}"#)), .plain(.projectCreated))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.statusChanged, "not json")), .plain(.statusChanged))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.statusChanged, #"{"from":"bogus","to":"inProgress"}"#)), .plain(.statusChanged))
    }
}
```

Money amounts in `ActivityDetail` are kept as the storage strings (`"30000.00"`) because `detailsJSON` carries no currency; the UI formats them with the company currency. (This narrows spec §3.5's `Money` to `String` — recorded in the plan, not a behaviour change.) Check how `GRDBProjectEstimateRepository.replace` writes `estimateChanged` details (keys `group`/`from`/`to`?) and `scheduleChanged`; use those exact keys in `ActivityDescription` and in the tests.

- [ ] **Step 2: Implement**

```swift
// ProjectStatusChange.swift
import Foundation

public struct StatusChangeOutcome: Hashable, Sendable {
    public let project: Project
    public let suggestProgress100: Bool
    public let requiresConfirmation: Bool
}

public enum ProjectStatusChange {
    public static func apply(_ project: Project, to status: ProjectStatus) -> StatusChangeOutcome {
        var p = project; p.status = status
        let workDone = status == .completed || status == .awaitingFinalPayment
        return StatusChangeOutcome(project: p, suggestProgress100: workDone && project.manualProgress == nil, requiresConfirmation: status == .closed || status == .cancelled)
    }
    public static func setManualProgress(_ project: Project, to value: Int?) throws -> Project {
        if let v = value, !(0...100).contains(v) { throw DomainError.invalidProgress }
        var p = project; p.manualProgress = value; return p
    }
}
```

```swift
// TimelineValidator.swift
import Foundation

public enum TimelineError: Hashable, Sendable, CaseIterable { case completionBeforeStart, hoursPerDayOutOfRange, workingDaysNegative, workersPerDayNegative }

public enum TimelineValidator {
    public static func validate(start: CalendarDate?, completion: CalendarDate?, workingDays: Int?, hoursPerDay: Decimal?, workersPerDay: Int?) -> [TimelineError] {
        var errors: [TimelineError] = []
        if let s = start, let e = completion, e < s { errors.append(.completionBeforeStart) }
        if let h = hoursPerDay, !(h > 0 && h <= 24) { errors.append(.hoursPerDayOutOfRange) }
        if let w = workingDays, w < 0 { errors.append(.workingDaysNegative) }
        if let w = workersPerDay, w < 0 { errors.append(.workersPerDayNegative) }
        return errors
    }
}
```

`ProjectDraft.swift`: change `case invalidTimeline` to `case invalidTimeline([TimelineError])`; keep `completionBeforeStart` case for source compatibility but the assembler no longer throws it. `ProjectDraftAssembler.swift:81-84` becomes:

```swift
        let timelineErrors = TimelineValidator.validate(start: draft.startDate, completion: draft.estimatedCompletionDate, workingDays: draft.workingDays, hoursPerDay: draft.hoursPerDay, workersPerDay: draft.workersPerDay)
        if !timelineErrors.isEmpty { throw DraftError.invalidTimeline(timelineErrors) }
```

Grep the Domain tests for `.invalidTimeline` / `.completionBeforeStart` expectations (2a assembler tests) and update them to the new payload (`.invalidTimeline([.completionBeforeStart])`).

```swift
// ActivityDescription.swift
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
```

`ActivityLog.swift`: append `case customerChanged` to `ActivityAction`. `DomainError.swift`: add `case customerDeleted, crossCompany, notFound`.

```swift
// InsightsRepository.swift
import Foundation
public protocol InsightsRepository: Sendable {
    /// Live company snapshot (every related table, non-deleted rows); emits on any change.
    func observeDashboard(companyId: UUID) -> AsyncThrowingStream<DashboardInputs.Snapshot, Error>
    /// nil when the project is missing or soft-deleted.
    func observeProject(id: UUID) -> AsyncThrowingStream<ProjectInsightsInputs.Snapshot?, Error>
}
// ActivityLogRepository.swift
import Foundation
public protocol ActivityLogRepository: Sendable {
    func observeForProject(projectId: UUID, limit: Int) -> AsyncThrowingStream<[ActivityLogEntry], Error>   // occurredAt desc
    func list(projectId: UUID) async throws -> [ActivityLogEntry]                                            // occurredAt desc, all
}
```

`ProjectRepository.swift` protocol additions:

```swift
    /// Writes `statusChanged {from,to}` in the same transaction; same status → no write. Throws DomainError.notFound.
    func changeStatus(id: UUID, to status: ProjectStatus, actor: ActivityActor) async throws
    /// Writes `progressChanged {from,to}` ("" for nil); equal → no write. Validates 0…100.
    func setManualProgress(id: UUID, to value: Int?, actor: ActivityActor) async throws
    /// Customer must be live and in the same company; writes `customerChanged {from,to,fromId,toId}` (names).
    func changeCustomer(id: UUID, to customerId: UUID, actor: ActivityActor) async throws
```

- [ ] **Step 3: Run all Domain tests — green**

Run: `swift test --package-path Packages/Domain`

- [ ] **Step 4: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add status change, timeline validator, activity description and 2b repository protocols"
```

---

### Task 4: Data — records for expenses/labour/payments/employees + `GRDBInsightsRepository`

**Files:**
- Create: `Packages/Data/Sources/Data/Records/ExpenseRecord.swift`, `LabourEntryRecord.swift`, `PaymentRecord.swift`, `EmployeeRecord.swift`
- Create: `Packages/Data/Sources/Data/Repositories/GRDBInsightsRepository.swift`
- Test: `Packages/Data/Tests/DataTests/MoneyRecordsTests.swift`, `Packages/Data/Tests/DataTests/InsightsRepositoryTests.swift`

**Interfaces:**
- Consumes: `RecordSupport.uuid/money/calendarDate/date/decimal(_:table:id:column:)`, `Timestamps.string`, `SyncState.pending`, record pattern of `PaymentScheduleItemRecord`; Domain `DashboardInputs.Snapshot`, `ProjectInsightsInputs.Snapshot`.
- Produces: `GRDBInsightsRepository(database:)`; records with `init(_ entity)`, `toDomain(currency:) throws`, `static fetchLive(_ db, projectId:currency:)` / `fetchLive(_ db, companyId:currency:)`.

- [ ] **Step 1: Failing tests**

```swift
// MoneyRecordsTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class MoneyRecordsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!; var companyId: UUID!; var project: Project!; var customer: Customer!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
        companyId = company.id
        customer = Customer(id: UUID(), companyId: companyId, name: "Ann", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(customer)
        project = Project(id: UUID(), companyId: companyId, customerId: customer.id, name: "P", jobType: .kitchen, customJobType: nil, status: .inProgress, address: Address(line: "1", unit: nil, city: nil, region: nil, postalCode: nil), scopeDescription: nil, scopeFields: [], startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil, contractValue: Money(1000, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).save(project, actor: ActivityActor(userId: owner.id, name: "Duc"))
    }

    func testExpenseRoundTrip() async throws {
        let e = Expense(id: UUID(), companyId: companyId, projectId: project.id, category: .materials, customCategoryId: nil, costGroup: .material, vendorName: "Home Depot", amount: Money(Decimal(string: "2400.00")!, .cad), tax: Money(Decimal(string: "312.00")!, .cad), spentOn: CalendarDate(storage: "2026-10-01")!, paymentMethod: .creditCard, notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: nil)
        try await db.writer.write { db in try ExpenseRecord(e).insert(db) }
        let back = try await db.writer.read { db in try ExpenseRecord.fetchLive(db, projectId: self.project.id.dbKey, currency: .cad) }
        XCTAssertEqual(back, [e])
        XCTAssertEqual(try back[0].totalCost(), Money(Decimal(string: "2712.00")!, .cad))
    }
    func testLabourEntryRoundTripNeedsEmployee() async throws {
        let emp = Employee(id: UUID(), companyId: companyId, name: "Mike", phone: nil, role: nil, trade: nil, hourlyRate: nil, dailyRate: Money(250, .cad), certifications: nil, emergencyContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        let l = LabourEntry(id: UUID(), companyId: companyId, projectId: project.id, employeeId: emp.id, workDate: CalendarDate(storage: "2026-10-01")!, days: Decimal(string: "1.5")!, dailyRate: Money(250, .cad), notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await db.writer.write { db in try EmployeeRecord(emp).insert(db); try LabourEntryRecord(l).insert(db) }
        let back = try await db.writer.read { db in try LabourEntryRecord.fetchLive(db, projectId: self.project.id.dbKey, currency: .cad) }
        XCTAssertEqual(back, [l]); XCTAssertEqual(back[0].cost, Money(375, .cad))
    }
    func testPaymentRoundTripAndDeletedFilter() async throws {
        let p = Payment(id: UUID(), companyId: companyId, projectId: project.id, scheduleItemId: nil, amount: Money(7600, .cad), paidOn: CalendarDate(storage: "2026-09-14")!, method: .eTransfer, notes: "deposit", createdAt: now, updatedAt: now, deletedAt: nil)
        let gone = Payment(id: UUID(), companyId: companyId, projectId: project.id, scheduleItemId: nil, amount: Money(1, .cad), paidOn: CalendarDate(storage: "2026-09-14")!, method: .cash, notes: nil, createdAt: now, updatedAt: now, deletedAt: now)
        try await db.writer.write { db in try PaymentRecord(p).insert(db); try PaymentRecord(gone).insert(db) }
        let back = try await db.writer.read { db in try PaymentRecord.fetchLive(db, projectId: self.project.id.dbKey, currency: .cad) }
        XCTAssertEqual(back, [p])
    }
}
```

Entities must be `Equatable` for `XCTAssertEqual`; they conform to `CompanyScoped` — check whether that implies `Hashable`; if not, compare field-by-field (`id`, `amount`, `tax`, `spentOn`).

```swift
// InsightsRepositoryTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class InsightsRepositoryTests: XCTestCase {
    // same setUp as MoneyRecordsTests (copy it; do not share a base class)
    func testObserveDashboardEmitsOnPaymentInsert() async throws {
        let repo = GRDBInsightsRepository(database: db)
        let stream = repo.observeDashboard(companyId: companyId)
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()!
        XCTAssertEqual(first.projects.count, 1); XCTAssertEqual(first.payments.count, 0); XCTAssertEqual(first.company.id, companyId)
        let pay = Payment(id: UUID(), companyId: companyId, projectId: project.id, scheduleItemId: nil, amount: Money(10, .cad), paidOn: CalendarDate(storage: "2026-10-01")!, method: .cash, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await db.writer.write { db in try PaymentRecord(pay).insert(db) }
        let second = try await iterator.next()!
        XCTAssertEqual(second.payments.map(\.id), [pay.id])
    }
    func testObserveProjectNilWhenDeleted() async throws {
        let repo = GRDBInsightsRepository(database: db)
        var iterator = repo.observeProject(id: project.id).makeAsyncIterator()
        let first = try await iterator.next()!
        XCTAssertEqual(first?.project.id, project.id)
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).softDelete(id: project.id, actor: ActivityActor(userId: nil, name: "Duc"))
        let second = try await iterator.next()!
        XCTAssertNil(second)
    }
    func testObserveDashboardExcludesDeletedRows() async throws {
        let repo = GRDBInsightsRepository(database: db)
        let gone = Expense(id: UUID(), companyId: companyId, projectId: project.id, category: .materials, customCategoryId: nil, costGroup: .material, vendorName: nil, amount: Money(1, .cad), tax: .zero(.cad), spentOn: CalendarDate(storage: "2026-10-01")!, paymentMethod: nil, notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: now)
        try await db.writer.write { db in try ExpenseRecord(gone).insert(db) }
        var iterator = repo.observeDashboard(companyId: companyId).makeAsyncIterator()
        let first = try await iterator.next()!
        XCTAssertEqual(first.expenses.count, 0)
    }
}
```

- [ ] **Step 2: Records** (pattern of `PaymentScheduleItemRecord`; columns from Migration001)

```swift
// ExpenseRecord.swift
import Foundation
import GRDB
import Domain

struct ExpenseRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "expenses"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    var id: String; var companyId: String; var createdAt: String; var updatedAt: String; var deletedAt: String?; var syncState: String
    var projectId: String; var category: String; var customCategoryId: String?; var costGroup: String; var vendorName: String?
    var amount: String; var tax: String; var spentOn: String; var paymentMethod: String?; var notes: String?

    init(_ e: Expense) {
        id = e.id.dbKey; companyId = e.companyId.dbKey; projectId = e.projectId.dbKey
        createdAt = Timestamps.string(e.createdAt); updatedAt = Timestamps.string(e.updatedAt); deletedAt = e.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        category = e.category.rawValue; customCategoryId = e.customCategoryId?.dbKey; costGroup = e.costGroup.rawValue; vendorName = e.vendorName
        amount = e.amount.storageString; tax = e.tax.storageString; spentOn = e.spentOn.storageString; paymentMethod = e.paymentMethod?.rawValue; notes = e.notes
    }
    func toDomain(currency: CurrencyCode) throws -> Expense {
        let t = Self.databaseTableName
        guard let cat = ExpenseCategory(rawValue: category) else { throw DataError.corruptRow(table: t, id: id, column: "category") }
        guard let group = CostGroup(rawValue: costGroup) else { throw DataError.corruptRow(table: t, id: id, column: "cost_group") }
        let method = try paymentMethod.map { raw -> PaymentMethod in guard let m = PaymentMethod(rawValue: raw) else { throw DataError.corruptRow(table: t, id: id, column: "payment_method") }; return m }
        return Expense(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"), companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                       projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"), category: cat,
                       customCategoryId: try customCategoryId.map { try RecordSupport.uuid($0, table: t, id: id, column: "custom_category_id") }, costGroup: group, vendorName: vendorName,
                       amount: try RecordSupport.money(amount, currency: currency, table: t, id: id, column: "amount"), tax: try RecordSupport.money(tax, currency: currency, table: t, id: id, column: "tax"),
                       spentOn: try RecordSupport.calendarDate(spentOn, table: t, id: id, column: "spent_on") ?? CalendarDate(storage: "1970-01-01")!, paymentMethod: method, notes: notes, receiptImages: [],
                       createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"), updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                       deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }
    static func fetchLive(_ db: Database, projectId: String, currency: CurrencyCode) throws -> [Expense] {
        try filter(Column("project_id") == projectId && Column("deleted_at") == nil).order(Column("spent_on")).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
    static func fetchLive(_ db: Database, companyId: String, currency: CurrencyCode) throws -> [Expense] {
        try filter(Column("company_id") == companyId && Column("deleted_at") == nil).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
}
```

`RecordSupport.calendarDate` returns an optional (used for nullable columns); for NOT NULL columns throw `DataError.corruptRow` when nil instead of the `?? CalendarDate(storage:)!` shown above (lint forbids `!`): write a tiny private helper `requiredDate(_:)` in each record or add `RecordSupport.requiredCalendarDate` in `RecordSupport.swift`.

`LabourEntryRecord` (columns `project_id, employee_id, work_date, days, daily_rate, notes`; `days` via `RecordSupport.decimal` required), `PaymentRecord` (`project_id, schedule_item_id?, amount, paid_on, method, notes`), `EmployeeRecord` (`name, phone, role, trade, hourly_rate?, daily_rate?, certifications, emergency_contact, notes`; `toDomain(currency:)` maps optional money) follow the same shape, each with `fetchLive(_:projectId:currency:)` and `fetchLive(_:companyId:currency:)` (Employee: company only).

- [ ] **Step 3: Repository**

```swift
// GRDBInsightsRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBInsightsRepository: InsightsRepository {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }

    public func observeDashboard(companyId: UUID) -> AsyncThrowingStream<DashboardInputs.Snapshot, Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> DashboardInputs.Snapshot in
            guard let companyRecord = try CompanyRecord.filter(Column("id") == key && Column("deleted_at") == nil).fetchOne(db) else { throw DataError.notFound }
            let company = try companyRecord.toDomain()
            let currency = company.currencyCode
            let projectRecords = try ProjectRecord.filter(Column("company_id") == key && Column("deleted_at") == nil).fetchAll(db)
            let fields = try GRDBProjectRepository.scopeFields(db, projectIds: projectRecords.map(\.id))
            let projects = try projectRecords.map { try $0.toDomain(currency: currency, scopeFields: fields[$0.id] ?? []) }
            return DashboardInputs.Snapshot(
                company: company, projects: projects,
                customers: try CustomerRecord.filter(Column("company_id") == key && Column("deleted_at") == nil).fetchAll(db).map { try $0.toDomain() },
                estimateLines: try ProjectEstimateLineRecord.fetchLive(db, companyId: key, currency: currency),
                scheduleItems: try PaymentScheduleItemRecord.fetchLive(db, companyId: key, currency: currency),
                expenses: try ExpenseRecord.fetchLive(db, companyId: key, currency: currency),
                labourEntries: try LabourEntryRecord.fetchLive(db, companyId: key, currency: currency),
                payments: try PaymentRecord.fetchLive(db, companyId: key, currency: currency))
        }
        return Self.stream(observation, in: database.writer)
    }

    public func observeProject(id: UUID) -> AsyncThrowingStream<ProjectInsightsInputs.Snapshot?, Error> {
        let key = id.dbKey
        let observation = ValueObservation.tracking { db -> ProjectInsightsInputs.Snapshot? in
            guard let record = try ProjectRecord.filter(Column("id") == key && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            let currency = try GRDBProjectRepository.currency(db, companyId: record.companyId)
            let fields = try GRDBProjectRepository.scopeFields(db, projectIds: [key])
            let project = try record.toDomain(currency: currency, scopeFields: fields[key] ?? [])
            return ProjectInsightsInputs.Snapshot(
                project: project,
                estimateLines: try ProjectEstimateLineRecord.fetchLive(db, projectId: key, currency: currency),
                scheduleItems: try PaymentScheduleItemRecord.fetchLive(db, projectId: key, currency: currency),
                expenses: try ExpenseRecord.fetchLive(db, projectId: key, currency: currency),
                labourEntries: try LabourEntryRecord.fetchLive(db, projectId: key, currency: currency),
                payments: try PaymentRecord.fetchLive(db, projectId: key, currency: currency))
        }
        return Self.stream(observation, in: database.writer)
    }

    static func stream<T: Sendable>(_ observation: ValueObservation<ValueReducers.Fetch<T>>, in writer: any DatabaseWriter) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: writer) { continuation.yield(value) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

Make `GRDBProjectRepository.currency` and `scopeFields` `static` **internal** (drop `private`) so this repository reuses them. Add `fetchLive(_:companyId:currency:)` to `ProjectEstimateLineRecord` and `PaymentScheduleItemRecord` if only the project variant exists. `CompanyRecord.toDomain()` / `CustomerRecord.toDomain()` — use the existing names (grep). If the `ValueObservation` generic signature does not match GRDB 7's `ValueObservation<ValueReducers.Fetch<T>>`, write `stream` as a generic over `Reducer: ValueReducer` with `Reducer.Value == T`.

- [ ] **Step 4: Push, CI (`ios.yml` runs `swift test` for Data), fix to green**

```bash
git add Packages/Data
git commit -m "feat(data): add expense/labour/payment/employee records and GRDBInsightsRepository"
git push origin HEAD
```

Run: `gh run watch <id> --exit-status`. Fix compile/test failures with follow-up `fix(data): …` commits.

---

### Task 5: Data — `changeStatus` / `setManualProgress` / `changeCustomer` + `GRDBActivityLogRepository`

**Files:**
- Modify: `Packages/Data/Sources/Data/Repositories/GRDBProjectRepository.swift`
- Create: `Packages/Data/Sources/Data/Repositories/GRDBActivityLogRepository.swift`
- Test: `Packages/Data/Tests/DataTests/ProjectMutationTests.swift`, `Packages/Data/Tests/DataTests/ActivityLogRepositoryTests.swift`

**Interfaces:**
- Consumes: Task 3 protocol additions; `ActivityLogRecord.append(_:companyId:actor:action:entityType:entityId:projectId:details:at:)`; `ActivityLogRecord` ↔ `ActivityLogEntry` mapping (check `toDomain()` exists; add if not).
- Produces: `GRDBActivityLogRepository(database:)`.

- [ ] **Step 1: Failing tests**

```swift
// ProjectMutationTests.swift — setUp identical to ProjectRepositoryTests (company, owner, customer, repo)
final class ProjectMutationTests: XCTestCase {
    // … setUp …
    func activities(_ pid: UUID) async throws -> [(String, String)] {
        try await db.writer.read { db in try Row.fetchAll(db, sql: "SELECT action, details_json FROM activity_log WHERE project_id = ? ORDER BY created_at, rowid", arguments: [pid.dbKey]).map { ($0["action"], $0["details_json"]) } }
    }
    func testChangeStatusWritesActivity() async throws {
        let p = project(status: .scheduled); try await repo.save(p, actor: actor)
        try await repo.changeStatus(id: p.id, to: .inProgress, actor: actor)
        XCTAssertEqual(try await repo.get(id: p.id)?.status, .inProgress)
        let a = try await activities(p.id)
        XCTAssertEqual(a.last?.0, "statusChanged"); XCTAssertEqual(a.last?.1, #"{"from":"scheduled","to":"inProgress"}"#)
    }
    func testChangeStatusSameStatusWritesNoActivity() async throws {
        let p = project(status: .scheduled); try await repo.save(p, actor: actor)
        let before = try await activities(p.id).count
        try await repo.changeStatus(id: p.id, to: .scheduled, actor: actor)
        XCTAssertEqual(try await activities(p.id).count, before)
    }
    func testChangeStatusMissingProjectThrowsNotFound() async {
        await XCTAssertThrowsErrorAsync(try await repo.changeStatus(id: UUID(), to: .closed, actor: actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }
    func testSetProgressWritesFromEmptyForNil() async throws {
        let p = project(); try await repo.save(p, actor: actor)
        try await repo.setManualProgress(id: p.id, to: 60, actor: actor)
        XCTAssertEqual(try await activities(p.id).last?.1, #"{"from":"","to":"60"}"#)
        try await repo.setManualProgress(id: p.id, to: nil, actor: actor)
        XCTAssertEqual(try await activities(p.id).last?.1, #"{"from":"60","to":""}"#)
        XCTAssertNil(try await repo.get(id: p.id)?.manualProgress)
    }
    func testSetProgressSameValueWritesNoActivity() async throws {
        let p = project(); try await repo.save(p, actor: actor)
        let before = try await activities(p.id).count
        try await repo.setManualProgress(id: p.id, to: nil, actor: actor)
        XCTAssertEqual(try await activities(p.id).count, before)
    }
    func testSetProgressOutOfRangeThrows() async throws {
        let p = project(); try await repo.save(p, actor: actor)
        await XCTAssertThrowsErrorAsync(try await repo.setManualProgress(id: p.id, to: 101, actor: actor)) { XCTAssertEqual($0 as? DomainError, .invalidProgress) }
    }
    func testChangeCustomerWritesNamesAndRejectsBadTargets() async throws {
        let p = project(); try await repo.save(p, actor: actor)
        let bob = Customer(id: UUID(), companyId: companyId, name: "Bob", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(bob)
        try await repo.changeCustomer(id: p.id, to: bob.id, actor: actor)
        XCTAssertEqual(try await repo.get(id: p.id)?.customerId, bob.id)
        let last = try await activities(p.id).last
        XCTAssertEqual(last?.0, "customerChanged")
        XCTAssertEqual(last?.1, #"{"from":"Ann Lee","fromId":"\#(customer.id.dbKey)","to":"Bob","toId":"\#(bob.id.dbKey)"}"#)
        await XCTAssertThrowsErrorAsync(try await repo.changeCustomer(id: p.id, to: UUID(), actor: actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        var deleted = bob; deleted.deletedAt = now
        try await db.writer.write { db in try db.execute(sql: "UPDATE customers SET deleted_at = ? WHERE id = ?", arguments: [Timestamps.string(self.now), bob.id.dbKey]) }
        await XCTAssertThrowsErrorAsync(try await repo.changeCustomer(id: p.id, to: bob.id, actor: actor)) { XCTAssertEqual($0 as? DomainError, .customerDeleted) }
    }
    func testChangeCustomerRejectsOtherCompany() async throws {
        let p = project(); try await repo.save(p, actor: actor)
        let other = Company(id: UUID(), name: "O", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner2 = User(id: UUID(), companyId: other.id, displayName: "O", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: other, owner: owner2)
        let foreign = Customer(id: UUID(), companyId: other.id, name: "F", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(foreign)
        await XCTAssertThrowsErrorAsync(try await repo.changeCustomer(id: p.id, to: foreign.id, actor: actor)) { XCTAssertEqual($0 as? DomainError, .crossCompany) }
    }
}
```

`XCTAssertThrowsErrorAsync` — check whether the Data tests already define such a helper (grep `ThrowsErrorAsync`); if not, add one in `Packages/Data/Tests/DataTests/TestSupport.swift`:

```swift
func XCTAssertThrowsErrorAsync(_ expression: @autoclosure () async throws -> Void, _ check: (Error) -> Void = { _ in }, file: StaticString = #filePath, line: UInt = #line) async {
    do { try await expression(); XCTFail("expected error", file: file, line: line) } catch { check(error) }
}
```

Whether `GRDBCompanyRepository.create` allows a second company (single-owner MVP) — if it refuses, insert the second company/customer rows with raw SQL in `testChangeCustomerRejectsOtherCompany`.

```swift
// ActivityLogRepositoryTests.swift
final class ActivityLogRepositoryTests: XCTestCase {
    // … same setUp …
    func testObserveForProjectLimitAndOrder() async throws {
        let p = project(status: .scheduled); try await repo.save(p, actor: actor)          // projectCreated
        try await repo.changeStatus(id: p.id, to: .inProgress, actor: actor)                // statusChanged
        try await repo.setManualProgress(id: p.id, to: 10, actor: actor)                    // progressChanged
        let logs = GRDBActivityLogRepository(database: db)
        var it = logs.observeForProject(projectId: p.id, limit: 2).makeAsyncIterator()
        let first = try await it.next()!
        XCTAssertEqual(first.map(\.action), [.progressChanged, .statusChanged])
        try await repo.changeStatus(id: p.id, to: .onHold, actor: actor)
        let second = try await it.next()!
        XCTAssertEqual(second.first?.action, .statusChanged); XCTAssertEqual(second.count, 2)
        XCTAssertEqual(try await logs.list(projectId: p.id).count, 4)
    }
}
```

Fixed clock → identical `occurred_at`; order ties by `rowid DESC` as a secondary key so the test is deterministic.

- [ ] **Step 2: Implement repository methods** (in `GRDBProjectRepository`)

```swift
    public func changeStatus(id: UUID, to status: ProjectStatus, actor: ActivityActor) async throws {
        let now = clock.now(); let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard record.status != status.rawValue else { return }
            try db.execute(sql: "UPDATE projects SET status = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [status.rawValue, stamp, record.id])
            let companyId = try RecordSupport.uuid(record.companyId, table: "projects", id: record.id, column: "company_id")
            try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .statusChanged, entityType: "project", entityId: id, projectId: id,
                                         details: ["from": record.status, "to": status.rawValue], at: now)
        }
    }

    public func setManualProgress(id: UUID, to value: Int?, actor: ActivityActor) async throws {
        if let v = value, !(0...100).contains(v) { throw DomainError.invalidProgress }
        let now = clock.now(); let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard record.manualProgress != value else { return }
            try db.execute(sql: "UPDATE projects SET manual_progress = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [value, stamp, record.id])
            let companyId = try RecordSupport.uuid(record.companyId, table: "projects", id: record.id, column: "company_id")
            try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .progressChanged, entityType: "project", entityId: id, projectId: id,
                                         details: ["from": record.manualProgress.map(String.init) ?? "", "to": value.map(String.init) ?? ""], at: now)
        }
    }

    public func changeCustomer(id: UUID, to customerId: UUID, actor: ActivityActor) async throws {
        let now = clock.now(); let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard let target = try CustomerRecord.filter(Column("id") == customerId.dbKey).fetchOne(db) else { throw DomainError.notFound }
            guard target.deletedAt == nil else { throw DomainError.customerDeleted }
            guard target.companyId == record.companyId else { throw DomainError.crossCompany }
            guard target.id != record.customerId else { return }
            let fromName = try String.fetchOne(db, sql: "SELECT name FROM customers WHERE id = ?", arguments: [record.customerId]) ?? ""
            try db.execute(sql: "UPDATE projects SET customer_id = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [target.id, stamp, record.id])
            let companyId = try RecordSupport.uuid(record.companyId, table: "projects", id: record.id, column: "company_id")
            try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .customerChanged, entityType: "project", entityId: id, projectId: id,
                                         details: ["from": fromName, "to": target.name, "fromId": record.customerId, "toId": target.id], at: now)
        }
    }
```

`ProjectRecord.manualProgress` is `Int?` (check); `CustomerRecord` fields `companyId`, `deletedAt`, `name` (check names).

```swift
// GRDBActivityLogRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBActivityLogRepository: ActivityLogRepository {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }

    public func observeForProject(projectId: UUID, limit: Int) -> AsyncThrowingStream<[ActivityLogEntry], Error> {
        let key = projectId.dbKey
        let observation = ValueObservation.tracking { db in try Self.fetch(db, projectId: key, limit: limit) }
        return GRDBInsightsRepository.stream(observation, in: database.writer)
    }
    public func list(projectId: UUID) async throws -> [ActivityLogEntry] {
        let key = projectId.dbKey
        return try await database.writer.read { db in try Self.fetch(db, projectId: key, limit: nil) }
    }
    private static func fetch(_ db: Database, projectId: String, limit: Int?) throws -> [ActivityLogEntry] {
        var request = ActivityLogRecord.filter(Column("project_id") == projectId && Column("deleted_at") == nil)
            .order(Column("occurred_at").desc, Column.rowID.desc)
        if let limit { request = request.limit(limit) }
        return try request.fetchAll(db).map { try $0.toDomain() }
    }
}
```

- [ ] **Step 3: Push, CI green, commit**

```bash
git add Packages/Data
git commit -m "feat(data): add status/progress/customer mutations and activity log repository"
git push origin HEAD
```

---

### Task 6: Data — `SampleData` with relative dates and money rows

**Files:**
- Modify: `Packages/Data/Sources/Data/Seed/SampleData.swift`
- Modify: `Packages/Data/Tests/DataTests/SampleDataTests.swift`

**Interfaces:**
- Produces: `SampleData.seedIfEmpty(_ database: AppDatabase, clock: Clock, today: CalendarDate) async throws -> CompanySetup` (new `today` parameter; App passes `--today` or the real date).

- [ ] **Step 1: Failing test** (append to `SampleDataTests`)

```swift
    func testSeedMatchesSpecTotals() async throws {
        let db = try AppDatabase.inMemory()
        let today = CalendarDate(storage: "2026-10-03")!
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now), today: today)
        var it = GRDBInsightsRepository(database: db).observeDashboard(companyId: setup.company.id).makeAsyncIterator()
        let snap = try await it.next()!
        let d = DashboardComposer.compose(snap.with(today: today))
        XCTAssertEqual(d.totals.activeJobs, 1)
        XCTAssertEqual(d.totals.outstanding, Money(55_400, .cad))
        XCTAssertEqual(d.totals.collected, Money(26_100, .cad))
        XCTAssertEqual(d.totals.spent, Money(10_685, .cad))
        XCTAssertEqual(d.totals.cashPosition, Money(15_415, .cad))
        XCTAssertEqual(d.attention.map(\.kind), [.paymentRisk, .paymentOverdue, .startsToday])
        let basement = try XCTUnwrap(d.cards.first { $0.project.name == "Basement Renovation" })
        XCTAssertEqual(basement.insights.financials?.cashPosition, Money(-3085, .cad))
        XCTAssertEqual(basement.insights.timeline.daysRemaining, 27)
        XCTAssertEqual(basement.project.startDate, today.adding(days: -18))
        let kitchen = try XCTUnwrap(d.cards.first { $0.project.name == "Kitchen Renovation" })
        XCTAssertEqual(kitchen.project.startDate, today)
        XCTAssertEqual(snap.labourEntries.count, 3); XCTAssertEqual(snap.expenses.count, 3); XCTAssertEqual(snap.payments.count, 2)
    }
```

Update the existing `testSeedCreatesThreeProjectsAndIsIdempotent` call site to the new signature.

- [ ] **Step 2: Implement** — in `SampleData.seedIfEmpty`:
  - signature `seedIfEmpty(_ database: AppDatabase, clock: Clock, today: CalendarDate)`; delete the local `let today = CalendarDate(now, timeZone: .gmt)`.
  - project dates: Basement `start: today.adding(days: -18)`, `end: today.adding(days: 27)`; Kitchen `start: today`, `end: today.adding(days: 34)`; Roof `start: today.adding(days: -63)`, `end: today.adding(days: -44)` — change the `project(...)` helper to take `CalendarDate` instead of `String`.
  - after the schedule block, insert employees, labour entries, expenses, payments inside one `database.writer.write`:

```swift
        let mike = employee("Mike", 250), john = employee("John", 220), davidW = employee("David", 200)   // helper builds Employee with dailyRate
        // `basementDeposit` is the PaymentScheduleItem value built with `item(...)` above — keep it in a `let` before passing it to `replace()`.
        let depositItem = basementDeposit
        try await database.writer.write { db in
            for e in [mike, john, davidW] { try EmployeeRecord(e).insert(db) }
            for l in [labour(basementProject.id, mike.id, days: 8, rate: 250, on: today.adding(days: -10)),
                      labour(basementProject.id, john.id, days: 10, rate: 220, on: today.adding(days: -9)),
                      labour(basementProject.id, davidW.id, days: 7, rate: 200, on: today.adding(days: -8))] { try LabourEntryRecord(l).insert(db) }
            for x in [expense(basementProject.id, .material, "Lumber — Home Depot", 2400, 312, on: today.adding(days: -15)),
                      expense(basementProject.id, .material, "Drywall", 1500, 195, on: today.adding(days: -12)),
                      expense(basementProject.id, .other, "Dumpster rental", 600, 78, on: today.adding(days: -16))] { try ExpenseRecord(x).insert(db) }
            try PaymentRecord(payment(basementProject.id, 7600, item: depositItem.id, on: today.adding(days: -19))).insert(db)
            try PaymentRecord(payment(roofProject.id, 18_500, item: nil, on: today.adding(days: -40))).insert(db)
        }
```

  with small local helper funcs `employee`, `labour`, `expense` (category `.materials`/`.wasteDisposal`, costGroup as given, `paymentMethod: .creditCard`), `payment` (method `.eTransfer`). Keep `roofProject` in a `let` (it is currently built inline).

- [ ] **Step 3: App call site** — `App/AppContainer.swift:65` passes `today:`; for now `CalendarDate(Date(), timeZone: .current)` (Task 13 replaces it with the `--today` override).

- [ ] **Step 4: Push, CI green, commit**

```bash
git add Packages/Data App/AppContainer.swift
git commit -m "feat(data): seed relative dates, expenses, labour and payments for the dashboard"
git push origin HEAD
```

---

### Task 7: DesignSystem — `DateLabel`, `HealthChip`, `DualProgressBar`, `ActivityRow`, `SkeletonCard`

**Files:**
- Create: `Packages/DesignSystem/Sources/DesignSystem/Components/DateLabel.swift`, `HealthChip.swift`, `DualProgressBar.swift`, `ActivityRow.swift`, `SkeletonCard.swift`
- Modify: `Packages/DesignSystem/Sources/DesignSystem/Gallery/*` (add one gallery row per component; follow the existing gallery pattern)

**Interfaces:**
- Produces: `DateLabel(_ date: Date, style: DateLabel.Style = .short)` (`.short` → "Oct 3, 2026", `.full` → "Friday, October 3, 2026"; vi via locale), `HealthChip(_ title: LocalizedStringKey, tone: DSTone)`, `DualProgressBar(expected: Int?, actual: Int, expectedLabel: LocalizedStringKey, actualLabel: LocalizedStringKey)`, `ActivityRow(systemImage: String, title: Text, subtitle: Text)`, `SkeletonCard(lines: Int = 3)`.

- [ ] **Step 1: Implement**

```swift
// DateLabel.swift
import SwiftUI

public struct DateLabel: View {
    public enum Style { case short, full }
    private let date: Date
    private let style: Style
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    public init(_ date: Date, style: Style = .short) { self.date = date; self.style = style }

    public var body: some View {
        Text(verbatim: Self.string(date, style: style, locale: locale, timeZone: timeZone))
    }

    /// DateFormatter honours the in-app locale override; `Text(date, format:)` does not.
    public static func string(_ date: Date, style: Style, locale: Locale, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = locale; f.timeZone = timeZone
        f.dateStyle = style == .short ? .medium : .full
        f.timeStyle = .none
        return f.string(from: date)
    }
}
```

```swift
// HealthChip.swift
import SwiftUI
public struct HealthChip: View {
    private let title: LocalizedStringKey; private let tone: DSTone
    public init(_ title: LocalizedStringKey, tone: DSTone) { self.title = title; self.tone = tone }
    public var body: some View {
        Label { Text(title) } icon: { Circle().fill(tone.foreground).frame(width: 8, height: 8) }
            .font(DSTypography.caption).foregroundStyle(tone.foreground)
            .padding(.horizontal, DSSpacing.sm).padding(.vertical, DSSpacing.xs)
            .background(tone.foreground.opacity(0.12), in: Capsule())
    }
}
```

```swift
// DualProgressBar.swift
import SwiftUI
public struct DualProgressBar: View {
    private let expected: Int?; private let actual: Int
    private let expectedLabel: LocalizedStringKey; private let actualLabel: LocalizedStringKey
    public init(expected: Int?, actual: Int, expectedLabel: LocalizedStringKey, actualLabel: LocalizedStringKey) { self.expected = expected; self.actual = actual; self.expectedLabel = expectedLabel; self.actualLabel = actualLabel }
    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DSColor.textSecondary.opacity(0.15))
                    if let e = expected { Capsule().fill(DSColor.textSecondary.opacity(0.35)).frame(width: geo.size.width * CGFloat(min(100, max(0, e))) / 100) }
                    Capsule().fill(actualTone.foreground).frame(width: geo.size.width * CGFloat(min(100, max(0, actual))) / 100, height: 6)
                }
            }.frame(height: 10)
            HStack(spacing: DSSpacing.md) {
                legend(actualLabel, "\(actual)%", actualTone.foreground)
                if let e = expected { legend(expectedLabel, "\(e)%", DSColor.textSecondary) }
            }.font(DSTypography.caption)
        }
    }
    private var actualTone: DSTone { if let e = expected, actual + 10 < e { return .warning }; return .accent }
    private func legend(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        HStack(spacing: DSSpacing.xs) { Circle().fill(color).frame(width: 6, height: 6); Text(title); Text(verbatim: value).font(DSTypography.money(.caption)) }
            .foregroundStyle(DSColor.textSecondary)
    }
}
```

`CGFloat` in DesignSystem is fine (lint only covers Domain/Data).

```swift
// ActivityRow.swift
import SwiftUI
public struct ActivityRow: View {
    private let systemImage: String; private let title: Text; private let subtitle: Text
    public init(systemImage: String, title: Text, subtitle: Text) { self.systemImage = systemImage; self.title = title; self.subtitle = subtitle }
    public var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            Image(systemName: systemImage).foregroundStyle(DSColor.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) { title.font(DSTypography.callout).foregroundStyle(DSColor.textPrimary); subtitle.font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
            Spacer(minLength: 0)
        }.frame(minHeight: DSSpacing.minTouch)
    }
}
// SkeletonCard.swift
import SwiftUI
public struct SkeletonCard: View {
    private let lines: Int
    public init(lines: Int = 3) { self.lines = lines }
    public var body: some View {
        Card { VStack(alignment: .leading, spacing: DSSpacing.sm) { ForEach(0..<lines, id: \.self) { i in RoundedRectangle(cornerRadius: 4).fill(DSColor.textSecondary.opacity(0.15)).frame(width: i == 0 ? 160 : 240, height: 14) } } }
            .redacted(reason: .placeholder).accessibilityHidden(true)
    }
}
```

Gallery: add a `GalleryRow` (or whatever the existing pattern is) for each so screenshots of the gallery cover them.

- [ ] **Step 2: Push, CI build green, commit**

```bash
git add Packages/DesignSystem
git commit -m "feat(design-system): add DateLabel, HealthChip, DualProgressBar, ActivityRow and SkeletonCard"
git push origin HEAD
```

---

### Task 8: FeatureSupport — styles, labels, `ProjectCardView` upgrade, localization batch, script

**Files:**
- Create: `Packages/Features/Sources/FeatureSupport/HealthStyle.swift`, `AttentionText.swift`, `ActivityText.swift`, `TodayProvider.swift`
- Modify: `Packages/Features/Sources/FeatureSupport/ProjectCardView.swift`, `ProjectRoute.swift`, `CalendarDateBridge.swift`
- Modify: `App/Resources/Localizable.xcstrings`, `scripts/check_localization.py`

**Interfaces:**
- Produces: `HealthStatus.titleKey/tone`, `HealthReason.text(currency:locale:) -> Text`, `AttentionItem.text(projectName:currency:locale:) -> Text`, `AttentionItem.tone/systemImage`, `ActivityDetail.text(currency:locale:) -> Text`, `ActivityAction.systemImage`, `ProjectStatus.hintKey`, `ProjectCardView(project:customerName:insights:progress:)`, `ProjectRoute.activity(UUID)`, `CalendarDate.init(_ date: Date, timeZone:)` (exists) + `TodayProvider.today(timeZone:) -> CalendarDate`.

- [ ] **Step 1: Styles**

```swift
// HealthStyle.swift
import SwiftUI
import Domain
import DesignSystem

public extension HealthStatus {
    var titleKey: LocalizedStringKey { LocalizedStringKey("health.status." + name) }
    var name: String { switch self { case .onTrack: return "onTrack"; case .atRisk: return "atRisk"; case .delayed: return "delayed"; case .paymentRisk: return "paymentRisk"; case .overBudget: return "overBudget" } }
    var tone: DSTone { switch self { case .onTrack: return .success; case .atRisk: return .warning; case .delayed, .paymentRisk, .overBudget: return .danger } }
}

public extension HealthReason {
    /// Localized sentence with parameters (money formatted with the company currency).
    func text(currency: String, locale: Locale) -> Text {
        switch self {
        case .budgetExceeded(let g, let over):
            return Text("health.reason.budgetExceeded \(Text(LocalizedStringKey("costGroup." + g.rawValue))) \(MoneyFormat.string(over.amount, currencyCode: currency, locale: locale))")
        case .paymentOverdue(let n): return Text("health.reason.paymentOverdue \(n)")
        case .pastCompletionDate(let d): return Text("health.reason.pastCompletionDate \(d)")
        case .budgetNearLimit(let g, let pct):
            let p = pct.map { LocaleNumberParser.string($0.points, locale: locale, fractionDigits: 1) + "%" } ?? "—"
            return Text("health.reason.budgetNearLimit \(Text(LocalizedStringKey("costGroup." + g.rawValue))) \(p)")
        case .deadlineApproaching(let d, let p): return Text("health.reason.deadlineApproaching \(d) \(p)")
        }
    }
}
```

`MoneyFormat.string(_:currencyCode:locale:)` — check what `MoneyText` uses internally in DesignSystem and expose that formatter as `public enum MoneyFormat` if not already public; `LocaleNumberParser` exists in DesignSystem (2a). `costGroup.<raw>` keys exist only for labour/material — add the other four (`subcontractor`, `equipment`, `permit`, `other`) in this task's localization batch.

```swift
// AttentionText.swift
public extension AttentionItem {
    var tone: DSTone { switch kind { case .overBudget, .paymentOverdue, .paymentRisk: return .danger; case .delayed, .dueToday: return .warning; case .startsToday: return .info; case .atRisk: return .warning } }
    var systemImage: String { switch kind { case .overBudget: return "chart.bar.xaxis"; case .paymentOverdue, .paymentRisk, .dueToday: return "dollarsign.circle"; case .delayed: return "clock.badge.exclamationmark"; case .startsToday: return "flag"; case .atRisk: return "exclamationmark.triangle" } }
    func text(currency: String, locale: Locale) -> Text {
        switch self {
        case .health(_, _, let reason): return reason.text(currency: currency, locale: locale)
        case .paymentOverdue(_, _, let label, let remaining, let days): return Text("attention.paymentOverdue \(RowLabel.text(label)) \(days) \(MoneyFormat.string(remaining.amount, currencyCode: currency, locale: locale))")
        case .paymentDueToday(_, _, let label, let remaining): return Text("attention.paymentDueToday \(RowLabel.text(label)) \(MoneyFormat.string(remaining.amount, currencyCode: currency, locale: locale))")
        case .startsToday: return Text("attention.startsToday")
        }
    }
}
```

`RowLabel.text(_:)` lives in ProjectsFeature today (2a) — move it to FeatureSupport in this task (it maps `schedule.row.*`/`otherCost.*` keys vs verbatim labels) and update its 2a call sites.

```swift
// ActivityText.swift
public extension ActivityAction {
    var systemImage: String {
        switch self {
        case .projectCreated: return "plus.circle"; case .projectDeleted: return "trash"; case .contractValueChanged: return "dollarsign.circle"
        case .progressChanged: return "chart.line.uptrend.xyaxis"; case .statusChanged: return "arrow.triangle.2.circlepath"; case .expenseAdded: return "cart"
        case .paymentReceived: return "banknote"; case .estimateChanged: return "list.number"; case .scheduleChanged: return "calendar.badge.clock"
        case .customerCreated, .customerChanged: return "person"; case .scopeChanged: return "doc.text"; case .timelineChanged: return "calendar"
        }
    }
}
public extension ActivityDetail {
    func text(currency: String, locale: Locale) -> Text {
        func money(_ s: String) -> String { MoneyFormat.string(Decimal(string: s) ?? 0, currencyCode: currency, locale: locale) }
        switch self {
        case .statusChanged(let f, let t): return Text("activity.statusChanged \(Text(f.titleKey)) \(Text(t.titleKey))")
        case .progressChanged(let f, let t): return Text("activity.progressChanged \(f.map { "\($0)%" } ?? "—") \(t.map { "\($0)%" } ?? "—")")
        case .contractValueChanged(let f, let t): return Text("activity.contractValueChanged \(money(f)) \(money(t))")
        case .estimateChanged(let g, let f, let t):
            let group = g.map { Text(LocalizedStringKey("costGroup." + $0.rawValue)) } ?? Text("activity.estimate.all")
            return Text("activity.estimateChanged \(group) \(money(f)) \(money(t))")
        case .scheduleChanged(let f, let t): return Text("activity.scheduleChanged \(money(f)) \(money(t))")
        case .customerChanged(let f, let t): return Text("activity.customerChanged \(f) \(t)")
        case .plain(let a): return Text(LocalizedStringKey("activity." + a.rawValue))
        }
    }
}
public extension ProjectStatus { var hintKey: LocalizedStringKey { LocalizedStringKey("status." + rawValue + ".hint") } }
```

String interpolation into `Text("key \(arg)")` produces a `LocalizedStringKey` with `%@`/`%lld` placeholders; the `.xcstrings` key must be written with the placeholders in place (e.g. key `"activity.statusChanged %@ %@"`). Match exactly the key strings SwiftUI generates (`%lld` for Int, `%@` for String/Text) — verify by running the app on CI and reading the screenshot, or by checking `check_localization.py` output: extend the script so an interpolated key literal `"activity.statusChanged \(…) \(…)"` is normalised to the placeholder form before lookup (regex: replace each `\(…)` with `%@`, and accept either `%@` or `%lld` variant in the catalog).

```swift
// TodayProvider.swift
import Foundation
import Domain
public enum TodayProvider {
    /// App-wide "today"; UI tests override it via `--today` (set by the App target).
    nonisolated(unsafe) public static var override: CalendarDate?
    public static func today(timeZone: TimeZone) -> CalendarDate { override ?? CalendarDate(Date(), timeZone: timeZone) }
}
```

`ProjectRoute`: `public enum ProjectRoute: Hashable { case detail(UUID), activity(UUID) }` — update the `switch` in `HomeView`/`ProjectsListView` (Task 9/11 add the `.activity` destination; until then handle it with the same `makeDetail` to keep the build green).

- [ ] **Step 2: `ProjectCardView`**

```swift
public struct ProjectCardView: View {
    let project: Project
    let customerName: String
    let insights: ProjectInsights?
    let progress: Int
    @Environment(\.timeZone) private var timeZone

    public init(project: Project, customerName: String, insights: ProjectInsights?, progress: Int) { … }
    /// 2a call sites.
    public init(summary: ProjectSummary, progress: Int) { self.init(project: summary.project, customerName: summary.customerName, insights: nil, progress: progress) }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) { /* address / name / customer as today */ }
                    Spacer()
                    VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                        StatusBadge(project.status.titleKey, tone: project.status.tone)
                        if let h = insights?.health { HealthChip(h.status.titleKey, tone: h.status.tone).accessibilityIdentifier("card_health") }
                    }
                }
                /* progress block as today */
                if let f = insights?.financials {
                    HStack {
                        stat("home.card.spent", f.spentSoFar); Divider(); stat("home.card.collected", f.collected); Divider()
                        stat("home.card.cash", f.cashPosition, tone: f.cashPosition.isNegative ? .danger : .neutral)
                    }.frame(maxWidth: .infinity)
                } else {
                    FormRow("home.contractValue") { MoneyText(amount: project.contractValue.amount, currencyCode: project.contractValue.currency.rawValue, style: .headline) }
                }
                if let start = project.startDate, let end = project.estimatedCompletionDate {
                    HStack(spacing: DSSpacing.xs) { DateLabel(start.noonDate(in: timeZone)); Text(verbatim: "→"); DateLabel(end.noonDate(in: timeZone)) }
                        .font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project_card_\(project.id.uuidString)")
    }
    private func stat(_ title: LocalizedStringKey, _ m: Money, tone: DSTone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary); MoneyText(amount: m.amount, currencyCode: m.currency.rawValue, style: .callout).foregroundStyle(tone == .danger ? DSColor.danger : DSColor.textPrimary) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 3: Localization batch + script**

Add every key from spec §7 to `Localizable.xcstrings` (en + vi), including the interpolated forms (`"activity.statusChanged %@ %@"`, `"health.reason.paymentOverdue %lld"`, `"attention.paymentOverdue %@ %lld %@"`, …) and the 13 `status.<raw>.hint`. Vietnamese examples: `health.status.paymentRisk` → "Payment risk" (trade term kept) — no: use "Rủi ro thanh toán"; `health.status.overBudget` → "Vượt budget"; `home.totals.cash` → "Dòng tiền hiện tại"; `home.attention.empty` → "Hôm nay không có gì cần chú ý"; `status.inProgress.hint` → "Đang thi công tại công trình".

`scripts/check_localization.py`: extend the generated set from Swift enums (parse `case` lines of `ProjectStatus`, `ActivityAction`, `HealthStatus` names via `name` switch, `HealthReason` case names, `TimelineError`, all six `CostGroup` cases) and add interpolation normalisation for string literals (`\(…)` → `%@`, accept `%lld` alternative). Run until 0 errors.

- [ ] **Step 4: Lint, push, CI green, commit**

```bash
python scripts/check_localization.py && python scripts/lint_sources.py
git add Packages/Features/Sources/FeatureSupport Packages/Features/Sources/ProjectsFeature App/Resources scripts
git commit -m "feat(features): add health/attention/activity text helpers, upgraded project card and 2b localization"
git push origin HEAD
```

---

### Task 9: HomeFeature — dashboard screen

**Files:**
- Modify: `Packages/Features/Sources/HomeFeature/HomeViewModel.swift`, `HomeView.swift`
- Create: `Packages/Features/Sources/HomeFeature/AttentionRow.swift`, `AttentionListSheet.swift`, `TotalsCard.swift`

**Interfaces:**
- Consumes: `InsightsRepository.observeDashboard`, `DashboardComposer`, Task 7/8 components.
- Produces: `HomeViewModel(insightsRepository:companyId:today:)`, `update(today:)`, `retry()`; `HomeView(viewModel:makeDetail:)` unchanged signature.

- [ ] **Step 1: VM**

```swift
@Observable @MainActor
public final class HomeViewModel {
    public private(set) var dashboard: Dashboard?
    public private(set) var isLoaded = false
    public private(set) var errorKey: LocalizedStringKey?
    public var currency: String { dashboard?.totals.currency.rawValue ?? "" }

    private var snapshot: DashboardInputs.Snapshot?
    private var today: CalendarDate
    private let insightsRepository: any InsightsRepository
    private let companyId: UUID
    private var generation = 0

    public init(insightsRepository: any InsightsRepository, companyId: UUID, today: CalendarDate) { self.insightsRepository = insightsRepository; self.companyId = companyId; self.today = today }

    public func start() async {
        generation += 1; let g = generation
        errorKey = nil
        do {
            for try await value in insightsRepository.observeDashboard(companyId: companyId) {
                guard g == generation else { return }
                snapshot = value; isLoaded = true; recompose()
            }
        } catch is CancellationError {
        } catch { errorKey = "home.error" }
    }
    public func update(today: CalendarDate) { guard today != self.today else { return }; self.today = today; recompose() }
    /// Resubscribes after an error (the view calls `start()` again in a fresh task).
    public func retry() { errorKey = nil; isLoaded = false }
    private func recompose() { if let s = snapshot { dashboard = DashboardComposer.compose(s.with(today: today)) } }
}
```

- [ ] **Step 2: View** — replace `HomeView.body`:

```swift
    public var body: some View {
        Group {
            if viewModel.errorKey != nil {
                VStack(spacing: DSSpacing.md) {
                    EmptyState(systemImage: "exclamationmark.triangle", title: "home.error", message: "home.error.message")
                    SecondaryButton("home.retry") { viewModel.retry(); retryToken += 1 }.accessibilityIdentifier("home_retry")
                }
            } else if let d = viewModel.dashboard {
                ScrollView { content(d).padding(.vertical, DSSpacing.lg) }
            } else {
                ScrollView { VStack(spacing: DSSpacing.md) { SkeletonCard(lines: 2); SkeletonCard(); SkeletonCard() }.padding(DSSpacing.lg) }
            }
        }
        .background(DSColor.background)
        .navigationTitle("home.title")
        .navigationDestination(for: ProjectRoute.self) { route in
            switch route { case .detail(let id), .activity(let id): makeDetail(id) }
        }
        .task(id: retryToken) { await viewModel.start() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { viewModel.update(today: TodayProvider.today(timeZone: timeZone)) } }
        .sheet(isPresented: $showAllAttention) { AttentionListSheet(items: viewModel.dashboard?.attention ?? [], names: names, currency: viewModel.currency) { id in showAllAttention = false; path.append(ProjectRoute.detail(id)) } }
    }

    @ViewBuilder private func content(_ d: Dashboard) -> some View {
        let names = Dictionary(d.cards.map { ($0.id, $0.project.name) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(verbatim: companyName).font(DSTypography.title)
                DateLabel(TodayProvider.today(timeZone: timeZone).noonDate(in: timeZone), style: .full).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary).accessibilityIdentifier("home_date")
            }.padding(.horizontal, DSSpacing.lg)

            Card {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("home.attention.title").font(DSTypography.headline)
                    if d.attention.isEmpty {
                        Label("home.attention.empty", systemImage: "checkmark.circle").foregroundStyle(DSColor.success).accessibilityIdentifier("home_attention_empty")
                    } else {
                        ForEach(d.attention.prefix(5)) { item in
                            NavigationLink(value: ProjectRoute.detail(item.projectId)) { AttentionRow(item: item, projectName: names[item.projectId] ?? "", currency: viewModel.currency) }.buttonStyle(.plain)
                        }
                        if d.attention.count > 5 { Button("home.attention.more \(d.attention.count)") { showAllAttention = true }.accessibilityIdentifier("home_attention_more") }
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("home_attention").padding(.horizontal, DSSpacing.lg)

            TotalsCard(totals: d.totals).padding(.horizontal, DSSpacing.lg)

            if d.cards.isEmpty {
                EmptyState(systemImage: "hammer", title: "home.empty.title", message: "home.empty.message")
            } else {
                ForEach(CardGroup.allCases, id: \.self) { group in
                    let cards = d.cards.filter { $0.group == group }
                    if !cards.isEmpty {
                        SectionHeader(groupKey(group)).padding(.horizontal, DSSpacing.lg)
                        ForEach(cards) { card in
                            NavigationLink(value: ProjectRoute.detail(card.id)) { ProjectCardView(project: card.project, customerName: card.customerName, insights: card.insights, progress: card.insights.progress) }
                                .buttonStyle(.plain).padding(.horizontal, DSSpacing.lg)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("home_projects")
    }
```

State: `@State private var showAllAttention = false`, `@State private var retryToken = 0`, `@Environment(\.scenePhase)`, `@Environment(\.timeZone)`; `companyName` injected via init (`HomeView(viewModel:companyName:makeDetail:)` — update `App/Screens.swift` accordingly in Task 13; until then keep a default `companyName: String = ""`). `groupKey`: `.inWork → "home.group.inWork"`, `.preStart → "home.group.preStart"`, `.workDone → "home.group.workDone"`. Keep `.accessibilityIdentifier("home_list")` on the ScrollView for Foundation smoke tests.

`TotalsCard`:

```swift
struct TotalsCard: View {
    let totals: CompanyTotals
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("home.totals.title").font(DSTypography.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                    SummaryTile("home.totals.active", value: Text(verbatim: "\(totals.activeJobs)")).accessibilityIdentifier("home_total_active")
                    SummaryTile("home.totals.outstanding", value: money(totals.outstanding)).accessibilityIdentifier("home_total_outstanding")
                    SummaryTile("home.totals.collected", value: money(totals.collected)).accessibilityIdentifier("home_total_collected")
                    SummaryTile("home.totals.cash", value: money(totals.cashPosition), tone: totals.cashPosition.isNegative ? .danger : .neutral).accessibilityIdentifier("home_total_cash")
                }
                if totals.excludedCount > 0 { Text("home.totals.excluded \(totals.excludedCount)").font(DSTypography.caption).foregroundStyle(DSColor.warning) }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("home_totals")
    }
    private func money(_ m: Money) -> Text { Text(verbatim: MoneyFormat.string(m.amount, currencyCode: m.currency.rawValue, locale: locale)) }
    @Environment(\.locale) private var locale
}
```

`SummaryTile` must forward `accessibilityIdentifier` to a labelled element whose `label` contains the value — set `.accessibilityElement(children: .combine)` inside `SummaryTile` if it is not already so UI tests can read `home_total_outstanding.label`.

`AttentionRow`: `ActivityRow(systemImage: item.systemImage, title: Text(verbatim: projectName), subtitle: item.text(currency:locale:))` tinted with `item.tone`, identifier `attention_<item.id>`. `AttentionListSheet`: `NavigationStack { List(items) { … } .navigationTitle("home.attention.title") }` with a Done button.

- [ ] **Step 3: App wiring stub** — `App/Screens.swift` `HomeScreen.init`: `HomeViewModel(insightsRepository: ready.insightsRepository, companyId: setup.company.id, today: TodayProvider.today(timeZone: .current))` — requires `Ready.insightsRepository` (Task 13 adds it; to keep this task green, add the `insightsRepository`/`activityLogRepository` fields to `AppContainer.Ready` and construct `GRDBInsightsRepository(database:)`/`GRDBActivityLogRepository(database:)` in `load()` **in this task**, and pass `companyName: setup.company.name`).

- [ ] **Step 4: Push, CI green (build + existing UI tests), commit**

```bash
git add Packages/Features/Sources/HomeFeature App
git commit -m "feat(home): dashboard with attention, company totals and grouped project cards"
git push origin HEAD
```

---

### Task 10: Detail VM — insights, status, progress, customer, delete

**Files:**
- Modify: `Packages/Features/Sources/ProjectsFeature/Detail/ProjectDetailViewModel.swift`
- Create: `Packages/Features/Sources/ProjectsFeature/Detail/StatusPickerSheet.swift`, `ProgressSheet.swift`, `CustomerPickerSheet.swift`

**Interfaces:**
- Consumes: `InsightsRepository.observeProject`, `ActivityLogRepository.observeForProject(limit: 5)`, `ProjectRepository.changeStatus/setManualProgress/changeCustomer/softDelete`, `CustomerRepository.observeAll`, `ProjectStatusChange`, `ProjectInsightsComposer`.
- Produces: VM API `insights: ProjectInsights?`, `activity: [ActivityLogEntry]`, `update(today:)`, `changeStatus(_:) async -> StatusChangeOutcome?`, `setProgress(_:) async -> Bool`, `changeCustomer(_:) async -> Bool`, `deleteProject() async -> Bool`, `actionErrorKey: LocalizedStringKey?`; init gains `insightsRepository:`, `activityLogRepository:`, `customerRepository:`, `today:`.

- [ ] **Step 1: VM additions**

```swift
    public private(set) var insights: ProjectInsights?
    public private(set) var activity: [ActivityLogEntry] = []
    public var actionErrorKey: LocalizedStringKey?
    private var insightsSnapshot: ProjectInsightsInputs.Snapshot?
    private var today: CalendarDate
    private let insightsRepository: any InsightsRepository
    private let activityLogRepository: any ActivityLogRepository
    public let customerRepository: any CustomerRepository

    /// Runs alongside `start()`; bind to a second `.task`.
    public func startInsights() async {
        do {
            for try await value in insightsRepository.observeProject(id: projectId) {
                insightsSnapshot = value
                insights = value.map { ProjectInsightsComposer.compose($0.with(today: today)) }
            }
        } catch is CancellationError {} catch { errorKey = "detail.error" }
    }
    public func startActivity() async {
        do { for try await value in activityLogRepository.observeForProject(projectId: projectId, limit: 5) { activity = value } } catch is CancellationError {} catch {}
    }
    public func update(today: CalendarDate) {
        guard today != self.today else { return }; self.today = today
        insights = insightsSnapshot.map { ProjectInsightsComposer.compose($0.with(today: today)) }
    }

    public func changeStatus(_ status: ProjectStatus) async -> StatusChangeOutcome? {
        guard let project = snapshot?.project else { return nil }
        let outcome = ProjectStatusChange.apply(project, to: status)
        do { try await projectRepository.changeStatus(id: projectId, to: status, actor: actor); return outcome } catch { actionErrorKey = Self.key(for: error); return nil }
    }
    public func setProgress(_ value: Int?) async -> Bool {
        do { try await projectRepository.setManualProgress(id: projectId, to: value, actor: actor); return true } catch { actionErrorKey = Self.key(for: error); return false }
    }
    public func changeCustomer(_ customerId: UUID) async -> Bool {
        do { try await projectRepository.changeCustomer(id: projectId, to: customerId, actor: actor); return true } catch { actionErrorKey = Self.key(for: error); return false }
    }
    public func deleteProject() async -> Bool {
        do { try await projectRepository.softDelete(id: projectId, actor: actor); return true } catch { actionErrorKey = Self.key(for: error); return false }
    }
    static func key(for error: Error) -> LocalizedStringKey {
        switch error as? DomainError {
        case .notFound?: return "error.projectGone"
        case .customerDeleted?: return "error.customerDeleted"
        case .currencyMismatch?: return "error.currencyMismatch"
        case .invalidProgress?: return "error.invalidProgress"
        default: return "error.generic"
        }
    }
```

`softDelete` in Data throws `DataError.notFound` (not `DomainError`) — map `DataError` is not visible to Features; make `GRDBProjectRepository.softDelete` throw `DomainError.notFound` instead (one-line change in Data; `DataError.notFound` stays for internal use). Grep Data tests asserting `DataError.notFound` from `softDelete` and update them.

- [ ] **Step 2: Sheets**

`StatusPickerSheet(current: ProjectStatus, onPick: (ProjectStatus) -> Void)`: `NavigationStack { List { ForEach(phases) { phase in Section(phaseKey) { ForEach(statuses(in: phase)) { s in Button { onPick(s) } label: { HStack { VStack(alignment: .leading) { Text(s.titleKey); Text(s.hintKey).font(caption).secondary }; Spacer(); if s == current { Image(systemName: "checkmark") } } }.accessibilityIdentifier("status_" + s.rawValue) } } } } .navigationTitle("detail.status.title") }` with identifier `status_picker` on the List; phases from `ProjectStatus.allCases` grouped by `.phase` in order preStart, inWork, workDone, terminal; phase keys `status.phase.<name>`.

`ProgressSheet(initial: Int?, onSave: (Int?) -> Void, onCancel: () -> Void)`: `@State var value: Int` (initial ?? 0); `Slider(value: Binding(get: { Double(value) }, set: { value = Int(($0 / 5).rounded()) * 5 }), in: 0...100, step: 5)` identifier `progress_slider`; `Stepper("progress.manual", value: $value, in: 0...100, step: 5)`; `Text(verbatim: "\(value)%")` identifier `progress_value`; toolbar Save (`progress_save`) → `onSave(value)`, Cancel; `if initial != nil { Button("progress.clear", role: .destructive) { onSave(nil) }.accessibilityIdentifier("progress_clear") }`. (`Double` is allowed in Features; the stored value stays `Int`.)

`CustomerPickerSheet(customerRepository:companyId:current:onPick:)`: `@State customers`, `@State query`; `.task` observes `customerRepository.observeAll(companyId:)`; filter with `SearchFold.normalize` on name/phone/email/companyName; `List` rows `Button { onPick(c.id) }` identifier `customer_pick_<uuid>` and a check on `current`; search field identifier `customer_picker_search`; title `customer.picker.title`.

- [ ] **Step 3: Push, CI build green, commit**

```bash
git add Packages/Features/Sources/ProjectsFeature/Detail Packages/Data
git commit -m "feat(projects): detail view model insights, status/progress/customer/delete actions and sheets"
git push origin HEAD
```

---

### Task 11: Detail view — financials, health, timeline, schedule badges, activity, menu

**Files:**
- Modify: `Packages/Features/Sources/ProjectsFeature/Detail/ProjectDetailView.swift`
- Create: `Packages/Features/Sources/ProjectsFeature/Detail/FinancialSummarySection.swift`, `HealthSection.swift`, `TimelineSection.swift`, `ActivitySection.swift`, `ActivityListView.swift`
- Modify: `Packages/Features/Sources/ProjectsFeature/List/ProjectsListView.swift` (route `.activity` destination), `App/Screens.swift` (`ProjectDetailScreen` passes new deps; `ActivityScreen`)

**Interfaces:**
- Consumes: Task 10 VM API; Task 7/8 components; `ActivityLogRepository.list`.
- Produces: `ProjectDetailView(viewModel:makeCustomer:makeActivity:)`, `ActivityListView(viewModel: ActivityListViewModel)`, `ActivityListViewModel(projectId:activityLogRepository:)`.

- [ ] **Step 1: Header + sections**

In `content(_:)` (header card): after `StatusBadge`, add `if let h = viewModel.insights?.health { HealthChip(h.status.titleKey, tone: h.status.tone).accessibilityIdentifier("detail_health") }`; make the status badge a `Button { showStatusPicker = true }` with identifier `detail_status`. Replace the storage-string date line with `DateLabel`s. Replace the `ProgressBar` block with:

```swift
Button { showProgress = true } label: {
    VStack(alignment: .leading, spacing: DSSpacing.xs) {
        HStack { Text("progress.title").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary); Spacer(); Text(verbatim: "\(viewModel.insights?.progress ?? 0)%").font(DSTypography.money(.caption)) }
        ProgressBar(progress: viewModel.insights?.progress ?? 0, tone: s.project.status.tone)
    }
}.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityIdentifier("detail_progress")
```

Insert after the header: `FinancialSummarySection(insights:currency:onEditEstimate:)` (replaces `estimateSection` — keep the three Edit buttons with their 2a identifiers `detail_edit_estimate_*` and `detail_estimate_total`), `HealthSection(insights:currency:)`, `TimelineSection(insights:project:onAdd: { edit(.timeline) })` (replaces the 2a timeline section's body but keeps `detail_edit_timeline`), then scope, priceDeposit, schedule (rows now use `viewModel.insights?.payments` for status + "paid X · Y left" when `paid > 0`; identifier `detail_schedule`), customer card with "Đổi khách" button (`detail_change_customer`), `ActivitySection(entries: viewModel.activity, currency:, onAll: { path/NavigationLink to ProjectRoute.activity(projectId) })` identifier `detail_activity`, rows `activity_row_<index>`.

`FinancialSummarySection` layout (identifier `detail_financials`):

```
Financial summary
Contract                          38,000.00
Estimated cost  [edit rows ⌄]     14,800.00   ← expandable: labour/material/other rows with Edit buttons (2a)
Projected profit                  23,200.00 (61.1%)
Spent so far  [⌄]                 10,685.00   ← expandable: 6 cost groups estimate / actual / badge      (detail_spent)
Collected                          7,600.00                                                            (detail_collected)
Outstanding                       30,400.00
Cash position                     -3,085.00  (danger when negative)                                     (detail_cash)
Projected at current spending     27,315.00 (71.9%)   ← label per profitLabel
[detail.financials.empty caption when expenses+labour+payments all empty]
[detail.financials.currencyMismatch warning when financials == nil → every value "—"]
```

Per-group row: `Text(costGroup.<raw>)`, estimate (or "—" when `estimateByGroup[g] == nil`), actual, and `StatusBadge("budget.nearLimit"/"budget.exceeded", tone:)` when a `BudgetAlert` exists for the group. Expand state is `@State`, default collapsed; the Edit buttons for labour/material/other live in the expanded estimate rows.

`HealthSection` (`detail_health_reasons`): nil health → `Text("health.notEvaluated")`; onTrack → `Label("health.status.onTrack", systemImage: "checkmark.circle")` success; else `HealthChip` + `ForEach(reasons)` `Label { reason.text(currency:locale:) } icon: { Image(systemName: "exclamationmark.circle") }`.

`TimelineSection` (`detail_timeline`): rows Start / Est. completion with `DateLabel` (or "—"); then `if let r = tl.daysRemaining { Text(r > 0 ? "detail.timeline.daysLeft \(r)" : r == 0 ? "detail.timeline.endsToday" : "detail.timeline.daysLate \(-r)") }` (add key `detail.timeline.endsToday`); `if tl.startDate == today { Text("detail.timeline.startsToday") }`; `DualProgressBar(expected: tl.expectedProgress, actual: insights.progress, expectedLabel: "detail.timeline.expected", actualLabel: "detail.timeline.actual")`; when both dates nil → `SecondaryButton("detail.timeline.add", action: onAdd).accessibilityIdentifier("detail_add_timeline")`. Working days/hours/workers rows as in 2a.

Menu (toolbar): `Menu { Button("detail.customer.change") { showCustomerPicker = true }.accessibilityIdentifier("detail_change_customer_menu"); Button("detail.delete.title", role: .destructive) { confirmDelete = true }.accessibilityIdentifier("detail_delete") } label: { Image(systemName: "ellipsis.circle") }.accessibilityIdentifier("detail_menu")`.

Dialogs/sheets:

```swift
.sheet(isPresented: $showStatusPicker) { StatusPickerSheet(current: s.project.status) { status in showStatusPicker = false; Task { await pick(status) } } }
.sheet(isPresented: $showProgress) { ProgressSheet(initial: s.project.manualProgress, onSave: { v in showProgress = false; Task { _ = await viewModel.setProgress(v) } }, onCancel: { showProgress = false }) }
.sheet(isPresented: $showCustomerPicker) { CustomerPickerSheet(customerRepository: viewModel.customerRepository, companyId: viewModel.companyId, current: s.project.customerId) { id in showCustomerPicker = false; Task { _ = await viewModel.changeCustomer(id) } } }
.confirmationDialog("status.confirm.title", isPresented: $confirmStatus, presenting: pendingStatus) { status in Button("status.confirm.confirm", role: .destructive) { Task { await apply(status) } }.accessibilityIdentifier("status_confirm"); Button("sheet.cancel", role: .cancel) {} } message: { _ in Text("status.confirm.message") }
.alert("status.suggestProgress.title", isPresented: $suggestProgress) { Button("status.suggestProgress.yes") { Task { _ = await viewModel.setProgress(100) } }.accessibilityIdentifier("status_progress_yes"); Button("status.suggestProgress.no", role: .cancel) {} }
.confirmationDialog("detail.delete.title", isPresented: $confirmDelete) { Button("detail.delete.confirm", role: .destructive) { Task { if await viewModel.deleteProject() { dismiss() } } }.accessibilityIdentifier("detail_delete_confirm"); Button("sheet.cancel", role: .cancel) {} } message: { Text("detail.delete.message") }
.alert(viewModel.actionErrorKey ?? "error.generic", isPresented: Binding(get: { viewModel.actionErrorKey != nil }, set: { if !$0 { viewModel.actionErrorKey = nil } })) { Button("sheet.ok") {} }
.task { await viewModel.startInsights() }
.task { await viewModel.startActivity() }
.onChange(of: scenePhase) { _, p in if p == .active { viewModel.update(today: TodayProvider.today(timeZone: timeZone)) } }
```

```swift
private func pick(_ status: ProjectStatus) async {
    guard let project = viewModel.snapshot?.project else { return }
    let probe = ProjectStatusChange.apply(project, to: status)
    if probe.requiresConfirmation { pendingStatus = status; confirmStatus = true; return }
    await apply(status)
}
private func apply(_ status: ProjectStatus) async {
    if let outcome = await viewModel.changeStatus(status), outcome.suggestProgress100 { suggestProgress = true }
}
```

`ActivityListView`: `List(viewModel.entries) { e in ActivityRow(systemImage: e.action.systemImage, title: ActivityDescription.detail(for: e).text(currency:locale:), subtitle: Text(verbatim: relative(e.occurredAt))) }` with `RelativeDateTimeFormatter` (locale from environment) for the subtitle; `ActivityListViewModel.load()` calls `activityLogRepository.list(projectId:)`. Empty → `activity.empty`. Identifier `activity_list`.

`ProjectDetailView.init(viewModel:makeCustomer:makeActivity:)`; destinations for `ProjectRoute.activity(id)` call `makeActivity(id)` in `HomeView`, `ProjectsListView`, and `CustomerProfileView` (whichever hosts `navigationDestination(for: ProjectRoute.self)`). `App/Screens.swift`: `ActivityScreen(projectId:ready:)` owns `ActivityListViewModel` in `@State`; `ProjectDetailScreen.init` passes `insightsRepository: ready.insightsRepository, activityLogRepository: ready.activityLogRepository, customerRepository: ready.customerRepository, today: TodayProvider.today(timeZone: .current)`.

- [ ] **Step 2: Localization for any new key introduced here** (`detail.timeline.endsToday`, `budget.nearLimit`, `budget.exceeded`, `status.confirm.confirm`, `detail.delete.confirm`, `error.invalidProgress`, `home.error.message`, `detail.status.title`, `progress.title`), `check_localization` 0 errors.

- [ ] **Step 3: Push, CI green (2a UI tests must still pass — `detail_header`, `detail_estimate_total`, `detail_schedule_total`, `detail_edit_estimate_material` unchanged), commit**

```bash
git add Packages/Features App/Resources App/Screens.swift
git commit -m "feat(projects): detail financial summary, health, timeline, activity and project actions"
git push origin HEAD
```

---

### Task 12: Timeline validation UI + missing-customer banner (carry-overs)

**Files:**
- Modify: `Packages/Features/Sources/ProjectsFeature/Wizard/Steps/TimelineStep.swift`, `Wizard/ProjectWizardViewModel.swift` (canContinue for `.timeline`, assembler error mapping), `Wizard/Steps/CustomerStep.swift`, `Detail/EditSectionSheet.swift` (Save disabled on timeline errors — it already uses `wizard.canContinue`)

- [ ] **Step 1: VM** — `canContinue` `.timeline` case: `TimelineValidator.validate(start: draft.startDate, completion: draft.estimatedCompletionDate, workingDays: draft.workingDays, hoursPerDay: draft.hoursPerDay, workersPerDay: draft.workersPerDay).isEmpty`; expose `public var timelineErrors: [TimelineError]` computed the same way. Where the VM catches `DraftError` from the assembler on Create: `case .invalidTimeline: step = WizardStep.timeline.rawValue; errorKey = nil` (errors are shown inline), other cases unchanged. `.customer` case: `canContinue` is false when `draft.customer == .existing(id)` and `id` is not in the step's loaded customers — the step owns the list, so add `public var missingCustomer = false` set by `CustomerStep.observe()` (after loading: `missingCustomer = { if case .existing(let id)? = draft.customer { return !customers.contains { $0.id == id } }; return false }()`), and `canContinue` for `.customer` returns `false` when `missingCustomer`.

- [ ] **Step 2: TimelineStep** — replace the single `completionBeforeStart` text with, under the dates card: `ForEach(viewModel.timelineErrors.filter { $0 == .completionBeforeStart }, id: \.self) { e in errorText(e) }` and under the numbers card the other three; `errorText(e)` = `Text(LocalizedStringKey("timeline.error." + name(e))).font(caption).foregroundStyle(DSColor.danger).accessibilityIdentifier("timeline_error_" + name(e))` with `name(.completionBeforeStart) = "completionBeforeStart"` etc. Give the numeric fields identifiers `wizard_working_days`, `wizard_hours_per_day`, `wizard_workers_per_day`. Remove the now-unused key `wizard.error.completionBeforeStart` from the catalog if nothing else uses it.

- [ ] **Step 3: CustomerStep** — when `viewModel.missingCustomer`: show `Label("wizard.customer.missing", systemImage: "exclamationmark.triangle").foregroundStyle(DSColor.danger).accessibilityIdentifier("wizard_customer_missing")` above the list.

- [ ] **Step 4: Push, CI green, commit**

```bash
git add Packages/Features App/Resources
git commit -m "feat(projects): inline timeline validation and missing-customer guard in the wizard"
git push origin HEAD
```

---

### Task 13: App — `--today`, scene-phase today, final wiring

**Files:**
- Modify: `App/LaunchOptions.swift`, `App/AppContainer.swift`, `App/Screens.swift`, `App/RootView.swift` (or wherever `scenePhase` is observed)

- [ ] **Step 1: `LaunchOptions`** — add `var todayOverride: String?`, parse `case "--today": options.todayOverride = iterator.next()`.

- [ ] **Step 2: `AppContainer.init`** — `if options.isUITesting, let s = options.todayOverride, let d = CalendarDate(storage: s) { TodayProvider.override = d }`. `load()`: `SampleData.seedIfEmpty(database, clock: clock, today: TodayProvider.today(timeZone: .current))`; `Ready` has `insightsRepository`, `activityLogRepository` (from Task 9).

- [ ] **Step 3: Screens** — verify every screen passes `TodayProvider.today(timeZone: .current)`; `HomeView` and `ProjectDetailView` already react to `scenePhase`.

- [ ] **Step 4: Push, CI green, commit**

```bash
git add App
git commit -m "feat(app): --today launch override and 2b repository wiring"
git push origin HEAD
```

---

### Task 14: UI tests (a)–(h) + screenshots

**Files:**
- Create: `UITests/DashboardFlowTests.swift`
- Modify: `UITests/ScreenshotTests.swift`
- Modify (spec errata): `docs/superpowers/specs/2026-10-03-dashboard-detail-design.md` — append to Errata: "§10 (g) exercises `hoursPerDay` out of range instead of completion < start (compact DatePicker is not scriptable in XCUITest); `completionBeforeStart` is covered by Domain tests."

**Interfaces:** identifiers from Tasks 9–12; launch args `--ui-testing --seed-sample-data --locale en --today 2026-10-03`.

- [ ] **Step 1: Tests**

```swift
import XCTest

final class DashboardFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(locale: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", locale, "--today", "2026-10-03"] + extra
        app.launch(); return app
    }
    private func tapTab(_ app: XCUIApplication, _ label: String) { app.tabBars.buttons[label].tap() }
    private func label(_ app: XCUIApplication, _ id: String) -> String { let e = app.descendants(matching: .any)[id]; XCTAssertTrue(e.waitForExistence(timeout: 5), id); return e.label }
    private func openProject(_ app: XCUIApplication, _ address: String) {
        tapTab(app, "Projects")
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", address)).firstMatch.tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 5))
    }

    /// (a) Home answers the dashboard questions with the seed numbers.
    func testHomeShowsAttentionAndTotals() {
        let app = launch()
        XCTAssertTrue(app.otherElements["home_attention"].waitForExistence(timeout: 10))
        let attention = app.otherElements["home_attention"].label + app.otherElements["home_attention"].descendants(matching: .any).allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(attention.contains("Payment risk"), attention)
        XCTAssertTrue(attention.contains("overdue 5 days"), attention)
        XCTAssertTrue(attention.contains("Starts today"), attention)
        XCTAssertTrue(label(app, "home_total_outstanding").contains("55,400.00"))
        XCTAssertTrue(label(app, "home_total_cash").contains("15,415.00"))
        XCTAssertTrue(label(app, "home_total_active").contains("1"))
    }

    /// (b) Basement detail: cash position, health, timeline.
    func testBasementDetailInsights() {
        let app = launch()
        openProject(app, "123 Main Street")
        let cash = label(app, "detail_cash")
        XCTAssertTrue(cash.contains("3,085.00") && (cash.contains("-") || cash.contains("−")), cash)
        XCTAssertTrue(label(app, "detail_health").contains("Payment risk"))
        XCTAssertTrue(label(app, "detail_timeline").contains("27 days left"))
    }

    /// (c) Status change writes activity and bumps Home active jobs.
    func testChangeStatusFromDetail() {
        let app = launch()
        openProject(app, "45 Oak Avenue")
        app.buttons["detail_status"].tap()
        XCTAssertTrue(app.buttons["status_inProgress"].waitForExistence(timeout: 3)); app.buttons["status_inProgress"].tap()
        XCTAssertTrue(app.buttons["detail_status"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "In progress")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Awaiting deposit → In progress")).firstMatch.waitForExistence(timeout: 5))
        tapTab(app, "Home")
        XCTAssertTrue(label(app, "home_total_active").contains("2"))
    }

    /// (d) Manual progress via the sheet.
    func testSetProgress() {
        let app = launch()
        openProject(app, "45 Oak Avenue")
        app.descendants(matching: .any)["detail_progress"].tap()
        let slider = app.sliders["progress_slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        slider.adjust(toNormalizedSliderPosition: 0.6)
        let shown = app.staticTexts["progress_value"].label
        app.buttons["progress_save"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", shown)).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "— → " + shown)).firstMatch.waitForExistence(timeout: 5))
    }

    /// (e) Delete project returns to the list and updates Home collected.
    func testDeleteProject() {
        let app = launch()
        openProject(app, "9 Birch Court")
        app.buttons["detail_menu"].tap()
        XCTAssertTrue(app.buttons["detail_delete"].waitForExistence(timeout: 3)); app.buttons["detail_delete"].tap()
        XCTAssertTrue(app.buttons["detail_delete_confirm"].waitForExistence(timeout: 3)); app.buttons["detail_delete_confirm"].tap()
        XCTAssertTrue(app.buttons["projects_add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Roof Replacement")).firstMatch.exists)
        tapTab(app, "Home")
        XCTAssertTrue(label(app, "home_total_collected").contains("7,600.00"))
    }

    /// (f) Change customer.
    func testChangeCustomer() {
        let app = launch()
        openProject(app, "45 Oak Avenue")
        app.buttons["detail_change_customer"].tap()
        let search = app.textFields["customer_picker_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3)); search.tap(); search.typeText("Maria")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "customer_pick_")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Maria Santos")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "David Nguyen → Maria Santos")).firstMatch.waitForExistence(timeout: 5))
    }

    /// (g) Timeline validation blocks Continue.
    func testTimelineValidationBlocksContinue() {
        let app = launch()
        tapTab(app, "Projects"); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_kitchen"].tap(); app.buttons["wizard_continue"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "Ann Lee")).firstMatch.tap(); app.buttons["wizard_continue"].tap()
        app.textFields["wizard_address_line"].tap(); app.textFields["wizard_address_line"].typeText("1 Test"); app.buttons["wizard_continue"].tap()
        app.buttons["wizard_skip"].tap()                                            // scope → timeline
        let hours = app.textFields["wizard_hours_per_day"]
        XCTAssertTrue(hours.waitForExistence(timeout: 3)); hours.tap(); hours.typeText("30")
        XCTAssertTrue(app.staticTexts["timeline_error_hoursPerDayOutOfRange"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["wizard_continue"].isEnabled)
        hours.tap(); hours.press(forDuration: 1.0); app.menuItems["Select All"].tap(); hours.typeText("8")
        XCTAssertTrue(app.buttons["wizard_continue"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["wizard_continue"].isEnabled)
    }

    /// (h) Vietnamese locale dates and timeline wording.
    func testVietnameseDatesAndTimeline() {
        let app = launch(locale: "vi", extra: ["-AppleLocale", "vi_VN"])
        XCTAssertTrue(app.descendants(matching: .any)["home_date"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["home_date"].label.lowercased().contains("3 tháng 10"), app.descendants(matching: .any)["home_date"].label)
        app.tabBars.buttons["Dự án"].tap()
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "123 Main Street")).firstMatch.tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 5))
        XCTAssertTrue(label(app, "detail_timeline").contains("Còn 27 ngày"))
    }
}
```

Containers that tests read via `.label` (`detail_cash`, `detail_health`, `detail_timeline`, `home_total_*`) must be `.accessibilityElement(children: .combine)`; containers that tests search inside (`home_attention`) must be `.contain`. If the "Select All" menu is unreliable, clear the field with `hours.buttons["Clear text"]` (add `.textFieldStyle` with clear button) or type `XCUIKeyboardKey.delete` twice.

- [ ] **Step 2: Screenshots** — in `ScreenshotTests.testCaptureAllScreens`, launch with `--today 2026-10-03` added; after the tab loop capture (both appearances) `home_<locale>_<appearance>` (Home is tab 0, already captured as a tab shot — rename/ensure the existing capture name is `home_…`); in the light pass add: open Basement detail → scroll to bottom (`app.swipeUp()` ×2) → `detail_full_<locale>`; tap `detail_status` → `status_picker_<locale>` → dismiss; tap `detail_activity_all` → `activity_<locale>` → back.

- [ ] **Step 3: Push, CI, fix to green; download artifact; append spec errata; commit**

```bash
git add UITests docs/superpowers/specs/2026-10-03-dashboard-detail-design.md
git commit -m "test(dashboard): add dashboard/detail UI flows and screenshots"
git push origin HEAD
```

---

## Thứ tự và phụ thuộc

- Task 1–3 (Domain) tuần tự, verify local (`swift test --package-path Packages/Domain`).
- Task 4–6 (Data) sau 3; mỗi task push + CI.
- Task 7 (DesignSystem) độc lập với 4–6, sau 3 là đủ.
- Task 8 sau 7; Task 9 sau 8 (và 4 cho `Ready` wiring); Task 10–11 sau 9; Task 12 sau 3 (độc lập với 9–11 nhưng chạy sau để tránh xung đột file VM); Task 13 sau 11–12; Task 14 cuối.
- Sau Task 14: final review, merge `main`, `testflight` lane `beta`.

## Deferred ghi nhận (không làm trong 2b)

Drag-reorder schedule; `categoryInUse`; Percentage Codable; deposit row bị xóa / template đè schedule đã sửa; màn hoạt động toàn công ty; undo xóa; `Task.detached` cho composer nếu > 200 project.
