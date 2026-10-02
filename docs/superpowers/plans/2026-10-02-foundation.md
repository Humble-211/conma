# Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dựng nền cho app iOS Construction Management: Domain package có test đầy đủ, schema SQLite theo Phụ lục A, DesignSystem, localization en/vi, app shell 5 tab cài được lên iPhone qua TestFlight, pipeline CI xanh.

**Architecture:** Bốn Swift Package (`Domain` thuần Foundation, `Data` dùng GRDB, `DesignSystem` SwiftUI, `Features` MVVM với `@Observable`) + app target mỏng sinh bằng XcodeGen. Business logic chỉ nằm trong `Domain`, test trên Linux runner; `Data` test bằng `swift test` trên macOS runner; UI smoke test + screenshot trên simulator; TestFlight qua fastlane match.

**Tech Stack:** Swift 6 toolchain (ngôn ngữ mode Swift 5), SwiftUI, Observation, XCTest, GRDB 7, XcodeGen, fastlane (match, pilot), GitHub Actions (`ubuntu-latest` container `swift:6.0`, `macos-15`), Python 3 cho script kiểm tra.

**Spec:** `docs/superpowers/specs/2026-10-02-foundation-design.md` (đọc trước khi làm bất kỳ task nào; Phụ lục A là contract cho Task 12).

## Global Constraints

- iOS 17.0 trở lên; iPhone-first.
- `Domain` chỉ `import Foundation`. Không SwiftUI, UIKit, GRDB.
- `DesignSystem` không import `Domain`. `Features` không import `Data`. Chỉ `App` import `Data`.
- Tiền: `Decimal` bọc trong `Money`, luôn đúng 2 chữ số thập phân, làm tròn half away from zero tại `Money.rounded`. Không `Double`/`Float` cho tiền trong `Domain` và `Data` (ngoại lệ duy nhất: `latitude`/`longitude` của `photos`, đánh dấu `// lint:allow-double`).
- `Percentage(points:)` là điểm phần trăm: 10 nghĩa là 10%.
- Enum lưu raw value chuỗi camelCase, không đổi sau phát hành.
- Mọi entity trừ `Company` có `companyId`. Soft delete bằng `deletedAt`; không xóa vật lý.
- SQL: bảng số nhiều snake_case; tiền TEXT 2 chữ số; ngày lịch `YYYY-MM-DD`; mốc thời gian ISO-8601 UTC; boolean INTEGER 0/1; `ON DELETE RESTRICT`; khóa ngoại tổ hợp `(x_id, company_id)`; unique đích FK là đầy đủ, unique business key là partial `WHERE deleted_at IS NULL`.
- Không chuỗi hiển thị hard-code trong View: `Text` chỉ nhận key dạng `a.b.c`. English là source, Tiếng Việt dịch 100%. Thuật ngữ nghề giữ tiếng Anh trong bản Việt.
- Không `try!`, `fatalError`, force-unwrap trong code production (được phép trong test).
- Không gọi `Date()` trong `Domain`; `today`/`now` luôn là tham số.
- Repo public: không secret nào trong repo; chứng chỉ ở repo private riêng; workflow có secret không chạy cho PR từ fork.
- Commit message tiếng Anh, dạng `type(scope): summary`. Không thêm trailer `Co-Authored-By`.

## Review Focus

Năm trường hợp spec ngụ ý nhưng dễ bị bỏ sót; mỗi dòng đã được gắn test vào task sở hữu:

1. Chuỗi tiền trong DB có dấu phẩy, khoảng trắng hoặc hơn 2 chữ số thập phân (`"1,000.5"`, `" 12.345 "`): `Money(storage:)` phải trả `nil` thay vì đọc sai hoặc crash. → Task 2.
2. `CalendarDate(storage:)` nhận ngày không tồn tại (`2026-02-30`) hoặc sai định dạng (`2026-2-3`): trả `nil`. `daysUntil` qua năm nhuận và qua đổi giờ mùa phải đúng số ngày lịch. → Task 4.
3. Project có task nhưng tất cả task đã soft-delete: progress phải là 0, không chia cho 0. → Task 8.
4. Mở app lần hai với DB đã có company nhưng `users` trống (ghi dở lần đầu): app không được coi là đã setup rồi crash khi cần actor; `CompanyRepository.current()` chỉ trả company khi có owner. → Task 13.
5. Đổi ngôn ngữ trong Settings khi đang ở tab More: tiêu đề của chính màn hình đang mở và các tab khác đổi ngay, không cần rời màn hình. → Task 21.

---

## Bố cục file

```
Construction/
  .gitignore
  README.md
  project.yml
  Gemfile
  fastlane/{Appfile,Fastfile,Matchfile}
  scripts/check_localization.py
  scripts/lint_sources.py
  .github/workflows/{domain.yml,ios.yml,testflight.yml}
  docs/SETUP.md
  App/
    ConstructionApp.swift
    AppContainer.swift
    LaunchOptions.swift
    RootView.swift
    RootTabView.swift
    DatabaseErrorView.swift
    Resources/Localizable.xcstrings
    Resources/Assets.xcassets/{AppIcon.appiconset,Contents.json}
  UITests/
    SmokeTests.swift
    ScreenshotTests.swift
  Packages/
    Domain/
      Package.swift
      Sources/Domain/
        Money/{CurrencyCode.swift,Money.swift,Percentage.swift,ScheduleSplitter.swift,CalendarDate.swift}
        Entities/{Common.swift,Enums.swift,Company.swift,User.swift,Customer.swift,Project.swift,ProjectEstimateLine.swift,ProjectTask.swift,Employee.swift,PaymentScheduleItem.swift,Payment.swift,Expense.swift,CustomExpenseCategory.swift,LabourEntry.swift,DailyLog.swift,Photo.swift,ActivityLog.swift,AppNotification.swift}
        DomainError.swift
        Finance/{FinancialInputs.swift,ProjectFinancials.swift,FinancialCalculator.swift}
        Progress/ProgressCalculator.swift
        Payments/{PaymentAllocation.swift,PaymentStatusResolver.swift}
        Health/{BudgetAlertRule.swift,ProjectHealthEvaluator.swift}
        Repositories/{ActivityActor.swift,CompanyRepository.swift,CustomerRepository.swift,ProjectRepository.swift}
      Tests/DomainTests/{MoneyTests,PercentageTests,ScheduleSplitterTests,CalendarDateTests,EnumMappingTests,ValidationTests,FinancialCalculatorTests,ProgressCalculatorTests,PaymentStatusResolverTests,BudgetAlertRuleTests,ProjectHealthEvaluatorTests}.swift
    Data/
      Package.swift
      Sources/Data/
        Database/{AppDatabase.swift,Clock.swift,Timestamps.swift}
        Migrations/Migration001_InitialSchema.swift
        Records/{CompanyRecord.swift,UserRecord.swift,CustomerRecord.swift,ProjectRecord.swift,ProjectScopeFieldRecord.swift,ActivityLogRecord.swift}
        Repositories/{GRDBCompanyRepository.swift,GRDBCustomerRepository.swift,GRDBProjectRepository.swift}
        Seed/SampleData.swift
      Tests/DataTests/{SchemaTests,ForeignKeyTests,CompanyRepositoryTests,CustomerRepositoryTests,ProjectRepositoryTests,SampleDataTests}.swift
    DesignSystem/
      Package.swift
      Sources/DesignSystem/
        Tokens/{DSColor.swift,DSSpacing.swift,DSTypography.swift}
        Components/{PrimaryButton.swift,SecondaryButton.swift,Card.swift,StatusBadge.swift,ProgressBar.swift,MoneyText.swift,SummaryTile.swift,SectionHeader.swift,EmptyState.swift,FormRow.swift,FloatingActionButton.swift}
        Gallery/ComponentGalleryView.swift
    Features/
      Package.swift
      Sources/
        FeatureSupport/{AppSettings.swift,LanguageChoice.swift,AppearanceChoice.swift,ProjectStatusStyle.swift,JobTypeLabel.swift}
        SetupFeature/{SetupView.swift,SetupViewModel.swift}
        HomeFeature/{HomeView.swift,HomeViewModel.swift,ProjectCardView.swift}
        ProjectsFeature/ProjectsPlaceholderView.swift
        CalendarFeature/CalendarPlaceholderView.swift
        ExpensesFeature/ExpensesPlaceholderView.swift
        MoreFeature/{MoreView.swift,SettingsView.swift}
```

Trách nhiệm:

- `Domain/Money`: kiểu giá trị tiền, phần trăm, ngày lịch. Không biết entity.
- `Domain/Entities`: struct dữ liệu thuần + enum + `validate()`.
- `Domain/Finance|Progress|Payments|Health`: hàm thuần, input là entity, output là struct kết quả.
- `Domain/Repositories`: protocol async, `Data` hiện thực.
- `Data/Database`: mở DB, migrator, clock, format thời gian.
- `Data/Migrations`: SQL theo Phụ lục A.
- `Data/Records`: struct GRDB snake_case + mapper sang entity.
- `Data/Repositories`: hiện thực protocol, transaction, activity log, cascade soft delete.
- `DesignSystem`: token + component không biết Domain.
- `Features/FeatureSupport`: settings ngôn ngữ/giao diện, map enum Domain sang style và key.
- `App`: composition root, launch options cho test, root navigation.

---

### Task 1: Khởi tạo repo, Domain package rỗng, CI `domain.yml`

**Files:**
- Create: `.gitignore`, `README.md`
- Create: `Packages/Domain/Package.swift`
- Create: `Packages/Domain/Sources/Domain/Money/CurrencyCode.swift`
- Create: `Packages/Domain/Tests/DomainTests/CurrencyCodeTests.swift`
- Create: `.github/workflows/domain.yml`

**Interfaces:**
- Produces: `public enum CurrencyCode: String, Codable, Sendable, CaseIterable { case cad = "CAD", usd = "USD" }`.

- [ ] **Step 1: Tạo `.gitignore` và `README.md`**

`.gitignore`:

```gitignore
# Xcode / SwiftPM
*.xcodeproj
*.xcworkspace
!*.xcworkspace/contents.xcworkspacedata
.build/
DerivedData/
*.xcresult
.swiftpm/
Packages/*/.build/
Packages/*/.swiftpm/

# fastlane
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots/
fastlane/test_output/
*.ipa
*.dSYM.zip
*.mobileprovision
*.p12
*.p8
*.cer

# Ruby
vendor/bundle/

# OS
.DS_Store
Thumbs.db

# Local
*.sqlite
*.sqlite-wal
*.sqlite-shm
```

`README.md`:

```markdown
# Construction Management

iOS app for small and mid-size contractors: jobs, progress, costs, payments, crew.

- Spec: `docs/superpowers/specs/`
- Plans: `docs/superpowers/plans/`
- Setup for CI, signing and TestFlight: `docs/SETUP.md`

## Layout

- `Packages/Domain` — pure Swift business rules (tested on Linux)
- `Packages/Data` — GRDB/SQLite persistence
- `Packages/DesignSystem` — SwiftUI tokens and components
- `Packages/Features` — screens (MVVM)
- `App/` — thin app target, generated with XcodeGen (`project.yml`)
```

- [ ] **Step 2: Viết `Package.swift` cho Domain**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Domain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
    ],
    targets: [
        .target(name: "Domain", path: "Sources/Domain"),
        .testTarget(name: "DomainTests", dependencies: ["Domain"], path: "Tests/DomainTests"),
    ]
)
```

- [ ] **Step 3: Viết test fail**

`Packages/Domain/Tests/DomainTests/CurrencyCodeTests.swift`:

```swift
import XCTest
@testable import Domain

