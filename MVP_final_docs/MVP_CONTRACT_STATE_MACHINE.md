# Movello MVP - Contract State Machine Specification

## Complete State Definitions, Transitions & Timeouts — Version 2.0

**Document Status:** AUTHORITATIVE — rewritten against running code
**Last verified against code:** 2026-07-23
**Supersedes:** Version 1.0 (December 22, 2025), which described states (`FAILED`, `UNDER_DISPUTE`, `PENDING_ALTERATION`, `ALTERED`) that were never implemented, and omitted five states that were (`Draft`, `PendingActivation`, `EscrowLockFailed`, `TerminationRequested`, `PartiallyReturned`).
**Ground truth files:** `backend/src/Marketplace.API/Modules/Contracts/Domain/Enums/ContractStatus.cs`, `Domain/Entities/Contract.cs`, `Domain/Entities/ContractLineItem.cs`, `Domain/Entities/ContractVehicleAssignment.cs`, `Controllers/Contracts/ContractsController.cs`, and every command handler under `Application/Contract/Commands/**`.
**Related documents:** `04_MODULE_SPECIFICATIONS/Contracts_Module.md`, `backlog/mvp/epic-06-contract-management.md`, `project-docs/partial-fulfillment-spec.md`.

---

## Document Purpose

This document defines the complete contract lifecycle state machine **as actually implemented** in `Marketplace.API`, including:
- All contract, line-item, and vehicle-assignment states and their real meanings
- State transition rules and the exact code that triggers each one
- Timeout definitions and the background jobs that enforce them
- State validation rules (assignment/blocking rule tables)
- Known dead code, unreachable states, and gaps between what's modeled and what's wired to an endpoint
- Event flow between the Contracts module and Finance/Delivery/Notifications

**A critical fact that shapes this entire document:** `Contract.Status` is a plain `string` column. A C# `ContractStatus` enum exists with 17 PascalCase members, but it is referenced **nowhere** in the codebase outside its own file (confirmed: zero matches for `ContractStatus.` across the backend). The actual system persists `UPPER_SNAKE_CASE` string literals set directly by domain methods, and there are **18** distinct values in practice — one (`CANCELLED`) isn't in the enum at all. This document treats the string values as ground truth and calls out every enum/reality mismatch explicitly.

---

## TABLE OF CONTENTS

