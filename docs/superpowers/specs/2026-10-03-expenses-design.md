# ConMa — Sub-project 3a: Expenses + receipts + custom categories

Ngày: 2026-10-03
Trạng thái: chờ review
Tiền đề: 2b merged (`main` 01565fe, TestFlight 0.1.0 (4)). Spec 2b: `docs/superpowers/specs/2026-10-03-dashboard-detail-design.md` (kể cả Errata). Foundation: `docs/superpowers/specs/2026-10-02-foundation-design.md` (§5.1 Money, §5.2 bảng ExpenseCategory→CostGroup và quy tắc `CustomExpenseCategory`, §5.3 financial engine, Phụ lục A — binding cho mọi công thức và cột ở đây).

## 1. Mục tiêu

Contractor đứng ở quầy Home Depot, một tay cầm hóa đơn: bấm "+", chụp receipt, gõ số tiền, chạm một category, Lưu — dưới 15 giây. Ngay sau đó Home, card project và Financial summary của project đã tính chi phí mới (Spent, Cash position, budget alert, health). 3a thêm lớp **nhập liệu chi phí** lên nền 2b: màn nhập "chụp trước, điền sau", tab Chi phí (danh sách theo ngày, tổng tháng này/tháng trước, lọc, tìm), section Chi phí trong project detail, sửa/xóa expense, receipt nhiều trang (VisionKit hoặc Photos) với viewer, custom categories (quản lý + quy tắc `categoryInUse`), thuế theo % và thuế mặc định. Payments và labour/crew là 3b.

## 2. Quyết định đã chốt

| Chủ đề | Quyết định |
|---|---|
| Phạm vi | Sub-project 3 tách đôi: **3a** = Expenses + receipts + custom categories (tài liệu này); **3b** = Payments + Labour/crew. |
| Luồng nhập | "Chụp trước, điền sau": "+" (tab Chi phí, Home, project detail) mở scanner ngay; Cancel trong scanner = bỏ qua ảnh, vào form. Một màn form duy nhất. Bắt buộc: project, amount (> 0), category. Vendor, cách trả, ghi chú gom trong "Thêm chi tiết" (đóng mặc định). |
| Project mặc định | Mở từ project detail → project đó. Còn lại → project của expense **tạo gần nhất** (theo `createdAt`, chưa xóa) nếu project đó còn và không ở phase `terminal`; không có → project `inWork` có `updatedAt` mới nhất; không có → trống (bắt chọn). Picker liệt kê mọi project chưa xóa theo phase inWork, preStart, workDone, terminal (receipt về muộn cho job đã đóng vẫn nhập được). |
| Category nhanh | 6 chip "dùng nhiều nhất": đếm trên 50 expense chưa xóa mới nhất (theo `spentOn` rồi `createdAt`), nhiều lượt trước, hòa thì lượt dùng gần hơn trước; thiếu thì điền theo thứ tự mặc định cố định `materials, fuel, toolPurchase, equipmentRental, subcontractor, delivery, wasteDisposal, permit, inspection, parking, labour, office, other`. Chip "Thêm" mở danh sách đủ 13 category + custom + "Danh mục mới". Category đang chọn luôn có mặt trong hàng chip. |
| Thuế | Một ô số tiền thuế + nút chuyển "%" (nhập ví dụ 13 → thuế = `amount × 13%`, làm tròn half-away-from-zero 2 chữ số qua `Money`). Chỉ lưu số tiền thuế (Foundation: một ô tax); % không lưu. Settings có "Thuế mặc định %" (trống = không có), lưu `UserDefaults` theo máy; khi có, expense **mới** mở sẵn ở chế độ % với giá trị đó (tự tính khi gõ amount); người dùng sửa được. Sửa expense cũ mở ở chế độ số tiền. |
| Sửa / xóa | Chạm dòng expense → cùng form ở chế độ sửa (không có màn chi tiết riêng). Xóa ở cuối form → xác nhận → soft delete expense + receipt rows; **file ảnh giữ trên đĩa** (dọn ở sub-project 5). Không undo. |
| Snapshot `costGroup` | Data là nguồn quyết định: tạo mới → built-in theo bảng Foundation, custom chép group **hiện tại** của custom category. Sửa → chỉ chụp lại khi người dùng đổi category; giữ nguyên category thì giữ `costGroup` cũ (đổi group của custom category sau này không đổi chi phí lịch sử). |
| Activity log | Thêm `ActivityAction.expenseUpdated`, `.expenseDeleted` (cột `activity_log.action` không có CHECK → không migration). `expenseAdded`/`expenseUpdated`/`expenseDeleted` ghi trong cùng transaction, `entity_type = "expense"`, `project_id` = project của expense. Lưu không đổi gì → không ghi, không stamp `updated_at`. Category không ghi activity (không phải dữ liệu tiền). |
| Custom categories | Quản lý ở Thêm → "Danh mục chi phí"; tạo nhanh được ngay trong picker category của form. Tên trim, không rỗng, không trùng (so sánh `SearchFold.normalize`) với category custom còn sống → `DomainError.duplicateName`. Đổi tên luôn được. Đổi `costGroup` khi đã từng có expense dùng (kể cả đã xóa) → `DomainError.categoryInUse` (UI khóa chip group và giải thích). Xóa khi còn expense chưa xóa dùng → `DomainError.categoryHasExpenses`. |
| Receipt | VisionKit document scanner (tự cắt, nhiều trang) hoặc Photos (`PhotosPicker`). JPEG cạnh dài ≤ 2000 px, quality 0.7. Tối đa 10 trang/expense (`DomainError.tooManyReceiptPages`; UI cắt bớt và báo). File `Application Support/Receipts/<expenseId>/<imageId>.jpg`, DB lưu đường dẫn tương đối `Receipts/<expenseId>/<imageId>.jpg`. Ghi file trước transaction, transaction lỗi thì xóa file vừa ghi. Sửa: bỏ trang = soft delete row (file giữ), thêm trang = nối cuối, đánh lại `page_index` 0…n−1; không có kéo đổi thứ tự trong 3a. Receipt nằm trong backup iCloud của máy (không exclude). |
| Viewer | Toàn màn hình, lật trang, pinch zoom (1×…5×, double-tap về 1×), "Trang x/y", chia sẻ/xuất mọi trang đã lưu (`ShareLink` các file URL). Trang mới chưa lưu xem được nhưng không chia sẻ. |
| Scanner trong test | `ReceiptCaptureMode.live` / `.fake`. Launch flag `--fake-scanner` (chỉ cùng `--ui-testing`) → màn scanner giả (`scanner_capture` trả 1 trang mẫu, `scanner_cancel`). Ảnh mẫu vẽ bằng `SampleReceipt` (UIGraphicsImageRenderer) — không có file nhị phân trong repo. `.live` trên máy không hỗ trợ VisionKit (simulator) → bỏ qua scanner, vào thẳng form. |
| Tab Chi phí | Mọi expense nhóm theo ngày (`spentOn` giảm dần; trong ngày `createdAt` giảm dần), mỗi ngày có tổng. Đầu trang: tổng **tháng này** và **tháng trước** (theo `spentOn`, tháng dương lịch của `today`), áp bộ lọc project + category nhưng **không** áp ô tìm. Lọc: chip-menu project, chip-menu category. Tìm: vendor hoặc notes, `SearchFold.normalize`, chứa chuỗi. Dòng: icon category, vendor (hoặc tên category nếu trống), tên project, tổng (amount + tax), dấu receipt kèm số trang. |
| Project detail | Section "Chi phí" ngay sau Financial summary: 5 expense mới nhất (cùng thứ tự tab) + "Xem tất cả" (đẩy màn danh sách đã lọc theo project, bỏ lọc được) + nút "+" (form với project đó). |
| Home | Thêm nút nổi "Thêm chi phí" (`home_add_expense`) góc dưới phải — hành động hay dùng nhất của contractor, một tay. |
| Cập nhật số liệu | Không thêm cơ chế mới: `GRDBInsightsRepository` đã quan sát bảng `expenses` → Home, card, Financial summary, budget alert, health tự cập nhật sau Lưu/Sửa/Xóa. UI test (a) chứng minh. |
| Carry-over từ 2b | Làm: câu có số tiền format theo currency của chính `Money` (bỏ tham số `currency:` khỏi `HealthReason.text`, `AttentionItem.text`); dòng activity có `action` lạ bị **bỏ qua** (không làm hỏng stream); `observeDashboard` ném `DomainError.notFound` khi company mất; seed expense đi qua repository (có activity). Để lại: nhãn "Awaiting final payment" cho job đã thu đủ, seed payment/labour bỏ qua activity (3b). |
| Schema | Không migration: `expenses`, `receipt_images`, `custom_expense_categories` của Migration001 đủ. Thuế mặc định không có cột company → `UserDefaults` (ghi nhận để sub-project 5 cân nhắc đồng bộ). |
| Ngôn ngữ | Giữ tiếng Anh trong bản vi: receipt, Material, Labour, Subcontractor, Permit, Inspection, e-Transfer, Cheque. Dịch: Vendor → "Nhà cung cấp", Tax → "Thuế", Category → "Danh mục", Expense → "Chi phí". |

