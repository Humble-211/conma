import XCTest
@testable import Domain

final class ActivityDescriptionTests: XCTestCase {
    func entry(_ action: ActivityAction, _ json: String) -> ActivityLogEntry {
        ActivityLogEntry(id: UUID(), companyId: Fx.companyId, userId: nil, actorName: "Duc", action: action, entityType: "project", entityId: UUID(), projectId: UUID(), detailsJSON: json, occurredAt: Fx.now, createdAt: Fx.now, updatedAt: Fx.now, deletedAt: nil)
    }
    func testStatus() { XCTAssertEqual(ActivityDescription.detail(for: entry(.statusChanged, #"{"from":"estimate","to":"inProgress"}"#)), .statusChanged(from: .estimate, to: .inProgress)) }
    func testProgressWithEmptyFrom() { XCTAssertEqual(ActivityDescription.detail(for: entry(.progressChanged, #"{"from":"","to":"60"}"#)), .progressChanged(from: nil, to: 60)) }
    func testContract() { XCTAssertEqual(ActivityDescription.detail(for: entry(.contractValueChanged, #"{"from":"30000.00","to":"32000.00"}"#)), .contractValueChanged(from: "30000.00", to: "32000.00")) }
    func testEstimateWithGroup() { XCTAssertEqual(ActivityDescription.detail(for: entry(.estimateChanged, #"{"group":"material","from":"0.00","to":"7900.00"}"#)), .estimateChanged(group: .material, from: "0.00", to: "7900.00")) }
    func testSchedule() { XCTAssertEqual(ActivityDescription.detail(for: entry(.scheduleChanged, #"{"from":"0.00","to":"38000.00"}"#)), .scheduleChanged(from: "0.00", to: "38000.00")) }
    func testCustomer() { XCTAssertEqual(ActivityDescription.detail(for: entry(.customerChanged, #"{"from":"Ann","to":"Bob","fromId":"x","toId":"y"}"#)), .customerChanged(fromName: "Ann", toName: "Bob")) }
    func testPlainAndCorrupt() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.projectCreated, #"{"name":"K"}"#)), .plain(.projectCreated))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.statusChanged, "not json")), .plain(.statusChanged))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.statusChanged, #"{"from":"bogus","to":"inProgress"}"#)), .plain(.statusChanged))
    }
}
