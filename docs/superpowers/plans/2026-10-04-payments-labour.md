# Sub-project 3b — Payments + Labour/crew — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Contractors record customer payments in two taps (from a payment-schedule row, a "Record payment" button in project detail, or the Home overdue/due-today row), with the amount pre-filled to what is left on the stage, unlinked payments and overpayments allowed, edit/delete with activity; manage a crew (More → Crew) with daily rates; log labour for several people at once (one entry per person, rate snapshot, one transaction), edit/delete entries. Collected/outstanding/cash, labour actual, budget alerts and health update live through the existing 2b insights stream.

**Architecture:** Pure Domain models (`PaymentDraft`, `PaymentFormContext`, `ProjectPaymentListComposer`, `EmployeeDraft`, `CrewList`, `LabourDraft`, `LabourListComposer`, payment/labour `ActivityDetail`) are fed by three new repositories — `GRDBPaymentRepository`, `GRDBEmployeeRepository`, `GRDBLabourRepository` — whose writes and `activity_log` rows share one transaction. The payment form reads its project through the existing `InsightsRepository.observeProject(id:)`; the detail's Payments card is computed from the detail VM's existing insights snapshot; the Labour card has its own `observeProject` stream (it needs employee names, deleted ones included). Features render only: `PaymentsFeature` (form), `CrewFeature` (crew list/form, labour form, Labour card and list). The App wires them through `Screens.swift`.

**Tech Stack:** Swift 6 toolchain / Swift 5 mode, iOS 17+, SwiftUI + Observation, GRDB 7, XCTest/XCUITest, XcodeGen, GitHub Actions (macos-15 verifies Data/Features/App; Domain tests run on Linux and locally on Windows).

**Spec:** `docs/superpowers/specs/2026-10-04-payments-labour-design.md` (binding). Foundation rules: `docs/superpowers/specs/2026-10-02-foundation-design.md` §5.3–5.5, Phụ lục A.2–A.3.

## Global Constraints

- Domain imports Foundation only; Features never imports Data; DesignSystem never imports Domain. `scripts/lint_sources.py` must pass (no `Double`/`Float`/`CGFloat` in Domain/Data; no `try!`/`as!`/`fatalError` in production).
- Money is `Money` (Decimal, 2 dp, `Money.rounded` half-away-from-zero). Labour cost is ONE rounding per entry (`LabourEntry.cost` = `rounded(days × dailyRate)`); totals are sums of rounded entry costs. Domain never calls `Date()`; `today: CalendarDate` and `now: Date` are passed in.
- Soft-deleted rows never take part in any calculation or list (`deleted_at IS NULL` in every query; composers also filter `isDeleted`) — except employee **names** for labour history, which read deleted employees too.
- Every payment and labour write (create, update, delete) and its `activity_log` row happen in one transaction; an update that changes nothing writes nothing. A multi-person labour log is one transaction: all entries or none.
- No schema migration: the Migration001 tables are used as they are.
- Every new protocol requirement lands in the same commit as its GRDB implementation (every pushed commit compiles).
- All user-visible strings are keys in `App/Resources/Localizable.xcstrings` with `en` + `vi`; user data is rendered with `Text(verbatim:)`. Trade terms stay English in vi (Labour, crew, e-Transfer, Cheque, Deposit, receipt). `python scripts/check_localization.py` must report 0 errors.
- Every VM is `@Observable @MainActor`, owned by an `@State` wrapper in `App/Screens.swift`, never constructed in `body`.
- Accessibility identifiers exactly as listed in spec §5 and the UI-test task.
- The 2b/3a seed numbers do not change; `UITests/DashboardFlowTests.swift` and `UITests/ExpensesFlowTests.swift` keep every expected number (only a scroll limit may be raised if the longer detail page needs it — record it in Errata).
- Commits: `type(scope): summary`, English, **no trailers** (no Co-Authored-By).
- CI: `ios.yml` is the verifier for Data/Features/App; Domain is verified locally with `swift test --package-path Packages/Domain`. Known flake: Foundation `testLanguageSwitchUpdatesOpenScreenAndTabsImmediately` / screenshot launch timeout → rerun failed jobs once.

## Review Focus

1. A multi-person labour log is atomic: when one selected person was removed from the crew meanwhile, **no** entry and **no** activity row may be written. (Task 5 `testBatchWithDeletedEmployeeWritesNothing`.)
2. History never re-prices: changing an employee's daily rate after logging keeps the entry's snapshot rate and the project's labour actual; removing the employee keeps the entry, its cost and its name. (Task 5 `testEmployeeRateChangeKeepsEntrySnapshot`, `testDeletedEmployeeKeepsHistory`; Task 2 `testSameDaySortedByNameAndDeletedHandling`.)
3. Payment allocation follows Foundation §5.4: a payment to a soft-deleted stage or another project's stage is refused; an overpayment is accepted, marks the stage paid and never spills into the next stage. (Task 4 `testRefusesDeletedOrForeignItemAndWritesNothing`, `testOverpaymentAndUnlinkedPayment`; Task 1 `testOverpaymentMarksItemPaidWithoutSpill`.)
4. Editing a payment excludes itself from "paid"/"remaining" — otherwise re-saving an unchanged deposit reports an overpayment and the wrong stage becomes the default. (Task 1 `testEditingExcludesOwnPayment`.)
5. Rounding: one rounding per labour entry, totals are sums of rounded costs — 0.5 × 333.33 = 166.67 and Mike 1 × 250 + John 0.5 × 333.33 = 416.67 in the single `labourLogged` row. (Task 2 `testHalfDayRounding`, Task 5 `testCreateBatchWritesOneActivity`.)

---

### Task 1: Domain — payment draft, form context, payment list, attention item id

**Files:**
- Create: `Packages/Domain/Sources/Domain/Payments/PaymentDraft.swift`
- Create: `Packages/Domain/Sources/Domain/Payments/PaymentFormContext.swift`
- Create: `Packages/Domain/Sources/Domain/Payments/PaymentList.swift`
- Modify: `Packages/Domain/Sources/Domain/DomainError.swift` (add `incompletePayment`, `incompleteLabour`)
- Modify: `Packages/Domain/Sources/Domain/Insights/Dashboard.swift` (`AttentionItem.scheduleItemId`)
- Create: `Packages/Domain/Tests/DomainTests/Payments/PaymentFixtures.swift`
- Create: `Packages/Domain/Tests/DomainTests/Payments/PaymentDraftTests.swift`
- Create: `Packages/Domain/Tests/DomainTests/Payments/PaymentFormContextTests.swift`
- Create: `Packages/Domain/Tests/DomainTests/Payments/PaymentListTests.swift`
- Modify: `Packages/Domain/Tests/DomainTests/Insights/DashboardComposerTests.swift`

**Interfaces:**
- Consumes: `Payment`, `PaymentScheduleItem`, `Project`, `PaymentAllocation`, `PaymentStatusResolver`, `ProjectInsightsComposer`; fixtures `Fx` (`Tests/DomainTests/Insights/InsightsFixtures.swift`: `Fx.now`, `Fx.today` = 2026-10-03, `Fx.companyId`, `Fx.money`, `Fx.moneyS`, `Fx.Basement` — deposit 7,600 paid by `payments[0]`, stage 2 due −5, stage 3 due +10, final no due).
- Produces: `PaymentDraftError` (`CaseIterable`), `PaymentDraft` (`methodOrder`, `defaultMethod(lastUsed:)`, `init(paidOn:method:scheduleItemId:amount:)`, `init(editing:)`, `errors`, `canSave`, `makePayment(id:companyId:projectId:currency:now:)`, `apply(to:now:)`); `PaymentItemOption`; `PaymentSuggestion` (`.money`); `PaymentFormContext.options/defaultItemId/outstanding/suggestions/overpayment`; `PaymentRow`, `ProjectPaymentList`, `ProjectPaymentListComposer.compose(payments:scheduleItems:currency:)`; `AttentionItem.scheduleItemId`; `DomainError.incompletePayment`, `.incompleteLabour`; fixture `Pay.payment(...)`. Tasks 3, 8, 12 use these names.

- [ ] **Step 1: Fixtures**

```swift
// Packages/Domain/Tests/DomainTests/Payments/PaymentFixtures.swift
import Foundation
@testable import Domain

enum Pay {
    static func payment(_ project: Project, _ amount: String, item: UUID?, on day: String = "2026-10-03", method: PaymentMethod = .eTransfer,
                        createdAt: Date = Fx.now, deletedAt: Date? = nil) -> Payment {
        Payment(id: UUID(), companyId: Fx.companyId, projectId: project.id, scheduleItemId: item, amount: Fx.moneyS(amount),
                paidOn: CalendarDate(storage: day)!, method: method, notes: nil, createdAt: createdAt, updatedAt: createdAt, deletedAt: deletedAt)
    }
}
```

- [ ] **Step 2: Failing tests**

```swift
// Packages/Domain/Tests/DomainTests/Payments/PaymentDraftTests.swift
import XCTest
@testable import Domain

final class PaymentDraftTests: XCTestCase {
    func testErrors() {
        var d = PaymentDraft(paidOn: Fx.today, method: .eTransfer)
        XCTAssertEqual(d.errors, [.amountMissing])
        d.amount = 0
        XCTAssertEqual(d.errors, [.amountNotPositive])
        d.amount = Decimal(string: "0.004")
        XCTAssertEqual(d.errors, [.amountNotPositive])
        d.amount = -5
        XCTAssertEqual(d.errors, [.amountNotPositive])
        d.amount = Decimal(string: "0.005")
        XCTAssertEqual(d.errors, [])                                  // rounds to 0.01
        XCTAssertTrue(d.canSave)
    }

    func testMakePaymentRoundsOnceAndTrimsNotes() throws {
        let b = Fx.Basement()
        var d = PaymentDraft(paidOn: Fx.today, method: .cheque, scheduleItemId: b.items[1].id, amount: Decimal(string: "11400.005"))
        d.notes = "  cheque #204  "
        let p = try d.makePayment(id: UUID(), companyId: Fx.companyId, projectId: b.project.id, currency: .cad, now: Fx.now)
        XCTAssertEqual(p.amount.storageString, "11400.01")
        XCTAssertEqual(p.notes, "cheque #204")
        XCTAssertEqual(p.method, .cheque)
        XCTAssertEqual(p.scheduleItemId, b.items[1].id)
        XCTAssertEqual(p.projectId, b.project.id)
        XCTAssertEqual(p.createdAt, Fx.now)
        XCTAssertNoThrow(try p.validate())
    }

    func testIncompleteThrows() {
        XCTAssertThrowsError(try PaymentDraft(paidOn: Fx.today, method: .cash).makePayment(id: UUID(), companyId: Fx.companyId, projectId: UUID(), currency: .cad, now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .incompletePayment)
        }
    }

    func testApplyKeepsIdentityAndUnlinks() throws {
        let b = Fx.Basement()
        let original = b.payments[0]
        var d = PaymentDraft(editing: original)
        XCTAssertEqual(d.amount, 7600)
        XCTAssertEqual(d.scheduleItemId, b.items[0].id)
        XCTAssertEqual(d.notes, "")
        d.scheduleItemId = nil
        d.amount = 7000
        d.notes = "   "
        let later = Fx.now.addingTimeInterval(60)
        let u = try d.apply(to: original, now: later)
        XCTAssertEqual(u.id, original.id)
        XCTAssertEqual(u.projectId, original.projectId)
        XCTAssertEqual(u.createdAt, original.createdAt)
        XCTAssertEqual(u.updatedAt, later)
        XCTAssertNil(u.scheduleItemId)
        XCTAssertEqual(u.amount, Fx.money(7000))
        XCTAssertNil(u.notes)
    }

    func testDefaultMethodAndOrder() {
        XCTAssertEqual(PaymentDraft.defaultMethod(lastUsed: nil), .eTransfer)
        XCTAssertEqual(PaymentDraft.defaultMethod(lastUsed: .cheque), .cheque)
        XCTAssertEqual(PaymentDraft.methodOrder.first, .eTransfer)
        XCTAssertEqual(PaymentDraft.methodOrder.count, PaymentMethod.allCases.count)
        XCTAssertEqual(Set(PaymentDraft.methodOrder), Set(PaymentMethod.allCases))
    }
}
```

```swift
// Packages/Domain/Tests/DomainTests/Payments/PaymentFormContextTests.swift
import XCTest
@testable import Domain

final class PaymentFormContextTests: XCTestCase {
    private func options(_ b: Fx.Basement, _ payments: [Payment], excluding: UUID? = nil, items: [PaymentScheduleItem]? = nil) -> [PaymentItemOption] {
        PaymentFormContext.options(items: items ?? b.items, payments: payments, excluding: excluding, today: Fx.today, currency: .cad)
    }

    func testBasementOptions() {
        let b = Fx.Basement()
        let o = options(b, b.payments)
        XCTAssertEqual(o.map(\.status), [.paid, .overdue, .upcoming, .upcoming])
        XCTAssertEqual(o.map(\.remaining.storageString), ["0.00", "11400.00", "11400.00", "7600.00"])
        XCTAssertEqual(o[0].paid, Fx.money(7600))
        XCTAssertEqual(PaymentFormContext.defaultItemId(o), b.items[1].id)
    }

    func testEditingExcludesOwnPayment() {
        let b = Fx.Basement()
        let o = options(b, b.payments, excluding: b.payments[0].id)
        XCTAssertEqual(o[0].paid, Fx.money(0))
        XCTAssertEqual(o[0].remaining, Fx.money(7600))
        XCTAssertEqual(o[0].status, .overdue)                                    // due −20
        XCTAssertEqual(PaymentFormContext.defaultItemId(o), b.items[0].id)
        XCTAssertNil(PaymentFormContext.overpayment(amount: 7600, option: o[0]))  // re-saving 7,600 is not an overpayment
        XCTAssertEqual(PaymentFormContext.outstanding(project: b.project, payments: b.payments, excluding: b.payments[0].id), Fx.money(38_000))
        XCTAssertEqual(PaymentFormContext.outstanding(project: b.project, payments: b.payments, excluding: nil), Fx.money(30_400))
    }

    func testSuggestions() {
        let b = Fx.Basement()
        let o = options(b, b.payments + [Pay.payment(b.project, "5000.00", item: b.items[1].id)])
        XCTAssertEqual(o[1].status, .overdue)                                    // part-paid but past due: overdue wins (Foundation §5.4 row 2)
        XCTAssertEqual(PaymentFormContext.suggestions(option: o[1], outstanding: nil), [.remaining(Fx.money(6400)), .fullItem(Fx.money(11_400))])
        XCTAssertEqual(PaymentFormContext.suggestions(option: o[2], outstanding: nil), [.remaining(Fx.money(11_400))])
        XCTAssertEqual(PaymentFormContext.suggestions(option: o[0], outstanding: Fx.money(1)), [])
        XCTAssertEqual(PaymentFormContext.suggestions(option: nil, outstanding: Fx.money(30_400)), [.outstanding(Fx.money(30_400))])
        XCTAssertEqual(PaymentFormContext.suggestions(option: nil, outstanding: Fx.money(0)), [])
        XCTAssertEqual(PaymentFormContext.suggestions(option: nil, outstanding: nil), [])
        XCTAssertEqual(PaymentSuggestion.fullItem(Fx.money(3)).money, Fx.money(3))
    }

    func testOverpaymentMarksItemPaidWithoutSpill() {
        let b = Fx.Basement()
        let o = options(b, b.payments)
        XCTAssertEqual(PaymentFormContext.overpayment(amount: 12_000, option: o[1]), Fx.money(600))
        XCTAssertNil(PaymentFormContext.overpayment(amount: 11_400, option: o[1]))
        XCTAssertNil(PaymentFormContext.overpayment(amount: 12_000, option: nil))
        XCTAssertNil(PaymentFormContext.overpayment(amount: nil, option: o[1]))
        let paid = b.payments + [Pay.payment(b.project, "12000.00", item: b.items[1].id)]
        let after = options(b, paid)
        XCTAssertEqual(after.map(\.status), [.paid, .paid, .upcoming, .upcoming])
        XCTAssertEqual(after[2].paid, Fx.money(0))                               // the 600 extra never moves to stage 3
        let insights = ProjectInsightsComposer.compose(ProjectInsightsInputs(project: b.project, estimateLines: b.lines, scheduleItems: b.items, expenses: b.expenses,
                                                                             labourEntries: b.labour, payments: paid, today: Fx.today))
        XCTAssertEqual(insights.financials?.collected, Fx.money(19_600))
        XCTAssertEqual(insights.financials?.outstandingBalance, Fx.money(18_400))
    }

    func testDeletedItemsAndPaymentsIgnored() {
        let b = Fx.Basement()
        var items = b.items
        items[3].deletedAt = Fx.now
        let o = options(b, b.payments + [Pay.payment(b.project, "100.00", item: b.items[1].id, deletedAt: Fx.now)], items: items)
        XCTAssertEqual(o.count, 3)
        XCTAssertEqual(o[1].paid, Fx.money(0))
        XCTAssertEqual(o.map(\.item.sortOrder), [0, 1, 2])
    }
}
```

```swift
// Packages/Domain/Tests/DomainTests/Payments/PaymentListTests.swift
import XCTest
@testable import Domain

final class PaymentListTests: XCTestCase {
    func testRowsNewestFirstWithLabels() {
        let b = Fx.Basement()
        let deposit = Pay.payment(b.project, "7600.00", item: b.items[0].id, on: "2026-09-14")
        let loose = Pay.payment(b.project, "500.00", item: nil, on: "2026-10-02", method: .cash)
        let older = Pay.payment(b.project, "50.00", item: nil, on: "2026-10-02", createdAt: Fx.now.addingTimeInterval(-60))
        let gone = Pay.payment(b.project, "999.00", item: nil, on: "2026-10-03", deletedAt: Fx.now)
        let l = ProjectPaymentListComposer.compose(payments: [deposit, older, loose, gone], scheduleItems: b.items, currency: .cad)
        XCTAssertEqual(l.rows.map(\.payment.amount.storageString), ["500.00", "50.00", "7600.00"])
        XCTAssertEqual(l.rows.map(\.itemLabel), [nil, nil, "schedule.row.deposit"])
        XCTAssertEqual(l.collected, Fx.money(8150))
        XCTAssertEqual(l.unallocated, Fx.money(550))
    }

    func testPaymentOnDeletedItemCountsAsNotLinked() {
        let b = Fx.Basement()
        var items = b.items
        items[1].deletedAt = Fx.now
        let l = ProjectPaymentListComposer.compose(payments: [Pay.payment(b.project, "1000.00", item: b.items[1].id)], scheduleItems: items, currency: .cad)
        XCTAssertNil(l.rows[0].itemLabel)
        XCTAssertEqual(l.unallocated, Fx.money(1000))
    }

    func testEmpty() {
        let l = ProjectPaymentListComposer.compose(payments: [], scheduleItems: [], currency: .cad)
        XCTAssertTrue(l.rows.isEmpty)
        XCTAssertEqual(l.collected, Fx.money(0))
        XCTAssertEqual(l.unallocated, Fx.money(0))
    }
}
```

Append to `DashboardComposerTests`:

```swift
    func testAttentionScheduleItemId() {
        let item = UUID(), project = UUID()
        XCTAssertEqual(AttentionItem.paymentOverdue(projectId: project, itemId: item, label: "x", remaining: Fx.money(1), daysLate: 2).scheduleItemId, item)
        XCTAssertEqual(AttentionItem.paymentDueToday(projectId: project, itemId: item, label: "x", remaining: Fx.money(1)).scheduleItemId, item)
        XCTAssertNil(AttentionItem.startsToday(projectId: project).scheduleItemId)
    }
```

- [ ] **Step 3: Run — expect compile failure**

Run: `swift test --package-path Packages/Domain --filter "PaymentDraftTests|PaymentFormContextTests|PaymentListTests|DashboardComposerTests"`

- [ ] **Step 4: Implement**

`DomainError.swift` — append two cases after `incompleteExpense`:

```swift
    case incompletePayment
    case incompleteLabour
```

```swift
// Packages/Domain/Sources/Domain/Payments/PaymentDraft.swift
import Foundation

public enum PaymentDraftError: Hashable, Sendable, CaseIterable {
    case amountMissing, amountNotPositive
}

/// The payment form's state (spec §3.1). Pure: no `Date()`, no persistence. The project is fixed by the entry point.
public struct PaymentDraft: Hashable, Sendable {
    /// Chip order: e-Transfer first (the common Canadian method), then cheque and cash.
    public static let methodOrder: [PaymentMethod] = [.eTransfer, .cheque, .cash, .bankTransfer, .creditCard, .other]

    /// Method of the company's most recently created live payment, else e-Transfer (spec §2 "Cách trả mặc định").
    public static func defaultMethod(lastUsed: PaymentMethod?) -> PaymentMethod { lastUsed ?? .eTransfer }

    public var amount: Decimal?
    public var paidOn: CalendarDate
    public var method: PaymentMethod
    public var scheduleItemId: UUID?
    public var notes: String

    public init(paidOn: CalendarDate, method: PaymentMethod, scheduleItemId: UUID? = nil, amount: Decimal? = nil) {
        self.amount = amount; self.paidOn = paidOn; self.method = method; self.scheduleItemId = scheduleItemId; self.notes = ""
    }

    public init(editing payment: Payment) {
        amount = payment.amount.amount
        paidOn = payment.paidOn
        method = payment.method
        scheduleItemId = payment.scheduleItemId
        notes = payment.notes ?? ""
    }

    public var errors: [PaymentDraftError] {
        guard let amount else { return [.amountMissing] }
        return Money.rounded(amount) <= 0 ? [.amountNotPositive] : []
    }

    public var canSave: Bool { errors.isEmpty }

    public func makePayment(id: UUID, companyId: UUID, projectId: UUID, currency: CurrencyCode, now: Date) throws -> Payment {
        let money = try resolvedAmount(currency: currency)
        return Payment(id: id, companyId: companyId, projectId: projectId, scheduleItemId: scheduleItemId, amount: money, paidOn: paidOn,
                       method: method, notes: Self.clean(notes), createdAt: now, updatedAt: now, deletedAt: nil)
    }

    /// Edit: keeps identity, project and creation time.
    public func apply(to existing: Payment, now: Date) throws -> Payment {
        let money = try resolvedAmount(currency: existing.amount.currency)
        return Payment(id: existing.id, companyId: existing.companyId, projectId: existing.projectId, scheduleItemId: scheduleItemId, amount: money,
                       paidOn: paidOn, method: method, notes: Self.clean(notes), createdAt: existing.createdAt, updatedAt: now, deletedAt: existing.deletedAt)
    }

    /// The single rounding point of a typed amount.
    private func resolvedAmount(currency: CurrencyCode) throws -> Money {
        guard errors.isEmpty, let amount else { throw DomainError.incompletePayment }
        return Money(amount, currency)
    }

    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

```swift
// Packages/Domain/Sources/Domain/Payments/PaymentFormContext.swift
import Foundation

/// A schedule item as the payment form shows it: paid by OTHER payments, what is left, its status.
public struct PaymentItemOption: Hashable, Sendable, Identifiable {
    public let item: PaymentScheduleItem
    public let paid: Money
    public let remaining: Money
    public let status: PaymentStatus
    public var id: UUID { item.id }
    public init(item: PaymentScheduleItem, paid: Money, remaining: Money, status: PaymentStatus) {
        self.item = item; self.paid = paid; self.remaining = remaining; self.status = status
    }
}

/// One-tap amounts (spec §2 "Chip số tiền").
public enum PaymentSuggestion: Hashable, Sendable {
    case remaining(Money)
    case fullItem(Money)
    case outstanding(Money)

    public var money: Money {
        switch self {
        case .remaining(let m), .fullItem(let m), .outstanding(let m): return m
        }
    }
}