### 2.1 Ràng buộc chung (plan chép nguyên văn)

- Domain imports Foundation only; Features never imports Data; DesignSystem never imports Domain. `scripts/lint_sources.py` must pass (no `Double`/`Float`/`CGFloat` in Domain/Data; no `try!`/`as!`/`fatalError` in production).
- Money is `Money` (Decimal, 2 dp, `Money.rounded` half-away-from-zero); a tax percent always goes through `Percentage.input`. Domain never calls `Date()`; `today: CalendarDate` and `now: Date` are passed in.
- Soft-deleted rows never take part in any calculation or list (`deleted_at IS NULL` in every query; composers also filter `isDeleted`). Receipt files are never deleted, except files written by an insert whose transaction failed.
- Every expense write (create, update, delete) and its `activity_log` row happen in one transaction; an update that changes nothing writes nothing.
- No schema migration: the Migration001 tables are used as they are.
- All user-visible strings are keys in `App/Resources/Localizable.xcstrings` with `en` + `vi`; user data is rendered with `Text(verbatim:)`. Trade terms stay English in vi (receipt, Material, Labour, Subcontractor, Permit, Inspection, e-Transfer, Cheque). `python scripts/check_localization.py` must report 0 errors.
- Every VM is `@Observable @MainActor`, owned by an `@State` wrapper in `App/Screens.swift`, never constructed in `body`.
- Accessibility identifiers exactly as listed in spec §5 and the UI-test task.
- The 2b seed numbers do not change; `UITests/DashboardFlowTests.swift` is not edited.
- Commits: `type(scope): summary`, English, **no trailers** (no Co-Authored-By).
- CI: `ios.yml` is the verifier for Data/Features/App; Domain is verified locally with `swift test --package-path Packages/Domain`. Known flake: Foundation `testLanguageSwitchUpdatesOpenScreenAndTabsImmediately` / screenshot launch timeout → rerun failed jobs once.

