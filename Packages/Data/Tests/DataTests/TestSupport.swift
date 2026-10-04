// Packages/Data/Tests/DataTests/TestSupport.swift
import XCTest
import Domain
@testable import Data

func XCTAssertThrowsErrorAsync(_ expression: @autoclosure () async throws -> Void, _ check: (Error) -> Void = { _ in }, file: StaticString = #filePath, line: UInt = #line) async {
    do { try await expression(); XCTFail("expected error", file: file, line: line) } catch { check(error) }
}

/// Company "N" (CAD) + owner "Duc" + customer "Ann" + in-progress project "P" (contract 1,000), all stamped `now`.
struct Fixture {
    let companyId: UUID
    let actor: ActivityActor
    let customer: Customer
    let project: Project
}

func makeFixture(_ db: AppDatabase, now: Date) async throws -> Fixture {
    let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
    let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
    let customer = Customer(id: UUID(), companyId: company.id, name: "Ann", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(customer)
    let project = Project(id: UUID(), companyId: company.id, customerId: customer.id, name: "P", jobType: .kitchen, customJobType: nil, status: .inProgress,
                          address: Address(line: "1", unit: nil, city: nil, region: nil, postalCode: nil), scopeDescription: nil, scopeFields: [],
                          startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil,
                          contractValue: Money(1000, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
    let actor = ActivityActor(userId: owner.id, name: "Duc")
    try await GRDBProjectRepository(database: db, clock: .fixed(now)).save(project, actor: actor)
    return Fixture(companyId: company.id, actor: actor, customer: customer, project: project)
}

func temporaryReceiptStore() -> FileReceiptStore {
    FileReceiptStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("receipts-\(UUID().uuidString)", isDirectory: true))
}

func XCTAssertEqualAsync<T: Equatable>(_ a: @autoclosure () async throws -> T, _ b: @autoclosure () -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do { let value = try await a(); XCTAssertEqual(value, b(), file: file, line: line) } catch { XCTFail("threw \(error)", file: file, line: line) }
}

func XCTAssertNilAsync<T>(_ a: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async {
    do { let value = try await a(); XCTAssertNil(value, file: file, line: line) } catch { XCTFail("threw \(error)", file: file, line: line) }
}

func XCTAssertNotNilAsync<T>(_ a: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async {
    do { let value = try await a(); XCTAssertNotNil(value, file: file, line: line) } catch { XCTFail("threw \(error)", file: file, line: line) }
}

func XCTUnwrapAsync<T>(_ a: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let value = try await a()
    return try XCTUnwrap(value, file: file, line: line)
}
