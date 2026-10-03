# Projects — Create & Browse (2a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Contractor tạo project bằng wizard 12 bước (4 bắt buộc, nháp tự lưu), duyệt danh sách project theo phase, xem/sửa chi tiết project theo section, quản lý khách hàng — trên nền Foundation đã có.

**Architecture:** `ProjectDraft` (Domain, Codable) là state wizard, file nháp và input cho edit sheet; `ProjectDraftAssembler`/`ScheduleMath`/`DraftDiff` là hàm thuần test trên Linux. Data thêm hai record + hai repository (estimate lines, schedule items), `create(bundle)` trong một transaction, `observeDetail`, `FileDraftStore`. Features: `ProjectsFeature` (wizard 12 step view, list, detail), `CustomersFeature`; mỗi step view dùng cả trong wizard lẫn edit sheet.

**Tech Stack:** Swift 6 toolchain / Swift 5 mode, SwiftUI + Observation, GRDB 7, XCTest, Python scripts, GitHub Actions (đã có từ Foundation).

**Spec:** `docs/superpowers/specs/2026-10-03-projects-create-browse-design.md` (đọc trước; Phụ lục B là catalog cho Task 11). Nền tảng: `docs/superpowers/specs/2026-10-02-foundation-design.md`.

## Global Constraints

- iOS 17+; `Domain` chỉ import Foundation; `Features` không import `Data`; chỉ `App` import `Data`.
- Tiền luôn là `Money` (2 chữ số, `Money.rounded` là điểm làm tròn duy nhất); không `Double`/`Float` trong Domain/Data; `Percentage(points:)` là điểm phần trăm.
- Bắt buộc để tạo project: jobType (+customJobType nếu other), customer, address.line, contractValue; mọi thứ khác optional; project tạo ở `status = .estimate`.
- Schedule: `amount` có thẩm quyền, `percentage` chỉ sinh/hiển thị; tổng ≠ contract là cảnh báo, không chặn; contract = 0 không chia cho 0.
- Soft delete, không xóa vật lý; activity log trong cùng transaction; `save` lên id đã xóa → `DataError.notFound`; currency project ≠ company → `DomainError.currencyMismatch`.
- Mọi chuỗi hiển thị là key catalog `a.b.c`, English source, Việt 100 %, thuật ngữ nghề giữ tiếng Anh; `Text(verbatim:)` cho dữ liệu người dùng; `python scripts/check_localization.py` và `scripts/lint_sources.py` phải in `0 error(s)` trước mỗi commit chạm Swift/catalog.
- Không `try!`, `fatalError`, force-unwrap trong code production (test được phép `!`).
- Số nhập/hiển thị theo `AppSettings.resolvedLocale`; lưu canonical (dấu chấm thập phân).
- View model không được tạo trong `body` (sở hữu bởi `@State` ở wrapper, như `App/Screens.swift`).
- Commit tiếng Anh `type(scope): summary`, **không** trailer `Co-Authored-By`.
- Toolchain: Domain test chạy local (Windows, `swift test --package-path Packages/Domain`); Data/Features/App chỉ compile trên macOS CI — implementer đọc kỹ, CI là verifier; push lên nhánh `worktree-*` để CI chạy.

## Review Focus

1. Nhập "1.500,50" với `--locale vi` vào `MoneyField` phải lưu `1500.50`; nhập "1,500.50" với en cũng `1500.50`. → Task 11 (DesignSystem test không chạy được local; UI test (f) ở Task 22 pin).
2. Contract = 0 (hoặc chưa nhập) khi đã chọn template schedule: mọi amount = 0, cảnh báo `.contractZero`, không crash. → Task 3.
3. Đổi job type sau khi đã điền scope fields: hỏi Giữ/Xóa/Hủy, "Giữ" biến field lạ thành `custom:<label>`. → Task 14.
4. Address line toàn khoảng trắng → `.missing([.addressLine])`. → Task 5.
5. File nháp hỏng (JSON sai) → `load()` trả nil, file đổi tên, app không crash; wizard bị kill giữa chừng → nháp mở lại đúng `step`. → Task 10 + Task 22 (c).

---

## Bố cục file

```
Packages/Domain/Sources/Domain/
  Drafts/{ProjectDraft.swift,OtherCostKind.swift,PaymentScheduleTemplate.swift,ScheduleMath.swift,DraftFinancialPreview.swift,ProjectDraftAssembler.swift,DraftSeed.swift,DraftDiff.swift}
  Repositories/{ProjectRepository.swift (sửa),ProjectEstimateRepository.swift,PaymentScheduleRepository.swift,CustomerRepository.swift (sửa),DraftStore.swift}
  Entities/ActivityLog.swift (thêm case)
Packages/Domain/Tests/DomainTests/{ProjectDraftTests,PaymentScheduleTemplateTests,ScheduleMathTests,DraftFinancialPreviewTests,ProjectDraftAssemblerTests,DraftDiffTests}.swift
Packages/Data/Sources/Data/
  Records/{ProjectEstimateLineRecord.swift,PaymentScheduleItemRecord.swift}
  Repositories/{GRDBProjectEstimateRepository.swift,GRDBPaymentScheduleRepository.swift,GRDBProjectRepository.swift (sửa),GRDBCustomerRepository.swift (sửa)}
  Drafts/FileDraftStore.swift
  Seed/SampleData.swift (sửa)
  Database/DataError.swift (thêm case)
Packages/Data/Tests/DataTests/{EstimateRepositoryTests,ScheduleRepositoryTests,ProjectCreateTests,CustomerObserveTests,FileDraftStoreTests}.swift
Packages/DesignSystem/Sources/DesignSystem/Components/{MoneyField.swift,DecimalField.swift,ChoiceChips.swift,StepHeader.swift}
Packages/Features/Sources/
  FeatureSupport/{ScopeFieldCatalog.swift,MaterialSuggestions.swift,DraftLabels.swift,ProjectCardView.swift (chuyển từ HomeFeature),PhaseFilter.swift}
  ProjectsFeature/
    Wizard/{ProjectWizardViewModel.swift,ProjectWizardView.swift,WizardStep.swift,StepFooter.swift}
    Wizard/Steps/{JobTypeStep.swift,CustomerStep.swift,LocationStep.swift,ScopeStep.swift,TimelineStep.swift,LabourStep.swift,MaterialStep.swift,OtherCostsStep.swift,PriceStep.swift,DepositStep.swift,ScheduleStep.swift,ReviewStep.swift}
    List/{ProjectsListView.swift,ProjectsListViewModel.swift,DraftBanner.swift}
    Detail/{ProjectDetailView.swift,ProjectDetailViewModel.swift,EditSectionSheet.swift}
  CustomersFeature/{CustomersListView.swift,CustomersListViewModel.swift,CustomerFormView.swift,CustomerProfileView.swift,CustomerProfileViewModel.swift}
  HomeFeature/{HomeView.swift (sửa: tap → detail),ProjectCardView.swift (xóa)}
  MoreFeature/MoreView.swift (thêm link Customers)
App/{AppContainer.swift (thêm repos + draft store),Screens.swift (thêm wrappers),RootTabView.swift (Projects tab thật)}
App/Resources/Localizable.xcstrings (thêm key theo từng task)
UITests/{ProjectsFlowTests.swift,ScreenshotTests.swift (mở rộng)}
scripts/check_localization.py (mở rộng: key sinh từ catalog Swift)
```

---

### Task 1: `ProjectDraft` và các kiểu nháp

**Files:**
- Create: `Packages/Domain/Sources/Domain/Drafts/ProjectDraft.swift`, `Packages/Domain/Sources/Domain/Drafts/OtherCostKind.swift`
- Test: `Packages/Domain/Tests/DomainTests/ProjectDraftTests.swift`

**Interfaces:**
- Produces (tất cả `public`, `Codable, Equatable, Sendable`):
  - `enum OtherCostKind: String, CaseIterable { subcontractors, equipmentRental, toolRental, permits, inspectionFees, dumpster, delivery, parking, gas, wasteDisposal, other; var costGroup: CostGroup }`
  - `struct NewCustomerInput { name, phone?, email?, preferredContact: ContactMethod?, companyName?, secondaryContact?, notes? }`
  - `enum CustomerChoice { existing(UUID), new(NewCustomerInput) }`
  - `enum LabourEntryMode: String { quick, detailed }`
  - `struct LabourQuickInput { workers: Int?, dailyRate: Money?, days: Decimal? }`
  - `struct DraftEstimateLine: Identifiable { id: UUID, label: String, amount: Money, quantity: Decimal?, unitRate: Money?, costGroup: CostGroup, otherKind: OtherCostKind?, sortOrder: Int }`
  - `struct DraftScopeField: Identifiable { id: UUID, key: String, value: String, sortOrder: Int }`
  - `enum DepositMode { percentage(Percentage), fixed(Money) }`; `struct DraftDeposit { mode: DepositMode, deadline: CalendarDate?, requiredToStart: Bool }`
  - `struct DraftScheduleRow: Identifiable { id: UUID, label: String, percentage: Percentage?, amount: Money?, dueDate: CalendarDate?, trigger: String?, isDeposit: Bool }`
  - `enum PaymentScheduleTemplate: String, CaseIterable { depositFinal, depositProgressFinal, fourStage, custom }` (chỉ khai báo; `rows` ở Task 2)
  - `enum DraftField: String { jobType, customJobType, customer, addressLine, contractValue }`
  - `enum DraftError: Error, Equatable { missing(Set<DraftField>), negativeAmount, completionBeforeStart, invalidTimeline, currencyMismatch }`
  - `struct ProjectDraft` với mọi trường của spec §3.1 và `init()`; `var isEmpty: Bool` (không trường nào có giá trị ngoài `step`/`updatedAt`/`labourMode`).

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class ProjectDraftTests: XCTestCase {
    func testEmptyDraft() {
        let d = ProjectDraft()
        XCTAssertTrue(d.isEmpty)
        XCTAssertEqual(d.step, 1)
        XCTAssertEqual(d.labourMode, .quick)
        XCTAssertNil(d.jobType)
        XCTAssertTrue(d.schedule.isEmpty)
    }

    func testIsEmptyFalseWhenAnyFieldSet() {
        var d = ProjectDraft(); d.jobType = .kitchen
        XCTAssertFalse(d.isEmpty)
        d = ProjectDraft(); d.address = Address(line: "1 Main", unit: nil, city: nil, region: nil, postalCode: nil)
        XCTAssertFalse(d.isEmpty)
        d = ProjectDraft(); d.step = 5
        XCTAssertTrue(d.isEmpty, "step alone does not make a draft")
    }

    func testCodableRoundTrip() throws {
        var d = ProjectDraft()
        d.jobType = .other; d.customJobType = "Sauna"
        d.customer = .new(NewCustomerInput(name: "Ann", phone: "416", email: nil, preferredContact: .text, companyName: nil, secondaryContact: nil, notes: nil))
        d.address = Address(line: "123 Main", unit: "2", city: "Toronto", region: "ON", postalCode: "M1M")
        d.scopeFields = [DraftScopeField(id: UUID(), key: "squareFootage", value: "1200", sortOrder: 0)]
        d.startDate = CalendarDate(storage: "2026-10-01"); d.estimatedCompletionDate = CalendarDate(storage: "2026-10-20")
        d.hoursPerDay = Decimal(string: "8.5")
        d.labourMode = .detailed
        d.labourLines = [DraftEstimateLine(id: UUID(), label: "Mike", amount: Money(2000, .cad), quantity: 8, unitRate: Money(250, .cad), costGroup: .labour, otherKind: nil, sortOrder: 0)]
        d.otherLines = [DraftEstimateLine(id: UUID(), label: "Dumpster", amount: Money(400, .cad), quantity: nil, unitRate: nil, costGroup: .other, otherKind: .dumpster, sortOrder: 0)]
        d.contractValue = Money(30_000, .cad)
        d.deposit = DraftDeposit(mode: .percentage(try Percentage.input(20)), deadline: CalendarDate(storage: "2026-10-10"), requiredToStart: true)
        d.scheduleTemplate = .fourStage
        d.schedule = [DraftScheduleRow(id: UUID(), label: "schedule.row.deposit", percentage: try Percentage.input(20), amount: Money(6000, .cad), dueDate: nil, trigger: nil, isDeposit: true)]
        d.step = 11
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(ProjectDraft.self, from: data)
        XCTAssertEqual(back, d)
    }

    func testOtherCostKindMapping() {
        XCTAssertEqual(OtherCostKind.allCases.count, 11)
        XCTAssertEqual(OtherCostKind.subcontractors.costGroup, .subcontractor)
        XCTAssertEqual(OtherCostKind.equipmentRental.costGroup, .equipment)
        XCTAssertEqual(OtherCostKind.toolRental.costGroup, .equipment)
        XCTAssertEqual(OtherCostKind.permits.costGroup, .permit)
        XCTAssertEqual(OtherCostKind.inspectionFees.costGroup, .permit)
        for k in [OtherCostKind.dumpster, .delivery, .parking, .gas, .wasteDisposal, .other] { XCTAssertEqual(k.costGroup, .other, "\(k)") }
    }

    func testDepositModeCodable() throws {
        let fixed = DraftDeposit(mode: .fixed(Money(5000, .cad)), deadline: nil, requiredToStart: false)
        let back = try JSONDecoder().decode(DraftDeposit.self, from: JSONEncoder().encode(fixed))
        XCTAssertEqual(back, fixed)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'ProjectDraft' in scope`.

- [ ] **Step 3: Viết `OtherCostKind.swift`**

```swift
/// Wizard step 8 "Other costs" kinds (spec 3.1) mapped onto the single cost taxonomy.
public enum OtherCostKind: String, Codable, Sendable, CaseIterable, Hashable {
    case subcontractors, equipmentRental, toolRental, permits, inspectionFees
    case dumpster, delivery, parking, gas, wasteDisposal, other

    public var costGroup: CostGroup {
        switch self {
        case .subcontractors: return .subcontractor
        case .equipmentRental, .toolRental: return .equipment
        case .permits, .inspectionFees: return .permit
        case .dumpster, .delivery, .parking, .gas, .wasteDisposal, .other: return .other
        }
    }
}
```

- [ ] **Step 4: Viết `ProjectDraft.swift`**

```swift
import Foundation

public struct NewCustomerInput: Codable, Equatable, Sendable {
    public var name: String
    public var phone: String?
    public var email: String?
    public var preferredContact: ContactMethod?
    public var companyName: String?
    public var secondaryContact: String?
    public var notes: String?

    public init(name: String, phone: String?, email: String?, preferredContact: ContactMethod?, companyName: String?, secondaryContact: String?, notes: String?) {
        self.name = name; self.phone = phone; self.email = email; self.preferredContact = preferredContact
        self.companyName = companyName; self.secondaryContact = secondaryContact; self.notes = notes
    }
}

public enum CustomerChoice: Codable, Equatable, Sendable {
    case existing(UUID)
    case new(NewCustomerInput)
}

public enum LabourEntryMode: String, Codable, Equatable, Sendable { case quick, detailed }

public struct LabourQuickInput: Codable, Equatable, Sendable {
    public var workers: Int?
    public var dailyRate: Money?
    public var days: Decimal?
    public init(workers: Int?, dailyRate: Money?, days: Decimal?) { self.workers = workers; self.dailyRate = dailyRate; self.days = days }
}

public struct DraftEstimateLine: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var amount: Money
    public var quantity: Decimal?
    public var unitRate: Money?
    public var costGroup: CostGroup
    public var otherKind: OtherCostKind?
    public var sortOrder: Int

    public init(id: UUID, label: String, amount: Money, quantity: Decimal?, unitRate: Money?, costGroup: CostGroup, otherKind: OtherCostKind?, sortOrder: Int) {
        self.id = id; self.label = label; self.amount = amount; self.quantity = quantity; self.unitRate = unitRate
        self.costGroup = costGroup; self.otherKind = otherKind; self.sortOrder = sortOrder
    }
}

public struct DraftScopeField: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var key: String
    public var value: String
    public var sortOrder: Int
    public init(id: UUID, key: String, value: String, sortOrder: Int) { self.id = id; self.key = key; self.value = value; self.sortOrder = sortOrder }
}

public enum DepositMode: Codable, Equatable, Sendable {
    case percentage(Percentage)
    case fixed(Money)
}

public struct DraftDeposit: Codable, Equatable, Sendable {
    public var mode: DepositMode
    public var deadline: CalendarDate?
    public var requiredToStart: Bool
    public init(mode: DepositMode, deadline: CalendarDate?, requiredToStart: Bool) { self.mode = mode; self.deadline = deadline; self.requiredToStart = requiredToStart }
}

public struct DraftScheduleRow: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var percentage: Percentage?
    public var amount: Money?
    public var dueDate: CalendarDate?
    public var trigger: String?
    public var isDeposit: Bool

    public init(id: UUID, label: String, percentage: Percentage?, amount: Money?, dueDate: CalendarDate?, trigger: String?, isDeposit: Bool) {
        self.id = id; self.label = label; self.percentage = percentage; self.amount = amount; self.dueDate = dueDate; self.trigger = trigger; self.isDeposit = isDeposit
    }
}

public enum PaymentScheduleTemplate: String, Codable, Equatable, Sendable, CaseIterable {
    case depositFinal, depositProgressFinal, fourStage, custom
}

public enum DraftField: String, Codable, Sendable, Hashable { case jobType, customJobType, customer, addressLine, contractValue }

public enum DraftError: Error, Equatable, Sendable {
    case missing(Set<DraftField>)
    case negativeAmount
    case completionBeforeStart
    case invalidTimeline
    case currencyMismatch
}

/// Wizard state, draft file and edit-sheet input in one value (spec 3.1).
public struct ProjectDraft: Codable, Equatable, Sendable {
    public var jobType: JobType?
    public var customJobType: String?
    public var customer: CustomerChoice?
    public var projectName: String?
    public var address: Address?
    public var scopeDescription: String?
    public var scopeFields: [DraftScopeField] = []
    public var startDate: CalendarDate?
    public var estimatedCompletionDate: CalendarDate?
    public var workingDays: Int?
    public var hoursPerDay: Decimal?
    public var workersPerDay: Int?
    public var labourMode: LabourEntryMode = .quick
    public var labourQuick: LabourQuickInput?
    public var labourLines: [DraftEstimateLine] = []
    public var materialLines: [DraftEstimateLine] = []
    public var otherLines: [DraftEstimateLine] = []
    public var contractValue: Money?
    public var deposit: DraftDeposit?
    public var scheduleTemplate: PaymentScheduleTemplate?
    public var schedule: [DraftScheduleRow] = []
    public var step: Int = 1
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)

    public init() {}

    /// True when nothing user-entered is present (step/updatedAt/labourMode are not content).
    public var isEmpty: Bool {
        jobType == nil && customJobType == nil && customer == nil && projectName == nil && address == nil && scopeDescription == nil
            && scopeFields.isEmpty && startDate == nil && estimatedCompletionDate == nil && workingDays == nil && hoursPerDay == nil
            && workersPerDay == nil && labourQuick == nil && labourLines.isEmpty && materialLines.isEmpty && otherLines.isEmpty
            && contractValue == nil && deposit == nil && scheduleTemplate == nil && schedule.isEmpty
    }
}
```

- [ ] **Step 5: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass (81 + 5).

- [ ] **Step 6: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add ProjectDraft value types for the project wizard"
```

---

### Task 2: `PaymentScheduleTemplate.rows(depositPercentage:)`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Drafts/PaymentScheduleTemplate.swift`
- Test: `Packages/Domain/Tests/DomainTests/PaymentScheduleTemplateTests.swift`

