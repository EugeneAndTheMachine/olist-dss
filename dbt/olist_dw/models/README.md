# dbt models

Toàn bộ model nghiệp vụ đã được xoá ngày 06/11/2026 để nhóm định nghĩa lại từng nghiệp vụ trước khi code.
Hướng dẫn làm lại từng bước: **`docs/rebuild_guide.md`**. Thiết kế đích: `docs/refactor_plan.md`.
Code cũ để tham khảo: `git show 83891b5:dbt/olist_dw/models/<path>`.

| Thư mục | Schema | Chứa | Bước trong rebuild guide |
| --- | --- | --- | --- |
| `staging/` | `stg` | `_sources.yml` (đã có: raw + meta); `stg_<nguồn>` | 1 |
| `intermediate/` | `stg` | `int_*` (bước trung gian dùng lại) | 3 |
| `warehouse/dims/`, `warehouse/facts/` | `dw` | `dim_*`, `fact_*` | 3 |
| `bi/` | `bi` | `v_*` views cho Power BI | 4–5 |

Macro còn giữ (`macros/`): `int_sk` (surrogate key băm), `generate_schema_name`, `grant_bi_reader` (on-run-end: user chỉ đọc schema bi).
Seed: chưa có (thêm khi chốt nghiệp vụ, vd. `order_status_map`).
