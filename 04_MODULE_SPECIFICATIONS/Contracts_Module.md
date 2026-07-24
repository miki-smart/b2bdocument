# Contracts Module — Specification

**Module Name:** Contracts
**Version:** 2.0 (rewritten against running code)
**Last verified against code:** 2026-07-23
**Location:** `Modules/Contracts/**` inside `Marketplace.API` (.NET 9 modular monolith) — this is a folder/namespace inside one deployable, not a separate service
**Related documents:** `MVP_CONTRACT_STATE_MACHINE.md` (full state machine), `backlog/mvp/epic-06-contract-management.md`

---

## Overview

### Purpose

The Contracts module owns the legal/operational agreement between a Business and a Provider — from the moment a bid is awarded or a Direct Rental request is accepted, through escrow, vehicle assignment, dual-party OTP signing, delivery-driven activation, day-to-day tracking, and termination/completion. It does not compute pricing (Marketplace module), move money (Finance module), or run OTP delivery verification (Delivery module) — it reacts to their events and orchestrates the contract's own status.

### Two creation paths, one aggregate

`Contract.SourceType` is either `"RFQ"` or `"DIRECT_RENTAL"`:
- **RFQ path:** `BidAwardedEvent` (Marketplace module) → `BidAwardedEventHandler` → `CreateContractCommand`. Resolves the provider's commission rate from their tier via MasterData, groups all awards for that bid into contract line items.
- **Direct Rental path:** `DirectRentalRequestAcceptedEvent` / `...PartiallyAcceptedEvent` → `DirectRentalRequestAcceptedEventHandler` → `CreateDirectRentalContractCommand`. Idempotent — re-syncs assignments if a contract already exists for that request instead of duplicating. Vehicles may already be attached at creation (chosen during booking), so this path can skip straight to `PENDING_SIGNING`.

Both paths produce the same `Contract` entity, the same status field, and the same downstream lifecycle.

### Responsibilities

**Contract lifecycle management**
- Creation from RFQ awards or Direct Rental acceptance
- Automatic escrow locking with retry, and manual retry after failure
- Vehicle-assignment sub-lifecycle (provider attaches specific vehicles before signing)
- Dual-party OTP terms acceptance (separate from delivery OTP)
- Delivery-driven activation (status derives from real, OTP-confirmed handovers)
- Termination (request → approve)
- Two-party completion (request → approve/reject/cancel, or admin override)
- Pre-signing cancellation (admin abort, or automatic escrow-timeout cancellation)

**Vehicle assignment**
- Linking specific vehicles to contract line items, enforcing quantity and status rules
- Tracking each assignment's own status (`ASSIGNED`/`DELIVERED`/`RETURNED`/`REPLACED`/`REMOVED`)
- Vehicle replacement is modeled but not functionally wired end-to-end (see Known Gaps)

**Policy & terms**
- Snapshotting the active contract policy (`ContractPolicySnapshot`, JSON) at contract creation
- Binding contract signing to a specific `ContractTermsVersion` (MasterData module)

**Amendment/penalty modeling**
- `ContractAmendment` and `ContractPenalty` entities exist with full domain behavior (`Sign()`/`Reject()`, `MarkPaid()`/`Waive()`/`Dispute()`) but **neither has a creation code path anywhere in the system** — see Known Gaps.

---

## Database Schema

Tables actually mapped by the module (10, not the 9 previously documented — `contract_completion_requests` and `contract_status_history` were missing from earlier versions of this doc, and `early_return_notices` was never listed):

