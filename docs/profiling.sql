-- Profiling — query dùng cho docs/profiling.md (chạy trên schema raw, mọi cột là text).
-- Chạy: docker compose exec -T postgres psql -U olist -d olist_dw < docs/profiling.sql

\pset footer off

\echo == Tổng quan: số dòng / khoá phân biệt
select 'orders' t, count(*) n, count(distinct order_id) d from raw.orders
union all select 'order_items', count(*), count(distinct order_id||'-'||order_item_id) from raw.order_items
union all select 'order_payments', count(*), count(distinct order_id||'-'||payment_sequential) from raw.order_payments
union all select 'order_reviews', count(*), count(distinct review_id) from raw.order_reviews
union all select 'customers', count(*), count(distinct customer_id) from raw.customers
union all select 'sellers', count(*), count(distinct seller_id) from raw.sellers
union all select 'products', count(*), count(distinct product_id) from raw.products
union all select 'geolocation', count(*), count(distinct geolocation_zip_code_prefix) from raw.geolocation
union all select 'translation', count(*), count(distinct product_category_name) from raw.product_category_name_translation
;

\echo == A1 order_status / payment_type
select order_status, count(*) from raw.orders group by 1 order by 2 desc;
select payment_type, count(*), count(*) filter (where payment_value::numeric = 0) zero_value
from raw.order_payments group by 1 order by 2 desc;
select min(payment_installments::int), max(payment_installments::int),
       count(*) filter (where payment_installments = '0') zero_inst
from raw.order_payments;

\echo == Orders: trạng thái vs ngày giao, mốc thời gian bất thường
select order_status,
       count(*) filter (where order_delivered_customer_date is null) no_deliv_date,
       count(*) filter (where order_delivered_customer_date is not null) has_deliv_date,
       count(*) filter (where order_approved_at is null) no_approved
from raw.orders group by 1 order by 1;
select count(*) filter (where order_delivered_customer_date::timestamp < order_purchase_timestamp::timestamp) deliv_before_purchase,
       count(*) filter (where order_delivered_carrier_date::timestamp < order_purchase_timestamp::timestamp) carrier_before_purchase,
       count(*) filter (where order_delivered_carrier_date::timestamp < order_approved_at::timestamp) carrier_before_approved,
       count(*) filter (where order_delivered_customer_date::timestamp < order_delivered_carrier_date::timestamp) deliv_before_carrier,
       count(*) filter (where order_estimated_delivery_date::timestamp::time <> '00:00') est_with_time
from raw.orders;

\echo == A2 reviews
select count(*) reviews, count(distinct review_id) uniq_review_id, count(distinct order_id) orders_with_review,
       (select count(*) from (select review_id from raw.order_reviews group by 1 having count(distinct order_id) > 1) x) review_ids_multi_orders,
       (select count(*) from (select order_id from raw.order_reviews group by 1 having count(*) > 1) x) orders_multi_reviews,
       (select count(*) from (select order_id from raw.order_reviews group by 1 having count(distinct review_score) > 1) x) orders_multi_scores,
       (select count(*) from raw.orders o where not exists (select 1 from raw.order_reviews r where r.order_id = o.order_id)) orders_without_review
from raw.order_reviews;

\echo == A3 geolocation (bbox Brazil: lat -34..5.5, lng -74..-34)
select count(*) n_rows, count(distinct geolocation_zip_code_prefix) zips,
       count(*) filter (where geolocation_lat::numeric not between -34 and 5.5
                           or geolocation_lng::numeric not between -74 and -34) outside_bbox,
       count(distinct geolocation_city) distinct_city_raw,
       count(distinct lower(public.unaccent(geolocation_city))) distinct_city_clean,
       count(*) filter (where geolocation_city ~ '[áàâãéêíóôõúç]') accented_rows
from raw.geolocation;
select count(*) zips_all_points_outside from (
  select geolocation_zip_code_prefix from raw.geolocation group by 1
  having bool_and(geolocation_lat::numeric not between -34 and 5.5 or geolocation_lng::numeric not between -74 and -34)) x;
select count(*) zips_multi_state from (
  select geolocation_zip_code_prefix from raw.geolocation group by 1 having count(distinct geolocation_state) > 1) x;
select (select count(distinct customer_zip_code_prefix) from raw.customers c
         where not exists (select 1 from raw.geolocation g where g.geolocation_zip_code_prefix = c.customer_zip_code_prefix)) cust_zip_missing,
       (select count(*) from raw.customers c
         where not exists (select 1 from raw.geolocation g where g.geolocation_zip_code_prefix = c.customer_zip_code_prefix)) cust_rows_missing,
       (select count(*) from raw.sellers s
         where not exists (select 1 from raw.geolocation g where g.geolocation_zip_code_prefix = s.seller_zip_code_prefix)) seller_zip_missing;

\echo == A4 products
select count(*) filter (where product_category_name is null) no_category,
       count(*) filter (where product_category_name is not null and product_category_name not in
                        (select product_category_name from raw.product_category_name_translation)) no_translation,
       count(*) filter (where product_weight_g is null) no_weight,
       count(*) filter (where product_weight_g = '0') zero_weight,
       count(*) filter (where product_length_cm is null) no_dims
