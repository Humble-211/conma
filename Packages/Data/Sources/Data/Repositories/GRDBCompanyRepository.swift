import Foundation
import GRDB
import Domain

public final class GRDBCompanyRepository: CompanyRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) {
        self.database = database; self.clock = clock
    }

    public func current() async throws -> CompanySetup? {
        try await database.writer.read { db in
            guard let companyRecord = try CompanyRecord.filter(Column("deleted_at") == nil).order(Column("created_at")).fetchOne(db) else { return nil }
            guard let ownerRecord = try UserRecord
                .filter(Column("company_id") == companyRecord.id && Column("deleted_at") == nil && Column("role") == UserRole.owner.rawValue)
                .order(Column("created_at")).fetchOne(db) else { return nil }
            return CompanySetup(company: try companyRecord.toDomain(), owner: try ownerRecord.toDomain())
        }
    }

    public func create(company: Company, owner: User) async throws {
        try company.validate()
        try owner.validate()
        try await database.writer.write { db in
            try CompanyRecord(company).insert(db)
            try UserRecord(owner).insert(db)
        }
    }

    public func update(company: Company) async throws {
        try company.validate()
        var stamped = company
        stamped.updatedAt = clock.now()
        let record = CompanyRecord(stamped)
        try await database.writer.write { db in
            try record.update(db)
        }
    }
}
