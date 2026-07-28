# Business Metric Definitions — E-Commerce Revenue Leakage

Each metric has one definition. Where the definition involves a judgment call, the
rationale is noted. All monetary values are in USD (GBP×1.27, EUR×1.08 fixed).

| Metric | Definition | Model / Column | Notes |
|---|---|---|---|
| **Gross bookings** | Sum of order_amount_usd across all orders, all statuses | mart_monthly_revenue.gross_bookings_usd | Finance's most optimistic figure. Includes unpaid + cancelled. |
| **Net revenue** | Deduped captured cash minus refunds | mart_monthly_revenue.net_revenue_usd | The bottom line. Ties to raw ledger at $615,917.65. |
| **Captured cash** | Sum of deduped succeeded payments | mart_monthly_revenue.captured_cash_usd | Only is_primary_record = true counts. |
| **Recognized revenue** | Net revenue for orders with a successful payment and not fully refunded | mart_revenue.net_revenue_usd (revenue_classification = 'recognized') | The defensible "real" revenue. |
| **Cancellation leakage** | order_amount of paid-but-cancelled orders | mart_monthly_revenue.paid_but_cancelled_usd | Cash collected against orders later cancelled — pending liability. |
| **Duplicate charge exposure** | order_amount of orders with 2+ succeeded payments | mart_monthly_revenue.duplicate_charge_exposure_usd | 121 orders. Would inflate cash if not deduped. |
| **Refunds** | Sum of refund_amount_usd | mart_monthly_revenue.refunds_usd | ~$54,500. 48% cross a month boundary. |
| **Bookings-to-net gap** | Gross bookings minus net revenue | mart_monthly_revenue.bookings_to_net_gap_usd | 17–23% monthly. The full reconciliation spread. |
| **Reporting currency** | USD | all _usd columns | GBP×1.27, EUR×1.08, fixed sprint rates. |

## Definitional contract

- **Revenue is recognized at successful payment, not at order or ship.** Ship dates are
  unreliable (637 null timestamps), so payment is the recognition event.
- **"Completed" ≠ recognized.** Order status is unreliable (43 cancelled orders shipped);
  a real transaction requires a successful payment and no full refund.
- **Refunds net by actual amount.** Partial refunds (334 of 979) subtract their real value,
  never the full order.
- **The 8–12% board figure is one slice of the wider bookings-to-net bridge**, not a
  competing total. Both Finance's and Ops' numbers sit inside the bridge.