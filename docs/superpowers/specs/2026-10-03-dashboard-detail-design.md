# ConMa — Sub-project 2b: Dashboard & detail full

Ngày: 2026-10-03
Trạng thái: chờ review
Tiền đề: 2a merged (`main` 6f2ccb3, TestFlight 0.1.0 (3)). Spec 2a: `docs/superpowers/specs/2026-10-03-projects-create-browse-design.md` (kể cả Errata). Foundation: `docs/superpowers/specs/2026-10-02-foundation-design.md` (§5.3 financial engine, §5.4 rules — binding cho mọi công thức ở đây).

## 1. Mục tiêu

Mở app, trong 10 giây contractor trả lời được: job nào cần chú ý, đã chi / đã thu bao nhiêu, job lời hay vượt budget, hôm nay có gì. 2b thêm lớp **đọc và đánh giá** lên dữ liệu 2a: Home dashboard, card project có tiền, detail có Financial summary + Health + Timeline + Activity, đổi status/progress thủ công, đổi khách, xóa project. Không có màn nhập expense/payment/labour (sub-project 3) — 2b đọc các bảng đó (đang rỗng ngoài seed) để khi 3 thêm màn nhập thì dashboard tự sáng.

## 2. Quyết định đã chốt

| Chủ đề | Quyết định |
|---|---|
| Số liệu tiền khi chưa có nhập liệu | Nối thật qua `FinancialCalculator` trên bảng `expenses`/`labour_entries`/`payments`; rỗng thì Spent = 0, Collected = 0, Outstanding = contract, kèm empty state. |
| Home "Cần chú ý" | Gộp health ≠ On Track, payment quá hạn / đến hạn hôm nay, project bắt đầu hôm nay, quá hạn hoàn thành. Sub-project 4 chèn tasks vào cùng danh sách. |
| Đổi status | Tự do chọn 13 status; `closed`/`cancelled` xác nhận; sang `completed`/`awaitingFinalPayment` khi chưa có progress thủ công → gợi ý 100%, không ép. |
| Progress | `manualProgress` 0…100 (bước 5), có "Xóa tiến độ thủ công" (nil). Tasks (sub-project 4) sẽ thắng khi `manualProgress == nil`. |
| Activity log | Section 5 dòng cuối detail + màn "Xem tất cả" theo project. Không có màn toàn công ty trong 2b. |
| Xóa project | Menu ⋯ → xác nhận → soft delete cascade (A.2) → quay về list. Không undo. |
| Carry-over từ 2a | Làm: `DateLabel` theo locale, validation Timeline + lỗi cụ thể, đổi khách, nháp tham chiếu khách đã xóa. Để lại: drag-reorder schedule, `categoryInUse`, Percentage Codable, deposit row bị xóa / template đè. |
| Kiến trúc | Một stream `DashboardInputs` từ GRDB (`ValueObservation` 7 bảng) → `DashboardComposer` thuần trong Domain. Detail: `ProjectInsightsInputs` → `ProjectInsightsComposer`. UI chỉ render. Không aggregate bằng SQL. |
| `today` | Luôn truyền vào Domain. App tính `CalendarDate(Date(), timeZone: .current)`; tính lại khi `scenePhase == .active`. |

## 3. Domain

Thư mục mới `Packages/Domain/Sources/Domain/Insights/`. Tất cả `Sendable`, `Hashable` (trừ nơi ghi chú), Foundation-only, test trên Linux.

### 3.1 `ProjectInsights` và `ProjectInsightsComposer`

