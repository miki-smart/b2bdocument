# Movello MVP - Settlement Processing Specification
## Settlement Triggers, Calculations & Workflows — As Implemented

**Version:** 2.0 (rewritten against running code)
**Last verified against code: 2026-07-23**
**Original version:** 1.0, dated December 22, 2025 — described a monthly-calendar cron job, a generic `Settlement`/`Debt` schema, grace-period/debt-escalation mechanics, and a three-tier (AUTO/MANAGER/ADMIN) approval ladder, none of which match the running system. Preserved only in git history.
**Ground truth files:** `Controllers/Finance/SettlementController.cs`, `Modules/Finance/Application/Settlement/Commands/{GenerateSettlementCommand,GenerateSettlementScheduleCommand,ApproveSettlementPayoutCommand,RejectSettlementPayoutCommand}*.cs`, `Modules/Finance/Domain/Entities/{SettlementCycle,SettlementPayout,SettlementPayoutLineItem,MonthlySettlementSchedule,SettlementStatusHistory}.cs`, `Modules/Finance/Application/Services/SettlementScheduleService.cs`
**Related documents:** [`project-docs/18_Implementation_Coverage_Audit.md`](../../../../project-docs/18_Implementation_Coverage_Audit.md) §2 (row 10), §6, §10.4; [`backlog/mvp/epic-10-monthly-renewal-settlement.md`](../../../../backlog/mvp/epic-10-monthly-renewal-settlement.md) (companion epic, rewritten the same date — this document expands on its Stories 10.2–10.6); [`backlog/mvp/epic-09-daily-ledger-billing.md`](../../../../backlog/mvp/epic-09-daily-ledger-billing.md) (provider-invoice/tax-reclaim flow this document's §7 depends on); [`backlog/mvp/epic-06-contract-management.md`](../../../../backlog/mvp/epic-06-contract-management.md) (delivery-driven settlement-schedule anchor point); [`MVP_MODULE_INTEGRATION_SPECIFICATION.md`](./MVP_MODULE_INTEGRATION_SPECIFICATION.md) §2.2 (Contracts↔Finance escrow integration); [`MVP_DISPUTE_RESOLUTION_WORKFLOW.md`](./MVP_DISPUTE_RESOLUTION_WORKFLOW.md) (confirms no settlement-dispute path exists); [`SETTLEMENT_ENHANCEMENTS_ADDENDUM.md`](./SETTLEMENT_ENHANCEMENTS_ADDENDUM.md) (should itself be re-verified against this rewrite before being trusted — not re-verified as part of this pass)

---

## 0. What changed in this rewrite

Version 1.0 described a settlement system that does not exist in the codebase. The corrections that matter most:

- **No calendar-month cron job.** v1.0's `@Cron('0 0 * * *')` "is it the last day of the month" daily check does not exist. The real system generates settlement schedules **per contract**, anchored to that contract's **first vehicle delivery date**, as fixed **30-day rolling windows** — not calendar months. There is no scheduled background job that auto-generates or auto-processes settlements at all; generation is **admin-triggered** via two endpoints (`POST /api/finance/settlements/generate` and `.../generate-current-cycle`).
- **No tier-based cadence.** A code comment inside `GenerateSettlementCommand.cs` itself claims tier-based cadence (Bronze/Silver monthly, Gold bi-weekly, Platinum weekly) — this is **not implemented anywhere**; it is a stale/aspirational comment inside the real codebase, not just a stale external doc. Cadence is uniformly a fixed 30-day rolling window per contract regardless of provider tier. **This is an unresolved contradiction with a companion document** — `backlog/mvp/epic-08-wallet-escrow.md`'s rewrite states the tier-based cadence *is* real; this document and `epic-10-monthly-renewal-settlement.md` state it is *not*. Per the 2026-07-23 audit §10.4, this was **not reconciled before publishing** — treat the 30-day-rolling-window behavior in this document as ground truth for the Finance settlement-generation code path specifically, and flag the wallet-escrow doc's claim for a human to resolve, don't silently pick a side.
- **No generic `Settlement`/`Debt` entities.** The real entities are `SettlementCycle` (global, cross-provider, `OPEN`/`PROCESSING`/`CLOSED`), `SettlementPayout` (per provider per cycle, `PENDING_ADMIN_APPROVAL`/`COMPLETED`/`FAILED`/rejected), `SettlementPayoutLineItem` (per contract/vehicle), and `MonthlySettlementSchedule` (per-contract cycle window, `PENDING`/`LOCKED`/`SETTLED`/`CANCELLED`). **There is no `Debt` entity anywhere in the codebase.**
- **No grace-period, late-fee, or debt-escalation mechanics of any kind.** v1.0's Sections 2.4–2.5, 7, and 10 (grace-period settlement, business-account suspension on unpaid debt, 5% late fee, debt-escalates-to-dispute-after-30-days job) describe functionality that was **never built**. There is no `ON_HOLD`-driven grace-period flow, no `suspendBusinessAccount` call tied to a settlement default, and no debt-repository anywhere in `Modules/Finance`.
- **No three-tier AUTO/MANAGER/ADMIN approval ladder.** The real system has exactly one approval gate: every generated payout starts `PENDING_ADMIN_APPROVAL`, and a single admin approve/reject action resolves it. There is an optional **auto-approve-below-threshold** setting (`SETTLEMENT_AUTO_APPROVE_THRESHOLD`, MasterData, disabled by default) — not a manager tier, and not the specific `50,000 / 200,000` ETB numbers v1.0 hardcoded.
- **No PDF generation, CSV export, or a dedicated monthly reconciliation report job.** None of v1.0's §11 (daily reconciliation cron, monthly PDF/CSV report generation) exists on any surface, confirmed against web `finance-service.ts` and both mobile wallet services.
- **No dispute integration.** v1.0's debt-escalation flow called into a `disputeService.create(...)` that assumed a working Disputes module. No such module, service, or entity exists — see `MVP_DISPUTE_RESOLUTION_WORKFLOW.md` for the full accounting.
- **Withholding tax mechanics are real and confirmed** (unlike some of the audit's earlier "unconfirmed" flags) — this is one part of v1.0's shape that survives close to intact, detailed in §7 below.

---

## 1. SETTLEMENT OVERVIEW (as implemented)

### 1.1 What triggers a settlement cycle

There is exactly one real trigger shape: a **per-contract, rolling 30-day window**, generated by `SettlementScheduleService.GenerateSchedule` (invoked via `GenerateSettlementScheduleCommand`) at the moment of the contract's **first vehicle delivery** (`DeliveryConfirmedEvent` → `Modules/Contracts/Application/EventHandlers/DeliveryConfirmedEventHandler.cs`, see `MVP_MODULE_INTEGRATION_SPECIFICATION.md` §2.3), not at contract creation and not on a calendar-month boundary.

- Each `MonthlySettlementSchedule` row is a fixed, **inclusive** 30-day window (`CycleStartDate`/`CycleEndDate` both inclusive) anchored to the contract's first-delivery date, repeated until the contract's end date.
- A contract shorter than 30 days gets a **single** cycle automatically.
- The **last** generated cycle for a contract is flagged `IsFinalSettlement = true`.
- Contract **extension** (Epic 06 Story 6.11 — not "renewal"; there is no renewal concept anywhere) regenerates the schedule: the previous final cycle is unmarked, new cycles are generated for the extension window, and the new last one is marked final.
- There is no monthly calendar-boundary check anywhere in this flow — a contract whose first delivery lands on, say, the 17th of a month settles on 30-day boundaries from the 17th, not at each subsequent month-end.

### 1.2 Settlement types that actually exist

Unlike v1.0's five named types (Monthly/Final/Immediate/Grace Period/Termination-with-Debt), the real system has exactly two operationally distinct settlement *shapes*, both processed through the same `SettlementCycle`/`SettlementPayout` machinery:

- **A non-final cycle** — settles a 30-day window mid-contract; on approval, the unused escrow for that window is rolled forward into the next cycle's lock rather than refunded.
- **The final cycle** (`IsFinalSettlement = true`) — the last cycle for that contract, whether reached by natural contract-end, a completed extension, or early termination/completion; on approval, any unused escrow (`lockedAmount − contractGross`) is refunded to the business `MAIN` wallet instead of rolled forward.

There is no separate "immediate" settlement type for short contracts distinct from the above — a contract shorter than 30 days simply gets one cycle, which is both the first and the final cycle, processed through the identical approval/posting flow.

### 1.3 Vehicle-Level Earnings Within a Cycle (real, confirmed)

This part of the original design is accurate to the real implementation: settlement windows are defined at the **contract** level, but actual earnings are computed from **individual vehicle activity** within each window, via `ContractVehicleAssignment.DeliveredAt`/`ReleasedAt` overlap against the cycle's `CycleStartDate`/`CycleEndDate`.

```
For each ContractVehicleAssignment on the contract:
  if not yet DeliveredAt: contributes 0 to this cycle (undelivered vehicle earns nothing)
  activeStart = DeliveredAt
  activeEnd   = ReleasedAt ?? contract end date
  activeDaysInWindow = overlap(activeStart, activeEnd, CycleStartDate, CycleEndDate)
  vehicleEarnings = activeDaysInWindow × ContractLineItem.UnitAmount
Sum across all assignments on the contract → contract's gross contribution to the cycle
```

This correctly handles partial delivery (a vehicle only earns from its real delivery date), late delivery (zero contribution until delivered), and early return (a vehicle stops earning at its actual return date) — all driven by real `ContractVehicleAssignment` timestamps, not the estimated/pro-rata daily-rate arithmetic v1.0's early-return and grace-period sections used.

---

## 2. SETTLEMENT CYCLE GENERATION (real endpoints and mechanics)

### 2.1 Admin-triggered generation — the only trigger that exists

There is no automatic/scheduled generation. Two admin-only endpoints on `Controllers/Finance/SettlementController.cs` (route `api/finance/settlements`) drive all cycle generation:

- **`POST /api/finance/settlements/generate`** (`[Authorize(Policy = "AdminOnly")]`) — generates/updates a settlement cycle for an explicit `StartDate`/`EndDate` range, across all contracts with a due `PENDING` schedule (`SettlementDate <= EndDate`), optionally scoped to a single `ContractId`.
- **`POST /api/finance/settlements/generate-current-cycle`** (`[Authorize(Policy = "AdminOnly")]`) — generates settlement only for each contract's single "processable" cycle: the earliest `PENDING` schedule whose `SettlementDate` has already passed (or, for a contract that reached `PARTIALLY_RETURNED`/`COMPLETED` via early return, the next sequential pending cycle regardless of date), with no earlier unresolved cycle blocking it. This is the practical, everyday generation action — it defaults `StartDate`/`EndDate` to "today" internally and relies on the `CurrentCycleOnly` flag rather than requiring the caller to compute a date range.

Both routes to the same underlying `GenerateSettlementCommand`/handler, differing only in the `CurrentCycleOnly` flag.

### 2.2 What generation actually does

For each due cycle, per provider:

1. Aggregate per-vehicle earnings (§1.3) into one `SettlementCycle` (global, cross-provider — a single cycle row can span many providers/contracts processed together) containing one `SettlementPayout` per provider.
2. Each `SettlementPayout` gets one `SettlementPayoutLineItem` per contract/vehicle, carrying gross, commission, commission rate, net, and days-in-period.
3. A payout is **skipped entirely** if the provider's gross earnings for the window fall below the configurable minimum-payout threshold (MasterData setting, default **100 ETB** if unset — not the 1,000 ETB figure that appears in an unrelated code comment on `GetSettlementReportQuery`, which describes a different, unimplemented threshold value; don't confuse the two).
4. Every new payout starts in status **`PENDING_ADMIN_APPROVAL`** — **no wallet movement happens at generation time**; all double-entry posting is deferred to the approval step (§4).
5. If the optional `SETTLEMENT_AUTO_APPROVE_THRESHOLD` MasterData setting is enabled and the payout's amount is at or below it, the payout is **automatically approved immediately after generation** (i.e., it still goes through the full approval posting logic in §4, just triggered by the system instead of an admin click). This setting is **disabled by default**.

### 2.3 Cycle/schedule state visibility

- **`GET /api/finance/settlements/schedule-states`** (admin) — surfaces each contract's schedules with a derived state: **Current** (the one processable cycle) or **Dormant** (`PENDING` but not yet processable), alongside the underlying raw statuses `PENDING`/`LOCKED`/`SETTLED`/`CANCELLED`. There is **no separate exposed "Locked" derived state** distinct from the raw status field, despite the schedule-states naming implying one.
- **`SettlementCycle`** itself has a simple `OPEN`/`PROCESSING`/`CLOSED` status, plus a full `SettlementStatusHistory` audit trail supporting trigger vocabulary `SYSTEM_CREATE`/`SYSTEM_CLOSE`/`USER_CLOSE`/`USER_REOPEN`/`USER_CANCEL`/`USER_APPROVE`/`USER_LOCK`/`USER_UNLOCK` — but **`SettlementController` exposes no endpoint to trigger `USER_CLOSE`/`USER_REOPEN`/`USER_CANCEL`/`USER_LOCK`/`USER_UNLOCK`** today. Only cycle generation and payout approve/reject are reachable via API; most of that trigger vocabulary is currently unreachable in practice. Do not build UI or automation assuming these actions are callable until the corresponding endpoints exist.
- **`GET /api/finance/settlements/cycles`** (admin) and **`GET /api/finance/settlements/cycles/{cycleId}/status-history`** (admin) — list cycles and their status-history rows.

---

## 3. SETTLEMENT PAYOUT ADMIN APPROVAL (real endpoints)

There is exactly one approval gate, not a three-tier ladder:

- **`GET /api/finance/settlements/payouts`** (admin, all providers, filterable by status/cycle) and **`GET /api/finance/settlements/payouts/{payoutId}`** / **`GET /api/finance/settlements/{payoutId}/details`** — surface payouts pending review with cycle/provider/line-item context. (Providers get their own scoped view via `GET /api/finance/settlements/my-settlements`, restricted server-side to their own `providerId`.)
- **`POST /api/finance/settlements/payouts/{payoutId}/approve`** — requires `payout.Status == PENDING_ADMIN_APPROVAL`; performs the full double-entry posting described in §4, then marks the payout `COMPLETED` and any `LOCKED` `MonthlySettlementSchedule`s tied to the underlying contracts as `SETTLED`. Body: optional `Notes`.
- **`POST /api/finance/settlements/payouts/{payoutId}/reject`** — requires a non-empty `Reason` (400 if blank); sets the payout's rejected status. There is **no automatic recalculation/reprocessing pipeline** — a rejected payout is not itself resubmitted; a fresh settlement-generation run over the same date range would be needed to produce a new payout for that window.
- Both actions resolve the acting admin via `IUserContextService.GetCurrentUserAccountAsync`, recorded on the payout/entity itself — there is **no separate "approval audit log" table**; the audit trail is the payout's own status plus `SettlementStatusHistory` rows tied to the parent cycle.

This entirely replaces v1.0's `AUTO_APPROVE` (<50,000 ETB) / `MANAGER_APPROVE` (50k–200k) / `ADMIN_APPROVE` (>200k) ladder — there is no manager-approval concept and no hardcoded 50k/200k thresholds anywhere in the real code; the only configurable threshold is the single optional auto-approve setting in §2.2.

---

## 4. SETTLEMENT PAYOUT DOUBLE-ENTRY POSTING (real, `ApproveSettlementPayoutCommand`)

This is the one part of the settlement flow that actually moves money, and it happens **only** on admin (or auto-approve-threshold) approval — never at generation time.

**Transaction A ("SETTLEMENT"), per contract touched by the payout:**
- DEBIT the business's **ESCROW** wallet for that contract's gross earned amount (via the contract's active `EscrowLock`).
- CREDIT the provider's **MAIN** wallet for the payout's net amount (once, for the whole payout).
- CREDIT the platform **COMMISSION** wallet for the commission deducted.
- CREDIT the platform **TAX** wallet for the tax withheld (see §7).

**Transaction B ("ESCROW_REFUND" or next-cycle relock), per contract:**
- If this is the contract's **final** settlement cycle (§1.2): refund any unused escrow (`lockedAmount − contractGross`) from the business ESCROW wallet back to the business MAIN wallet, and release the escrow lock.
- If **not** final: release the current escrow lock and immediately lock the unused amount toward the **next** cycle via `LockNextCycleEscrowCommand`; if no next cycle exists (e.g., the contract ended early), falls back to refunding the unused amount to the business MAIN wallet.

**On success:** payout → `COMPLETED`; any `LOCKED` `MonthlySettlementSchedule`s for the involved contracts → `SETTLED`; `SettlementPayoutApprovedEvent` and `WalletCreditedEvent` (source `SettlementPayout`) are published as in-process MediatR notifications, fanning out to Notifications (see `MVP_MODULE_INTEGRATION_SPECIFICATION.md` §2.4).

**On any failure mid-transaction:** full rollback, payout marked `FAILED`, exception surfaced to the admin caller. **There is no automatic retry** of a failed approval — an admin must re-attempt manually. All monetary movements are backed by immutable `WalletLedgerTransaction`/`WalletLedgerEntry` rows, independently verifiable by summing debits vs. credits per transaction (documented and demonstrated in `markdown-documentations/SETTLEMENT_TRANSACTION_TRACKING_IMPLEMENTATION.md`).

This entirely replaces v1.0's §4–§6 (generic `walletService.transfer` calls, separate early-return/grace-period settlement functions with their own ad hoc calculations) — early termination/completion settlements are **not** a distinct code path; they simply reach the existing final-cycle branch of the same `ApproveSettlementPayoutCommand` logic above, using the real `ContractVehicleAssignment.ReleasedAt` timestamps to bound each vehicle's actual earning window (§1.3), not v1.0's separate `calculateEarlyReturnSettlement`/penalty-rate/notice-period formulas — none of which exist in code.

---

## 5. COMMISSION CALCULATION (real)

Commission rate is **not** recomputed per settlement — it is resolved **once, at contract-creation time**, from the provider's tier (`ProviderTierAssignment` → `CommissionStrategy`, MasterData, defaulting to 5% if nothing resolves — see Epic 06 Story 6.1) and stored on the `Contract`/`ContractLineItem`. Settlement simply applies that already-resolved rate to the window's gross earnings; it does not re-query the provider's *current* tier at settlement time, so a mid-contract tier change does not retroactively change commission on that contract.

Seeded commission rates by tier (MasterData `ProviderTier`, admin-configurable in principle, though the admin web UI's edit action is currently a stub — "Update functionality coming soon," per `project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md` §1.3):

| Tier | Commission rate |
|---|---|
| Bronze | 10% |
| Silver | 8% |
| Gold | 6% |
| Platinum | 5% |

There is **no fifth "Red Zone"/blacklist tier** anywhere in code. This table matches `epic-06-contract-management.md`/the trust-engine spec; if project memory (`movello_business_overview.md`) states different numbers, that memory file — not this document — is what needs reconciling against code, per the 2026-07-23 audit §10.2.

---

## 6. FOUR SETTLEMENT-RELATED SURFACES: HISTORY & REPORTING (real, no PDF/CSV)

- **Provider:** `GET /api/finance/settlements/my-settlements` (filterable by status/cycle, paginated); payout detail includes gross/commission/tax/net plus per-contract/per-vehicle line items.
- **Web:** `ProviderSettlementsPage.tsx` / `SettlementDetailPage.tsx` (provider); `AdminSettlementManagementPage.tsx` / `AdminSettlementDetailPage.tsx` / `SettlementPayoutsPage.tsx` / `SettlementPoliciesPage.tsx` (admin).
- **Provider mobile app:** `provider_settlements_screen.dart`, `provider_settlement_detail_screen.dart`, `provider_upcoming_settlements_screen.dart`.
- **Business mobile app:** `contract_settlement_schedule_screen.dart` (per-contract schedule/cycle visibility via `mobile/contracts/{id}/settlement-schedule`), `contract_transactions_screen.dart` (per-contract wallet-ledger view).
- **No PDF report generation or PDF viewer exists for settlements on any surface.** v1.0's "PDF download endpoint"/"PDF viewer" concept was never built; all settlement data is presented as structured tables/screens.
- **No CSV export exists for settlement history on any surface** (checked web `finance-service.ts` and both mobile wallet services).
- **No month/year filter presets** — only generic status/cycle filters exist; no dedicated month/year picker was confirmed on any surface.
- **No daily/monthly reconciliation job** (v1.0 §11) exists — there is no scheduled process that sums yesterday's settlements, checks debit/credit balance, or emails a discrepancy report. Reconciliation today is a manual, on-demand exercise against the immutable ledger rows, not an automated one.

---

## 7. WITHHOLDING TAX DEDUCTION & RECLAIM (real, confirmed)

Unlike most of v1.0, the withholding-tax mechanics survive this rewrite close to intact — they are real and confirmed, not aspirational:

- The withholding rate is a **MasterData setting** (`WITHHOLDING_TAX_RATE`), defaulting to **2%** if unset — admin-editable through general MasterData settings, not a Finance-specific "tax rate" screen.
- Tax is deducted from every payout's **post-commission net** (`netBeforeTax × withholdingRate`, rounded to 2 decimal places) **at settlement-generation time** (§2.2, not at approval time) and stored on `SettlementPayout.TaxDeducted`; `NetPayoutAmount = TotalAmount − CommissionDeducted − TaxDeducted`.
- On payout **approval**, the tax amount is credited to a **dedicated platform TAX wallet** — separate from the platform COMMISSION wallet — as part of Transaction A (§4).
- **Reclaim mechanism:** a VAT-registered provider submits an invoice referencing completed payouts (Epic 09 Story 9.5, the provider-invoice flow); on admin approval of that invoice, `Σ payouts.TaxDeducted` for the referenced payouts is released from the platform TAX wallet to the provider's MAIN wallet via a `WITHHOLDING_RELEASE` transaction. This is the **only** real reclaim path — there is no separate "tax dispute" or automatic periodic release.
- **Admin-facing report:** `GET /api/finance/admin/wallets/tax-report` (`WithholdingTaxPage.tsx` on web) — filterable by provider/contract/date/entry-type (`ALL`/`WITHHELD`/`RELEASED`), returning per-payout rows (tax deducted, tax released, net owed, linked invoice number/status) and running totals (withheld/released/outstanding). This is a **live, on-demand query**, not a generated/stored monthly artifact — there is no scheduled "tax report generation" job.
- **Provider-facing visibility:** the settlement detail view/screen shows `TaxDeducted` alongside gross/commission/net per payout; the reclaim status itself (linked invoice, released/outstanding) lives on the provider invoice pages/screen (Epic 09), not duplicated into the settlement screens.

---

## 8. WHAT DOES NOT EXIST — EXPLICIT NEGATIVE-SPACE LIST

To prevent this document from being read as implying partial support for things that were only ever proposed in v1.0:

- **No `Debt` entity, table, or repository** anywhere in `Modules/Finance` or elsewhere in the backend.
- **No grace-period mechanic.** No `gracePeriodGranted`/`gracePeriodDays` field on `Contract`, no `ON_HOLD`-driven reactivation flow, no "grace period settlement" code path. (`ON_HOLD` is a reserved, never-set `Contract.Status` value — see `MVP_DISPUTE_RESOLUTION_WORKFLOW.md` §1 and `MVP_CONTRACT_STATE_MACHINE.md`.)
- **No late-fee calculation** (v1.0's flat 5% late fee) anywhere in Finance.
- **No business-account suspension tied to a settlement/payment default.** No `suspendBusinessAccount`-equivalent call exists in this flow.
- **No debt-escalation cron job, no 7/14/30-day overdue-notice cadence, and no automatic "escalate to dispute" action** — there is no dispute system to escalate into in the first place (see `MVP_DISPUTE_RESOLUTION_WORKFLOW.md`).
- **No settlement-dispute endpoint of any kind.** `SettlementController` has no `POST /settlements/{id}/dispute` or equivalent. Confirmed definitively — not merely "unconfirmed" — by `epic-10-monthly-renewal-settlement.md` Story 10.7 and this rewrite: repo-wide search inside `Modules/Finance` for "dispute" returns only the unrelated `EscrowLock` `DISPUTED`-adjacent status value used by early-termination/freeze/partial-release commands, which is not a workflow.
- **No manager-approval tier**, and no hardcoded 50,000/200,000 ETB threshold constants — the real system has one admin approval gate plus one optional configurable auto-approve threshold (§2.2, §3).
- **No PDF generation library, no MinIO/S3 dependency, no CSV export, no scheduled reconciliation job** anywhere in this epic's real scope (§6).
- **`SettlementCycle`'s modeled `USER_CLOSE`/`USER_REOPEN`/`USER_CANCEL`/`USER_LOCK`/`USER_UNLOCK` triggers have no controller endpoints** — don't build against them as if they were reachable today (§2.3).

---

## 9. UNRESOLVED CONTRADICTION — SETTLEMENT CADENCE (flagged, not resolved here)

Per the 2026-07-23 audit §10.4: the wallet-cluster rewrite (`backlog/mvp/epic-08-wallet-escrow.md`) states settlement cadence is real and **tier-based** (Bronze/Silver monthly, Gold bi-weekly, Platinum weekly, citing `GenerateSettlementCommand`). This document, following the ledger/settlement-cluster rewrite (`epic-10-monthly-renewal-settlement.md`), states the opposite: settlement runs on a **uniform rolling 30-day cycle per contract regardless of tier**, and that the tier-based-cadence comment inside `GenerateSettlementCommand.cs` is itself stale/aspirational, not implemented logic. **This was not reconciled before either document was published.** Whoever next touches `Modules/Finance/Application/Settlement/Commands/GenerateSettlementCommand*.cs` should resolve which is true by reading the actual branching logic (or lack thereof) in `SettlementScheduleService`/the schedule-generation query, and correct both `epic-08-wallet-escrow.md` and `epic-10-monthly-renewal-settlement.md` (and, if needed, this document) accordingly. This document's own read of the code (§1.1, §0) found **no tier-branching logic anywhere in the schedule-generation path** — but is explicitly not presented as the final word given the standing disagreement between the two rewrite passes.

---

**For Implementation:** treat this document, not v1.0, as the reference for how settlement actually works. The controller/command/entity names above (`SettlementController`, `GenerateSettlementCommand`, `ApproveSettlementPayoutCommand`, `SettlementCycle`/`SettlementPayout(LineItem)`/`MonthlySettlementSchedule`/`SettlementStatusHistory`) are the real, current API surface — verify against them directly, not against v1.0's `finance_schema.settlements`/`finance_schema.debts` schema, which was never built.

**For Testing:** verify against real behavior, not v1.0's assumptions:
1. Settlement schedules generate as 30-day rolling windows from first delivery, not calendar-month boundaries.
2. Generation requires an explicit admin action (`generate` or `generate-current-cycle`) — nothing runs automatically on a timer.
3. Every payout starts `PENDING_ADMIN_APPROVAL`; no wallet movement occurs before approval (or auto-approve-threshold trigger).
4. Commission is the rate resolved at contract creation, not recalculated from the provider's current tier at settlement time.
5. Withholding tax (2% default, MasterData-configurable) is deducted at generation time and only reclaimed via the Epic 09 provider-invoice flow — there is no other release path.
6. No grace-period, debt, or dispute code path exists to test — confirm their absence rather than assuming partial coverage.
