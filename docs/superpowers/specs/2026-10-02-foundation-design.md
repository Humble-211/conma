# Construction Management — Sub-project 1: Foundation

Ngày: 2026-10-02
Trạng thái: chờ review

## 1. Bối cảnh và mục tiêu

Construction Management là iOS app cho contractor và đội thi công nhỏ/vừa ở Bắc Mỹ. Nguyên tắc sản phẩm: đây là "Contractor Operating System", không phải accounting app. Mở app, trong 10 giây contractor phải trả lời được: đang làm job nào, job nào cần chú ý, crew ở đâu, đã chi bao nhiêu, còn phải thu bao nhiêu, job lời hay vượt budget, việc tiếp theo là gì.

Toàn bộ MVP (Phase 1 trong yêu cầu gốc) được chia thành 5 sub-project, mỗi cái có spec, plan và implementation riêng:

| # | Sub-project | Nội dung |
|---|---|---|
| 1 | **Foundation** (tài liệu này) | Repo, pipeline, Domain, schema local, DesignSystem, localization, app shell |
| 2 | Projects core | Home dashboard, project list, wizard 12 bước, project detail, customers |
| 3 | Money | Expenses, chụp receipt (chưa OCR), labour simple mode, payment schedule, profit, budget alerts |
| 4 | Field ops | Tasks + progress, daily logs, photos, calendar cơ bản, local notifications, quick actions |
| 5 | Cloud | Supabase Auth, Postgres schema + Row Level Security, sync engine, upload ảnh |

Ngoài MVP: estimates/quotes, invoices, change orders, clock in/out, subcontractors, vendors, analytics, cash flow, OCR, role system, client portal. Schema chừa chỗ nhưng không build.

Mục tiêu của sub-project 1: có một app trống cài được lên iPhone qua TestFlight, pipeline xanh, và toàn bộ business logic tài chính đã có test. Sub-project sau chỉ việc thêm màn hình lên nền này.

## 2. Quyết định đã chốt

| Chủ đề | Quyết định |
|---|---|
| Môi trường dev | Máy Windows, không có Mac. Build và test iOS trên GitHub Actions macOS runner. |
| Thiết bị thật | Có Apple Developer Program + iPhone. CI ký app và đẩy TestFlight. |
| Repo | GitHub, **public**. |
| Người dùng MVP | Chỉ Owner, một tài khoản một company. Workers là record, không login. Schema multi-tenant sẵn (`company_id`). |
| Dữ liệu | Local-first: SQLite trên máy là nguồn chính. Supabase sync đến ở sub-project 5, sau cùng repository protocol. |
| Tiền | Swift `Decimal`; Postgres `NUMERIC(14,2)`; SQLite lưu TEXT. Không dùng `Double`. Làm tròn half-up 2 chữ số tại một chỗ trong Domain. |
| Thị trường | Canada + US. Company chọn một currency (CAD hoặc USD) lúc setup, không quy đổi. Tax nhập tay một ô theo từng expense. |
| Ngôn ngữ | English (mặc định, source) + Tiếng Việt. Theo system language, đổi được trong Settings. Thuật ngữ nghề giữ tiếng Anh trong bản Việt. |
| Kiến trúc | Swift Packages theo module + MVVM (`@Observable`), Repository pattern, async/await. |
| Local DB | GRDB (SQLite), không dùng SwiftData. |
| Nền tảng | iOS 17+, iPhone-first. |
| Project file | XcodeGen (`project.yml`), `.xcodeproj` sinh trên CI, không commit. |
| Nhãn "Profit so far" | Đổi thành **"Cash position"** / "Dòng tiền hiện tại" để không gây hiểu nhầm là lợi nhuận đã chốt. |

## 3. Cấu trúc repo

```
Construction/
  project.yml
  App/
    ConstructionApp.swift          # composition root
    RootTabView.swift              # Home, Projects, Calendar, Expenses, More
    Resources/Localizable.xcstrings
    Resources/Assets.xcassets
  Packages/
    Domain/
      Sources/Domain/{Entities,Money,Finance,Progress,Payments,Health,Repositories}
      Tests/DomainTests/
    Data/
      Sources/Data/{Database,Migrations,Records,Repositories}
      Tests/DataTests/
    DesignSystem/
      Sources/DesignSystem/{Tokens,Components}
    Features/
      Sources/{Home,Projects,Calendar,Expenses,More}
  fastlane/
  scripts/                         # kiểm tra localization, lint tiền
  .github/workflows/{domain.yml,ios.yml,testflight.yml}
  docs/superpowers/specs/
```

Quy tắc phụ thuộc:

- `Domain` chỉ import Foundation. Không SwiftUI, UIKit, GRDB.
- `Data` phụ thuộc `Domain` + GRDB.
- `DesignSystem` chỉ SwiftUI, không phụ thuộc `Domain`.
- `Features` phụ thuộc `Domain` + `DesignSystem`. ViewModel nhận repository protocol, không thấy GRDB.
- Chỉ `App` biết `Data`: tạo repository cụ thể rồi inject.

## 4. Pipeline

**`domain.yml`** — mọi push, runner Ubuntu. Chạy `swift test` cho `Packages/Domain`. Feedback 1–2 phút cho business logic. Chạy được cả trên Windows nếu cài Swift toolchain (tùy chọn).

**`ios.yml`** — mọi push, runner macOS. Các bước: cài XcodeGen, sinh project, build, chạy `DataTests` + UI smoke test trên simulator, chạy script kiểm tra localization và lint tiền, lưu screenshot (từng tab + Component Gallery, light/dark × en/vi) thành artifact.