```swift
public struct PaymentItemInsight: Hashable, Sendable {
    public let item: PaymentScheduleItem
    public let paid: Money          // Σ payments có scheduleItemId == item.id (chưa xóa)
    public let remaining: Money     // max(0, item.amount − paid)
    public let status: PaymentStatus
}

public struct TimelineInsight: Hashable, Sendable {
    public let startDate: CalendarDate?
    public let estimatedCompletionDate: CalendarDate?
    public let daysElapsed: Int?        // start → today, ≥ 0; nil nếu không có start hoặc today < start (khi đó 0)
    public let daysRemaining: Int?      // today → completion; âm = trễ; nil nếu không có completion
    public let totalDays: Int?          // start → completion, nil nếu thiếu một ngày; 0 khi cùng ngày
    public let expectedProgress: Int?   // round(elapsed / total × 100) kẹp 0…100; nil nếu totalDays nil hoặc 0 → 100 nếu today ≥ completion
}

public struct ProjectInsights: Hashable, Sendable {
    public let projectId: UUID
    public let financials: ProjectFinancials?   // nil khi FinancialCalculator ném currencyMismatch
    public let budgetAlerts: [BudgetAlert]      // [] khi financials nil
    public let payments: [PaymentItemInsight]   // theo sortOrder item
    public let unallocatedCollected: Money      // Σ payments có scheduleItemId == nil
    public let progress: Int                    // ProgressCalculator.percent(tasks: [], manualProgress:)
    public let health: ProjectHealth?           // nil ở phase terminal
    public let timeline: TimelineInsight
}

public struct ProjectInsightsInputs: Sendable {
    public var project: Project
    public var estimateLines: [ProjectEstimateLine]
    public var scheduleItems: [PaymentScheduleItem]
    public var expenses: [Expense]
    public var labourEntries: [LabourEntry]
    public var payments: [Payment]
    public var today: CalendarDate
}

public enum ProjectInsightsComposer {
    public static func compose(_ inputs: ProjectInsightsInputs) -> ProjectInsights
}
```

Thứ tự tính: `FinancialCalculator.compute` (lỗi → `financials = nil`, `budgetAlerts = []`); `PaymentStatusResolver` cho từng item với `paid`; `ProgressCalculator`; `ProjectHealthEvaluator.evaluate(HealthInputs(status, estimatedCompletionDate, progress, budgetAlerts, paymentStatuses, today))`; `TimelineInsight`. Payment có `scheduleItemId` trỏ tới item đã xóa/không tồn tại tính như chưa gắn (vào `unallocatedCollected`; `collected` tổng vẫn đúng theo §5.3).

### 3.2 `Dashboard` và `DashboardComposer`

```swift
public struct DashboardInputs: Sendable {
    public var company: Company
    public var projects: [Project]              // chưa xóa, mọi status
    public var customers: [Customer]
    public var estimateLines: [ProjectEstimateLine]
    public var scheduleItems: [PaymentScheduleItem]
    public var expenses: [Expense]
    public var labourEntries: [LabourEntry]
    public var payments: [Payment]
    public var today: CalendarDate
}

public enum AttentionKind: Int, Comparable, Sendable { // thứ tự = mức nặng, nhỏ hơn = nặng hơn
    case overBudget = 0, paymentOverdue, paymentRisk, delayed, dueToday, startsToday, atRisk
}

public enum AttentionItem: Hashable, Sendable, Identifiable {
    case health(projectId: UUID, status: HealthStatus, reason: HealthReason)       // reason = reasons.first
    case paymentOverdue(projectId: UUID, itemId: UUID, label: String, remaining: Money, daysLate: Int)
    case paymentDueToday(projectId: UUID, itemId: UUID, label: String, remaining: Money)
    case startsToday(projectId: UUID)
    public var kind: AttentionKind { get }
    public var projectId: UUID { get }
    public var id: String { get }   // "<kind>:<projectId>[:<itemId>]"
}

public struct CompanyTotals: Hashable, Sendable {
    public let currency: Currency
    public let activeJobs: Int          // phase == .inWork
    public let outstanding: Money       // Σ outstandingBalance, phase ≠ terminal
    public let collected: Money         // Σ collected, phase ≠ terminal
    public let spent: Money             // Σ spentSoFar, phase ≠ terminal
    public let cashPosition: Money      // collected − spent
    public let excludedCount: Int       // project ≠ terminal có financials nil (khác currency)
}

public enum CardGroup: Int, Sendable { case inWork = 0, preStart, workDone }

public struct ProjectCard: Hashable, Sendable, Identifiable {
    public let project: Project
    public let customerName: String     // "" nếu customer mất
    public let insights: ProjectInsights
    public let group: CardGroup
    public var id: UUID { project.id }
}

public struct Dashboard: Hashable, Sendable {
    public let totals: CompanyTotals
    public let attention: [AttentionItem]
    public let cards: [ProjectCard]      // terminal không có mặt
}

public enum DashboardComposer {
    public static func compose(_ inputs: DashboardInputs) -> Dashboard
}
```

Quy tắc attention (mỗi project ≠ terminal):

