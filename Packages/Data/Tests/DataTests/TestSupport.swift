import XCTest

func XCTAssertThrowsErrorAsync(_ expression: @autoclosure () async throws -> Void, _ check: (Error) -> Void = { _ in }, file: StaticString = #filePath, line: UInt = #line) async {
    do { try await expression(); XCTFail("expected error", file: file, line: line) } catch { check(error) }
}