final class CurrencyCodeTests: XCTestCase {
    func testRawValuesAreISOCodes() {
        XCTAssertEqual(CurrencyCode.cad.rawValue, "CAD")
        XCTAssertEqual(CurrencyCode.usd.rawValue, "USD")
        XCTAssertEqual(CurrencyCode.allCases.count, 2)
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: lỗi biên dịch `cannot find 'CurrencyCode' in scope`.

- [ ] **Step 5: Viết `CurrencyCode`**

```swift
public enum CurrencyCode: String, Codable, Sendable, CaseIterable, Hashable {
    case cad = "CAD"
    case usd = "USD"
}
```

- [ ] **Step 6: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: `Executed 1 test, with 0 failures`.

- [ ] **Step 7: Viết `domain.yml`**

```yaml
name: domain

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    container: swift:6.0
    steps:
      - uses: actions/checkout@v4
      - name: Test Domain package
        run: swift test --package-path Packages/Domain
```

- [ ] **Step 8: Commit**

```bash
git add .gitignore README.md Packages/Domain .github/workflows/domain.yml
git commit -m "chore: scaffold Domain package and Linux CI"
```

---

### Task 2: `Money` + quy tắc làm tròn

**Files:**
- Create: `Packages/Domain/Sources/Domain/Money/Money.swift`
- Create: `Packages/Domain/Sources/Domain/DomainError.swift`
- Test: `Packages/Domain/Tests/DomainTests/MoneyTests.swift`

**Interfaces:**
- Produces:
  - `public struct Money: Hashable, Sendable, Codable` với `amount: Decimal`, `currency: CurrencyCode`.
  - `init(_ raw: Decimal, _ currency: CurrencyCode)` (làm tròn), `init?(storage: String, currency: CurrencyCode)`.
  - `static func rounded(_ value: Decimal, scale: Int = 2) -> Decimal`, `static func zero(_ currency: CurrencyCode) -> Money`.
  - `var storageString: String`, `var isNegative: Bool`, `var isZero: Bool`.
  - `func adding(_:) throws -> Money`, `func subtracting(_:) throws -> Money`, `func multiplied(by factor: Decimal) -> Money`.
  - `static func sum(_ values: [Money], currency: CurrencyCode) throws -> Money`.
  - `public enum DomainError: Error, Equatable` với case đầu tiên `currencyMismatch`.

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class MoneyTests: XCTestCase {
    private func cad(_ s: String) -> Money { Money(Decimal(string: s)!, .cad) }

    func testRoundingHalfAwayFromZero() {
        XCTAssertEqual(Money.rounded(Decimal(string: "0.005")!), Decimal(string: "0.01")!)
        XCTAssertEqual(Money.rounded(Decimal(string: "0.004")!), Decimal(string: "0.00")!)
        XCTAssertEqual(Money.rounded(Decimal(string: "2.675")!), Decimal(string: "2.68")!)
        XCTAssertEqual(Money.rounded(Decimal(string: "-0.005")!), Decimal(string: "-0.01")!)
    }

    func testInitRoundsToTwoDecimals() {
        XCTAssertEqual(cad("12.345").amount, Decimal(string: "12.35")!)
        XCTAssertEqual(cad("12.344").storageString, "12.34")
    }

    func testStorageStringAlwaysHasTwoDecimals() {
        XCTAssertEqual(cad("5").storageString, "5.00")
        XCTAssertEqual(cad("5.5").storageString, "5.50")
        XCTAssertEqual(cad("0").storageString, "0.00")
        XCTAssertEqual(cad("-3.4").storageString, "-3.40")
        XCTAssertEqual(cad("1234567.89").storageString, "1234567.89")
    }

    func testStorageRoundTrip() {
        let m = Money(storage: "246.50", currency: .cad)
        XCTAssertEqual(m?.amount, Decimal(string: "246.50")!)
        XCTAssertEqual(m?.storageString, "246.50")
    }

    func testStorageRejectsMalformedStrings() {
        XCTAssertNil(Money(storage: "1,000.5", currency: .cad))
        XCTAssertNil(Money(storage: " 12.345 ", currency: .cad))
        XCTAssertNil(Money(storage: "12.345", currency: .cad))
        XCTAssertNil(Money(storage: "abc", currency: .cad))
        XCTAssertNil(Money(storage: "", currency: .cad))
        XCTAssertNotNil(Money(storage: "-12.30", currency: .cad))
    }

    func testAddSubtractExact() throws {
        let a = cad("0.10"), b = cad("0.20")
        XCTAssertEqual(try a.adding(b).storageString, "0.30")
        XCTAssertEqual(try a.subtracting(b).storageString, "-0.10")
    }

    func testMultiplyRounds() {
        XCTAssertEqual(cad("250.00").multiplied(by: Decimal(string: "0.5")!).storageString, "125.00")
        XCTAssertEqual(cad("10.00").multiplied(by: Decimal(string: "0.3333")!).storageString, "3.33")
        XCTAssertEqual(cad("0.01").multiplied(by: Decimal(string: "0.5")!).storageString, "0.01")
    }

    func testSumIsSumOfRoundedLines() throws {
        let lines = [cad("0.333"), cad("0.333"), cad("0.333")]
        XCTAssertEqual(try Money.sum(lines, currency: .cad).storageString, "0.99")
        XCTAssertEqual(try Money.sum([], currency: .usd), Money.zero(.usd))
    }

    func testCurrencyMismatchThrows() {
        let a = cad("1.00"), b = Money(1, .usd)
        XCTAssertThrowsError(try a.adding(b)) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
        XCTAssertThrowsError(try a.subtracting(b)) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
        XCTAssertThrowsError(try Money.sum([a, b], currency: .cad)) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
    }

    func testSignFlags() {
        XCTAssertTrue(cad("-0.01").isNegative)
        XCTAssertFalse(cad("0.00").isNegative)
        XCTAssertTrue(cad("0.00").isZero)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'Money' in scope`.

- [ ] **Step 3: Viết `DomainError` (case đầu) và `Money`**

`DomainError.swift`:

```swift
public enum DomainError: Error, Equatable, Sendable {
    case currencyMismatch
}
```

`Money.swift`:

```swift
import Foundation

public struct Money: Hashable, Sendable, Codable {
    /// Always exactly 2 decimal places (see spec 5.1).
    public let amount: Decimal
    public let currency: CurrencyCode

    public init(_ raw: Decimal, _ currency: CurrencyCode) {
        self.amount = Money.rounded(raw)
        self.currency = currency
    }

    /// Parses the canonical storage form: optional "-", digits, ".", exactly two digits.
    public init?(storage: String, currency: CurrencyCode) {
        guard Money.isCanonical(storage), let value = Decimal(string: storage, locale: nil) else { return nil }
        self.amount = value
        self.currency = currency
    }

    public static func zero(_ currency: CurrencyCode) -> Money { Money(0, currency) }

    /// The single rounding point of the domain: half away from zero, `scale` decimals.
    public static func rounded(_ value: Decimal, scale: Int = 2) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    public var isNegative: Bool { amount < 0 }
    public var isZero: Bool { amount == 0 }

    public var storageString: String {
        let cents = NSDecimalNumber(decimal: amount * 100).int64Value
        let magnitude = cents.magnitude
        let whole = magnitude / 100
        let fraction = magnitude % 100
        let fractionText = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return "\(cents < 0 ? "-" : "")\(whole).\(fractionText)"
    }

    public func adding(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        return Money(amount + other.amount, currency)
    }

    public func subtracting(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        return Money(amount - other.amount, currency)
    }

    public func multiplied(by factor: Decimal) -> Money {
        Money(amount * factor, currency)
    }

    public static func sum(_ values: [Money], currency: CurrencyCode) throws -> Money {
        var total = Money.zero(currency)
        for value in values { total = try total.adding(value) }
        return total
    }

    private func requireSameCurrency(_ other: Money) throws {
        guard currency == other.currency else { throw DomainError.currencyMismatch }
    }

    private static func isCanonical(_ text: String) -> Bool {
        var chars = Substring(text)
        if chars.first == "-" { chars = chars.dropFirst() }
        let parts = chars.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) } && parts[0].allSatisfy(\.isASCII) && parts[1].allSatisfy(\.isASCII)
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: tất cả `MoneyTests` pass. Nếu `testRoundingHalfAwayFromZero` fail ở `-0.005`: kiểm tra `NSDecimalRound` dùng `.plain` (half away from zero), không phải `.bankers`.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add Money with single rounding point"
```

---

### Task 3: `Percentage` + `ScheduleSplitter`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Money/Percentage.swift`
- Create: `Packages/Domain/Sources/Domain/Money/ScheduleSplitter.swift`
- Modify: `Packages/Domain/Sources/Domain/DomainError.swift` (thêm `invalidPercentage`)
- Test: `Packages/Domain/Tests/DomainTests/PercentageTests.swift`, `ScheduleSplitterTests.swift`

**Interfaces:**
- Produces:
  - `public struct Percentage: Hashable, Sendable, Codable { public let points: Decimal; public var fraction: Decimal }`
  - `static func input(_ points: Decimal) throws -> Percentage` (0...100, ≤ 2 chữ số thập phân)
  - `static func computed(_ points: Decimal) -> Percentage` (làm tròn 1 chữ số, không giới hạn)
  - `static func ratio(_ numerator: Money, over denominator: Money) -> Percentage?` (nil khi mẫu = 0)
  - `extension Money { func multiplied(by percentage: Percentage) -> Money }`
  - `public enum ScheduleSplitter { static func amounts(of contract: Money, percentages: [Percentage]) -> [Money] }`

- [ ] **Step 1: Viết test fail**

`PercentageTests.swift`:

```swift
import XCTest
@testable import Domain

final class PercentageTests: XCTestCase {
    func testInputAcceptsRangeAndTwoDecimals() throws {
        XCTAssertEqual(try Percentage.input(10).points, 10)
        XCTAssertEqual(try Percentage.input(0).points, 0)
        XCTAssertEqual(try Percentage.input(100).points, 100)
        XCTAssertEqual(try Percentage.input(Decimal(string: "33.33")!).points, Decimal(string: "33.33")!)
    }

    func testInputRejectsOutOfRangeAndTooManyDecimals() {
        XCTAssertThrowsError(try Percentage.input(-1)) { XCTAssertEqual($0 as? DomainError, .invalidPercentage) }
        XCTAssertThrowsError(try Percentage.input(Decimal(string: "100.01")!)) { XCTAssertEqual($0 as? DomainError, .invalidPercentage) }
        XCTAssertThrowsError(try Percentage.input(Decimal(string: "12.345")!)) { XCTAssertEqual($0 as? DomainError, .invalidPercentage) }
    }

    func testFractionAndMoneyMultiplication() throws {
        let contract = Money(30_000, .cad)
        XCTAssertEqual(contract.multiplied(by: try Percentage.input(10)).storageString, "3000.00")
        XCTAssertEqual(contract.multiplied(by: try Percentage.input(20)).storageString, "6000.00")
        XCTAssertEqual(try Percentage.input(25).fraction, Decimal(string: "0.25")!)
    }

    func testComputedRoundsToOneDecimal() {
        XCTAssertEqual(Percentage.computed(Decimal(string: "51.6666")!).points, Decimal(string: "51.7")!)
        XCTAssertEqual(Percentage.computed(Decimal(string: "-12.35")!).points, Decimal(string: "-12.4")!)
        XCTAssertEqual(Percentage.computed(150).points, 150)
    }

    func testRatio() {
        let profit = Money(15_500, .cad), contract = Money(30_000, .cad)
        XCTAssertEqual(Percentage.ratio(profit, over: contract)?.points, Decimal(string: "51.7")!)
        XCTAssertNil(Percentage.ratio(profit, over: Money.zero(.cad)))
    }
}
```

`ScheduleSplitterTests.swift`:

```swift
import XCTest
@testable import Domain

final class ScheduleSplitterTests: XCTestCase {
    private func pct(_ s: String) -> Percentage { try! Percentage.input(Decimal(string: s)!) }

    func testLastLineTakesResidualWhenTotalIs100() {
        let contract = Money(Decimal(string: "30000.01")!, .cad)
        let amounts = ScheduleSplitter.amounts(of: contract, percentages: [pct("20"), pct("30"), pct("30"), pct("20")])
        XCTAssertEqual(amounts.map(\.storageString), ["6000.00", "9000.00", "9000.00", "6000.01"])
    }

    func testThirdsOfHundredWithResidual() {
        let amounts = ScheduleSplitter.amounts(of: Money(100, .cad), percentages: [pct("33.33"), pct("33.33"), pct("33.34")])
        XCTAssertEqual(amounts.map(\.storageString), ["33.33", "33.33", "33.34"])
    }

    func testNoResidualWhenTotalIsNot100() {
        let amounts = ScheduleSplitter.amounts(of: Money(100, .cad), percentages: [pct("33.33"), pct("33.33"), pct("33.33")])
        XCTAssertEqual(amounts.map(\.storageString), ["33.33", "33.33", "33.33"])
    }

    func testEmptyInput() {
        XCTAssertEqual(ScheduleSplitter.amounts(of: Money(100, .cad), percentages: []), [])
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'Percentage' in scope`.

- [ ] **Step 3: Viết code**

`DomainError.swift` thêm case:

```swift
    case invalidPercentage
```

`Percentage.swift`:

```swift
import Foundation

/// Percentage points: `Percentage(points: 10)` means 10 %, never "10 times".
public struct Percentage: Hashable, Sendable, Codable {
    public let points: Decimal

    private init(points: Decimal) { self.points = points }

    /// User input: 0...100 with at most two decimals.
    public static func input(_ points: Decimal) throws -> Percentage {
        guard points >= 0, points <= 100, Money.rounded(points, scale: 2) == points else {
            throw DomainError.invalidPercentage
        }
        return Percentage(points: points)
    }

    /// Computed result (margin, budget used): unbounded, rounded to one decimal.
    public static func computed(_ points: Decimal) -> Percentage {
        Percentage(points: Money.rounded(points, scale: 1))
    }

    /// numerator / denominator × 100, or nil when the denominator is zero.
    public static func ratio(_ numerator: Money, over denominator: Money) -> Percentage? {
        guard !denominator.isZero else { return nil }
        return computed(numerator.amount / denominator.amount * 100)
    }

    public var fraction: Decimal { points / 100 }
}

public extension Money {
    func multiplied(by percentage: Percentage) -> Money {
        multiplied(by: percentage.fraction)
    }
}
```

`ScheduleSplitter.swift`:

```swift
import Foundation

public enum ScheduleSplitter {
    /// Each line is `rounded(contract × fraction)`. When the percentages total exactly 100,
    /// the last line receives the residual so the lines sum to the contract to the cent.
    public static func amounts(of contract: Money, percentages: [Percentage]) -> [Money] {
        guard !percentages.isEmpty else { return [] }
        var lines = percentages.map { contract.multiplied(by: $0) }
        let totalPoints = percentages.reduce(Decimal(0)) { $0 + $1.points }
        if totalPoints == 100 {
            let allButLast = lines.dropLast().reduce(Decimal(0)) { $0 + $1.amount }
            lines[lines.count - 1] = Money(contract.amount - allButLast, contract.currency)
        }
        return lines
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass toàn bộ.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add Percentage and schedule splitting with residual"
```

---

### Task 4: `CalendarDate`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Money/CalendarDate.swift`
- Test: `Packages/Domain/Tests/DomainTests/CalendarDateTests.swift`

**Interfaces:**
- Produces: `public struct CalendarDate: Hashable, Comparable, Sendable, Codable` với `year`, `month`, `day`; `init?(year:month:day:)`, `init?(storage: String)`, `init(_ date: Date, timeZone: TimeZone)`, `var storageString: String`, `func daysUntil(_ other: CalendarDate) -> Int`, `func adding(days: Int) -> CalendarDate`.

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class CalendarDateTests: XCTestCase {
    func testStorageRoundTrip() {
        let d = CalendarDate(storage: "2026-10-05")
        XCTAssertEqual(d?.year, 2026); XCTAssertEqual(d?.month, 10); XCTAssertEqual(d?.day, 5)
        XCTAssertEqual(d?.storageString, "2026-10-05")
        XCTAssertEqual(CalendarDate(year: 2026, month: 1, day: 9)?.storageString, "2026-01-09")
    }

    func testRejectsInvalidDates() {
        XCTAssertNil(CalendarDate(storage: "2026-02-30"))
        XCTAssertNil(CalendarDate(storage: "2026-2-3"))
        XCTAssertNil(CalendarDate(storage: "2026/02/03"))
        XCTAssertNil(CalendarDate(storage: "2026-13-01"))
        XCTAssertNil(CalendarDate(year: 2025, month: 2, day: 29))
        XCTAssertNotNil(CalendarDate(year: 2024, month: 2, day: 29))
    }

    func testDaysUntilAcrossLeapDayAndYears() {
        let a = CalendarDate(storage: "2024-02-28")!, b = CalendarDate(storage: "2024-03-01")!
        XCTAssertEqual(a.daysUntil(b), 2)
        XCTAssertEqual(b.daysUntil(a), -2)
        XCTAssertEqual(a.daysUntil(a), 0)
        XCTAssertEqual(CalendarDate(storage: "2025-12-31")!.daysUntil(CalendarDate(storage: "2026-01-01")!), 1)
    }

    func testDaysUntilAcrossDSTChangeIsWholeDays() {
        // Toronto DST starts 2026-03-08; calendar math must not produce 23-hour days.
        let a = CalendarDate(storage: "2026-03-07")!, b = CalendarDate(storage: "2026-03-09")!
        XCTAssertEqual(a.daysUntil(b), 2)
    }

    func testAddingDays() {
        XCTAssertEqual(CalendarDate(storage: "2026-10-30")!.adding(days: 3).storageString, "2026-11-02")
        XCTAssertEqual(CalendarDate(storage: "2026-01-01")!.adding(days: -1).storageString, "2025-12-31")
    }

    func testComparable() {
        XCTAssertLessThan(CalendarDate(storage: "2026-01-31")!, CalendarDate(storage: "2026-02-01")!)
    }

    func testFromDateUsesGivenTimeZone() {
        // 2026-10-05 03:30 UTC is still 2026-10-04 in Toronto (UTC-4).
        let instant = Date(timeIntervalSince1970: 1_791_171_000) // 2026-10-05T03:30:00Z
        XCTAssertEqual(CalendarDate(instant, timeZone: TimeZone(identifier: "UTC")!).storageString, "2026-10-05")
        XCTAssertEqual(CalendarDate(instant, timeZone: TimeZone(identifier: "America/Toronto")!).storageString, "2026-10-04")
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'CalendarDate' in scope`.

- [ ] **Step 3: Viết `CalendarDate`**

```swift
import Foundation

/// A calendar day without time: due dates, start dates, completion dates.
public struct CalendarDate: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    private static let utc = TimeZone(identifier: "UTC")!
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    public init?(year: Int, month: Int, day: Int) {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        guard components.isValidDate(in: CalendarDate.calendar) else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    /// Parses exactly `YYYY-MM-DD`.
    public init?(storage: String) {
        let parts = storage.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The calendar day of an instant, as seen in `timeZone`.
    public init(_ date: Date, timeZone: TimeZone) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        let parts = c.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year ?? 1970; self.month = parts.month ?? 1; self.day = parts.day ?? 1
    }

    public var storageString: String {
        func pad(_ v: Int, _ width: Int) -> String {
            let s = String(v)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    private var midnightUTC: Date {
        var c = DateComponents(); c.year = year; c.month = month; c.day = day
        return CalendarDate.calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// Whole calendar days from `self` to `other`; negative when `other` is earlier.
    public func daysUntil(_ other: CalendarDate) -> Int {
        CalendarDate.calendar.dateComponents([.day], from: midnightUTC, to: other.midnightUTC).day ?? 0
    }

    public func adding(days: Int) -> CalendarDate {
        let shifted = CalendarDate.calendar.date(byAdding: .day, value: days, to: midnightUTC) ?? midnightUTC
        return CalendarDate(shifted, timeZone: CalendarDate.utc)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass. Nếu `testFromDateUsesGivenTimeZone` fail trên Linux với lỗi timezone: container `swift:6.0` có tzdata; nếu thiếu, thêm `apt-get update && apt-get install -y tzdata` vào `domain.yml` trước bước test.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add CalendarDate for time-free dates"
```

---

### Task 5: Enums, `phase`, mapping `ExpenseCategory → CostGroup`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Entities/Enums.swift`
- Test: `Packages/Domain/Tests/DomainTests/EnumMappingTests.swift`

**Interfaces:**
- Produces (tất cả `String, Codable, Sendable, CaseIterable, Hashable`):
  - `ProjectStatus` (13) với `var phase: ProjectPhase`; `enum ProjectPhase { preStart, inWork, workDone, terminal }`
  - `TaskStatus` (6), `PaymentMethod` (6), `PhotoCategory` (6), `JobType` (20), `CostGroup` (6)
  - `ExpenseCategory` (14 gồm `custom`) với `var defaultCostGroup: CostGroup?` (nil cho `custom`)
  - `ContactMethod { phone, text, email }`, `UserRole { owner }`, `SyncState { pending, synced }`

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class EnumMappingTests: XCTestCase {
    func testProjectStatusCountAndRawValues() {
        XCTAssertEqual(ProjectStatus.allCases.count, 13)
        XCTAssertEqual(ProjectStatus.awaitingFinalPayment.rawValue, "awaitingFinalPayment")
        XCTAssertEqual(ProjectStatus.waitingForInspection.rawValue, "waitingForInspection")
    }

    func testPhases() {
        XCTAssertEqual([ProjectStatus.estimate, .awaitingApproval, .awaitingDeposit].map(\.phase), [.preStart, .preStart, .preStart])
        XCTAssertEqual([ProjectStatus.scheduled, .inProgress, .onHold, .waitingForInspection, .waitingForMaterial, .waitingForClient].map(\.phase),
                       Array(repeating: .inWork, count: 6))
        XCTAssertEqual([ProjectStatus.completed, .awaitingFinalPayment].map(\.phase), [.workDone, .workDone])
        XCTAssertEqual([ProjectStatus.closed, .cancelled].map(\.phase), [.terminal, .terminal])
    }

    func testJobTypes() {
        XCTAssertEqual(JobType.allCases.count, 20)
        XCTAssertEqual(JobType.deckFence.rawValue, "deckFence")
        XCTAssertEqual(JobType.windowsDoors.rawValue, "windowsDoors")
        XCTAssertEqual(JobType.hvac.rawValue, "hvac")
        XCTAssertEqual(JobType.allCases.last, .other)
    }

    func testExpenseCategoryToCostGroup() {
        XCTAssertEqual(ExpenseCategory.allCases.count, 14)
        XCTAssertEqual(ExpenseCategory.materials.defaultCostGroup, .material)
        XCTAssertEqual(ExpenseCategory.labour.defaultCostGroup, .labour)
        XCTAssertEqual(ExpenseCategory.subcontractor.defaultCostGroup, .subcontractor)
        XCTAssertEqual(ExpenseCategory.equipmentRental.defaultCostGroup, .equipment)
        XCTAssertEqual(ExpenseCategory.toolPurchase.defaultCostGroup, .equipment)
        XCTAssertEqual(ExpenseCategory.permit.defaultCostGroup, .permit)
        XCTAssertEqual(ExpenseCategory.inspection.defaultCostGroup, .permit)
        for c in [ExpenseCategory.delivery, .fuel, .wasteDisposal, .parking, .office, .other] {
            XCTAssertEqual(c.defaultCostGroup, .other, "\(c)")
        }
        XCTAssertNil(ExpenseCategory.custom.defaultCostGroup)
    }

    func testOtherEnumCounts() {
        XCTAssertEqual(TaskStatus.allCases.count, 6)
        XCTAssertEqual(PaymentMethod.allCases.count, 6)
        XCTAssertEqual(PaymentMethod.eTransfer.rawValue, "eTransfer")
        XCTAssertEqual(PhotoCategory.allCases.count, 6)
        XCTAssertEqual(CostGroup.allCases.count, 6)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'ProjectStatus' in scope`.

- [ ] **Step 3: Viết `Enums.swift`**

```swift
public enum ProjectPhase: Sendable, Hashable { case preStart, inWork, workDone, terminal }

public enum ProjectStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case estimate, awaitingApproval, awaitingDeposit
    case scheduled, inProgress, onHold, waitingForInspection, waitingForMaterial, waitingForClient
    case completed, awaitingFinalPayment
    case closed, cancelled

    public var phase: ProjectPhase {
        switch self {
        case .estimate, .awaitingApproval, .awaitingDeposit: return .preStart
        case .scheduled, .inProgress, .onHold, .waitingForInspection, .waitingForMaterial, .waitingForClient: return .inWork
        case .completed, .awaitingFinalPayment: return .workDone
        case .closed, .cancelled: return .terminal
        }
    }
}

public enum TaskStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case notStarted, scheduled, inProgress, blocked, waiting, completed
}

public enum PaymentMethod: String, Codable, Sendable, CaseIterable, Hashable {
    case cash, cheque, eTransfer, creditCard, bankTransfer, other
}

public enum PhotoCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case before, progress, issues, inspection, completed, receipts
}

public enum JobType: String, Codable, Sendable, CaseIterable, Hashable {
    case generalRenovation, basementRenovation, kitchen, bathroom, landscaping
    case roofing, plumbing, electrical, hvac, flooring, painting, drywall, concrete
    case deckFence, framing, windowsDoors, exterior, demolition, commercial, other
}

/// The single cost taxonomy shared by estimates, actual cost and budget alerts.
public enum CostGroup: String, Codable, Sendable, CaseIterable, Hashable {
    case material, labour, subcontractor, equipment, permit, other
}

public enum ExpenseCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case materials, labour, subcontractor, equipmentRental, toolPurchase, permit, inspection
    case delivery, fuel, wasteDisposal, parking, office, other
    case custom

    /// Spec 5.2 mapping table. `nil` for `custom`: the group comes from the custom category.
    public var defaultCostGroup: CostGroup? {
        switch self {
        case .materials: return .material
        case .labour: return .labour
        case .subcontractor: return .subcontractor
        case .equipmentRental, .toolPurchase: return .equipment
        case .permit, .inspection: return .permit
        case .delivery, .fuel, .wasteDisposal, .parking, .office, .other: return .other
        case .custom: return nil
        }
    }
}

public enum ContactMethod: String, Codable, Sendable, CaseIterable, Hashable { case phone, text, email }
public enum UserRole: String, Codable, Sendable, CaseIterable, Hashable { case owner }
public enum SyncState: String, Codable, Sendable, CaseIterable, Hashable { case pending, synced }
```

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add status, job type and cost taxonomy enums"
```

---

### Task 6: Entities + validation

**Files:**
- Create: `Packages/Domain/Sources/Domain/Entities/Common.swift` và một file mỗi entity (xem Bố cục file)
- Modify: `Packages/Domain/Sources/Domain/DomainError.swift`
- Test: `Packages/Domain/Tests/DomainTests/ValidationTests.swift`

**Interfaces:**
- Produces: các struct public dưới đây; `protocol Entity { id, createdAt, updatedAt, deletedAt }`; `protocol CompanyScoped: Entity { companyId }`; `var isDeleted: Bool`.
- `DomainError` đầy đủ: `currencyMismatch, invalidPercentage, negativeAmount, invalidPaymentAmount, invalidProgress, invalidLabourDays, completionBeforeStart, customJobTypeRequired, customCategoryRequired, costGroupMismatch, categoryInUse, customerHasProjects, categoryHasExpenses, emptyName, emptyFieldKey`.
- `Expense.resolveCostGroup(category:customCategory:) throws -> CostGroup`.

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class ValidationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let company = UUID(), project = UUID(), customer = UUID(), employee = UUID()

    private func baseProject() -> Project {
        Project(id: project, companyId: company, customerId: customer, name: "123 Main St", jobType: .kitchen, customJobType: nil,
                status: .inProgress, address: Address(line: "123 Main St", unit: nil, city: "Toronto", region: "ON", postalCode: "M1M 1M1"),
                scopeDescription: nil, scopeFields: [], startDate: CalendarDate(storage: "2026-10-01"),
                estimatedCompletionDate: CalendarDate(storage: "2026-10-20"), workingDays: 10, hoursPerDay: nil, workersPerDay: 3,
                contractValue: Money(30_000, .cad), manualProgress: nil, depositRequiredToStart: true,
                createdAt: now, updatedAt: now, deletedAt: nil)
    }

    func testValidProjectPasses() throws {
        XCTAssertNoThrow(try baseProject().validate())
    }

    func testProjectRejectsCompletionBeforeStart() {
        var p = baseProject()
        p.estimatedCompletionDate = CalendarDate(storage: "2026-09-30")
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .completionBeforeStart) }
    }

    func testProjectRejectsOtherWithoutCustomJobType() {
        var p = baseProject(); p.jobType = .other
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .customJobTypeRequired) }
        p.customJobType = "Sauna"
        XCTAssertNoThrow(try p.validate())
    }

    func testProjectRejectsBadProgressNegativeContractEmptyName() {
        var p = baseProject(); p.manualProgress = 101
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .invalidProgress) }
        p = baseProject(); p.contractValue = Money(-1, .cad)
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .negativeAmount) }
        p = baseProject(); p.name = "   "
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .emptyName) }
        p = baseProject(); p.scopeFields = [ProjectScopeField(id: UUID(), companyId: company, projectId: project, fieldKey: "", valueText: "x", sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)]
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .emptyFieldKey) }
    }

    func testPaymentAmountMustBePositive() {
        let p = Payment(id: UUID(), companyId: company, projectId: project, scheduleItemId: nil, amount: Money(0, .cad),
                        paidOn: CalendarDate(storage: "2026-10-09")!, method: .cash, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .invalidPaymentAmount) }
    }

    func testLabourDaysMustBePositive() {
        let e = LabourEntry(id: UUID(), companyId: company, projectId: project, employeeId: employee, workDate: CalendarDate(storage: "2026-10-05")!,
                            days: 0, dailyRate: Money(250, .cad), notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertThrowsError(try e.validate()) { XCTAssertEqual($0 as? DomainError, .invalidLabourDays) }
        XCTAssertEqual(LabourEntry.cost(days: Decimal(string: "0.5")!, dailyRate: Money(Decimal(string: "250.01")!, .cad)).storageString, "125.01")
    }

    func testExpenseCostGroupResolution() throws {
        XCTAssertEqual(try Expense.resolveCostGroup(category: .toolPurchase, customCategory: nil), .equipment)
        let custom = CustomExpenseCategory(id: UUID(), companyId: company, name: "Scaffolding", costGroup: .equipment, createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertEqual(try Expense.resolveCostGroup(category: .custom, customCategory: custom), .equipment)
        XCTAssertThrowsError(try Expense.resolveCostGroup(category: .custom, customCategory: nil)) { XCTAssertEqual($0 as? DomainError, .customCategoryRequired) }
    }

    func testExpenseValidateChecksSnapshotAgainstMapping() {
        var e = Expense(id: UUID(), companyId: company, projectId: project, category: .materials, customCategoryId: nil, costGroup: .material,
                        vendorName: "Home Depot", amount: Money(100, .cad), tax: Money(13, .cad), spentOn: CalendarDate(storage: "2026-10-05")!,
                        paymentMethod: .creditCard, notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertNoThrow(try e.validate())
        XCTAssertEqual(try e.totalCost().storageString, "113.00")
        e.costGroup = .labour
        XCTAssertThrowsError(try e.validate()) { XCTAssertEqual($0 as? DomainError, .costGroupMismatch) }
        e.costGroup = .material; e.tax = Money(-1, .cad)
        XCTAssertThrowsError(try e.validate()) { XCTAssertEqual($0 as? DomainError, .negativeAmount) }
        e.tax = Money(0, .cad); e.category = .custom; e.customCategoryId = nil
        XCTAssertThrowsError(try e.validate()) { XCTAssertEqual($0 as? DomainError, .customCategoryRequired) }
    }

    func testIsDeleted() {
        var c = Customer(id: UUID(), companyId: company, name: "Ann", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertFalse(c.isDeleted)
        c.deletedAt = now
        XCTAssertTrue(c.isDeleted)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'Project' in scope`.

- [ ] **Step 3: Viết `DomainError` đầy đủ và `Common.swift`**

`DomainError.swift` (thay toàn bộ):

```swift
public enum DomainError: Error, Equatable, Sendable {
    case currencyMismatch
    case invalidPercentage
    case negativeAmount
    case invalidPaymentAmount
    case invalidProgress
    case invalidLabourDays
    case completionBeforeStart
    case customJobTypeRequired
    case customCategoryRequired
    case costGroupMismatch
    case categoryInUse
    case customerHasProjects
    case categoryHasExpenses
    case emptyName
    case emptyFieldKey
}
```

`Common.swift`:

```swift
import Foundation

public protocol Entity: Identifiable, Hashable, Sendable, Codable {
    var id: UUID { get }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

public protocol CompanyScoped: Entity {
    var companyId: UUID { get }
}

public extension Entity {
    var isDeleted: Bool { deletedAt != nil }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
```

- [ ] **Step 4: Viết các entity**

`Company.swift`:

```swift
import Foundation

public struct Company: Entity {
    public let id: UUID
    public var name: String
    public var currencyCode: CurrencyCode
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, name: String, currencyCode: CurrencyCode, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.name = name; self.currencyCode = currencyCode
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank { throw DomainError.emptyName }
    }
}
```

`User.swift`:

```swift
import Foundation

public struct User: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var displayName: String
    public var email: String?
    public var role: UserRole
    public var authUserId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, displayName: String, email: String?, role: UserRole, authUserId: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.displayName = displayName; self.email = email; self.role = role
        self.authUserId = authUserId; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if displayName.isBlank { throw DomainError.emptyName }
    }
}
```

`Customer.swift`:

```swift
import Foundation

public struct Customer: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var name: String
    public var phone: String?
    public var email: String?
    public var preferredContact: ContactMethod?
    public var companyName: String?
    public var secondaryContact: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, name: String, phone: String?, email: String?, preferredContact: ContactMethod?, companyName: String?, secondaryContact: String?, notes: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.name = name; self.phone = phone; self.email = email
        self.preferredContact = preferredContact; self.companyName = companyName; self.secondaryContact = secondaryContact
        self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank { throw DomainError.emptyName }
    }
}
```

`Project.swift`:

```swift
import Foundation

public struct Address: Hashable, Sendable, Codable {
    public var line: String
    public var unit: String?
    public var city: String?
    public var region: String?
    public var postalCode: String?

    public init(line: String, unit: String?, city: String?, region: String?, postalCode: String?) {
        self.line = line; self.unit = unit; self.city = city; self.region = region; self.postalCode = postalCode
    }
}

public struct ProjectScopeField: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var fieldKey: String
    public var valueText: String
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, fieldKey: String, valueText: String, sortOrder: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.fieldKey = fieldKey; self.valueText = valueText
        self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct Project: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var customerId: UUID
    public var name: String
    public var jobType: JobType
    public var customJobType: String?
    public var status: ProjectStatus
    public var address: Address
    public var scopeDescription: String?
    public var scopeFields: [ProjectScopeField]
    public var startDate: CalendarDate?
    public var estimatedCompletionDate: CalendarDate?
    public var workingDays: Int?
    public var hoursPerDay: Decimal?
    public var workersPerDay: Int?
    public var contractValue: Money
    /// 0...100; when set it overrides task-based progress.
    public var manualProgress: Int?
    public var depositRequiredToStart: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, customerId: UUID, name: String, jobType: JobType, customJobType: String?, status: ProjectStatus, address: Address, scopeDescription: String?, scopeFields: [ProjectScopeField], startDate: CalendarDate?, estimatedCompletionDate: CalendarDate?, workingDays: Int?, hoursPerDay: Decimal?, workersPerDay: Int?, contractValue: Money, manualProgress: Int?, depositRequiredToStart: Bool, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.customerId = customerId; self.name = name; self.jobType = jobType
        self.customJobType = customJobType; self.status = status; self.address = address; self.scopeDescription = scopeDescription
        self.scopeFields = scopeFields; self.startDate = startDate; self.estimatedCompletionDate = estimatedCompletionDate
        self.workingDays = workingDays; self.hoursPerDay = hoursPerDay; self.workersPerDay = workersPerDay
        self.contractValue = contractValue; self.manualProgress = manualProgress; self.depositRequiredToStart = depositRequiredToStart
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank || address.line.isBlank { throw DomainError.emptyName }
        if jobType == .other, (customJobType ?? "").isBlank { throw DomainError.customJobTypeRequired }
        if contractValue.isNegative { throw DomainError.negativeAmount }
        if let p = manualProgress, !(0...100).contains(p) { throw DomainError.invalidProgress }
        if let s = startDate, let e = estimatedCompletionDate, e < s { throw DomainError.completionBeforeStart }
        if scopeFields.contains(where: { $0.fieldKey.isBlank }) { throw DomainError.emptyFieldKey }
    }
}
```

`ProjectEstimateLine.swift`:

```swift
import Foundation

public struct ProjectEstimateLine: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var costGroup: CostGroup
    public var label: String
    public var amount: Money
    public var quantity: Decimal?
    public var unitRate: Money?
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, costGroup: CostGroup, label: String, amount: Money, quantity: Decimal?, unitRate: Money?, sortOrder: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.costGroup = costGroup; self.label = label
        self.amount = amount; self.quantity = quantity; self.unitRate = unitRate; self.sortOrder = sortOrder
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if amount.isNegative { throw DomainError.negativeAmount }
    }
}
```

`ProjectTask.swift`:

```swift
import Foundation

public struct TaskChecklistItem: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let taskId: UUID
    public var title: String
    public var isDone: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, taskId: UUID, title: String, isDone: Bool, sortOrder: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.taskId = taskId; self.title = title; self.isDone = isDone
        self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct ProjectTask: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var name: String
    public var status: TaskStatus
    public var startDate: CalendarDate?
    public var dueDate: CalendarDate?
    public var notes: String?
    public var sortOrder: Int
    /// Employee ids, stored in `task_assignees`.
    public var assignees: [UUID]
    public var checklist: [TaskChecklistItem]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, name: String, status: TaskStatus, startDate: CalendarDate?, dueDate: CalendarDate?, notes: String?, sortOrder: Int, assignees: [UUID], checklist: [TaskChecklistItem], createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.name = name; self.status = status
        self.startDate = startDate; self.dueDate = dueDate; self.notes = notes; self.sortOrder = sortOrder
        self.assignees = assignees; self.checklist = checklist; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct ProjectWorker: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public let employeeId: UUID
    public var workDate: CalendarDate
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, employeeId: UUID, workDate: CalendarDate, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.employeeId = employeeId; self.workDate = workDate
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
```

`Employee.swift`:

```swift
import Foundation

public struct Employee: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var name: String
    public var phone: String?
    public var role: String?
    public var trade: String?
    public var hourlyRate: Money?
    public var dailyRate: Money?
    public var certifications: String?
    public var emergencyContact: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, name: String, phone: String?, role: String?, trade: String?, hourlyRate: Money?, dailyRate: Money?, certifications: String?, emergencyContact: String?, notes: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.name = name; self.phone = phone; self.role = role; self.trade = trade
        self.hourlyRate = hourlyRate; self.dailyRate = dailyRate; self.certifications = certifications; self.emergencyContact = emergencyContact
        self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank { throw DomainError.emptyName }
        if hourlyRate?.isNegative == true || dailyRate?.isNegative == true { throw DomainError.negativeAmount }
    }
}
```

`PaymentScheduleItem.swift`:

```swift
import Foundation

public struct PaymentScheduleItem: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var label: String
    /// Authoritative payable value. `percentage` is only the generating input.
    public var amount: Money
    public var percentage: Percentage?
    public var dueDate: CalendarDate?
    public var triggerText: String?
    public var isDeposit: Bool
    public var notes: String?
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, label: String, amount: Money, percentage: Percentage?, dueDate: CalendarDate?, triggerText: String?, isDeposit: Bool, notes: String?, sortOrder: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.label = label; self.amount = amount
        self.percentage = percentage; self.dueDate = dueDate; self.triggerText = triggerText; self.isDeposit = isDeposit
        self.notes = notes; self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if amount.isNegative { throw DomainError.negativeAmount }
    }
}
```

`Payment.swift`:

```swift
import Foundation

public struct Payment: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    /// nil = unallocated: counts toward `collected`, not toward any schedule item.
    public var scheduleItemId: UUID?
    public var amount: Money
    public var paidOn: CalendarDate
    public var method: PaymentMethod
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, scheduleItemId: UUID?, amount: Money, paidOn: CalendarDate, method: PaymentMethod, notes: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.scheduleItemId = scheduleItemId; self.amount = amount
        self.paidOn = paidOn; self.method = method; self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if amount.isNegative || amount.isZero { throw DomainError.invalidPaymentAmount }
    }
}
```

`Expense.swift`:

```swift
import Foundation

public struct ReceiptImage: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let expenseId: UUID
    public var filePath: String
    public var remotePath: String?
    public var pageIndex: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, expenseId: UUID, filePath: String, remotePath: String?, pageIndex: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.expenseId = expenseId; self.filePath = filePath; self.remotePath = remotePath
        self.pageIndex = pageIndex; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct Expense: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var category: ExpenseCategory
    public var customCategoryId: UUID?
    /// Snapshot taken at creation (spec 5.2). Never re-derived later.
    public var costGroup: CostGroup
    public var vendorName: String?
    /// Pre-tax amount.
    public var amount: Money
    public var tax: Money
    public var spentOn: CalendarDate
    public var paymentMethod: PaymentMethod?
    public var notes: String?
    public var receiptImages: [ReceiptImage]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, category: ExpenseCategory, customCategoryId: UUID?, costGroup: CostGroup, vendorName: String?, amount: Money, tax: Money, spentOn: CalendarDate, paymentMethod: PaymentMethod?, notes: String?, receiptImages: [ReceiptImage], createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.category = category; self.customCategoryId = customCategoryId
        self.costGroup = costGroup; self.vendorName = vendorName; self.amount = amount; self.tax = tax; self.spentOn = spentOn
        self.paymentMethod = paymentMethod; self.notes = notes; self.receiptImages = receiptImages
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    /// The group to snapshot when creating an expense.
    public static func resolveCostGroup(category: ExpenseCategory, customCategory: CustomExpenseCategory?) throws -> CostGroup {
        if let group = category.defaultCostGroup { return group }
        guard let custom = customCategory else { throw DomainError.customCategoryRequired }
        return custom.costGroup
    }

    /// What the contractor actually paid: amount + tax.
    public func totalCost() throws -> Money { try amount.adding(tax) }

    public func validate() throws {
        if amount.isNegative || tax.isNegative { throw DomainError.negativeAmount }
        if category == .custom {
            if customCategoryId == nil { throw DomainError.customCategoryRequired }
        } else if let expected = category.defaultCostGroup, expected != costGroup {
            throw DomainError.costGroupMismatch
        }
    }
}
```

`CustomExpenseCategory.swift`:

```swift
import Foundation

public struct CustomExpenseCategory: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var name: String
    /// Immutable once any expense (even a deleted one) uses this category.
    public var costGroup: CostGroup
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, name: String, costGroup: CostGroup, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.name = name; self.costGroup = costGroup
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank { throw DomainError.emptyName }
    }
}
```

`LabourEntry.swift`:

```swift
import Foundation

public struct LabourEntry: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public let employeeId: UUID
    public var workDate: CalendarDate
    /// e.g. 0.5 for half a day. Must be > 0.
    public var days: Decimal
    /// Snapshot of the employee's rate at entry time.
    public var dailyRate: Money
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, employeeId: UUID, workDate: CalendarDate, days: Decimal, dailyRate: Money, notes: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.employeeId = employeeId; self.workDate = workDate
        self.days = days; self.dailyRate = dailyRate; self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public static func cost(days: Decimal, dailyRate: Money) -> Money { dailyRate.multiplied(by: days) }
    public var cost: Money { LabourEntry.cost(days: days, dailyRate: dailyRate) }

    public func validate() throws {
        if days <= 0 { throw DomainError.invalidLabourDays }
        if dailyRate.isNegative { throw DomainError.negativeAmount }
    }
}
```

`DailyLog.swift`:

```swift
import Foundation

public struct DailyLog: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var logDate: CalendarDate
    public var workersOnsite: Int?
    public var weather: String?
    public var workCompleted: String?
    public var materialDelivered: String?
    public var problems: String?
    public var tomorrowPlan: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, logDate: CalendarDate, workersOnsite: Int?, weather: String?, workCompleted: String?, materialDelivered: String?, problems: String?, tomorrowPlan: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.logDate = logDate; self.workersOnsite = workersOnsite
        self.weather = weather; self.workCompleted = workCompleted; self.materialDelivered = materialDelivered; self.problems = problems
        self.tomorrowPlan = tomorrowPlan; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
```

`Photo.swift`:

```swift
import Foundation

