# ConMa — Sub-project 3b: Payments + Labour/crew

Ngày: 2026-10-04
Trạng thái: chờ review
Tiền đề: 3a merged (`main` aac842d, TestFlight 0.1.0 (5)). Spec 3a: `docs/superpowers/specs/2026-10-03-expenses-design.md` (kể cả Errata). Spec 2b: `docs/superpowers/specs/2026-10-03-dashboard-detail-design.md`. Foundation: `docs/superpowers/specs/2026-10-02-foundation-design.md` (§5.3 chi phí `LabourEntry` = `rounded(days × dailyRate)` với rate chụp lại; §5.4 Payment allocation + `PaymentStatusResolver`; §5.5 `Payment.amount > 0`, `LabourEntry.days > 0`, payment dư được chấp nhận; Phụ lục A.2 soft delete employee giữ lịch sử; A.3 bảng `payments`, `employees`, `labour_entries` — binding cho mọi công thức và cột ở đây).

## 1. Mục tiêu

Khách vừa e-Transfer đợt 2: contractor mở Home, chạm "Ghi nhận" cạnh dòng "Stage 2 quá hạn 5 ngày", số tiền đã điền sẵn đúng phần còn lại, bấm Lưu — ba chạm, dưới 5 giây. Cuối ngày, ở project detail bấm "Ghi công", chạm Mike và John, Lưu — chi phí Labour, budget alert, health và Home đổi ngay. 3b thêm hai luồng nhập tiền còn thiếu lên nền 2b/3a: **tiền vào** (payment theo project, gắn hoặc không gắn đợt của payment schedule, sửa/xóa) và **công thợ** (danh sách crew ở Thêm, ghi công nhiều người một lần theo ngày với rate chụp lại, sửa/xóa từng dòng). Không migration: bảng `payments`, `employees`, `labour_entries` của Migration001 đủ; `FinancialCalculator`, `PaymentStatusResolver`, `DashboardComposer` đã tính sẵn mọi thứ — 3b chỉ cho người dùng nhập dữ liệu và ghi activity đúng.

## 2. Quyết định đã chốt

| Chủ đề | Quyết định |
|---|---|
| Phạm vi | Payments (tiền vào) + Crew (employees) + Labour chế độ đơn giản (ngày công × rate ngày). Không có chấm công giờ, không lương, không `project_workers`/phân công (sub-project 4). |
| Form payment luôn theo project | Mọi lối vào đều biết project (detail, dòng schedule, dòng attention ở Home) → form **không có ô chọn project**; tên project hiện ở đầu form (`payment_project`). Bớt một trường bắt buộc, không thể ghi nhầm project. |
| Lối vào payment | (1) Chạm dòng payment schedule trong detail → form gắn sẵn đợt đó, số tiền = **phần còn lại** của đợt (nếu > 0), không auto-focus (Lưu ngay được). (2) "Ghi thanh toán" trong card Thanh toán của detail → đợt mặc định = đợt **đầu tiên theo thứ tự chưa `paid`** (không có → không gắn), số tiền **trống + focus** (bàn phím mở sẵn), chip "Còn lại" để điền một chạm. (3) Home: dòng attention `paymentOverdue`/`paymentDueToday` có nút "Ghi nhận" (`attention_record_<itemId>`) cạnh dòng (dòng vẫn mở detail như 2b) → như (1). Danh sách attention đầy đủ (sheet) cũng có nút này. |
| Chip số tiền | Tùy ngữ cảnh, tối đa 2: đợt đang chọn còn lại > 0 → "Còn lại $X" (`payment_chip_remaining`); đợt đã trả một phần → thêm "Cả đợt $Y" (`payment_chip_full`); không gắn đợt và project còn phải thu > 0 → "Còn phải thu $Z" (`payment_chip_outstanding`). Đợt đã trả đủ → không chip. |
| Payment không gắn đợt / trả dư | Không gắn: tính vào `collected`, không vào item nào (Foundation §5.4). Trả dư: chấp nhận, đợt thành `paid`, phần dư **không** chuyển sang đợt khác; form hiện chú thích `payment_overpay_notice` với số dư (không chặn). |
| Sửa payment | Phần "đã trả"/"còn lại"/chip/trạng thái của từng đợt trong form tính **không kể chính payment đang sửa** (nếu không, sửa 7,600 thành 7,600 sẽ báo trả dư). Project của payment không đổi được (xóa rồi ghi lại). |
| Cách trả mặc định | Lấy từ **dữ liệu**: method của payment sống được tạo gần nhất trong company (`PaymentRepository.lastUsedMethod`); chưa có → **e-Transfer** (cách phổ biến ở Canada). Không lưu `UserDefaults` → đúng trên mọi máy sau khi sync (sub-project 5). Chip theo thứ tự e-Transfer, Cheque, Cash, Bank transfer, Credit card, Other. |
| Xóa payment | Cuối form sửa → xác nhận → soft delete + `paymentDeleted`. Không undo. |
| Crew | Thêm → "Crew" (`more_crew`, ngay sau Khách hàng). Trường: tên (bắt buộc), nghề (một ô text → cột `trade`; `role` để nil), điện thoại, rate ngày, rate giờ (không bắt buộc, chỉ hiển thị), ghi chú. Rate ngày **không bắt buộc ở form crew**; khi ghi công cho người chưa có rate thì phải gõ rate ở form công. Nút "Dùng 8 giờ × rate giờ = $X" (`crew_daily_from_hourly`) điền rate ngày từ rate giờ. Trùng tên được phép (dòng hiện nghề để phân biệt). Sửa crew không ghi activity (không phải tiền của project). |
| Xóa crew | Soft delete (xác nhận, nói rõ công đã ghi vẫn giữ). Ẩn khỏi danh sách crew và form ghi công; labour entry cũ giữ nguyên rate chụp và vẫn hiện **tên** (truy vấn employee kể cả đã xóa — Foundation A.2). Không thể ghi công mới cho người đã xóa (`notFound`). |
| Ngày vs giờ | Labour chỉ ghi theo **ngày** (`days`, Decimal > 0, nút −/+ bước 0.5, gõ được số khác như 0.25). Không quy đổi giờ trong form công; rate giờ chỉ hiện ở crew ("$31.25/h") và dùng cho nút 8 giờ. Hiển thị "1 day" / "0.5 days" / "8 days". |
| Form ghi công nhiều người | Một sheet: Ngày (mặc định today) → Số ngày (chung cho mọi người đã chọn, mặc định 1) → danh sách crew sống (theo tên) dạng dòng chạm-để-chọn; dòng đã chọn mở ô rate (điền sẵn rate ngày của người đó, sửa được, chụp vào entry) + chi phí dòng; cảnh báo "Đã ghi X ngày trong ngày này" khi người đó đã có công cùng project cùng ngày (không chặn) → ghi chú → Tổng → "Ghi công". Lưu = **một `LabourEntry` mỗi người trong MỘT transaction** và **một** dòng activity `labourLogged` cho cả lô. Người khác số ngày → sửa dòng của họ sau. |
| Sửa / xóa công | Chạm dòng công → cùng form ở chế độ sửa một người: người **không đổi được** (`employeeId` bất biến), sửa ngày/số ngày/rate/ghi chú; xóa ở cuối (xác nhận, soft delete). |
| Rate $0 | Cho phép (chủ tự ghi ngày công của mình để theo dõi); rate trống thì chặn (`rateMissing`), rate âm chặn. |
| Crew trống | Danh sách crew: `EmptyState` "Chưa có crew" + câu giải thích rate tự điền + nút "Thêm người". Form ghi công khi crew trống: cùng EmptyState và nút "Thêm người" mở form crew ngay trong sheet; lưu xong người đó **được chọn sẵn**. |
| Project detail | Thứ tự card: header, Financial summary, **Thanh toán** (mới), Chi phí (3a), **Labour** (mới), Health, Timeline, Phạm vi, Giá/Deposit, Payment schedule (dòng nay chạm được → ghi thanh toán), Khách, Activity. Card Thanh toán: mọi payment sống (mới nhất trước), dòng "Không gắn đợt: $X" khi có. Card Labour: tổng (số ngày · tiền), 3 ngày gần nhất (nhóm theo ngày, tổng ngày), "Xem tất cả" → màn danh sách đủ. |
| Activity | Thêm `ActivityAction.paymentUpdated`, `.paymentDeleted`, `.labourLogged`, `.labourUpdated`, `.labourDeleted` (cột `action` không có CHECK). `paymentReceived` (có sẵn) dùng cho tạo. Ghi trong cùng transaction; sửa không đổi gì → không ghi, không stamp `updated_at`. JSON payment `{"amount","currency","item","method"}` (+ `"from"` khi sửa); labour `{"currency","names","people","total","workDate"}` (+ `"from"` khi sửa). |
| Carry-over | Làm: (a) câu activity format tiền theo `"currency"` lưu trong chính dòng activity (dòng cũ không có → currency company); (b) `ExpenseFormViewModel` edit-load bỏ qua `CancellationError` (không báo lỗi/đóng form khi task bị hủy); (c) seed payment/labour/employee đi qua repository (có activity); (d) nhãn nhóm Home `workDone` đổi "Awaiting final payment" → "Work done" / "Xong việc" (job đã thu đủ không còn bị gọi là chờ tiền). Để lại: các mục 3a khác (photo picker pending, `keptImageIds` trùng, guard companyId của expense update, path receipt, seed atomic, alert 9 trang, vi `expense.receipt.title`). |
| Schema | Không migration. Không cột mới; method mặc định suy từ `payments`. |
| Seed | Không đổi số tiền nào của 2b/3a. Payment (2) và labour (3) đi qua repository (thêm 2 `paymentReceived`, 3 `labourLogged`); crew có nghề + điện thoại; Mike có rate giờ 31.25. Mọi test số 2b/3a giữ nguyên; `SampleDataTests` thêm assert (§4). |
| Ngôn ngữ | Giữ tiếng Anh trong bản vi: Labour, crew/Crew, e-Transfer, Cheque, Deposit, rate (theo "Rate mỗi ngày" có sẵn). Dịch: Payment → "Thanh toán", Record → "Ghi nhận", Log labour → "Ghi công", Stage → "Đợt", Days → "Số ngày". Tên người, nghề, ghi chú là dữ liệu người dùng → `Text(verbatim:)`. |

