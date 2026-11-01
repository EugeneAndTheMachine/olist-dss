-- S1 profiling — Phần 2: Xác nhận giả định A1–A9 (schema raw, mọi cột text).
-- Chạy: docker compose exec -T postgres psql -U olist -d olist_dw < docs/profiling/02_assumptions.sql
-- Kết quả tóm tắt trong docs/profiling.md, mục "Giả định cần xác nhận".
-- Lưu ý: load_raw nạp bằng COPY csv nên ô rỗng trong CSV thành NULL (không phải '').

\echo == A1 order_status
select order_status, count(*) n,
  count(*) filter (where nullif(order_delivered_customer_date,'') is not null) has_delivered_date,
  count(*) filter (where not exists (select 1 from raw.order_items i where i.order_id=o.order_id)) no_items
from raw.orders o group by 1 order by 2 desc;
\echo == A1 payment_type
select payment_type, count(*) n, count(distinct order_id) orders, sum(payment_value::numeric) value from raw.order_payments group by 1 order by 2 desc;
\echo == A1 installments
select payment_installments::int inst, count(*) from raw.order_payments group by 1 order by 1;
\echo == A1 installments=0 / not_defined detail
select payment_type, payment_installments, payment_value from raw.order_payments where payment_installments::int=0 or payment_type='not_defined';
\echo == A1 payment_value 0
select payment_type, count(*) from raw.order_payments where payment_value::numeric=0 group by 1;
\echo == A1 status of not_defined orders, debit/boleto with installments>1
select o.order_status, count(*) from raw.order_payments p join raw.orders o using(order_id) where p.payment_type='not_defined' group by 1;
select payment_type, count(*) filter (where payment_installments::int>1) gt1 from raw.order_payments group by 1;
\echo == A1 orders paid only by voucher
select count(*) from (select order_id from raw.order_payments group by 1 having bool_and(payment_type='voucher')) x;
\echo == A2 review_id per order count distribution
select c orders_per_review, count(*) from (select review_id, count(distinct order_id) c from raw.order_reviews group by 1) x group by 1 order by 1;
select c reviews_per_order, count(*) from (select order_id, count(*) c from raw.order_reviews group by 1) x group by 1 order by 1;
\echo == A2 duplicates of key (review_id, order_id)
select count(*) - count(distinct (review_id, order_id)) dup_keys from raw.order_reviews;
\echo == A2 orders with many reviews: different scores? tie on answer_timestamp?
select count(*) orders,
  count(*) filter (where n_score>1) diff_score,
  count(*) filter (where n_answer < n) tie_answer_ts
from (select order_id, count(*) n, count(distinct review_score) n_score, count(distinct review_answer_timestamp) n_answer
      from raw.order_reviews group by 1 having count(*)>1) x;
\echo == A2 review_score values & answer before creation
select review_score, count(*) from raw.order_reviews group by 1 order by 1;
select count(*) filter (where review_answer_timestamp::timestamp < review_creation_date::timestamp) answer_before_create from raw.order_reviews;
\echo == A2 review_id gắn nhiều đơn: các trường có khác nhau không (0 = giống hệt), cùng 1 khách?
select count(*) review_ids,
  count(*) filter (where n_score>1) diff_score, count(*) filter (where n_msg>1) diff_msg,
  count(*) filter (where n_created>1) diff_created, count(*) filter (where n_answer>1) diff_answer,
  count(*) filter (where n_cust=1) same_customer_unique
from (select r.review_id, count(distinct review_score) n_score, count(distinct review_comment_message) n_msg,
        count(distinct review_creation_date) n_created, count(distinct review_answer_timestamp) n_answer,
        count(distinct c.customer_unique_id) n_cust
      from raw.order_reviews r join raw.orders o using(order_id) join raw.customers c using(customer_id)
      group by 1 having count(distinct r.order_id)>1) x;
\echo == A2 review tạo trước ngày mua
select count(*) from raw.order_reviews r join raw.orders o using(order_id) where r.review_creation_date::timestamp < o.order_purchase_timestamp::timestamp::date;

\echo == A3 points per zip
select percentile_cont(array[0.5,0.9,0.99]) within group (order by n) pctl, max(n) from (select geolocation_zip_code_prefix, count(*) n from raw.geolocation group by 1) x;
\echo == A3 exact duplicate rows
select count(*) - count(distinct (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state)) exact_dups from raw.geolocation;
\echo == A3 outside Brazil bbox (lat -34..5.5, lng -74..-34)
select count(*) rows_out, count(distinct geolocation_zip_code_prefix) zips_out from raw.geolocation
 where not (geolocation_lat::numeric between -34 and 5.5 and geolocation_lng::numeric between -74 and -34);