**Interfaces:**
- Produces: `extension PaymentScheduleTemplate { public func rows(depositPercentage: Percentage?) -> [DraftScheduleRow]; public static let labelKeys: [String: String] }`. Label của dòng là key: `schedule.row.deposit`, `schedule.row.progress`, `schedule.row.stage2`, `schedule.row.stage3`, `schedule.row.final`.

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class PaymentScheduleTemplateTests: XCTestCase {
    private func pts(_ rows: [DraftScheduleRow]) -> [Decimal] { rows.map { $0.percentage?.points ?? -1 } }

    func testDefaultRows() {
        XCTAssertEqual(pts(PaymentScheduleTemplate.depositFinal.rows(depositPercentage: nil)), [30, 70])
        XCTAssertEqual(pts(PaymentScheduleTemplate.depositProgressFinal.rows(depositPercentage: nil)), [30, 40, 30])
        XCTAssertEqual(pts(PaymentScheduleTemplate.fourStage.rows(depositPercentage: nil)), [20, 30, 30, 20])
        XCTAssertEqual(PaymentScheduleTemplate.fourStage.rows(depositPercentage: nil).map(\.label), ["schedule.row.deposit", "schedule.row.stage2", "schedule.row.stage3", "schedule.row.final"])
        XCTAssertEqual(PaymentScheduleTemplate.depositProgressFinal.rows(depositPercentage: nil).map(\.label), ["schedule.row.deposit", "schedule.row.progress", "schedule.row.final"])
    }

    func testFirstRowIsDepositOthersAreNot() {
        let rows = PaymentScheduleTemplate.fourStage.rows(depositPercentage: nil)
        XCTAssertEqual(rows.map(\.isDeposit), [true, false, false, false])
        XCTAssertTrue(rows.allSatisfy { $0.amount == nil && $0.dueDate == nil })
    }

    func testDepositOverrideSplitsRemainderProportionally() throws {
        let rows = PaymentScheduleTemplate.fourStage.rows(depositPercentage: try Percentage.input(25))
        XCTAssertEqual(pts(rows), [25, Decimal(string: "28.13")!, Decimal(string: "28.13")!, Decimal(string: "18.74")!])
        XCTAssertEqual(rows.reduce(Decimal(0)) { $0 + ($1.percentage?.points ?? 0) }, 100)
        XCTAssertEqual(pts(PaymentScheduleTemplate.depositFinal.rows(depositPercentage: try Percentage.input(50))), [50, 50])
        XCTAssertEqual(pts(PaymentScheduleTemplate.depositProgressFinal.rows(depositPercentage: try Percentage.input(10))), [10, Decimal(string: "51.43")!, Decimal(string: "38.57")!])
    }

    func testCustom() throws {
        XCTAssertEqual(PaymentScheduleTemplate.custom.rows(depositPercentage: nil), [])
        let rows = PaymentScheduleTemplate.custom.rows(depositPercentage: try Percentage.input(20))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].percentage?.points, 20)
        XCTAssertTrue(rows[0].isDeposit)
    }

    func testDepositHundredPercentLeavesZeroRows() throws {
        let rows = PaymentScheduleTemplate.depositFinal.rows(depositPercentage: try Percentage.input(100))
        XCTAssertEqual(pts(rows), [100, 0])
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `value of type 'PaymentScheduleTemplate' has no member 'rows'`.

- [ ] **Step 3: Viết code**

```swift
import Foundation

public extension PaymentScheduleTemplate {
    /// Base rows as (label key, percentage points). First row is the deposit.
    private var base: [(String, Decimal)] {
        switch self {
        case .depositFinal: return [("schedule.row.deposit", 30), ("schedule.row.final", 70)]
        case .depositProgressFinal: return [("schedule.row.deposit", 30), ("schedule.row.progress", 40), ("schedule.row.final", 30)]
        case .fourStage: return [("schedule.row.deposit", 20), ("schedule.row.stage2", 30), ("schedule.row.stage3", 30), ("schedule.row.final", 20)]
        case .custom: return []
        }
    }

    /// Spec 3.2: when a deposit percentage is given, the first row takes it and the remainder is
    /// split across the other rows in the template's proportions; the last row absorbs rounding.
    func rows(depositPercentage: Percentage?) -> [DraftScheduleRow] {
        if self == .custom {
            guard let deposit = depositPercentage else { return [] }
            return [DraftScheduleRow(id: UUID(), label: "schedule.row.deposit", percentage: deposit, amount: nil, dueDate: nil, trigger: nil, isDeposit: true)]
        }
        var points = base.map(\.1)
        if let deposit = depositPercentage?.points {
            let remainder = 100 - deposit
            let weights = Array(points.dropFirst())
            let weightSum = weights.reduce(Decimal(0), +)
            var split = weights.map { Money.rounded(remainder * $0 / weightSum, scale: 2) }
            if !split.isEmpty {
                let allButLast = split.dropLast().reduce(Decimal(0), +)
                split[split.count - 1] = remainder - allButLast
            }
            points = [deposit] + split
        }
        return zip(base, points).enumerated().map { index, pair in
            let (labelKey, pct) = (pair.0.0, pair.1)
            return DraftScheduleRow(id: UUID(), label: labelKey, percentage: Percentage.computed(pct), amount: nil, dueDate: nil, trigger: nil, isDeposit: index == 0)
        }
    }
}
```

Ghi chú: `Percentage.computed` làm tròn 1 chữ số — **không dùng được** cho 28.13. Thêm vào `Percentage.swift` một factory nội bộ cho module:

```swift
    /// Exact points without rounding or validation: template rows and re-hydration of stored values.
    public static func exact(_ points: Decimal) -> Percentage { Percentage(points: points) }
```

và trong `rows` dùng `Percentage.exact(pct)` thay `Percentage.computed(pct)`.

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass. Kiểm tra bằng tay ví dụ 25: remainder 75; weights 30/30/20 (sum 80); 75×30/80 = 28.125 → 28.13; 28.13; last = 75 − 56.26 = 18.74.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add payment schedule templates with deposit-aware split"
```

---

### Task 3: `ScheduleMath`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Drafts/ScheduleMath.swift`
- Test: `Packages/Domain/Tests/DomainTests/ScheduleMathTests.swift`

**Interfaces:**
- Produces:
  - `public enum EditedField: Equatable { case percentage(Int), amount(Int), none }`
  - `public enum ScheduleWarning: Equatable { case totalMismatch(difference: Money), contractZero }`
  - `public struct ScheduleResult: Equatable { rows: [DraftScheduleRow], total: Money, warning: ScheduleWarning? }`
  - `public enum ScheduleMath { static func recompute(rows:contract:edited:) -> ScheduleResult }`

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class ScheduleMathTests: XCTestCase {
    private func row(_ pct: Decimal?, amount: Decimal? = nil) -> DraftScheduleRow {
        DraftScheduleRow(id: UUID(), label: "x", percentage: pct.map { try! Percentage.input($0) }, amount: amount.map { Money($0, .cad) }, dueDate: nil, trigger: nil, isDeposit: false)
    }
    private func amounts(_ r: ScheduleResult) -> [String] { r.rows.map { $0.amount?.storageString ?? "nil" } }

    func testPercentagesProduceAmountsWithResidual() {
        let r = ScheduleMath.recompute(rows: [row(20), row(30), row(30), row(20)], contract: Money(Decimal(string: "30000.01")!, .cad), edited: .none)
        XCTAssertEqual(amounts(r), ["6000.00", "9000.00", "9000.00", "6000.01"])
        XCTAssertEqual(r.total.storageString, "30000.01")
        XCTAssertNil(r.warning)
    }

    func testEditingAmountRecomputesOnlyThatPercentage() {
        let base = ScheduleMath.recompute(rows: [row(50), row(50)], contract: Money(1000, .cad), edited: .none).rows
        var rows = base; rows[1].amount = Money(600, .cad)
        let r = ScheduleMath.recompute(rows: rows, contract: Money(1000, .cad), edited: .amount(1))
        XCTAssertEqual(r.rows[1].percentage?.points, 60)
        XCTAssertEqual(r.rows[0].amount?.storageString, "500.00")
        XCTAssertEqual(r.total.storageString, "1100.00")
        XCTAssertEqual(r.warning, .totalMismatch(difference: Money(100, .cad)))
    }

    func testEditingPercentageRecomputesAllAmounts() {
        var rows = [row(50), row(50)]; rows[0].percentage = try! Percentage.input(40)
        let r = ScheduleMath.recompute(rows: rows, contract: Money(1000, .cad), edited: .percentage(0))
        XCTAssertEqual(amounts(r), ["400.00", "500.00"])
        XCTAssertEqual(r.warning, .totalMismatch(difference: Money(-100, .cad)))
    }

    func testRowsWithoutPercentageKeepTheirAmount() {
        let r = ScheduleMath.recompute(rows: [row(nil, amount: 250), row(50)], contract: Money(1000, .cad), edited: .none)
        XCTAssertEqual(amounts(r), ["250.00", "500.00"])
    }

    func testContractZero() {
        let r = ScheduleMath.recompute(rows: [row(30), row(70)], contract: Money(0, .cad), edited: .none)
        XCTAssertEqual(amounts(r), ["0.00", "0.00"])
        XCTAssertEqual(r.warning, .contractZero)
        var rows = r.rows; rows[0].amount = Money(100, .cad)
        let r2 = ScheduleMath.recompute(rows: rows, contract: Money(0, .cad), edited: .amount(0))
        XCTAssertNil(r2.rows[0].percentage, "no division by zero")
    }

    func testEmptyRows() {
        let r = ScheduleMath.recompute(rows: [], contract: Money(1000, .cad), edited: .none)
        XCTAssertTrue(r.rows.isEmpty); XCTAssertEqual(r.total.storageString, "0.00"); XCTAssertNil(r.warning)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'ScheduleMath' in scope`.

- [ ] **Step 3: Viết code**

```swift
import Foundation

public enum EditedField: Equatable, Sendable { case percentage(Int), amount(Int), none }

public enum ScheduleWarning: Equatable, Sendable {
    case totalMismatch(difference: Money)
    case contractZero
}

public struct ScheduleResult: Equatable, Sendable {
    public let rows: [DraftScheduleRow]
    public let total: Money
    public let warning: ScheduleWarning?
}

public enum ScheduleMath {
    /// Spec 3.3. Percent edits re-derive every amount from percentages (residual on the last row
    /// when they total 100); an amount edit re-derives only that row's percentage.
    public static func recompute(rows: [DraftScheduleRow], contract: Money, edited: EditedField) -> ScheduleResult {
        var rows = rows
        let currency = contract.currency
        switch edited {
        case .amount(let i):
            if rows.indices.contains(i), let amount = rows[i].amount {
                rows[i].percentage = contract.isZero ? nil : Percentage.ratio(amount, over: contract)
            }
        case .percentage, .none:
            let withPct = rows.indices.filter { rows[$0].percentage != nil }
            let pcts = withPct.compactMap { rows[$0].percentage }
            let amounts = ScheduleSplitter.amounts(of: contract, percentages: pcts)
            for (k, index) in withPct.enumerated() { rows[index].amount = amounts[k] }
        }
        let total = rows.reduce(Money.zero(currency)) { acc, row in
            guard let amount = row.amount, let sum = try? acc.adding(amount) else { return acc }
            return sum
        }
        var warning: ScheduleWarning?
        if contract.isZero, rows.contains(where: { $0.percentage != nil }) {
            warning = .contractZero
        } else if !rows.isEmpty, total != contract, let diff = try? total.subtracting(contract) {
            warning = .totalMismatch(difference: diff)
        }
        return ScheduleResult(rows: rows, total: total, warning: warning)
    }
}
```

Lưu ý: `Percentage.ratio` làm tròn 1 chữ số (600/1000 → 60.0 ✓). Với `.amount` edit mà % khác đổi theo nhu cầu người dùng? Không — spec: chỉ dòng i.

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass. `testEditingPercentageRecomputesAllAmounts`: 40 + 50 = 90 ≠ 100 → không residual → 400/500, diff −100 ✓.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add ScheduleMath for percent/amount schedule editing"
```

---

### Task 4: `DraftFinancialPreview`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Drafts/DraftFinancialPreview.swift`
- Test: `Packages/Domain/Tests/DomainTests/DraftFinancialPreviewTests.swift`

**Interfaces:**
- Produces:
  - `public struct DraftFinancialPreview: Equatable { estimateByGroup: [CostGroup: Money], estimatedCost: Money, projectedProfit: Money?, projectedMargin: Percentage?, scheduleTotal: Money, scheduleWarning: ScheduleWarning?, depositAmount: Money? }`
  - `extension DraftFinancialPreview { public static func compute(_ draft: ProjectDraft, currency: CurrencyCode) -> DraftFinancialPreview }`
  - `extension ProjectDraft { public func allEstimateLines(currency: CurrencyCode) -> [DraftEstimateLine] }` — labour (quick → một dòng tổng hợp với `label = "schedule.row.labourQuick"`, `quantity = workers × days`, `unitRate = dailyRate`, `amount = rounded(dailyRate × workers × days)`; detailed → dòng với `amount = rounded(unitRate × quantity)` khi có cả hai) + material + other (amount tính lại khi có quantity & unitRate). Dùng chung với assembler (Task 5).

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class DraftFinancialPreviewTests: XCTestCase {
    private func line(_ amount: Decimal, _ group: CostGroup, qty: Decimal? = nil, rate: Decimal? = nil) -> DraftEstimateLine {
        DraftEstimateLine(id: UUID(), label: "l", amount: Money(amount, .cad), quantity: qty, unitRate: rate.map { Money($0, .cad) }, costGroup: group, otherKind: nil, sortOrder: 0)
    }

    func testQuickLabourBecomesOneLine() {
        var d = ProjectDraft()
        d.labourMode = .quick
        d.labourQuick = LabourQuickInput(workers: 4, dailyRate: Money(230, .cad), days: 10)
        let lines = d.allEstimateLines(currency: .cad)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].costGroup, .labour)
        XCTAssertEqual(lines[0].quantity, 40)
        XCTAssertEqual(lines[0].unitRate?.storageString, "230.00")
        XCTAssertEqual(lines[0].amount.storageString, "9200.00")
        XCTAssertEqual(lines[0].label, "schedule.row.labourQuick")
    }

    func testQuickLabourIncompleteProducesNoLine() {
        var d = ProjectDraft(); d.labourQuick = LabourQuickInput(workers: 4, dailyRate: nil, days: 10)
        XCTAssertTrue(d.allEstimateLines(currency: .cad).isEmpty)
    }

    func testDetailedLinesRecomputeAmountFromRateAndQuantity() {
        var d = ProjectDraft(); d.labourMode = .detailed
        d.labourLines = [line(1, .labour, qty: Decimal(string: "7.5")!, rate: Decimal(string: "250.01")!), line(500, .labour)]
        let lines = d.allEstimateLines(currency: .cad)
        XCTAssertEqual(lines.map { $0.amount.storageString }, ["1875.08", "500.00"])
    }

    func testPreviewNumbers() throws {
        var d = ProjectDraft()
        d.labourMode = .detailed
        d.labourLines = [line(8000, .labour)]
        d.materialLines = [line(6000, .material)]
        d.otherLines = [line(4000, .other)]
        d.contractValue = Money(30_000, .cad)
        d.deposit = DraftDeposit(mode: .percentage(try Percentage.input(20)), deadline: nil, requiredToStart: true)
        d.schedule = PaymentScheduleTemplate.fourStage.rows(depositPercentage: try Percentage.input(20))
        let p = DraftFinancialPreview.compute(d, currency: .cad)
        XCTAssertEqual(p.estimatedCost.storageString, "18000.00")
        XCTAssertEqual(p.estimateByGroup[.labour]?.storageString, "8000.00")
        XCTAssertNil(p.estimateByGroup[.permit])
        XCTAssertEqual(p.projectedProfit?.storageString, "12000.00")
        XCTAssertEqual(p.projectedMargin?.points, 40)
        XCTAssertEqual(p.scheduleTotal.storageString, "30000.00")
        XCTAssertNil(p.scheduleWarning)
        XCTAssertEqual(p.depositAmount?.storageString, "6000.00")
    }

    func testPreviewWithoutContract() {
        var d = ProjectDraft(); d.materialLines = [line(100, .material)]
        let p = DraftFinancialPreview.compute(d, currency: .cad)
        XCTAssertNil(p.projectedProfit); XCTAssertNil(p.projectedMargin); XCTAssertNil(p.depositAmount)
        XCTAssertEqual(p.estimatedCost.storageString, "100.00")
    }

    func testFixedDepositAndMismatchWarning() throws {
        var d = ProjectDraft()
        d.contractValue = Money(1000, .cad)
        d.deposit = DraftDeposit(mode: .fixed(Money(300, .cad)), deadline: nil, requiredToStart: false)
        d.schedule = [DraftScheduleRow(id: UUID(), label: "a", percentage: try Percentage.input(50), amount: nil, dueDate: nil, trigger: nil, isDeposit: true)]
        let p = DraftFinancialPreview.compute(d, currency: .cad)
        XCTAssertEqual(p.depositAmount?.storageString, "300.00")
        XCTAssertEqual(p.scheduleWarning, .totalMismatch(difference: Money(-500, .cad)))
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'DraftFinancialPreview' in scope`.

- [ ] **Step 3: Viết code**

```swift
import Foundation

public struct DraftFinancialPreview: Equatable, Sendable {
    public let estimateByGroup: [CostGroup: Money]
    public let estimatedCost: Money
    public let projectedProfit: Money?
    public let projectedMargin: Percentage?
    public let scheduleTotal: Money
    public let scheduleWarning: ScheduleWarning?
    public let depositAmount: Money?

    /// Spec 3.4. Pure; uses the same sums the assembler will persist.
    public static func compute(_ draft: ProjectDraft, currency: CurrencyCode) -> DraftFinancialPreview {
        let zero = Money.zero(currency)
        let lines = draft.allEstimateLines(currency: currency)
        var byGroup: [CostGroup: Money] = [:]
        for line in lines where line.amount.currency == currency {
            byGroup[line.costGroup] = (try? (byGroup[line.costGroup] ?? zero).adding(line.amount)) ?? byGroup[line.costGroup]
        }
        let estimatedCost = byGroup.values.reduce(zero) { (try? $0.adding($1)) ?? $0 }
        let contract = draft.contractValue
        let profit = contract.flatMap { try? $0.subtracting(estimatedCost) }
        let margin = contract.flatMap { c in profit.flatMap { Percentage.ratio($0, over: c) } }
        let schedule = ScheduleMath.recompute(rows: draft.schedule, contract: contract ?? zero, edited: .none)
        let deposit: Money? = draft.deposit.flatMap { dep in
            switch dep.mode {
            case .fixed(let m): return m
            case .percentage(let p): return contract?.multiplied(by: p)
            }
        }
        return DraftFinancialPreview(estimateByGroup: byGroup, estimatedCost: estimatedCost, projectedProfit: profit, projectedMargin: margin,
                                     scheduleTotal: schedule.total, scheduleWarning: draft.schedule.isEmpty ? nil : schedule.warning, depositAmount: deposit)
    }
}

public extension ProjectDraft {
    /// Labour (quick or detailed) + material + other, amounts re-derived from rate × quantity where both exist.
    func allEstimateLines(currency: CurrencyCode) -> [DraftEstimateLine] {
        var result: [DraftEstimateLine] = []
        switch labourMode {
        case .quick:
            if let q = labourQuick, let workers = q.workers, let rate = q.dailyRate, let days = q.days, workers > 0, days > 0 {
                let quantity = Decimal(workers) * days
                result.append(DraftEstimateLine(id: UUID(), label: "schedule.row.labourQuick", amount: rate.multiplied(by: quantity), quantity: quantity,
                                                unitRate: rate, costGroup: .labour, otherKind: nil, sortOrder: 0))
            }
        case .detailed:
            result.append(contentsOf: labourLines.map(Self.recomputed))
        }
        result.append(contentsOf: materialLines.map(Self.recomputed))
        result.append(contentsOf: otherLines.map(Self.recomputed))
        return result
    }

    private static func recomputed(_ line: DraftEstimateLine) -> DraftEstimateLine {
        guard let qty = line.quantity, let rate = line.unitRate else { return line }
        var copy = line
        copy.amount = rate.multiplied(by: qty)
        return copy
    }
}
```

Ghi chú: quick labour tạo `id` mới mỗi lần gọi; assembler (Task 5) dùng id này một lần khi tạo; edit sheet luôn seed `labourMode = .detailed` (Task 6) nên không có vấn đề id trôi.

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass. `testDetailedLines`: 250.01 × 7.5 = 1875.075 → 1875.08 ✓.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add draft financial preview and unified estimate lines"
```

---

### Task 5: `ProjectDraftAssembler` + `NewProjectBundle`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Drafts/ProjectDraftAssembler.swift`
- Test: `Packages/Domain/Tests/DomainTests/ProjectDraftAssemblerTests.swift`

**Interfaces:**
- Produces:
  - `public enum BundleWarning: Equatable { scheduleTotalMismatch(difference: Money), depositExceedsContract, scheduleEmpty }`
  - `public struct NewProjectBundle: Equatable, Sendable { project: Project, scopeFields: [ProjectScopeField], estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], newCustomer: Customer?, warnings: [BundleWarning] }`
  - `public enum ProjectDraftAssembler { static func assemble(_ draft: ProjectDraft, companyId: UUID, currency: CurrencyCode, now: Date) throws -> NewProjectBundle; static func defaultName(for draft: ProjectDraft) -> String? }`
  - `extension JobType { public var englishName: String }` (tên mặc định; "Deck / Fence", "Windows / Doors", "HVAC", "General Renovation", …)

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class ProjectDraftAssemblerTests: XCTestCase {
    let company = UUID(), existingCustomer = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func minimal() -> ProjectDraft {
        var d = ProjectDraft()
        d.jobType = .kitchen
        d.customer = .existing(existingCustomer)
        d.address = Address(line: "123 Main St", unit: nil, city: "Toronto", region: "ON", postalCode: nil)
        d.contractValue = Money(25_000, .cad)
        return d
    }
    private func assemble(_ d: ProjectDraft) throws -> NewProjectBundle { try ProjectDraftAssembler.assemble(d, companyId: company, currency: .cad, now: now) }
    private func missing(_ d: ProjectDraft) -> Set<DraftField>? {
        do { _ = try assemble(d); return nil } catch DraftError.missing(let f) { return f } catch { return nil }
    }

    func testMinimalDraftAssembles() throws {
        let b = try assemble(minimal())
        XCTAssertEqual(b.project.status, .estimate)
        XCTAssertEqual(b.project.name, "Kitchen")
        XCTAssertEqual(b.project.customerId, existingCustomer)
        XCTAssertEqual(b.project.companyId, company)
        XCTAssertEqual(b.project.contractValue.storageString, "25000.00")
        XCTAssertNil(b.project.manualProgress)
        XCTAssertFalse(b.project.depositRequiredToStart)
        XCTAssertEqual(b.project.createdAt, now); XCTAssertEqual(b.project.updatedAt, now)
        XCTAssertTrue(b.estimateLines.isEmpty); XCTAssertTrue(b.scheduleItems.isEmpty); XCTAssertNil(b.newCustomer)
        XCTAssertEqual(b.warnings, [.scheduleEmpty])
    }

    func testMissingFieldsAreCollected() {
        XCTAssertEqual(missing(ProjectDraft()), [.jobType, .customer, .addressLine, .contractValue])
        var d = minimal(); d.jobType = .other
        XCTAssertEqual(missing(d), [.customJobType])
        d.customJobType = "  "
        XCTAssertEqual(missing(d), [.customJobType])
        d = minimal(); d.address = Address(line: "   ", unit: nil, city: nil, region: nil, postalCode: nil)
        XCTAssertEqual(missing(d), [.addressLine])
        d = minimal(); d.customer = .new(NewCustomerInput(name: " ", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil))
        XCTAssertEqual(missing(d), [.customer])
    }

    func testCustomJobTypeNameAndNewCustomer() throws {
        var d = minimal(); d.jobType = .other; d.customJobType = "Sauna build"
        d.customer = .new(NewCustomerInput(name: "Ann Lee", phone: "416", email: nil, preferredContact: .text, companyName: nil, secondaryContact: nil, notes: nil))
        let b = try assemble(d)
        XCTAssertEqual(b.project.name, "Sauna build")
        XCTAssertEqual(b.newCustomer?.name, "Ann Lee")
        XCTAssertEqual(b.project.customerId, b.newCustomer?.id)
        XCTAssertEqual(b.newCustomer?.companyId, company)
    }

    func testExplicitNameWins() throws {
        var d = minimal(); d.projectName = "Smith kitchen"
        XCTAssertEqual(try assemble(d).project.name, "Smith kitchen")
        XCTAssertEqual(JobType.deckFence.englishName, "Deck / Fence")
        XCTAssertEqual(JobType.hvac.englishName, "HVAC")
        XCTAssertEqual(JobType.basementRenovation.englishName, "Basement Renovation")
    }

    func testValidationErrors() {
        var d = minimal(); d.contractValue = Money(-1, .cad)
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .negativeAmount) }
        d = minimal(); d.startDate = CalendarDate(storage: "2026-10-20"); d.estimatedCompletionDate = CalendarDate(storage: "2026-10-01")
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .completionBeforeStart) }
        d = minimal(); d.hoursPerDay = 25
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .invalidTimeline) }
        d = minimal(); d.workersPerDay = -1
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .invalidTimeline) }
        d = minimal(); d.contractValue = Money(1, .usd)
        XCTAssertThrowsError(try assemble(d)) { XCTAssertEqual($0 as? DraftError, .currencyMismatch) }
    }

    func testScopeFieldsDropBlankAndKeepOrder() throws {
        var d = minimal()
        d.scopeFields = [DraftScopeField(id: UUID(), key: "rooms", value: "3", sortOrder: 1),
                         DraftScopeField(id: UUID(), key: "squareFootage", value: "1200", sortOrder: 0),
                         DraftScopeField(id: UUID(), key: "", value: "x", sortOrder: 2),
                         DraftScopeField(id: UUID(), key: "floors", value: "  ", sortOrder: 3)]
        let b = try assemble(d)
        XCTAssertEqual(b.scopeFields.map(\.fieldKey), ["squareFootage", "rooms"])
        XCTAssertTrue(b.scopeFields.allSatisfy { $0.projectId == b.project.id && $0.companyId == company })
    }

    func testEstimateLinesAndSchedule() throws {
        var d = minimal()
        d.labourQuick = LabourQuickInput(workers: 4, dailyRate: Money(230, .cad), days: 10)
        d.materialLines = [DraftEstimateLine(id: UUID(), label: "Lumber", amount: Money(2500, .cad), quantity: nil, unitRate: nil, costGroup: .material, otherKind: nil, sortOrder: 0)]
        d.otherLines = [DraftEstimateLine(id: UUID(), label: "Dumpster", amount: Money(400, .cad), quantity: nil, unitRate: nil, costGroup: .other, otherKind: .dumpster, sortOrder: 0)]
        d.deposit = DraftDeposit(mode: .percentage(try Percentage.input(20)), deadline: CalendarDate(storage: "2026-10-10"), requiredToStart: true)
        d.schedule = PaymentScheduleTemplate.fourStage.rows(depositPercentage: try Percentage.input(20))
        let b = try assemble(d)
        XCTAssertEqual(b.estimateLines.map(\.costGroup), [.labour, .material, .other])
        XCTAssertEqual(b.estimateLines[0].amount.storageString, "9200.00")
        XCTAssertEqual(b.estimateLines[0].quantity, 40)
        XCTAssertEqual(b.scheduleItems.count, 4)
        XCTAssertEqual(b.scheduleItems.map { $0.amount.storageString }, ["5000.00", "7500.00", "7500.00", "5000.00"])
        XCTAssertEqual(b.scheduleItems[0].isDeposit, true)
        XCTAssertEqual(b.scheduleItems[0].dueDate, CalendarDate(storage: "2026-10-10"))
        XCTAssertNil(b.scheduleItems[1].dueDate)
        XCTAssertEqual(b.scheduleItems.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertTrue(b.project.depositRequiredToStart)
        XCTAssertTrue(b.warnings.isEmpty)
    }

    func testDepositWithoutScheduleCreatesOneItem() throws {
        var d = minimal()
        d.deposit = DraftDeposit(mode: .fixed(Money(30_000, .cad)), deadline: nil, requiredToStart: false)
        let b = try assemble(d)
        XCTAssertEqual(b.scheduleItems.count, 1)
        XCTAssertEqual(b.scheduleItems[0].amount.storageString, "30000.00")
        XCTAssertTrue(b.scheduleItems[0].isDeposit)
        XCTAssertEqual(Set(b.warnings), [.depositExceedsContract, .scheduleTotalMismatch(difference: Money(5000, .cad))])
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'ProjectDraftAssembler' in scope`.

- [ ] **Step 3: Viết code**

```swift
import Foundation

public enum BundleWarning: Equatable, Sendable, Hashable {
    case scheduleTotalMismatch(difference: Money)
    case depositExceedsContract
    case scheduleEmpty
}

public struct NewProjectBundle: Equatable, Sendable {
    public let project: Project
    public let scopeFields: [ProjectScopeField]
    public let estimateLines: [ProjectEstimateLine]
    public let scheduleItems: [PaymentScheduleItem]
    public let newCustomer: Customer?
    public let warnings: [BundleWarning]

    public init(project: Project, scopeFields: [ProjectScopeField], estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], newCustomer: Customer?, warnings: [BundleWarning]) {
        self.project = project; self.scopeFields = scopeFields; self.estimateLines = estimateLines; self.scheduleItems = scheduleItems; self.newCustomer = newCustomer; self.warnings = warnings
    }
}

public extension JobType {
    /// Default project name (user data from then on, never re-localized).
    var englishName: String {
        switch self {
        case .generalRenovation: return "General Renovation"
        case .basementRenovation: return "Basement Renovation"
        case .kitchen: return "Kitchen"
        case .bathroom: return "Bathroom"
        case .landscaping: return "Landscaping"
        case .roofing: return "Roofing"
        case .plumbing: return "Plumbing"
        case .electrical: return "Electrical"
        case .hvac: return "HVAC"
        case .flooring: return "Flooring"
        case .painting: return "Painting"
        case .drywall: return "Drywall"
        case .concrete: return "Concrete"
        case .deckFence: return "Deck / Fence"
        case .framing: return "Framing"
        case .windowsDoors: return "Windows / Doors"
        case .exterior: return "Exterior"
        case .demolition: return "Demolition"
        case .commercial: return "Commercial"
        case .other: return "Other"
        }
    }
}

public enum ProjectDraftAssembler {
    public static func defaultName(for draft: ProjectDraft) -> String? {
        if let name = draft.projectName, !name.isBlank { return name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let type = draft.jobType else { return nil }
        if type == .other { return draft.customJobType.flatMap { $0.isBlank ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        return type.englishName
    }

    /// Spec 3.5.
    public static func assemble(_ draft: ProjectDraft, companyId: UUID, currency: CurrencyCode, now: Date) throws -> NewProjectBundle {
        var missing = Set<DraftField>()
        if draft.jobType == nil { missing.insert(.jobType) }
        if draft.jobType == .other, (draft.customJobType ?? "").isBlank { missing.insert(.customJobType) }
        switch draft.customer {
        case nil: missing.insert(.customer)
        case .new(let input)? where input.name.isBlank: missing.insert(.customer)
        default: break
        }
        if (draft.address?.line ?? "").isBlank { missing.insert(.addressLine) }
        if draft.contractValue == nil { missing.insert(.contractValue) }
        if !missing.isEmpty { throw DraftError.missing(missing) }

        guard let jobType = draft.jobType, let address = draft.address, let contract = draft.contractValue, let name = defaultName(for: draft) else {
            throw DraftError.missing([.jobType])
        }
        let allMoney: [Money] = [contract] + draft.allEstimateLines(currency: currency).map(\.amount)
            + draft.schedule.compactMap(\.amount) + [draft.deposit].compactMap { dep -> Money? in
                if case .fixed(let m)? = dep?.mode { return m } else { return nil }
            }
        if allMoney.contains(where: { $0.currency != currency }) { throw DraftError.currencyMismatch }
        if allMoney.contains(where: \.isNegative) { throw DraftError.negativeAmount }
        if let s = draft.startDate, let e = draft.estimatedCompletionDate, e < s { throw DraftError.completionBeforeStart }
        if let w = draft.workingDays, w < 0 { throw DraftError.invalidTimeline }
        if let w = draft.workersPerDay, w < 0 { throw DraftError.invalidTimeline }
        if let h = draft.hoursPerDay, !(h > 0 && h <= 24) { throw DraftError.invalidTimeline }

        let projectId = UUID()
        var newCustomer: Customer?
        let customerId: UUID
        switch draft.customer {
        case .existing(let id)?: customerId = id
        case .new(let input)?:
            let customer = Customer(id: UUID(), companyId: companyId, name: input.name.trimmingCharacters(in: .whitespacesAndNewlines), phone: input.phone, email: input.email,
                                    preferredContact: input.preferredContact, companyName: input.companyName, secondaryContact: input.secondaryContact, notes: input.notes,
                                    createdAt: now, updatedAt: now, deletedAt: nil)
            newCustomer = customer; customerId = customer.id
        case nil: throw DraftError.missing([.customer])
        }

        let scopeFields = draft.scopeFields
            .filter { !$0.key.isBlank && !$0.value.isBlank }
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, f in ProjectScopeField(id: f.id, companyId: companyId, projectId: projectId, fieldKey: f.key, valueText: f.value, sortOrder: index, createdAt: now, updatedAt: now, deletedAt: nil) }

        var sortByGroup: [CostGroup: Int] = [:]
        let estimateLines = draft.allEstimateLines(currency: currency).map { line -> ProjectEstimateLine in
            let order = sortByGroup[line.costGroup, default: 0]; sortByGroup[line.costGroup] = order + 1
            return ProjectEstimateLine(id: line.id, companyId: companyId, projectId: projectId, costGroup: line.costGroup, label: line.label, amount: line.amount,
                                       quantity: line.quantity, unitRate: line.unitRate, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
        }

        var warnings: [BundleWarning] = []
        var rows = ScheduleMath.recompute(rows: draft.schedule, contract: contract, edited: .none).rows
        if rows.isEmpty, let dep = draft.deposit {
            let amount: Money
            switch dep.mode {
            case .fixed(let m): amount = m
            case .percentage(let p): amount = contract.multiplied(by: p)
            }
            rows = [DraftScheduleRow(id: UUID(), label: "schedule.row.deposit", percentage: nil, amount: amount, dueDate: dep.deadline, trigger: nil, isDeposit: true)]
        }
        let scheduleItems = rows.enumerated().compactMap { index, row -> PaymentScheduleItem? in
            guard let amount = row.amount else { return nil }
            let due = row.dueDate ?? (row.isDeposit ? draft.deposit?.deadline : nil)
            return PaymentScheduleItem(id: row.id, companyId: companyId, projectId: projectId, label: row.label, amount: amount, percentage: row.percentage, dueDate: due,
                                       triggerText: row.trigger, isDeposit: row.isDeposit, notes: nil, sortOrder: index, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        if scheduleItems.isEmpty {
            warnings.append(.scheduleEmpty)
        } else {
            let total = try Money.sum(scheduleItems.map(\.amount), currency: currency)
            if total != contract { warnings.append(.scheduleTotalMismatch(difference: try total.subtracting(contract))) }
        }
        if let dep = draft.deposit {
            let depositAmount: Money
            switch dep.mode {
            case .fixed(let m): depositAmount = m
            case .percentage(let p): depositAmount = contract.multiplied(by: p)
            }
            if depositAmount.amount > contract.amount { warnings.append(.depositExceedsContract) }
        }

        let project = Project(id: projectId, companyId: companyId, customerId: customerId, name: name, jobType: jobType,
                              customJobType: jobType == .other ? draft.customJobType?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                              status: .estimate, address: address, scopeDescription: draft.scopeDescription, scopeFields: scopeFields,
                              startDate: draft.startDate, estimatedCompletionDate: draft.estimatedCompletionDate, workingDays: draft.workingDays,
                              hoursPerDay: draft.hoursPerDay, workersPerDay: draft.workersPerDay, contractValue: contract, manualProgress: nil,
                              depositRequiredToStart: draft.deposit?.requiredToStart ?? false, createdAt: now, updatedAt: now, deletedAt: nil)
        try project.validate()
        try newCustomer?.validate()
        return NewProjectBundle(project: project, scopeFields: scopeFields, estimateLines: estimateLines, scheduleItems: scheduleItems, newCustomer: newCustomer, warnings: warnings)
    }
}
```

`String.isBlank` đã có (internal) trong `Entities/Common.swift`.

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass. Nếu `testDepositWithoutScheduleCreatesOneItem` khác thứ tự warnings: test dùng `Set`, OK.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add ProjectDraftAssembler producing a NewProjectBundle"
```

---

### Task 6: `ProjectDraft(from:)` seed + `DraftDiff`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Drafts/DraftSeed.swift`, `Packages/Domain/Sources/Domain/Drafts/DraftDiff.swift`
- Test: `Packages/Domain/Tests/DomainTests/DraftDiffTests.swift`

**Interfaces:**
- Produces:
  - `extension ProjectDraft { public init(project: Project, estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], step: Int) }` — `customer = .existing`, `labourMode = .detailed`, lines giữ id, `scheduleTemplate = .custom`, `deposit` suy từ item `isDeposit` (mode `.fixed(amount)`, deadline = dueDate, requiredToStart = project.depositRequiredToStart), `projectName = project.name`.
  - `public struct EstimateLineChange: Equatable { upserts: [ProjectEstimateLine], deletedIds: [UUID], totalBefore: Money, totalAfter: Money }`
  - `public struct ScheduleItemChange: Equatable { upserts: [PaymentScheduleItem], deletedIds: [UUID], totalBefore: Money, totalAfter: Money }`
  - `public enum DraftDiff { static func estimateLines(group:old:new:companyId:projectId:currency:now:) throws -> EstimateLineChange; static func scheduleItems(old:new:contract:companyId:projectId:now:) throws -> ScheduleItemChange; static func scopeFields(old:new:companyId:projectId:now:) -> [ProjectScopeField] }` (scope: trả danh sách đầy đủ để gán `project.scopeFields` rồi `save` — repository hiện có đã soft-delete dòng thiếu).

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class DraftDiffTests: XCTestCase {
    let company = UUID(), project = UUID(), customer = UUID()
    let t0 = Date(timeIntervalSince1970: 1_790_000_000), t1 = Date(timeIntervalSince1970: 1_790_000_600)

    private func oldLine(_ label: String, _ amount: Decimal, group: CostGroup = .material, order: Int = 0) -> ProjectEstimateLine {
        ProjectEstimateLine(id: UUID(), companyId: company, projectId: project, costGroup: group, label: label, amount: Money(amount, .cad), quantity: nil, unitRate: nil, sortOrder: order, createdAt: t0, updatedAt: t0, deletedAt: nil)
    }
    private func draftLine(from l: ProjectEstimateLine, amount: Decimal? = nil) -> DraftEstimateLine {
        DraftEstimateLine(id: l.id, label: l.label, amount: amount.map { Money($0, .cad) } ?? l.amount, quantity: l.quantity, unitRate: l.unitRate, costGroup: l.costGroup, otherKind: nil, sortOrder: l.sortOrder)
    }

    func testEstimateDiffKeepsIdsDeletesMissingAddsNew() throws {
        let a = oldLine("Lumber", 2500), b = oldLine("Drywall", 1600, order: 1)
        let newB = draftLine(from: b, amount: 1800)
        let c = DraftEstimateLine(id: UUID(), label: "Paint", amount: Money(800, .cad), quantity: nil, unitRate: nil, costGroup: .material, otherKind: nil, sortOrder: 2)
        let change = try DraftDiff.estimateLines(group: .material, old: [a, b], new: [newB, c], companyId: company, projectId: project, currency: .cad, now: t1)
        XCTAssertEqual(change.deletedIds, [a.id])
        XCTAssertEqual(change.upserts.map(\.id), [b.id, c.id])
        XCTAssertEqual(change.upserts[0].createdAt, t0, "existing line keeps createdAt")
        XCTAssertEqual(change.upserts[0].updatedAt, t1)
        XCTAssertEqual(change.upserts[1].createdAt, t1)
        XCTAssertEqual(change.upserts.map(\.sortOrder), [0, 1])
        XCTAssertEqual(change.totalBefore.storageString, "4100.00")
        XCTAssertEqual(change.totalAfter.storageString, "2600.00")
    }

    func testEstimateDiffIgnoresOtherGroupsAndRejectsWrongGroup() throws {
        let labour = oldLine("Mike", 2000, group: .labour)
        let change = try DraftDiff.estimateLines(group: .material, old: [labour], new: [], companyId: company, projectId: project, currency: .cad, now: t1)
        XCTAssertTrue(change.deletedIds.isEmpty, "lines of other groups are untouched")
        let wrong = DraftEstimateLine(id: UUID(), label: "x", amount: Money(1, .cad), quantity: nil, unitRate: nil, costGroup: .labour, otherKind: nil, sortOrder: 0)
        XCTAssertThrowsError(try DraftDiff.estimateLines(group: .material, old: [], new: [wrong], companyId: company, projectId: project, currency: .cad, now: t1))
    }

    func testScheduleDiff() throws {
        let dep = PaymentScheduleItem(id: UUID(), companyId: company, projectId: project, label: "schedule.row.deposit", amount: Money(6000, .cad), percentage: try Percentage.input(20), dueDate: nil, triggerText: nil, isDeposit: true, notes: nil, sortOrder: 0, createdAt: t0, updatedAt: t0, deletedAt: nil)
        let fin = PaymentScheduleItem(id: UUID(), companyId: company, projectId: project, label: "schedule.row.final", amount: Money(24_000, .cad), percentage: try Percentage.input(80), dueDate: nil, triggerText: nil, isDeposit: false, notes: nil, sortOrder: 1, createdAt: t0, updatedAt: t0, deletedAt: nil)
        let rows = [DraftScheduleRow(id: dep.id, label: dep.label, percentage: try Percentage.input(30), amount: nil, dueDate: CalendarDate(storage: "2026-10-10"), trigger: nil, isDeposit: true),
                    DraftScheduleRow(id: UUID(), label: "schedule.row.final", percentage: try Percentage.input(70), amount: nil, dueDate: nil, trigger: "After paint", isDeposit: false)]
        let change = try DraftDiff.scheduleItems(old: [dep, fin], new: rows, contract: Money(30_000, .cad), companyId: company, projectId: project, now: t1)
        XCTAssertEqual(change.deletedIds, [fin.id])
        XCTAssertEqual(change.upserts.map { $0.amount.storageString }, ["9000.00", "21000.00"])
        XCTAssertEqual(change.upserts[0].id, dep.id); XCTAssertEqual(change.upserts[0].createdAt, t0)
        XCTAssertEqual(change.upserts[0].dueDate, CalendarDate(storage: "2026-10-10"))
        XCTAssertEqual(change.upserts[1].triggerText, "After paint")
        XCTAssertEqual(change.totalBefore.storageString, "30000.00"); XCTAssertEqual(change.totalAfter.storageString, "30000.00")
    }

    func testScheduleDiffSkipsRowsWithoutAmount() throws {
        let rows = [DraftScheduleRow(id: UUID(), label: "a", percentage: nil, amount: nil, dueDate: nil, trigger: nil, isDeposit: true)]
        let change = try DraftDiff.scheduleItems(old: [], new: rows, contract: Money(1000, .cad), companyId: company, projectId: project, now: t1)
        XCTAssertTrue(change.upserts.isEmpty)
    }

    func testScopeFieldsDiff() {
        let old = ProjectScopeField(id: UUID(), companyId: company, projectId: project, fieldKey: "rooms", valueText: "3", sortOrder: 0, createdAt: t0, updatedAt: t0, deletedAt: nil)
        let new = [DraftScopeField(id: old.id, key: "rooms", value: "4", sortOrder: 1), DraftScopeField(id: UUID(), key: "floors", value: "2", sortOrder: 0), DraftScopeField(id: UUID(), key: "x", value: " ", sortOrder: 2)]
        let fields = DraftDiff.scopeFields(old: [old], new: new, companyId: company, projectId: project, now: t1)
        XCTAssertEqual(fields.map(\.fieldKey), ["floors", "rooms"])
        XCTAssertEqual(fields[1].id, old.id); XCTAssertEqual(fields[1].createdAt, t0); XCTAssertEqual(fields[1].valueText, "4")
        XCTAssertEqual(fields.map(\.sortOrder), [0, 1])
    }

    func testSeedFromProjectRoundTripsThroughAssembler() throws {
        let p = Project(id: project, companyId: company, customerId: customer, name: "Smith kitchen", jobType: .kitchen, customJobType: nil, status: .inProgress,
                        address: Address(line: "1 Main", unit: nil, city: "Toronto", region: "ON", postalCode: nil), scopeDescription: "Full gut", scopeFields: [],
                        startDate: CalendarDate(storage: "2026-10-01"), estimatedCompletionDate: CalendarDate(storage: "2026-11-01"), workingDays: 20, hoursPerDay: 8, workersPerDay: 3,
                        contractValue: Money(30_000, .cad), manualProgress: 40, depositRequiredToStart: true, createdAt: t0, updatedAt: t0, deletedAt: nil)
        let lines = [oldLine("Mike", 2000, group: .labour), oldLine("Lumber", 2500)]
        let items = [PaymentScheduleItem(id: UUID(), companyId: company, projectId: project, label: "schedule.row.deposit", amount: Money(6000, .cad), percentage: try Percentage.input(20), dueDate: CalendarDate(storage: "2026-10-10"), triggerText: nil, isDeposit: true, notes: nil, sortOrder: 0, createdAt: t0, updatedAt: t0, deletedAt: nil)]
        let draft = ProjectDraft(project: p, estimateLines: lines, scheduleItems: items, step: 9)
        XCTAssertEqual(draft.customer, .existing(customer))
        XCTAssertEqual(draft.labourMode, .detailed)
        XCTAssertEqual(draft.labourLines.map(\.id), [lines[0].id])
        XCTAssertEqual(draft.materialLines.map(\.id), [lines[1].id])
        XCTAssertEqual(draft.deposit, DraftDeposit(mode: .fixed(Money(6000, .cad)), deadline: CalendarDate(storage: "2026-10-10"), requiredToStart: true))
        XCTAssertEqual(draft.schedule.map(\.id), [items[0].id])
        XCTAssertEqual(draft.scheduleTemplate, .custom)
        XCTAssertEqual(draft.step, 9)
        let bundle = try ProjectDraftAssembler.assemble(draft, companyId: company, currency: .cad, now: t1)
        XCTAssertEqual(bundle.project.name, "Smith kitchen")
        XCTAssertEqual(bundle.estimateLines.map { $0.amount.storageString }, ["2000.00", "2500.00"])
        XCTAssertEqual(bundle.scheduleItems.first?.amount.storageString, "6000.00")
        XCTAssertTrue(bundle.project.depositRequiredToStart)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `no exact matches in call to initializer` / `cannot find 'DraftDiff'`.

- [ ] **Step 3: Viết `DraftSeed.swift`**

```swift
import Foundation

public extension ProjectDraft {
    /// Spec 3.6: seed an edit sheet from persisted data. Ids are preserved so DraftDiff can match rows.
    init(project: Project, estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], step: Int) {
        self.init()
        jobType = project.jobType
        customJobType = project.customJobType
        customer = .existing(project.customerId)
        projectName = project.name
        address = project.address
        scopeDescription = project.scopeDescription
        scopeFields = project.scopeFields.sorted { $0.sortOrder < $1.sortOrder }.map { DraftScopeField(id: $0.id, key: $0.fieldKey, value: $0.valueText, sortOrder: $0.sortOrder) }
        startDate = project.startDate
        estimatedCompletionDate = project.estimatedCompletionDate
        workingDays = project.workingDays
        hoursPerDay = project.hoursPerDay
        workersPerDay = project.workersPerDay
        labourMode = .detailed
        func toDraft(_ l: ProjectEstimateLine) -> DraftEstimateLine {
            DraftEstimateLine(id: l.id, label: l.label, amount: l.amount, quantity: l.quantity, unitRate: l.unitRate, costGroup: l.costGroup, otherKind: nil, sortOrder: l.sortOrder)
        }
        let live = estimateLines.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
        labourLines = live.filter { $0.costGroup == .labour }.map(toDraft)
        materialLines = live.filter { $0.costGroup == .material }.map(toDraft)
        otherLines = live.filter { ![.labour, .material].contains($0.costGroup) }.map(toDraft)
        contractValue = project.contractValue
        let items = scheduleItems.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
        if let dep = items.first(where: \.isDeposit) {
            deposit = DraftDeposit(mode: .fixed(dep.amount), deadline: dep.dueDate, requiredToStart: project.depositRequiredToStart)
        }
        scheduleTemplate = .custom
        schedule = items.map { DraftScheduleRow(id: $0.id, label: $0.label, percentage: $0.percentage, amount: $0.amount, dueDate: $0.dueDate, trigger: $0.triggerText, isDeposit: $0.isDeposit) }
        self.step = step
        updatedAt = project.updatedAt
    }
}
```

- [ ] **Step 4: Viết `DraftDiff.swift`**

```swift
import Foundation

public struct EstimateLineChange: Equatable, Sendable {
    public let upserts: [ProjectEstimateLine]
    public let deletedIds: [UUID]
    public let totalBefore: Money
    public let totalAfter: Money
    public init(upserts: [ProjectEstimateLine], deletedIds: [UUID], totalBefore: Money, totalAfter: Money) {
        self.upserts = upserts; self.deletedIds = deletedIds; self.totalBefore = totalBefore; self.totalAfter = totalAfter
    }
}

public struct ScheduleItemChange: Equatable, Sendable {
    public let upserts: [PaymentScheduleItem]
    public let deletedIds: [UUID]
    public let totalBefore: Money
    public let totalAfter: Money
    public init(upserts: [PaymentScheduleItem], deletedIds: [UUID], totalBefore: Money, totalAfter: Money) {
        self.upserts = upserts; self.deletedIds = deletedIds; self.totalBefore = totalBefore; self.totalAfter = totalAfter
    }
}

public enum DraftDiffError: Error, Equatable { case lineOutsideGroup }

public enum DraftDiff {
    /// Spec 3.6. Only lines of `group` are considered on both sides.
    public static func estimateLines(group: CostGroup, old: [ProjectEstimateLine], new: [DraftEstimateLine], companyId: UUID, projectId: UUID, currency: CurrencyCode, now: Date) throws -> EstimateLineChange {
        guard new.allSatisfy({ $0.costGroup == group }) else { throw DraftDiffError.lineOutsideGroup }
        let oldInGroup = old.filter { $0.costGroup == group && !$0.isDeleted }
        let oldById = Dictionary(oldInGroup.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newIds = Set(new.map(\.id))
        let upserts = new.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { index, line -> ProjectEstimateLine in
            let amount = (line.quantity != nil && line.unitRate != nil) ? line.unitRate!.multiplied(by: line.quantity!) : line.amount // lint:allow-crash
            return ProjectEstimateLine(id: line.id, companyId: companyId, projectId: projectId, costGroup: group, label: line.label, amount: amount,
                                       quantity: line.quantity, unitRate: line.unitRate, sortOrder: index,
                                       createdAt: oldById[line.id]?.createdAt ?? now, updatedAt: now, deletedAt: nil)
        }
        let deleted = oldInGroup.filter { !newIds.contains($0.id) }.map(\.id)
        return EstimateLineChange(upserts: upserts, deletedIds: deleted,
                                  totalBefore: try Money.sum(oldInGroup.map(\.amount), currency: currency),
                                  totalAfter: try Money.sum(upserts.map(\.amount), currency: currency))
    }

    public static func scheduleItems(old: [PaymentScheduleItem], new: [DraftScheduleRow], contract: Money, companyId: UUID, projectId: UUID, now: Date) throws -> ScheduleItemChange {
        let live = old.filter { !$0.isDeleted }
        let oldById = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = ScheduleMath.recompute(rows: new, contract: contract, edited: .none).rows
        let upserts = rows.enumerated().compactMap { index, row -> PaymentScheduleItem? in
            guard let amount = row.amount else { return nil }
            return PaymentScheduleItem(id: row.id, companyId: companyId, projectId: projectId, label: row.label, amount: amount, percentage: row.percentage, dueDate: row.dueDate,
                                       triggerText: row.trigger, isDeposit: row.isDeposit, notes: oldById[row.id]?.notes, sortOrder: index,
                                       createdAt: oldById[row.id]?.createdAt ?? now, updatedAt: now, deletedAt: nil)
        }
        let keep = Set(upserts.map(\.id))
        let deleted = live.filter { !keep.contains($0.id) }.map(\.id)
        return ScheduleItemChange(upserts: upserts, deletedIds: deleted,
                                  totalBefore: try Money.sum(live.map(\.amount), currency: contract.currency),
                                  totalAfter: try Money.sum(upserts.map(\.amount), currency: contract.currency))
    }

    /// Returns the full replacement list for `project.scopeFields` (the repository soft-deletes what is missing).
    public static func scopeFields(old: [ProjectScopeField], new: [DraftScopeField], companyId: UUID, projectId: UUID, now: Date) -> [ProjectScopeField] {
        let oldById = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return new.filter { !$0.key.isBlank && !$0.value.isBlank }.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { index, f in
            ProjectScopeField(id: f.id, companyId: companyId, projectId: projectId, fieldKey: f.key, valueText: f.value, sortOrder: index,
                              createdAt: oldById[f.id]?.createdAt ?? now, updatedAt: now, deletedAt: nil)
        }
    }
}
```

Thay dòng có `// lint:allow-crash` bằng dạng không force-unwrap (lint cấm `!` dạng `as!`/`try!` nhưng quy ước cấm cả force-unwrap):

```swift
            let amount: Money
            if let qty = line.quantity, let rate = line.unitRate { amount = rate.multiplied(by: qty) } else { amount = line.amount }
```

- [ ] **Step 5: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass. `testScheduleDiff`: 30 % + 70 % của 30,000 → 9,000 / 21,000 ✓.

- [ ] **Step 6: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add draft seeding from persisted data and DraftDiff"
```

---

### Task 7: Repository protocols + `ActivityAction` mới

**Files:**
- Modify: `Packages/Domain/Sources/Domain/Repositories/ProjectRepository.swift`, `CustomerRepository.swift`
- Create: `Packages/Domain/Sources/Domain/Repositories/ProjectEstimateRepository.swift`, `PaymentScheduleRepository.swift`, `DraftStore.swift`
- Modify: `Packages/Domain/Sources/Domain/Entities/ActivityLog.swift`

**Interfaces:**
- Produces (verbatim):

```swift
// ProjectRepository.swift — thêm vào protocol hiện có
public struct ProjectDetailSnapshot: Sendable, Hashable {
    public let project: Project
    public let customer: Customer
    public let estimateLines: [ProjectEstimateLine]
    public let scheduleItems: [PaymentScheduleItem]
    public init(project: Project, customer: Customer, estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem])
}
public protocol ProjectRepository: Sendable {
    func get(id: UUID) async throws -> Project?
    func list(companyId: UUID) async throws -> [Project]
    func observeSummaries(companyId: UUID) -> AsyncThrowingStream<[ProjectSummary], Error>
    /// Inserts project, scope fields, estimate lines, schedule items and the optional new customer in ONE transaction,
    /// with a single `projectCreated` activity row (+ `customerCreated` when a customer is created).
    func create(_ bundle: NewProjectBundle, actor: ActivityActor) async throws
    /// Live project + customer + lines + items; emits nil when the project is missing or soft-deleted.
    func observeDetail(id: UUID) -> AsyncThrowingStream<ProjectDetailSnapshot?, Error>
    func save(_ project: Project, actor: ActivityActor) async throws
    func softDelete(id: UUID, actor: ActivityActor) async throws
}

// ProjectEstimateRepository.swift
public protocol ProjectEstimateRepository: Sendable {
    func lines(projectId: UUID) async throws -> [ProjectEstimateLine]
    /// Applies the change in one transaction; logs `estimateChanged` only when totalBefore != totalAfter.
    func replace(projectId: UUID, group: CostGroup, change: EstimateLineChange, actor: ActivityActor) async throws
}

// PaymentScheduleRepository.swift
public protocol PaymentScheduleRepository: Sendable {
    func items(projectId: UUID) async throws -> [PaymentScheduleItem]
    /// One transaction; deleted items' payments get schedule_item_id = NULL; logs `scheduleChanged` only when the total changed.
    func replace(projectId: UUID, change: ScheduleItemChange, actor: ActivityActor) async throws
}

// CustomerRepository.swift — thêm
    func observeAll(companyId: UUID) -> AsyncThrowingStream<[Customer], Error>
    func projects(customerId: UUID) async throws -> [Project]

// DraftStore.swift
public protocol DraftStore: Sendable {
    func load() throws -> ProjectDraft?
    func save(_ draft: ProjectDraft) throws
    func clear() throws
}

// ActivityAction — thêm case
    case estimateChanged, scheduleChanged, customerCreated, scopeChanged, timelineChanged
```

- [ ] **Step 1: Áp dụng các khai báo trên** (thêm `import Foundation` ở file mới). `Features` sẽ biên dịch lại vì protocol đổi — không có conformer nào trong Domain nên Domain build sạch; `Data` conformers cập nhật ở Task 8–10.

- [ ] **Step 2: Build + test Domain**

Run: `swift build --package-path Packages/Domain && swift test --package-path Packages/Domain`
Expected: build sạch; toàn bộ test pass (81 + ~35).

- [ ] **Step 3: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): extend repository protocols for project creation, estimates, schedules and drafts"
```

---

### Task 8: Records + `GRDBProjectEstimateRepository` + `GRDBPaymentScheduleRepository`

**Files:**
- Create: `Packages/Data/Sources/Data/Records/ProjectEstimateLineRecord.swift`, `PaymentScheduleItemRecord.swift`
- Create: `Packages/Data/Sources/Data/Repositories/GRDBProjectEstimateRepository.swift`, `GRDBPaymentScheduleRepository.swift`
- Modify: `Packages/Data/Sources/Data/Database/DataError.swift` (thêm `case scopeMismatch`)
- Test: `Packages/Data/Tests/DataTests/EstimateRepositoryTests.swift`, `ScheduleRepositoryTests.swift`

**Interfaces:**
- Consumes: `ProjectEstimateRepository`, `PaymentScheduleRepository`, `EstimateLineChange`, `ScheduleItemChange`, `ActivityLogRecord.append(_:companyId:actor:action:entityType:entityId:projectId:details:at:)`, `RecordSupport` (`uuid`, `money`, `date`, `calendarDate`, `decimal`), `UUID.dbKey`, `Timestamps`.
- Produces: `public final class GRDBProjectEstimateRepository(database:clock:)`, `public final class GRDBPaymentScheduleRepository(database:clock:)`; `ProjectEstimateLineRecord`/`PaymentScheduleItemRecord` với `init(_ entity)` và `toDomain(currency:) throws`; static helpers `fetchLines(_ db:, projectId: String, currency:)` và `fetchItems(...)` dùng lại ở Task 9.

Toolchain: GRDB không checkout trên Windows → viết, `swift package --package-path Packages/Data dump-package`, đọc lại, commit, báo DONE_WITH_CONCERNS; CI verify. Ruling 7 Foundation áp dụng: không capture `var` trong closure `write`.

- [ ] **Step 1: Viết test fail**

`EstimateRepositoryTests.swift`:

```swift
import XCTest
import GRDB
import Domain
@testable import Data

final class EstimateRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!; var companyId: UUID!; var projectId: UUID!; var actor: ActivityActor!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now))
        companyId = setup.company.id
        actor = ActivityActor(userId: setup.owner.id, name: "Duc")
        let projects = try await GRDBProjectRepository(database: db, clock: .fixed(now)).list(companyId: companyId)
        projectId = projects.first { $0.status == .awaitingDeposit }!.id   // Kitchen: no estimate lines in seed
    }

    private func line(_ label: String, _ amount: Decimal, group: CostGroup = .material, id: UUID = UUID(), order: Int = 0, created: Date? = nil) -> ProjectEstimateLine {
        ProjectEstimateLine(id: id, companyId: companyId, projectId: projectId, costGroup: group, label: label, amount: Money(amount, .cad), quantity: nil, unitRate: nil, sortOrder: order, createdAt: created ?? now, updatedAt: now, deletedAt: nil)
    }
    private func actions() throws -> [String] { try db.writer.read { try String.fetchAll($0, sql: "SELECT action FROM activity_log WHERE project_id = ? ORDER BY rowid", arguments: [self.projectId.dbKey]) } }

    func testReplaceInsertsAndReadsBack() async throws {
        let repo = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let a = line("Lumber", 2500), b = line("Drywall", 1600, order: 1)
        try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [a, b], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(4100, .cad)), actor: actor)
        let lines = try await repo.lines(projectId: projectId)
        XCTAssertEqual(lines, [a, b])
        XCTAssertEqual(try actions(), ["projectCreated", "estimateChanged"])
        let details = try await db.writer.read { try String.fetchOne($0, sql: "SELECT details_json FROM activity_log WHERE action = 'estimateChanged'") }
        XCTAssertEqual(details, #"{"from":"0.00","group":"material","to":"4100.00"}"#)
    }

    func testReplaceSoftDeletesAndKeepsCreatedAt() async throws {
        let repo = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let a = line("Lumber", 2500), b = line("Drywall", 1600, order: 1)
        try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [a, b], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(4100, .cad)), actor: actor)
        let later = now.addingTimeInterval(600)
        let repo2 = GRDBProjectEstimateRepository(database: db, clock: .fixed(later))
        var b2 = b; b2.amount = Money(1800, .cad); b2.updatedAt = later
        try await repo2.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [b2], deletedIds: [a.id], totalBefore: Money(4100, .cad), totalAfter: Money(1800, .cad)), actor: actor)
        let lines = try await repo2.lines(projectId: projectId)
        XCTAssertEqual(lines.map(\.id), [b.id])
        XCTAssertEqual(lines[0].createdAt, now)
        XCTAssertEqual(lines[0].amount.storageString, "1800.00")
        let deletedAt = try await db.writer.read { try String.fetchOne($0, sql: "SELECT deleted_at FROM project_estimate_lines WHERE id = ?", arguments: [a.id.dbKey]) }
        XCTAssertNotNil(deletedAt)
    }

    func testNoActivityWhenTotalUnchanged() async throws {
        let repo = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let a = line("Lumber", 2500)
        try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [a], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(2500, .cad)), actor: actor)
        var renamed = a; renamed.label = "Lumber (SPF)"
        try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [renamed], deletedIds: [], totalBefore: Money(2500, .cad), totalAfter: Money(2500, .cad)), actor: actor)
        XCTAssertEqual(try actions().filter { $0 == "estimateChanged" }.count, 1)
    }

    func testScopeMismatchRejected() async throws {
        let repo = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let wrongGroup = line("Mike", 2000, group: .labour)
        do {
            try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [wrongGroup], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(2000, .cad)), actor: actor)
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? DataError, .scopeMismatch) }
        var otherProject = line("Lumber", 1)
        otherProject = ProjectEstimateLine(id: otherProject.id, companyId: companyId, projectId: UUID(), costGroup: .material, label: "x", amount: Money(1, .cad), quantity: nil, unitRate: nil, sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)
        do {
            try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [otherProject], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(1, .cad)), actor: actor)
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? DataError, .scopeMismatch) }
    }
}
```

`ScheduleRepositoryTests.swift`:

```swift
import XCTest
import GRDB
import Domain
@testable import Data

final class ScheduleRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!; var companyId: UUID!; var projectId: UUID!; var actor: ActivityActor!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now))
        companyId = setup.company.id
        actor = ActivityActor(userId: setup.owner.id, name: "Duc")
        projectId = try await GRDBProjectRepository(database: db, clock: .fixed(now)).list(companyId: companyId).first { $0.status == .completed }!.id  // Roof: no schedule in seed
    }

    private func item(_ label: String, _ amount: Decimal, deposit: Bool = false, order: Int = 0, id: UUID = UUID()) -> PaymentScheduleItem {
        PaymentScheduleItem(id: id, companyId: companyId, projectId: projectId, label: label, amount: Money(amount, .cad), percentage: nil, dueDate: nil, triggerText: nil, isDeposit: deposit, notes: nil, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
    }

    func testReplaceRoundTripAndActivity() async throws {
        let repo = GRDBPaymentScheduleRepository(database: db, clock: .fixed(now))
        let dep = item("schedule.row.deposit", 5000, deposit: true), fin = item("schedule.row.final", 13_500, order: 1)
        try await repo.replace(projectId: projectId, change: ScheduleItemChange(upserts: [dep, fin], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(18_500, .cad)), actor: actor)
        XCTAssertEqual(try await repo.items(projectId: projectId), [dep, fin])
        let details = try await db.writer.read { try String.fetchOne($0, sql: "SELECT details_json FROM activity_log WHERE action = 'scheduleChanged' AND project_id = ?", arguments: [self.projectId.dbKey]) }
        XCTAssertEqual(details, #"{"from":"0.00","to":"18500.00"}"#)
    }

    func testDeletingItemNullifiesPayments() async throws {
        let repo = GRDBPaymentScheduleRepository(database: db, clock: .fixed(now))
        let dep = item("schedule.row.deposit", 5000, deposit: true)
        try await repo.replace(projectId: projectId, change: ScheduleItemChange(upserts: [dep], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(5000, .cad)), actor: actor)
        let (c, p, i) = (companyId.dbKey, projectId.dbKey, dep.id.dbKey)
        try await db.writer.write { db in
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES ('pay1', ?, ?, ?, '5000.00', '2026-10-05', 'cash', ?, ?)",
                           arguments: [c, p, i, "2026-10-05T00:00:00.000Z", "2026-10-05T00:00:00.000Z"])
        }
        try await repo.replace(projectId: projectId, change: ScheduleItemChange(upserts: [], deletedIds: [dep.id], totalBefore: Money(5000, .cad), totalAfter: .zero(.cad)), actor: actor)
        let link = try await db.writer.read { try Row.fetchOne($0, sql: "SELECT schedule_item_id, deleted_at FROM payments WHERE id = 'pay1'") }
        XCTAssertNil(link?["schedule_item_id"] as String?)
        XCTAssertNil(link?["deleted_at"] as String?, "payment itself stays live")
        XCTAssertEqual(try await repo.items(projectId: projectId), [])
    }

    func testScopeMismatchRejected() async throws {
        let repo = GRDBPaymentScheduleRepository(database: db, clock: .fixed(now))
        let foreign = PaymentScheduleItem(id: UUID(), companyId: companyId, projectId: UUID(), label: "x", amount: Money(1, .cad), percentage: nil, dueDate: nil, triggerText: nil, isDeposit: false, notes: nil, sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)
        do {
            try await repo.replace(projectId: projectId, change: ScheduleItemChange(upserts: [foreign], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(1, .cad)), actor: actor)
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? DataError, .scopeMismatch) }
    }
}
```

Lưu ý test dựa vào seed hiện tại (Task 10 mở rộng seed: Basement có lines/schedule; Kitchen và Roof **không có** — giữ như vậy để các test này đúng).

- [ ] **Step 2: `DataError` thêm case**

```swift
    case scopeMismatch
```

- [ ] **Step 3: Viết records**

`ProjectEstimateLineRecord.swift`:

```swift
import Foundation
import GRDB
import Domain

struct ProjectEstimateLineRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_estimate_lines"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var projectId: String
    var costGroup: String
    var label: String
    var amount: String
    var quantity: String?
    var unitRate: String?
    var sortOrder: Int

    init(_ l: ProjectEstimateLine) {
        id = l.id.dbKey; companyId = l.companyId.dbKey; projectId = l.projectId.dbKey
        createdAt = Timestamps.string(l.createdAt); updatedAt = Timestamps.string(l.updatedAt)
        deletedAt = l.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        costGroup = l.costGroup.rawValue; label = l.label; amount = l.amount.storageString
        quantity = l.quantity.map { "\($0)" }; unitRate = l.unitRate?.storageString; sortOrder = l.sortOrder
    }

    func toDomain(currency: CurrencyCode) throws -> ProjectEstimateLine {
        let t = Self.databaseTableName
        guard let group = CostGroup(rawValue: costGroup) else { throw DataError.corruptRow(table: t, id: id, column: "cost_group") }
        let rate = try unitRate.map { try RecordSupport.money($0, currency: currency, table: t, id: id, column: "unit_rate") }
        return ProjectEstimateLine(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                                   companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                                   projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"),
                                   costGroup: group, label: label,
                                   amount: try RecordSupport.money(amount, currency: currency, table: t, id: id, column: "amount"),
                                   quantity: try RecordSupport.decimal(quantity, table: t, id: id, column: "quantity"), unitRate: rate, sortOrder: sortOrder,
                                   createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                                   updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                                   deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }

    static func fetchLive(_ db: Database, projectId: String, currency: CurrencyCode) throws -> [ProjectEstimateLine] {
        try ProjectEstimateLineRecord.filter(Column("project_id") == projectId && Column("deleted_at") == nil)
            .order(Column("cost_group"), Column("sort_order")).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
}
```

`PaymentScheduleItemRecord.swift`:

```swift
import Foundation
import GRDB
import Domain

struct PaymentScheduleItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "payment_schedule_items"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var projectId: String
    var label: String
    var amount: String
    var percentage: String?
    var dueDate: String?
    var triggerText: String?
    var isDeposit: Bool
    var notes: String?
    var sortOrder: Int

    init(_ i: PaymentScheduleItem) {
        id = i.id.dbKey; companyId = i.companyId.dbKey; projectId = i.projectId.dbKey
        createdAt = Timestamps.string(i.createdAt); updatedAt = Timestamps.string(i.updatedAt)
        deletedAt = i.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        label = i.label; amount = i.amount.storageString; percentage = i.percentage.map { "\($0.points)" }
        dueDate = i.dueDate?.storageString; triggerText = i.triggerText; isDeposit = i.isDeposit; notes = i.notes; sortOrder = i.sortOrder
    }

    func toDomain(currency: CurrencyCode) throws -> PaymentScheduleItem {
        let t = Self.databaseTableName
        let pct = try RecordSupport.decimal(percentage, table: t, id: id, column: "percentage").map { Percentage.exact($0) }
        return PaymentScheduleItem(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                                   companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                                   projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"),
                                   label: label, amount: try RecordSupport.money(amount, currency: currency, table: t, id: id, column: "amount"),
                                   percentage: pct, dueDate: try RecordSupport.calendarDate(dueDate, table: t, id: id, column: "due_date"),
                                   triggerText: triggerText, isDeposit: isDeposit, notes: notes, sortOrder: sortOrder,
                                   createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                                   updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                                   deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }

    static func fetchLive(_ db: Database, projectId: String, currency: CurrencyCode) throws -> [PaymentScheduleItem] {
        try PaymentScheduleItemRecord.filter(Column("project_id") == projectId && Column("deleted_at") == nil)
            .order(Column("sort_order")).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
}
```

`Percentage.exact` (Task 2) đã `public`; Data dùng để tái tạo giá trị đã lưu (không validate).

- [ ] **Step 4: Viết hai repository**

`GRDBProjectEstimateRepository.swift`:

```swift
import Foundation
import GRDB
import Domain

public final class GRDBProjectEstimateRepository: ProjectEstimateRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    public func lines(projectId: UUID) async throws -> [ProjectEstimateLine] {
        try await database.writer.read { db in
            let currency = try CompanyLookup.currency(db, projectId: projectId.dbKey)
            return try ProjectEstimateLineRecord.fetchLive(db, projectId: projectId.dbKey, currency: currency)
        }
    }

    public func replace(projectId: UUID, group: CostGroup, change: EstimateLineChange, actor: ActivityActor) async throws {
        guard change.upserts.allSatisfy({ $0.projectId == projectId && $0.costGroup == group }) else { throw DataError.scopeMismatch }
        let now = clock.now()
        let stamp = Timestamps.string(now)
        let records = change.upserts.map { line -> ProjectEstimateLineRecord in var l = line; l.updatedAt = now; return ProjectEstimateLineRecord(l) }
        let deletedKeys = change.deletedIds.map(\.dbKey)
        let pid = projectId.dbKey
        try await database.writer.write { db in
            guard let projectRow = try Row.fetchOne(db, sql: "SELECT company_id FROM projects WHERE id = ? AND deleted_at IS NULL", arguments: [pid]) else { throw DataError.notFound }
            let companyKey: String = projectRow["company_id"]
            for key in deletedKeys {
                try db.execute(sql: "UPDATE project_estimate_lines SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ? AND project_id = ? AND cost_group = ? AND deleted_at IS NULL",
                               arguments: [stamp, stamp, key, pid, group.rawValue])
            }
            for record in records { try record.save(db) }
            if change.totalBefore != change.totalAfter {
                let companyId = try RecordSupport.uuid(companyKey, table: "projects", id: pid, column: "company_id")
                try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .estimateChanged, entityType: "project", entityId: projectId, projectId: projectId,
                                             details: ["group": group.rawValue, "from": change.totalBefore.storageString, "to": change.totalAfter.storageString], at: now)
            }
        }
    }
}

/// Shared read helper: the company currency of a project.
enum CompanyLookup {
    static func currency(_ db: Database, projectId: String) throws -> CurrencyCode {
        guard let raw = try String.fetchOne(db, sql: "SELECT c.currency_code FROM projects p JOIN companies c ON c.id = p.company_id WHERE p.id = ?", arguments: [projectId]),
              let currency = CurrencyCode(rawValue: raw) else { throw DataError.notFound }
        return currency
    }
}
```

`GRDBPaymentScheduleRepository.swift`:

```swift
import Foundation
import GRDB
import Domain

public final class GRDBPaymentScheduleRepository: PaymentScheduleRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    public func items(projectId: UUID) async throws -> [PaymentScheduleItem] {
        try await database.writer.read { db in
            let currency = try CompanyLookup.currency(db, projectId: projectId.dbKey)
            return try PaymentScheduleItemRecord.fetchLive(db, projectId: projectId.dbKey, currency: currency)
        }
    }

    public func replace(projectId: UUID, change: ScheduleItemChange, actor: ActivityActor) async throws {
        guard change.upserts.allSatisfy({ $0.projectId == projectId }) else { throw DataError.scopeMismatch }
        let now = clock.now()
        let stamp = Timestamps.string(now)
        let records = change.upserts.map { item -> PaymentScheduleItemRecord in var i = item; i.updatedAt = now; return PaymentScheduleItemRecord(i) }
        let deletedKeys = change.deletedIds.map(\.dbKey)
        let pid = projectId.dbKey
        try await database.writer.write { db in
            guard let projectRow = try Row.fetchOne(db, sql: "SELECT company_id FROM projects WHERE id = ? AND deleted_at IS NULL", arguments: [pid]) else { throw DataError.notFound }
            let companyKey: String = projectRow["company_id"]
            for key in deletedKeys {
                try db.execute(sql: "UPDATE payments SET schedule_item_id = NULL, updated_at = ?, sync_state = 'pending' WHERE schedule_item_id = ? AND deleted_at IS NULL", arguments: [stamp, key])
                try db.execute(sql: "UPDATE payment_schedule_items SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ? AND project_id = ? AND deleted_at IS NULL",
                               arguments: [stamp, stamp, key, pid])
            }
            for record in records { try record.save(db) }
            if change.totalBefore != change.totalAfter {
                let companyId = try RecordSupport.uuid(companyKey, table: "projects", id: pid, column: "company_id")
                try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .scheduleChanged, entityType: "project", entityId: projectId, projectId: projectId,
                                             details: ["from": change.totalBefore.storageString, "to": change.totalAfter.storageString], at: now)
            }
        }
    }
}
```

Lưu ý thứ tự trong `replace` schedule: nullify payments **trước** khi soft-delete item (FK tổ hợp `(schedule_item_id, project_id, company_id)` vẫn thỏa vì item không bị xóa vật lý — nullify chỉ để A.2 đúng về nghiệp vụ).

- [ ] **Step 5: Manifest check, đọc lại, commit**

Run: `swift package --package-path Packages/Data dump-package` → parse OK. Đọc lại hai record đối chiếu cột với migration (`project_estimate_lines`: project_id, cost_group, label, amount, quantity, unit_rate, sort_order; `payment_schedule_items`: project_id, label, amount, percentage, due_date, trigger_text, is_deposit, notes, sort_order).

```bash
git add Packages/Data Packages/Domain/Sources/Domain/Money/Percentage.swift
git commit -m "feat(data): add estimate line and payment schedule repositories"
```

---

### Task 9: `GRDBProjectRepository.create` + `observeDetail` + guards

**Files:**
- Modify: `Packages/Data/Sources/Data/Repositories/GRDBProjectRepository.swift`
- Test: `Packages/Data/Tests/DataTests/ProjectCreateTests.swift`

**Interfaces:**
- Consumes: `NewProjectBundle`, `ProjectDetailSnapshot`, `CustomerRecord`, `ProjectEstimateLineRecord.fetchLive`, `PaymentScheduleItemRecord.fetchLive`, `CompanyLookup`.
- Produces: conformance đầy đủ cho `ProjectRepository` (Task 7); `save` ném `DomainError.currencyMismatch` khi currency ≠ company, `DataError.notFound` khi id đã soft-delete.

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
import GRDB
import Domain
@testable import Data

final class ProjectCreateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!; var companyId: UUID!; var actor: ActivityActor!; var repo: GRDBProjectRepository!; var customerId: UUID!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
        companyId = company.id; actor = ActivityActor(userId: owner.id, name: "Duc")
        let c = Customer(id: UUID(), companyId: companyId, name: "Ann", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(c)
        customerId = c.id
        repo = GRDBProjectRepository(database: db, clock: .fixed(now))
    }

    private func bundle(newCustomer: Bool = false) throws -> NewProjectBundle {
        var d = ProjectDraft()
        d.jobType = .basementRenovation
        d.customer = newCustomer ? .new(NewCustomerInput(name: "Bob", phone: "647", email: nil, preferredContact: .phone, companyName: nil, secondaryContact: nil, notes: nil)) : .existing(customerId)
        d.address = Address(line: "123 Main St", unit: nil, city: "Toronto", region: "ON", postalCode: nil)
        d.scopeFields = [DraftScopeField(id: UUID(), key: "squareFootage", value: "1200", sortOrder: 0)]
        d.contractValue = Money(38_000, .cad)
        d.labourQuick = LabourQuickInput(workers: 3, dailyRate: Money(250, .cad), days: 10)
        d.materialLines = [DraftEstimateLine(id: UUID(), label: "Lumber", amount: Money(2500, .cad), quantity: nil, unitRate: nil, costGroup: .material, otherKind: nil, sortOrder: 0)]
        d.deposit = DraftDeposit(mode: .percentage(try Percentage.input(20)), deadline: CalendarDate(storage: "2026-10-10"), requiredToStart: true)
        d.schedule = PaymentScheduleTemplate.fourStage.rows(depositPercentage: try Percentage.input(20))
        return try ProjectDraftAssembler.assemble(d, companyId: companyId, currency: .cad, now: now)
    }

    func testCreatePersistsEverythingInOneTransaction() async throws {
        let b = try bundle()
        try await repo.create(b, actor: actor)
        var it = repo.observeDetail(id: b.project.id).makeAsyncIterator()
        let snap = try await it.next() ?? nil
        XCTAssertEqual(snap?.project, b.project)
        XCTAssertEqual(snap?.customer.id, customerId)
        XCTAssertEqual(snap?.estimateLines.count, 2)
        XCTAssertEqual(snap?.scheduleItems.map { $0.amount.storageString }, ["7600.00", "11400.00", "11400.00", "7600.00"])
        let actions = try await db.writer.read { try String.fetchAll($0, sql: "SELECT action FROM activity_log WHERE project_id = ?", arguments: [b.project.id.dbKey]) }
        XCTAssertEqual(actions, ["projectCreated"])
        let details = try await db.writer.read { try String.fetchOne($0, sql: "SELECT details_json FROM activity_log WHERE action = 'projectCreated'") }
        XCTAssertEqual(details, #"{"contractValue":"38000.00","estimateLines":"2","name":"Basement Renovation","scheduleItems":"4"}"#)
    }

    func testCreateWithNewCustomerLogsCustomerCreated() async throws {
        let b = try bundle(newCustomer: true)
        try await repo.create(b, actor: actor)
        let customers = try await GRDBCustomerRepository(database: db, clock: .fixed(now)).list(companyId: companyId)
        XCTAssertEqual(customers.map(\.name), ["Ann", "Bob"])
        let actions = try await db.writer.read { try String.fetchAll($0, sql: "SELECT action FROM activity_log WHERE company_id = ? ORDER BY rowid", arguments: [self.companyId.dbKey]) }
        XCTAssertEqual(actions, ["customerCreated", "projectCreated"])
    }

    func testCreateRollsBackOnConstraintFailure() async throws {
        var b = try bundle()
        // Two schedule items with the same id violate the primary key inside the transaction.
        let dup = b.scheduleItems[0]
        b = NewProjectBundle(project: b.project, scopeFields: b.scopeFields, estimateLines: b.estimateLines, scheduleItems: b.scheduleItems + [dup], newCustomer: nil, warnings: [])
        do { try await repo.create(b, actor: actor); XCTFail("expected throw") } catch {}
        let count = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM projects") }
        XCTAssertEqual(count, 0)
        let lines = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM project_estimate_lines") }
        XCTAssertEqual(lines, 0)
    }

    func testObserveDetailEmitsNilForMissingAndAfterDelete() async throws {
        var it = repo.observeDetail(id: UUID()).makeAsyncIterator()
        let first = try await it.next()
        XCTAssertEqual(first.map { $0 == nil }, true)
        let b = try bundle(); try await repo.create(b, actor: actor)
        var it2 = repo.observeDetail(id: b.project.id).makeAsyncIterator()
        _ = try await it2.next()
        try await repo.softDelete(id: b.project.id, actor: actor)
        let afterDelete = try await it2.next()
        XCTAssertEqual(afterDelete.map { $0 == nil }, true)
    }

    func testObserveDetailEmitsAfterEstimateReplace() async throws {
        let b = try bundle(); try await repo.create(b, actor: actor)
        var it = repo.observeDetail(id: b.project.id).makeAsyncIterator()
        _ = try await it.next()
        let est = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let newLine = ProjectEstimateLine(id: UUID(), companyId: companyId, projectId: b.project.id, costGroup: .material, label: "Paint", amount: Money(800, .cad), quantity: nil, unitRate: nil, sortOrder: 1, createdAt: now, updatedAt: now, deletedAt: nil)
        let existing = b.estimateLines.filter { $0.costGroup == .material }
        try await est.replace(projectId: b.project.id, group: .material, change: EstimateLineChange(upserts: existing + [newLine], deletedIds: [], totalBefore: Money(2500, .cad), totalAfter: Money(3300, .cad)), actor: actor)
        let snap = try await it.next() ?? nil
        XCTAssertEqual(snap?.estimateLines.filter { $0.costGroup == .material }.count, 2)
    }

    func testSaveGuards() async throws {
        let b = try bundle(); try await repo.create(b, actor: actor)
        var usd = b.project; usd.contractValue = Money(1, .usd)
        do { try await repo.save(usd, actor: actor); XCTFail("expected throw") } catch { XCTAssertEqual(error as? DomainError, .currencyMismatch) }
        try await repo.softDelete(id: b.project.id, actor: actor)
        do { try await repo.save(b.project, actor: actor); XCTFail("expected throw") } catch { XCTAssertEqual(error as? DataError, .notFound) }
    }
}
```

- [ ] **Step 2: Sửa `GRDBProjectRepository`**

Thêm sau `observeSummaries`:

```swift
    public func create(_ bundle: NewProjectBundle, actor: ActivityActor) async throws {
        try bundle.project.validate()
        try bundle.newCustomer?.validate()
        let now = clock.now()
        let projectRecord = ProjectRecord(bundle.project)
        let fieldRecords = bundle.scopeFields.map(ProjectScopeFieldRecord.init)
        let lineRecords = bundle.estimateLines.map(ProjectEstimateLineRecord.init)
        let itemRecords = bundle.scheduleItems.map(PaymentScheduleItemRecord.init)
        let customerRecord = bundle.newCustomer.map(CustomerRecord.init)
        let project = bundle.project
        let newCustomer = bundle.newCustomer
        try await database.writer.write { db in
            let currency = try Self.currency(db, companyId: project.companyId.dbKey)
            guard project.contractValue.currency == currency else { throw DomainError.currencyMismatch }
            if let customerRecord, let newCustomer {
                try customerRecord.insert(db)
                try ActivityLogRecord.append(db, companyId: project.companyId, actor: actor, action: .customerCreated, entityType: "customer", entityId: newCustomer.id, projectId: nil,
                                             details: ["name": newCustomer.name], at: now)
            }
            try projectRecord.insert(db)
            for record in fieldRecords { try record.insert(db) }
            for record in lineRecords { try record.insert(db) }
            for record in itemRecords { try record.insert(db) }
            try ActivityLogRecord.append(db, companyId: project.companyId, actor: actor, action: .projectCreated, entityType: "project", entityId: project.id, projectId: project.id,
                                         details: ["name": project.name, "contractValue": project.contractValue.storageString,
                                                   "estimateLines": String(lineRecords.count), "scheduleItems": String(itemRecords.count)], at: now)
        }
    }

    public func observeDetail(id: UUID) -> AsyncThrowingStream<ProjectDetailSnapshot?, Error> {
        let key = id.dbKey
        let observation = ValueObservation.tracking { db -> ProjectDetailSnapshot? in
            guard let record = try ProjectRecord.filter(Column("id") == key && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            let currency = try Self.currency(db, companyId: record.companyId)
            let fields = try Self.scopeFields(db, projectIds: [record.id])[record.id] ?? []
            let project = try record.toDomain(currency: currency, scopeFields: fields)
            guard let customerRecord = try CustomerRecord.filter(Column("id") == record.customerId).fetchOne(db) else {
                throw DataError.corruptRow(table: "projects", id: record.id, column: "customer_id")
            }
            return ProjectDetailSnapshot(project: project, customer: try customerRecord.toDomain(),
                                         estimateLines: try ProjectEstimateLineRecord.fetchLive(db, projectId: record.id, currency: currency),
                                         scheduleItems: try PaymentScheduleItemRecord.fetchLive(db, projectId: record.id, currency: currency))
        }
        let writer = database.writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: writer) { continuation.yield(value) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
```

Trong `save(_:actor:)`, thay đoạn đầu closure:

```swift
        try await database.writer.write { db in
            let currency = try Self.currency(db, companyId: stampedProject.companyId.dbKey)
            guard stampedProject.contractValue.currency == currency else { throw DomainError.currencyMismatch }
            let existing = try ProjectRecord.filter(Column("id") == stampedProject.id.dbKey).fetchOne(db)
            if let existing, existing.deletedAt != nil { throw DataError.notFound }
            try record.save(db)
```

(`ProjectRecord.deletedAt` là `String?` — có sẵn.)

- [ ] **Step 3: Manifest check, đọc lại, commit**

Đối chiếu: `CustomerRecord.init(_:)` và `toDomain()` tồn tại (Task 13 Foundation); `ProjectScopeFieldRecord.init(_:)` tồn tại. `ProjectDetailSnapshot: Hashable` → test `XCTAssertEqual(first.map { $0 == nil }, true)` hợp lệ.

```bash
git add Packages/Data
git commit -m "feat(data): create project bundles transactionally and observe project detail"
```

---

### Task 10: `GRDBCustomerRepository` mở rộng, `FileDraftStore`, seed mở rộng

**Files:**
- Modify: `Packages/Data/Sources/Data/Repositories/GRDBCustomerRepository.swift`, `Packages/Data/Sources/Data/Seed/SampleData.swift`
- Create: `Packages/Data/Sources/Data/Drafts/FileDraftStore.swift`
- Test: `Packages/Data/Tests/DataTests/CustomerObserveTests.swift`, `FileDraftStoreTests.swift`; Modify `SampleDataTests.swift`

**Interfaces:**
- Produces: `GRDBCustomerRepository.observeAll(companyId:)`, `.projects(customerId:)`; `public final class FileDraftStore: DraftStore { public init(directory: URL) }` với `static func defaultDirectory() -> URL` (`Application Support/ConMa/drafts`); `SampleData` seed thêm scope fields/estimate/schedule cho "Basement Renovation" và deposit deadline cho "Kitchen Renovation" (Kitchen và Roof **không** có estimate lines; Kitchen có đúng 1 schedule item deposit; Roof không có schedule).

- [ ] **Step 1: Viết test fail**

`CustomerObserveTests.swift`:

```swift
import XCTest
import Domain
@testable import Data

final class CustomerObserveTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testObserveAllEmitsSortedAndUpdates() async throws {
        let db = try AppDatabase.inMemory()
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now))
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        var it = repo.observeAll(companyId: setup.company.id).makeAsyncIterator()
        let first = try await it.next()
        XCTAssertEqual(first?.map(\.name), ["Ann Lee", "David Nguyen", "Maria Santos"])
        try await repo.save(Customer(id: UUID(), companyId: setup.company.id, name: "Bob", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil))
        let second = try await it.next()
        XCTAssertEqual(second?.map(\.name), ["Ann Lee", "Bob", "David Nguyen", "Maria Santos"])
    }

    func testProjectsForCustomer() async throws {
        let db = try AppDatabase.inMemory()
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now))
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        let ann = try await repo.list(companyId: setup.company.id).first { $0.name == "Ann Lee" }!
        let projects = try await repo.projects(customerId: ann.id)
        XCTAssertEqual(projects.map(\.name), ["Basement Renovation"])
        XCTAssertEqual(try await repo.projects(customerId: UUID()), [])
    }
}
```

`FileDraftStoreTests.swift`:

```swift
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
```

Thêm vào `SampleDataTests.testSeedCreatesThreeProjectsAndIsIdempotent` (sau phần kiểm tra count):

```swift
        let basement = projects.first { $0.status == .inProgress }!
        XCTAssertEqual(basement.scopeFields.count, 6)
        let lines = try await GRDBProjectEstimateRepository(database: db, clock: clock).lines(projectId: basement.id)
        XCTAssertEqual(lines.count, 9)
        let items = try await GRDBPaymentScheduleRepository(database: db, clock: clock).items(projectId: basement.id)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(try Money.sum(items.map(\.amount), currency: .cad).storageString, "38000.00")
        let kitchen = projects.first { $0.status == .awaitingDeposit }!
        let kitchenItems = try await GRDBPaymentScheduleRepository(database: db, clock: clock).items(projectId: kitchen.id)
        XCTAssertEqual(kitchenItems.count, 1)
        XCTAssertEqual(kitchenItems[0].dueDate, CalendarDate(clock.now(), timeZone: .gmt).adding(days: 7))
```

- [ ] **Step 2: `GRDBCustomerRepository` thêm**

```swift
    public func observeAll(companyId: UUID) -> AsyncThrowingStream<[Customer], Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> [Customer] in
            try CustomerRecord.filter(Column("company_id") == key && Column("deleted_at") == nil)
                .order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db).map { try $0.toDomain() }
        }
        let writer = database.writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: writer) { continuation.yield(value) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func projects(customerId: UUID) async throws -> [Project] {
        try await database.writer.read { db in
            let records = try ProjectRecord.filter(Column("customer_id") == customerId.dbKey && Column("deleted_at") == nil).order(Column("updated_at").desc, Column("name")).fetchAll(db)
            guard let first = records.first else { return [] }
            let currencyRaw = try String.fetchOne(db, sql: "SELECT currency_code FROM companies WHERE id = ?", arguments: [first.companyId]) ?? ""
            guard let currency = CurrencyCode(rawValue: currencyRaw) else { throw DataError.corruptRow(table: "companies", id: first.companyId, column: "currency_code") }
            return try records.map { try $0.toDomain(currency: currency, scopeFields: []) }
        }
    }
```

(Scope fields rỗng trong danh sách của khách — chỉ cần header; detail tải đủ qua `observeDetail`.)

- [ ] **Step 3: `FileDraftStore.swift`**

```swift
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
        let data = try Data(contentsOf: fileURL)
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
```

`Data` module name shadows `Foundation.Data` **inside the Data module itself**: trong `FileDraftStore.swift`, `Data(contentsOf:)` tham chiếu kiểu `Foundation.Data` — bên trong module tên `Data`, tên `Data` trỏ tới module. Dùng `Foundation.Data(contentsOf: fileURL)` tường minh để tránh lỗi "'Data' is not a type". Mọi chỗ khác không dùng kiểu `Data`.

- [ ] **Step 4: Seed mở rộng** (`SampleData.swift`, sau khi lưu 3 project; tạo repos `GRDBProjectEstimateRepository`/`GRDBPaymentScheduleRepository` với cùng `clock`):

```swift
        let basement = /* project("Basement Renovation", ...) đã tạo — giữ biến `basementProject` khi gọi save */
        var withScope = basementProject
        let scopeKeys: [(String, String)] = [("squareFootage", "1200"), ("bedrooms", "1"), ("bathrooms", "1"), ("egressWindows", "1"), ("ceilingHeight", "7.5"), ("wetBar", "false")]
        withScope.scopeFields = scopeKeys.enumerated().map { i, kv in ProjectScopeField(id: UUID(), companyId: company.id, projectId: basementProject.id, fieldKey: kv.0, valueText: kv.1, sortOrder: i, createdAt: now, updatedAt: now, deletedAt: nil) }
        try await projects.save(withScope, actor: actor)

        func est(_ group: CostGroup, _ label: String, _ amount: Int, _ order: Int, qty: Decimal? = nil, rate: Int? = nil) -> ProjectEstimateLine {
            ProjectEstimateLine(id: UUID(), companyId: company.id, projectId: basementProject.id, costGroup: group, label: label, amount: Money(Decimal(amount), .cad), quantity: qty, unitRate: rate.map { Money(Decimal($0), .cad) }, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        let estimates = GRDBProjectEstimateRepository(database: database, clock: clock)
        try await estimates.replace(projectId: basementProject.id, group: .labour, change: EstimateLineChange(upserts: [est(.labour, "Mike", 2000, 0, qty: 8, rate: 250), est(.labour, "John", 2200, 1, qty: 10, rate: 220), est(.labour, "David", 1800, 2, qty: 9, rate: 200)], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(6000, .cad)), actor: actor)
        try await estimates.replace(projectId: basementProject.id, group: .material, change: EstimateLineChange(upserts: [est(.material, "Lumber", 2500, 0), est(.material, "Drywall", 1600, 1), est(.material, "Flooring", 3000, 2), est(.material, "Paint", 800, 3)], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(7900, .cad)), actor: actor)
        try await estimates.replace(projectId: basementProject.id, group: .other, change: EstimateLineChange(upserts: [est(.other, "Dumpster", 600, 0), est(.other, "Delivery", 300, 1)], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(900, .cad)), actor: actor)

        let schedules = GRDBPaymentScheduleRepository(database: database, clock: clock)
        let today = CalendarDate(now, timeZone: .gmt)
        func item(_ pid: UUID, _ label: String, _ amount: Int, pct: Decimal, due: CalendarDate?, deposit: Bool, _ order: Int) throws -> PaymentScheduleItem {
            PaymentScheduleItem(id: UUID(), companyId: company.id, projectId: pid, label: label, amount: Money(Decimal(amount), .cad), percentage: try Percentage.input(pct), dueDate: due, triggerText: nil, isDeposit: deposit, notes: nil, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        try await schedules.replace(projectId: basementProject.id, change: ScheduleItemChange(upserts: [
            try item(basementProject.id, "schedule.row.deposit", 7600, pct: 20, due: today.adding(days: -20), deposit: true, 0),
            try item(basementProject.id, "schedule.row.stage2", 11_400, pct: 30, due: today.adding(days: -5), deposit: false, 1),
            try item(basementProject.id, "schedule.row.stage3", 11_400, pct: 30, due: today.adding(days: 10), deposit: false, 2),
            try item(basementProject.id, "schedule.row.final", 7600, pct: 20, due: nil, deposit: false, 3),
        ], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(38_000, .cad)), actor: actor)
        try await schedules.replace(projectId: kitchenProject.id, change: ScheduleItemChange(upserts: [
            try item(kitchenProject.id, "schedule.row.deposit", 5000, pct: 20, due: today.adding(days: 7), deposit: true, 0),
        ], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(5000, .cad)), actor: actor)
```

Giữ biến `basementProject`/`kitchenProject` khi tạo (thay vì gọi `project(...)` inline trong `save`). Cập nhật `SampleDataTests` theo Step 1 (lines 9 = 3 + 4 + 2).

- [ ] **Step 5: Manifest check, đọc lại, commit**

```bash
git add Packages/Data
git commit -m "feat(data): observe customers, file-backed wizard drafts and richer sample data"
```

---

### Task 11: DesignSystem input fields, `ScopeFieldCatalog`, labels, catalog keys, lint mở rộng

**Files:**
- Create: `Packages/DesignSystem/Sources/DesignSystem/Components/MoneyField.swift`, `DecimalField.swift`, `ChoiceChips.swift`, `StepHeader.swift`
- Create: `Packages/Features/Sources/FeatureSupport/ScopeFieldCatalog.swift`, `MaterialSuggestions.swift`, `DraftLabels.swift`, `PhaseFilter.swift`
- Move: `Packages/Features/Sources/HomeFeature/ProjectCardView.swift` → `Packages/Features/Sources/FeatureSupport/ProjectCardView.swift` (đổi `struct` thành `public struct`, `public init(summary:progress:)`, thêm dòng ngày)
- Modify: `Packages/Features/Package.swift` (thêm target `CustomersFeature`), `scripts/check_localization.py`, `App/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces:
  - `MoneyField(_ title: LocalizedStringKey, amount: Binding<Decimal?>, currencyCode: String)` — hiện ký hiệu currency, `.decimalPad`, parse theo `@Environment(\.locale)`; chuỗi rỗng → nil; caller bọc thành `Money` với currency của company.
  - `DecimalField(_ title: LocalizedStringKey, value: Binding<Decimal?>, fractionDigits: Int = 2)`; `IntegerField(_:value: Binding<Int?>)` (cùng file `DecimalField.swift`).
  - `ChoiceChips<T: Hashable>(options: [T], selection: Binding<T?>, label: (T) -> LocalizedStringKey)` — chip cuộn ngang, chọn một.
  - `StepHeader(title: LocalizedStringKey, step: Int, total: Int)`.
  - `enum LocaleNumberParser { static func decimal(from text: String, locale: Locale) -> Decimal?; static func string(_ value: Decimal, locale: Locale, fractionDigits: Int) -> String }` (DesignSystem, dùng `NumberFormatter` với `locale`, `generatesDecimalNumbers = true`; rỗng/khoảng trắng → nil).
  - `ScopeFieldDefinition { key: String, kind: Kind, unitKey: String? }`, `enum Kind { integer, decimal, text, toggle, choice([String]) }`, `ScopeFieldCatalog.common: [ScopeFieldDefinition]`, `ScopeFieldCatalog.fields(for: JobType) -> [ScopeFieldDefinition]` (= common + theo type, Phụ lục B), `ScopeFieldCatalog.definition(forKey:) -> ScopeFieldDefinition?`, `ScopeFieldCatalog.labelKey(forFieldKey:) -> LocalizedStringKey` (`scope.field.<key>`; `custom:<label>` → `nil` để UI hiện verbatim), `optionLabelKey(_:) -> LocalizedStringKey` (`scope.option.<key>`), `unitLabelKey`.
  - `MaterialSuggestions.labels(for: JobType) -> [String]` (Phụ lục B.3; English, là dữ liệu người dùng — không dịch).
  - `DraftLabels`: `extension OtherCostKind { titleKey }` (`otherCost.<raw>`), `extension PaymentScheduleTemplate { titleKey }` (`schedule.template.<raw>`), `extension DraftScheduleRow { displayLabel: Text }` (label bắt đầu `schedule.row.` → `Text(LocalizedStringKey(label))`, khác → `Text(verbatim:)`), `extension ProjectEstimateLine { displayLabel: Text }` cùng rule.
  - `enum PhaseFilter: String, CaseIterable { all, inWork, preStart, workDone, terminal; titleKey; func matches(_ status: ProjectStatus) -> Bool }`.
  - `ProjectCardView` public trong FeatureSupport; Home dùng lại.
  - `check_localization.py`: ngoài kiểm tra hiện có, parse `ScopeFieldCatalog.swift` bằng regex `key: "([A-Za-z0-9]+)"` → yêu cầu `scope.field.<key>`; regex `\.choice\(\[([^\]]+)\]\)` → mỗi option `"x"` yêu cầu `scope.option.x`; regex `unitKey: "([a-z]+)"` → `scope.unit.<key>`; `OtherCostKind` cases → `otherCost.<case>`; `PaymentScheduleTemplate` cases → `schedule.template.<case>`; row keys `schedule.row.{deposit,progress,stage2,stage3,final,labourQuick}`. Thiếu → lỗi.

- [ ] **Step 1: DesignSystem fields**

`MoneyField.swift`:

```swift
import SwiftUI

/// Parses/prints decimals in the environment locale; stores canonical values.
public enum LocaleNumberParser {
    public static func decimal(from text: String, locale: Locale) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        if let number = formatter.number(from: trimmed) as? NSDecimalNumber { return number.decimalValue }
        // Fallback: canonical dot-decimal text (e.g. values typed before a locale switch).
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func string(_ value: Decimal, locale: Locale, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

public struct MoneyField: View {
    private let title: LocalizedStringKey
    @Binding private var amount: Decimal?
    private let currencyCode: String
    @Environment(\.locale) private var locale
    @State private var text = ""
    @FocusState private var focused: Bool

    /// `amount` is the Decimal value; callers wrap it into their money type with the company currency.
    public init(_ title: LocalizedStringKey, amount: Binding<Decimal?>, currencyCode: String) {
        self.title = title; _amount = amount; self.currencyCode = currencyCode
    }

    public var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(verbatim: currencySymbol).font(DSTypography.money(.title3)).foregroundStyle(DSColor.textSecondary)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .font(DSTypography.money(.title2))
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .onChange(of: text) { _, newValue in amount = LocaleNumberParser.decimal(from: newValue, locale: locale) }
                .onChange(of: focused) { _, isFocused in if !isFocused, let amount { text = LocaleNumberParser.string(amount, locale: locale, fractionDigits: 2) } }
                .onAppear { if let amount { text = LocaleNumberParser.string(amount, locale: locale, fractionDigits: 2) } }
        }
        .frame(minHeight: DSSpacing.minTouch)
    }

    private var currencySymbol: String {
        locale.localizedCurrencySymbol(forCurrencyCode: currencyCode) ?? currencyCode
    }
}

private extension Locale {
    func localizedCurrencySymbol(forCurrencyCode code: String) -> String? {
        var components = Locale.Components(locale: self)
        components.currency = Locale.Currency(code)
        return Locale(components: components).currencySymbol
    }
}
```

`DecimalField.swift`:

```swift
import SwiftUI

public struct DecimalField: View {
    private let title: LocalizedStringKey
    @Binding private var value: Decimal?
    private let fractionDigits: Int
    @Environment(\.locale) private var locale
    @State private var text = ""
    @FocusState private var focused: Bool

    public init(_ title: LocalizedStringKey, value: Binding<Decimal?>, fractionDigits: Int = 2) {
        self.title = title; _value = value; self.fractionDigits = fractionDigits
    }

    public var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .font(DSTypography.money(.body))
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onChange(of: text) { _, newValue in value = LocaleNumberParser.decimal(from: newValue, locale: locale) }
            .onChange(of: focused) { _, isFocused in if !isFocused, let value { text = LocaleNumberParser.string(value, locale: locale, fractionDigits: fractionDigits) } }
            .onAppear { if let value { text = LocaleNumberParser.string(value, locale: locale, fractionDigits: fractionDigits) } }
            .frame(minHeight: DSSpacing.minTouch)
    }
}

public struct IntegerField: View {
    private let title: LocalizedStringKey
    @Binding private var value: Int?
    @State private var text = ""

    public init(_ title: LocalizedStringKey, value: Binding<Int?>) { self.title = title; _value = value }

    public var body: some View {
        TextField(title, text: $text)
            .keyboardType(.numberPad)
            .font(DSTypography.money(.body))
            .multilineTextAlignment(.trailing)
            .onChange(of: text) { _, newValue in value = Int(newValue.filter(\.isNumber)) }
            .onAppear { if let value { text = String(value) } }
            .frame(minHeight: DSSpacing.minTouch)
    }
}
```

`ChoiceChips.swift`:

```swift
import SwiftUI

public struct ChoiceChips<T: Hashable>: View {
    private let options: [T]
    @Binding private var selection: T?
    private let label: (T) -> LocalizedStringKey

    public init(options: [T], selection: Binding<T?>, label: @escaping (T) -> LocalizedStringKey) {
        self.options = options; _selection = selection; self.label = label
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button { selection = selected ? nil : option } label: {
                        Text(label(option))
                            .font(DSTypography.callout.weight(.medium))
                            .padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.sm)
                            .frame(minHeight: DSSpacing.minTouch)
                            .background(selected ? DSColor.accent : DSColor.surface, in: Capsule())
                            .foregroundStyle(selected ? DSColor.onAccent : DSColor.textPrimary)
                            .overlay(Capsule().strokeBorder(DSColor.border, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
    }
}
```

`StepHeader.swift`:

```swift
import SwiftUI

public struct StepHeader: View {
    private let title: LocalizedStringKey
    private let step: Int
    private let total: Int

    public init(title: LocalizedStringKey, step: Int, total: Int) { self.title = title; self.step = step; self.total = total }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(title).font(DSTypography.title).foregroundStyle(DSColor.textPrimary)
                Spacer()
                Text(verbatim: "\(step)/\(total)").font(DSTypography.money(.callout)).foregroundStyle(DSColor.textSecondary)
            }
            ProgressBar(progress: Int((Double(step) / Double(max(total, 1)) * 100).rounded()))
        }
        .padding(.horizontal, DSSpacing.lg)
    }
}
```

(`Double` ở đây nằm trong DesignSystem, không bị lint cấm — lint chỉ quét Domain/Data.)

Thêm vào `ComponentGalleryView` một section "gallery.inputs" chứa `MoneyField("gallery.contractValue", amount: .constant(Decimal(38_000)), currencyCode: "CAD")`, `DecimalField("gallery.quantity", value: .constant(7.5))`, `IntegerField("gallery.workers", value: .constant(3))`, `ChoiceChips(options: ["a","b"], selection: .constant("a")) { _ in "gallery.badge" }` (literal `"a"`,`"b"` trên dòng có `lint:allow-string`), `StepHeader(title: "gallery.progress", step: 6, total: 12)`. Key mới: `gallery.inputs`, `gallery.quantity`, `gallery.workers`.

- [ ] **Step 2: `ScopeFieldCatalog.swift`** (FeatureSupport)

```swift
import SwiftUI
import Domain

public struct ScopeFieldDefinition: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case integer, decimal, text, toggle, choice([String]) }
    public let key: String
    public let kind: Kind
    public let unitKey: String?
    public init(key: String, kind: Kind, unitKey: String? = nil) { self.key = key; self.kind = kind; self.unitKey = unitKey }
}

/// Spec Appendix B. Keys are catalog ids; labels come from the String Catalog as `scope.field.<key>`.
public enum ScopeFieldCatalog {
    public static let customPrefix = "custom:"

    public static let common: [ScopeFieldDefinition] = [
        ScopeFieldDefinition(key: "squareFootage", kind: .decimal, unitKey: "sqft"),
        ScopeFieldDefinition(key: "rooms", kind: .integer),
        ScopeFieldDefinition(key: "floors", kind: .integer),
        ScopeFieldDefinition(key: "itemsToRepair", kind: .integer),
        ScopeFieldDefinition(key: "itemsToInstall", kind: .integer),
    ]

    private static let byType: [JobType: [ScopeFieldDefinition]] = [
        .generalRenovation: [ScopeFieldDefinition(key: "bathrooms", kind: .integer), ScopeFieldDefinition(key: "windows", kind: .integer), ScopeFieldDefinition(key: "doors", kind: .integer)],
        .basementRenovation: [ScopeFieldDefinition(key: "bedrooms", kind: .integer), ScopeFieldDefinition(key: "bathrooms", kind: .integer), ScopeFieldDefinition(key: "egressWindows", kind: .integer),
                              ScopeFieldDefinition(key: "ceilingHeight", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "wetBar", kind: .toggle)],
        .kitchen: [ScopeFieldDefinition(key: "cabinetLinearFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "countertopType", kind: .choice(["laminate", "quartz", "granite", "butcherBlock", "other"])),
                   ScopeFieldDefinition(key: "appliances", kind: .integer), ScopeFieldDefinition(key: "island", kind: .toggle), ScopeFieldDefinition(key: "backsplashSqft", kind: .decimal, unitKey: "sqft")],
        .bathroom: [ScopeFieldDefinition(key: "fixtures", kind: .integer), ScopeFieldDefinition(key: "tub", kind: .toggle), ScopeFieldDefinition(key: "shower", kind: .toggle),
                    ScopeFieldDefinition(key: "vanity", kind: .toggle), ScopeFieldDefinition(key: "toilet", kind: .toggle), ScopeFieldDefinition(key: "tileSqft", kind: .decimal, unitKey: "sqft")],
        .landscaping: [ScopeFieldDefinition(key: "lotSize", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "grassArea", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "patioArea", kind: .decimal, unitKey: "sqft"),
                       ScopeFieldDefinition(key: "fenceLength", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "trees", kind: .integer), ScopeFieldDefinition(key: "irrigation", kind: .toggle)],
        .roofing: [ScopeFieldDefinition(key: "roofSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "roofType", kind: .choice(["asphaltShingle", "metal", "flat", "cedar", "tile", "other"])),
                   ScopeFieldDefinition(key: "slopes", kind: .integer), ScopeFieldDefinition(key: "layersToRemove", kind: .integer), ScopeFieldDefinition(key: "materialType", kind: .text)],
        .plumbing: [ScopeFieldDefinition(key: "fixtures", kind: .integer), ScopeFieldDefinition(key: "bathrooms", kind: .integer), ScopeFieldDefinition(key: "waterHeater", kind: .toggle), ScopeFieldDefinition(key: "repipe", kind: .toggle)],
        .electrical: [ScopeFieldDefinition(key: "outlets", kind: .integer), ScopeFieldDefinition(key: "switches", kind: .integer), ScopeFieldDefinition(key: "lightFixtures", kind: .integer),
                      ScopeFieldDefinition(key: "panelUpgrade", kind: .toggle), ScopeFieldDefinition(key: "panelAmps", kind: .choice(["amps100", "amps200", "other"]))],
        .hvac: [ScopeFieldDefinition(key: "systemType", kind: .choice(["furnace", "heatPump", "centralAir", "ductless", "other"])), ScopeFieldDefinition(key: "units", kind: .integer),
                ScopeFieldDefinition(key: "ductworkFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "thermostats", kind: .integer)],
        .flooring: [ScopeFieldDefinition(key: "floorSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "flooringType", kind: .choice(["hardwood", "laminate", "vinyl", "tile", "carpet", "other"])),
                    ScopeFieldDefinition(key: "stairs", kind: .integer), ScopeFieldDefinition(key: "removalRequired", kind: .toggle)],
        .painting: [ScopeFieldDefinition(key: "wallSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "ceilingSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "doors", kind: .integer),
                    ScopeFieldDefinition(key: "trimLinearFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "coats", kind: .integer)],
        .drywall: [ScopeFieldDefinition(key: "sheets", kind: .integer), ScopeFieldDefinition(key: "drywallSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "ceilings", kind: .toggle),
                   ScopeFieldDefinition(key: "finishLevel", kind: .choice(["level3", "level4", "level5"]))],
        .concrete: [ScopeFieldDefinition(key: "concreteSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "thicknessInches", kind: .decimal, unitKey: "in"),
                    ScopeFieldDefinition(key: "concreteType", kind: .choice(["slab", "driveway", "sidewalk", "foundation", "other"])), ScopeFieldDefinition(key: "rebar", kind: .toggle)],
        .deckFence: [ScopeFieldDefinition(key: "deckSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "fenceLength", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "fenceHeight", kind: .decimal, unitKey: "ft"),
                     ScopeFieldDefinition(key: "deckMaterial", kind: .choice(["pressureTreated", "cedar", "composite", "vinyl", "other"])), ScopeFieldDefinition(key: "stairs", kind: .integer), ScopeFieldDefinition(key: "railingFeet", kind: .decimal, unitKey: "ft")],
        .framing: [ScopeFieldDefinition(key: "wallLinearFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "framingSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "loadBearing", kind: .toggle)],
        .windowsDoors: [ScopeFieldDefinition(key: "windows", kind: .integer), ScopeFieldDefinition(key: "doors", kind: .integer), ScopeFieldDefinition(key: "exteriorDoors", kind: .integer), ScopeFieldDefinition(key: "patioDoors", kind: .integer)],
        .exterior: [ScopeFieldDefinition(key: "sidingSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "sidingType", kind: .choice(["vinyl", "wood", "fiberCement", "brick", "stucco", "other"])),
                    ScopeFieldDefinition(key: "soffitFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "gutterFeet", kind: .decimal, unitKey: "ft")],
        .demolition: [ScopeFieldDefinition(key: "demoSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "dumpsters", kind: .integer), ScopeFieldDefinition(key: "hazardousMaterials", kind: .toggle)],
        .commercial: [ScopeFieldDefinition(key: "commercialSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "units", kind: .integer), ScopeFieldDefinition(key: "permitsRequired", kind: .toggle)],
        .other: [],
    ]

    public static func fields(for type: JobType) -> [ScopeFieldDefinition] { common + (byType[type] ?? []) }

    public static func definition(forKey key: String) -> ScopeFieldDefinition? {
        (common + byType.values.flatMap { $0 }).first { $0.key == key }
    }

    public static func isCustom(_ key: String) -> Bool { key.hasPrefix(customPrefix) }
    public static func customLabel(_ key: String) -> String { String(key.dropFirst(customPrefix.count)) }

    /// nil for custom keys (show verbatim).
    public static func labelKey(forFieldKey key: String) -> LocalizedStringKey? {
        isCustom(key) ? nil : LocalizedStringKey("scope.field." + key)
    }
    public static func optionLabelKey(_ option: String) -> LocalizedStringKey { LocalizedStringKey("scope.option." + option) }
    public static func unitLabelKey(_ unit: String) -> LocalizedStringKey { LocalizedStringKey("scope.unit." + unit) }
}
```

- [ ] **Step 3: `MaterialSuggestions.swift`, `DraftLabels.swift`, `PhaseFilter.swift`**

```swift
// MaterialSuggestions.swift
import Domain

public enum MaterialSuggestions {
    private static let base = ["Lumber", "Drywall", "Flooring", "Paint", "Tile", "Fasteners", "Other"]
    private static let byType: [JobType: [String]] = [
        .kitchen: ["Cabinets", "Countertop", "Backsplash", "Appliances"], .bathroom: ["Vanity", "Tub/Shower", "Toilet", "Plumbing fixtures"],
        .roofing: ["Shingles", "Underlayment", "Flashing", "Vents"], .landscaping: ["Sod", "Pavers", "Gravel", "Plants", "Fence panels"],
        .electrical: ["Wire", "Panel", "Outlets/Switches", "Fixtures"], .plumbing: ["Pipe", "Fittings", "Water heater", "Fixtures"],
        .flooring: ["Flooring", "Underlay", "Transitions"], .painting: ["Paint", "Primer", "Caulk"], .concrete: ["Concrete", "Rebar", "Forms"],
        .deckFence: ["Deck boards", "Posts", "Fence panels", "Hardware"], .exterior: ["Siding", "Soffit", "Gutters"], .drywall: ["Drywall sheets", "Mud", "Tape"],
        .hvac: ["Unit", "Ductwork", "Thermostat"], .framing: ["Lumber", "Hangers", "Sheathing"], .windowsDoors: ["Windows", "Doors", "Trim"],
    ]
    /// English labels (user data once chosen, not localized).
    public static func labels(for type: JobType?) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for label in (type.flatMap { byType[$0] } ?? []) + base where seen.insert(label).inserted { out.append(label) }
        return out
    }
}
```

```swift
// DraftLabels.swift
import SwiftUI
import Domain

public extension OtherCostKind { var titleKey: LocalizedStringKey { LocalizedStringKey("otherCost." + rawValue) } }
public extension PaymentScheduleTemplate { var titleKey: LocalizedStringKey { LocalizedStringKey("schedule.template." + rawValue) } }

public enum RowLabel {
    /// Labels starting with `schedule.row.` are catalog keys; anything else is user text.
    public static func text(_ label: String) -> Text {
        label.hasPrefix("schedule.row.") ? Text(LocalizedStringKey(label)) : Text(verbatim: label)
    }
}
```

```swift
// PhaseFilter.swift
import SwiftUI
import Domain

public enum PhaseFilter: String, CaseIterable, Sendable {
    case all, inWork, preStart, workDone, terminal
    public var titleKey: LocalizedStringKey { LocalizedStringKey("projects.filter." + rawValue) }
    public func matches(_ status: ProjectStatus) -> Bool {
        switch self {
        case .all: return true
        case .inWork: return status.phase == .inWork
        case .preStart: return status.phase == .preStart
        case .workDone: return status.phase == .workDone
        case .terminal: return status.phase == .terminal
        }
    }
}
```

- [ ] **Step 4: Chuyển `ProjectCardView` sang FeatureSupport**

Xóa `Packages/Features/Sources/HomeFeature/ProjectCardView.swift`; tạo `Packages/Features/Sources/FeatureSupport/ProjectCardView.swift` với nội dung cũ, đổi `struct ProjectCardView` → `public struct ProjectCardView`, thêm `public init(summary: ProjectSummary, progress: Int)`, và dưới `FormRow("home.contractValue")` thêm:

```swift
                if let start = summary.project.startDate, let end = summary.project.estimatedCompletionDate {
                    Text(verbatim: "\(start.storageString) → \(end.storageString)")
                        .font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
```

(Format ngày theo locale ở 2b; Foundation hiện chưa có helper date → dùng storage string tạm, ghi deferred.) `HomeView` giữ nguyên lời gọi (`import FeatureSupport` đã có).

- [ ] **Step 5: `Package.swift` thêm target**

Thêm `"CustomersFeature"` vào product `targets` và `.target(name: "CustomersFeature", dependencies: featureDeps, path: "Sources/CustomersFeature")`. Tạo file tạm `Sources/CustomersFeature/CustomersFeature.swift` chứa `import SwiftUI` + `enum CustomersFeatureModule {}` để target không rỗng (Task 20 thay bằng view thật).

- [ ] **Step 6: String Catalog — thêm key** (cùng format JSON Foundation; mỗi key có `en` và `vi`)

| Key | en | vi |
|---|---|---|
| gallery.inputs | Inputs | Ô nhập |
| gallery.quantity | Quantity | Số lượng |
| gallery.workers | Workers | Số thợ |
| scope.unit.sqft | sq ft | sqft |
| scope.unit.ft | ft | ft |
| scope.unit.in | in | inch |
| scope.field.squareFootage | Square footage | Diện tích |
| scope.field.rooms | Rooms | Số phòng |
| scope.field.floors | Floors | Số tầng |
| scope.field.itemsToRepair | Items to repair | Hạng mục sửa |
| scope.field.itemsToInstall | Items to install | Hạng mục lắp |
| scope.field.bathrooms | Bathrooms | Phòng tắm |
| scope.field.windows | Windows | Cửa sổ |
| scope.field.doors | Doors | Cửa |
| scope.field.bedrooms | Bedrooms | Phòng ngủ |
| scope.field.egressWindows | Egress windows | Egress window |
| scope.field.ceilingHeight | Ceiling height | Chiều cao trần |
| scope.field.wetBar | Wet bar | Wet bar |
| scope.field.cabinetLinearFeet | Cabinets (linear feet) | Tủ bếp (ft dài) |
| scope.field.countertopType | Countertop type | Loại countertop |
| scope.field.appliances | Appliances | Thiết bị |
| scope.field.island | Island | Đảo bếp |
| scope.field.backsplashSqft | Backsplash area | Diện tích backsplash |
| scope.field.fixtures | Fixtures | Fixtures |
| scope.field.tub | Tub | Bồn tắm |
| scope.field.shower | Shower | Vòi sen |
| scope.field.vanity | Vanity | Vanity |
| scope.field.toilet | Toilet | Bồn cầu |
| scope.field.tileSqft | Tile area | Diện tích tile |
| scope.field.lotSize | Lot size | Diện tích lô |
| scope.field.grassArea | Grass area | Diện tích cỏ |
| scope.field.patioArea | Patio area | Diện tích patio |
| scope.field.fenceLength | Fence length | Chiều dài fence |
| scope.field.trees | Trees | Cây |
| scope.field.irrigation | Irrigation | Tưới tự động |
| scope.field.roofSqft | Roof area | Diện tích mái |
| scope.field.roofType | Roof type | Loại mái |
| scope.field.slopes | Slopes | Số mặt dốc |
| scope.field.layersToRemove | Layers to remove | Lớp cần gỡ |
| scope.field.materialType | Material type | Loại material |
| scope.field.waterHeater | Water heater | Máy nước nóng |
| scope.field.repipe | Repipe | Thay ống toàn bộ |
| scope.field.outlets | Outlets | Ổ cắm |
| scope.field.switches | Switches | Công tắc |
| scope.field.lightFixtures | Light fixtures | Đèn |
| scope.field.panelUpgrade | Panel upgrade | Nâng cấp panel |
| scope.field.panelAmps | Panel amps | Panel (amp) |
| scope.field.systemType | System type | Loại hệ thống |
| scope.field.units | Units | Số đơn vị |
| scope.field.ductworkFeet | Ductwork (feet) | Ống gió (ft) |
| scope.field.thermostats | Thermostats | Thermostat |
| scope.field.floorSqft | Floor area | Diện tích sàn |
| scope.field.flooringType | Flooring type | Loại flooring |
| scope.field.stairs | Stairs | Cầu thang |
| scope.field.removalRequired | Removal required | Cần tháo dỡ cũ |
| scope.field.wallSqft | Wall area | Diện tích tường |
| scope.field.ceilingSqft | Ceiling area | Diện tích trần |
| scope.field.trimLinearFeet | Trim (linear feet) | Trim (ft dài) |
| scope.field.coats | Coats | Số lớp sơn |
| scope.field.sheets | Sheets | Số tấm |
| scope.field.drywallSqft | Drywall area | Diện tích drywall |
| scope.field.ceilings | Ceilings | Trần |
| scope.field.finishLevel | Finish level | Finish level |
| scope.field.concreteSqft | Concrete area | Diện tích bê tông |
| scope.field.thicknessInches | Thickness | Độ dày |
| scope.field.concreteType | Concrete type | Loại hạng mục |
| scope.field.rebar | Rebar | Cốt thép |
| scope.field.deckSqft | Deck area | Diện tích deck |
| scope.field.fenceHeight | Fence height | Chiều cao fence |
| scope.field.deckMaterial | Material | Vật liệu |
| scope.field.railingFeet | Railing (feet) | Lan can (ft) |
| scope.field.wallLinearFeet | Walls (linear feet) | Tường (ft dài) |
| scope.field.framingSqft | Framing area | Diện tích framing |
| scope.field.loadBearing | Load-bearing | Tường chịu lực |
| scope.field.exteriorDoors | Exterior doors | Cửa ngoài |
| scope.field.patioDoors | Patio doors | Cửa patio |
| scope.field.sidingSqft | Siding area | Diện tích siding |
| scope.field.sidingType | Siding type | Loại siding |
| scope.field.soffitFeet | Soffit (feet) | Soffit (ft) |
| scope.field.gutterFeet | Gutters (feet) | Máng xối (ft) |
| scope.field.demoSqft | Demolition area | Diện tích demolition |
| scope.field.dumpsters | Dumpsters | Dumpster |
| scope.field.hazardousMaterials | Hazardous materials | Vật liệu nguy hại |
| scope.field.commercialSqft | Area | Diện tích |
| scope.field.permitsRequired | Permits required | Cần permit |
| scope.option.laminate | Laminate | Laminate |
| scope.option.quartz | Quartz | Quartz |
| scope.option.granite | Granite | Granite |
| scope.option.butcherBlock | Butcher block | Butcher block |
| scope.option.other | Other | Khác |
| scope.option.asphaltShingle | Asphalt shingle | Asphalt shingle |
| scope.option.metal | Metal | Kim loại |
| scope.option.flat | Flat | Mái bằng |
| scope.option.cedar | Cedar | Cedar |
| scope.option.tile | Tile | Tile |
| scope.option.amps100 | 100 A | 100 A |
| scope.option.amps200 | 200 A | 200 A |
| scope.option.furnace | Furnace | Furnace |
| scope.option.heatPump | Heat pump | Heat pump |
| scope.option.centralAir | Central air | Máy lạnh trung tâm |
| scope.option.ductless | Ductless | Ductless |
| scope.option.hardwood | Hardwood | Gỗ tự nhiên |
| scope.option.vinyl | Vinyl | Vinyl |
| scope.option.carpet | Carpet | Thảm |
| scope.option.level3 | Level 3 | Level 3 |
| scope.option.level4 | Level 4 | Level 4 |
| scope.option.level5 | Level 5 | Level 5 |
| scope.option.slab | Slab | Slab |
| scope.option.driveway | Driveway | Driveway |
| scope.option.sidewalk | Sidewalk | Vỉa hè |
| scope.option.foundation | Foundation | Móng |
| scope.option.pressureTreated | Pressure-treated | Pressure-treated |
| scope.option.composite | Composite | Composite |
| scope.option.wood | Wood | Gỗ |
| scope.option.fiberCement | Fiber cement | Fiber cement |
| scope.option.brick | Brick | Gạch |
| scope.option.stucco | Stucco | Stucco |
| otherCost.subcontractors | Subcontractors | Subcontractor |
| otherCost.equipmentRental | Equipment rental | Thuê thiết bị |
| otherCost.toolRental | Tool rental | Thuê dụng cụ |
| otherCost.permits | Permits | Permit |
| otherCost.inspectionFees | Inspection fees | Phí inspection |
| otherCost.dumpster | Dumpster | Dumpster |
| otherCost.delivery | Delivery | Vận chuyển |
| otherCost.parking | Parking | Đậu xe |
| otherCost.gas | Gas | Xăng |
| otherCost.wasteDisposal | Waste disposal | Đổ rác |
| otherCost.other | Other | Khác |
| schedule.template.depositFinal | Deposit + Final | Deposit + Cuối |
| schedule.template.depositProgressFinal | Deposit + Progress + Final | Deposit + Giữa + Cuối |
| schedule.template.fourStage | 20 / 30 / 30 / 20 | 20 / 30 / 30 / 20 |
| schedule.template.custom | Custom | Tự chia |
| schedule.row.deposit | Deposit | Deposit |
| schedule.row.progress | Progress payment | Thanh toán giữa kỳ |
| schedule.row.stage2 | Stage 2 | Đợt 2 |
| schedule.row.stage3 | Stage 3 | Đợt 3 |
| schedule.row.final | Final payment | Thanh toán cuối |
| schedule.row.labourQuick | Crew (quick estimate) | Crew (ước tính nhanh) |
| projects.filter.all | All | Tất cả |
| projects.filter.inWork | Active | Đang làm |
| projects.filter.preStart | Upcoming | Sắp tới |
| projects.filter.workDone | Done | Xong |
| projects.filter.terminal | Closed | Đã đóng |

- [ ] **Step 7: `check_localization.py` mở rộng** — thêm sau vòng kiểm tra View (trước `for e in errors`):

```python
    # Keys generated from Swift catalogs must exist too.
    generated: set[str] = set()
    catalog_swift = (ROOT / "Packages/Features/Sources/FeatureSupport/ScopeFieldCatalog.swift").read_text(encoding="utf-8")
    for m in re.finditer(r'key: "([A-Za-z0-9]+)"', catalog_swift): generated.add(f"scope.field.{m.group(1)}")
    for m in re.finditer(r'unitKey: "([a-z]+)"', catalog_swift): generated.add(f"scope.unit.{m.group(1)}")
    for m in re.finditer(r"\.choice\(\[([^\]]+)\]\)", catalog_swift):
        for opt in re.findall(r'"([A-Za-z0-9]+)"', m.group(1)): generated.add(f"scope.option.{opt}")
    enums = (ROOT / "Packages/Domain/Sources/Domain/Drafts/OtherCostKind.swift").read_text(encoding="utf-8")
    body = enums.split("{", 1)[1]
    for case_line in re.findall(r"case ([a-zA-Z0-9, ]+)", body.split("var costGroup")[0]):
        for name in case_line.split(","): generated.add(f"otherCost.{name.strip()}")
    for tpl in ["depositFinal", "depositProgressFinal", "fourStage", "custom"]: generated.add(f"schedule.template.{tpl}")
    for row in ["deposit", "progress", "stage2", "stage3", "final", "labourQuick"]: generated.add(f"schedule.row.{row}")
    for phase in ["all", "inWork", "preStart", "workDone", "terminal"]: generated.add(f"projects.filter.{phase}")
    for key in sorted(generated):
        if key not in strings: errors.append(f"generated key '{key}' missing from catalog")
```

Và thêm `"lint:allow-string"` đã có; literal `"a"`, `"b"` trong gallery nằm trên dòng có marker.

- [ ] **Step 8: Chạy script, commit**

Run: `python scripts/check_localization.py` → `0 error(s)`; `python scripts/lint_sources.py` → `0 error(s)`.

```bash
git add Packages/DesignSystem Packages/Features scripts App/Resources
git commit -m "feat(features): add scope field catalog, draft labels, input fields and generated-key lint"
```

---

### Task 12: `ProjectWizardViewModel`

**Files:**
- Create: `Packages/Features/Sources/ProjectsFeature/Wizard/WizardStep.swift`, `ProjectWizardViewModel.swift`

**Interfaces:**
- Consumes: `ProjectDraft`, `ProjectDraftAssembler`, `DraftFinancialPreview`, `ScheduleMath`, `DraftError`, `ProjectRepository.create`, `DraftStore`, `CurrencyCode`.
- Produces:
  - `public enum WizardStep: Int, CaseIterable { jobType = 1, customer, location, scope, timeline, labour, material, otherCosts, price, deposit, schedule, review; var titleKey: LocalizedStringKey ("wizard.step.<name>"); var isRequired: Bool (jobType, customer, location, price); var requiredFields: Set<DraftField> }`
  - `@Observable @MainActor public final class ProjectWizardViewModel` với:
    - `init(draft: ProjectDraft, companyId: UUID, currency: CurrencyCode, projectRepository: any ProjectRepository, draftStore: any DraftStore, actor: ActivityActor, onCreated: @escaping (UUID) -> Void, onDismiss: @escaping () -> Void)`
    - `var draft: ProjectDraft` (didSet → `scheduleAutosave()`), `private(set) var step: WizardStep`, `var missing: Set<DraftField>`, `var preview: DraftFinancialPreview`, `private(set) var isSaving`, `var errorKey: LocalizedStringKey?`, `var showCloseDialog: Bool`
    - `var canContinue: Bool` (bước bắt buộc: field của bước có giá trị; bước Timeline: không `completionBeforeStart`), `var canSkip: Bool`
    - `func next()`, `func skip()`, `func back()`, `func go(to: WizardStep)`, `func requestClose()` (draft rỗng → `onDismiss()`; khác → `showCloseDialog = true`), `func saveDraftAndClose()`, `func discardDraftAndClose()`
    - `func applyTemplate(_:)`, `func scheduleEdited(_ field: EditedField)`, `func create() async`
    - `func flushAutosave()` (gọi khi app vào background).

- [ ] **Step 1: `WizardStep.swift`**

```swift
import SwiftUI
import Domain

public enum WizardStep: Int, CaseIterable, Sendable {
    case jobType = 1, customer, location, scope, timeline, labour, material, otherCosts, price, deposit, schedule, review

    public var titleKey: LocalizedStringKey {
        switch self {
        case .jobType: return "wizard.step.jobType"
        case .customer: return "wizard.step.customer"
        case .location: return "wizard.step.location"
        case .scope: return "wizard.step.scope"
        case .timeline: return "wizard.step.timeline"
        case .labour: return "wizard.step.labour"
        case .material: return "wizard.step.material"
        case .otherCosts: return "wizard.step.otherCosts"
        case .price: return "wizard.step.price"
        case .deposit: return "wizard.step.deposit"
        case .schedule: return "wizard.step.schedule"
        case .review: return "wizard.step.review"
        }
    }

    public var isRequired: Bool { [.jobType, .customer, .location, .price].contains(self) }

    public var requiredFields: Set<DraftField> {
        switch self {
        case .jobType: return [.jobType, .customJobType]
        case .customer: return [.customer]
        case .location: return [.addressLine]
        case .price: return [.contractValue]
        default: return []
        }
    }

    public static let total = WizardStep.allCases.count
    public var next: WizardStep? { WizardStep(rawValue: rawValue + 1) }
    public var previous: WizardStep? { WizardStep(rawValue: rawValue - 1) }

    /// The step that owns a missing field (for "Fix" buttons on Review).
    public static func owning(_ field: DraftField) -> WizardStep {
        switch field {
        case .jobType, .customJobType: return .jobType
        case .customer: return .customer
        case .addressLine: return .location
        case .contractValue: return .price
        }
    }
}
```

- [ ] **Step 2: `ProjectWizardViewModel.swift`**

```swift
import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class ProjectWizardViewModel {
    public var draft: ProjectDraft { didSet { if draft != oldValue { recomputePreview(); scheduleAutosave() } } }
    public private(set) var step: WizardStep
    public var missing: Set<DraftField> = []
    public private(set) var preview: DraftFinancialPreview
    public private(set) var isSaving = false
    public var errorKey: LocalizedStringKey?
    public var showCloseDialog = false

    public let companyId: UUID
    public let currency: CurrencyCode
    private let projectRepository: any ProjectRepository
    private let draftStore: any DraftStore
    private let actor: ActivityActor
    private let onCreated: (UUID) -> Void
    private let onDismiss: () -> Void
    private var autosaveTask: Task<Void, Never>?

    public init(draft: ProjectDraft, companyId: UUID, currency: CurrencyCode, projectRepository: any ProjectRepository, draftStore: any DraftStore,
                actor: ActivityActor, onCreated: @escaping (UUID) -> Void, onDismiss: @escaping () -> Void) {
        self.draft = draft
        self.step = WizardStep(rawValue: draft.step) ?? .jobType
        self.preview = DraftFinancialPreview.compute(draft, currency: currency)
        self.companyId = companyId; self.currency = currency
        self.projectRepository = projectRepository; self.draftStore = draftStore; self.actor = actor
        self.onCreated = onCreated; self.onDismiss = onDismiss
    }

    // MARK: Navigation

    public var canContinue: Bool {
        switch step {
        case .jobType: return draft.jobType != nil && (draft.jobType != .other || !(draft.customJobType ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
        case .customer:
            switch draft.customer {
            case .existing?: return true
            case .new(let input)?: return !input.name.trimmingCharacters(in: .whitespaces).isEmpty
            case nil: return false
            }
        case .location: return !(draft.address?.line ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case .timeline:
            if let s = draft.startDate, let e = draft.estimatedCompletionDate { return e >= s }
            return true
        case .price: return draft.contractValue != nil
        default: return true
        }
    }

    public var canSkip: Bool { !step.isRequired && step != .review }

    public func next() { guard canContinue, let n = step.next else { return }; move(to: n) }
    public func skip() { guard canSkip, let n = step.next else { return }; move(to: n) }
    public func back() { guard let p = step.previous else { return }; move(to: p) }
    public func go(to target: WizardStep) { move(to: target) }

    private func move(to target: WizardStep) {
        step = target
        draft.step = target.rawValue
        persistNow()
    }

    // MARK: Close / drafts

    public func requestClose() {
        if draft.isEmpty { discardDraftAndClose() } else { showCloseDialog = true }
    }

    public func saveDraftAndClose() { persistNow(); onDismiss() }

    public func discardDraftAndClose() {
        autosaveTask?.cancel()
        try? draftStore.clear()
        onDismiss()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    public func flushAutosave() { autosaveTask?.cancel(); persistNow() }

    private func persistNow() {
        guard !draft.isEmpty else { return }
        var copy = draft
        copy.updatedAt = Date()
        try? draftStore.save(copy)
    }

    // MARK: Schedule helpers

    public func applyTemplate(_ template: PaymentScheduleTemplate) {
        draft.scheduleTemplate = template
        var depositPct: Percentage?
        if case .percentage(let p)? = draft.deposit?.mode { depositPct = p }
        let rows = template.rows(depositPercentage: depositPct)
        draft.schedule = ScheduleMath.recompute(rows: rows, contract: draft.contractValue ?? .zero(currency), edited: .none).rows
    }

    public func scheduleEdited(_ field: EditedField) {
        draft.schedule = ScheduleMath.recompute(rows: draft.schedule, contract: draft.contractValue ?? .zero(currency), edited: field).rows
    }

    private func recomputePreview() { preview = DraftFinancialPreview.compute(draft, currency: currency) }

    // MARK: Create

    public func create() async {
        guard !isSaving else { return }
        isSaving = true; errorKey = nil
        defer { isSaving = false }
        do {
            let bundle = try ProjectDraftAssembler.assemble(draft, companyId: companyId, currency: currency, now: Date())
            try await projectRepository.create(bundle, actor: actor)
            autosaveTask?.cancel()
            try? draftStore.clear()
            onCreated(bundle.project.id)
        } catch DraftError.missing(let fields) {
            missing = fields
            errorKey = "wizard.error.missing"
        } catch DraftError.completionBeforeStart {
            errorKey = "wizard.error.completionBeforeStart"
        } catch {
            errorKey = "wizard.error.saveFailed"
        }
    }
}
```

Ghi chú: `didSet` trên `draft` so sánh `!= oldValue` (ProjectDraft Equatable) để tránh autosave thừa; `move(to:)` đổi `draft.step` → didSet lại schedule autosave rồi `persistNow` lưu ngay — chấp nhận.

- [ ] **Step 3: Thêm key** — `wizard.step.*` (12), `wizard.error.missing` ("Please fill the required fields." / "Điền các ô bắt buộc."), `wizard.error.completionBeforeStart` ("Completion date is before the start date." / "Ngày hoàn thành trước ngày bắt đầu."), `wizard.error.saveFailed` ("Could not save the project. Try again." / "Không lưu được dự án. Thử lại."). Bản vi của 12 bước: Loại job, Khách hàng, Địa điểm, Phạm vi, Thời gian, Labour, Material, Chi phí khác, Giá, Deposit, Lịch thanh toán, Xem lại. Bản en: Job type, Customer, Location, Scope, Timeline, Labour, Materials, Other costs, Price, Deposit, Payment schedule, Review.

- [ ] **Step 4: Script check, commit**

```bash
git add Packages/Features App/Resources
git commit -m "feat(projects): add wizard step model and view model"
```

---

### Task 13: Wizard shell + bước 1–3 (Job type, Customer, Location)

**Files:**
- Create: `Packages/Features/Sources/ProjectsFeature/Wizard/ProjectWizardView.swift`, `StepFooter.swift`, `Steps/JobTypeStep.swift`, `Steps/CustomerStep.swift`, `Steps/LocationStep.swift`

**Interfaces:**
- Consumes: `ProjectWizardViewModel`, `StepHeader`, `PrimaryButton`, `SecondaryButton`, `Card`, `FormRow`, `JobType.titleKey`, `CustomerRepository.observeAll`.
- Produces: `public struct ProjectWizardView: View { init(viewModel: ProjectWizardViewModel, customerRepository: any CustomerRepository) }`; mỗi step là `struct XStep: View { @Bindable var viewModel: ProjectWizardViewModel }` (internal). `JobTypeStep` còn được dùng ở edit? Không — Scope/Timeline/Estimate/Price/Deposit/Schedule mới dùng lại; nhưng viết tất cả step cùng kiểu để nhất quán.
- Accessibility identifiers: `wizard_close`, `wizard_continue`, `wizard_skip`, `wizard_back`, `wizard_jobtype_<raw>`, `wizard_custom_jobtype`, `wizard_customer_search`, `wizard_new_customer`, `wizard_customer_name`, `wizard_address_line`, `wizard_open_maps`.

- [ ] **Step 1: `StepFooter.swift`**

```swift
import SwiftUI
import DesignSystem

struct StepFooter: View {
    let canContinue: Bool
    let canSkip: Bool
    let isLast: Bool
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            PrimaryButton(isLast ? "wizard.create" : "wizard.continue", systemImage: isLast ? "checkmark" : "arrow.right", action: onContinue)
                .disabled(!canContinue).opacity(canContinue ? 1 : 0.5)
                .accessibilityIdentifier("wizard_continue")
            if canSkip {
                SecondaryButton("wizard.skip", action: onSkip).accessibilityIdentifier("wizard_skip")
            }
        }
        .padding(.horizontal, DSSpacing.lg).padding(.bottom, DSSpacing.md)
        .background(DSColor.background)
    }
}
```

- [ ] **Step 2: `ProjectWizardView.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct ProjectWizardView: View {
    @Bindable private var viewModel: ProjectWizardViewModel
    private let customerRepository: any CustomerRepository
    @Environment(\.scenePhase) private var scenePhase

    public init(viewModel: ProjectWizardViewModel, customerRepository: any CustomerRepository) {
        self.viewModel = viewModel; self.customerRepository = customerRepository
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StepHeader(title: viewModel.step.titleKey, step: viewModel.step.rawValue, total: WizardStep.total)
                    .padding(.top, DSSpacing.sm)
                ScrollView {
                    stepBody.padding(.vertical, DSSpacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                if let errorKey = viewModel.errorKey {
                    Text(errorKey).font(DSTypography.callout).foregroundStyle(DSColor.danger).padding(.horizontal, DSSpacing.lg)
                }
                StepFooter(canContinue: viewModel.canContinue, canSkip: viewModel.canSkip, isLast: viewModel.step == .review,
                           onContinue: { if viewModel.step == .review { Task { await viewModel.create() } } else { viewModel.next() } },
                           onSkip: { viewModel.skip() })
            }
            .background(DSColor.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.step.previous != nil {
                        Button { viewModel.back() } label: { Label("wizard.back", systemImage: "chevron.left") }.accessibilityIdentifier("wizard_back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.requestClose() } label: { Image(systemName: "xmark") }.accessibilityIdentifier("wizard_close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("wizard.done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("wizard.close.title", isPresented: $viewModel.showCloseDialog, titleVisibility: .visible) {
                Button("wizard.close.saveDraft") { viewModel.saveDraftAndClose() }
                Button("wizard.close.discard", role: .destructive) { viewModel.discardDraftAndClose() }
                Button("wizard.close.cancel", role: .cancel) {}
            }
            .onChange(of: scenePhase) { _, phase in if phase == .background { viewModel.flushAutosave() } }
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder private var stepBody: some View {
        switch viewModel.step {
        case .jobType: JobTypeStep(viewModel: viewModel)
        case .customer: CustomerStep(viewModel: viewModel, customerRepository: customerRepository)
        case .location: LocationStep(viewModel: viewModel)
        case .scope: ScopeStep(viewModel: viewModel)
        case .timeline: TimelineStep(viewModel: viewModel)
        case .labour: LabourStep(viewModel: viewModel)
        case .material: MaterialStep(viewModel: viewModel)
        case .otherCosts: OtherCostsStep(viewModel: viewModel)
        case .price: PriceStep(viewModel: viewModel)
        case .deposit: DepositStep(viewModel: viewModel)
        case .schedule: ScheduleStep(viewModel: viewModel)
        case .review: ReviewStep(viewModel: viewModel)
        }
    }
}
```

Để Task 13 compile độc lập trên CI trước khi Task 14–17 tồn tại: tạo các file step còn lại (`ScopeStep`… `ReviewStep`) dạng tạm `struct ScopeStep: View { @Bindable var viewModel: ProjectWizardViewModel; var body: some View { EmptyView() } }` trong đúng file đích; Task 14–17 thay nội dung.

- [ ] **Step 3: `JobTypeStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct JobTypeStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    private let columns = [GridItem(.flexible(), spacing: DSSpacing.md), GridItem(.flexible(), spacing: DSSpacing.md)]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            LazyVGrid(columns: columns, spacing: DSSpacing.md) {
                ForEach(JobType.allCases, id: \.self) { type in
                    let selected = viewModel.draft.jobType == type
                    Button { select(type) } label: {
                        VStack(spacing: DSSpacing.sm) {
                            Image(systemName: Self.symbol(for: type)).font(.title2)
                            Text(type.titleKey).font(DSTypography.callout.weight(.medium)).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .padding(DSSpacing.sm)
                        .background(selected ? DSColor.accent : DSColor.surface, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
                        .foregroundStyle(selected ? DSColor.onAccent : DSColor.textPrimary)
                        .overlay(RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous).strokeBorder(DSColor.border, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wizard_jobtype_" + type.rawValue)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            if viewModel.draft.jobType == .other {
                Card {
                    TextField("wizard.jobType.customPlaceholder", text: Binding(get: { viewModel.draft.customJobType ?? "" }, set: { viewModel.draft.customJobType = $0 }))
                        .frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("wizard_custom_jobtype")
                }
                .padding(.horizontal, DSSpacing.lg)
            }
        }
    }

    private func select(_ type: JobType) {
        if viewModel.draft.jobType != type && !viewModel.draft.scopeFields.isEmpty {
            viewModel.pendingJobTypeChange = type   // Task 14 adds the keep/clear dialog
        } else {
            viewModel.draft.jobType = type
        }
        if type != .other { viewModel.draft.customJobType = nil }
    }

    static func symbol(for type: JobType) -> String {
        switch type {
        case .generalRenovation: return "hammer"
        case .basementRenovation: return "stairs"
        case .kitchen: return "fork.knife"
        case .bathroom: return "shower"
        case .landscaping: return "leaf"
        case .roofing: return "house"
        case .plumbing: return "drop"
        case .electrical: return "bolt"
        case .hvac: return "wind"
        case .flooring: return "square.grid.3x3"
        case .painting: return "paintbrush"
        case .drywall: return "rectangle.split.2x1"
        case .concrete: return "cube"
        case .deckFence: return "fence"
        case .framing: return "ruler"
        case .windowsDoors: return "door.left.hand.open"
        case .exterior: return "building.2"
        case .demolition: return "trash"
        case .commercial: return "building"
        case .other: return "ellipsis.circle"
        }
    }
}
```

Thêm vào `ProjectWizardViewModel`: `public var pendingJobTypeChange: JobType?` (Task 14 dùng cho dialog; ở Task 13 chỉ khai báo và `JobTypeStep` gán — khi `scopeFields` rỗng không bao giờ gán).

- [ ] **Step 4: `CustomerStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct CustomerStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    let customerRepository: any CustomerRepository
    @State private var customers: [Customer] = []
    @State private var query = ""
    @State private var creatingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            if creatingNew {
                newCustomerForm
            } else {
                TextField("wizard.customer.search", text: $query)
                    .textFieldStyle(.roundedBorder).padding(.horizontal, DSSpacing.lg)
                    .accessibilityIdentifier("wizard_customer_search")
                SecondaryButton("wizard.customer.new", systemImage: "person.badge.plus") {
                    creatingNew = true
                    viewModel.draft.customer = .new(NewCustomerInput(name: "", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil))
                }
                .padding(.horizontal, DSSpacing.lg)
                .accessibilityIdentifier("wizard_new_customer")
                VStack(spacing: DSSpacing.sm) {
                    ForEach(filtered) { customer in
                        let selected = viewModel.draft.customer == .existing(customer.id)
                        Button { viewModel.draft.customer = .existing(customer.id) } label: {
                            Card {
                                HStack {
                                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                        Text(verbatim: customer.name).font(DSTypography.headline).foregroundStyle(DSColor.textPrimary)
                                        if let phone = customer.phone { Text(verbatim: phone).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                                    }
                                    Spacer()
                                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(DSColor.accent) }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
            }
        }
        .task { await observe() }
        .onAppear { if case .new? = viewModel.draft.customer { creatingNew = true } }
    }

    private var filtered: [Customer] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return customers }
        return customers.filter { $0.name.localizedCaseInsensitiveContains(q) || ($0.phone ?? "").contains(q) }
    }

    private var newInput: Binding<NewCustomerInput> {
        Binding(get: {
            if case .new(let input)? = viewModel.draft.customer { return input }
            return NewCustomerInput(name: "", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil)
        }, set: { viewModel.draft.customer = .new($0) })
    }

    private var newCustomerForm: some View {
        Card {
            VStack(spacing: DSSpacing.md) {
                TextField("wizard.customer.name", text: newInput.name).textContentType(.name).frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("wizard_customer_name")
                Divider()
                TextField("wizard.customer.phone", text: optional(newInput.phone)).keyboardType(.phonePad).textContentType(.telephoneNumber).frame(minHeight: DSSpacing.minTouch)
                Divider()
                TextField("wizard.customer.email", text: optional(newInput.email)).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).frame(minHeight: DSSpacing.minTouch)
                Divider()
                FormRow("wizard.customer.preferredContact") {
                    Picker("wizard.customer.preferredContact", selection: newInput.preferredContact) {
                        Text("wizard.customer.contact.none").tag(ContactMethod?.none)
                        ForEach(ContactMethod.allCases, id: \.self) { Text(LocalizedStringKey("contact." + $0.rawValue)).tag(ContactMethod?.some($0)) }
                    }.labelsHidden()
                }
                Divider()
                TextField("wizard.customer.company", text: optional(newInput.companyName)).frame(minHeight: DSSpacing.minTouch)
                SecondaryButton("wizard.customer.pickExisting") { creatingNew = false; viewModel.draft.customer = nil }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func observe() async {
        do { for try await value in customerRepository.observeAll(companyId: viewModel.companyId) { customers = value } } catch {}
    }
}
```

- [ ] **Step 5: `LocationStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct LocationStep: View {
    @Bindable var viewModel: ProjectWizardViewModel

    private var address: Binding<Address> {
        Binding(get: { viewModel.draft.address ?? Address(line: "", unit: nil, city: nil, region: nil, postalCode: nil) },
                set: { viewModel.draft.address = $0 })
    }

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                VStack(spacing: DSSpacing.md) {
                    TextField("wizard.location.line", text: address.line).textContentType(.streetAddressLine1).frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("wizard_address_line")
                    Divider()
                    TextField("wizard.location.unit", text: optional(address.unit)).textContentType(.streetAddressLine2).frame(minHeight: DSSpacing.minTouch)
                    Divider()
                    TextField("wizard.location.city", text: optional(address.city)).textContentType(.addressCity).frame(minHeight: DSSpacing.minTouch)
                    Divider()
                    HStack(spacing: DSSpacing.md) {
                        TextField("wizard.location.region", text: optional(address.region)).textContentType(.addressState).frame(minHeight: DSSpacing.minTouch)
                        TextField("wizard.location.postalCode", text: optional(address.postalCode)).textContentType(.postalCode).textInputAutocapitalization(.characters).frame(minHeight: DSSpacing.minTouch)
                    }
                }
            }
            SecondaryButton("wizard.location.openMaps", systemImage: "map") { openMaps() }
                .disabled(!viewModel.canContinue).opacity(viewModel.canContinue ? 1 : 0.5)
                .accessibilityIdentifier("wizard_open_maps")
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func openMaps() {
        let a = address.wrappedValue
        let query = [a.line, a.unit, a.city, a.region, a.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: "maps://?q=" + encoded) else { return }
        UIApplication.shared.open(url)
    }
}
```

- [ ] **Step 6: Key mới**

`wizard.continue` Continue/Tiếp tục · `wizard.create` Create project/Tạo dự án · `wizard.skip` Skip/Bỏ qua · `wizard.back` Back/Quay lại · `wizard.done` Done/Xong · `wizard.close.title` Leave the wizard?/Rời wizard? · `wizard.close.saveDraft` Save draft/Lưu nháp · `wizard.close.discard` Discard draft/Bỏ nháp · `wizard.close.cancel` Cancel/Hủy · `wizard.jobType.customPlaceholder` Describe the job type/Mô tả loại job · `wizard.customer.search` Search customers/Tìm khách hàng · `wizard.customer.new` New customer/Khách mới · `wizard.customer.name` Customer name/Tên khách · `wizard.customer.phone` Phone/Điện thoại · `wizard.customer.email` Email/Email · `wizard.customer.preferredContact` Preferred contact/Liên hệ ưu tiên · `wizard.customer.contact.none` Not set/Chưa chọn · `contact.phone` Call/Gọi · `contact.text` Text/Nhắn tin · `contact.email` Email/Email · `wizard.customer.company` Company (optional)/Công ty (tùy chọn) · `wizard.customer.pickExisting` Pick an existing customer/Chọn khách có sẵn · `wizard.location.line` Street address/Địa chỉ · `wizard.location.unit` Unit/Căn hộ · `wizard.location.city` City/Thành phố · `wizard.location.region` Province / State/Tỉnh / Bang · `wizard.location.postalCode` Postal code/Mã bưu chính · `wizard.location.openMaps` Open in Maps/Mở Maps.

- [ ] **Step 7: Script check, commit**

```bash
git add Packages/Features App/Resources
git commit -m "feat(projects): add wizard shell with job type, customer and location steps"
```

---

### Task 14: Bước 4–5 (Scope, Timeline) + dialog đổi job type

**Files:**
- Create (thay placeholder): `Packages/Features/Sources/ProjectsFeature/Wizard/Steps/ScopeStep.swift`, `TimelineStep.swift`
- Modify: `ProjectWizardViewModel.swift` (`confirmJobTypeChange(keepFields:)`), `ProjectWizardView.swift` (dialog)

**Interfaces:**
- Produces: `ScopeStep`, `TimelineStep` (dùng lại ở edit sheet Task 19 — nhận `@Bindable var viewModel: ProjectWizardViewModel`); `ProjectWizardViewModel.confirmJobTypeChange(keepFields: Bool)`.
- Identifiers: `wizard_scope_description`, `wizard_scope_field_<key>`, `wizard_scope_add`, `wizard_start_date`, `wizard_end_date`.

- [ ] **Step 1: ViewModel — đổi job type**

```swift
    public var pendingJobTypeChange: JobType?

    /// Review Focus #3: keep foreign fields as custom:<label> or drop them.
    public func confirmJobTypeChange(keepFields: Bool, labelFor: (String) -> String) {
        guard let newType = pendingJobTypeChange else { return }
        let allowed = Set(ScopeFieldCatalog.fields(for: newType).map(\.key))
        if keepFields {
            draft.scopeFields = draft.scopeFields.map { field in
                guard !allowed.contains(field.key), !ScopeFieldCatalog.isCustom(field.key) else { return field }
                var copy = field; copy.key = ScopeFieldCatalog.customPrefix + labelFor(field.key); return copy
            }
        } else {
            draft.scopeFields.removeAll { !allowed.contains($0.key) && !ScopeFieldCatalog.isCustom($0.key) }
        }
        draft.jobType = newType
        if newType != .other { draft.customJobType = nil }
        pendingJobTypeChange = nil
    }
```

`ProjectWizardView` thêm:

```swift
            .confirmationDialog("wizard.jobType.change.title", isPresented: Binding(get: { viewModel.pendingJobTypeChange != nil }, set: { if !$0 { viewModel.pendingJobTypeChange = nil } }), titleVisibility: .visible) {
                Button("wizard.jobType.change.keep") { viewModel.confirmJobTypeChange(keepFields: true, labelFor: { String(localized: String.LocalizationValue("scope.field." + $0)) }) }
                Button("wizard.jobType.change.clear", role: .destructive) { viewModel.confirmJobTypeChange(keepFields: false, labelFor: { $0 }) }
                Button("wizard.close.cancel", role: .cancel) { viewModel.pendingJobTypeChange = nil }
            }
```

(`String(localized:)` dùng locale hệ thống, không phải `resolvedLocale` — chấp nhận cho nhãn custom; ghi deferred.)

- [ ] **Step 2: `ScopeStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct ScopeStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    @Environment(\.locale) private var locale
    @State private var newFieldLabel = ""

    private var definitions: [ScopeFieldDefinition] { viewModel.draft.jobType.map(ScopeFieldCatalog.fields(for:)) ?? ScopeFieldCatalog.common }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Card {
                TextField("wizard.scope.description", text: Binding(get: { viewModel.draft.scopeDescription ?? "" }, set: { viewModel.draft.scopeDescription = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("wizard_scope_description")
            }
            Card {
                VStack(spacing: DSSpacing.md) {
                    ForEach(definitions, id: \.key) { def in
                        fieldRow(def)
                        if def.key != definitions.last?.key { Divider() }
                    }
                }
            }
            if !customFields.isEmpty {
                Card {
                    VStack(spacing: DSSpacing.md) {
                        ForEach(customFields) { field in
                            FormRow(verbatimLabel: ScopeFieldCatalog.customLabel(field.key)) {
                                HStack(spacing: DSSpacing.sm) {
                                    TextField("wizard.scope.value", text: binding(for: field.key)).multilineTextAlignment(.trailing)
                                    Button { remove(field.key) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DSColor.textSecondary) }
                                        .accessibilityLabel(Text("wizard.scope.remove"))
                                }
                            }
                        }
                    }
                }
            }
            Card {
                HStack {
                    TextField("wizard.scope.newField", text: $newFieldLabel).frame(minHeight: DSSpacing.minTouch)
                    Button { addCustom() } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .disabled(newFieldLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("wizard_scope_add")
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private var customFields: [DraftScopeField] { viewModel.draft.scopeFields.filter { ScopeFieldCatalog.isCustom($0.key) } }

    @ViewBuilder private func fieldRow(_ def: ScopeFieldDefinition) -> some View {
        let label = ScopeFieldCatalog.labelKey(forFieldKey: def.key) ?? "wizard.scope.value"
        switch def.kind {
        case .integer:
            FormRow(label) { IntegerField("wizard.scope.value", value: intBinding(def.key)) }.accessibilityIdentifier("wizard_scope_field_" + def.key)
        case .decimal:
            FormRow(label) {
                HStack(spacing: DSSpacing.xs) {
                    DecimalField("wizard.scope.value", value: decimalBinding(def.key))
                    if let unit = def.unitKey { Text(ScopeFieldCatalog.unitLabelKey(unit)).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                }
            }.accessibilityIdentifier("wizard_scope_field_" + def.key)
        case .text:
            FormRow(label) { TextField("wizard.scope.value", text: binding(for: def.key)).multilineTextAlignment(.trailing) }
        case .toggle:
            Toggle(isOn: Binding(get: { value(def.key) == "true" }, set: { set(def.key, $0 ? "true" : "false") })) { Text(label) }
                .frame(minHeight: DSSpacing.minTouch).tint(DSColor.accent)
        case .choice(let options):
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(label).font(DSTypography.body)
                ChoiceChips(options: options, selection: Binding(get: { value(def.key).isEmpty ? nil : value(def.key) }, set: { set(def.key, $0 ?? "") }), label: ScopeFieldCatalog.optionLabelKey)
                    .padding(.horizontal, -DSSpacing.lg)
            }
        }
    }

    // MARK: value plumbing (canonical storage)

    private func value(_ key: String) -> String { viewModel.draft.scopeFields.first { $0.key == key }?.value ?? "" }

    private func set(_ key: String, _ newValue: String) {
        if let index = viewModel.draft.scopeFields.firstIndex(where: { $0.key == key }) {
            if newValue.isEmpty { viewModel.draft.scopeFields.remove(at: index) } else { viewModel.draft.scopeFields[index].value = newValue }
        } else if !newValue.isEmpty {
            viewModel.draft.scopeFields.append(DraftScopeField(id: UUID(), key: key, value: newValue, sortOrder: viewModel.draft.scopeFields.count))
        }
    }

    private func binding(for key: String) -> Binding<String> { Binding(get: { value(key) }, set: { set(key, $0) }) }

    private func intBinding(_ key: String) -> Binding<Int?> {
        Binding(get: { Int(value(key)) }, set: { set(key, $0.map(String.init) ?? "") })
    }

    private func decimalBinding(_ key: String) -> Binding<Decimal?> {
        Binding(get: { Decimal(string: value(key), locale: Locale(identifier: "en_US_POSIX")) },
                set: { set(key, $0.map { "\($0)" } ?? "") })
    }

    private func addCustom() {
        let label = newFieldLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        set(ScopeFieldCatalog.customPrefix + label, " ")   // placeholder so the row appears; user types the value
        newFieldLabel = ""
    }

    private func remove(_ key: String) { viewModel.draft.scopeFields.removeAll { $0.key == key } }
}
```

Thêm vào DesignSystem `FormRow` một init verbatim: `public init(verbatimLabel: String, @ViewBuilder content: () -> Content)` lưu `Text(verbatim:)` thay `LocalizedStringKey` (sửa `FormRow` giữ `private let label: Text`).

Lưu ý `addCustom` đặt value `" "` để dòng hiện ra; assembler/DraftDiff bỏ dòng value blank nên không lưu rác.

- [ ] **Step 3: `TimelineStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct TimelineStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                VStack(spacing: DSSpacing.md) {
                    dateRow("wizard.timeline.start", date: $viewModel.draft.startDate, id: "wizard_start_date")
                    Divider()
                    dateRow("wizard.timeline.end", date: $viewModel.draft.estimatedCompletionDate, id: "wizard_end_date")
                    if !viewModel.canContinue {
                        Text("wizard.error.completionBeforeStart").font(DSTypography.caption).foregroundStyle(DSColor.danger)
                    }
                }
            }
            Card {
                VStack(spacing: DSSpacing.md) {
                    FormRow("wizard.timeline.workingDays") { IntegerField("wizard.timeline.workingDays", value: $viewModel.draft.workingDays) }
                    Divider()
                    FormRow("wizard.timeline.hoursPerDay") { DecimalField("wizard.timeline.hoursPerDay", value: $viewModel.draft.hoursPerDay, fractionDigits: 1) }
                    Divider()
                    FormRow("wizard.timeline.workersPerDay") { IntegerField("wizard.timeline.workersPerDay", value: $viewModel.draft.workersPerDay) }
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func dateRow(_ title: LocalizedStringKey, date: Binding<CalendarDate?>, id: String) -> some View {
        HStack {
            Toggle(isOn: Binding(get: { date.wrappedValue != nil }, set: { on in date.wrappedValue = on ? CalendarDate(Date(), timeZone: timeZone) : nil })) { Text(title) }
                .tint(DSColor.accent)
            if let current = date.wrappedValue {
                DatePicker("", selection: Binding(get: { Self.date(from: current, timeZone) }, set: { date.wrappedValue = CalendarDate($0, timeZone: timeZone) }), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact)
                    .accessibilityIdentifier(id)
            }
        }
        .frame(minHeight: DSSpacing.minTouch)
    }

    private static func date(from day: CalendarDate, _ tz: TimeZone) -> Date {
        var c = DateComponents(); c.year = day.year; c.month = day.month; c.day = day.day; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        return cal.date(from: c) ?? Date()
    }
}
```

- [ ] **Step 4: Key mới**

`wizard.jobType.change.title` Keep the fields you filled in?/Giữ các trường đã điền? · `wizard.jobType.change.keep` Keep as custom fields/Giữ làm trường tự do · `wizard.jobType.change.clear` Remove them/Xóa · `wizard.scope.description` Describe the work/Mô tả công việc · `wizard.scope.value` Value/Giá trị · `wizard.scope.newField` Add a custom field/Thêm trường tự do · `wizard.scope.remove` Remove/Xóa · `wizard.timeline.start` Start date/Ngày bắt đầu · `wizard.timeline.end` Estimated completion/Dự kiến hoàn thành · `wizard.timeline.workingDays` Working days/Số ngày làm · `wizard.timeline.hoursPerDay` Hours per day/Giờ mỗi ngày · `wizard.timeline.workersPerDay` Workers per day/Thợ mỗi ngày.

- [ ] **Step 5: Script check, commit**

```bash
git add Packages/Features Packages/DesignSystem App/Resources
git commit -m "feat(projects): add scope and timeline wizard steps"
```

---

### Task 15: Bước 6–8 (Labour, Material, Other costs)

**Files:**
- Create (thay placeholder): `Steps/LabourStep.swift`, `Steps/MaterialStep.swift`, `Steps/OtherCostsStep.swift`, `Steps/EstimateLineList.swift` (dùng chung)

**Interfaces:**
- Produces: `EstimateLineList(lines: Binding<[DraftEstimateLine]>, group: CostGroup, currency: CurrencyCode, showsRate: Bool, suggestions: [String], kindPicker: Bool)` — danh sách dòng có label, (rate × qty) hoặc amount, nút thêm/xóa, tổng; `LabourStep`, `MaterialStep`, `OtherCostsStep`.
- Identifiers: `wizard_labour_mode`, `wizard_labour_workers`, `wizard_labour_rate`, `wizard_labour_days`, `wizard_line_add`, `wizard_line_label_<index>`, `wizard_line_amount_<index>`, `wizard_estimate_total`.

- [ ] **Step 1: `EstimateLineList.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct EstimateLineList: View {
    @Binding var lines: [DraftEstimateLine]
    let group: CostGroup
    let currency: CurrencyCode
    let showsRate: Bool            // labour detailed: rate/day × days
    let suggestions: [String]      // material chips
    let kindPicker: Bool           // other costs: OtherCostKind menu

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            if !suggestions.isEmpty {
                ChoiceChips(options: suggestions, selection: .constant(nil)) { _ in "wizard.estimate.suggestion" }
                    .hidden().frame(height: 0)   // keeps layout stable; real chips below
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(suggestions, id: \.self) { label in
                            Button { add(label: label) } label: {
                                Text(verbatim: label).font(DSTypography.callout).padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.sm)
                                    .frame(minHeight: DSSpacing.minTouch)
                                    .background(DSColor.surface, in: Capsule()).overlay(Capsule().strokeBorder(DSColor.border))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, DSSpacing.lg)
                }
            }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, _ in
                Card { row(index) }.padding(.horizontal, DSSpacing.lg)
            }
            SecondaryButton("wizard.estimate.addLine", systemImage: "plus") { add(label: "") }
                .padding(.horizontal, DSSpacing.lg).accessibilityIdentifier("wizard_line_add")
            HStack {
                Text("wizard.estimate.total").font(DSTypography.headline)
                Spacer()
                MoneyText(amount: total.amount, currencyCode: currency.rawValue, style: .headline).accessibilityIdentifier("wizard_estimate_total")
            }.padding(.horizontal, DSSpacing.lg)
        }
    }

    private var total: Money { (try? Money.sum(lines.map(\.amount), currency: currency)) ?? .zero(currency) }

    @ViewBuilder private func row(_ index: Int) -> some View {
        VStack(spacing: DSSpacing.sm) {
            HStack {
                if kindPicker {
                    Picker("wizard.estimate.kind", selection: Binding(get: { lines[index].otherKind ?? .other }, set: { lines[index].otherKind = $0; lines[index].costGroup = $0.costGroup })) {
                        ForEach(OtherCostKind.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                    }.labelsHidden()
                } else {
                    TextField(showsRate ? "wizard.estimate.worker" : "wizard.estimate.label", text: $lines[index].label).frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("wizard_line_label_\(index)")
                }
                Spacer()
                Button(role: .destructive) { lines.remove(at: index) } label: { Image(systemName: "trash") }.accessibilityLabel(Text("wizard.scope.remove"))
            }
            if showsRate {
                HStack(spacing: DSSpacing.md) {
                    FormRow("wizard.estimate.rate") { MoneyField("wizard.estimate.rate", amount: rateBinding(index), currencyCode: currency.rawValue) }
                    FormRow("wizard.estimate.days") { DecimalField("wizard.estimate.days", value: $lines[index].quantity, fractionDigits: 1) }
                }
                FormRow("wizard.estimate.amount") { MoneyText(amount: lines[index].amount.amount, currencyCode: currency.rawValue) }
            } else {
                FormRow("wizard.estimate.amount") { MoneyField("wizard.estimate.amount", amount: amountBinding(index), currencyCode: currency.rawValue).accessibilityIdentifier("wizard_line_amount_\(index)") }
            }
        }
        .onChange(of: lines[index].quantity) { _, _ in recompute(index) }
    }

    private func rateBinding(_ index: Int) -> Binding<Decimal?> {
        Binding(get: { lines[index].unitRate?.amount }, set: { lines[index].unitRate = $0.map { Money($0, currency) }; recompute(index) })
    }
    private func amountBinding(_ index: Int) -> Binding<Decimal?> {
        Binding(get: { lines[index].amount.isZero ? nil : lines[index].amount.amount }, set: { lines[index].amount = Money($0 ?? 0, currency) })
    }
    private func recompute(_ index: Int) {
        guard lines.indices.contains(index), let rate = lines[index].unitRate, let qty = lines[index].quantity else { return }
        lines[index].amount = rate.multiplied(by: qty)
    }
    private func add(label: String) {
        lines.append(DraftEstimateLine(id: UUID(), label: label, amount: .zero(currency), quantity: showsRate ? 1 : nil, unitRate: nil, costGroup: kindPicker ? OtherCostKind.other.costGroup : group, otherKind: kindPicker ? .other : nil, sortOrder: lines.count))
    }
}
```

Bỏ khối `ChoiceChips(...).hidden()` (dòng thừa) — chỉ giữ `ScrollView` chip verbatim.

- [ ] **Step 2: `LabourStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct LabourStep: View {
    @Bindable var viewModel: ProjectWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Picker("wizard.labour.mode", selection: $viewModel.draft.labourMode) {
                Text("wizard.labour.quick").tag(LabourEntryMode.quick)
                Text("wizard.labour.detailed").tag(LabourEntryMode.detailed)
            }
            .pickerStyle(.segmented).padding(.horizontal, DSSpacing.lg).accessibilityIdentifier("wizard_labour_mode")

            switch viewModel.draft.labourMode {
            case .quick:
                Card {
                    VStack(spacing: DSSpacing.md) {
                        FormRow("wizard.labour.workers") { IntegerField("wizard.labour.workers", value: quick.workers).accessibilityIdentifier("wizard_labour_workers") }
                        Divider()
                        FormRow("wizard.labour.rate") { MoneyField("wizard.labour.rate", amount: Binding(get: { quick.wrappedValue.dailyRate?.amount }, set: { quick.wrappedValue.dailyRate = $0.map { Money($0, viewModel.currency) } }), currencyCode: viewModel.currency.rawValue).accessibilityIdentifier("wizard_labour_rate") }
                        Divider()
                        FormRow("wizard.labour.days") { DecimalField("wizard.labour.days", value: quick.days, fractionDigits: 1).accessibilityIdentifier("wizard_labour_days") }
                        Divider()
                        FormRow("wizard.estimate.total") { MoneyText(amount: viewModel.preview.estimateByGroup[.labour]?.amount ?? 0, currencyCode: viewModel.currency.rawValue, style: .headline) }
                    }
                }.padding(.horizontal, DSSpacing.lg)
            case .detailed:
                EstimateLineList(lines: $viewModel.draft.labourLines, group: .labour, currency: viewModel.currency, showsRate: true, suggestions: [], kindPicker: false)
            }
        }
    }

    private var quick: Binding<LabourQuickInput> {
        Binding(get: { viewModel.draft.labourQuick ?? LabourQuickInput(workers: nil, dailyRate: nil, days: nil) }, set: { viewModel.draft.labourQuick = $0 })
    }
}
```

- [ ] **Step 3: `MaterialStep.swift`, `OtherCostsStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct MaterialStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    var body: some View {
        EstimateLineList(lines: $viewModel.draft.materialLines, group: .material, currency: viewModel.currency, showsRate: false,
                         suggestions: MaterialSuggestions.labels(for: viewModel.draft.jobType), kindPicker: false)
    }
}
```

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct OtherCostsStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    var body: some View {
        EstimateLineList(lines: $viewModel.draft.otherLines, group: .other, currency: viewModel.currency, showsRate: false, suggestions: [], kindPicker: true)
    }
}
```

- [ ] **Step 4: Key mới**

`wizard.labour.mode` Entry mode/Cách nhập · `wizard.labour.quick` Quick/Nhanh · `wizard.labour.detailed` Detailed/Chi tiết · `wizard.labour.workers` Workers/Số thợ · `wizard.labour.rate` Daily rate/Rate mỗi ngày · `wizard.labour.days` Days/Số ngày · `wizard.estimate.addLine` Add line/Thêm dòng · `wizard.estimate.total` Total/Tổng · `wizard.estimate.label` Item/Hạng mục · `wizard.estimate.worker` Worker/Thợ · `wizard.estimate.rate` Rate/day/Rate/ngày · `wizard.estimate.days` Days/Ngày · `wizard.estimate.amount` Amount/Số tiền · `wizard.estimate.kind` Type/Loại · `wizard.estimate.suggestion` Suggestion/Gợi ý.

- [ ] **Step 5: Script check, commit**

```bash
git add Packages/Features App/Resources
git commit -m "feat(projects): add labour, material and other-cost estimate steps"
```

---

### Task 16: Bước 9–11 (Price, Deposit, Schedule)

**Files:**
- Create (thay placeholder): `Steps/PriceStep.swift`, `Steps/DepositStep.swift`, `Steps/ScheduleStep.swift`

**Interfaces:**
- Produces: ba step view; identifiers `wizard_contract_value`, `wizard_deposit_toggle`, `wizard_deposit_mode`, `wizard_deposit_value`, `wizard_deposit_deadline`, `wizard_template_<raw>`, `wizard_schedule_row_<index>_pct`, `wizard_schedule_row_<index>_amount`, `wizard_schedule_add`, `wizard_schedule_total`.

- [ ] **Step 1: `PriceStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct PriceStep: View {
    @Bindable var viewModel: ProjectWizardViewModel

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("wizard.price.contract").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    MoneyField("wizard.price.contract", amount: Binding(get: { viewModel.draft.contractValue?.amount }, set: { viewModel.draft.contractValue = $0.map { Money($0, viewModel.currency) } }), currencyCode: viewModel.currency.rawValue)
                        .accessibilityIdentifier("wizard_contract_value")
                }
            }
            let p = viewModel.preview
            HStack(spacing: DSSpacing.md) {
                SummaryTile("wizard.price.estimatedCost", value: Text(p.estimatedCost.amount, format: .currency(code: viewModel.currency.rawValue)))
                SummaryTile("wizard.price.profit", value: Text(p.projectedProfit?.amount ?? 0, format: .currency(code: viewModel.currency.rawValue)),
                            tone: (p.projectedProfit?.isNegative ?? false) ? .danger : .success)
            }
            Card {
                FormRow("wizard.price.margin") {
                    if let margin = p.projectedMargin { Text(verbatim: "\(margin.points)%").font(DSTypography.money(.headline)) } else { Text(verbatim: "—") }
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }
}
```

- [ ] **Step 2: `DepositStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct DepositStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    @Environment(\.timeZone) private var timeZone
    @State private var usesPercentage = true

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                Toggle(isOn: Binding(get: { viewModel.draft.deposit != nil }, set: { on in
                    viewModel.draft.deposit = on ? DraftDeposit(mode: .percentage((try? Percentage.input(20)) ?? Percentage.computed(20)), deadline: nil, requiredToStart: true) : nil
                })) { Text("wizard.deposit.required") }.tint(DSColor.accent).frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("wizard_deposit_toggle")
            }
            if let deposit = viewModel.draft.deposit {
                Card {
                    VStack(spacing: DSSpacing.md) {
                        Picker("wizard.deposit.mode", selection: $usesPercentage) {
                            Text("wizard.deposit.percentage").tag(true)
                            Text("wizard.deposit.fixed").tag(false)
                        }.pickerStyle(.segmented).accessibilityIdentifier("wizard_deposit_mode")
                        .onChange(of: usesPercentage) { _, pct in switchMode(toPercentage: pct) }
                        if usesPercentage {
                            FormRow("wizard.deposit.percentage") {
                                DecimalField("wizard.deposit.percentage", value: Binding(get: { percentagePoints }, set: { setPercentage($0) }), fractionDigits: 2).accessibilityIdentifier("wizard_deposit_value")
                            }
                        } else {
                            FormRow("wizard.deposit.fixed") {
                                MoneyField("wizard.deposit.fixed", amount: Binding(get: { fixedAmount }, set: { setFixed($0) }), currencyCode: viewModel.currency.rawValue).accessibilityIdentifier("wizard_deposit_value")
                            }
                        }
                        Divider()
                        FormRow("wizard.deposit.amount") {
                            MoneyText(amount: viewModel.preview.depositAmount?.amount ?? 0, currencyCode: viewModel.currency.rawValue, style: .headline)
                        }
                        Divider()
                        HStack {
                            Toggle(isOn: Binding(get: { deposit.deadline != nil }, set: { on in viewModel.draft.deposit?.deadline = on ? CalendarDate(Date(), timeZone: timeZone) : nil })) { Text("wizard.deposit.deadline") }.tint(DSColor.accent)
                            if let deadline = deposit.deadline {
                                DatePicker("", selection: Binding(get: { Self.date(deadline, timeZone) }, set: { viewModel.draft.deposit?.deadline = CalendarDate($0, timeZone: timeZone) }), displayedComponents: .date)
                                    .labelsHidden().accessibilityIdentifier("wizard_deposit_deadline")
                            }
                        }.frame(minHeight: DSSpacing.minTouch)
                        Divider()
                        Toggle(isOn: Binding(get: { deposit.requiredToStart }, set: { viewModel.draft.deposit?.requiredToStart = $0 })) { Text("wizard.deposit.blocksStart") }.tint(DSColor.accent).frame(minHeight: DSSpacing.minTouch)
                    }
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .onAppear { if case .fixed? = viewModel.draft.deposit?.mode { usesPercentage = false } }
    }

    private var percentagePoints: Decimal? { if case .percentage(let p)? = viewModel.draft.deposit?.mode { return p.points } else { return nil } }
    private var fixedAmount: Decimal? { if case .fixed(let m)? = viewModel.draft.deposit?.mode { return m.amount } else { return nil } }

    private func setPercentage(_ points: Decimal?) {
        guard let points, let pct = try? Percentage.input(points) else { return }
        viewModel.draft.deposit?.mode = .percentage(pct)
    }
    private func setFixed(_ amount: Decimal?) { viewModel.draft.deposit?.mode = .fixed(Money(amount ?? 0, viewModel.currency)) }

    private func switchMode(toPercentage: Bool) {
        guard let contract = viewModel.draft.contractValue, let current = viewModel.preview.depositAmount else { return }
        if toPercentage {
            if let ratio = Percentage.ratio(current, over: contract), let pct = try? Percentage.input(min(max(ratio.points, 0), 100)) { viewModel.draft.deposit?.mode = .percentage(pct) }
        } else {
            viewModel.draft.deposit?.mode = .fixed(current)
        }
    }

    private static func date(_ day: CalendarDate, _ tz: TimeZone) -> Date {
        var c = DateComponents(); c.year = day.year; c.month = day.month; c.day = day.day; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        return cal.date(from: c) ?? Date()
    }
}
```

- [ ] **Step 3: `ScheduleStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct ScheduleStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    ForEach(PaymentScheduleTemplate.allCases, id: \.self) { template in
                        let selected = viewModel.draft.scheduleTemplate == template
                        Button { viewModel.applyTemplate(template) } label: {
                            Text(template.titleKey).font(DSTypography.callout.weight(.medium)).padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.sm)
                                .frame(minHeight: DSSpacing.minTouch)
                                .background(selected ? DSColor.accent : DSColor.surface, in: Capsule())
                                .foregroundStyle(selected ? DSColor.onAccent : DSColor.textPrimary)
                                .overlay(Capsule().strokeBorder(DSColor.border, lineWidth: selected ? 0 : 1))
                        }.buttonStyle(.plain).accessibilityIdentifier("wizard_template_" + template.rawValue)
                    }
                }.padding(.horizontal, DSSpacing.lg)
            }
            ForEach(Array(viewModel.draft.schedule.enumerated()), id: \.element.id) { index, row in
                Card { rowView(index, row) }.padding(.horizontal, DSSpacing.lg)
            }
            SecondaryButton("wizard.schedule.addRow", systemImage: "plus") {
                viewModel.draft.schedule.append(DraftScheduleRow(id: UUID(), label: "", percentage: nil, amount: nil, dueDate: nil, trigger: nil, isDeposit: viewModel.draft.schedule.isEmpty))
                if viewModel.draft.scheduleTemplate == nil { viewModel.draft.scheduleTemplate = .custom }
            }.padding(.horizontal, DSSpacing.lg).accessibilityIdentifier("wizard_schedule_add")
            Card {
                VStack(spacing: DSSpacing.sm) {
                    FormRow("wizard.schedule.total") { MoneyText(amount: viewModel.preview.scheduleTotal.amount, currencyCode: viewModel.currency.rawValue, style: .headline).accessibilityIdentifier("wizard_schedule_total") }
                    if let warning = viewModel.preview.scheduleWarning {
                        switch warning {
                        case .totalMismatch(let diff):
                            HStack(spacing: DSSpacing.xs) {
                                Text("wizard.schedule.mismatch").font(DSTypography.caption)
                                MoneyText(amount: diff.amount, currencyCode: viewModel.currency.rawValue, style: .caption)
                            }.foregroundStyle(DSColor.warning)
                        case .contractZero:
                            Text("wizard.schedule.noContract").font(DSTypography.caption).foregroundStyle(DSColor.warning)
                        }
                    }
                }
            }.padding(.horizontal, DSSpacing.lg)
        }
    }

    @ViewBuilder private func rowView(_ index: Int, _ row: DraftScheduleRow) -> some View {
        VStack(spacing: DSSpacing.sm) {
            HStack {
                if row.label.hasPrefix("schedule.row.") {
                    RowLabel.text(row.label).font(DSTypography.headline)
                } else {
                    TextField("wizard.schedule.label", text: $viewModel.draft.schedule[index].label).font(DSTypography.headline)
                }
                Spacer()
                if row.isDeposit { StatusBadge("schedule.row.deposit", tone: .warning) }
                Button(role: .destructive) { viewModel.draft.schedule.remove(at: index); viewModel.scheduleEdited(.none) } label: { Image(systemName: "trash") }.accessibilityLabel(Text("wizard.scope.remove"))
            }
            HStack(spacing: DSSpacing.md) {
                FormRow("wizard.schedule.percent") {
                    DecimalField("wizard.schedule.percent", value: Binding(get: { row.percentage?.points }, set: { pts in
                        viewModel.draft.schedule[index].percentage = pts.flatMap { try? Percentage.input($0) }
                        viewModel.scheduleEdited(.percentage(index))
                    }), fractionDigits: 2).accessibilityIdentifier("wizard_schedule_row_\(index)_pct")
                }
                FormRow("wizard.estimate.amount") {
                    MoneyField("wizard.estimate.amount", amount: Binding(get: { row.amount?.amount }, set: { amt in
                        viewModel.draft.schedule[index].amount = amt.map { Money($0, viewModel.currency) }
                        viewModel.scheduleEdited(.amount(index))
                    }), currencyCode: viewModel.currency.rawValue).accessibilityIdentifier("wizard_schedule_row_\(index)_amount")
                }
            }
            HStack {
                Toggle(isOn: Binding(get: { row.dueDate != nil }, set: { on in viewModel.draft.schedule[index].dueDate = on ? CalendarDate(Date(), timeZone: timeZone) : nil })) { Text("wizard.schedule.dueDate") }.tint(DSColor.accent)
                if let due = row.dueDate {
                    DatePicker("", selection: Binding(get: { Self.date(due, timeZone) }, set: { viewModel.draft.schedule[index].dueDate = CalendarDate($0, timeZone: timeZone) }), displayedComponents: .date).labelsHidden()
                }
            }.frame(minHeight: DSSpacing.minTouch)
            TextField("wizard.schedule.trigger", text: Binding(get: { row.trigger ?? "" }, set: { viewModel.draft.schedule[index].trigger = $0.isEmpty ? nil : $0 })).frame(minHeight: DSSpacing.minTouch)
        }
    }

    private static func date(_ day: CalendarDate, _ tz: TimeZone) -> Date {
        var c = DateComponents(); c.year = day.year; c.month = day.month; c.day = day.day; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        return cal.date(from: c) ?? Date()
    }
}
```

Chuyển hàm `date(_:_:)` dùng ở 3 step vào `FeatureSupport/CalendarDateBridge.swift` dạng `public extension CalendarDate { func noonDate(in tz: TimeZone) -> Date }` và gọi `due.noonDate(in: timeZone)` thay cho 3 bản copy.

- [ ] **Step 4: Key mới**

`wizard.price.contract` Contract price/Giá hợp đồng · `wizard.price.estimatedCost` Estimated cost/Chi phí dự tính · `wizard.price.profit` Projected profit/Lợi nhuận dự kiến · `wizard.price.margin` Margin/Biên lợi nhuận · `wizard.deposit.required` Deposit required/Có deposit · `wizard.deposit.mode` Deposit type/Kiểu deposit · `wizard.deposit.percentage` Percentage/Phần trăm · `wizard.deposit.fixed` Fixed amount/Số tiền cố định · `wizard.deposit.amount` Deposit amount/Số tiền deposit · `wizard.deposit.deadline` Deadline/Hạn chót · `wizard.deposit.blocksStart` Job cannot begin until deposit is received/Chưa nhận deposit thì chưa bắt đầu · `wizard.schedule.addRow` Add payment/Thêm đợt · `wizard.schedule.total` Schedule total/Tổng lịch · `wizard.schedule.mismatch` Differs from contract by/Lệch hợp đồng · `wizard.schedule.noContract` Enter a contract price to compute amounts/Nhập giá hợp đồng để tính số tiền · `wizard.schedule.label` Payment name/Tên đợt · `wizard.schedule.percent` Percent/Phần trăm · `wizard.schedule.dueDate` Due date/Hạn thanh toán · `wizard.schedule.trigger` Trigger (e.g. after framing)/Mốc (ví dụ sau framing).

- [ ] **Step 5: Script check, commit**

```bash
git add Packages/Features App/Resources
git commit -m "feat(projects): add price, deposit and payment schedule steps"
```

---

### Task 17: Bước 12 Review + tạo project + banner nháp

**Files:**
- Create (thay placeholder): `Steps/ReviewStep.swift`; Create: `List/DraftBanner.swift`

**Interfaces:**
- Produces: `ReviewStep`; `public struct DraftBanner: View { init(draft: ProjectDraft, onContinue: () -> Void, onDiscard: () -> Void) }` hiện "Tiếp tục nháp: <address.line ?? job type> · bước N/12".
- Identifiers: `wizard_review_name`, `wizard_review_fix_<field>`, `draft_banner`, `draft_continue`, `draft_discard`.

- [ ] **Step 1: `ReviewStep.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct ReviewStep: View {
    @Bindable var viewModel: ProjectWizardViewModel

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("wizard.review.projectName").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    TextField("wizard.review.projectName", text: Binding(get: { viewModel.draft.projectName ?? ProjectDraftAssembler.defaultName(for: viewModel.draft) ?? "" },
                                                                        set: { viewModel.draft.projectName = $0.isEmpty ? nil : $0 }))
                        .font(DSTypography.title).accessibilityIdentifier("wizard_review_name")
                }
            }
            section(.jobType, missing: [.jobType, .customJobType]) {
                if let type = viewModel.draft.jobType { Text(type == .other ? LocalizedStringKey(stringLiteral: "") : type.titleKey); if type == .other, let c = viewModel.draft.customJobType { Text(verbatim: c) } }
            }
            section(.customer, missing: [.customer]) {
                switch viewModel.draft.customer {
                case .existing?: Text("wizard.review.existingCustomer")
                case .new(let input)?: Text(verbatim: input.name)
                case nil: EmptyView()
                }
            }
            section(.location, missing: [.addressLine]) {
                if let a = viewModel.draft.address { Text(verbatim: [a.line, a.unit, a.city, a.region, a.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")) }
            }
            section(.scope) {
                if let d = viewModel.draft.scopeDescription { Text(verbatim: d) }
                Text(verbatim: "\(viewModel.draft.scopeFields.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }.count)").font(DSTypography.caption) + Text(" ").font(DSTypography.caption) + Text("wizard.review.fields").font(DSTypography.caption)
            }
            section(.timeline) {
                if let s = viewModel.draft.startDate, let e = viewModel.draft.estimatedCompletionDate { Text(verbatim: "\(s.storageString) → \(e.storageString)") }
            }
            section(.labour) { moneyLine(viewModel.preview.estimateByGroup[.labour]) }
            section(.material) { moneyLine(viewModel.preview.estimateByGroup[.material]) }
            section(.otherCosts) { moneyLine(otherTotal) }
            section(.price, missing: [.contractValue]) {
                if let c = viewModel.draft.contractValue { MoneyText(amount: c.amount, currencyCode: viewModel.currency.rawValue, style: .headline) }
                if let profit = viewModel.preview.projectedProfit {
                    HStack { Text("wizard.price.profit").font(DSTypography.caption); Spacer(); MoneyText(amount: profit.amount, currencyCode: viewModel.currency.rawValue, style: .caption) }
                }
            }
            section(.deposit) { moneyLine(viewModel.preview.depositAmount) }
            section(.schedule) {
                ForEach(viewModel.draft.schedule) { row in
                    HStack { RowLabel.text(row.label).font(DSTypography.callout); Spacer(); if let a = row.amount { MoneyText(amount: a.amount, currencyCode: viewModel.currency.rawValue, style: .callout) } }
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private var otherTotal: Money? {
        let groups: [CostGroup] = [.subcontractor, .equipment, .permit, .other]
        let values = groups.compactMap { viewModel.preview.estimateByGroup[$0] }
        return values.isEmpty ? nil : try? Money.sum(values, currency: viewModel.currency)
    }

    @ViewBuilder private func moneyLine(_ money: Money?) -> some View {
        if let money { MoneyText(amount: money.amount, currencyCode: viewModel.currency.rawValue) } else { Text("wizard.review.notSet").foregroundStyle(DSColor.textSecondary) }
    }

    private func section<Content: View>(_ step: WizardStep, missing: Set<DraftField> = [], @ViewBuilder content: () -> Content) -> some View {
        let isMissing = !viewModel.missing.isDisjoint(with: missing)
        return Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text(step.titleKey).font(DSTypography.headline).foregroundStyle(isMissing ? DSColor.danger : DSColor.textPrimary)
                    Spacer()
                    Button(isMissing ? "wizard.review.fix" : "wizard.review.edit") { viewModel.go(to: step) }
                        .font(DSTypography.callout).accessibilityIdentifier("wizard_review_fix_" + String(describing: step))
                }
                content()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous).strokeBorder(isMissing ? DSColor.danger : .clear, lineWidth: 1))
    }
}
```

Sửa dòng `section(.jobType …)`: viết gọn và đúng kiểu —

```swift
            section(.jobType, missing: [.jobType, .customJobType]) {
                if let type = viewModel.draft.jobType {
                    if type == .other { Text(verbatim: viewModel.draft.customJobType ?? "") } else { Text(type.titleKey) }
                }
            }
```

và dòng đếm field: `Text(verbatim: "\(count)") + Text(verbatim: " ") + Text("wizard.review.fields")` với `let count = ...` bên trên.

- [ ] **Step 2: `DraftBanner.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct DraftBanner: View {
    private let draft: ProjectDraft
    private let onContinue: () -> Void
    private let onDiscard: () -> Void

    public init(draft: ProjectDraft, onContinue: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        self.draft = draft; self.onContinue = onContinue; self.onDiscard = onDiscard
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("draft.title").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                HStack {
                    VStack(alignment: .leading) {
                        if let line = draft.address?.line, !line.isEmpty { Text(verbatim: line).font(DSTypography.headline) }
                        else if let type = draft.jobType { Text(type.titleKey).font(DSTypography.headline) }
                        else { Text("draft.untitled").font(DSTypography.headline) }
                        Text(verbatim: "\(draft.step)/\(WizardStep.total)").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    Button("draft.discard", role: .destructive, action: onDiscard).accessibilityIdentifier("draft_discard")
                    Button("draft.continue", action: onContinue).buttonStyle(.borderedProminent).tint(DSColor.accent).accessibilityIdentifier("draft_continue")
                }
            }
        }
        .accessibilityIdentifier("draft_banner")
    }
}
```

- [ ] **Step 3: Key mới**

`wizard.review.projectName` Project name/Tên dự án · `wizard.review.existingCustomer` Existing customer/Khách có sẵn · `wizard.review.fields` fields/trường · `wizard.review.notSet` Not set/Chưa nhập · `wizard.review.fix` Fix/Sửa · `wizard.review.edit` Edit/Sửa · `draft.title` Continue draft/Tiếp tục nháp · `draft.untitled` New project/Dự án mới · `draft.discard` Discard/Bỏ · `draft.continue` Continue/Tiếp tục.

- [ ] **Step 4: Script check, commit**

```bash
git add Packages/Features App/Resources
git commit -m "feat(projects): add review step and draft banner"
```

---

### Task 18: Projects list + App wiring (wizard mở từ tab Projects)

**Files:**
- Create: `Packages/Features/Sources/ProjectsFeature/List/ProjectsListViewModel.swift`, `ProjectsListView.swift`
- Delete: `Packages/Features/Sources/ProjectsFeature/ProjectsPlaceholderView.swift`
- Modify: `App/AppContainer.swift` (thêm `estimateRepository`, `scheduleRepository`, `draftStore`, `actor`), `App/Screens.swift` (`ProjectsScreen`), `App/RootTabView.swift` (tab Projects), `Packages/Features/Sources/HomeFeature/HomeView.swift` (tap card → detail qua `navigationDestination`)

**Interfaces:**
- Produces:
  - `@Observable @MainActor public final class ProjectsListViewModel { init(projectRepository:draftStore:companyId:); summaries, filter: PhaseFilter, query: String, draft: ProjectDraft?, isLoaded; var visible: [ProjectSummary]; func start() async; func reloadDraft(); func discardDraft() }`
  - `public struct ProjectsListView: View { init(viewModel:, makeWizard: @escaping (ProjectDraft, _ onCreated: @escaping (UUID) -> Void, _ onDismiss: @escaping () -> Void) -> AnyView, makeDetail: @escaping (UUID) -> AnyView) }` — App cung cấp closure tạo wizard/detail để Features không biết Data.
  - `ProjectRoute` enum `Hashable` (`.detail(UUID)`) dùng với `navigationDestination`.
  - Identifiers: `projects_search`, `projects_filter`, `projects_list`, `projects_add`.

- [ ] **Step 1: `ProjectsListViewModel.swift`**

```swift
import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

