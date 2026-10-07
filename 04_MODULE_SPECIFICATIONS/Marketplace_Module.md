# Marketplace Module — Specification

**Module Name:** Marketplace
**Version:** 2.0 (rewritten against running code)
**Last verified against code:** 2026-07-23
**Location:** `Modules/Marketplace/**` inside `Marketplace.API` (.NET 9 modular monolith) — this is a folder/namespace inside one deployable, not a separate `marketplace-core` service
**Related documents:** `backlog/mvp/epic-04-rfq-management.md`, `backlog/mvp/epic-05-bidding-engine.md`, `backlog/post-mvp/epic-21-direct-rental.md`, `project-docs/partial-fulfillment-spec.md`, `project-docs/18_Implementation_Coverage_Audit.md` §4 and §10.3

---

## What changed in this rewrite

The previous version of this document (v1.2, dated December 2025 / updated June 2026) described a single-vehicle-type, whole-RFQ bidding model with price floor/ceiling validation and a `BiddingController`. None of that matches the running code. This rewrite replaces it entirely:

- **RFQ is a header + `RFQLineItem[]` model**, not single vehicle-type/date-range. `RFQ.StartDate`/`EndDate` are computed properties (`Min`/`Max` across line items), not stored columns.
- **Bidding is per-line-item at the quantity level** (`RFQBidItem`), not a single bid amount per RFQ. No specific vehicle is chosen at bid time on any surface.
- **Awards can be split** across multiple providers per line item (`RFQBidAward`), followed by a **separate, universal post-award vehicle-assignment step** (`RFQAwardVehicleAssignment`) — this step exists identically on backend, web, and both mobile apps (§10.3 of the audit corrected an earlier claim that it was mobile-only).
- **There is no price floor/ceiling validation, no `MarketPriceSnapshot`/`MarketPriceService`, and no `BiddingController`** in the real codebase — the previous doc's "Market Intelligence" and "Price Validation" sections describe code that does not exist as a live guard. (`IPriceValidator`/`PriceValidator` do exist in `Domain/Services`, but are not called from any bid/award command — see Known Gaps.)
- **The weighted bid-ranking algorithm and anti-collusion detection that the previous doc's business-rules section implied were live are not built anywhere** — confirmed by repo-wide search across backend, web, and both mobile apps.
- **Direct Rental** (fixed-price, non-bidding vehicle booking) is a second, fully-built product line inside this same module, folded in here because it lives in the same `Modules/Marketplace/**` tree and shares fleet-capacity accounting with RFQ bidding. It was previously undocumented at the epic level; it now has its own epic (`backlog/post-mvp/epic-21-direct-rental.md`).
- **Contract creation from an awarded bid is genuinely event-driven**, resolving an open question in `epic-05-bidding-engine.md` Story 5.5: `AwardBidCommandHandler` contains a `// TODO: Publish BidAwardedEvent...` comment that reads as if nothing publishes it — but `RFQBid.MarkAsAwarded()` (called earlier in the same handler) already raises `BidAwardedEvent`, and the Contracts module's `BidAwardedEventHandler` consumes it, pulling all pending awards for that bid from the EF Core change tracker (since domain events dispatch before `SaveChanges`) and creating one contract per bid. The TODO comment is stale/misleading, not a real gap — verified directly against both handler bodies.

---

## Overview

### Purpose

The Marketplace module owns two parallel acquisition channels that both feed the same downstream Contract → Escrow → Delivery → Settlement pipeline:

1. **RFQ / blind bidding** — a business publishes a multi-line-item Request for Quotation; providers submit blind, per-line-item bids; the business awards (possibly splitting a line item across several providers); awarded providers then assign specific vehicles.
2. **Direct Rental** — a business browses a catalog of provider-listed vehicles at fixed daily rates, adds them to a cart, and submits per-provider requests; providers accept/reject at vehicle-level granularity; accepted vehicles flow straight into a contract with vehicles pre-assigned (no separate post-award assignment step).

Both channels produce a `Contract` with a different `SourceType` (`"RFQ"` vs `"DIRECT_RENTAL"`) but otherwise hand off to identical Contracts-module machinery. The Marketplace module does not move money (Finance module), run OTP delivery verification (Delivery module), or compute trust scores (Identity module) — it reacts to and publishes events around those.

### Responsibilities

**RFQ lifecycle**
- Multi-line-item RFQ creation, update (full line-item replace only), publish, manual close, deadline extension (including reviving an `EXPIRED` RFQ), cancellation
- Automatic expiry via a 5-minute-poll background job
- Provider discovery/browse with fleet-match filtering (`myMatchesOnly`) — visibility is **not** fleet-gated, only the publish-time notification is

