import Foundation
import Domain

public enum SampleData {
    public static func seedIfEmpty(_ database: AppDatabase, clock: Clock, today: CalendarDate, receiptStore: FileReceiptStore? = nil, sampleReceipt: Data? = nil) async throws -> CompanySetup {
        let companies = GRDBCompanyRepository(database: database, clock: clock)
        if let existing = try await companies.current() { return existing }

        let store = receiptStore ?? FileReceiptStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("conma-seed-receipts", isDirectory: true))
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
        func project(_ name: String, _ customer: Customer, _ jobType: JobType, _ status: ProjectStatus, line: String, city: String, contract: Int, progress: Int?, start: CalendarDate, end: CalendarDate) -> Project {
            Project(id: UUID(), companyId: company.id, customerId: customer.id, name: name, jobType: jobType, customJobType: nil, status: status,
                    address: Address(line: line, unit: nil, city: city, region: "ON", postalCode: nil), scopeDescription: nil, scopeFields: [],
                    startDate: start, estimatedCompletionDate: end, workingDays: nil, hoursPerDay: nil, workersPerDay: 3,
                    contractValue: Money(Decimal(contract), .cad), manualProgress: progress, depositRequiredToStart: true, createdAt: now, updatedAt: now, deletedAt: nil)
        }

        let ann = customer("Ann Lee", "416-555-0101"), david = customer("David Nguyen", "647-555-0199"), maria = customer("Maria Santos", "905-555-0142")
        for c in [ann, david, maria] { try await customers.save(c) }

