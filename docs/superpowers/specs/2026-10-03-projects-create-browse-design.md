# ConMa — Sub-project 2a: Projects — Create & browse

Ngày: 2026-10-03
Trạng thái: chờ review
Tiền đề: Sub-project 1 Foundation (`docs/superpowers/specs/2026-10-02-foundation-design.md`) đã merge, CI xanh, TestFlight build 0.1.0 (3).

## 1. Mục tiêu

Contractor tạo được project thật trên iPhone bằng wizard 12 bước (tối thiểu 4 bước bắt buộc), xem danh sách project theo trạng thái, xem và bổ sung chi tiết project, quản lý khách hàng. Không có số liệu tiền thực tế (expenses/payments) — phần đó thuộc sub-project 3; dashboard số liệu và health thuộc 2b.

Sub-project 2 được tách:

| | Phạm vi |
|---|---|
| **2a (tài liệu này)** | Customers, Wizard 12 bước, Project list, Project detail cơ bản + edit sheet từng section, nháp wizard |
| 2b | Dashboard summary + Today, card Home với Spent/Collected/Cash position, Financial summary + Health + Timeline trong detail, đổi status/progress thủ công, xóa project, activity log view |

## 2. Quyết định đã chốt

| Chủ đề | Quyết định |
|---|---|
| Bắt buộc để tạo project | Job type (+ tên nếu Other), Customer, Address line, Contract price. Mọi bước khác có **Bỏ qua**; project tạo ở `status = estimate`. |
| Scope fields | Catalog tĩnh trong code cho 20 job type (Phụ lục B) + trường chung + trường tự do `custom:<label>`. Tất cả optional. |
| Payment schedule | Template (`depositFinal` 30/70, `depositProgressFinal` 30/40/30, `fourStage` 20/30/30/20, `custom`) + chỉnh tay % hoặc số tiền; tổng ≠ contract là cảnh báo vàng, không chặn. |
| Nháp wizard | Tự lưu JSON file sau mỗi bước và debounce 2 giây khi gõ; một nháp duy nhất; banner "Tiếp tục nháp" ở tab Projects. |
| Sửa sau khi tạo | Mỗi section trong detail mở lại đúng view bước wizard dạng sheet, lưu ngay qua repository. Một bộ UI cho tạo và sửa. |
| Customer trong wizard | Chọn từ danh sách có tìm kiếm hoặc "+ Khách mới" inline. |
| Project list | Lọc theo phase (Tất cả / Đang làm / Sắp tới / Xong / Đã đóng), tìm theo tên, địa chỉ, khách. |
| Customers | Vào từ More → Khách hàng (giữ 5 tab). |
| Kiến trúc | `ProjectDraft` value type (Domain, Codable) là state wizard, file nháp và input edit sheet; `ProjectDraftAssembler` thuần; tạo project trong một transaction. |

## 3. Domain

### 3.1 `ProjectDraft`

`public struct ProjectDraft: Codable, Equatable, Sendable`. Mọi trường optional/rỗng mặc định; `init()` cho draft trống.

| Trường | Kiểu | Ghi chú |
|---|---|---|
| `jobType` | `JobType?` | |
| `customJobType` | `String?` | bắt buộc khi `jobType == .other` |
| `customer` | `CustomerChoice?` | `.existing(UUID)` hoặc `.new(NewCustomerInput)` |
| `projectName` | `String?` | nil → assembler đặt mặc định (3.5) |
| `address` | `Address?` | `line` bắt buộc khi tạo |
| `scopeDescription` | `String?` | |
| `scopeFields` | `[DraftScopeField]` | `key: String` (catalog key hoặc `custom:<label>`), `value: String`, `sortOrder: Int` |
| `startDate`, `estimatedCompletionDate` | `CalendarDate?` | completion < start → `DraftError.completionBeforeStart` |
| `workingDays`, `workersPerDay` | `Int?` | ≥ 0 |
| `hoursPerDay` | `Decimal?` | 0 < h ≤ 24 |
| `labourMode` | `LabourEntryMode` | `.quick` \| `.detailed`; mặc định `.quick` |
| `labourQuick` | `LabourQuickInput?` | `workers: Int`, `dailyRate: Money`, `days: Decimal` |
| `labourLines` | `[DraftEstimateLine]` | mode detailed: `label` = tên worker, `unitRate` = rate/ngày, `quantity` = ngày |
| `materialLines` | `[DraftEstimateLine]` | |
| `otherLines` | `[DraftEstimateLine]` | `otherKind: OtherCostKind?` để map costGroup |
| `contractValue` | `Money?` | ≥ 0 |
| `deposit` | `DraftDeposit?` | `mode: .percentage(Percentage) \| .fixed(Money)`, `deadline: CalendarDate?`, `requiredToStart: Bool` |
| `scheduleTemplate` | `PaymentScheduleTemplate?` | nil = chưa chọn |
| `schedule` | `[DraftScheduleRow]` | `label: String`, `percentage: Percentage?`, `amount: Money?`, `dueDate: CalendarDate?`, `trigger: String?`, `isDeposit: Bool` |
| `step` | `Int` | 1…12, bước đang đứng (cho nháp) |
| `updatedAt` | `Date` | |