public enum PaymentFormContext {
    /// Live items by sort order; `paid` counts live payments except `excluding` (the payment being edited).
    public static func options(items: [PaymentScheduleItem], payments: [Payment], excluding paymentId: UUID?, today: CalendarDate, currency: CurrencyCode) -> [PaymentItemOption] {
        let zero = Money.zero(currency)
        let counted = payments.filter { !$0.isDeleted && $0.id != paymentId }
        return items.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }.map { item in
            let paid = (try? PaymentAllocation.paidForItem(item.id, payments: counted, currency: currency)) ?? zero
            let left = (try? item.amount.subtracting(paid)) ?? zero
            return PaymentItemOption(item: item, paid: paid, remaining: left.isNegative ? zero : left,
                                     status: PaymentStatusResolver.status(item: item, paidForItem: paid, today: today))
        }
    }

    /// "Record payment" without a stage: the first stage (in order) that is not fully paid.
    public static func defaultItemId(_ options: [PaymentItemOption]) -> UUID? {
        options.first { $0.status != .paid }?.id
    }

    /// Contract − collected, ignoring `excluding`; nil on a currency mismatch.
    public static func outstanding(project: Project, payments: [Payment], excluding paymentId: UUID?) -> Money? {
        let currency = project.contractValue.currency
        guard let collected = try? PaymentAllocation.collected(payments.filter { $0.id != paymentId }, currency: currency) else { return nil }
        return try? project.contractValue.subtracting(collected)
    }

    public static func suggestions(option: PaymentItemOption?, outstanding: Money?) -> [PaymentSuggestion] {
        guard let option else {
            if let outstanding, outstanding.amount > 0 { return [.outstanding(outstanding)] }
            return []
        }
        guard option.remaining.amount > 0 else { return [] }
        var result: [PaymentSuggestion] = [.remaining(option.remaining)]
        if option.paid.amount > 0 { result.append(.fullItem(option.item.amount)) }
        return result
    }

    /// How much the typed amount exceeds what is left on the stage (accepted, shown as a notice).
    public static func overpayment(amount: Decimal?, option: PaymentItemOption?) -> Money? {
        guard let amount, let option else { return nil }
        guard let extra = try? Money(amount, option.remaining.currency).subtracting(option.remaining), extra.amount > 0 else { return nil }
        return extra
    }
}
```

```swift
// Packages/Domain/Sources/Domain/Payments/PaymentList.swift
import Foundation

public struct PaymentRow: Hashable, Sendable, Identifiable {
    public let payment: Payment
    /// Label of the linked LIVE schedule item (a `schedule.row.*` key or user text); nil = not linked.
    public let itemLabel: String?
    public var id: UUID { payment.id }
    public init(payment: Payment, itemLabel: String?) { self.payment = payment; self.itemLabel = itemLabel }
}

public struct ProjectPaymentList: Hashable, Sendable {
    public let rows: [PaymentRow]
    public let collected: Money
    public let unallocated: Money
    public init(rows: [PaymentRow], collected: Money, unallocated: Money) { self.rows = rows; self.collected = collected; self.unallocated = unallocated }
}