1. [Contract State Overview](#1-contract-state-overview)
2. [Contract State Definitions](#2-contract-state-definitions)
3. [Contract Line Item State Definitions](#3-contract-line-item-state-definitions)
4. [Vehicle Assignment State Definitions](#4-vehicle-assignment-state-definitions)
5. [State Transition Matrix](#5-state-transition-matrix)
6. [State Machine Diagram](#6-state-machine-diagram)
7. [Timeout Rules](#7-timeout-rules)
8. [State Validation Rules](#8-state-validation-rules)
9. [Dead Code, Vestigial States & Unwired Commands](#9-dead-code-vestigial-states--unwired-commands)
10. [State Change Event Flow](#10-state-change-event-flow)
11. [Status Aggregation Rules](#11-status-aggregation-rules)
12. [API Surface Reference](#12-api-surface-reference)

---

## 1. CONTRACT STATE OVERVIEW

### 1.1 The 18 real status values

| # | String value | In `ContractStatus` enum? | Reachable in current code? |
|---|---|---|---|
| 1 | `DRAFT` | ✅ `Draft` | ❌ backing-field default only; every factory overrides it before save |
| 2 | `PENDING_ESCROW` | ✅ `PendingEscrow` | ✅ |
| 3 | `ESCROW_LOCK_FAILED` | ✅ `EscrowLockFailed` | ✅ |
| 4 | `PENDING_VEHICLE_ASSIGNMENT` | ✅ `PendingVehicleAssignment` | ✅ |
| 5 | `PENDING_ACTIVATION` | ✅ `PendingActivation` | ❌ vestigial — guarded against, never set |
| 6 | `PENDING_SIGNING` | ✅ `PendingSigning` | ✅ |
| 7 | `SIGNED` | ✅ `Signed` | ⚠️ momentary/in-memory only, never persisted as a distinct row |
| 8 | `PENDING_DELIVERY` | ✅ `PendingDelivery` | ✅ |
| 9 | `PARTIALLY_DELIVERED` | ✅ `PartiallyDelivered` | ✅ |
| 10 | `ACTIVE` | ✅ `Active` | ✅ |
| 11 | `TERMINATION_REQUESTED` | ✅ `TerminationRequested` | ✅ |
| 12 | `TERMINATED` | ✅ `Terminated` | ✅ (only via request→approve pair) |
| 13 | `COMPLETED` | ✅ `Completed` | ✅ |
| 14 | `DISPUTED` | ✅ `Disputed` | ❌ vestigial — guarded against, never set |
| 15 | `ON_HOLD` | ✅ `OnHold` | ❌ vestigial — guarded against, never set |
| 16 | `TIMEOUT_PENDING` | ✅ `TimeoutPending` | ✅ |
| 17 | `PARTIALLY_RETURNED` | ✅ `PartiallyReturned` | ✅ |
| 18 | `CANCELLED` | ❌ not in enum | ✅ |

Three of the 17 enum members (`PendingActivation`, `Disputed`, `OnHold`) are never produced by any transition in the current build — they exist only as guard-clause literals (e.g. "don't overwrite this status during aggregation," "this status is required to call this endpoint") that nothing ever actually satisfies. `Draft` is the EF Core backing-field default but is always overwritten before the first save. `Signed` is set and then overwritten within the same method call before `SaveChanges`, so it is real in the sense that the code briefly holds it, but it can never be observed in the database or in `GetContractStatusHistory`. `CANCELLED` is the opposite case: fully real and reachable, but completely undocumented in the enum.

There is **no `SUSPENDED` state and no suspension mechanism of any kind.** Nothing in the Contracts module re-checks business wallet balance once a contract is `ACTIVE`. This is the single biggest divergence from earlier drafts of this document and from `backlog/mvp/epic-06-contract-management.md`'s pre-rewrite text.

### 1.2 State categories

**Setup states** (contract not yet operational):
- `PENDING_ESCROW` — waiting for the automatic escrow lock
- `ESCROW_LOCK_FAILED` — escrow lock exhausted 5 retries
- `PENDING_VEHICLE_ASSIGNMENT` — waiting for provider to assign specific vehicles
- `PENDING_SIGNING` — all vehicles assigned, waiting for dual-party OTP terms acceptance
- `PENDING_DELIVERY` — terms signed, waiting for first physical delivery

**Operational states** (vehicles moving/in service):
- `PARTIALLY_DELIVERED` — some but not all awarded vehicles delivered
- `ACTIVE` — every awarded vehicle delivered; contract fully in service
- `PARTIALLY_RETURNED` — some or all vehicles returned; gate for the two-party completion flow
- `TIMEOUT_PENDING` — contract end date reached with vehicles still outstanding

**Exit/administrative states:**
- `TERMINATION_REQUESTED` — one party asked to end the contract early
- `TERMINATED` — termination approved
- `COMPLETED` — two-party (or admin-override) completion approved
- `CANCELLED` — cancelled pre-signing (admin abort or escrow timeout); not in the `ContractStatus` enum

**Vestigial (defined, never reached):**
- `PENDING_ACTIVATION`, `DISPUTED`, `ON_HOLD`

### 1.3 Real lifecycle path (happy path, RFQ-sourced contract)

```
CreateContract (BidAwardedEvent)
  └─▶ PENDING_ESCROW
        └─▶ [escrow locked] ─▶ PENDING_VEHICLE_ASSIGNMENT
                                   └─▶ [all line items fully assigned] ─▶ PENDING_SIGNING
                                          └─▶ [both parties OTP-confirm terms] ─▶ (SIGNED, in-memory only) ─▶ PENDING_DELIVERY
                                                 └─▶ [first vehicle delivered] ─▶ PARTIALLY_DELIVERED
                                                        └─▶ [last vehicle delivered] ─▶ ACTIVE
                                                               └─▶ [some vehicles returned] ─▶ PARTIALLY_RETURNED
                                                                      └─▶ [two-party completion approved] ─▶ COMPLETED

Side branches:
  PENDING_ESCROW  ──(5 retries exhausted)──▶ ESCROW_LOCK_FAILED ──(manual retry)──▶ PENDING_ESCROW
  PENDING_ESCROW  ──(24h timeout, job)─────▶ CANCELLED
  {PENDING_VEHICLE_ASSIGNMENT, PENDING_ESCROW, PENDING_SIGNING} ──(admin abort)──▶ CANCELLED
  {ACTIVE, PARTIALLY_RETURNED} ──(request)──▶ TERMINATION_REQUESTED ──(approve)──▶ TERMINATED
  {contract past EndDate, vehicles still out} ──(daily job)──▶ TIMEOUT_PENDING (settlement still runs; not a dead end)
```

Direct Rental contracts follow the same status machine; the only difference is that a Direct Rental contract may already have vehicle assignments at creation (chosen during booking), so `ActivateAfterEscrowLock()` can send it straight to `PENDING_SIGNING` instead of `PENDING_VEHICLE_ASSIGNMENT`.

---

## 2. CONTRACT STATE DEFINITIONS

### 2.1 PENDING_ESCROW

**Description:** Contract just created (from bid award or Direct Rental acceptance); escrow not yet locked.

**Entry:** `Contract.Create()` / `CreateFromBid()` / `CreateFromDirectRental()` — this is the initial status for every contract, always, regardless of source.

**Exit:**
- `ContractCreatedEventHandler` locks escrow successfully → `Contract.ActivateAfterEscrowLock()` → `PENDING_VEHICLE_ASSIGNMENT` (or `PENDING_SIGNING` if already fully assigned)
- 5 lock retries exhausted → `Contract.MarkAsEscrowLockFailed()` → `ESCROW_LOCK_FAILED`
- `EscrowTimeoutJob` (every 15 min) finds the contract older than the configurable timeout (`ESCROW_RELEASE_DELAY_HOURS` MasterData setting, default 24h) → `Contract.Cancel()` → `CANCELLED`
- Admin `abort-before-signing` → `CANCELLED` (with escrow refund if a lock happens to already exist)

**Escrow amount formula:** `Σ over line items of (UnitAmount × QuantityAwarded × min(DurationDays, 30))` — capped at 30 days per line item even for long-term contracts, so escrow only ever covers the first billing cycle.

**Business rule reference:** BR-010 (auto escrow lock), BR-011 (5-retry backoff).

---

### 2.2 ESCROW_LOCK_FAILED

**Description:** Escrow lock failed on all 5 attempts (1s/2s/4s/8s/16s backoff).

**Entry:** `ContractCreatedEventHandler`, after the 5th failed attempt.

**Exit:**
- `RetryEscrowLockCommand` (admin or business-triggered) pre-validates wallet balance, then `Contract.ResetForEscrowRetry()` → back to `PENDING_ESCROW`, republishes `ContractCreatedEvent`.
- No automatic notification is sent on entry — the handler only logs a `LogCritical` line and has two `// TODO` comments for business/admin notification and an admin task queue, neither implemented.

---

### 2.3 PENDING_VEHICLE_ASSIGNMENT

**Description:** Escrow locked; provider must attach specific vehicles to each line item before the contract can move to signing.

**Entry:**
- `ActivateAfterEscrowLock()` when at least one operational line item isn't fully assigned
- `ResetVehicleAssignmentsCommand` (wipes all assignments/delivery sessions/OTPs, returns here) — admin or provider
- `ResetContractToPendingVehicleAssignmentCommand` (admin-only) — **guarded on `Status == PENDING_ACTIVATION`, which nothing ever sets; this endpoint's precondition can never be satisfied today**
- `AbortContractBeforeSigningCommand` resets line items here as part of cancelling (though the contract itself ends up `CANCELLED`, not this status)

**Exit:** Once `Σ QuantityActive == Σ QuantityAwarded` across operational line items → `PENDING_SIGNING` (propagated by `IContractVehicleAssignmentService.TryPropagateContractStatusFromLineItems` after each `AssignVehicleCommand`).

**Allowed actions:** Provider assigns vehicles (`POST .../assign-vehicle`, `1..N` vehicle IDs per call); provider/admin can unassign or reset.

---

### 2.4 PENDING_SIGNING

**Description:** Every awarded vehicle is assigned; contract now needs both parties to OTP-confirm the current contract-terms version.

**Entry:** Full assignment reached (see 2.3), or `ActivateAfterEscrowLock()` directly for Direct Rental contracts whose vehicles were pre-assigned.

**Exit:**
- `VerifyContractTermsOtpCommandHandler`, once both `BusinessOtpConfirmed` and `ProviderOtpConfirmed` are true → `Contract.MarkTermsSigned()` → `SIGNED` then immediately `PENDING_DELIVERY` in the same call (see 2.5).
- Admin `abort-before-signing` → `CANCELLED`.

**Mechanism:** `POST /contracts/{id}/terms/otp/generate` creates/refreshes a `ContractTermsAcceptance` row bound to the active `ContractTermsVersion`; each party gets an independent 6-digit OTP (5-min expiry, 60s resend cooldown). `POST /contracts/{id}/terms/otp/verify` lets only the authenticated caller's own party confirm their own code — there is no cross-party verification path. This is a completely separate mechanism from the delivery-confirmation OTP in Epic 07.

---

### 2.5 SIGNED (transient, not persisted)

**Description:** Logically, "both parties have signed." In code, `Contract.MarkTermsSigned()` does:
```csharp
Status = "SIGNED";       // assigned in-memory
UpdatedAt = ...;
Status = "PENDING_DELIVERY";  // immediately overwritten, same method, before SaveChanges
UpdatedAt = ...;
```
No `SaveChanges` occurs between the two assignments, and `VerifyContractTermsOtpCommandHandler` does not write a `ContractStatusHistory` row for the `SIGNED` step. **A contract's `Status` column can never be observed as `"SIGNED"` in the database, and there is no audit-trail evidence that a "signed, awaiting delivery" moment ever separately existed.** Treat this as a logical/instantaneous state useful for narrating the flow, not a queryable state.

---

### 2.6 PENDING_DELIVERY

**Description:** Terms fully signed; waiting for the first vehicle to be physically delivered and OTP-confirmed (Epic 07 flow).

**Entry:** End of dual-OTP signing (2.5).

**Exit:** First `DeliveryConfirmedEvent` → `DeliveryConfirmedEventHandler` → `Contract.UpdateStatusBasedOnDelivery()` → `PARTIALLY_DELIVERED` (if more remain) or `ACTIVE` (if that one delivery covers the entire awarded quantity, e.g. a single-vehicle contract).

---

### 2.7 PARTIALLY_DELIVERED

**Description:** Some, but not all, awarded vehicles have been delivered and OTP-confirmed.

**Entry/Exit:** Managed entirely by `Contract.UpdateStatusBasedOnDelivery()`, called from `DeliveryConfirmedEventHandler` and `DeliveryReturnConfirmedEventHandler`. Moves to `ACTIVE` once `totalDelivered == totalAwarded && totalReturned == 0`; can also be re-entered from `ACTIVE`-adjacent states if a vehicle is unassigned/replaced pre-completion (rare in practice, since post-delivery removal is effectively blocked — see §9).

**Vehicles can still be assigned during this state** (`ContractAssignmentRules.AssignableContractStatuses` includes it) — useful for filling in vehicles that weren't ready at initial assignment time.

---

### 2.8 ACTIVE

**Description:** Every awarded vehicle across every line item has been delivered; the contract is fully in service.

**Entry:** `Contract.UpdateStatusBasedOnDelivery()` when `totalDelivered == totalAwarded && totalReturned == 0`; `ActivatedAt` is stamped on first entry only. `DeliveryConfirmedEventHandler` publishes `ContractActivatedEvent` at this exact moment (the one true "activation" event in the system) and triggers settlement-schedule generation anchored to the **first** delivery date (not contract creation date, not this activation moment).

**Exit:**
- Any return (`DeliveryReturnConfirmedEvent`) → `PARTIALLY_RETURNED` (even a single vehicle returning moves the whole contract out of `ACTIVE`)
- `RequestTerminationCommand` → `TERMINATION_REQUESTED`
- Contract end date reached with vehicles still outstanding → `TIMEOUT_PENDING` (daily job)

**Protected from aggregation overwrite** alongside `ON_HOLD`, `TERMINATED`, `TIMEOUT_PENDING`, `DISPUTED` — i.e. `UpdateStatusBasedOnDelivery()` will not silently move a contract out of these five statuses based on quantity math; `ACTIVE` itself is not in that protected list, so it *is* subject to being recalculated (e.g. down to `PARTIALLY_RETURNED`) as returns happen.

---

### 2.9 TERMINATION_REQUESTED

**Description:** One party has asked to end the contract before its natural completion.

**Entry:** `RequestTerminationCommand`. Note a real gap between two layers of validation:
- The **domain method** `Contract.RequestTermination()` allows this from `ACTIVE`, `PENDING_ACTIVATION`, `PENDING_ESCROW`, or `PARTIALLY_RETURNED`.
- The **command handler** actually wired to the API only allows `ACTIVE` or `PARTIALLY_RETURNED` — the other two branches of the domain guard are unreachable through the real endpoint.

**Exit:** `ApproveTerminationCommand` (any of business/provider/admin — no self-vs-other-party restriction, unlike completion) → `TERMINATED`; all currently `ACTIVE` line items are individually force-`TERMINATED` too. There is no reject/withdraw endpoint for a termination request.

---

### 2.10 TERMINATED

**Description:** Contract formally ended via the termination-request/approve pair.

**Entry:** `ApproveTerminationCommand` only, in the current build. The lower-level domain methods `Contract.Terminate()` and `Contract.TerminateEarly()` (the latter computes an early-termination penalty amount and writes it into `TerminationReason` as text) **have zero callers anywhere in the codebase** — fully dead code today, despite being fully implemented and documented in the entity.

**Exit:** None — terminal state.

---

### 2.11 COMPLETED

**Description:** Contract successfully wound down; every vehicle returned, all settlement cycles cleared, both parties (or an admin) agreed it's done.

**Entry:**
- `ApproveContractCompletionCommand` (the *other* party from whoever requested) → `Contract.ApproveCompletion()` → `Complete()`
- `CompleteContractCommand` (admin/super-admin override) — same prerequisite checks, bypasses the two-party requirement, resolves any pending `ContractCompletionRequest` as `ADMIN_OVERRIDE`

**Prerequisites (enforced identically by request/approve/admin-complete):** every `ContractVehicleAssignment` is `RETURNED`; no `MonthlySettlementSchedule` is `LOCKED` or overdue `PENDING`; `ContractCompletionSettlementGuard` confirms every returned vehicle's service window is covered by a `COMPLETED` settlement payout, and there's no unresolved `AVAILABLE` escrow rollover.

**Exit:** None — terminal state.

---

### 2.12 DISPUTED / ON_HOLD (vestigial)

**Description (as designed, never realized):** Both appear in `Contract.UpdateStatusBasedOnDelivery()`'s `protectedStatuses` array (meaning if a contract were ever in one of these, the aggregation logic wouldn't silently overwrite it), and `DISPUTED` is separately counted by an admin dashboard stats query (`openDisputesCount`). **No command, handler, controller, or background job anywhere sets a `Contract.Status` to `"DISPUTED"` or `"ON_HOLD"`.** These read as fully designed states with zero implementation behind them — the same conclusion the audit reached about the absence of a dedicated Dispute Engine (`11_Trust_Escrow_Dispute_Engines_Spec.md`). Note: `EscrowLock` and `ContractPenalty` entities have their *own*, unrelated `"DISPUTED"` status values (escrow-lock disputes, penalty disputes) — those are real and reachable, just not the same field as `Contract.Status`.

---

### 2.13 TIMEOUT_PENDING

**Description:** Contract has passed its `EndDate` but still has vehicle assignments that are neither `RETURNED` nor `REPLACED`.

**Entry:** `ContractEndLifecycleJob` — a daily background job (targets 00:45 UTC) that scans all non-`COMPLETED`/`TERMINATED`/`CANCELLED` contracts with `EndDate.Date <= today`, and for each one with outstanding vehicles: sets `TIMEOUT_PENDING` (once), triggers due-settlement generation for that contract (approval stays manual), and notifies both parties to return/collect vehicles (once, only on the actual transition).

**Exit:** Not automated — as vehicles get returned via the normal delivery-return flow, `UpdateStatusBasedOnDelivery()` would recompute status, but `TIMEOUT_PENDING` is in the protected-statuses list, so **it will not automatically fall through to `PARTIALLY_RETURNED` on its own** — this is a genuine ambiguity in the current implementation worth flagging to engineering: a contract that enters `TIMEOUT_PENDING` and then has all its vehicles returned has no automated path back into the normal completion pipeline today; it would need manual/admin intervention to move it forward.

---

### 2.14 PARTIALLY_RETURNED

**Description:** At least one vehicle has been returned; gate for the two-party completion flow.

**Entry:** `Contract.UpdateStatusBasedOnDelivery()`, whenever `0 < totalReturned < totalAwarded`, **or** when `totalReturned == totalAwarded` too (the same branch fires for "some" and "all" returned — the method does not have a separate branch that jumps straight to `COMPLETED` on full return; full return still lands here so the two-party completion gate is never bypassed automatically). This is deliberate: the code comment on `UpdateStatusBasedOnDelivery()` explicitly says auto-setting `COMPLETED` here would bypass the completion flow.

**Exit:** `PARTIALLY_RETURNED` is where `RequestTerminationCommand` (still allowed here) and the whole completion-request pipeline (§2.11) both operate.

---

### 2.15 CANCELLED (not in the `ContractStatus` enum)

**Description:** Contract cancelled before it was ever signed.

**Entry:**
- `AbortContractBeforeSigningCommand` (admin/super-admin, from `PENDING_VEHICLE_ASSIGNMENT`/`PENDING_ESCROW`/`PENDING_SIGNING`) — soft-removes vehicle assignments, resets line items, releases vehicles, refunds any locked escrow, writes a `ContractStatusHistory` row (`USER_CANCEL`)
- `EscrowTimeoutJob` (from `PENDING_ESCROW` only, past the configurable timeout) — **does not write a `ContractStatusHistory` row**, an inconsistency with the admin path

**Exit:** None — terminal state.

---

## 3. CONTRACT LINE ITEM STATE DEFINITIONS

`ContractLineItem.Status` (string, default `"PENDING_ACTIVATION"` on the backing field but always set to `"PENDING_VEHICLE_ASSIGNMENT"` by both `Create()` factories) uses 7 real values:

| Status | Meaning | Set by |
|---|---|---|
| `PENDING_VEHICLE_ASSIGNMENT` | No vehicles assigned yet | `ContractLineItem.Create()` / `CreateFromDirectRental()` |
| `PENDING_ACTIVATION` | Assigned quantity reached, none delivered yet | `UpdateStatusBasedOnDelivery()`/`UpdateStatusBasedOnReturn()`/`UpdateStatus()` internal branches, once `QuantityActive > 0` |
| `PARTIALLY_DELIVERED` | Some, not all, awarded vehicles delivered | same internal methods |
| `ACTIVE` | All awarded vehicles delivered, none returned | same |
| `PARTIALLY_RETURNED` | Some, not all, delivered vehicles returned | same |
| `COMPLETED` | All awarded vehicles returned | same |
| `TERMINATED` | Line item force-closed (contract termination approval terminates all `ACTIVE` line items) | `ContractLineItem.Terminate()` |

The separate `ContractLineStatus` C# enum (`PendingActivation, PartiallyDelivered, Active, PartiallyReturned, Completed, Terminated, OnHold, Disputed`) **does not match this list**: it's missing `PendingVehicleAssignment` (the real, heavily-used initial value) and carries `OnHold`/`Disputed`, neither of which is ever set at line-item level. Same enum/reality gap pattern as the contract-level enum.

Line items track quantities, not just status: `QuantityAwarded`, `QuantityActive` (currently assigned & not yet returned/removed), `QuantityDelivered` (cumulative, OTP-confirmed), `QuantityReturned` (cumulative). `TotalAmount = QuantityAwarded × UnitAmount × DurationDays`.

---

## 4. VEHICLE ASSIGNMENT STATE DEFINITIONS

`ContractVehicleAssignment.Status` is a plain string with **no dedicated enum type at all**. The entity's own doc comment lists 4 values; the real code uses 5:

| Status | Meaning | Set by | In entity's own comment? |
|---|---|---|---|
| `ASSIGNED` | Vehicle attached to a line item, not yet delivered | `ContractVehicleAssignment.Create()` | ✅ |
| `DELIVERED` | OTP-confirmed physical handover | `MarkDelivered()`, from `DeliveryConfirmedEventHandler` | ✅ |
| `RETURNED` | Vehicle handed back | `Release()`, from `DeliveryReturnConfirmedEventHandler` or `InitiateEarlyReturnCommandHandler` (unreachable — see §9) | ✅ |
| `REPLACED` | Superseded by a replacement assignment | `Replace()` | ✅ |
| `REMOVED` | Unassigned pre-delivery, or force-cleared by admin reset/abort | `SetStatus("REMOVED")` in `UnassignVehicleCommandHandler`, `ResetVehicleAssignmentsCommandHandler`, `AbortContractBeforeSigningCommandHandler` | ❌ not documented in the entity comment |

`ContractVehicleBlockingRules.ActiveAssignmentStatuses = { ASSIGNED, DELIVERED }` — only these two statuses hold a slot open against the line item's awarded quantity and block the underlying `Vehicle` from being reused elsewhere.

---

## 5. STATE TRANSITION MATRIX

| From | To | Trigger | Handler |
|---|---|---|---|
| *(new)* | `PENDING_ESCROW` | Bid awarded / Direct Rental accepted | `CreateContractCommand` / `CreateDirectRentalContractCommand` |
| `PENDING_ESCROW` | `PENDING_VEHICLE_ASSIGNMENT` or `PENDING_SIGNING` | Escrow locked | `ContractCreatedEventHandler` → `ActivateAfterEscrowLock()` |
| `PENDING_ESCROW` | `ESCROW_LOCK_FAILED` | 5 lock retries failed | `ContractCreatedEventHandler` |
| `PENDING_ESCROW` | `CANCELLED` | Timeout (default 24h) | `EscrowTimeoutJob` |
| `PENDING_ESCROW` | `CANCELLED` | Admin pre-signing abort | `AbortContractBeforeSigningCommand` |
| `ESCROW_LOCK_FAILED` | `PENDING_ESCROW` | Manual retry, balance re-checked | `RetryEscrowLockCommand` |
| `PENDING_VEHICLE_ASSIGNMENT` | `PENDING_SIGNING` | All line items fully assigned | `AssignVehicleCommand` → status propagation |
| `PENDING_VEHICLE_ASSIGNMENT` | `CANCELLED` | Admin pre-signing abort | `AbortContractBeforeSigningCommand` |
| any assignable status | `PENDING_VEHICLE_ASSIGNMENT` | Full assignment reset | `ResetVehicleAssignmentsCommand` |
| `PENDING_SIGNING` | `PENDING_DELIVERY` (via momentary `SIGNED`) | Both parties OTP-confirm terms | `VerifyContractTermsOtpCommand` → `MarkTermsSigned()` |
| `PENDING_SIGNING` | `CANCELLED` | Admin pre-signing abort | `AbortContractBeforeSigningCommand` |
| `PENDING_DELIVERY` | `PARTIALLY_DELIVERED` or `ACTIVE` | First delivery confirmed | `DeliveryConfirmedEventHandler` |
| `PARTIALLY_DELIVERED` | `ACTIVE` | Last vehicle delivered | `DeliveryConfirmedEventHandler` |
| `ACTIVE` | `PARTIALLY_RETURNED` | Any vehicle returned | `DeliveryReturnConfirmedEventHandler` |
| `ACTIVE` / `PARTIALLY_RETURNED` | `TERMINATION_REQUESTED` | Termination requested | `RequestTerminationCommand` |
| `TERMINATION_REQUESTED` | `TERMINATED` | Termination approved | `ApproveTerminationCommand` |
| `PARTIALLY_RETURNED` | `COMPLETED` | Two-party approval or admin override | `ApproveContractCompletionCommand` / `CompleteContractCommand` |
| `PARTIALLY_RETURNED` | `PARTIALLY_RETURNED` | Completion rejected (no-op transition) | `RejectContractCompletionCommand` |
| any non-`COMPLETED`/`TERMINATED`/`CANCELLED` past `EndDate` with open vehicles | `TIMEOUT_PENDING` | Daily end-of-term scan | `ContractEndLifecycleJob` |

Not real transitions (documented for completeness, never fired): anything into/out of `PENDING_ACTIVATION`, `DISPUTED`, `ON_HOLD` at the contract level.

---

## 6. STATE MACHINE DIAGRAM

```mermaid
stateDiagram-v2
    [*] --> PENDING_ESCROW: bid awarded / DR accepted

    PENDING_ESCROW --> PENDING_VEHICLE_ASSIGNMENT: escrow locked (RFQ, unassigned)
    PENDING_ESCROW --> PENDING_SIGNING: escrow locked (DR, pre-assigned)
    PENDING_ESCROW --> ESCROW_LOCK_FAILED: 5 retries failed
    PENDING_ESCROW --> CANCELLED: timeout job / admin abort
    ESCROW_LOCK_FAILED --> PENDING_ESCROW: manual retry

    PENDING_VEHICLE_ASSIGNMENT --> PENDING_SIGNING: all line items fully assigned
    PENDING_VEHICLE_ASSIGNMENT --> CANCELLED: admin abort

    PENDING_SIGNING --> PENDING_DELIVERY: both parties OTP-confirm terms
    PENDING_SIGNING --> CANCELLED: admin abort

    PENDING_DELIVERY --> PARTIALLY_DELIVERED: some vehicles delivered
    PENDING_DELIVERY --> ACTIVE: all vehicles delivered (single-vehicle contract)
    PARTIALLY_DELIVERED --> ACTIVE: last vehicle delivered

    ACTIVE --> PARTIALLY_RETURNED: any vehicle returned
    ACTIVE --> TERMINATION_REQUESTED: termination requested
    ACTIVE --> TIMEOUT_PENDING: end date reached, vehicles still out

    PARTIALLY_RETURNED --> TERMINATION_REQUESTED: termination requested
    PARTIALLY_RETURNED --> COMPLETED: two-party approval / admin override
    PARTIALLY_RETURNED --> TIMEOUT_PENDING: end date reached, vehicles still out

    TERMINATION_REQUESTED --> TERMINATED: approved

    COMPLETED --> [*]
    TERMINATED --> [*]
    CANCELLED --> [*]

    note right of PENDING_ACTIVATION
        PENDING_ACTIVATION, DISPUTED, ON_HOLD:
        defined in enum + guard code,
        never produced by any transition
    end note
```

---

## 7. TIMEOUT RULES

| Job | Frequency | Scans for | Action |
|---|---|---|---|
| `EscrowTimeoutJob` | Every 15 minutes | Contracts in `PENDING_ESCROW` older than `ESCROW_RELEASE_DELAY_HOURS` (MasterData setting, default 24h) | `Contract.Cancel()` → `CANCELLED` (no status-history row written) |
| `ContractEndLifecycleJob` | Daily, targets 00:45 UTC | Contracts with `EndDate.Date <= today`, status not `COMPLETED`/`TERMINATED`/`CANCELLED`, with any vehicle assignment not `RETURNED`/`REPLACED` | First time only: `TIMEOUT_PENDING` + party notifications. Every run: attempts due-settlement generation for that contract (`GenerateSettlementCommand`, swallows `InvalidOperationException` if nothing's due) |

There is **no** timeout for a contract stuck in `PENDING_VEHICLE_ASSIGNMENT`, `PENDING_SIGNING`, or `PENDING_DELIVERY` — only the pre-escrow window is time-boxed. A contract can sit in `PENDING_SIGNING` indefinitely if one party never completes their OTP.

Escrow-lock retry backoff (not a "timeout" but time-based): 5 attempts at 1s, 2s, 4s, 8s, 16s (≈31 seconds total) inside a single synchronous handler invocation — this is not a background job, it happens within the initial `ContractCreatedEvent` handling.

Early-return notice period (`InitiateEarlyReturnCommand`): reads `ContractPolicyRule` scenario `EARLY_RETURN`'s `GracePeriodHours` (converted to days, ceiling), defaulting to 7 days if unconfigured. **This command has no controller endpoint anywhere and is never invoked from any other module — it is unreachable in the running system today** (see §9). Actual vehicle returns, early or on-schedule, happen exclusively through the Delivery module's return-confirmation flow (`DeliveryReturnConfirmedEvent`), which has no notice-period concept at all.

---

## 8. STATE VALIDATION RULES

### 8.1 `ContractAssignmentRules` — where vehicles may be assigned

- **Assignable contract statuses:** `PENDING_VEHICLE_ASSIGNMENT`, `PENDING_ACTIVATION`, `PENDING_SIGNING`, `PARTIALLY_DELIVERED`, `PARTIALLY_RETURNED`. (Note `PENDING_ACTIVATION` appears here even though it's unreachable at contract level — harmless dead branch.)
- **Assignable line-item statuses:** `PENDING_VEHICLE_ASSIGNMENT`, `PENDING_ACTIVATION`, `PARTIALLY_DELIVERED`, `PARTIALLY_RETURNED`, `COMPLETED` — `COMPLETED` is intentionally included so a fully-returned line item can still receive a replacement vehicle before the whole contract is closed out.
- **Quantity math:** open slots = `QuantityAwarded − (count of assignments with status ASSIGNED or DELIVERED)`.

### 8.2 `ContractVehicleBlockingRules` — when an assigned vehicle can't be reused elsewhere

- **Blocking contract statuses:** `PENDING_ESCROW`, `PENDING_VEHICLE_ASSIGNMENT`, `PENDING_ACTIVATION`, `PENDING_SIGNING`, `SIGNED`, `PENDING_DELIVERY`, `PARTIALLY_DELIVERED`, `PARTIALLY_RETURNED`, `ACTIVE` — includes `PENDING_ESCROW` because Direct Rental contracts may pre-assign vehicles before escrow even locks.
- **Active assignment statuses:** `ASSIGNED`, `DELIVERED` only — `RETURNED`/`REPLACED`/`REMOVED` never block reuse.

### 8.3 Vehicle prerequisites for assignment

- Vehicle must belong to the awarded provider and have `Status == APPROVED`.
- Vehicle must not already hold an `ASSIGNED`/`DELIVERED` assignment on a *different* contract or a *different* line item within the same contract.

### 8.4 Two-party completion prerequisites (§2.11) — identical across request/approve/admin-complete

1. Every `ContractVehicleAssignment` (non-deleted) has `Status == RETURNED`.
2. No `MonthlySettlementSchedule` for the contract is `LOCKED`, or `PENDING` with `SettlementDate <= today` (future-dated `PENDING` cycles don't block).
3. `ContractCompletionSettlementGuard`: every returned vehicle's `[DeliveredAt, ReleasedAt)` service window must be covered by a `COMPLETED` `SettlementPayout`/`SettlementPayoutLineItem` for every settlement cycle that window overlaps; and there must be no `AVAILABLE` `EscrowRollover` left unresolved for the contract.
4. Requester ≠ approver/rejecter (self-approval and self-rejection are both explicitly blocked; admin is exempt from this check).

---

## 9. DEAD CODE, VESTIGIAL STATES & UNWIRED COMMANDS

This section exists because a spec that only describes "the happy path" would misrepresent how much of the modeled richness is actually reachable. Verified by exhaustive grep across the backend (0 call sites found for each):

| Component | Status | Evidence |
|---|---|---|
| `Contract.Terminate()`, `Contract.TerminateEarly()` | Fully implemented (incl. early-termination penalty math), **zero callers** | `ApproveTermination()` is the only real path to `TERMINATED` |
| `ExtendContractCommand`/Handler | Fully implemented (settlement-schedule regeneration), **no controller route anywhere** | Web's `ExtendContractDialog.tsx` calls `POST /contracts/{id}/extend`, which does not exist on any controller — the shipped "Extend Contract" button has no working backend |
| `ReplaceVehicleCommand`/Handler | Fully implemented, **no controller route anywhere** | Vehicle replacement can only theoretically happen through `UnassignVehicleCommand`'s replacement branch |
| `InitiateEarlyReturnCommand`/Handler | Fully implemented (notice-period logic, policy-driven grace period), **no controller route, no event-handler invocation anywhere** | Only reference to the command is its own command/handler/validator files |
| `ContractAmendment.Create()` | Entity fully modeled (`Sign()`/`Reject()`), **zero callers** | `UnassignVehicleCommand`'s post-delivery replacement branch requires a signed `SCOPE_CHANGE` amendment that nothing can ever create — that branch is unreachable in practice |
| `ContractPenalty.Create()` | Entity fully modeled (`MarkPaid()`/`Waive()`/`Dispute()`), **zero callers** | No termination, early-return, or replacement flow produces a penalty record despite UI copy (e.g. `AdminContractTerminationPage`) implying penalties are applied |
| `PENDING_ACTIVATION` contract status | Defined in enum, referenced in 2 rule tables and 1 termination guard | Never set by any transition |
| `DISPUTED` / `ON_HOLD` contract status | Defined in enum, protected in aggregation logic, `DISPUTED` counted in an admin dashboard query | Never set by any transition |
| `ResetContractToPendingVehicleAssignmentCommand` | Fully wired to `PATCH /contracts/{id}/reset-to-pending-vehicle-assignment` | Precondition (`Status == PENDING_ACTIVATION`) can never be true, so the endpoint always 400s |
| `SIGNED` status | Set in-memory | Overwritten before `SaveChanges`; no history row |

**Practical implication:** the *actually reachable* end-to-end contract flow is narrower than the domain layer suggests. Treat anything in this table as "modeled, not delivered" — don't spec new work assuming it functions, and don't count it as done in coverage audits without re-verifying wiring first.

---

## 10. STATE CHANGE EVENT FLOW

```
BidAwardedEvent (Marketplace module)
  └─▶ BidAwardedEventHandler ─▶ CreateContractCommand ─▶ ContractCreatedEvent

DirectRentalRequestAcceptedEvent / ...PartiallyAcceptedEvent (Marketplace module)
  └─▶ DirectRentalRequestAcceptedEventHandler ─▶ CreateDirectRentalContractCommand ─▶ ContractCreatedEvent

ContractCreatedEvent
  └─▶ ContractCreatedEventHandler (Finance module)
        ├─▶ success ─▶ ContractEscrowLockedEvent
        └─▶ 5 failures ─▶ Contract marked ESCROW_LOCK_FAILED (no event published)

AssignVehicleCommand (per call)
  └─▶ VehicleAssignedEvent (per newly-assigned vehicle)
  └─▶ contract status propagated in the same transaction if fully assigned

VerifyContractTermsOtpCommand (both parties confirmed)
  └─▶ ContractTermsAcceptedEvent

DeliveryConfirmedEvent (Delivery module, per vehicle)
  └─▶ DeliveryConfirmedEventHandler (Contracts module)
        ├─▶ first delivery ─▶ settlement schedule generated
        └─▶ last delivery ─▶ ContractActivatedEvent

DeliveryReturnConfirmedEvent (Delivery module, per vehicle)
  └─▶ DeliveryReturnConfirmedEventHandler (Contracts module)
        └─▶ all returned ─▶ in-app admin notification "contract_completion_eligible_admin"
            (no automatic settlement, no automatic completion)

RequestTerminationCommand / ApproveTerminationCommand
  └─▶ in-app notifications to both parties (no domain event published on these two paths)

RequestContractCompletionCommand / Approve.../Reject.../Cancel...
  └─▶ in-app notifications to the relevant party/parties (no domain event published)

ContractEndLifecycleJob (daily)
  └─▶ TIMEOUT_PENDING + party notifications (first transition only)
  └─▶ GenerateSettlementCommand attempt (every run)

EscrowTimeoutJob (every 15 min)
  └─▶ Contract.Cancel() — no event, no notification, no status-history row
```

---

## 11. STATUS AGGREGATION RULES

`Contract.UpdateStatusBasedOnDelivery()` is the single function that derives contract status from line-item quantities after any delivery or return. Its precedence, in order:

1. If status is in `{ ON_HOLD, TERMINATED, TIMEOUT_PENDING, DISPUTED }` → return immediately, do not touch status (protected).
2. If every operational (non-`TERMINATED`/`COMPLETED`) line item has been fully returned → `PARTIALLY_RETURNED` (deliberately not `COMPLETED` — see §2.14).
3. Else, using aggregated `totalAwarded`/`totalDelivered`/`totalReturned` across operational line items:
   - `0 < totalReturned < totalAwarded` → `PARTIALLY_RETURNED`
   - `0 < totalDelivered < totalAwarded` → `PARTIALLY_DELIVERED`
   - `totalDelivered == totalAwarded && totalReturned == 0` → `ACTIVE` (stamps `ActivatedAt` on first entry)
   - `totalDelivered == 0`, with `totalAssigned >= totalAwarded` → `PENDING_SIGNING`
   - `totalDelivered == 0`, with `totalAssigned == 0` → `PENDING_VEHICLE_ASSIGNMENT`

`ContractStatusProgression.TryUpgradeContractFromLineItems()` is a separate, one-directional helper (used by the RFQ and Direct Rental assignment services) that walks a fixed hierarchy — `PENDING_VEHICLE_ASSIGNMENT → PENDING_ACTIVATION → PENDING_SIGNING → SIGNED → PENDING_DELIVERY → PARTIALLY_DELIVERED → ACTIVE → PARTIALLY_RETURNED → COMPLETED` — and only ever moves the contract *forward* to the least-advanced line item's position, never backward. Note this hierarchy array itself includes `PENDING_ACTIVATION` and `SIGNED` as named rungs even though, per §1.1/§2.5, neither is ever the contract's actual persisted status — they're included for ordinal-index purposes only, not because a contract ever stops there.

`ContractStatusProgression.TryRepairFullyAssignedContractStatus()` is a defensive repair helper: if a contract is stuck in `PENDING_VEHICLE_ASSIGNMENT` but its line items are actually fully assigned, it forces a re-run of `UpdateStatusBasedOnDelivery()` to unstick it.

---

## 12. API SURFACE REFERENCE

All routes below are under `[Route("api/contracts")]` on `ContractsController` unless noted.

| Method | Route | Purpose |
|---|---|---|
| GET | `/admin` | List all contracts (admin) |
| GET | `/{contractId}` | Contract detail |
| GET | `/{contractId}/status-history` | `ContractStatusHistory` rows |
| GET | `/business/{businessId}` | Business's contracts |
| GET | `/provider/{providerId}` | Provider's contracts |
| GET | `/{contractId}/line-items/{lineItemId}/available-vehicles` | Assignable vehicles |
| POST | `/{contractId}/line-items/{lineItemId}/assign-vehicle` | Assign vehicles |
| POST | `/{contractId}/line-items/{lineItemId}/unassign-vehicle` | Unassign/replace |
| POST | `/{contractId}/reset-vehicle-assignments` | Wipe & reset all assignments |
| PATCH | `/{contractId}/reset-to-pending-vehicle-assignment` | Admin nudge (unreachable precondition, §9) |
| POST | `/{contractId}/terms/otp/generate` | Start/refresh dual-OTP signing |
| POST | `/{contractId}/terms/otp/verify` | Confirm caller's own OTP |
| GET | `/{contractId}/terms` | Terms content + acceptance status |
| POST | `/{contractId}/termination/request` | Request termination |
| POST | `/{contractId}/termination/approve` | Approve termination |
| GET | `/{contractId}/completion/readiness` | Completion blockers/readiness |
| POST | `/{contractId}/completion/request` | Request completion |
| POST | `/{contractId}/completion/approve` | Approve completion (other party/admin) |
| POST | `/{contractId}/completion/reject` | Reject completion (other party/admin) |
| POST | `/{contractId}/completion/cancel` | Cancel own pending request |
| POST | `/{contractId}/complete` | Admin-override completion |
| POST | `/{contractId}/abort-before-signing` | Admin pre-signing cancel + escrow refund |

**Not on this controller, or any other, despite having a handler:** `POST /{contractId}/extend`, any replace-vehicle route, any early-return route. See §9.