| Item | Điều kiện |
|---|---|
| `.health(status, reason)` | `health.status != .onTrack`; kind = overBudget / paymentRisk / delayed / atRisk theo status |
| `.paymentOverdue` | mỗi `PaymentItemInsight.status == .overdue`, `daysLate = dueDate.daysUntil(today)`. Nếu project đã có `.health(.paymentRisk)` thì vẫn thêm item này (dòng health nói "Payment risk", dòng item nói rõ item nào) |
| `.paymentDueToday` | `status == .dueToday` |
| `.startsToday` | `startDate == today` và phase `preStart` hoặc status `scheduled` |

Quá hạn hoàn thành không có item riêng: phase `inWork` đã được health Delayed phủ; `workDone` cố ý không cảnh báo (Foundation §5.4).

Sắp xếp: `kind` tăng dần, rồi `remaining`/`overBy` giảm dần, rồi tên project. Danh sách đầy đủ, UI tự cắt 5.

Cards: nhóm `inWork` (sắp theo `health.status` giảm dần — nặng trước — rồi `updatedAt` giảm dần), rồi `preStart` (theo `startDate` tăng dần, nil cuối), rồi `workDone` (theo `updatedAt` giảm dần).

Totals: chỉ project có `financials != nil` và currency == company.currency; còn lại đếm `excludedCount`. Tất cả Σ trên `Money.sum` cùng currency công ty.

### 3.3 Đổi status / progress

```swift
public struct StatusChangeOutcome: Hashable, Sendable {
    public let project: Project            // đã đổi status (và updatedAt không đổi — Data stamp)
    public let suggestProgress100: Bool    // true khi to ∈ {completed, awaitingFinalPayment} và manualProgress == nil
    public let requiresConfirmation: Bool  // true khi to ∈ {closed, cancelled}
}
public enum ProjectStatusChange {
    public static func apply(_ project: Project, to status: ProjectStatus) -> StatusChangeOutcome
    public static func setManualProgress(_ project: Project, to value: Int?) throws -> Project  // DomainError.invalidProgress ngoài 0…100
}
```

Không ràng buộc chuyển trạng thái; cùng status → outcome trả project không đổi, Data không ghi activity.

### 3.4 `TimelineValidator` (carry-over)

```swift
public enum TimelineError: Hashable, Sendable { case completionBeforeStart, hoursPerDayOutOfRange, workingDaysNegative, workersPerDayNegative }
public enum TimelineValidator {
    public static func validate(start: CalendarDate?, completion: CalendarDate?, workingDays: Int?, hoursPerDay: Decimal?, workersPerDay: Int?) -> [TimelineError]
}
```

`hoursPerDay` hợp lệ: `0 < h ≤ 24`. `ProjectDraftAssembler` và `ProjectDraft` validation dùng validator này; `DraftError.invalidTimeline` đổi thành `invalidTimeline([TimelineError])` (Equatable giữ nguyên). Wizard step Timeline và edit sheet Timeline hiện lỗi inline theo trường; Tiếp tục / Lưu disabled khi có lỗi.

### 3.5 `ActivityDescription`

```swift
public enum ActivityDetail: Hashable, Sendable {
    case statusChanged(from: ProjectStatus, to: ProjectStatus)
    case progressChanged(from: Int?, to: Int?)
    case contractValueChanged(from: Money, to: Money)
    case estimateChanged(group: CostGroup?, from: Money, to: Money)
    case scheduleChanged(from: Money, to: Money)
    case customerChanged(fromName: String, toName: String)
    case plain(ActivityAction)                 // created/deleted/scope/timeline/customerCreated/expenseAdded/paymentReceived hoặc JSON không đọc được
}
public enum ActivityDescription {
    public static func detail(for entry: ActivityLogEntry) -> ActivityDetail   // parse detailsJSON; lỗi → .plain(action)
}
```

`ActivityAction` thêm case `customerChanged`; `detailsJSON` ghi `{"from":"<name>","to":"<name>","fromId":"…","toId":"…"}`. Cột `activity_log.action` không có CHECK → không cần migration.

### 3.6 Repository protocols (Domain)

```swift
public protocol InsightsRepository: Sendable {
    /// Mọi bảng liên quan của company, chưa xóa; phát lại khi bất kỳ bảng nào đổi. `today` do caller gắn sau.
    func observeDashboard(companyId: UUID) -> AsyncThrowingStream<DashboardInputs.Snapshot, Error>
    /// nil khi project mất hoặc đã xóa.
    func observeProject(id: UUID) -> AsyncThrowingStream<ProjectInsightsInputs.Snapshot?, Error>
}
```

