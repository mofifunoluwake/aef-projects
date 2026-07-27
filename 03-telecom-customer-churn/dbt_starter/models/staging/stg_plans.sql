select plan_code, plan_type, monthly_recurring_charge, data_allowance_gb, contract_months
from {{ source("raw", "raw_plans") }}
