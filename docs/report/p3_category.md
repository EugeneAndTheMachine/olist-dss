# P3 — Top category (bản nháp phần báo cáo)

> Số liệu từ lần chạy local ngày 08/11/2026 trên dữ liệu Olist đầy đủ, cửa sổ phân tích đến 2018-08. Chốt lại số sau lần
> `make all` cuối trên `main` (khi đủ model của cả nhóm) và ghi ngày chạy vào báo cáo chung.

## 1. Introduction

P1 hỏi *giao hàng có ổn không*, P2 hỏi *mở rộng ở vùng nào*, P3 hỏi *bán gì*: Category Manager cần biết category nào
đáng đầu tư, category nào cần sửa chất lượng trước khi đẩy, và category nào phụ thuộc quá ít seller. Ba bài toán dùng
chung các dimension conformed (`dim_date`, `dim_geography`, `dim_seller`, `dim_product`) nên số liệu khớp nhau giữa các
trang.

## 2. Business problem definition

- **Decision maker:** Category Manager.
- **Quyết định:** phân bổ ngân sách marketing, tuyển seller và ưu tiên cải thiện chất lượng theo category cho quý tới.
- **Expected goals (đo được):** tăng thị phần GMV của nhóm category được chọn đầu tư; giảm tỷ lệ review ≤ 2 sao ở category
  bị gắn cờ chất lượng; giảm HHI seller ở category bị gắn cờ tuyển seller.

| # | Câu hỏi | KPI / mô hình |
| --- | --- | --- |
| D1 | Top N category bán chạy theo thời gian, vùng? | GMV, Orders, Items, GMV share, Pareto |
| D2 | Category nào tăng / mất thị phần so với toàn sàn? | YoY, relative growth, share change |
| D3 | Category nào bán nhiều nhưng khách không hài lòng / giao trễ? | Avg score, low-score rate, late rate, cờ chất lượng |
| D4 | Category nào phụ thuộc vài seller? | Seller HHI, active sellers, cờ tuyển seller |
| D5 | Nhu cầu quý tới bao nhiêu? | Dự báo GMV 3 tháng + khoảng 80% (ML-3a) |
| D6 | Nên Grow / Invest / Maintain / Review category nào, làm gì? | Class, opportunity score, hành động (ML-3b) |
| D7 | Khi nào khuyến mãi cho nhóm nào? | Seasonality index |
| D8 | Category mạnh ở bang nào? | GMV theo category × bang |

Mapping Simon: Intelligence = trang 6 (D1–D3, D7, D8); Design = growth–share, dự báo (D4, D5); Choice = ranking theo
trọng số chỉnh được + hành động đề xuất (D6).

## 3. Proposed solution

### 3.1 Warehouse

- `dim_category` (1 dòng / category, 74 category + thành viên `-1`): tên PT, EN, tên hiển thị, nhóm (11 nhóm + Unknown),
  `is_rankable`. Tách khỏi `dim_product` (snowflake một bậc) vì category là đối tượng ra quyết định của P3, có thuộc tính
  riêng và được `ml.category_opportunity` nối tới; `dim_product` vẫn mang `category_key`.
- `fact_order_item` (1 dòng / item) và `fact_review` (1 dòng / review × đơn) là fact dùng chung.
- `fact_category_month` — periodic snapshot **category × bang của khách × tháng mua**, chỉ đơn tính là bán (BR-P3-2).
  Item được gộp về (đơn, category) **trước** khi nối review mới nhất và trạng thái giao 1:1 theo `order_id`. Nối ở grain
  item làm một review bị đếm lặp theo số item: `review_count` tăng 13%, điểm TB của office_furniture tụt từ 3,62 xuống
  3,50 (BR-P3-3). Measure cộng được qua bang và tháng; `customers`, `sellers_active` không cộng được. Tỷ lệ luôn tính
  Σ tử / Σ mẫu.
- Test đối soát: items và GMV của mart khớp `fact_order_item`; mỗi cặp (đơn, category) có review được đếm đúng một lần;
  đơn giao / trễ cũng vậy; GMV fact khớp staging.

### 3.2 KPI

Định nghĩa đầy đủ và DAX ở `docs/kpi_dictionary.md` (mục Chung và P3). Điểm khác với refactor plan: **relative growth**
= (1 + YoY category) / (1 + YoY sàn) − 1, vì cả sàn tăng 74% (3 tháng gần nhất so với cùng kỳ), nên YoY thô cho thấy gần
như mọi category đều "tăng". Ví dụ: bed_bath_table YoY +20% nhưng relative growth −31%, tức đang mất thị phần (BR-P3-4).
Growth để trống khi một trong hai cửa sổ 3 tháng có < 30 đơn.

### 3.3 Mô hình

- **ML-3a (dự báo):** chuỗi GMV tháng cho 18 category đủ dày (≥ 10 đơn mọi tháng train) và 11 nhóm. Ứng viên: naive,
  seasonal naive, moving average 3 tháng, ETS (damped trend). Chọn model theo level bằng rolling-origin trong train
  (origin 2017-12, 2018-01, 2018-02; horizon 3), chấm một lần trên 2018-06..08. Quy tắc định trước: nếu model chọn không
  thắng baseline tốt nhất theo validation trên test thì dùng baseline đó.