`Snapshot` = cùng struct nhưng không có `today` (`DashboardInputs.Snapshot`, `ProjectInsightsInputs.Snapshot` với `func with(today:)`). Lý do: stream không biết "hôm nay"; VM gắn `today` khi compose và compose lại khi `today` đổi mà không cần phát lại DB.

`ProjectRepository` thêm:

```swift
func changeStatus(id: UUID, to status: ProjectStatus, actor: ActivityActor) async throws          // activity statusChanged {"from","to"}; cùng status → không ghi
func setManualProgress(id: UUID, to value: Int?, actor: ActivityActor) async throws              // activity progressChanged {"from": "65"|null, "to": …}; bằng nhau → không ghi
func changeCustomer(id: UUID, to customerId: UUID, actor: ActivityActor) async throws            // DomainError.notFound / customerDeleted / crossCompany; activity customerChanged
```

Mới:

```swift
public protocol ActivityLogRepository: Sendable {
    func observeForProject(projectId: UUID, limit: Int) -> AsyncThrowingStream<[ActivityLogEntry], Error>   // occurredAt desc
    func list(projectId: UUID) async throws -> [ActivityLogEntry]                                            // toàn bộ, occurredAt desc
}
```

`DomainError` thêm `customerDeleted`, `crossCompany`, `invalidProgress`.

## 4. Data

- Records mới: `ExpenseRecord`, `LabourEntryRecord`, `PaymentRecord`, `EmployeeRecord` — map ↔ entity theo quy ước A.4 (Money TEXT, CalendarDate TEXT, soft delete). `ReceiptImage` của Expense đọc từ cột JSON hiện có (rỗng `[]` trong 2b).
- `GRDBInsightsRepository`: một `ValueObservation.tracking` đọc 7 bảng theo `company_id` (dashboard) hoặc `project_id` (project), `deleted_at IS NULL`; `removeDuplicates()`. Project snapshot nil khi project không còn.
- `GRDBActivityLogRepository`: `ValueObservation` trên `activity_log WHERE project_id = ? ORDER BY occurred_at DESC LIMIT ?`.
- `GRDBProjectRepository.changeStatus/setManualProgress/changeCustomer`: một transaction; đọc project (notFound nếu mất/xóa), kiểm customer (`deleted_at IS NULL`, cùng `company_id`), update + stamp `updated_at`, `ActivityLogRecord.append`.
- Repository ghi cho expenses/payments/labour **không** làm trong 2b.
- `SampleData` (seed `--seed-sample-data`, chỉ DEBUG) đổi sang ngày **tương đối** với `today = CalendarDate(now, .gmt)` và thêm dữ liệu tiền. Số liệu cố định sau đây là hợp đồng cho UI test và screenshot:

| Project | Status | Start / End | Contract | Estimate | Actual (amount+tax) | Payments | Schedule |
|---|---|---|---|---|---|---|---|
| Basement Renovation (Ann Lee) | inProgress, progress 65 | today−18 / today+27 | 38,000 | labour 6,000 · material 7,900 · other 900 = 14,800 | material: Lumber 2,400+312, Drywall 1,500+195 = 4,407 · other: Dumpster 600+78 = 678 · labour entries: Mike 8d×250 = 2,000, John 10d×220 = 2,200, David 7d×200 = 1,400 = 5,600 → totalCost **10,685** | 7,600 gắn deposit (paidOn today−19) | deposit 7,600 due today−20 (paid) · stage2 11,400 due today−5 (**overdue**) · stage3 11,400 due today+10 (upcoming) · final 7,600 no due |
| Kitchen Renovation (David Nguyen) | awaitingDeposit | **today** / today+34 | 25,000 | – | – | – | deposit 5,000 due today+7 |
| Roof Replacement (Maria Santos) | completed, progress 100 | today−63 / today−44 | 18,500 | – | – | 18,500 không gắn item (paidOn today−40) | – |

Employees seed: Mike (dailyRate 250), John (220), David (200), cùng company.

