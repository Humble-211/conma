import Foundation

public enum ProjectRoute: Hashable {
    case detail(UUID)
    /// Full activity list of a project.
    case activity(UUID)
}
