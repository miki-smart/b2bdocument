# Movello MVP — Direct Rental Request State Machine
## State Definitions, Transitions & Timeouts — Version 2.0

**Document Status:** AUTHORITATIVE (Direct Rental lifecycle)
**Last verified against code: 2026-07-23** — verified directly against `Modules/Marketplace/Domain/Entities/DirectRentalRequest*.cs`, `Controllers/Marketplace/DirectRentalRequestController.cs`, `Controllers/Admin/AdminDirectRentalController.cs`, `Modules/Marketplace/Application/DirectRentalRequest/Commands/RespondToDirectRentalRequestCommand.cs`, `Modules/Marketplace/Domain/Services/DirectRentalRequestHistoryTriggers.cs`, and `BackgroundServices/ExpireDirectRentalRequestsJob.cs`. Version 1.0 (June 27, 2026) was already reasonably accurate; this pass confirms every transition against the running domain model and corrects two omissions (admin-on-behalf-of history triggers; the request-level all-vehicles-rejected reason string).

**Related documents:**
- [MVP_DIRECT_RENTAL_SPECIFICATION.md](./MVP_DIRECT_RENTAL_SPECIFICATION.md) — business rules, domain model, API surface (also rewritten 2026-07-23)
- `backlog/post-mvp/epic-21-direct-rental.md` — the formal backlog entry for this feature (2026-07-23), user-story-level detail
- `project-docs/18_Implementation_Coverage_Audit.md` §1.1, §7.1 — how this feature was discovered to be undocumented at the epic level
- [MVP_CONTRACT_STATE_MACHINE.md](./MVP_CONTRACT_STATE_MACHINE.md) — the contract lifecycle a Direct Rental request bridges into on acceptance

---

## 1. State Overview

### 1.1 Request-Level States

`DirectRentalRequest.Status` (`Modules/Marketplace/Domain/Entities/DirectRentalRequest.cs`) is a plain string column, not a C# enum — the six values below are the only ones any code path produces.

| State | Category | Terminal |
|-------|----------|----------|
| `PENDING` | Awaiting provider | No |
| `ACCEPTED` | Provider accepted all | Yes* |
| `PARTIALLY_ACCEPTED` | Provider accepted some | Yes* |
| `REJECTED` | Provider rejected all | Yes |
| `EXPIRED` | System timeout (48h) | Yes |
| `CANCELLED` | Business cancelled | Yes |

\*Terminal for the **request** lifecycle; triggers contract creation for accepted vehicles. The resulting contract has its own, separate lifecycle (see `MVP_CONTRACT_STATE_MACHINE.md`) — the request entity itself never transitions to a "contract linked" status value; see §8 for how the bridge is actually recorded.

### 1.2 Sub-Entity States

**Line item** (`DirectRentalRequestLineItem.Status`): `PENDING` → `ACCEPTED` | `PARTIALLY_ACCEPTED` | `REJECTED`, derived from its vehicles by `UpdatePartialAcceptanceStatus()` (0/N accepted → `REJECTED`; N/N → `ACCEPTED`; else → `PARTIALLY_ACCEPTED`).

**Vehicle row** (`DirectRentalRequestVehicle.IsAccepted`): `null` (pending) → `true` | `false`, set exactly once by `Accept()`/`Reject()` — both methods throw if a decision already exists, so a vehicle-level decision cannot be changed once made.

---

## 2. State Diagram

```
                    ┌─────────────┐
                    │  (created)  │
                    └──────┬──────┘
                           │ USER_SUBMIT / ADMIN_SEND
                           ▼
                    ┌─────────────┐
         ┌─────────│   PENDING   │─────────┐
         │         └──────┬──────┘         │
         │                │                │
  USER_CANCEL      provider/admin     SYSTEM_EXPIRE
  (business)          respond           (48h job,
         │                │            hourly check)
         ▼                ▼                ▼
  ┌───────────┐    ┌──────────────┐  ┌─────────┐
  │ CANCELLED │    │ see decision │  │ EXPIRED │
  └───────────┘    │   matrix §4  │  └─────────┘
                   └──────┬───────┘
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
   ┌──────────┐  ┌──────────────────┐  ┌──────────┐
   │ ACCEPTED │  │PARTIALLY_ACCEPTED│  │ REJECTED │
   └────┬─────┘  └────────┬─────────┘  └──────────┘
        │                   │
        └─────────┬─────────┘
                  │ SYSTEM_CONTRACT_CREATED
                  ▼
     Contract (SourceType = DIRECT_RENTAL)
```

