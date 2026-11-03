select
    order_id as "Order ID",
    payment_sequential as "Payment Sequential",
    purchase_date_key,
    customer_key,
    payment_type_key,
    order_status_key,
    payment_value as "Payment Value",
    payment_count as "Payment Count",
    payment_installments as "Installments"
from {{ ref('fact_payment') }}