- **ML-3b (danh mục):** class theo Pareto 80% GMV 12 tháng × relative growth (dead band ±5%); cờ chất lượng khi điểm TB
  thấp hơn sàn > 0,2, hoặc tỷ lệ review thấp cao hơn sàn > 5 điểm %, hoặc late rate cao hơn sàn > 2 điểm %; cờ tuyển seller
  khi HHI ≥ 0,25. Opportunity score = trung bình có trọng số của percentile rank 6 thành phần (quy mô 0,25, growth 0,25,
  forecast 0,10, hài lòng 0,15, đúng hạn 0,15, freight 0,10), chỉ trên thành phần khác null. Hành động: cờ chất lượng →
  *Fix quality first*; Grow / Invest có cờ seller → *Recruit sellers*; còn lại theo class.

## 4. Application development

Pipeline: `make all` = raw → dbt (`stg` → `dw` → `bi`) → `ml.p3_category` → `ml.recommendations` → meta. Airflow chạy cùng
thứ tự (`dbt_build >> ml_p3 >> ml_recommendations`). Power BI đọc schema `bi` bằng user chỉ đọc.

- Trang 6 — Category Performance: KPI cards, Top-N động (what-if 5–30, field parameter GMV / Orders / Items), Pareto,
  scatter GMV × điểm review, bảng share change / relative growth / HHI, heatmap mùa vụ, matrix category × bang.
- Trang 7 — Category Opportunities: growth–share với ngưỡng chỉnh được, slider 6 trọng số, ranking với class / cờ /
  hành động tính lại bằng DAX, dự báo + backtest, bảng đề xuất mặc định từ `v_recommendations`.

Wireframe: `powerbi/work/p3_wireframe.png`; measure: `powerbi/work/p3_measures.dax`. Hình chụp trang: *chờ dựng*.

## 5. Evaluation

### 5.1 ML-3a — sMAPE trung vị trên test 2018-06..08

| Level | ETS (chọn theo validation) | Naive | Moving average | Seasonal naive | Dùng cho dự báo |
| --- | --- | --- | --- | --- | --- |
| Category (18) | 0,354 | **0,263** | 0,293 | 0,539 | naive |
| Nhóm (11) | 0,295 | 0,182 | **0,178** | 0,779 | moving average |

ETS thắng ở validation (sMAPE 0,257 / 0,242) nhưng thua trên test, vì nó ngoại suy đà tăng mạnh của 2017 trong khi
2018 đi ngang. Theo quy tắc định trước, dự báo dùng baseline tốt nhất theo validation; vì quyết định này dùng tập test,
sMAPE test của baseline được dùng không còn là holdout hoàn toàn sạch. Khoảng danh nghĩa 80% phủ trung vị 2/3 tháng test. Kết luận: chuỗi 20 tháng chưa đủ để model có trend đánh bại baseline; dự báo chỉ là một thành phần nhỏ (trọng số
0,10) của điểm cơ hội.

### 5.2 ML-3b — backtest (BR-P3-12)

Chạy cùng hàm feature với as-of 2018-05-31, đo thay đổi GMV share 2018-06..08 so với 2018-03..05:

| Class tại 2018-05 | Số category | Thay đổi share trung vị (điểm %) |
| --- | --- | --- |
| Grow | 7 | +0,63 |
| Invest selectively | 5 | −0,32 |
| Maintain | 9 | −1,04 |
| Review | 27 | +0,04 |

Grow vượt Review như kỳ vọng; Invest selectively thì không, nên tiêu chí gộp "Grow / Invest > Review" **không đạt**.
Ngưỡng không được chỉnh để cho đạt. Giải thích: nhóm Invest chỉ 5 category nhỏ, share dao động mạnh, và cửa sổ kết
quả chỉ 3 tháng. Độ ổn định: đổi Pareto 75% / 85% làm 3 category đổi class; đổi dead band ±3% / ±7% làm 1 / 0 category
đổi class.

### 5.3 Giới hạn

Không có giá vốn, nên freight ratio là proxy cho lợi nhuận. Chuỗi thời gian ngắn (2017-01 → 2018-08). Tăng trưởng của
sàn chi phối YoY. 25 category không xếp loại (24 vì < 100 đơn giao trong 12 tháng, cộng Unknown). Growth của 21 / 49
category xếp loại để trống do < 30 đơn và được coi là ổn định.

## 6. Conclusion — đề xuất

- **Đầu tư:** beleza_saude (9,7% GMV, relative growth +65%), relogios_presentes (+47%), utilidades_domesticas (+52%),
  automotivo, telefonia, papelaria.
- **Thử và mở rộng:** pet_shop (+64%), eletronicos (+39%).
- **Sửa chất lượng trước:** moveis_escritorio (điểm 3,56, 24,7% review thấp, late 9,6%), casa_conforto, audio,
  telefonia_fixa.
- **Giữ, theo dõi mất thị phần:** cama_mesa_banho (−31%), informatica_acessorios (−36%), cool_stuff (−71%), brinquedos.
- **Tuyển seller:** pcs (HHI 0,55), moveis_escritorio (0,43) — phụ thuộc vài seller lớn.

## Appendix 1 — đóng góp của Vinh

- Dùng chung: `stg_order_items` (C-S2), `stg_products` / `stg_order_reviews` / bản dịch category (C-S6, C-S7),
  `dim_product` / `dim_category` (C-W5), `fact_order_item` (C-W8), `fact_review` (C-W10), bảng và writer
  `ml.recommendations` (C-M2), rule tương ứng trong `business_rules.md`.
- P3: `fact_category_month`, KPI P3, `ml/p3_category` (ML-3a, ML-3b, backtest), view `bi` P3, DAX và wireframe trang 6–7,
  phần báo cáo này.