public struct Photo: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var dailyLogId: UUID?
    public var category: PhotoCategory
    public var takenAt: Date
    public var latitude: Double? // lint:allow-double (coordinates, not money)
    public var longitude: Double? // lint:allow-double (coordinates, not money)
    public var filePath: String
    public var remotePath: String?
    public var caption: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, dailyLogId: UUID?, category: PhotoCategory, takenAt: Date, latitude: Double?, longitude: Double?, filePath: String, remotePath: String?, caption: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) { // lint:allow-double
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.dailyLogId = dailyLogId; self.category = category
        self.takenAt = takenAt; self.latitude = latitude; self.longitude = longitude; self.filePath = filePath; self.remotePath = remotePath
        self.caption = caption; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
```

`ActivityLog.swift`:

```swift
import Foundation

/// Stable action codes; the UI renders a localized sentence from `action` + `details`.
public enum ActivityAction: String, Codable, Sendable, CaseIterable, Hashable {
    case projectCreated, projectDeleted, contractValueChanged, progressChanged, statusChanged
    case expenseAdded, paymentReceived
}

public struct ActivityLogEntry: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var userId: UUID?
    public var actorName: String
    public var action: ActivityAction
    public var entityType: String
    public var entityId: UUID
    public var projectId: UUID?
    /// JSON object text, e.g. {"from":"30000.00","to":"37500.00"}.
    public var detailsJSON: String
    public var occurredAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, userId: UUID?, actorName: String, action: ActivityAction, entityType: String, entityId: UUID, projectId: UUID?, detailsJSON: String, occurredAt: Date, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.userId = userId; self.actorName = actorName; self.action = action
        self.entityType = entityType; self.entityId = entityId; self.projectId = projectId; self.detailsJSON = detailsJSON
        self.occurredAt = occurredAt; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
```

`AppNotification.swift`:

```swift
import Foundation

public struct AppNotification: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var projectId: UUID?
    public var kind: String
    public var entityType: String?
    public var entityId: UUID?
    public var detailsJSON: String
    public var fireAt: Date
    public var readAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID?, kind: String, entityType: String?, entityId: UUID?, detailsJSON: String, fireAt: Date, readAt: Date?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.kind = kind; self.entityType = entityType
        self.entityId = entityId; self.detailsJSON = detailsJSON; self.fireAt = fireAt; self.readAt = readAt
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
```

- [ ] **Step 5: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass toàn bộ `ValidationTests`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add MVP entities with validation rules"
```

---

### Task 7: `FinancialCalculator`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Finance/FinancialInputs.swift`, `ProjectFinancials.swift`, `FinancialCalculator.swift`
- Test: `Packages/Domain/Tests/DomainTests/FinancialCalculatorTests.swift`

**Interfaces:**
- Produces:
  - `public struct FinancialInputs { project, estimateLines: [ProjectEstimateLine], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment], approvedChangeOrders: Money }`
  - `public struct ProjectFinancials` với `adjustedContract, actualByGroup: [CostGroup: Money], estimateByGroup: [CostGroup: Money]` (nhóm không có dòng thì **không có key**), `totalCost, estimatedCost, projectedProfit, spentSoFar, collected, outstandingBalance, cashPosition, actualProfit, projectedMargin: Percentage?, actualMargin: Percentage?, profitLabel: ProfitLabel`
  - `public enum ProfitLabel { actual, projectedAtCurrentSpending }`
  - `public enum FinancialCalculator { static func compute(_ inputs: FinancialInputs) throws -> ProjectFinancials }`

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class FinancialCalculatorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let company = UUID(), projectId = UUID(), customer = UUID(), employee = UUID()
    let day = CalendarDate(storage: "2026-10-05")!

    private func project(contract: Decimal, status: ProjectStatus = .inProgress) -> Project {
        Project(id: projectId, companyId: company, customerId: customer, name: "Basement", jobType: .basementRenovation, customJobType: nil, status: status,
                address: Address(line: "1 Main", unit: nil, city: nil, region: nil, postalCode: nil), scopeDescription: nil, scopeFields: [],
                startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil,
                contractValue: Money(contract, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    private func expense(_ category: ExpenseCategory, _ amount: Decimal, tax: Decimal = 0, deleted: Bool = false, group: CostGroup? = nil) -> Expense {
        Expense(id: UUID(), companyId: company, projectId: projectId, category: category, customCategoryId: category == .custom ? UUID() : nil,
                costGroup: group ?? category.defaultCostGroup!, vendorName: nil, amount: Money(amount, .cad), tax: Money(tax, .cad), spentOn: day,
                paymentMethod: nil, notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: deleted ? now : nil)
    }
    private func labour(_ days: Decimal, rate: Decimal) -> LabourEntry {
        LabourEntry(id: UUID(), companyId: company, projectId: projectId, employeeId: employee, workDate: day, days: days, dailyRate: Money(rate, .cad), notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    private func payment(_ amount: Decimal, item: UUID? = nil) -> Payment {
        Payment(id: UUID(), companyId: company, projectId: projectId, scheduleItemId: item, amount: Money(amount, .cad), paidOn: day, method: .eTransfer, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    private func estimate(_ group: CostGroup, _ amount: Decimal) -> ProjectEstimateLine {
        ProjectEstimateLine(id: UUID(), companyId: company, projectId: projectId, costGroup: group, label: "\(group)", amount: Money(amount, .cad), quantity: nil, unitRate: nil, sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)
    }

    func testSpecExample() throws {
        let inputs = FinancialInputs(project: project(contract: 30_000),
                                     estimateLines: [estimate(.material, 6_000), estimate(.labour, 8_000), estimate(.other, 4_000)],
                                     expenses: [expense(.materials, 6_000), expense(.delivery, 1_000)],
                                     labourEntries: [labour(30, rate: 250)],
                                     payments: [payment(5_000), payment(15_000)],
                                     approvedChangeOrders: Money.zero(.cad))
        let f = try FinancialCalculator.compute(inputs)
        XCTAssertEqual(f.totalCost.storageString, "14500.00")
        XCTAssertEqual(f.actualByGroup[.material]?.storageString, "6000.00")
        XCTAssertEqual(f.actualByGroup[.labour]?.storageString, "7500.00")
        XCTAssertEqual(f.actualByGroup[.other]?.storageString, "1000.00")
        XCTAssertEqual(f.actualByGroup[.permit]?.storageString, "0.00")
        XCTAssertEqual(f.estimatedCost.storageString, "18000.00")
        XCTAssertEqual(f.projectedProfit.storageString, "12000.00")
        XCTAssertEqual(f.projectedMargin?.points, 40)
        XCTAssertEqual(f.actualProfit.storageString, "15500.00")
        XCTAssertEqual(f.actualMargin?.points, Decimal(string: "51.7")!)
        XCTAssertEqual(f.collected.storageString, "20000.00")
        XCTAssertEqual(f.outstandingBalance.storageString, "10000.00")
        XCTAssertEqual(f.cashPosition.storageString, "5500.00")
        XCTAssertEqual(f.spentSoFar, f.totalCost)
        XCTAssertEqual(f.profitLabel, .projectedAtCurrentSpending)
    }

    func testExpenseCostIncludesTaxAndUsesSnapshotGroup() throws {
        let custom = expense(.custom, 100, tax: 13, group: .equipment)
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1_000), estimateLines: [], expenses: [custom], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
        XCTAssertEqual(f.actualByGroup[.equipment]?.storageString, "113.00")
        XCTAssertEqual(f.totalCost.storageString, "113.00")
    }

    func testSoftDeletedRecordsAreIgnored() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1_000), estimateLines: [], expenses: [expense(.materials, 100, deleted: true)], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
        XCTAssertEqual(f.totalCost.storageString, "0.00")
    }

    func testEstimateByGroupDistinguishesMissingFromZero() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1_000), estimateLines: [estimate(.material, 0)], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
        XCTAssertEqual(f.estimateByGroup[.material]?.storageString, "0.00")
        XCTAssertNil(f.estimateByGroup[.labour])
    }

    func testMarginNilWhenContractZero() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 0), estimateLines: [], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
        XCTAssertNil(f.projectedMargin)
        XCTAssertNil(f.actualMargin)
    }

    func testUnallocatedPaymentsCountTowardCollected() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1_000), estimateLines: [], expenses: [], labourEntries: [], payments: [payment(100, item: UUID()), payment(50, item: nil)], approvedChangeOrders: .zero(.cad)))
        XCTAssertEqual(f.collected.storageString, "150.00")
    }

    func testChangeOrdersAdjustContract() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 30_000), estimateLines: [], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: Money(7_500, .cad)))
        XCTAssertEqual(f.adjustedContract.storageString, "37500.00")
        XCTAssertEqual(f.outstandingBalance.storageString, "37500.00")
    }

    func testProfitLabelByStatus() throws {
        for status in [ProjectStatus.completed, .awaitingFinalPayment, .closed] {
            let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1, status: status), estimateLines: [], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
            XCTAssertEqual(f.profitLabel, .actual, "\(status)")
        }
        for status in [ProjectStatus.inProgress, .cancelled, .estimate] {
            let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1, status: status), estimateLines: [], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
            XCTAssertEqual(f.profitLabel, .projectedAtCurrentSpending, "\(status)")
        }
    }

    func testCurrencyMismatchThrows() {
        var usd = payment(10); usd.amount = Money(10, .usd)
        XCTAssertThrowsError(try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1), estimateLines: [], expenses: [], labourEntries: [], payments: [usd], approvedChangeOrders: .zero(.cad)))) {
            XCTAssertEqual($0 as? DomainError, .currencyMismatch)
        }
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'FinancialInputs' in scope`.

- [ ] **Step 3: Viết code**

`FinancialInputs.swift`:

```swift
public struct FinancialInputs: Sendable {
    public var project: Project
    public var estimateLines: [ProjectEstimateLine]
    public var expenses: [Expense]
    public var labourEntries: [LabourEntry]
    public var payments: [Payment]
    /// Always zero until change orders ship; kept in the formula so it never changes shape.
    public var approvedChangeOrders: Money

    public init(project: Project, estimateLines: [ProjectEstimateLine], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment], approvedChangeOrders: Money) {
        self.project = project; self.estimateLines = estimateLines; self.expenses = expenses
        self.labourEntries = labourEntries; self.payments = payments; self.approvedChangeOrders = approvedChangeOrders
    }
}
```

`ProjectFinancials.swift`:

```swift
public enum ProfitLabel: Sendable, Hashable { case actual, projectedAtCurrentSpending }

public struct ProjectFinancials: Sendable, Hashable {
    public let adjustedContract: Money
    /// Every CostGroup has a key (zero when nothing was spent).
    public let actualByGroup: [CostGroup: Money]
    /// Only groups that have at least one estimate line have a key.
    public let estimateByGroup: [CostGroup: Money]
    public let totalCost: Money
    public let estimatedCost: Money
    public let projectedProfit: Money
    public let spentSoFar: Money
    public let collected: Money
    public let outstandingBalance: Money
    public let cashPosition: Money
    public let actualProfit: Money
    public let projectedMargin: Percentage?
    public let actualMargin: Percentage?
    public let profitLabel: ProfitLabel
}
```

`FinancialCalculator.swift`:

```swift
import Foundation

public enum FinancialCalculator {
    public static func compute(_ inputs: FinancialInputs) throws -> ProjectFinancials {
        let currency = inputs.project.contractValue.currency
        let zero = Money.zero(currency)

        let expenses = inputs.expenses.filter { !$0.isDeleted }
        let labour = inputs.labourEntries.filter { !$0.isDeleted }
        let payments = inputs.payments.filter { !$0.isDeleted }
        let estimates = inputs.estimateLines.filter { !$0.isDeleted }

        var actualByGroup: [CostGroup: Money] = [:]
        for group in CostGroup.allCases { actualByGroup[group] = zero }
        for expense in expenses {
            actualByGroup[expense.costGroup] = try actualByGroup[expense.costGroup, default: zero].adding(expense.totalCost())
        }
        for entry in labour {
            actualByGroup[.labour] = try actualByGroup[.labour, default: zero].adding(entry.cost)
        }

        var estimateByGroup: [CostGroup: Money] = [:]
        for line in estimates {
            estimateByGroup[line.costGroup] = try estimateByGroup[line.costGroup, default: zero].adding(line.amount)
        }

        let totalCost = try Money.sum(CostGroup.allCases.map { actualByGroup[$0] ?? zero }, currency: currency)
        let estimatedCost = try Money.sum(estimates.map(\.amount), currency: currency)
        let adjustedContract = try inputs.project.contractValue.adding(inputs.approvedChangeOrders)
        let collected = try Money.sum(payments.map(\.amount), currency: currency)
        let projectedProfit = try adjustedContract.subtracting(estimatedCost)
        let actualProfit = try adjustedContract.subtracting(totalCost)

        let label: ProfitLabel = (inputs.project.status.phase == .workDone || inputs.project.status == .closed) ? .actual : .projectedAtCurrentSpending

        return ProjectFinancials(
            adjustedContract: adjustedContract,
            actualByGroup: actualByGroup,
            estimateByGroup: estimateByGroup,
            totalCost: totalCost,
            estimatedCost: estimatedCost,
            projectedProfit: projectedProfit,
            spentSoFar: totalCost,
            collected: collected,
            outstandingBalance: try adjustedContract.subtracting(collected),
            cashPosition: try collected.subtracting(totalCost),
            actualProfit: actualProfit,
            projectedMargin: Percentage.ratio(projectedProfit, over: adjustedContract),
            actualMargin: Percentage.ratio(actualProfit, over: adjustedContract),
            profitLabel: label
        )
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass. `testSpecExample` kiểm tra đúng số của yêu cầu gốc: 14,500 / 15,500 / 51.7%.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add FinancialCalculator with cost groups and margins"
```

---

### Task 8: `ProgressCalculator`, `PaymentAllocation`, `PaymentStatusResolver`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Progress/ProgressCalculator.swift`
- Create: `Packages/Domain/Sources/Domain/Payments/PaymentAllocation.swift`, `PaymentStatusResolver.swift`
- Test: `Packages/Domain/Tests/DomainTests/ProgressCalculatorTests.swift`, `PaymentStatusResolverTests.swift`

**Interfaces:**
- Produces:
  - `public enum ProgressCalculator { static func percent(tasks: [ProjectTask], manualProgress: Int?) -> Int }`
  - `public enum PaymentStatus: String, Sendable, Hashable, CaseIterable { upcoming, dueSoon, dueToday, overdue, partiallyPaid, paid }`
  - `public enum PaymentAllocation { static func paidForItem(_ itemId: UUID, payments: [Payment], currency: CurrencyCode) throws -> Money; static func collected(_ payments: [Payment], currency: CurrencyCode) throws -> Money }`
  - `public enum PaymentStatusResolver { static func status(item: PaymentScheduleItem, paidForItem: Money, today: CalendarDate) -> PaymentStatus }`

- [ ] **Step 1: Viết test fail**

`ProgressCalculatorTests.swift`:

```swift
import XCTest
@testable import Domain

final class ProgressCalculatorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func task(_ status: TaskStatus, deleted: Bool = false) -> ProjectTask {
        ProjectTask(id: UUID(), companyId: UUID(), projectId: UUID(), name: "t", status: status, startDate: nil, dueDate: nil, notes: nil, sortOrder: 0,
                    assignees: [], checklist: [], createdAt: now, updatedAt: now, deletedAt: deleted ? now : nil)
    }

    func testTaskBasedProgressRoundsHalfUp() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed), task(.completed), task(.inProgress), task(.notStarted), task(.blocked)], manualProgress: nil), 40)
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed), task(.notStarted), task(.notStarted)], manualProgress: nil), 33)
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed), task(.completed), task(.notStarted)], manualProgress: nil), 67)
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed)], manualProgress: nil), 100)
    }

    func testNoTasksIsZero() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [], manualProgress: nil), 0)
    }

    func testAllTasksDeletedIsZero() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed, deleted: true)], manualProgress: nil), 0)
    }

    func testDeletedTasksIgnored() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed), task(.notStarted, deleted: true)], manualProgress: nil), 100)
    }

    func testManualOverrideWins() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed)], manualProgress: 55), 55)
        XCTAssertEqual(ProgressCalculator.percent(tasks: [], manualProgress: 0), 0)
    }
}
```

`PaymentStatusResolverTests.swift`:

```swift
import XCTest
@testable import Domain

final class PaymentStatusResolverTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let company = UUID(), project = UUID()
    let due = CalendarDate(storage: "2026-10-10")!

    private func item(_ amount: Decimal, due: CalendarDate?) -> PaymentScheduleItem {
        PaymentScheduleItem(id: UUID(), companyId: company, projectId: project, label: "Deposit", amount: Money(amount, .cad), percentage: nil, dueDate: due,
                            triggerText: nil, isDeposit: true, notes: nil, sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    private func payment(_ amount: Decimal, item: UUID?, deleted: Bool = false) -> Payment {
        Payment(id: UUID(), companyId: company, projectId: project, scheduleItemId: item, amount: Money(amount, .cad), paidOn: due, method: .cash, notes: nil,
                createdAt: now, updatedAt: now, deletedAt: deleted ? now : nil)
    }
    private func status(_ i: PaymentScheduleItem, paid: Decimal, today: String) -> PaymentStatus {
        PaymentStatusResolver.status(item: i, paidForItem: Money(paid, .cad), today: CalendarDate(storage: today)!)
    }

    func testDateBoundaries() {
        let i = item(5_000, due: due)
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-06"), .upcoming)   // 4 days left
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-07"), .dueSoon)    // 3 days left
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-09"), .dueSoon)    // 1 day left
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-10"), .dueToday)
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-11"), .overdue)
    }

    func testPaidAndOverpaid() {
        let i = item(5_000, due: due)
        XCTAssertEqual(status(i, paid: 5_000, today: "2026-10-20"), .paid)
        XCTAssertEqual(status(i, paid: 6_000, today: "2026-10-20"), .paid)
    }

    func testPartialBeforeAndAfterDue() {
        let i = item(5_000, due: due)
        XCTAssertEqual(status(i, paid: 1_000, today: "2026-10-01"), .partiallyPaid)
        XCTAssertEqual(status(i, paid: 1_000, today: "2026-10-10"), .partiallyPaid) // partial beats dueToday
        XCTAssertEqual(status(i, paid: 1_000, today: "2026-10-11"), .overdue)       // overdue beats partial
    }

    func testNoDueDate() {
        let i = item(5_000, due: nil)
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-01"), .upcoming)
        XCTAssertEqual(status(i, paid: 10, today: "2026-10-01"), .partiallyPaid)
        XCTAssertEqual(status(i, paid: 5_000, today: "2026-10-01"), .paid)
    }

    func testZeroAmountIsAlwaysPaid() {
        XCTAssertEqual(status(item(0, due: due), paid: 0, today: "2026-12-01"), .paid)
    }

    func testAllocation() throws {
        let i = item(5_000, due: due)
        let other = UUID()
        let payments = [payment(1_000, item: i.id), payment(2_000, item: other), payment(500, item: nil), payment(700, item: i.id, deleted: true)]
        XCTAssertEqual(try PaymentAllocation.paidForItem(i.id, payments: payments, currency: .cad).storageString, "1000.00")
        XCTAssertEqual(try PaymentAllocation.collected(payments, currency: .cad).storageString, "3500.00")
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'ProgressCalculator' in scope`.

- [ ] **Step 3: Viết code**

`ProgressCalculator.swift`:

```swift
import Foundation

public enum ProgressCalculator {
    /// completed / total, rounded half-up to a whole percent. Manual progress overrides.
    public static func percent(tasks: [ProjectTask], manualProgress: Int?) -> Int {
        if let manual = manualProgress { return min(max(manual, 0), 100) }
        let live = tasks.filter { !$0.isDeleted }
        guard !live.isEmpty else { return 0 }
        let completed = live.filter { $0.status == .completed }.count
        let ratio = Decimal(completed) / Decimal(live.count) * 100
        return NSDecimalNumber(decimal: Money.rounded(ratio, scale: 0)).intValue
    }
}
```

`PaymentAllocation.swift`:

```swift
import Foundation

public enum PaymentAllocation {
    /// Payments explicitly allocated to the item. Unallocated payments never count here.
    public static func paidForItem(_ itemId: UUID, payments: [Payment], currency: CurrencyCode) throws -> Money {
        try Money.sum(payments.filter { !$0.isDeleted && $0.scheduleItemId == itemId }.map(\.amount), currency: currency)
    }

    /// Every live payment of the project, allocated or not.
    public static func collected(_ payments: [Payment], currency: CurrencyCode) throws -> Money {
        try Money.sum(payments.filter { !$0.isDeleted }.map(\.amount), currency: currency)
    }
}
```

`PaymentStatusResolver.swift`:

```swift
public enum PaymentStatus: String, Sendable, Hashable, CaseIterable {
    case upcoming, dueSoon, dueToday, overdue, partiallyPaid, paid
}

public enum PaymentStatusResolver {
    /// Spec 5.4 table, evaluated top to bottom; the first matching row wins.
    public static func status(item: PaymentScheduleItem, paidForItem: Money, today: CalendarDate) -> PaymentStatus {
        if paidForItem.amount >= item.amount.amount { return .paid }
        if let due = item.dueDate, today > due { return .overdue }
        if paidForItem.amount > 0 { return .partiallyPaid }
        guard let due = item.dueDate else { return .upcoming }
        let daysLeft = today.daysUntil(due)
        if daysLeft == 0 { return .dueToday }
        if (1...3).contains(daysLeft) { return .dueSoon }
        return .upcoming
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add progress and payment status rules"
```

---

### Task 9: `BudgetAlertRule`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Health/BudgetAlertRule.swift`
- Test: `Packages/Domain/Tests/DomainTests/BudgetAlertRuleTests.swift`

**Interfaces:**
- Produces:
  - `public enum BudgetAlertLevel { nearLimit, exceeded }`
  - `public struct BudgetAlert: Hashable, Sendable { group: CostGroup, level: BudgetAlertLevel, estimate: Money, actual: Money, overBy: Money?, percentUsed: Percentage? }`
  - `public enum BudgetAlertRule { static func alerts(for financials: ProjectFinancials) throws -> [BudgetAlert] }` (thứ tự theo `CostGroup.allCases`)

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class BudgetAlertRuleTests: XCTestCase {
    private func financials(estimate: [CostGroup: Decimal], actual: [CostGroup: Decimal]) -> ProjectFinancials {
        let zero = Money.zero(.cad)
        var actualMap: [CostGroup: Money] = [:]
        for g in CostGroup.allCases { actualMap[g] = Money(actual[g] ?? 0, .cad) }
        let estimateMap = estimate.mapValues { Money($0, .cad) }
        return ProjectFinancials(adjustedContract: zero, actualByGroup: actualMap, estimateByGroup: estimateMap, totalCost: zero, estimatedCost: zero,
                                 projectedProfit: zero, spentSoFar: zero, collected: zero, outstandingBalance: zero, cashPosition: zero, actualProfit: zero,
                                 projectedMargin: nil, actualMargin: nil, profitLabel: .projectedAtCurrentSpending)
    }

    func testThresholds() throws {
        XCTAssertEqual(try BudgetAlertRule.alerts(for: financials(estimate: [.material: 10_000], actual: [.material: 8_900])), [])
        let near = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 10_000], actual: [.material: 9_000]))
        XCTAssertEqual(near.count, 1)
        XCTAssertEqual(near[0].level, .nearLimit)
        XCTAssertEqual(near[0].percentUsed?.points, 90)
        XCTAssertNil(near[0].overBy)
        let full = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 10_000], actual: [.material: 10_000]))
        XCTAssertEqual(full[0].level, .nearLimit)
        XCTAssertEqual(full[0].percentUsed?.points, 100)
        let over = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 10_000], actual: [.material: 10_100]))
        XCTAssertEqual(over[0].level, .exceeded)
        XCTAssertEqual(over[0].overBy?.storageString, "100.00")
        XCTAssertEqual(over[0].percentUsed?.points, 101)
    }

    func testNoEstimateNoAlert() throws {
        XCTAssertEqual(try BudgetAlertRule.alerts(for: financials(estimate: [:], actual: [.material: 50_000])), [])
    }

    func testZeroActualNoAlert() throws {
        XCTAssertEqual(try BudgetAlertRule.alerts(for: financials(estimate: [.material: 0], actual: [:])), [])
        XCTAssertEqual(try BudgetAlertRule.alerts(for: financials(estimate: [.material: 100], actual: [:])), [])
    }

    func testZeroEstimateWithSpendIsExceeded() throws {
        let alerts = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 0], actual: [.material: 250]))
        XCTAssertEqual(alerts[0].level, .exceeded)
        XCTAssertEqual(alerts[0].overBy?.storageString, "250.00")
        XCTAssertNil(alerts[0].percentUsed)
    }

    func testBoundaryUsesExactDecimalComparison() throws {
        // 89.995 % would round to 90.0 but is below the threshold.
        let alerts = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 100_000], actual: [.material: Decimal(string: "89995")!]))
        XCTAssertEqual(alerts, [])
    }

    func testOrderFollowsCostGroupCases() throws {
        let alerts = try BudgetAlertRule.alerts(for: financials(estimate: [.other: 10, .material: 10], actual: [.other: 20, .material: 20]))
        XCTAssertEqual(alerts.map(\.group), [.material, .other])
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'BudgetAlertRule' in scope`.

- [ ] **Step 3: Viết code**

```swift
import Foundation

public enum BudgetAlertLevel: Sendable, Hashable { case nearLimit, exceeded }

public struct BudgetAlert: Hashable, Sendable {
    public let group: CostGroup
    public let level: BudgetAlertLevel
    public let estimate: Money
    public let actual: Money
    public let overBy: Money?
    public let percentUsed: Percentage?
}

public enum BudgetAlertRule {
    /// Spec 5.4 table. Compares with exact Decimal arithmetic, never with rounded percentages.
    public static func alerts(for financials: ProjectFinancials) throws -> [BudgetAlert] {
        var result: [BudgetAlert] = []
        for group in CostGroup.allCases {
            guard let estimate = financials.estimateByGroup[group] else { continue }
            guard let actual = financials.actualByGroup[group], !actual.isZero else { continue }
            if estimate.isZero {
                result.append(BudgetAlert(group: group, level: .exceeded, estimate: estimate, actual: actual, overBy: actual, percentUsed: nil))
                continue
            }
            let percentUsed = Percentage.ratio(actual, over: estimate)
            if actual.amount > estimate.amount {
                result.append(BudgetAlert(group: group, level: .exceeded, estimate: estimate, actual: actual, overBy: try actual.subtracting(estimate), percentUsed: percentUsed))
            } else if actual.amount * 100 >= estimate.amount * 90 {
                result.append(BudgetAlert(group: group, level: .nearLimit, estimate: estimate, actual: actual, overBy: nil, percentUsed: percentUsed))
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add budget alert rule per cost group"
```

---

### Task 10: `ProjectHealthEvaluator`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Health/ProjectHealthEvaluator.swift`
- Test: `Packages/Domain/Tests/DomainTests/ProjectHealthEvaluatorTests.swift`

**Interfaces:**
- Produces:
  - `public enum HealthStatus: Int, Comparable { onTrack = 0, atRisk, delayed, paymentRisk, overBudget }`
  - `public enum HealthReason: Hashable, Sendable { budgetExceeded(CostGroup, overBy: Money), paymentOverdue(count: Int), pastCompletionDate(daysLate: Int), budgetNearLimit(CostGroup, percentUsed: Percentage?), deadlineApproaching(daysLeft: Int, progress: Int) }`
  - `public struct ProjectHealth: Hashable, Sendable { status: HealthStatus, reasons: [HealthReason] }`
  - `public struct HealthInputs { status: ProjectStatus, estimatedCompletionDate: CalendarDate?, progress: Int, budgetAlerts: [BudgetAlert], paymentStatuses: [PaymentStatus], today: CalendarDate }`
  - `public enum ProjectHealthEvaluator { static func evaluate(_ inputs: HealthInputs) -> ProjectHealth? }` (nil cho phase `terminal`)

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
@testable import Domain

final class ProjectHealthEvaluatorTests: XCTestCase {
    let today = CalendarDate(storage: "2026-10-10")!
    private func alert(_ level: BudgetAlertLevel, group: CostGroup = .material) -> BudgetAlert {
        BudgetAlert(group: group, level: level, estimate: Money(100, .cad), actual: Money(level == .exceeded ? 125 : 92, .cad),
                    overBy: level == .exceeded ? Money(25, .cad) : nil, percentUsed: Percentage.computed(level == .exceeded ? 125 : 92))
    }
    private func inputs(_ status: ProjectStatus, completion: String? = "2026-10-20", progress: Int = 50, alerts: [BudgetAlert] = [], payments: [PaymentStatus] = []) -> HealthInputs {
        HealthInputs(status: status, estimatedCompletionDate: completion.flatMap { CalendarDate(storage: $0) }, progress: progress, budgetAlerts: alerts, paymentStatuses: payments, today: today)
    }

    func testOnTrack() {
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress)), ProjectHealth(status: .onTrack, reasons: []))
    }

    func testTerminalIsNil() {
        XCTAssertNil(ProjectHealthEvaluator.evaluate(inputs(.closed, alerts: [alert(.exceeded)])))
        XCTAssertNil(ProjectHealthEvaluator.evaluate(inputs(.cancelled, payments: [.overdue])))
    }

    func testDelayedOnlyInWork() {
        let late = ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-05"))
        XCTAssertEqual(late?.status, .delayed)
        XCTAssertEqual(late?.reasons, [.pastCompletionDate(daysLate: 5)])
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingFinalPayment, completion: "2026-10-05"))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.completed, completion: "2026-10-05"))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingDeposit, completion: "2026-10-05"))?.status, .onTrack)
    }

    func testDeadlineApproachingWindow() {
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-10", progress: 79))?.reasons, [.deadlineApproaching(daysLeft: 0, progress: 79)])
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-17", progress: 79))?.status, .atRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-18", progress: 79))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-17", progress: 80))?.status, .onTrack)
        // Already late: Delayed only, no "approaching" reason.
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-09", progress: 10))?.reasons, [.pastCompletionDate(daysLate: 1)])
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: nil, progress: 10))?.status, .onTrack)
    }

    func testBudgetSignalsByPhase() {
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, alerts: [alert(.exceeded)]))?.status, .overBudget)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.completed, alerts: [alert(.exceeded)]))?.status, .overBudget)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingDeposit, alerts: [alert(.exceeded)]))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, alerts: [alert(.nearLimit)]))?.status, .atRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingFinalPayment, alerts: [alert(.nearLimit)]))?.status, .atRisk)
    }

    func testPaymentRiskByPhase() {
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, payments: [.overdue, .paid]))?.status, .paymentRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, payments: [.overdue, .overdue]))?.reasons, [.paymentOverdue(count: 2)])
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingFinalPayment, payments: [.overdue]))?.status, .paymentRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingDeposit, payments: [.overdue]))?.status, .paymentRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.estimate, payments: [.overdue]))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingApproval, payments: [.overdue]))?.status, .onTrack)
    }

    func testSeverityOrderAndAllReasonsKept() {
        let h = ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-01", progress: 10, alerts: [alert(.nearLimit, group: .labour), alert(.exceeded)], payments: [.overdue]))
        XCTAssertEqual(h?.status, .overBudget)
        XCTAssertEqual(h?.reasons, [
            .budgetExceeded(.material, overBy: Money(25, .cad)),
            .paymentOverdue(count: 1),
            .pastCompletionDate(daysLate: 9),
            .budgetNearLimit(.labour, percentUsed: Percentage.computed(92)),
        ])
        let h2 = ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-01", payments: [.overdue]))
        XCTAssertEqual(h2?.status, .paymentRisk)
        XCTAssertEqual(h2?.reasons.count, 2)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Domain`
Expected: `cannot find 'HealthInputs' in scope`.

- [ ] **Step 3: Viết code**

```swift
import Foundation

public enum HealthStatus: Int, Comparable, Sendable, Hashable {
    case onTrack = 0, atRisk, delayed, paymentRisk, overBudget
    public static func < (lhs: HealthStatus, rhs: HealthStatus) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum HealthReason: Hashable, Sendable {
    case budgetExceeded(CostGroup, overBy: Money)
    case paymentOverdue(count: Int)
    case pastCompletionDate(daysLate: Int)
    case budgetNearLimit(CostGroup, percentUsed: Percentage?)
    case deadlineApproaching(daysLeft: Int, progress: Int)
}

public struct ProjectHealth: Hashable, Sendable {
    public let status: HealthStatus
    public let reasons: [HealthReason]
    public init(status: HealthStatus, reasons: [HealthReason]) { self.status = status; self.reasons = reasons }
}

public struct HealthInputs: Sendable {
    public var status: ProjectStatus
    public var estimatedCompletionDate: CalendarDate?
    public var progress: Int
    public var budgetAlerts: [BudgetAlert]
    public var paymentStatuses: [PaymentStatus]
    public var today: CalendarDate

    public init(status: ProjectStatus, estimatedCompletionDate: CalendarDate?, progress: Int, budgetAlerts: [BudgetAlert], paymentStatuses: [PaymentStatus], today: CalendarDate) {
        self.status = status; self.estimatedCompletionDate = estimatedCompletionDate; self.progress = progress
        self.budgetAlerts = budgetAlerts; self.paymentStatuses = paymentStatuses; self.today = today
    }
}

public enum ProjectHealthEvaluator {
    /// Spec 5.4 health table. Returns nil for terminal projects.
    public static func evaluate(_ inputs: HealthInputs) -> ProjectHealth? {
        let phase = inputs.status.phase
        guard phase != .terminal else { return nil }

        let budgetPhases: Set<ProjectPhase> = [.inWork, .workDone]
        let paymentApplies = phase != .preStart || inputs.status == .awaitingDeposit

        var exceeded: [HealthReason] = []
        var nearLimit: [HealthReason] = []
        if budgetPhases.contains(phase) {
            for alert in inputs.budgetAlerts {
                switch alert.level {
                case .exceeded: exceeded.append(.budgetExceeded(alert.group, overBy: alert.overBy ?? alert.actual))
                case .nearLimit: nearLimit.append(.budgetNearLimit(alert.group, percentUsed: alert.percentUsed))
                }
            }
        }

        var payment: [HealthReason] = []
        if paymentApplies {
            let overdue = inputs.paymentStatuses.filter { $0 == .overdue }.count
            if overdue > 0 { payment.append(.paymentOverdue(count: overdue)) }
        }

        var delayed: [HealthReason] = []
        var approaching: [HealthReason] = []
        if phase == .inWork, let completion = inputs.estimatedCompletionDate {
            let daysLeft = inputs.today.daysUntil(completion)
            if daysLeft < 0 {
                delayed.append(.pastCompletionDate(daysLate: -daysLeft))
            } else if (0...7).contains(daysLeft), inputs.progress < 80 {
                approaching.append(.deadlineApproaching(daysLeft: daysLeft, progress: inputs.progress))
            }
        }

        let reasons = exceeded + payment + delayed + nearLimit + approaching
        let status: HealthStatus
        if !exceeded.isEmpty { status = .overBudget }
        else if !payment.isEmpty { status = .paymentRisk }
        else if !delayed.isEmpty { status = .delayed }
        else if !nearLimit.isEmpty || !approaching.isEmpty { status = .atRisk }
        else { status = .onTrack }
        return ProjectHealth(status: status, reasons: reasons)
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Domain`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add rule-based project health evaluator"
```

---

### Task 11: Repository protocols + `ActivityActor`

**Files:**
- Create: `Packages/Domain/Sources/Domain/Repositories/ActivityActor.swift`, `CompanyRepository.swift`, `CustomerRepository.swift`, `ProjectRepository.swift`

**Interfaces:**
- Produces (Data hiện thực ở Task 13–14; Features dùng ở Task 20):

```swift
public struct ActivityActor: Sendable, Hashable {
    public let userId: UUID?
    public let name: String
    public init(userId: UUID?, name: String)
}

public struct CompanySetup: Sendable, Hashable {
    public let company: Company
    public let owner: User
}

public protocol CompanyRepository: Sendable {
    /// The single local company with its owner, or nil when setup has not completed.
    func current() async throws -> CompanySetup?
    func create(company: Company, owner: User) async throws
    func update(company: Company) async throws
}

public protocol CustomerRepository: Sendable {
    func get(id: UUID) async throws -> Customer?
    func list(companyId: UUID) async throws -> [Customer]
    func save(_ customer: Customer) async throws
    func softDelete(id: UUID, actor: ActivityActor) async throws
}

public struct ProjectSummary: Sendable, Hashable, Identifiable {
    public let project: Project
    public let customerName: String
    public var id: UUID { project.id }
}

public protocol ProjectRepository: Sendable {
    func get(id: UUID) async throws -> Project?
    func list(companyId: UUID) async throws -> [Project]
    /// Live, non-deleted projects with customer name, ordered by updatedAt desc. Emits on every change.
    func observeSummaries(companyId: UUID) -> AsyncThrowingStream<[ProjectSummary], Error>
    /// Insert or update, including scope fields; writes activity log rows for creation,
    /// contract value, status and manual progress changes, in the same transaction.
    func save(_ project: Project, actor: ActivityActor) async throws
    /// Cascading soft delete per spec A.2.
    func softDelete(id: UUID, actor: ActivityActor) async throws
}
```

- [ ] **Step 1: Viết bốn file đúng như khối trên** (mỗi struct/protocol vào file cùng tên; `CompanySetup` nằm trong `CompanyRepository.swift`, `ProjectSummary` trong `ProjectRepository.swift`; thêm `import Foundation` đầu mỗi file và `public init` memberwise cho `ActivityActor`, `CompanySetup`, `ProjectSummary`).

- [ ] **Step 2: Build + chạy toàn bộ Domain test**

Run: `swift build --package-path Packages/Domain && swift test --package-path Packages/Domain`
Expected: build sạch, mọi test pass.

- [ ] **Step 3: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): define repository protocols and activity actor"
```

---

### Task 12: Data package, `AppDatabase`, migration 001 theo Phụ lục A

**Files:**
- Create: `Packages/Data/Package.swift`
- Create: `Packages/Data/Sources/Data/Database/AppDatabase.swift`, `Clock.swift`, `Timestamps.swift`, `DataError.swift`
- Create: `Packages/Data/Sources/Data/Migrations/Migration001_InitialSchema.swift`
- Test: `Packages/Data/Tests/DataTests/SchemaTests.swift`, `ForeignKeyTests.swift`

**Interfaces:**
- Produces:
  - `public final class AppDatabase: Sendable { public let writer: any DatabaseWriter; static func onDisk(at: URL) throws -> AppDatabase; static func inMemory() throws -> AppDatabase }`
  - `public struct Clock: Sendable { var now: @Sendable () -> Date; var timeZone: TimeZone; static let system: Clock; static func fixed(_ date: Date) -> Clock }`
  - `enum Timestamps { static func string(_ date: Date) -> String; static func date(_ string: String) -> Date? }`
  - `public enum DataError: Error { corruptRow(table: String, id: String, column: String), notFound }`

- [ ] **Step 1: `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Data",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Data", targets: ["Data"])],
    dependencies: [
        .package(path: "../Domain"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "Data", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")], path: "Sources/Data"),
        .testTarget(name: "DataTests", dependencies: ["Data"], path: "Tests/DataTests"),
    ]
)
```

- [ ] **Step 2: Viết test schema fail**

`SchemaTests.swift`:

```swift
import XCTest
import GRDB
@testable import Data

final class SchemaTests: XCTestCase {
    func testMigrationCreatesAllTables() throws {
        let db = try AppDatabase.inMemory()
        let tables = try db.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY name")
        }
        XCTAssertEqual(tables, [
            "activity_log", "companies", "custom_expense_categories", "customers", "daily_logs", "employees", "expenses",
            "labour_entries", "notifications", "payment_schedule_items", "payments", "photos", "project_estimate_lines",
            "project_scope_fields", "project_tasks", "project_workers", "projects", "receipt_images", "task_assignees",
            "task_checklist_items", "users",
        ])
    }

    func testCommonColumnsOnEveryTable() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'")
            for table in tables {
                let columns = try db.columns(in: table).map(\.name)
                for required in ["id", "created_at", "updated_at", "deleted_at", "sync_state"] {
                    XCTAssertTrue(columns.contains(required), "\(table) missing \(required)")
                }
                if table == "companies" {
                    XCTAssertFalse(columns.contains("company_id"))
                } else {
                    XCTAssertTrue(columns.contains("company_id"), "\(table) missing company_id")
                }
            }
        }
    }

    func testPaymentsHaveCompositeForeignKeys() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.read { db in
            let fks = try db.foreignKeys(on: "payments")
            let toProjects = fks.first { $0.destinationTable == "projects" }
            XCTAssertEqual(toProjects?.mapping.map(\.origin), ["project_id", "company_id"])
            let toItems = fks.first { $0.destinationTable == "payment_schedule_items" }
            XCTAssertEqual(toItems?.mapping.map(\.origin), ["schedule_item_id", "project_id", "company_id"])
            let photoFks = try db.foreignKeys(on: "photos")
            XCTAssertEqual(photoFks.first { $0.destinationTable == "daily_logs" }?.mapping.map(\.origin), ["daily_log_id", "project_id", "company_id"])
        }
    }

    func testPartialUniqueIndexesAndFullFKTargets() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.read { db in
            let partial = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND sql LIKE '%WHERE deleted_at IS NULL%' ORDER BY name")
            XCTAssertEqual(partial, [
                "uq_custom_expense_categories_name", "uq_daily_logs_date", "uq_project_scope_fields_key", "uq_project_workers_day",
                "uq_receipt_images_page", "uq_task_assignees_pair", "uq_users_auth",
            ])
            // FK targets are full unique constraints (no WHERE).
            let projectsSQL = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'projects'") ?? ""
            XCTAssertTrue(projectsSQL.contains("UNIQUE (id, company_id)"))
            let itemsSQL = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'payment_schedule_items'") ?? ""
            XCTAssertTrue(itemsSQL.contains("UNIQUE (id, project_id, company_id)"))
        }
    }

    func testForeignKeysEnabled() throws {
        let db = try AppDatabase.inMemory()
        let enabled = try db.writer.read { try Bool.fetchOne($0, sql: "PRAGMA foreign_keys") }
        XCTAssertEqual(enabled, true)
    }

    func testTimestampsRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        let text = Timestamps.string(date)
        XCTAssertEqual(text, "2026-09-21T06:13:20.250Z")
        XCTAssertEqual(Timestamps.date(text), date)
        XCTAssertNil(Timestamps.date("yesterday"))
    }
}
```

`ForeignKeyTests.swift`:

```swift
import XCTest
import GRDB
@testable import Data