`DraftEstimateLine { id: UUID, label: String, amount: Money, quantity: Decimal?, unitRate: Money?, costGroup: CostGroup, otherKind: OtherCostKind?, sortOrder: Int }`. `id` giữ nguyên qua edit để `DraftDiff` nhận ra dòng cũ. Khi có cả `quantity` và `unitRate`, `amount = unitRate.multiplied(by: quantity)` (UI tính, assembler kiểm tra lại và ghi đè).

`NewCustomerInput { name, phone?, email?, preferredContact?, companyName?, secondaryContact?, notes? }` — `name` không rỗng.

`OtherCostKind` (11, theo yêu cầu gốc bước 8) → `CostGroup`: subcontractors → subcontractor; equipmentRental, toolRental → equipment; permits, inspectionFees → permit; dumpster, delivery, parking, gas, wasteDisposal, other → other.

### 3.2 `PaymentScheduleTemplate`

`enum PaymentScheduleTemplate: String, CaseIterable, Codable { depositFinal, depositProgressFinal, fourStage, custom }`.

`rows(depositPercentage: Percentage?) -> [DraftScheduleRow]`:

| Template | Dòng (label key, %) |
|---|---|
| `depositFinal` | deposit 30, final 70 |
| `depositProgressFinal` | deposit 30, progress 40, final 30 |
| `fourStage` | deposit 20, stage2 30, stage3 30, final 20 |
| `custom` | một dòng deposit 0 % hoặc `[]` nếu không có deposit |

Nếu `depositPercentage` có giá trị: dòng đầu dùng % đó; phần còn lại (100 − deposit) chia **theo tỉ lệ** của mẫu giữa các dòng sau, làm tròn 2 chữ số, dòng cuối nhận phần dư để tổng đúng 100. Ví dụ `fourStage` với deposit 25 → 25 / 28.13 / 28.13 / 18.74. Label dòng là key (`schedule.row.deposit`, `.progress`, `.stage2`, `.stage3`, `.final`); UI dịch; contractor sửa label thì lưu text tự do.

### 3.3 `ScheduleMath`

`recompute(rows: [DraftScheduleRow], contract: Money, edited: EditedField) -> ScheduleResult` với `EditedField = .percentage(index) | .amount(index) | .none`:

- `.percentage(i)`: giữ % mọi dòng, tính lại `amount` toàn bộ bằng `ScheduleSplitter.amounts(of: contract, percentages:)` (dòng cuối nhận phần dư khi tổng % = 100). Dòng không có % → amount giữ nguyên.
- `.amount(i)`: dòng i giữ amount vừa nhập, `percentage = Percentage.computed(amount / contract × 100)` (contract = 0 → `nil`); dòng khác không đổi.
- `.none`: như `.percentage` cho mọi dòng có %.
- `ScheduleResult { rows, total: Money, warning: ScheduleWarning? }`; `warning = .totalMismatch(difference: Money)` khi `total ≠ contract`, `.contractZero` khi contract = 0 và có dòng %.
- `contract = 0`: mọi amount từ % = 0; không chia cho 0.

### 3.4 `DraftFinancialPreview`

