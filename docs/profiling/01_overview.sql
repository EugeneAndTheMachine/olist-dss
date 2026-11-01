-- S1 profiling — Phần 1: Tổng quan nguồn (schema raw, mọi cột text).
-- Chạy: docker compose exec -T postgres psql -U olist -d olist_dw < docs/profiling/01_overview.sql
-- Kết quả tóm tắt trong docs/profiling.md, mục "Tổng quan nguồn".

-- 1. Số dòng, số khoá phân biệt (k1, k2), khoảng thời gian theo bảng
select 'orders' t, count(*) n, count(distinct order_id) k1, count(distinct customer_id) k2,
  min(order_purchase_timestamp) dmin, max(order_purchase_timestamp) dmax from raw.orders
union all select 'order_items', count(*), count(distinct (order_id, order_item_id)), count(distinct order_id),
  min(shipping_limit_date), max(shipping_limit_date) from raw.order_items
union all select 'order_payments', count(*), count(distinct (order_id, payment_sequential)), count(distinct order_id), null, null from raw.order_payments
union all select 'order_reviews', count(*), count(distinct review_id), count(distinct order_id),
  min(review_creation_date), max(review_creation_date) from raw.order_reviews
union all select 'customers', count(*), count(distinct customer_id), count(distinct customer_unique_id), null, null from raw.customers
union all select 'sellers', count(*), count(distinct seller_id), count(distinct seller_zip_code_prefix), null, null from raw.sellers
union all select 'products', count(*), count(distinct product_id), count(distinct product_category_name), null, null from raw.products
union all select 'geolocation', count(*), count(distinct geolocation_zip_code_prefix), count(distinct (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state)), null, null from raw.geolocation
union all select 'translation', count(*), count(distinct product_category_name), count(distinct product_category_name_english), null, null from raw.product_category_name_translation
union all select 'mql', count(*), count(distinct mql_id), count(distinct origin), min(first_contact_date), max(first_contact_date) from raw.mql
union all select 'closed_deals', count(*), count(distinct mql_id), count(distinct seller_id), min(won_date), max(won_date) from raw.closed_deals
union all select 'br_holidays', count(*), count(distinct holiday_date), null, min(holiday_date), max(holiday_date) from raw.br_holidays
union all select 'br_states', count(*), count(distinct state_code), count(distinct region_name), null, null from raw.br_states
union all select 'calendar_events', count(*), count(distinct event_date), count(distinct event_type), min(event_date), max(event_date) from raw.calendar_events;

-- 2. Khoảng thời gian các mốc khác của orders, reviews
-- các cột ngày khác của orders
select min(order_approved_at), max(order_approved_at), min(order_delivered_carrier_date), max(order_delivered_carrier_date),
 min(order_delivered_customer_date), max(order_delivered_customer_date), min(order_estimated_delivery_date), max(order_estimated_delivery_date) from raw.orders;
select min(review_answer_timestamp), max(review_answer_timestamp) from raw.order_reviews;

-- 3. Đơn theo năm; các tháng đầu/cuối thưa
select left(order_purchase_timestamp,4) y, count(*) from raw.orders group by 1 order by 1;
select left(order_purchase_timestamp,7) ym, count(*) from raw.orders where order_purchase_timestamp < '2017-01' or order_purchase_timestamp >= '2018-08' group by 1 order by 1;

-- 4. Review trùng, đơn thiếu item/payment/review, category thiếu bản dịch, funnel
select count(*) filter (where c>1) review_id_multi_order from (select review_id, count(*) c from raw.order_reviews group by 1) x;
select count(*) filter (where c>1) order_multi_review from (select order_id, count(*) c from raw.order_reviews group by 1) x;
-- đơn không có item / payment / review
select (select count(*) from raw.orders o where not exists (select 1 from raw.order_items i where i.order_id=o.order_id)) no_item,
       (select count(*) from raw.orders o where not exists (select 1 from raw.order_payments p where p.order_id=o.order_id)) no_pay,
       (select count(*) from raw.orders o where not exists (select 1 from raw.order_reviews r where r.order_id=o.order_id)) no_review;