final class ForeignKeyTests: XCTestCase {
    var db: AppDatabase!
    let now = "2026-10-05T12:00:00.000Z"
    let companyA = "aaaaaaaa-0000-0000-0000-000000000001"
    let companyB = "bbbbbbbb-0000-0000-0000-000000000001"
    let customerA = "aaaaaaaa-0000-0000-0000-00000000c001"
    let projectA = "aaaaaaaa-0000-0000-0000-00000000a001"
    let projectA2 = "aaaaaaaa-0000-0000-0000-00000000a002"
    let itemA = "aaaaaaaa-0000-0000-0000-00000000e001"
    let logA = "aaaaaaaa-0000-0000-0000-00000000d001"

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        try db.writer.write { db in
            for (id, name) in [(companyA, "A"), (companyB, "B")] {
                try db.execute(sql: "INSERT INTO companies (id, name, currency_code, created_at, updated_at) VALUES (?, ?, 'CAD', ?, ?)", arguments: [id, name, now, now])
            }
            try db.execute(sql: "INSERT INTO customers (id, company_id, name, created_at, updated_at) VALUES (?, ?, 'Ann', ?, ?)", arguments: [customerA, companyA, now, now])
            for pid in [projectA, projectA2] {
                try db.execute(sql: """
                    INSERT INTO projects (id, company_id, customer_id, name, job_type, status, address_line, contract_value, deposit_required_to_start, created_at, updated_at)
                    VALUES (?, ?, ?, 'P', 'kitchen', 'inProgress', '1 Main', '0.00', 0, ?, ?)
                    """, arguments: [pid, companyA, customerA, now, now])
            }
            try db.execute(sql: "INSERT INTO payment_schedule_items (id, company_id, project_id, label, amount, is_deposit, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'Deposit', '100.00', 1, 0, ?, ?)", arguments: [itemA, companyA, projectA, now, now])
            try db.execute(sql: "INSERT INTO daily_logs (id, company_id, project_id, log_date, created_at, updated_at) VALUES (?, ?, ?, '2026-10-05', ?, ?)", arguments: [logA, companyA, projectA, now, now])
        }
    }

    private func assertForeignKeyFailure(_ body: @escaping (Database) throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try db.writer.write(body), file: file, line: line) { error in
            XCTAssertEqual((error as? DatabaseError)?.extendedResultCode, .SQLITE_CONSTRAINT_FOREIGNKEY, "\(error)", file: file, line: line)
        }
    }

    func testCrossCompanyProjectReferenceRejected() {
        assertForeignKeyFailure { db in
            try db.execute(sql: "INSERT INTO project_tasks (id, company_id, project_id, name, status, sort_order, created_at, updated_at) VALUES ('t1', ?, ?, 'Framing', 'notStarted', 0, ?, ?)",
                           arguments: [self.companyB, self.projectA, self.now, self.now])
        }
    }

    func testCrossProjectScheduleItemRejectedAndNullAccepted() throws {
        assertForeignKeyFailure { db in
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES ('p1', ?, ?, ?, '50.00', '2026-10-05', 'cash', ?, ?)",
                           arguments: [self.companyA, self.projectA2, self.itemA, self.now, self.now])
        }
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES ('p2', ?, ?, NULL, '50.00', '2026-10-05', 'cash', ?, ?)",
                           arguments: [self.companyA, self.projectA2, self.now, self.now])
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES ('p3', ?, ?, ?, '50.00', '2026-10-05', 'cash', ?, ?)",
                           arguments: [self.companyA, self.projectA, self.itemA, self.now, self.now])
        }
    }

    func testCrossProjectDailyLogRejectedAndNullAccepted() throws {
        assertForeignKeyFailure { db in
            try db.execute(sql: "INSERT INTO photos (id, company_id, project_id, daily_log_id, category, taken_at, file_path, created_at, updated_at) VALUES ('ph1', ?, ?, ?, 'progress', ?, 'a.jpg', ?, ?)",
                           arguments: [self.companyA, self.projectA2, self.logA, self.now, self.now, self.now])
        }
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO photos (id, company_id, project_id, daily_log_id, category, taken_at, file_path, created_at, updated_at) VALUES ('ph2', ?, ?, NULL, 'progress', ?, 'b.jpg', ?, ?)",
                           arguments: [self.companyA, self.projectA2, self.now, self.now, self.now])
        }
    }

    func testCheckConstraintsRejectUnknownEnumValues() {
        XCTAssertThrowsError(try db.writer.write { db in
            try db.execute(sql: "UPDATE projects SET job_type = 'sauna' WHERE id = ?", arguments: [self.projectA])
        }) { XCTAssertEqual(($0 as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT) }
        XCTAssertThrowsError(try db.writer.write { db in
            try db.execute(sql: "INSERT INTO expenses (id, company_id, project_id, category, cost_group, amount, tax, spent_on, created_at, updated_at) VALUES ('e1', ?, ?, 'materials', 'snacks', '1.00', '0.00', '2026-10-05', ?, ?)",
                           arguments: [self.companyA, self.projectA, self.now, self.now])
        }) { XCTAssertEqual(($0 as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT) }
    }

    func testPartialUniqueAllowsReuseAfterSoftDelete() throws {
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO custom_expense_categories (id, company_id, name, cost_group, created_at, updated_at, deleted_at) VALUES ('c1', ?, 'Scaffolding', 'equipment', ?, ?, ?)", arguments: [self.companyA, self.now, self.now, self.now])
            try db.execute(sql: "INSERT INTO custom_expense_categories (id, company_id, name, cost_group, created_at, updated_at) VALUES ('c2', ?, 'Scaffolding', 'equipment', ?, ?)", arguments: [self.companyA, self.now, self.now])
        }
        XCTAssertThrowsError(try db.writer.write { db in
            try db.execute(sql: "INSERT INTO custom_expense_categories (id, company_id, name, cost_group, created_at, updated_at) VALUES ('c3', ?, 'Scaffolding', 'equipment', ?, ?)", arguments: [self.companyA, self.now, self.now])
        })
    }
}
```

- [ ] **Step 3: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Data` (trên macOS; trên Windows/Linux GRDB không build, chỉ chạy được qua CI `ios.yml` ở Task 21 — khi đó chạy bước này bằng cách push lên nhánh và xem CI)
Expected: lỗi biên dịch `cannot find 'AppDatabase' in scope`.

- [ ] **Step 4: Viết `DataError`, `Clock`, `Timestamps`, `AppDatabase`**

`DataError.swift`:

```swift
public enum DataError: Error, Equatable {
    case corruptRow(table: String, id: String, column: String)
    case notFound
}
```

`Clock.swift`:

```swift
import Foundation

public struct Clock: Sendable {
    public var now: @Sendable () -> Date
    public var timeZone: TimeZone

    public init(now: @escaping @Sendable () -> Date, timeZone: TimeZone) {
        self.now = now; self.timeZone = timeZone
    }

    public static let system = Clock(now: { Date() }, timeZone: .current)
    public static func fixed(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Clock {
        Clock(now: { date }, timeZone: timeZone)
    }
}
```

`Timestamps.swift`:

```swift
import Foundation

enum Timestamps {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ string: String) -> Date? { formatter.date(from: string) }
}
```

`AppDatabase.swift`:

```swift
import Foundation
import GRDB

public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try AppDatabase.migrator.migrate(writer)
    }

    public static func onDisk(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        return try AppDatabase(DatabasePool(path: url.path, configuration: configuration))
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return config
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("001_initial_schema") { db in
            try Migration001_InitialSchema.apply(db)
        }
        return migrator
    }
}
```

- [ ] **Step 5: Viết migration 001**

`Migration001_InitialSchema.swift` — SQL theo Phụ lục A. `common` là cột chung; `enumList` sinh danh sách CHECK từ enum của Domain để không lệch raw value.

```swift
import Foundation
import GRDB
import Domain

enum Migration001_InitialSchema {
    private static let common = """
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_state TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced')),
        """

    private static func enumList<T: RawRepresentable & CaseIterable>(_ type: T.Type) -> String where T.RawValue == String {
        type.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
    }

    private static func fk(_ column: String, _ table: String) -> String {
        "FOREIGN KEY (\(column), company_id) REFERENCES \(table)(id, company_id) ON DELETE RESTRICT"
    }

    private static func projectScopedFK(_ column: String, _ table: String) -> String {
        "FOREIGN KEY (\(column), project_id, company_id) REFERENCES \(table)(id, project_id, company_id) ON DELETE RESTRICT"
    }

    static func apply(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE companies (
                id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                sync_state TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced')),
                name TEXT NOT NULL,
                currency_code TEXT NOT NULL CHECK (currency_code IN (\(enumList(CurrencyCode.self))))
            );

            CREATE TABLE users (
                \(common)
                display_name TEXT NOT NULL,
                email TEXT,
                role TEXT NOT NULL DEFAULT 'owner' CHECK (role IN (\(enumList(UserRole.self)))),
                auth_user_id TEXT,
                UNIQUE (id, company_id)
            );
            CREATE INDEX idx_users_company ON users(company_id);
            CREATE UNIQUE INDEX uq_users_auth ON users(auth_user_id) WHERE auth_user_id IS NOT NULL AND deleted_at IS NULL;

            CREATE TABLE customers (
                \(common)
                name TEXT NOT NULL,
                phone TEXT,
                email TEXT,
                preferred_contact TEXT CHECK (preferred_contact IN (\(enumList(ContactMethod.self)))),
                company_name TEXT,
                secondary_contact TEXT,
                notes TEXT,
                UNIQUE (id, company_id)
            );
            CREATE INDEX idx_customers_company ON customers(company_id);
            CREATE INDEX idx_customers_company_name ON customers(company_id, name);

            CREATE TABLE projects (
                \(common)
                customer_id TEXT NOT NULL,
                name TEXT NOT NULL,
                job_type TEXT NOT NULL CHECK (job_type IN (\(enumList(JobType.self)))),
                custom_job_type TEXT,
                status TEXT NOT NULL CHECK (status IN (\(enumList(ProjectStatus.self)))),
                address_line TEXT NOT NULL,
                unit TEXT,
                city TEXT,
                region TEXT,
                postal_code TEXT,
                scope_description TEXT,
                start_date TEXT,
                estimated_completion_date TEXT,
                working_days INTEGER,
                hours_per_day TEXT,
                workers_per_day INTEGER,
                contract_value TEXT NOT NULL DEFAULT '0.00',
                manual_progress INTEGER CHECK (manual_progress BETWEEN 0 AND 100),
                deposit_required_to_start INTEGER NOT NULL DEFAULT 0,
                UNIQUE (id, company_id),
                \(fk("customer_id", "customers"))
            );
            CREATE INDEX idx_projects_company ON projects(company_id);
            CREATE INDEX idx_projects_company_status ON projects(company_id, status);
            CREATE INDEX idx_projects_customer ON projects(customer_id);

            CREATE TABLE project_scope_fields (
                \(common)
                project_id TEXT NOT NULL,
                field_key TEXT NOT NULL CHECK (length(field_key) > 0),
                value_text TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_project_scope_fields_company ON project_scope_fields(company_id);
            CREATE INDEX idx_project_scope_fields_project ON project_scope_fields(project_id);
            CREATE UNIQUE INDEX uq_project_scope_fields_key ON project_scope_fields(project_id, field_key) WHERE deleted_at IS NULL;

            CREATE TABLE project_estimate_lines (
                \(common)
                project_id TEXT NOT NULL,
                cost_group TEXT NOT NULL CHECK (cost_group IN (\(enumList(CostGroup.self)))),
                label TEXT NOT NULL,
                amount TEXT NOT NULL,
                quantity TEXT,
                unit_rate TEXT,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_project_estimate_lines_company ON project_estimate_lines(company_id);
            CREATE INDEX idx_project_estimate_lines_project_group ON project_estimate_lines(project_id, cost_group);

            CREATE TABLE employees (
                \(common)
                name TEXT NOT NULL,
                phone TEXT,
                role TEXT,
                trade TEXT,
                hourly_rate TEXT,
                daily_rate TEXT,
                certifications TEXT,
                emergency_contact TEXT,
                notes TEXT,
                UNIQUE (id, company_id)
            );
            CREATE INDEX idx_employees_company ON employees(company_id);
            CREATE INDEX idx_employees_company_name ON employees(company_id, name);

            CREATE TABLE project_tasks (
                \(common)
                project_id TEXT NOT NULL,
                name TEXT NOT NULL,
                status TEXT NOT NULL CHECK (status IN (\(enumList(TaskStatus.self)))),
                start_date TEXT,
                due_date TEXT,
                notes TEXT,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_project_tasks_company ON project_tasks(company_id);
            CREATE INDEX idx_project_tasks_project_order ON project_tasks(project_id, sort_order);
            CREATE INDEX idx_project_tasks_company_due ON project_tasks(company_id, due_date);

            CREATE TABLE task_checklist_items (
                \(common)
                task_id TEXT NOT NULL,
                title TEXT NOT NULL,
                is_done INTEGER NOT NULL DEFAULT 0,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("task_id", "project_tasks"))
            );
            CREATE INDEX idx_task_checklist_items_company ON task_checklist_items(company_id);
            CREATE INDEX idx_task_checklist_items_task ON task_checklist_items(task_id);

            CREATE TABLE task_assignees (
                \(common)
                task_id TEXT NOT NULL,
                employee_id TEXT NOT NULL,
                UNIQUE (id, company_id),
                \(fk("task_id", "project_tasks")),
                \(fk("employee_id", "employees"))
            );
            CREATE INDEX idx_task_assignees_company ON task_assignees(company_id);
            CREATE INDEX idx_task_assignees_task ON task_assignees(task_id);
            CREATE INDEX idx_task_assignees_employee ON task_assignees(employee_id);
            CREATE UNIQUE INDEX uq_task_assignees_pair ON task_assignees(task_id, employee_id) WHERE deleted_at IS NULL;

            CREATE TABLE project_workers (
                \(common)
                project_id TEXT NOT NULL,
                employee_id TEXT NOT NULL,
                work_date TEXT NOT NULL,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects")),
                \(fk("employee_id", "employees"))
            );
            CREATE INDEX idx_project_workers_company ON project_workers(company_id);
            CREATE INDEX idx_project_workers_project ON project_workers(project_id);
            CREATE INDEX idx_project_workers_employee ON project_workers(employee_id);
            CREATE INDEX idx_project_workers_company_date ON project_workers(company_id, work_date);
            CREATE UNIQUE INDEX uq_project_workers_day ON project_workers(project_id, employee_id, work_date) WHERE deleted_at IS NULL;

            CREATE TABLE payment_schedule_items (
                \(common)
                project_id TEXT NOT NULL,
                label TEXT NOT NULL,
                amount TEXT NOT NULL,
                percentage TEXT,
                due_date TEXT,
                trigger_text TEXT,
                is_deposit INTEGER NOT NULL DEFAULT 0,
                notes TEXT,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                UNIQUE (id, project_id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_payment_schedule_items_company ON payment_schedule_items(company_id);
            CREATE INDEX idx_payment_schedule_items_project_order ON payment_schedule_items(project_id, sort_order);
            CREATE INDEX idx_payment_schedule_items_company_due ON payment_schedule_items(company_id, due_date);

            CREATE TABLE payments (
                \(common)
                project_id TEXT NOT NULL,
                schedule_item_id TEXT,
                amount TEXT NOT NULL,
                paid_on TEXT NOT NULL,
                method TEXT NOT NULL CHECK (method IN (\(enumList(PaymentMethod.self)))),
                notes TEXT,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects")),
                \(projectScopedFK("schedule_item_id", "payment_schedule_items"))
            );
            CREATE INDEX idx_payments_company ON payments(company_id);
            CREATE INDEX idx_payments_project_date ON payments(project_id, paid_on);
            CREATE INDEX idx_payments_schedule_item ON payments(schedule_item_id);

            CREATE TABLE custom_expense_categories (
                \(common)
                name TEXT NOT NULL,
                cost_group TEXT NOT NULL DEFAULT 'other' CHECK (cost_group IN (\(enumList(CostGroup.self)))),
                UNIQUE (id, company_id)
            );
            CREATE INDEX idx_custom_expense_categories_company ON custom_expense_categories(company_id);
            CREATE UNIQUE INDEX uq_custom_expense_categories_name ON custom_expense_categories(company_id, name) WHERE deleted_at IS NULL;

            CREATE TABLE expenses (
                \(common)
                project_id TEXT NOT NULL,
                category TEXT NOT NULL CHECK (category IN (\(enumList(ExpenseCategory.self)))),
                custom_category_id TEXT,
                cost_group TEXT NOT NULL CHECK (cost_group IN (\(enumList(CostGroup.self)))),
                vendor_name TEXT,
                amount TEXT NOT NULL,
                tax TEXT NOT NULL DEFAULT '0.00',
                spent_on TEXT NOT NULL,
                payment_method TEXT CHECK (payment_method IN (\(enumList(PaymentMethod.self)))),
                notes TEXT,
                UNIQUE (id, company_id),
                CHECK ((category = 'custom') = (custom_category_id IS NOT NULL)),
                \(fk("project_id", "projects")),
                \(fk("custom_category_id", "custom_expense_categories"))
            );
            CREATE INDEX idx_expenses_company ON expenses(company_id);
            CREATE INDEX idx_expenses_project_date ON expenses(project_id, spent_on);
            CREATE INDEX idx_expenses_company_date ON expenses(company_id, spent_on);
            CREATE INDEX idx_expenses_custom_category ON expenses(custom_category_id);

            CREATE TABLE receipt_images (
                \(common)
                expense_id TEXT NOT NULL,
                file_path TEXT NOT NULL,
                remote_path TEXT,
                page_index INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("expense_id", "expenses"))
            );
            CREATE INDEX idx_receipt_images_company ON receipt_images(company_id);
            CREATE INDEX idx_receipt_images_expense ON receipt_images(expense_id);
            CREATE UNIQUE INDEX uq_receipt_images_page ON receipt_images(expense_id, page_index) WHERE deleted_at IS NULL;

            CREATE TABLE labour_entries (
                \(common)
                project_id TEXT NOT NULL,
                employee_id TEXT NOT NULL,
                work_date TEXT NOT NULL,
                days TEXT NOT NULL,
                daily_rate TEXT NOT NULL,
                notes TEXT,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects")),
                \(fk("employee_id", "employees"))
            );
            CREATE INDEX idx_labour_entries_company ON labour_entries(company_id);
            CREATE INDEX idx_labour_entries_project_date ON labour_entries(project_id, work_date);
            CREATE INDEX idx_labour_entries_employee_date ON labour_entries(employee_id, work_date);

            CREATE TABLE daily_logs (
                \(common)
                project_id TEXT NOT NULL,
                log_date TEXT NOT NULL,
                workers_onsite INTEGER,
                weather TEXT,
                work_completed TEXT,
                material_delivered TEXT,
                problems TEXT,
                tomorrow_plan TEXT,
                UNIQUE (id, company_id),
                UNIQUE (id, project_id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_daily_logs_company ON daily_logs(company_id);
            CREATE INDEX idx_daily_logs_project ON daily_logs(project_id);
            CREATE UNIQUE INDEX uq_daily_logs_date ON daily_logs(project_id, log_date) WHERE deleted_at IS NULL;

            CREATE TABLE photos (
                \(common)
                project_id TEXT NOT NULL,
                daily_log_id TEXT,
                category TEXT NOT NULL CHECK (category IN (\(enumList(PhotoCategory.self)))),
                taken_at TEXT NOT NULL,
                latitude REAL,
                longitude REAL,
                file_path TEXT NOT NULL,
                remote_path TEXT,
                caption TEXT,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects")),
                \(projectScopedFK("daily_log_id", "daily_logs"))
            );
            CREATE INDEX idx_photos_company ON photos(company_id);
            CREATE INDEX idx_photos_project_taken ON photos(project_id, taken_at);
            CREATE INDEX idx_photos_daily_log ON photos(daily_log_id);

            CREATE TABLE activity_log (
                \(common)
                user_id TEXT,
                actor_name TEXT NOT NULL,
                action TEXT NOT NULL,
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                project_id TEXT,
                details_json TEXT NOT NULL,
                occurred_at TEXT NOT NULL,
                UNIQUE (id, company_id),
                \(fk("user_id", "users")),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_activity_log_company ON activity_log(company_id);
            CREATE INDEX idx_activity_log_project_time ON activity_log(project_id, occurred_at);
            CREATE INDEX idx_activity_log_company_time ON activity_log(company_id, occurred_at);
            CREATE INDEX idx_activity_log_user ON activity_log(user_id);

            CREATE TABLE notifications (
                \(common)
                project_id TEXT,
                kind TEXT NOT NULL,
                entity_type TEXT,
                entity_id TEXT,
                details_json TEXT NOT NULL,
                fire_at TEXT NOT NULL,
                read_at TEXT,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_notifications_company ON notifications(company_id);
            CREATE INDEX idx_notifications_company_fire ON notifications(company_id, fire_at);
            CREATE INDEX idx_notifications_project ON notifications(project_id);
            """)
    }
}
```