### 2.1 Ràng buộc chung (plan chép nguyên văn)

- Domain imports Foundation only; Features never imports Data; DesignSystem never imports Domain. `scripts/lint_sources.py` must pass (no `Double`/`Float`/`CGFloat` in Domain/Data; no `try!`/`as!`/`fatalError` in production).
- Money is `Money` (Decimal, 2 dp, `Money.rounded` half-away-from-zero). Labour cost is ONE rounding per entry (`LabourEntry.cost` = `rounded(days × dailyRate)`); totals are sums of rounded entry costs. Domain never calls `Date()`; `today: CalendarDate` and `now: Date` are passed in.
- Soft-deleted rows never take part in any calculation or list (`deleted_at IS NULL` in every query; composers also filter `isDeleted`) — except employee **names** for labour history, which read deleted employees too.
- Every payment and labour write (create, update, delete) and its `activity_log` row happen in one transaction; an update that changes nothing writes nothing. A multi-person labour log is one transaction: all entries or none.
- No schema migration: the Migration001 tables are used as they are.
- Every new protocol requirement lands in the same commit as its GRDB implementation (every pushed commit compiles).
- All user-visible strings are keys in `App/Resources/Localizable.xcstrings` with `en` + `vi`; user data is rendered with `Text(verbatim:)`. Trade terms stay English in vi (Labour, crew, e-Transfer, Cheque, Deposit, receipt). `python scripts/check_localization.py` must report 0 errors.
- Every VM is `@Observable @MainActor`, owned by an `@State` wrapper in `App/Screens.swift`, never constructed in `body`.
- Accessibility identifiers exactly as listed in spec §5 and the UI-test task.
- The 2b/3a seed numbers do not change; `UITests/DashboardFlowTests.swift` and `UITests/ExpensesFlowTests.swift` keep every expected number (only a scroll limit may be raised if the longer detail page needs it — record it in Errata).
- Commits: `type(scope): summary`, English, **no trailers** (no Co-Authored-By).
- CI: `ios.yml` is the verifier for Data/Features/App; Domain is verified locally with `swift test --package-path Packages/Domain`. Known flake: Foundation `testLanguageSwitchUpdatesOpenScreenAndTabsImmediately` / screenshot launch timeout → rerun failed jobs once.

## 3. Domain

Thư mục mới `Packages/Domain/Sources/Domain/Payments/` (đã có `PaymentAllocation`, `PaymentStatusResolver`), `Crew/`, `Labour/`. Foundation-only, `Sendable`, test trên Windows/Linux.

### 3.1 Payments

