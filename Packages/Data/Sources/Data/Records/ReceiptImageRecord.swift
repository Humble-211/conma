// Packages/Data/Sources/Data/Records/ReceiptImageRecord.swift
import Foundation
import GRDB
import Domain

struct ReceiptImageRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "receipt_images"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var expenseId: String
    var filePath: String
    var remotePath: String?
    var pageIndex: Int

    init(_ r: ReceiptImage) {
        id = r.id.dbKey; companyId = r.companyId.dbKey
        createdAt = Timestamps.string(r.createdAt); updatedAt = Timestamps.string(r.updatedAt)
        deletedAt = r.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        expenseId = r.expenseId.dbKey; filePath = r.filePath; remotePath = r.remotePath; pageIndex = r.pageIndex
    }

    func toDomain() throws -> ReceiptImage {
        let t = Self.databaseTableName
        return ReceiptImage(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                            companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                            expenseId: try RecordSupport.uuid(expenseId, table: t, id: id, column: "expense_id"),
                            filePath: filePath, remotePath: remotePath, pageIndex: pageIndex,
                            createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                            updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                            deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }

    /// Live pages of every expense of the company, keyed by expense db key, ordered by page index.
    static func fetchLive(_ db: Database, companyId: String) throws -> [String: [ReceiptImage]] {
        let records = try ReceiptImageRecord.filter(Column("company_id") == companyId && Column("deleted_at") == nil)
            .order(Column("expense_id"), Column("page_index")).fetchAll(db)
        var result: [String: [ReceiptImage]] = [:]
        for record in records { result[record.expenseId, default: []].append(try record.toDomain()) }
        return result
    }

    static func fetchLive(_ db: Database, expenseId: String) throws -> [ReceiptImage] {
        try ReceiptImageRecord.filter(Column("expense_id") == expenseId && Column("deleted_at") == nil)
            .order(Column("page_index")).fetchAll(db).map { try $0.toDomain() }
    }
}