| Table | Schema | Purpose |
|---|---|---|
| `contracts` | default | Master contract record (`Contract`) |
| `contract_line_items` | default | Per-line-item quantities/status (`ContractLineItem`) |
| `contract_vehicle_assignments` | default | Per-vehicle assignment tracking (`ContractVehicleAssignment`) |
| `contract_party_businesses` | `contracts` | Immutable business snapshot at contract creation |
| `contract_party_providers` | `contracts` | Immutable provider snapshot at contract creation |
| `contract_policy_snapshots` | `contracts` | JSON snapshot of the active policy at creation |
| `contract_amendments` | `contracts` | Amendment records (entity ready; nothing creates rows today) |
| `contract_penalties` | `contracts` | Penalty records (entity ready; nothing creates rows today) |
| `contract_event_logs` | `contracts` | Generic audit log entity (separate from status history) |
| `contract_status_history` | `contracts` | Status transition audit trail (`ContractStatusHistory`) — coverage is partial, not every transition writes a row |
| `contract_terms_acceptances` | `contracts` | Dual-party OTP terms-acceptance state (`ContractTermsAcceptance`) |
| `early_return_notices` | `contracts` | Notice-then-process records for early returns — entity/handler exist, but the command is never invoked from anywhere (no controller route, no other module calls it) |
| `contract_completion_requests` | `contracts` | Audit trail of every completion request attempt and its resolution |

---

## Module Structure (actual folders)

```
Modules/Contracts/
├── Domain/
│   ├── Entities/
│   │   ├── Contract.cs
│   │   ├── ContractLineItem.cs
│   │   ├── ContractVehicleAssignment.cs
│   │   ├── ContractPartyBusiness.cs
│   │   ├── ContractPartyProvider.cs
│   │   ├── ContractPolicySnapshot.cs
│   │   ├── ContractAmendment.cs        (no write path — see Known Gaps)
│   │   ├── ContractPenalty.cs          (no write path — see Known Gaps)
│   │   ├── ContractEventLog.cs
│   │   ├── ContractStatusHistory.cs
│   │   ├── ContractTermsAcceptance.cs  (dual-party OTP e-signature)
│   │   └── EarlyReturnNotice.cs        (unreachable — see Known Gaps)
│   ├── Enums/
│   │   ├── ContractStatus.cs      (17 members — NEVER referenced anywhere else in code; real status strings and enum values diverge, see MVP_CONTRACT_STATE_MACHINE.md §1)
│   │   └── ContractLineStatus.cs  (8 members — also diverges from the 7 real line-item status strings)
│   ├── Events/
│   │   ├── ContractCreatedEvent.cs
│   │   ├── ContractEscrowLockedEvent.cs   (NOT activation — published right after escrow lock)
│   │   ├── ContractActivatedEvent.cs      (published only when ALL vehicles are delivered)
│   │   ├── ContractTermsAcceptedEvent.cs
│   │   ├── VehicleAssignedEvent.cs / VehicleUnassignedEvent.cs
│   │   └── ContractLifecycleEvents.cs (ContractTerminatedEvent, ContractCompletionRequestedEvent, ContractCompletionApprovedEvent, etc.)
│   ├── ContractStatusProgression.cs      (line-item → contract status upgrade helper)
│   ├── ContractAssignmentRules.cs        (where vehicles may be assigned)
│   └── ContractVehicleBlockingRules.cs   (when an assignment blocks vehicle reuse)
│
├── Application/
│   ├── Contract/Commands/
│   │   ├── CreateContract/, CreateDirectRentalContract/
│   │   ├── AssignVehicle/, UnassignVehicle/, ResetVehicleAssignments/, ResetContractToPendingVehicleAssignment/
│   │   ├── InitiateContractTermsAcceptance/, VerifyContractTermsOtp/
│   │   ├── RequestTermination/, ApproveTermination/
│   │   ├── RequestContractCompletion/, ApproveContractCompletion/, RejectContractCompletion/, CancelContractCompletion/, CompleteContract/
│   │   ├── AbortContractBeforeSigning/
│   │   ├── InitiateEarlyReturn/ (unreachable, no caller)
│   │   └── ContractCompletionSettlementGuard.cs (shared prerequisite checks)
│   ├── Commands/ (a second, flatter folder — inconsistent with the nested folder above)
│   │   ├── ExtendContractCommand.cs   (no controller route — see Known Gaps)
│   │   └── ReplaceVehicleCommand.cs   (no controller route — see Known Gaps)
│   ├── Contract/Queries/
│   │   ├── GetContractById/, GetAllContracts/, GetContractsByBusinessId/, GetContractsByProviderId/
│   │   ├── GetAvailableVehiclesForAssignment/, GetVehicleAssignments/
│   │   ├── GetContractCompletionReadiness/, GetContractStatusHistory/
│   │   └── GetContractTermsAcceptanceStatus/
│   └── EventHandlers/
│       ├── BidAwardedEventHandler.cs
│       ├── DeliveryConfirmedEventHandler.cs
│       ├── DeliveryReturnConfirmedEventHandler.cs
│       └── DirectRentalRequestAcceptedEventHandler.cs
│
└── Infrastructure/
    ├── Configurations/ContractsConfigurations.cs (EF Core mappings)
    ├── Repositories/ (Contract, ContractAmendment, ContractPenalty, ContractStatusHistory, ContractTermsAcceptance, EarlyReturnNotice)
    └── Services/
        ├── ContractNumberGenerator.cs      (CTR-YYMMDD-XXXX)
        ├── ContractVehicleAssignmentService.cs (assignment application + status propagation, shared by RFQ and Direct Rental paths)
        └── VehicleValidationService.cs
```

