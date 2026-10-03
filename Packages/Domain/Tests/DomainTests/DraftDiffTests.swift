import XCTest
@testable import Domain

final class DraftDiffTests: XCTestCase {
    let company = UUID(), project = UUID(), customer = UUID()
    let t0 = Date(timeIntervalSince1970: 1_790_000_000), t1 = Date(timeIntervalSince1970: 1_790_000_600)

    private func oldLine(_ label: String, _ amount: Decimal, group: CostGroup = .material, order: Int = 0) -> ProjectEstimateLine {
        ProjectEstimateLine(id: UUID(), companyId: company, projectId: project, costGroup: group, label: label, amount: Money(amount, .cad), quantity: nil, unitRate: nil, sortOrder: order, createdAt: t0, updatedAt: t0, deletedAt: nil)
    }
    private func draftLine(from l: ProjectEstimateLine, amount: Decimal? = nil) -> DraftEstimateLine {
        DraftEstimateLine(id: l.id, label: l.label, amount: amount.map { Money($0, .cad) } ?? l.amount, quantity: l.quantity, unitRate: l.unitRate, costGroup: l.costGroup, otherKind: nil, sortOrder: l.sortOrder)
    }

    func testEstimateDiffKeepsIdsDeletesMissingAddsNew() throws {
        let a = oldLine("Lumber", 2500), b = oldLine("Drywall", 1600, order: 1)
        let newB = draftLine(from: b, amount: 1800)
        let c = DraftEstimateLine(id: UUID(), label: "Paint", amount: Money(800, .cad), quantity: nil, unitRate: nil, costGroup: .material, otherKind: nil, sortOrder: 2)
        let change = try DraftDiff.estimateLines(group: .material, old: [a, b], new: [newB, c], companyId: company, projectId: project, currency: .cad, now: t1)
        XCTAssertEqual(change.deletedIds, [a.id])
        XCTAssertEqual(change.upserts.map(\.id), [b.id, c.id])
        XCTAssertEqual(change.upserts[0].createdAt, t0, "existing line keeps createdAt")
        XCTAssertEqual(change.upserts[0].updatedAt, t1)
        XCTAssertEqual(change.upserts[1].createdAt, t1)
        XCTAssertEqual(change.upserts.map(\.sortOrder), [0, 1])
        XCTAssertEqual(change.totalBefore.storageString, "4100.00")
        XCTAssertEqual(change.totalAfter.storageString, "2600.00")
    }

    func testEstimateDiffIgnoresOtherGroupsAndRejectsWrongGroup() throws {
        let labour = oldLine("Mike", 2000, group: .labour)
        let change = try DraftDiff.estimateLines(group: .material, old: [labour], new: [], companyId: company, projectId: project, currency: .cad, now: t1)
        XCTAssertTrue(change.deletedIds.isEmpty, "lines of other groups are untouched")
        let wrong = DraftEstimateLine(id: UUID(), label: "x", amount: Money(1, .cad), quantity: nil, unitRate: nil, costGroup: .labour, otherKind: nil, sortOrder: 0)
        XCTAssertThrowsError(try DraftDiff.estimateLines(group: .material, old: [], new: [wrong], companyId: company, projectId: project, currency: .cad, now: t1))
    }

    func testScheduleDiff() throws {
        let dep = PaymentScheduleItem(id: UUID(), companyId: company, projectId: project, label: "schedule.row.deposit", amount: Money(6000, .cad), percentage: try Percentage.input(20), dueDate: nil, triggerText: nil, isDeposit: true, notes: nil, sortOrder: 0, createdAt: t0, updatedAt: t0, deletedAt: nil)
        let fin = PaymentScheduleItem(id: UUID(), companyId: company, projectId: project, label: "schedule.row.final", amount: Money(24_000, .cad), percentage: try Percentage.input(80), dueDate: nil, triggerText: nil, isDeposit: false, notes: nil, sortOrder: 1, createdAt: t0, updatedAt: t0, deletedAt: nil)
        let rows = [DraftScheduleRow(id: dep.id, label: dep.label, percentage: try Percentage.input(30), amount: nil, dueDate: CalendarDate(storage: "2026-10-10"), trigger: nil, isDeposit: true),
                    DraftScheduleRow(id: UUID(), label: "schedule.row.final", percentage: try Percentage.input(70), amount: nil, dueDate: nil, trigger: "After paint", isDeposit: false)]
        let change = try DraftDiff.scheduleItems(old: [dep, fin], new: rows, contract: Money(30_000, .cad), companyId: company, projectId: project, now: t1)
        XCTAssertEqual(change.deletedIds, [fin.id])
        XCTAssertEqual(change.upserts.map { $0.amount.storageString }, ["9000.00", "21000.00"])
        XCTAssertEqual(change.upserts[0].id, dep.id); XCTAssertEqual(change.upserts[0].createdAt, t0)
        XCTAssertEqual(change.upserts[0].dueDate, CalendarDate(storage: "2026-10-10"))
        XCTAssertEqual(change.upserts[1].triggerText, "After paint")
        XCTAssertEqual(change.totalBefore.storageString, "30000.00"); XCTAssertEqual(change.totalAfter.storageString, "30000.00")
    }