```swift
public enum PaymentDraftError: Hashable, Sendable, CaseIterable { case amountMissing, amountNotPositive }
public struct PaymentDraft: Hashable, Sendable {
    public static let methodOrder: [PaymentMethod]            // eTransfer, cheque, cash, bankTransfer, creditCard, other
    public static func defaultMethod(lastUsed: PaymentMethod?) -> PaymentMethod   // lastUsed ?? .eTransfer
    public var amount: Decimal?
    public var paidOn: CalendarDate
    public var method: PaymentMethod
    public var scheduleItemId: UUID?
    public var notes: String
    public init(paidOn: CalendarDate, method: PaymentMethod, scheduleItemId: UUID? = nil, amount: Decimal? = nil)
    public init(editing payment: Payment)
    public var errors: [PaymentDraftError] { get }             // amount nil → amountMissing; rounded(amount) ≤ 0 → amountNotPositive
    public var canSave: Bool { get }
    public func makePayment(id: UUID, companyId: UUID, projectId: UUID, currency: CurrencyCode, now: Date) throws -> Payment
    public func apply(to existing: Payment, now: Date) throws -> Payment   // giữ id, companyId, projectId, createdAt
}

public struct PaymentItemOption: Hashable, Sendable, Identifiable { item; paid: Money; remaining: Money; status: PaymentStatus }
public enum PaymentSuggestion: Hashable, Sendable { case remaining(Money), fullItem(Money), outstanding(Money); public var money: Money }
public enum PaymentFormContext {
    public static func options(items: [PaymentScheduleItem], payments: [Payment], excluding paymentId: UUID?, today: CalendarDate, currency: CurrencyCode) -> [PaymentItemOption]
    public static func defaultItemId(_ options: [PaymentItemOption]) -> UUID?            // đầu tiên không .paid
    public static func outstanding(project: Project, payments: [Payment], excluding paymentId: UUID?) -> Money?
    public static func suggestions(option: PaymentItemOption?, outstanding: Money?) -> [PaymentSuggestion]   // §2 "Chip số tiền"
    public static func overpayment(amount: Decimal?, option: PaymentItemOption?) -> Money?               // amount − remaining khi > 0
}

public struct PaymentRow: Hashable, Sendable, Identifiable { payment; itemLabel: String? }   // nil = không gắn (hoặc đợt đã xóa)
public struct ProjectPaymentList: Hashable, Sendable { rows; collected: Money; unallocated: Money }
public enum ProjectPaymentListComposer {
    public static func compose(payments: [Payment], scheduleItems: [PaymentScheduleItem], currency: CurrencyCode) -> ProjectPaymentList
}
```

- `options`: item sống theo `sortOrder`; `paid` = `PaymentAllocation.paidForItem` trên payment sống trừ `excluding`; `remaining = max(0, amount − paid)`; `status` = `PaymentStatusResolver` với `paid` đó.
- `makePayment`/`apply` ném `DomainError.incompletePayment` khi `errors` khác rỗng; amount làm tròn **một lần** qua `Money`; notes trim, rỗng → nil.
- `ProjectPaymentListComposer`: payment sống, `paidOn` giảm dần, rồi `createdAt` giảm dần; `itemLabel` chỉ khi item **còn sống** (khớp `ProjectInsightsComposer`, nơi payment trỏ item đã xóa tính là chưa phân bổ); `unallocated` = tổng các dòng `itemLabel == nil`.
- `AttentionItem.scheduleItemId: UUID?` (mới): item của `paymentOverdue`/`paymentDueToday`, còn lại nil.
- `DomainError` thêm `incompletePayment`, `incompleteLabour`.

### 3.2 Crew

```swift
public enum EmployeeDraftError: Hashable, Sendable, CaseIterable { case nameMissing, rateNegative }
public struct EmployeeDraft: Hashable, Sendable {
    public static let hoursPerDay: Decimal                      // 8, chỉ cho nút "8 giờ × rate giờ"
    public var name, trade, phone, notes: String
    public var dailyRate: Decimal?
    public var hourlyRate: Decimal?
    public init(); public init(editing employee: Employee)
    public var errors: [EmployeeDraftError] { get }; public var canSave: Bool { get }
    public var dailyFromHourly: Decimal? { get }                // rounded(rounded(hourly) × 8)
    public func makeEmployee(id: UUID, companyId: UUID, currency: CurrencyCode, now: Date) throws -> Employee   // emptyName / negativeAmount
    public func apply(to existing: Employee, currency: CurrencyCode, now: Date) throws -> Employee           // giữ role, certifications, emergencyContact
}
public enum CrewList { public static func ordered(_ employees: [Employee]) -> [Employee] }   // sống, theo tên (localizedStandardCompare), rồi createdAt
```

### 3.3 Labour

```swift
public enum LabourDraftError: Hashable, Sendable, CaseIterable { case noCrewSelected, daysMissing, daysNotPositive, rateMissing, rateNegative }
public struct LabourLine: Hashable, Sendable, Identifiable { public let employeeId: UUID; public var dailyRate: Decimal? }
public struct LabourDraft: Hashable, Sendable {
    public static let dayStep: Decimal                           // 0.5
    public var workDate: CalendarDate
    public var days: Decimal?                                    // mặc định 1
    public var lines: [LabourLine]                               // người đã chọn, theo thứ tự chọn
    public var notes: String
    public init(workDate: CalendarDate); public init(editing entry: LabourEntry)
    public func isSelected(_ employeeId: UUID) -> Bool
    public mutating func toggle(_ employee: Employee)            // chọn với rate ngày hiện tại của người đó (nil nếu chưa có) / bỏ chọn
    public mutating func setRate(_ rate: Decimal?, for employeeId: UUID)
    public mutating func stepDays(up: Bool)                      // ±0.5, không dưới 0.5; nil + → 0.5
    public func cost(for employeeId: UUID, currency: CurrencyCode) -> Money?   // LabourEntry.cost(days:dailyRate:)
    public func total(currency: CurrencyCode) -> Money?          // tổng các cost đã làm tròn; nil khi trống hoặc còn dòng chưa tính được
    public func lineError(for employeeId: UUID) -> LabourDraftError?
    public var errors: [LabourDraftError] { get }                // theo thứ tự khai báo
    public var canSave: Bool { get }
    public func makeEntries(companyId: UUID, projectId: UUID, currency: CurrencyCode, now: Date, makeId: () -> UUID) throws -> [LabourEntry]
    public func apply(to existing: LabourEntry, now: Date) throws -> LabourEntry   // giữ id, employeeId, projectId, createdAt
    public static func alreadyLoggedDays(employeeId: UUID, on day: CalendarDate, entries: [LabourEntry], excluding entryId: UUID?) -> Decimal
}

public struct LabourRow: Hashable, Sendable, Identifiable { entry; employeeName: String; cost: Money }   // "" khi không tìm thấy employee
public struct LabourDaySection: Hashable, Sendable, Identifiable { day: CalendarDate; rows; total: Money; days: Decimal }
public struct ProjectLabourList: Hashable, Sendable { sections; total: Money; totalDays: Decimal; var rows }
public enum LabourListComposer {
    public static func compose(entries: [LabourEntry], employees: [Employee], currency: CurrencyCode) -> ProjectLabourList
}
```