Tính cho bước 9 và 12 từ draft, không cần DB: `estimateByGroup`, `estimatedCost`, `projectedProfit = contract − estimatedCost`, `projectedMargin` (nil khi contract = 0 hoặc nil), `scheduleTotal`, `scheduleWarning`, `depositAmount` (từ % hoặc fixed). Dùng `FinancialCalculator` với expenses/labour/payments rỗng và `Project` tạm.

### 3.5 `ProjectDraftAssembler`

`assemble(_ draft: ProjectDraft, companyId: UUID, currency: CurrencyCode, now: Date) throws -> NewProjectBundle`.

Validation (ném `DraftError`):

| Lỗi | Điều kiện |
|---|---|
| `.missing([.jobType])` | `jobType == nil` |
| `.missing([.customJobType])` | `.other` và `customJobType` rỗng/blank |
| `.missing([.customer])` | `customer == nil`; `.new` với name blank |
| `.missing([.addressLine])` | `address == nil` hoặc `line` blank |
| `.missing([.contractValue])` | `contractValue == nil` |
| `.negativeAmount` | contract, line amount, deposit fixed < 0 |
| `.completionBeforeStart` | cả hai ngày có và completion < start |
| `.invalidTimeline` | workingDays/workersPerDay < 0, hoursPerDay ∉ (0, 24] |
| `.currencyMismatch` | bất kỳ Money nào khác `currency` |

`.missing` gom tất cả field thiếu trong một lỗi để UI tô đỏ nhiều section cùng lúc. Các điều kiện khác dừng ở lỗi đầu tiên.

Kết quả `NewProjectBundle { project: Project, scopeFields: [ProjectScopeField], estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], newCustomer: Customer? }`:

- `project.status = .estimate`; `name = draft.projectName` hoặc mặc định: tên job type bằng tiếng Anh từ `JobType` (ví dụ "Kitchen", "Basement Renovation") hoặc `customJobType`. Tên là dữ liệu người dùng, không dịch lại sau.
- `customerId`: `.existing(id)` hoặc `newCustomer.id` (UUID mới, `createdAt = now`).
- `manualProgress = nil`, `depositRequiredToStart = deposit?.requiredToStart ?? false`.
- Scope fields: giữ `sortOrder`, bỏ dòng có `key` blank hoặc `value` blank.
- Estimate lines: labour quick → **một** dòng `label = "schedule.row.labourQuick"` (key, UI dịch), `quantity = workers × days`, `unitRate = dailyRate`, `amount = rounded(dailyRate × workers × days)`; labour detailed → mỗi dòng `amount = rounded(unitRate × quantity)`; material/other giữ amount nhập (unitRate/quantity nếu có thì amount tính lại). `sortOrder` theo thứ tự nhập trong từng nhóm.
- Schedule items: từ `ScheduleMath.recompute(.none)`; `amount` là giá trị có thẩm quyền; `percentage` lưu kèm; dòng `isDeposit = true` lấy `dueDate = deposit.deadline` nếu dòng không có dueDate riêng. Nếu draft có `deposit` nhưng `schedule` rỗng → tạo một item deposit (amount từ % hoặc fixed, dueDate = deadline).
- Mọi entity: `id` mới, `companyId`, `createdAt = updatedAt = now`, `deletedAt = nil`.

Cảnh báo (không chặn, trả trong `bundle.warnings`): `.scheduleTotalMismatch(difference)`, `.depositExceedsContract`, `.scheduleEmpty`.

### 3.6 `ProjectDraft(from:)` và `DraftDiff`

`ProjectDraft(project:, scopeFields:, estimateLines:, scheduleItems:)` dựng draft seed cho edit sheet: `customer = .existing(project.customerId)`, `labourMode = .detailed`, mọi line giữ `id` gốc, `scheduleTemplate = .custom`, `step` = bước của section.

`DraftDiff.estimateLines(group:, old: [ProjectEstimateLine], new: [DraftEstimateLine], companyId:, projectId:, now:) -> EstimateLineChange { upserts: [ProjectEstimateLine], deletedIds: [UUID], totalBefore: Money, totalAfter: Money }`: dòng `new.id` trùng `old.id` → update giữ `createdAt`; `new.id` lạ → insert; `old.id` không còn → soft-delete. Tương tự `DraftDiff.scheduleItems(...)` và `DraftDiff.scopeFields(...)`.

