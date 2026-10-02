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

        try await projects.save(project("Basement Renovation", ann, .basementRenovation, .inProgress, line: "123 Main Street", city: "Toronto", contract: 38_000, progress: 65, start: "2026-09-15", end: "2026-10-30"), actor: actor)
        try await projects.save(project("Kitchen Renovation", david, .kitchen, .awaitingDeposit, line: "45 Oak Avenue", city: "Mississauga", contract: 25_000, progress: nil, start: "2026-10-12", end: "2026-11-15"), actor: actor)
        try await projects.save(project("Roof Replacement", maria, .roofing, .completed, line: "9 Birch Court", city: "Vaughan", contract: 18_500, progress: 100, start: "2026-08-01", end: "2026-08-20"), actor: actor)

        guard let setup = try await companies.current() else { throw DataError.notFound }
        return setup
    }
}
