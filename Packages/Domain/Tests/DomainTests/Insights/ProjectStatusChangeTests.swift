import XCTest
@testable import Domain

final class ProjectStatusChangeTests: XCTestCase {
    let c = Fx.customer("X")
    func p(_ s: ProjectStatus, progress: Int?) -> Project { Fx.project("p", customer: c, status: s, contract: 1, progress: progress, start: nil, end: nil) }

    func testSuggestsProgress100OnlyForWorkDoneWithoutManualProgress() {
        XCTAssertTrue(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .completed).suggestProgress100)
        XCTAssertTrue(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .awaitingFinalPayment).suggestProgress100)
        XCTAssertFalse(ProjectStatusChange.apply(p(.inProgress, progress: 40), to: .completed).suggestProgress100)
        XCTAssertFalse(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .onHold).suggestProgress100)
    }
    func testRequiresConfirmationForTerminal() {
        XCTAssertTrue(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .closed).requiresConfirmation)
        XCTAssertTrue(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .cancelled).requiresConfirmation)
        XCTAssertFalse(ProjectStatusChange.apply(p(.inProgress, progress: nil), to: .completed).requiresConfirmation)
    }
    func testApplySetsStatus() {
        let o = ProjectStatusChange.apply(p(.estimate, progress: nil), to: .scheduled)
        XCTAssertEqual(o.project.status, .scheduled)
    }
    func testManualProgressRange() throws {
        XCTAssertEqual(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: nil), to: 0).manualProgress, 0)
        XCTAssertEqual(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: nil), to: 100).manualProgress, 100)
        XCTAssertNil(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: 5), to: nil).manualProgress)
        XCTAssertThrowsError(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: nil), to: -1)) { XCTAssertEqual($0 as? DomainError, .invalidProgress) }
        XCTAssertThrowsError(try ProjectStatusChange.setManualProgress(p(.inProgress, progress: nil), to: 101))
    }
}