**Blind bidding**
- Per-line-item bid submission at the quantity level (no vehicle chosen), one bid per provider per line item, bundling multiple line items in one submission
- SHA-256 provider-identity hashing (`RFQBidSnapshot`) plus a trust-score/tier snapshot at submission time
- Bid update (partial-item semantics) and withdrawal, including a deliberate hard-delete-and-resubmit path after withdrawal

**Award processing**
- Split awards across multiple providers per line item, with wallet-affordability validation and an affordable-quantity suggestion on shortfall
- Fleet-segment capacity re-validation at award time
- Auto-rejection of non-awarded bids once an RFQ reaches full `AWARDED` status

**Post-award vehicle assignment**
- Linking specific vehicles from an awarded provider's fleet to their award, identically across all four surfaces

**Direct Rental (fixed-price channel)**
- Provider vehicle listing (rate + opt-in toggle), business catalog browse, multi-provider cart, per-provider request submission with wallet-gate and race-condition re-check, vehicle-level accept/reject, 48-hour auto-expiry, fleet-capacity conflict preview shared with RFQ bidding, automatic contract creation on acceptance
- Admin on-behalf-of operations across the whole Direct Rental surface

**Market intelligence** — not real. The previous doc's `MarketPriceSnapshot`/`MarketPriceService` do not exist in code; there is no price floor/ceiling enforcement anywhere in the live bid/award path.

---

## Database Schema

### RFQ / Bidding tables

| Table | Schema | Purpose |
|---|---|---|
| `rfqs` | default | RFQ header (`RFQ`) |
| `rfq_line_items` | `marketplace` | Per-line-item vehicle type/quantity/term/dates (`RFQLineItem`) |
| `rfq_bids` | default | Provider bid header (`RFQBid`) |
| `rfq_bid_items` | `marketplace` | Per-line-item quantity/price within a bid (`RFQBidItem`) |
| `rfq_bid_snapshots` | `marketplace` | Blind-bidding anonymized snapshot: hashed provider ID + trust/tier at submission (`RFQBidSnapshot`) |
| `rfq_bid_history` | `marketplace` | Audit trail of bid changes with JSON diffs (`RFQBidHistory`) |
| `rfq_bid_awards` | default | Awarded bid records, one per (bid, line item) award (`RFQBidAward`) |
| `rfq_award_vehicle_assignments` | `marketplace` | Specific vehicles assigned to an award (`RFQAwardVehicleAssignment`) |
| `rfq_line_item_fulfillments` | `marketplace` | Post-award delivery/return progress per award (`RFQLineItemFulfillment`) |
| `rfq_status_history` | `marketplace` | RFQ status transition audit trail (`RFQStatusHistory`) |
| `marketplace_event_logs` | `marketplace` | Generic marketplace audit entity — **`MarketplaceEventLog.Create()` has zero call sites anywhere in the backend; the table exists but nothing ever writes to it** |

### Direct Rental tables

| Table | Schema | Purpose |
|---|---|---|
| `direct_rental_carts` | `marketplace` | Business shopping cart, one active cart per business (`DirectRentalCart`) |
| `direct_rental_cart_items` | `marketplace` | Vehicle + dates + snapshotted daily rate in cart (`DirectRentalCartItem`) |
| `direct_rental_requests` | `marketplace` | One request per provider, created from a cart submit (`DirectRentalRequest`) |
| `direct_rental_request_line_items` | `marketplace` | Vehicles grouped by type within a request (`DirectRentalRequestLineItem`) |
| `direct_rental_request_vehicles` | `marketplace` | Specific vehicle instance accept/reject rows (`DirectRentalRequestVehicle`) |
| `direct_rental_request_status_history` | `marketplace` | Status transition audit trail (`DirectRentalRequestStatusHistory`) |

---

## Module Structure (actual folders)

