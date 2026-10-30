# Power BI — hướng dẫn setup

Chủ file: **Xuân Vinh (TV3)**. Trang 2, 4, 7 do **Trường An (TV4)** làm rồi gửi để ghép (CLAUDE.md mục 14.2).
Power BI Desktop **chỉ chạy trên Windows**.

## 1. Cài đặt

1. Cài **Power BI Desktop** từ Microsoft Store (tự cập nhật) hoặc trang tải của Microsoft.
2. Bật lưu dạng project: *File → Options and settings → Options → Preview features* → tick
   **Power BI Project (.pbip) save option** (và **Store semantic model using TMDL format** nếu có) → khởi động lại.
   Bản mới đã đưa tính năng này ra chính thức thì không cần bước này.
3. Driver PostgreSQL (Npgsql) đã có sẵn trong Power BI Desktop, không cần cài thêm.

## 2. Kết nối warehouse

Điều kiện: `make up` đang chạy và `make build` đã tạo schema `bi`.

1. *Home → Get data → PostgreSQL database*
   - Server: `localhost:5432`
   - Database: `olist_dw`
   - Data connectivity mode: **Import**
2. Đăng nhập kiểu **Database**: user/password trong `.env` (mặc định `olist` / `olist`).
3. Nếu báo lỗi chứng chỉ / SSL: *File → Options and settings → Data source settings* → chọn nguồn
   `localhost:5432;olist_dw` → *Edit Permissions* → bỏ tick **Encrypt connections**. Postgres trong Docker không bật SSL.
4. Trong Navigator **chỉ chọn view của schema `bi`** (`bi.v_*`). Không đọc `dw`, `stg`, `ml` trực tiếp.

## 3. Quy ước semantic model

- Mô hình galaxy: dim conformed dùng chung; role-playing date / geography bằng view riêng
  (`v_dim_customer_geo`, `v_dim_seller_geo`) hoặc inactive relationship + `USERELATIONSHIP`.
- Mọi DAX measure để trong bảng `_Measures`, **đúng định nghĩa** ở CLAUDE.md mục 8 / `docs/kpi_dictionary.md`.
  Tỷ lệ luôn = tổng tử số / tổng mẫu số (vd. `Late Rate = DIVIDE(SUM(is_late), SUM(is_delivered))`).
- What-if parameter (trang 2, 4, 7) đọc bảng kịch bản tính sẵn trong `bi.v_promise_whatif`, `bi.v_voucher_allocation`, `bi.v_gmv_forecast`.

## 4. Lưu & làm việc chung

- Lưu thành `powerbi/olist_dw.pbip` (*File → Save as → Power BI project files*). Thư mục `.SemanticModel/` và `.Report/` là text → commit được.
- `.gitignore` đã bỏ qua `.pbi/localSettings.json` và `.pbi/cache.abf`.
- Tránh hai người sửa cùng lúc một file: TV4 làm trang 2, 4, 7 trên bản copy rồi gửi TV3 ghép, hoặc chia trang rõ ràng và pull trước khi mở.
- Refresh dữ liệu: *Home → Refresh* sau mỗi lần `make build` / `make ml`.