**`testflight.yml`** — chạy tay (`workflow_dispatch`) hoặc khi push tag `v*`. Ký bằng fastlane match, upload bằng App Store Connect API key, build number lấy từ số lần chạy workflow.

Bảo mật (repo public):

- Chứng chỉ ký nằm ở một repo **private riêng** (fastlane match, mã hóa). Không bao giờ trong repo này.
- App Store Connect API key, mật khẩu match, và sau này mọi khóa Supabase chỉ nằm trong GitHub Secrets.
- Workflow dùng secrets không chạy cho pull request từ fork.
- Supabase `service_role` key không bao giờ vào app hay repo.

Người dùng cần chuẩn bị (plan sẽ hướng dẫn từng bước): repo GitHub public, repo private cho match, bundle id, app record trên App Store Connect, App Store Connect API key.

## 5. Domain

### 5.1 Kiểu nền

`Money`: bọc `Decimal` + `currencyCode` (`CAD` | `USD`). Phép tính giữa hai currency khác nhau ném `DomainError.currencyMismatch`.

Quy tắc làm tròn (một hàm duy nhất `Money.rounded`, mọi nơi khác gọi nó):

- Bất biến: giá trị bên trong `Money` luôn có đúng 2 chữ số thập phân. Không tồn tại `Money` chưa làm tròn.
- Làm tròn xảy ra tại: (a) khởi tạo `Money` từ `Decimal` bất kỳ (input người dùng, đọc DB), (b) kết quả của mọi phép nhân hoặc chia (`Money × Decimal`, `Money × Percentage`). Cộng và trừ hai `Money` là chính xác, không cần làm tròn.
- Kiểu làm tròn: half-up theo trị tuyệt đối (half away from zero). `0.005 → 0.01`, `0.004 → 0.00`, `2.675 → 2.68`, `-0.005 → -0.01`.
- Tổng luôn là tổng của các giá trị đã làm tròn (cộng các dòng 2 chữ số), không bao giờ làm tròn sau khi cộng số thô. Nhờ vậy tổng trên màn hình khớp với cộng tay từng dòng.
- `Money` âm chỉ hợp lệ cho kết quả tính (`cashPosition`, profit, chênh lệch). Input người dùng âm bị từ chối.

`Percentage`: bọc `Decimal` theo **điểm phần trăm**: `Percentage(10)` nghĩa là 10%, không phải 10 lần. Thuộc tính `fraction` = value / 100. `Money × Percentage` = `rounded(amount × fraction)`. Percentage do người dùng nhập (deposit, payment schedule) phải trong `0...100`, tối đa 2 chữ số thập phân; ngoài khoảng ném `DomainError.invalidPercentage`. Percentage là kết quả tính (margin, budget used) không bị giới hạn khoảng, làm tròn half-up về 1 chữ số thập phân khi tạo.

Chia contract theo phần trăm (payment schedule): mỗi dòng = `rounded(contract × fraction)`; nếu tổng phần trăm = 100 thì dòng cuối nhận phần dư (`contract − tổng các dòng trước`) để tổng schedule khớp contract từng cent. Sau khi tạo, `PaymentScheduleItem.amount` là giá trị thanh toán **có thẩm quyền**; `percentage` chỉ là nguồn sinh dòng và để hiển thị, có thể lệch `amount` vài cent ở dòng nhận phần dư. Mọi tính toán dùng `amount`.

`CalendarDate`: ngày lịch không kèm giờ (`YYYY-MM-DD`), dùng cho due date, start date, completion date. Mốc thời gian thực (createdAt, timestamp ảnh) dùng `Date` UTC. `daysUntil(other)` trả số ngày lịch nguyên, âm nếu đã qua.

Trường chung: mọi entity có `id: UUID`, `createdAt`, `updatedAt`, `deletedAt?` (soft delete). Mọi entity **trừ `Company`** có thêm `companyId`. `Company` là root aggregate, không có `companyId`.

### 5.2 Entities MVP

Project là entity trung tâm.

Danh sách dưới đây nêu ý nghĩa. Trường, nullability, khóa ngoại, index và hành vi xóa được khóa trong **Phụ lục A**; Phụ lục A là contract duy nhất cho migration và cho schema Postgres sau này.

- `Company` (name, currencyCode): root aggregate.
- `User` (displayName, email?, role, authUserId?): setup lần đầu tạo đúng một `User` với `role = owner`, `displayName` lấy từ màn hình setup, `authUserId = nil`. Sub-project 5 gắn `authUserId` khi có login. `User` là actor trong `ActivityLog`.
- `Customer`
- `Project`: scope gồm mô tả tự do + các `ProjectScopeField` (key-value theo jobType).
- `ProjectEstimateLine`: một dòng dự toán, thuộc đúng một `CostGroup`.
- `ProjectTask` + `TaskChecklistItem` + `TaskAssignee`; `ProjectWorker` (gán employee vào project theo ngày)
- `Employee` (chỉ là record, không login)
- `PaymentScheduleItem` và `Payment`
- `Expense` + `ReceiptImage` (một receipt = các ảnh có thứ tự của một expense; receipt dài thì nhiều ảnh); `CustomExpenseCategory`
- `LabourEntry` simple mode
- `DailyLog`, `Photo`
- `ActivityLog`, `AppNotification`