public enum ProjectPaymentListComposer {
    /// Project detail's Payments card: live payments newest first (paid date, then creation); a payment whose stage was deleted
    /// counts as not linked, exactly like `ProjectInsightsComposer`.
    public static func compose(payments: [Payment], scheduleItems: [PaymentScheduleItem], currency: CurrencyCode) -> ProjectPaymentList {
        let zero = Money.zero(currency)
        let labels = Dictionary(scheduleItems.filter { !$0.isDeleted }.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
        let live = payments.filter { !$0.isDeleted }
        let rows = live
            .sorted { ($0.paidOn, $0.createdAt, $0.id.uuidString) > ($1.paidOn, $1.createdAt, $1.id.uuidString) }
            .map { PaymentRow(payment: $0, itemLabel: $0.scheduleItemId.flatMap { labels[$0] }) }
        let collected = (try? Money.sum(live.map(\.amount), currency: currency)) ?? zero
        let unallocated = (try? Money.sum(rows.filter { $0.itemLabel == nil }.map(\.payment.amount), currency: currency)) ?? zero
        return ProjectPaymentList(rows: rows, collected: collected, unallocated: unallocated)
    }
}
```

`Dashboard.swift` — inside `AttentionItem`, after `projectId`:

```swift
    /// The schedule item a payment row is about (Home's "Record" button); nil for other rows.
    public var scheduleItemId: UUID? {
        switch self {
        case .paymentOverdue(_, let item, _, _, _), .paymentDueToday(_, let item, _, _): return item
        case .health, .startsToday: return nil
        }
    }
```

- [ ] **Step 5: Run — all green**

Run: `swift test --package-path Packages/Domain --filter "PaymentDraftTests|PaymentFormContextTests|PaymentListTests|DashboardComposerTests"`, then the whole package `swift test --package-path Packages/Domain` (the 204 existing tests stay green).

- [ ] **Step 6: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add payment draft, payment form context and project payment list"
```

---

### Task 2: Domain — crew draft, labour draft, labour list

**Files:**
- Create: `Packages/Domain/Sources/Domain/Crew/EmployeeDraft.swift` (also holds `CrewList`)
- Create: `Packages/Domain/Sources/Domain/Labour/LabourDraft.swift`
- Create: `Packages/Domain/Sources/Domain/Labour/LabourList.swift`
- Create: `Packages/Domain/Tests/DomainTests/Labour/LabourFixtures.swift`
- Create: `Packages/Domain/Tests/DomainTests/Labour/EmployeeDraftTests.swift`
- Create: `Packages/Domain/Tests/DomainTests/Labour/LabourDraftTests.swift`
- Create: `Packages/Domain/Tests/DomainTests/Labour/LabourListTests.swift`

**Interfaces:**
- Consumes: `Employee`, `LabourEntry` (`cost(days:dailyRate:)`), `Money`, `DomainError` (Task 1 `incompleteLabour`), `Fx`.
- Produces: `EmployeeDraftError`, `EmployeeDraft` (`hoursPerDay`, `init()`, `init(editing:)`, `errors`, `canSave`, `dailyFromHourly`, `makeEmployee(id:companyId:currency:now:)`, `apply(to:currency:now:)`), `CrewList.ordered(_:)`; `LabourDraftError`, `LabourLine`, `LabourDraft` (`dayStep`, `init(workDate:)`, `init(editing:)`, `isSelected`, `toggle`, `setRate`, `stepDays(up:)`, `cost(for:currency:)`, `total(currency:)`, `lineError(for:)`, `errors`, `canSave`, `makeEntries(companyId:projectId:currency:now:makeId:)`, `apply(to:now:)`, `alreadyLoggedDays(employeeId:on:entries:excluding:)`); `LabourRow`, `LabourDaySection`, `ProjectLabourList`, `LabourListComposer.compose(entries:employees:currency:)`; fixtures `Lab.employee`, `Lab.entry`, `Lab.Seed`. Tasks 5, 9–11 use these names.

- [ ] **Step 1: Fixtures**

```swift
// Packages/Domain/Tests/DomainTests/Labour/LabourFixtures.swift
import Foundation
@testable import Domain

enum Lab {
    static func employee(_ name: String, rate: String?, hourly: String? = nil, deleted: Bool = false, createdAt: Date = Fx.now) -> Employee {
        Employee(id: UUID(), companyId: Fx.companyId, name: name, phone: nil, role: nil, trade: nil, hourlyRate: hourly.map { Fx.moneyS($0) },
                 dailyRate: rate.map { Fx.moneyS($0) }, certifications: nil, emergencyContact: nil, notes: nil,
                 createdAt: createdAt, updatedAt: createdAt, deletedAt: deleted ? Fx.now : nil)
    }

    static func entry(_ project: Project, _ employee: Employee, days: String, rate: String, on day: String, createdAt: Date = Fx.now, deletedAt: Date? = nil) -> LabourEntry {
        LabourEntry(id: UUID(), companyId: Fx.companyId, projectId: project.id, employeeId: employee.id, workDate: CalendarDate(storage: day)!,
                    days: Decimal(string: days)!, dailyRate: Fx.moneyS(rate), notes: nil, createdAt: createdAt, updatedAt: createdAt, deletedAt: deletedAt)
    }

    /// Spec §4 seed crew and Basement labour (today = 2026-10-03).
    struct Seed {
        let project = Fx.project("Basement Renovation", customer: Fx.customer("Ann Lee"), status: .inProgress, contract: 38_000, progress: 65, start: -18, end: 27)
        let mike = Lab.employee("Mike", rate: "250.00", hourly: "31.25")
        let john = Lab.employee("John", rate: "220.00")
        let david = Lab.employee("David", rate: "200.00")
        var entries: [LabourEntry] {
            [Lab.entry(project, mike, days: "8", rate: "250.00", on: "2026-09-23"),
             Lab.entry(project, john, days: "10", rate: "220.00", on: "2026-09-24"),
             Lab.entry(project, david, days: "7", rate: "200.00", on: "2026-09-25")]
        }
    }
}
```

`entries` is computed: each access builds new ids, so a test reads it once into a local.

- [ ] **Step 2: Failing tests**

```swift
// Packages/Domain/Tests/DomainTests/Labour/EmployeeDraftTests.swift
import XCTest
@testable import Domain

final class EmployeeDraftTests: XCTestCase {
    func testValidation() {
        var d = EmployeeDraft()
        XCTAssertEqual(d.errors, [.nameMissing])
        d.name = "   "
        XCTAssertEqual(d.errors, [.nameMissing])
        d.name = "Sam"
        d.dailyRate = -1
        XCTAssertEqual(d.errors, [.rateNegative])
        d.dailyRate = nil
        d.hourlyRate = -1
        XCTAssertEqual(d.errors, [.rateNegative])
        d.hourlyRate = nil
        XCTAssertTrue(d.canSave)                                  // the daily rate is optional on the crew form
    }

    func testMakeEmployeeTrimsAndUsesTrade() throws {
        var d = EmployeeDraft()
        d.name = " Sam Patel "
        d.trade = " Electrician "
        d.phone = "  "
        d.dailyRate = 300
        let e = try d.makeEmployee(id: UUID(), companyId: Fx.companyId, currency: .cad, now: Fx.now)
        XCTAssertEqual(e.name, "Sam Patel")
        XCTAssertEqual(e.trade, "Electrician")
        XCTAssertNil(e.role)
        XCTAssertNil(e.phone)
        XCTAssertNil(e.notes)
        XCTAssertEqual(e.dailyRate, Fx.money(300))
        XCTAssertNil(e.hourlyRate)
        XCTAssertEqual(e.createdAt, Fx.now)
        XCTAssertThrowsError(try EmployeeDraft().makeEmployee(id: UUID(), companyId: Fx.companyId, currency: .cad, now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .emptyName)
        }
        var negative = d
        negative.dailyRate = -5
        XCTAssertThrowsError(try negative.makeEmployee(id: UUID(), companyId: Fx.companyId, currency: .cad, now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .negativeAmount)
        }
    }

    func testDailyFromHourly() {
        var d = EmployeeDraft()
        XCTAssertNil(d.dailyFromHourly)
        d.hourlyRate = Decimal(string: "31.25")
        XCTAssertEqual(d.dailyFromHourly, 250)
        d.hourlyRate = Decimal(string: "28.33")
        XCTAssertEqual(d.dailyFromHourly, Decimal(string: "226.64"))
    }

    func testApplyKeepsHiddenFields() throws {
        var mike = Lab.employee("Mike", rate: "250.00")
        mike.role = "Lead"
        mike.certifications = "WHMIS"
        var d = EmployeeDraft(editing: mike)
        XCTAssertEqual(d.name, "Mike")
        XCTAssertEqual(d.dailyRate, 250)
        d.dailyRate = 275
        let later = Fx.now.addingTimeInterval(5)
        let u = try d.apply(to: mike, currency: .cad, now: later)
        XCTAssertEqual(u.id, mike.id)
        XCTAssertEqual(u.role, "Lead")
        XCTAssertEqual(u.certifications, "WHMIS")
        XCTAssertEqual(u.dailyRate, Fx.money(275))
        XCTAssertEqual(u.createdAt, mike.createdAt)
        XCTAssertEqual(u.updatedAt, later)
    }

    func testCrewListOrder() {
        let a = Lab.employee("mike", rate: nil), b = Lab.employee("David", rate: nil)
        let gone = Lab.employee("Adam", rate: nil, deleted: true), c = Lab.employee("Zoe", rate: nil)
        XCTAssertEqual(CrewList.ordered([a, b, gone, c]).map(\.name), ["David", "mike", "Zoe"])
    }
}
```

```swift
// Packages/Domain/Tests/DomainTests/Labour/LabourDraftTests.swift
import XCTest
@testable import Domain

final class LabourDraftTests: XCTestCase {
    func testToggleSnapshotsRateAndRemoves() {
        let s = Lab.Seed()
        var d = LabourDraft(workDate: Fx.today)
        XCTAssertEqual(d.days, 1)
        d.toggle(s.mike)
        d.toggle(s.john)
        XCTAssertEqual(d.lines.map(\.dailyRate), [250, 220])
        XCTAssertTrue(d.isSelected(s.mike.id))
        d.toggle(s.mike)
        XCTAssertEqual(d.lines.map(\.employeeId), [s.john.id])
        XCTAssertFalse(d.isSelected(s.mike.id))
    }

    func testTwoPeopleTotals() {
        let s = Lab.Seed()
        var d = LabourDraft(workDate: Fx.today)
        XCTAssertNil(d.total(currency: .cad))
        d.toggle(s.mike)
        d.toggle(s.john)
        XCTAssertEqual(d.total(currency: .cad), Fx.money(470))
        d.days = Decimal(string: "1.5")
        XCTAssertEqual(d.cost(for: s.mike.id, currency: .cad), Fx.money(375))
        XCTAssertEqual(d.total(currency: .cad), Fx.money(705))
    }

    func testHalfDayRounding() {
        let odd = Lab.employee("Sam", rate: "333.33")
        var d = LabourDraft(workDate: Fx.today)
        d.toggle(odd)
        d.days = Decimal(string: "0.5")
        XCTAssertEqual(d.cost(for: odd.id, currency: .cad), Fx.moneyS("166.67"))   // 166.665 → half away from zero
        d.toggle(Lab.Seed().mike)
        XCTAssertEqual(d.total(currency: .cad), Fx.moneyS("291.67"))               // 166.67 + 125.00, rounded per person
    }

    func testErrorsInOrderAndZeroRate() {
        var d = LabourDraft(workDate: Fx.today)
        d.days = nil
        XCTAssertEqual(d.errors, [.noCrewSelected, .daysMissing])
        let noRate = Lab.employee("Pat", rate: nil)
        d.toggle(noRate)
        d.days = 0
        XCTAssertEqual(d.errors, [.daysNotPositive, .rateMissing])
        XCTAssertEqual(d.lineError(for: noRate.id), .rateMissing)
        XCTAssertNil(d.cost(for: noRate.id, currency: .cad))
        d.setRate(-1, for: noRate.id)
        d.days = 1
        XCTAssertEqual(d.errors, [.rateNegative])
        d.setRate(0, for: noRate.id)
        XCTAssertTrue(d.canSave)                                                     // $0 allowed (an owner's own day)
        XCTAssertEqual(d.total(currency: .cad), Fx.money(0))
    }

    func testStepDays() {
        var d = LabourDraft(workDate: Fx.today)
        d.stepDays(up: true)
        XCTAssertEqual(d.days, Decimal(string: "1.5"))
        d.stepDays(up: false)
        d.stepDays(up: false)
        XCTAssertEqual(d.days, Decimal(string: "0.5"))
        d.stepDays(up: false)
        XCTAssertEqual(d.days, Decimal(string: "0.5"))
        d.days = nil
        d.stepDays(up: true)
        XCTAssertEqual(d.days, Decimal(string: "0.5"))
    }

    func testMakeEntriesOnePerPerson() throws {
        let s = Lab.Seed()
        var d = LabourDraft(workDate: Fx.today)
        d.toggle(s.mike)
        d.toggle(s.john)
        d.notes = "  framing  "
        let entries = try d.makeEntries(companyId: Fx.companyId, projectId: s.project.id, currency: .cad, now: Fx.now)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.id)).count, 2)
        XCTAssertEqual(entries.map(\.employeeId), [s.mike.id, s.john.id])
        XCTAssertEqual(entries.map(\.dailyRate), [Fx.money(250), Fx.money(220)])
        XCTAssertTrue(entries.allSatisfy { $0.workDate == Fx.today && $0.days == 1 && $0.notes == "framing" && $0.projectId == s.project.id && $0.createdAt == Fx.now })
        XCTAssertThrowsError(try LabourDraft(workDate: Fx.today).makeEntries(companyId: Fx.companyId, projectId: s.project.id, currency: .cad, now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .incompleteLabour)
        }
    }

    func testApplyKeepsPersonAndIdentity() throws {
        let s = Lab.Seed()
        let david = s.entries[2]
        var d = LabourDraft(editing: david)
        XCTAssertEqual(d.days, 7)
        XCTAssertEqual(d.lines, [LabourLine(employeeId: david.employeeId, dailyRate: 200)])
        d.days = 8
        let later = Fx.now.addingTimeInterval(60)
        let u = try d.apply(to: david, now: later)
        XCTAssertEqual(u.id, david.id)
        XCTAssertEqual(u.employeeId, david.employeeId)
        XCTAssertEqual(u.cost, Fx.money(1600))
        XCTAssertEqual(u.createdAt, david.createdAt)
        XCTAssertEqual(u.updatedAt, later)
    }

    func testAlreadyLoggedDays() {
        let s = Lab.Seed()
        let entries = s.entries
        let more = Lab.entry(s.project, s.mike, days: "0.5", rate: "250.00", on: "2026-09-23")
        let day = CalendarDate(storage: "2026-09-23")!
        XCTAssertEqual(LabourDraft.alreadyLoggedDays(employeeId: s.mike.id, on: day, entries: entries + [more], excluding: nil), Decimal(string: "8.5"))
        XCTAssertEqual(LabourDraft.alreadyLoggedDays(employeeId: s.mike.id, on: day, entries: entries + [more], excluding: more.id), 8)
        XCTAssertEqual(LabourDraft.alreadyLoggedDays(employeeId: s.john.id, on: Fx.today, entries: entries, excluding: nil), 0)
    }
}
```

```swift
// Packages/Domain/Tests/DomainTests/Labour/LabourListTests.swift
import XCTest
@testable import Domain

final class LabourListTests: XCTestCase {
    func testSeedSectionsNewestFirst() {
        let s = Lab.Seed()
        let l = LabourListComposer.compose(entries: s.entries, employees: [s.mike, s.john, s.david], currency: .cad)
        XCTAssertEqual(l.sections.map(\.day.storageString), ["2026-09-25", "2026-09-24", "2026-09-23"])
        XCTAssertEqual(l.sections.map(\.total.storageString), ["1400.00", "2200.00", "2000.00"])
        XCTAssertEqual(l.rows.map(\.employeeName), ["David", "John", "Mike"])
        XCTAssertEqual(l.total, Fx.money(5600))
        XCTAssertEqual(l.totalDays, 25)
    }

    func testSameDaySortedByNameAndDeletedHandling() {
        let s = Lab.Seed()
        var gone = s.john
        gone.deletedAt = Fx.now                                                   // left the crew: the name stays on history
        let today = [Lab.entry(s.project, s.mike, days: "1", rate: "250.00", on: "2026-10-03"),
                     Lab.entry(s.project, gone, days: "0.5", rate: "220.00", on: "2026-10-03"),
                     Lab.entry(s.project, s.david, days: "1", rate: "200.00", on: "2026-10-03", deletedAt: Fx.now)]
        let stranger = Lab.entry(s.project, Lab.employee("X", rate: "1.00"), days: "1", rate: "100.00", on: "2026-10-02")
        let l = LabourListComposer.compose(entries: today + [stranger], employees: [s.mike, gone, s.david], currency: .cad)
        XCTAssertEqual(l.sections.first?.rows.map(\.employeeName), ["John", "Mike"])
        XCTAssertEqual(l.sections.first?.total, Fx.money(360))
        XCTAssertEqual(l.sections.first?.days, Decimal(string: "1.5"))
        XCTAssertEqual(l.sections.last?.rows.first?.employeeName, "")
        XCTAssertEqual(l.total, Fx.money(460))
    }

    func testEmpty() {
        let l = LabourListComposer.compose(entries: [], employees: [], currency: .cad)
        XCTAssertTrue(l.sections.isEmpty)
        XCTAssertEqual(l.total, Fx.money(0))
        XCTAssertEqual(l.totalDays, 0)
    }
}
```

`Employee.role`, `.certifications`, `.deletedAt` are `var`; tests may set them.

- [ ] **Step 3: Run — expect compile failure**

Run: `swift test --package-path Packages/Domain --filter "EmployeeDraftTests|LabourDraftTests|LabourListTests"`

- [ ] **Step 4: Implement**

```swift
// Packages/Domain/Sources/Domain/Crew/EmployeeDraft.swift
import Foundation

public enum EmployeeDraftError: Hashable, Sendable, CaseIterable {
    case nameMissing, rateNegative
}

/// Crew member form (spec §3.2). Trade is the one "what they do" field (`role` stays nil in 3b).
public struct EmployeeDraft: Hashable, Sendable {
    /// Only for the "8 h × hourly" helper; labour is always logged in days.
    public static let hoursPerDay: Decimal = 8

    public var name: String
    public var trade: String
    public var phone: String
    public var notes: String
    public var dailyRate: Decimal?
    public var hourlyRate: Decimal?

    public init() { name = ""; trade = ""; phone = ""; notes = ""; dailyRate = nil; hourlyRate = nil }

    public init(editing employee: Employee) {
        name = employee.name
        trade = employee.trade ?? ""
        phone = employee.phone ?? ""
        notes = employee.notes ?? ""
        dailyRate = employee.dailyRate?.amount
        hourlyRate = employee.hourlyRate?.amount
    }

    public var errors: [EmployeeDraftError] {
        var result: [EmployeeDraftError] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.nameMissing) }
        if (dailyRate ?? 0) < 0 || (hourlyRate ?? 0) < 0 { result.append(.rateNegative) }
        return result
    }

    public var canSave: Bool { errors.isEmpty }

    /// rounded(rounded(hourly) × 8); nil without an hourly rate.
    public var dailyFromHourly: Decimal? { hourlyRate.map { Money.rounded(Money.rounded($0) * Self.hoursPerDay) } }

    public func makeEmployee(id: UUID, companyId: UUID, currency: CurrencyCode, now: Date) throws -> Employee {
        try check()
        return Employee(id: id, companyId: companyId, name: trimmedName, phone: Self.clean(phone), role: nil, trade: Self.clean(trade),
                        hourlyRate: hourlyRate.map { Money($0, currency) }, dailyRate: dailyRate.map { Money($0, currency) },
                        certifications: nil, emergencyContact: nil, notes: Self.clean(notes), createdAt: now, updatedAt: now, deletedAt: nil)
    }

    /// Edit: keeps identity, creation time and the fields 3b does not show (role, certifications, emergency contact).
    public func apply(to existing: Employee, currency: CurrencyCode, now: Date) throws -> Employee {
        try check()
        var e = existing
        e.name = trimmedName
        e.trade = Self.clean(trade)
        e.phone = Self.clean(phone)
        e.notes = Self.clean(notes)
        e.dailyRate = dailyRate.map { Money($0, currency) }
        e.hourlyRate = hourlyRate.map { Money($0, currency) }
        e.updatedAt = now
        return e
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func check() throws {
        let found = errors
        if found.contains(.nameMissing) { throw DomainError.emptyName }
        if found.contains(.rateNegative) { throw DomainError.negativeAmount }
    }

    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum CrewList {
    /// Live crew by name (Finder-style compare), then creation time.
    public static func ordered(_ employees: [Employee]) -> [Employee] {
        employees.filter { !$0.isDeleted }.sorted { a, b in
            let c = a.name.localizedStandardCompare(b.name)
            if c != .orderedSame { return c == .orderedAscending }
            return a.createdAt < b.createdAt
        }
    }
}
```

```swift
// Packages/Domain/Sources/Domain/Labour/LabourDraft.swift
import Foundation

public enum LabourDraftError: Hashable, Sendable, CaseIterable {
    case noCrewSelected, daysMissing, daysNotPositive, rateMissing, rateNegative
}

/// One selected person and the daily rate that will be snapshotted on their entry.
public struct LabourLine: Hashable, Sendable, Identifiable {
    public let employeeId: UUID
    public var dailyRate: Decimal?
    public var id: UUID { employeeId }
    public init(employeeId: UUID, dailyRate: Decimal?) { self.employeeId = employeeId; self.dailyRate = dailyRate }
}

/// "Log labour" (spec §3.3): one date and one days value for every selected person; one entry per person.
public struct LabourDraft: Hashable, Sendable {
    public static let dayStep: Decimal = Decimal(5) / Decimal(10)

    public var workDate: CalendarDate
    public var days: Decimal?
    public var lines: [LabourLine]
    public var notes: String

    public init(workDate: CalendarDate) {
        self.workDate = workDate; days = 1; lines = []; notes = ""
    }

    public init(editing entry: LabourEntry) {
        workDate = entry.workDate
        days = entry.days
        lines = [LabourLine(employeeId: entry.employeeId, dailyRate: entry.dailyRate.amount)]
        notes = entry.notes ?? ""
    }

    public func isSelected(_ employeeId: UUID) -> Bool { lines.contains { $0.employeeId == employeeId } }

    /// Selects with the employee's current daily rate (nil when they have none), or deselects.
    public mutating func toggle(_ employee: Employee) {
        if let index = lines.firstIndex(where: { $0.employeeId == employee.id }) { lines.remove(at: index) }
        else { lines.append(LabourLine(employeeId: employee.id, dailyRate: employee.dailyRate?.amount)) }
    }

    public mutating func setRate(_ rate: Decimal?, for employeeId: UUID) {
        guard let index = lines.firstIndex(where: { $0.employeeId == employeeId }) else { return }
        lines[index].dailyRate = rate
    }

    /// ± half a day; never below half a day.
    public mutating func stepDays(up: Bool) {
        let next = (days ?? 0) + (up ? Self.dayStep : -Self.dayStep)
        days = max(Self.dayStep, next)
    }

    /// rounded(days × rate): the same single rounding as `LabourEntry.cost`.
    public func cost(for employeeId: UUID, currency: CurrencyCode) -> Money? {
        guard let days, days > 0, let rate = lines.first(where: { $0.employeeId == employeeId })?.dailyRate, Money.rounded(rate) >= 0 else { return nil }
        return LabourEntry.cost(days: days, dailyRate: Money(rate, currency))
    }

    /// Sum of the rounded per-person costs; nil while nobody is selected or a line cannot be costed.
    public func total(currency: CurrencyCode) -> Money? {
        guard !lines.isEmpty else { return nil }
        var sum = Money.zero(currency)
        for line in lines {
            guard let cost = cost(for: line.employeeId, currency: currency), let next = try? sum.adding(cost) else { return nil }
            sum = next
        }
        return sum
    }

    public func lineError(for employeeId: UUID) -> LabourDraftError? {
        guard let line = lines.first(where: { $0.employeeId == employeeId }) else { return nil }
        guard let rate = line.dailyRate else { return .rateMissing }
        return Money.rounded(rate) < 0 ? .rateNegative : nil
    }

    /// In declaration order of `LabourDraftError`.
    public var errors: [LabourDraftError] {
        var result: [LabourDraftError] = []
        if lines.isEmpty { result.append(.noCrewSelected) }
        if let days {
            if days <= 0 { result.append(.daysNotPositive) }
        } else {
            result.append(.daysMissing)
        }
        let lineErrors = Set(lines.compactMap { lineError(for: $0.employeeId) })
        if lineErrors.contains(.rateMissing) { result.append(.rateMissing) }
        if lineErrors.contains(.rateNegative) { result.append(.rateNegative) }
        return result
    }

    public var canSave: Bool { errors.isEmpty }

    public func makeEntries(companyId: UUID, projectId: UUID, currency: CurrencyCode, now: Date, makeId: () -> UUID = { UUID() }) throws -> [LabourEntry] {
        guard canSave, let days else { throw DomainError.incompleteLabour }
        let note = Self.clean(notes)
        return lines.map { line in
            LabourEntry(id: makeId(), companyId: companyId, projectId: projectId, employeeId: line.employeeId, workDate: workDate, days: days,
                        dailyRate: Money(line.dailyRate ?? 0, currency), notes: note, createdAt: now, updatedAt: now, deletedAt: nil)
        }
    }

    /// Edit one entry: date, days, rate and notes change; the person never does.
    public func apply(to existing: LabourEntry, now: Date) throws -> LabourEntry {
        guard canSave, let days, let rate = lines.first(where: { $0.employeeId == existing.employeeId })?.dailyRate else { throw DomainError.incompleteLabour }
        var entry = existing
        entry.workDate = workDate
        entry.days = days
        entry.dailyRate = Money(rate, existing.dailyRate.currency)
        entry.notes = Self.clean(notes)
        entry.updatedAt = now
        return entry
    }

    /// Days already logged for this person on this day (live entries of the project; `excluding` = the entry being edited).
    public static func alreadyLoggedDays(employeeId: UUID, on day: CalendarDate, entries: [LabourEntry], excluding entryId: UUID?) -> Decimal {
        entries.filter { !$0.isDeleted && $0.employeeId == employeeId && $0.workDate == day && $0.id != entryId }
            .reduce(Decimal(0)) { $0 + $1.days }
    }

    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

```swift
// Packages/Domain/Sources/Domain/Labour/LabourList.swift
import Foundation

public struct LabourRow: Hashable, Sendable, Identifiable {
    public let entry: LabourEntry
    /// The person's name, also after they left the crew; "" when the employee row is missing.
    public let employeeName: String
    public let cost: Money
    public var id: UUID { entry.id }
    public init(entry: LabourEntry, employeeName: String, cost: Money) { self.entry = entry; self.employeeName = employeeName; self.cost = cost }
}

public struct LabourDaySection: Hashable, Sendable, Identifiable {
    public let day: CalendarDate
    public let rows: [LabourRow]
    public let total: Money
    public let days: Decimal
    public var id: CalendarDate { day }
    public init(day: CalendarDate, rows: [LabourRow], total: Money, days: Decimal) { self.day = day; self.rows = rows; self.total = total; self.days = days }
}

public struct ProjectLabourList: Hashable, Sendable {
    public let sections: [LabourDaySection]
    public let total: Money
    public let totalDays: Decimal
    public var rows: [LabourRow] { sections.flatMap(\.rows) }
    public init(sections: [LabourDaySection], total: Money, totalDays: Decimal) { self.sections = sections; self.total = total; self.totalDays = totalDays }
}

public enum LabourListComposer {
    /// Spec §3.3: live entries grouped by work date (newest first), by name inside a day; `employees` includes deleted people.
    public static func compose(entries: [LabourEntry], employees: [Employee], currency: CurrencyCode) -> ProjectLabourList {
        let zero = Money.zero(currency)
        let names = Dictionary(employees.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let rows = entries.filter { !$0.isDeleted }.map { LabourRow(entry: $0, employeeName: names[$0.employeeId] ?? "", cost: $0.cost) }
        func sum(_ rows: [LabourRow]) -> Money { (try? Money.sum(rows.map(\.cost), currency: currency)) ?? zero }
        func days(_ rows: [LabourRow]) -> Decimal { rows.reduce(Decimal(0)) { $0 + $1.entry.days } }
        let byDay = Dictionary(grouping: rows, by: { $0.entry.workDate })
        let sections = byDay.keys.sorted(by: >).map { day -> LabourDaySection in
            let dayRows = (byDay[day] ?? []).sorted { a, b in
                let c = a.employeeName.localizedStandardCompare(b.employeeName)
                if c != .orderedSame { return c == .orderedAscending }
                return (a.entry.createdAt, a.id.uuidString) < (b.entry.createdAt, b.id.uuidString)
            }
            return LabourDaySection(day: day, rows: dayRows, total: sum(dayRows), days: days(dayRows))
        }
        return ProjectLabourList(sections: sections, total: sum(rows), totalDays: days(rows))
    }
}
```

- [ ] **Step 5: Run — all green**

Run: `swift test --package-path Packages/Domain --filter "EmployeeDraftTests|LabourDraftTests|LabourListTests"`, then `swift test --package-path Packages/Domain`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add crew draft, multi-person labour draft and labour list"
```

---

### Task 3: Domain — payment/labour activity, entry currency (+ keep the app compiling)

**Files:**
- Modify: `Packages/Domain/Sources/Domain/Entities/ActivityLog.swift`
- Modify: `Packages/Domain/Sources/Domain/Insights/ActivityDescription.swift`
- Modify: `Packages/Domain/Tests/DomainTests/Insights/ActivityDescriptionTests.swift`
- Modify: `Packages/Features/Sources/FeatureSupport/ActivityText.swift` (exhaustive switches; temporary plain branches)
- Modify: `App/Resources/Localizable.xcstrings` (5 plain activity keys)

**Interfaces:**
- Consumes: `ActivityLogEntry`, `PaymentMethod`, `CurrencyCode`.
- Produces: `ActivityAction.paymentUpdated/.paymentDeleted/.labourLogged/.labourUpdated/.labourDeleted`; `PaymentTitle`; `ActivityDetail.payment(action:title:amount:previousAmount:)`, `.labour(action:names:total:previousTotal:)`; `ActivityDescription.currency(for:) -> CurrencyCode?`. Tasks 4, 5, 7 depend on these.

- [ ] **Step 1: Failing tests** — append to `ActivityDescriptionTests`:

```swift
    func testPaymentReceivedLinked() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentReceived, #"{"amount":"7600.00","currency":"CAD","item":"schedule.row.deposit","method":"eTransfer"}"#)),
                       .payment(action: .paymentReceived, title: .item("schedule.row.deposit"), amount: "7600.00", previousAmount: nil))
    }
    func testPaymentUnlinkedUsesMethod() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentReceived, #"{"amount":"1000.00","currency":"CAD","item":"","method":"cheque"}"#)),
                       .payment(action: .paymentReceived, title: .method(.cheque), amount: "1000.00", previousAmount: nil))
    }
    func testPaymentUpdatedAndDeleted() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentUpdated, #"{"amount":"450.00","currency":"CAD","from":"400.00","item":"","method":"cash"}"#)),
                       .payment(action: .paymentUpdated, title: .method(.cash), amount: "450.00", previousAmount: "400.00"))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentDeleted, #"{"amount":"400.00","currency":"CAD","from":"1.00","item":"Deposit","method":"cash"}"#)),
                       .payment(action: .paymentDeleted, title: .item("Deposit"), amount: "400.00", previousAmount: nil))
    }
    func testLabourLoggedAndUpdated() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourLogged, #"{"currency":"CAD","names":"Mike, John","people":"2","total":"470.00","workDate":"2026-10-03"}"#)),
                       .labour(action: .labourLogged, names: "Mike, John", total: "470.00", previousTotal: nil))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourUpdated, #"{"currency":"CAD","from":"1400.00","names":"David","people":"1","total":"1600.00","workDate":"2026-09-25"}"#)),
                       .labour(action: .labourUpdated, names: "David", total: "1600.00", previousTotal: "1400.00"))
    }
    func testPaymentAndLabourMissingFieldsArePlain() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentReceived, #"{"amount":"1.00"}"#)), .plain(.paymentReceived))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentReceived, #"{"amount":"1.00","method":"bitcoin"}"#)), .plain(.paymentReceived))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourDeleted, #"{"names":"","total":"1.00"}"#)), .plain(.labourDeleted))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourLogged, "not json")), .plain(.labourLogged))
    }
    func testCurrencyFromDetails() {
        XCTAssertEqual(ActivityDescription.currency(for: entry(.paymentReceived, #"{"amount":"1.00","currency":"USD","item":"","method":"cash"}"#)), .usd)
        XCTAssertNil(ActivityDescription.currency(for: entry(.expenseAdded, #"{"category":"fuel","total":"1.00"}"#)))
        XCTAssertNil(ActivityDescription.currency(for: entry(.paymentReceived, "not json")))
        XCTAssertEqual(ActivityAction.allCases.count, 20)
    }
```

- [ ] **Step 2: Run — expect compile failure**

Run: `swift test --package-path Packages/Domain --filter ActivityDescriptionTests`

- [ ] **Step 3: Implement**

`ActivityLog.swift`:

```swift
public enum ActivityAction: String, Codable, Sendable, CaseIterable, Hashable {
    case projectCreated, projectDeleted, contractValueChanged, progressChanged, statusChanged
    case expenseAdded, paymentReceived
    case estimateChanged, scheduleChanged, customerCreated, scopeChanged, timelineChanged, customerChanged
    case expenseUpdated, expenseDeleted
    case paymentUpdated, paymentDeleted, labourLogged, labourUpdated, labourDeleted
}
```

`ActivityDescription.swift` — add after `ExpenseTitle`:

```swift
/// How a payment is named in a sentence: its schedule stage when linked, else its method.
public enum PaymentTitle: Hashable, Sendable {
    case item(String)            // a `schedule.row.*` key or user text
    case method(PaymentMethod)
}
```

add to `ActivityDetail` (before `.plain`):

```swift
    case payment(action: ActivityAction, title: PaymentTitle, amount: String, previousAmount: String?)
    case labour(action: ActivityAction, names: String, total: String, previousTotal: String?)
```

before `default:` in `detail(for:)`:

```swift
        case .paymentReceived, .paymentUpdated, .paymentDeleted:
            guard let amount = s("amount"), let method = s("method").flatMap(PaymentMethod.init(rawValue:)) else { return .plain(entry.action) }
            let item = s("item") ?? ""
            return .payment(action: entry.action, title: item.isEmpty ? .method(method) : .item(item), amount: amount,
                            previousAmount: entry.action == .paymentUpdated ? s("from") : nil)
        case .labourLogged, .labourUpdated, .labourDeleted:
            guard let total = s("total"), let names = s("names"), !names.isEmpty else { return .plain(entry.action) }
            return .labour(action: entry.action, names: names, total: total, previousTotal: entry.action == .labourUpdated ? s("from") : nil)
```

and a new function in `ActivityDescription`:

```swift
    /// The currency written with the row (3b money rows); nil for older rows, which fall back to the company currency.
    public static func currency(for entry: ActivityLogEntry) -> CurrencyCode? {
        guard let data = entry.detailsJSON.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (obj["currency"] as? String).flatMap(CurrencyCode.init(rawValue:))
    }
```

- [ ] **Step 4: Run — all green**

Run: `swift test --package-path Packages/Domain`.

- [ ] **Step 5: Keep the app target and CI lint green**

`ActivityText.swift` — add to `ActivityAction.systemImage`:

```swift
        case .paymentUpdated: return "banknote"
        case .paymentDeleted: return "minus.circle"
        case .labourLogged, .labourUpdated: return "person.badge.clock"
        case .labourDeleted: return "person.badge.minus"
```

and to `ActivityDetail.text(currency:locale:)` temporary branches (Task 7 replaces them with full sentences):

```swift
        case .payment(let action, _, _, _):
            return Text(action.titleKey)
        case .labour(let action, _, _, _):
            return Text(action.titleKey)
```

`Localizable.xcstrings` — add (existing entry format, `"state": "translated"`): `activity.paymentUpdated` "Payment updated" / "Đã sửa thanh toán", `activity.paymentDeleted` "Payment deleted" / "Đã xóa thanh toán", `activity.labourLogged` "Labour logged" / "Đã ghi công", `activity.labourUpdated` "Labour updated" / "Đã sửa công", `activity.labourDeleted` "Labour deleted" / "Đã xóa công". Run `python scripts/check_localization.py` and `python scripts/lint_sources.py` — 0 errors.

- [ ] **Step 6: Commit, push, CI green**

```bash
git add Packages/Domain Packages/Features/Sources/FeatureSupport/ActivityText.swift App/Resources/Localizable.xcstrings
git commit -m "feat(domain): add payment and labour activity details and per-row currency"
git push origin HEAD
```

---

### Task 4: Data — `PaymentRepository` + `GRDBPaymentRepository`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Repositories/PaymentRepository.swift`
- Modify: `Packages/Data/Sources/Data/Records/PaymentRecord.swift` (`Equatable`)
- Create: `Packages/Data/Sources/Data/Repositories/GRDBPaymentRepository.swift`
- Create: `Packages/Data/Tests/DataTests/PaymentRepositoryTests.swift`

**Interfaces:**
- Consumes: `PaymentRecord`, `ActivityLogRecord.append`, `GRDBProjectRepository.currency`, `GRDBExpenseRepository.requireLiveProject`, `GRDBInsightsRepository.observeProject`, `ProjectInsightsComposer`, test helpers `makeFixture`, `XCTAssertThrowsErrorAsync`, `XCTUnwrapAsync`, `XCTAssertNilAsync`.
- Produces: `PaymentRepository` (`get`, `lastUsedMethod`, `create`, `update`, `softDelete`), `GRDBPaymentRepository(database:clock:)`. Tasks 6, 8, 12 use these.

- [ ] **Step 1: Protocol** (compiles alone; its only conformer lands in this same commit)

```swift
// Packages/Domain/Sources/Domain/Repositories/PaymentRepository.swift
import Foundation

public protocol PaymentRepository: Sendable {
    /// nil when missing or soft-deleted.
    func get(id: UUID) async throws -> Payment?
    /// Method of the company's most recently created live payment; nil when there is none.
    func lastUsedMethod(companyId: UUID) async throws -> PaymentMethod?
    /// Payment + `paymentReceived` in one transaction. Throws DomainError.invalidPaymentAmount, .currencyMismatch,
    /// .notFound (project not live, or the schedule item not live / not of this project).
    func create(_ payment: Payment, actor: ActivityActor) async throws
    /// No-op when nothing changed; otherwise `paymentUpdated` (with "from"). DataError.scopeMismatch when company/project changed.
    func update(_ payment: Payment, actor: ActivityActor) async throws
    /// Soft delete + `paymentDeleted`. DomainError.notFound when missing.
    func softDelete(id: UUID, actor: ActivityActor) async throws
}
```

`PaymentRecord`: change the declaration to `struct PaymentRecord: Codable, FetchableRecord, PersistableRecord, Equatable {`.

- [ ] **Step 2: Failing tests**

```swift
// Packages/Data/Tests/DataTests/PaymentRepositoryTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class PaymentRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let today = CalendarDate(storage: "2026-10-03")!
    var db: AppDatabase!
    var f: Fixture!
    var repo: GRDBPaymentRepository!
    var deposit: PaymentScheduleItem!
    var balance: PaymentScheduleItem!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        f = try await makeFixture(db, now: now)
        repo = GRDBPaymentRepository(database: db, clock: .fixed(now))
        deposit = item("Deposit", 400, order: 0)
        balance = item("schedule.row.final", 600, order: 1)
        try await GRDBPaymentScheduleRepository(database: db, clock: .fixed(now)).replace(projectId: f.project.id, change: ScheduleItemChange(
            upserts: [deposit, balance], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(1000, .cad)), actor: f.actor)
    }

    func item(_ label: String, _ amount: Int, order: Int, project: Project? = nil) -> PaymentScheduleItem {
        PaymentScheduleItem(id: UUID(), companyId: f.companyId, projectId: (project ?? f.project).id, label: label, amount: Money(Decimal(amount), .cad),
                            percentage: nil, dueDate: CalendarDate(storage: "2026-10-10"), triggerText: nil, isDeposit: order == 0, notes: nil,
                            sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func payment(_ amount: String, item: UUID?, method: PaymentMethod = .eTransfer, currency: CurrencyCode = .cad, project: Project? = nil) -> Payment {
        Payment(id: UUID(), companyId: f.companyId, projectId: (project ?? f.project).id, scheduleItemId: item, amount: Money(storage: amount, currency: currency)!,
                paidOn: today, method: method, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func activities() async throws -> [(action: String, details: String)] {
        try await db.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT action, details_json FROM activity_log WHERE entity_type = 'payment' ORDER BY rowid").map { ($0["action"], $0["details_json"]) }
        }
    }
    func paymentRows() async throws -> Int {
        try await db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM payments") ?? 0 }
    }
    func insights() async throws -> ProjectInsights {
        var it = GRDBInsightsRepository(database: db).observeProject(id: f.project.id).makeAsyncIterator()
        let value = try await it.next()
        let snap = try XCTUnwrap(value ?? nil)
        return ProjectInsightsComposer.compose(snap.with(today: today))
    }
    func otherProject() async throws -> Project {
        let p = f.project
        let q = Project(id: UUID(), companyId: p.companyId, customerId: p.customerId, name: "Q", jobType: p.jobType, customJobType: nil, status: .inProgress, address: p.address,
                        scopeDescription: nil, scopeFields: [], startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil,
                        contractValue: Money(500, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).save(q, actor: f.actor)
        return q
    }

    func testCreateLinkedPaymentLogsActivityAndPaysItem() async throws {
        let p = payment("400.00", item: deposit.id)
        try await repo.create(p, actor: f.actor)
        let back = try await XCTUnwrapAsync(try await repo.get(id: p.id))
        XCTAssertEqual(back.amount.storageString, "400.00")
        XCTAssertEqual(back.scheduleItemId, deposit.id)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["paymentReceived"])
        XCTAssertEqual(a[0].details, #"{"amount":"400.00","currency":"CAD","item":"Deposit","method":"eTransfer"}"#)
        let i = try await insights()
        XCTAssertEqual(i.payments.map(\.status), [.paid, .upcoming])
        XCTAssertEqual(i.financials?.collected, Money(400, .cad))
        XCTAssertEqual(i.financials?.outstandingBalance, Money(600, .cad))
    }

    func testOverpaymentAndUnlinkedPayment() async throws {
        try await repo.create(payment("700.00", item: balance.id), actor: f.actor)
        try await repo.create(payment("50.00", item: nil), actor: f.actor)
        let i = try await insights()
        XCTAssertEqual(i.payments.map(\.status), [.upcoming, .paid])
        XCTAssertEqual(i.payments.map(\.remaining.storageString), ["400.00", "0.00"])
        XCTAssertEqual(i.payments[0].paid, Money(0, .cad))               // the 100 extra never moves to the deposit
        XCTAssertEqual(i.financials?.collected, Money(750, .cad))
        XCTAssertEqual(i.unallocatedCollected, Money(50, .cad))
        let a = try await activities()
        XCTAssertEqual(a.last?.details, #"{"amount":"50.00","currency":"CAD","item":"","method":"eTransfer"}"#)
    }

    func testRefusesDeletedOrForeignItemAndWritesNothing() async throws {
        let q = try await otherProject()
        let foreign = item("Q deposit", 100, order: 0, project: q)
        try await GRDBPaymentScheduleRepository(database: db, clock: .fixed(now)).replace(projectId: q.id, change: ScheduleItemChange(
            upserts: [foreign], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(100, .cad)), actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.payment("10.00", item: foreign.id), actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        try await GRDBPaymentScheduleRepository(database: db, clock: .fixed(now)).replace(projectId: f.project.id, change: ScheduleItemChange(
            upserts: [], deletedIds: [deposit.id], totalBefore: Money(1000, .cad), totalAfter: Money(600, .cad)), actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.payment("10.00", item: self.deposit.id), actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.payment("10.00", item: nil, currency: .usd), actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
        let zero = Payment(id: UUID(), companyId: f.companyId, projectId: f.project.id, scheduleItemId: nil, amount: .zero(.cad), paidOn: today, method: .cash,
                           notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        await XCTAssertThrowsErrorAsync(try await self.repo.create(zero, actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .invalidPaymentAmount) }
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).softDelete(id: q.id, actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.payment("10.00", item: nil, project: q), actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        await XCTAssertEqualAsync(try await self.paymentRows(), 0)
        await XCTAssertEqualAsync(try await self.activities().count, 0)
    }

    func testUpdateNoOpAmountChangeAndScope() async throws {
        let p = payment("400.00", item: deposit.id)
        try await repo.create(p, actor: f.actor)
        let stored = try await XCTUnwrapAsync(try await repo.get(id: p.id))
        let later = GRDBPaymentRepository(database: db, clock: .fixed(now.addingTimeInterval(60)))
        try await later.update(stored, actor: f.actor)                                    // nothing changed
        await XCTAssertEqualAsync(try await self.activities().map(\.action), ["paymentReceived"])
        await XCTAssertEqualAsync(try await self.repo.get(id: p.id)?.updatedAt, now)
        var changed = stored
        changed.amount = Money(450, .cad)
        changed.scheduleItemId = nil
        try await later.update(changed, actor: f.actor)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["paymentReceived", "paymentUpdated"])
        XCTAssertEqual(a[1].details, #"{"amount":"450.00","currency":"CAD","from":"400.00","item":"","method":"eTransfer"}"#)
        let back = try await XCTUnwrapAsync(try await repo.get(id: p.id))
        XCTAssertNil(back.scheduleItemId)
        XCTAssertEqual(back.updatedAt, now.addingTimeInterval(60))
        XCTAssertEqual(back.createdAt, now)
        let q = try await otherProject()
        let moved = Payment(id: p.id, companyId: f.companyId, projectId: q.id, scheduleItemId: nil, amount: Money(450, .cad), paidOn: today, method: .eTransfer,
                            notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        await XCTAssertThrowsErrorAsync(try await self.repo.update(moved, actor: self.f.actor)) { XCTAssertEqual($0 as? DataError, .scopeMismatch) }
    }

    func testSoftDeleteRemovesFromCollected() async throws {
        let p = payment("400.00", item: deposit.id)
        try await repo.create(p, actor: f.actor)
        try await repo.softDelete(id: p.id, actor: f.actor)
        await XCTAssertNilAsync(try await self.repo.get(id: p.id))
        let i = try await insights()
        XCTAssertEqual(i.financials?.collected, Money(0, .cad))
        XCTAssertEqual(i.payments.first?.status, .upcoming)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["paymentReceived", "paymentDeleted"])
        XCTAssertEqual(a[1].details, #"{"amount":"400.00","currency":"CAD","item":"Deposit","method":"eTransfer"}"#)
        await XCTAssertThrowsErrorAsync(try await self.repo.softDelete(id: p.id, actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }

    func testLastUsedMethod() async throws {
        await XCTAssertNilAsync(try await self.repo.lastUsedMethod(companyId: self.f.companyId))
        try await repo.create(payment("10.00", item: nil, method: .cheque), actor: f.actor)
        let cash = payment("20.00", item: nil, method: .cash)
        try await GRDBPaymentRepository(database: db, clock: .fixed(now.addingTimeInterval(60))).create(cash, actor: f.actor)
        await XCTAssertEqualAsync(try await self.repo.lastUsedMethod(companyId: self.f.companyId), .cash)
        try await repo.softDelete(id: cash.id, actor: f.actor)
        await XCTAssertEqualAsync(try await self.repo.lastUsedMethod(companyId: self.f.companyId), .cheque)
    }
}
```

- [ ] **Step 3: Implement**

```swift
// Packages/Data/Sources/Data/Repositories/GRDBPaymentRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBPaymentRepository: PaymentRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    // MARK: Reads

    public func get(id: UUID) async throws -> Payment? {
        try await database.writer.read { db in
            guard let record = try PaymentRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            return try record.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: record.companyId))
        }
    }

    public func lastUsedMethod(companyId: UUID) async throws -> PaymentMethod? {
        try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT method FROM payments WHERE company_id = ? AND deleted_at IS NULL ORDER BY created_at DESC, rowid DESC LIMIT 1",
                                arguments: [companyId.dbKey]).flatMap(PaymentMethod.init(rawValue:))
        }
    }

    // MARK: Writes

    public func create(_ payment: Payment, actor: ActivityActor) async throws {
        try payment.validate()
        let now = clock.now()
        var stamped = payment
        stamped.createdAt = now; stamped.updatedAt = now; stamped.deletedAt = nil
        let input = stamped
        try await database.writer.write { db in
            try Self.checkScope(db, input)
            try PaymentRecord(input).insert(db)
            try ActivityLogRecord.append(db, companyId: input.companyId, actor: actor, action: .paymentReceived, entityType: "payment", entityId: input.id,
                                         projectId: input.projectId, details: try Self.details(db, input), at: now)
        }
    }

    public func update(_ payment: Payment, actor: ActivityActor) async throws {
        try payment.validate()
        let now = clock.now()
        let input = payment
        try await database.writer.write { db in
            guard let old = try PaymentRecord.filter(Column("id") == input.id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard old.companyId == input.companyId.dbKey, old.projectId == input.projectId.dbKey else { throw DataError.scopeMismatch }
            try Self.checkScope(db, input)
            let previous = try old.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: old.companyId))
            var row = input
            row.createdAt = previous.createdAt
            row.updatedAt = previous.updatedAt
            row.deletedAt = nil
            var candidate = PaymentRecord(row)
            candidate.syncState = old.syncState
            guard candidate != old else { return }
            row.updatedAt = now
            try PaymentRecord(row).update(db)
            var details = try Self.details(db, row)
            details["from"] = previous.amount.storageString
            try ActivityLogRecord.append(db, companyId: row.companyId, actor: actor, action: .paymentUpdated, entityType: "payment", entityId: row.id,
                                         projectId: row.projectId, details: details, at: now)
        }
    }

    public func softDelete(id: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try PaymentRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            let payment = try record.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: record.companyId))
            try db.execute(sql: "UPDATE payments SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, record.id])
            try ActivityLogRecord.append(db, companyId: payment.companyId, actor: actor, action: .paymentDeleted, entityType: "payment", entityId: payment.id,
                                         projectId: payment.projectId, details: try Self.details(db, payment), at: now)
        }
    }

    // MARK: Helpers

    /// Currency matches the company; project live in the company; a linked item live AND of the same project
    /// (the composite foreign key cannot see soft deletes).
    static func checkScope(_ db: Database, _ payment: Payment) throws {
        let currency = try GRDBProjectRepository.currency(db, companyId: payment.companyId.dbKey)
        guard payment.amount.currency == currency else { throw DomainError.currencyMismatch }
        try GRDBExpenseRepository.requireLiveProject(db, id: payment.projectId, companyId: payment.companyId)
        if let item = payment.scheduleItemId {
            let live = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM payment_schedule_items WHERE id = ? AND project_id = ? AND company_id = ? AND deleted_at IS NULL",
                                        arguments: [item.dbKey, payment.projectId.dbKey, payment.companyId.dbKey]) ?? 0
            guard live > 0 else { throw DomainError.notFound }
        }
    }

    static func details(_ db: Database, _ payment: Payment) throws -> [String: String] {
        let label = try payment.scheduleItemId.flatMap { try String.fetchOne(db, sql: "SELECT label FROM payment_schedule_items WHERE id = ?", arguments: [$0.dbKey]) } ?? ""
        return ["amount": payment.amount.storageString, "currency": payment.amount.currency.rawValue, "item": label, "method": payment.method.rawValue]
    }
}
```

`Payment.amount`, `.scheduleItemId`, `.createdAt`, `.updatedAt`, `.deletedAt` are `var`; `projectId`/`companyId` are `let` (tests rebuild a `Payment` to move it).

- [ ] **Step 4: Lint, push, CI green, commit**

```bash
python scripts/lint_sources.py
git add Packages/Domain/Sources/Domain/Repositories/PaymentRepository.swift Packages/Data
git commit -m "feat(data): add payment repository with allocation checks and activity"
git push origin HEAD
```

---

### Task 5: Data — `EmployeeRepository`, `LabourRepository` + GRDB implementations

**Files:**
- Create: `Packages/Domain/Sources/Domain/Repositories/EmployeeRepository.swift`
- Create: `Packages/Domain/Sources/Domain/Repositories/LabourRepository.swift`
- Modify: `Packages/Data/Sources/Data/Records/EmployeeRecord.swift` (`Equatable`, `fetchAll` incl. deleted)
- Modify: `Packages/Data/Sources/Data/Records/LabourEntryRecord.swift` (`Equatable`)
- Create: `Packages/Data/Sources/Data/Repositories/GRDBEmployeeRepository.swift`
- Create: `Packages/Data/Sources/Data/Repositories/GRDBLabourRepository.swift`
- Create: `Packages/Data/Tests/DataTests/EmployeeRepositoryTests.swift`
- Create: `Packages/Data/Tests/DataTests/LabourRepositoryTests.swift`

**Interfaces:**
- Consumes: `EmployeeRecord`, `LabourEntryRecord`, `ProjectRecord`, `CrewList`, `LabourListComposer`, `ActivityLogRecord.append`, `GRDBInsightsRepository.stream`, `GRDBExpenseRepository.requireLiveProject`.
- Produces: `EmployeeRepository` (`observeAll`, `get(id:includingDeleted:)`, `create`, `update`, `softDelete`), `ProjectLabourSnapshot`, `LabourRepository` (`observeProject`, `get`, `create`, `update`, `softDelete`), `GRDBEmployeeRepository(database:clock:)`, `GRDBLabourRepository(database:clock:)`. Tasks 6, 9–12 use these.

- [ ] **Step 1: Protocols**

```swift
// Packages/Domain/Sources/Domain/Repositories/EmployeeRepository.swift
import Foundation

public protocol EmployeeRepository: Sendable {
    /// Live crew ordered by `CrewList.ordered`; emits on any change.
    func observeAll(companyId: UUID) -> AsyncThrowingStream<[Employee], Error>
    /// `includingDeleted: true` is for history (names of labour entries).
    func get(id: UUID, includingDeleted: Bool) async throws -> Employee?
    /// DomainError.emptyName / .negativeAmount / .currencyMismatch.
    func create(_ employee: Employee) async throws
    /// No-op when nothing changed. DomainError.notFound, DataError.scopeMismatch (other company).
    func update(_ employee: Employee) async throws
    /// Hides the person; their labour entries stay (Foundation A.2). DomainError.notFound.
    func softDelete(id: UUID) async throws
}
```

```swift
// Packages/Domain/Sources/Domain/Repositories/LabourRepository.swift
import Foundation

public struct ProjectLabourSnapshot: Hashable, Sendable {
    public var currency: CurrencyCode
    /// Live entries of the project.
    public var entries: [LabourEntry]
    /// Every employee of the company, deleted ones included (names of history rows).
    public var employees: [Employee]
    public init(currency: CurrencyCode, entries: [LabourEntry], employees: [Employee]) { self.currency = currency; self.entries = entries; self.employees = employees }
}

public protocol LabourRepository: Sendable {
    /// nil when the project is missing or soft-deleted; emits on any change.
    func observeProject(id: UUID) -> AsyncThrowingStream<ProjectLabourSnapshot?, Error>
    /// nil when missing or soft-deleted.
    func get(id: UUID) async throws -> LabourEntry?
    /// All entries + ONE `labourLogged` in one transaction, or nothing. DomainError.incompleteLabour (empty), .invalidLabourDays,
    /// .negativeAmount, .currencyMismatch, .notFound (project or an employee not live); DataError.scopeMismatch (mixed projects).
    func create(_ entries: [LabourEntry], actor: ActivityActor) async throws
    /// No-op when nothing changed; otherwise `labourUpdated`. DataError.scopeMismatch when company/project/employee changed.
    func update(_ entry: LabourEntry, actor: ActivityActor) async throws
    /// Soft delete + `labourDeleted`. DomainError.notFound.
    func softDelete(id: UUID, actor: ActivityActor) async throws
}
```

`EmployeeRecord`: declaration gains `, Equatable`; add

```swift
    /// Every employee of the company, deleted ones included (labour history names).
    static func fetchAll(_ db: Database, companyId: String, currency: CurrencyCode) throws -> [Employee] {
        try EmployeeRecord.filter(Column("company_id") == companyId).order(Column("name")).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
```

`LabourEntryRecord`: declaration gains `, Equatable`.

- [ ] **Step 2: Failing tests**

```swift
// Packages/Data/Tests/DataTests/EmployeeRepositoryTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class EmployeeRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!
    var f: Fixture!
    var repo: GRDBEmployeeRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        f = try await makeFixture(db, now: now)
        repo = GRDBEmployeeRepository(database: db, clock: .fixed(now))
    }

    func person(_ name: String, daily: Int? = 250, currency: CurrencyCode = .cad) -> Employee {
        Employee(id: UUID(), companyId: f.companyId, name: name, phone: nil, role: nil, trade: "Carpenter", hourlyRate: nil,
                 dailyRate: daily.map { Money(Decimal($0), currency) }, certifications: nil, emergencyContact: nil, notes: nil,
                 createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func firstEmission() async throws -> [Employee] {
        var it = repo.observeAll(companyId: f.companyId).makeAsyncIterator()
        return try await XCTUnwrapAsync(try await it.next())
    }

    func testCreateAndObserveLiveByName() async throws {
        try await repo.create(person("mike"))
        try await repo.create(person("David"))
        await XCTAssertEqualAsync(try await self.firstEmission().map(\.name), ["David", "mike"])
    }

    func testValidation() async throws {
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.person("  "))) { XCTAssertEqual($0 as? DomainError, .emptyName) }
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.person("Neg", daily: -1))) { XCTAssertEqual($0 as? DomainError, .negativeAmount) }
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.person("Usd", currency: .usd))) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
    }

    func testUpdateNoOpAndChange() async throws {
        let mike = person("Mike")
        try await repo.create(mike)
        let later = GRDBEmployeeRepository(database: db, clock: .fixed(now.addingTimeInterval(60)))
        try await later.update(mike)
        await XCTAssertEqualAsync(try await self.repo.get(id: mike.id, includingDeleted: false)?.updatedAt, now)
        var raised = mike
        raised.dailyRate = Money(275, .cad)
        try await later.update(raised)
        let back = try await XCTUnwrapAsync(try await repo.get(id: mike.id, includingDeleted: false))
        XCTAssertEqual(back.dailyRate, Money(275, .cad))
        XCTAssertEqual(back.updatedAt, now.addingTimeInterval(60))
        XCTAssertEqual(back.createdAt, now)
    }

    func testSoftDeleteHidesButKeepsHistoryLookup() async throws {
        let mike = person("Mike"), john = person("John")
        try await repo.create(mike)
        try await repo.create(john)
        try await repo.softDelete(id: mike.id)
        await XCTAssertEqualAsync(try await self.firstEmission().map(\.name), ["John"])
        await XCTAssertNilAsync(try await self.repo.get(id: mike.id, includingDeleted: false))
        let gone = try await XCTUnwrapAsync(try await repo.get(id: mike.id, includingDeleted: true))
        XCTAssertNotNil(gone.deletedAt)
        await XCTAssertThrowsErrorAsync(try await self.repo.update(mike)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        await XCTAssertThrowsErrorAsync(try await self.repo.softDelete(id: mike.id)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }
}
```

```swift
// Packages/Data/Tests/DataTests/LabourRepositoryTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class LabourRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let today = CalendarDate(storage: "2026-10-03")!
    var db: AppDatabase!
    var f: Fixture!
    var crew: GRDBEmployeeRepository!
    var repo: GRDBLabourRepository!
    var mike: Employee!
    var john: Employee!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        f = try await makeFixture(db, now: now)
        crew = GRDBEmployeeRepository(database: db, clock: .fixed(now))
        repo = GRDBLabourRepository(database: db, clock: .fixed(now))
        mike = person("Mike", "250.00")
        john = person("John", "333.33")
        try await crew.create(mike)
        try await crew.create(john)
    }

    func person(_ name: String, _ rate: String) -> Employee {
        Employee(id: UUID(), companyId: f.companyId, name: name, phone: nil, role: nil, trade: nil, hourlyRate: nil, dailyRate: Money(storage: rate, currency: .cad),
                 certifications: nil, emergencyContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func entry(_ e: Employee, days: String, rate: String, project: Project? = nil, id: UUID = UUID()) -> LabourEntry {
        LabourEntry(id: id, companyId: f.companyId, projectId: (project ?? f.project).id, employeeId: e.id, workDate: today, days: Decimal(string: days)!,
                    dailyRate: Money(storage: rate, currency: .cad)!, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func activities() async throws -> [(action: String, details: String)] {
        try await db.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT action, details_json FROM activity_log WHERE entity_type = 'labour_entry' ORDER BY rowid").map { ($0["action"], $0["details_json"]) }
        }
    }
    func entryRows() async throws -> Int {
        try await db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM labour_entries") ?? 0 }
    }
    func snapshot() async throws -> ProjectLabourSnapshot {
        var it = repo.observeProject(id: f.project.id).makeAsyncIterator()
        let value = try await it.next()
        return try XCTUnwrap(value ?? nil)
    }
    func labourActual() async throws -> Money? {
        var it = GRDBInsightsRepository(database: db).observeProject(id: f.project.id).makeAsyncIterator()
        let value = try await it.next()
        let snap = try XCTUnwrap(value ?? nil)
        return ProjectInsightsComposer.compose(snap.with(today: today)).financials?.actualByGroup[.labour]
    }

    func testCreateBatchWritesOneActivity() async throws {
        try await repo.create([entry(mike, days: "1", rate: "250.00"), entry(john, days: "0.5", rate: "333.33")], actor: f.actor)
        await XCTAssertEqualAsync(try await self.entryRows(), 2)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["labourLogged"])
        XCTAssertEqual(a[0].details, #"{"currency":"CAD","names":"Mike, John","people":"2","total":"416.67","workDate":"2026-10-03"}"#)
        await XCTAssertEqualAsync(try await self.snapshot().entries.count, 2)
        await XCTAssertEqualAsync(try await self.labourActual(), Money(storage: "416.67", currency: .cad))
    }

    func testBatchWithDeletedEmployeeWritesNothing() async throws {
        try await crew.softDelete(id: john.id)
        await XCTAssertThrowsErrorAsync(try await self.repo.create([self.entry(self.mike, days: "1", rate: "250.00"), self.entry(self.john, days: "1", rate: "333.33")], actor: self.f.actor)) {
            XCTAssertEqual($0 as? DomainError, .notFound)
        }
        await XCTAssertEqualAsync(try await self.entryRows(), 0)
        await XCTAssertEqualAsync(try await self.activities().count, 0)
    }

    func testInvalidBatches() async throws {
        await XCTAssertThrowsErrorAsync(try await self.repo.create([], actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .incompleteLabour) }
        await XCTAssertThrowsErrorAsync(try await self.repo.create([self.entry(self.mike, days: "0", rate: "250.00")], actor: self.f.actor)) {
            XCTAssertEqual($0 as? DomainError, .invalidLabourDays)
        }
        let p = f.project
        let other = Project(id: UUID(), companyId: p.companyId, customerId: p.customerId, name: "Q", jobType: p.jobType, customJobType: nil, status: .inProgress,
                            address: p.address, scopeDescription: nil, scopeFields: [], startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil,
                            workersPerDay: nil, contractValue: Money(1, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).save(other, actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await self.repo.create([self.entry(self.mike, days: "1", rate: "250.00"), self.entry(self.john, days: "1", rate: "1.00", project: other)], actor: self.f.actor)) {
            XCTAssertEqual($0 as? DataError, .scopeMismatch)
        }
        await XCTAssertEqualAsync(try await self.entryRows(), 0)
    }

    func testUpdateDaysNoOpAndPersonLocked() async throws {
        let e = entry(mike, days: "1", rate: "250.00")
        try await repo.create([e], actor: f.actor)
        let stored = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        let later = GRDBLabourRepository(database: db, clock: .fixed(now.addingTimeInterval(60)))
        try await later.update(stored, actor: f.actor)
        await XCTAssertEqualAsync(try await self.activities().map(\.action), ["labourLogged"])
        var longer = stored
        longer.days = Decimal(string: "1.5")!
        try await later.update(longer, actor: f.actor)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["labourLogged", "labourUpdated"])
        XCTAssertEqual(a[1].details, #"{"currency":"CAD","from":"250.00","names":"Mike","people":"1","total":"375.00","workDate":"2026-10-03"}"#)
        await XCTAssertEqualAsync(try await self.repo.get(id: e.id)?.cost, Money(375, .cad))
        let swapped = entry(john, days: "1.5", rate: "250.00", id: e.id)
        await XCTAssertThrowsErrorAsync(try await self.repo.update(swapped, actor: self.f.actor)) { XCTAssertEqual($0 as? DataError, .scopeMismatch) }
    }

    func testEmployeeRateChangeKeepsEntrySnapshot() async throws {
        let e = entry(mike, days: "2", rate: "250.00")
        try await repo.create([e], actor: f.actor)
        var raised = mike!
        raised.dailyRate = Money(300, .cad)
        try await crew.update(raised)
        await XCTAssertEqualAsync(try await self.repo.get(id: e.id)?.dailyRate, Money(250, .cad))
        await XCTAssertEqualAsync(try await self.labourActual(), Money(500, .cad))
    }

    func testDeletedEmployeeKeepsHistory() async throws {
        let e = entry(mike, days: "1", rate: "250.00")
        try await repo.create([e], actor: f.actor)
        try await crew.softDelete(id: mike.id)
        let snap = try await snapshot()
        XCTAssertEqual(snap.entries.map(\.id), [e.id])
        let list = LabourListComposer.compose(entries: snap.entries, employees: snap.employees, currency: snap.currency)
        XCTAssertEqual(list.rows.map(\.employeeName), ["Mike"])
        await XCTAssertEqualAsync(try await self.labourActual(), Money(250, .cad))
        var fixed = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        fixed.days = 2
        try await repo.update(fixed, actor: f.actor)                                  // history stays editable
        await XCTAssertEqualAsync(try await self.labourActual(), Money(500, .cad))
    }

    func testSoftDeleteEntry() async throws {
        let e = entry(mike, days: "1", rate: "250.00")
        try await repo.create([e], actor: f.actor)
        try await repo.softDelete(id: e.id, actor: f.actor)
        await XCTAssertNilAsync(try await self.repo.get(id: e.id))
        await XCTAssertEqualAsync(try await self.snapshot().entries.count, 0)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["labourLogged", "labourDeleted"])
        XCTAssertEqual(a[1].details, #"{"currency":"CAD","names":"Mike","people":"1","total":"250.00","workDate":"2026-10-03"}"#)
        await XCTAssertThrowsErrorAsync(try await self.repo.softDelete(id: e.id, actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }
}
```

`mike!` unwraps the implicitly-unwrapped test property into a mutable copy (test code; the lint skips `Tests`).

- [ ] **Step 3: Implement**

```swift
// Packages/Data/Sources/Data/Repositories/GRDBEmployeeRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBEmployeeRepository: EmployeeRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    public func observeAll(companyId: UUID) -> AsyncThrowingStream<[Employee], Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> [Employee] in
            let currency = try GRDBProjectRepository.currency(db, companyId: key)
            return CrewList.ordered(try EmployeeRecord.fetchLive(db, companyId: key, currency: currency))
        }
        return GRDBInsightsRepository.stream(observation, in: database.writer)
    }

    public func get(id: UUID, includingDeleted: Bool) async throws -> Employee? {
        try await database.writer.read { db in
            var request = EmployeeRecord.filter(Column("id") == id.dbKey)
            if !includingDeleted { request = request.filter(Column("deleted_at") == nil) }
            guard let record = try request.fetchOne(db) else { return nil }
            return try record.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: record.companyId))
        }
    }

    public func create(_ employee: Employee) async throws {
        try employee.validate()
        let now = clock.now()
        var stamped = employee
        stamped.createdAt = now; stamped.updatedAt = now; stamped.deletedAt = nil
        let input = stamped
        try await database.writer.write { db in
            try Self.checkCurrency(db, input)
            try EmployeeRecord(input).insert(db)
        }
    }

    public func update(_ employee: Employee) async throws {
        try employee.validate()
        let now = clock.now()
        let input = employee
        try await database.writer.write { db in
            guard let old = try EmployeeRecord.filter(Column("id") == input.id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard old.companyId == input.companyId.dbKey else { throw DataError.scopeMismatch }
            try Self.checkCurrency(db, input)
            var row = input
            row.createdAt = try RecordSupport.date(old.createdAt, table: "employees", id: old.id, column: "created_at")
            row.updatedAt = try RecordSupport.date(old.updatedAt, table: "employees", id: old.id, column: "updated_at")
            row.deletedAt = nil
            var candidate = EmployeeRecord(row)
            candidate.syncState = old.syncState
            guard candidate != old else { return }
            row.updatedAt = now
            try EmployeeRecord(row).update(db)
        }
    }

    public func softDelete(id: UUID) async throws {
        let stamp = Timestamps.string(clock.now())
        try await database.writer.write { db in
            guard try EmployeeRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) != nil else { throw DomainError.notFound }
            try db.execute(sql: "UPDATE employees SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, id.dbKey])
        }
    }

    private static func checkCurrency(_ db: Database, _ employee: Employee) throws {
        let currency = try GRDBProjectRepository.currency(db, companyId: employee.companyId.dbKey)
        guard [employee.dailyRate, employee.hourlyRate].compactMap({ $0 }).allSatisfy({ $0.currency == currency }) else { throw DomainError.currencyMismatch }
    }
}
```

```swift
// Packages/Data/Sources/Data/Repositories/GRDBLabourRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBLabourRepository: LabourRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    // MARK: Reads

    public func observeProject(id: UUID) -> AsyncThrowingStream<ProjectLabourSnapshot?, Error> {
        let key = id.dbKey
        let observation = ValueObservation.tracking { db -> ProjectLabourSnapshot? in
            guard let project = try ProjectRecord.filter(Column("id") == key && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            let currency = try GRDBProjectRepository.currency(db, companyId: project.companyId)
            return ProjectLabourSnapshot(currency: currency,
                                         entries: try LabourEntryRecord.fetchLive(db, projectId: key, currency: currency),
                                         employees: try EmployeeRecord.fetchAll(db, companyId: project.companyId, currency: currency))
        }
        return GRDBInsightsRepository.stream(observation, in: database.writer)
    }

    public func get(id: UUID) async throws -> LabourEntry? {
        try await database.writer.read { db in
            guard let record = try LabourEntryRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            return try record.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: record.companyId))
        }
    }

    // MARK: Writes

    public func create(_ entries: [LabourEntry], actor: ActivityActor) async throws {
        guard let first = entries.first else { throw DomainError.incompleteLabour }
        guard entries.allSatisfy({ $0.projectId == first.projectId && $0.companyId == first.companyId }) else { throw DataError.scopeMismatch }
        for entry in entries { try entry.validate() }
        let now = clock.now()
        let stamped = entries.map { e -> LabourEntry in var s = e; s.createdAt = now; s.updatedAt = now; s.deletedAt = nil; return s }
        try await database.writer.write { db in
            let currency = try GRDBProjectRepository.currency(db, companyId: first.companyId.dbKey)
            guard stamped.allSatisfy({ $0.dailyRate.currency == currency }) else { throw DomainError.currencyMismatch }
            try GRDBExpenseRepository.requireLiveProject(db, id: first.projectId, companyId: first.companyId)
            var names: [String] = []
            for entry in stamped {
                guard let name = try String.fetchOne(db, sql: "SELECT name FROM employees WHERE id = ? AND company_id = ? AND deleted_at IS NULL",
                                                     arguments: [entry.employeeId.dbKey, entry.companyId.dbKey]) else { throw DomainError.notFound }
                names.append(name)
                try LabourEntryRecord(entry).insert(db)
            }
            let total = try Money.sum(stamped.map(\.cost), currency: currency)
            try ActivityLogRecord.append(db, companyId: first.companyId, actor: actor, action: .labourLogged, entityType: "labour_entry", entityId: first.id,
                                         projectId: first.projectId,
                                         details: ["currency": currency.rawValue, "names": names.joined(separator: ", "), "people": String(stamped.count),
                                                   "total": total.storageString, "workDate": first.workDate.storageString], at: now)
        }
    }

    public func update(_ entry: LabourEntry, actor: ActivityActor) async throws {
        try entry.validate()
        let now = clock.now()
        let input = entry
        try await database.writer.write { db in
            guard let old = try LabourEntryRecord.filter(Column("id") == input.id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard old.companyId == input.companyId.dbKey, old.projectId == input.projectId.dbKey, old.employeeId == input.employeeId.dbKey else { throw DataError.scopeMismatch }
            let currency = try GRDBProjectRepository.currency(db, companyId: old.companyId)
            guard input.dailyRate.currency == currency else { throw DomainError.currencyMismatch }
            try GRDBExpenseRepository.requireLiveProject(db, id: input.projectId, companyId: input.companyId)
            let previous = try old.toDomain(currency: currency)
            var row = input
            row.createdAt = previous.createdAt
            row.updatedAt = previous.updatedAt
            row.deletedAt = nil
            var candidate = LabourEntryRecord(row)
            candidate.syncState = old.syncState
            guard candidate != old else { return }
            row.updatedAt = now
            try LabourEntryRecord(row).update(db)
            var details = try Self.details(db, row, currency: currency)
            details["from"] = previous.cost.storageString
            try ActivityLogRecord.append(db, companyId: row.companyId, actor: actor, action: .labourUpdated, entityType: "labour_entry", entityId: row.id,
                                         projectId: row.projectId, details: details, at: now)
        }
    }

    public func softDelete(id: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try LabourEntryRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            let currency = try GRDBProjectRepository.currency(db, companyId: record.companyId)
            let entry = try record.toDomain(currency: currency)
            try db.execute(sql: "UPDATE labour_entries SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, record.id])
            try ActivityLogRecord.append(db, companyId: entry.companyId, actor: actor, action: .labourDeleted, entityType: "labour_entry", entityId: entry.id,
                                         projectId: entry.projectId, details: try Self.details(db, entry, currency: currency), at: now)
        }
    }

    /// One-person details; the name is read even when the employee left the crew.
    static func details(_ db: Database, _ entry: LabourEntry, currency: CurrencyCode) throws -> [String: String] {
        let name = try String.fetchOne(db, sql: "SELECT name FROM employees WHERE id = ?", arguments: [entry.employeeId.dbKey]) ?? ""
        return ["currency": currency.rawValue, "names": name, "people": "1", "total": entry.cost.storageString, "workDate": entry.workDate.storageString]
    }
}
```

`LabourEntryRecord` stores `days` as `"\(days)"`; an unchanged entry re-encodes to the same text, so the no-op comparison holds. `ActivityDescription` treats an empty `names` as plain, which only happens if the employee row is missing.

- [ ] **Step 4: Lint, push, CI green, commit**

```bash
python scripts/lint_sources.py
git add Packages/Domain/Sources/Domain/Repositories Packages/Data
git commit -m "feat(data): add crew and labour repositories with one-transaction batch logging"
git push origin HEAD
```

---

### Task 6: Data — seed through repositories, crew details

**Files:**
- Modify: `Packages/Data/Sources/Data/Seed/SampleData.swift`
- Modify: `Packages/Data/Tests/DataTests/SampleDataTests.swift`

**Interfaces:**
- Consumes: Tasks 4–5 repositories.
- Produces: seed per spec §4 (numbers unchanged; 2 `paymentReceived`, 3 `labourLogged`; crew trades/phones; Mike hourly 31.25).

- [ ] **Step 1: Failing test** — append to `SampleDataTests`:

```swift
    func testSeedRoutesPaymentsAndLabourThroughRepositories() async throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let today = CalendarDate(storage: "2026-10-03")!
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now), today: today)
        let counts = try await db.writer.read { db in
            try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT action, COUNT(*) AS n FROM activity_log WHERE action IN ('paymentReceived', 'labourLogged') GROUP BY action")
                .map { (row: Row) -> (String, Int) in (row["action"], row["n"]) })
        }
        XCTAssertEqual(counts, ["paymentReceived": 2, "labourLogged": 3])
        let mikeJSON = try await db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT details_json FROM activity_log WHERE action = 'labourLogged' AND details_json LIKE '%Mike%'")
        }
        XCTAssertEqual(mikeJSON, #"{"currency":"CAD","names":"Mike","people":"1","total":"2000.00","workDate":"2026-09-23"}"#)
        let depositJSON = try await db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT details_json FROM activity_log WHERE action = 'paymentReceived' AND details_json LIKE '%7600.00%'")
        }
        XCTAssertEqual(depositJSON, #"{"amount":"7600.00","currency":"CAD","item":"schedule.row.deposit","method":"eTransfer"}"#)
        var it = GRDBEmployeeRepository(database: db, clock: .fixed(now)).observeAll(companyId: setup.company.id).makeAsyncIterator()
        let crew = try await XCTUnwrapAsync(try await it.next())
        XCTAssertEqual(crew.map(\.name), ["David", "John", "Mike"])
        XCTAssertEqual(crew.map { $0.trade ?? "" }, ["Labourer", "Drywall", "Carpenter"])
        XCTAssertEqual(crew.map { $0.dailyRate?.storageString ?? "" }, ["200.00", "220.00", "250.00"])
        XCTAssertEqual(crew.last?.hourlyRate?.storageString, "31.25")
        XCTAssertEqual(crew.last?.phone, "416-555-0110")
        await XCTAssertEqualAsync(try await GRDBPaymentRepository(database: db, clock: .fixed(now)).lastUsedMethod(companyId: setup.company.id), .eTransfer)
    }
```

`testSeedMatchesSpecTotals` stays unchanged (outstanding 55,400; collected 26,100; spent 10,685; cash 15,415; 3 labour entries, 3 expenses, 2 payments) and must pass.

- [ ] **Step 2: Implement** — in `SampleData.seedIfEmpty` replace the `employee(_:_:)` helper, the crew list and the raw `database.writer.write { … }` block with:

```swift
        func employee(_ name: String, trade: String, phone: String, _ rate: Int, hourlyCents: Int? = nil) -> Employee {
            Employee(id: UUID(), companyId: company.id, name: name, phone: phone, role: nil, trade: trade,
                     hourlyRate: hourlyCents.map { Money(Decimal($0) / 100, .cad) }, dailyRate: Money(Decimal(rate), .cad),
                     certifications: nil, emergencyContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        }
```

```swift
        let mike = employee("Mike", trade: "Carpenter", phone: "416-555-0110", 250, hourlyCents: 3125)
        let john = employee("John", trade: "Drywall", phone: "647-555-0111", 220)
        let davidW = employee("David", trade: "Labourer", phone: "905-555-0112", 200)
```

(keep `labour(…)`, `expense(…)`, `payment(…)`, `labourEntries`, `expenseRows`, `paymentRows` as they are), then instead of the raw write:

```swift
        let crewRepository = GRDBEmployeeRepository(database: database, clock: clock)
        for e in [mike, john, davidW] { try await crewRepository.create(e) }
        let labourRepository = GRDBLabourRepository(database: database, clock: clock)
        for l in labourEntries { try await labourRepository.create([l], actor: actor) }        // one log per day, as a contractor would enter them
        let paymentRepository = GRDBPaymentRepository(database: database, clock: clock)
        for p in paymentRows { try await paymentRepository.create(p, actor: actor) }
```

Nothing else changes (expenses, custom category, return value).

- [ ] **Step 3: Push, CI green (all Data tests incl. `testSeedMatchesSpecTotals`, all UI tests), commit**

```bash
git add Packages/Data
git commit -m "feat(data): seed crew, labour and payments through their repositories"
git push origin HEAD
```

---

### Task 7: FeatureSupport — requests, labels, activity sentences, carry-overs, 3b strings

**Files:**
- Create: `Packages/Features/Sources/FeatureSupport/PaymentFormRequest.swift` (also `LabourFormRequest`)
- Create: `Packages/Features/Sources/FeatureSupport/PaymentLabels.swift`
- Modify: `Packages/Features/Sources/FeatureSupport/ActivityText.swift`
- Modify: `Packages/Features/Sources/ProjectsFeature/Detail/ActivitySection.swift` (`ActivityEntryRow` uses the row currency)
- Modify: `Packages/Features/Sources/ExpensesFeature/Form/ExpenseFormViewModel.swift` (carry-over b)
- Modify: `App/Resources/Localizable.xcstrings`, `scripts/check_localization.py`

**Interfaces:**
- Consumes: Tasks 1–3 Domain types.
- Produces: `PaymentFormRequest` (`.create(projectId:scheduleItemId:)`, `.edit`), `LabourFormRequest` (`.create(projectId:)`, `.edit`); `PaymentStatus.titleKey/tone`; `PaymentDraftError`/`LabourDraftError`/`EmployeeDraftError` `.name/.messageKey`; `PaymentTitle.text`; `LabourDays.text(_:locale:)`; `ActivityLogEntry.sentence(fallbackCurrency:locale:)`; every 3b catalog key (spec §7). Tasks 8–13 use these.

- [ ] **Step 1: Requests and labels**

```swift
// Packages/Features/Sources/FeatureSupport/PaymentFormRequest.swift
import Foundation

/// Opens the payment form (a sheet) from project detail, a schedule row or Home's attention row.
public enum PaymentFormRequest: Identifiable, Hashable {
    /// `scheduleItemId` nil = "Record payment" (default stage, empty focused amount); set = that stage with its remaining amount.
    case create(projectId: UUID, scheduleItemId: UUID?)
    case edit(UUID)

    public var id: String {
        switch self {
        case .create(let projectId, let item): return "create:" + projectId.uuidString + ":" + (item?.uuidString ?? "")
        case .edit(let id): return "edit:" + id.uuidString
        }
    }
}

/// Opens the labour form (a sheet) from the project's Labour card or list.
public enum LabourFormRequest: Identifiable, Hashable {
    case create(projectId: UUID)
    case edit(UUID)

    public var id: String {
        switch self {
        case .create(let projectId): return "create:" + projectId.uuidString
        case .edit(let id): return "edit:" + id.uuidString
        }
    }
}
```

```swift
// Packages/Features/Sources/FeatureSupport/PaymentLabels.swift
import SwiftUI
import Domain
import DesignSystem

public extension PaymentStatus {
    var titleKey: LocalizedStringKey { LocalizedStringKey("payment.status." + rawValue) }
    var tone: DSTone {
        switch self {
        case .paid: return .success
        case .overdue: return .danger
        case .dueToday, .dueSoon, .partiallyPaid: return .warning
        case .upcoming: return .neutral
        }
    }
}

public extension PaymentDraftError {
    var name: String {
        switch self {
        case .amountMissing: return "amountMissing"
        case .amountNotPositive: return "amountNotPositive"
        }
    }
    var messageKey: LocalizedStringKey { LocalizedStringKey("payment.error." + name) }
}

public extension LabourDraftError {
    var name: String {
        switch self {
        case .noCrewSelected: return "noCrewSelected"
        case .daysMissing: return "daysMissing"
        case .daysNotPositive: return "daysNotPositive"
        case .rateMissing: return "rateMissing"
        case .rateNegative: return "rateNegative"
        }
    }
    var messageKey: LocalizedStringKey { LocalizedStringKey("labour.error." + name) }
}

public extension EmployeeDraftError {
    var name: String {
        switch self {
        case .nameMissing: return "nameMissing"
        case .rateNegative: return "rateNegative"
        }
    }
    var messageKey: LocalizedStringKey { LocalizedStringKey("crew.error." + name) }
}

public extension PaymentTitle {
    /// Stage label (catalog key or user text) or the payment method.
    var text: Text {
        switch self {
        case .item(let label): return RowLabel.text(label)
        case .method(let method): return Text(method.titleKey)
        }
    }
}

public enum LabourDays {
    /// "1 day" / "0.5 days" / "8 days", the number in the app locale.
    public static func text(_ days: Decimal, locale: Locale) -> Text {
        if days == 1 { return Text("labour.days.one") }
        let number = LocaleNumberParser.string(days, locale: locale, fractionDigits: 2)
        return Text("labour.days.count \(number)")
    }
}
```

- [ ] **Step 2: Activity sentences and row currency (carry-over a)**

`ActivityText.swift` — replace the two temporary branches from Task 3 with:

```swift
        case .payment(let action, let title, let amount, let previous):
            let titleText = title.text
            let amountText = money(amount)
            switch action {
            case .paymentUpdated:
                let fromText = money(previous ?? amount)
                return Text("activity.paymentUpdated \(titleText) \(fromText) \(amountText)")
            case .paymentDeleted:
                return Text("activity.paymentDeleted \(amountText) \(titleText)")
            default:
                return Text("activity.paymentReceived \(amountText) \(titleText)")
            }
        case .labour(let action, let names, let total, let previous):
            let totalText = money(total)
            switch action {
            case .labourUpdated:
                let fromText = money(previous ?? total)
                return Text("activity.labourUpdated \(names) \(fromText) \(totalText)")
            case .labourDeleted:
                return Text("activity.labourDeleted \(names) \(totalText)")
            default:
                return Text("activity.labourLogged \(names) \(totalText)")
            }
```

and append to the file:

```swift
public extension ActivityLogEntry {
    /// The localized sentence; amounts use the currency written with the row (3b money rows), else `fallbackCurrency`.
    func sentence(fallbackCurrency: CurrencyCode, locale: Locale) -> Text {
        let currency = ActivityDescription.currency(for: self) ?? fallbackCurrency
        return ActivityDescription.detail(for: self).text(currency: currency.rawValue, locale: locale)
    }
}
```

`ActivitySection.swift` — in `ActivityEntryRow.body` replace `title: ActivityDescription.detail(for: entry).text(currency: currency.rawValue, locale: locale)` with `title: entry.sentence(fallbackCurrency: currency, locale: locale)`.

- [ ] **Step 3: Carry-over b** — `ExpenseFormViewModel.start()`, edit-load `do/catch`:

```swift
            } catch is CancellationError {
                return                                           // the task was cancelled (form closing): no alert, no loadFailed
            } catch { loadFailed = true; alertKey = "expense.error.saveFailed"; return }
```

- [ ] **Step 4: Strings** — run once from the repo root (keeps the catalog's insertion order and 2-space format):

```bash
python - <<'EOF'
import json, pathlib
path = pathlib.Path("App/Resources/Localizable.xcstrings")
catalog = json.loads(path.read_text(encoding="utf-8"))
S = catalog["strings"]
def put(key, en, vi):
    S[key] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": en}},
                                "vi": {"stringUnit": {"state": "translated", "value": vi}}}}
pairs = {
 "keyboard.done": ("Done", "Xong"),
 "attention.record": ("Record", "Ghi nhận"),
 "detail.payments.title": ("Payments", "Thanh toán"),
 "detail.payments.add": ("Record payment", "Ghi thanh toán"),
 "detail.payments.empty": ("No payments yet", "Chưa có thanh toán"),
 "detail.payments.notLinked": ("Not linked to a stage", "Không gắn đợt"),
 "detail.payments.unallocated %@": ("Not linked to a stage: %@", "Không gắn đợt: %@"),
 "payment.new.title": ("Record payment", "Ghi thanh toán"),
 "payment.edit.title": ("Edit payment", "Sửa thanh toán"),
 "payment.amount": ("Amount received", "Số tiền nhận"),
 "payment.chip.remaining %@": ("Remaining %@", "Còn lại %@"),
 "payment.chip.full %@": ("Full stage %@", "Cả đợt %@"),
 "payment.chip.outstanding %@": ("Balance owing %@", "Còn phải thu %@"),
 "payment.overpay %@": ("%@ more than what is left on this stage. The stage will show as paid; the extra still counts as collected.",
                        "Nhiều hơn phần còn lại của đợt %@. Đợt sẽ hiện là đã trả; phần dư vẫn tính vào đã thu."),
 "payment.items": ("Applies to", "Cho đợt"),
 "payment.item.none": ("Not linked to a stage", "Không gắn đợt nào"),
 "payment.item.left %@": ("%@ left", "Còn %@"),
 "payment.date": ("Date received", "Ngày nhận"),
 "payment.method": ("Method", "Cách trả"),
 "payment.notes": ("Notes", "Ghi chú"),
 "payment.save": ("Save payment", "Lưu thanh toán"),
 "payment.delete": ("Delete payment", "Xóa thanh toán"),
 "payment.delete.title": ("Delete this payment?", "Xóa thanh toán này?"),
 "payment.delete.message": ("It will no longer count as collected.", "Khoản này sẽ không còn tính vào đã thu."),
 "payment.delete.confirm": ("Delete", "Xóa"),
 "payment.error.amountMissing": ("Enter the amount", "Nhập số tiền"),
 "payment.error.amountNotPositive": ("The amount must be more than 0", "Số tiền phải lớn hơn 0"),
 "payment.error.gone": ("This payment or its project no longer exists.", "Thanh toán hoặc dự án này không còn tồn tại."),
 "payment.error.incomplete": ("Fill the required fields.", "Điền các ô bắt buộc."),
 "payment.error.saveFailed": ("Could not save the payment. Try again.", "Không lưu được thanh toán. Thử lại."),
 "payment.error.load": ("Could not load the project.", "Không tải được dự án."),
 "detail.labour.title": ("Labour", "Labour"),
 "detail.labour.add": ("Log labour", "Ghi công"),
 "detail.labour.empty": ("No labour logged yet", "Chưa ghi công"),
 "detail.labour.all": ("See all", "Xem tất cả"),
 "detail.labour.total %@ %@": ("Total: %1$@ · %2$@", "Tổng: %1$@ · %2$@"),
 "labour.list.title": ("Labour", "Labour"),
 "labour.new.title": ("Log labour", "Ghi công"),
 "labour.edit.title": ("Edit labour", "Sửa công"),
 "labour.date": ("Date", "Ngày"),
 "labour.days": ("Days", "Số ngày"),
 "labour.days.hint": ("Same for everyone selected. Half a day = 0.5.", "Áp dụng cho mọi người đã chọn. Nửa ngày = 0,5."),
 "labour.days.minus": ("Half a day less", "Bớt nửa ngày"),
 "labour.days.plus": ("Half a day more", "Thêm nửa ngày"),
 "labour.days.one": ("1 day", "1 ngày"),
 "labour.days.count %@": ("%@ days", "%@ ngày"),
 "labour.crew": ("Crew", "Crew"),
 "labour.rate": ("Daily rate", "Rate mỗi ngày"),
 "labour.rate.perDay %@": ("%@/day", "%@/ngày"),
 "labour.cost %@": ("= %@", "= %@"),
 "labour.already %@": ("Already logged %@ on this day", "Đã ghi %@ trong ngày này"),
 "labour.row.detail %@ %@": ("%1$@ × %2$@", "%1$@ × %2$@"),
 "labour.unknownPerson": ("Former crew member", "Người cũ"),
 "labour.notes": ("Notes", "Ghi chú"),
 "labour.total": ("Total", "Tổng"),
 "labour.save": ("Log labour", "Ghi công"),
 "labour.delete": ("Delete entry", "Xóa dòng công"),
 "labour.delete.title": ("Delete this labour entry?", "Xóa dòng công này?"),
 "labour.delete.message": ("It will no longer count toward labour cost.", "Dòng này sẽ không còn tính vào chi phí Labour."),
 "labour.delete.confirm": ("Delete", "Xóa"),
 "labour.error.noCrewSelected": ("Pick at least one person", "Chọn ít nhất một người"),
 "labour.error.daysMissing": ("Enter the days", "Nhập số ngày"),
 "labour.error.daysNotPositive": ("Days must be more than 0", "Số ngày phải lớn hơn 0"),
 "labour.error.rateMissing": ("Enter a daily rate", "Nhập rate mỗi ngày"),
 "labour.error.rateNegative": ("The rate cannot be negative", "Rate không được âm"),
 "labour.error.gone": ("This entry, its project or the person no longer exists.", "Dòng công, dự án hoặc người này không còn tồn tại."),
 "labour.error.incomplete": ("Fill the required fields.", "Điền các ô bắt buộc."),
 "labour.error.saveFailed": ("Could not save the labour. Try again.", "Không lưu được công. Thử lại."),
 "labour.error.load": ("Could not load the crew or labour.", "Không tải được crew hoặc công."),
 "crew.title": ("Crew", "Crew"),
 "crew.add": ("Add crew member", "Thêm người"),
 "crew.empty.title": ("No crew yet", "Chưa có crew"),
 "crew.empty.message": ("Add the people you pay by the day. Their daily rate fills in when you log labour.",
                        "Thêm những người bạn trả công theo ngày. Rate mỗi ngày sẽ tự điền khi ghi công."),
 "crew.new.title": ("New crew member", "Người mới"),
 "crew.edit.title": ("Edit crew member", "Sửa thông tin"),
 "crew.name": ("Name", "Tên"),
 "crew.trade": ("Trade (e.g. Carpenter)", "Nghề (vd. Carpenter)"),
 "crew.phone": ("Phone", "Điện thoại"),
 "crew.dailyRate": ("Daily rate", "Rate mỗi ngày"),
 "crew.dailyRate.hint": ("Labour is logged by the day; this rate fills in automatically.", "Công được ghi theo ngày; rate này tự điền khi ghi công."),
 "crew.hourlyRate": ("Hourly rate (optional)", "Rate theo giờ (không bắt buộc)"),
 "crew.dailyFromHourly %@": ("Use 8 h × hourly = %@", "Dùng 8 giờ × rate giờ = %@"),
 "crew.notes": ("Notes", "Ghi chú"),
 "crew.rate.hourly %@": ("%@/h", "%@/giờ"),
 "crew.noRate": ("No daily rate", "Chưa có rate"),
 "crew.delete": ("Remove from crew", "Xóa khỏi crew"),
 "crew.delete.title": ("Remove this person?", "Xóa người này?"),
 "crew.delete.message": ("Labour already logged for them stays in your projects.", "Công đã ghi cho người này vẫn được giữ trong các dự án."),
 "crew.delete.confirm": ("Remove", "Xóa"),
 "crew.error.nameMissing": ("Enter a name", "Nhập tên"),
 "crew.error.rateNegative": ("Rates cannot be negative", "Rate không được âm"),
 "crew.error.gone": ("This person no longer exists.", "Người này không còn tồn tại."),
 "crew.error.saveFailed": ("Could not save. Try again.", "Không lưu được. Thử lại."),
 "crew.error": ("Could not load the crew.", "Không tải được crew."),
 "more.crew": ("Crew", "Crew"),
 "activity.paymentReceived %@ %@": ("Payment received: %1$@ — %2$@", "Đã nhận thanh toán: %1$@ — %2$@"),
 "activity.paymentUpdated %@ %@ %@": ("Payment %1$@: %2$@ → %3$@", "Thanh toán %1$@: %2$@ → %3$@"),
 "activity.paymentDeleted %@ %@": ("Payment deleted: %1$@ — %2$@", "Đã xóa thanh toán: %1$@ — %2$@"),
 "activity.labourLogged %@ %@": ("Labour: %1$@ — %2$@", "Labour: %1$@ — %2$@"),
 "activity.labourUpdated %@ %@ %@": ("Labour %1$@: %2$@ → %3$@", "Labour %1$@: %2$@ → %3$@"),
 "activity.labourDeleted %@ %@": ("Labour deleted: %1$@ — %2$@", "Đã xóa Labour: %1$@ — %2$@"),
 "home.group.workDone": ("Work done", "Xong việc"),                     # carry-over d (existing key, new values)
}
for key, (en, vi) in pairs.items(): put(key, en, vi)
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(len(pairs), "keys written")
EOF
```

`scripts/check_localization.py` — after the `ExpenseDraftError` line add:

```python
    for name in enum_cases(DOMAIN / "Payments/PaymentDraft.swift", "PaymentDraftError"): generated.add(f"payment.error.{name}")
    for name in enum_cases(DOMAIN / "Labour/LabourDraft.swift", "LabourDraftError"): generated.add(f"labour.error.{name}")
    for name in enum_cases(DOMAIN / "Crew/EmployeeDraft.swift", "EmployeeDraftError"): generated.add(f"crew.error.{name}")
```

Run `python scripts/check_localization.py` and `python scripts/lint_sources.py` — 0 errors. Check `git diff --stat App/Resources/Localizable.xcstrings` shows only additions plus the two `home.group.workDone` values (if `json.dumps` reformats unrelated lines, the original file was written with the same `indent=2, ensure_ascii=False` settings by 3a; any other diff means stop and write the keys by hand).

- [ ] **Step 5: Push, CI green, commit**

```bash
git add Packages/Features App/Resources/Localizable.xcstrings scripts/check_localization.py
git commit -m "feat(features): add payment and labour labels, activity sentences in the row currency and 3b strings"
git push origin HEAD
```

---

### Task 8: PaymentsFeature — payment form

**Files:**
- Modify: `Packages/Features/Package.swift` (target + product `PaymentsFeature`)
- Create: `Packages/Features/Sources/PaymentsFeature/PaymentFormViewModel.swift`
- Create: `Packages/Features/Sources/PaymentsFeature/PaymentFormView.swift`

**Interfaces:**
- Consumes: `PaymentRepository`, `InsightsRepository.observeProject`, `PaymentDraft`, `PaymentFormContext`, Task 7 labels/requests, DesignSystem `MoneyField`, `ChoiceChips`, `PrimaryButton`, `Card`, `StatusBadge`.
- Produces: `PaymentFormViewModel(request:companyId:currency:paymentRepository:insightsRepository:actor:today:)`, `PaymentFormView(viewModel:onClose:)`. Task 12 wires them.

- [ ] **Step 1: Package** — in `Packages/Features/Package.swift` add `"PaymentsFeature"` to the `Features` library's `targets` list and

```swift
        .target(name: "PaymentsFeature", dependencies: featureDeps, path: "Sources/PaymentsFeature"),
```

- [ ] **Step 2: View model**

```swift
// Packages/Features/Sources/PaymentsFeature/PaymentFormViewModel.swift
import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

@Observable
@MainActor
public final class PaymentFormViewModel {
    public var draft: PaymentDraft
    public private(set) var snapshot: ProjectInsightsInputs.Snapshot?
    public private(set) var original: Payment?
    /// Stays true after a successful save/delete so a second tap during the dismissal cannot write again.
    public private(set) var isSaving = false
    public private(set) var showErrors = false
    /// The payment or its project could not be loaded: the form closes after the alert.
    public private(set) var loadFailed = false
    public var alertKey: LocalizedStringKey?

    public let request: PaymentFormRequest
    public let currency: CurrencyCode
    private let companyId: UUID
    private let paymentRepository: any PaymentRepository
    private let insightsRepository: any InsightsRepository
    private let actor: ActivityActor
    private let today: CalendarDate
    private var didApplyDefaults = false
    private var methodTouched = false
    private var didFinish = false

    public init(request: PaymentFormRequest, companyId: UUID, currency: CurrencyCode, paymentRepository: any PaymentRepository,
                insightsRepository: any InsightsRepository, actor: ActivityActor, today: CalendarDate) {
        self.request = request; self.companyId = companyId; self.currency = currency
        self.paymentRepository = paymentRepository; self.insightsRepository = insightsRepository; self.actor = actor; self.today = today
        self.draft = PaymentDraft(paidOn: today, method: PaymentDraft.defaultMethod(lastUsed: nil))
    }

    public var isEditing: Bool { if case .edit = request { return true } else { return false } }
    /// Keyboard up only for "Record payment" without a stage (spec §2 "Lối vào payment").
    public var focusAmount: Bool {
        if case .create(_, let item) = request { return item == nil }
        return false
    }
    private var projectId: UUID? {
        if case .create(let id, _) = request { return id }
        return original?.projectId
    }

    /// Bind to `.task`: loads the edited payment once, remembers the last method, then keeps the project live.
    public func start() async {
        if case .edit(let id) = request, original == nil {
            guard !loadFailed else { return }
            do {
                guard let payment = try await paymentRepository.get(id: id) else { loadFailed = true; alertKey = "payment.error.gone"; return }
                original = payment
                draft = PaymentDraft(editing: payment)
            } catch is CancellationError {
                return
            } catch { loadFailed = true; alertKey = "payment.error.load"; return }
        }
        if !isEditing, !didApplyDefaults {
            let last = try? await paymentRepository.lastUsedMethod(companyId: companyId)
            if !methodTouched { draft.method = PaymentDraft.defaultMethod(lastUsed: last ?? nil) }
        }
        guard let projectId else { return }
        do {
            for try await value in insightsRepository.observeProject(id: projectId) {
                guard let value else {
                    snapshot = nil
                    if !didFinish { loadFailed = true; alertKey = "payment.error.gone" }
                    return
                }
                snapshot = value
                applyDefaultsOnce()
            }
        } catch is CancellationError {
        } catch { loadFailed = true; alertKey = "payment.error.load" }
    }

    /// First snapshot only: the stage and amount implied by the entry point.
    private func applyDefaultsOnce() {
        guard !didApplyDefaults else { return }
        didApplyDefaults = true
        guard case .create(_, let itemId) = request else { return }
        if let itemId {
            guard let option = options.first(where: { $0.id == itemId }) else { return }   // stage deleted meanwhile: stays unlinked
            draft.scheduleItemId = itemId
            if option.remaining.amount > 0 { draft.amount = option.remaining.amount }
        } else {
            draft.scheduleItemId = PaymentFormContext.defaultItemId(options)
        }
    }

    // MARK: Derived

    public var projectName: String? { snapshot?.project.name }
    public var options: [PaymentItemOption] {
        guard let snapshot else { return [] }
        return PaymentFormContext.options(items: snapshot.scheduleItems, payments: snapshot.payments, excluding: original?.id, today: today, currency: currency)
    }
    public var selectedOption: PaymentItemOption? { draft.scheduleItemId.flatMap { id in options.first { $0.id == id } } }
    public var outstanding: Money? {
        snapshot.flatMap { PaymentFormContext.outstanding(project: $0.project, payments: $0.payments, excluding: original?.id) }
    }
    public var suggestions: [PaymentSuggestion] { PaymentFormContext.suggestions(option: selectedOption, outstanding: outstanding) }
    public var overpayment: Money? { PaymentFormContext.overpayment(amount: draft.amount, option: selectedOption) }
    public var errors: [PaymentDraftError] { draft.errors }
    public var canSubmit: Bool { !isSaving && snapshot != nil && !(isEditing && original == nil) }

    // MARK: Input

    public func selectMethod(_ method: PaymentMethod) { methodTouched = true; draft.method = method }
    public func selectItem(_ id: UUID?) { draft.scheduleItemId = id }
    public func apply(_ suggestion: PaymentSuggestion) { draft.amount = suggestion.money.amount }

    // MARK: Writes

    public func save() async -> Bool {
        guard !(isEditing && original == nil), !didFinish else { return false }
        showErrors = true
        guard draft.canSave, !isSaving, let projectId = snapshot?.project.id else { return false }
        isSaving = true
        do {
            if let original {
                try await paymentRepository.update(try draft.apply(to: original, now: Date()), actor: actor)
            } else {
                try await paymentRepository.create(try draft.makePayment(id: UUID(), companyId: companyId, projectId: projectId, currency: currency, now: Date()), actor: actor)
            }
            didFinish = true
            return true
        } catch {
            isSaving = false
            alertKey = Self.key(for: error)
            return false
        }
    }

    public func delete() async -> Bool {
        guard let original, !isSaving, !didFinish else { return false }
        isSaving = true
        do {
            try await paymentRepository.softDelete(id: original.id, actor: actor)
            didFinish = true
            return true
        } catch {
            isSaving = false
            alertKey = Self.key(for: error)
            return false
        }
    }

    static func key(for error: Error) -> LocalizedStringKey {
        switch error as? DomainError {
        case .notFound?: return "payment.error.gone"
        case .currencyMismatch?: return "error.currencyMismatch"
        case .incompletePayment?, .invalidPaymentAmount?: return "payment.error.incomplete"
        default: return "payment.error.saveFailed"
        }
    }
}
```

`try? await …lastUsedMethod` yields `PaymentMethod??` only before Swift 5 (SE-0230 flattens it); `last ?? nil` keeps it explicit and compiles either way.

- [ ] **Step 3: View**

```swift
// Packages/Features/Sources/PaymentsFeature/PaymentFormView.swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Record or edit one customer payment (spec §5.2). The project is fixed by the entry point; the amount is the only required field.
public struct PaymentFormView: View {
    @Bindable private var viewModel: PaymentFormViewModel
    private let onClose: () -> Void
    @State private var confirmDelete = false
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    public init(viewModel: PaymentFormViewModel, onClose: @escaping () -> Void) { self.viewModel = viewModel; self.onClose = onClose }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    if let name = viewModel.projectName {
                        Label { Text(verbatim: name) } icon: { Image(systemName: "folder") }
                            .font(DSTypography.callout)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("payment_project")
                    }
                    amountCard
                    if !viewModel.options.isEmpty { itemsCard }
                    Card {
                        DatePicker("payment.date", selection: Binding(get: { viewModel.draft.paidOn.noonDate(in: timeZone) },
                                                                     set: { viewModel.draft.paidOn = CalendarDate($0, timeZone: timeZone) }),
                                   displayedComponents: .date)
                            .accessibilityIdentifier("payment_date")
                    }
                    Card {
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            Text("payment.method").font(DSTypography.headline)
                            ChoiceChips(options: PaymentDraft.methodOrder,
                                        selection: Binding(get: { viewModel.draft.method }, set: { if let m = $0 { viewModel.selectMethod(m) } }),
                                        text: { Text($0.titleKey) }, identifier: { "payment_method_" + $0.rawValue })
                                .padding(.horizontal, -DSSpacing.lg)
                        }
                    }
                    Card {
                        TextField("payment.notes", text: $viewModel.draft.notes, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityIdentifier("payment_notes")
                    }
                    if viewModel.isEditing {
                        Button("payment.delete", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity, minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("payment_delete")
                    }
                }
                .padding(DSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DSColor.background)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton("payment.save", systemImage: "checkmark") { Task { if await viewModel.save() { onClose() } } }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("payment_save")
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.sm)
                    .background(DSColor.background)
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sheet.cancel", action: onClose).accessibilityIdentifier("payment_cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("keyboard.done") { KeyboardDismiss.dismiss() }.accessibilityIdentifier("payment_keyboard_done")
                }
            }
            .task { await viewModel.start() }
            .confirmationDialog("payment.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("payment.delete.confirm", role: .destructive) { Task { if await viewModel.delete() { onClose() } } }
                    .accessibilityIdentifier("payment_delete_confirm")
                Button("sheet.cancel", role: .cancel) {}
            } message: {
                Text("payment.delete.message")
            }
            .alert(viewModel.alertKey ?? "payment.error.saveFailed",
                   isPresented: Binding(get: { viewModel.alertKey != nil }, set: { if !$0 { viewModel.alertKey = nil } })) {
                Button("sheet.ok") { if viewModel.loadFailed { onClose() } }
            }
        }
    }

    // MARK: Sections

    private var amountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                MoneyField("payment.amount", amount: $viewModel.draft.amount, currencyCode: viewModel.currency.rawValue, autoFocus: viewModel.focusAmount)
                    .accessibilityIdentifier("payment_amount")
                if !viewModel.suggestions.isEmpty {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(viewModel.suggestions, id: \.self) { suggestion in
                            Button { viewModel.apply(suggestion) } label: { suggestionText(suggestion).font(DSTypography.callout) }
                                .buttonStyle(.bordered)
                                .frame(minHeight: DSSpacing.minTouch)
                                .accessibilityIdentifier(suggestionIdentifier(suggestion))
                        }
                    }
                }
                if let extra = viewModel.overpayment {
                    Label { Text("payment.overpay \(money(extra))") } icon: { Image(systemName: "info.circle") }
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("payment_overpay_notice")
                }
                errorText(.amountMissing)
                errorText(.amountNotPositive)
            }
        }
    }

    private var itemsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("payment.items").font(DSTypography.headline)
                ForEach(viewModel.options) { option in
                    itemRow(selected: viewModel.draft.scheduleItemId == option.id, identifier: "payment_item_\(option.item.sortOrder)",
                            action: { viewModel.selectItem(option.id) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            RowLabel.text(option.item.label).font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                            Text("payment.item.left \(money(option.remaining))").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                        }
                        Spacer()
                        StatusBadge(option.status.titleKey, tone: option.status.tone)
                    }
                }
                itemRow(selected: viewModel.draft.scheduleItemId == nil, identifier: "payment_item_none", action: { viewModel.selectItem(nil) }) {
                    Text("payment.item.none").font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("payment_items")
    }

    private func itemRow<Content: View>(selected: Bool, identifier: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? DSColor.accent : DSColor.textSecondary)
                content()
            }
            .frame(minHeight: DSSpacing.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    // MARK: Helpers

    private var titleKey: LocalizedStringKey { viewModel.isEditing ? "payment.edit.title" : "payment.new.title" }

    private func suggestionText(_ suggestion: PaymentSuggestion) -> Text {
        let amount = money(suggestion.money)
        switch suggestion {
        case .remaining: return Text("payment.chip.remaining \(amount)")
        case .fullItem: return Text("payment.chip.full \(amount)")
        case .outstanding: return Text("payment.chip.outstanding \(amount)")
        }
    }

    private func suggestionIdentifier(_ suggestion: PaymentSuggestion) -> String {
        switch suggestion {
        case .remaining: return "payment_chip_remaining" // lint:allow-string
        case .fullItem: return "payment_chip_full" // lint:allow-string
        case .outstanding: return "payment_chip_outstanding" // lint:allow-string
        }
    }

    @ViewBuilder
    private func errorText(_ error: PaymentDraftError) -> some View {
        if viewModel.showErrors && viewModel.errors.contains(error) {
            Text(error.messageKey)
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.danger)
                .accessibilityIdentifier("payment_error_" + error.name)
        }
    }

    private func money(_ money: Money) -> String { MoneyFormat.string(money.amount, currencyCode: money.currency.rawValue, locale: locale) }
}
```

- [ ] **Step 4: Lint, push, CI green (the target builds with the app), commit**

```bash
python scripts/check_localization.py && python scripts/lint_sources.py
git add Packages/Features
git commit -m "feat(payments): add the payment form with stage choice, amount chips and method memory"
git push origin HEAD
```

---

### Task 9: CrewFeature — crew list and crew form

**Files:**
- Modify: `Packages/Features/Package.swift` (target + product `CrewFeature`)
- Create: `Packages/Features/Sources/CrewFeature/Crew/CrewListViewModel.swift`
- Create: `Packages/Features/Sources/CrewFeature/Crew/CrewListView.swift` (also `CrewRowView`)
- Create: `Packages/Features/Sources/CrewFeature/Crew/CrewFormSheet.swift`

**Interfaces:**
- Consumes: `EmployeeRepository`, `EmployeeDraft`, Task 7 labels.
- Produces: `CrewListViewModel(employeeRepository:companyId:currency:)` with `create/update/delete -> LocalizedStringKey?` and `static key(for:)`; `CrewListView(viewModel:)`; `CrewFormSheet(employee:currency:onSave:onDelete:onCancel:)`. Tasks 10, 12 use these.

- [ ] **Step 1: Package** — add `"CrewFeature"` to the `Features` library's `targets` and

```swift
        .target(name: "CrewFeature", dependencies: featureDeps, path: "Sources/CrewFeature"),
```

- [ ] **Step 2: View model**

```swift
// Packages/Features/Sources/CrewFeature/Crew/CrewListViewModel.swift
import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class CrewListViewModel {
    public private(set) var employees: [Employee] = []
    public private(set) var isLoaded = false
    public var errorKey: LocalizedStringKey?
    public let currency: CurrencyCode
    private let companyId: UUID
    private let repository: any EmployeeRepository

    public init(employeeRepository: any EmployeeRepository, companyId: UUID, currency: CurrencyCode) {
        self.repository = employeeRepository; self.companyId = companyId; self.currency = currency
    }

    public func start() async {
        do {
            for try await value in repository.observeAll(companyId: companyId) { employees = value; isLoaded = true }
        } catch is CancellationError {
        } catch { errorKey = "crew.error" }
    }

    public func create(_ draft: EmployeeDraft) async -> LocalizedStringKey? {
        await run { try await self.repository.create(try draft.makeEmployee(id: UUID(), companyId: self.companyId, currency: self.currency, now: Date())) }
    }
    public func update(_ employee: Employee, with draft: EmployeeDraft) async -> LocalizedStringKey? {
        await run { try await self.repository.update(try draft.apply(to: employee, currency: self.currency, now: Date())) }
    }
    public func delete(_ id: UUID) async -> LocalizedStringKey? { await run { try await self.repository.softDelete(id: id) } }

    private func run(_ work: () async throws -> Void) async -> LocalizedStringKey? {
        do { try await work(); return nil } catch { return Self.key(for: error) }
    }

    public static func key(for error: Error) -> LocalizedStringKey {
        switch error as? DomainError {
        case .emptyName?: return "crew.error.nameMissing"
        case .negativeAmount?: return "crew.error.rateNegative"
        case .notFound?: return "crew.error.gone"
        default: return "crew.error.saveFailed"
        }
    }
}
```

- [ ] **Step 3: Views**

```swift
// Packages/Features/Sources/CrewFeature/Crew/CrewListView.swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// More → Crew: live crew by name; tap to edit, "+" to add (spec §5.4).
public struct CrewListView: View {
    @Bindable var viewModel: CrewListViewModel
    @State private var editing: EditTarget?

    enum EditTarget: Identifiable {
        case new
        case existing(Employee)
        var id: String {
            switch self {
            case .new: return "new" // lint:allow-string
            case .existing(let employee): return employee.id.uuidString
            }
        }
    }

    public init(viewModel: CrewListViewModel) { self.viewModel = viewModel }

    public var body: some View {
        Group {
            if viewModel.isLoaded && viewModel.employees.isEmpty {
                VStack(spacing: DSSpacing.lg) {
                    EmptyState(systemImage: "person.2", title: "crew.empty.title", message: "crew.empty.message")
                    PrimaryButton("crew.add", systemImage: "plus") { editing = .new }
                        .accessibilityIdentifier("crew_empty_add")
                        .padding(.horizontal, DSSpacing.lg)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("crew_empty")
            } else {
                List {
                    ForEach(Array(viewModel.employees.enumerated()), id: \.element.id) { index, employee in
                        Button { editing = .existing(employee) } label: { CrewRowView(employee: employee) }
                            .accessibilityIdentifier("crew_row_\(index)")
                    }
                }
                .accessibilityIdentifier("crew_list")
            }
        }
        .background(DSColor.background)
        .navigationTitle("crew.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Label("crew.add", systemImage: "plus") }.accessibilityIdentifier("crew_add")
            }
        }
        .task { await viewModel.start() }
        .sheet(item: $editing) { target in
            switch target {
            case .new:
                CrewFormSheet(employee: nil, currency: viewModel.currency,
                              onSave: { draft in
                                  let error = await viewModel.create(draft)
                                  if error == nil { editing = nil }
                                  return error
                              },
                              onDelete: nil, onCancel: { editing = nil })
            case .existing(let employee):
                CrewFormSheet(employee: employee, currency: viewModel.currency,
                              onSave: { draft in
                                  let error = await viewModel.update(employee, with: draft)
                                  if error == nil { editing = nil }
                                  return error
                              },
                              onDelete: {
                                  let error = await viewModel.delete(employee.id)
                                  if error == nil { editing = nil }
                                  return error
                              },
                              onCancel: { editing = nil })
            }
        }
        .alert(viewModel.errorKey ?? "crew.error", isPresented: Binding(get: { viewModel.errorKey != nil }, set: { if !$0 { viewModel.errorKey = nil } })) {
            Button("sheet.ok") {}
        }
    }
}

/// Name, trade, "$250.00/day" (or "No daily rate"), "$31.25/h" when set.
struct CrewRowView: View {
    let employee: Employee
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: employee.name).font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                if let trade = employee.trade { Text(verbatim: trade).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let daily = employee.dailyRate {
                    Text("labour.rate.perDay \(money(daily))").font(DSTypography.money(.callout)).foregroundStyle(DSColor.textPrimary)
                } else {
                    Text("crew.noRate").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
                if let hourly = employee.hourlyRate {
                    Text("crew.rate.hourly \(money(hourly))").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .frame(minHeight: DSSpacing.minTouch)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func money(_ m: Money) -> String { MoneyFormat.string(m.amount, currencyCode: m.currency.rawValue, locale: locale) }
}
```

```swift
// Packages/Features/Sources/CrewFeature/Crew/CrewFormSheet.swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// New (employee == nil) or existing crew member. Only the name is required; the daily rate pre-fills labour.
public struct CrewFormSheet: View {
    private let employee: Employee?
    private let currency: CurrencyCode
    private let onSave: (EmployeeDraft) async -> LocalizedStringKey?
    private let onDelete: (() async -> LocalizedStringKey?)?
    private let onCancel: () -> Void
    @State private var draft: EmployeeDraft
    @State private var showErrors = false
    @State private var errorKey: LocalizedStringKey?
    @State private var saving = false
    @State private var confirmDelete = false
    @Environment(\.locale) private var locale

    public init(employee: Employee?, currency: CurrencyCode, onSave: @escaping (EmployeeDraft) async -> LocalizedStringKey?,
                onDelete: (() async -> LocalizedStringKey?)?, onCancel: @escaping () -> Void) {
        self.employee = employee; self.currency = currency; self.onSave = onSave; self.onDelete = onDelete; self.onCancel = onCancel
        _draft = State(initialValue: employee.map(EmployeeDraft.init(editing:)) ?? EmployeeDraft())
    }

    private var titleKey: LocalizedStringKey { employee == nil ? "crew.new.title" : "crew.edit.title" }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("crew.name", text: $draft.name).textContentType(.name).accessibilityIdentifier("crew_name")
                    errorText(.nameMissing)
                    TextField("crew.trade", text: $draft.trade).accessibilityIdentifier("crew_trade")
                    TextField("crew.phone", text: $draft.phone).keyboardType(.phonePad).textContentType(.telephoneNumber).accessibilityIdentifier("crew_phone")
                }
                Section {
                    FormRow("crew.dailyRate") {
                        MoneyField("crew.dailyRate", amount: $draft.dailyRate, currencyCode: currency.rawValue).accessibilityIdentifier("crew_daily_rate")
                    }
                    Text("crew.dailyRate.hint").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    FormRow("crew.hourlyRate") {
                        MoneyField("crew.hourlyRate", amount: $draft.hourlyRate, currencyCode: currency.rawValue).accessibilityIdentifier("crew_hourly_rate")
                    }
                    if let daily = draft.dailyFromHourly, daily != draft.dailyRate {
                        Button("crew.dailyFromHourly \(money(daily))") { draft.dailyRate = daily }
                            .accessibilityIdentifier("crew_daily_from_hourly")
                    }
                    errorText(.rateNegative)
                }
                Section {
                    TextField("crew.notes", text: $draft.notes, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("crew_notes")
                }
                if let errorKey {
                    Text(errorKey).foregroundStyle(DSColor.danger).accessibilityIdentifier("crew_error")
                }
                if employee != nil, onDelete != nil {
                    Button("crew.delete", role: .destructive) { confirmDelete = true }.accessibilityIdentifier("crew_delete")
                }
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel", action: onCancel).accessibilityIdentifier("sheet_cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("sheet.save") { Task { await save() } }.disabled(saving).accessibilityIdentifier("crew_save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("keyboard.done") { KeyboardDismiss.dismiss() }
                }
            }
            .confirmationDialog("crew.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("crew.delete.confirm", role: .destructive) { Task { if let onDelete { errorKey = await onDelete() } } }
                    .accessibilityIdentifier("crew_delete_confirm")
                Button("sheet.cancel", role: .cancel) {}
            } message: {
                Text("crew.delete.message")
            }
        }
    }

    private func save() async {
        showErrors = true
        guard draft.canSave, !saving else { return }
        saving = true
        errorKey = await onSave(draft)
        saving = false
    }

    @ViewBuilder
    private func errorText(_ error: EmployeeDraftError) -> some View {
        if showErrors && draft.errors.contains(error) {
            Text(error.messageKey).font(DSTypography.caption).foregroundStyle(DSColor.danger).accessibilityIdentifier("crew_error_" + error.name)
        }
    }

    private func money(_ value: Decimal) -> String { MoneyFormat.string(value, currencyCode: currency.rawValue, locale: locale) }
}
```

- [ ] **Step 4: Lint, push, CI green, commit**

```bash
python scripts/check_localization.py && python scripts/lint_sources.py
git add Packages/Features
git commit -m "feat(crew): add the crew list and crew member form"
git push origin HEAD
```

---

### Task 10: CrewFeature — log labour form

**Files:**
- Create: `Packages/Features/Sources/CrewFeature/Labour/LabourFormViewModel.swift`
- Create: `Packages/Features/Sources/CrewFeature/Labour/LabourFormView.swift`

**Interfaces:**
- Consumes: `LabourRepository`, `EmployeeRepository`, `LabourDraft`, `CrewList`, `EmployeeDraft`, Task 9 `CrewFormSheet`, `CrewListViewModel.key(for:)`, Task 7 labels.
- Produces: `LabourFormViewModel(request:companyId:currency:labourRepository:employeeRepository:actor:today:)` (`PersonRow`, `rows`, `start()`, `startEntries()`, `toggle(_:)`, `addPerson(_:)`, `save()`, `delete()`), `LabourFormView(viewModel:onClose:)`. Tasks 11–12 use these.

- [ ] **Step 1: View model**

```swift
// Packages/Features/Sources/CrewFeature/Labour/LabourFormViewModel.swift
import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

@Observable
@MainActor
public final class LabourFormViewModel {
    /// One selectable person (create: the live crew; edit: the entry's person, even after they left the crew).
    public struct PersonRow: Identifiable, Hashable {
        public let id: UUID
        public let name: String
        public let trade: String?
        public let dailyRate: Money?
    }

    public var draft: LabourDraft
    public private(set) var crew: [Employee] = []
    public private(set) var projectEntries: [LabourEntry] = []
    public private(set) var original: LabourEntry?
    public private(set) var originalPerson: Employee?
    public private(set) var isLoaded = false
    public private(set) var isSaving = false
    public private(set) var showErrors = false
    public private(set) var loadFailed = false
    public var alertKey: LocalizedStringKey?

    public let request: LabourFormRequest
    public let currency: CurrencyCode
    private let companyId: UUID
    private let labourRepository: any LabourRepository
    private let employeeRepository: any EmployeeRepository
    private let actor: ActivityActor
    private var createdCrew: [Employee] = []
    private var didFinish = false

    public init(request: LabourFormRequest, companyId: UUID, currency: CurrencyCode, labourRepository: any LabourRepository,
                employeeRepository: any EmployeeRepository, actor: ActivityActor, today: CalendarDate) {
        self.request = request; self.companyId = companyId; self.currency = currency
        self.labourRepository = labourRepository; self.employeeRepository = employeeRepository; self.actor = actor
        self.draft = LabourDraft(workDate: today)
    }

    public var isEditing: Bool { if case .edit = request { return true } else { return false } }
    private var projectId: UUID? {
        if case .create(let id) = request { return id }
        return original?.projectId
    }

    /// Bind to `.task`: edit loads the entry and its person once; create keeps the crew live.
    public func start() async {
        if case .edit(let id) = request {
            guard original == nil, !loadFailed else { return }
            do {
                guard let entry = try await labourRepository.get(id: id) else { loadFailed = true; alertKey = "labour.error.gone"; return }
                originalPerson = try await employeeRepository.get(id: entry.employeeId, includingDeleted: true)
                original = entry
                draft = LabourDraft(editing: entry)
                isLoaded = true
            } catch is CancellationError {
                return
            } catch { loadFailed = true; alertKey = "labour.error.load" }
            return
        }
        do {
            for try await value in employeeRepository.observeAll(companyId: companyId) { crew = value; isLoaded = true }
        } catch is CancellationError {
        } catch { alertKey = "labour.error.load" }
    }

    /// Second `.task` (create only): this project's entries for the "already logged" notice. A failure only hides the notice.
    public func startEntries() async {
        guard case .create(let projectId) = request else { return }
        do {
            for try await value in labourRepository.observeProject(id: projectId) { projectEntries = value?.entries ?? [] }
        } catch {}
    }

    // MARK: Derived

    public var rows: [PersonRow] {
        if isEditing {
            guard let original else { return [] }
            return [PersonRow(id: original.employeeId, name: originalPerson?.name ?? "", trade: originalPerson?.trade, dailyRate: originalPerson?.dailyRate)]
        }
        let known = crew
        let all = CrewList.ordered(known + createdCrew.filter { c in !known.contains { $0.id == c.id } })
        return all.map { PersonRow(id: $0.id, name: $0.name, trade: $0.trade, dailyRate: $0.dailyRate) }
    }
    public func cost(for id: UUID) -> Money? { draft.cost(for: id, currency: currency) }
    public var total: Money? { draft.total(currency: currency) }
    public var errors: [LabourDraftError] { draft.errors }
    public func alreadyLogged(_ id: UUID) -> Decimal {
        isEditing ? 0 : LabourDraft.alreadyLoggedDays(employeeId: id, on: draft.workDate, entries: projectEntries, excluding: nil)
    }
    public var canSubmit: Bool { !isSaving && !(isEditing && original == nil) }

    // MARK: Input

    public func toggle(_ id: UUID) {
        guard !isEditing, let employee = (crew + createdCrew).first(where: { $0.id == id }) else { return }
        draft.toggle(employee)
    }

    /// "Add crew member" inside the sheet: creates the person and selects them.
    public func addPerson(_ employeeDraft: EmployeeDraft) async -> LocalizedStringKey? {
        do {
            let employee = try employeeDraft.makeEmployee(id: UUID(), companyId: companyId, currency: currency, now: Date())
            try await employeeRepository.create(employee)
            createdCrew.append(employee)
            draft.toggle(employee)
            return nil
        } catch { return CrewListViewModel.key(for: error) }
    }

    // MARK: Writes

    public func save() async -> Bool {
        guard !(isEditing && original == nil), !didFinish else { return false }
        showErrors = true
        guard draft.canSave, !isSaving, let projectId else { return false }
        isSaving = true
        do {
            if let original {
                try await labourRepository.update(try draft.apply(to: original, now: Date()), actor: actor)
            } else {
                try await labourRepository.create(try draft.makeEntries(companyId: companyId, projectId: projectId, currency: currency, now: Date()), actor: actor)
            }
            didFinish = true
            return true
        } catch {
            isSaving = false
            alertKey = Self.key(for: error)
            return false
        }
    }

    public func delete() async -> Bool {
        guard let original, !isSaving, !didFinish else { return false }
        isSaving = true
        do {
            try await labourRepository.softDelete(id: original.id, actor: actor)
            didFinish = true
            return true
        } catch {
            isSaving = false
            alertKey = Self.key(for: error)
            return false
        }
    }

    static func key(for error: Error) -> LocalizedStringKey {
        switch error as? DomainError {
        case .notFound?: return "labour.error.gone"
        case .incompleteLabour?, .invalidLabourDays?: return "labour.error.incomplete"
        case .currencyMismatch?: return "error.currencyMismatch"
        default: return "labour.error.saveFailed"
        }
    }
}
```

- [ ] **Step 2: View**

```swift
// Packages/Features/Sources/CrewFeature/Labour/LabourFormView.swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// "Log labour" for several people at once, or edit one entry (spec §5.5).
public struct LabourFormView: View {
    @Bindable private var viewModel: LabourFormViewModel
    private let onClose: () -> Void
    @State private var addingPerson = false
    @State private var confirmDelete = false
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    public init(viewModel: LabourFormViewModel, onClose: @escaping () -> Void) { self.viewModel = viewModel; self.onClose = onClose }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    Card {
                        DatePicker("labour.date", selection: Binding(get: { viewModel.draft.workDate.noonDate(in: timeZone) },
                                                                    set: { viewModel.draft.workDate = CalendarDate($0, timeZone: timeZone) }),
                                   displayedComponents: .date)
                            .accessibilityIdentifier("labour_date")
                    }
                    daysCard
                    crewCard
                    Card {
                        TextField("labour.notes", text: $viewModel.draft.notes, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("labour_notes")
                    }
                    HStack {
                        Text("labour.total").font(DSTypography.headline)
                        Spacer()
                        Text(verbatim: moneyText(viewModel.total)).font(DSTypography.money(.title3))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("labour_total")
                    if viewModel.isEditing {
                        Button("labour.delete", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity, minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("labour_delete")
                    }
                }
                .padding(DSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DSColor.background)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(saveKey, systemImage: "checkmark") { Task { if await viewModel.save() { onClose() } } }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("labour_save")
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.sm)
                    .background(DSColor.background)
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sheet.cancel", action: onClose).accessibilityIdentifier("labour_cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("keyboard.done") { KeyboardDismiss.dismiss() }.accessibilityIdentifier("labour_keyboard_done")
                }
            }
            .task { await viewModel.start() }
            .task { await viewModel.startEntries() }
            .sheet(isPresented: $addingPerson) {
                CrewFormSheet(employee: nil, currency: viewModel.currency,
                              onSave: { draft in
                                  let error = await viewModel.addPerson(draft)
                                  if error == nil { addingPerson = false }
                                  return error
                              },
                              onDelete: nil, onCancel: { addingPerson = false })
            }
            .confirmationDialog("labour.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("labour.delete.confirm", role: .destructive) { Task { if await viewModel.delete() { onClose() } } }
                    .accessibilityIdentifier("labour_delete_confirm")
                Button("sheet.cancel", role: .cancel) {}
            } message: {
                Text("labour.delete.message")
            }
            .alert(viewModel.alertKey ?? "labour.error.saveFailed",
                   isPresented: Binding(get: { viewModel.alertKey != nil }, set: { if !$0 { viewModel.alertKey = nil } })) {
                Button("sheet.ok") { if viewModel.loadFailed { onClose() } }
            }
        }
    }

    // MARK: Sections

    private var daysCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.sm) {
                    Text("labour.days").font(DSTypography.headline)
                    Spacer()
                    Button { viewModel.draft.stepDays(up: false) } label: { Image(systemName: "minus.circle").font(DSTypography.title) }
                        .frame(minWidth: DSSpacing.minTouch, minHeight: DSSpacing.minTouch)
                        .accessibilityLabel(Text("labour.days.minus"))
                        .accessibilityIdentifier("labour_days_minus")
                    DecimalField("labour.days", value: $viewModel.draft.days)
                        .frame(width: 72)
                        .accessibilityIdentifier("labour_days")
                    Button { viewModel.draft.stepDays(up: true) } label: { Image(systemName: "plus.circle").font(DSTypography.title) }
                        .frame(minWidth: DSSpacing.minTouch, minHeight: DSSpacing.minTouch)
                        .accessibilityLabel(Text("labour.days.plus"))
                        .accessibilityIdentifier("labour_days_plus")
                }
                if !viewModel.isEditing {
                    Text("labour.days.hint").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
                errorText(.daysMissing)
                errorText(.daysNotPositive)
            }
        }
    }

    private var crewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("labour.crew").font(DSTypography.headline)
                    Spacer()
                    if !viewModel.isEditing && !viewModel.rows.isEmpty {
                        Button { addingPerson = true } label: { Label("crew.add", systemImage: "person.badge.plus") }
                            .font(DSTypography.callout)
                            .frame(minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("labour_add_person")
                    }
                }
                if !viewModel.isEditing && viewModel.isLoaded && viewModel.rows.isEmpty {
                    VStack(spacing: DSSpacing.md) {
                        EmptyState(systemImage: "person.2", title: "crew.empty.title", message: "crew.empty.message")
                        SecondaryButton("crew.add", systemImage: "person.badge.plus") { addingPerson = true }
                            .accessibilityIdentifier("labour_add_person")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("labour_empty_crew")
                }
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    personRow(index, row)
                }
                errorText(.noCrewSelected)
                errorText(.rateMissing)
                errorText(.rateNegative)
            }
        }
    }

    @ViewBuilder
    private func personRow(_ index: Int, _ row: LabourFormViewModel.PersonRow) -> some View {
        let selected = viewModel.draft.isSelected(row.id)
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button { viewModel.toggle(row.id) } label: {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? DSColor.accent : DSColor.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        (row.name.isEmpty ? Text("labour.unknownPerson") : Text(verbatim: row.name))
                            .font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                        if let trade = row.trade { Text(verbatim: trade).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                    }
                    Spacer()
                    if let rate = row.dailyRate {
                        Text("labour.rate.perDay \(money(rate))").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                }
                .frame(minHeight: DSSpacing.minTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isEditing)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("labour_person_\(index)")
            if selected {
                HStack(spacing: DSSpacing.sm) {
                    MoneyField("labour.rate", amount: Binding(get: { viewModel.draft.lines.first { $0.employeeId == row.id }?.dailyRate },
                                                              set: { viewModel.draft.setRate($0, for: row.id) }),
                               currencyCode: viewModel.currency.rawValue)
                        .accessibilityIdentifier("labour_rate_\(index)")
                    Text("labour.cost \(moneyText(viewModel.cost(for: row.id)))")
                        .font(DSTypography.money(.callout))
                        .accessibilityIdentifier("labour_cost_\(index)")
                }
                .padding(.leading, DSSpacing.xl)
                if viewModel.showErrors, let error = viewModel.draft.lineError(for: row.id) {
                    Text(error.messageKey).font(DSTypography.caption).foregroundStyle(DSColor.danger)
                        .padding(.leading, DSSpacing.xl)
                        .accessibilityIdentifier("labour_rate_error_\(index)")
                }
                let already = viewModel.alreadyLogged(row.id)
                if already > 0 {
                    Label { Text("labour.already \(LabourDays.text(already, locale: locale))") } icon: { Image(systemName: "exclamationmark.circle") }
                        .font(DSTypography.caption).foregroundStyle(DSColor.warning)
                        .padding(.leading, DSSpacing.xl)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("labour_already_\(index)")
                }
            }
        }
    }

    // MARK: Helpers

    private var titleKey: LocalizedStringKey { viewModel.isEditing ? "labour.edit.title" : "labour.new.title" }
    private var saveKey: LocalizedStringKey { viewModel.isEditing ? "sheet.save" : "labour.save" }

    @ViewBuilder
    private func errorText(_ error: LabourDraftError) -> some View {
        if viewModel.showErrors && viewModel.errors.contains(error) {
            Text(error.messageKey).font(DSTypography.caption).foregroundStyle(DSColor.danger).accessibilityIdentifier("labour_error_" + error.name)
        }
    }

    private func money(_ m: Money) -> String { MoneyFormat.string(m.amount, currencyCode: m.currency.rawValue, locale: locale) }
    private func moneyText(_ m: Money?) -> String { m.map(money) ?? "—" } // lint:allow-string
}
```

`DSTypography.title` is the existing title font token (used by Home); the minus/plus symbols use it so they stay a 44 pt target.

- [ ] **Step 3: Lint, push, CI green, commit**

```bash
python scripts/check_localization.py && python scripts/lint_sources.py
git add Packages/Features
git commit -m "feat(crew): add the multi-person log labour form"
git push origin HEAD
```

---

### Task 11: CrewFeature — Labour card and list

**Files:**
- Create: `Packages/Features/Sources/CrewFeature/Labour/ProjectLabourViewModel.swift`
- Create: `Packages/Features/Sources/CrewFeature/Labour/LabourRowView.swift` (also `LabourDayList`)
- Create: `Packages/Features/Sources/CrewFeature/Labour/ProjectLabourSection.swift`
- Create: `Packages/Features/Sources/CrewFeature/Labour/ProjectLabourListView.swift`

**Interfaces:**
- Consumes: `LabourRepository.observeProject`, `LabourListComposer`, `LabourDays`, `LabourFormRequest`.
- Produces: `ProjectLabourViewModel(labourRepository:projectId:)`, `ProjectLabourSection(viewModel:makeAll:makeForm:)`, `ProjectLabourListView(viewModel:makeForm:)`. Task 12 wires them.

- [ ] **Step 1: Code**

```swift
// Packages/Features/Sources/CrewFeature/Labour/ProjectLabourViewModel.swift
import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class ProjectLabourViewModel {
    public private(set) var list: ProjectLabourList?
    public private(set) var errorKey: LocalizedStringKey?
    public let projectId: UUID
    private let repository: any LabourRepository

    public init(labourRepository: any LabourRepository, projectId: UUID) { self.repository = labourRepository; self.projectId = projectId }

    public func start() async {
        do {
            for try await value in repository.observeProject(id: projectId) {
                list = value.map { LabourListComposer.compose(entries: $0.entries, employees: $0.employees, currency: $0.currency) }
            }
        } catch is CancellationError {
        } catch { errorKey = "labour.error.load" }
    }
}
```

```swift
// Packages/Features/Sources/CrewFeature/Labour/LabourRowView.swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Name, "8 days × $250.00", cost.
struct LabourRowView: View {
    let row: LabourRow
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "person.crop.circle").frame(width: 32, height: 32).foregroundStyle(DSColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                name.font(DSTypography.callout).foregroundStyle(DSColor.textPrimary).lineLimit(1)
                Text("labour.row.detail \(LabourDays.text(row.entry.days, locale: locale)) \(money(row.entry.dailyRate))")
                    .font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
            }
            Spacer()
            MoneyText(amount: row.cost.amount, currencyCode: row.cost.currency.rawValue, style: .callout).foregroundStyle(DSColor.textPrimary)
        }
        .frame(minHeight: DSSpacing.minTouch)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var name: Text { row.employeeName.isEmpty ? Text("labour.unknownPerson") : Text(verbatim: row.employeeName) }
    private func money(_ m: Money) -> String { MoneyFormat.string(m.amount, currencyCode: m.currency.rawValue, locale: locale) }
}

/// Day headers (date + day total) and their rows; a row opens the edit form.
struct LabourDayList: View {
    let sections: [LabourDaySection]
    let onEdit: (UUID) -> Void
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack {
                    DateLabel(section.day.noonDate(in: timeZone))
                    Spacer()
                    MoneyText(amount: section.total.amount, currencyCode: section.total.currency.rawValue, style: .caption)
                }
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail_labour_day_" + section.day.storageString)
                ForEach(section.rows) { row in
                    Button { onEdit(row.id) } label: { LabourRowView(row: row) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("labour_row_" + row.id.uuidString)
                }
            }
        }
    }
}
```

```swift
// Packages/Features/Sources/CrewFeature/Labour/ProjectLabourSection.swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Project detail: labour total, the three latest days, "Log labour", "See all" (spec §5.6).
public struct ProjectLabourSection: View {
    private let viewModel: ProjectLabourViewModel
    private let makeAll: () -> AnyView
    private let makeForm: (LabourFormRequest) -> AnyView
    @State private var formRequest: LabourFormRequest?
    @Environment(\.locale) private var locale

    public init(viewModel: ProjectLabourViewModel, makeAll: @escaping () -> AnyView, makeForm: @escaping (LabourFormRequest) -> AnyView) {
        self.viewModel = viewModel; self.makeAll = makeAll; self.makeForm = makeForm
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("detail.labour.title").font(DSTypography.headline)
                    Spacer()
                    Button { formRequest = .create(projectId: viewModel.projectId) } label: { Label("detail.labour.add", systemImage: "plus") }
                        .font(DSTypography.callout)
                        .frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("detail_labour_add")
                }
                if let list = viewModel.list {
                    if list.sections.isEmpty {
                        Text("detail.labour.empty")
                            .font(DSTypography.callout)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityIdentifier("detail_labour_empty")
                    } else {
                        Text("detail.labour.total \(LabourDays.text(list.totalDays, locale: locale)) \(MoneyFormat.string(list.total.amount, currencyCode: list.total.currency.rawValue, locale: locale))")
                            .font(DSTypography.callout)
                            .accessibilityIdentifier("detail_labour_total")
                        LabourDayList(sections: Array(list.sections.prefix(3)), onEdit: { formRequest = .edit($0) })
                        if list.sections.count > 3 {
                            NavigationLink { makeAll() } label: { Text("detail.labour.all").font(DSTypography.callout) }
                                .frame(minHeight: DSSpacing.minTouch)
                                .accessibilityIdentifier("detail_labour_all")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_labour")
        .task { await viewModel.start() }
        .sheet(item: $formRequest) { request in makeForm(request) }
    }
}
```

```swift
// Packages/Features/Sources/CrewFeature/Labour/ProjectLabourListView.swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// "See all": every day of the project's labour.
public struct ProjectLabourListView: View {
    private let viewModel: ProjectLabourViewModel
    private let makeForm: (LabourFormRequest) -> AnyView
    @State private var formRequest: LabourFormRequest?

    public init(viewModel: ProjectLabourViewModel, makeForm: @escaping (LabourFormRequest) -> AnyView) { self.viewModel = viewModel; self.makeForm = makeForm }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                LabourDayList(sections: viewModel.list?.sections ?? [], onEdit: { formRequest = .edit($0) })
            }
            .padding(DSSpacing.lg)
        }
        .background(DSColor.background)
        .navigationTitle("labour.list.title")
        .accessibilityIdentifier("labour_list")
        .task { await viewModel.start() }
        .sheet(item: $formRequest) { request in makeForm(request) }
    }
}
```

- [ ] **Step 2: Lint, push, CI green, commit**

```bash
python scripts/check_localization.py && python scripts/lint_sources.py
git add Packages/Features
git commit -m "feat(crew): add the project labour card grouped by day and the full labour list"
git push origin HEAD
```

---

### Task 12: Hosts + App wiring

**Files:**
- Modify: `Packages/Features/Sources/ProjectsFeature/Detail/ProjectDetailViewModel.swift` (`payments`)
- Create: `Packages/Features/Sources/ProjectsFeature/Detail/ProjectPaymentsSection.swift` (also `PaymentRowView`)
- Modify: `Packages/Features/Sources/ProjectsFeature/Detail/ProjectDetailView.swift`
- Modify: `Packages/Features/Sources/HomeFeature/HomeView.swift`, `HomeFeature/AttentionListSheet.swift`
- Modify: `Packages/Features/Sources/MoreFeature/MoreView.swift`
- Modify: `App/AppContainer.swift`, `App/Screens.swift`, `App/RootTabView.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `ProjectDetailView(viewModel:makeCustomer:makeActivity:makeExpensesSection:makeLabourSection:makePaymentForm:)`, `HomeView(viewModel:companyName:makeDetail:makeActivity:makeExpenseForm:makePaymentForm:)`, `AttentionListSheet(items:names:onSelect:onRecord:)`, `MoreView(settings:company:showsGallery:makeCustomers:makeCrew:makeCategories:)`; `AppContainer.Ready` gains `paymentRepository`, `employeeRepository`, `labourRepository`; screens `PaymentFormScreen`, `CrewScreen`, `LabourFormScreen`, `ProjectLabourSectionScreen`, `ProjectLabourListScreen`.

- [ ] **Step 1: Project detail**

`ProjectDetailViewModel` — new property `public private(set) var payments: ProjectPaymentList?`; in `startInsights()` right after `insights = …`:

```swift
                payments = value.map { ProjectPaymentListComposer.compose(payments: $0.payments, scheduleItems: $0.scheduleItems, currency: currency) }
```

```swift
// Packages/Features/Sources/ProjectsFeature/Detail/ProjectPaymentsSection.swift
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
```

`ProjectDetailView`:
- stored `private let makeLabourSection: (UUID) -> AnyView`, `private let makePaymentForm: (PaymentFormRequest) -> AnyView`; init parameters after `makeExpensesSection`, both defaulting to `{ _ in AnyView(EmptyView()) }`; `@State private var paymentRequest: PaymentFormRequest?`.
- body: add `.sheet(item: $paymentRequest) { request in makePaymentForm(request) }` next to the other sheets.
- `content(_:)`: between `FinancialSummarySection(…)` and `makeExpensesSection(viewModel.projectId)` insert

```swift
            ProjectPaymentsSection(list: viewModel.payments,
                                   onAdd: { paymentRequest = .create(projectId: viewModel.projectId, scheduleItemId: nil) },
                                   onEdit: { paymentRequest = .edit($0) })
```

  and right after `makeExpensesSection(viewModel.projectId)` add `makeLabourSection(viewModel.projectId)`.
- `scheduleSection`: the row becomes a button (identifier unchanged), using the shared status labels:

```swift
            ForEach(s.scheduleItems) { item in
                let insight = byItem[item.id]
                let status = insight?.status ?? PaymentStatusResolver.status(item: item, paidForItem: .zero(currency), today: viewModel.today)
                Button { paymentRequest = .create(projectId: viewModel.projectId, scheduleItemId: item.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            RowLabel.text(item.label).font(DSTypography.callout)
                            if let due = item.dueDate { DateLabel(due.noonDate(in: timeZone)).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                            if let insight, insight.paid.amount > 0 {
                                let paid = MoneyFormat.string(insight.paid.amount, currencyCode: currency.rawValue, locale: locale)
                                let left = MoneyFormat.string(insight.remaining.amount, currencyCode: currency.rawValue, locale: locale)
                                Text("detail.schedule.paid \(paid) \(left)").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                            }
                        }
                        Spacer()
                        StatusBadge(status.titleKey, tone: status.tone)
                        MoneyText(amount: item.amount.amount, currencyCode: currency.rawValue)
                        Image(systemName: "chevron.right").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    .foregroundStyle(DSColor.textPrimary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("detail.payments.add"))
                .accessibilityIdentifier("detail_schedule_row_\(item.sortOrder)")
            }
```

  and delete the now-unused `private static func tone(_ status: PaymentStatus) -> DSTone` (moved to FeatureSupport in Task 7).

- [ ] **Step 2: Home** — `HomeView`:
- stored `private let makePaymentForm: ((PaymentFormRequest) -> AnyView)?` (init parameter after `makeExpenseForm`, default `nil`); `@State private var paymentRequest: PaymentFormRequest?`, `@State private var pendingPayment: PaymentFormRequest?`.
- attention rows in `content(_:)`:

```swift
                        ForEach(d.attention.prefix(5)) { item in
                            HStack(spacing: DSSpacing.sm) {
                                NavigationLink(value: ProjectRoute.detail(item.projectId)) {
                                    AttentionRow(item: item, projectName: names[item.projectId] ?? "")
                                }
                                .buttonStyle(.plain)
                                if makePaymentForm != nil, let itemId = item.scheduleItemId {
                                    Button { paymentRequest = .create(projectId: item.projectId, scheduleItemId: itemId) } label: {
                                        Text("attention.record").font(DSTypography.callout)
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(minHeight: DSSpacing.minTouch)
                                    .accessibilityIdentifier("attention_record_\(itemId.uuidString)")
                                }
                            }
                        }
```

- the all-attention sheet (opens the form after it is gone) and the payment sheet:

```swift
        .sheet(isPresented: $showAllAttention, onDismiss: {
            if let next = pendingPayment { pendingPayment = nil; paymentRequest = next }
        }) {
            AttentionListSheet(items: viewModel.dashboard?.attention ?? [], names: names,
                               onSelect: { id in showAllAttention = false; pendingDetail = id },
                               onRecord: makePaymentForm == nil ? nil : { item in
                                   guard let itemId = item.scheduleItemId else { return }
                                   pendingPayment = .create(projectId: item.projectId, scheduleItemId: itemId)
                                   showAllAttention = false
                               })
        }
        .sheet(item: $paymentRequest) { request in makePaymentForm?(request) ?? AnyView(EmptyView()) }
```

`AttentionListSheet` — new stored `let onRecord: ((AttentionItem) -> Void)?` after `onSelect`; each list row becomes

```swift
            List(items) { item in
                HStack(spacing: DSSpacing.sm) {
                    Button { onSelect(item.projectId) } label: { AttentionRow(item: item, projectName: names[item.projectId] ?? "") }
                        .buttonStyle(.plain)
                    if let onRecord, let itemId = item.scheduleItemId {
                        Button("attention.record") { onRecord(item) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("attention_record_\(itemId.uuidString)")
                    }
                }
            }
```

(`AttentionListSheet` already imports Domain and DesignSystem; nothing else is needed).

- [ ] **Step 3: More** — `MoreView`: stored `private let makeCrew: () -> AnyView`, init `init(settings:company:showsGallery:makeCustomers:makeCrew:makeCategories:)`; row right after Customers:

```swift
            NavigationLink { makeCrew() } label: { Label("more.crew", systemImage: "person.3") }
                .frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("more_crew")
```

- [ ] **Step 4: App**

`AppContainer.Ready` — after `categoryRepository` declare

```swift
        let paymentRepository: any PaymentRepository
        let employeeRepository: any EmployeeRepository
        let labourRepository: any LabourRepository
```

and in `load()` pass, in the same position of the `Ready(…)` call (after `categoryRepository:`):

```swift
                              paymentRepository: GRDBPaymentRepository(database: database, clock: clock),
                              employeeRepository: GRDBEmployeeRepository(database: database, clock: clock),
                              labourRepository: GRDBLabourRepository(database: database, clock: clock),
```

`Screens.swift` — add `import PaymentsFeature` and `import CrewFeature`, and:

```swift
/// Owns the payment form view model for one create/edit; closes with `dismiss` (presented as a sheet).
struct PaymentFormScreen: View {
    @State private var viewModel: PaymentFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(request: PaymentFormRequest, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: PaymentFormViewModel(request: request, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                              paymentRepository: ready.paymentRepository, insightsRepository: ready.insightsRepository,
                                                              actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName),
                                                              today: TodayProvider.today(timeZone: .current)))
    }

    var body: some View { PaymentFormView(viewModel: viewModel, onClose: { dismiss() }) }
}

struct CrewScreen: View {
    @State private var viewModel: CrewListViewModel

    init(ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: CrewListViewModel(employeeRepository: ready.employeeRepository, companyId: setup.company.id, currency: setup.company.currencyCode))
    }

    var body: some View { CrewListView(viewModel: viewModel) }
}

struct LabourFormScreen: View {
    @State private var viewModel: LabourFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(request: LabourFormRequest, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: LabourFormViewModel(request: request, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                             labourRepository: ready.labourRepository, employeeRepository: ready.employeeRepository,
                                                             actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName),
                                                             today: TodayProvider.today(timeZone: .current)))
    }

    var body: some View { LabourFormView(viewModel: viewModel, onClose: { dismiss() }) }
}

/// Project detail's Labour card (three latest days, "Log labour", "See all").
struct ProjectLabourSectionScreen: View {
    @State private var viewModel: ProjectLabourViewModel
    let projectId: UUID
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(projectId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ProjectLabourViewModel(labourRepository: ready.labourRepository, projectId: projectId))
        self.projectId = projectId; self.ready = ready; self.setup = setup
    }