- [ ] **Step 6: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Data`
Expected: pass toàn bộ `SchemaTests` và `ForeignKeyTests`. Lỗi hay gặp: `testPartialUniqueIndexesAndFullFKTargets` so chuỗi `UNIQUE (id, company_id)` — giữ đúng khoảng trắng như trong SQL trên.

- [ ] **Step 7: Commit**

```bash
git add Packages/Data
git commit -m "feat(data): add GRDB database with initial schema per spec appendix A"
```

---

### Task 13: Records + `GRDBCompanyRepository` + `GRDBCustomerRepository`

**Files:**
- Create: `Packages/Data/Sources/Data/Records/CompanyRecord.swift`, `UserRecord.swift`, `CustomerRecord.swift`, `ActivityLogRecord.swift`, `RecordSupport.swift`
- Create: `Packages/Data/Sources/Data/Repositories/GRDBCompanyRepository.swift`, `GRDBCustomerRepository.swift`
- Test: `Packages/Data/Tests/DataTests/CompanyRepositoryTests.swift`, `CustomerRepositoryTests.swift`

**Interfaces:**
- Consumes: `CompanyRepository`, `CustomerRepository`, `ActivityActor`, entity từ Domain; `AppDatabase`, `Clock`, `Timestamps`, `DataError`.
- Produces:
  - `public final class GRDBCompanyRepository: CompanyRepository { public init(database: AppDatabase, clock: Clock) }`
  - `public final class GRDBCustomerRepository: CustomerRepository { public init(database: AppDatabase, clock: Clock) }`
  - `enum RecordSupport { static func uuid(_: String, table:, id:, column:) throws -> UUID; static func money(_: String, currency:, table:, id:, column:) throws -> Money; static func date(_: String, ...) throws -> Date; static func calendarDate(_: String?, ...) throws -> CalendarDate? }`
  - `struct ActivityLogRecord` + `static func append(_ db: Database, companyId: UUID, actor: ActivityActor, action: ActivityAction, entityType: String, entityId: UUID, projectId: UUID?, details: [String: String], at now: Date) throws` (append-only, gọi trong transaction của repository)

- [ ] **Step 1: Viết test fail**

`CompanyRepositoryTests.swift`:

```swift
import XCTest
import GRDB
import Domain
@testable import Data

final class CompanyRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func makeCompany(_ id: UUID = UUID()) -> Company { Company(id: id, name: "Northwind Contracting", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil) }
    func makeOwner(_ companyId: UUID) -> User { User(id: UUID(), companyId: companyId, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil) }

    func testCurrentIsNilBeforeSetup() async throws {
        let repo = GRDBCompanyRepository(database: try AppDatabase.inMemory(), clock: .fixed(now))
        let current = try await repo.current()
        XCTAssertNil(current)
    }

    func testCreateThenCurrentRoundTrips() async throws {
        let repo = GRDBCompanyRepository(database: try AppDatabase.inMemory(), clock: .fixed(now))
        let company = makeCompany(), owner = makeOwner(company.id)
        try await repo.create(company: company, owner: owner)
        let current = try await repo.current()
        XCTAssertEqual(current?.company, company)
        XCTAssertEqual(current?.owner, owner)
    }

    func testCurrentIsNilWhenCompanyExistsWithoutOwner() async throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO companies (id, name, currency_code, created_at, updated_at) VALUES (?, 'X', 'CAD', ?, ?)", arguments: [UUID().uuidString.lowercased(), "2026-01-01T00:00:00.000Z", "2026-01-01T00:00:00.000Z"])
        }
        let repo = GRDBCompanyRepository(database: db, clock: .fixed(now))
        let current = try await repo.current()
        XCTAssertNil(current)
    }

    func testCreateRejectsBlankName() async throws {
        let repo = GRDBCompanyRepository(database: try AppDatabase.inMemory(), clock: .fixed(now))
        var company = makeCompany(); company.name = " "
        do { try await repo.create(company: company, owner: makeOwner(company.id)); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? DomainError, .emptyName) }
    }

    func testUpdateChangesNameAndTimestamp() async throws {
        let later = now.addingTimeInterval(60)
        let repo = GRDBCompanyRepository(database: try AppDatabase.inMemory(), clock: .fixed(later))
        var company = makeCompany(); try await repo.create(company: company, owner: makeOwner(company.id))
        company.name = "Northwind Builders"
        try await repo.update(company: company)
        let current = try await repo.current()
        XCTAssertEqual(current?.company.name, "Northwind Builders")
        XCTAssertEqual(current?.company.updatedAt, later)
    }
}
```

`CustomerRepositoryTests.swift`:

```swift
import XCTest
import GRDB
import Domain
@testable import Data

final class CustomerRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!
    var companyId: UUID!
    var actor: ActivityActor!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
        companyId = company.id
        actor = ActivityActor(userId: owner.id, name: owner.displayName)
    }

    func customer(_ name: String) -> Customer {
        Customer(id: UUID(), companyId: companyId, name: name, phone: "416", email: nil, preferredContact: .text, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }

    func testSaveListGetRoundTrip() async throws {
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        let ann = customer("Ann"), bob = customer("Bob")
        try await repo.save(bob); try await repo.save(ann)
        let listed = try await repo.list(companyId: companyId)
        XCTAssertEqual(listed.map(\.name), ["Ann", "Bob"])
        let fetched = try await repo.get(id: ann.id)
        XCTAssertEqual(fetched, ann)
    }

    func testSoftDeleteHidesFromListAndKeepsRow() async throws {
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        let ann = customer("Ann"); try await repo.save(ann)
        try await repo.softDelete(id: ann.id, actor: actor)
        let listed = try await repo.list(companyId: companyId)
        XCTAssertEqual(listed, [])
        let deletedAt = try db.writer.read { try String.fetchOne($0, sql: "SELECT deleted_at FROM customers WHERE id = ?", arguments: [ann.id.uuidString.lowercased()]) }
        XCTAssertNotNil(deletedAt)
        let fetched = try await repo.get(id: ann.id)
        XCTAssertNil(fetched)
    }

    func testSoftDeleteRejectedWhenLiveProjectExists() async throws {
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        let ann = customer("Ann"); try await repo.save(ann)
        try db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO projects (id, company_id, customer_id, name, job_type, status, address_line, contract_value, deposit_required_to_start, created_at, updated_at)
                VALUES (?, ?, ?, 'P', 'kitchen', 'inProgress', '1 Main', '0.00', 0, ?, ?)
                """, arguments: [UUID().uuidString.lowercased(), self.companyId.uuidString.lowercased(), ann.id.uuidString.lowercased(), "2026-01-01T00:00:00.000Z", "2026-01-01T00:00:00.000Z"])
        }
        do { try await repo.softDelete(id: ann.id, actor: actor); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? DomainError, .customerHasProjects) }
    }

    func testSaveRejectsBlankName() async throws {
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        do { try await repo.save(customer("")); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? DomainError, .emptyName) }
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Data`
Expected: `cannot find 'GRDBCompanyRepository' in scope`.

- [ ] **Step 3: Viết `RecordSupport` và các record**

`RecordSupport.swift`:

```swift
import Foundation
import GRDB
import Domain

enum RecordSupport {
    static func uuid(_ text: String, table: String, id: String, column: String) throws -> UUID {
        guard let value = UUID(uuidString: text) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func uuid(_ text: String?, table: String, id: String, column: String) throws -> UUID? {
        guard let text else { return nil }
        return try uuid(text, table: table, id: id, column: column)
    }

    static func money(_ text: String, currency: CurrencyCode, table: String, id: String, column: String) throws -> Money {
        guard let value = Money(storage: text, currency: currency) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func date(_ text: String, table: String, id: String, column: String) throws -> Date {
        guard let value = Timestamps.date(text) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func date(_ text: String?, table: String, id: String, column: String) throws -> Date? {
        guard let text else { return nil }
        return try date(text, table: table, id: id, column: column)
    }

    static func calendarDate(_ text: String?, table: String, id: String, column: String) throws -> CalendarDate? {
        guard let text else { return nil }
        guard let value = CalendarDate(storage: text) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func decimal(_ text: String?, table: String, id: String, column: String) throws -> Decimal? {
        guard let text else { return nil }
        guard let value = Decimal(string: text, locale: nil) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func key(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }
}

extension UUID {
    var dbKey: String { uuidString.lowercased() }
}
```

`CompanyRecord.swift`:

```swift
import Foundation
import GRDB
import Domain

struct CompanyRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "companies"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var name: String
    var currencyCode: String

    init(_ company: Company) {
        id = company.id.dbKey
        createdAt = Timestamps.string(company.createdAt)
        updatedAt = Timestamps.string(company.updatedAt)
        deletedAt = company.deletedAt.map(Timestamps.string)
        syncState = SyncState.pending.rawValue
        name = company.name
        currencyCode = company.currencyCode.rawValue
    }

    func toDomain() throws -> Company {
        let table = Self.databaseTableName
        guard let currency = CurrencyCode(rawValue: currencyCode) else { throw DataError.corruptRow(table: table, id: id, column: "currency_code") }
        return Company(id: try RecordSupport.uuid(id, table: table, id: id, column: "id"), name: name, currencyCode: currency,
                       createdAt: try RecordSupport.date(createdAt, table: table, id: id, column: "created_at"),
                       updatedAt: try RecordSupport.date(updatedAt, table: table, id: id, column: "updated_at"),
                       deletedAt: try RecordSupport.date(deletedAt, table: table, id: id, column: "deleted_at"))
    }
}
```

`UserRecord.swift`:

```swift
import Foundation
import GRDB
import Domain

struct UserRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "users"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var displayName: String
    var email: String?
    var role: String
    var authUserId: String?

    init(_ user: User) {
        id = user.id.dbKey; companyId = user.companyId.dbKey
        createdAt = Timestamps.string(user.createdAt); updatedAt = Timestamps.string(user.updatedAt)
        deletedAt = user.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        displayName = user.displayName; email = user.email; role = user.role.rawValue; authUserId = user.authUserId
    }

    func toDomain() throws -> User {
        let table = Self.databaseTableName
        guard let role = UserRole(rawValue: role) else { throw DataError.corruptRow(table: table, id: id, column: "role") }
        return User(id: try RecordSupport.uuid(id, table: table, id: id, column: "id"),
                    companyId: try RecordSupport.uuid(companyId, table: table, id: id, column: "company_id"),
                    displayName: displayName, email: email, role: role, authUserId: authUserId,
                    createdAt: try RecordSupport.date(createdAt, table: table, id: id, column: "created_at"),
                    updatedAt: try RecordSupport.date(updatedAt, table: table, id: id, column: "updated_at"),
                    deletedAt: try RecordSupport.date(deletedAt, table: table, id: id, column: "deleted_at"))
    }
}
```

`CustomerRecord.swift`:

```swift
import Foundation
import GRDB
import Domain

struct CustomerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "customers"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var name: String
    var phone: String?
    var email: String?
    var preferredContact: String?
    var companyName: String?
    var secondaryContact: String?
    var notes: String?

    init(_ c: Customer) {
        id = c.id.dbKey; companyId = c.companyId.dbKey
        createdAt = Timestamps.string(c.createdAt); updatedAt = Timestamps.string(c.updatedAt)
        deletedAt = c.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        name = c.name; phone = c.phone; email = c.email; preferredContact = c.preferredContact?.rawValue
        companyName = c.companyName; secondaryContact = c.secondaryContact; notes = c.notes
    }

    func toDomain() throws -> Customer {
        let table = Self.databaseTableName
        let contact = try preferredContact.map { raw -> ContactMethod in
            guard let v = ContactMethod(rawValue: raw) else { throw DataError.corruptRow(table: table, id: id, column: "preferred_contact") }
            return v
        }
        return Customer(id: try RecordSupport.uuid(id, table: table, id: id, column: "id"),
                        companyId: try RecordSupport.uuid(companyId, table: table, id: id, column: "company_id"),
                        name: name, phone: phone, email: email, preferredContact: contact, companyName: companyName,
                        secondaryContact: secondaryContact, notes: notes,
                        createdAt: try RecordSupport.date(createdAt, table: table, id: id, column: "created_at"),
                        updatedAt: try RecordSupport.date(updatedAt, table: table, id: id, column: "updated_at"),
                        deletedAt: try RecordSupport.date(deletedAt, table: table, id: id, column: "deleted_at"))
    }
}
```

`ActivityLogRecord.swift`:

```swift
import Foundation
import GRDB
import Domain

struct ActivityLogRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "activity_log"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var userId: String?
    var actorName: String
    var action: String
    var entityType: String
    var entityId: String
    var projectId: String?
    var detailsJson: String
    var occurredAt: String

    init(_ e: ActivityLogEntry) {
        id = e.id.dbKey; companyId = e.companyId.dbKey
        createdAt = Timestamps.string(e.createdAt); updatedAt = Timestamps.string(e.updatedAt)
        deletedAt = nil; syncState = SyncState.pending.rawValue
        userId = e.userId?.dbKey; actorName = e.actorName; action = e.action.rawValue
        entityType = e.entityType; entityId = e.entityId.dbKey; projectId = e.projectId?.dbKey
        detailsJson = e.detailsJSON; occurredAt = Timestamps.string(e.occurredAt)
    }

    /// Append-only helper used inside repository transactions.
    static func append(_ db: Database, companyId: UUID, actor: ActivityActor, action: ActivityAction, entityType: String, entityId: UUID, projectId: UUID?, details: [String: String], at now: Date) throws {
        let json = try JSONSerialization.data(withJSONObject: details.sorted { $0.key < $1.key }.reduce(into: [String: String]()) { $0[$1.key] = $1.value }, options: [.sortedKeys])
        let entry = ActivityLogEntry(id: UUID(), companyId: companyId, userId: actor.userId, actorName: actor.name, action: action, entityType: entityType,
                                     entityId: entityId, projectId: projectId, detailsJSON: String(decoding: json, as: UTF8.self), occurredAt: now,
                                     createdAt: now, updatedAt: now, deletedAt: nil)
        try ActivityLogRecord(entry).insert(db)
    }
}
```

- [ ] **Step 4: Viết hai repository**

`GRDBCompanyRepository.swift`:

```swift
import Foundation
import GRDB
import Domain

public final class GRDBCompanyRepository: CompanyRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) {
        self.database = database; self.clock = clock
    }

    public func current() async throws -> CompanySetup? {
        try await database.writer.read { db in
            guard let companyRecord = try CompanyRecord.filter(Column("deleted_at") == nil).order(Column("created_at")).fetchOne(db) else { return nil }
            guard let ownerRecord = try UserRecord
                .filter(Column("company_id") == companyRecord.id && Column("deleted_at") == nil && Column("role") == UserRole.owner.rawValue)
                .order(Column("created_at")).fetchOne(db) else { return nil }
            return CompanySetup(company: try companyRecord.toDomain(), owner: try ownerRecord.toDomain())
        }
    }

    public func create(company: Company, owner: User) async throws {
        try company.validate()
        try owner.validate()
        try await database.writer.write { db in
            try CompanyRecord(company).insert(db)
            try UserRecord(owner).insert(db)
        }
    }

    public func update(company: Company) async throws {
        try company.validate()
        var stamped = company
        stamped.updatedAt = clock.now()
        try await database.writer.write { db in
            try CompanyRecord(stamped).update(db)
        }
    }
}
```

`GRDBCustomerRepository.swift`:

```swift
import Foundation
import GRDB
import Domain

public final class GRDBCustomerRepository: CustomerRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) {
        self.database = database; self.clock = clock
    }

    public func get(id: UUID) async throws -> Customer? {
        try await database.writer.read { db in
            try CustomerRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db)?.toDomain()
        }
    }

    public func list(companyId: UUID) async throws -> [Customer] {
        try await database.writer.read { db in
            try CustomerRecord.filter(Column("company_id") == companyId.dbKey && Column("deleted_at") == nil)
                .order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db).map { try $0.toDomain() }
        }
    }

    public func save(_ customer: Customer) async throws {
        try customer.validate()
        var stamped = customer
        stamped.updatedAt = clock.now()
        try await database.writer.write { db in
            try CustomerRecord(stamped).save(db)
        }
    }

    public func softDelete(id: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        try await database.writer.write { db in
            guard let record = try CustomerRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DataError.notFound }
            let liveProjects = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects WHERE customer_id = ? AND deleted_at IS NULL", arguments: [record.id]) ?? 0
            guard liveProjects == 0 else { throw DomainError.customerHasProjects }
            try db.execute(sql: "UPDATE customers SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?",
                           arguments: [Timestamps.string(now), Timestamps.string(now), record.id])
        }
    }
}
```

- [ ] **Step 5: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Data`
Expected: pass. Nếu `.collating(.localizedCaseInsensitiveCompare)` không có trên macOS test: thay bằng `.order(Column("name").collating(.nocase))`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Data
git commit -m "feat(data): add company and customer repositories with records"
```

---

### Task 14: `GRDBProjectRepository` (save + activity log, observe, cascade soft delete)

**Files:**
- Create: `Packages/Data/Sources/Data/Records/ProjectRecord.swift`, `ProjectScopeFieldRecord.swift`
- Create: `Packages/Data/Sources/Data/Repositories/GRDBProjectRepository.swift`
- Test: `Packages/Data/Tests/DataTests/ProjectRepositoryTests.swift`

**Interfaces:**
- Consumes: `ProjectRepository`, `ProjectSummary`, `ActivityActor`, `ActivityLogRecord.append`, `RecordSupport`.
- Produces: `public final class GRDBProjectRepository: ProjectRepository { public init(database: AppDatabase, clock: Clock) }`.

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
import GRDB
import Domain
@testable import Data

final class ProjectRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!
    var companyId: UUID!
    var customer: Customer!
    var actor: ActivityActor!
    var repo: GRDBProjectRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
        companyId = company.id
        actor = ActivityActor(userId: owner.id, name: "Duc")
        customer = Customer(id: UUID(), companyId: companyId, name: "Ann Lee", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(customer)
        repo = GRDBProjectRepository(database: db, clock: .fixed(now))
    }

    func project(_ name: String = "123 Main St", status: ProjectStatus = .inProgress) -> Project {
        let id = UUID()
        return Project(id: id, companyId: companyId, customerId: customer.id, name: name, jobType: .basementRenovation, customJobType: nil, status: status,
                       address: Address(line: "123 Main St", unit: "2", city: "Toronto", region: "ON", postalCode: "M1M 1M1"), scopeDescription: "1200 sqft",
                       scopeFields: [ProjectScopeField(id: UUID(), companyId: companyId, projectId: id, fieldKey: "squareFootage", valueText: "1200", sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)],
                       startDate: CalendarDate(storage: "2026-10-01"), estimatedCompletionDate: CalendarDate(storage: "2026-10-20"), workingDays: 10,
                       hoursPerDay: Decimal(string: "8.5"), workersPerDay: 3, contractValue: Money(38_000, .cad), manualProgress: 65, depositRequiredToStart: true,
                       createdAt: now, updatedAt: now, deletedAt: nil)
    }

    private func activityActions(_ projectId: UUID) throws -> [String] {
        try db.writer.read { try String.fetchAll($0, sql: "SELECT action FROM activity_log WHERE project_id = ? ORDER BY created_at, rowid", arguments: [projectId.dbKey]) }
    }

    func testSaveAndGetRoundTripIncludingScopeFields() async throws {
        let p = project()
        try await repo.save(p, actor: actor)
        let fetched = try await repo.get(id: p.id)
        XCTAssertEqual(fetched, p)
        XCTAssertEqual(try activityActions(p.id), ["projectCreated"])
    }

    func testUpdateLogsContractStatusAndProgressChanges() async throws {
        var p = project(); try await repo.save(p, actor: actor)
        p.contractValue = Money(45_000, .cad); p.status = .onHold; p.manualProgress = 70; p.name = "Renamed"
        try await repo.save(p, actor: actor)
        XCTAssertEqual(try activityActions(p.id), ["projectCreated", "contractValueChanged", "statusChanged", "progressChanged"])
        let details = try db.writer.read { try String.fetchOne($0, sql: "SELECT details_json FROM activity_log WHERE action = 'contractValueChanged'") }
        XCTAssertEqual(details, #"{"from":"38000.00","to":"45000.00"}"#)
        // Renaming alone adds no activity row.
        p.name = "Renamed again"; try await repo.save(p, actor: actor)
        XCTAssertEqual(try activityActions(p.id).count, 4)
    }

    func testScopeFieldsReplacedWithSoftDelete() async throws {
        var p = project(); try await repo.save(p, actor: actor)
        p.scopeFields = [ProjectScopeField(id: UUID(), companyId: companyId, projectId: p.id, fieldKey: "rooms", valueText: "3", sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)]
        try await repo.save(p, actor: actor)
        let fetched = try await repo.get(id: p.id)
        XCTAssertEqual(fetched?.scopeFields.map(\.fieldKey), ["rooms"])
        let rows = try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM project_scope_fields WHERE project_id = ?", arguments: [p.id.dbKey]) }
        XCTAssertEqual(rows, 2)
    }

    func testValidationFailureRollsBack() async throws {
        var p = project(); p.estimatedCompletionDate = CalendarDate(storage: "2026-09-01")
        do { try await repo.save(p, actor: actor); XCTFail("expected throw") } catch { XCTAssertEqual(error as? DomainError, .completionBeforeStart) }
        let count = try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM projects") }
        XCTAssertEqual(count, 0)
        XCTAssertEqual(try activityActions(p.id), [])
    }

    func testListAndSummariesExcludeDeleted() async throws {
        let a = project("A"), b = project("B")
        try await repo.save(a, actor: actor); try await repo.save(b, actor: actor)
        try await repo.softDelete(id: a.id, actor: actor)
        let listed = try await repo.list(companyId: companyId)
        XCTAssertEqual(listed.map(\.name), ["B"])
        var iterator = repo.observeSummaries(companyId: companyId).makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.map(\.project.name), ["B"])
        XCTAssertEqual(first?.first?.customerName, "Ann Lee")
    }

    func testObserveEmitsOnChange() async throws {
        var iterator = repo.observeSummaries(companyId: companyId).makeAsyncIterator()
        let initial = try await iterator.next()
        XCTAssertEqual(initial?.count, 0)
        try await repo.save(project("New"), actor: actor)
        let next = try await iterator.next()
        XCTAssertEqual(next?.map(\.project.name), ["New"])
    }

    func testCascadeSoftDeleteCoversChildrenAndNotificationsKeepsActivityLog() async throws {
        let p = project(); try await repo.save(p, actor: actor)
        let ts = "2026-10-05T00:00:00.000Z"
        let taskId = UUID().dbKey, expenseId = UUID().dbKey, employeeId = UUID().dbKey, logId = UUID().dbKey, itemId = UUID().dbKey
        try db.writer.write { db in
            let c = self.companyId.dbKey, pid = p.id.dbKey
            try db.execute(sql: "INSERT INTO employees (id, company_id, name, created_at, updated_at) VALUES (?, ?, 'Mike', ?, ?)", arguments: [employeeId, c, ts, ts])
            try db.execute(sql: "INSERT INTO project_tasks (id, company_id, project_id, name, status, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'Framing', 'inProgress', 0, ?, ?)", arguments: [taskId, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO task_checklist_items (id, company_id, task_id, title, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'Walls', 0, ?, ?)", arguments: [UUID().dbKey, c, taskId, ts, ts])
            try db.execute(sql: "INSERT INTO task_assignees (id, company_id, task_id, employee_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)", arguments: [UUID().dbKey, c, taskId, employeeId, ts, ts])
            try db.execute(sql: "INSERT INTO project_workers (id, company_id, project_id, employee_id, work_date, created_at, updated_at) VALUES (?, ?, ?, ?, '2026-10-05', ?, ?)", arguments: [UUID().dbKey, c, pid, employeeId, ts, ts])
            try db.execute(sql: "INSERT INTO project_estimate_lines (id, company_id, project_id, cost_group, label, amount, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'material', 'Lumber', '2500.00', 0, ?, ?)", arguments: [UUID().dbKey, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO payment_schedule_items (id, company_id, project_id, label, amount, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'Deposit', '5000.00', 0, ?, ?)", arguments: [itemId, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES (?, ?, ?, ?, '5000.00', '2026-10-05', 'cash', ?, ?)", arguments: [UUID().dbKey, c, pid, itemId, ts, ts])
            try db.execute(sql: "INSERT INTO expenses (id, company_id, project_id, category, cost_group, amount, tax, spent_on, created_at, updated_at) VALUES (?, ?, ?, 'materials', 'material', '100.00', '13.00', '2026-10-05', ?, ?)", arguments: [expenseId, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO receipt_images (id, company_id, expense_id, file_path, page_index, created_at, updated_at) VALUES (?, ?, ?, 'r.jpg', 0, ?, ?)", arguments: [UUID().dbKey, c, expenseId, ts, ts])
            try db.execute(sql: "INSERT INTO labour_entries (id, company_id, project_id, employee_id, work_date, days, daily_rate, created_at, updated_at) VALUES (?, ?, ?, ?, '2026-10-05', '1', '250.00', ?, ?)", arguments: [UUID().dbKey, c, pid, employeeId, ts, ts])
            try db.execute(sql: "INSERT INTO daily_logs (id, company_id, project_id, log_date, created_at, updated_at) VALUES (?, ?, ?, '2026-10-05', ?, ?)", arguments: [logId, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO photos (id, company_id, project_id, daily_log_id, category, taken_at, file_path, created_at, updated_at) VALUES (?, ?, ?, ?, 'progress', ?, 'p.jpg', ?, ?)", arguments: [UUID().dbKey, c, pid, logId, ts, ts, ts])
            try db.execute(sql: "INSERT INTO notifications (id, company_id, project_id, kind, details_json, fire_at, created_at, updated_at) VALUES (?, ?, ?, 'depositDue', '{}', '2099-01-01T00:00:00.000Z', ?, ?)", arguments: [UUID().dbKey, c, pid, ts, ts])
        }

        try await repo.softDelete(id: p.id, actor: actor)

        try db.writer.read { db in
            for table in ["projects", "project_scope_fields", "project_estimate_lines", "project_tasks", "task_checklist_items", "task_assignees", "project_workers",
                          "payment_schedule_items", "payments", "expenses", "receipt_images", "labour_entries", "daily_logs", "photos", "notifications"] {
                let live = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE deleted_at IS NULL") ?? -1
                XCTAssertEqual(live, 0, "\(table) still has live rows")
                let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
                XCTAssertGreaterThan(total, 0, "\(table) rows were physically deleted")
            }
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM employees WHERE deleted_at IS NULL"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM activity_log WHERE deleted_at IS NULL AND project_id = ?", arguments: [p.id.dbKey]), 2)
        }
        XCTAssertEqual(try activityActions(p.id), ["projectCreated", "projectDeleted"])
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Data`
Expected: `cannot find 'GRDBProjectRepository' in scope`.

- [ ] **Step 3: Viết records**

`ProjectScopeFieldRecord.swift`:

```swift
import Foundation
import GRDB
import Domain

struct ProjectScopeFieldRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_scope_fields"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var projectId: String
    var fieldKey: String
    var valueText: String
    var sortOrder: Int

    init(_ f: ProjectScopeField) {
        id = f.id.dbKey; companyId = f.companyId.dbKey; projectId = f.projectId.dbKey
        createdAt = Timestamps.string(f.createdAt); updatedAt = Timestamps.string(f.updatedAt)
        deletedAt = f.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        fieldKey = f.fieldKey; valueText = f.valueText; sortOrder = f.sortOrder
    }

    func toDomain() throws -> ProjectScopeField {
        let t = Self.databaseTableName
        return ProjectScopeField(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                                 companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                                 projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"),
                                 fieldKey: fieldKey, valueText: valueText, sortOrder: sortOrder,
                                 createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                                 updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                                 deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }
}
```

`ProjectRecord.swift`:

```swift
import Foundation
import GRDB
import Domain

struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var customerId: String
    var name: String
    var jobType: String
    var customJobType: String?
    var status: String
    var addressLine: String
    var unit: String?
    var city: String?
    var region: String?
    var postalCode: String?
    var scopeDescription: String?
    var startDate: String?
    var estimatedCompletionDate: String?
    var workingDays: Int?
    var hoursPerDay: String?
    var workersPerDay: Int?
    var contractValue: String
    var manualProgress: Int?
    var depositRequiredToStart: Bool

    init(_ p: Project) {
        id = p.id.dbKey; companyId = p.companyId.dbKey; customerId = p.customerId.dbKey
        createdAt = Timestamps.string(p.createdAt); updatedAt = Timestamps.string(p.updatedAt)
        deletedAt = p.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        name = p.name; jobType = p.jobType.rawValue; customJobType = p.customJobType; status = p.status.rawValue
        addressLine = p.address.line; unit = p.address.unit; city = p.address.city; region = p.address.region; postalCode = p.address.postalCode
        scopeDescription = p.scopeDescription
        startDate = p.startDate?.storageString; estimatedCompletionDate = p.estimatedCompletionDate?.storageString
        workingDays = p.workingDays; hoursPerDay = p.hoursPerDay.map { "\($0)" }; workersPerDay = p.workersPerDay
        contractValue = p.contractValue.storageString; manualProgress = p.manualProgress; depositRequiredToStart = p.depositRequiredToStart
    }

    func toDomain(currency: CurrencyCode, scopeFields: [ProjectScopeField]) throws -> Project {
        let t = Self.databaseTableName
        guard let jobType = JobType(rawValue: jobType) else { throw DataError.corruptRow(table: t, id: id, column: "job_type") }
        guard let status = ProjectStatus(rawValue: status) else { throw DataError.corruptRow(table: t, id: id, column: "status") }
        return Project(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                       companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                       customerId: try RecordSupport.uuid(customerId, table: t, id: id, column: "customer_id"),
                       name: name, jobType: jobType, customJobType: customJobType, status: status,
                       address: Address(line: addressLine, unit: unit, city: city, region: region, postalCode: postalCode),
                       scopeDescription: scopeDescription, scopeFields: scopeFields,
                       startDate: try RecordSupport.calendarDate(startDate, table: t, id: id, column: "start_date"),
                       estimatedCompletionDate: try RecordSupport.calendarDate(estimatedCompletionDate, table: t, id: id, column: "estimated_completion_date"),
                       workingDays: workingDays, hoursPerDay: try RecordSupport.decimal(hoursPerDay, table: t, id: id, column: "hours_per_day"), workersPerDay: workersPerDay,
                       contractValue: try RecordSupport.money(contractValue, currency: currency, table: t, id: id, column: "contract_value"),
                       manualProgress: manualProgress, depositRequiredToStart: depositRequiredToStart,
                       createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                       updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                       deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }
}
```

- [ ] **Step 4: Viết repository**

```swift
import Foundation
import GRDB
import Domain

public final class GRDBProjectRepository: ProjectRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) {
        self.database = database; self.clock = clock
    }

    // MARK: Reads

    public func get(id: UUID) async throws -> Project? {
        try await database.writer.read { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            let currency = try Self.currency(db, companyId: record.companyId)
            let fields = try Self.scopeFields(db, projectIds: [record.id])[record.id] ?? []
            return try record.toDomain(currency: currency, scopeFields: fields)
        }
    }

    public func list(companyId: UUID) async throws -> [Project] {
        try await database.writer.read { db in
            let records = try ProjectRecord.filter(Column("company_id") == companyId.dbKey && Column("deleted_at") == nil).order(Column("updated_at").desc).fetchAll(db)
            let currency = try Self.currency(db, companyId: companyId.dbKey)
            let fields = try Self.scopeFields(db, projectIds: records.map(\.id))
            return try records.map { try $0.toDomain(currency: currency, scopeFields: fields[$0.id] ?? []) }
        }
    }

    public func observeSummaries(companyId: UUID) -> AsyncThrowingStream<[ProjectSummary], Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> [ProjectSummary] in
            let currency = try Self.currency(db, companyId: key)
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.*, c.name AS customer_name
                FROM projects p JOIN customers c ON c.id = p.customer_id
                WHERE p.company_id = ? AND p.deleted_at IS NULL
                ORDER BY p.updated_at DESC, p.name
                """, arguments: [key])
            let records = try rows.map { try ProjectRecord(row: $0) }
            let fields = try Self.scopeFields(db, projectIds: records.map(\.id))
            return try zip(records, rows).map { record, row in
                ProjectSummary(project: try record.toDomain(currency: currency, scopeFields: fields[record.id] ?? []), customerName: row["customer_name"])
            }
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

    // MARK: Writes

    public func save(_ project: Project, actor: ActivityActor) async throws {
        try project.validate()
        let now = clock.now()
        var stamped = project
        stamped.updatedAt = now
        try await database.writer.write { db in
            let existing = try ProjectRecord.filter(Column("id") == stamped.id.dbKey).fetchOne(db)
            try ProjectRecord(stamped).save(db)
            try Self.replaceScopeFields(db, project: stamped, now: now)

            if let old = existing {
                if old.contractValue != stamped.contractValue.storageString {
                    try ActivityLogRecord.append(db, companyId: stamped.companyId, actor: actor, action: .contractValueChanged, entityType: "project", entityId: stamped.id, projectId: stamped.id,
                                                 details: ["from": old.contractValue, "to": stamped.contractValue.storageString], at: now)
                }
                if old.status != stamped.status.rawValue {
                    try ActivityLogRecord.append(db, companyId: stamped.companyId, actor: actor, action: .statusChanged, entityType: "project", entityId: stamped.id, projectId: stamped.id,
                                                 details: ["from": old.status, "to": stamped.status.rawValue], at: now)
                }
                if old.manualProgress != stamped.manualProgress {
                    try ActivityLogRecord.append(db, companyId: stamped.companyId, actor: actor, action: .progressChanged, entityType: "project", entityId: stamped.id, projectId: stamped.id,
                                                 details: ["from": old.manualProgress.map(String.init) ?? "", "to": stamped.manualProgress.map(String.init) ?? ""], at: now)
                }
            } else {
                try ActivityLogRecord.append(db, companyId: stamped.companyId, actor: actor, action: .projectCreated, entityType: "project", entityId: stamped.id, projectId: stamped.id,
                                             details: ["name": stamped.name, "contractValue": stamped.contractValue.storageString], at: now)
            }
        }
    }

    public func softDelete(id: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DataError.notFound }
            let pid = record.id
            let set = "SET deleted_at = ?, updated_at = ?, sync_state = 'pending'"
            try db.execute(sql: "UPDATE projects \(set) WHERE id = ?", arguments: [stamp, stamp, pid])
            for table in ["project_scope_fields", "project_estimate_lines", "project_tasks", "project_workers", "payment_schedule_items", "payments",
                          "expenses", "labour_entries", "daily_logs", "photos", "notifications"] {
                try db.execute(sql: "UPDATE \(table) \(set) WHERE project_id = ? AND deleted_at IS NULL", arguments: [stamp, stamp, pid])
            }
            try db.execute(sql: "UPDATE task_checklist_items \(set) WHERE deleted_at IS NULL AND task_id IN (SELECT id FROM project_tasks WHERE project_id = ?)", arguments: [stamp, stamp, pid])
            try db.execute(sql: "UPDATE task_assignees \(set) WHERE deleted_at IS NULL AND task_id IN (SELECT id FROM project_tasks WHERE project_id = ?)", arguments: [stamp, stamp, pid])
            try db.execute(sql: "UPDATE receipt_images \(set) WHERE deleted_at IS NULL AND expense_id IN (SELECT id FROM expenses WHERE project_id = ?)", arguments: [stamp, stamp, pid])
            let companyId = try RecordSupport.uuid(record.companyId, table: "projects", id: pid, column: "company_id")
            try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .projectDeleted, entityType: "project", entityId: id, projectId: id, details: ["name": record.name], at: now)
        }
    }

    // MARK: Helpers

    private static func currency(_ db: Database, companyId: String) throws -> CurrencyCode {
        guard let raw = try String.fetchOne(db, sql: "SELECT currency_code FROM companies WHERE id = ?", arguments: [companyId]),
              let currency = CurrencyCode(rawValue: raw) else { throw DataError.corruptRow(table: "companies", id: companyId, column: "currency_code") }
        return currency
    }

    private static func scopeFields(_ db: Database, projectIds: [String]) throws -> [String: [ProjectScopeField]] {
        guard !projectIds.isEmpty else { return [:] }
        let records = try ProjectScopeFieldRecord.filter(projectIds.contains(Column("project_id")) && Column("deleted_at") == nil).order(Column("sort_order")).fetchAll(db)
        var result: [String: [ProjectScopeField]] = [:]
        for record in records { result[record.projectId, default: []].append(try record.toDomain()) }
        return result
    }

    /// Upserts the given fields and soft-deletes live fields that are no longer present.
    private static func replaceScopeFields(_ db: Database, project: Project, now: Date) throws {
        let keep = Set(project.scopeFields.map { $0.id.dbKey })
        let live = try ProjectScopeFieldRecord.filter(Column("project_id") == project.id.dbKey && Column("deleted_at") == nil).fetchAll(db)
        let stamp = Timestamps.string(now)
        for record in live where !keep.contains(record.id) {
            try db.execute(sql: "UPDATE project_scope_fields SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, record.id])
        }
        for var field in project.scopeFields {
            field.updatedAt = now
            try ProjectScopeFieldRecord(field).save(db)
        }
    }
}
```

- [ ] **Step 5: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Data`
Expected: pass. Nếu `testSaveAndGetRoundTripIncludingScopeFields` fail vì `updatedAt` khác: test dùng `Clock.fixed(now)` và entity có `updatedAt = now`, nên phải bằng nhau; kiểm tra `stamped.updatedAt = now` không bị ghi đè chỗ khác. Nếu `testUpdateLogsContractStatusAndProgressChanges` fail ở JSON: `ActivityLogRecord.append` dùng `.sortedKeys`, kết quả phải đúng `{"from":"38000.00","to":"45000.00"}`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Data
git commit -m "feat(data): add project repository with audit log and cascading soft delete"
```

---

### Task 15: Seed dữ liệu mẫu (debug)

**Files:**
- Create: `Packages/Data/Sources/Data/Seed/SampleData.swift`
- Test: `Packages/Data/Tests/DataTests/SampleDataTests.swift`

**Interfaces:**
- Produces: `public enum SampleData { public static func seedIfEmpty(_ database: AppDatabase, clock: Clock) async throws -> CompanySetup }` — tạo company "Northwind Contracting" (CAD), owner "Duc", 3 customer, 3 project (inProgress 65%, awaitingDeposit, completed); nếu đã có company thì trả `current()` không ghi gì.

- [ ] **Step 1: Viết test fail**

```swift
import XCTest
import Domain
@testable import Data

