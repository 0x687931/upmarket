# ADR 0003: Pack Credit Accounting

## Status

Accepted

## Context

Upmarket sells Basic and Pro as non-consumable unlocks and a small document pack as a StoreKit consumable. The old pack balance stored remaining paid credits directly in `UserDefaults`, which made the client balance authoritative and hard to reconcile for support, interrupted purchases, duplicate transaction delivery, or refunds.

StoreKit consumables are not restorable in the same way as non-consumables. A server ledger would be the strongest accounting model, but v1 is a private, on-device Mac app and does not otherwise require an account or backend.

## Decision

Keep v1 serverless, but make the local app derive pack balance from a small ledger:

- Only verified StoreKit transactions can add pack credits.
- Transaction IDs are recorded once so duplicate purchase callbacks do not double-credit.
- Credit consumption records debits instead of mutating a remaining-balance counter.
- Revoked StoreKit transactions are recorded and remove remaining credits.
- StoreKit consumable transactions are finished only after the ledger write succeeds.
- Legacy `UserDefaults` pack balances are migrated once into the ledger before the old keys are removed.
- `UserDefaults` remains acceptable for free trial counters and UI preferences, but not paid pack credit balances.

The ledger is not an anti-tamper system. It is an audit trail for a single-device, pre-account v1 that avoids accidental double-crediting and makes support behavior explainable.

## Consequences

Users can still use Upmarket offline after purchase because no server call is required for conversion. If paid packs become material revenue, cross-device restore becomes a requirement, or refund abuse becomes a real support issue, replace the local ledger with App Store Server API or a minimal backend ledger before expanding the pack model.

## Release Gate

Before release, StoreKit testing must cover successful pack purchase, duplicate transaction delivery, pending or interrupted purchase, non-consumable restore, and revoked/refunded transaction behavior. Consumable pack restore must be described as unsupported by StoreKit unless a backend ledger is added.