    var body: some View {
        ProjectLabourSection(viewModel: viewModel,
                             makeAll: { AnyView(ProjectLabourListScreen(projectId: projectId, ready: ready, setup: setup)) },
                             makeForm: { request in AnyView(LabourFormScreen(request: request, ready: ready, setup: setup)) })
    }
}

struct ProjectLabourListScreen: View {
    @State private var viewModel: ProjectLabourViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(projectId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ProjectLabourViewModel(labourRepository: ready.labourRepository, projectId: projectId))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        ProjectLabourListView(viewModel: viewModel, makeForm: { request in AnyView(LabourFormScreen(request: request, ready: ready, setup: setup)) })
    }
}
```

`HomeScreen.body` passes `makePaymentForm: { request in AnyView(PaymentFormScreen(request: request, ready: ready, setup: setup)) }`; `ProjectDetailScreen.body` passes `makeLabourSection: { id in AnyView(ProjectLabourSectionScreen(projectId: id, ready: ready, setup: setup)) }` and `makePaymentForm: { request in AnyView(PaymentFormScreen(request: request, ready: ready, setup: setup)) }`. `RootTabView`: `MoreView(…, makeCustomers: …, makeCrew: { AnyView(CrewScreen(ready: ready, setup: setup)) }, makeCategories: …)`.

- [ ] **Step 5: Lint, push, CI green (all existing UI tests incl. DashboardFlowTests, ExpensesFlowTests, SmokeTests), commit**

```bash
python scripts/check_localization.py && python scripts/lint_sources.py
git add Packages/Features App
git commit -m "feat(app): wire payments card, tappable schedule, home record button, labour card and crew"
git push origin HEAD
```

If an existing UI test fails only because a target moved below its scroll limit (the detail page is longer), raise that limit (never an expected number) and record it in the spec Errata.

---

### Task 13: UI tests (a)–(h) + screenshots

**Files:**
- Create: `UITests/PaymentsLabourFlowTests.swift`
- Modify: `UITests/ScreenshotTests.swift`

**Interfaces:** identifiers from spec §5; launch args `--ui-testing --seed-sample-data --locale en --today 2026-10-03`.

- [ ] **Step 1: Tests**

```swift
import XCTest

