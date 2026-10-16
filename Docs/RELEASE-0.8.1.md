# Pivot 0.8.1 — release candidate scope

Prepared source, not evidence that the IPA or hardware checks have passed.
Build 23 continues Serie 8; it is not a new major objective or all of Serie 8.

## Included

- Explicit online request review, minimized known contacts/locations and no
  automatic Health-derived statuses or unprovenanced memories in cloud context.
- Password-confirmed portable encrypted backups, no plaintext fallback, legacy
  copies preserved and imported Health/profile/rank data excluded before export.
- Manual savings goals/reservations, real expense corrections and visible
  shortfalls; annual historical earnings do not automatically become cash funds.
- Confirmed calendar history import with rates, duplicate/conflict checks,
  opening-aggregate attribution and unknown receipt dates kept unknown.
- General contacts and activity types, separate compensation/receipt/residual,
  partial receipt entry, contact month/year/all reporting and complete history.
- Existing email corrections retained: editable receipts/compensation, explicit
  profile merging, recovery visibility/minimization, next-set details and gold
  record rows without replacing the series labels.

## Required gates before distribution

Full Core, offline gateway and Python tests; targeted UI and full iPhone simulator
regression without skips; Release build and package signature verification;
manifest/hash/bundle/widget/entitlement inspection on the actual resulting IPA.
The package is a sideload candidate and still requires the user's existing
AltStore signing procedure. Never bundle AI credentials or user fixtures.

The full simulator suite includes the four protected-QR tests and the three
modern-UI regression paths. They run once within that complete suite, not again
in duplicate preliminary builds. A separate three-case diagnostic run covers
the last observed income-history, carousel and composer visibility failures;
passing that subset alone never authorizes packaging.

Do not replace the installed 0.8.0 or previous archived releases until the new
artifact is verified. Preserve existing backups and training documents. No real
calendar/ledger migration takes place on the development computer.

## Not claimed

No automatic clinical judgments, taxes/contracts, bank syncing, investments,
FitPros synchronization or all-day/multiday travel-aware AI scheduling. No
guarantee of semantic anonymization of unknown sensitive prose. Separate exports
are not automatically encrypted. Older plaintext backups are not retroactively
encrypted. Historical month graphs need actual receipt dates, not guesses.

AlarmKit speaker/music-interruption feedback from the physical experiment does
not prove automatic recovery integration or guaranteed two-second stop while
locked. The independent opt-in experiment remains distinct. Real AI activation
is a supervised user-present step after installing a verified candidate.