\echo == A3 zips whose ALL points are outside bbox
select count(*) from (select geolocation_zip_code_prefix from raw.geolocation group by 1
 having bool_and(not (geolocation_lat::numeric between -34 and 5.5 and geolocation_lng::numeric between -74 and -34))) x;
\echo == A3 zip with >1 state
select count(*) from (select geolocation_zip_code_prefix from raw.geolocation group by 1 having count(distinct geolocation_state)>1) x;
\echo == A3 cách viết city: thô vs chuẩn hoá (lower + unaccent)
select count(distinct geolocation_city) raw_cities,
       count(distinct lower(unaccent(trim(geolocation_city)))) norm_cities,
       count(*) filter (where geolocation_city <> unaccent(geolocation_city)) rows_with_accent,
       count(*) filter (where geolocation_city ~ '[A-Z]') rows_upper,
       count(*) filter (where geolocation_city ~ '[^a-zA-Z0-9 \-''çãõáéíóúâêôàüÇÃÕÁÉÍÓÚÂÊÔÀÜ]') rows_odd_chars
from raw.geolocation;
\echo == A3 zip with >1 normalized city
select count(*) from (select geolocation_zip_code_prefix from raw.geolocation group by 1 having count(distinct lower(unaccent(trim(geolocation_city))))>1) x;
\echo == A3 odd city examples
select geolocation_city, count(*) from raw.geolocation where geolocation_city ~ '[^a-zA-Z0-9 \-''çãõáéíóúâêôàüÇÃÕÁÉÍÓÚÂÊÔÀÜ]' group by 1 order by 2 desc limit 12;
\echo == A3 accent examples sao paulo
select geolocation_city, count(*) from raw.geolocation where lower(unaccent(geolocation_city)) like 'sao paulo%' group by 1 order by 2 desc;
\echo == A3 customers/sellers zip coverage in geolocation, accents
with gz as (select distinct geolocation_zip_code_prefix zip from raw.geolocation)
select 'cust' t, count(*) filter (where customer_city <> unaccent(customer_city)) accent_rows,
  count(distinct customer_zip_code_prefix) filter (where gz.zip is null) zip_missing_geo,
  count(*) filter (where gz.zip is null) rows_missing_geo, count(distinct customer_zip_code_prefix) zips
from raw.customers c left join gz on gz.zip=c.customer_zip_code_prefix
union all
select 'sell', count(*) filter (where seller_city <> unaccent(seller_city)),
  count(distinct seller_zip_code_prefix) filter (where gz.zip is null), count(*) filter (where gz.zip is null), count(distinct seller_zip_code_prefix)
from raw.sellers s left join gz on gz.zip=s.seller_zip_code_prefix;
\echo == A3 seller/customer city odd values
select seller_city, count(*) from raw.sellers where seller_city ~ '[^a-z \-''çãõáéíóúâêôàü]' group by 1 order by 2 desc limit 15;
select count(*) from raw.customers where customer_city ~ '[^a-z \-''çãõáéíóúâêôàü]';
\echo == A3 customer/seller state vs geolocation state of the zip
with gs as (select geolocation_zip_code_prefix zip, mode() within group (order by geolocation_state) st from raw.geolocation group by 1)
select (select count(*) from raw.customers c join gs on gs.zip=c.customer_zip_code_prefix where gs.st<>c.customer_state) cust_state_mismatch,
       (select count(*) from raw.sellers s join gs on gs.zip=s.seller_zip_code_prefix where gs.st<>s.seller_state) sell_state_mismatch;
\echo == A3 the 5 zips entirely outside Brazil
select geolocation_zip_code_prefix, min(geolocation_state), round(avg(geolocation_lat::numeric),2) lat, round(avg(geolocation_lng::numeric),2) lng, count(*)
from raw.geolocation group by 1
having bool_and(not (geolocation_lat::numeric between -34 and 5.5 and geolocation_lng::numeric between -74 and -34));

\echo == A4 products without category: items & GMV share
select count(distinct p.product_id) products, count(*) items, round(100.0*count(*)/(select count(*) from raw.order_items),2) pct_items,
  round(sum(i.price::numeric)) gmv, round(100*sum(i.price::numeric)/(select sum(price::numeric) from raw.order_items),2) pct_gmv