Enums (lưu bằng raw value dạng chuỗi camelCase, không đổi sau khi phát hành):

- `ProjectStatus` (13): estimate, awaitingApproval, awaitingDeposit, scheduled, inProgress, onHold, waitingForInspection, waitingForMaterial, waitingForClient, completed, awaitingFinalPayment, closed, cancelled.
- Nhóm status (thuộc tính `phase` của `ProjectStatus`, dùng cho mọi rule):
  - `preStart`: estimate, awaitingApproval, awaitingDeposit
  - `inWork`: scheduled, inProgress, onHold, waitingForInspection, waitingForMaterial, waitingForClient
  - `workDone`: completed, awaitingFinalPayment
  - `terminal`: closed, cancelled
- `TaskStatus` (6): notStarted, scheduled, inProgress, blocked, waiting, completed.
- `PaymentMethod` (6): cash, cheque, eTransfer, creditCard, bankTransfer, other.
- `PhotoCategory` (6): before, progress, issues, inspection, completed, receipts.
- `JobType` (20): generalRenovation, basementRenovation, kitchen, bathroom, landscaping, roofing, plumbing, electrical, hvac, flooring, painting, drywall, concrete, deckFence, framing, windowsDoors, exterior, demolition, commercial, other. `other` bắt buộc kèm `customJobType`.
- Scope-field catalog (danh sách `field_key` theo từng `JobType`, ví dụ `squareFootage`, `roofType`, `fenceLength`) thuộc sub-project 2 (wizard). Ở Foundation, `field_key` là chuỗi không ràng buộc, chỉ cần khác rỗng; Domain không biết catalog.
- `CostGroup` (6): material, labour, subcontractor, equipment, permit, other. Đây là taxonomy chi phí **duy nhất**, dùng chung cho estimate, actual cost và budget alert.
- Mỗi `Expense` mang `costGroup` riêng (snapshot lúc tạo, lưu cột `cost_group`): category mặc định thì bằng giá trị trong bảng dưới (Domain từ chối nếu lệch); category custom thì chép từ `CustomExpenseCategory.costGroup` tại thời điểm tạo. `FinancialCalculator` chỉ đọc `expense.costGroup`, không cần biết bảng category.
- `CustomExpenseCategory.costGroup` bất biến sau khi đã có expense (kể cả expense đã soft-delete) dùng category đó; đổi group khi đã dùng ném `DomainError.categoryInUse`. Chi phí lịch sử vì thế không bao giờ đổi nhóm.
- `ExpenseCategory` (13 mặc định + custom). Mỗi category thuộc đúng một `CostGroup`:

| ExpenseCategory | CostGroup |
|---|---|
| materials | material |
| labour | labour |
| subcontractor | subcontractor |
| equipmentRental, toolPurchase | equipment |
| permit, inspection | permit |
| delivery, fuel, wasteDisposal, parking, office, other | other |
| custom | do người dùng chọn khi tạo category; mặc định other |

Các mục "Other Costs" của wizard (bước 8) tạo `ProjectEstimateLine` theo mapping: Subcontractors → subcontractor; Equipment rental, Tool rental → equipment; Permits, Inspection fees → permit; Dumpster, Delivery, Parking, Gas, Waste disposal, Other → other. Bước 6 tạo dòng `labour`, bước 7 tạo dòng `material`.

Chưa build: Estimate/Quote, Invoice, ChangeOrder, Vendor, Subcontractor, TimeEntry.

### 5.3 Financial engine

`FinancialCalculator` là hàm thuần: nhận project, estimate, expenses, labour entries, payments, `approvedChangeOrders` (hiện luôn bằng 0), trả `ProjectFinancials`.

| Giá trị | Công thức |
|---|---|
| `adjustedContract` | contractValue + approvedChangeOrders |
| `actualByGroup[g]` | với mỗi `CostGroup` g: tổng (`amount + tax`) của các Expense có `costGroup = g`; riêng `labour` cộng thêm tổng `LabourEntry` |
| `estimateByGroup[g]` | tổng `amount` các `ProjectEstimateLine` thuộc g; g không có dòng nào thì `nil` (khác với có dòng mà tổng = 0) |
| `totalCost` | tổng `actualByGroup` của cả 6 nhóm |
| `estimatedCost` | tổng mọi `ProjectEstimateLine` |
| `projectedProfit` | adjustedContract − estimatedCost |
| `spentSoFar` | bằng `totalCost` (tên dùng khi hiển thị cho project chưa xong) |
| `collected` | tổng mọi `Payment` của project, kể cả payment không gắn schedule item |
| `outstandingBalance` | adjustedContract − collected |
| `cashPosition` | collected − spentSoFar |
| `actualProfit` | adjustedContract − totalCost |
| `margin` | `Percentage`(profit / adjustedContract × 100), 1 chữ số thập phân; adjustedContract = 0 thì `nil` |

Quy ước chi phí:

- Chi phí một Expense = `amount + tax` (số tiền contractor thực trả). `amount` là số trước tax. App không tách tax được hoàn.
- Chi phí một `LabourEntry` = `rounded(days × dailyRate)`. `dailyRate` chụp lại tại thời điểm nhập, đổi rate của employee sau này không đổi entry cũ.
- Record đã soft-delete không tham gia bất kỳ phép tính nào.
- Mọi phép tính đi trên `Money` đã làm tròn theo mục 5.1; `ProjectFinancials` không làm tròn thêm lần nào, trừ `margin`.

