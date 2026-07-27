select ticket_id, subscriber_id, category, channel, opened_at, resolved_at,
       case when resolved_at is null then true else false end as is_unresolved
from {{ source("raw", "raw_support_tickets") }}
