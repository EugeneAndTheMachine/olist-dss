-- SCD2 liên tục (implementation.md mục 10): version đầu bắt đầu 1900-01-01, version cuối mở tới 9999-12-31,
-- version kế bắt đầu đúng 1 ngày sau version trước → mọi ngày tra được đúng 1 version. Trả dòng = lỗi.
with ordered as (
    select
        seller_id,
        version_no,
        valid_from,
        valid_to,
        lead(valid_from) over (partition by seller_id order by valid_from) as next_valid_from,
        min(valid_from) over (partition by seller_id) as first_valid_from,
        max(valid_to) over (partition by seller_id) as last_valid_to
    from {{ ref('dim_seller') }}
)

select seller_id, version_no, valid_from, valid_to, next_valid_from, 'gap_or_overlap' as problem
from ordered
where next_valid_from is not null and next_valid_from <> valid_to + 1

union all

select seller_id, version_no, valid_from, valid_to, null, 'first_version_not_1900'
from ordered
where version_no = 1 and first_valid_from <> '{{ var("scd_first_valid_from") }}'::date

union all

select seller_id, version_no, valid_from, valid_to, null, 'last_version_not_open'
from ordered
where next_valid_from is null and last_valid_to <> '{{ var("scd_open_end_date") }}'::date