All six request states are reachable only from `PENDING`; none of the five terminal states has any outbound transition (confirmed — no method on `DirectRentalRequest` mutates `Status` away from `ACCEPTED`/`PARTIALLY_ACCEPTED`/`REJECTED`/`EXPIRED`/`CANCELLED`).

---

## 3. State Definitions

### 3.1 PENDING

**Entry:** Cart submit succeeds — `DirectRentalRequest.Create(...)` sets `Status = "PENDING"`, `ExpiresAt = DateTime.UtcNow.AddHours(48)`. `Create()` also validates `startDate < endDate` and `startDate >= DateTime.UtcNow.Date` (start date cannot be in the past) and `totalAmount > 0` — violations throw at creation, before the row ever exists.

**Allowed actions:**

| Actor | Action |
|-------|--------|
| Business | View (`GET .../requests`, `.../requests/{id}`), cancel (`POST .../cancel`) |
| Provider | View, accept-preview (`GET .../accept-preview`), respond (`POST .../respond`) |
| Admin | All of the above, on behalf of the business or provider, via `AdminDirectRentalController` |
| System | Hourly expiry sweep (`ExpireDirectRentalRequestsJob`) |

**Exit transitions:**

| To | Trigger | Guard (enforced in code) |
|----|---------|---------------------------|
| ACCEPTED | provider (or admin-on-behalf) responds, all vehicles accepted | `Status == "PENDING"`, not past `ExpiresAt`; if `IsAllOrNone`, every line item must already be `ACCEPTED` |
| PARTIALLY_ACCEPTED | provider responds, some vehicles accepted | `Status == "PENDING"`, not expired, `IsAllOrNone == false`, at least one line item `ACCEPTED`/`PARTIALLY_ACCEPTED` |
| REJECTED | provider responds, zero vehicles accepted, or explicit reject | `Status == "PENDING"`; request-level reject requires a reason ≥ 10 characters |
| CANCELLED | business calls `Cancel()` | `Status == "PENDING"` and `DateTime.UtcNow <= ExpiresAt` |
| EXPIRED | `ExpireDirectRentalRequestsJob` (hourly) | `Status == "PENDING"` and `ExpiresAt < now` |

**Vehicle locking:** vehicles referenced by a non-expired `PENDING` request are excluded from `GET /api/marketplace/direct-rental/vehicles` browse results (`IVehicleAvailabilityService`) — they become visible again only on `CANCELLED`/`REJECTED`/`EXPIRED`.

---

### 3.2 ACCEPTED

**Entry:** `DirectRentalRequest.Accept()` — requires `Status == "PENDING"`, not past `ExpiresAt`, and (if `IsAllOrNone`) every line item already `ACCEPTED`. Called by `RespondToDirectRentalRequestCommandHandler` when `acceptedCount == totalCount`.

**Effects:**
- `RespondedAt = DateTime.UtcNow`
- `DirectRentalRequestAcceptedEvent` raised (domain event, dispatched on `SaveChanges`)
- `DirectRentalRequestAcceptedEventHandler` (Contracts module) → `CreateDirectRentalContractCommand` → contract created for all accepted vehicles
- History row recorded: trigger `SYSTEM_CONTRACT_CREATED`, `to_status = "CONTRACT_LINKED"` (see §8 — this is a history-table label, not a mutation of `DirectRentalRequest.Status`, which remains `ACCEPTED`)

**Terminal:** no further provider/business mutation of the request itself; the request DTO exposes `contractId` once the contract exists.

---

### 3.3 PARTIALLY_ACCEPTED

**Entry:** `DirectRentalRequest.AcceptPartial()` — requires `Status == "PENDING"`, not expired, `IsAllOrNone == false`, and at least one line item accepted/partially-accepted. Called when `0 < acceptedCount < totalCount`.