Two other files live outside the `Contracts/Application/Contract/Commands/` tree, directly under `Contracts/Application/Commands/`: `ExtendContractCommand.cs` and `ReplaceVehicleCommand.cs`. This isn't just a naming inconsistency — it correlates with the fact that neither has a controller route. They read as commands built ahead of their HTTP wiring and never finished.

---

## Core Entities (field-level)

### Contract
- `SourceType` (`"RFQ"` | `"DIRECT_RENTAL"`), `RFQId`/`RFQBidAwardId` or `DirectRentalRequestId` (mutually exclusive)
- `BusinessId`, `ProviderId`, `ContractNumber`, `Status` (string — see state machine doc), `StartDate`, `EndDate`, `TotalContractValue`
- `ActivatedAt` (stamped once, first time `Status` becomes `ACTIVE`), `FinalSettlementProcessed`
- `TerminationRequestedBy`/`TerminationRequestedAt`/`TerminationReason` — **also reused, unrelated, by `ExtendEndDate()`, which overwrites `TerminationReason` with an `"EXTENDED: ..."` note.** Extension and termination share one text field; there is no dedicated extension-audit field.
- Computed: `DurationDays`, `IsLongTerm` (`>= 30` days), `IsRFQBased`, `IsDirectRental`
- Navigation: `BusinessParty`, `ProviderParty`, `LineItems`, `VehicleAssignments`, `Amendments`, `Penalties`, `CompletionRequests`, `TermsAcceptance`

### ContractLineItem
- `ContractId`, `RFQLineItemId` **or** `DirectRentalRequestLineItemId`, `QuantityAwarded`, `QuantityActive`, `QuantityDelivered`, `QuantityReturned`, `UnitAmount`, `TotalAmount`, `CommissionRate`, `DurationDays`, `Status`
- `TotalAmount = QuantityAwarded × UnitAmount × DurationDays` — computed once at creation, not recalculated on partial return

### ContractVehicleAssignment
- `ContractId`, `ContractLineItemId`, `VehicleId`, `AssignedAt`, `ReleasedAt`, `DeliveredAt`, `RemovedReason`, `Status` (string, no enum type)

### ContractTermsAcceptance (dual-party OTP e-signature)
- `ContractId`, `TermsVersionId`, `TermsVersionNumber`
- Per party (business/provider, fully independent): `{Party}OtpCode` (6 digits, cleared after use), `{Party}OtpExpiresAt` (5 min), `{Party}OtpConfirmed`, `{Party}OtpConfirmedAt`, `{Party}OtpLastSentAt` (60s resend cooldown)
- `AcceptedAt` — stamped only once both parties have confirmed
- This is entirely distinct from delivery-confirmation OTP (Epic 07 / Delivery module) — different entity, different table, different purpose

