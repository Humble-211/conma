// Packages/Data/Sources/Data/Receipts/FileReceiptStore.swift
import Foundation

/// Receipt JPEGs on disk at `<root>/Receipts/<expenseId>/<imageId>.jpg`; `receipt_images.file_path` stores the part after `root`.
public struct FileReceiptStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    /// Application Support (included in the device backup on purpose: receipts matter at tax time).
    public static func applicationSupport() -> FileReceiptStore {
        FileReceiptStore(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }

    public static func relativePath(expenseId: UUID, imageId: UUID) -> String {
        "Receipts/\(expenseId.dbKey)/\(imageId.dbKey).jpg"
    }

    /// Creates the folder, writes atomically, returns the relative path to store in the DB.
    public func write(_ jpeg: Data, expenseId: UUID, imageId: UUID) throws -> String {
        let relative = Self.relativePath(expenseId: expenseId, imageId: imageId)
        let target = url(for: relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try jpeg.write(to: target, options: .atomic)
        return relative
    }

    public func url(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath, isDirectory: false)
    }

    /// Best effort; only used to roll back files of an insert whose transaction failed.
    public func remove(relativePath: String) {
        try? FileManager.default.removeItem(at: url(for: relativePath))
    }
}