    func testScheduleDiffSkipsRowsWithoutAmount() throws {
        let rows = [DraftScheduleRow(id: UUID(), label: "a", percentage: nil, amount: nil, dueDate: nil, trigger: nil, isDeposit: true)]
        let change = try DraftDiff.scheduleItems(old: [], new: rows, contract: Money(1000, .cad), companyId: company, projectId: project, now: t1)
        XCTAssertTrue(change.upserts.isEmpty)
    }

    func testScopeFieldsDiff() {
        let old = ProjectScopeField(id: UUID(), companyId: company, projectId: project, fieldKey: "rooms", valueText: "3", sortOrder: 0, createdAt: t0, updatedAt: t0, deletedAt: nil)
        let new = [DraftScopeField(id: old.id, key: "rooms", value: "4", sortOrder: 1), DraftScopeField(id: UUID(), key: "floors", value: "2", sortOrder: 0), DraftScopeField(id: UUID(), key: "x", value: " ", sortOrder: 2)]
        let fields = DraftDiff.scopeFields(old: [old], new: new, companyId: company, projectId: project, now: t1)
        XCTAssertEqual(fields.map(\.fieldKey), ["floors", "rooms"])
        XCTAssertEqual(fields[1].id, old.id); XCTAssertEqual(fields[1].createdAt, t0); XCTAssertEqual(fields[1].valueText, "4")
        XCTAssertEqual(fields.map(\.sortOrder), [0, 1])
    }

    func testScopeFieldValueIsTrimmed() {
        let new = [DraftScopeField(id: UUID(), key: "rooms", value: "  5 ", sortOrder: 0)]
        let fields = DraftDiff.scopeFields(old: [], new: new, companyId: company, projectId: project, now: t1)
        XCTAssertEqual(fields.map(\.valueText), ["5"])
    }

    func testSeedFromProjectRoundTripsThroughAssembler() throws {
        let p = Project(id: project, companyId: company, customerId: customer, name: "Smith kitchen", jobType: .kitchen, customJobType: nil, status: .inProgress,
                        address: Address(line: "1 Main", unit: nil, city: "Toronto", region: "ON", postalCode: nil), scopeDescription: "Full gut", scopeFields: [],
                        startDate: CalendarDate(storage: "2026-10-01"), estimatedCompletionDate: CalendarDate(storage: "2026-11-01"), workingDays: 20, hoursPerDay: 8, workersPerDay: 3,
                        contractValue: Money(30_000, .cad), manualProgress: 40, depositRequiredToStart: true, createdAt: t0, updatedAt: t0, deletedAt: nil)
        let lines = [oldLine("Mike", 2000, group: .labour), oldLine("Lumber", 2500), oldLine("Permit", 300, group: .permit)]
        let items = [PaymentScheduleItem(id: UUID(), companyId: company, projectId: project, label: "schedule.row.deposit", amount: Money(6000, .cad), percentage: try Percentage.input(20), dueDate: CalendarDate(storage: "2026-10-10"), triggerText: nil, isDeposit: true, notes: nil, sortOrder: 0, createdAt: t0, updatedAt: t0, deletedAt: nil)]
        let draft = ProjectDraft(project: p, estimateLines: lines, scheduleItems: items, step: 9)
        XCTAssertEqual(draft.customer, .existing(customer))
        XCTAssertEqual(draft.labourMode, .detailed)
        XCTAssertEqual(draft.labourLines.map(\.id), [lines[0].id])
        XCTAssertEqual(draft.materialLines.map(\.id), [lines[1].id])
        XCTAssertEqual(draft.otherLines.first?.otherKind, .permits)
        XCTAssertEqual(draft.deposit, DraftDeposit(mode: .fixed(Money(6000, .cad)), deadline: CalendarDate(storage: "2026-10-10"), requiredToStart: true))
        XCTAssertEqual(draft.schedule.map(\.id), [items[0].id])
        XCTAssertEqual(draft.scheduleTemplate, .custom)
        XCTAssertEqual(draft.step, 9)
        let bundle = try ProjectDraftAssembler.assemble(draft, companyId: company, currency: .cad, now: t1)
        XCTAssertEqual(bundle.project.name, "Smith kitchen")
        XCTAssertEqual(bundle.estimateLines.map { $0.amount.storageString }, ["2000.00", "2500.00", "300.00"])
        XCTAssertEqual(bundle.scheduleItems.first?.amount.storageString, "6000.00")
        XCTAssertEqual(bundle.estimateLines.last?.costGroup, .permit)
        XCTAssertTrue(bundle.project.depositRequiredToStart)
    }

    func testScheduleDiffSortOrderHasNoGaps() throws {
        let rows = [DraftScheduleRow(id: UUID(), label: "a", percentage: nil, amount: Money(100, .cad), dueDate: nil, trigger: nil, isDeposit: false),
                    DraftScheduleRow(id: UUID(), label: "n", percentage: nil, amount: nil, dueDate: nil, trigger: nil, isDeposit: false),
                    DraftScheduleRow(id: UUID(), label: "b", percentage: nil, amount: Money(200, .cad), dueDate: nil, trigger: nil, isDeposit: false)]
        let change = try DraftDiff.scheduleItems(old: [], new: rows, contract: Money(300, .cad), companyId: company, projectId: project, now: t1)
        XCTAssertEqual(change.upserts.map(\.sortOrder), [0, 1])
    }
}