## 3. Domain

Thư mục mới `Packages/Domain/Sources/Domain/Expenses/`. Foundation-only, `Sendable`, test trên Linux/Windows.

### 3.1 Category choice, ranking, project mặc định

```swift
public enum ExpenseCategoryChoice: Hashable, Sendable {
    case standard(ExpenseCategory)   // không bao giờ .custom
    case custom(UUID)
    public init(_ expense: Expense)  // .custom + id → .custom(id); .custom thiếu id → .standard(.other)
    public static let defaultOrder: [ExpenseCategory]   // §2 "Category nhanh"
}

public enum CategoryRanking {
    public static let window = 50
    public static func mostUsed(expenses: [Expense], customCategories: [CustomExpenseCategory], limit: Int = 6) -> [ExpenseCategoryChoice]
}

public enum ExpenseProjectChoice {
    public static func ordered(_ projects: [Project]) -> [Project]                     // bỏ đã xóa; phase inWork, preStart, workDone, terminal; rồi tên
    public static func defaultProject(expenses: [Expense], projects: [Project]) -> UUID? // §2 "Project mặc định"
}
```

`mostUsed` bỏ expense đã xóa và custom category đã xóa/không tồn tại.

### 3.2 `ExpenseDraft`

```swift
public enum TaxInput: Hashable, Sendable { case none, amount(Decimal), percent(Decimal) }
public enum ExpenseDraftError: Hashable, Sendable {
    case projectMissing, amountMissing, amountNotPositive, categoryMissing, taxNegative, taxPercentOutOfRange
}
public struct ExpenseDraft: Hashable, Sendable {
    public var projectId: UUID?
    public var amount: Decimal?
    public var category: ExpenseCategoryChoice?
    public var tax: TaxInput
    public var spentOn: CalendarDate
    public var vendorName: String
    public var paymentMethod: PaymentMethod?
    public var notes: String
    public init(projectId: UUID?, spentOn: CalendarDate, defaultTaxPercent: Decimal?)   // tax = .percent(d) hoặc .none
    public init(editing expense: Expense)                                               // tax = .amount(tax) hoặc .none khi 0
    public func taxMoney(currency: CurrencyCode) -> Money?    // nil khi % chưa tính được (thiếu amount hoặc % sai)
    public func total(currency: CurrencyCode) -> Money?       // amount + tax
    public var errors: [ExpenseDraftError] { get }            // theo thứ tự khai báo
    public var canSave: Bool { get }
    public func makeExpense(id: UUID, companyId: UUID, currency: CurrencyCode, customCategories: [CustomExpenseCategory], now: Date) throws -> Expense
    public func apply(to existing: Expense, customCategories: [CustomExpenseCategory], now: Date) throws -> Expense
}
```

- `.percent(p)`: `Percentage.input(p)` (0…100, ≤ 2 chữ số thập phân), thuế = `Money(amount) × p` (một lần làm tròn). Ngoài khoảng → `taxPercentOutOfRange`.
- `.amount(d)`: `d < 0` → `taxNegative`.
- `makeExpense`/`apply` ném `DomainError.incompleteExpense` khi `errors` khác rỗng; custom category không còn sống → `DomainError.notFound`; vendor/notes trim, rỗng → nil. `apply` giữ `id`, `companyId`, `createdAt`, `receiptImages`; `costGroup` giữ nguyên khi `ExpenseCategoryChoice(existing) == category`, ngược lại resolve lại (`Expense.resolveCostGroup`).

### 3.3 Danh sách

```swift
public struct ExpenseListSnapshot: Hashable, Sendable {
    public var currency: CurrencyCode
    public var expenses: [Expense]                     // chưa xóa, kèm receiptImages chưa xóa theo pageIndex
    public var projects: [Project]                     // chưa xóa
    public var customCategories: [CustomExpenseCategory]  // mọi dòng, kể cả đã xóa (để hiện tên lịch sử)
}
public struct ExpenseFilter: Hashable, Sendable { public var projectId: UUID?; public var category: ExpenseCategoryChoice?; public var query: String }
public struct ExpenseRow: Hashable, Sendable, Identifiable {
    public let expense: Expense; public let choice: ExpenseCategoryChoice
    public let customCategoryName: String?; public let projectName: String; public let total: Money
    public var receiptCount: Int { get }; public var id: UUID { get }
}
public struct ExpenseDaySection: Hashable, Sendable, Identifiable { public let day: CalendarDate; public let rows: [ExpenseRow]; public let total: Money }
public struct ExpenseList: Hashable, Sendable {
    public let sections: [ExpenseDaySection]; public let thisMonth: Money; public let lastMonth: Money
    public var rows: [ExpenseRow] { get }
}
public enum ExpenseListComposer {
    public static func compose(_ snapshot: ExpenseListSnapshot, filter: ExpenseFilter, today: CalendarDate) -> ExpenseList
}
```

Tháng trước của tháng 1 là tháng 12 năm trước. Tổng là `Money.sum` của `amount + tax` từng dòng (đã làm tròn).

### 3.4 Quy tắc category và receipt

```swift
public enum CustomCategoryRules {
    public static func validatedName(_ name: String, excluding id: UUID?, existing: [CustomExpenseCategory]) throws -> String   // emptyName, duplicateName
    public static func update(_ category: CustomExpenseCategory, name: String, costGroup: CostGroup, everUsed: Bool, existing: [CustomExpenseCategory]) throws -> CustomExpenseCategory  // categoryInUse
    public static func checkDelete(liveExpenseCount: Int) throws                                                                 // categoryHasExpenses
}
public enum ReceiptRules {
    public static let maxPages = 10
    public static func validate(pageCount: Int) throws            // > 10 → tooManyReceiptPages
    public static func acceptedCount(existing: Int, incoming: Int) -> Int
}
```

