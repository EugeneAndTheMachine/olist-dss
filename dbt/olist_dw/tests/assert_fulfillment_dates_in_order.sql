-- Business rule: ngày khách nhận không trước ngày mua (staging đã null các dòng vi phạm). Trả dòng = lỗi.
select order_id, purchase_date_key, delivered_date_key
from {{ ref('fact_order_fulfillment') }}
where delivered_date_key <> -1
  and delivered_date_key < purchase_date_key
