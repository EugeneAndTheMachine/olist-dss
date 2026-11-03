select
    payment_type_key,
    payment_type as "Payment Type",
    instalment_band as "Instalment Band",
    instalment_band_sort as "Instalment Band Sort",
    is_instalment as "Is Instalment"
from {{ ref('dim_payment_type') }}