`DomainError` thêm `duplicateName`, `tooManyReceiptPages`, `incompleteExpense`.

### 3.5 Activity

`ActivityAction` thêm `expenseUpdated`, `expenseDeleted`. `detailsJSON` của 3 action expense: `{"category":"<raw>","categoryName":"<tên custom hoặc rỗng>","total":"<amount+tax storage>","vendor":"<vendor hoặc rỗng>"}`; `expenseUpdated` thêm `"from":"<total cũ>"` và `"fromProjectId"` khi đổi project.

```swift
public enum ExpenseTitle: Hashable, Sendable { case vendor(String), category(ExpenseCategory), customCategory(String) }
// ActivityDetail thêm:
case expense(action: ActivityAction, title: ExpenseTitle, total: String, previousTotal: String?)
```

Thiếu `total` hoặc category lạ → `.plain(action)`. Vendor khác rỗng thắng; category `custom` → `.customCategory(categoryName)`.

### 3.6 Repository protocols

```swift
public struct ReceiptChange: Hashable, Sendable {
    public var keptImageIds: [UUID]   // trang cũ giữ lại, theo thứ tự mới
    public var newPages: [Data]       // JPEG nối sau
}
public protocol ExpenseRepository: Sendable {
    func observeAll(companyId: UUID) -> AsyncThrowingStream<ExpenseListSnapshot, Error>
    func get(id: UUID) async throws -> Expense?                                         // nil khi mất/đã xóa; kèm receipts
    func create(_ expense: Expense, receiptPages: [Data], actor: ActivityActor) async throws
    func update(_ expense: Expense, receipts: ReceiptChange, actor: ActivityActor) async throws
    func softDelete(id: UUID, actor: ActivityActor) async throws
    func fileURL(for image: ReceiptImage) -> URL
}
public struct CustomCategoryUsage: Hashable, Sendable, Identifiable {
    public let category: CustomExpenseCategory; public let liveExpenseCount: Int; public let everUsed: Bool
}
public protocol CustomCategoryRepository: Sendable {
    func observeAll(companyId: UUID) -> AsyncThrowingStream<[CustomCategoryUsage], Error>   // chưa xóa, theo tên (không phân biệt hoa thường)
    func create(_ category: CustomExpenseCategory) async throws
    func update(id: UUID, name: String, costGroup: CostGroup) async throws
    func softDelete(id: UUID) async throws
}
```

## 4. Data

- Records mới: `ReceiptImageRecord` (`receipt_images`), `CustomExpenseCategoryRecord` (`custom_expense_categories`); `ExpenseRecord` thêm `Equatable` và `toDomain(currency:receipts:)`.
- `FileReceiptStore(root:)`: `write(_:expenseId:imageId:) throws -> String` (tạo thư mục, ghi atomic, trả path tương đối), `url(for:)`, `remove(relativePath:)` (best effort). App: root = Application Support; UI testing: `tmp/conma-ui-receipts` (xóa mỗi lần launch).
- `GRDBExpenseRepository(database:clock:receiptStore:)`:
  - `observeAll`: một `ValueObservation` đọc projects, expenses, receipt_images, custom_expense_categories của company.
  - `create`: `validate()`, `ReceiptRules.validate`, ghi file; transaction: currency khớp company (`currencyMismatch`), project sống cùng company (`notFound`), snapshot group (§2), insert expense + receipt rows + `expenseAdded`. Lỗi → xóa file vừa ghi, ném lại.
  - `update`: expense sống (`notFound`), project sống, `keptImageIds` ⊆ trang sống (`notFound`), không đổi gì → return; soft delete trang bỏ, đánh lại `page_index` hai lượt (+1000 rồi về 0…), insert trang mới, `expenseUpdated`.
  - `softDelete`: expense + receipt rows, `expenseDeleted`; file giữ.
- `GRDBCustomCategoryRepository(database:clock:)`: `observeAll` (kèm `COUNT` expense sống và mọi expense); `create`/`update`/`softDelete` trong transaction dùng `CustomCategoryRules`.
- `GRDBActivityLogRepository`: bỏ qua dòng có `action` không thuộc `ActivityAction`.
- `GRDBInsightsRepository.observeDashboard`: company mất → `DomainError.notFound`.
- `SampleData.seedIfEmpty(_:clock:today:receiptStore:sampleReceipt:)` (2 tham số mới, mặc định nil): expense đi qua `GRDBExpenseRepository` (3 dòng `expenseAdded`); Drywall đổi ngày sang **today−2** (tiền giữ nguyên → mọi số 2b không đổi); receipt: Lumber 2 trang, Dumpster 1 trang (khi có `sampleReceipt`); custom category "Scaffolding" (equipment, chưa dùng).

Số liệu seed với `today = 2026-10-03` (hợp đồng cho test và screenshot):

| Expense | Project | Category | Ngày | Amount + tax = Total | Receipt |
|---|---|---|---|---|---|
| Lumber — Home Depot | Basement | materials | 2026-09-18 (−15) | 2,400 + 312 = 2,712.00 | 2 trang |
| Dumpster rental | Basement | wasteDisposal | 2026-09-17 (−16) | 600 + 78 = 678.00 | 1 trang |
| Drywall | Basement | materials | **2026-10-01 (−2)** | 1,500 + 195 = 1,695.00 | – |