- `makeEntries`/`apply` ném `DomainError.incompleteLabour` khi `errors` khác rỗng.
- Composer: entry sống; section theo `workDate` giảm dần; trong ngày theo tên rồi `createdAt`; `employees` gồm cả người đã xóa (tên lịch sử).

### 3.4 Activity

- `ActivityAction` thêm `paymentUpdated`, `paymentDeleted`, `labourLogged`, `labourUpdated`, `labourDeleted` (20 case).
- `PaymentTitle { case item(String), method(PaymentMethod) }` — đợt khi có `item` khác rỗng, ngược lại cách trả.
- `ActivityDetail` thêm `.payment(action:title:amount:previousAmount:)` (thiếu `amount` hoặc `method` lạ → `.plain`) và `.labour(action:names:total:previousTotal:)` (thiếu `total` hoặc `names` rỗng → `.plain`). `previous…` chỉ cho action `…Updated`, đọc `"from"`.
- `ActivityDescription.currency(for:) -> CurrencyCode?` đọc `"currency"`; dòng cũ → nil.

### 3.5 Repository protocols (mỗi protocol vào cùng commit với GRDB implementation)

```swift
public protocol PaymentRepository: Sendable {
    func get(id: UUID) async throws -> Payment?                          // nil khi mất/đã xóa
    func lastUsedMethod(companyId: UUID) async throws -> PaymentMethod?  // payment sống tạo gần nhất
    func create(_ payment: Payment, actor: ActivityActor) async throws    // notFound (project/item không sống, item khác project), currencyMismatch, invalidPaymentAmount
    func update(_ payment: Payment, actor: ActivityActor) async throws    // + scopeMismatch khi đổi company/project; không đổi → no-op
    func softDelete(id: UUID, actor: ActivityActor) async throws
}
public protocol EmployeeRepository: Sendable {
    func observeAll(companyId: UUID) -> AsyncThrowingStream<[Employee], Error>   // sống, CrewList.ordered
    func get(id: UUID, includingDeleted: Bool) async throws -> Employee?
    func create(_ employee: Employee) async throws                               // emptyName, negativeAmount, currencyMismatch
    func update(_ employee: Employee) async throws                               // notFound, scopeMismatch; không đổi → no-op
    func softDelete(id: UUID) async throws                                       // notFound
}
public struct ProjectLabourSnapshot: Hashable, Sendable { currency; entries: [LabourEntry] /* sống */; employees: [Employee] /* mọi người, kể cả đã xóa */ }
public protocol LabourRepository: Sendable {
    func observeProject(id: UUID) -> AsyncThrowingStream<ProjectLabourSnapshot?, Error>   // nil khi project mất/đã xóa
    func get(id: UUID) async throws -> LabourEntry?
    func create(_ entries: [LabourEntry], actor: ActivityActor) async throws   // một transaction; incompleteLabour (rỗng), scopeMismatch (khác project), notFound (project/employee không sống), invalidLabourDays, negativeAmount, currencyMismatch
    func update(_ entry: LabourEntry, actor: ActivityActor) async throws       // notFound, scopeMismatch (đổi company/project/employee); không đổi → no-op
    func softDelete(id: UUID, actor: ActivityActor) async throws
}
```

Form payment đọc dữ liệu project qua `InsightsRepository.observeProject(id:)` có sẵn (project, schedule items, payments) — không thêm observation mới.

## 4. Data

- `PaymentRecord`, `LabourEntryRecord`, `EmployeeRecord` thêm `Equatable`; `EmployeeRecord.fetchAll(_:companyId:currency:)` (kể cả đã xóa).
- `GRDBPaymentRepository(database:clock:)`: tạo/sửa kiểm tra currency khớp company, project sống cùng company, item (nếu có) sống **cùng project và company** (khóa ngoại tổ hợp không bắt được item đã soft delete); ghi + activity (`entity_type = "payment"`, `project_id`). `details.item` = nhãn của item (key `schedule.row.*` hoặc chữ người dùng) hoặc "".
- `GRDBEmployeeRepository(database:clock:)`: không activity.
- `GRDBLabourRepository(database:clock:)`: `create` một transaction: project sống, từng employee **sống** cùng company (người đã xóa → `notFound`, không dòng nào được ghi), insert mọi entry, một `labourLogged` (`entity_type = "labour_entry"`, `entity_id` = entry đầu, `names` nối ", " theo thứ tự lô, `people`, `total` = tổng cost đã làm tròn, `workDate`). `update`/`softDelete` đọc tên employee kể cả đã xóa.
- `SampleData.seedIfEmpty`: employee qua `GRDBEmployeeRepository`, labour qua `GRDBLabourRepository` (mỗi entry một lô), payment qua `GRDBPaymentRepository`; xóa đoạn ghi thẳng record.

Số liệu seed với `today = 2026-10-03` (hợp đồng cho test và screenshot):

| Crew | Nghề | Điện thoại | Rate ngày | Rate giờ |
|---|---|---|---|---|
| David | Labourer | 905-555-0112 | 200.00 | – |
| John | Drywall | 647-555-0111 | 220.00 | – |
| Mike | Carpenter | 416-555-0110 | 250.00 | 31.25 |

| Labour (Basement) | Ngày | Số ngày × rate = Cost |
|---|---|---|
| Mike | 2026-09-23 (−10) | 8 × 250.00 = 2,000.00 |
| John | 2026-09-24 (−9) | 10 × 220.00 = 2,200.00 |
| David | 2026-09-25 (−8) | 7 × 200.00 = 1,400.00 |

| Payment | Project | Đợt | Ngày | Cách | Số tiền |
|---|---|---|---|---|---|
| 1 | Basement | Deposit | 2026-09-14 (−19) | e-Transfer | 7,600.00 |
| 2 | Roof | – (không gắn) | 2026-08-24 (−40) | e-Transfer | 18,500.00 |