@Observable
@MainActor
public final class ProjectsListViewModel {
    public private(set) var summaries: [ProjectSummary] = []
    public private(set) var isLoaded = false
    public var filter: PhaseFilter
    public var query = ""
    public private(set) var draft: ProjectDraft?
    public var errorKey: LocalizedStringKey?

    private let projectRepository: any ProjectRepository
    private let draftStore: any DraftStore
    public let companyId: UUID
    private var defaultFilterApplied = false

    public init(projectRepository: any ProjectRepository, draftStore: any DraftStore, companyId: UUID) {
        self.projectRepository = projectRepository; self.draftStore = draftStore; self.companyId = companyId
        self.filter = .all
        reloadDraft()
    }

    public func start() async {
        do {
            for try await value in projectRepository.observeSummaries(companyId: companyId) {
                summaries = value
                if !defaultFilterApplied {
                    defaultFilterApplied = true
                    filter = value.contains { $0.project.status.phase == .inWork } ? .inWork : .all
                }
                isLoaded = true
            }
        } catch is CancellationError {
        } catch { errorKey = "home.error" }
    }

    public var visible: [ProjectSummary] {
        let q = Self.fold(query)
        return summaries.filter { s in
            filter.matches(s.project.status) && (q.isEmpty || [s.project.name, s.project.address.line, s.project.address.city ?? "", s.customerName].contains { Self.fold($0).contains(q) })
        }
    }

