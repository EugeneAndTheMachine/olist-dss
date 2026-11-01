with source as (
    select * from {{ source('raw', 'order_payments') }}
),

deduped as (
    select
        *,
        row_number() over (partition by order_id, payment_sequential order by _loaded_at desc) as _rn
    from source
),

typed as (
    select
        {{ clean_text('order_id') }} as order_id,
        {{ clean_text('payment_sequential') }}::int as payment_sequential,
        lower({{ clean_text('payment_type') }}) as payment_type,
        {{ clean_text('payment_installments') }}::int as payment_installments_raw,
        {{ clean_text('payment_value') }}::numeric(12, 2) as payment_value,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
),

final as (
    select
        order_id,
        payment_sequential,
        -- S1: 3 dòng not_defined (đơn canceled, value 0) — giữ nguyên như 1 payment_type
        coalesce(payment_type, 'not_defined') as payment_type,
        -- S1: 2 dòng installments = 0 (credit_card, delivered) → 1 kỳ
        greatest(coalesce(payment_installments_raw, 1), 1) as payment_installments,
        payment_value,
        case
            when payment_installments_raw is null or payment_installments_raw < 1 then 'installments_fixed_to_1'
        end as _dq_issue,
        _batch_id,
        _loaded_at
    from typed
)

select * from final
