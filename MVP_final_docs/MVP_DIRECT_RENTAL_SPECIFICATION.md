# Movello MVP — Direct Rental (DR) Specification
## Business Rules, Lifecycle, Flows & Integration — Version 2.0

**Document Status:** AUTHORITATIVE (Direct Rental domain)
**Last verified against code: 2026-07-23** — verified directly against `Modules/Marketplace/Domain/Entities/DirectRentalCart*.cs`, `DirectRentalRequest*.cs`, `Controllers/Marketplace/DirectRentalCartController.cs`, `DirectRentalRequestController.cs`, `DirectRentalVehicleController.cs`, `Controllers/Admin/AdminDirectRentalController.cs`, `Controllers/Identity/VehicleController.cs` (rate/enable/disable endpoints), `Modules/Marketplace/Application/DirectRentalCart/Commands/SubmitCartCommand.cs`, `Modules/Marketplace/Application/DirectRentalRequest/Commands/RespondToDirectRentalRequestCommand.cs`, `Modules/Marketplace/Application/DirectRentalRequest/Queries/GetDirectRentalAcceptPreviewQuery.cs`, `Modules/Contracts/Application/Contract/Commands/CreateDirectRentalContract/CreateDirectRentalContractCommandHandler.cs`, and `BackgroundServices/ExpireDirectRentalRequestsJob.cs`. Version 1.0 (June 27, 2026) was already directionally accurate and was used as source material for `backlog/post-mvp/epic-21-direct-rental.md`; this pass re-verifies every claim line-by-line against the running code and corrects the handful of details below that had drifted or were unconfirmed.

**Related documents:**
- [MVP_DIRECT_RENTAL_STATE_MACHINE.md](./MVP_DIRECT_RENTAL_STATE_MACHINE.md) — request-status state machine and transition matrix (also rewritten 2026-07-23)
- [MVP_CONTRACT_STATE_MACHINE.md](./MVP_CONTRACT_STATE_MACHINE.md) — the contract lifecycle a Direct Rental acceptance bridges into
- `backlog/post-mvp/epic-21-direct-rental.md` — formal backlog entry (10 user stories), the primary product-facing reference for this feature
- `project-docs/17_Direct_Rental_Product_Design_Brief.md` — product/UX brief
- `project-docs/18_Implementation_Coverage_Audit.md` §1.1, §7.1 — how this feature was found to be a fully-built, undocumented-at-the-epic-level product surface
- `backlog/mvp/epic-08-wallet-escrow.md`, `project-docs/service-specs/14_Wallet_Engine_Flow_Specification.md` — the escrow/wallet machinery a Direct-Rental-sourced contract enters (also rewritten 2026-07-23)
- `MVP_AUTHORITATIVE_BUSINESS_RULES.md` §19 (BR-DR-*) — cited as the authoritative rule-ID source in v1.0; this pass did not re-locate/re-verify that file, so treat the rule IDs in §4 below as pointers to confirm independently rather than as newly-verified in this rewrite

**Implementation reference:** `Marketplace.API` — Marketplace module (`DirectRentalCart`, `DirectRentalRequest`, `DirectRentalVehicle`, `ProviderFleetCapacityService`), Identity module (`Vehicle.IsAvailableForDirectRental`), Contracts module (`CreateDirectRentalContractCommandHandler`)

---

## 1. Purpose & Scope

### 1.1 What Direct Rental Is

Direct Rental is a **vehicle-specific, provider-catalog** booking channel alongside the RFQ/blind-bidding marketplace. A verified business browses provider-listed vehicles, adds them to a cart, and submits **Direct Rental Requests (DRRs)** — one request per provider. The provider accepts or rejects at **vehicle granularity**. Accepted vehicles flow into the **same contract, escrow, delivery, and settlement** machinery as RFQ awards (`Contract.SourceType = "DIRECT_RENTAL"`, `Contract.DirectRentalRequestId` set) — Direct Rental is purely an acquisition channel, not a parallel financial or legal model.

### 1.2 In Scope (MVP, as built)