- Labour Basement: tổng 5,600.00 / 25 ngày; estimate 6,000.00 → 93.3 % → `nearLimit`. Card Labour: sections 2026-09-25 (1,400.00), 2026-09-24 (2,200.00), 2026-09-23 (2,000.00).
- Activity mới: 3 `labourLogged` (ví dụ Mike `{"currency":"CAD","names":"Mike","people":"1","total":"2000.00","workDate":"2026-09-23"}`), 2 `paymentReceived` (Basement `{"amount":"7600.00","currency":"CAD","item":"schedule.row.deposit","method":"eTransfer"}`).
- Form payment Basement "Ghi thanh toán": đợt mặc định Stage 2 (sort 1), chip `Còn lại 11,400.00`; cách trả e-Transfer; Basement còn phải thu 30,400.00.
- Dashboard 2b/3a giữ nguyên: outstanding 55,400; collected 26,100; spent 10,685; cash 15,415; Basement cash −3,085; attention `[paymentRisk, paymentOverdue, startsToday]`.

## 5. Features

Target mới trong `Packages/Features`: `PaymentsFeature` (form payment), `CrewFeature` (crew, form công, card và danh sách Labour). Card Thanh toán nằm trong `ProjectsFeature/Detail` (dữ liệu đã có trong detail VM).

### 5.1 FeatureSupport

- `PaymentFormRequest: Identifiable, Hashable { case create(projectId: UUID, scheduleItemId: UUID?), edit(UUID) }`; `LabourFormRequest { case create(projectId: UUID), edit(UUID) }`.
- Nhãn: `PaymentStatus.titleKey/tone` (chuyển từ `ProjectDetailView`), `PaymentDraftError.name/messageKey`, `LabourDraftError.name/messageKey`, `EmployeeDraftError.name/messageKey`, `PaymentTitle.text`, `LabourDays.text(_:locale:)` ("1 day" khi = 1, ngược lại "%@ days" với số theo locale).
- `ActivityText`: câu cho `.payment`/`.labour`; `ActivityLogEntry.sentence(fallbackCurrency:locale:)` dùng `ActivityDescription.currency(for:)` rồi mới tới currency company (carry-over a). `ActivityEntryRow` gọi hàm này.
- Carry-over b: `ExpenseFormViewModel.start()` thêm `catch is CancellationError { return }` trước nhánh lỗi edit-load.

### 5.2 Form payment (`PaymentsFeature`)

`PaymentFormViewModel(request:companyId:currency:paymentRepository:insightsRepository:actor:today:)`; `start()`: edit → `get(id:)` một lần (nil → `payment.error.gone`, đóng sau alert); create → `lastUsedMethod` (không ghi đè nếu người dùng đã chạm chip); rồi `insightsRepository.observeProject(id:)` (nil → project đã xóa → `payment.error.gone`). Mặc định đợt/số tiền áp **một lần** ở snapshot đầu (§2). `PaymentFormView(viewModel:onClose:)` là sheet có `NavigationStack`.

| # | Phần tử | Identifier | Hành vi |
|---|---|---|---|
| 1 | Tiêu đề | – | `payment.new.title` / `payment.edit.title` |
| 2 | Hủy | `payment_cancel` | đóng, không lưu |
| 3 | Project | `payment_project` | tên project (verbatim) |
| 4 | Số tiền | `payment_amount` | `MoneyField(autoFocus:)` — focus chỉ khi `create(_, nil)`; thanh phím `payment_keyboard_done` (`keyboard.done`) |
| 5 | Chip | `payment_chip_remaining` / `payment_chip_full` / `payment_chip_outstanding` | điền số tiền (`payment.chip.* %@`) |
| 6 | Trả dư | `payment_overpay_notice` | `payment.overpay %@` khi `overpayment` ≠ nil |
| 7 | Cho đợt | `payment_items` (container); dòng `payment_item_<sortOrder>`; `payment_item_none` | chỉ hiện khi project có schedule; dòng: nhãn đợt, "Còn $X", `StatusBadge`; chọn = trait `isSelected` |
| 8 | Ngày | `payment_date` | `DatePicker` compact, mặc định `today` |
| 9 | Cách trả | `payment_method_<raw>` | `ChoiceChips` theo `PaymentDraft.methodOrder` |
| 10 | Ghi chú | `payment_notes` | `TextField` nhiều dòng |
| 11 | Lỗi | `payment_error_<case>` | sau lần bấm Lưu đầu |
| 12 | Lưu | `payment_save` | `PrimaryButton` (`payment.save`) nửa dưới; disabled khi `isSaving`/chưa có snapshot |
| 13 | Xóa (sửa) | `payment_delete` → `payment_delete_confirm` | confirmationDialog `payment.delete.title/message` |

Lỗi ghi → alert: `notFound` → `payment.error.gone`; `currencyMismatch` → `error.currencyMismatch`; `incompletePayment`/`invalidPaymentAmount` → `payment.error.incomplete`; còn lại `payment.error.saveFailed`. Dữ liệu đang nhập giữ nguyên.

### 5.3 Project detail: Thanh toán + payment schedule

- `ProjectDetailViewModel.payments: ProjectPaymentList?` tính từ snapshot `observeProject` sẵn có.
- `ProjectPaymentsSection` (`detail_payments`): tiêu đề `detail.payments.title`, nút `detail_payments_add` (`detail.payments.add`) → `.create(projectId, nil)`; dòng `detail_payment_row_<i>` (mới nhất trước; ngày, nhãn đợt hoặc `detail.payments.notLinked`, cách trả, số tiền; chạm → `.edit`); `detail_payments_unallocated` (`detail.payments.unallocated %@`) khi `unallocated > 0`; trống → `detail_payments_empty`.
- Dòng payment schedule `detail_schedule_row_<sortOrder>` thành `Button` (giữ identifier 2b, thêm chevron, hint `detail.payments.add`) → `.create(projectId, item.id)`.
- `ProjectDetailView(viewModel:makeCustomer:makeActivity:makeExpensesSection:makeLabourSection:makePaymentForm:)`; form trình bày bằng `.sheet(item:)`.

### 5.4 Crew (`CrewFeature/Crew`)

`CrewListViewModel(employeeRepository:companyId:currency:)`. `CrewListView` (`crew_list`, tiêu đề `crew.title`): dòng `crew_row_<i>` (tên, nghề, "$250.00/day" hoặc `crew.noRate`, "$31.25/h" khi có); toolbar `crew_add`; trống `crew_empty` (+ nút `crew_empty_add`). `CrewFormSheet(employee:currency:onSave:onDelete:onCancel:)` (sheet, không gắn identifier lên container — 3a Errata): `crew_name`, `crew_trade`, `crew_phone`, `crew_daily_rate`, `crew_hourly_rate`, `crew_daily_from_hourly` (khi có rate giờ), `crew_notes`, lỗi `crew_error_<case>` và `crew_error`, `crew_save`, `crew_delete` → `crew_delete_confirm`, Hủy `sheet_cancel`. Lỗi: `emptyName` → `crew.error.nameMissing`, `negativeAmount` → `crew.error.rateNegative`, `notFound` → `crew.error.gone`, còn lại `crew.error.saveFailed`.

