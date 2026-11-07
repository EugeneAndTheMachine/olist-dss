-- Schema theo layer (implementation.md mục 6)
create schema if not exists raw;   -- Bronze: append-only, mọi cột text
create schema if not exists stg;   -- Silver: dbt staging + intermediate + seeds
create schema if not exists dw;    -- Gold: dims + facts
create schema if not exists bi;    -- Logical data marts: Power BI chỉ đọc schema này
create schema if not exists ml;    -- Output mô hình (Python ghi)
create schema if not exists meta;  -- Run log, DQ, dictionary, lineage, model registry

-- Extension bỏ dấu tiếng Bồ Đào Nha, sẵn cho rule làm sạch text nếu nhóm chốt dùng (docs/rebuild_guide.md)
create extension if not exists unaccent;
