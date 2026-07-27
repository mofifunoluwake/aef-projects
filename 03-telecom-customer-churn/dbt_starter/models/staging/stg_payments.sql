with source as (
    select * from {{ source("raw", "raw_payments") }}
),
ranked as (
    select *,
        row_number() over (
            partition by subscriber_id, billing_period
            order by case payment_status when 'paid' then 3 when 'past_due' then 2 else 1 end desc,
                     coalesce(paid_at, due_at) desc
        ) as rn
    from source
)
select payment_id, subscriber_id, billing_period, amount_due, payment_status,
       payment_method, due_at, paid_at
from ranked
where rn = 1