### 5.5 Form công (`CrewFeature/Labour`)

`LabourFormViewModel(request:companyId:currency:labourRepository:employeeRepository:actor:today:)`; `start()` (edit → `get(id:)` + tên qua `employeeRepository.get(id:includingDeleted: true)`; create → `observeAll` crew) và `startEntries()` (create → `labourRepository.observeProject` cho cảnh báo "đã ghi"). `LabourFormView(viewModel:onClose:)` là sheet.

| # | Phần tử | Identifier | Hành vi |
|---|---|---|---|
| 1 | Tiêu đề | – | `labour.new.title` / `labour.edit.title` |
| 2 | Hủy | `labour_cancel` | đóng |
| 3 | Ngày | `labour_date` | `DatePicker` compact, mặc định today |
| 4 | Số ngày | `labour_days`, `labour_days_minus`, `labour_days_plus` | `DecimalField` + nút −/+ (`stepDays`); chú thích `labour.days.hint` |
| 5 | Crew | `labour_person_<i>` | create: crew sống theo tên, chạm để chọn/bỏ (trait `isSelected`); edit: một dòng người đó, không chạm được |
| 6 | Rate dòng | `labour_rate_<i>`, `labour_cost_<i>`, `labour_rate_error_<i>`, `labour_already_<i>` | chỉ dòng đã chọn; `MoneyField`; cost "= $X"; lỗi rate; `labour.already %@` |
| 7 | Thêm người | `labour_add_person` | mở `CrewFormSheet` tạo mới; lưu xong chọn sẵn người đó |
| 8 | Crew trống | `labour_empty_crew` | `EmptyState` `crew.empty.*` + #7 |
| 9 | Ghi chú | `labour_notes` | áp cho mọi entry của lô |
| 10 | Tổng | `labour_total` | `labour.total` + `total(currency:)` |
| 11 | Lỗi | `labour_error_<case>` | sau lần Lưu đầu |
| 12 | Lưu | `labour_save` | create `labour.save` ("Ghi công"), edit `sheet.save` |
| 13 | Xóa (sửa) | `labour_delete` → `labour_delete_confirm` | `labour.delete.title/message` |
| 14 | Bàn phím | `labour_keyboard_done` | `keyboard.done` |

Lỗi ghi: `notFound` → `labour.error.gone`; `incompleteLabour`/`invalidLabourDays` → `labour.error.incomplete`; `currencyMismatch` → `error.currencyMismatch`; còn lại `labour.error.saveFailed`.

### 5.6 Card và danh sách Labour (`CrewFeature/Labour`)

`ProjectLabourViewModel(labourRepository:projectId:)` → `LabourListComposer`. `ProjectLabourSection(viewModel:makeAll:makeForm:)` (`detail_labour`): tiêu đề `detail.labour.title`, `detail_labour_add` (`detail.labour.add`), `detail_labour_total` (`detail.labour.total %@ %@` = số ngày · tiền), tối đa 3 section ngày `detail_labour_day_<YYYY-MM-DD>` (ngày + tổng ngày), dòng `labour_row_<uuid>` (tên hoặc `labour.unknownPerson`, `labour.row.detail %@ %@` = "8 days × $250.00", cost; chạm → form sửa), `detail_labour_all` (khi > 3 ngày), trống `detail_labour_empty`. `ProjectLabourListView(viewModel:makeForm:)` (`labour_list`, tiêu đề `labour.list.title`): mọi section, cùng dòng.

### 5.7 Host

- Home: dòng attention có `scheduleItemId` → `HStack { NavigationLink(row) ; Button("attention.record") }` với `attention_record_<itemId>` → `PaymentFormRequest.create(projectId:scheduleItemId:)`; `AttentionListSheet(items:names:onSelect:onRecord:)` làm tương tự (đóng sheet rồi mở form). `HomeView(…, makePaymentForm:)`.
- More: dòng `more_crew` (`more.crew`) sau Khách hàng. `MoreView(…, makeCrew:)`.
- Detail: §5.3 + slot `makeLabourSection` ngay sau `makeExpensesSection`.

## 6. DesignSystem

Không thay đổi. Nút −/+ số ngày dùng `Button` + SF Symbol `minus.circle`/`plus.circle` (vùng chạm 44pt) ngay trong form.

## 7. Localization

Thêm (en nguồn + vi):

- `detail.payments.*`: `title` ("Payments"/"Thanh toán"), `add` ("Record payment"/"Ghi thanh toán"), `empty`, `notLinked` ("Not linked to a stage"/"Không gắn đợt"), `unallocated %@`.
- `payment.*`: `new.title`, `edit.title`, `amount`, `chip.remaining %@`, `chip.full %@`, `chip.outstanding %@`, `overpay %@`, `items`, `item.none`, `item.left %@`, `date`, `method`, `notes`, `save`, `delete`, `delete.title`, `delete.message`, `delete.confirm`, `error.amountMissing`, `error.amountNotPositive`, `error.gone`, `error.incomplete`, `error.saveFailed`, `error.load`.
- `attention.record` ("Record"/"Ghi nhận"); `keyboard.done` ("Done"/"Xong").
- `detail.labour.*`: `title` ("Labour"/"Labour"), `add` ("Log labour"/"Ghi công"), `empty`, `all`, `total %@ %@`.
- `labour.*`: `list.title`, `new.title`, `edit.title`, `date`, `days`, `days.hint`, `days.minus`, `days.plus`, `days.one`, `days.count %@`, `crew`, `rate`, `rate.perDay %@`, `cost %@`, `already %@`, `row.detail %@ %@`, `unknownPerson`, `notes`, `total`, `save`, `delete`, `delete.title`, `delete.message`, `delete.confirm`, `error.<LabourDraftError>` ×5, `error.gone`, `error.incomplete`, `error.saveFailed`, `error.load`.
- `crew.*`: `title`, `add`, `empty.title`, `empty.message`, `new.title`, `edit.title`, `name`, `trade`, `phone`, `dailyRate`, `dailyRate.hint`, `hourlyRate`, `dailyFromHourly %@`, `notes`, `rate.hourly %@`, `noRate`, `delete`, `delete.title`, `delete.message`, `delete.confirm`, `error.nameMissing`, `error.rateNegative`, `error.gone`, `error.saveFailed`, `error`.
- `more.crew`.
- `activity.paymentUpdated`, `activity.paymentDeleted`, `activity.labourLogged`, `activity.labourUpdated`, `activity.labourDeleted` (câu trơn); `activity.paymentReceived %@ %@` ("Payment received: %1$@ — %2$@"), `activity.paymentUpdated %@ %@ %@` ("Payment %1$@: %2$@ → %3$@"), `activity.paymentDeleted %@ %@` ("Payment deleted: %1$@ — %2$@"), `activity.labourLogged %@ %@` ("Labour: %1$@ — %2$@"), `activity.labourUpdated %@ %@ %@` ("Labour %1$@: %2$@ → %3$@"), `activity.labourDeleted %@ %@` ("Labour deleted: %1$@ — %2$@").
- Đổi giá trị: `home.group.workDone` → "Work done" / "Xong việc".

