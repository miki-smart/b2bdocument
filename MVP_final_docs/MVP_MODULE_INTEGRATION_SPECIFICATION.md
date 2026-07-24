# Movello MVP - Module Integration Specification
## Module Communication Patterns & Dependencies

**Version:** 2.0 (rewritten against running code)
**Last verified against code: 2026-07-23**
**Original version:** 1.0, dated December 21, 2025 — described a schema-per-module, message-bus-style architecture that was never built. Preserved only in git history.
**Related documents:** [`project-docs/18_Implementation_Coverage_Audit.md`](../../../../project-docs/18_Implementation_Coverage_Audit.md), [`backlog/mvp/epic-06-contract-management.md`](../../../../backlog/mvp/epic-06-contract-management.md), [`project-docs/service-specs/contract-engine-spec.md`](../../../../project-docs/service-specs/contract-engine-spec.md), [`backlog/post-mvp/epic-21-direct-rental.md`](../../../../backlog/post-mvp/epic-21-direct-rental.md), [`backlog/mvp/epic-10-monthly-renewal-settlement.md`](../../../../backlog/mvp/epic-10-monthly-renewal-settlement.md), [`MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md`](./MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md), [`MVP_DISPUTE_RESOLUTION_WORKFLOW.md`](./MVP_DISPUTE_RESOLUTION_WORKFLOW.md), [`architecture/auth-service-microservice-spec.md`](../../../../architecture/auth-service-microservice-spec.md) (the sibling doc this rewrite follows the same current-vs-proposed pattern from)

---

## 0. What changed in this rewrite

Version 1.0 of this document described an architecture that does not exist in the codebase:

- **A message-bus/event-broker integration style** ("Publish Event" to a broker, a transactional outbox table per module, a background `EventOutboxPublisher` worker). The real system uses **in-process MediatR domain events** — `IMediator.Publish(...)` calling `INotificationHandler<TEvent>` implementations synchronously in the same request/process, inside the same `Marketplace.API` ASP.NET Core process. There is no message broker, no outbox table, and no separate publisher worker anywhere in the backend.
- **Per-module database schemas** (`marketplace_schema`, `contracts_schema`, `finance_schema`, etc.) with cross-schema SQL joins shown as example queries. The real system uses **one shared Postgres database with no schema-per-module isolation** — snake_case tables (`contracts`, `contract_line_items`, `wallet_accounts`, `settlement_cycles`, ...) all live in the same default schema, accessed through one shared EF Core `DbContext` per module's repository classes, not raw cross-schema SQL.
- **A `Disputes` module** with its own schema and API. **This module does not exist.** The backend has exactly 8 module folders under `Modules/`: `Auth`, `Contracts`, `Delivery`, `Finance`, `Identity`, `Marketplace`, `MasterData`, `Notifications`. There is no `Modules/Disputes` anywhere in the codebase — see [`MVP_DISPUTE_RESOLUTION_WORKFLOW.md`](./MVP_DISPUTE_RESOLUTION_WORKFLOW.md) for the full accounting of what does and does not exist around disputes.
- **Redis-cached MasterData with a 6-hourly cache-warm job.** No Redis dependency or cache-loader job was found anywhere in the backend for MasterData; MasterData is read directly from Postgres per-request through its own repositories. (If a caching layer is added later, this document should be updated to match — it is not there today.)
- **A separate API Gateway routing requests to per-module "services."** There is one deployable (`Marketplace.API`), one `Program.cs`, one set of controllers under one process — not eight independently deployed services behind a gateway.

What follows describes the real module list, the real in-process event mechanism, and the real cross-module integration points, verified directly against the code named throughout.

---

## 1. MODULE ARCHITECTURE OVERVIEW (as implemented)

### 1.1 Module List

`Marketplace.API` is a single .NET 9 ASP.NET Core process containing 8 module folders under `Modules/`:

1. **Auth** — Keycloak-backed login/session/MFA-stub integration (see `architecture/auth-service-microservice-spec.md` for the full current-vs-proposed picture; not otherwise covered here)
2. **Marketplace** — RFQ (header + `RFQLineItem[]`), per-line-item bidding (`RFQBidItem`), multi-provider split awards (`RFQBidAward`/`RFQAwardVehicleAssignment`), and Direct Rental (`DirectRentalCart/Request`) — Direct Rental lives in the Marketplace module, not a separate one
3. **Contracts** — Contract lifecycle (18 real status strings, not the 6-value model v1.0 assumed), vehicle-assignment sub-lifecycle, dual-party OTP terms signing, termination/completion
4. **Finance** — Wallets, double-entry ledger, escrow locks, settlement cycles/payouts, payment-gateway webhooks (Chapa/Telebirr/CBEBirr), withholding tax
5. **Delivery** — Delivery/return OTP verification, vehicle inspection checklists
6. **Identity** — Users, businesses, providers, vehicles, insurance, KYC/KYB, provider trust score (`TrustScoreCalculator`, provider-only — see `project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md` §1)
7. **MasterData** — Lookups, commission strategies/tiers, contract/escrow/settlement policy versions and rules, vehicle types, geography, banks
8. **Notifications** — Email/SMS/push (FCM) multi-channel provider system, admin-configurable, plus real-time SignalR hub (`NotificationHub`); a pure event consumer, does not publish domain events of its own

There is **no `Disputes` module**. `DISPUTED`/`ON_HOLD` exist only as unused, reserved values on the `Contract.Status` string field — see §2.4 and `MVP_DISPUTE_RESOLUTION_WORKFLOW.md` for the complete picture.

### 1.2 Data Storage (single shared database, no schema isolation)

```
Marketplace.API (one process)
│
└── PostgreSQL (one shared database, one EF Core model per module's DbContext,
    all tables in the default schema, snake_case naming via EFCore.NamingConventions)
    ├── contracts, contract_line_items, contract_vehicle_assignments,
    │   contract_terms_acceptances, contract_status_history            (Contracts)
    ├── rfqs, rfq_line_items, rfq_bids, rfq_bid_items, rfq_bid_awards,
    │   direct_rental_carts, direct_rental_requests                    (Marketplace)
    ├── wallet_accounts, wallet_ledger_transactions, wallet_ledger_entries,
    │   escrow_locks, settlement_cycles, settlement_payouts,
    │   monthly_settlement_schedules                                   (Finance)
    ├── delivery_sessions, delivery_return_sessions, vehicle_inspection_checklists (Delivery)
    ├── businesses, providers, vehicles, user_accounts, insurance_records (Identity)
    ├── lookups, lookup_types, commission_strategy_versions,
    │   contract_policy_versions, settlement_policy_versions            (MasterData)
    └── (Notifications persists templates/config/logs, not shown in full)
```