Quy tắc hiển thị (theo yêu cầu gốc mục 42):

- `cashPosition` mang nhãn "Cash position", không gọi là profit.
- `actualProfit` chỉ mang nhãn "Actual profit" khi project ở phase `workDone` hoặc status `closed`. Trước đó nhãn là "Projected at current spending".
- `margin = nil` hiển thị "—".

Ví dụ kiểm chứng từ yêu cầu gốc: contract $30,000; material $6,000; labour $7,500; other $1,000 → totalCost $14,500, profit $15,500, margin 51.7%. Deposit $5,000 + payments $15,000 → outstanding $10,000.

### 5.4 Rule khác

`today`/`now` luôn được truyền vào, không gọi `Date()` trong Domain.

**`ProgressCalculator`**: phần trăm = task `completed` / tổng task, làm tròn half-up về số nguyên `0...100`. Không có task thì 0. `manualProgress` nếu có thì thắng.

**Payment allocation**

- `paidForItem` = tổng `Payment` có `scheduleItemId` trỏ tới item đó.
- Payment không gắn schedule item (`scheduleItemId = nil`) tính vào `collected` của project, **không** tính vào `paidForItem` của item nào.
- Không tự động phân bổ payment dư sang item khác.

**`PaymentStatusResolver`**: nhận schedule item, `paidForItem`, `today`. Xét theo thứ tự, điều kiện đầu tiên đúng thì trả về:

| Thứ tự | Điều kiện | Kết quả |
|---|---|---|
| 1 | `paidForItem >= amount` | `paid` |
| 2 | có dueDate và `today > dueDate` | `overdue` (kể cả khi đã trả một phần) |
| 3 | `paidForItem > 0` | `partiallyPaid` |
| 4 | có dueDate và `today == dueDate` | `dueToday` |
| 5 | có dueDate và còn `1...3` ngày | `dueSoon` |
| 6 | còn lại (còn ≥ 4 ngày, hoặc không có dueDate) | `upcoming` |

Item không có dueDate chỉ có thể là `paid`, `partiallyPaid` hoặc `upcoming`. Item có `amount = 0` luôn là `paid`.

**`BudgetAlertRule`**: xét từng `CostGroup` g với `estimate = estimateByGroup[g]`, `actual = actualByGroup[g]`:

| Trường hợp | Kết quả |
|---|---|
| `estimate = nil` (nhóm không có dòng estimate) | không alert |
| `actual = 0` | không alert |
| `estimate = 0` và `actual > 0` | `exceeded`, vượt = actual, phần trăm đã dùng = `nil` |
| `actual > estimate` | `exceeded`, vượt = actual − estimate |
| `actual × 100 >= estimate × 90` và `actual <= estimate` | `nearLimit` |
| còn lại | không alert |

So sánh bằng phép nhân trên `Decimal`, không so phần trăm đã làm tròn. Đúng 100% là `nearLimit`, chưa `exceeded`.

**`ProjectHealthEvaluator`**: rule-based, trả trạng thái + danh sách lý do. Phạm vi theo phase:

| Tín hiệu | Điều kiện | Xét ở phase |
|---|---|---|
| Over Budget | có nhóm `exceeded` | `inWork`, `workDone` |
| Payment Risk | có schedule item `overdue` | mọi phase trừ `terminal`; trong `preStart` chỉ xét ở status `awaitingDeposit` |
| Delayed | `today > estimatedCompletionDate` | chỉ `inWork` |
| At Risk | có nhóm `nearLimit` | `inWork`, `workDone` |
| At Risk | còn `0...7` ngày tới estimatedCompletionDate và progress < 80% | chỉ `inWork` |

- Project `workDone` (completed, awaitingFinalPayment) không bao giờ Delayed, dù completion date đã qua: việc đã xong, chỉ còn chờ tiền.
- Project đã trễ (số ngày còn lại âm) nhận Delayed, không nhận thêm lý do "sắp đến hạn".
- Không có estimatedCompletionDate thì bỏ qua hai rule về ngày.
- Phase `terminal` (closed, cancelled): không đánh giá, health = `nil`.
- Không tín hiệu nào: On Track.
- Nhiều tín hiệu: trạng thái là mức nặng nhất theo thứ tự Over Budget, Payment Risk, Delayed, At Risk; danh sách lý do giữ đủ mọi tín hiệu, sắp theo cùng thứ tự.

### 5.5 Validation

Domain từ chối: số tiền input âm, `Payment.amount <= 0`, percentage input ngoài `0...100`, `manualProgress` ngoài `0...100`, `LabourEntry.days <= 0`, estimatedCompletionDate trước startDate, trộn currency. Tổng payment schedule khác contract value là cảnh báo, không chặn. Payment vượt số còn lại của schedule item được chấp nhận (item thành `paid`).

### 5.6 Repository protocols

Mỗi aggregate một protocol trong Domain (`ProjectRepository`, `CustomerRepository`, `CompanyRepository`, …) với các hàm async `get`, `list`, `save`, `delete` và `observe…` trả `AsyncSequence` để UI tự cập nhật.

## 6. Data layer