### 3.7 Repository protocols (Domain)

```swift
public protocol ProjectRepository {               // mở rộng
    func create(_ bundle: NewProjectBundle, actor: ActivityActor) async throws
    func observeDetail(id: UUID) -> AsyncThrowingStream<ProjectDetailSnapshot?, Error>
    // giữ: get, list, observeSummaries, save(_:actor:), softDelete
}
public struct ProjectDetailSnapshot: Sendable, Hashable {
    public let project: Project
    public let customer: Customer
    public let estimateLines: [ProjectEstimateLine]
    public let scheduleItems: [PaymentScheduleItem]
}
public protocol ProjectEstimateRepository: Sendable {
    func lines(projectId: UUID) async throws -> [ProjectEstimateLine]
    func replace(projectId: UUID, group: CostGroup, change: EstimateLineChange, actor: ActivityActor) async throws
}
public protocol PaymentScheduleRepository: Sendable {
    func items(projectId: UUID) async throws -> [PaymentScheduleItem]
    func replace(projectId: UUID, change: ScheduleItemChange, actor: ActivityActor) async throws
}
public protocol CustomerRepository {              // mở rộng
    func observeAll(companyId: UUID) -> AsyncThrowingStream<[Customer], Error>
    func projects(customerId: UUID) async throws -> [Project]
}
public protocol DraftStore: Sendable {
    func load() throws -> ProjectDraft?
    func save(_ draft: ProjectDraft) throws
    func clear() throws
}
```

`ActivityAction` thêm: `estimateChanged`, `scheduleChanged`, `customerCreated`, `scopeChanged`, `timelineChanged`.

### 3.8 `ScopeFieldCatalog` (FeatureSupport, không phải Domain)

`ScopeFieldDefinition { key: String, kind: Kind, unitKey: String? }` với `Kind = integer | decimal | text | toggle | choice([optionKey])`. `ScopeFieldCatalog.fields(for: JobType) -> [ScopeFieldDefinition]` = trường chung + trường theo type (Phụ lục B). Giá trị lưu `value_text`: integer/decimal dạng chuỗi số canonical (dấu chấm thập phân, không nhóm hàng nghìn); toggle `"true"/"false"`; choice = optionKey; text nguyên văn. UI parse/format theo locale (`Decimal.FormatStyle` với `resolvedLocale`), lưu canonical.

Đổi job type khi `scopeFields` đã có giá trị: hỏi "Giữ các trường không thuộc loại mới?" — Giữ (thành `custom:<label dịch>`) / Xóa / Hủy.

## 4. Data

### 4.1 Records mới

`ProjectEstimateLineRecord`, `PaymentScheduleItemRecord` theo mẫu Foundation (Codable snake_case, mapper hai chiều, `DataError.corruptRow`). Không có migration mới.

### 4.2 `GRDBProjectRepository`

- `create(bundle, actor)`: một `write`: validate project + customer mới (Domain `validate()`), insert customer mới (nếu có) → project → scope fields → estimate lines → schedule items → `activity_log` **một** dòng `projectCreated` với details `{"name","contractValue","estimateLines","scheduleItems"}` (+ `customerCreated` nếu có khách mới). Lỗi bất kỳ → rollback toàn bộ.
- `save(_:actor:)` thêm guard: `contractValue.currency` ≠ `companies.currency_code` → `DomainError.currencyMismatch`; id đã soft-delete → `DataError.notFound` (không hồi sinh).
- `observeDetail(id)`: `ValueObservation` đọc project (live), customer (kể cả đã xóa — hiển thị lịch sử), scope fields, estimate lines, schedule items live, sort theo `sort_order`; project không tồn tại/đã xóa → emit `nil`.

### 4.3 `GRDBProjectEstimateRepository.replace`

Một transaction: kiểm tra mọi `upsert.projectId == projectId && costGroup == group` (lệch → `DataError.scopeMismatch`); upsert; soft-delete `deletedIds` (chỉ dòng thuộc project và group); nếu `totalBefore ≠ totalAfter` ghi `estimateChanged` `{"group","from","to"}`.