```
Modules/Marketplace/
├── Domain/
│   ├── Entities/
│   │   ├── RFQ.cs, RFQLineItem.cs
│   │   ├── RFQBid.cs, RFQBidItem.cs, RFQBidSnapshot.cs, RFQBidHistory.cs
│   │   ├── RFQBidAward.cs, RFQAwardVehicleAssignment.cs, RFQLineItemFulfillment.cs
│   │   ├── RFQStatusHistory.cs
│   │   ├── MarketplaceEventLog.cs         (dead — zero writes anywhere)
│   │   ├── DirectRentalCart.cs, DirectRentalCartItem.cs
│   │   └── DirectRentalRequest.cs, DirectRentalRequestLineItem.cs,
│   │       DirectRentalRequestVehicle.cs, DirectRentalRequestStatusHistory.cs
│   ├── Enums/
│   │   ├── FuelType.cs   (ANY, ELECTRIC, PETROL, DIESEL, CNG, HYBRID)
│   │   └── RFQTerm.cs    (SHORT_TERM, LONG_TERM)
│   ├── Events/MarketplaceEvents.cs (all RFQ/bid/direct-rental domain events, single file)
│   └── Services/
│       ├── BlindBiddingService.cs / IBlindBiddingService.cs   (SHA-256 provider-ID hashing)
│       ├── PriceValidator.cs / IPriceValidator.cs             (present but not called from any bid/award path — see Known Gaps)
│       ├── ProviderFleetCapacityService.cs / IProviderFleetCapacityService.cs (shared segment-capacity engine, RFQ + Direct Rental)
│       ├── VehicleAvailabilityService.cs, FuelTypeNormalizer.cs, CapacitySegment.cs, FleetCapacityModels.cs
│       └── DirectRentalRequestHistoryService.cs / IDirectRentalRequestHistoryService.cs (+ ...HistoryTriggers.cs)
│
├── Application/
│   ├── RFQ/
│   │   ├── Commands/ CreateRFQCommand, UpdateRFQCommand, PublishRFQCommand, CloseRFQCommand,
│   │   │             ExtendRFQDeadlineCommand, CancelRFQCommand
│   │   └── Queries/  GetRFQQuery, GetRFQsByBusinessQuery, GetActiveRFQsQuery,
│   │                 GetActiveRFQsForProviderQuery, GetRFQStatusHistoryQuery, GetRecommendedRFQsQuery
│   ├── RFQBid/
│   │   ├── Commands/ SubmitBidCommand, UpdateBidCommand, WithdrawBidCommand, AwardBidCommand,
│   │   │             AssignVehiclesToAwardCommand, ReleaseAwardVehicleAssignmentCommand, RevokeAwardCommand
│   │   └── Queries/  GetBidQuery, GetBidsByRFQQuery, GetBidsByProviderQuery,
│   │                 GetBidAwardAssignmentsQuery, GetAwardAssignmentStatusQuery
│   ├── DirectRentalCart/
│   │   ├── Commands/ AddToCartCommand, UpdateCartItemCommand, RemoveFromCartCommand, SubmitCartCommand
│   │   └── Queries/  (cart + submit-preview queries)
│   ├── DirectRentalRequest/
│   │   ├── Commands/ RespondToDirectRentalRequestCommand, CancelDirectRentalRequestCommand
│   │   └── Queries/  GetDirectRentalRequestsQuery, GetDirectRentalRequestByIdQuery,
│   │                 GetDirectRentalRequestStatusHistoryQuery, GetDirectRentalAcceptPreviewQuery
│   ├── DirectRentalVehicle/Queries/ (catalog browse/detail)
│   └── ProviderFleet/Queries/ (fleet-capacity dashboards for providers, `ProviderFleetController`)
│
└── Infrastructure/
    ├── Configurations/ (EF Core mappings)
    └── Repositories/ (RFQ, RFQBid, Awards, DirectRentalCart, DirectRentalRequest, etc.)
```

Controllers live outside the module tree, under `Marketplace.API/Controllers/Marketplace/`: `RFQController`, `BidController`, `RfqAwardController`, `DirectRentalCartController`, `DirectRentalRequestController`, `DirectRentalVehicleController`, `ProviderFleetController`. The admin Direct Rental surface (`AdminDirectRentalController`) lives under `Controllers/Admin/`.

---

## Core Entities (field-level)

