-- Point-in-time lookup (SCD2): version seller gắn với mỗi item phải hiệu lực đúng vào ngày mua. Trả dòng = lỗi.
select
    f.order_id,
    f.order_item_id,
    d.full_date as purchase_date,
    s.seller_id,
    s.valid_from,
    s.valid_to
from {{ ref('fact_order_item') }} as f
inner join {{ ref('dim_date') }} as d on f.purchase_date_key = d.date_key
inner join {{ ref('dim_seller') }} as s on f.seller_key = s.seller_key
where f.seller_key <> -1
  and not (d.full_date between s.valid_from and s.valid_to)
