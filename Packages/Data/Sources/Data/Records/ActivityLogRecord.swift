import Foundation
import GRDB
import Domain

struct ActivityLogRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "activity_log"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var userId: String?
    var actorName: String
    var action: String
    var entityType: String
    var entityId: String
    var projectId: String?
    var detailsJson: String
    var occurredAt: String

    init(_ e: ActivityLogEntry) {
        id = e.id.dbKey; companyId = e.companyId.dbKey
        createdAt = Timestamps.string(e.createdAt); updatedAt = Timestamps.string(e.updatedAt)
        deletedAt = nil; syncState = SyncState.pending.rawValue
        userId = e.userId?.dbKey; actorName = e.actorName; action = e.action.rawValue
        entityType = e.entityType; entityId = e.entityId.dbKey; projectId = e.projectId?.dbKey
        detailsJson = e.detailsJSON; occurredAt = Timestamps.string(e.occurredAt)
    }

    /// Append-only helper used inside repository transactions.
    static func append(_ db: Database, companyId: UUID, actor: ActivityActor, action: ActivityAction, entityType: String, entityId: UUID, projectId: UUID?, details: [String: String], at now: Date) throws {
        let json = try JSONSerialization.data(withJSONObject: details.sorted { $0.key < $1.key }.reduce(into: [String: String]()) { $0[$1.key] = $1.value }, options: [.sortedKeys])
        let entry = ActivityLogEntry(id: UUID(), companyId: companyId, userId: actor.userId, actorName: actor.name, action: action, entityType: entityType,
                                     entityId: entityId, projectId: projectId, detailsJSON: String(decoding: json, as: UTF8.self), occurredAt: now,
                                     createdAt: now, updatedAt: now, deletedAt: nil)
        try ActivityLogRecord(entry).insert(db)
    }
}
