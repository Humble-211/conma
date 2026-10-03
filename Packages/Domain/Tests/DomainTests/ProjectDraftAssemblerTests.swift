import XCTest
@testable import Domain

final class ProjectDraftAssemblerTests: XCTestCase {
    let company = UUID(), existingCustomer = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func minimal() -> ProjectDraft {
        var d = ProjectDraft()
        d.jobType = .kitchen
        d.customer = .existing(existingCustomer)
        d.address = Address(line: "123 Main St", unit: nil, city: "Toronto", region: "ON", postalCode: nil)
        d.contractValue = Money(25_000, .cad)
        return d
    }
    private func assemble(_ d: ProjectDraft) throws -> NewProjectBundle { try ProjectDraftAssembler.assemble(d, companyId: company, currency: .cad, now: now) }
    private func missing(_ d: ProjectDraft) -> Set<DraftField>? {
        do { _ = try assemble(d); return nil } catch DraftError.missing(let f) { return f } catch { return nil }
    }

    func testMinimalDraftAssembles() throws {
        let b = try assemble(minimal())
        XCTAssertEqual(b.project.status, .estimate)
        XCTAssertEqual(b.project.name, "Kitchen")
        XCTAssertEqual(b.project.customerId, existingCustomer)
        XCTAssertEqual(b.project.companyId, company)
        XCTAssertEqual(b.project.contractValue.storageString, "25000.00")
        XCTAssertNil(b.project.manualProgress)
        XCTAssertFalse(b.project.depositRequiredToStart)
        XCTAssertEqual(b.project.createdAt, now); XCTAssertEqual(b.project.updatedAt, now)
        XCTAssertTrue(b.estimateLines.isEmpty); XCTAssertTrue(b.scheduleItems.isEmpty); XCTAssertNil(b.newCustomer)
        XCTAssertEqual(b.warnings, [.scheduleEmpty])
    }

    func testMissingFieldsAreCollected() {
        XCTAssertEqual(missing(ProjectDraft()), [.jobType, .customer, .addressLine, .contractValue])
        var d = minimal(); d.jobType = .other
        XCTAssertEqual(missing(d), [.customJobType])
        d.customJobType = "  "
        XCTAssertEqual(missing(d), [.customJobType])
        d = minimal(); d.address = Address(line: "   ", unit: nil, city: nil, region: nil, postalCode: nil)
        XCTAssertEqual(missing(d), [.addressLine])
        d = minimal(); d.customer = .new(NewCustomerInput(name: " ", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil))
        XCTAssertEqual(missing(d), [.customer])
    }

    func testCustomJobTypeNameAndNewCustomer() throws {
        var d = minimal(); d.jobType = .other; d.customJobType = "Sauna build"
        d.customer = .new(NewCustomerInput(name: "Ann Lee", phone: "416", email: nil, preferredContact: .text, companyName: nil, secondaryContact: nil, notes: nil))
        let b = try assemble(d)
        XCTAssertEqual(b.project.name, "Sauna build")
        XCTAssertEqual(b.newCustomer?.name, "Ann Lee")
        XCTAssertEqual(b.project.customerId, b.newCustomer?.id)
        XCTAssertEqual(b.newCustomer?.companyId, company)
    }

    func testExplicitNameWins() throws {
        var d = minimal(); d.projectName = "Smith kitchen"
        XCTAssertEqual(try assemble(d).project.name, "Smith kitchen")
        XCTAssertEqual(JobType.deckFence.englishName, "Deck / Fence")
        XCTAssertEqual(JobType.hvac.englishName, "HVAC")
        XCTAssertEqual(JobType.basementRenovation.englishName, "Basement Renovation")
    }

    func testValidationErrors() {
        var d = minimal(); d.contractValue = Money(-1, .cad)
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .negativeAmount) }
        d = minimal(); d.startDate = CalendarDate(storage: "2026-10-20"); d.estimatedCompletionDate = CalendarDate(storage: "2026-10-01")
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .completionBeforeStart) }
        d = minimal(); d.hoursPerDay = 25
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .invalidTimeline) }
        d = minimal(); d.workersPerDay = -1
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .invalidTimeline) }
        d = minimal(); d.contractValue = Money(1, .usd)
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .currencyMismatch) }
    }

    func testScopeFieldsDropBlankAndKeepOrder() throws {
        var d = minimal()
        d.scopeFields = [DraftScopeField(id: UUID(), key: "rooms", value: "3", sortOrder: 1),
                         DraftScopeField(id: UUID(), key: "squareFootage", value: "1200", sortOrder: 0),
                         DraftScopeField(id: UUID(), key: "", value: "x", sortOrder: 2),
                         DraftScopeField(id: UUID(), key: "floors", value: "  ", sortOrder: 3)]
        let b = try assemble(d)
        XCTAssertEqual(b.scopeFields.map(\.fieldKey), ["squareFootage", "rooms"])
        XCTAssertTrue(b.scopeFields.allSatisfy { $0.projectId == b.project.id && $0.companyId == company })
    }

    func testEstimateLinesAndSchedule() throws {
        var d = minimal()
        d.labourQuick = LabourQuickInput(workers: 4, dailyRate: Money(230, .cad), days: 10)
        d.materialLines = [DraftEstimateLine(id: UUID(), label: "Lumber", amount: Money(2500, .cad), quantity: nil, unitRate: nil, costGroup: .material, otherKind: nil, sortOrder: 0)]
        d.otherLines = [DraftEstimateLine(id: UUID(), label: "Dumpster", amount: Money(400, .cad), quantity: nil, unitRate: nil, costGroup: .other, otherKind: .dumpster, sortOrder: 0)]
        d.deposit = DraftDeposit(mode: .percentage(try Percentage.input(20)), deadline: CalendarDate(storage: "2026-10-10"), requiredToStart: true)
        d.schedule = PaymentScheduleTemplate.fourStage.rows(depositPercentage: try Percentage.input(20))
        let b = try assemble(d)
        XCTAssertEqual(b.estimateLines.map(\.costGroup), [.labour, .material, .other])
        XCTAssertEqual(b.estimateLines[0].amount.storageString, "9200.00")
        XCTAssertEqual(b.estimateLines[0].quantity, 40)
        XCTAssertEqual(b.scheduleItems.count, 4)
        XCTAssertEqual(b.scheduleItems.map { $0.amount.storageString }, ["5000.00", "7500.00", "7500.00", "5000.00"])
        XCTAssertEqual(b.scheduleItems[0].isDeposit, true)
        XCTAssertEqual(b.scheduleItems[0].dueDate, CalendarDate(storage: "2026-10-10"))
        XCTAssertNil(b.scheduleItems[1].dueDate)
        XCTAssertEqual(b.scheduleItems.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertTrue(b.project.depositRequiredToStart)
        XCTAssertTrue(b.warnings.isEmpty)
    }

    func testDepositWithoutScheduleCreatesOneItem() throws {
        var d = minimal()
        d.deposit = DraftDeposit(mode: .fixed(Money(30_000, .cad)), deadline: nil, requiredToStart: false)
        let b = try assemble(d)
        XCTAssertEqual(b.scheduleItems.count, 1)
        XCTAssertEqual(b.scheduleItems[0].amount.storageString, "30000.00")
        XCTAssertTrue(b.scheduleItems[0].isDeposit)
        XCTAssertEqual(Set(b.warnings), [.depositExceedsContract, .scheduleTotalMismatch(difference: Money(5000, .cad))])
    }
}
