import Foundation

public struct ActivityActor: Sendable, Hashable {
    public let userId: UUID?
    public let name: String

    public init(userId: UUID?, name: String) {
        self.userId = userId
        self.name = name
    }
}
