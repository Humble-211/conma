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
    func testExpenseAddedWithVendor() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.expenseAdded, #"{"category":"materials","categoryName":"","total":"2712.00","vendor":"Home Depot"}"#)),
                       .expense(action: .expenseAdded, title: .vendor("Home Depot"), total: "2712.00", previousTotal: nil))
    }
    func testExpenseDeletedCustomWithoutVendor() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.expenseDeleted, #"{"category":"custom","categoryName":"Scaffolding","total":"40.00","vendor":""}"#)),
                       .expense(action: .expenseDeleted, title: .customCategory("Scaffolding"), total: "40.00", previousTotal: nil))
    }
    func testExpenseUpdatedCarriesFrom() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.expenseUpdated, #"{"category":"fuel","categoryName":"","from":"250.00","total":"260.00","vendor":""}"#)),
                       .expense(action: .expenseUpdated, title: .category(.fuel), total: "260.00", previousTotal: "250.00"))
    }
    func testExpenseMissingTotalIsPlain() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.expenseAdded, #"{"category":"fuel"}"#)), .plain(.expenseAdded))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.expenseAdded, #"{"category":"bogus","total":"1.00"}"#)), .plain(.expenseAdded))
    }

    func testPaymentReceivedLinked() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentReceived, #"{"amount":"7600.00","currency":"CAD","item":"schedule.row.deposit","method":"eTransfer"}"#)),
                       .payment(action: .paymentReceived, title: .item("schedule.row.deposit"), amount: "7600.00", previousAmount: nil))
    }
    func testPaymentUnlinkedUsesMethod() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentReceived, #"{"amount":"1000.00","currency":"CAD","item":"","method":"cheque"}"#)),
                       .payment(action: .paymentReceived, title: .method(.cheque), amount: "1000.00", previousAmount: nil))
    }
    func testPaymentUpdatedAndDeleted() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentUpdated, #"{"amount":"450.00","currency":"CAD","from":"400.00","item":"","method":"cash"}"#)),
                       .payment(action: .paymentUpdated, title: .method(.cash), amount: "450.00", previousAmount: "400.00"))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentDeleted, #"{"amount":"400.00","currency":"CAD","from":"1.00","item":"Deposit","method":"cash"}"#)),
                       .payment(action: .paymentDeleted, title: .item("Deposit"), amount: "400.00", previousAmount: nil))
    }
    func testLabourLoggedAndUpdated() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourLogged, #"{"currency":"CAD","names":"Mike, John","people":"2","total":"470.00","workDate":"2026-10-03"}"#)),
                       .labour(action: .labourLogged, names: "Mike, John", total: "470.00", previousTotal: nil))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourUpdated, #"{"currency":"CAD","from":"1400.00","names":"David","people":"1","total":"1600.00","workDate":"2026-09-25"}"#)),
                       .labour(action: .labourUpdated, names: "David", total: "1600.00", previousTotal: "1400.00"))
    }
    func testUpdatesWithoutMoneyChangeHaveNoPrevious() {
        // New rows omit "from"; older rows wrote "from" equal to the new value — both read as a plain update.
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentUpdated, #"{"amount":"400.00","currency":"CAD","item":"","method":"cash"}"#)),
                       .payment(action: .paymentUpdated, title: .method(.cash), amount: "400.00", previousAmount: nil))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentUpdated, #"{"amount":"400.00","currency":"CAD","from":"400.00","item":"Deposit","method":"cash"}"#)),
                       .payment(action: .paymentUpdated, title: .item("Deposit"), amount: "400.00", previousAmount: nil))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourUpdated, #"{"currency":"CAD","names":"David","people":"1","total":"1600.00","workDate":"2026-09-25"}"#)),
                       .labour(action: .labourUpdated, names: "David", total: "1600.00", previousTotal: nil))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourUpdated, #"{"currency":"CAD","from":"1600.00","names":"David","people":"1","total":"1600.00","workDate":"2026-09-25"}"#)),
                       .labour(action: .labourUpdated, names: "David", total: "1600.00", previousTotal: nil))
    }
    func testPaymentAndLabourMissingFieldsArePlain() {
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentReceived, #"{"amount":"1.00"}"#)), .plain(.paymentReceived))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.paymentReceived, #"{"amount":"1.00","method":"bitcoin"}"#)), .plain(.paymentReceived))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourDeleted, #"{"names":"","total":"1.00"}"#)), .plain(.labourDeleted))
        XCTAssertEqual(ActivityDescription.detail(for: entry(.labourLogged, "not json")), .plain(.labourLogged))
    }
    func testCurrencyFromDetails() {
        XCTAssertEqual(ActivityDescription.currency(for: entry(.paymentReceived, #"{"amount":"1.00","currency":"USD","item":"","method":"cash"}"#)), .usd)
        XCTAssertNil(ActivityDescription.currency(for: entry(.expenseAdded, #"{"category":"fuel","total":"1.00"}"#)))
        XCTAssertNil(ActivityDescription.currency(for: entry(.paymentReceived, "not json")))
        XCTAssertEqual(ActivityAction.allCases.count, 20)
    }
}
