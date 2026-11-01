with source as (
    select * from {{ source('raw', 'br_states') }}
),

deduped as (
    select
        *,
        row_number() over (partition by upper(trim(state_code)) order by _loaded_at desc) as _rn
    from source
)

select
    {{ state_code('state_code') }} as state_code,
    {{ clean_text('state_name') }} as state_name,
    {{ clean_text('region_name') }} as region_name
from deduped
where _rn = 1