Kết quả kỳ vọng (Domain test dùng cùng số):
- Basement: estimatedCost 14,800; projectedProfit 23,200 (61.1%); spent 10,685; collected 7,600; outstanding 30,400; cashPosition **−3,085**; actualProfit 27,315 (nhãn "Projected at current spending"); budget alerts: labour `nearLimit` 93.3%; payment: 1 overdue; health **Payment Risk** (reasons: paymentOverdue 1, budgetNearLimit labour 93.3%); timeline: elapsed 18, remaining 27, total 45, expected 40%, actual 65%.
- Kitchen: financials toàn 0 trừ outstanding 25,000; health On Track (preStart, awaitingDeposit: payment chưa overdue); attention `startsToday`.
- Roof: collected 18,500, spent 0, cash 18,500, actual profit 18,500 (nhãn "Actual profit"), health On Track (workDone không Delayed).
- Totals: activeJobs 1; outstanding **55,400**; collected **26,100**; spent **10,685**; cashPosition **15,415**; excluded 0.
- Attention (thứ tự): Basement health Payment Risk → Basement stage2 overdue 5 ngày (11,400) → Kitchen starts today.

## 5. Features

### 5.1 Home (`HomeFeature`)

`HomeViewModel`: subscribe `InsightsRepository.observeDashboard`, giữ `snapshot` và `today`; `dashboard = DashboardComposer.compose(snapshot.with(today:))` tính lại khi một trong hai đổi. `today` do `HomeScreen` truyền và cập nhật ở `scenePhase == .active`.

Bố cục (mỗi khối một `Card`):

| # | Khối | Identifier | Nội dung |
|---|---|---|---|
| 1 | Header | – | tên company, `DateLabel(today, .full)` |
| 2 | Cần chú ý | `home_attention` | ≤ 5 `AttentionRow` (icon + màu theo kind: đỏ overBudget/paymentOverdue/paymentRisk, cam delayed/dueToday, xanh dương startsToday, vàng atRisk; tên project; mô tả 1 dòng). > 5 → nút "Xem thêm (N)" (`home_attention_more`) mở sheet danh sách đầy đủ. Trống → `home_attention_empty` "Hôm nay không có gì cần chú ý". Tap → detail |
| 3 | Tổng công ty | `home_totals` | 4 `SummaryTile`: Active jobs (`home_total_active`), Outstanding (`home_total_outstanding`), Collected (`home_total_collected`), Cash position (`home_total_cash`, tone đỏ khi âm). `excludedCount > 0` → chú thích `home.totals.excluded` |
| 4 | Dự án | `home_projects` | `ProjectCardView` nâng cấp theo nhóm: "Đang làm" / "Sắp tới" / "Chờ thanh toán cuối" (`SectionHeader`). Trống hoàn toàn → `EmptyState` + nút tạo (giữ 2a) |

`ProjectCardView` (FeatureSupport) thêm: hàng 3 số Spent · Collected · Cash position (`MoneyText`, cash âm tone đỏ), `HealthChip`, `ProgressBar`. Dùng trong Home và Projects list (list vẫn dùng `observeSummaries` + không có tiền → card nhận `insights: ProjectInsights?`, nil thì ẩn hàng tiền và chip).

Loading: skeleton (redacted) tới lần phát đầu. Lỗi stream: banner `home.error` + nút "Thử lại" (`home_retry`) resubscribe.

### 5.2 Project detail (`ProjectsFeature/Detail`)

`ProjectDetailViewModel` thêm subscribe `InsightsRepository.observeProject` → `insights`; `observeDetail` (2a) giữ cho edit sheets. Section mới/đổi, thứ tự từ trên xuống:

