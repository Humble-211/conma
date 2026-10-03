import Foundation
import Domain

/// One wizard at a time; identity is irrelevant for fullScreenCover(item:).
extension ProjectDraft: Identifiable { public var id: Int { 0 } }