final class SampleDataTests: XCTestCase {
    func testSeedCreatesThreeProjectsAndIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let clock = Clock.fixed(Date(timeIntervalSince1970: 1_790_000_000))
        let setup = try await SampleData.seedIfEmpty(db, clock: clock)
        XCTAssertEqual(setup.company.name, "Northwind Contracting")
        XCTAssertEqual(setup.owner.displayName, "Duc")
        let projects = try await GRDBProjectRepository(database: db, clock: clock).list(companyId: setup.company.id)
        XCTAssertEqual(Set(projects.map(\.status)), [.inProgress, .awaitingDeposit, .completed])
        XCTAssertEqual(projects.first { $0.status == .inProgress }?.manualProgress, 65)
        XCTAssertEqual(projects.first { $0.status == .inProgress }?.contractValue.storageString, "38000.00")

        let again = try await SampleData.seedIfEmpty(db, clock: clock)
        XCTAssertEqual(again.company.id, setup.company.id)
        let count = try await GRDBProjectRepository(database: db, clock: clock).list(companyId: setup.company.id).count
        XCTAssertEqual(count, 3)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

Run: `swift test --package-path Packages/Data`
Expected: `cannot find 'SampleData' in scope`.

- [ ] **Step 3: Viết `SampleData`**

```swift
import Foundation
import Domain

public enum SampleData {
    public static func seedIfEmpty(_ database: AppDatabase, clock: Clock) async throws -> CompanySetup {
        let companies = GRDBCompanyRepository(database: database, clock: clock)
        if let existing = try await companies.current() { return existing }

        let now = clock.now()
        let company = Company(id: UUID(), name: "Northwind Contracting", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await companies.create(company: company, owner: owner)
        let actor = ActivityActor(userId: owner.id, name: owner.displayName)

        let customers = GRDBCustomerRepository(database: database, clock: clock)
        let projects = GRDBProjectRepository(database: database, clock: clock)

        func customer(_ name: String, _ phone: String) -> Customer {
            Customer(id: UUID(), companyId: company.id, name: name, phone: phone, email: nil, preferredContact: .text, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        func project(_ name: String, _ customer: Customer, _ jobType: JobType, _ status: ProjectStatus, line: String, city: String, contract: Int, progress: Int?, start: String, end: String) -> Project {
            Project(id: UUID(), companyId: company.id, customerId: customer.id, name: name, jobType: jobType, customJobType: nil, status: status,
                    address: Address(line: line, unit: nil, city: city, region: "ON", postalCode: nil), scopeDescription: nil, scopeFields: [],
                    startDate: CalendarDate(storage: start), estimatedCompletionDate: CalendarDate(storage: end), workingDays: nil, hoursPerDay: nil, workersPerDay: 3,
                    contractValue: Money(Decimal(contract), .cad), manualProgress: progress, depositRequiredToStart: true, createdAt: now, updatedAt: now, deletedAt: nil)
        }

        let ann = customer("Ann Lee", "416-555-0101"), david = customer("David Nguyen", "647-555-0199"), maria = customer("Maria Santos", "905-555-0142")
        for c in [ann, david, maria] { try await customers.save(c) }

        try await projects.save(project("Basement Renovation", ann, .basementRenovation, .inProgress, line: "123 Main Street", city: "Toronto", contract: 38_000, progress: 65, start: "2026-09-15", end: "2026-10-30"), actor: actor)
        try await projects.save(project("Kitchen Renovation", david, .kitchen, .awaitingDeposit, line: "45 Oak Avenue", city: "Mississauga", contract: 25_000, progress: nil, start: "2026-10-12", end: "2026-11-15"), actor: actor)
        try await projects.save(project("Roof Replacement", maria, .roofing, .completed, line: "9 Birch Court", city: "Vaughan", contract: 18_500, progress: 100, start: "2026-08-01", end: "2026-08-20"), actor: actor)

        guard let setup = try await companies.current() else { throw DataError.notFound }
        return setup
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

Run: `swift test --package-path Packages/Data`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/Data
git commit -m "feat(data): add debug sample data seeder"
```

---

### Task 16: DesignSystem tokens

**Files:**
- Create: `Packages/DesignSystem/Package.swift`
- Create: `Packages/DesignSystem/Sources/DesignSystem/Tokens/DSColor.swift`, `DSSpacing.swift`, `DSTypography.swift`

**Interfaces:**
- Produces:
  - `public enum DSColor { static let background, surface, textPrimary, textSecondary, accent, success, warning, danger, info, border: Color }` (dynamic light/dark)
  - `public enum DSSpacing { static let xs: CGFloat = 4, sm = 8, md = 12, lg = 16, xl = 24; static let cardRadius: CGFloat = 12, sheetRadius = 16; static let minTouch: CGFloat = 44; static let primaryButtonHeight: CGFloat = 56 }`
  - `public enum DSTypography { static let largeTitle, title, headline, body, callout, caption: Font; static func money(_ size: Font.TextStyle) -> Font }`
  - `public enum DSTone { neutral, info, success, warning, danger, accent; var foreground: Color; var background: Color }`

Lưu ý: package này và `Features` chỉ build cho iOS; không chạy `swift build` trên macOS được. Xác minh bằng `xcodebuild build` ở Task 20 (CI). Trước đó, kiểm tra cú pháp bằng cách đọc lại kỹ; lỗi biên dịch sẽ lộ ở CI.

- [ ] **Step 1: `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v17)],
    products: [.library(name: "DesignSystem", targets: ["DesignSystem"])],
    targets: [
        .target(name: "DesignSystem", path: "Sources/DesignSystem"),
    ]
)
```

- [ ] **Step 2: `DSColor.swift`**

```swift
import SwiftUI
import UIKit

public enum DSColor {
    public static let background = dynamic(light: 0xF5F5F2, dark: 0x0F0F10)
    public static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    public static let textPrimary = dynamic(light: 0x1A1A1A, dark: 0xF2F2F2)
    public static let textSecondary = dynamic(light: 0x5F5F5F, dark: 0xA1A1A6)
    public static let accent = dynamic(light: 0xD9651F, dark: 0xFF8A3D)
    public static let success = dynamic(light: 0x2E7D4F, dark: 0x4CC38A)
    public static let warning = dynamic(light: 0xB8860B, dark: 0xF0C419)
    public static let danger = dynamic(light: 0xB71C1C, dark: 0xFF6B6B)
    public static let info = dynamic(light: 0x2A5DB0, dark: 0x6FA0FF)
    public static let border = dynamic(light: 0xE2E2DE, dark: 0x2C2C2E)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

public enum DSTone: Sendable, Hashable, CaseIterable {
    case neutral, info, success, warning, danger, accent

    public var foreground: Color {
        switch self {
        case .neutral: return DSColor.textSecondary
        case .info: return DSColor.info
        case .success: return DSColor.success
        case .warning: return DSColor.warning
        case .danger: return DSColor.danger
        case .accent: return DSColor.accent
        }
    }

    public var background: Color { foreground.opacity(0.14) }
}
```

- [ ] **Step 3: `DSSpacing.swift`**

```swift
import SwiftUI

public enum DSSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let cardRadius: CGFloat = 12
    public static let sheetRadius: CGFloat = 16
    public static let minTouch: CGFloat = 44
    public static let primaryButtonHeight: CGFloat = 56
}
```

- [ ] **Step 4: `DSTypography.swift`**

```swift
import SwiftUI

public enum DSTypography {
    public static let largeTitle = Font.largeTitle.weight(.bold)
    public static let title = Font.title2.weight(.semibold)
    public static let headline = Font.headline
    public static let body = Font.body
    public static let callout = Font.callout
    public static let caption = Font.caption

    /// Monospaced digits so amounts line up in lists.
    public static func money(_ style: Font.TextStyle = .body) -> Font {
        Font.system(style, design: .default).weight(.semibold).monospacedDigit()
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Packages/DesignSystem
git commit -m "feat(design-system): add color, spacing and typography tokens"
```

---

### Task 17: DesignSystem components + Component Gallery

**Files:**
- Create: `Packages/DesignSystem/Sources/DesignSystem/Components/PrimaryButton.swift`, `SecondaryButton.swift`, `Card.swift`, `StatusBadge.swift`, `ProgressBar.swift`, `MoneyText.swift`, `SummaryTile.swift`, `SectionHeader.swift`, `EmptyState.swift`, `FormRow.swift`, `FloatingActionButton.swift`
- Create: `Packages/DesignSystem/Sources/DesignSystem/Gallery/ComponentGalleryView.swift`

**Interfaces:**
- Produces (tất cả nhận `LocalizedStringKey` cho text để không hard-code chuỗi; `Text(key)` resolve về `Bundle.main` của app):
  - `PrimaryButton(_ title: LocalizedStringKey, systemImage: String? = nil, isLoading: Bool = false, action: () -> Void)`
  - `SecondaryButton(_ title: LocalizedStringKey, systemImage: String? = nil, action: () -> Void)`
  - `Card<Content: View> { init(@ViewBuilder content) }`
  - `StatusBadge(_ title: LocalizedStringKey, tone: DSTone)`
  - `ProgressBar(progress: Int, tone: DSTone = .accent)` (0...100)
  - `MoneyText(amount: Decimal, currencyCode: String, style: Font.TextStyle = .body)` — format theo `@Environment(\.locale)`
  - `SummaryTile(_ title: LocalizedStringKey, value: Text, tone: DSTone = .neutral)`
  - `SectionHeader(_ title: LocalizedStringKey, trailing: AnyView? = nil)`
  - `EmptyState(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey)`
  - `FormRow<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content)`
  - `FloatingActionButton(systemImage: String = "plus", accessibilityLabel: LocalizedStringKey, action: () -> Void)`
  - `ComponentGalleryView()` — hiển thị mọi component; accessibility identifier `component_gallery`.

- [ ] **Step 1: Viết các component**

`PrimaryButton.swift`:

```swift
import SwiftUI

public struct PrimaryButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let isLoading: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.isLoading = isLoading; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(DSTypography.headline)
            }
            .frame(maxWidth: .infinity, minHeight: DSSpacing.primaryButtonHeight)
            .foregroundStyle(.white)
            .background(DSColor.accent, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
```

`SecondaryButton.swift`:

```swift
import SwiftUI

public struct SecondaryButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(DSTypography.headline)
            }
            .frame(maxWidth: .infinity, minHeight: DSSpacing.primaryButtonHeight)
            .foregroundStyle(DSColor.accent)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous).strokeBorder(DSColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
```

`Card.swift`:

```swift
import SwiftUI

public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous).strokeBorder(DSColor.border, lineWidth: 1))
    }
}
```

`StatusBadge.swift`:

```swift
import SwiftUI

public struct StatusBadge: View {
    private let title: LocalizedStringKey
    private let tone: DSTone

    public init(_ title: LocalizedStringKey, tone: DSTone) { self.title = title; self.tone = tone }

    public var body: some View {
        Text(title)
            .font(DSTypography.caption.weight(.semibold))
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .foregroundStyle(tone.foreground)
            .background(tone.background, in: Capsule())
    }
}
```

`ProgressBar.swift`:

```swift
import SwiftUI

public struct ProgressBar: View {
    private let progress: Int
    private let tone: DSTone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Int, tone: DSTone = .accent) {
        self.progress = min(max(progress, 0), 100); self.tone = tone
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(DSColor.border)
                Capsule().fill(tone.foreground)
                    .frame(width: geometry.size.width * CGFloat(progress) / 100)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(progress)%"))
    }
}
```

`MoneyText.swift`:

```swift
import SwiftUI

public struct MoneyText: View {
    private let amount: Decimal
    private let currencyCode: String
    private let style: Font.TextStyle
    @Environment(\.locale) private var locale

    public init(amount: Decimal, currencyCode: String, style: Font.TextStyle = .body) {
        self.amount = amount; self.currencyCode = currencyCode; self.style = style
    }

    public var body: some View {
        Text(amount, format: .currency(code: currencyCode).locale(locale).precision(.fractionLength(2)))
            .font(DSTypography.money(style))
    }
}
```

`SummaryTile.swift`:

```swift
import SwiftUI

public struct SummaryTile: View {
    private let title: LocalizedStringKey
    private let value: Text
    private let tone: DSTone

    public init(_ title: LocalizedStringKey, value: Text, tone: DSTone = .neutral) {
        self.title = title; self.value = value; self.tone = tone
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(title).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                value.font(DSTypography.money(.title3)).foregroundStyle(tone == .neutral ? DSColor.textPrimary : tone.foreground)
            }
        }
    }
}
```

`SectionHeader.swift`:

```swift
import SwiftUI

public struct SectionHeader: View {
    private let title: LocalizedStringKey
    private let trailing: AnyView?

    public init(_ title: LocalizedStringKey, trailing: AnyView? = nil) { self.title = title; self.trailing = trailing }

    public var body: some View {
        HStack {
            Text(title).font(DSTypography.title).foregroundStyle(DSColor.textPrimary)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, DSSpacing.lg)
    }
}
```

`EmptyState.swift`:

```swift
import SwiftUI

public struct EmptyState: View {
    private let systemImage: String
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey

    public init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.systemImage = systemImage; self.title = title; self.message = message
    }

    public var body: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(DSColor.textSecondary)
            Text(title).font(DSTypography.title).foregroundStyle(DSColor.textPrimary)
            Text(message).font(DSTypography.body).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`FormRow.swift`:

```swift
import SwiftUI

public struct FormRow<Content: View>: View {
    private let label: LocalizedStringKey
    private let content: Content

    public init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label; self.content = content()
    }

    public var body: some View {
        HStack(spacing: DSSpacing.md) {
            Text(label).font(DSTypography.body).foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: DSSpacing.md)
            content.multilineTextAlignment(.trailing)
        }
        .frame(minHeight: DSSpacing.minTouch)
    }
}
```

`FloatingActionButton.swift`:

```swift
import SwiftUI

public struct FloatingActionButton: View {
    private let systemImage: String
    private let accessibilityLabel: LocalizedStringKey
    private let action: () -> Void