final class PaymentsLabourFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(locale: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", locale, "--today", "2026-10-03"] + extra
        app.launch()
        return app
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func containing(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    private func button(_ app: XCUIApplication, prefix: String, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", prefix, text)).firstMatch
    }
    @discardableResult
    private func waitLabel(_ app: XCUIApplication, _ id: String, contains text: String, timeout: TimeInterval = 8) -> String {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), id)
        let done = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: e)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: timeout), .completed, "\(id): '\(e.label)' lacks '\(text)'")
        return e.label
    }
    private func waitLabel(_ app: XCUIApplication, _ id: String, lacks text: String, timeout: TimeInterval = 8) {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), id)
        let done = expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", text), evaluatedWith: e)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: timeout), .completed, "\(id): '\(e.label)' still has '\(text)'")
    }
    /// A `.contain` container has no label of its own: join its descendants' labels.
    private func text(_ app: XCUIApplication, _ id: String) -> String {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 8), id)
        return ([e.label] + e.descendants(matching: .any).allElementsBoundByIndex.map(\.label)).joined(separator: " ")
    }
    private func type(_ app: XCUIApplication, _ id: String, _ text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), id)
        field.tap()
        field.typeText(text)
    }
    private func replace(_ app: XCUIApplication, _ id: String, with text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), id)
        let current = (field.value as? String) ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()        // caret at the end (trailing-aligned text)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }
    private func doneKeyboard(_ app: XCUIApplication, _ id: String) {
        let done = app.buttons[id]
        if done.waitForExistence(timeout: 2) { done.tap() }
    }
    private func tab(_ app: XCUIApplication, _ label: String) {
        let button = app.tabBars.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "tab \(label)")
        button.tap()
    }
    private func scrollTo(_ app: XCUIApplication, _ el: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !(el.exists && el.isHittable) && swipes < maxSwipes { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(el.exists, "not found after scrolling\n" + app.debugDescription)
    }
    /// 2b pattern: the list defaults to the In-work filter, so show every project before looking for the card.
    private func openProject(_ app: XCUIApplication, _ address: String, projectsTab: String = "Projects") {
        tab(app, projectsTab)
        let all = app.descendants(matching: .any)["projects_filter"].buttons.element(boundBy: 0)
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        all.tap()
        let card = containing(app, address)
        XCTAssertTrue(card.waitForExistence(timeout: 10), address)
        card.tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
    }
    private func savePayment(_ app: XCUIApplication) {
        app.buttons["payment_save"].tap()
        XCTAssertTrue(app.buttons["payment_save"].waitForNonExistence(timeout: 5), "payment form still open\n" + app.debugDescription)
    }
    private func saveLabour(_ app: XCUIApplication) {
        app.buttons["labour_save"].tap()
        XCTAssertTrue(app.buttons["labour_save"].waitForNonExistence(timeout: 5), "labour form still open\n" + app.debugDescription)
    }

    /// (a) Stage 2 (overdue 11,400) from its schedule row: pre-filled, paid, Home moves by exactly 11,400.
    func testRecordPaymentFromScheduleRow() {
        let app = launch()
        openProject(app, "123 Main Street")
        let stage2 = element(app, "detail_schedule_row_1")
        scrollTo(app, stage2)
        XCTAssertTrue(stage2.label.contains("Overdue"), stage2.label)
        stage2.tap()
        waitLabel(app, "payment_chip_remaining", contains: "11,400.00")
        let amount = app.textFields["payment_amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(((amount.value as? String) ?? "").contains("11400"), String(describing: amount.value))
        savePayment(app)
        waitLabel(app, "detail_schedule_row_1", contains: "Paid")
        waitLabel(app, "detail_schedule_row_1", lacks: "Overdue")
        waitLabel(app, "detail_collected", contains: "19,000.00")
        tab(app, "Home")
        waitLabel(app, "home_total_collected", contains: "37,500.00")
        waitLabel(app, "home_total_outstanding", contains: "44,000.00")
        waitLabel(app, "home_total_cash", contains: "26,815.00")
        XCTAssertFalse(text(app, "home_attention").contains("overdue 5 days"))
    }

    /// (b) Home's "Record" next to the overdue row: two taps.
    func testRecordPaymentFromHomeAttention() {
        let app = launch()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "attention_record_")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 15), "attention_record_*")
        record.tap()
        waitLabel(app, "payment_project", contains: "Basement Renovation")
        waitLabel(app, "payment_chip_remaining", contains: "11,400.00")
        savePayment(app)
        waitLabel(app, "home_total_collected", contains: "37,500.00")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "attention_record_")).firstMatch.exists)
    }

    /// (c) Kitchen: a payment not linked to any stage counts as collected only.
    func testUnlinkedPayment() {
        let app = launch()
        openProject(app, "45 Oak Avenue")
        let add = app.buttons["detail_payments_add"]
        scrollTo(app, add)
        add.tap()
        let none = app.buttons["payment_item_none"]
        XCTAssertTrue(none.waitForExistence(timeout: 5))
        none.tap()
        type(app, "payment_amount", "1000")
        doneKeyboard(app, "payment_keyboard_done")
        savePayment(app)
        let row = waitLabel(app, "detail_payment_row_0", contains: "1,000.00")
        XCTAssertTrue(row.contains("Not linked"), row)
        waitLabel(app, "detail_collected", contains: "1,000.00")
        waitLabel(app, "detail_schedule_row_0", contains: "Upcoming")
        tab(app, "Home")
        waitLabel(app, "home_total_collected", contains: "27,100.00")
        waitLabel(app, "home_total_outstanding", contains: "54,400.00")
    }

    /// (d) Delete Basement's deposit payment: the deposit is overdue again.
    func testDeletePayment() {
        let app = launch()
        openProject(app, "123 Main Street")
        let row = element(app, "detail_payment_row_0")
        scrollTo(app, row)
        XCTAssertTrue(row.label.contains("7,600.00"), row.label)
        row.tap()
        let delete = app.buttons["payment_delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        scrollTo(app, delete)
        delete.tap()
        // The confirmation dialog exposes its action twice (sheet + popover representation); tap the first.
        let confirm = app.buttons.matching(identifier: "payment_delete_confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["payment_save"].waitForNonExistence(timeout: 5))
        waitLabel(app, "detail_collected", contains: "$0.00")
        waitLabel(app, "detail_schedule_row_0", contains: "Overdue")
        tab(app, "Home")
        waitLabel(app, "home_total_collected", contains: "18,500.00")
        waitLabel(app, "home_total_outstanding", contains: "63,000.00")
        waitLabel(app, "home_total_cash", contains: "7,815.00")
        XCTAssertTrue(text(app, "home_attention").contains("overdue 20 days"))
    }

    /// (e) Add a crew member in More, then log a day for them: their rate fills in.
    func testAddCrewMemberThenLogLabour() {
        let app = launch()
        tab(app, "More")
        app.buttons["more_crew"].tap()
        let add = app.buttons["crew_add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        type(app, "crew_name", "Sam Patel")
        type(app, "crew_trade", "Electrician")
        type(app, "crew_daily_rate", "300")
        app.buttons["crew_save"].tap()
        let sam = button(app, prefix: "crew_row_", containing: "Sam Patel")
        XCTAssertTrue(sam.waitForExistence(timeout: 5), "crew row Sam Patel")
        XCTAssertTrue(sam.label.contains("300.00"), sam.label)
        openProject(app, "123 Main Street")
        let log = app.buttons["detail_labour_add"]
        scrollTo(app, log)
        log.tap()
        let person = button(app, prefix: "labour_person_", containing: "Sam Patel")
        XCTAssertTrue(person.waitForExistence(timeout: 5), "labour_person Sam Patel")
        person.tap()
        waitLabel(app, "labour_total", contains: "300.00")
        saveLabour(app)
        waitLabel(app, "detail_labour_total", contains: "5,900.00")
        tab(app, "Home")
        waitLabel(app, "home_total_spent", contains: "10,985.00")
    }

    /// (f) Mike + John, one day: labour 5,600 → 6,070, over its 6,000 estimate by exactly 70.
    func testLogLabourForTwoPeople() {
        let app = launch()
        openProject(app, "123 Main Street")
        let log = app.buttons["detail_labour_add"]
        scrollTo(app, log)
        log.tap()
        for name in ["Mike", "John"] {
            let person = button(app, prefix: "labour_person_", containing: name)
            XCTAssertTrue(person.waitForExistence(timeout: 5), name)
            person.tap()
        }
        waitLabel(app, "labour_total", contains: "470.00")
        saveLabour(app)
        waitLabel(app, "detail_labour_total", contains: "6,070.00")
        waitLabel(app, "detail_health", contains: "Over budget")
        waitLabel(app, "detail_health_reasons", contains: "70.00")
        tab(app, "Home")
        waitLabel(app, "home_total_spent", contains: "11,155.00")
        waitLabel(app, "home_total_cash", contains: "14,945.00")
    }

    /// (g) Edit David's entry 7 → 8 days.
    func testEditLabourEntry() {
        let app = launch()
        openProject(app, "123 Main Street")
        let david = button(app, prefix: "labour_row_", containing: "David")
        scrollTo(app, david)
        david.tap()
        XCTAssertTrue(app.textFields["labour_days"].waitForExistence(timeout: 5))
        replace(app, "labour_days", with: "8")
        doneKeyboard(app, "labour_keyboard_done")
        waitLabel(app, "labour_total", contains: "1,600.00")
        saveLabour(app)
        waitLabel(app, "detail_labour_total", contains: "5,800.00")
        tab(app, "Home")
        waitLabel(app, "home_total_spent", contains: "10,885.00")
    }

    /// (h) Vietnamese smoke: Payments/Labour cards and the crew list.
    func testVietnameseSmoke() {
        let app = launch(locale: "vi", extra: ["-AppleLocale", "vi_VN"])
        openProject(app, "123 Main Street", projectsTab: "Dự án")
        let payments = element(app, "detail_payments")
        scrollTo(app, payments)
        XCTAssertTrue(text(app, "detail_payments").contains("Thanh toán"))
        let log = app.buttons["detail_labour_add"]
        scrollTo(app, log)
        XCTAssertTrue(log.label.contains("Ghi công"), log.label)
        tab(app, "Thêm")
        waitLabel(app, "more_crew", contains: "Crew")
        app.buttons["more_crew"].tap()
        let mike = button(app, prefix: "crew_row_", containing: "Mike")
        XCTAssertTrue(mike.waitForExistence(timeout: 5), "crew row Mike")
        XCTAssertTrue(mike.label.contains("ngày"), mike.label)
    }
}
```

`waitForNonExistence(timeout:)` needs Xcode 16 (CI uses latest-stable). "$0.00" matches both "CA$0.00" and "$0.00".

- [ ] **Step 2: Screenshots** — in `ScreenshotTests`:
- raise the scroll limit to `detail_activity_all` from `swipes < 4` to `swipes < 8`, and in `captureExpenseScreens` to `detail_expenses` from `swipes < 3` to `swipes < 5` (detail is longer: Payments and Labour cards);
- add the helper below and call `captureMoneyScreens(app, locale: locale)` right after `captureExpenseScreens(app, locale: locale)` (both leave the app on the Projects tab root).

```swift
    private func captureMoneyScreens(_ app: XCUIApplication, locale: String) {
        app.tabBars.buttons.element(boundBy: 1).tap()
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "123 Main Street")).firstMatch.tap()
        _ = app.otherElements["detail_header"].waitForExistence(timeout: 5)
        let payments = app.descendants(matching: .any)["detail_payments"]
        var swipes = 0
        while !(payments.exists && payments.isHittable) && swipes < 4 { app.swipeUp(); swipes += 1 }
        snap(app, "detail_payments_\(locale)")
        app.buttons["detail_payments_add"].tap()
        _ = app.buttons["payment_save"].waitForExistence(timeout: 5)
        snap(app, "payment_form_\(locale)")
        app.buttons["payment_cancel"].tap()
        let labour = app.descendants(matching: .any)["detail_labour"]
        swipes = 0
        while !(labour.exists && labour.isHittable) && swipes < 5 { app.swipeUp(); swipes += 1 }
        snap(app, "detail_labour_\(locale)")
        app.buttons["detail_labour_add"].tap()
        _ = app.buttons["labour_save"].waitForExistence(timeout: 5)
        snap(app, "labour_form_\(locale)")
        app.buttons["labour_cancel"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons.element(boundBy: 4).tap()
        app.buttons["more_crew"].tap()
        _ = app.buttons["crew_add"].waitForExistence(timeout: 5)
        snap(app, "crew_\(locale)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons.element(boundBy: 1).tap()
    }
```

- [ ] **Step 3: Push, CI, fix to green; download the screenshot artifact and look at `detail_payments_*`, `payment_form_*`, `detail_labour_*`, `labour_form_*`, `crew_*`, `detail_full_*`; append spec Errata for any deviation; commit**

```bash
git add UITests docs/superpowers/specs/2026-10-04-payments-labour-design.md
git commit -m "test(payments): add payment, crew and labour flow UI tests and screenshots"
git push origin HEAD
```

---

## Thứ tự và phụ thuộc

- Task 1–3 (Domain) tuần tự, verify local (`swift test --package-path Packages/Domain`); Task 3 cũng giữ app compile + catalog nên push.
- Task 4–6 (Data) sau 3, tuần tự (5 không cần 4 nhưng dùng chung mẫu; 6 cần cả 4 và 5); mỗi task push + CI. Protocol của mỗi repository nằm trong cùng commit với GRDB implementation.
- Task 7 (FeatureSupport + strings) sau 3; chạy song song được với 4–6 nhưng push tuần tự.
- Task 8 sau 4 và 7; Task 9 sau 5 và 7; Task 10 sau 9; Task 11 sau 10; Task 12 sau 6, 8 và 11; Task 13 cuối.
- Sau Task 13: final review toàn nhánh, merge `main`, `testflight` lane `beta`, thử trên iPhone thật: ghi Stage 2 từ Home, ghi công 2 người, sửa một dòng công.

## Deferred ghi nhận (không làm trong 3b)

Nhắc thanh toán bằng notification, invoice/biên nhận gửi khách (4/5); chấm công theo giờ, timesheet, lương; phân công crew theo ngày (`project_workers`) và cảnh báo trùng lịch (4); số ngày khác nhau cho từng người trong một lô; chuyển payment sang project khác; undo xóa; đồng bộ (5); các mục 3a còn lại (photo picker pending loads, `keptImageIds` trùng, guard companyId của expense update, path receipt trước sync, seed atomic, alert 9 trang, vi `expense.receipt.title`); drag-reorder schedule, Percentage Codable, DateFormatter cache (2b).