| # | Section | Identifier | Hành vi |
|---|---|---|---|
| 1 | Header (2a) | `detail_header` | thêm `HealthChip` (`detail_health`) và dòng status tap được (`detail_status`) → `StatusPickerSheet` |
| 2 | Tiến độ | `detail_progress` | `ProgressBar` + "%"; tap → `ProgressSheet` |
| 3 | Financial summary | `detail_financials` | Contract · Estimated cost · Projected profit (margin) · **Spent so far** (`detail_spent`, mở rộng → 6 cost group: estimate / actual / `StatusBadge` nearLimit vàng, exceeded đỏ) · Collected (`detail_collected`) · Outstanding · Cash position (`detail_cash`) · dòng cuối theo `profitLabel`: "Projected at current spending" / "Actual profit" + margin. `financials == nil` → mọi số "—" + cảnh báo `detail.financials.currencyMismatch`. Chưa có expense/payment → chú thích `detail.financials.empty` |
| 4 | Health | `detail_health_reasons` | status + danh sách `HealthReason` localized có tham số. Terminal → `health.notEvaluated`. On Track → một dòng xanh |
| 5 | Timeline | `detail_timeline` | Start · Est. completion (`DateLabel`) · "Còn N ngày" / "Trễ N ngày" / "Bắt đầu hôm nay" · `DualProgressBar(expected, actual)` + chú thích. Thiếu ngày → nút "Thêm timeline" (`detail_add_timeline`) mở edit sheet Timeline (2a) |
| 6 | Payment schedule (2a) | `detail_schedule` | mỗi dòng thêm `StatusBadge(payment.status.<raw>)` + "đã trả X / còn Y" khi paid > 0 |
| 7 | Customer (2a) | `detail_customer` | thêm nút "Đổi khách" (`detail_change_customer`) → `CustomerPickerSheet` (tái dùng list + search của `CustomerStep`, không có "+ Khách mới") → `changeCustomer` |
| 8 | Hoạt động | `detail_activity` | 5 dòng mới nhất (`ActivityRow`: icon theo action, mô tả từ `ActivityDetail`, thời gian tương đối theo locale app) + "Xem tất cả" (`detail_activity_all`) → `ActivityListView` (push) |
| 9 | Menu ⋯ | `detail_menu` | Đổi khách · Xóa project (`detail_delete`, destructive) → `confirmationDialog` `detail.delete.title`/`.message` ("Xóa kèm estimate, payment schedule và hoạt động") → `softDelete` → pop |

`StatusPickerSheet` (`status_picker`): 13 status nhóm 4 phase (`SectionHeader` phase), mỗi dòng tên + hint (`status.<raw>.hint`), dòng hiện tại có check; identifier `status_<raw>`. Chọn `closed`/`cancelled` → xác nhận (`status_confirm`). `suggestProgress100` → alert "Đặt tiến độ 100%?" Có (`status_progress_yes`) / Không — Có gọi thêm `setManualProgress(100)`.

`ProgressSheet` (`progress_sheet`): `Stepper` bước 5 + `Slider` 0…100 (`progress_slider`), nhãn %, nút Lưu (`progress_save`), "Xóa tiến độ thủ công" (`progress_clear`, chỉ khi hiện có giá trị).

Lỗi ghi: alert cục bộ trên sheet với key theo `DomainError`: `notFound` → `error.projectGone`, `customerDeleted` → `error.customerDeleted`, `currencyMismatch` → `error.currencyMismatch`, còn lại `error.generic`. `notFound` khi detail đang mở (stream phát nil) → màn "Project không còn tồn tại" + nút quay lại (đã có từ 2a, giữ).

### 5.3 Wizard / edit sheet Timeline (carry-over)

`TimelineStep` và `EditSectionSheet(.timeline)`: chạy `TimelineValidator` trên mỗi thay đổi; lỗi hiện dưới trường liên quan (`timeline.error.<case>`), Tiếp tục / Lưu disabled khi `errors` khác rỗng. Assembler trả `DraftError.invalidTimeline(errors)` → wizard nhảy về step Timeline và hiện lỗi (không còn alert "save failed" chung).

`CustomerStep`: `customer == .existing(id)` không còn trong `customers` → banner `wizard.customer.missing` "Khách không còn tồn tại — chọn lại", `canContinue` false.

### 5.4 Projects list

`ProjectCardView` nâng cấp dùng chung; list không có insights (nil) — hàng tiền/chip ẩn; không đổi gì khác.

## 6. DesignSystem

Mới (không import Domain):
- `DateLabel(_ date: Date, style: DateLabelStyle /* .short "Oct 3, 2026" | .full "Friday, October 3, 2026" */)` — dùng `Locale` từ environment (`\.locale`, đã được app set theo ngôn ngữ in-app); `Text(date, format:)` không dùng vì không nhận locale override → dùng `DateFormatter` cache theo locale.
- `HealthChip(_ title: LocalizedStringKey, tone: DSTone)` — alias semantic của `StatusBadge` với kích thước nhỏ hơn.
- `DualProgressBar(expected: Int, actual: Int)` — hai thanh chồng, chú giải.
- `ActivityRow(icon: String, title: Text, subtitle: Text)`.
- `DSTone` thêm `.info` (xanh dương) nếu chưa có; `.warning` vàng, `.danger` đỏ, `.caution` cam.
- `SkeletonCard` (redacted placeholder) cho Home loading.

