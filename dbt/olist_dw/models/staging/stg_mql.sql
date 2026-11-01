with source as (
    select * from {{ source('raw', 'mql') }}
),

deduped as (
    select
        *,
        row_number() over (partition by mql_id order by _loaded_at desc) as _rn
    from source
)

select
    {{ clean_text('mql_id') }} as mql_id,
    {{ clean_text('first_contact_date') }}::date as first_contact_date,
    {{ clean_text('landing_page_id') }} as landing_page_id,
    -- S1 (A6): 60 lead origin null → gộp vào 'unknown' (đã có 1 099 lead 'unknown' trong nguồn)
    coalesce(lower({{ clean_text('origin') }}), 'unknown') as origin,
    _batch_id,
    _loaded_at::timestamptz as _loaded_at
from deduped
where _rn = 1
