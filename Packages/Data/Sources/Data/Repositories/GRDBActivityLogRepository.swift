import Foundation
import GRDB
import Domain

public final class GRDBActivityLogRepository: ActivityLogRepository {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }

    public func observeForProject(projectId: UUID, limit: Int) -> AsyncThrowingStream<[ActivityLogEntry], Error> {
        let key = projectId.dbKey
        let observation = ValueObservation.tracking { db in try Self.fetch(db, projectId: key, limit: limit) }
        return GRDBInsightsRepository.stream(observation, in: database.writer)
    }

    public func list(projectId: UUID) async throws -> [ActivityLogEntry] {
        let key = projectId.dbKey
        return try await database.writer.read { db in try Self.fetch(db, projectId: key, limit: nil) }
    }

    private static func fetch(_ db: Database, projectId: String, limit: Int?) throws -> [ActivityLogEntry] {
        var request = ActivityLogRecord.filter(Column("project_id") == projectId && Column("deleted_at") == nil)
            .order(Column("occurred_at").desc, Column.rowID.desc)
        if let limit { request = request.limit(limit) }
        // Rows written by a newer app version (unknown action code) are skipped instead of failing the whole stream.
        return try request.fetchAll(db).compactMap { record in
            ActivityAction(rawValue: record.action) == nil ? nil : try record.toDomain()
        }
    }
}
