-- BR-O4: Ngày khách nhận không được trước ngày mua (stg_orders đã null các dòng vi phạm). Trả về dòng = lỗi.
select
    order_id,
    purchase_date_key,
    delivered_date_key
from {{ ref('fact_order_fulfillment') }}
where delivered_date_key <> -1
  and delivered_date_key < purchase_date_key

