{{ config(severity='warn', warn_if='>1000') }}
-- Đối soát tiền (implementation.md mục 11.1): Σ item_total vs Σ payment_value theo đơn.
-- Tolerance chốt ở profiling S1 (A5): |chênh| <= max(1 BRL, 1% item_total). Chỉ xét đơn có cả item và payment.
-- Trả về các đơn vượt tolerance (S1: ~248 đơn = 0,25%, phần lớn do lãi trả góp / voucher).
-- Chỉ cảnh báo khi > 1000 đơn (~1%) — số dòng lệch vẫn được ghi vào meta.dq_results.
with items as (
    select order_id, sum(item_total) as item_total
    from {{ ref('fact_order_item') }}
    group by order_id
),

payments as (
    select order_id, sum(payment_value) as payment_total
    from {{ ref('fact_payment') }}
    group by order_id
)

select
    i.order_id,
    i.item_total,
    p.payment_total,
    p.payment_total - i.item_total as diff
from items as i
inner join payments as p on i.order_id = p.order_id
where abs(p.payment_total - i.item_total) > greatest(1, 0.01 * i.item_total)