**Effects:** identical contract-bridge path as ACCEPTED (`DirectRentalRequestAcceptedEventHandler` also handles `DirectRentalRequestPartiallyAcceptedEvent`), but `CreateDirectRentalContractCommandHandler` includes only vehicles where `IsAccepted == true`. Rejected vehicles in the same request are not placed on any contract; their rejection reasons remain on the `DirectRentalRequestVehicle` rows.

---

### 3.4 REJECTED

**Entry:** `DirectRentalRequest.Reject(reason)` — requires `Status == "PENDING"` and `reason` non-empty, ≥ 10 characters. Two code paths reach this:
1. Provider rejects every vehicle individually → handler calls `Reject("All vehicles rejected by provider.")` (a fixed, 32-character string — always satisfies the ≥10-char guard).
2. (Domain method also supports a direct request-level reject with a caller-supplied reason, though the current `RespondToDirectRentalRequestCommand` always uses vehicle-level responses and only synthesizes the fixed string above — no UI path submits a custom whole-request rejection reason today.)

**Effects:** `RejectionReason` populated at request level; per-vehicle rejection reasons (each independently validated ≥ 5 characters by `DirectRentalRequestVehicle.Reject()`) remain on the vehicle rows; vehicles unlocked for other businesses.

---

### 3.5 EXPIRED

**Entry:** `DirectRentalRequest.Expire()` — guard: only from `PENDING` (throws otherwise). Called exclusively by `ExpireDirectRentalRequestsJob`.

**Effects:**
- `DirectRentalRequestExpiredEvent` raised → business notified
- Vehicles unlocked for rebrowsing
- History row: trigger `SYSTEM_EXPIRE`

---

### 3.6 CANCELLED

**Entry:** `DirectRentalRequest.Cancel(reason?)` — guard: `Status == "PENDING"` and `DateTime.UtcNow <= ExpiresAt` (both checked; expired-but-still-PENDING requests cannot be cancelled — they can only be picked up by the expiry job).

**Effects:**
- Optional `CancelReason` (trimmed; stored as `null` if blank), `CancelledAt` set
- `DirectRentalRequestCancelledEvent` raised → provider notified
- Vehicles unlocked
- Provider can no longer call `respond` (request is no longer `IsActive`)

---

## 4. Transition Matrix

| From \ To | PENDING | ACCEPTED | PARTIAL | REJECTED | EXPIRED | CANCELLED |
|-----------|---------|----------|---------|----------|---------|-----------|
| **PENDING** | — | ✓ | ✓ | ✓ | ✓ | ✓ |
| **ACCEPTED** | — | — | — | — | — | — |
| **PARTIALLY_ACCEPTED** | — | — | — | — | — | — |
| **REJECTED** | — | — | — | — | — | — |
| **EXPIRED** | — | — | — | — | — | — |
| **CANCELLED** | — | — | — | — | — | — |

All five non-`PENDING` states are terminal and immutable — confirmed by reading every public mutator on `DirectRentalRequest`: `Accept()`, `AcceptPartial()`, `Reject()`, `Expire()`, `Cancel()` all guard on `Status == "PENDING"` as their sole entry condition (plus the expiry-window check where relevant). There is no "reopen" or "re-submit" path; a business that wants another attempt after rejection/expiry/cancellation must add the vehicles to a new cart and submit again.

---

## 5. Timeout Rules

| Rule | Value | Enforcement |
|------|-------|-------------|
| Provider response window | **48 hours** from request creation | `ExpiresAt = DateTime.UtcNow.AddHours(48)`, set in `Create()` |
| Expiry job interval | Every **1 hour**, with a 30-second startup delay | `ExpireDirectRentalRequestsJob` (`BackgroundService`, `_interval = TimeSpan.FromHours(1)`) |
| Cancel deadline | Before `ExpiresAt`, while `PENDING` | `DirectRentalRequest.Cancel()` — both conditions checked explicitly |

The expiry job queries `Status == "PENDING" && ExpiresAt < now && !IsDeleted`, calls `Expire()` per row inside a try/catch so one failing request doesn't stop the batch, and records a `SYSTEM_EXPIRE` history entry via `IDirectRentalRequestHistoryService` before a single `SaveChangesAsync()` call (which dispatches all queued `DirectRentalRequestExpiredEvent`s together). Job duration and error counts are instrumented via `MarketplaceMetrics.BackgroundJobDuration`/`BackgroundJobErrors`, labeled `"ExpireDirectRentalRequestsJob"`.