## 7. Localization

Thêm vào `App/Resources/Localizable.xcstrings` (en nguồn + vi; thuật ngữ nghề giữ tiếng Anh: Deposit, Cash position giữ "Dòng tiền hiện tại" theo quyết định Foundation):

- `home.*`: `home.attention.title`, `home.attention.empty`, `home.attention.more` (%lld), `home.totals.title`, `home.totals.active`, `home.totals.outstanding`, `home.totals.collected`, `home.totals.cash`, `home.totals.excluded` (%lld), `home.group.inWork/preStart/workDone`, `home.retry`, `home.error` (có).
- `attention.*`: `attention.paymentOverdue` ("%@ overdue %lld days — %@" label/days/money), `attention.paymentDueToday`, `attention.startsToday`.
- `health.status.onTrack/atRisk/delayed/paymentRisk/overBudget`, `health.notEvaluated`, `health.reason.budgetExceeded` (group, money), `health.reason.paymentOverdue` (%lld), `health.reason.pastCompletionDate` (%lld), `health.reason.budgetNearLimit` (group, %@ percent hoặc "—"), `health.reason.deadlineApproaching` (%lld days, %lld %).
- `status.<raw>` (có) + `status.<raw>.hint` ×13; `status.phase.preStart/inWork/workDone/terminal`; `status.confirm.title/message`; `status.suggestProgress.title/yes/no`.
- `progress.title`, `progress.save`, `progress.clear`, `progress.manual`.
- `detail.financials.*`: `title`, `contract`, `estimatedCost`, `projectedProfit`, `spent`, `collected`, `outstanding`, `cash`, `projectedAtCurrent`, `actualProfit`, `currencyMismatch`, `empty`, `byGroup`; `costGroup.<raw>` (có).
- `detail.timeline.*`: `title`, `start`, `completion`, `daysLeft` (%lld), `daysLate` (%lld), `startsToday`, `expected`, `actual`, `add`.
- `detail.schedule.paid` ("Paid %@ · %@ left"), `payment.status.<raw>` (có).
- `detail.customer.change`, `customer.picker.title`.
- `detail.activity.title`, `detail.activity.all`, `activity.<action>` ×13 (có tham số cho status/progress/contract/estimate/schedule/customer), `activity.empty`.
- `detail.delete.title/message/confirm`, `detail.menu`.
- `timeline.error.completionBeforeStart/hoursPerDayOutOfRange/workingDaysNegative/workersPerDayNegative`, `wizard.customer.missing`.
- `error.projectGone`, `error.customerDeleted`, `error.currencyMismatch`, `error.generic`.

`scripts/check_localization.py` mở rộng: sinh key từ `ProjectStatus` (`status.<raw>.hint`), `ActivityAction` (`activity.<raw>`), `HealthStatus` (`health.status.<name>`), `HealthReason` (`health.reason.<name>`), `TimelineError` (`timeline.error.<name>`), `PaymentStatus` (có) và báo thiếu.

## 8. App

- `AppContainer.Ready` thêm `insightsRepository`, `activityLogRepository`.
- `HomeScreen`, `ProjectDetailScreen` truyền `today` (`CalendarDate(Date(), timeZone: .current)`) và cập nhật qua `scenePhase`.
- Launch arg mới cho UI test: `--today YYYY-MM-DD` (chỉ `--ui-testing`): App dùng ngày này thay `Date()` cho `today` **và** seed dùng cùng ngày làm mốc — để UI test/screenshot xác định. Không truyền → ngày thật.
- `ProjectRoute` thêm `.activity(projectId)`.

## 9. Lỗi và biên

- Stream lỗi (DB hỏng): Home banner + Thử lại; Detail giữ hành vi 2a.
- Currency project ≠ company (chỉ xảy ra qua dữ liệu lỗi): Home loại khỏi tổng + chú thích; detail "—" + cảnh báo; không chặn thao tác khác.
- Project bị xóa khi đang mở detail: stream nil → màn "không còn tồn tại".
- `today` qua nửa đêm khi app mở: không tự tính lại cho tới `scenePhase.active` kế tiếp (chấp nhận).
- Hiệu năng: compose trên MainActor; dữ liệu seed < 1 ms. Rủi ro ghi nhận: > 200 project có thể cần `Task.detached` — không build trước.

## 10. Testing