    /// Case- and diacritic-insensitive (Vietnamese names).
    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces) }

    public func reloadDraft() { draft = (try? draftStore.load()) ?? nil }
    public func discardDraft() { try? draftStore.clear(); draft = nil }
}
```

- [ ] **Step 2: `ProjectsListView.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public enum ProjectRoute: Hashable { case detail(UUID) }

public struct ProjectsListView: View {
    @Bindable private var viewModel: ProjectsListViewModel
    private let makeWizard: (ProjectDraft, @escaping (UUID) -> Void, @escaping () -> Void) -> AnyView
    private let makeDetail: (UUID) -> AnyView
    @State private var wizardDraft: ProjectDraft?
    @State private var path: [ProjectRoute] = []

    public init(viewModel: ProjectsListViewModel,
                makeWizard: @escaping (ProjectDraft, @escaping (UUID) -> Void, @escaping () -> Void) -> AnyView,
                makeDetail: @escaping (UUID) -> AnyView) {
        self.viewModel = viewModel; self.makeWizard = makeWizard; self.makeDetail = makeDetail
    }

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isLoaded && viewModel.summaries.isEmpty && viewModel.draft == nil {
                    VStack(spacing: DSSpacing.lg) {
                        EmptyState(systemImage: "folder", title: "projects.empty.title", message: "projects.empty.message")
                        PrimaryButton("projects.createFirst", systemImage: "plus") { wizardDraft = ProjectDraft() }.padding(.horizontal, DSSpacing.lg)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DSSpacing.md) {
                            if let draft = viewModel.draft {
                                DraftBanner(draft: draft, onContinue: { wizardDraft = draft }, onDiscard: { viewModel.discardDraft() }).padding(.horizontal, DSSpacing.lg)
                            }
                            Picker("projects.filter", selection: $viewModel.filter) {
                                ForEach(PhaseFilter.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                            }.pickerStyle(.segmented).padding(.horizontal, DSSpacing.lg).accessibilityIdentifier("projects_filter")
                            ForEach(viewModel.visible) { summary in
                                NavigationLink(value: ProjectRoute.detail(summary.project.id)) {
                                    ProjectCardView(summary: summary, progress: ProgressCalculator.percent(tasks: [], manualProgress: summary.project.manualProgress))
                                }.buttonStyle(.plain).padding(.horizontal, DSSpacing.lg)
                            }
                            if viewModel.visible.isEmpty && viewModel.isLoaded {
                                Text("projects.noMatches").font(DSTypography.callout).foregroundStyle(DSColor.textSecondary).padding(.horizontal, DSSpacing.lg)
                            }
                        }.padding(.vertical, DSSpacing.lg)
                    }
                    .accessibilityIdentifier("projects_list")
                }
            }
            .background(DSColor.background)
            .navigationTitle("projects.title")
            .searchable(text: $viewModel.query, prompt: Text("projects.search"))
            .overlay(alignment: .bottomTrailing) {
                FloatingActionButton(accessibilityLabel: "projects.add") { wizardDraft = ProjectDraft() }
                    .padding(DSSpacing.xl).accessibilityIdentifier("projects_add")
            }
            .navigationDestination(for: ProjectRoute.self) { route in
                switch route { case .detail(let id): makeDetail(id) }
            }
        }
        .fullScreenCover(item: $wizardDraft) { draft in
            makeWizard(draft, { id in wizardDraft = nil; viewModel.reloadDraft(); path = [.detail(id)] }, { wizardDraft = nil; viewModel.reloadDraft() })
        }
        .task { await viewModel.start() }
    }
}