from raw.products;
select count(*) items_no_category from raw.order_items i join raw.products p using (product_id) where p.product_category_name is null;

\echo == A5 Σ item_total vs Σ payment_value theo đơn
with it as (select order_id, sum(price::numeric + freight_value::numeric) item_total from raw.order_items group by 1),
     pa as (select order_id, sum(payment_value::numeric) pay_total from raw.order_payments group by 1),
     j  as (select o.order_id, it.item_total, pa.pay_total, abs(pa.pay_total - it.item_total) diff
            from raw.orders o left join it using (order_id) left join pa using (order_id))
select count(*) orders,
       count(*) filter (where item_total is null) no_items,
       count(*) filter (where pay_total is null) no_payment,
       count(*) filter (where diff <= 0.01) diff_le_1cent,
       count(*) filter (where diff > 0.01 and diff <= 1) diff_1cent_1brl,
       count(*) filter (where diff > 1 and diff <= 0.05 * item_total) diff_1brl_5pct,
       count(*) filter (where diff > 0.05 * item_total) diff_gt_5pct,
       round(100.0 * count(*) filter (where diff <= greatest(1, 0.01 * item_total)) / count(diff), 2) pct_pass_tolerance
from j;
select o.order_status, count(*) orders_without_items from raw.orders o
where not exists (select 1 from raw.order_items i where i.order_id = o.order_id) group by 1 order by 2 desc;

\echo == A7 khách mua lặp
with c as (select cu.customer_unique_id, count(distinct o.order_id) n
           from raw.orders o join raw.customers cu using (customer_id) group by 1)
select count(*) uniq_customers, count(*) filter (where n >= 2) repeat_customers,
       round(100.0 * count(*) filter (where n >= 2) / count(*), 2) pct_repeat, max(n) max_orders
from c;

\echo == A8 số đơn theo tháng
select to_char(order_purchase_timestamp::timestamp, 'YYYY-MM') m, count(*) orders,
       count(*) filter (where order_status = 'delivered') delivered
from raw.orders group by 1 order by 1;

\echo == A9 độ dài zip (raw là text nên giữ số 0 đầu)
select 'geo' src, length(geolocation_zip_code_prefix) len, count(*) from raw.geolocation group by 1, 2
union all select 'cust', length(customer_zip_code_prefix), count(*) from raw.customers group by 1, 2
union all select 'seller', length(seller_zip_code_prefix), count(*) from raw.sellers group by 1, 2 order by 1, 2;
select count(*) cust_zip_leading_zero from raw.customers where customer_zip_code_prefix like '0%';

\echo == Late rate: so ngày (định nghĩa KPI) vs so timestamp
with d as (select order_purchase_timestamp::timestamp p, order_delivered_customer_date::timestamp dl,
                  order_estimated_delivery_date::timestamp e
           from raw.orders where order_status = 'delivered' and order_delivered_customer_date is not null)
select count(*) delivered, round(100.0 * avg((dl::date > e::date)::int), 2) late_pct_date,
       round(100.0 * avg((dl > e)::int), 2) late_pct_timestamp,
       round(avg(extract(epoch from dl - p) / 86400)::numeric, 1) avg_delivery_days,
       round(avg(extract(epoch from e - p) / 86400)::numeric, 1) avg_promised_days
from d;

\echo == Đơn nhiều seller
select count(*) filter (where n_sellers > 1) multi_seller_orders, max(n_items) max_items, round(avg(n_items), 2) avg_items
from (select order_id, count(*) n_items, count(distinct seller_id) n_sellers from raw.order_items group by 1) x;

\echo == Phân bố seller: đơn / seller / tháng; late rate seller (>= 20 đơn đã giao)
with sm as (select seller_id, m, count(*) n from (
              select distinct i.order_id, i.seller_id, date_trunc('month', o.order_purchase_timestamp::timestamp) m
              from raw.order_items i join raw.orders o using (order_id)
              where o.order_status not in ('canceled', 'unavailable')) x group by 1, 2)
select percentile_cont(array[0.25, 0.5, 0.75, 0.9, 0.99]) within group (order by n) orders_per_seller_month from sm;
with x as (select i.seller_id,
                  (o.order_delivered_customer_date::timestamp::date > o.order_estimated_delivery_date::timestamp::date) late
           from raw.orders o join (select distinct order_id, seller_id from raw.order_items) i using (order_id)
           where o.order_status = 'delivered' and o.order_delivered_customer_date is not null),
     s as (select seller_id, avg(late::int) lr from x group by 1 having count(*) >= 20)
select count(*) sellers, percentile_cont(array[0.5, 0.75, 0.9]) within group (order by lr) late_rate_p50_p75_p90,
       count(*) filter (where lr >= 0.15) late_ge_15pct
from s;

\echo == Danh sách bang của customers và sellers
select (select count(distinct customer_state) from raw.customers) customer_states,
       (select count(distinct seller_state) from raw.sellers) seller_states,
       (select string_agg(distinct customer_state, ',' order by customer_state) from raw.customers) customer_state_list;