        let basementProject = project("Basement Renovation", ann, .basementRenovation, .inProgress, line: "123 Main Street", city: "Toronto", contract: 38_000, progress: 65, start: today.adding(days: -18), end: today.adding(days: 27))
        let kitchenProject = project("Kitchen Renovation", david, .kitchen, .awaitingDeposit, line: "45 Oak Avenue", city: "Mississauga", contract: 25_000, progress: nil, start: today, end: today.adding(days: 34))
        let roofProject = project("Roof Replacement", maria, .roofing, .completed, line: "9 Birch Court", city: "Vaughan", contract: 18_500, progress: 100, start: today.adding(days: -63), end: today.adding(days: -44))
        try await projects.save(basementProject, actor: actor)
        try await projects.save(kitchenProject, actor: actor)
        try await projects.save(roofProject, actor: actor)

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
        func item(_ pid: UUID, _ label: String, _ amount: Int, pct: Decimal, due: CalendarDate?, deposit: Bool, _ order: Int) throws -> PaymentScheduleItem {
            PaymentScheduleItem(id: UUID(), companyId: company.id, projectId: pid, label: label, amount: Money(Decimal(amount), .cad), percentage: try Percentage.input(pct), dueDate: due, triggerText: nil, isDeposit: deposit, notes: nil, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        let basementDeposit = try item(basementProject.id, "schedule.row.deposit", 7600, pct: 20, due: today.adding(days: -20), deposit: true, 0)
        try await schedules.replace(projectId: basementProject.id, change: ScheduleItemChange(upserts: [
            basementDeposit,
            try item(basementProject.id, "schedule.row.stage2", 11_400, pct: 30, due: today.adding(days: -5), deposit: false, 1),
            try item(basementProject.id, "schedule.row.stage3", 11_400, pct: 30, due: today.adding(days: 10), deposit: false, 2),
            try item(basementProject.id, "schedule.row.final", 7600, pct: 20, due: nil, deposit: false, 3),
        ], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(38_000, .cad)), actor: actor)
        try await schedules.replace(projectId: kitchenProject.id, change: ScheduleItemChange(upserts: [
            try item(kitchenProject.id, "schedule.row.deposit", 5000, pct: 20, due: today.adding(days: 7), deposit: true, 0),
        ], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(5000, .cad)), actor: actor)

        func employee(_ name: String, trade: String, phone: String, _ rate: Int, hourlyCents: Int? = nil) -> Employee {
            Employee(id: UUID(), companyId: company.id, name: name, phone: phone, role: nil, trade: trade,
                     hourlyRate: hourlyCents.map { Money(Decimal($0) / 100, .cad) }, dailyRate: Money(Decimal(rate), .cad),
                     certifications: nil, emergencyContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        func labour(_ pid: UUID, _ employeeId: UUID, days: Int, rate: Int, on date: CalendarDate) -> LabourEntry {
            LabourEntry(id: UUID(), companyId: company.id, projectId: pid, employeeId: employeeId, workDate: date, days: Decimal(days), dailyRate: Money(Decimal(rate), .cad),
                        notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        func expense(_ pid: UUID, _ group: CostGroup, _ vendor: String, _ amount: Int, _ tax: Int, on date: CalendarDate) -> Expense {
            Expense(id: UUID(), companyId: company.id, projectId: pid, category: group == .material ? .materials : .wasteDisposal, customCategoryId: nil, costGroup: group,
                    vendorName: vendor, amount: Money(Decimal(amount), .cad), tax: Money(Decimal(tax), .cad), spentOn: date, paymentMethod: .creditCard, notes: nil,
                    receiptImages: [], createdAt: now, updatedAt: now, deletedAt: nil)
        }
        func payment(_ pid: UUID, _ amount: Int, item: UUID?, on date: CalendarDate) -> Payment {
            Payment(id: UUID(), companyId: company.id, projectId: pid, scheduleItemId: item, amount: Money(Decimal(amount), .cad), paidOn: date, method: .eTransfer,
                    notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        let mike = employee("Mike", trade: "Carpenter", phone: "416-555-0110", 250, hourlyCents: 3125)
        let john = employee("John", trade: "Drywall", phone: "647-555-0111", 220)
        let davidW = employee("David", trade: "Labourer", phone: "905-555-0112", 200)
        let labourEntries = [labour(basementProject.id, mike.id, days: 8, rate: 250, on: today.adding(days: -10)),
                             labour(basementProject.id, john.id, days: 10, rate: 220, on: today.adding(days: -9)),
                             labour(basementProject.id, davidW.id, days: 7, rate: 200, on: today.adding(days: -8))]
        let expenseRows = [expense(basementProject.id, .material, "Lumber — Home Depot", 2400, 312, on: today.adding(days: -15)),
                           expense(basementProject.id, .material, "Drywall", 1500, 195, on: today.adding(days: -2)),
                           expense(basementProject.id, .other, "Dumpster rental", 600, 78, on: today.adding(days: -16))]
        let paymentRows = [payment(basementProject.id, 7600, item: basementDeposit.id, on: today.adding(days: -19)),
                           payment(roofProject.id, 18_500, item: nil, on: today.adding(days: -40))]
        let crewRepository = GRDBEmployeeRepository(database: database, clock: clock)
        for e in [mike, john, davidW] { try await crewRepository.create(e) }
        let labourRepository = GRDBLabourRepository(database: database, clock: clock)
        for l in labourEntries { try await labourRepository.create([l], actor: actor) }        // one log per day, as a contractor would enter them
        let paymentRepository = GRDBPaymentRepository(database: database, clock: clock)
        for p in paymentRows { try await paymentRepository.create(p, actor: actor) }

        let expenseRepository = GRDBExpenseRepository(database: database, clock: clock, receiptStore: store)
        let pageCounts = [2, 0, 1]                                    // Lumber, Drywall, Dumpster (order of `expenseRows`)
        for (row, pages) in zip(expenseRows, pageCounts) {
            let jpegs = sampleReceipt.map { Array(repeating: $0, count: pages) } ?? []
            try await expenseRepository.create(row, receiptPages: jpegs, actor: actor)
        }
        try await GRDBCustomCategoryRepository(database: database, clock: clock)
            .create(CustomExpenseCategory(id: UUID(), companyId: company.id, name: "Scaffolding", costGroup: .equipment, createdAt: now, updatedAt: now, deletedAt: nil))

        guard let setup = try await companies.current() else { throw DataError.notFound }
        return setup
    }
}
