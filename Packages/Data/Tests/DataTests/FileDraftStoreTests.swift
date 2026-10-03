import XCTest
import Domain
@testable import Data

final class FileDraftStoreTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("draft-tests-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testEmptyLoadIsNil() throws {
        XCTAssertNil(try FileDraftStore(directory: dir).load())
    }

    func testSaveLoadClear() throws {
        let store = FileDraftStore(directory: dir)
        var d = ProjectDraft(); d.jobType = .roofing; d.step = 4; d.contractValue = Money(Decimal(string: "12500.50")!, .cad)
        try store.save(d)
        XCTAssertEqual(try store.load(), d)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("project-wizard.json").path))
        try store.clear()
        XCTAssertNil(try store.load())
        try store.clear() // idempotent
    }

    func testCorruptFileIsRenamedAndReturnsNil() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let file = dir.appendingPathComponent("project-wizard.json")
        try "not json".data(using: .utf8)!.write(to: file)
        let store = FileDraftStore(directory: dir)
        XCTAssertNil(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let renamed = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("project-wizard.corrupt-") }
        XCTAssertEqual(renamed.count, 1)
    }
}