- Tháng này (10/2026): **1,695.00**; tháng trước (09/2026): **3,390.00**. Sections: 2026-10-01 (1,695.00), 2026-09-18 (2,712.00), 2026-09-17 (678.00).
- Category nhanh: `[materials, wasteDisposal, fuel, toolPurchase, equipmentRental, subcontractor]`. Project mặc định: Basement.
- Dashboard 2b giữ nguyên: spent 10,685; cash 15,415; Basement cash −3,085.

## 5. Features

### 5.1 FeatureSupport

- `ExpenseFormRequest: Identifiable, Hashable { case create(projectId: UUID?), edit(UUID) }` — Home/detail/tab dùng chung để mở form (`fullScreenCover(item:)`).
- `ReceiptCaptureMode { live, fake }`, `ReceiptScannerView(mode:onFinish:onCancel:)` (`.live` bọc `VNDocumentCameraViewController`; `.fake` là `FakeReceiptScannerView`), `ReceiptCaptureMode.isScannerAvailable`.
- `ReceiptImageProcessor.jpeg(from: UIImage) -> Data?` (cạnh dài ≤ 2000, quality 0.7, scale 1); `SampleReceipt.jpeg(vendor:lines:total:) -> Data?`; `KeyboardDismiss.dismiss()`.
- Nhãn: `ExpenseCategory.titleKey/systemImage`, `ExpenseCategoryChoice.title(customName:) -> Text`, `PaymentMethod.titleKey`, `ExpenseDraftError.messageKey`, `ExpenseTitle.text`, `ActivityDetail.expense` trong `ActivityText`.
- Carry-over: `HealthReason.text(locale:)`, `AttentionItem.text(locale:)` dùng `money.currency`.
- `AppSettings.defaultTaxPercent: Decimal?` (key `settings.defaultTaxPercent`, chuỗi chuẩn; giá trị không qua `Percentage.input` bị bỏ).

### 5.2 Form (`ExpensesFeature/Form`)

`ExpenseFormViewModel(request:companyId:currency:expenseRepository:categoryRepository:actor:today:defaultTaxPercent:)`; subscribe `observeAll` (projects, categories, ranking luôn mới); edit → `get(id:)` một lần. `ExpenseFlowView(viewModel:captureMode:onClose:)`: create + scanner khả dụng → scanner trước, xong/Cancel → form.

| # | Phần tử | Identifier | Hành vi |
|---|---|---|---|
| 1 | Tiêu đề | – | `expense.new.title` / `expense.edit.title` |
| 2 | Hủy | `expense_cancel` | đóng, không lưu |
| 3 | Dải receipt | `expense_receipts` (container) | số trang `expense_receipt_count` ("x/10", `expense.receipt.count %lld`); thumbnail `expense_receipt_thumb_<i>` (chạm → viewer), nút bỏ `expense_receipt_remove_<i>`; menu thêm `expense_receipt_add` → `expense_receipt_scan` (chỉ khi scanner khả dụng) / `expense_receipt_photos`; hết chỗ thì ẩn; cắt bớt → alert `expense.receipt.limit` |
| 4 | Amount | `expense_amount` | `MoneyField(autoFocus:)`, focus khi vào form mới; thanh phím có "Xong" `expense_keyboard_done` (`expense.keyboard.done`) |
| 5 | Category chips | `expense_category_<raw>` / `expense_category_custom_<n>` / `expense_category_more` | 6 chip §2; "Thêm" → `CategoryPickerSheet` (`category_picker`, dòng `category_pick_<raw>` / `category_pick_custom_<n>`, `category_picker_new` → tạo nhanh) |
| 6 | Project | `expense_project` | tên project hoặc `expense.project.choose`; chạm → `ProjectPickerSheet` (`project_picker`, dòng `project_pick_<n>`, mục theo phase) |
| 7 | Thuế | `expense_tax` / `expense_tax_percent` / `expense_tax_percent_toggle` / `expense_tax_amount` | toggle đổi chế độ; ở chế độ % hiện `expense.tax.computed %@` |
| 8 | Ngày | `expense_date` | `DatePicker` compact, mặc định `today` |
| 9 | Tổng | `expense_total` | `expense.total` + amount+tax |
| 10 | Thêm chi tiết | `expense_more_details` | `DisclosureGroup`: vendor `expense_vendor`, cách trả chips `expense_method_<raw>`, ghi chú `expense_notes` |
| 11 | Lỗi | `expense_error_<case>` | hiện sau lần bấm Lưu đầu khi còn lỗi |
| 12 | Lưu | `expense_save` | `PrimaryButton` nửa dưới; disabled khi `isSaving` |
| 13 | Xóa (sửa) | `expense_delete` → `expense_delete_confirm` | confirmationDialog `expense.delete.title/message` |

Lỗi ghi → alert theo `DomainError`: `notFound` → `expense.error.gone`, `tooManyReceiptPages` → `expense.receipt.limit`, `currencyMismatch` → `error.currencyMismatch`, `incompleteExpense` → `expense.error.incomplete`, còn lại `expense.error.saveFailed`; dữ liệu đang nhập giữ nguyên.

`ReceiptViewer(pages:startIndex:shareURLs:onClose:)` (`receipt_viewer`): `TabView` page, `receipt_page_label` "Trang x/y", `receipt_share` (khi `shareURLs` không rỗng), `receipt_close`.

### 5.3 Danh sách (`ExpensesFeature/List`)

`ExpensesListViewModel(expenseRepository:companyId:currency:today:projectId:)` → `ExpenseListComposer`; tính lại khi snapshot, filter hoặc `today` đổi.