### RFQ
- `BusinessId`, `RFQNumber` (auto-generated), `Title`, `Status` (string, 9 real values — see below), `Type` (`STANDARD`/`URGENT`/`LONG_TERM`), `SubmissionDeadline`, `AwardedAt`
- `StartDate`/`EndDate` — **`[NotMapped]` computed properties**: `Min(LineItems.RequiredFrom)` / `Max(LineItems.RequiredTo)`, not stored columns
- `PickupCity`/`DropoffCity` (optional), `IsBlind` (always `true`), `ContractDurationDays` (optional, currently unused by any read path found)
- Status values actually produced by entity methods: `DRAFT, PUBLISHED, BIDDING, BIDDING_CLOSED, PARTIALLY_AWARDED, AWARDED, EXPIRED, CANCELLED, COMPLETED` (9 values — the entity's own status-comment lists only 7, omitting `BIDDING_CLOSED` and `EXPIRED`)
- Methods: `Publish()` (`DRAFT→PUBLISHED`), `StartBidding()` (`PUBLISHED→BIDDING`, called on first bid), `CloseBidding()`, `MarkExpired()`, `Cancel()` (blocked only from `AWARDED`/`COMPLETED`), `MarkAsPartiallyAwarded()`, `MarkAsAwarded()`, `MarkAsCompleted()`, `Update()` (`DRAFT`/`PUBLISHED` only), `ClearLineItems()`, `RevertToBidding()`, `ExtendDeadline()`, `ReopenBiddingForDeadlineExtension()`, `RestoreAfterExtension(previousStatus)` (falls back to `BIDDING` if no prior status found)

### RFQLineItem
- `RFQId`, `VehicleType`, `Quantity`, `Term` (`RFQTerm`: `SHORT_TERM`/`LONG_TERM`), `Purpose` (required, ≤500 chars), `FuelType` (optional `FuelType` enum), `RequiredFrom`/`RequiredTo`, `Specifications` (optional), `TargetPricePerUnit` (optional), `PickupLocation`/`DropoffLocation` (optional)
- `DurationDays` — `[NotMapped]` computed as `Ceiling(RequiredTo − RequiredFrom)`
- Factory (`Create`) throws if `Term == SHORT_TERM` and duration exceeds 30 days — enforced in the domain layer, not just the web wizard

### RFQBid
- `RFQId`, `ProviderId`, `Status` (`SUBMITTED`/`WITHDRAWN`/`REJECTED`/`AWARDED`), `TotalAmount`, `ValidUntil` (optional), `Notes` (optional)
- Methods: `AddItem()`, `Withdraw()` (blocked if `AWARDED`), `MarkAsAwarded()` (raises `BidAwardedEvent` — see Key Workflows §5), `Reject()`, `Update()` (`SUBMITTED`/`PENDING` only), `RevokeAward()`

### RFQBidItem
- `BidId`, `RFQLineItemId`, `UnitPrice`, `Quantity`, `Description` (optional)

### RFQBidSnapshot (blind bidding)
- `RFQBidId`, `HashedProviderId` (SHA-256), `BidAmountPerUnit`, `QuantityOffered`, `ProviderTierCode` (optional), `ProviderTrustScore` (int, snapshotted at submission)

### RFQBidHistory
- `RFQBidId`, `Action` (`CREATED`/`UPDATED`/`WITHDRAWN`/`REJECTED`/`AWARDED`), `PreviousStatus`/`NewStatus`, `PreviousTotalAmount`/`NewTotalAmount`, `ChangedByUserId`/`ChangedByUserType` (`PROVIDER`/`BUSINESS`/`ADMIN`), `ChangeDetails` (JSON diff), `Notes`, `ChangedAt`

### RFQBidAward
- `RFQBidId`, `RFQLineItemId`, `QuantityAwarded`, `AgreedPricePerUnit`, `AwardedAt`

### RFQAwardVehicleAssignment
- `RFQBidAwardId`, `VehicleId`, `AssignedAt`, `ReleasedAt` (optional), `Status` (string: `ASSIGNED`/`DELIVERED`/`RETURNED`)
- Methods: `MarkDelivered()`, `Release()` (→ `RETURNED`, stamps `ReleasedAt`)

### RFQLineItemFulfillment
- `RFQLineItemId`, `RFQBidAwardId`, `QuantityDelivered`, `QuantityReturned`, `Status` (`PENDING`/`PARTIAL`/`FULFILLED`/`COMPLETED`)
- Methods: `RecordDelivery()`, `RecordReturn()`, `MarkAsFulfilled()`

### RFQStatusHistory
- `RFQId`, `FromStatus`/`ToStatus`, `Trigger` (`SYSTEM_EXPIRE`, `USER_PUBLISH`, `USER_CANCEL`, `USER_EXTEND_DEADLINE`, `USER_AWARD`, `USER_PARTIAL_AWARD`, `USER_REVERT_BIDDING`, `USER_CLOSE_BIDDING`), `TriggeredByUserId`/`TriggeredByUserType` (`BUSINESS`/`ADMIN`/`SYSTEM`/`PROVIDER`), `Notes`, `ChangedAt`

### DirectRentalCart / DirectRentalCartItem
- Cart: `BusinessId`, `Items[]`; computed `TotalVehicles`, `TotalAmount`, `UniqueProvidersCount` (all excluding soft-deleted items)
- CartItem: `CartId`, `VehicleId`, `ProviderId`, `StartDate`/`EndDate`, `DailyRate` (snapshotted at add time), denormalized `PlateNumber`/`Make`/`Model`/`Type`; computed `TotalDays`/`TotalAmount`
- `Cart.AddItem()` throws if the vehicle is already in the cart (soft-deleted items excluded from the check)

### DirectRentalRequest
- `RequestNumber` (`DR-{yyyyMMdd}-{seq}`), `BusinessId`, `ProviderId`, `Status` (`PENDING`/`ACCEPTED`/`PARTIALLY_ACCEPTED`/`REJECTED`/`EXPIRED`/`CANCELLED`), `StartDate`/`EndDate`, `TotalAmount`, `IsAllOrNone`, `SpecialInstructions` (≤1000 chars), `RejectionReason`, `ExpiresAt` (48h from creation), `RespondedAt`, `CancelledAt`/`CancelReason`
- Methods: `Accept()`, `AcceptPartial()` (blocked if `IsAllOrNone`), `Reject(reason)` (≥10 chars), `Expire()`, `Cancel(reason?)` (only from `PENDING`, before `ExpiresAt`)
- Computed: `TotalDays`, `IsActive`, `HoursRemaining`

### DirectRentalRequestLineItem
- `DirectRentalRequestId`, `VehicleType`, `Quantity`, `SubtotalAmount`, `Status` (`PENDING`/`ACCEPTED`/`PARTIALLY_ACCEPTED`/`REJECTED`), `RejectionReason`
- `UpdatePartialAcceptanceStatus()` derives line-item status from its vehicles' individual decisions

### DirectRentalRequestVehicle
- `LineItemId`, `VehicleId`, `IsAccepted` (nullable bool — `null` = pending), `RejectionReason` (≥5 chars if rejecting), denormalized `PlateNumber`/`Make`/`Model`, `DailyRate`, `TotalAmount`

### DirectRentalRequestStatusHistory
- Same shape as `RFQStatusHistory`; triggers: `USER_SUBMIT`, `USER_CANCEL`, `PROVIDER_ACCEPT`, `PROVIDER_PARTIAL_ACCEPT`, `PROVIDER_REJECT`, `SYSTEM_EXPIRE`, `SYSTEM_CONTRACT_CREATED`

---

## Key Workflows

### 1. RFQ creation → publish → bidding
`CreateRFQCommand` creates `DRAFT` + line items (30-day `SHORT_TERM` cap enforced in `RFQLineItem.Create`). `PublishRFQCommand` requires ≥1 line item, moves to `PUBLISHED`, fires `RFQPublishedEvent` → `RFQPublishedNotificationHandler` computes matching providers **live at notify time** (not persisted) by checking active-vehicle-type match, and fans out in-app/push/email/SMS respecting each provider's own preference toggles. The RFQ only moves to `BIDDING` when the **first bid** is submitted, not at publish time. Editing is allowed while `DRAFT` or `PUBLISHED` (a full line-item replace, no per-item patch) — existing bids on unaffected line items are not invalidated.

### 2. Blind bid submission
`SubmitBidCommand` validates the RFQ is `PUBLISHED`/`BIDDING`/`PARTIALLY_AWARDED` and the deadline hasn't passed, checks one-bid-per-provider-per-line-item, caps quantity at the line item's remaining un-awarded slots, and gates on fleet-segment capacity (`IProviderValidationService`/`ProviderFleetCapacityService`) — no specific vehicle is chosen. Creates `RFQBid` + `RFQBidItem`s + a blind `RFQBidSnapshot` (SHA-256 hashed provider ID + trust score/tier at that instant). First bid on a `PUBLISHED` RFQ calls `StartBidding()`.

### 3. Bid update / withdrawal
`UpdateBidCommand` is a partial-item update (omitted items are left untouched), re-validates fleet capacity excluding the bid's own existing reservation, and logs a JSON diff to `RFQBidHistory`. `WithdrawBidCommand` sets `WITHDRAWN`; `SubmitBidCommand` **hard-deletes** any prior `WITHDRAWN` bid row for the same (provider, RFQ) pair before inserting a new one, deliberately allowing resubmission after withdrawal.

### 4. Business bid review
`GetBidsByRFQQuery`/`GetBidQuery` return bids at any time after publish (not gated behind RFQ closure). **Verified gap:** both queries set `ProviderName` unconditionally on the returned DTO regardless of award status, despite a doc comment saying "NULL if not awarded." Blind bidding is enforced today only by the web UI not rendering that field — a direct API call or alternate client can see the real provider name pre-award.

### 5. Split award and contract-creation trigger
`AwardBidCommand` accepts a flat `{bidId, lineItemId, quantityAwarded}` list, validates cumulative award doesn't exceed a line item's requested quantity, checks business wallet `AvailableBalance` against `Σ quantityAwarded × unitPrice × min(durationDays, 30)`, and validates provider fleet-segment capacity per new award quantity. On insufficient balance, the error includes an estimated affordable quantity. For each award: creates `RFQBidAward`, calls `bid.MarkAsAwarded()` (which raises `BidAwardedEvent(BidId, RFQId, ProviderId)` as a domain event), and logs `RFQBidHistory`. RFQ becomes `AWARDED` only once every line item is fully awarded, otherwise `PARTIALLY_AWARDED`; only on full `AWARDED` are other still-`SUBMITTED` bids auto-rejected.

**Contract creation is genuinely event-driven, not a TODO gap.** `BidAwardedEventHandler` (Contracts module) handles the same `BidAwardedEvent` raised by `bid.MarkAsAwarded()`. Because domain events dispatch *before* `SaveChanges`, the handler first checks the EF Core change tracker for pending (not-yet-persisted) awards for that bid via `GetPendingAwardsByBidId`, falling back to a database read for re-processing. It groups all of the bid's awards into contract line items, resolves the provider's commission rate from their current tier via MasterData (defaulting to 5% on any lookup failure), derives contract start/end dates from the awarded line items only (not the RFQ header), and sends `CreateContractCommand`. The `// TODO: Publish BidAwardedEvent...` comment left inside `AwardBidCommandHandler` is stale — the event is already published, just from inside `bid.MarkAsAwarded()` rather than explicitly in the handler.

### 6. Post-award vehicle assignment (universal pattern)
`RFQAwardVehicleAssignment` links specific vehicles to an award via `POST /rfq/awards/{awardId}/vehicles` / `DELETE .../vehicles/{vehicleId}` / `GET .../eligible-vehicles`, identical across backend, web (`AwardAssignPage.tsx`), and both mobile apps. Assignment status progresses `ASSIGNED → DELIVERED → RETURNED`, feeding the Contracts module's delivery lifecycle.

### 7. RFQ auto-expiry, manual close, deadline extension
`RFQDeadlineJob` (hosted `BackgroundService`, 5-minute poll) marks `PUBLISHED`/`BIDDING` RFQs past deadline as `EXPIRED`, recording `SYSTEM_EXPIRE` history and firing `RFQExpiredEvent`. `PUT /{id}/close` moves to `BIDDING_CLOSED`. `PUT /{id}/extend-deadline` (default +3 days) reopens a `BIDDING_CLOSED` RFQ to `BIDDING`, or — for an `EXPIRED` RFQ — restores whichever status it held immediately before expiry (falling back to `BIDDING` if no history row exists).

### 8. RFQ cancellation
`DELETE /{id}` blocks only `AWARDED`/`COMPLETED`; cancelling a `PARTIALLY_AWARDED` RFQ does not itself unwind escrow already locked for prior awards — that is a Contracts/Finance concern. No structured cancellation-reason field exists on the entity.

### 9. Direct Rental: catalog → cart → submit → respond → contract
Provider enables a vehicle (`Vehicle.EnableDirectRental()`, requires `APPROVED` status + positive `DailyRentalRate`, blocked if contract/award-committed). Business browses the catalog (excludes locked vehicles), builds a multi-provider cart (`DirectRentalCartController`), and submits (`SubmitCartCommandHandler`): groups cart items by provider then vehicle type, checks wallet balance, re-validates vehicle availability transactionally (aborting on any newly-locked vehicle), and creates one `DirectRentalRequest` per provider with a 48-hour `expiresAt`. Provider responds vehicle-by-vehicle (`RespondToDirectRentalRequestCommand`) — full accept, partial accept (blocked if `IsAllOrNone`), or reject; `DirectRentalRequest.Accept()`/`AcceptPartial()`/`Reject()` derive the overall outcome from per-vehicle decisions. `ExpireDirectRentalRequestsJob` (hourly `BackgroundService`) auto-expires unanswered `PENDING` requests. On `ACCEPTED`/`PARTIALLY_ACCEPTED`, `DirectRentalRequestAcceptedEventHandler` (Contracts module) creates a contract with vehicles pre-assigned — no separate post-award assignment step, unlike the RFQ path.

### 10. Fleet-capacity conflict preview
Before responding to a Direct Rental request, a provider can call `GET /direct-rental/requests/{id}/accept-preview` (`GetDirectRentalAcceptPreviewQuery`) to see per-vehicle conflict codes (`DR_ACCEPT_AWARD_NOT_FULLY_ASSIGNED`, `DR_ACCEPT_VEHICLE_ON_AWARD`, `DR_ACCEPT_BID_CAPACITY`) against their RFQ bid/award commitments, via the same `IProviderFleetCapacityService` used for RFQ bidding. The preview is advisory — the actual `respond` call re-enforces the same gate server-side.

### 11. Shared services for guest mode and the website

**Full spec:** [../MVP_final_docs/MVP_GUEST_MODE_SPECIFICATION.md](../MVP_final_docs/MVP_GUEST_MODE_SPECIFICATION.md) §11. **Last verified against code: 2026-10-05**, backend branch `feature/mobile-guest-mode` (not yet merged to `development`).

Work prepared without an account — on the marketing website (`PendingActionApplier`, Public module) or in the mobile apps' guest mode — enters the Marketplace module through three shared pieces, so both channels apply identical rules:

| Piece | Location | Contract | Used by |
|---|---|---|---|
| `ICartMergeService` / `CartMergeService` | `Application/DirectRentalCart/Services/CartMergeService.cs` | `MergeAsync(businessId, items, ct)` → per-vehicle `ADDED` / `ALREADY_IN_CART` / `INVALID_DATES` / `UNAVAILABLE`. Adds through `AddToCartCommand` one vehicle at a time; a vehicle already in the cart keeps its server dates; a refused line becomes an outcome instead of failing the batch (`UnsavedChanges.Discard` drops half-built entities). Idempotent, never submits. | `MergeCartCommand` (`POST api/marketplace/cart/merge`), `PendingActionApplier.ApplyCartAsync` |
| `IBidDraftService` / `BidDraftService` | `Application/BidDrafts/BidDraftService.cs` | `SaveAsync(providerId, rfqId, items, notes, ct)` → `Saved` with per-line `SAVED` / `LINE_REMOVED` / `ALREADY_BID`, or `RfqNotFound` / `RfqClosed`. One live `ProviderBidDraft` per provider per line (saving again updates it); never creates an `RFQBid`. Tracks changes; the caller saves. | `CreateBidDraftsCommand` (`POST api/marketplace/bid-drafts`, maps not-found/closed to `422 RFQ_CLOSED`), `PendingActionApplier.ApplyBidAsync` |
| `RentableVehicles` + `DirectRentalPeriod` | `Domain/Services/RentableVehicles.cs` | `RentableVehicles.Predicate`: not deleted, `IsAvailableForDirectRental`, `APPROVED`, active, not in maintenance, `DailyRentalRate > 0`, provider not deleted and **`VERIFIED`**. `DirectRentalPeriod`: dates valid when start ≥ today (UTC) and end > start; `TotalDays` inclusive; `EscrowHold = rate × min(days, 30)`. Locks from requests/contracts stay in `IVehicleAvailabilityService`. | `GetAvailableVehiclesQuery`, `GetAvailableVehicleByIdQuery`, `AddToCartCommand`, the anonymous catalogue and cart quote (Public module) |

Related changes in this module: `AddToCartCommand` throws `CodedRuleException` (`422`) with `VEHICLE_UNAVAILABLE`, `ALREADY_IN_CART` or `INVALID_DATES`; migration `20261002180240_Add-DirectRentalCartItem-UniqueVehiclePerCart` adds the filtered unique index `UX_direct_rental_cart_items_cart_vehicle_active` on `(cartId, vehicleId) WHERE "isDeleted" = false` (older live duplicates are soft-deleted first) and the handler maps a unique violation to `ALREADY_IN_CART`. Because the predicate now requires a `VERIFIED` provider, the signed-in catalogue no longer lists vehicles of pending, suspended or blocked providers.

---

## Events

`Domain/Events/MarketplaceEvents.cs` (single file, all records):

**RFQ/Bid:** `RFQCreatedEvent`, `RFQPublishedEvent`, `RFQExpiredEvent`, `BidSubmittedEvent`, `BidAwardedEvent(BidId, RFQId, ProviderId)`, `BidRejectedEvent`, `BidWithdrawnEvent`

**Direct Rental:** `DirectRentalRequestSubmittedEvent`, `DirectRentalRequestAcceptedEvent`, `DirectRentalRequestPartiallyAcceptedEvent`, `DirectRentalRequestRejectedEvent`, `DirectRentalRequestExpiredEvent`, `DirectRentalRequestCancelledEvent`

`MarketplaceEventLog` is the module's own generic audit-log entity for these events, but **`MarketplaceEventLog.Create()` has zero call sites anywhere in the backend** — the table and entity exist and are mapped, but nothing ever writes a row. The real audit trail for RFQ/bid/request lifecycle changes is `RFQStatusHistory`/`RFQBidHistory`/`DirectRentalRequestStatusHistory`, not this entity.

---

## APIs (controllers, actual routes)

| Controller | Base route | Key endpoints |
|---|---|---|
| `RFQController` | `api/marketplace/rfqs` | `POST` (create, admin can create-on-behalf-of via `BusinessId`, auto-publishes), `PUT /{id}`, `PUT /{id}/publish`, `PUT /{id}/close`, `PUT /{id}/extend-deadline`, `DELETE /{id}`, `GET /{id}`, `GET /{id}/status-history`, `GET` (list/browse) |
| `BidController` | `api/marketplace/bids` | `POST`, `PUT /{id}`, `DELETE /{id}`, `POST /award`, `GET /{id}`, `GET`, `GET /rfq/{rfqId}`, `GET /provider/{providerId}`, `GET /{id}/award-assignments` |
| `RfqAwardController` | `api/marketplace/rfq/awards` | `GET /{awardId}/assignments`, `POST /{awardId}/vehicles`, `DELETE /{awardId}/vehicles/{vehicleId}`, `GET /{awardId}/eligible-vehicles` |
| `DirectRentalVehicleController` | `api/marketplace/direct-rental/vehicles` | `GET` (catalog list), `GET /{vehicleId}` (detail) |
| `DirectRentalCartController` | `api/marketplace/cart` | `GET`, `POST /items`, `PATCH /items/{cartItemId}`, `DELETE /items/{cartItemId}`, `POST /merge` (guest cart hand-over, §11), `GET /submit-preview`, `POST /submit` |
| `BidDraftController` | `api/marketplace/bid-drafts` | `Policy=ProviderUser`: `POST` (save prices as saved bids, §11), `GET`, `PUT /{id}`, `DELETE /{id}`, `GET /{id}/readiness`, `POST /{id}/submit` (runs `SubmitBidCommand`) |
| `DirectRentalRequestController` | `api/marketplace/direct-rental/requests` | `GET`, `GET /{requestId}`, `GET /{requestId}/history`, `POST /{requestId}/cancel`, `POST /{requestId}/respond`, `GET /{requestId}/accept-preview` |
| `ProviderFleetController` | `api/marketplace/provider/fleet` | `GET /capacity`, `POST /capacity/bid-preview`, `GET /action-items` |
| `AdminDirectRentalController` (`Controllers/Admin/`) | `api/admin/direct-rental` | Vehicle browse, request list/detail/history, business-cart CRUD + submit-preview + submit (tagged `ADMIN`), respond-on-behalf-of-provider — all `[Authorize(Policy = "AdminOnly")]` |

---

## Known Gaps (verified by code search, zero call sites unless noted)

1. **Weighted bid-ranking algorithm does not exist anywhere** — no composite price/trust/condition/response-time scoring, no admin-configurable weights, on any surface. The web's `sortBy` is a single-column client sort only.
2. **Anti-collusion detection does not exist anywhere** — no identical-bid, same-IP, or shared-bank-account checks. `RFQBid`/`RFQBidItem`/`RFQBidHistory` don't even capture an IP address, so there's no data to build the cheapest signal from.
3. **Blind bidding is not enforced server-side.** `GetBidsByRFQQuery`/`GetBidQuery` set `ProviderName` unconditionally; only the web client's choice not to render it protects identity pre-award.
4. **`MarketplaceEventLog` is dead code** — mapped entity and table, zero writes.
5. **`IPriceValidator`/`PriceValidator` exist in `Domain/Services` but are not called from `SubmitBidCommand`, `UpdateBidCommand`, or `AwardBidCommand`** — no price floor/ceiling is enforced anywhere in the live bid/award path, despite the service being fully coded.
6. **No persisted "eligible providers at publish time" table** — `RFQPublishedNotificationHandler` computes matches live and doesn't audit who was notified.
7. **The 10-line-item / 50-vehicle-per-RFQ caps are enforced only in the web Zod schema**, not confirmed server-side in `RFQ`/`RFQLineItem`.
8. **Editing a `PUBLISHED` RFQ's line items does not invalidate bids already placed against the prior definitions.**
9. **No structured cancellation-reason field** on `RFQ` (free-text notes only via the status-history API caller) or bid-withdrawal-reason field on `RFQBid`.
10. **Resubmission-after-withdrawal is real and deliberate** (`SubmitBidCommandHandler` hard-deletes the prior `WITHDRAWN` row) — not a bug, but it means the platform does not prevent "withdraw and watch, then resubmit near the deadline."
11. **No escrow lock occurs at Direct Rental cart submit** — the wallet check at submit-preview/submit is an estimate only; funds aren't actually held until the resulting contract reaches its escrow stage (documented as a known MVP limitation in `MVP_DIRECT_RENTAL_SPECIFICATION.md` §12).
12. **Fleet-capacity accept-preview and the actual accept-time gate share the same `IProviderFleetCapacityService` codepath today** (low risk of drift), but they are two separate call sites — if one is ever changed without the other, a provider could see a false "safe to accept" signal.

---

## Integration Points

- **Contracts module:** consumes `BidAwardedEvent` (via `BidAwardedEventHandler` → `CreateContractCommand`, RFQ path) and `DirectRentalRequestAcceptedEvent`/`...PartiallyAcceptedEvent` (via `DirectRentalRequestAcceptedEventHandler` → `CreateDirectRentalContractCommand`, Direct Rental path); reads/cancels `DeliverySession` rows when a post-delivery vehicle is unassigned.
- **Finance module:** `IWalletService`/`IWalletCalculationService` provide business wallet balance checks at RFQ award time and Direct Rental cart submit-preview/submit; actual escrow locking happens downstream once a contract exists, triggered by `ContractCreatedEvent`.
- **Identity module:** `Provider.TrustScore` read live and snapshotted into `RFQBidSnapshot` at bid submission; `IProviderValidationService`/`ProviderFleetCapacityService` gate bid/award/Direct-Rental-accept eligibility on verification status and fleet-segment capacity; `Vehicle.IsAvailableForDirectRental`/`EnableDirectRental()`/`DisableDirectRental()` and vehicle status/insurance drive Direct Rental catalog eligibility.
- **MasterData module:** provider tier + commission-strategy lookup for contract commission rate, resolved at contract-creation time on both the RFQ path (`BidAwardedEventHandler`) and the Direct Rental path (`CreateDirectRentalContractCommandHandler`), each with its own 5% default fallback.
- **Notifications module:** `RFQPublishedNotificationHandler` (4-channel fanout, live fleet-match filtering), `BidSubmittedEvent`/`BidWithdrawnEvent`/`BidRejectedEvent` notifications, `DirectRentalNotificationHandlers` for submit/accept/reject/expire/cancel.
