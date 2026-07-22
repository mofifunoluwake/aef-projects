# Ride-Hailing Marketplace — Brief Notes & Assumptions Skeleton

Working reference pulled from `BRIEF.md`. Use this during profiling (Wed) and modeling
(Thu-Fri) - fill in the blanks as you make each decision. This is the seed for your
final `assumptions.md`, not the final version.

---

## The core tension

GMV (Growth's number, gross fares at request time) runs **8-12% higher** than net
revenue (Finance's number), every month, by an amount that moves around. The whole
engagement is explaining that gap with a defensible bridge - not making it disappear.

---

## Profiling findings by table
 
### RAW_RIDERS (3,750 rows)
- **RIDER_ID is a true primary key** - 3,750 distinct, zero duplicates.
- **Zero nulls** across all columns.
- **ACCOUNT_STATUS breakdown:** active 3,055 (81.5%), dormant 442 (11.8%), guest 135 (3.6%), suspended 118 (3.1%).
- The "active" flag is just "account not closed" per the Data Lead - NOT a usage signal. Real active-rider count will be lower once defined by trip history.
- **Cities roughly even:** metro_north 957, bayview 952, rivermouth 929, sunbelt 912.
- **Referral rate:** 25.2% (944 referred, 2,806 organic).
- **No issues found.** Clean table.


### RAW_DRIVERS (780 rows, but only 750 distinct drivers)
- **30 drivers have duplicate rows** (each appears exactly twice) due to DRIVER_ID reuse on re-onboarding. That is 4% of the driver base.
- This is the known issue the Data Lead flagged. Staging must collapse these to 1 row per driver (keep latest ONBOARDED_AT for current attributes, preserve both dates).
- **DRIVER_STATUS:** active 682 (87.4%), inactive 60 (7.7%), deactivated 38 (4.9%).
- **Zero nulls** across all columns.
- **Cities:** metro_north 214, bayview 199, rivermouth 198, sunbelt 169.
- **Vehicle class:** standard 378, xl 206, premium 196.
- **Ratings:** min 3.92, max 5.00, avg 4.68. All within expected 3.0-5.0 range.


### RAW_TRIPS (15,000 rows)
- **TRIP_ID is a true primary key** - 15,000 distinct.
- **Trip status:** completed 12,550 (83.7%), cancelled 2,450 (16.3%).
- **Cancellation reasons:** rider_cancel 1,031, no_driver_found 602, driver_cancel 495, rider_no_show 322.
- **Billed cancellations (fare > 0):**
  - rider_cancel: 584 billed (avg $5.61), 447 zero-fare
  - no_driver_found: ALL 602 are zero-fare (no service, no charge)
  - driver_cancel: 290 billed (avg $5.45), 205 zero-fare
  - rider_no_show: 182 billed (avg $5.71), 140 zero-fare
  - **Total: 1,056 cancelled trips still have a fare. 1,394 are zero-fare.**
- **Fraud:** 395 fraud-flagged trips (3.15%), ALL on completed trips, zero on cancelled.
- **Currency:** GBP 3,668 trips ($45,310.87 GMV), USD 11,332 trips ($140,880.24 GMV). GBP is ~24% of marketplace.
- **Cities:** metro_north 3,853, bayview 3,804, sunbelt 3,675, rivermouth 3,668. Rivermouth = GBP confirmed.
- **Nulls:** STARTED_AT and ENDED_AT are null on exactly the 2,450 cancelled trips. All other columns have zero nulls.


### RAW_PAYMENTS (14,773 rows)
- **PAYMENT_ID is unique** - 14,773 distinct.
- **Payment status:** captured 13,399 (90.7%), failed 1,374 (9.3%).
- **210 trips have duplicate captured payments** (2 successful captures each). These are the webhook double-logs the Data Lead suspected. Same TRIP_ID, same AMOUNT, different PAYMENT_ID. Must be deduped or revenue is double-counted.
- **1,775 trips have no payment row at all.** We know 1,394 cancellations are zero-fare (no charge expected), so ~381 trips with a fare have no payment record — possibly failed-only attempts or billing gaps.
- **Payment methods:** card 7,288, wallet 2,508, apple_pay 2,502, cash 2,475.
- **Currency:** USD 11,147 rows ($138,780.62 captured), GBP 3,626 rows ($44,821.24 captured).


### RAW_DRIVER_INCENTIVES (5,404 rows)
- **INCENTIVE_ID is unique** - 5,404 distinct.
- **1,213 trips have 2 incentive lines each** (qualified for 2 overlapping campaigns). 2,978 trips have 1 line. Total: 4,191 distinct trips with incentives.
- If you naively sum BONUS_AMOUNT per trip, the 1,213 double-campaign trips are double-attributed.
- **5 campaigns, evenly distributed:** quest_weekly 1,125 ($3,295.81), referral_bonus 1,052 ($3,288.26), consecutive_trips 1,080 ($3,202.28), surge_guarantee 1,094 ($3,199.46), peak_hour_boost 1,053 ($3,134.53).
- **169 incentive lines ($494.19) were paid on fraud-flagged trips.** Drivers got bonuses on trips later flagged as fraud. Per the brief, driver payouts are sacred - cannot silently restate.
- **Payout timing lag:** avg 10.8 days, min 3, max 37. Some bonuses cross month boundaries.
- **Currency:** USD 4,108 ($12,326.36), GBP 1,296 ($3,793.98).
- **Zero nulls** across all columns.
- **NOTE:** Timestamp corruption was found during initial load (Python 3.14 + Snowflake connector incompatibility). Fixed by reloading with string-formatted timestamps via fix_and_load.py. Log this as a data quality finding — in production, timestamp validation tests should catch this.
---


## The 5 definitional questions you must answer and defend

1. **What is an "active rider"?**
   Options: CRM flag / requested a trip / completed a trip / non-fraud completed only.
   Count swings 10-15% depending on choice.
   **My decision:** ___________________________________________
   **Why:** ___________________________________________

2. **How do cancelled trips count?**
   Is a billed cancellation revenue, a fee line, or leakage? Do zero-fare / no-driver-found
   cancellations belong in GMV at all?
   **My decision:** ___________________________________________
   **Why:** ___________________________________________

3. **How does fraud flow through revenue?**
   Flag lands after the trip. Does fraud reverse GMV? Is the driver's incentive on that
   trip clawed back - and in which period?
   **My decision:** ___________________________________________
   **Why:** ___________________________________________

4. **When is revenue recognized, and in what currency?**
   Trip-end vs. capture-time. The rivermouth market bills in GBP - convert, or scope to
   one reporting currency?
   **My decision:** ___________________________________________
   **Why:** ___________________________________________

5. **How do you dedupe** retried/duplicate captures and over-attributed incentive lines
   without double-counting cash or bonus spend?
   **My decision:** ___________________________________________
   **Why:** ___________________________________________

---

## Non-negotiables (ground rules from the brief)

- **Idempotent pipeline** - re-running it must produce the same marts.
- **Driver payouts are sacred** - a driver's paid incentive total must still reconcile
  to the payouts ledger after dedup. Surface the dedup; never silently restate what a
  driver was historically shown as paid.
- **Document the gap, don't hide it** - a model where the discrepancy vanishes without
  explanation has failed the engagement, even if the numbers look clean.

---

## Key numbers for the reconciliation bridge (rough estimate)
 
- **Total GMV (all gross fares):** ~$186,191 (140,880 USD + 45,311 GBP, pre-conversion)
- **Zero-fare cancellations:** 1,394 trips with $0 fare — inflate trip count but not GMV
- **Fraud GMV:** 395 trips at ~3.15% of completed — this amount is in GMV but arguably not revenue
- **Duplicate captures:** 210 trips charged twice — inflates captured revenue if not deduped
- **Incentive double-attribution:** 1,213 trips with 2 campaign lines — inflates incentive cost if naively summed
- **Fraud incentives:** $494.19 paid on fraud trips — cost that arguably shouldn't have been incurred

---

## Deliverables checklist (from Section 4 of the brief)

- [ ] Driver performance mart (1 row/driver, re-onboarding dedup handled)
- [ ] Rider activity mart (multi-definition active-rider model)
- [ ] Marketplace KPI layer (GMV, net revenue, take rate, completion rate, cancellation
      rate, fraud rate, incentive spend - each with a written definition)
- [ ] Reconciliation bridge (GMV to net revenue, line by line)
- [ ] Data quality framework (tests + severity + failure behavior)
- [ ] Orchestration DAG design (schedule, dependencies, freshness checks, alerting -
      design only, running DAG is a stretch goal)
- [ ] Architecture diagram
- [ ] Source-to-target map
- [ ] 10+ tests, 3+ business-rule
- [ ] Deck (8-12 slides)
