with source as (
    select * from {{ source('raw', 'calendar_events') }}
),

deduped as (
    select
        *,
        row_number() over (partition by event_date, event_name order by _loaded_at desc) as _rn
    from source
)

select
    {{ clean_text('event_date') }}::date as event_date,
    {{ clean_text('event_name') }} as event_name,
    lower({{ clean_text('event_type') }}) as event_type
from deduped
where _rn = 1