There is no cross-schema foreign key isolation to enforce — everything is one physical database — but modules still observe logical ownership boundaries in their repository/DbContext code (a module's repository only queries the tables it owns, plus read-only lookups against Identity/MasterData entities via EF Core navigation or explicit queries, not raw cross-schema SQL as v1.0 showed).

### 1.3 Architecture Principles (as implemented)

**Principle 1: No cross-module writes bypassing the owning module's domain logic**
- A module does not directly mutate another module's entities from its own command handlers.
- Instead: Module A's domain method fires a MediatR notification → Module B's `INotificationHandler<TEvent>` runs Module B's own command/service to update Module B's own entities.
- This is enforced by convention and code review, not by a database-level schema boundary (since there is only one schema).

**Principle 2: Read access across modules is real and direct, via EF Core**
- Handlers commonly query another module's `DbContext`/repository directly for read-only lookups (e.g., Finance reading `Provider.TrustScore`/tier, Contracts reading `Vehicle.Status`) — this is a normal in-process method call and/or EF query against the shared database, not a network call.
- There is no MasterData Redis cache in the real system; MasterData reads go straight to Postgres per call.

**Principle 3: Event-driven state changes are real, but in-process**
- State changes that other modules care about are raised as MediatR notifications (`IMediator.Publish(event)`) from the owning module's domain/application layer.
- Other modules' `INotificationHandler<TEvent>` implementations run **synchronously, in the same request pipeline, in the same process** — not asynchronously via a broker. If a handler throws, it can affect the outcome of the original request unless the calling code explicitly isolates failures (this varies by handler; it is not a guaranteed fire-and-forget style across the board).
- There is no outbox table, no background event-publisher worker, and no at-least-once/exactly-once delivery guarantee beyond normal in-process method-call semantics.

---

## 2. REAL CROSS-MODULE INTEGRATION POINTS

This section replaces v1.0's generic decision matrix/flowchart with the actual integration points verified against code, grouped by the module pairs the task explicitly calls out.

### 2.1 Marketplace ↔ Contracts (award → contract creation)

**RFQ path:**
- A business awards one or more `RFQLineItem`s of a bid to a provider (possibly split across providers per line item — `RFQBidAward`/`RFQAwardVehicleAssignment`).
- Marketplace fires `BidAwardedEvent`.
- `Modules/Contracts/Application/EventHandlers/BidAwardedEventHandler.cs` handles it: groups all awards belonging to one bid-award action, resolves the provider's commission rate from `ProviderTierAssignment`/`CommissionStrategy` (MasterData, defaulting to 5% if nothing resolves), and issues `CreateContractCommand`.
- Contract is created with `SourceType = RFQ`, status `PENDING_ESCROW`, one `ContractLineItem` per awarded line item; RFQ-sourced contracts never pre-create vehicle assignments — they always require the separate vehicle-assignment step (§2.2 of `epic-06-contract-management.md`, Story 6.3).

**Direct Rental path (parallel, not the same code path):**
- Direct Rental is a fixed-price, non-bidding booking channel living inside the **Marketplace module** (`DirectRentalCart(Item)`, `DirectRentalRequest(LineItem/Vehicle)` entities, `DirectRentalCartController`/`DirectRentalRequestController`) — not a separate module, and not one of the numbered epics until `backlog/post-mvp/epic-21-direct-rental.md` formalized it retroactively.
- A provider accepting (or partially accepting) a submitted request fires `DirectRentalRequestAcceptedEvent` / `...PartiallyAcceptedEvent`.
- `Modules/Contracts/Application/EventHandlers/DirectRentalRequestAcceptedEventHandler.cs` issues `CreateDirectRentalContractCommand` — **idempotent**: if a contract already exists for that request (e.g. a retried event), it re-syncs vehicle assignments instead of duplicating the `Contract` row.
- Contract is created with `SourceType = DIRECT_RENTAL`, linked to the originating request; unlike the RFQ path, vehicle assignments **are** pre-created immediately (the business already chose specific vehicles during browse/cart), so there is no separate post-creation vehicle-assignment step for this path (epic-21, Story 21.9).
- Both paths converge on the same `Contract` aggregate, the same `Contract.Status` string field, and the rest of the lifecycle below — Direct Rental is an acquisition channel into the standard contract machinery, not a parallel contract model.

### 2.2 Contracts ↔ Finance (escrow lock / release triggers)

**Lock, on contract creation:**
- `Contract.Create*` factories always set the initial status to `PENDING_ESCROW` and publish `ContractCreatedEvent`.
- `Modules/Finance/Application/EventHandlers/ContractCreatedEventHandler.cs` locks `Σ line item (UnitAmount × QuantityAwarded × min(DurationDays, 30))` from the business's `MAIN` wallet into `ESCROW`, double-entry, with 5-attempt exponential backoff (1s/2s/4s/8s/16s) on transient failure.
- On success: `Contract.ActivateAfterEscrowLock()` moves status to `PENDING_VEHICLE_ASSIGNMENT` (RFQ default) or `PENDING_SIGNING` (Direct Rental, vehicles already assigned); `ContractEscrowLockedEvent` is published — this is **not** activation, just a successful lock.
- On exhausted retries: `Contract.MarkAsEscrowLockFailed()` → `ESCROW_LOCK_FAILED`; a separate `EscrowTimeoutJob` (15-minute interval) later cancels any contract still stuck in `PENDING_ESCROW` past a configurable timeout (default 24h, MasterData `ESCROW_RELEASE_DELAY_HOURS`) via `Contract.Cancel()` → `CANCELLED` (a status **not present** in the C# `ContractStatus` enum at all — see `MVP_CONTRACT_STATE_MACHINE.md`).
- **Known internal inconsistency (per the 2026-07-23 audit, §10.5):** a second, competing escrow-lock code path (`FinanceBidAwardedEventHandler`, using the MasterData policy engine) also exists but does not actually run in the live flow — only `ContractCreatedEventHandler`'s hardcoded-constant path does. The two paths also look up the platform commission wallet using two different `AccountType` strings (`"COMMISSION"` vs `"PLATFORM_COMMISSION"`) for what should be the same wallet. Flagged here so no integration work assumes both paths are equally live.

**Release, on settlement:**
- Contract activation and delivery events do not themselves move money — settlement is a separate, scheduled process (see `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` and `epic-10-monthly-renewal-settlement.md`). On admin approval of a `SettlementPayout`, Finance debits the business `ESCROW` wallet, credits the provider `MAIN` wallet, the platform `COMMISSION` wallet, and the platform `TAX` wallet, and either refunds unused escrow (final cycle) or rolls it into the next cycle's lock (non-final cycle) — all inside `Modules/Finance/Application/Settlement/Commands/ApproveSettlementPayoutCommand.cs`. This does **not** go back through a Contracts-published event; Finance reads contract/line-item/assignment data directly (`IContractsUnitOfWork`) rather than waiting on a new Contracts event per settlement.
- Termination/abort paths also trigger escrow refunds directly in Contracts-owned code (`AbortContractBeforeSigningCommand` refunds locked escrow back to the business `MAIN` wallet as part of the same handler, not via a round-trip event to Finance).

### 2.3 Delivery ↔ Contracts (OTP/checklist confirmation → activation)

- Delivery module confirms a vehicle handover (OTP + optional inspection checklist) and fires `DeliveryConfirmedEvent`.
- `Modules/Contracts/Application/EventHandlers/DeliveryConfirmedEventHandler.cs` marks the corresponding `ContractVehicleAssignment` `DELIVERED`, increments `ContractLineItem.QuantityDelivered`, and recomputes contract status: `PARTIALLY_DELIVERED` while some assigned vehicles remain undelivered, `ACTIVE` once every assigned vehicle across every line item is delivered.
- On the **first** delivery for a contract, `GenerateSettlementScheduleCommand` runs, anchoring the monthly settlement schedule to that first delivery date — not to contract creation (this is the integration point `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` §1.3 depends on).
- On the delivery that completes the last remaining vehicle, `ContractActivatedEvent` fires — this is the one true "activation" moment in the system; it is distinct from, and later than, the dual-party OTP terms-signing step (`PENDING_SIGNING → PENDING_DELIVERY`), which is a separate mechanism from delivery confirmation entirely (Epic 06 Story 6.4 vs. Story 6.5).
- Symmetrically, `Modules/Contracts/Application/EventHandlers/DeliveryReturnConfirmedEventHandler.cs` handles `DeliveryReturnConfirmedEvent`: marks the assignment `RETURNED`, releases the vehicle back to `APPROVED`, recomputes status toward `PARTIALLY_RETURNED`, and once every assignment is `RETURNED`, fires an admin in-app notification flagging the contract as completion-eligible (no automatic settlement or completion is triggered by this alone).

### 2.4 All modules ↔ Notifications (event fan-out)

- Notifications is a **pure consumer** — it never publishes its own domain events for other modules to react to; every other module's events fan out into it.
- Pattern: each event has a dedicated `INotificationHandler<TEvent>` class under `Modules/Notifications/EventHandlers/`, one handler class per event, e.g. `ContractCreatedNotificationHandler`, `ContractActivatedNotificationHandler`, `ContractTerminatedNotificationHandler`, `ContractCompletionRequestedNotificationHandler`, `BidAwardedNotificationHandler`, `BidRejectedNotificationHandler`, `DeliveryConfirmedNotificationHandler`, `DeliveryReturnConfirmedNotificationHandler`, `SettlementCycleGeneratedNotificationHandler`, `SettlementPayoutApprovedNotificationHandler`, `DirectRentalNotificationHandlers` (covers submit/accept/reject/expire/cancel for that channel), `DepositCompletedNotificationHandler`, plus auth/account handlers (`AccountOTPNotificationHandler`, `BusinessRegisteredNotificationHandler`, `ProviderVerifiedNotificationHandler`, etc.).
- Each handler resolves recipient(s), renders the configured template for the enabled channels (email/SMS/push, each independently toggleable per category via `NotificationAdminController`'s 40+ admin endpoints), and dispatches — plus, for in-app notifications, pushes to the recipient's live connection via the `NotificationHub` SignalR hub if connected.
- Gaps confirmed by the audit and still true: no automated notification is wired for `ESCROW_LOCK_FAILED` (marked `// TODO` in the handler); status-history/notification coverage is inconsistent across some Contracts transitions (e.g., the transient `SIGNED` status and some admin-only transitions don't always produce a distinct notification).

---

## 3. IN-PROCESS EVENT MECHANISM (replaces v1.0's message-bus/outbox pattern)

### 3.1 How an event actually flows

```csharp
// Illustrative shape of the real pattern — MediatR INotificationHandler, not a broker

// 1. Publishing module's domain/application layer, inside a command handler,
//    AFTER the local state change and (in most handlers) inside the same
//    EF Core SaveChanges transaction as the state change itself:
await _mediator.Publish(new ContractCreatedEvent(contract.Id, contract.BusinessId, ...), cancellationToken);

// 2. Subscribing module's handler — runs synchronously, same process, same call stack:
public class ContractCreatedEventHandler : INotificationHandler<ContractCreatedEvent>
{
    public async Task Handle(ContractCreatedEvent notification, CancellationToken cancellationToken)
    {
        // locks escrow, retries on failure, etc. — see §2.2
    }
}
```

- **No outbox table, no background publisher worker, no message broker** (Kafka/RabbitMQ/SQS/etc.) exists anywhere in the backend. `IMediator.Publish` fans a single in-process notification out to every registered `INotificationHandler<T>` for that event type, all running in the calling thread before the publish call returns (MediatR's default in-process notification publisher).
- **Idempotency** is handled per-handler where it matters (e.g., `DirectRentalRequestAcceptedEventHandler`/`CreateDirectRentalContractCommand` re-syncs instead of duplicating on a repeat call), not via a generic idempotency-key table as v1.0's example showed.
- **Multiple handlers per event** are normal — e.g. `ContractCreatedEvent` is handled by both `Modules/Finance/Application/EventHandlers/ContractCreatedEventHandler.cs` (escrow lock) and `Modules/Notifications/EventHandlers/ContractCreatedNotificationHandler.cs` (notify parties) — MediatR dispatches to all registered handlers for the published type.
- **Failure semantics:** because handlers run in-process and synchronously, an unhandled exception in one handler can propagate back to the original HTTP request depending on how/where `Publish` is awaited — this is a materially different failure mode from a broker-based system (where a subscriber failure does not affect the publisher's original transaction). No systematic review of "does handler failure roll back the publisher's own commit" was done for this rewrite; treat this as a real behavior to verify case-by-case, not a guarantee either way.

### 3.2 Real event names actually found in the codebase (illustrative, not exhaustive)

| Publishing module | Event | At least one real consumer |
|---|---|---|
| Marketplace | `BidAwardedEvent` | Contracts (`BidAwardedEventHandler`), Notifications |
| Marketplace | `DirectRentalRequestAcceptedEvent` / `...PartiallyAcceptedEvent` / `...RejectedEvent` / `...ExpiredEvent` / `...CancelledEvent` / `...SubmittedEvent` | Contracts (accepted/partially-accepted only), Notifications (all) |
| Contracts | `ContractCreatedEvent` | Finance (escrow lock), Notifications |
| Contracts | `ContractEscrowLockedEvent` | Notifications |
| Contracts | `ContractActivatedEvent` | Notifications; Finance does not re-subscribe to this for money movement (settlement is schedule-driven, not activation-event-driven) |
| Contracts | `ContractTermsAcceptedEvent` | Notifications |
| Delivery | `DeliveryConfirmedEvent` | Contracts (`DeliveryConfirmedEventHandler`), Notifications |
| Delivery | `DeliveryReturnConfirmedEvent` | Contracts (`DeliveryReturnConfirmedEventHandler`), Notifications |
| Finance | `SettlementPayoutApprovedEvent`, `WalletCreditedEvent` | Notifications |
| Finance | `SettlementCycleGeneratedEvent`-equivalent | Notifications (`SettlementCycleGeneratedNotificationHandler`) |

Exact event-class names, fields, and the full handler list should be confirmed against `Modules/*/Domain/Events/` and `Modules/Notifications/EventHandlers/` before being treated as a stable contract for new work — this table is illustrative of the real pattern, not an exhaustive catalog. (`MVP_EVENT_CATALOG_AND_HANDLERS.md` in this same folder should be treated with the same "verify before relying on" caution as this document was before its own rewrite.)

**Confirmed absent:** `InsuranceExpiredEvent`/`InsuranceExpiringEvent` and a daily insurance-monitor cron job, as v1.0 described in its Identity-integration example — no such job or event was found in the backend; this was aspirational in v1.0, not a simplification of something real.

---

## 4. READ PATTERNS (real, direct EF Core queries — not raw cross-schema SQL)

Cross-module reads are real and common, but happen as ordinary in-process EF Core repository calls or method calls against another module's read model/DTOs — not the literal `queryIdentity('SELECT ... FROM identity_schema...')` string-SQL v1.0 showed (there is no `identity_schema` prefix; tables are unprefixed in the one shared schema). Representative real examples:

- **Contracts reads Identity** for vehicle status/ownership when validating vehicle-assignment requests (`Vehicle` must be `APPROVED`, owned by the awarded provider, not already active on another contract).
- **Finance reads Identity** for the provider's current tier (`ProviderTierAssignment`) and reads MasterData (`CommissionStrategy`) to resolve a commission rate at contract-creation time (owned/resolved by MasterData/Marketplace logic, merely consumed by Contracts/Finance — see `epic-06-contract-management.md` Story 6.1).
- **Finance reads Contracts** during settlement generation (`IContractsUnitOfWork`, reading `ContractVehicleAssignment.DeliveredAt`/`ReleasedAt` windowed against each `MonthlySettlementSchedule`'s cycle dates) — a direct cross-module read, not an event-driven pull.
- **Delivery reads Contracts** to validate that a delivery/return confirmation applies to a real, currently-assignable `ContractVehicleAssignment`.
- **All modules read MasterData** directly per call (lookups, policy versions, commission strategies) — there is no cache-aside Redis layer in the real system; if one is added later, update this section.

---

## 5. MODULE API BOUNDARIES (real, per-module controllers under one process)

There is no API Gateway routing to independently deployed services. All controllers live in the single `Marketplace.API` process; module boundaries are reflected in controller/route naming, not deployment topology. Representative real routes (not exhaustive — see each module's own controller files and the referenced epics for full endpoint tables):

- **Marketplace:** `Controllers/Marketplace/*` — RFQ CRUD/publish, bid submit/withdraw, award (including split-award), plus Direct Rental (`DirectRentalCartController`, `DirectRentalRequestController`, `DirectRentalVehicleController`, admin `AdminDirectRentalController`)
- **Contracts:** `Controllers/Contracts/ContractsController.cs` — `GET/POST /contracts/...`, `terms/otp/generate|verify`, `line-items/{id}/assign-vehicle|unassign-vehicle`, `termination/request|approve`, `completion/request|approve|reject|cancel`, `abort-before-signing`, `reset-vehicle-assignments` (see `project-docs/service-specs/contract-engine-spec.md` §5 for the full list)
- **Finance:** `Controllers/Finance/*` — wallet, escrow, `SettlementController` (`GET/POST /api/finance/settlements/...` — see `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` §2 for the exact real endpoint list), `PaymentController` (gateway webhooks)
- **Delivery:** `Controllers/Delivery/*` — OTP generate/verify/resend, return sessions, inspection checklists
- **Identity:** `Controllers/Identity/*` — profile, business/provider detail, vehicle CRUD + insurance + direct-rental enable/disable, trust score read endpoints
- **MasterData:** `Controllers/MasterData/*`, plus dedicated controllers like `BusinessTiersController`/`ProviderTiersController`, `SettlementPoliciesController` — admin-only writes, broad reads
- **Notifications:** `NotificationAdminController` (40+ endpoints: provider config, credential rotation, test-send, per-category × per-channel toggles) plus a `NotificationHub` SignalR endpoint for real-time delivery

Mobile clients hit a parallel `Controllers/Mobile/*` route tree (`MobileContractController`, `MobileAuthController`, `MobileWalletController`, etc.) rather than the web-facing routes above — see `MOBILE_APP_SPEC.md` for the mobile endpoint table.

---

## 6. DATA OWNERSHIP & RESPONSIBILITIES (real)

| Module | Owns | Notes vs. v1.0 |
|---|---|---|
| Marketplace | RFQs, line items, bids/bid items, awards, **Direct Rental carts/requests** | Direct Rental was not in v1.0 at all — it shipped later and lives here, not in a separate module |
| Contracts | Contracts, line items, vehicle assignments, terms acceptances, status history | 18 real status strings, not the 6-value model v1.0 implied by omission |
| Finance | Wallets, ledger entries, escrow locks, settlement cycles/payouts/schedules | No generic `Settlement`/`Debt` tables as shown in v1.0 §1 — real entities are `SettlementCycle`/`SettlementPayout(LineItem)`/`MonthlySettlementSchedule`; **no `Debt` entity exists anywhere** in the codebase (see `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` §0 for the full correction) |
| Delivery | Delivery/return sessions, OTP verifications, inspection checklists | Return-trip OTP + checklist system (Epic 07 scope, undocumented in the original epic text) |
| Identity | Users, businesses, providers, vehicles, insurance, provider trust score | Trust score is provider-only — no business-side risk score exists (`project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md` §1) |
| MasterData | Lookups, commission strategies/tiers, contract/escrow/settlement policy versions | No Redis cache layer; reads go straight to Postgres |
| Notifications | Templates, per-category/channel config, delivery logs | Pure consumer — publishes nothing for other modules to react to |
| — | **Disputes** | **Does not exist.** No module, no schema, no entities, no API. See `MVP_DISPUTE_RESOLUTION_WORKFLOW.md`. |

---

## 7. What was correct in v1.0 and is kept conceptually

A few high-level ideas in the original document are directionally still true, just implemented differently:

- **Modules should not directly write into another module's data — they should go through that module's own domain logic.** True today; enforced via MediatR events + code convention rather than a hard schema boundary.
- **Reads across modules are cheaper/simpler than writes and are done liberally.** True today, just as direct EF Core queries against the one shared database rather than cross-schema SQL against physically separate schemas.
- **MasterData changes are infrequent and don't need real-time push to other modules.** Still true — MasterData still doesn't publish events — the correction is only that there's no Redis cache-aside layer sitting in front of it today.

---

**For Implementation:** treat this document, not v1.0, as the reference for how modules actually talk to each other. When adding a new cross-module integration, follow the existing pattern for the module pair involved (§2) rather than inventing a new mechanism (no message broker, no outbox, no Redis cache-aside for MasterData) unless a separate architectural decision explicitly introduces one.

**For Architecture Reviews:** verify against real code, not this document's prose, for anything load-bearing — module boundaries evolve; re-run a targeted search against `Modules/*/Domain/Events/` and `Modules/Notifications/EventHandlers/` before assuming an event/handler pair described here is still current.