| # | Khối | Identifier | Nội dung |
|---|---|---|---|
| 1 | Tổng | `expenses_total_this_month`, `expenses_total_last_month` | 2 `SummaryTile` |
| 2 | Lọc | `expenses_filter_project`, `expenses_filter_category` | `Menu` dạng chip; mục `expenses_filter_project_all`/`expenses_filter_category_all` + từng mục |
| 3 | Tìm | `.searchable` | prompt `expenses.search` |
| 4 | Section ngày | `expenses_day_<YYYY-MM-DD>` | `DateLabel` + tổng ngày |
| 5 | Dòng | `expense_row_<uuid>` | combine: vendor/category, project, tổng, `expenses.receipts %lld`; chạm → form sửa |
| 6 | Trống | `expenses_empty` / `expenses_no_results` | không có expense / lọc không ra |
| 7 | "+" | `expenses_add` | `FloatingActionButton` |
| 8 | Lỗi | `expenses_retry` | banner `expenses.error` + Thử lại |

Tiêu đề `expenses.title` (SmokeTests cần nav bar "Expenses"). Ô tìm luôn hiện (`.searchable(placement: .navigationBarDrawer(displayMode: .always))`).

`ProjectExpensesSection(viewModel:makeAll:makeForm:)` (`detail_expenses`): tiêu đề `detail.expenses.title`, `detail_expenses_add`, tối đa 5 dòng `detail_expense_row_<i>`, `detail_expenses_all`, trống → `detail_expenses_empty`.

### 5.4 Danh mục chi phí (`ExpensesFeature/Categories`)

`CategoriesViewModel(categoryRepository:companyId:)`. `CategoriesView` (`categories_list`): section Có sẵn (13 dòng, group bên phải, chỉ đọc) và Của bạn (dòng `category_row_<n>`: tên, group, `categories.usage %lld`); toolbar `categories_add`. `CategoryEditSheet`: tên `category_name`, group chips `category_group_<raw>` (khóa khi `everUsed`, chú thích `category_group_locked`), `category_save`, `category_delete` (chỉ khi `liveExpenseCount == 0`; ngược lại `category_delete_blocked`), lỗi inline `category_error`; Hủy `sheet_cancel`. Lỗi: `emptyName`/`duplicateName`/`categoryInUse`/`categoryHasExpenses` → `categories.error.<case>`.

### 5.5 Host

- Home: `FloatingActionButton` `home_add_expense` → `.create(projectId: nil)`.
- Project detail: `ProjectExpensesSection` sau `FinancialSummarySection` (App truyền `makeExpensesSection`).
- More: dòng `more_categories` (sau Khách hàng).
- Settings: section `settings.tax`, `DecimalField` `settings_default_tax`, chú thích `settings.defaultTax.hint`, lỗi `expense.error.taxPercentOutOfRange` khi > 100 hoặc > 2 chữ số thập phân (không lưu).

## 6. DesignSystem

- `ChoiceChips` thêm `init(options:selection:text:identifier:)` (nhãn `Text` cho tên custom nguyên văn, identifier từng chip); init cũ giữ.
- `ReceiptThumbnail(image: Image?, pageNumber: Int)` — ô 64×88 bo góc, placeholder khi nil.
- `ZoomableImage(image: Image)` — `MagnifyGesture` kẹp 1…5, kéo khi đang zoom, double-tap về 1, tôn trọng Reduce Motion.
- `MoneyField` thêm tham số `autoFocus: Bool = false`.
- Gallery thêm mục `gallery.receipts` cho 2 component trên.

## 7. Localization

Thêm (en nguồn + vi):

- `expenses.*`: `title` (có), `empty.title` → "No expenses yet"/"Chưa có chi phí", `empty.message` → "Tap + to snap a receipt and log what you spent."/"Bấm + để chụp receipt và ghi chi phí.", `add`, `thisMonth`, `lastMonth`, `search`, `filter.allProjects`, `filter.allCategories`, `noResults`, `receipts %lld` ("%lld-page receipt"/"Receipt %lld trang"), `error`, `retry`.
- `expense.*`: `new.title`, `edit.title`, `amount`, `category`, `category.more`, `project`, `project.choose`, `tax`, `tax.percent`, `tax.usePercent`, `tax.useAmount`, `tax.computed %@`, `date`, `total`, `moreDetails`, `vendor`, `paymentMethod`, `notes`, `save`, `delete`, `delete.title`, `delete.message`, `delete.confirm`, `receipt.title`, `receipt.add`, `receipt.scan`, `receipt.photos`, `receipt.count %lld`, `receipt.limit`, `receipt.remove`, `error.<ExpenseDraftError>` ×6, `error.gone`, `error.incomplete`, `error.saveFailed`.
- `expenseCategory.<raw>` ×13 (trừ `custom`), `paymentMethod.<raw>` ×6.
- `category.picker.title`, `category.picker.custom`, `category.picker.new`, `project.picker.title`.
- `categories.*`: `title`, `builtIn`, `custom`, `add`, `new.title`, `edit.title`, `name`, `group`, `groupLocked`, `usage %lld`, `delete`, `deleteBlocked`, `empty`, `error.emptyName`, `error.duplicateName`, `error.categoryInUse`, `error.categoryHasExpenses`.
- `more.categories`; `settings.tax`, `settings.defaultTax`, `settings.defaultTax.hint`; `home.addExpense`; `detail.expenses.title`, `detail.expenses.all`, `detail.expenses.add`, `detail.expenses.empty`.
- `expense.keyboard.done`, `gallery.receipts`.
- `receipt.viewer.page %lld %lld` ("Page %1$lld of %2$lld"/"Trang %1$lld/%2$lld"), `receipt.viewer.share`, `receipt.viewer.close`; `scanner.fake.title`, `scanner.fake.capture`, `scanner.fake.cancel`.
- `activity.expenseUpdated`, `activity.expenseDeleted`, `activity.expenseAdded %@ %@` ("Expense: %1$@ — %2$@"), `activity.expenseUpdated %@ %@ %@` ("Expense %1$@: %2$@ → %3$@"), `activity.expenseDeleted %@ %@` ("Expense deleted: %1$@ — %2$@").
- `InfoPlist.xcstrings` (mới): `NSCameraUsageDescription` en "ConMa uses the camera to scan receipts." / vi "ConMa dùng camera để chụp receipt."