### 4.4 `GRDBPaymentScheduleRepository.replace`

Cùng mẫu; với mỗi item soft-delete: `UPDATE payments SET schedule_item_id = NULL, updated_at, sync_state='pending' WHERE schedule_item_id = ? AND deleted_at IS NULL` (A.2); activity `scheduleChanged` `{"from","to"}` khi tổng đổi.

### 4.5 `GRDBCustomerRepository`

Thêm `observeAll(companyId)` (live, sort tên, `localizedCaseInsensitiveCompare`), `projects(customerId)` (live projects, `updated_at DESC`). `softDelete` giữ rule `customerHasProjects`.

### 4.6 `FileDraftStore`

File `Application Support/ConMa/drafts/project-wizard.json`; ghi `Data.write(options: .atomic)`; JSON qua `JSONEncoder` với `.sortedKeys`. `load()`: file không có → `nil`; decode lỗi → đổi tên thành `project-wizard.corrupt-<timestamp>.json`, trả `nil`, không ném. `--ui-testing`: thư mục temp riêng, xóa lúc khởi động.

### 4.7 Seed (debug)

Project "Basement Renovation": 6 scope fields (sqft 1200, bedrooms 1, bathrooms 1, egressWindows 1, ceilingHeight 7.5, wetBar false), estimate 3 labour + 4 material + 2 other (tổng ≈ $24,000), schedule `fourStage` với deposit đã có dueDate quá khứ. "Kitchen Renovation" (awaitingDeposit): deposit 20 % deadline = seed date + 7 ngày.

## 5. Màn hình

### 5.1 Tab Projects

- Search bar (`.searchable`), lọc client-side trên `observeSummaries`: khớp `project.name`, `address.line`, `address.city`, `customerName` (không phân biệt hoa thường, bỏ dấu tiếng Việt khi so).
- Segmented filter: Tất cả · Đang làm (`inWork`) · Sắp tới (`preStart`) · Xong (`workDone`) · Đã đóng (`terminal`). Mặc định "Đang làm" nếu có ≥ 1, không thì "Tất cả". Lưu lựa chọn trong `@SceneStorage`.
- Danh sách `ProjectCardView` (chuyển vào `FeatureSupport` để Home dùng chung; thêm dòng ngày `start → completion` khi có). Tap → `ProjectDetailView`.
- Banner nháp (khi `DraftStore.load() != nil`): "Tiếp tục nháp: <address.line hoặc job type> · bước N/12" — [Tiếp tục] mở wizard ở bước N, [Bỏ] xác nhận rồi `clear()`.
- FAB "+" → wizard. Empty state: "Chưa có dự án" + nút "Tạo dự án đầu tiên".

### 5.2 Wizard

`fullScreenCover`, `NavigationStack` nội bộ, `ProjectWizardViewModel` (@Observable, @MainActor) giữ `draft`, `step`, `errors: Set<DraftField>`, `preview`, `isSaving`. Header: tiêu đề bước + "N/12" + `ProgressBar`. Footer cố định: **Tiếp tục** (PrimaryButton), **Bỏ qua** (SecondaryButton, chỉ bước optional). Nút X: draft rỗng → đóng; có dữ liệu → alert Lưu nháp / Bỏ nháp / Hủy.

Tự lưu: `DraftStore.save` sau mỗi lần đổi bước và debounce 2 giây sau thay đổi draft. Ghi lỗi → log, không chặn người dùng.