from raw.products p join raw.order_items i using(product_id) where p.product_category_name is null;
\echo == A4 untranslated categories: products & items
select p.product_category_name, count(distinct p.product_id) products, count(*) items
from raw.products p join raw.order_items i using(product_id)
where p.product_category_name in ('pc_gamer','portateis_cozinha_e_preparadores_de_alimentos') group by 1;
\echo == A4 category trong raw chưa có trong seed category_group (đối chiếu sau khi dbt seed)
-- select distinct product_category_name from raw.products p
--  where product_category_name is not null and not exists (select 1 from stg.category_group g where g.product_category_name = p.product_category_name);

\echo == A5 item_total vs payment_value per order
create temp table d as
with i as (select order_id, sum(price::numeric + freight_value::numeric) item_total from raw.order_items group by 1),
     p as (select order_id, sum(payment_value::numeric) paid, bool_or(payment_type='voucher') has_voucher, max(payment_installments::int) inst from raw.order_payments group by 1)
select o.order_id, o.order_status, i.item_total, p.paid, p.paid - i.item_total diff, p.has_voucher, p.inst
from raw.orders o join i using(order_id) join p using(order_id);
select count(*) orders,
  count(*) filter (where abs(diff) <= 0.01) le_001,
  count(*) filter (where abs(diff) > 0.01) gt_001,
  count(*) filter (where abs(diff) > 1) gt_1,
  count(*) filter (where abs(diff) > 5) gt_5,
  count(*) filter (where abs(diff) > 0.01 and abs(diff) <= 0.05*item_total) le_5pct,
  count(*) filter (where abs(diff) > 0.05*item_total) gt_5pct,
  count(*) filter (where diff > 0.01) paid_more, count(*) filter (where diff < -0.01) paid_less
from d;
\echo == A5 percentiles of abs diff among mismatched
select percentile_cont(array[0.5,0.9,0.95,0.99]) within group (order by abs(diff)) p, max(abs(diff)) from d where abs(diff) > 0.01;
\echo == A5 mismatches by installments>1 / voucher
select inst > 1 instalment, has_voucher, count(*) n, count(*) filter (where abs(diff)>0.01) mismatched, round(avg(diff) filter (where abs(diff)>0.01),2) avg_diff
from d group by 1,2 order by 1,2;
\echo == A5 ratio paid/item_total for instalment mismatches
select percentile_cont(array[0.5,0.9,0.99]) within group (order by paid/item_total) from d where diff > 0.01 and inst > 1;
\echo == A5 totals
select sum(item_total) items, sum(paid) paid, round(100*(sum(paid)-sum(item_total))/sum(item_total),3) pct from d;
\echo == A5 orders paid less (examples)
select order_status, item_total, paid, diff, has_voucher, inst from d where diff < -1 order by diff limit 8;
select count(*) filter (where diff < -0.01) paid_less, count(*) filter (where diff < -0.01 and has_voucher) paid_less_voucher from d;

\echo == A6 closed_deals seller match & sales after won
with sel as (select seller_id, min(o.order_purchase_timestamp::timestamp) first_sale, max(o.order_purchase_timestamp::timestamp) last_sale
             from raw.order_items i join raw.orders o using(order_id) group by 1)
select count(*) deals,
  count(*) filter (where s.seller_id is not null) in_sellers,
  count(*) filter (where sel.first_sale is not null) has_sales,
  count(*) filter (where sel.first_sale < d.won_date::timestamp) sold_before_won,
  count(*) filter (where sel.first_sale >= d.won_date::timestamp) first_sale_after_won,
  count(*) filter (where sel.first_sale is not null and d.won_date::timestamp + interval '90 day' <= '2018-08-31') full_90d_window_has_sales,
  count(*) filter (where d.won_date::timestamp + interval '90 day' <= '2018-08-31') full_90d_window
from raw.closed_deals d left join raw.sellers s using(seller_id) left join sel using(seller_id);
\echo == A6 gmv_first_90_days for deals with sales
with g as (select d.mql_id, sum(i.price::numeric) gmv90
  from raw.closed_deals d join raw.order_items i using(seller_id) join raw.orders o using(order_id)
  where o.order_purchase_timestamp::timestamp >= d.won_date::timestamp and o.order_purchase_timestamp::timestamp < d.won_date::timestamp + interval '90 day' group by 1)