`scripts/check_localization.py` sinh thêm: `expenseCategory.<case>` (trừ `custom`), `paymentMethod.<case>`, `expense.error.<ExpenseDraftError case>`.

## 8. App

- `AppContainer.Ready` thêm `expenseRepository`, `categoryRepository`, `captureMode`, `settings`.
- `LaunchOptions` thêm `fakeScanner` (`--fake-scanner`, chỉ hiệu lực cùng `--ui-testing`).
- Receipt root: thật → Application Support; UI testing → `FileManager.default.temporaryDirectory/conma-ui-receipts` (xóa khi launch).
- Seed (DEBUG): `SampleData.seedIfEmpty(…, receiptStore:, sampleReceipt: SampleReceipt.jpeg(…))`.
- `Screens.swift`: `ExpensesScreen(projectId:)` (tab khi nil, "Xem tất cả" khi có project), `ExpenseFlowScreen(request:)` (đóng bằng `dismiss`), `CategoriesScreen`, `ProjectExpensesSectionScreen(projectId:)`; Home/detail/More nhận closure tương ứng; `AppContainer.Ready` thêm `settings` để form đọc thuế mặc định.
- `project.yml`: `NSCameraUsageDescription` trong `info.properties`.

## 9. Lỗi và biên

- Scanner không khả dụng (simulator, máy không camera) → vào thẳng form; vẫn có "Chọn từ Ảnh".
- Ảnh không nén được (`jpeg` nil) → bỏ trang đó, không chặn.
- Ghi file lỗi (đầy bộ nhớ) → `expense.error.saveFailed`, không có dòng DB nào; file đã ghi một phần bị xóa.
- Project/category/expense bị xóa khi form đang mở → Lưu ném `notFound` → `expense.error.gone`; form giữ dữ liệu.
- Scanner trả > số trang còn lại → nhận `ReceiptRules.acceptedCount`, báo `expense.receipt.limit`.
- Currency expense ≠ company (dữ liệu hỏng) → `currencyMismatch`.
- `today` qua nửa đêm: list/form lấy `today` lúc mở; list tính lại ở `scenePhase == .active` (như 2b).
- Hiệu năng: compose trên MainActor, mọi expense của company trong một stream; ghi nhận rủi ro > 5,000 expense (không build trước).
- Expense của project đã xóa không xuất hiện (cascade 2b đã soft delete expenses + receipt_images).

## 10. Testing

Domain (Windows/Linux, XCTest):
- `CategoryRankingTests`: seed → `[materials, wasteDisposal, fuel, toolPurchase, equipmentRental, subcontractor]`; rỗng → `[materials, fuel, toolPurchase, equipmentRental, subcontractor, delivery]`; hòa lượt → gần hơn trước; expense xóa và custom xóa bị bỏ; cửa sổ 50.
- `ExpenseProjectChoiceTests`: seed → Basement; expense Kitchen tạo sau → Kitchen; project expense mới nhất đã `closed` → inWork `updatedAt` mới nhất; không inWork → nil; `ordered` theo phase.
- `ExpenseDraftTests`: 13% của 100 = 13.00, total 113.00; 13% của 99.99 = 13.00; 5% của 0.10 = 0.01 (half-away); 13% của 2,400 = 312.00; % 100.5 và 13.125 → `taxPercentOutOfRange`; tax −1 → `taxNegative`; amount 0 → `amountNotPositive`; thứ tự lỗi; `makeExpense` built-in fuel → group other; custom → group của category; custom đã xóa → `notFound`; `apply` giữ group khi không đổi category, resolve lại khi đổi; init editing → `.amount`/`.none`.
- `ExpenseListComposerTests`: fixture seed + Kitchen fuel 80 + 10.40 ngày 2026-08-30 → tháng này 1,695.00, tháng trước 3,390.00, 4 section, tổng ngày 1,695.00/2,712.00/678.00/90.40; lọc Kitchen → 0/0, 1 section; lọc materials → 1,695.00/2,712.00; tìm "home depot", "DUMP", "da granite" (notes "Đá granite"); tìm không đổi tổng tháng; tháng 1/2027 → tháng trước là 12/2026; cùng ngày → `createdAt` giảm dần.
- `CustomCategoryRulesTests`: rỗng/khoảng trắng → `emptyName`; "scaffolding " trùng "Scaffolding" → `duplicateName`; trùng với chính nó khi đổi tên → ok; đổi group khi `everUsed` → `categoryInUse`; đổi tên khi `everUsed` → ok; xóa còn 1 expense → `categoryHasExpenses`. `ReceiptRules`: 10 ok, 11 ném; accepted(8, 5) = 2.
- `ActivityDescriptionTests`: thêm 4 case expense + thiếu total → plain.