    public init(systemImage: String = "plus", accessibilityLabel: LocalizedStringKey, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.accessibilityLabel = accessibilityLabel; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(DSColor.accent, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
```

Cuối mỗi file component thêm một `#Preview` (spec mục 7), ví dụ cho `PrimaryButton.swift`:

```swift
#Preview {
    VStack(spacing: DSSpacing.md) {
        PrimaryButton("gallery.primaryButton", systemImage: "plus") {}
        PrimaryButton("gallery.loadingButton", isLoading: true) {}
    }
    .padding()
}
```

Preview của component khác dùng cùng key `gallery.*` (xem catalog Task 18) và giá trị mẫu tương tự như trong `ComponentGalleryView` dưới đây.

- [ ] **Step 2: Viết `ComponentGalleryView`**

Key chuỗi dùng ở đây được thêm vào String Catalog ở Task 18 (nhóm `gallery.*`).

```swift
import SwiftUI

public struct ComponentGalleryView: View {
    @State private var progress = 65

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                SectionHeader("gallery.buttons")
                VStack(spacing: DSSpacing.md) {
                    PrimaryButton("gallery.primaryButton", systemImage: "plus") {}
                    PrimaryButton("gallery.loadingButton", isLoading: true) {}
                    SecondaryButton("gallery.secondaryButton", systemImage: "camera") {}
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.badges")
                HStack(spacing: DSSpacing.sm) {
                    ForEach(DSTone.allCases, id: \.self) { tone in StatusBadge("gallery.badge", tone: tone) }
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.progress")
                VStack(spacing: DSSpacing.md) {
                    ProgressBar(progress: progress)
                    ProgressBar(progress: 100, tone: .success)
                    ProgressBar(progress: 20, tone: .danger)
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.money")
                HStack(spacing: DSSpacing.md) {
                    SummaryTile("gallery.collected", value: Text(Decimal(20_000), format: .currency(code: "CAD")), tone: .success)
                    SummaryTile("gallery.spent", value: Text(Decimal(19_450), format: .currency(code: "CAD")), tone: .danger)
                }
                .padding(.horizontal, DSSpacing.lg)
                Card {
                    FormRow("gallery.contractValue") { MoneyText(amount: Decimal(string: "38000.00") ?? 0, currencyCode: "CAD") }
                    FormRow("gallery.cashPosition") { MoneyText(amount: Decimal(550), currencyCode: "CAD", style: .headline) }
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.emptyState")
                EmptyState(systemImage: "tray", title: "gallery.emptyTitle", message: "gallery.emptyMessage")
                    .frame(height: 220)
            }
            .padding(.vertical, DSSpacing.lg)
        }
        .background(DSColor.background)
        .overlay(alignment: .bottomTrailing) {
            FloatingActionButton(accessibilityLabel: "gallery.add") { progress = progress >= 100 ? 0 : progress + 10 }
                .padding(DSSpacing.xl)
        }
        .accessibilityIdentifier("component_gallery")
        .navigationTitle("gallery.title")
    }
}

#Preview("Light") { NavigationStack { ComponentGalleryView() } }
#Preview("Dark") { NavigationStack { ComponentGalleryView() }.preferredColorScheme(.dark) }
```

- [ ] **Step 3: Commit**

```bash
git add Packages/DesignSystem
git commit -m "feat(design-system): add core components and component gallery"
```

---

### Task 18: Features package, `FeatureSupport`, String Catalog en/vi, script kiểm tra

**Files:**
- Create: `Packages/Features/Package.swift`
- Create: `Packages/Features/Sources/FeatureSupport/AppSettings.swift`, `LanguageChoice.swift`, `AppearanceChoice.swift`, `ProjectStatusStyle.swift`, `JobTypeLabel.swift`
- Create: `App/Resources/Localizable.xcstrings`
- Create: `scripts/check_localization.py`, `scripts/lint_sources.py`

**Interfaces:**
- Produces:
  - `@Observable public final class AppSettings { var language: LanguageChoice; var appearance: AppearanceChoice; var resolvedLocale: Locale; var colorScheme: ColorScheme?; init(defaults: UserDefaults, systemLanguageCode: String?) }`
  - `public enum LanguageChoice: String, CaseIterable { system, english, vietnamese; var titleKey: LocalizedStringKey }`
  - `public enum AppearanceChoice: String, CaseIterable { system, light, dark; var titleKey: LocalizedStringKey }`
  - `extension ProjectStatus { public var titleKey: LocalizedStringKey; public var tone: DSTone }`
  - `extension JobType { public var titleKey: LocalizedStringKey }`
  - `extension CurrencyCode { public var titleKey: LocalizedStringKey }`
  - Script: `python3 scripts/check_localization.py` (exit 1 khi key thiếu `vi`, hoặc literal trong View không phải key/không có trong catalog); `python3 scripts/lint_sources.py` (exit 1 khi có `Double`/`Float`/`CGFloat` trong `Domain`/`Data` không có `lint:allow-double`, hoặc `try!`/`as!`/`fatalError(` trong mọi `Sources`).

- [ ] **Step 1: `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let featureDeps: [Target.Dependency] = ["FeatureSupport", .product(name: "Domain", package: "Domain"), .product(name: "DesignSystem", package: "DesignSystem")]

let package = Package(
    name: "Features",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Features", targets: ["FeatureSupport", "SetupFeature", "HomeFeature", "ProjectsFeature", "CalendarFeature", "ExpensesFeature", "MoreFeature"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "FeatureSupport", dependencies: [.product(name: "Domain", package: "Domain"), .product(name: "DesignSystem", package: "DesignSystem")], path: "Sources/FeatureSupport"),
        .target(name: "SetupFeature", dependencies: featureDeps, path: "Sources/SetupFeature"),
        .target(name: "HomeFeature", dependencies: featureDeps, path: "Sources/HomeFeature"),
        .target(name: "ProjectsFeature", dependencies: featureDeps, path: "Sources/ProjectsFeature"),
        .target(name: "CalendarFeature", dependencies: featureDeps, path: "Sources/CalendarFeature"),
        .target(name: "ExpensesFeature", dependencies: featureDeps, path: "Sources/ExpensesFeature"),
        .target(name: "MoreFeature", dependencies: featureDeps, path: "Sources/MoreFeature"),
    ]
)
```

- [ ] **Step 2: `FeatureSupport`**

`LanguageChoice.swift`:

```swift
import SwiftUI

public enum LanguageChoice: String, CaseIterable, Sendable {
    case system, english, vietnamese

    public var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "language.system"
        case .english: return "language.english"
        case .vietnamese: return "language.vietnamese"
        }
    }

    /// nil = follow the system.
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .vietnamese: return "vi"
        }
    }
}
```

`AppearanceChoice.swift`:

```swift
import SwiftUI

public enum AppearanceChoice: String, CaseIterable, Sendable {
    case system, light, dark

    public var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "appearance.system"
        case .light: return "appearance.light"
        case .dark: return "appearance.dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
```

`AppSettings.swift`:

```swift
import SwiftUI
import Observation

@Observable
public final class AppSettings {
    public static let languageKey = "settings.language"
    public static let appearanceKey = "settings.appearance"

    public var language: LanguageChoice { didSet { defaults.set(language.rawValue, forKey: AppSettings.languageKey) } }
    public var appearance: AppearanceChoice { didSet { defaults.set(appearance.rawValue, forKey: AppSettings.appearanceKey) } }

    private let defaults: UserDefaults
    private let systemLanguageCode: String?

    public init(defaults: UserDefaults = .standard, systemLanguageCode: String? = Locale.current.language.languageCode?.identifier) {
        self.defaults = defaults
        self.systemLanguageCode = systemLanguageCode
        self.language = defaults.string(forKey: AppSettings.languageKey).flatMap(LanguageChoice.init(rawValue:)) ?? .system
        self.appearance = defaults.string(forKey: AppSettings.appearanceKey).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
    }

    /// Vietnamese when chosen, or when the system is Vietnamese and "system" is selected; English otherwise.
    public var resolvedLocale: Locale {
        let code = language.localeIdentifier ?? (systemLanguageCode == "vi" ? "vi" : "en")
        return Locale(identifier: code)
    }

    public var colorScheme: ColorScheme? { appearance.colorScheme }
}
```

`ProjectStatusStyle.swift`:

```swift
import SwiftUI
import Domain
import DesignSystem

public extension ProjectStatus {
    var titleKey: LocalizedStringKey { LocalizedStringKey("status.\(rawValue)") }

    var tone: DSTone {
        switch self {
        case .estimate, .awaitingApproval: return .neutral
        case .awaitingDeposit, .awaitingFinalPayment: return .warning
        case .scheduled: return .info
        case .inProgress: return .accent
        case .onHold, .waitingForInspection, .waitingForMaterial, .waitingForClient: return .warning
        case .completed, .closed: return .success
        case .cancelled: return .danger
        }
    }
}
```

`JobTypeLabel.swift`:

```swift
import SwiftUI
import Domain

public extension JobType {
    var titleKey: LocalizedStringKey { LocalizedStringKey("jobType.\(rawValue)") }
}

public extension CurrencyCode {
    var titleKey: LocalizedStringKey { LocalizedStringKey("currency.\(rawValue)") }
}
```

- [ ] **Step 3: String Catalog**

`App/Resources/Localizable.xcstrings` — English là source, mỗi key có `en` và `vi`. Thuật ngữ nghề giữ tiếng Anh trong bản Việt.

```json
{
  "sourceLanguage" : "en",
  "version" : "1.0",
  "strings" : {
    "tab.home" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Home" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Trang chủ" } } } },
    "tab.projects" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Projects" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Dự án" } } } },
    "tab.calendar" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Calendar" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Lịch" } } } },
    "tab.expenses" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Expenses" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chi phí" } } } },
    "tab.more" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "More" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thêm" } } } },

    "setup.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Set up your company" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thiết lập công ty" } } } },
    "setup.subtitle" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "You can change these later in Settings." } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Bạn có thể đổi sau trong Cài đặt." } } } },
    "setup.companyName" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Company name" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tên công ty" } } } },
    "setup.yourName" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Your name" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tên của bạn" } } } },
    "setup.currency" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Currency" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tiền tệ" } } } },
    "setup.language" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Language" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Ngôn ngữ" } } } },
    "setup.start" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Get started" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Bắt đầu" } } } },
    "setup.error" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Could not save. Please check the fields and try again." } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Không lưu được. Kiểm tra lại các ô và thử lại." } } } },

    "language.system" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "System" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Theo hệ thống" } } } },
    "language.english" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "English" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "English" } } } },
    "language.vietnamese" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Tiếng Việt" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tiếng Việt" } } } },
    "appearance.system" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "System" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Theo hệ thống" } } } },
    "appearance.light" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Light" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Sáng" } } } },
    "appearance.dark" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Dark" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tối" } } } },
    "currency.CAD" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Canadian dollar (CAD)" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Đô la Canada (CAD)" } } } },
    "currency.USD" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "US dollar (USD)" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Đô la Mỹ (USD)" } } } },

    "home.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Home" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Trang chủ" } } } },
    "home.ongoingJobs" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Ongoing jobs" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Job đang chạy" } } } },
    "home.progress" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Progress" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tiến độ" } } } },
    "home.contractValue" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Contract value" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Giá trị hợp đồng" } } } },
    "home.empty.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "No jobs yet" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chưa có job nào" } } } },
    "home.empty.message" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Your projects will show up here." } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Các dự án của bạn sẽ hiện ở đây." } } } },
    "home.error" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Could not load projects." } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Không tải được dự án." } } } },

    "projects.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Projects" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Dự án" } } } },
    "projects.empty.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Projects" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Dự án" } } } },
    "projects.empty.message" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "The project list and the create-project wizard are coming next." } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Danh sách dự án và wizard tạo dự án sẽ có ở bước tiếp theo." } } } },
    "calendar.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Calendar" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Lịch" } } } },
    "calendar.empty.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Calendar" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Lịch" } } } },
    "calendar.empty.message" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Deadlines, payments and crew schedule will appear here." } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Deadline, thanh toán và lịch crew sẽ hiện ở đây." } } } },
    "expenses.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Expenses" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chi phí" } } } },
    "expenses.empty.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Expenses" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chi phí" } } } },
    "expenses.empty.message" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Add expenses and scan receipts here once the Money module ships." } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thêm chi phí và chụp receipt ở đây khi module Money hoàn thành." } } } },

    "more.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "More" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thêm" } } } },
    "more.settings" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Settings" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Cài đặt" } } } },
    "more.componentGallery" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Component gallery" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thư viện component" } } } },
    "settings.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Settings" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Cài đặt" } } } },
    "settings.language" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Language" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Ngôn ngữ" } } } },
    "settings.appearance" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Appearance" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Giao diện" } } } },
    "settings.company" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Company" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Công ty" } } } },
    "settings.currency" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Currency" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tiền tệ" } } } },

    "error.database.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Could not open your data" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Không mở được dữ liệu" } } } },
    "error.database.message" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Nothing was deleted. Try again, or export the database file and send it to support." } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Không có gì bị xóa. Thử lại, hoặc xuất file dữ liệu và gửi cho hỗ trợ." } } } },
    "error.database.retry" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Try again" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thử lại" } } } },
    "error.database.export" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Export database" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Xuất file dữ liệu" } } } },

    "status.estimate" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Estimate" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Estimate" } } } },
    "status.awaitingApproval" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Awaiting approval" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chờ khách duyệt" } } } },
    "status.awaitingDeposit" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Awaiting deposit" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chờ deposit" } } } },
    "status.scheduled" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Scheduled" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Đã lên lịch" } } } },
    "status.inProgress" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "In progress" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Đang thi công" } } } },
    "status.onHold" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "On hold" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tạm dừng" } } } },
    "status.waitingForInspection" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Waiting for inspection" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chờ inspection" } } } },
    "status.waitingForMaterial" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Waiting for material" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chờ material" } } } },
    "status.waitingForClient" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Waiting for client" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chờ khách" } } } },
    "status.completed" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Completed" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Hoàn thành" } } } },
    "status.awaitingFinalPayment" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Awaiting final payment" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chờ thanh toán cuối" } } } },
    "status.closed" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Closed" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Đã đóng" } } } },
    "status.cancelled" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Cancelled" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Đã hủy" } } } },

    "jobType.generalRenovation" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "General renovation" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Renovation tổng quát" } } } },
    "jobType.basementRenovation" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Basement renovation" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Basement renovation" } } } },
    "jobType.kitchen" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Kitchen" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Nhà bếp" } } } },
    "jobType.bathroom" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Bathroom" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Phòng tắm" } } } },
    "jobType.landscaping" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Landscaping" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Landscaping" } } } },
    "jobType.roofing" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Roofing" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Roofing" } } } },
    "jobType.plumbing" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Plumbing" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Plumbing" } } } },
    "jobType.electrical" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Electrical" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Điện" } } } },
    "jobType.hvac" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "HVAC" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "HVAC" } } } },
    "jobType.flooring" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Flooring" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Flooring" } } } },
    "jobType.painting" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Painting" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Sơn" } } } },
    "jobType.drywall" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Drywall" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Drywall" } } } },
    "jobType.concrete" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Concrete" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Bê tông" } } } },
    "jobType.deckFence" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Deck / Fence" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Deck / Fence" } } } },
    "jobType.framing" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Framing" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Framing" } } } },
    "jobType.windowsDoors" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Windows / Doors" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Cửa sổ / Cửa" } } } },
    "jobType.exterior" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Exterior" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Ngoại thất" } } } },
    "jobType.demolition" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Demolition" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Demolition" } } } },
    "jobType.commercial" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Commercial" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thương mại" } } } },
    "jobType.other" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Other" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Khác" } } } },

    "gallery.title" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Components" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Component" } } } },
    "gallery.buttons" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Buttons" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Nút" } } } },
    "gallery.primaryButton" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Add expense" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thêm chi phí" } } } },
    "gallery.loadingButton" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Saving" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Đang lưu" } } } },
    "gallery.secondaryButton" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Scan receipt" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chụp receipt" } } } },
    "gallery.badges" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Status badges" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Badge trạng thái" } } } },
    "gallery.badge" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Badge" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Badge" } } } },
    "gallery.progress" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Progress" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tiến độ" } } } },
    "gallery.money" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Money" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Tiền" } } } },
    "gallery.collected" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Collected" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Đã thu" } } } },
    "gallery.spent" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Spent" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Đã chi" } } } },
    "gallery.contractValue" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Contract value" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Giá trị hợp đồng" } } } },
    "gallery.cashPosition" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Cash position" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Dòng tiền hiện tại" } } } },
    "gallery.emptyState" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Empty state" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Trạng thái trống" } } } },
    "gallery.emptyTitle" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Nothing here" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Chưa có gì" } } } },
    "gallery.emptyMessage" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Items you add will appear in this list." } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Mục bạn thêm sẽ hiện trong danh sách này." } } } },
    "gallery.add" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Add" } }, "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thêm" } } } }
  }
}
```

- [ ] **Step 4: `scripts/check_localization.py`**

```python
#!/usr/bin/env python3
"""Fails when a catalog key lacks a Vietnamese translation, or when a View file
contains a string literal that is neither a catalog key nor explicitly allowed."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "App/Resources/Localizable.xcstrings"
VIEW_DIRS = [ROOT / "App", ROOT / "Packages/Features/Sources", ROOT / "Packages/DesignSystem/Sources/DesignSystem/Gallery"]
# Only SwiftUI view files are checked; LaunchOptions.swift, AppContainer.swift and other
# non-view files carry CLI flags, paths and defaults keys that are not user-facing strings.
VIEW_MARKER = "import SwiftUI"
KEY_RE = re.compile(r"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$")
LITERAL_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
ALLOW_MARKERS = ["verbatim:", "systemImage", "systemName", "accessibilityIdentifier", "identifier", "forKey", "UserDefaults", "#Preview",
                 "code:", "lint:allow-string", "import ", "Bundle", "url", "URL", "path", "Path", "arguments", "CommandLine", "LocalizedStringKey(\""]

def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    errors = []
    for key, entry in strings.items():
        vi = entry.get("localizations", {}).get("vi", {}).get("stringUnit", {})
        if vi.get("state") != "translated" or not vi.get("value"):
            errors.append(f"{CATALOG.name}: key '{key}' has no Vietnamese translation")
    for directory in VIEW_DIRS:
        for path in directory.rglob("*.swift"):
            if "Tests" in path.parts or path.name.endswith("Tests.swift"):
                continue
            source = path.read_text(encoding="utf-8")
            if VIEW_MARKER not in source:
                continue
            for lineno, line in enumerate(source.splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//") or any(marker in line for marker in ALLOW_MARKERS):
                    continue
                for literal in LITERAL_RE.findall(line):
                    if literal == "" or literal.startswith("\\(") or literal.startswith("--"):
                        continue
                    if KEY_RE.match(literal):
                        if literal not in strings:
                            errors.append(f"{path.relative_to(ROOT)}:{lineno}: key '{literal}' missing from catalog")
                    else:
                        errors.append(f"{path.relative_to(ROOT)}:{lineno}: hard-coded string \"{literal}\"")
    for e in errors:
        print(e)
    print(f"check_localization: {len(strings)} keys, {len(errors)} error(s)")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
```

Script chỉ quét file có `import SwiftUI`; file không phải View (`LaunchOptions.swift`, `AppContainer.swift`, ViewModel) không bị kiểm tra literal.

Quy ước cho View: chuỗi không cần dịch (ví dụ tên công ty mẫu trong preview) phải viết `Text(verbatim: ...)`; identifier dùng `.accessibilityIdentifier("...")`; dòng nào cố ý có literal khác thì thêm `// lint:allow-string`.

- [ ] **Step 5: `scripts/lint_sources.py`**

```python
#!/usr/bin/env python3
"""Money safety and crash-safety lint for production sources."""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MONEY_DIRS = [ROOT / "Packages/Domain/Sources", ROOT / "Packages/Data/Sources"]
ALL_SOURCE_DIRS = MONEY_DIRS + [ROOT / "Packages/DesignSystem/Sources", ROOT / "Packages/Features/Sources", ROOT / "App"]
FLOAT_RE = re.compile(r"\b(Double|Float|CGFloat)\b")
CRASH_RE = re.compile(r"(try!|as!|fatalError\()")

def swift_files(directory):
    return [p for p in directory.rglob("*.swift") if "Tests" not in p.parts and "UITests" not in p.parts]

def main() -> int:
    errors = []
    for directory in MONEY_DIRS:
        for path in swift_files(directory):
            for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if FLOAT_RE.search(line) and "lint:allow-double" not in line:
                    errors.append(f"{path.relative_to(ROOT)}:{lineno}: floating point type in money-bearing module")
    for directory in ALL_SOURCE_DIRS:
        for path in swift_files(directory):
            for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if line.strip().startswith("//"):
                    continue
                if CRASH_RE.search(line) and "lint:allow-crash" not in line:
                    errors.append(f"{path.relative_to(ROOT)}:{lineno}: try!/as!/fatalError in production code")
    for e in errors:
        print(e)
    print(f"lint_sources: {len(errors)} error(s)")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 6: Chạy hai script trên Windows**

Run: `python scripts/check_localization.py; python scripts/lint_sources.py`
Expected: cả hai in `0 error(s)` và exit 0. (Gallery dùng key `gallery.*` đã có trong catalog; `Photo.swift` có `lint:allow-double`.) Nếu `check_localization` báo literal trong `ComponentGalleryView.swift` dòng `format: .currency(code: "CAD")`: dòng đó chứa `code:` nên được bỏ qua; nếu vẫn báo, kiểm tra regex.

- [ ] **Step 7: Thêm hai script vào `domain.yml`** (Python có sẵn trong `ubuntu-latest`, nhưng job đang chạy trong container `swift:6.0` không có Python — tách job):

```yaml
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: python3 scripts/check_localization.py
      - run: python3 scripts/lint_sources.py
```

- [ ] **Step 8: Commit**

```bash
git add Packages/Features App/Resources scripts .github/workflows/domain.yml
git commit -m "feat(features): add settings, status styling, en/vi string catalog and lint scripts"
```

---

### Task 19: Màn hình Setup, Home, placeholder tabs, More/Settings

**Files:**
- Create: `Packages/Features/Sources/SetupFeature/SetupViewModel.swift`, `SetupView.swift`
- Create: `Packages/Features/Sources/HomeFeature/HomeViewModel.swift`, `HomeView.swift`, `ProjectCardView.swift`
- Create: `Packages/Features/Sources/ProjectsFeature/ProjectsPlaceholderView.swift`, `CalendarFeature/CalendarPlaceholderView.swift`, `ExpensesFeature/ExpensesPlaceholderView.swift`
- Create: `Packages/Features/Sources/MoreFeature/MoreView.swift`, `SettingsView.swift`

**Interfaces:**
- Consumes: `CompanyRepository`, `ProjectRepository`, `ProjectSummary`, `CompanySetup`, `AppSettings`, DesignSystem components, `ProjectStatus.titleKey/tone`, `ProgressCalculator`.
- Produces:
  - `SetupView(viewModel: SetupViewModel, settings: AppSettings)`; `SetupViewModel(companyRepository:, onCompleted: @escaping (CompanySetup) -> Void)` với `companyName`, `ownerName`, `currency`, `isSaving`, `errorKey: LocalizedStringKey?`, `func submit() async`.
  - `HomeView(viewModel: HomeViewModel)`; `HomeViewModel(projectRepository:, companyId:)` với `summaries: [ProjectSummary]`, `errorKey`, `func start() async`.
  - `ProjectsPlaceholderView()`, `CalendarPlaceholderView()`, `ExpensesPlaceholderView()`.
  - `MoreView(settings: AppSettings, company: Company, showsGallery: Bool)`, `SettingsView(settings: AppSettings, company: Company)`.
  - Accessibility identifiers: `setup_company_name`, `setup_owner_name`, `setup_start`, `home_list`, `tab_home`… (tabs đặt ở Task 20), `settings_language_picker`, `settings_appearance_picker`, `more_settings`, `more_gallery`.

- [ ] **Step 1: Setup**

`SetupViewModel.swift`:

```swift
import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class SetupViewModel {
    public var companyName = ""
    public var ownerName = ""
    public var currency: CurrencyCode = .cad
    public private(set) var isSaving = false
    public private(set) var errorKey: LocalizedStringKey?

    private let companyRepository: any CompanyRepository
    private let onCompleted: (CompanySetup) -> Void

    public init(companyRepository: any CompanyRepository, onCompleted: @escaping (CompanySetup) -> Void) {
        self.companyRepository = companyRepository
        self.onCompleted = onCompleted
    }

    public var canSubmit: Bool {
        !companyName.trimmingCharacters(in: .whitespaces).isEmpty && !ownerName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    public func submit() async {
        guard canSubmit else { return }
        isSaving = true
        errorKey = nil
        defer { isSaving = false }
        let now = Date()
        let company = Company(id: UUID(), name: companyName.trimmingCharacters(in: .whitespaces), currencyCode: currency, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: ownerName.trimmingCharacters(in: .whitespaces), email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        do {
            try await companyRepository.create(company: company, owner: owner)
            onCompleted(CompanySetup(company: company, owner: owner))
        } catch {
            errorKey = "setup.error"
        }
    }
}
```

`SetupView.swift`:

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct SetupView: View {
    @Bindable private var viewModel: SetupViewModel
    @Bindable private var settings: AppSettings

    public init(viewModel: SetupViewModel, settings: AppSettings) {
        self.viewModel = viewModel; self.settings = settings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("setup.title").font(DSTypography.largeTitle).foregroundStyle(DSColor.textPrimary)
                    Text("setup.subtitle").font(DSTypography.body).foregroundStyle(DSColor.textSecondary)
                }
                Card {
                    VStack(spacing: DSSpacing.md) {
                        TextField("setup.companyName", text: $viewModel.companyName)
                            .textContentType(.organizationName)
                            .frame(minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("setup_company_name")
                        Divider()
                        TextField("setup.yourName", text: $viewModel.ownerName)
                            .textContentType(.name)
                            .frame(minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("setup_owner_name")
                        Divider()
                        FormRow("setup.currency") {
                            Picker("setup.currency", selection: $viewModel.currency) {
                                ForEach(CurrencyCode.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                            }
                            .labelsHidden()
                        }
                        Divider()
                        FormRow("setup.language") {
                            Picker("setup.language", selection: $settings.language) {
                                ForEach(LanguageChoice.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                }
                if let errorKey = viewModel.errorKey {
                    Text(errorKey).font(DSTypography.callout).foregroundStyle(DSColor.danger)
                }
                Spacer(minLength: DSSpacing.xl)
                PrimaryButton("setup.start", systemImage: "arrow.right", isLoading: viewModel.isSaving) {
                    Task { await viewModel.submit() }
                }
                .disabled(!viewModel.canSubmit)
                .opacity(viewModel.canSubmit ? 1 : 0.5)
                .accessibilityIdentifier("setup_start")
            }
            .padding(DSSpacing.lg)
        }
        .background(DSColor.background)
    }
}
```

- [ ] **Step 2: Home**

`HomeViewModel.swift`:

```swift
import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class HomeViewModel {
    public private(set) var summaries: [ProjectSummary] = []
    public private(set) var errorKey: LocalizedStringKey?
    public private(set) var isLoaded = false

    private let projectRepository: any ProjectRepository
    private let companyId: UUID

    public init(projectRepository: any ProjectRepository, companyId: UUID) {
        self.projectRepository = projectRepository; self.companyId = companyId
    }

    /// Runs until cancelled (bind to the view's `.task`).
    public func start() async {
        do {
            for try await value in projectRepository.observeSummaries(companyId: companyId) {
                summaries = value
                isLoaded = true
            }
        } catch is CancellationError {
        } catch {
            errorKey = "home.error"
        }
    }

    public func progress(for summary: ProjectSummary) -> Int {
        ProgressCalculator.percent(tasks: [], manualProgress: summary.project.manualProgress)
    }
}
```

`ProjectCardView.swift`:

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct ProjectCardView: View {
    let summary: ProjectSummary
    let progress: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(verbatim: summary.project.address.line).font(DSTypography.headline).foregroundStyle(DSColor.textPrimary)
                        Text(verbatim: summary.project.name).font(DSTypography.callout).foregroundStyle(DSColor.textSecondary)
                        Text(verbatim: summary.customerName).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    StatusBadge(summary.project.status.titleKey, tone: summary.project.status.tone)
                }
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack {
                        Text("home.progress").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                        Spacer()
                        Text(verbatim: "\(progress)%").font(DSTypography.money(.caption)).foregroundStyle(DSColor.textPrimary)
                    }
                    ProgressBar(progress: progress, tone: summary.project.status.tone)
                }
                FormRow("home.contractValue") {
                    MoneyText(amount: summary.project.contractValue.amount, currencyCode: summary.project.contractValue.currency.rawValue, style: .headline)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project_card_\(summary.project.id.uuidString)")
    }
}
```

`HomeView.swift`:

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct HomeView: View {
    private let viewModel: HomeViewModel

    public init(viewModel: HomeViewModel) { self.viewModel = viewModel }

    public var body: some View {
        Group {
            if let errorKey = viewModel.errorKey {
                EmptyState(systemImage: "exclamationmark.triangle", title: "home.error", message: errorKey)
            } else if viewModel.isLoaded && viewModel.summaries.isEmpty {
                EmptyState(systemImage: "hammer", title: "home.empty.title", message: "home.empty.message")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        SectionHeader("home.ongoingJobs")
                        ForEach(viewModel.summaries) { summary in
                            ProjectCardView(summary: summary, progress: viewModel.progress(for: summary))
                                .padding(.horizontal, DSSpacing.lg)
                        }
                    }
                    .padding(.vertical, DSSpacing.lg)
                }
                .accessibilityIdentifier("home_list")
            }
        }
        .background(DSColor.background)
        .navigationTitle("home.title")
        .task { await viewModel.start() }
    }
}
```

- [ ] **Step 3: Placeholder tabs**

`ProjectsPlaceholderView.swift`:

```swift
import SwiftUI
import DesignSystem

public struct ProjectsPlaceholderView: View {
    public init() {}
    public var body: some View {
        EmptyState(systemImage: "folder", title: "projects.empty.title", message: "projects.empty.message")
            .background(DSColor.background)
            .navigationTitle("projects.title")
    }
}
```

`CalendarPlaceholderView.swift`:

```swift
import SwiftUI
import DesignSystem

public struct CalendarPlaceholderView: View {
    public init() {}
    public var body: some View {
        EmptyState(systemImage: "calendar", title: "calendar.empty.title", message: "calendar.empty.message")
            .background(DSColor.background)
            .navigationTitle("calendar.title")
    }
}
```

`ExpensesPlaceholderView.swift`:

```swift
import SwiftUI
import DesignSystem

public struct ExpensesPlaceholderView: View {
    public init() {}
    public var body: some View {
        EmptyState(systemImage: "receipt", title: "expenses.empty.title", message: "expenses.empty.message")
            .background(DSColor.background)
            .navigationTitle("expenses.title")
    }
}
```

- [ ] **Step 4: More + Settings**

`SettingsView.swift`:

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct SettingsView: View {
    @Bindable private var settings: AppSettings
    private let company: Company

    public init(settings: AppSettings, company: Company) { self.settings = settings; self.company = company }

    public var body: some View {
        Form {
            Section("settings.language") {
                Picker("settings.language", selection: $settings.language) {
                    ForEach(LanguageChoice.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("settings_language_picker")
            }
            Section("settings.appearance") {
                Picker("settings.appearance", selection: $settings.appearance) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("settings_appearance_picker")
            }
            Section("settings.company") {
                FormRow("settings.company") { Text(verbatim: company.name).foregroundStyle(DSColor.textSecondary) }
                FormRow("settings.currency") { Text(company.currencyCode.titleKey).foregroundStyle(DSColor.textSecondary) }
            }
        }
        .navigationTitle("settings.title")
    }
}
```

`MoreView.swift`:

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct MoreView: View {
    private let settings: AppSettings
    private let company: Company
    private let showsGallery: Bool

    public init(settings: AppSettings, company: Company, showsGallery: Bool) {
        self.settings = settings; self.company = company; self.showsGallery = showsGallery
    }

    public var body: some View {
        List {
            NavigationLink { SettingsView(settings: settings, company: company) } label: {
                Label("more.settings", systemImage: "gearshape")
            }
            .frame(minHeight: DSSpacing.minTouch)
            .accessibilityIdentifier("more_settings")
            if showsGallery {
                NavigationLink { ComponentGalleryView() } label: {
                    Label("more.componentGallery", systemImage: "square.grid.2x2")
                }
                .frame(minHeight: DSSpacing.minTouch)
                .accessibilityIdentifier("more_gallery")
            }
        }
        .navigationTitle("more.title")
    }
}
```

- [ ] **Step 5: Chạy script localization**

Run: `python scripts/check_localization.py`
Expected: `0 error(s)`. Mọi key dùng trong 4 bước trên đã có trong catalog Task 18.

- [ ] **Step 6: Commit**

```bash
git add Packages/Features
git commit -m "feat(features): add setup, home list, placeholder tabs and settings screens"
```

---

### Task 20: App target (XcodeGen), composition root, root navigation, CI `ios.yml`

**Files:**
- Create: `project.yml`
- Create: `App/ConstructionApp.swift`, `AppContainer.swift`, `LaunchOptions.swift`, `RootView.swift`, `RootTabView.swift`, `DatabaseErrorView.swift`
- Create: `App/Resources/Assets.xcassets/Contents.json`, `App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`, `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (sinh bằng `scripts/make_app_icon.py`)
- Create: `scripts/make_app_icon.py`
- Create: `App/Info.plist`
- Create: `.github/workflows/ios.yml`

**Interfaces:**
- Consumes: mọi package.
- Produces:
  - `struct LaunchOptions { isUITesting: Bool; seedSampleData: Bool; localeOverride: String?; appearanceOverride: String?; static func parse(_ args: [String]) -> LaunchOptions }` — đọc `--ui-testing`, `--seed-sample-data`, `--locale <en|vi>`, `--appearance <light|dark>`.
  - `@Observable final class AppContainer { state: State (.loading | .ready(Ready) | .failed(Error)); func load() async; func retry() async }` với `Ready { database, companyRepository, customerRepository, projectRepository, settings, setup: CompanySetup? }`.
  - `RootView` chuyển giữa `SetupView`, `RootTabView`, `DatabaseErrorView`; áp `.environment(\.locale, settings.resolvedLocale)` và `.preferredColorScheme(settings.colorScheme)`.
  - Tab accessibility identifiers: `tab_home`, `tab_projects`, `tab_calendar`, `tab_expenses`, `tab_more`.

- [ ] **Step 1: `project.yml`**

Thay `BUNDLE_ID_PLACEHOLDER` bằng bundle id thật (ví dụ `com.yourname.constructionmanagement`) và `TEAM_ID_PLACEHOLDER` bằng Team ID Apple Developer. Giá trị này không phải secret.

```yaml
name: ConstructionManagement
options:
  bundleIdPrefix: BUNDLE_ID_PLACEHOLDER
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "16.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.10"
    DEVELOPMENT_TEAM: TEAM_ID_PLACEHOLDER
    CODE_SIGN_STYLE: Manual
    SWIFT_STRICT_CONCURRENCY: targeted
    CURRENT_PROJECT_VERSION: 1
packages:
  Domain:
    path: Packages/Domain
  Data:
    path: Packages/Data
  DesignSystem:
    path: Packages/DesignSystem
  Features:
    path: Packages/Features
targets:
  ConstructionManagement:
    type: application
    platform: iOS
    sources:
      - path: App
        excludes: ["Info.plist"]
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Construction Management
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        ITSAppUsesNonExemptEncryption: false
        CFBundleLocalizations: [en, vi]
        CFBundleDevelopmentRegion: en
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: BUNDLE_ID_PLACEHOLDER
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ENABLE_USER_SCRIPT_SANDBOXING: false
      configs:
        Debug:
          CODE_SIGN_IDENTITY: ""
          CODE_SIGNING_REQUIRED: false
          CODE_SIGNING_ALLOWED: false
        Release:
          CODE_SIGN_IDENTITY: "iPhone Distribution"
          PROVISIONING_PROFILE_SPECIFIER: "match AppStore BUNDLE_ID_PLACEHOLDER"
    dependencies:
      - package: Domain
      - package: Data
      - package: DesignSystem
      - package: Features
  ConstructionManagementUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: BUNDLE_ID_PLACEHOLDER.uitests
        CODE_SIGNING_ALLOWED: false
    dependencies:
      - target: ConstructionManagement
schemes:
  ConstructionManagement:
    build:
      targets:
        ConstructionManagement: all
        ConstructionManagementUITests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets: [ConstructionManagementUITests]
    archive:
      config: Release
```

`App/Info.plist` được XcodeGen sinh từ `info.properties`; tạo file rỗng hợp lệ để tránh lỗi khi generate lần đầu:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

`App/Resources/Assets.xcassets/Contents.json`:

```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

App icon: App Store Connect từ chối upload không có icon 1024×1024. Tạo icon tạm bằng script Python thuần (không cần Pillow), chạy một lần và commit PNG:

`scripts/make_app_icon.py`:

```python
#!/usr/bin/env python3
"""Writes a 1024x1024 placeholder app icon (orange field, white beam-and-post mark) without Pillow."""
import pathlib, struct, zlib

SIZE = 1024
BG = (0xD9, 0x65, 0x1F)
FG = (0xFF, 0xFF, 0xFF)
OUT = pathlib.Path(__file__).resolve().parents[1] / "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

def inside_mark(x, y):
    # Horizontal beam
    if 192 <= x < 832 and 300 <= y < 420:
        return True
    # Two posts
    if (272 <= x < 392 or 632 <= x < 752) and 420 <= y < 760:
        return True
    return False

def png_chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

def main():
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # filter: none
        for x in range(SIZE):
            rows.extend(FG if inside_mark(x, y) else BG)
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + png_chunk(b"IEND", b"")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png)
    print(f"wrote {OUT} ({len(png)} bytes)")

if __name__ == "__main__":
    main()
```

Run: `python scripts/make_app_icon.py`
Expected: file `AppIcon-1024.png` khoảng 10–20 KB, mở ra là nền cam với hình dầm trắng. Icon không có alpha (RGB, color type 2) đúng yêu cầu App Store.

`App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [ { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Trong `project.yml`, target `ConstructionManagement` → `settings.base` thêm `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. Icon thật (do designer làm) thay file PNG này sau, không đổi cấu hình.

- [ ] **Step 2: `LaunchOptions.swift`**

```swift
import Foundation

struct LaunchOptions {
    var isUITesting = false
    var seedSampleData = false
    var localeOverride: String?
    var appearanceOverride: String?

    static func parse(_ args: [String] = CommandLine.arguments) -> LaunchOptions {
        var options = LaunchOptions()
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--ui-testing": options.isUITesting = true
            case "--seed-sample-data": options.seedSampleData = true
            case "--locale": options.localeOverride = iterator.next()
            case "--appearance": options.appearanceOverride = iterator.next()
            default: break
            }
        }
        return options
    }
}
```

- [ ] **Step 3: `AppContainer.swift`**

```swift
import Foundation
import Observation
import Domain
import Data
import FeatureSupport

@Observable
@MainActor
final class AppContainer {
    struct Ready {
        let database: AppDatabase
        let companyRepository: any CompanyRepository
        let customerRepository: any CustomerRepository
        let projectRepository: any ProjectRepository
        var setup: CompanySetup?
    }

    enum State {
        case loading
        case ready(Ready)
        case failed(Error)
    }

    private(set) var state: State = .loading
    let settings: AppSettings
    let options: LaunchOptions

    init(options: LaunchOptions = .parse()) {
        self.options = options
        let defaults: UserDefaults = options.isUITesting ? UserDefaults(suiteName: "ui-testing") ?? .standard : .standard
        if options.isUITesting { defaults.removePersistentDomain(forName: "ui-testing") }
        self.settings = AppSettings(defaults: defaults)
        if let locale = options.localeOverride { settings.language = locale == "vi" ? .vietnamese : .english }
        if let appearance = options.appearanceOverride { settings.appearance = appearance == "dark" ? .dark : .light }
    }

    static var databaseURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ConstructionManagement", isDirectory: true).appendingPathComponent("construction.sqlite")
    }

    func load() async {
        state = .loading
        do {
            let database = options.isUITesting ? try AppDatabase.inMemory() : try AppDatabase.onDisk(at: AppContainer.databaseURL)
            let clock = Clock.system
            let companies = GRDBCompanyRepository(database: database, clock: clock)
            var ready = Ready(database: database,
                              companyRepository: companies,
                              customerRepository: GRDBCustomerRepository(database: database, clock: clock),
                              projectRepository: GRDBProjectRepository(database: database, clock: clock),
                              setup: nil)
            #if DEBUG
            if options.seedSampleData {
                ready.setup = try await SampleData.seedIfEmpty(database, clock: clock)
            }
            #endif
            if ready.setup == nil { ready.setup = try await companies.current() }
            state = .ready(ready)
        } catch {
            state = .failed(error)
        }
    }

    func completeSetup(_ setup: CompanySetup) {
        guard case .ready(var ready) = state else { return }
        ready.setup = setup
        state = .ready(ready)
    }

    func retry() async { await load() }
}
```

- [ ] **Step 4: `RootView.swift`, `RootTabView.swift`, `DatabaseErrorView.swift`**

`RootView.swift`:

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport
import SetupFeature

struct RootView: View {
    @Bindable var container: AppContainer

    var body: some View {
        Group {
            switch container.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(DSColor.background)
            case .failed(let error):
                DatabaseErrorView(error: error, databaseURL: AppContainer.databaseURL) { Task { await container.retry() } }
            case .ready(let ready):
                if let setup = ready.setup {
                    RootTabView(ready: ready, setup: setup, settings: container.settings)
                } else {
                    SetupView(viewModel: SetupViewModel(companyRepository: ready.companyRepository) { container.completeSetup($0) },
                              settings: container.settings)
                }
            }
        }
        .environment(\.locale, container.settings.resolvedLocale)
        .preferredColorScheme(container.settings.colorScheme)
        .task { if case .loading = container.state { await container.load() } }
    }
}
```

`RootTabView.swift`:

```swift
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport
import HomeFeature
import ProjectsFeature
import CalendarFeature
import ExpensesFeature
import MoreFeature

struct RootTabView: View {
    let ready: AppContainer.Ready
    let setup: CompanySetup
    let settings: AppSettings

    var body: some View {
        TabView {
            NavigationStack { HomeView(viewModel: HomeViewModel(projectRepository: ready.projectRepository, companyId: setup.company.id)) }
                .tabItem { Label("tab.home", systemImage: "house") }
                .accessibilityIdentifier("tab_home")
            NavigationStack { ProjectsPlaceholderView() }
                .tabItem { Label("tab.projects", systemImage: "folder") }
                .accessibilityIdentifier("tab_projects")
            NavigationStack { CalendarPlaceholderView() }
                .tabItem { Label("tab.calendar", systemImage: "calendar") }
                .accessibilityIdentifier("tab_calendar")
            NavigationStack { ExpensesPlaceholderView() }
                .tabItem { Label("tab.expenses", systemImage: "receipt") }
                .accessibilityIdentifier("tab_expenses")
            NavigationStack { MoreView(settings: settings, company: setup.company, showsGallery: showsGallery) }
                .tabItem { Label("tab.more", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("tab_more")
        }
        .tint(DSColor.accent)
    }

    private var showsGallery: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
```

`DatabaseErrorView.swift`:

```swift
import SwiftUI
import DesignSystem

struct DatabaseErrorView: View {
    let error: Error
    let databaseURL: URL
    let retry: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            EmptyState(systemImage: "externaldrive.badge.exclamationmark", title: "error.database.title", message: "error.database.message")
            Text(verbatim: String(describing: error)).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary).padding(.horizontal, DSSpacing.lg)
            VStack(spacing: DSSpacing.md) {
                PrimaryButton("error.database.retry", systemImage: "arrow.clockwise", action: retry)
                if FileManager.default.fileExists(atPath: databaseURL.path) {
                    ShareLink(item: databaseURL) {
                        Label("error.database.export", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: DSSpacing.primaryButtonHeight)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
        .padding(.bottom, DSSpacing.xl)
        .background(DSColor.background)
    }
}
```

- [ ] **Step 5: `ConstructionApp.swift`**

```swift
import SwiftUI

@main
struct ConstructionApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
```

- [ ] **Step 6: `.github/workflows/ios.yml`** (build + Data tests + lint; UI test và screenshot thêm ở Task 21)

```yaml
name: ios

on:
  push:
  pull_request:

concurrency:
  group: ios-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    runs-on: macos-15
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable
      - name: Install tools
        run: brew install xcodegen xcbeautify
      - name: Lint and localization checks
        run: |
          python3 scripts/check_localization.py
          python3 scripts/lint_sources.py
      - name: Data package tests
        run: swift test --package-path Packages/Data
      - name: Generate Xcode project
        run: xcodegen generate
      - name: Pick simulator
        id: sim
        run: |
          UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print(next(x['udid'] for k in sorted(d, reverse=True) if 'iOS' in k for x in d[k] if x['name'].startswith('iPhone 16') and x['isAvailable']))")
          echo "udid=$UDID" >> "$GITHUB_OUTPUT"
      - name: Build app
        run: |
          xcodebuild build \
            -project ConstructionManagement.xcodeproj \
            -scheme ConstructionManagement \
            -destination "id=${{ steps.sim.outputs.udid }}" \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO \
            -skipPackagePluginValidation \
            | xcbeautify --quiet || exit ${PIPESTATUS[0]}
```

- [ ] **Step 7: Push và xem CI**

Run: `git add project.yml App scripts/make_app_icon.py .github/workflows/ios.yml && git commit -m "feat(app): add XcodeGen app target, composition root and iOS CI" && git push`
Expected: job `ios / build-and-test` xanh. Lỗi biên dịch SwiftUI chỉ lộ ở đây; sửa và push lại cho tới khi xanh (giữ mỗi lần sửa là một commit nhỏ, tiền tố `fix(app):`). Nếu `Pick simulator` không tìm thấy `iPhone 16`: đổi tiền tố thành `iPhone` để lấy máy đầu tiên.

Lưu ý: repo GitHub phải tồn tại trước bước này — xem Task 22 Step 1 (tạo repo public) và làm bước đó trước nếu chưa có remote.

---

### Task 21: UI smoke test + screenshot artifact

**Files:**
- Create: `UITests/SmokeTests.swift`, `UITests/ScreenshotTests.swift`
- Modify: `.github/workflows/ios.yml`

**Interfaces:**
- Consumes: launch options `--ui-testing --seed-sample-data --locale --appearance`, identifiers `tab_*`, `setup_*`, `home_list`, `more_settings`, `more_gallery`, `settings_language_picker`, `component_gallery`.

- [ ] **Step 1: `SmokeTests.swift`**

```swift
import XCTest

final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extra
        app.launch()
        return app
    }

    func testSetupFlowCreatesCompanyAndShowsTabs() {
        let app = launch(["--locale", "en"])
        let company = app.textFields["setup_company_name"]
        XCTAssertTrue(company.waitForExistence(timeout: 10))
        company.tap(); company.typeText("Northwind Contracting")
        let owner = app.textFields["setup_owner_name"]
        owner.tap(); owner.typeText("Duc")
        app.buttons["setup_start"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No jobs yet"].exists)
    }

    func testAllTabsOpenWithSeedData() {
        let app = launch(["--seed-sample-data", "--locale", "en"])
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["123 Main Street"].waitForExistence(timeout: 5))
        for (tab, title) in [("Projects", "Projects"), ("Calendar", "Calendar"), ("Expenses", "Expenses"), ("More", "More")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "tab \(tab)")
        }
    }

    func testLanguageSwitchUpdatesOpenScreenAndTabsImmediately() {
        let app = launch(["--seed-sample-data", "--locale", "en"])
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 10))
        app.tabBars.buttons["More"].tap()
        app.buttons["more_settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Tiếng Việt"].tap()
        // Review Focus #5: the open screen and the tab bar change without leaving the screen.
        XCTAssertTrue(app.navigationBars["Cài đặt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Trang chủ"].exists)
        XCTAssertTrue(app.tabBars.buttons["Chi phí"].exists)
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 2: `ScreenshotTests.swift`**

```swift
import XCTest

final class ScreenshotTests: XCTestCase {
    private func launch(locale: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", locale, "--appearance", appearance]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureAllScreens() {
        let tabs = ["home", "projects", "calendar", "expenses", "more"]
        for locale in ["en", "vi"] {
            for appearance in ["light", "dark"] {
                let app = launch(locale: locale, appearance: appearance)
                XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
                let tabButtons = app.tabBars.buttons
                for (index, tab) in tabs.enumerated() {
                    tabButtons.element(boundBy: index).tap()
                    _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)
                    snap(app, "\(tab)_\(locale)_\(appearance)")
                }
                app.buttons["more_gallery"].tap()
                XCTAssertTrue(app.scrollViews["component_gallery"].waitForExistence(timeout: 5))
                snap(app, "gallery_\(locale)_\(appearance)")
                app.terminate()
            }
        }
    }
}
```

- [ ] **Step 3: Thêm bước test + xuất screenshot vào `ios.yml`** (sau bước Build app)

```yaml
      - name: UI tests
        run: |
          xcodebuild test \
            -project ConstructionManagement.xcodeproj \
            -scheme ConstructionManagement \
            -destination "id=${{ steps.sim.outputs.udid }}" \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO \
            -skipPackagePluginValidation \
            -resultBundlePath build/UITests.xcresult \
            | xcbeautify --quiet || exit ${PIPESTATUS[0]}
      - name: Export screenshots
        if: always()
        run: |
          brew install chargepoint/xcparse/xcparse
          mkdir -p build/screenshots
          xcparse screenshots build/UITests.xcresult build/screenshots || true
          ls -R build/screenshots | head -50
      - name: Upload screenshots
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: screenshots
          path: build/screenshots
          if-no-files-found: warn
      - name: Upload test results
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: xcresult
          path: build/UITests.xcresult
```

- [ ] **Step 4: Push, xem CI, tải artifact `screenshots`**

Run: `git add UITests .github/workflows/ios.yml && git commit -m "test(app): add UI smoke tests and screenshot capture" && git push`
Expected: job xanh; artifact có 24 ảnh (6 màn × en/vi × light/dark). Mở vài ảnh để kiểm tra: tab bản vi là "Trang chủ, Dự án, Lịch, Chi phí, Thêm"; dark mode nền tối; card Home có badge + progress bar.

Nếu `testLanguageSwitchUpdatesOpenScreenAndTabsImmediately` fail vì `Text` không đổi theo `\.locale`: chuyển localization sang cách tường minh — thêm vào `FeatureSupport` một `LocalizedBundle` chọn `Bundle.main.path(forResource: code, ofType: "lproj")` theo `settings.resolvedLocale`, và tạo `extension Text { init(key: String, bundle: Bundle) }`; thay mọi `Text("a.b")` trong Features/App bằng `Text(key:bundle:)` đọc bundle từ environment. Ghi lại thay đổi này trong plan trước khi làm.

---

### Task 22: fastlane + `testflight.yml` + `docs/SETUP.md`

**Files:**
- Create: `Gemfile`, `fastlane/Appfile`, `fastlane/Fastfile`, `fastlane/Matchfile`
- Create: `.github/workflows/testflight.yml`
- Create: `docs/SETUP.md`

**Interfaces:**
- Consumes: `project.yml` (Release ký bằng `match AppStore <bundle id>`).
- Produces: lane `setup_signing` (chạy một lần, tạo cert + profile vào repo match) và lane `beta` (build + upload TestFlight). Secrets: `MATCH_GIT_URL`, `MATCH_GIT_BASIC_AUTHORIZATION`, `MATCH_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`, `APP_BUNDLE_ID`, `APPLE_TEAM_ID`.

- [ ] **Step 1: `Gemfile`**

```ruby
source "https://rubygems.org"
gem "fastlane", "~> 2.220"
```

- [ ] **Step 2: `fastlane/Appfile`, `Matchfile`, `Fastfile`**

`Appfile`:

```ruby
app_identifier(ENV["APP_BUNDLE_ID"])
team_id(ENV["APPLE_TEAM_ID"])
```

`Matchfile`:

```ruby
git_url(ENV["MATCH_GIT_URL"])
storage_mode("git")
type("appstore")
app_identifier([ENV["APP_BUNDLE_ID"]])
readonly(true)
```

`Fastfile`:

```ruby
default_platform(:ios)

platform :ios do
  before_all do
    setup_ci if ENV["CI"]
    app_store_connect_api_key(
      key_id: ENV["ASC_KEY_ID"],
      issuer_id: ENV["ASC_ISSUER_ID"],
      key_content: ENV["ASC_KEY_CONTENT"],
      is_key_content_base64: true,
      in_house: false
    )
  end

  desc "One-time: create distribution certificate and App Store profile in the match repo"
  lane :setup_signing do
    match(type: "appstore", readonly: false)
  end

  desc "Build and upload to TestFlight (the workflow runs `xcodegen generate` before this lane)"
  lane :beta do
    match(type: "appstore", readonly: true)
    build_app(
      project: "ConstructionManagement.xcodeproj",
      scheme: "ConstructionManagement",
      configuration: "Release",
      export_method: "app-store",
      output_directory: "build",
      xcargs: "-skipPackagePluginValidation CURRENT_PROJECT_VERSION=#{ENV['BUILD_NUMBER']}"
    )
    upload_to_testflight(skip_waiting_for_build_processing: true)
  end
end
```

- [ ] **Step 3: `.github/workflows/testflight.yml`**

```yaml
name: testflight

on:
  workflow_dispatch:
    inputs:
      lane:
        description: "fastlane lane"
        required: true
        default: beta
        type: choice
        options: [beta, setup_signing]
  push:
    tags: ["v*"]

jobs:
  deploy:
    runs-on: macos-15
    timeout-minutes: 60
    if: github.event_name != 'pull_request'
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - name: Install tools
        run: brew install xcodegen
      - name: Generate Xcode project
        run: xcodegen generate
      - name: Run fastlane
        env:
          APP_BUNDLE_ID: ${{ secrets.APP_BUNDLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          MATCH_GIT_URL: ${{ secrets.MATCH_GIT_URL }}
          MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_BASIC_AUTHORIZATION }}
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}
          BUILD_NUMBER: ${{ github.run_number }}
        run: bundle exec fastlane ios ${{ github.event.inputs.lane || 'beta' }}
```

- [ ] **Step 4: `docs/SETUP.md`** — hướng dẫn cho người dùng, tiếng Việt, làm một lần

```markdown
# Thiết lập GitHub, ký app và TestFlight

Làm một lần. Không có bước nào cần Mac.

## 1. Repo GitHub

1. Tạo repo **public** `construction-management` trên GitHub, không khởi tạo README.
2. Trong thư mục dự án: `git remote add origin https://github.com/<user>/construction-management.git && git push -u origin main`.
3. Settings → Code security → bật **Secret scanning** và **Push protection**.

## 2. Repo private cho chứng chỉ (fastlane match)

1. Tạo repo **private** `ios-certificates`, trống.
2. Tạo Personal Access Token (classic) chỉ có scope `repo`. Lưu tạm.
3. Tính giá trị `MATCH_GIT_BASIC_AUTHORIZATION`: trong PowerShell
   `[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("<github-user>:<token>"))`.
4. Chọn một mật khẩu dài làm `MATCH_PASSWORD` (mã hóa chứng chỉ trong repo).

## 3. Apple Developer / App Store Connect

1. developer.apple.com → Identifiers → tạo App ID với bundle id, ví dụ `com.<ten>.constructionmanagement`. Không cần capability nào.
2. appstoreconnect.apple.com → Apps → New App → iOS, tên "Construction Management", bundle id vừa tạo, SKU tùy ý.
3. Users and Access → Integrations → App Store Connect API → Generate key, role **App Manager**. Tải file `.p8` (chỉ tải được một lần). Ghi lại **Key ID** và **Issuer ID**.
4. `ASC_KEY_CONTENT` = base64 của file `.p8`: PowerShell
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))`.
5. Team ID: developer.apple.com → Membership details.

## 4. GitHub Secrets (repo public → Settings → Secrets and variables → Actions)

| Secret | Giá trị |
|---|---|
| `APP_BUNDLE_ID` | bundle id |
| `APPLE_TEAM_ID` | Team ID |
| `MATCH_GIT_URL` | `https://github.com/<user>/ios-certificates.git` |
| `MATCH_GIT_BASIC_AUTHORIZATION` | chuỗi base64 ở mục 2.3 |
| `MATCH_PASSWORD` | mật khẩu ở mục 2.4 |
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_CONTENT` | base64 của `.p8` |

## 5. Điền bundle id và Team ID vào `project.yml`

Thay `BUNDLE_ID_PLACEHOLDER` và `TEAM_ID_PLACEHOLDER`, commit, push.

## 6. Tạo chứng chỉ (một lần)

Actions → workflow **testflight** → Run workflow → lane `setup_signing`. Thành công thì repo `ios-certificates` có thư mục `certs/` và `profiles/` đã mã hóa.

## 7. Đẩy TestFlight

Actions → **testflight** → Run workflow → lane `beta` (hoặc push tag `v0.1.0`). Sau 5–15 phút, build xuất hiện trong App Store Connect → TestFlight. Thêm Apple ID của bạn vào Internal Testing, cài app TestFlight trên iPhone, nhận build.

## Khi gặp lỗi

- `No matching provisioning profiles`: chạy lại `setup_signing`; kiểm tra `APP_BUNDLE_ID` trùng với App ID.
- `Authentication credentials are missing or invalid` từ match: `MATCH_GIT_BASIC_AUTHORIZATION` sai hoặc token hết hạn.
- `Could not find App` khi upload: app record ở App Store Connect chưa tạo hoặc bundle id khác.
- Build lên TestFlight nhưng không hiện: đợi xử lý xong, kiểm tra email Apple về missing compliance (đã khai `ITSAppUsesNonExemptEncryption = false`).
```

- [ ] **Step 5: Commit, làm theo `docs/SETUP.md` mục 1–7**

```bash
git add Gemfile fastlane .github/workflows/testflight.yml docs/SETUP.md
git commit -m "ci: add fastlane match/TestFlight pipeline and setup guide"
git push
```

Expected: lane `setup_signing` xanh (repo chứng chỉ có nội dung), lane `beta` xanh (archive có icon, bước `upload_to_testflight` không báo `Missing app icon`), build hiện trên TestFlight, cài lên iPhone, qua màn hình setup, thấy 5 tab, đổi ngôn ngữ và giao diện trong Settings có hiệu lực ngay. Đó là tiêu chí hoàn thành 1–5 của spec mục 12.

---

## Thứ tự thực hiện và phụ thuộc

- Task 1–11 (Domain) tuần tự, chạy được hoàn toàn trên Windows (`swift test` nếu cài Swift toolchain) hoặc qua `domain.yml`.
- Task 12–15 (Data) sau Task 11; test chỉ chạy trên macOS (CI). Khi làm trên Windows: viết test + code, push, đọc kết quả CI của job `ios / Data package tests`.
- Task 16–19 (DesignSystem, Features) sau Task 11, song song được với 12–15 nếu dùng hai nhánh; chỉ biên dịch được ở Task 20.
- Task 20 cần repo GitHub (SETUP.md mục 1). Task 22 mục 6–7 cần Apple Developer đã sẵn sàng.

## Ngoài phạm vi (nhắc lại từ spec mục 13)

Dashboard summary, wizard, project detail, form nghiệp vụ, camera, notifications, calendar thật, Supabase, Auth, sync. Không thêm vào plan này.
