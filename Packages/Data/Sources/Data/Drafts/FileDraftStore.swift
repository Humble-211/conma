import Foundation
import Domain

public final class FileDraftStore: DraftStore {
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("project-wizard.json") }

    public init(directory: URL) { self.directory = directory }

    public static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ConMa", isDirectory: true).appendingPathComponent("drafts", isDirectory: true)
    }

    public func load() throws -> ProjectDraft? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Foundation.Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode(ProjectDraft.self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let corrupt = directory.appendingPathComponent("project-wizard.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: corrupt)
            return nil
        }
    }

    public func save(_ draft: ProjectDraft) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(draft).write(to: fileURL, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