Data (macOS CI):
- `ReceiptStoreTests`: ghi → path `Receipts/<e>/<i>.jpg`, đọc lại đúng byte; remove.
- `ExpenseRepositoryTests`: create ghi expense + 2 receipt + `expenseAdded` (JSON đúng); custom category: group lấy từ DB dù entity sai; project đã xóa → `notFound`, **không còn file** trong store; update bỏ trang 0 + thêm 1 trang → `page_index` [0, 1], trang bỏ có `deleted_at`, file còn; update không đổi gì → không activity; đổi amount → `expenseUpdated` có `from`; giữ category → giữ group cũ dù category đổi group trong DB (qua SQL); softDelete → expense + receipts xóa, `observeAll` phát danh sách mới, file còn; 11 trang → `tooManyReceiptPages`.
- `CustomCategoryRepositoryTests`: create/duplicate; đổi group sau khi expense dùng rồi bị xóa → `categoryInUse` (**test Foundation còn nợ**); đổi tên ok; xóa khi còn expense sống → `categoryHasExpenses`; `observeAll` đếm sống/ever.
- `ActivityLogRepositoryTests`: dòng `action = 'futureAction'` chèn bằng SQL → stream vẫn phát, bỏ dòng đó.
- `InsightsRepositoryTests`: company không có → `DomainError.notFound`; tạo expense qua repository → `observeProject` phát lại với spent mới.
- `SampleDataTests`: số §4 (tổng tháng, receipts 2/1/0, Scaffolding, 3 `expenseAdded`), số 2b không đổi.

UI tests (`UITests/ExpensesFlowTests.swift`, launch `--ui-testing --seed-sample-data --locale en --today 2026-10-03 --fake-scanner`):
- (a) Home `home_add_expense` → `scanner_cancel` → `expense_project` chứa "Basement Renovation"; amount 250; chip `expense_category_fuel`; Lưu → Home `home_total_spent` "10,935.00", `home_total_cash` "15,165.00", `home_attention` chứa "Over budget"; detail Basement `detail_health` "Over budget", `detail_cash` "3,335.00" có dấu âm, `detail_health_reasons` chứa "28.00"; tab Chi phí `expenses_total_this_month` "1,945.00".
- (b) Tab Chi phí `expenses_add` → `scanner_capture` → `expense_receipt_count` "1/10"; amount 100; `expense_tax_percent_toggle`; `expense_tax_percent` 13 → `expense_tax_amount` "13.00", `expense_total` "113.00"; `expense_category_materials`; Lưu → `expenses_total_this_month` "1,808.00"; có dòng chứa "113.00" và "1-page receipt".
- (c) Sửa Drywall amount 1600 → "1,795.00"; mở lại → `expense_delete` → `expense_delete_confirm` → "$0.00"; detail Basement `detail_spent` "8,990.00".
- (d) Lumber → `expense_receipt_thumb_0` → `receipt_viewer`, `receipt_page_label` "Page 1 of 2" → vuốt → "Page 2 of 2"; `receipt_share` tồn tại; `receipt_close`.
- (e) Thêm → `more_categories` → `categories_add` → "Dump runs" (group Other mặc định) → `category_save` → có dòng "Dump runs"; Scaffolding → `category_group_material` → lưu → dòng chứa "Materials"; tạo expense 40 với "Dump runs" qua `expense_category_more`; mở lại "Dump runs" → `category_group_locked` hiện, `category_group_material` disabled.
- (f) Kitchen detail → `detail_expenses_empty` → `detail_expenses_add` → `scanner_cancel` → `expense_project` chứa "Kitchen Renovation"; amount 75, fuel, Lưu → `detail_expenses` chứa "75.00", `detail_spent` "75.00"; Basement `detail_expenses_all` → `expenses_filter_project` chứa "Basement Renovation", 3 dòng.
- (g) Settings `settings_default_tax` 13 → tab Chi phí `expenses_add` → `scanner_cancel` → amount 200 → `expense_tax_amount` "26.00", `expense_total` "226.00".
- (h) vi (`--locale vi`, `-AppleLocale vi_VN`): tab "Chi phí" → `expenses_total_this_month` chứa "Tháng này", `expenses_total_last_month` chứa "Tháng trước"; tìm "dumpster" → còn dòng "Dumpster rental", không còn "Drywall".
- Screenshots (thêm vào `ScreenshotTests`, có `--fake-scanner`): `expenses_<locale>_<appearance>` (tab, đã có), `expense_form_<locale>`, `receipt_viewer_<locale>`, `categories_<locale>`, `detail_expenses_<locale>`.

## 11. Tiêu chí hoàn thành

- Domain/Data/UI tests xanh; `check_localization.py` 0 lỗi; `lint_sources.py` 0 lỗi; DashboardFlowTests 2b vẫn xanh không sửa số.
- Trên seed: từ Home, thêm một expense 250 Fuel cho Basement ≤ 6 lần chạm sau khi gõ số (+, Cancel scanner, gõ, Fuel, Lưu), Home và detail đổi số ngay.
- TestFlight build mới từ `main`; thử trên iPhone thật: scan 2 trang, xem, chia sẻ.

## 12. Ngoài phạm vi 3a

Payments, labour/crew, employees (3b); OCR; vendor list/autocomplete; kéo đổi thứ tự trang receipt; xóa vĩnh viễn file receipt (5); đồng bộ thuế mặc định giữa máy (5); chi phí ngoài project; split một receipt cho nhiều project; báo cáo/xuất CSV; nhiều currency; undo xóa.
