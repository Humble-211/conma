import Foundation

public protocol DraftStore: Sendable {
    func load() throws -> ProjectDraft?
    func save(_ draft: ProjectDraft) throws
    func clear() throws
}