extension ProjectDraft: Identifiable { public var id: Int { 0 } }   // one wizard at a time; identity is irrelevant for fullScreenCover(item:)
```

Ghi chú: `fullScreenCover(item:)` cần `Identifiable`; đặt extension này **trong `FeatureSupport`** thay vì ProjectsFeature (một nơi, public).

- [ ] **Step 3: App wiring**

`AppContainer.Ready` thêm:

```swift
        let estimateRepository: any ProjectEstimateRepository
        let scheduleRepository: any PaymentScheduleRepository
        let draftStore: any DraftStore
```

và trong `load()`:

```swift
            let draftDirectory = options.isUITesting
                ? FileManager.default.temporaryDirectory.appendingPathComponent("conma-ui-drafts", isDirectory: true)
                : FileDraftStore.defaultDirectory()
            if options.isUITesting { try? FileManager.default.removeItem(at: draftDirectory) }
            var ready = Ready(database: database, companyRepository: companies,
                              customerRepository: GRDBCustomerRepository(database: database, clock: clock),
                              projectRepository: GRDBProjectRepository(database: database, clock: clock),
                              estimateRepository: GRDBProjectEstimateRepository(database: database, clock: clock),
                              scheduleRepository: GRDBPaymentScheduleRepository(database: database, clock: clock),
                              draftStore: FileDraftStore(directory: draftDirectory),
                              setup: nil)