| Bước | Bắt buộc | Nội dung |
|---|---|---|
| 1 Job type | ✓ | Lưới 2 cột 20 ô (SF Symbol + tên); Other → TextField tên. |
| 2 Customer | ✓ | Search + danh sách `observeAll`; "+ Khách mới" mở form inline (tên bắt buộc). |
| 3 Location | ✓ (line) | line, unit, city, region, postal code; "Mở Maps" (`maps://?q=<address>`). |
| 4 Scope | – | TextEditor mô tả; trường theo catalog; "+ Thêm trường" (label → `custom:<label>`). |
| 5 Timeline | – | 2 DatePicker compact; working days, hours/day, workers/day (stepper hoặc keypad). Completion < start → lỗi đỏ, chặn Tiếp tục. |
| 6 Labour | – | Segmented Nhanh/Chi tiết. Nhanh: workers, rate/ngày, ngày → tổng. Chi tiết: danh sách dòng (tên, rate, ngày), thêm/xóa. |
| 7 Material | – | Dòng label + amount; chip gợi ý label theo job type (Phụ lục B.3); tổng. |
| 8 Other costs | – | Thêm dòng chọn `OtherCostKind` (11) + amount; tổng. |
| 9 Price | ✓ | Contract value (decimalPad, font lớn); Estimated cost / Projected profit / Margin từ preview; đỏ khi profit âm. |
| 10 Deposit | – | Toggle Yes/No; segmented % / số tiền; giá trị quy đổi; deadline (optional); toggle "Chưa nhận deposit thì chưa bắt đầu". |
| 11 Schedule | – | 4 nút template; danh sách dòng: label, %, amount, due date, trigger; sửa % ↔ amount qua `ScheduleMath`; thêm/xóa/kéo sắp xếp; cảnh báo vàng tổng ≠ contract; dòng đầu đánh dấu Deposit. |
| 12 Review | – | Tên project (prefill); sections gấp được; thiếu bắt buộc → section đỏ + "Sửa" nhảy bước; **Tạo project** → `create` → `clear()` nháp → đóng wizard → push detail. Lỗi lưu → alert, giữ wizard. |

Nhập số: `TextField` với `format: .number.locale(resolvedLocale)` cho Decimal, `.decimalPad`, toolbar nút Xong. Tiền: `MoneyField` component mới trong DesignSystem (hiện ký hiệu currency, parse theo locale, lưu `Money`).

### 5.3 Project detail (cơ bản)

Header: tên, địa chỉ, khách (tap → customer profile), `StatusBadge`, `ProgressBar` (manual hoặc 0), contract value, "start → completion".

