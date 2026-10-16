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
Source provenance and the original imported receipt ID are preserved locally for
audit. Correcting that receipt never turns it into spendable money; a different,
later genuine receipt can still fund the budget. Older Pivot releases that require
an exact receipt date cannot read year-only receipts; preserve pre-upgrade backups
instead of promising backward compatibility with the old application binary.

## Native entry point and checks

Entrate → Recupera dal calendario queries the selected calendars for the chosen
year in the existing EventKit actor, separately from the home agenda. It never
changes events or broadens the routine agenda fetch. Excluded calendars remain
excluded. Each row shows the calendar title/date/duration, contact and tariff;
unknown contacts can be added through the existing contact form. Selection is
explicit, including a select-ready convenience action. Conflicts stay unselected.

The confirmation shows full reconstructed receipts, the share already in the
opening aggregate, and the resulting annual total. The user must confirm that
the selected lessons were actually held and paid in the chosen year. The receipt
day stays unknown. Cancel/background causes no ledger write. Final confirmation
reads EventKit again, validates source/rates against the current AppData, and
refuses a changed preview rather than silently changing the accepted amounts.
Expensive preview/commit validation runs off the UI thread; only a validated,
revision-matched snapshot is assigned back to the store. New native interaction
coverage uses a unique Debug-simulator-only synthetic storage namespace.