### ContractCompletionRequest (audit trail, one row per attempt)
- `ContractId`, `RequestedBy`, `RequestedByParty` (`BUSINESS`|`PROVIDER`), `RequestedAt`
- `Resolution`: `PENDING` → `APPROVED` | `REJECTED` | `ADMIN_OVERRIDE` | `CANCELLED` — the entity's own doc comment lists only the first three outcomes; `CANCELLED` (from a requester withdrawing their own request) is real but undocumented there
- `ResolvedBy`, `ResolvedByParty`, `ResolvedAt`, `RejectionReason`

### ContractAmendment (no write path today)
- `ContractId`, `AmendmentNumber`, `Type` (`EXTENSION`|`SCOPE_CHANGE`|`TERMINATION`), `Description`, `NewEndDate`, `NewTotalValue`, `Status` (`DRAFT`|`SIGNED`|`REJECTED`), `SignedAt`
- `ContractAmendment.Create()` has zero call sites anywhere in the backend. The only *consumer* of this entity is `UnassignVehicleCommandHandler`, which requires a signed `SCOPE_CHANGE` amendment to allow replacing a vehicle after delivery — since nothing can create one, that branch can never actually be satisfied.

### ContractPenalty (no write path today)
- `ContractId`, `ReasonCode` (e.g. `CANCELLATION`/`LATE_DELIVERY`/`DAMAGE`), `Amount`, `AppliedToParty` (`PROVIDER`|`BUSINESS`), `Description`, `Status` (`PENDING`|`PAID`|`WAIVED`|`DISPUTED`)
- `ContractPenalty.Create()` has zero call sites anywhere. `Contract.TerminateEarly()` computes a penalty *amount* and writes it as free text into `TerminationReason`, but doesn't create a `ContractPenalty` row — and `TerminateEarly()` itself has zero callers too.

### EarlyReturnNotice (unreachable today)
- `ContractId`, `LineItemId`, `VehicleId`, `RequestedBy`, `Reason`, `NoticeSubmittedAt`, `EarliestReturnDate` (policy-driven grace period, default 7 days), `Status` (`PENDING`|`PROCESSED`|`CANCELLED`)
- Fully implemented notice→process workflow in `InitiateEarlyReturnCommandHandler`, but the command has no controller route and is never dispatched from any event handler either. Real vehicle returns — early or on-schedule — happen exclusively via the Delivery module's `DeliveryReturnConfirmedEvent`, which has no notice-period concept.

---

## Key Workflows

### 1. Contract creation (RFQ or Direct Rental)
Snapshots business/provider/policy → creates line items → initial status always `PENDING_ESCROW` → `ContractCreatedEvent` published → `SYSTEM_CREATE` row in `ContractStatusHistory`.

### 2. Automatic escrow lock (Finance module reacting to `ContractCreatedEvent`)
`Σ line item (UnitAmount × QuantityAwarded × min(DurationDays, 30))` locked from business `MAIN` wallet to `ESCROW` wallet, double-entry. 5 retries (1/2/4/8/16s). Success → `ActivateAfterEscrowLock()`. Failure → `ESCROW_LOCK_FAILED`, manually retryable via `RetryEscrowLockCommand`.

### 3. Vehicle assignment
Provider assigns 1..N vehicles per call to a line item; contract auto-advances to `PENDING_SIGNING` once every line item is fully assigned. Reset endpoints exist to wipe and restart assignment.

### 4. Dual-party OTP signing
Independent 6-digit OTP per party, 5-minute expiry, 60s resend cooldown; both must confirm before `PENDING_SIGNING → PENDING_DELIVERY` (the intermediate `SIGNED` value is set and overwritten within the same method call and is never persisted or logged as a separate history row — see state machine doc §2.5).

### 5. Delivery-driven activation
`DeliveryConfirmedEventHandler` marks the assignment `DELIVERED`, advances line-item/contract status, generates the settlement schedule on the *first* delivery (anchored to that date, not creation date), and publishes `ContractActivatedEvent` only once every awarded vehicle is delivered.