- Một file SQLite trong Application Support. Ảnh và receipt lưu thành file trong thư mục app; DB giữ đường dẫn tương đối.
- Migration đánh số, SQL tường minh. Tên bảng và cột snake_case, trùng với schema Postgres của sub-project 5.
- Migration đầu tạo đủ bảng theo **Phụ lục A**, đúng từng cột, ràng buộc và index. Lệch khỏi Phụ lục A là lỗi; cần đổi thì sửa spec trước.
- `Decimal` lưu TEXT (`"246.50"`). `Date` lưu ISO-8601 UTC. `CalendarDate` lưu `YYYY-MM-DD`.
- Mỗi bảng có `updated_at`, `deleted_at`, `sync_state` (`pending` | `synced`). Sub-project 1 chưa dùng `sync_state`.
- Xóa luôn là soft delete (đặt `deleted_at`); app không bao giờ xóa vật lý, vì sync cần tombstone. Mọi truy vấn mặc định lọc `deleted_at IS NULL`.
- GRDB record tách khỏi Domain entity, có mapper hai chiều.
- Thay đổi dữ liệu tiền hoặc progress ghi kèm một dòng `activity_log` trong cùng transaction.
- Sub-project 1 hiện thực repository cho `Company`, `Project`, `Customer`. Phần còn lại làm ở sub-project dùng tới.
- Seed dữ liệu mẫu chỉ trong debug build (3 project ở các trạng thái khác nhau) để screenshot có nội dung.

## 7. DesignSystem

Tokens:

- Màu semantic trong asset catalog, có light + dark: background, surface, textPrimary, textSecondary, accent, success, warning, danger, border. Một accent cam an toàn dịu; còn lại trung tính.
- Spacing: 4, 8, 12, 16, 24. Bo góc: 12 (card), 16 (sheet).
- Typography theo Dynamic Type. Số tiền dùng monospaced digits.

Components: `PrimaryButton` (cao tối thiểu 56pt), `SecondaryButton`, `Card`, `StatusBadge`, `ProgressBar`, `MoneyText`, `SummaryTile`, `SectionHeader`, `EmptyState`, `FormRow`, `FloatingActionButton`.

Quy tắc:

- Vùng chạm tối thiểu 44pt. Hành động chính ở nửa dưới màn hình.
- Tương phản đạt WCAG AA.
- Component không import Domain. `StatusBadge` nhận style trung tính (tone + text); Features map `ProjectStatus` sang style.
- Mỗi component có SwiftUI Preview và xuất hiện trong Component Gallery (debug build).
- Animation nhẹ, tôn trọng Reduce Motion.

## 8. Localization

- `Localizable.xcstrings`: English là source, Tiếng Việt dịch 100%. Script CI fail khi có key thiếu bản vi.
- Không có chuỗi hiển thị hard-code trong View.
- Enum của Domain chỉ là giá trị; Features map sang localization key.
- Nội dung user tự nhập (custom category, tên task) giữ nguyên văn.
- Tiền, ngày, số format bằng `FormatStyle` theo locale đang chọn và `currencyCode` của company.
- Chọn ngôn ngữ: mặc định theo system (vi thì Tiếng Việt, còn lại English). Settings cho chọn System / English / Tiếng Việt; lưu `UserDefaults`, áp `Locale` qua environment ở root, đổi ngay.

Thuật ngữ nghề giữ tiếng Anh trong bản Việt:

| Giữ tiếng Anh | Dịch |
|---|---|
| deposit, estimate, change order, invoice, receipt | Project → Dự án; Customer → Khách hàng |
| drywall, framing, roofing, flooring, plumbing, HVAC, deck, demolition | Expenses → Chi phí; Payment → Thanh toán |
| contractor, subcontractor, crew | Progress → Tiến độ; Calendar → Lịch |
| labour, material (trong ngữ cảnh chi phí) | Overdue → Quá hạn; Completed → Hoàn thành |
| e-transfer, cheque | Cash position → Dòng tiền hiện tại; Settings → Cài đặt |

Tên tab bản Việt: Trang chủ, Dự án, Lịch, Chi phí, Thêm.

## 9. App shell

- `ConstructionApp`: mở DB, chạy migration, tạo repositories, inject qua environment.
- Lần chạy đầu: màn hình setup ngắn (tên company, currency, ngôn ngữ), tạo `Company` + `User` local. Chưa có login.
- `RootTabView`: 5 tab, mỗi tab một `NavigationStack`.
  - Home: danh sách project từ repository dạng card tối giản (tên, địa chỉ, `StatusBadge`, `ProgressBar`, contract value). Chứng minh đường Domain → Data → ViewModel → View chạy thông. Dashboard thật ở sub-project 2.
  - Projects, Calendar, Expenses: `EmptyState` đã localize.
  - More: Settings (ngôn ngữ, giao diện sáng/tối/theo máy, thông tin company) và Component Gallery (debug).

## 10. Xử lý lỗi

- Không mở được DB hoặc migration lỗi: màn hình lỗi, không crash, không tự xóa dữ liệu. Có nút thử lại và xuất file DB.
- Lỗi ghi: transaction rollback; ViewModel nhận `DomainError` có kiểu; UI hiện thông báo đã localize; dữ liệu đang nhập giữ nguyên.
- Không dùng `try!`, `fatalError`, force-unwrap trong code production.

## 11. Testing