`scripts/check_localization.py` sinh thêm: `payment.error.<PaymentDraftError>`, `labour.error.<LabourDraftError>`, `crew.error.<EmployeeDraftError>`.

## 8. App

- `AppContainer.Ready` thêm `paymentRepository`, `employeeRepository`, `labourRepository`.
- `Screens.swift`: `PaymentFormScreen(request:)`, `CrewScreen`, `LabourFormScreen(request:)`, `ProjectLabourSectionScreen(projectId:)`, `ProjectLabourListScreen(projectId:)`; `HomeScreen` truyền `makePaymentForm`; `ProjectDetailScreen` truyền `makeLabourSection` + `makePaymentForm`; `RootTabView` truyền `makeCrew`.
- Seed (DEBUG) không đổi chữ ký.

## 9. Lỗi và biên

- Project bị xóa khi form payment/công đang mở → snapshot nil / Lưu ném `notFound` → alert `*.error.gone`, form đóng sau OK (payment) hoặc giữ dữ liệu (công: Lưu ném).
- Đợt bị xóa (sửa schedule) khi form đang mở → snapshot mới không còn đợt đó; nếu đang chọn đợt đó thì Lưu ném `notFound` → `payment.error.gone`. Payment đã gắn đợt bị xóa → 2b đặt `schedule_item_id = NULL` → hiện "Không gắn đợt".
- Người bị xóa khỏi crew khi form công đang mở → Lưu ném `notFound`, **không** entry nào của lô được ghi.
- Payment cho project khác currency (dữ liệu hỏng) → `currencyMismatch`.
- Rate employee đổi sau khi ghi công → entry cũ giữ rate chụp; chỉ lần ghi mới lấy rate mới.
- Ghi trùng cùng người cùng ngày → cho phép, form cảnh báo `labour_already_<i>`.
- `today` qua nửa đêm: form lấy `today` lúc mở (như 3a).
- Hiệu năng: card Labour compose trên MainActor từ một stream theo project; payment form dùng stream insights của project.

## 10. Testing

Domain (Windows/Linux, XCTest):
- `PaymentDraftTests`: lỗi nil/0/0.004/−5, 0.005 hợp lệ; `makePayment` 11400.005 → 11400.01, notes trim; thiếu amount → `incompletePayment`; `apply` giữ id/project/createdAt, bỏ gắn đợt; method mặc định e-Transfer/cheque; `methodOrder`.
- `PaymentFormContextTests` (fixture Basement 2b): status `[paid, overdue, upcoming, upcoming]`, remaining `[0, 11,400, 11,400, 7,600]`, đợt mặc định Stage 2; sửa deposit (loại trừ chính nó) → deposit paid 0, remaining 7,600, `overdue`, outstanding 38,000 (không loại trừ: 30,400); chip: Stage 2 đã trả 5,000 → `[remaining 6,400, fullItem 11,400]`, Stage 3 → `[remaining 11,400]`, Deposit → `[]`, không gắn → `[outstanding 30,400]`, outstanding 0 → `[]`; trả dư 12,000 vào Stage 2 → dư 600, Stage 2 `paid`, Stage 3 vẫn paid 0, collected 19,600, outstanding 18,400; item/payment đã xóa bị bỏ.
- `PaymentListTests`: thứ tự `[500 (10-02, mới hơn), 50 (10-02), 7,600 (09-14)]`, nhãn `[nil, nil, "schedule.row.deposit"]`, collected 8,150, unallocated 550; payment gắn đợt đã xóa → không gắn; rỗng.
- `DashboardComposerTests`: `AttentionItem.scheduleItemId`.
- `EmployeeDraftTests`: lỗi tên trống/rate âm, rate ngày không bắt buộc; `makeEmployee` trim, trade → `trade`, `role` nil; `dailyFromHourly` 31.25 → 250.00, 28.33 → 226.64; `apply` giữ role/certifications; `CrewList.ordered` → `[David, mike, Zoe]` (bỏ người đã xóa).
- `LabourDraftTests`: toggle chụp rate `[250, 220]` và bỏ chọn; Mike+John 1 ngày = 470.00, 1.5 ngày → Mike 375.00, tổng 705.00; 0.5 × 333.33 = 166.67, + Mike 0.5 ngày = 291.67; thứ tự lỗi; rate 0 hợp lệ; `stepDays` 1 → 1.5 → 0.5 (sàn), nil → 0.5; `makeEntries` 2 entry cùng ngày/số ngày/ghi chú trim, id khác nhau; trống → `incompleteLabour`; `apply` David 7 → 8 ngày = 1,600.00 giữ người; `alreadyLoggedDays` 8.5 / 8 (loại trừ) / 0.
- `LabourListTests`: seed → ngày `[09-25, 09-24, 09-23]`, tổng `[1,400.00, 2,200.00, 2,000.00]`, tên `[David, John, Mike]`, tổng 5,600.00 / 25 ngày; cùng ngày theo tên, người đã xóa vẫn tên, entry đã xóa bị bỏ, employee không có → "", tổng 460.00.
- `ActivityDescriptionTests`: payment gắn đợt / không gắn (method) / sửa có `from`; labour logged/updated; thiếu trường → plain; `currency(for:)`.