select count(*) deals_with_gmv90, round(percentile_cont(0.5) within group (order by gmv90)) median, round(sum(gmv90)) total from g;
\echo == A6 days from won to first sale
with sel as (select seller_id, min(o.order_purchase_timestamp::timestamp) first_sale from raw.order_items i join raw.orders o using(order_id) group by 1)
select percentile_cont(array[0.1,0.5,0.9]) within group (order by extract(epoch from first_sale - won_date::timestamp)/86400) days
from raw.closed_deals d join sel using(seller_id);
\echo == A6 won by month & mql by origin with conversion
select left(won_date,7) m, count(*) from raw.closed_deals group by 1 order by 1;
select coalesce(m.origin,'(null)') origin, count(*) mql, count(d.mql_id) won, round(100.0*count(d.mql_id)/count(*),1) conv
from raw.mql m left join raw.closed_deals d using(mql_id) group by 1 order by 2 desc;
\echo == A6 profile only for won leads? (mql has no profile columns) ; closed_deals categorical values
select business_segment is null bs_null, lead_type, count(*) from raw.closed_deals group by 1,2 order by 3 desc limit 10;
select has_company, has_gtin, count(*) from raw.closed_deals group by 1,2;
select count(*) filter (where won_date::timestamp < m.first_contact_date::timestamp) won_before_contact from raw.closed_deals d join raw.mql m using(mql_id);
select percentile_cont(array[0.1,0.5,0.9]) within group (order by won_date::date - first_contact_date::date) days_to_close from raw.closed_deals d join raw.mql m using(mql_id);
select count(*) filter (where declared_monthly_revenue::numeric = 0) rev_zero, count(*) filter (where declared_monthly_revenue::numeric > 0) rev_pos from raw.closed_deals;

\echo == A7 repeat customers (all orders / counts_as_sale / in window)
with o as (select c.customer_unique_id cu, o.order_id, o.order_status, o.order_purchase_timestamp ts
           from raw.orders o join raw.customers c using(customer_id))
select 'all' scope, count(distinct cu) customers, count(*) filter (where n>=2) repeat, round(100.0*count(*) filter (where n>=2)/count(*),2) pct, max(n)
  from (select cu, count(*) n from o group by 1) x
union all
select 'sale', count(*), count(*) filter (where n>=2), round(100.0*count(*) filter (where n>=2)/count(*),2), max(n)
  from (select cu, count(*) n from o where order_status not in ('canceled','unavailable') group by 1) x
union all
select 'sale_window', count(*), count(*) filter (where n>=2), round(100.0*count(*) filter (where n>=2)/count(*),2), max(n)
  from (select cu, count(*) n from o where order_status not in ('canceled','unavailable') and ts >= '2017-01-01' and ts < '2018-09-01' group by 1) x;
\echo == A7 distribution of orders per customer (sale)
with o as (select c.customer_unique_id cu, count(*) n from raw.orders o join raw.customers c using(customer_id) where o.order_status not in ('canceled','unavailable') group by 1)
select least(n,5) n_orders, count(*) from o group by 1 order by 1;
\echo == A7 repeat on same day (likely split orders)
with o as (select c.customer_unique_id cu, o.order_purchase_timestamp::date d from raw.orders o join raw.customers c using(customer_id) where o.order_status not in ('canceled','unavailable'))
select count(*) filter (where days>=2) repeat_distinct_days from (select cu, count(distinct d) days from o group by 1) x;
\echo == A8 orders per month
select left(order_purchase_timestamp,7) ym, count(*) n,
  count(*) filter (where order_status='delivered') delivered from raw.orders group by 1 order by 1;
\echo == A8 share inside window
select count(*) filter (where order_purchase_timestamp >= '2017-01-01' and order_purchase_timestamp < '2018-09-01') inside, count(*) total from raw.orders;
\echo == A8 delivery status for orders bought in last months (estimated date coverage)
select left(order_purchase_timestamp,7) ym, count(*) n, count(*) filter (where order_status='delivered') delivered,
  count(*) filter (where order_status in ('shipped','invoiced','processing','approved','created')) open
from raw.orders where order_purchase_timestamp >= '2018-06' group by 1 order by 1;
\echo == A9 zip prefix length & leading zero
select 'cust' t, count(*) filter (where customer_zip_code_prefix like '0%') leading0, min(customer_zip_code_prefix), max(length(customer_zip_code_prefix)), min(length(customer_zip_code_prefix)) from raw.customers
union all select 'sell', count(*) filter (where seller_zip_code_prefix like '0%'), min(seller_zip_code_prefix), max(length(seller_zip_code_prefix)), min(length(seller_zip_code_prefix)) from raw.sellers
union all select 'geo', count(*) filter (where geolocation_zip_code_prefix like '0%'), min(geolocation_zip_code_prefix), max(length(geolocation_zip_code_prefix)), min(length(geolocation_zip_code_prefix)) from raw.geolocation;