| Capability | Description |
|------------|-------------|
| Provider catalog | Enable DR per vehicle, set daily rate (`Controllers/Identity/VehicleController.cs`) |
| Business browse & cart | Search/filter, add vehicles, edit dates |
| Cart submit | Wallet gate (estimate only, no lock), availability re-check, grouping by provider |
| Provider response | Per-vehicle accept/reject, all-or-none option, fleet-capacity gate |
| Status history | Immutable timeline (`direct_rental_request_status_history`) |
| Expiry | 48-hour provider response window, hourly sweep job |
| Business cancel | Cancel pending requests before provider responds |
| Contract bridge | Idempotent auto-create contract on accept / partial accept |
| Fleet segment capacity | Shared pool with RFQ bids & award assignments |
| Admin oversight | Platform-wide browse/request visibility + act-on-behalf-of for both business and provider |

### 1.3 Out of Scope (MVP)

- Multi-provider single checkout (cart splits into multiple DRRs — by design; see §6)
- Negotiated pricing after submit (rates are snapshotted at cart-add time)
- DR without provider opt-in (`Vehicle.IsAvailableForDirectRental` must be true)
- Instant booking without provider acceptance
- Any escrow lock at cart-submit time — see §12, this is a confirmed MVP limitation, not an oversight

---

## 2. Actors & Preconditions

| Actor | Preconditions |
|-------|----------------|
| **Business** | Active/verified; can operate per `IAccountOperationGuard.EnsureBusinessCanOperateAsync` |
| **Provider** | Active/verified per `IAccountOperationGuard.EnsureProviderCanOperateAsync`; vehicle `APPROVED`, daily rate > 0, DR enabled |
| **Admin** | `AdminOnly` authorization policy; acts through `AdminDirectRentalController`, never through the business/provider controllers directly |
| **System** | `ExpireDirectRentalRequestsJob` running (hourly `BackgroundService`, 30s startup delay) |

---

## 3. Domain Model

### 3.1 Aggregate Hierarchy

```
DirectRentalCart (per business, tracked by BusinessId, one active cart at a time)
  └── DirectRentalCartItem[] (one row per vehicle; soft-deleted on submit/removal)

DirectRentalRequest (per provider per submit)
  ├── requestNumber: DR-YYYYMMDD-NNN
  ├── businessId, providerId
  ├── startDate, endDate (date-only columns), totalAmount
  ├── isAllOrNone, specialInstructions (max 1000 chars)
  ├── expiresAt (createdAt + 48h)
  ├── respondedAt, cancelledAt, cancelReason, rejectionReason
  └── DirectRentalRequestLineItem[] (grouped by vehicleType)
        └── DirectRentalRequestVehicle[] (specific vehicleId + snapshot: plate, make, model, dailyRate, totalAmount)
```

Both `DirectRentalCartItem.TotalDays`/`TotalAmount` and `DirectRentalRequest.TotalDays` are computed properties (`[NotMapped]`), not stored columns: `TotalDays = (EndDate.Date - StartDate.Date).Days + 1` (inclusive of both ends).

### 3.2 Request Number Format

`DR-{yyyyMMdd}-{sequence}` — sequence is `(count of non-deleted requests created today) + 1`, zero-padded to 3 digits (e.g. `DR-20260627-001`). Generated per-provider-group inside `SubmitCartCommandHandler`, so a single multi-provider submit can produce sequential numbers within the same call.

### 3.3 Pricing

- `DirectRentalCartItem.TotalAmount` = `DailyRate × TotalDays` (computed, not stored)
- `DirectRentalRequestVehicle.TotalAmount` is stored at creation time as a **snapshot** of the cart item's computed total — it does not recompute if the underlying vehicle's rate changes later
- `DirectRentalRequest.TotalAmount` = sum of all its vehicles' snapshotted amounts, set once at `Create()`
- Cart-item `PATCH` (date change) recalculates `TotalAmount` live (computed property) but does not touch already-submitted requests

### 3.4 Vehicle Locking (Implicit)

Vehicles are **not** locked while only in a cart (BR-DR-003) — confirmed: `DirectRentalCart`/`DirectRentalCartItem` carry no lock/availability flag at all. Locks are entirely a function of what else references the vehicle:

| Lock source | Condition |
|-------------|-----------|
| Pending DRR | A `DirectRentalRequest` with `Status = "PENDING"` and `ExpiresAt > now` references the vehicle |
| Accepted DRR | A `DirectRentalRequest` with `Status IN (ACCEPTED, PARTIALLY_ACCEPTED)` references the vehicle |
| Active contract assignment | Vehicle is on a blocking contract (any source) |
| RFQ award assignment | Vehicle assigned to an active RFQ award |

`IVehicleAvailabilityService` is the single source of truth consulted both by the browse query (`GetAvailableVehiclesQuery`) and by `SubmitCartCommandHandler`'s race-condition re-check.

---

## 4. Business Rules Summary

Rule IDs below follow the numbering already used by `backlog/post-mvp/epic-21-direct-rental.md` and v1.0 of this document; treat `MVP_AUTHORITATIVE_BUSINESS_RULES.md §19` as the rule-ID system of record to double-check against, not something this rewrite independently re-verified line-by-line.

| Rule ID | Summary | Code confirms |
|---------|---------|----------------|
| BR-DR-001 | Business must be verified/active to browse, cart, submit | ✅ `IAccountOperationGuard` |
| BR-DR-002 | Vehicle must be APPROVED, DR-enabled, rate > 0 to list | ✅ `GetAvailableVehiclesQuery` filter |
| BR-DR-003 | Cart does not lock vehicles | ✅ no lock field on cart entities |
| BR-DR-004 | Submit requires wallet balance ≥ cart total (escrow *estimate*, not an actual lock) | ✅ `GetCartSubmitPreviewQuery.CanSubmit` |
| BR-DR-005 | Submit re-validates vehicle availability (race protection) | ✅ `SubmitCartCommandHandler` step 4 |
| BR-DR-006 | One DRR per provider per cart submit | ✅ `GroupBy(item => item.ProviderId)` |
| BR-DR-007 | Line items grouped by vehicle type within DRR | ✅ `GroupBy(item => item.Type)` |
| BR-DR-008 | Provider has 48h to respond; else SYSTEM_EXPIRE | ✅ `ExpiresAt`, `ExpireDirectRentalRequestsJob` |
| BR-DR-009 | Business may cancel only while PENDING and not expired | ✅ `DirectRentalRequest.Cancel()` |
| BR-DR-010 | Provider must respond for every vehicle in request | ✅ `SetEquals` check, throws otherwise |
| BR-DR-011 | Rejection reason required per rejected vehicle (min 5 chars) | ✅ `DirectRentalRequestVehicle.Reject()` |
| BR-DR-012 | `isAllOrNone`: accept all or reject all — no partial | ✅ throws if `0 < acceptedCount < totalCount` |
| BR-DR-013 | Fleet segment capacity gate on DR accept | ✅ `IProviderFleetCapacityService`, per accepted vehicle |
| BR-DR-014 | Accept/partial accept triggers contract creation | ✅ idempotent, `DirectRentalRequestAcceptedEventHandler` |
| BR-DR-015 | Cannot enable DR on contract/award-committed vehicle | ✅ `SetVehicleDirectRentalAvailabilityCommand` guard |

---

## 5. End-to-End Flows

### 5.1 Provider Setup

```
Provider → Set daily rate (PUT /api/identity/vehicles/{id}/rental-rate)  [ProviderUser policy]
        → Enable DR (POST /api/identity/vehicles/{id}/enable-direct-rental)
            └─ Blocked if vehicle on active contract or RFQ award assignment
        → Disable DR (POST /api/identity/vehicles/{id}/disable-direct-rental)
```

Both rate-setting and enable/disable route through `Modules/Identity`'s `VehicleController`, not the Marketplace module — Direct Rental "catalog" state lives on the `Vehicle` entity itself (`IsAvailableForDirectRental`, `DailyRentalRate`), with `SetVehicleDirectRentalAvailabilityCommand` doing the enable/disable and `UpdateVehicleRentalRateCommand` doing the rate update.

### 5.2 Business Happy Path

