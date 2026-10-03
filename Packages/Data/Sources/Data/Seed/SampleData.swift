import Foundation
import Domain

public enum SampleData {
    public static func seedIfEmpty(_ database: AppDatabase, clock: Clock) async throws -> CompanySetup {
        let companies = GRDBCompanyRepository(database: database, clock: clock)
        if let existing = try await companies.current() { return existing }

        let now = clock.now()
        let company = Company(id: UUID(), name: "Northwind Contracting", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await companies.create(company: company, owner: owner)
        let actor = ActivityActor(userId: owner.id, name: owner.displayName)

        let customers = GRDBCustomerRepository(database: database, clock: clock)
        let projects = GRDBProjectRepository(database: database, clock: clock)

        func customer(_ name: String, _ phone: String) -> Customer {
            Customer(id: UUID(), companyId: company.id, name: name, phone: phone, email: nil, preferredContact: .text, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        func project(_ name: String, _ customer: Customer, _ jobType: JobType, _ status: ProjectStatus, line: String, city: String, contract: Int, progress: Int?, start: String, end: String) -> Project {
            Project(id: UUID(), companyId: company.id, customerId: customer.id, name: name, jobType: jobType, customJobType: nil, status: status,
                    address: Address(line: line, unit: nil, city: city, region: "ON", postalCode: nil), scopeDescription: nil, scopeFields: [],
                    startDate: CalendarDate(storage: start), estimatedCompletionDate: CalendarDate(storage: end), workingDays: nil, hoursPerDay: nil, workersPerDay: 3,
                    contractValue: Money(Decimal(contract), .cad), manualProgress: progress, depositRequiredToStart: true, createdAt: now, updatedAt: now, deletedAt: nil)
        }

        let ann = customer("Ann Lee", "416-555-0101"), david = customer("David Nguyen", "647-555-0199"), maria = customer("Maria Santos", "905-555-0142")
        for c in [ann, david, maria] { try await customers.save(c) }

        let basementProject = project("Basement Renovation", ann, .basementRenovation, .inProgress, line: "123 Main Street", city: "Toronto", contract: 38_000, progress: 65, start: "2026-09-15", end: "2026-10-30")
        let kitchenProject = project("Kitchen Renovation", david, .kitchen, .awaitingDeposit, line: "45 Oak Avenue", city: "Mississauga", contract: 25_000, progress: nil, start: "2026-10-12", end: "2026-11-15")
        try await projects.save(basementProject, actor: actor)
        try await projects.save(kitchenProject, actor: actor)
        try await projects.save(project("Roof Replacement", maria, .roofing, .completed, line: "9 Birch Court", city: "Vaughan", contract: 18_500, progress: 100, start: "2026-08-01", end: "2026-08-20"), actor: actor)

        var withScope = basementProject
        let scopeKeys: [(String, String)] = [("squareFootage", "1200"), ("bedrooms", "1"), ("bathrooms", "1"), ("egressWindows", "1"), ("ceilingHeight", "7.5"), ("wetBar", "false")]
        withScope.scopeFields = scopeKeys.enumerated().map { i, kv in ProjectScopeField(id: UUID(), companyId: company.id, projectId: basementProject.id, fieldKey: kv.0, valueText: kv.1, sortOrder: i, createdAt: now, updatedAt: now, deletedAt: nil) }
        let scopedBasement = withScope
        try await projects.save(scopedBasement, actor: actor)

        func est(_ group: CostGroup, _ label: String, _ amount: Int, _ order: Int, qty: Decimal? = nil, rate: Int? = nil) -> ProjectEstimateLine {
            ProjectEstimateLine(id: UUID(), companyId: company.id, projectId: basementProject.id, costGroup: group, label: label, amount: Money(Decimal(amount), .cad), quantity: qty, unitRate: rate.map { Money(Decimal($0), .cad) }, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        let estimates = GRDBProjectEstimateRepository(database: database, clock: clock)
        try await estimates.replace(projectId: basementProject.id, group: .labour, change: EstimateLineChange(upserts: [est(.labour, "Mike", 2000, 0, qty: 8, rate: 250), est(.labour, "John", 2200, 1, qty: 10, rate: 220), est(.labour, "David", 1800, 2, qty: 9, rate: 200)], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(6000, .cad)), actor: actor)
        try await estimates.replace(projectId: basementProject.id, group: .material, change: EstimateLineChange(upserts: [est(.material, "Lumber", 2500, 0), est(.material, "Drywall", 1600, 1), est(.material, "Flooring", 3000, 2), est(.material, "Paint", 800, 3)], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(7900, .cad)), actor: actor)
        try await estimates.replace(projectId: basementProject.id, group: .other, change: EstimateLineChange(upserts: [est(.other, "Dumpster", 600, 0), est(.other, "Delivery", 300, 1)], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(900, .cad)), actor: actor)

        let schedules = GRDBPaymentScheduleRepository(database: database, clock: clock)
        let today = CalendarDate(now, timeZone: .gmt)
        func item(_ pid: UUID, _ label: String, _ amount: Int, pct: Decimal, due: CalendarDate?, deposit: Bool, _ order: Int) throws -> PaymentScheduleItem {
            PaymentScheduleItem(id: UUID(), companyId: company.id, projectId: pid, label: label, amount: Money(Decimal(amount), .cad), percentage: try Percentage.input(pct), dueDate: due, triggerText: nil, isDeposit: deposit, notes: nil, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        try await schedules.replace(projectId: basementProject.id, change: ScheduleItemChange(upserts: [
            try item(basementProject.id, "schedule.row.deposit", 7600, pct: 20, due: today.adding(days: -20), deposit: true, 0),
            try item(basementProject.id, "schedule.row.stage2", 11_400, pct: 30, due: today.adding(days: -5), deposit: false, 1),
            try item(basementProject.id, "schedule.row.stage3", 11_400, pct: 30, due: today.adding(days: 10), deposit: false, 2),
            try item(basementProject.id, "schedule.row.final", 7600, pct: 20, due: nil, deposit: false, 3),
        ], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(38_000, .cad)), actor: actor)
        try await schedules.replace(projectId: kitchenProject.id, change: ScheduleItemChange(upserts: [
            try item(kitchenProject.id, "schedule.row.deposit", 5000, pct: 20, due: today.adding(days: 7), deposit: true, 0),
        ], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(5000, .cad)), actor: actor)

        guard let setup = try await companies.current() else { throw DataError.notFound }
        return setup
    }
}
