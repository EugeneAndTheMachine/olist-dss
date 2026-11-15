-- BR-CW10-1: fact_review giữ đủ dòng và đúng một review được tính cho mỗi đơn như staging.
select
    (select count(*) from {{ ref('fact_review') }}) as fact_rows,
    (select count(*) from {{ ref('stg_order_reviews') }}) as stg_rows,
    (select sum(is_latest_for_order) from {{ ref('fact_review') }}) as fact_latest,
    (select count(distinct order_id) from {{ ref('stg_order_reviews') }}) as reviewed_orders
where (select count(*) from {{ ref('fact_review') }}) <> (select count(*) from {{ ref('stg_order_reviews') }})
   or (select sum(is_latest_for_order) from {{ ref('fact_review') }}) <> (select count(distinct order_id) from {{ ref('stg_order_reviews') }})