```
Browse (GET direct-rental/vehicles)
  → Add to cart (POST cart/items) — dates, availability check
  → Edit cart item dates (PATCH cart/items/{id})
  → Submit preview (GET cart/submit-preview) — wallet + totals
  → Submit cart (POST cart/submit)
      ├─ Wallet insufficient → 422 INSUFFICIENT_WALLET_BALANCE
      ├─ Vehicle locked since added → 400, conflicting plate numbers listed, entire submit aborted
      └─ Success → N requestIds (one per provider), cart items soft-deleted
  → Track request (GET direct-rental/requests/{id})
  → Optional: cancel while PENDING (POST .../cancel)
```

### 5.3 Provider Response Path

```
List requests (GET direct-rental/requests) — provider scope
  → Optional: accept-preview (GET .../accept-preview) — capacity conflicts, advisory only
  → Respond (POST .../respond) — vehicle-level decisions, all vehicles must be covered
      ├─ All accepted → ACCEPTED → contract created
      ├─ Mixed (isAllOrNone=false) → PARTIALLY_ACCEPTED → contract for accepted vehicles only
      └─ None accepted → REJECTED
  → View history (GET .../history)
```

### 5.4 System Expiry Path

```
ExpireDirectRentalRequestsJob (hourly, 30s startup delay)
  → PENDING where expiresAt < now
  → status = EXPIRED, trigger = SYSTEM_EXPIRE (per-request try/catch, batch continues on individual failure)
  → Vehicles unlocked for browse
```

### 5.5 Contract Bridge

```
DirectRentalRequestAcceptedEvent / DirectRentalRequestPartiallyAcceptedEvent
  → CreateDirectRentalContractCommand (idempotent — GetByDirectRentalRequestIdAsync guards re-trigger)
      → Contract.CreateFromDirectRental(...): SourceType = "DIRECT_RENTAL", DirectRentalRequestId set
      → Line items from accepted DR vehicles, grouped by DR line item
      → Commission rate resolved from provider's current tier via CommissionStrategies.CalculateCommissionAsync,
        falls back to hardcoded 5% if tier/strategy lookup fails
      → Vehicle assignments pre-created directly (no separate post-award assignment step, unlike RFQ awards)
      → History: SYSTEM_CONTRACT_CREATED (to_status label "CONTRACT_LINKED"; request.Status itself unchanged)
      → ContractCreatedEvent published → Finance module locks escrow automatically (see §12)
```

### 5.6 Admin On-Behalf-Of Path

```
AdminDirectRentalController [AdminOnly]
  → Browse full catalog / all requests (not scoped to a single business or provider)
  → View/manage a specific business's cart (add/update/remove item, submit-preview, submit)
      — submissions tagged ADMIN_SEND in history, actor = admin's user-account id
  → Respond to a request on a provider's behalf
      — responses tagged ADMIN_RESPOND_ACCEPT / _PARTIAL / _REJECT in history
```

---

## 6. Cart Grouping Algorithm

On `POST /api/marketplace/cart/submit` (`SubmitCartCommandHandler`):

