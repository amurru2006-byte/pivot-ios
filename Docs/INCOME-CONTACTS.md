# Income contacts and per-contact reporting

Existing contacts and income default to hourly tutoring. Optional activity/billing
metadata allow work, gifts/contributions and other income without bank syncing,
portfolio valuation, contract interpretation or invented tax deductions.

New manual income captures the activity type, billing mode, compensation and
actual receipt independently. An hourly activity requires 1–480 minutes; a gift
or fixed-price job stores zero minutes rather than inventing working hours.
The real payment date is selected separately from the activity date. A partial
receipt leaves the exact outstanding amount. No receipt exists for an unpaid
activity. A stable confirmation UUID prevents duplicate taps from creating money.
Validation is atomic, including contact/tariff changes and backup consistency.
Changing a contact's defaults never reprices or reclassifies existing income.
The activity type can also be overridden for one record without changing the
contact default, so the same person can pay for work and separately give a gift.

Per-contact receipts are selected by linked income/client UUIDs, never by display
name. The overview offers month/year/all receipts, a yearly monthly chart, and
an always-unfiltered outstanding amount for that contact. Full activity history
and Add lesson/activity remain independent from the receipt period selector.
Unknown receipt dates stay in annual/all totals, not a guessed month. Unassigned
opening aggregates are never distributed between contacts for presentation.

The native overview uses the existing green gradient, rounded cards, typography
and separate page controls; the general contact terminology is an extension of
the register rather than a redesign. Work contracts/taxes remain a future scoped
feature requiring real terms and verified professional guidance. No financial,
health, calendar or identity data is included in the public QA fixtures.