### 6. Returns
`DeliveryReturnConfirmedEventHandler` marks the assignment `RETURNED`, releases the vehicle to `APPROVED`, recomputes status (`PARTIALLY_RETURNED`), and — once every assignment is returned — sends an admin in-app notification flagging completion-eligibility. No automatic settlement or completion follows.

### 7. Termination
`RequestTerminationCommand` (handler-enforced: only from `ACTIVE`/`PARTIALLY_RETURNED`, narrower than the domain method's own guard) → `TERMINATION_REQUESTED` → `ApproveTerminationCommand` (any party or admin, no self-check) → `TERMINATED`, force-terminating any still-`ACTIVE` line items. No reject/withdraw path exists.

### 8. Two-party completion
Only from `PARTIALLY_RETURNED`. Request → other party (or admin) approves/rejects; requester can cancel their own pending request; admin can bypass entirely via `CompleteContractCommand`. All four paths share the same prerequisite checks (`ContractCompletionSettlementGuard`).

### 9. Pre-signing cancellation
Admin `AbortContractBeforeSigningCommand` (from any pre-signing status) refunds locked escrow, releases vehicles, resets line items, sets `CANCELLED` (not in the `ContractStatus` enum), writes a history row. `EscrowTimeoutJob` does the equivalent automatically for contracts stuck too long in `PENDING_ESCROW`, but does **not** write a history row — an inconsistency worth fixing.

---

## Known Gaps (verified by code search, zero call sites found for each)

1. **`POST /contracts/{id}/extend` does not exist on any controller.** `ExtendContractCommandHandler` is fully implemented and the web app's `ExtendContractDialog.tsx` calls this exact route — it 404s today. Highest-priority gap in the module.
2. **Vehicle replacement (`ReplaceVehicleCommand`) has no controller route.**
3. **Post-delivery vehicle replacement via `UnassignVehicleCommand` is blocked** because it requires a signed `SCOPE_CHANGE` `ContractAmendment`, and nothing in the system can create one.
4. **`ContractPenalty` is never created** by any flow, despite UI copy implying penalties are applied on termination.
5. **`InitiateEarlyReturnCommand` is fully unreachable** — no controller route, no event-handler invocation.
6. **`PENDING_ACTIVATION`, `DISPUTED`, `ON_HOLD` contract statuses are never set** by any code path, despite being defined in the enum and referenced in guard/rule logic.
7. **`ResetContractToPendingVehicleAssignmentCommand`'s precondition (`Status == PENDING_ACTIVATION`) can never be satisfied**, since nothing sets that status — the endpoint always fails validation.
8. **Status-history logging is inconsistent** — escrow lock, delivery/return-driven transitions, dual-OTP signing, and `EscrowTimeoutJob` cancellations do not write `ContractStatusHistory` rows; contract creation, termination approval, admin completion, and admin pre-signing abort do.

---

## Integration Points

- **Finance module:** consumes `ContractCreatedEvent` (escrow lock), reads settlement schedules for completion-readiness checks, provides wallet balance/refund operations used by `RetryEscrowLockCommand` and `AbortContractBeforeSigningCommand`.
- **Delivery module:** publishes `DeliveryConfirmedEvent`/`DeliveryReturnConfirmedEvent` consumed by this module; this module's `UnassignVehicleCommand` reads/cancels `DeliverySession` rows directly.
- **MasterData module:** provides active `ContractTermsVersion` (signing), `ContractPolicyRule` (early-return notice period, currently unused end-to-end), commission strategy/tier lookups (used at contract creation to price the commission rate).
- **Notifications module:** in-app/SMS/email notifications on OTP generation, termination request/approval, completion request/approval/rejection/cancellation, escrow-lock failure (partially — see Known Gaps), end-of-term timeout.
- **Marketplace module:** source of `BidAwardedEvent`/`DirectRentalRequestAcceptedEvent` that trigger contract creation.