1. Ensure business is active/operable
2. Begin an explicit DB transaction (skipped only when the underlying EF Core provider doesn't support one — i.e. the InMemory test provider)
3. Load the business's most-recently-updated non-deleted cart and its non-deleted items; empty cart → throws
4. Re-run `GetCartSubmitPreviewQuery`; if `CanSubmit == false` → throws `UnprocessableEntityException` (`INSUFFICIENT_WALLET_BALANCE`, HTTP 422) with `availableBalance`/`estimatedHold`/`shortfall` in the error payload
5. Re-check all cart vehicle IDs against `IVehicleAvailabilityService.GetLockedVehicleIdsAsync` — any hit aborts the **entire** submit (not just the affected provider group) with the locked plate numbers listed
6. **Group by `providerId`**
7. For each provider group:
   - Generate a request number (`DR-{yyyyMMdd}-{sequence}`, sequence counted across all non-deleted requests created that day, not scoped per provider)
   - Create one `DirectRentalRequest` (all items in the group are assumed to share the same rental period — enforced by validation at cart add/update time, not re-validated at submit)
   - **Sub-group by `Type`** (vehicle type) → one `DirectRentalRequestLineItem` per subgroup
   - One `DirectRentalRequestVehicle` per cart item within that subgroup
   - Raise `DirectRentalRequestSubmittedEvent`; record history (`USER_SUBMIT` or `ADMIN_SEND` → `PENDING`)
8. Soft-delete all cart items (`IsDeleted = true`), touch cart's `UpdatedAt`
9. `SaveChangesAsync` + commit

**Constraint:** all items in one provider group are expected to share the same rental period — this is validated when items are added/updated in the cart, not re-checked at submit time.

---

## 7. Provider Response Logic

| Accepted | Total | Request status | History trigger (provider / admin-on-behalf) |
|----------|-------|----------------|-----------------------------------------------|
| 0 | N | `REJECTED` | `PROVIDER_REJECT` / `ADMIN_RESPOND_REJECT` |
| N | N | `ACCEPTED` | `PROVIDER_ACCEPT` / `ADMIN_RESPOND_ACCEPT` |
| 1..N-1 | N | `PARTIALLY_ACCEPTED` | `PROVIDER_PARTIAL_ACCEPT` / `ADMIN_RESPOND_PARTIAL` |

**All-or-none (`isAllOrNone = true`):** if the response would mix accept/reject (`0 < acceptedCount < totalCount`), `RespondToDirectRentalRequestCommandHandler` throws before applying any vehicle decision — the whole call fails atomically.

**Response-set completeness:** the vehicle IDs in the response must exactly match (`SetEquals`) the request's vehicle IDs. A response covering only some vehicles is rejected outright with an error, not treated as an implicit partial.

**Fleet gate (per accepted vehicle):** see §8. The gate runs *before* any vehicle decision is applied — a blocked vehicle aborts the entire respond call, not just that one vehicle's decision.

**Request-level rejection reason:** when every vehicle is individually rejected, the handler calls `Reject("All vehicles rejected by provider.")` — a fixed string, always ≥ 10 characters. There is currently no client path that submits a custom whole-request rejection reason; per-vehicle reasons (each ≥ 5 characters, provider-supplied) are what's actually shown to the business.

---

## 8. Fleet Segment Capacity (RFQ Interaction)

Direct Rental shares provider fleet capacity with RFQ bidding and awards **by segment** (vehicle type + fuel type), via the same `IProviderFleetCapacityService` used by the RFQ/bidding module.

### 8.1 Segment Definition

- Fuel normalized via `FuelTypeNormalizer` (EV, PETROL, DIESEL, etc.)
- Aliases: `EV_SEDAN` ↔ `SEDAN` + `ELECTRIC`

### 8.2 DR Accept Block Reasons

Enumerated by `DirectRentalAcceptConflictType` and surfaced as string codes to clients:

| Code | Enum value | Meaning |
|------|------------|---------|
| `DR_ACCEPT_AWARD_NOT_FULLY_ASSIGNED` | `AwardNotFullyAssigned` | An overlapping segment has an RFQ award with unassigned units |
| `DR_ACCEPT_VEHICLE_ON_AWARD` | `VehicleAssignedToAward` | This exact vehicle is already assigned to an RFQ award |
| `DR_ACCEPT_BID_CAPACITY` | `ActiveBid` | Accepting would leave insufficient segment pool for active bids + unassigned awards |
| `DR_ACCEPT_CAPACITY` | (fallback) | Any other conflict type not covered above (defensive default in the `switch`) |

### 8.3 Enforcement Points

- **Preview** (`GET .../accept-preview`, `GetDirectRentalAcceptPreviewQueryHandler`): runs the same capacity check per vehicle in the request and returns a per-vehicle `canAccept`/conflict breakdown — **advisory only**, does not lock or reserve anything.
- **Actual enforcement** (`RespondToDirectRentalRequestCommandHandler` step 7): re-runs the identical `GetDirectRentalAcceptCheckAsync` call per accepted vehicle and throws `FleetCapacityConflictException` on the first conflict found — this is the real gate; the preview and the enforcement share the same service method, so the two cannot drift into different conflict logic (they could still disagree if fleet state changes between the preview call and the respond call, since the preview reserves nothing).

### 8.4 Provider APIs (UI support)

| Endpoint | Purpose |
|----------|---------|
| `GET /api/marketplace/provider/fleet/capacity` | Segment snapshot |
| `POST /api/marketplace/provider/fleet/capacity/bid-preview` | Bid quantity preview |
| `GET /api/marketplace/rfq/awards/{awardId}/eligible-vehicles` | Award assignment picker |
| `GET /api/marketplace/provider/fleet/action-items` | Dashboard badges |

---

## 9. Status History Triggers

See `MVP_DIRECT_RENTAL_STATE_MACHINE.md` §9 for the full, exhaustive list as implemented in `DirectRentalRequestHistoryTriggers` — it includes four admin-on-behalf-of triggers (`ADMIN_SEND`, `ADMIN_RESPOND_ACCEPT`, `ADMIN_RESPOND_PARTIAL`, `ADMIN_RESPOND_REJECT`) alongside the business/provider/system ones summarized in §5–§7 above.

---

## 10. API Surface (MVP, as implemented)

### 10.1 Business

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/marketplace/direct-rental/vehicles` | Browse catalog |
| GET | `/api/marketplace/direct-rental/vehicles/{id}` | Vehicle detail (404 if not found or not DR-available) |
| GET | `/api/marketplace/cart` | Current cart (returns an empty-cart shape, not 404, if none exists yet) |
| POST | `/api/marketplace/cart/items` | Add vehicle |
| PATCH | `/api/marketplace/cart/items/{id}` | Update dates |
| DELETE | `/api/marketplace/cart/items/{id}` | Remove item |
| GET | `/api/marketplace/cart/submit-preview` | Wallet gate preview |
| POST | `/api/marketplace/cart/submit` | Create DRR(s) |
| GET | `/api/marketplace/direct-rental/requests` | List sent requests |
| GET | `/api/marketplace/direct-rental/requests/{id}` | Request detail |
| GET | `/api/marketplace/direct-rental/requests/{id}/history` | Status timeline |
| POST | `/api/marketplace/direct-rental/requests/{id}/cancel` | Cancel pending |

### 10.2 Provider

| Method | Path | Description |
|--------|------|-------------|
| PUT | `/api/identity/vehicles/{id}/rental-rate` | Set daily rate (`ProviderUser` policy) |
| POST | `/api/identity/vehicles/{id}/enable-direct-rental` | Toggle DR listing on (`ProviderUser` policy) |
| POST | `/api/identity/vehicles/{id}/disable-direct-rental` | Toggle DR listing off (`ProviderUser` policy) |
| GET | `/api/marketplace/direct-rental/requests` | Incoming requests |
| GET | `/api/marketplace/direct-rental/requests/{id}/accept-preview` | Capacity preview |
| POST | `/api/marketplace/direct-rental/requests/{id}/respond` | Accept/reject vehicles |

### 10.3 Admin (`AdminOnly` policy, `AdminDirectRentalController`)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/admin/direct-rental/vehicles` | Full catalog, unscoped |
| GET | `/api/admin/direct-rental/requests` | All requests, filterable by business/provider/status/date |
| GET | `/api/admin/direct-rental/requests/{id}` | Any request's detail |
| GET | `/api/admin/direct-rental/requests/{id}/history` | Any request's history |
| GET | `/api/admin/direct-rental/businesses/{businessId}/cart` | View a business's cart |
| POST | `/api/admin/direct-rental/businesses/{businessId}/cart/items` | Add item on behalf of business |
| PATCH | `/api/admin/direct-rental/businesses/{businessId}/cart/items/{cartItemId}` | Update item on behalf of business |
| DELETE | `/api/admin/direct-rental/businesses/{businessId}/cart/items/{cartItemId}` | Remove item on behalf of business |
| GET | `/api/admin/direct-rental/businesses/{businessId}/cart/submit-preview` | Wallet preview on behalf of business |
| POST | `/api/admin/direct-rental/businesses/{businessId}/cart/submit` | Submit cart on behalf of business |
| POST | `/api/admin/direct-rental/requests/{requestId}/respond` | Respond on behalf of provider (provider ID passed in body) |

Mobile mirrors of the business/provider endpoints exist under `/api/mobile/marketplace/...` per both Flutter apps' feature modules — not independently re-verified endpoint-by-endpoint in this pass, but their existence is confirmed by `business_app/lib/features/direct_rental/` and `provider_app/lib/features/direct_rental/` in the mobile codebases (see `epic-21-direct-rental.md` Technical Dependencies).

---

## 11. Events & Notifications

| Domain event | Downstream |
|--------------|------------|
| `DirectRentalRequestSubmittedEvent` | Provider notification |
| `DirectRentalRequestAcceptedEvent` | Contract creation (Contracts module), business notification |
| `DirectRentalRequestPartiallyAcceptedEvent` | Contract creation (partial), notifications |
| `DirectRentalRequestRejectedEvent` | Business notification |
| `DirectRentalRequestExpiredEvent` | Business notification |
| `DirectRentalRequestCancelledEvent` | Provider notification |
| `ContractCreatedEvent` | Finance module: automatic escrow lock (see §12) |

---

## 12. Financial Rules

| Stage | Wallet action |
|-------|---------------|
| Cart submit preview | **Check only** — `availableBalance >= cartTotal`, no funds touched |
| Cart submit | **No escrow lock at submit.** This is a confirmed MVP design choice, not a bug: `DirectRentalCart`/`DirectRentalRequest` have no code path that debits any wallet. The wallet check is an estimate used purely to gate submission. |
| Contract created | Standard `ContractCreatedEvent` fires from `CreateDirectRentalContractCommandHandler`; the Finance module's `ContractCreatedEventHandler` locks escrow automatically (MAIN → ESCROW, 5-attempt exponential-backoff retry) — see `backlog/mvp/epic-08-wallet-escrow.md` Story 8.4 and `14_Wallet_Engine_Flow_Specification.md` §4 Step 1–2 for the full mechanism. This is **not** gated on any particular `Contract.Status` value from the Direct Rental module's point of view — it is purely a reaction to the event. |

**Known consequence (documented, not hidden):** because no hold occurs at cart-submit time, a business can submit multiple carts whose combined totals exceed its real available balance before any single resulting contract reaches escrow lock — each submit's wallet check only compares against the *current* available balance at that moment, with no reservation carried between submits. `epic-21-direct-rental.md`'s Risks section documents this explicitly as an accepted MVP limitation, to be revisited (e.g. a soft hold at submit) only if abuse is observed.

---

## 13. Error Codes (Client Handling)

| Code | HTTP | When |
|------|------|------|
| `INSUFFICIENT_WALLET_BALANCE` | 422 | Submit preview/submit — available balance < cart total |
| `DR_ACCEPT_AWARD_NOT_FULLY_ASSIGNED` | (handled via `FleetCapacityConflictException`, mapped by global exception handling — verify the exact HTTP status against the current exception-handling middleware rather than assuming 409) | Provider accept blocked — assign award vehicles first |
| `DR_ACCEPT_VEHICLE_ON_AWARD` | (same as above) | Vehicle committed to RFQ award |
| `DR_ACCEPT_BID_CAPACITY` | (same as above) | Segment pool insufficient for active bids |

v1.0 of this document asserted these three fleet-capacity codes return HTTP 409 specifically; this rewrite confirmed the codes and the exception type (`FleetCapacityConflictException`) but did not trace the global exception-handling middleware to confirm the exact status code it maps that exception type to — treat 409 as likely-but-unconfirmed rather than re-asserting it as verified.

---

## 14. Database Objects

**Schema:** `marketplace`

| Table | Purpose |
|-------|---------|
| `direct_rental_carts` | Business shopping cart |
| `direct_rental_cart_items` | Cart line items |
| `direct_rental_requests` | Submitted requests |
| `direct_rental_request_line_items` | Type-grouped lines |
| `direct_rental_request_vehicles` | Vehicle-level rows |
| `direct_rental_request_status_history` | Audit timeline |

---

## 15. Testing & Verification

`backend/scripts/direct-rental-smoke-test.md` was cited in v1.0 as the canonical E2E checklist; this rewrite did not re-locate or re-verify that specific file's contents — confirm it still exists and is current before relying on it as a test plan.

---

**END OF DIRECT RENTAL SPECIFICATION**