---

## 6. Validation Rules by Transition

### 6.1 USER_SUBMIT / ADMIN_SEND (implicit → PENDING)

Enforced in `SubmitCartCommandHandler`:
- Business must be active/operable (`IAccountOperationGuard.EnsureBusinessCanOperateAsync`)
- Cart must exist and have at least one non-deleted item
- `GetCartSubmitPreviewQuery.CanSubmit` must be true (`availableBalance >= cartTotal`) — else throws `UnprocessableEntityException` with code `INSUFFICIENT_WALLET_BALANCE` (HTTP 422)
- Vehicle availability is re-checked inside the transaction; any vehicle locked since being added to cart aborts the entire submit (all providers, not just the affected one) with the conflicting plate numbers listed
- The whole grouping-and-create operation runs inside an explicit DB transaction where the provider supports one (skipped only for the EF Core InMemory test provider)
- When an admin submits on a business's behalf (`AdminDirectRentalController.SubmitCart`), the history trigger is `ADMIN_SEND` instead of `USER_SUBMIT`, and the history row's actor is the admin's user-account id with a note identifying the business

### 6.2 PROVIDER_RESPOND / ADMIN_RESPOND_*

Enforced in `RespondToDirectRentalRequestCommandHandler`, in this order:
1. Provider must be active/operable (`IAccountOperationGuard.EnsureProviderCanOperateAsync`)
2. Request must exist and belong to the responding provider
3. Request must be `IsActive` (`Status == "PENDING" && DateTime.UtcNow <= ExpiresAt`)
4. The response set's vehicle IDs must exactly match the request's vehicle IDs (`SetEquals`) — a partial response set is rejected outright, not silently accepted as partial
5. Every rejected vehicle must carry a non-empty `RejectionReason` (domain-level, `DirectRentalRequestVehicle.Reject()` additionally enforces ≥ 5 characters)
6. If `IsAllOrNone == true` and the response mixes accept/reject (`0 < acceptedCount < totalCount`), the whole call throws — no partial commit
7. **Fleet capacity gate** — for every vehicle in the response marked accepted, `IProviderFleetCapacityService.GetDirectRentalAcceptCheckAsync()` is called; a blocking result throws `FleetCapacityConflictException` with one of the codes in §8 of the specification doc, and the exception is thrown *before* any vehicle decisions are applied (i.e., the whole respond call fails atomically, not vehicle-by-vehicle)
8. Only after all of the above pass are `Accept()`/`Reject()` applied per vehicle, then `UpdatePartialAcceptanceStatus()` per line item, then the request-level `Accept()`/`AcceptPartial()`/`Reject()` call

When an admin responds on a provider's behalf (`AdminDirectRentalController.RespondToRequest`), the history trigger becomes `ADMIN_RESPOND_ACCEPT` / `ADMIN_RESPOND_PARTIAL` / `ADMIN_RESPOND_REJECT` (see §9) and the history actor/notes identify the acting admin and the provider they acted for.

### 6.3 USER_CANCEL