- `DomainTests` (viết theo TDD):
  - Làm tròn: `0.005`, `0.004`, `2.675`, `-0.005`; `Money` khởi tạo từ số 3 chữ số thập phân; tổng các dòng đã làm tròn.
  - `Percentage`: `Percentage(10)` của $30,000 = $3,000; 20% của $30,000 = $6,000; input `-1`, `100.01` bị từ chối; chia 33.33/33.33/33.34 của $100.00 và 3 × 33.33% (tổng khác 100, không có dòng nhận phần dư); schedule 20/30/30/20 của $30,000.01 khớp từng cent.
  - Financial engine với số từ yêu cầu gốc; expense có tax; margin khi contract = 0; trộn currency; record soft-delete bị bỏ qua; mapping từng `ExpenseCategory` mặc định sang `CostGroup`; expense custom lấy `costGroup` snapshot (đổi category sau đó không đổi chi phí lịch sử); tạo expense mặc định với `costGroup` lệch mapping bị từ chối; đổi `costGroup` của category đã dùng ném `categoryInUse`.
  - Payment status: từng dòng bảng mục 5.4, biên `today` = dueDate − 4, − 3, − 1, 0, + 1; trả một phần rồi quá hạn; không dueDate; payment không gắn item vào `collected` nhưng không vào `paidForItem`; trả dư.
  - Progress có và không có override; không task.
  - Budget alert ở 89%, 90%, 100%, 101%; estimate `nil`; estimate $0 với actual $0 và > $0.
  - Health: từng phase; `awaitingFinalPayment` quá completion date không Delayed; còn 0, 7, 8, −1 ngày; thứ tự ưu tiên và danh sách lý do; `terminal` trả `nil`.
- `DataTests`: migration từ DB trống tạo đúng bảng, cột, index của Phụ lục A; round-trip record (đặc biệt `Decimal`, `CalendarDate`); soft delete và cascade soft delete của project (gồm notifications); unique index bỏ qua dòng đã xóa; vi phạm khóa ngoại bị từ chối; record company B trỏ vào project company A bị DB từ chối (khóa ngoại tổ hợp); payment của project A gắn schedule item của project B bị từ chối, payment `schedule_item_id = NULL` được chấp nhận; photo của project A gắn daily log của project B bị từ chối, photo `daily_log_id = NULL` được chấp nhận; CHECK `job_type`, `cost_group` từ chối giá trị lạ; transaction ghi kèm `activity_log`; rollback khi lỗi.
- UI smoke test: mở app, qua setup, đi 5 tab, đổi sang Tiếng Việt, kiểm tra tiêu đề tab; chụp screenshot.
- Script: key thiếu bản vi; lint cấm `Double`/`Float` cho tiền trong `Domain` và `Data`.

## 12. Tiêu chí hoàn thành

1. `domain.yml` và `ios.yml` xanh trên `main`.
2. `testflight.yml` đẩy được build; cài lên iPhone, mở được, qua setup, thấy 5 tab.
3. Đổi English/Tiếng Việt và sáng/tối trong Settings có hiệu lực ngay.
4. Artifact screenshot đủ light/dark × en/vi cho từng tab và Component Gallery.
5. Không chuỗi hard-code, không `Double` cho tiền, bản vi đủ 100%.

## 13. Ngoài phạm vi

Dashboard summary, wizard tạo project, project detail, mọi form nghiệp vụ, camera, notifications, calendar thật, Supabase, Auth, sync.

## 14. Rủi ro

- Vòng feedback UI qua CI 10–20 phút; lỗi compile SwiftUI chỉ lộ trên CI. Giảm thiểu: dựng pipeline đầu tiên, giữ logic trong Domain test được trên Linux/Windows, commit nhỏ.
- Signing trên CI hay trục trặc lần đầu. Giảm thiểu: làm `testflight.yml` sớm với app gần như trống.
- Repo public: lộ secrets là sự cố nghiêm trọng. Giảm thiểu: quy tắc mục 4, `.gitignore` chặt, bật secret scanning của GitHub.

## Phụ lục A: Data-model contract

Contract này là nguồn duy nhất cho migration SQLite đầu tiên và cho schema Postgres ở sub-project 5.

### A.1 Quy ước chung

- Tên bảng số nhiều, snake_case. Tên cột snake_case.
- Kiểu lưu trong SQLite (kiểu Postgres tương ứng trong ngoặc):
  - UUID: TEXT chữ thường có gạch nối (`uuid`)
  - Tiền: TEXT đúng 2 chữ số thập phân (`numeric(14,2)`)
  - Số thập phân khác (days, quantity, percentage): TEXT (`numeric`)
  - Mốc thời gian: TEXT ISO-8601 UTC (`timestamptz`)
  - Ngày lịch: TEXT `YYYY-MM-DD` (`date`)
  - Boolean: INTEGER 0/1 (`boolean`)
  - Enum: TEXT raw value camelCase, có CHECK liệt kê giá trị