```

`Screens.swift` thêm:

```swift
import ProjectsFeature

/// Owns the list view model; builds wizard/detail screens with Data-backed repositories.
struct ProjectsScreen: View {
    @State private var viewModel: ProjectsListViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ProjectsListViewModel(projectRepository: ready.projectRepository, draftStore: ready.draftStore, companyId: setup.company.id))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        ProjectsListView(viewModel: viewModel,
                         makeWizard: { draft, onCreated, onDismiss in AnyView(WizardScreen(draft: draft, ready: ready, setup: setup, onCreated: onCreated, onDismiss: onDismiss)) },
                         makeDetail: { id in AnyView(ProjectDetailScreen(projectId: id, ready: ready, setup: setup)) })
    }
}

struct WizardScreen: View {
    @State private var viewModel: ProjectWizardViewModel
    let customerRepository: any CustomerRepository

    init(draft: ProjectDraft, ready: AppContainer.Ready, setup: CompanySetup, onCreated: @escaping (UUID) -> Void, onDismiss: @escaping () -> Void) {
        _viewModel = State(initialValue: ProjectWizardViewModel(draft: draft, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                                 projectRepository: ready.projectRepository, draftStore: ready.draftStore,
                                                                 actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName),
                                                                 onCreated: onCreated, onDismiss: onDismiss))
        self.customerRepository = ready.customerRepository
    }

    var body: some View { ProjectWizardView(viewModel: viewModel, customerRepository: customerRepository) }
}
```

`ProjectDetailScreen` được tạo ở Task 19 — Task 18 tạm thêm `struct ProjectDetailScreen: View { let projectId: UUID; let ready: AppContainer.Ready; let setup: CompanySetup; var body: some View { Text(verbatim: projectId.uuidString) } }` để compile; Task 19 thay.

`RootTabView`: thay `NavigationStack { ProjectsPlaceholderView() }` bằng `ProjectsScreen(ready: ready, setup: setup)` (ProjectsListView đã có `NavigationStack` riêng).

`HomeView`: bọc card trong `NavigationLink(value: ProjectRoute.detail(summary.project.id))` và thêm `.navigationDestination(for: ProjectRoute.self) { route in ... }` — Home không biết Data, nên `HomeView` nhận thêm `makeDetail: (UUID) -> AnyView` qua init; `HomeScreen` truyền `{ AnyView(ProjectDetailScreen(projectId: $0, ready: ready, setup: setup)) }` (cập nhật `HomeScreen.init(ready:setup:)`, `RootTabView` theo).

- [ ] **Step 4: Key mới**

`projects.search` Search name, address or customer/Tìm tên, địa chỉ, khách · `projects.filter` Filter/Lọc · `projects.add` New project/Dự án mới · `projects.createFirst` Create your first project/Tạo dự án đầu tiên · `projects.noMatches` No projects match/Không có dự án phù hợp. Cập nhật `projects.empty.message` thành "Tap + to create a project." / "Bấm + để tạo dự án."

- [ ] **Step 5: Script check, push nhánh để CI build (lần đầu của Features mới), commit**

```bash
git add Packages/Features App App/Resources
git commit -m "feat(projects): add projects list with filters, search, draft banner and wizard entry"
git push origin HEAD
```

Xem `ios.yml`; lỗi compile của Task 11–18 lộ ở đây — sửa trong task này (commit `fix(projects): …`) cho tới khi "Build app" xanh. UI test cũ (Foundation) vẫn phải pass.

---

### Task 19: Project detail + edit sheet

**Files:**
- Create: `Packages/Features/Sources/ProjectsFeature/Detail/ProjectDetailViewModel.swift`, `ProjectDetailView.swift`, `EditSectionSheet.swift`
- Modify: `App/Screens.swift` (`ProjectDetailScreen` thật)

**Interfaces:**
- Produces:
  - `public enum EditSection: Hashable { scope, timeline, estimate(CostGroup), priceDeposit, schedule }`
  - `@Observable @MainActor public final class ProjectDetailViewModel { init(projectId:companyId:currency:projectRepository:estimateRepository:scheduleRepository:draftStore:actor:); snapshot: ProjectDetailSnapshot?; isLoaded; errorKey; editing: EditSection?; func start() async; func makeEditWizard(_:) -> ProjectWizardViewModel?; func save(_ wizard: ProjectWizardViewModel, section: EditSection) async -> Bool }`
  - `public struct ProjectDetailView: View { init(viewModel:, customerRepository:, makeCustomer: @escaping (UUID) -> AnyView) }`
  - Identifiers: `detail_header`, `detail_edit_<section>`, `detail_estimate_total`, `detail_schedule_total`, `sheet_save`, `sheet_cancel`.

- [ ] **Step 1: `ProjectDetailViewModel.swift`**

```swift
import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