- Business must own the request (`BusinessId` match, enforced by the controller resolving the caller's own business id)
- `Status == "PENDING"`
- `DateTime.UtcNow <= ExpiresAt`

---

## 7. Line Item & Vehicle Aggregation

After every provider (or admin-on-behalf) respond call, each affected line item calls `UpdatePartialAcceptanceStatus()`:

| Accepted vehicles | Line item status |
|-------------------|------------------|
| 0 / N | `REJECTED` |
| N / N | `ACCEPTED` |
| 1..N-1 / N | `PARTIALLY_ACCEPTED` |

The request-level status is then derived independently from the same accept/reject counts across *all* vehicles in the request (§3, §6.2) — it is not a roll-up of line-item statuses, though in practice the two always agree since both are computed from the same underlying vehicle decisions in the same command.

---

## 8. Contract Linkage (Post-Acceptance)

On `ACCEPTED` or `PARTIALLY_ACCEPTED`, `DirectRentalRequestAcceptedEventHandler` (Contracts module) sends `CreateDirectRentalContractCommand`. The handler:
- Is **idempotent**: if a contract already exists for `DirectRentalRequestId` (`GetByDirectRentalRequestIdAsync`), it re-syncs vehicle assignments instead of creating a duplicate contract — safe to re-trigger.
- Includes only vehicles where `IsAccepted == true`, grouped by the originating `DirectRentalRequestLineItem`.
- Creates `Contract.CreateFromDirectRental(...)` with `SourceType = "DIRECT_RENTAL"` and `DirectRentalRequestId` set; vehicle assignments are pre-created directly (no separate post-award assignment step, unlike RFQ-sourced contracts).
- Resolves the provider's commission rate via current tier → `CommissionStrategies.CalculateCommissionAsync`, falling back to a hardcoded `0.05m` (5%) default if tier/strategy lookup fails for any reason.
- On success, records a **request-history row** with trigger `SYSTEM_CONTRACT_CREATED` and `to_status = "CONTRACT_LINKED"` — this is a label written into `direct_rental_request_status_history` only; it is not a value `DirectRentalRequest.Status` itself ever takes (the request row's actual `Status` column stays `ACCEPTED`/`PARTIALLY_ACCEPTED` forever). Contract linkage for API/UI purposes is read via `Contract.DirectRentalRequestId` and the request DTO's `contractId` field, not via the request's own status.
- Publishes the standard `ContractCreatedEvent` afterward, which is what actually triggers escrow locking (Finance module) — see `backlog/mvp/epic-08-wallet-escrow.md` and `14_Wallet_Engine_Flow_Specification.md`.

---

## 9. Status History Triggers (as implemented)

`DirectRentalRequestHistoryTriggers` (`Modules/Marketplace/Domain/Services/`) defines the complete, exhaustive set of trigger constants actually used — this list corrects Version 1.0, which omitted the four admin-on-behalf-of triggers:

| Trigger | Actor | Typical transition |
|---------|-------|-------------------|
| `USER_SUBMIT` | BUSINESS | (created) → PENDING |
| `ADMIN_SEND` | ADMIN (on behalf of business) | (created) → PENDING |
| `USER_CANCEL` | BUSINESS | PENDING → CANCELLED |
| `PROVIDER_ACCEPT` | PROVIDER | PENDING → ACCEPTED |
| `ADMIN_RESPOND_ACCEPT` | ADMIN (on behalf of provider) | PENDING → ACCEPTED |
| `PROVIDER_PARTIAL_ACCEPT` | PROVIDER | PENDING → PARTIALLY_ACCEPTED |
| `ADMIN_RESPOND_PARTIAL` | ADMIN (on behalf of provider) | PENDING → PARTIALLY_ACCEPTED |
| `PROVIDER_REJECT` | PROVIDER | PENDING → REJECTED |
| `ADMIN_RESPOND_REJECT` | ADMIN (on behalf of provider) | PENDING → REJECTED |
| `SYSTEM_EXPIRE` | SYSTEM | PENDING → EXPIRED |
| `SYSTEM_CONTRACT_CREATED` | SYSTEM | (ACCEPTED/PARTIALLY_ACCEPTED, unchanged) → history label `CONTRACT_LINKED` |

Every history row also records `triggeredByUserId`/`triggeredByUserType` (`"BUSINESS"`, `"PROVIDER"`, `"ADMIN"`, or `"SYSTEM"`) and, for admin-initiated rows, a free-text note identifying which business/provider the admin acted for (e.g. `"Admin submitted request on behalf of business {businessId}."`).

---

## 10. Business Rules Mapping

Rule IDs below are as used in `MVP_DIRECT_RENTAL_SPECIFICATION.md` §4 (this document's companion spec — the authoritative `MVP_AUTHORITATIVE_BUSINESS_RULES.md §19` cross-reference cited in v1.0 was not located in this repo pass and should be treated as a pointer to verify separately, not as a file this rewrite re-confirmed).

| State / Transition | Rule IDs |
|--------------------|----------|
| Submit → PENDING | BR-DR-001, 002 (vehicle eligibility), 003 (cart doesn't lock), 004, 005, 006, 007 |
| PENDING timeout | BR-DR-008 |
| Cancel | BR-DR-009 |
| Provider respond | BR-DR-010, 011, 012, 013 |
| Contract creation | BR-DR-014 |
| Direct-rental-enable guard | BR-DR-015 |

---

**END OF DIRECT RENTAL STATE MACHINE**