- **Cột chung** của mọi bảng: `id` PK, `company_id` NOT NULL FK → `companies.id`, `created_at` NOT NULL, `updated_at` NOT NULL, `deleted_at` NULL, `sync_state` NOT NULL DEFAULT `'pending'`. Ngoại lệ: `companies` không có `company_id`.
- Các bảng dưới đây chỉ liệt kê cột riêng. Cột không ghi "NULL" là NOT NULL.
- Mọi khóa ngoại là `ON DELETE RESTRICT` và `PRAGMA foreign_keys = ON`. Xóa vật lý không xảy ra trong vận hành bình thường; RESTRICT là lưới an toàn.
- **Khóa ngoại cùng company**: mọi bảng có `company_id` khai báo thêm `UNIQUE (id, company_id)`. Mọi tham chiếu tới bảng cha (trừ tới `companies`) là khóa ngoại tổ hợp `FOREIGN KEY (<parent>_id, company_id) REFERENCES <parent>(id, company_id)`. Nhờ vậy DB tự chặn record company B trỏ vào project của company A; quy tắc này mang nguyên sang Postgres và làm nền cho RLS. Trong tài liệu này, "`x_id` FK → bảng" luôn hiểu là khóa ngoại tổ hợp kiểu trên.
- **Khóa ngoại cùng project**: khi một bảng con tham chiếu một bảng khác cũng thuộc project (`payments → payment_schedule_items`, `photos → daily_logs`), bảng được tham chiếu khai báo thêm `UNIQUE (id, project_id, company_id)` và khóa ngoại là `FOREIGN KEY (<ref>_id, project_id, company_id) REFERENCES <ref>(id, project_id, company_id)`, giữ nguyên khóa ngoại tới `projects`. Cột `<ref>_id` NULL thì khóa ngoại tổ hợp không áp dụng (SQLite và Postgres cùng mặc định `MATCH SIMPLE`), nên payment chưa phân bổ và photo không gắn daily log vẫn hợp lệ.
- Mọi cột khóa ngoại có index. Mọi bảng có index `(company_id)`.
- Hai loại unique, không lẫn nhau:
  - **Đích của khóa ngoại** (`UNIQUE (id, company_id)`, `UNIQUE (id, project_id, company_id)`): unique constraint **đầy đủ**, không có `WHERE`. SQLite và Postgres không cho khóa ngoại tham chiếu partial unique index.
  - **Business/natural key** cần tái dùng sau soft delete (`(company_id, name)`, `(project_id, log_date)`, `(project_id, field_key)`, `(task_id, employee_id)`, `(project_id, employee_id, work_date)`, `(expense_id, page_index)`, `(auth_user_id)`): partial unique index `WHERE deleted_at IS NULL`. Trong A.3, chữ "Unique" ở các khóa này hiểu là partial.
- `sort_order` là INTEGER, thứ tự hiển thị trong cha.

### A.2 Hành vi soft delete

Repository thực hiện trong một transaction:

| Xóa | Hành vi |
|---|---|
| Project | Soft delete project và mọi bản ghi con: scope fields, estimate lines, tasks (kéo theo checklist items, assignees), project workers, schedule items, payments, expenses (kéo theo receipt images), labour entries, daily logs, photos, và mọi `notifications` có `project_id` trỏ tới project (kể cả chưa tới `fire_at`). `activity_log` giữ nguyên. Phòng vệ thêm: truy vấn notification luôn join loại project đã xóa. |
| Customer | Từ chối nếu còn project chưa xóa (`DomainError.customerHasProjects`). |
| Employee | Soft delete employee. Labour entries, task assignees, project workers cũ giữ nguyên để giữ lịch sử và chi phí; khi hiển thị lịch sử, truy vấn employee kể cả đã xóa. |
| Task | Kéo theo checklist items và assignees. |
| Expense | Kéo theo receipt images. File ảnh giữ trên đĩa cho tới khi sync xác nhận (sub-project 5 quyết định dọn dẹp). |
| Payment schedule item | Payments gắn với item được giữ, đặt `schedule_item_id = NULL` (vẫn tính vào `collected`). |
| Custom expense category | Từ chối nếu còn expense chưa xóa đang dùng. Đổi `cost_group` bị từ chối nếu đã từng có expense dùng (kể cả đã xóa); đổi `name` luôn được phép. |
| Company, User | Không có thao tác xóa trong MVP. |

`activity_log` là append-only: không sửa, không xóa.

### A.3 Bảng

**companies** — `name`; `currency_code` CHECK (`CAD`, `USD`).

**users** — `display_name`; `email` NULL; `role` CHECK (`owner`), mặc định `owner`; `auth_user_id` NULL. Unique `(auth_user_id)` khi khác NULL.

**customers** — `name`; `phone` NULL; `email` NULL; `preferred_contact` NULL CHECK (`phone`, `text`, `email`); `company_name` NULL; `secondary_contact` NULL; `notes` NULL. Index `(company_id, name)`.

**projects** — `customer_id` FK → customers; `name`; `job_type` CHECK 20 giá trị `JobType`; `custom_job_type` NULL (bắt buộc khi `job_type = other`); `status`; `address_line`; `unit` NULL; `city` NULL; `region` NULL; `postal_code` NULL; `scope_description` NULL; `start_date` NULL; `estimated_completion_date` NULL; `working_days` INTEGER NULL; `hours_per_day` NULL; `workers_per_day` INTEGER NULL; `contract_value` DEFAULT `'0.00'`; `manual_progress` INTEGER NULL CHECK 0–100; `deposit_required_to_start` DEFAULT 0. Index `(company_id, status)`, `(customer_id)`.

**project_scope_fields** — `project_id` FK → projects; `field_key` (TEXT khác rỗng, không CHECK; catalog theo job type do sub-project 2 định nghĩa, trường tự thêm dùng tiền tố `custom:`); `value_text`; `sort_order`. Unique `(project_id, field_key)`.

**project_estimate_lines** — `project_id` FK; `cost_group` CHECK 6 giá trị `CostGroup`; `label`; `amount`; `quantity` NULL; `unit_rate` NULL (khi có cả hai, `amount = rounded(quantity × unit_rate)`; labour: quantity là số ngày công); `sort_order`. Index `(project_id, cost_group)`.

**employees** — `name`; `phone` NULL; `role` NULL; `trade` NULL; `hourly_rate` NULL; `daily_rate` NULL; `certifications` NULL; `emergency_contact` NULL; `notes` NULL. Index `(company_id, name)`.