public enum EditSection: Hashable, Identifiable {
    case scope, timeline, estimate(CostGroup), priceDeposit, schedule
    public var id: String { String(describing: self) }
    var wizardStep: WizardStep {
        switch self {
        case .scope: return .scope
        case .timeline: return .timeline
        case .estimate(let g): return g == .labour ? .labour : (g == .material ? .material : .otherCosts)
        case .priceDeposit: return .price
        case .schedule: return .schedule
        }
    }
}

/// A DraftStore that never persists: edit sheets must not touch the wizard draft file.
struct NullDraftStore: DraftStore {
    func load() throws -> ProjectDraft? { nil }
    func save(_ draft: ProjectDraft) throws {}
    func clear() throws {}
}

@Observable
@MainActor
public final class ProjectDetailViewModel {
    public private(set) var snapshot: ProjectDetailSnapshot?
    public private(set) var isLoaded = false
    public var errorKey: LocalizedStringKey?
    public var editing: EditSection?

    public let projectId: UUID
    public let companyId: UUID
    public let currency: CurrencyCode
    private let projectRepository: any ProjectRepository
    private let estimateRepository: any ProjectEstimateRepository
    private let scheduleRepository: any PaymentScheduleRepository
    private let actor: ActivityActor

    public init(projectId: UUID, companyId: UUID, currency: CurrencyCode, projectRepository: any ProjectRepository, estimateRepository: any ProjectEstimateRepository,
                scheduleRepository: any PaymentScheduleRepository, actor: ActivityActor) {
        self.projectId = projectId; self.companyId = companyId; self.currency = currency
        self.projectRepository = projectRepository; self.estimateRepository = estimateRepository; self.scheduleRepository = scheduleRepository; self.actor = actor
    }

    public func start() async {
        do {
            for try await value in projectRepository.observeDetail(id: projectId) { snapshot = value; isLoaded = true }
        } catch is CancellationError {
        } catch { errorKey = "detail.error" }
    }

    /// Wizard VM seeded from the current snapshot, parked on the section's step, with no autosave.
    /// The view sets `editing` after it has stored the returned VM, so the sheet never opens empty.
    public func makeEditWizard(_ section: EditSection) -> ProjectWizardViewModel? {
        guard let s = snapshot else { return nil }
        let draft = ProjectDraft(project: s.project, estimateLines: s.estimateLines, scheduleItems: s.scheduleItems, step: section.wizardStep.rawValue)
        return ProjectWizardViewModel(draft: draft, companyId: companyId, currency: currency, projectRepository: projectRepository, draftStore: NullDraftStore(),
                                      actor: actor, onCreated: { _ in }, onDismiss: {})
    }

    /// Persists only the edited section. Returns false (and sets errorKey) on failure.
    public func save(_ wizard: ProjectWizardViewModel, section: EditSection) async -> Bool {
        guard let s = snapshot else { return false }
        let draft = wizard.draft
        let now = Date()
        do {
            switch section {
            case .scope:
                var project = s.project
                project.scopeDescription = draft.scopeDescription
                project.scopeFields = DraftDiff.scopeFields(old: s.project.scopeFields, new: draft.scopeFields, companyId: companyId, projectId: projectId, now: now)
                try await projectRepository.save(project, actor: actor)
            case .timeline:
                var project = s.project
                project.startDate = draft.startDate; project.estimatedCompletionDate = draft.estimatedCompletionDate
                project.workingDays = draft.workingDays; project.hoursPerDay = draft.hoursPerDay; project.workersPerDay = draft.workersPerDay
                try await projectRepository.save(project, actor: actor)
            case .estimate(let group):
                let lines: [DraftEstimateLine]
                switch group {
                case .labour: lines = draft.allEstimateLines(currency: currency).filter { $0.costGroup == .labour }
                case .material: lines = draft.materialLines
                default: lines = draft.otherLines
                }
                if group == .labour || group == .material {
                    let change = try DraftDiff.estimateLines(group: group, old: s.estimateLines, new: lines, companyId: companyId, projectId: projectId, currency: currency, now: now)
                    try await estimateRepository.replace(projectId: projectId, group: group, change: change, actor: actor)
                } else {
                    // "Other costs" span several cost groups: replace each group that appears in old or new.
                    let groups = Set(s.estimateLines.map(\.costGroup)).union(lines.map(\.costGroup)).subtracting([.labour, .material])
                    for g in groups {
                        let change = try DraftDiff.estimateLines(group: g, old: s.estimateLines, new: lines.filter { $0.costGroup == g }, companyId: companyId, projectId: projectId, currency: currency, now: now)
                        try await estimateRepository.replace(projectId: projectId, group: g, change: change, actor: actor)
                    }
                }
            case .priceDeposit:
                var project = s.project
                if let contract = draft.contractValue { project.contractValue = contract }
                project.depositRequiredToStart = draft.deposit?.requiredToStart ?? false
                try await projectRepository.save(project, actor: actor)
                // Deposit row: update/insert/delete the isDeposit item to match the draft deposit.
                var rows = draft.schedule
                if let dep = draft.deposit {
                    let amount: Money
                    switch dep.mode { case .fixed(let m): amount = m; case .percentage(let p): amount = project.contractValue.multiplied(by: p) }
                    if let i = rows.firstIndex(where: \.isDeposit) { rows[i].amount = amount; rows[i].percentage = nil; rows[i].dueDate = dep.deadline }
                    else { rows.insert(DraftScheduleRow(id: UUID(), label: "schedule.row.deposit", percentage: nil, amount: amount, dueDate: dep.deadline, trigger: nil, isDeposit: true), at: 0) }
                } else {
                    rows.removeAll(where: \.isDeposit)
                }
                let change = try DraftDiff.scheduleItems(old: s.scheduleItems, new: rows, contract: project.contractValue, companyId: companyId, projectId: projectId, now: now)
                try await scheduleRepository.replace(projectId: projectId, change: change, actor: actor)
            case .schedule:
                let change = try DraftDiff.scheduleItems(old: s.scheduleItems, new: draft.schedule, contract: s.project.contractValue, companyId: companyId, projectId: projectId, now: now)
                try await scheduleRepository.replace(projectId: projectId, change: change, actor: actor)
            }
            editing = nil
            return true
        } catch {
            errorKey = "detail.saveFailed"
            return false
        }
    }
}
```

Trong `.priceDeposit`, các dòng không phải deposit giữ `percentage` → `ScheduleMath` tính lại amount theo contract mới (đúng kỳ vọng: đổi giá thì các đợt % co giãn). Ghi vào spec note khi review.

- [ ] **Step 2: `EditSectionSheet.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Hosts one wizard step as an edit sheet. The wizard VM is created by the detail VM and owned here.
struct EditSectionSheet: View {
    let section: EditSection
    @State private var wizard: ProjectWizardViewModel
    let onSave: (ProjectWizardViewModel) async -> Bool
    let onCancel: () -> Void
    @State private var saving = false

