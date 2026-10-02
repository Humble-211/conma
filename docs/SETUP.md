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

Thay bundle id tạm `com.humble211.constructionmanagement` bằng bundle id thật (nếu khác) và `TEAM_ID_PLACEHOLDER` bằng Team ID, commit, push.

## 6. Tạo chứng chỉ (một lần)

Actions → workflow **testflight** → Run workflow → lane `setup_signing`. Thành công thì repo `ios-certificates` có thư mục `certs/` và `profiles/` đã mã hóa.

## 7. Đẩy TestFlight

Actions → **testflight** → Run workflow → lane `beta` (hoặc push tag `v0.1.0`). Sau 5–15 phút, build xuất hiện trong App Store Connect → TestFlight. Thêm Apple ID của bạn vào Internal Testing, cài app TestFlight trên iPhone, nhận build.

## Khi gặp lỗi

- `No matching provisioning profiles`: chạy lại `setup_signing`; kiểm tra `APP_BUNDLE_ID` trùng với App ID.
- `Authentication credentials are missing or invalid` từ match: `MATCH_GIT_BASIC_AUTHORIZATION` sai hoặc token hết hạn.
- `Could not find App` khi upload: app record ở App Store Connect chưa tạo hoặc bundle id khác.
- Build lên TestFlight nhưng không hiện: đợi xử lý xong, kiểm tra email Apple về missing compliance (đã khai `ITSAppUsesNonExemptEncryption = false`).