**project_tasks** — `project_id` FK; `name`; `status` CHECK 6 giá trị `TaskStatus`; `start_date` NULL; `due_date` NULL; `notes` NULL; `sort_order`. Index `(project_id, sort_order)`, `(company_id, due_date)`.

**task_checklist_items** — `task_id` FK → project_tasks; `title`; `is_done` DEFAULT 0; `sort_order`.

**task_assignees** — `task_id` FK; `employee_id` FK → employees. Unique `(task_id, employee_id)`.

**project_workers** — `project_id` FK; `employee_id` FK; `work_date`. Unique `(project_id, employee_id, work_date)`. Index `(company_id, work_date)`. Một employee được phép ở hai project cùng ngày (là dữ liệu cho cảnh báo trùng lịch sau này).

**payment_schedule_items** — `project_id` FK; `label`; `amount` (giá trị có thẩm quyền); `percentage` NULL (chỉ là nguồn sinh và hiển thị); `due_date` NULL; `trigger_text` NULL; `is_deposit` DEFAULT 0; `notes` NULL; `sort_order`. Unique `(id, project_id, company_id)` (đích cho khóa ngoại cùng project). Index `(project_id, sort_order)`, `(company_id, due_date)`.

**payments** — `project_id` FK; `schedule_item_id` NULL, khóa ngoại tổ hợp `(schedule_item_id, project_id, company_id) → payment_schedule_items(id, project_id, company_id)`; `amount` (> 0); `paid_on`; `method` CHECK 6 giá trị `PaymentMethod`; `notes` NULL. Index `(project_id, paid_on)`, `(schedule_item_id)`.

**custom_expense_categories** — `name`; `cost_group` CHECK 6 giá trị `CostGroup`, DEFAULT `other`, bất biến sau khi đã có expense dùng (repository kiểm tra). Unique `(company_id, name)`.

**expenses** — `project_id` FK (bắt buộc: MVP không có chi phí ngoài project); `category` CHECK 13 giá trị mặc định + `custom`; `custom_category_id` NULL FK → custom_expense_categories (bắt buộc khi và chỉ khi `category = custom`); `cost_group` CHECK 6 giá trị `CostGroup` (snapshot lúc tạo theo mục 5.2, không đổi theo category sau này); `vendor_name` NULL; `amount`; `tax` DEFAULT `'0.00'`; `spent_on`; `payment_method` NULL; `notes` NULL. Index `(project_id, spent_on)`, `(company_id, spent_on)`.

**receipt_images** — `expense_id` FK → expenses; `file_path` (tương đối trong thư mục app); `remote_path` NULL (sub-project 5); `page_index`. Unique `(expense_id, page_index)`.

**labour_entries** — `project_id` FK; `employee_id` FK; `work_date`; `days` (> 0, ví dụ `0.5`); `daily_rate`; `notes` NULL. Index `(project_id, work_date)`, `(employee_id, work_date)`.

**daily_logs** — `project_id` FK; `log_date`; `workers_onsite` INTEGER NULL; `weather` NULL; `work_completed` NULL; `material_delivered` NULL; `problems` NULL; `tomorrow_plan` NULL. Unique `(project_id, log_date)`, `(id, project_id, company_id)` (đích cho khóa ngoại cùng project).

**photos** — `project_id` FK; `daily_log_id` NULL, khóa ngoại tổ hợp `(daily_log_id, project_id, company_id) → daily_logs(id, project_id, company_id)`; `category` CHECK 6 giá trị `PhotoCategory`; `taken_at`; `latitude` REAL NULL; `longitude` REAL NULL (tọa độ không phải tiền, dùng REAL); `file_path`; `remote_path` NULL; `caption` NULL. Index `(project_id, taken_at)`.

**activity_log** — `user_id` NULL FK → users; `actor_name` (chụp lại tên lúc ghi); `action` (mã ổn định, ví dụ `expenseAdded`, `paymentReceived`, `progressChanged`); `entity_type`; `entity_id`; `project_id` NULL FK; `details_json` (tham số để UI dựng câu theo ngôn ngữ đang chọn, ví dụ `{"amount":"450.00"}` hoặc `{"from":40,"to":55}`); `occurred_at`. Index `(project_id, occurred_at)`, `(company_id, occurred_at)`. Không lưu câu đã dịch.

**notifications** — `project_id` NULL FK; `kind` (mã ổn định); `entity_type` NULL; `entity_id` NULL; `details_json`; `fire_at`; `read_at` NULL. Index `(company_id, fire_at)`.

### A.4 Biểu diễn trong Domain

- `ProjectTask.assignees`: danh sách `employeeId`, lưu ở `task_assignees`.
- `ProjectTask.checklist`: danh sách `TaskChecklistItem` có thứ tự, lưu ở `task_checklist_items`.
- `Expense.receiptImages`: danh sách có thứ tự, lưu ở `receipt_images`. Khái niệm "Receipt" trong yêu cầu gốc là tập ảnh này cộng các trường vendor/date/amount/tax của chính Expense; không có bảng `receipts` riêng.
- `Project.scopeFields`: danh sách key-value có thứ tự, lưu ở `project_scope_fields`; giá trị luôn là chuỗi, Features diễn giải theo catalog của job type.
- Bảng liên kết và bảng con đều là dòng riêng có `id`, `updated_at`, `deleted_at` (không dùng cột JSON hay mảng) để sync theo từng dòng.