Domain (Linux, XCTest):
- `ProjectInsightsComposerTests`: số liệu Basement/Kitchen/Roof ở §4 ra đúng từng trường; ví dụ Foundation ($30,000 / 6,000 / 7,500 / 1,000 → 14,500, 51.7%, outstanding 10,000); currency mismatch → `financials nil`, health vẫn có reason ngày; payment trỏ item đã xóa → unallocated; `TimelineInsight` biên (start = completion → total 0, expected 100 khi today ≥ completion; today < start → elapsed 0, expected 0; thiếu ngày → nil).
- `DashboardComposerTests`: totals §4; excludedCount; terminal ẩn khỏi cards và totals; thứ tự attention (overBudget trước paymentOverdue trước dueToday trước startsToday trước atRisk); card ordering 3 nhóm; project inWork quá hạn chỉ sinh một item (health Delayed).
- `ProjectStatusChangeTests`: suggestProgress100 đúng 2 status và chỉ khi nil; requiresConfirmation 2 status; setManualProgress 0/100 ok, −1/101 throw, nil ok.
- `TimelineValidatorTests`: từng lỗi, kết hợp, hợp lệ rỗng; `hoursPerDay` 0 và 24.5 lỗi, 24 ok.
- `ActivityDescriptionTests`: parse 6 loại detail + JSON hỏng → `.plain`.

Data (macOS CI):
- `observeDashboard` phát lại khi insert payment / soft-delete expense; snapshot loại record đã xóa.
- `changeStatus` ghi activity, cùng status không ghi; `setManualProgress` from/to JSON (nil → `null`); `changeCustomer` từ chối customer khác company / đã xóa, ghi activity với tên.
- `GRDBActivityLogRepository.observeForProject` limit + thứ tự.
- Records round-trip Expense (amount+tax), LabourEntry (days Decimal), Payment, Employee.
- Seed khớp §4 (query tổng).

UI tests (`UITests/DashboardFlowTests.swift`, launch `--ui-testing --seed-sample-data --locale en --today 2026-10-03`):
- (a) Home: `home_attention` chứa "Payment risk" và "overdue 5 days"; `home_total_outstanding` chứa "55,400.00"; `home_total_cash` chứa "15,415.00".
- (b) Detail Basement: `detail_cash` chứa "-3,085.00" (hoặc "−3,085.00" theo formatter — assert bằng cả hai), `detail_health` "Payment risk"; `detail_timeline` chứa "27 days left".
- (c) Đổi status Kitchen → In progress qua `status_picker`/`status_inProgress`; header hiện "In progress"; `detail_activity` có dòng "Awaiting deposit → In progress"; Home totals `home_total_active` = 2.
- (d) Progress: Kitchen `detail_progress` → `progress_slider` tới 60 → `progress_save`; bar "60%"; activity "— → 60%".
- (e) Xóa Roof: `detail_menu` → `detail_delete` → confirm → về list, "Roof Replacement" không còn; Home collected = 7,600.00.
- (f) Đổi khách Kitchen → Maria Santos; header hiện tên mới; activity "David Nguyen → Maria Santos".
- (g) Wizard Timeline: completion < start → `timeline_error_completionBeforeStart` hiện, `wizard_continue` disabled; sửa lại → enabled.
- (h) vi locale (`--locale vi`, `-AppleLocale vi_VN`): Home header chứa "3 tháng 10" (DateLabel), `detail_timeline` "Còn 27 ngày".
- Screenshots: `home_<locale>_<appearance>` (en/vi × light/dark), `detail_full_<locale>`, `status_picker_<locale>`, `activity_<locale>`.

## 11. Tiêu chí hoàn thành

- Domain/Data/UI tests trên xanh; `check_localization.py` 0 lỗi (kể cả key sinh mới); `lint_sources.py` 0 lỗi.
- Trên seed, Home trả lời 4 câu trong 10 giây: cần chú ý gì (Basement Payment risk, Kitchen starts today), đã chi (10,685), còn thu (55,400), lời/vượt (Basement nearLimit labour, Projected 27,315).
- TestFlight build mới từ `main`.

## 12. Ngoài phạm vi 2b

Nhập expense / payment / labour (3); tasks, daily logs, calendar, notifications (4); drag-reorder schedule; `categoryInUse`; Percentage Codable; undo xóa; màn hoạt động toàn công ty; sửa activity; đổi currency; tasks-based progress.