-- products: category không có trong translation
select distinct p.product_category_name from raw.products p left join raw.product_category_name_translation t using (product_category_name)
 where t.product_category_name is null and p.product_category_name <> '';
-- mql có khớp closed_deals; closed_deals seller khớp sellers
select count(*) filter (where m.mql_id is null) deals_no_mql,
       count(*) filter (where s.seller_id is not null) deals_seller_in_sellers from raw.closed_deals d
 left join raw.mql m using (mql_id) left join raw.sellers s using (seller_id);

-- 5. Ngoại lệ & bảng mồ côi
select count(*) filter (where shipping_limit_date >= '2019') items_ship_2019plus, min(shipping_limit_date) filter (where shipping_limit_date >= '2019') from raw.order_items;
select count(*) from raw.order_items i where not exists (select 1 from raw.orders o where o.order_id=i.order_id);
select count(*) filter (where won_date > '2018-08-31') deals_after_aug18, count(*) filter (where won_date > '2018-10-17') deals_after_last_order from raw.closed_deals;
select count(*) from raw.customers c where not exists (select 1 from raw.orders o where o.customer_id=c.customer_id);
select count(distinct product_category_name) filter (where product_category_name<>'') cats from raw.products;
select count(*) from raw.product_category_name_translation t where not exists (select 1 from raw.products p where p.product_category_name=t.product_category_name);
select count(*) filter (where review_creation_date ~ '00:00:00$') rev_midnight, count(*) from raw.order_reviews;
select count(*) filter (where position(E'\n' in review_comment_message)>0) msg_newline from raw.order_reviews;
select count(*) filter (where order_estimated_delivery_date !~ '00:00:00$') est_with_time from raw.orders;
select (select count(*) from raw.sellers s where not exists (select 1 from raw.order_items i where i.seller_id=s.seller_id)) sellers_no_item,
       (select count(*) from raw.products p where not exists (select 1 from raw.order_items i where i.product_id=p.product_id)) products_no_item;

-- 6. Độ dài zip prefix, số bang, loại sự kiện
select 'cust' t, length(customer_zip_code_prefix) l, count(*) from raw.customers group by 1,2
union all select 'sell', length(seller_zip_code_prefix), count(*) from raw.sellers group by 1,2
union all select 'geo', length(geolocation_zip_code_prefix), count(*) from raw.geolocation group by 1,2 order by 1,2;
-- distinct states, mql origin values
select count(distinct customer_state) cust_states, (select count(distinct seller_state) from raw.sellers) seller_states,
  (select count(distinct geolocation_state) from raw.geolocation) geo_states from raw.customers;
select event_type, count(*) from raw.calendar_events group by 1;

-- 7. Số giá trị rỗng ('' hoặc null) theo cột
do $$
declare r record; n bigint;
begin
  for r in select table_name, column_name, ordinal_position from information_schema.columns
           where table_schema='raw' and column_name not like '\_%' order by table_name, ordinal_position loop
    execute format('select count(*) from raw.%I where nullif(trim(%I),'''') is null', r.table_name, r.column_name) into n;
    if n > 0 then raise notice '%|%|%', r.table_name, r.column_name, n; end if;
  end loop;
end $$;

-- 8. Mã bang không có trong br_states (kỳ vọng 0)
select 'cust' t, count(distinct customer_state) from raw.customers c where not exists (select 1 from raw.br_states b where b.state_code = c.customer_state)
union all select 'sell', count(distinct seller_state) from raw.sellers s where not exists (select 1 from raw.br_states b where b.state_code = s.seller_state)
union all select 'geo', count(distinct geolocation_state) from raw.geolocation g where not exists (select 1 from raw.br_states b where b.state_code = g.geolocation_state);