Sections (mỗi section nút **Sửa** mở sheet = view bước tương ứng với draft seed, footer **Lưu**/**Hủy**):

| Section | Bước tái dùng | Lưu qua |
|---|---|---|
| Scope | 4 | `ProjectRepository.save` (scopeDescription + scopeFields qua `replaceScopeFields` hiện có) + activity `scopeChanged` |
| Timeline | 5 | `ProjectRepository.save` + activity `timelineChanged` khi ngày đổi |
| Estimate (3 nhóm, tổng, projected profit/margin) | 6 / 7 / 8 | `ProjectEstimateRepository.replace(group:)` |
| Price & Deposit | 9 + 10 | `ProjectRepository.save` (contract) + `PaymentScheduleRepository.replace` cho dòng deposit |
| Payment schedule | 11 | `PaymentScheduleRepository.replace`; mỗi dòng hiện `PaymentStatus` từ resolver với `paidForItem = 0` |
| Customer | – | tap mở profile; đổi khách để 2b |

Không có ở 2a: đổi status/progress, xóa, activity log, health, Mark received.

### 5.4 Customers (More → Khách hàng)

Danh sách `observeAll` + search; "+" form (tên bắt buộc, phone, email, preferred contact, company, secondary contact, notes). Profile: thông tin + nút Gọi/Nhắn/Email (`tel:`, `sms:`, `mailto:`; ẩn khi thiếu dữ liệu) + danh sách project của khách (`projects(customerId)`, tap → detail) + Sửa + Xóa (từ chối với thông báo khi `customerHasProjects`).

### 5.5 Home

Giữ card hiện tại; dùng `ProjectCardView` chung; tap → detail. Số liệu dashboard để 2b.

## 6. Localization

Key mới (≈ 200): `wizard.*`, `scope.field.*`, `scope.unit.*`, `scope.option.*`, `estimate.*`, `otherCost.*`, `schedule.*`, `detail.*`, `customers.*`, `projects.*`, `draft.*`. English source, Việt 100 %, thuật ngữ nghề giữ tiếng Anh theo bảng Foundation (deposit, estimate, drywall, framing, roofing, flooring, plumbing, HVAC, deck, demolition, inspection, subcontractor, labour, material, e-transfer).

`check_localization.py` mở rộng: đọc `ScopeFieldCatalog.swift`, `OtherCostKind`, `PaymentScheduleTemplate` bằng regex và yêu cầu mọi key sinh ra (`scope.field.<key>`, `scope.option.<key>`, `otherCost.<kind>`, `schedule.row.<label>`) có trong catalog với bản vi.

Số: parse/format theo `resolvedLocale` (vi: dấu phẩy thập phân, chấm hàng nghìn). Lưu canonical.

## 7. Testing

**Domain (Linux)**: assembler đầy đủ / tối thiểu / `.missing` gom nhiều field / từng lỗi khác; mặc định tên project; labour quick `quantity = workers × days`; 11 `OtherCostKind` → costGroup; template rows có/không deposit % (kể cả 25 → 25/28.13/28.13/18.74); `ScheduleMath` sửa %, sửa amount, contract 0, cảnh báo; deposit fixed > contract → cảnh báo không chặn; `ProjectDraft(from:)` → assemble → cùng dữ liệu; `DraftDiff` giữ id dòng cũ, xóa dòng bỏ, tổng before/after.

**Data (macOS)**: `create` round trip + `observeDetail` emit; rollback khi item vi phạm FK; `replace` estimate (giữ id, soft-delete, activity chỉ khi tổng đổi, scopeMismatch); `replace` schedule nullify payment; currency guard; save id đã xóa → notFound; `observeAll`/`projects(customerId)`; `FileDraftStore` round trip, file hỏng → nil + đổi tên, atomic.

**UI (simulator)**: (a) tạo tối thiểu 4 bước + Skip → detail; (b) tạo đầy đủ với `fourStage` → 4 dòng, tổng = contract; (c) đóng giữa chừng → relaunch → banner → đúng bước; (d) sửa Estimate từ detail → tổng live; (e) thêm khách từ More → hiện ở bước 2; (f) `--locale vi` nhập "1.500,50" → lưu `1500.50`.

**Screenshot**: 12 bước + detail + customers list/profile, en/vi light; detail dark.

**Review Focus** (test gắn vào task sở hữu): parse số theo locale vi; contract 0 với schedule %; đổi job type khi đã có scope fields; address line toàn khoảng trắng = thiếu; nháp hỏng không crash; wizard đang mở khi app bị kill → nháp đúng bước.

## 8. Tiêu chí hoàn thành

1. `domain.yml`, `ios.yml` xanh; TestFlight build mới cài được.
2. Trên iPhone: tạo project tối thiểu < 60 giây; tạo đầy đủ với template; thoát và tiếp tục nháp đúng bước.
3. Projects lọc theo phase và tìm theo tên/địa chỉ/khách.
4. Detail đủ section; sửa Scope/Timeline/Estimate/Price·Deposit/Schedule ghi DB và hiện lại ngay.
5. Customers thêm/sửa/xem project; không xóa khách còn project.
6. 100 % key có bản vi; lint xanh.

## 9. Ngoài phạm vi

Dashboard summary/Today, financial summary thật, health, timeline sự kiện, đổi status/progress, xóa project, đổi khách của project, Mark payment received, expenses, photos, Supabase.

## 10. Rủi ro

- Wizard 12 bước là khối UI lớn nhất tới nay; CI mỗi vòng 10–15 phút. Giảm thiểu: Domain + Data trước, UI chia theo bước, screenshot để duyệt sớm.
- Nhập số theo locale dễ sai (vi dùng dấu phẩy). Giảm thiểu: một `MoneyField`/`DecimalField` dùng chung, test UI với `--locale vi`.
- `fullScreenCover` + `NavigationStack` lồng trong TabView có lúc mất state khi đổi locale (Foundation rebuild view theo `resolvedLocale`). Giảm thiểu: wizard giữ `draft` trong ViewModel sở hữu bởi `@State` ở `ProjectsScreen`, không tạo trong `body`.

## Phụ lục B: Scope field catalog

Kiểu: `int`, `dec` (Decimal), `text`, `toggle`, `choice(...)`. Đơn vị trong ngoặc vuông.

### B.1 Trường chung (mọi job type)

`squareFootage` dec [sqft] · `rooms` int · `floors` int · `itemsToRepair` int · `itemsToInstall` int

### B.2 Theo job type

| JobType | Trường |
|---|---|
| generalRenovation | `bathrooms` int, `windows` int, `doors` int |
| basementRenovation | `bedrooms` int, `bathrooms` int, `egressWindows` int, `ceilingHeight` dec [ft], `wetBar` toggle |
| kitchen | `cabinetLinearFeet` dec [ft], `countertopType` choice(laminate, quartz, granite, butcherBlock, other), `appliances` int, `island` toggle, `backsplashSqft` dec [sqft] |
| bathroom | `fixtures` int, `tub` toggle, `shower` toggle, `vanity` toggle, `toilet` toggle, `tileSqft` dec [sqft] |
| landscaping | `lotSize` dec [sqft], `grassArea` dec [sqft], `patioArea` dec [sqft], `fenceLength` dec [ft], `trees` int, `irrigation` toggle |
| roofing | `roofSqft` dec [sqft], `roofType` choice(asphaltShingle, metal, flat, cedar, tile, other), `slopes` int, `layersToRemove` int, `materialType` text |
| plumbing | `fixtures` int, `bathrooms` int, `waterHeater` toggle, `repipe` toggle |
| electrical | `outlets` int, `switches` int, `lightFixtures` int, `panelUpgrade` toggle, `panelAmps` choice(amps100, amps200, other) |
| hvac | `systemType` choice(furnace, heatPump, centralAir, ductless, other), `units` int, `ductworkFeet` dec [ft], `thermostats` int |
| flooring | `floorSqft` dec [sqft], `flooringType` choice(hardwood, laminate, vinyl, tile, carpet, other), `stairs` int, `removalRequired` toggle |
| painting | `wallSqft` dec [sqft], `ceilingSqft` dec [sqft], `doors` int, `trimLinearFeet` dec [ft], `coats` int |
| drywall | `sheets` int, `drywallSqft` dec [sqft], `ceilings` toggle, `finishLevel` choice(level3, level4, level5) |
| concrete | `concreteSqft` dec [sqft], `thicknessInches` dec [in], `concreteType` choice(slab, driveway, sidewalk, foundation, other), `rebar` toggle |
| deckFence | `deckSqft` dec [sqft], `fenceLength` dec [ft], `fenceHeight` dec [ft], `deckMaterial` choice(pressureTreated, cedar, composite, vinyl, other), `stairs` int, `railingFeet` dec [ft] |
| framing | `wallLinearFeet` dec [ft], `framingSqft` dec [sqft], `loadBearing` toggle |
| windowsDoors | `windows` int, `doors` int, `exteriorDoors` int, `patioDoors` int |
| exterior | `sidingSqft` dec [sqft], `sidingType` choice(vinyl, wood, fiberCement, brick, stucco, other), `soffitFeet` dec [ft], `gutterFeet` dec [ft] |
| demolition | `demoSqft` dec [sqft], `dumpsters` int, `hazardousMaterials` toggle |
| commercial | `commercialSqft` dec [sqft], `units` int, `permitsRequired` toggle |
| other | chỉ trường chung |

Key trùng tên giữa các type (ví dụ `bathrooms`, `fixtures`, `doors`, `stairs`, `fenceLength`) là **một** key và một bản dịch.

### B.3 Gợi ý label material theo job type (chip ở bước 7)

Mặc định: Lumber, Drywall, Flooring, Paint, Tile, Fasteners, Other. Thêm theo type: kitchen → Cabinets, Countertop, Backsplash, Appliances; bathroom → Vanity, Tub/Shower, Toilet, Plumbing fixtures; roofing → Shingles, Underlayment, Flashing, Vents; landscaping → Sod, Pavers, Gravel, Plants, Fence panels; electrical → Wire, Panel, Outlets/Switches, Fixtures; plumbing → Pipe, Fittings, Water heater, Fixtures; flooring → Flooring, Underlay, Transitions; painting → Paint, Primer, Caulk; concrete → Concrete, Rebar, Forms; deckFence → Deck boards, Posts, Fence panels, Hardware; exterior → Siding, Soffit, Gutters; drywall → Drywall sheets, Mud, Tape; hvac → Unit, Ductwork, Thermostat; framing → Lumber, Hangers, Sheathing; windowsDoors → Windows, Doors, Trim. Chip chỉ điền label; contractor nhập amount.