Data (macOS CI):
- `PaymentRepositoryTests`: tạo 400 gắn Deposit → JSON `{"amount":"400.00","currency":"CAD","item":"Deposit","method":"eTransfer"}`, insights: Deposit `paid`, collected 400.00, outstanding 600.00; trả dư 700 vào đợt 600 + 50 không gắn → đợt `paid`, collected 750.00, unallocated 50.00; đợt đã xóa / đợt của project khác / project đã xóa → `notFound`, amount 0 → `invalidPaymentAmount`, USD → `currencyMismatch`, không dòng nào; sửa không đổi → không activity; sửa 400 → 450 + bỏ gắn → `{"amount":"450.00","currency":"CAD","from":"400.00","item":"","method":"eTransfer"}`; đổi project → `scopeMismatch`; xóa → `get` nil, collected 0.00, `paymentDeleted`, xóa lần hai `notFound`; `lastUsedMethod` nil → cash (mới nhất) → cheque sau khi xóa cash.
- `EmployeeRepositoryTests`: thứ tự sống; `emptyName`/`negativeAmount`/`currencyMismatch`; sửa không đổi giữ `updated_at`; sửa rate stamp `updated_at`; xóa → ẩn khỏi `observeAll`, `get(includingDeleted: false)` nil, `true` trả về; sửa/xóa người đã xóa → `notFound`.
- `LabourRepositoryTests`: lô Mike 1 × 250.00 + John 0.5 × 333.33 → 2 entry, **một** activity `{"currency":"CAD","names":"Mike, John","people":"2","total":"416.67","workDate":"2026-10-03"}`, insights labour 416.67; lô có người đã xóa → `notFound`, 0 entry, 0 activity; days 0 → `invalidLabourDays`; lô hai project → `scopeMismatch`; lô rỗng → `incompleteLabour`; sửa không đổi → không activity; 1 → 1.5 ngày → `{"currency":"CAD","from":"250.00","names":"Mike","people":"1","total":"375.00","workDate":"2026-10-03"}`; đổi employee → `scopeMismatch`; đổi rate employee sau khi ghi → entry vẫn 250.00, labour 500.00; xóa employee → entry còn, `observeProject.employees` còn tên, labour giữ nguyên, sửa entry vẫn được; xóa entry → `labourDeleted`, `observeProject` rỗng.
- `SampleDataTests`: 2 `paymentReceived`, 3 `labourLogged` (JSON Mike §4), crew 3 người với nghề §4, rate giờ Mike 31.25; số 2b/3a giữ nguyên.

UI tests (`UITests/PaymentsLabourFlowTests.swift`, launch `--ui-testing --seed-sample-data --locale en --today 2026-10-03`):
- (a) Basement → `detail_schedule_row_1` (Stage 2) → `payment_save` → `detail_schedule_row_1` chứa "Paid", không chứa "Overdue"; `detail_collected` "19,000.00"; Home `home_total_collected` "37,500.00", `home_total_outstanding` "44,000.00", `home_total_cash` "26,815.00"; `home_attention` không còn "overdue 5 days".
- (b) Home → `attention_record_*` (đầu tiên) → `payment_project` chứa "Basement Renovation" → `payment_save` → `home_total_collected` "37,500.00".
- (c) Kitchen → `detail_payments_add` → `payment_item_none` → amount 1000 → Lưu → `detail_payment_row_0` chứa "1,000.00" và "Not linked"; `detail_collected` "1,000.00"; `detail_schedule_row_0` chứa "Upcoming"; Home collected "27,100.00", outstanding "54,400.00".
- (d) Basement → `detail_payment_row_0` (Deposit 7,600) → `payment_delete` → `payment_delete_confirm` → `detail_collected` "$0.00"; `detail_schedule_row_0` chứa "Overdue"; Home collected "18,500.00", outstanding "63,000.00", cash "7,815.00"; `home_attention` chứa "overdue 20 days".
- (e) Thêm → `more_crew` → `crew_add` → "Sam Patel", nghề "Electrician", rate ngày 300 → `crew_save` → dòng `crew_row_*` chứa "Sam Patel" và "300.00"; Basement → `detail_labour_add` → chọn Sam → `labour_total` "300.00" → `labour_save` → `detail_labour_total` "5,900.00"; Home spent "10,985.00".
- (f) Basement → `detail_labour_add` → chọn Mike + John (số ngày 1) → `labour_total` "470.00" → `labour_save` → `detail_labour_total` "6,070.00"; `detail_health` "Over budget"; `detail_health_reasons` chứa "70.00"; Home spent "11,155.00", cash "14,945.00".
- (g) Basement → dòng `labour_row_*` chứa "David" → `labour_days` 7 → 8 → `labour_save` → `detail_labour_total` "5,800.00"; Home spent "10,885.00".
- (h) vi (`--locale vi`, `-AppleLocale vi_VN`): Basement → `detail_payments` chứa "Thanh toán"; `detail_labour_add` chứa "Ghi công"; tab "Thêm" → `more_crew` chứa "Crew" → dòng Mike chứa "ngày".
- Screenshots (thêm vào `ScreenshotTests`, nhánh light): `detail_payments_<locale>`, `payment_form_<locale>`, `detail_labour_<locale>`, `labour_form_<locale>`, `crew_<locale>`. Giới hạn vuốt tới `detail_activity_all` nâng 4 → 8, tới `detail_expenses` 3 → 5 (detail dài hơn).

## 11. Tiêu chí hoàn thành

- Domain/Data/UI tests xanh; `check_localization.py` 0 lỗi; `lint_sources.py` 0 lỗi; DashboardFlowTests/ExpensesFlowTests giữ mọi số.
- Trên seed: từ Home ghi nhận Stage 2 ≤ 3 chạm (Ghi nhận, Lưu — số tiền đã điền); ghi công cho 2 người ≤ 5 chạm (Ghi công, Mike, John, Ghi công); Home và detail đổi số ngay.
- TestFlight build mới từ `main`; thử trên iPhone thật một lần ghi payment và một lần ghi công.

## 12. Ngoài phạm vi 3b

Invoice/receipt gửi khách, nhắc thanh toán (notification — 4/5), chấm công theo giờ và timesheet, lương/payroll, phân công crew theo ngày (`project_workers`) và cảnh báo trùng lịch (4), số ngày khác nhau cho từng người trong một lô (sửa từng dòng sau), chuyển payment sang project khác, tự phân bổ payment dư sang đợt sau (Foundation cấm), undo xóa, đồng bộ (5), báo cáo/xuất CSV, nhiều currency.

## Errata

- Task 13 (CI): with the eight `PaymentsLabourFlowTests` and the money screenshots, the `ios.yml` UI test step takes ~40.5 min and the job finished 28 s under its 45-minute `timeout-minutes` (run 37223436970). Raised to 60 minutes.
- Task 13 (screenshots): `detail_payments_<locale>` drags the Payments card from the lower half of the screen towards the top after the swipe loop, because the card already counts as hittable while only its top edge shows under the tab bar.
