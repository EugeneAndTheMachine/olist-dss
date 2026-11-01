{#-
    Junk dimension: payment_type × instalment_band (seed). Sinh đủ mọi tổ hợp để fact_payment luôn tra được.
-#}
with payment_types as (
    select distinct payment_type
    from {{ ref('stg_order_payments') }}
),

bands as (
    select
        instalment_band,
        min_instalments,
        max_instalments,
        is_instalment,
        sort_order
    from {{ ref('instalment_band') }}
),

final as (
    select
        {{ int_sk(['p.payment_type', 'b.instalment_band']) }} as payment_type_key,
        p.payment_type,
        b.instalment_band,
        b.min_instalments,
        b.max_instalments,
        b.is_instalment,
        b.sort_order as instalment_band_sort
    from payment_types as p
    cross join bands as b

    union all

    select
        {{ unknown_key() }},
        'unknown',
        'unknown',
        null::int,
        null::int,
        false,
        99
)

select * from final
