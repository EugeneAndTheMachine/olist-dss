-- Các version của cùng seller không chồng lấn và valid_from <= valid_to (implementation.md mục 10). Trả dòng = lỗi.
select
    a.seller_id,
    a.valid_from as a_valid_from,
    a.valid_to as a_valid_to,
    b.valid_from as b_valid_from,
    b.valid_to as b_valid_to
from {{ ref('dim_seller') }} as a
inner join {{ ref('dim_seller') }} as b
    on a.seller_id = b.seller_id
    and a.seller_key <> b.seller_key
    and a.valid_from <= b.valid_to
    and b.valid_from <= a.valid_to

union all

select seller_id, valid_from, valid_to, null, null
from {{ ref('dim_seller') }}
where valid_from > valid_to