    init(section: EditSection, wizard: ProjectWizardViewModel, onSave: @escaping (ProjectWizardViewModel) async -> Bool, onCancel: @escaping () -> Void) {
        self.section = section; _wizard = State(initialValue: wizard); self.onSave = onSave; self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView { stepBody.padding(.vertical, DSSpacing.lg) }
                .scrollDismissesKeyboard(.interactively)
                .background(DSColor.background)
                .navigationTitle(section.wizardStep.titleKey)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel", action: onCancel).accessibilityIdentifier("sheet_cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("sheet.save") { Task { saving = true; _ = await onSave(wizard); saving = false } }
                            .disabled(saving || !wizard.canContinue).accessibilityIdentifier("sheet_save")
                    }
                }
        }
    }

    @ViewBuilder private var stepBody: some View {
        switch section {
        case .scope: ScopeStep(viewModel: wizard)
        case .timeline: TimelineStep(viewModel: wizard)
        case .estimate(let g):
            switch g {
            case .labour: LabourStep(viewModel: wizard)
            case .material: MaterialStep(viewModel: wizard)
            default: OtherCostsStep(viewModel: wizard)
            }
        case .priceDeposit:
            VStack(spacing: DSSpacing.lg) { PriceStep(viewModel: wizard); DepositStep(viewModel: wizard) }
        case .schedule: ScheduleStep(viewModel: wizard)
        }
    }
}
```

- [ ] **Step 3: `ProjectDetailView.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct ProjectDetailView: View {
    @Bindable private var viewModel: ProjectDetailViewModel
    private let makeCustomer: (UUID) -> AnyView
    @State private var editWizard: ProjectWizardViewModel?
    @Environment(\.timeZone) private var timeZone

    public init(viewModel: ProjectDetailViewModel, makeCustomer: @escaping (UUID) -> AnyView) { self.viewModel = viewModel; self.makeCustomer = makeCustomer }

    public var body: some View {
        Group {
            if let s = viewModel.snapshot {
                ScrollView { content(s).padding(.vertical, DSSpacing.lg) }
            } else if viewModel.isLoaded {
                EmptyState(systemImage: "trash", title: "detail.deleted.title", message: "detail.deleted.message")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DSColor.background)
        .navigationTitle(Text(verbatim: viewModel.snapshot?.project.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.start() }
        .sheet(item: $viewModel.editing) { section in
            if let wizard = editWizard {
                EditSectionSheet(section: section, wizard: wizard, onSave: { w in await viewModel.save(w, section: section) }, onCancel: { viewModel.editing = nil })
            }
        }
        .alert("detail.saveFailed", isPresented: Binding(get: { viewModel.errorKey != nil }, set: { if !$0 { viewModel.errorKey = nil } })) { Button("sheet.ok") {} }
    }

    private func edit(_ section: EditSection) {
        guard let wizard = viewModel.makeEditWizard(section) else { return }
        editWizard = wizard
        viewModel.editing = section
    }

    @ViewBuilder private func content(_ s: ProjectDetailSnapshot) -> some View {
        let currency = viewModel.currency.rawValue
        let today = CalendarDate(Date(), timeZone: timeZone)
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Card {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(verbatim: s.project.address.line).font(DSTypography.headline)
                            if let city = s.project.address.city { Text(verbatim: city).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                            NavigationLink { makeCustomer(s.customer.id) } label: {
                                Label { Text(verbatim: s.customer.name) } icon: { Image(systemName: "person") }.font(DSTypography.callout)
                            }
                        }
                        Spacer()
                        StatusBadge(s.project.status.titleKey, tone: s.project.status.tone)
                    }
                    ProgressBar(progress: ProgressCalculator.percent(tasks: [], manualProgress: s.project.manualProgress), tone: s.project.status.tone)
                    FormRow("home.contractValue") { MoneyText(amount: s.project.contractValue.amount, currencyCode: currency, style: .headline) }
                    if let start = s.project.startDate, let end = s.project.estimatedCompletionDate {
                        Text(verbatim: "\(start.storageString) → \(end.storageString)").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                }
            }.accessibilityIdentifier("detail_header")

            section("detail.scope", .scope) {
                if let d = s.project.scopeDescription { Text(verbatim: d) }
                ForEach(s.project.scopeFields) { f in
                    HStack {
                        if let key = ScopeFieldCatalog.labelKey(forFieldKey: f.fieldKey) { Text(key) } else { Text(verbatim: ScopeFieldCatalog.customLabel(f.fieldKey)) }
                        Spacer(); Text(verbatim: f.valueText).foregroundStyle(DSColor.textSecondary)
                    }.font(DSTypography.callout)
                }
                if s.project.scopeDescription == nil && s.project.scopeFields.isEmpty { Text("detail.empty").foregroundStyle(DSColor.textSecondary) }
            }
            section("detail.timeline", .timeline) {
                if let start = s.project.startDate { FormRow("wizard.timeline.start") { Text(verbatim: start.storageString) } }
                if let end = s.project.estimatedCompletionDate { FormRow("wizard.timeline.end") { Text(verbatim: end.storageString) } }
                if let d = s.project.workingDays { FormRow("wizard.timeline.workingDays") { Text(verbatim: "\(d)") } }
                if s.project.startDate == nil && s.project.estimatedCompletionDate == nil { Text("detail.empty").foregroundStyle(DSColor.textSecondary) }
            }
            estimateSection(s)
            section("detail.priceDeposit", .priceDeposit) {
                FormRow("wizard.price.contract") { MoneyText(amount: s.project.contractValue.amount, currencyCode: currency) }
                if let dep = s.scheduleItems.first(where: \.isDeposit) {
                    FormRow("schedule.row.deposit") { MoneyText(amount: dep.amount.amount, currencyCode: currency) }
                    if let due = dep.dueDate { FormRow("wizard.deposit.deadline") { Text(verbatim: due.storageString) } }
                } else { Text("detail.noDeposit").foregroundStyle(DSColor.textSecondary) }
                if s.project.depositRequiredToStart { Text("wizard.deposit.blocksStart").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
            }
            section("detail.schedule", .schedule) {
                ForEach(s.scheduleItems) { item in
                    let status = PaymentStatusResolver.status(item: item, paidForItem: .zero(viewModel.currency), today: today)
                    HStack {
                        VStack(alignment: .leading) {
                            RowLabel.text(item.label).font(DSTypography.callout)
                            if let due = item.dueDate { Text(verbatim: due.storageString).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                        }
                        Spacer()
                        StatusBadge(LocalizedStringKey("payment.status." + status.rawValue), tone: Self.tone(status))
                        MoneyText(amount: item.amount.amount, currencyCode: currency)
                    }
                }
                if s.scheduleItems.isEmpty { Text("detail.empty").foregroundStyle(DSColor.textSecondary) }
                FormRow("wizard.schedule.total") {
                    MoneyText(amount: ((try? Money.sum(s.scheduleItems.map(\.amount), currency: viewModel.currency)) ?? .zero(viewModel.currency)).amount, currencyCode: currency, style: .headline)
                        .accessibilityIdentifier("detail_schedule_total")
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    @ViewBuilder private func estimateSection(_ s: ProjectDetailSnapshot) -> some View {
        let currency = viewModel.currency
        let f = (try? FinancialCalculator.compute(FinancialInputs(project: s.project, estimateLines: s.estimateLines, expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(currency))))
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("detail.estimate").font(DSTypography.headline)
                ForEach([CostGroup.labour, .material], id: \.self) { group in
                    HStack {
                        Text(LocalizedStringKey("costGroup." + group.rawValue))
                        Spacer()
                        MoneyText(amount: f?.estimateByGroup[group]?.amount ?? 0, currencyCode: currency.rawValue)
                        Button("wizard.review.edit") { edit(.estimate(group)) }.font(DSTypography.callout).accessibilityIdentifier("detail_edit_estimate_" + group.rawValue)
                    }
                }
                HStack {
                    Text("wizard.step.otherCosts"); Spacer()
                    let other = [CostGroup.subcontractor, .equipment, .permit, .other].compactMap { f?.estimateByGroup[$0] }
                    MoneyText(amount: ((try? Money.sum(other, currency: currency)) ?? .zero(currency)).amount, currencyCode: currency.rawValue)
                    Button("wizard.review.edit") { edit(.estimate(.other)) }.font(DSTypography.callout).accessibilityIdentifier("detail_edit_estimate_other")
                }
                Divider()
                FormRow("wizard.price.estimatedCost") { MoneyText(amount: f?.estimatedCost.amount ?? 0, currencyCode: currency.rawValue, style: .headline).accessibilityIdentifier("detail_estimate_total") }
                FormRow("wizard.price.profit") { MoneyText(amount: f?.projectedProfit.amount ?? 0, currencyCode: currency.rawValue) }
                FormRow("wizard.price.margin") { if let m = f?.projectedMargin { Text(verbatim: "\(m.points)%") } else { Text(verbatim: "—") } }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, _ edit: EditSection, @ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text(title).font(DSTypography.headline); Spacer()
                    Button("wizard.review.edit") { self.edit(edit) }.font(DSTypography.callout).accessibilityIdentifier("detail_edit_" + edit.id)
                }
                content()
            }
        }
    }

    private static func tone(_ status: PaymentStatus) -> DSTone {
        switch status {
        case .paid: return .success
        case .overdue: return .danger
        case .dueToday, .dueSoon, .partiallyPaid: return .warning
        case .upcoming: return .neutral
        }
    }
}
```

- [ ] **Step 4: `ProjectDetailScreen` (App/Screens.swift) và `CustomerProfileScreen` tạm**

```swift
struct ProjectDetailScreen: View {
    @State private var viewModel: ProjectDetailViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(projectId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ProjectDetailViewModel(projectId: projectId, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                                 projectRepository: ready.projectRepository, estimateRepository: ready.estimateRepository,
                                                                 scheduleRepository: ready.scheduleRepository, actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName)))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        ProjectDetailView(viewModel: viewModel, makeCustomer: { id in AnyView(CustomerProfileScreen(customerId: id, ready: ready, setup: setup)) })
    }
}
```

`CustomerProfileScreen` tạm: `Text(verbatim: customerId.uuidString)`; Task 20 thay.

- [ ] **Step 5: Key mới**

`detail.error` Could not load the project./Không tải được dự án. · `detail.saveFailed` Could not save changes./Không lưu được thay đổi. · `detail.deleted.title` Project removed/Dự án đã xóa · `detail.deleted.message` This project is no longer available./Dự án này không còn. · `detail.scope` Scope/Phạm vi · `detail.timeline` Timeline/Thời gian · `detail.estimate` Estimate/Dự toán · `detail.priceDeposit` Price & deposit/Giá & deposit · `detail.schedule` Payment schedule/Lịch thanh toán · `detail.empty` Not set yet/Chưa nhập · `detail.noDeposit` No deposit/Không có deposit · `sheet.save` Save/Lưu · `sheet.cancel` Cancel/Hủy · `sheet.ok` OK/OK · `costGroup.labour` Labour/Labour · `costGroup.material` Materials/Material · `payment.status.upcoming` Upcoming/Sắp tới · `payment.status.dueSoon` Due soon/Sắp đến hạn · `payment.status.dueToday` Due today/Đến hạn hôm nay · `payment.status.overdue` Overdue/Quá hạn · `payment.status.partiallyPaid` Partially paid/Trả một phần · `payment.status.paid` Paid/Đã trả.

Thêm `payment.status.*` và `costGroup.*` vào danh sách generated keys trong `check_localization.py` (6 + 2).

- [ ] **Step 6: Script check, commit, push, CI xanh**

```bash
git add Packages/Features App App/Resources scripts
git commit -m "feat(projects): add project detail with per-section edit sheets"
git push origin HEAD
```

---

### Task 20: Customers (list, form, profile) + link từ More

**Files:**
- Create: `Packages/Features/Sources/CustomersFeature/CustomersListViewModel.swift`, `CustomersListView.swift`, `CustomerFormView.swift`, `CustomerProfileViewModel.swift`, `CustomerProfileView.swift`
- Delete: `Packages/Features/Sources/CustomersFeature/CustomersFeature.swift` (placeholder)
- Modify: `Packages/Features/Sources/MoreFeature/MoreView.swift` (link `more.customers`), `App/Screens.swift` (`CustomersScreen`, `CustomerProfileScreen` thật), `App/RootTabView.swift` (truyền `makeCustomers` vào `MoreView`)

**Interfaces:**
- Produces:
  - `@Observable @MainActor public final class CustomersListViewModel { init(customerRepository:companyId:actor:); customers, query, isLoaded, errorKey; var visible: [Customer]; func start() async; func save(_ customer: Customer) async -> Bool; func delete(_ id: UUID) async -> DeleteOutcome }` với `public enum DeleteOutcome { deleted, hasProjects, failed }`
  - `public struct CustomersListView: View { init(viewModel:, makeProfile: @escaping (UUID) -> AnyView) }`
  - `public struct CustomerFormView: View { init(customer: Customer?, companyId: UUID, onSave: @escaping (Customer) async -> Bool, onCancel: @escaping () -> Void) }` (sheet; `customer == nil` → tạo mới)
  - `@Observable @MainActor public final class CustomerProfileViewModel { init(customerId:customerRepository:); customer: Customer?, projects: [Project]; func load() async }`
  - `public struct CustomerProfileView: View { init(viewModel:, companyId:, onSave: @escaping (Customer) async -> Bool, onDelete: @escaping () async -> DeleteOutcome, makeProject: @escaping (UUID) -> AnyView) }`
  - `MoreView.init(settings:company:showsGallery:makeCustomers: @escaping () -> AnyView)`
  - Identifiers: `customers_list`, `customers_add`, `customer_form_name`, `customer_form_save`, `customer_profile`, `customer_call`, `customer_text`, `customer_email`, `customer_edit`, `customer_delete`, `more_customers`.

- [ ] **Step 1: ViewModels**

```swift
// CustomersListViewModel.swift
import Foundation
import Observation
import SwiftUI
import Domain

public enum DeleteOutcome: Equatable, Sendable { case deleted, hasProjects, failed }

@Observable
@MainActor
public final class CustomersListViewModel {
    public private(set) var customers: [Customer] = []
    public private(set) var isLoaded = false
    public var query = ""
    public var errorKey: LocalizedStringKey?
    public let companyId: UUID
    private let customerRepository: any CustomerRepository
    private let actor: ActivityActor

    public init(customerRepository: any CustomerRepository, companyId: UUID, actor: ActivityActor) {
        self.customerRepository = customerRepository; self.companyId = companyId; self.actor = actor
    }

    public func start() async {
        do { for try await value in customerRepository.observeAll(companyId: companyId) { customers = value; isLoaded = true } }
        catch is CancellationError {} catch { errorKey = "customers.error" }
    }

    public var visible: [Customer] {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return customers }
        return customers.filter { c in [c.name, c.phone ?? "", c.email ?? "", c.companyName ?? ""].contains { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) } }
    }

    public func save(_ customer: Customer) async -> Bool {
        do { try await customerRepository.save(customer); return true } catch { errorKey = "customers.saveFailed"; return false }
    }

    public func delete(_ id: UUID) async -> DeleteOutcome {
        do { try await customerRepository.softDelete(id: id, actor: actor); return .deleted }
        catch DomainError.customerHasProjects { return .hasProjects }
        catch { return .failed }
    }
}
```

```swift
// CustomerProfileViewModel.swift
import Foundation
import Observation
import Domain

@Observable
@MainActor
public final class CustomerProfileViewModel {
    public private(set) var customer: Customer?
    public private(set) var projects: [Project] = []
    public private(set) var isLoaded = false
    private let customerId: UUID
    private let customerRepository: any CustomerRepository

    public init(customerId: UUID, customerRepository: any CustomerRepository) { self.customerId = customerId; self.customerRepository = customerRepository }

    public func load() async {
        customer = try? await customerRepository.get(id: customerId)
        projects = (try? await customerRepository.projects(customerId: customerId)) ?? []
        isLoaded = true
    }
}
```

- [ ] **Step 2: `CustomerFormView.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct CustomerFormView: View {
    private let existing: Customer?
    private let companyId: UUID
    private let onSave: (Customer) async -> Bool
    private let onCancel: () -> Void
    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var preferredContact: ContactMethod?
    @State private var companyName: String
    @State private var secondaryContact: String
    @State private var notes: String
    @State private var saving = false

    public init(customer: Customer?, companyId: UUID, onSave: @escaping (Customer) async -> Bool, onCancel: @escaping () -> Void) {
        existing = customer; self.companyId = companyId; self.onSave = onSave; self.onCancel = onCancel
        _name = State(initialValue: customer?.name ?? ""); _phone = State(initialValue: customer?.phone ?? ""); _email = State(initialValue: customer?.email ?? "")
        _preferredContact = State(initialValue: customer?.preferredContact); _companyName = State(initialValue: customer?.companyName ?? "")
        _secondaryContact = State(initialValue: customer?.secondaryContact ?? ""); _notes = State(initialValue: customer?.notes ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("customers.form.contact") {
                    TextField("wizard.customer.name", text: $name).textContentType(.name).accessibilityIdentifier("customer_form_name")
                    TextField("wizard.customer.phone", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                    TextField("wizard.customer.email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
                    Picker("wizard.customer.preferredContact", selection: $preferredContact) {
                        Text("wizard.customer.contact.none").tag(ContactMethod?.none)
                        ForEach(ContactMethod.allCases, id: \.self) { Text(LocalizedStringKey("contact." + $0.rawValue)).tag(ContactMethod?.some($0)) }
                    }
                }
                Section("customers.form.more") {
                    TextField("wizard.customer.company", text: $companyName)
                    TextField("customers.form.secondaryContact", text: $secondaryContact)
                    TextField("customers.form.notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(existing == nil ? "customers.form.newTitle" : "customers.form.editTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("sheet.save") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("customer_form_save")
                }
            }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let now = Date()
        func nilIfEmpty(_ s: String) -> String? { s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s }
        let customer = Customer(id: existing?.id ?? UUID(), companyId: companyId, name: name.trimmingCharacters(in: .whitespaces), phone: nilIfEmpty(phone), email: nilIfEmpty(email),
                                preferredContact: preferredContact, companyName: nilIfEmpty(companyName), secondaryContact: nilIfEmpty(secondaryContact), notes: nilIfEmpty(notes),
                                createdAt: existing?.createdAt ?? now, updatedAt: now, deletedAt: nil)
        _ = await onSave(customer)
    }
}
```

- [ ] **Step 3: `CustomersListView.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct CustomersListView: View {
    @Bindable private var viewModel: CustomersListViewModel
    private let makeProfile: (UUID) -> AnyView
    @State private var showForm = false

    public init(viewModel: CustomersListViewModel, makeProfile: @escaping (UUID) -> AnyView) { self.viewModel = viewModel; self.makeProfile = makeProfile }

    public var body: some View {
        Group {
            if viewModel.isLoaded && viewModel.customers.isEmpty {
                VStack(spacing: DSSpacing.lg) {
                    EmptyState(systemImage: "person.2", title: "customers.empty.title", message: "customers.empty.message")
                    PrimaryButton("customers.add", systemImage: "person.badge.plus") { showForm = true }.padding(.horizontal, DSSpacing.lg)
                }
            } else {
                List(viewModel.visible) { customer in
                    NavigationLink { makeProfile(customer.id) } label: {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(verbatim: customer.name).font(DSTypography.headline)
                            if let phone = customer.phone { Text(verbatim: phone).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                        }.frame(minHeight: DSSpacing.minTouch)
                    }
                }
                .listStyle(.plain).accessibilityIdentifier("customers_list")
            }
        }
        .navigationTitle("customers.title")
        .searchable(text: $viewModel.query, prompt: Text("customers.search"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showForm = true } label: { Image(systemName: "plus") }.accessibilityIdentifier("customers_add") } }
        .sheet(isPresented: $showForm) {
            CustomerFormView(customer: nil, companyId: viewModel.companyId, onSave: { c in let ok = await viewModel.save(c); if ok { showForm = false }; return ok }, onCancel: { showForm = false })
        }
        .task { await viewModel.start() }
    }
}
```

- [ ] **Step 4: `CustomerProfileView.swift`**

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct CustomerProfileView: View {
    private let viewModel: CustomerProfileViewModel
    private let companyId: UUID
    private let onSave: (Customer) async -> Bool
    private let onDelete: () async -> DeleteOutcome
    private let makeProject: (UUID) -> AnyView
    @State private var editing = false
    @State private var deleteOutcome: DeleteOutcome?
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: CustomerProfileViewModel, companyId: UUID, onSave: @escaping (Customer) async -> Bool, onDelete: @escaping () async -> DeleteOutcome, makeProject: @escaping (UUID) -> AnyView) {
        self.viewModel = viewModel; self.companyId = companyId; self.onSave = onSave; self.onDelete = onDelete; self.makeProject = makeProject
    }

    public var body: some View {
        Group {
            if let c = viewModel.customer {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.lg) {
                        Card {
                            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                                Text(verbatim: c.name).font(DSTypography.largeTitle)
                                if let company = c.companyName { Text(verbatim: company).foregroundStyle(DSColor.textSecondary) }
                                HStack(spacing: DSSpacing.md) {
                                    if let phone = c.phone {
                                        contactButton("customers.call", "phone.fill", url: "tel:" + phone.filter { !$0.isWhitespace }, id: "customer_call")
                                        contactButton("customers.text", "message.fill", url: "sms:" + phone.filter { !$0.isWhitespace }, id: "customer_text")
                                    }
                                    if let email = c.email { contactButton("customers.email", "envelope.fill", url: "mailto:" + email, id: "customer_email") }
                                }
                                if let phone = c.phone { FormRow("wizard.customer.phone") { Text(verbatim: phone) } }
                                if let email = c.email { FormRow("wizard.customer.email") { Text(verbatim: email) } }
                                if let pref = c.preferredContact { FormRow("wizard.customer.preferredContact") { Text(LocalizedStringKey("contact." + pref.rawValue)) } }
                                if let secondary = c.secondaryContact { FormRow("customers.form.secondaryContact") { Text(verbatim: secondary) } }
                                if let notes = c.notes { Text(verbatim: notes).font(DSTypography.callout).foregroundStyle(DSColor.textSecondary) }
                            }
                        }
                        SectionHeader("customers.projects")
                        if viewModel.projects.isEmpty { Text("customers.noProjects").foregroundStyle(DSColor.textSecondary).padding(.horizontal, DSSpacing.lg) }
                        ForEach(viewModel.projects) { project in
                            NavigationLink { makeProject(project.id) } label: {
                                Card {
                                    HStack {
                                        VStack(alignment: .leading) { Text(verbatim: project.name).font(DSTypography.headline); Text(verbatim: project.address.line).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                                        Spacer(); StatusBadge(project.status.titleKey, tone: project.status.tone)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(DSSpacing.lg)
                }
                .accessibilityIdentifier("customer_profile")
            } else if viewModel.isLoaded {
                EmptyState(systemImage: "person.slash", title: "customers.missing.title", message: "customers.missing.message")
            } else { ProgressView() }
        }
        .background(DSColor.background)
        .navigationTitle(Text(verbatim: viewModel.customer?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("customers.edit") { editing = true }.accessibilityIdentifier("customer_edit")
                    Button("customers.delete", role: .destructive) { Task { deleteOutcome = await onDelete(); if deleteOutcome == .deleted { dismiss() } } }.accessibilityIdentifier("customer_delete")
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editing) {
            CustomerFormView(customer: viewModel.customer, companyId: companyId, onSave: { c in let ok = await onSave(c); if ok { editing = false; await viewModel.load() }; return ok }, onCancel: { editing = false })
        }
        .alert("customers.delete.blocked", isPresented: Binding(get: { deleteOutcome == .hasProjects }, set: { if !$0 { deleteOutcome = nil } })) { Button("sheet.ok") {} }
        .alert("customers.saveFailed", isPresented: Binding(get: { deleteOutcome == .failed }, set: { if !$0 { deleteOutcome = nil } })) { Button("sheet.ok") {} }
        .task { await viewModel.load() }
    }

    private func contactButton(_ title: LocalizedStringKey, _ symbol: String, url: String, id: String) -> some View {
        Button { if let u = URL(string: url) { UIApplication.shared.open(u) } } label: {
            Label(title, systemImage: symbol).font(DSTypography.callout).padding(.horizontal, DSSpacing.md).frame(minHeight: DSSpacing.minTouch)
                .background(DSColor.accent.opacity(0.14), in: Capsule()).foregroundStyle(DSColor.accent)
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
```

- [ ] **Step 5: `MoreView` + App**

`MoreView` thêm tham số `makeCustomers: @escaping () -> AnyView` và dòng đầu List:

```swift
            NavigationLink { makeCustomers() } label: { Label("more.customers", systemImage: "person.2") }
                .frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("more_customers")
```

`Screens.swift` thêm:

```swift
import CustomersFeature

struct CustomersScreen: View {
    @State private var viewModel: CustomersListViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup
    init(ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: CustomersListViewModel(customerRepository: ready.customerRepository, companyId: setup.company.id, actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName)))
        self.ready = ready; self.setup = setup
    }
    var body: some View { CustomersListView(viewModel: viewModel, makeProfile: { id in AnyView(CustomerProfileScreen(customerId: id, ready: ready, setup: setup)) }) }
}

struct CustomerProfileScreen: View {
    @State private var viewModel: CustomerProfileViewModel
    @State private var listViewModel: CustomersListViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup
    init(customerId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: CustomerProfileViewModel(customerId: customerId, customerRepository: ready.customerRepository))
        _listViewModel = State(initialValue: CustomersListViewModel(customerRepository: ready.customerRepository, companyId: setup.company.id, actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName)))
        self.ready = ready; self.setup = setup
    }
    var body: some View {
        CustomerProfileView(viewModel: viewModel, companyId: setup.company.id,
                            onSave: { await listViewModel.save($0) },
                            onDelete: { await listViewModel.delete(viewModel.customer?.id ?? UUID()) },
                            makeProject: { id in AnyView(ProjectDetailScreen(projectId: id, ready: ready, setup: setup)) })
    }
}
```

`RootTabView`: `MoreView(settings:company:showsGallery:makeCustomers: { AnyView(CustomersScreen(ready: ready, setup: setup)) })`.

- [ ] **Step 6: Key mới**

`more.customers` Customers/Khách hàng · `customers.title` Customers/Khách hàng · `customers.search` Search customers/Tìm khách · `customers.add` Add customer/Thêm khách · `customers.empty.title` No customers yet/Chưa có khách · `customers.empty.message` Add customers here or while creating a project./Thêm khách ở đây hoặc khi tạo dự án. · `customers.error` Could not load customers./Không tải được khách. · `customers.saveFailed` Could not save./Không lưu được. · `customers.form.contact` Contact/Liên hệ · `customers.form.more` More/Thêm · `customers.form.secondaryContact` Secondary contact/Liên hệ phụ · `customers.form.notes` Notes/Ghi chú · `customers.form.newTitle` New customer/Khách mới · `customers.form.editTitle` Edit customer/Sửa khách · `customers.call` Call/Gọi · `customers.text` Text/Nhắn · `customers.email` Email/Email · `customers.projects` Projects/Dự án · `customers.noProjects` No projects yet/Chưa có dự án · `customers.missing.title` Customer not found/Không thấy khách · `customers.missing.message` This customer was removed./Khách này đã bị xóa. · `customers.edit` Edit/Sửa · `customers.delete` Delete/Xóa · `customers.delete.blocked` This customer still has projects and cannot be deleted./Khách còn dự án, không xóa được.

- [ ] **Step 7: Script check, commit, push, CI xanh**

```bash
git add Packages/Features App App/Resources
git commit -m "feat(customers): add customer list, form and profile"
git push origin HEAD
```

---

### Task 21: UI tests (a–f) + screenshots + ghi chú deferred

**Files:**
- Create: `UITests/ProjectsFlowTests.swift`
- Modify: `UITests/ScreenshotTests.swift` (thêm wizard steps, detail, customers), `.github/workflows/ios.yml` (không đổi — test chạy theo scheme)

**Interfaces:**
- Consumes: identifiers của Task 13–20; launch args Foundation (`--ui-testing --seed-sample-data --locale --appearance`).

- [ ] **Step 1: `ProjectsFlowTests.swift`**

```swift
import XCTest
import Foundation

final class ProjectsFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", "en"] + extra
        app.launch()
        return app
    }
    private func tapTab(_ app: XCUIApplication, _ label: String) { app.tabBars.buttons[label].tap() }
    private func type(_ el: XCUIElement, _ text: String) { el.tap(); el.typeText(text) }
    private func row(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let b = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        return b.waitForExistence(timeout: 2) ? b : app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// (a) minimal project through the 4 required steps, skipping the rest
    func testCreateMinimalProject() {
        let app = launch()
        tapTab(app, "Projects")
        app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_kitchen"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "Ann Lee").tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_address_line"], "77 Elm Street"); app.buttons["wizard_continue"].tap()
        for _ in 0..<5 { app.buttons["wizard_skip"].tap() }                 // scope, timeline, labour, material, other
        type(app.textFields["wizard_contract_value"], "12000"); app.buttons["wizard_continue"].tap()
        app.buttons["wizard_skip"].tap(); app.buttons["wizard_skip"].tap()   // deposit, schedule
        XCTAssertTrue(app.textFields["wizard_review_name"].waitForExistence(timeout: 3))
        app.buttons["wizard_continue"].tap()                                 // Create project
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["77 Elm Street"].exists)
    }

    /// (b) full project with the four-stage template → 4 rows, total == contract
    func testCreateProjectWithFourStageSchedule() {
        let app = launch()
        tapTab(app, "Projects"); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_roofing"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "Maria Santos").tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_address_line"], "9 Pine Road"); app.buttons["wizard_continue"].tap()
        for _ in 0..<5 { app.buttons["wizard_skip"].tap() }
        type(app.textFields["wizard_contract_value"], "20000"); app.buttons["wizard_continue"].tap()
        app.buttons["wizard_skip"].tap()                                     // deposit
        app.buttons["wizard_template_fourStage"].tap()
        XCTAssertTrue(app.textFields["wizard_schedule_row_3_amount"].waitForExistence(timeout: 3))
        app.buttons["wizard_continue"].tap()
        app.buttons["wizard_continue"].tap()                                 // Create
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
        let total = app.descendants(matching: .any)["detail_schedule_total"]
        XCTAssertTrue(total.waitForExistence(timeout: 3))
        XCTAssertTrue(total.label.contains("20,000.00"), total.label)
    }

    /// (c) close mid-way, relaunch, banner resumes at the same step
    func testDraftSurvivesRelaunch() {
        let app = launch()
        tapTab(app, "Projects"); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_bathroom"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "David Nguyen").tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_address_line"], "5 Lake Ave"); app.buttons["wizard_continue"].tap()   // now on step 4
        app.buttons["wizard_close"].tap()
        app.buttons["Save draft"].tap()
        XCTAssertTrue(app.otherElements["draft_banner"].waitForExistence(timeout: 3))
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", "en", "--keep-drafts"]
        again.launch()
        again.tabBars.buttons["Projects"].tap()
        XCTAssertTrue(again.otherElements["draft_banner"].waitForExistence(timeout: 5))
        XCTAssertTrue(again.staticTexts["4/12"].exists)
        again.buttons["draft_continue"].tap()
        XCTAssertTrue(again.textFields["wizard_scope_description"].waitForExistence(timeout: 3))
    }

    /// (d) edit estimate from detail → total updates live
    func testEditEstimateFromDetail() {
        let app = launch()
        tapTab(app, "Projects")
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "123 Main Street")).firstMatch.tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 5))
        app.buttons["detail_edit_estimate_material"].tap()
        XCTAssertTrue(app.buttons["wizard_line_add"].waitForExistence(timeout: 3))
        app.buttons["wizard_line_add"].tap()
        let newIndex = 4   // seed has 4 material lines
        type(app.textFields["wizard_line_label_\(newIndex)"], "Trim")
        type(app.textFields["wizard_line_amount_\(newIndex)"], "500")
        app.buttons["sheet_save"].tap()
        let total = app.descendants(matching: .any)["detail_estimate_total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("15,300.00"), total.label)      // 14,800 seed + 500
    }

    /// (e) add a customer from More → visible in wizard step 2
    func testCustomerAddedFromMoreAppearsInWizard() {
        let app = launch()
        tapTab(app, "More"); app.buttons["more_customers"].tap()
        app.buttons["customers_add"].tap()
        type(app.textFields["customer_form_name"], "Zed Young")
        app.buttons["customer_form_save"].tap()
        XCTAssertTrue(app.staticTexts["Zed Young"].waitForExistence(timeout: 5))
        tapTab(app, "Projects"); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_painting"].tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_customer_search"], "Zed")
        XCTAssertTrue(row(app, "Zed Young").waitForExistence(timeout: 3))
    }

    /// (f) Vietnamese locale: "1.500,50" is stored as 1500.50 and shown back
    func testVietnameseDecimalInput() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", "vi"]
        app.launch()
        app.tabBars.buttons["Dự án"].tap(); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_kitchen"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "Ann Lee").tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_address_line"], "1 Test"); app.buttons["wizard_continue"].tap()
        for _ in 0..<5 { app.buttons["wizard_skip"].tap() }
        type(app.textFields["wizard_contract_value"], "1500,50"); app.buttons["wizard_continue"].tap()
        app.buttons["wizard_skip"].tap(); app.buttons["wizard_skip"].tap()
        app.buttons["wizard_continue"].tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
        let header = app.otherElements["detail_header"]
        XCTAssertTrue(header.label.contains("1.500,50") || header.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1.500,50")).firstMatch.exists, header.label)
    }
}
```

Hỗ trợ (c): `LaunchOptions` thêm cờ `--keep-drafts` (không xóa thư mục nháp khi `--ui-testing`); `AppContainer.load()` chỉ `removeItem(draftDirectory)` khi `isUITesting && !keepDrafts`. Seed material total = 7,900 (Task 10), labour 6,000, other 900 → `detail_estimate_total` sau khi thêm 500 = 15,300.00 (sửa comment trong test: "14,800 seed" là tổng 3 nhóm).

- [ ] **Step 2: Screenshots** — thêm vào `ScreenshotTests.testCaptureAllScreens` sau vòng tab (chỉ `locale en/vi`, `light`; detail thêm `dark`):

```swift
                if appearance == "light" {
                    app.tabBars.buttons.element(boundBy: 1).tap()
                    app.buttons["projects_add"].tap()
                    let steps = ["jobType", "customer", "location", "scope", "timeline", "labour", "material", "other", "price", "deposit", "schedule", "review"]
                    app.buttons["wizard_jobtype_basementRenovation"].tap(); snap(app, "wizard_1_\(steps[0])_\(locale)")
                    app.buttons["wizard_continue"].tap(); snap(app, "wizard_2_\(steps[1])_\(locale)")
                    app.buttons.matching(NSPredicate(format: "label == %@", "Ann Lee")).firstMatch.tap(); app.buttons["wizard_continue"].tap()
                    app.textFields["wizard_address_line"].tap(); app.textFields["wizard_address_line"].typeText("88 Screenshot Lane")
                    snap(app, "wizard_3_\(steps[2])_\(locale)")
                    for i in 3..<12 {
                        app.buttons["wizard_continue"].exists && app.buttons["wizard_continue"].isEnabled ? app.buttons["wizard_continue"].tap() : app.buttons["wizard_skip"].tap()
                        if i == 8 { app.textFields["wizard_contract_value"].tap(); app.textFields["wizard_contract_value"].typeText("38000") }
                        if i == 10 { app.buttons["wizard_template_fourStage"].tap() }
                        snap(app, "wizard_\(i + 1)_\(steps[i])_\(locale)")
                    }
                    app.buttons["wizard_close"].tap(); app.buttons.element(boundBy: 1).tap()   // Discard draft
                    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "123 Main Street")).firstMatch.tap()
                    _ = app.otherElements["detail_header"].waitForExistence(timeout: 5)
                    snap(app, "detail_\(locale)_light")
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                    app.tabBars.buttons.element(boundBy: 4).tap(); app.buttons["more_customers"].tap()
                    snap(app, "customers_\(locale)")
                    app.cells.firstMatch.tap(); snap(app, "customer_profile_\(locale)")
                } else {
                    app.tabBars.buttons.element(boundBy: 1).tap()
                    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "123 Main Street")).firstMatch.tap()
                    _ = app.otherElements["detail_header"].waitForExistence(timeout: 5)
                    snap(app, "detail_\(locale)_dark")
                }
```

Dòng ternary với side effect — viết thành `if … { tap } else { tap }` khi implement. Nút "Discard draft" trong confirmation dialog: dùng `app.buttons["Discard draft"]` (en) / `app.buttons["Bỏ nháp"]` (vi) theo `locale`.

- [ ] **Step 3: Push, CI, sửa tới xanh**

```bash
git add UITests App
git commit -m "test(projects): add create/browse UI flows and wizard screenshots"
git push origin HEAD
```

Vòng sửa: lỗi lookup XCUITest thường gặp — `textFields[...]` cho `TextField` có identifier; `otherElements["detail_header"]` (Card là `.other`); segmented picker là `app.segmentedControls`; `DatePicker` compact là `app.datePickers`. Sửa test hoặc identifier, không nới lỏng assertion về số tiền.

Tải artifact `screenshots`, kiểm tra bằng mắt: 12 bước × 2 locale, detail en/vi light + dark, customers, profile.

---

## Thứ tự và phụ thuộc

- Task 1–7 (Domain) tuần tự, verify local.
- Task 8–10 (Data) sau 7; CI verify — gộp push một lần sau Task 10 (nhánh `worktree-*`), sửa compile nếu có trước khi sang Features.
- Task 11 sau 7; Task 12–17 tuần tự (mỗi step file một task); Task 18 là mốc CI đầu tiên của Features (build + UI test cũ).
- Task 19, 20 sau 18; Task 21 cuối.
- Sau Task 21: final review, merge `main`, chạy `testflight` lane `beta`.

## Deferred ghi nhận trước (không làm trong 2a)

- Ngày hiển thị `storageString` (YYYY-MM-DD) thay vì format theo locale — 2b thêm `DateLabel`.
- `confirmJobTypeChange` dùng `String(localized:)` (system locale) cho nhãn custom.
- `ProjectDetailViewModel.save(.priceDeposit)` co giãn các đợt % theo contract mới — ghi vào spec 2b nếu cần hành vi khác.
- `MoneyField`/`DecimalField` chưa có test đơn vị (DesignSystem không có test target); UI test (f) là bằng chứng.