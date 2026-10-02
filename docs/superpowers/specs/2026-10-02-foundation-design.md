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

`Money`: bọc `Decimal` + `currencyCode` (`CAD` | `USD`). Hỗ trợ cộng, trừ, nhân với số lượng, nhân phần trăm. Làm tròn half-up về 2 chữ số tại một hàm duy nhất. Phép tính giữa hai currency khác nhau ném `DomainError.currencyMismatch`.

`CalendarDate`: ngày lịch không kèm giờ (`YYYY-MM-DD`), dùng cho due date, start date, completion date. Mốc thời gian thực (createdAt, timestamp ảnh) dùng `Date` UTC.

Mọi entity có: `id: UUID`, `companyId`, `createdAt`, `updatedAt`, `deletedAt?` (soft delete).

### 5.2 Entities MVP

Project là entity trung tâm.

- `Company` (name, currencyCode), `User`
- `Customer` (name, phone, email, preferredContact, companyName?, secondaryContact?, notes)
- `Project`: name, jobType (20 loại + custom), status, customerId, address (line, unit, city, region, postalCode), scope (mô tả + các trường động theo jobType dạng key-value), startDate, estimatedCompletionDate, workingDays, contractValue, manualProgress?, depositRequiredToStart
- `ProjectEstimate`: các dòng dự toán theo nhóm labour / material / other
- `ProjectTask` (name, assignees, startDate, dueDate, status, checklist) và `ProjectWorker` (gán employee vào project theo ngày)
- `Employee` (name, phone, role, trade, hourlyRate?, dailyRate?, notes)
- `PaymentScheduleItem` (label, amount, percentage?, dueDate?, trigger?, isDeposit, notes) và `Payment` (scheduleItemId?, amount, date, method, notes)
- `Expense` (category, vendorName, amount, tax, date, paymentMethod, notes) và `Receipt` (danh sách ảnh)
- `LabourEntry` simple mode (employeeId, date, days, dailyRate)
- `DailyLog` (date, workersOnsite, weather, workCompleted, materialDelivered, problems, tomorrow)
- `Photo` (category, takenAt, latitude?, longitude?, filePath)
- `ActivityLog` (actor, action, entityType, entityId, summary, occurredAt)
- `AppNotification`

Enums: `ProjectStatus` (13 giá trị: estimate, awaitingApproval, awaitingDeposit, scheduled, inProgress, onHold, waitingForInspection, waitingForMaterial, waitingForClient, completed, awaitingFinalPayment, closed, cancelled), `TaskStatus` (6), `PaymentMethod` (6), `ExpenseCategory` (13 mặc định + custom), `PhotoCategory` (6), `JobType`.

Chưa build: Estimate/Quote, Invoice, ChangeOrder, Vendor, Subcontractor, TimeEntry.

### 5.3 Financial engine

`FinancialCalculator` là hàm thuần: nhận project, estimate, expenses, labour entries, payments, `approvedChangeOrders` (hiện luôn bằng 0), trả `ProjectFinancials`.

| Giá trị | Công thức |
|---|---|
| `adjustedContract` | contractValue + approvedChangeOrders |
| `totalCost` | material + labour + subcontractor + equipment + permit + other (Expense theo category + LabourEntry) |
| `estimatedCost` | tổng các dòng `ProjectEstimate` |
| `projectedProfit` | adjustedContract − estimatedCost |
| `spentSoFar` | totalCost thực tế đến nay |
| `collected` | tổng `Payment` |
| `outstandingBalance` | adjustedContract − collected |
| `cashPosition` | collected − spentSoFar |
| `actualProfit` | adjustedContract − totalCost |
| `margin` | profit / adjustedContract × 100; adjustedContract = 0 thì `nil` |

Quy tắc hiển thị (theo yêu cầu gốc mục 42):

- `cashPosition` mang nhãn "Cash position", không gọi là profit.
- `actualProfit` chỉ mang nhãn "Actual profit" khi project ở trạng thái completed, awaitingFinalPayment hoặc closed. Trước đó nhãn là "Projected at current spending".
- `margin = nil` hiển thị "—".

Ví dụ kiểm chứng từ yêu cầu gốc: contract $30,000; material $6,000; labour $7,500; other $1,000 → totalCost $14,500, profit $15,500, margin 51.7%. Deposit $5,000 + payments $15,000 → outstanding $10,000.

### 5.4 Rule khác

- `ProgressCalculator`: phần trăm = task completed / tổng task (làm tròn số nguyên). Không có task thì 0. `manualProgress` nếu có thì thắng.
- `PaymentStatusResolver`: nhận schedule item, tổng đã trả, `today`. Trả paid (đã trả đủ), partiallyPaid (0 < đã trả < amount), overdue (chưa đủ, quá hạn), dueToday, dueSoon (còn ≤ 3 ngày), upcoming. Overdue ưu tiên hơn partiallyPaid khi đã quá hạn.
- `BudgetAlertRule`: theo từng nhóm chi phí so với estimate. ≥ 90% là `nearLimit`, > 100% là `exceeded` kèm số tiền vượt. Không có estimate thì không cảnh báo.
- `ProjectHealthEvaluator`: rule-based, trả trạng thái + danh sách lý do. Over Budget (có nhóm exceeded), Payment Risk (có khoản overdue), Delayed (quá estimatedCompletionDate mà chưa completed), At Risk (budget nearLimit, hoặc còn ≤ 7 ngày mà progress < 80%), còn lại On Track. Nhiều tín hiệu thì lấy mức nặng nhất theo thứ tự trên, giữ đủ lý do.

`today`/`now` luôn được truyền vào, không gọi `Date()` trong Domain.

### 5.5 Validation

Domain từ chối: số tiền âm, estimatedCompletionDate trước startDate, trộn currency. Tổng payment schedule khác contract value là cảnh báo, không chặn.

### 5.6 Repository protocols

Mỗi aggregate một protocol trong Domain (`ProjectRepository`, `CustomerRepository`, `CompanyRepository`, …) với các hàm async `get`, `list`, `save`, `delete` và `observe…` trả `AsyncSequence` để UI tự cập nhật.

## 6. Data layer

- Một file SQLite trong Application Support. Ảnh và receipt lưu thành file trong thư mục app; DB giữ đường dẫn tương đối.
- Migration đánh số, SQL tường minh. Tên bảng và cột snake_case, trùng với schema Postgres của sub-project 5.
- Migration đầu tạo đủ bảng cho mọi entity MVP ở mục 5.2.
- `Decimal` lưu TEXT (`"246.50"`). `Date` lưu ISO-8601 UTC. `CalendarDate` lưu `YYYY-MM-DD`.
- Mỗi bảng có `updated_at`, `deleted_at`, `sync_state` (`pending` | `synced`). Sub-project 1 chưa dùng `sync_state`.
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

- `DomainTests` (viết theo TDD): financial engine với số từ yêu cầu gốc; làm tròn half-up; margin khi contract = 0; trộn currency; payment status ở từng mốc ngày; progress có và không có override; budget alert ở 89%, 90%, 100%, 101%; health rules và thứ tự ưu tiên.
- `DataTests`: migration từ DB trống; round-trip record (đặc biệt `Decimal`, `CalendarDate`); soft delete; transaction ghi kèm `activity_log`; rollback khi lỗi.
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
