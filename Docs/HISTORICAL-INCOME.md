# Historical income reconstruction

This is a local, explicitly confirmed reconstruction, not proof of payment from
calendar presence. No external calendar or actual user ledger is bundled in tests.

## Two distinct clocks

`IncomeEntry.date` is the activity date. `Payment.date` is the receipt date and
can now be absent; `receivedYear` then records only the confirmed receipt year.
Legacy dated payments decode unchanged. A receipt without either date or year,
or with inconsistent date/year, is rejected. Daily/monthly charts and daily
reports exclude undated receipts. Annual totals include the confirmed year.
Exports label the missing date, never manufacture January 1 or the lesson day.

## Confirmation and duplicate safety

The Core quotes a selected past work/tutoring occurrence using a user-confirmed
contact and its tariff. No age, neighborhood or name-based rate inference.
Rates and duration are frozen in the preview and rechecked against fresh calendar
events and current contacts before commit. All-day, future, cross-year, non-work,
invalid and >8-hour occurrences are rejected. A work-calendar meeting is not
automatically selected as a paid lesson.

Existing income IDs, calendar links, diary snapshots and historical provenance
prevent duplicate imports. Explicit skipped/partial/running answers, manually
recorded times, same-day unlinked income and possible combined weekly payments
require review rather than being overwritten. Repeating a confirmed identical
batch is a no-op. A changed source or tariff rejects the whole batch atomically.

## Opening aggregate and budget

Capture the savings opening funds before any reclassification. In chronological
order, consume at most the remaining annual opening aggregate for each imported
receipt. The receipt itself always has the full tariff × duration amount; only
its attribution to the former aggregate can be partial. Excess historical income
increases annual reporting, not available savings funds. Every imported receipt
is budget-excluded. Existing unpaid entries and normal receipts are untouched.
Independent notes/ratings remain; no actual stopwatch times are invented.

The batch is schema-validated before assignment. A missing/ambiguous identity,
calendar conflict or invalid backup leaves the original AppData untouched.
Source provenance is preserved locally for audit. Importing must remain behind
a native local review/confirmation, not run automatically when opening Pivot.
