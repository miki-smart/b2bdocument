# Movello MVP - Event Catalog and Handler Specifications
## Event-Driven Architecture Reference

**Last verified against code: 2026-07-23**
**Document Status:** Rewritten against running code (previous "AUTHORITATIVE, approved" version described a system that was never built)
**Ground truth:** every `Modules/**/Domain/Events/*.cs` and `Modules/**/Application/**/EventHandlers/*.cs` file under `marketplace-project-implementation/backend/src/Marketplace.API/`, plus `Infrastructure/Persistence/MarketplaceDbContext.cs`, `Infrastructure/Repositories/UnitOfWork.cs`, and `Program.cs`.
**Companion document (mechanism/how-it-works):** [`../07_EVENT_DRIVEN_PATTERNS.md`](../07_EVENT_DRIVEN_PATTERNS.md) — read that first for *how* dispatch works (in-process MediatR, after-commit timing, the two raise mechanisms, the RabbitMQ SMS side-channel). This document is the *catalog* — every real event, its real fields, its real producer, and every real consumer.
**Related:** `architecture/backend-architecture-assessment-2026-07-12.md`, `architecture/backend-remediation-roadmap-2026-07-12.md`, `backlog/mvp/epic-11-notification-system.md` (Notifications is by far the largest consumer of this catalog — ~35 handler files / 40 handler classes), `backlog/mvp/epic-06-contract-management.md` / `project-docs/service-specs/contract-engine-spec.md` (narrative contract event flow), `project-docs/18_Implementation_Coverage_Audit.md`.

---

## What changed in this rewrite

The previous version of this document was aspirational, not descriptive. It invented a message-bus-shaped event envelope (`eventId`/`eventType`/`eventVersion`/`correlationId`/`causationId`/`aggregateId`/`metadata.publisherId`), exactly-once delivery guarantees, a dead-letter queue, saga compensating-action pseudocode, JavaScript handler pseudocode (this is a C#/.NET codebase — there is no JavaScript event handler anywhere), a whole **Dispute module** with four events (`DisputeCreatedEvent`, `DisputeEvidenceSubmittedEvent`, `DisputeResolvedEvent`, `DisputeEscalatedEvent`) that **does not exist in the codebase at all** — no `Dispute` entity, no Disputes module folder, nothing — and roughly 20 other events (`ProviderRejectedAwardEvent`, `RFQCancelledEvent`, `ContractCreationFailedEvent`, `VehicleAssignmentFailedEvent`, `ContractActivationTimeoutEvent`, `ContractAlteredEvent`, `EarlyReturnRequestedEvent`, `EarlyReturnApprovedEvent`, `WalletDepositedEvent`, `EscrowLockedEvent` — vs. the real `ContractEscrowLockedEvent` — `EscrowLockFailedEvent`, `EscrowReleasedEvent`, `SettlementProcessedEvent`, `SettlementFailedEvent`, `RefundProcessedEvent`, `MonthEndSettlementEvent`, `DeliveryScheduledEvent`, `DeliveryRejectedEvent`, `DeliveryNoShowEvent`, `VehicleReturnedEvent` — vs. the real `DeliveryReturnConfirmedEvent` — `BusinessVerifiedEvent`, `BusinessSuspendedEvent`, `ProviderSuspendedEvent`, `InsuranceExpiringEvent`, `VehicleVerifiedEvent`, `VehicleSuspendedEvent`) that also do not exist anywhere in the backend.

This rewrite replaces every one of those with the **49 events that actually exist**, grepped directly from `Domain/Events/*.cs` across the five modules that produce any (Contracts, Delivery, Finance, Identity, Marketplace — Auth and MasterData produce none; Notifications produces none, it is purely a consumer), cross-referenced against every real `INotificationHandler<T>` implementation to build an honest raised → consumed matrix. Where an event is defined but never raised, or raised but never consumed, that is stated explicitly — several of the "dead event" cases turned out to be genuine, current gaps, not writing errors in this document.

---

## TABLE OF CONTENTS

1. [How Events Actually Work Here (Summary)](#1-how-events-actually-work-here-summary)
2. [Real Processing Guarantees](#2-real-processing-guarantees)
3. [Event Catalog by Module](#3-event-catalog-by-module)
4. [Real Event Flow Narratives](#4-real-event-flow-narratives)
5. [Error Handling — What Actually Happens on Failure](#5-error-handling--what-actually-happens-on-failure)
6. [Dead, Inert, and Gap Events — Consolidated](#6-dead-inert-and-gap-events--consolidated)
7. [Appendix: Complete Real Event List](#7-appendix-complete-real-event-list)

---

## 1. How Events Actually Work Here (Summary)

Full explanation lives in `07_EVENT_DRIVEN_PATTERNS.md`. Short version, needed to read this catalog correctly:

- An event is a C# `record` implementing `MediatR.INotification` — either directly, via the `Marketplace.API.Shared.Events.DomainEvent` abstract record base, or (rarely) via the near-empty `Marketplace.API.Shared.Common.IDomainEvent` marker. All three dispatch identically.
- **"Published"** means one of two things happened: `entity.AddDomainEvent(new XEvent(...))` (collected by `BaseEntity`, drained and dispatched by `MarketplaceDbContext.SaveChangesAsync` after the save succeeds), or a handler called `_mediator.Publish(new XEvent(...))` directly (fires immediately, independent of any save).
- **"Consumed"** means a class implementing `MediatR.INotificationHandler<XEvent>` exists somewhere in the codebase and is registered via the single `AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(Program).Assembly))` call in `Program.cs`. There is one assembly (it's a monolith) — no per-module registration, no separate consumer process, no network hop.
- **Dispatch timing (fixed 2026-07-13):** if the raising code is inside an explicit `BeginTransactionAsync()`/`CommitTransactionAsync()` block, the event is held and only dispatched after the commit succeeds; an explicit rollback drops it. Outside a transaction, it dispatches immediately after `SaveChangesAsync`.
- **RabbitMQ** is used by exactly two consumers in this entire catalog (`OTPGeneratedEventHandler`, `ReturnOTPGeneratedEventHandler`, both in Delivery) to fire-and-forget an SMS-gateway message onto a named routing key (`notification.sms.movello`). No other event in this catalog touches RabbitMQ, and no outbox/DLQ backs that publish.

---

## 2. Real Processing Guarantees

**There is no exactly-once delivery, no idempotency-key store, and no dead-letter queue anywhere in this codebase.** The previous version of this document's `checkIdempotency(event.eventId)` / `storeIdempotencyKey(...)` pattern does not exist. What actually provides safety, where it exists at all:

- **At-most-once, best-effort, per-handler-isolated.** MediatR invokes every registered `INotificationHandler<T>` for a published event; each handler is independently wrapped in its own `try/catch`. A throwing handler is logged (Serilog) and does **not** stop other handlers for the same event, and does **not** fail the original command/save that triggered it — this is true for essentially every handler in this catalog except the one described next.
- **One real retry loop exists**: `ContractCreatedEventHandler` (Finance) retries escrow-lock up to 5 times with exponential backoff (1s/2s/4s/8s/16s) before marking the contract `ESCROW_LOCK_FAILED` and re-throwing. No other handler in this catalog has retry logic — everything else is single-attempt.
- **Hand-written idempotency guards exist in a handful of specific handlers** (e.g. `BusinessRegisteredWalletHandler`/`ProviderRegisteredWalletHandler` check for an existing wallet before creating one; `DirectRentalRequestAcceptedEventHandler`'s downstream `CreateDirectRentalContractCommand` re-syncs instead of duplicating if a contract already exists), but this is per-handler defensive code, not a framework facility any handler gets for free.
- **Ordering is not guaranteed or enforced** between multiple handlers of the same event. See §4.1 for a real example (`BidAwardedEvent`) where two module handlers race and one silently no-ops as a result.
- **No saga/compensating-action framework exists.** Where a multi-step flow needs a "what if step 3 fails" answer, the real answer is almost always a background sweep job (`EscrowTimeoutJob`, `ContractEndLifecycleJob`), not an event-driven compensation.

---

## 3. Event Catalog by Module

Every event below is real — its C# signature is transcribed from the actual `record` declaration in `Domain/Events/`. "Raised by" names the real file/method (or entity method) that calls `AddDomainEvent`/`Publish`. "Consumed by" lists every real `INotificationHandler<T>` implementation, module by module. "●" marks an event with at least one real, functioning consumer; "○" marks an event that is defined and even raised, but has **zero** consumers today (a genuine gap, not a documentation omission).

### 3.1 Identity Module Events (`Modules/Identity/Domain/Events/`)

| Event | Status |
|---|---|
| `AccountEmailOTPGeneratedEvent` | ● |
| `AccountOTPGeneratedEvent` | ● |
| `BusinessRegisteredEvent` | ● |
| `InsuranceExpiredEvent` | ○ (raised, zero consumers) |
| `PasswordResetOTPGeneratedEvent` | ● |
| `ProviderRegisteredEvent` | ● |
| `ProviderVerifiedEvent` | ● |
| `TrustScoreUpdatedEvent` | ○ (never even raised) |
| `UserAccountCreatedEvent` | ● |
| `VehicleRegisteredEvent` | ○ (never even raised) |

#### `AccountEmailOTPGeneratedEvent(Guid UserId, string Email, string OtpCode, string FirstName) : DomainEvent`
Raised during account creation when the email-verification OTP is generated.
**Consumed by:** `AccountEmailOTPNotificationHandler` (Notifications) — sends the OTP via email.

#### `AccountOTPGeneratedEvent(Guid UserId, string PhoneNumber, string OtpCode, string FirstName, string Email) : DomainEvent`
Raised during account creation when the phone-verification OTP is generated.
**Consumed by:** `AccountOTPNotificationHandler` (Notifications) — sends via SMS, or email if SMS is disabled platform-wide.

#### `BusinessRegisteredEvent(Guid BusinessId, Guid UserAccountId, string BusinessName, string Email) : DomainEvent`
Raised when a business account is registered.
**Consumed by:**
- `BusinessRegisteredWalletHandler` (Finance) — creates the business's `MAIN` wallet account (`WalletAccount.Create(businessId, "BUSINESS", "MAIN", "ETB")`), idempotent (checks for an existing wallet first, logs and skips if found; failures are caught and logged, never block registration).
- `BusinessRegisteredNotificationHandler` (Notifications) — sends a welcome notification.

#### `InsuranceExpiredEvent(Guid VehicleId, Guid PolicyId, DateTime ExpiryDate) : DomainEvent`
Raised from `Vehicle.cs` when an insurance policy's `ValidTo` date passes.
**Consumed by:** nobody. **Zero registered handlers exist for this event.** This is a real, current gap — a vehicle's insurance can expire and nothing in the system reacts (no notification to the provider, no automatic vehicle-status change tied to *this event specifically*; whatever insurance-expiry UI exists elsewhere is driven by direct queries, not this event).

#### `PasswordResetOTPGeneratedEvent(Guid UserId, string PhoneNumber, string OtpCode, string FirstName, string Email) : DomainEvent`
**Consumed by:** `PasswordResetOTPNotificationHandler` (Notifications) — SMS, with email fallback if SMS is disabled.

#### `ProviderRegisteredEvent(Guid ProviderId, string ProviderName, string Email) : DomainEvent`
Raised in `Provider.Create` (fixed 2026-07-13 remediation — previously never raised at all, see §6).
**Consumed by:**
- `ProviderRegisteredWalletHandler` (Finance) — creates the provider's `MAIN` wallet, same idempotent-check pattern as the business handler.
- `ProviderRegisteredNotificationHandler` (Notifications) — welcome notification.

#### `ProviderVerifiedEvent(Guid ProviderId, DateTime VerifiedAt) : DomainEvent`
Raised in `Provider.Verify` (fixed 2026-07-13 remediation).
**Consumed by:** `ProviderVerifiedNotificationHandler` (Notifications).

#### `TrustScoreUpdatedEvent(Guid ProviderId, int OldScore, int NewScore) : DomainEvent`
Defined, but **never raised anywhere in the codebase and never consumed anywhere**. This is the event-level symptom of a larger, confirmed finding (`project-docs/18_Implementation_Coverage_Audit.md` §10.2): `TrustScoreCalculator`/`ITrustScoreCalculator` is fully implemented and unit-tested, but has **zero production call sites**. Nothing in the delivery-confirmation, contract-completion, no-show, or bid-rejection flow ever calls it or publishes this event — every provider's trust score is frozen at its registration-time default (50) unless an admin manually intervenes via the tier-assignment endpoint.

#### `UserAccountCreatedEvent(Guid UserId, string KeycloakUserId, string Email, string FirstName, string LastName, UserType UserType) : DomainEvent`
Raised whenever any new user account (business, provider, admin, compliance officer) is created.
**Consumed by:**
- `UserAccountCreatedWalletHandler` (Finance) — **this is a no-op by design.** It logs which downstream stage will actually create the wallet (`CompleteBusinessOnboardingCommandHandler` for BUSINESS, `RegisterProviderCommandHandler` for PROVIDER) and returns `Task.CompletedTask`. Real wallet creation happens via `BusinessRegisteredEvent`/`ProviderRegisteredEvent` (above), tied to the Business/Provider entity ID, not the raw user account — this handler exists purely to document that decision in code and log the no-op.
- `UserAccountCreatedNotificationHandler` (Notifications) — sends account-created notification(s).

#### `VehicleRegisteredEvent(Guid VehicleId, Guid ProviderId, string LicensePlate) : DomainEvent`
Defined, **never raised, never consumed anywhere in the codebase**. Fully inert — do not build against it assuming it fires.

---

### 3.2 Marketplace Module Events (`Modules/Marketplace/Domain/Events/MarketplaceEvents.cs`)

All 13 events in this module live in one file. All are real; none are fabricated.

| Event | Status |
|---|---|
| `RFQCreatedEvent` | ● |
| `RFQPublishedEvent` | ● |
| `RFQExpiredEvent` | ● |
| `BidSubmittedEvent` | ● |
| `BidAwardedEvent` | ● (2 cross-module consumers + notifications) |
| `BidRejectedEvent` | ● |
| `BidWithdrawnEvent` | ● |
| `DirectRentalRequestAcceptedEvent` | ● |
| `DirectRentalRequestPartiallyAcceptedEvent` | ● |
| `DirectRentalRequestRejectedEvent` | ● |
| `DirectRentalRequestExpiredEvent` | ● |
| `DirectRentalRequestSubmittedEvent` | ● |
| `DirectRentalRequestCancelledEvent` | ● |

#### `RFQCreatedEvent(Guid RFQId, Guid BusinessId, string Title, string RFQNumber) : DomainEvent`
Raised via a namespace-qualified `new Events.RFQCreatedEvent(...)` inside the RFQ entity itself — the 2026-07-12 audit's grep originally missed this qualified form and flagged it as dead; the 2026-07-13 correction confirmed it was never actually broken.
**Consumed by:** `RFQCreatedNotificationHandler` (Notifications) only. (The original document claimed an Identity "audit" consumer — no such handler exists.)

#### `RFQPublishedEvent(Guid RFQId) : DomainEvent`
**Consumed by:** `RFQPublishedNotificationHandler` (Notifications) — notifies eligible providers an RFQ is live.

#### `RFQExpiredEvent(Guid RFQId, Guid BusinessId, string Title, string RFQNumber, DateTime ExpiredAt) : DomainEvent`
Raised by the `RFQDeadlineJob` background job for RFQs past their deadline. Same false-positive/correction history as `RFQCreatedEvent`.
**Consumed by:** `RFQExpiredNotificationHandler` (Notifications).

#### `BidSubmittedEvent(Guid BidId, Guid RFQId, Guid ProviderId) : DomainEvent`
**Consumed by:** `BidSubmittedNotificationHandler` (Notifications) — notifies the business a new bid arrived. (No trust-score consumer exists — `TrustScoreUpdatedEvent` is never wired to bid activity; see §3.1.)

#### `BidAwardedEvent(Guid BidId, Guid RFQId, Guid ProviderId) : DomainEvent`
The busiest event in the catalog — the real trigger for contract creation. Note the real signature carries **no amount/quantity fields** — every consumer re-derives dollar amounts from the persisted `RFQBidAward` rows, not from the event payload.
**Consumed by (in registration order, but MediatR does not guarantee execution order between them):**
- `BidAwardedEventHandler` (Contracts) — reads the awards for this bid (checking the EF change tracker first for pending/unsaved awards, falling back to the database), resolves the provider's commission rate via `ProviderTierAssignment`/`CommissionStrategy` (MasterData, defaulting to 5%), and sends `CreateContractCommand`. **This is the handler that actually creates the `Contract` row.**
- `FinanceBidAwardedEventHandler` (Finance) — computes an escrow amount from the MasterData escrow-policy engine, then looks up a `Contract` for the RFQ/provider pair. **In practice this lookup usually comes back empty**, because `BidAwardedEventHandler` (above) may not have finished creating the contract yet when this handler runs — MediatR gives no ordering guarantee between the two. The handler logs *"Contract not yet created... escrow will be handled during contract creation"* and returns, discarding the escrow amount it just computed. **Real escrow locking happens later, from a different event** — see `ContractCreatedEvent` below. This is a confirmed, documented dead-code path (`project-docs/18_Implementation_Coverage_Audit.md` §10.5): two escrow-calculation formulas exist in the codebase (this one, MasterData-policy-driven; and the one in `ContractCreatedEventHandler`, a hardcoded 30-day cap), and only the second ever actually executes.
- `BidAwardedNotificationHandler` (Notifications) — notifies the provider they won.

#### `BidRejectedEvent(Guid BidId, Guid RFQId, Guid ProviderId, Guid BusinessId) : DomainEvent`
**Consumed by:** `BidRejectedNotificationHandler` (Notifications).

#### `BidWithdrawnEvent(Guid BidId, Guid RFQId, Guid ProviderId, Guid BusinessId) : DomainEvent`
**Consumed by:** `BidWithdrawnNotificationHandler` (Notifications).

#### Direct Rental request events (all `(Guid RequestId, Guid BusinessId, Guid ProviderId[, ...])  : DomainEvent`)
- `DirectRentalRequestAcceptedEvent` / `DirectRentalRequestPartiallyAcceptedEvent` — **consumed by** `DirectRentalRequestAcceptedEventHandler` (Contracts, a single class implementing both `INotificationHandler<T>` interfaces, both branches calling the same private method to send `CreateDirectRentalContractCommand` — idempotent: re-syncs vehicle assignments instead of duplicating if a contract already exists for the request) **and** the matching notification handler class in `DirectRentalNotificationHandlers.cs` (Notifications).
- `DirectRentalRequestRejectedEvent`, `DirectRentalRequestExpiredEvent`, `DirectRentalRequestSubmittedEvent(..., string RequestNumber)`, `DirectRentalRequestCancelledEvent` — **each consumed by its own handler class**, all six bundled together in the single file `Modules/Notifications/EventHandlers/DirectRentalNotificationHandlers.cs` (`DirectRentalRequestSubmittedNotificationHandler`, `...AcceptedNotificationHandler`, `...PartiallyAcceptedNotificationHandler`, `...RejectedNotificationHandler`, `...ExpiredNotificationHandler`, `...CancelledNotificationHandler`). No cross-module (non-notification) consumer exists for the reject/expire/cancel variants — only acceptance creates a contract.

---

### 3.3 Contracts Module Events (`Modules/Contracts/Domain/Events/`)

| Event | Status |
|---|---|
| `ContractCreatedEvent` | ● |
| `ContractEscrowLockedEvent` | ● |
| `VehicleAssignedEvent` | ● |
| `VehicleUnassignedEvent` | ○ (raised, zero consumers — documented extension point) |
| `ContractTermsAcceptedEvent` | ● (Delivery only — no Notifications handler) |
| `ContractActivatedEvent` | ● |
| `ContractTerminatedEvent` | ● |
| `ContractCompletionRequestedEvent` | ● |
| `ContractCompletionApprovedEvent` | ● |

#### `ContractCreatedEvent(Guid ContractId, Guid BusinessId, Guid ProviderId, decimal TotalAmount, int DurationDays, DateTime StartDate, DateTime EndDate, DateTime CreatedAt) : MediatR.INotification`
Published by `CreateContractCommandHandler` once the `Contract` row (RFQ path) or `CreateDirectRentalContractCommandHandler` (Direct Rental path) is saved. **This — not `BidAwardedEvent` — is the real trigger for escrow locking.**
**Consumed by:**
- `ContractCreatedEventHandler` (Finance) — the real escrow-lock handler. Computes `Σ line item: UnitAmount × QuantityAwarded × min(DurationDays, 30)` (hardcoded 30-day cap, not the MasterData policy engine — see the `FinanceBidAwardedEvent` note above), retries up to 5× with exponential backoff on failure, double-entry debits the business `MAIN` wallet and credits a `ESCROW` wallet, creates an `EscrowLock` row, calls `contract.ActivateAfterEscrowLock()` (moves status to `PENDING_SIGNING` if all line items are already assigned — Direct Rental — or `PENDING_VEHICLE_ASSIGNMENT` otherwise — RFQ), then publishes `ContractEscrowLockedEvent`. On the 5th failure: `contract.MarkAsEscrowLockFailed()` → status `ESCROW_LOCK_FAILED`, logs `LogCritical`, re-throws (the one deliberate exception to "handlers never fail the save" — this is meant to surface as an alert). A code comment marks the business/admin notification on failure as a `// TODO` — **not currently implemented**.
- `ContractCreatedNotificationHandler` (Notifications) — notifies the provider a contract exists, sent immediately (before escrow is confirmed locked) so the provider knows one is coming.

#### `ContractEscrowLockedEvent(Guid ContractId, Guid BusinessId, Guid ProviderId, string ContractNumber, decimal EscrowAmount, decimal TotalContractValue, DateTime LockedAt) : MediatR.INotification`
Published by `ContractCreatedEventHandler` (Finance, above) — despite living in the *Contracts* module's `Domain/Events/` folder, the event is actually raised from Finance code. **Not** contract activation — the code comment on the event class is explicit about this. The contract-status transition this event's docstring implies ("Contracts Module: Update contract status to PENDING_VEHICLE_ASSIGNMENT") is **not done by a separate consumer reacting to this event** — it already happened synchronously, in the same `ContractCreatedEventHandler` method, via `contract.ActivateAfterEscrowLock()`, *before* this event is even published. This event exists purely to drive notifications.
**Consumed by:** `ContractEscrowLockedNotificationHandler` (Notifications) only.

#### `VehicleAssignedEvent(Guid ContractId, Guid VehicleId, Guid ProviderId, Guid BusinessId) : MediatR.INotification`
Published when a provider/admin assigns a vehicle to a contract line item (`AssignVehicleCommandHandler`).
**Consumed by:**
- `VehicleAssignedEventHandler` (Delivery) — creates a `DeliverySession` for the vehicle, **but only if the contract has already passed the signing gate** (skips if status is `PENDING_VEHICLE_ASSIGNMENT` or `PENDING_SIGNING`); also skips if a session already exists for that contract/vehicle pair. For contracts still in the signing gate, session bootstrap instead happens via `ContractTermsAcceptedEvent` (below) once signing completes.
- `VehicleAssignedNotificationHandler` (Notifications).

#### `VehicleUnassignedEvent(Guid ContractId, Guid VehicleId, bool WasDelivered, Guid? ReplacementVehicleId) : MediatR.INotification`
Published from `UnassignVehicleCommandHandler`. **Zero registered handlers anywhere in the codebase.** A documented, intentional extension point per the 2026-07-12 architecture audit (harmless no-op today) — not a bug, but also not doing anything: no delivery-session cleanup, no notification, fires from `UnassignVehicleCommandHandler.cs:177` and goes nowhere.

#### `ContractTermsAcceptedEvent(Guid ContractId, Guid BusinessId, Guid ProviderId, string ContractNumber, string PreviousStatus, string CurrentStatus, DateTime AcceptedAt) : MediatR.INotification`
Published once both business and provider complete the dual-party OTP terms-acceptance flow (`VerifyContractTermsOtpCommandHandler`, when `Contract.MarkTermsSigned()` fires — the transient `SIGNED` → `PENDING_DELIVERY` transition, see `contract-engine-spec.md` §4.4).
**Consumed by:** `ContractTermsAcceptedEventHandler` (Delivery) **only** — bootstraps `DeliverySession` rows for every already-assigned, not-yet-sessioned vehicle on the contract, but only if the contract is in a delivery-eligible status (`PENDING_DELIVERY`, `PARTIALLY_DELIVERED`, `PARTIALLY_RETURNED`). **There is no Notifications-module handler for this event** — despite epic-11's story text implying a "signing confirmation notification," no such handler exists in `Modules/Notifications/EventHandlers/` today. Any signing-related notification a user sees comes from the terms-acceptance command handlers calling the notification publisher directly (SMS/email OTP delivery during generate/verify), not from a reaction to this domain event.

#### `ContractActivatedEvent(Guid ContractId, Guid BusinessId, Guid ProviderId, string ContractNumber, decimal TotalAmount, DateTime StartDate, DateTime EndDate, DateTime ActivatedAt, int TotalVehiclesDelivered, DateTime FirstDeliveryAt) : MediatR.INotification`
Published by `DeliveryConfirmedEventHandler` (Contracts) — **only** when the vehicle just delivered was the *last* outstanding one for the contract (`totalDeliveredAfter == totalAwarded`). This is the one true "activation" moment in the system — do not confuse with `ContractEscrowLockedEvent`, which fires much earlier.
**Consumed by:** `ContractActivatedNotificationHandler` (Notifications) only. (No Identity/trust-score consumer — see the `TrustScoreUpdatedEvent` gap in §3.1.)

#### `ContractTerminatedEvent(Guid ContractId, Guid BusinessId, Guid ProviderId, string ContractNumber, string Reason, DateTime TerminatedAt) : DomainEvent`
Published when `ApproveTerminationCommandHandler` moves a contract to `TERMINATED`.
**Consumed by:** `ContractTerminatedNotificationHandler` (Notifications) — notifies both parties.

#### `ContractCompletionRequestedEvent(Guid ContractId, Guid BusinessId, Guid ProviderId, string ContractNumber, string RequestedByParty, DateTime RequestedAt) : DomainEvent`
**Consumed by:** `ContractCompletionRequestedNotificationHandler` (Notifications) — notifies the counter-party a completion request is pending their approval.

#### `ContractCompletionApprovedEvent(Guid ContractId, Guid BusinessId, Guid ProviderId, string ContractNumber, string ApprovedByParty, DateTime CompletedAt) : DomainEvent`
Published when the counter-party (or admin override) approves completion, moving the contract to `COMPLETED`.
**Consumed by:** `ContractCompletionApprovedNotificationHandler` (Notifications).

> **Note on naming:** there is no `ContractCompletedEvent` anywhere in the codebase — the previous version of this document invented one. The real event fired on completion is `ContractCompletionApprovedEvent`.

---

### 3.4 Delivery Module Events (`Modules/Delivery/Domain/Events/`)

| Event | Status |
|---|---|
| `OTPGeneratedEvent` | ● |
| `OTPVerifiedEvent` | ○ (raised, zero consumers) |
| `DeliveryConfirmedEvent` | ● |
| `DeliveryReturnConfirmedEvent` | ● |
| `ReturnOTPGeneratedEvent` | ● |
| `ReturnSessionInitiatedEvent` | ● |
| `DeliveryChecklistApprovedEvent` | ● |
| `ReturnChecklistSubmittedEvent` | ● |
| `ReturnChecklistApprovedEvent` | ● |

#### `OTPGeneratedEvent(Guid SessionId, string ContractNumber, string RecipientPhone, string Code, string? RecipientEmail = null) : MediatR.INotification`
Raised when a delivery-handover OTP is generated.
**Consumed by:**
- `OTPGeneratedEventHandler` (Delivery) — publishes to **RabbitMQ** (routing key `notification.sms.movello`), only when `FeaturesSettings.SmsEnabled` is true. One of only two RabbitMQ consumers in the entire backend.
- `OTPGeneratedNotificationHandler` (Notifications) — the email fallback / general notification path, independent of the RabbitMQ publish.

#### `OTPVerifiedEvent(Guid SessionId, DateTime VerifiedAt) : MediatR.INotification`
Published from `VerifyOTPCommandHandler.cs:65` (a direct-publish site, not `AddDomainEvent`). **Zero registered handlers anywhere.** A documented, intentional extension point per the architecture audit — the actual "delivery confirmed" side effects (contract activation, settlement schedule, notifications) all happen via `DeliveryConfirmedEvent` (below), which is published separately from the same command flow.

#### `DeliveryConfirmedEvent(Guid SessionId, Guid ContractId, Guid VehicleId, DateTime DeliveredAt) : MediatR.INotification`
The real "vehicle handed over" event.
**Consumed by:**
- `DeliveryConfirmedEventHandler` (Contracts) — marks the `ContractVehicleAssignment` `DELIVERED`, increments `ContractLineItem.QuantityDelivered`, recomputes contract status (`PARTIALLY_DELIVERED` while some remain, `ACTIVE` once all are delivered), generates the monthly settlement schedule **on the first delivery only** (anchored to that delivery's date, not contract creation — `GenerateSettlementScheduleCommand`), and publishes `ContractActivatedEvent` when the *last* vehicle is delivered.
- `FinanceDeliveryConfirmedEventHandler` (Finance) — verifies an active `EscrowLock` exists for the contract and logs that "daily ledger accrual can begin"; the actual daily-ledger processing is done by a separate scheduled job (`ProcessDailyLedgerCommand`), not by this handler. This handler today is effectively a logging/verification no-op with a `// TODO: Could publish a FinancialTrackingStartedEvent` comment — it does not itself write any ledger entries.
- `DeliveryConfirmedNotificationHandler` (Notifications) — notifies both business and provider.

#### `DeliveryReturnConfirmedEvent(Guid SessionId, Guid ContractId, Guid VehicleId, DateTime ReturnedAt, double OdometerReading) : MediatR.INotification`
**Consumed by:**
- `DeliveryReturnConfirmedEventHandler` (Contracts) — marks the vehicle assignment `RETURNED`, releases the vehicle back to `APPROVED` status (via `Vehicle.ReleaseFromContract()`), updates line-item return counts, recomputes contract status (`PARTIALLY_RETURNED` while some assignments remain out). **When every assignment on the contract is `RETURNED`**, publishes an admin **in-app notification only** (`contract_completion_eligible_admin` template, via `INotificationPublisher.PublishInAppAsync` directly — not a further domain event) flagging the contract as completion-eligible. **No automatic settlement or completion is triggered** — both require an explicit follow-up action (two-party completion request/approve, or admin override).
- `DeliveryReturnConfirmedNotificationHandler` (Notifications).

#### `ReturnOTPGeneratedEvent(Guid SessionId, string ContractNumber, string RecipientPhone, string Code, string? RecipientEmail = null) : MediatR.INotification`
**Consumed by:** a single handler, `ReturnOTPGeneratedEventHandler` (Delivery), which — unlike the delivery-OTP equivalent above — handles **both** branches itself in one class: if `SmsEnabled`, publishes to RabbitMQ (the second of the two RabbitMQ consumers in the backend); if SMS is disabled, sends the OTP via email directly through `INotificationPublisher.PublishEmailAsync` (template `returnOTPEmail`) instead of delegating to a separate Notifications-module handler. There is no dedicated Notifications-module handler class for this event, unlike `OTPGeneratedEvent`.

#### `ReturnSessionInitiatedEvent(Guid SessionId, string SessionReference, Guid ContractId, Guid VehicleId, Guid ProviderId, Guid BusinessId, string InitiatorRole) : MediatR.INotification`
Raised when a return session is created; `InitiatorRole` (`BUSINESS`/`PROVIDER`) determines who gets notified — the party that did *not* initiate.
**Consumed by:** `ReturnSessionInitiatedNotificationHandler` (Notifications).

#### `DeliveryChecklistApprovedEvent(Guid ChecklistId, Guid DeliverySessionId, Guid ContractId, Guid VehicleId, Guid ProviderId, Guid BusinessId, DateTime ApprovedAt) : MediatR.INotification`
Raised when the business-side reviewer approves the delivery (handover) inspection checklist.
**Consumed by:** `DeliveryChecklistApprovedNotificationHandler` (Notifications) — notifies the provider.

#### `ReturnChecklistSubmittedEvent(Guid ChecklistId, Guid ReturnSessionId, Guid ContractId, Guid VehicleId, Guid ProviderId, Guid BusinessId, DateTime SubmittedAt) : MediatR.INotification`
Raised when the provider submits the return inspection checklist.
**Consumed by:** `ReturnChecklistSubmittedNotificationHandler` (Notifications) — notifies the business.

#### `ReturnChecklistApprovedEvent(Guid ChecklistId, Guid ReturnSessionId) : MediatR.INotification`
Raised when the return checklist is approved (by the provider, per the docstring).
**Consumed by:** `ReturnChecklistApprovedNotificationHandler` (Notifications) — prompts the business to request the return OTP.

---

### 3.5 Finance Module Events (`Modules/Finance/Domain/Events/`)

| Event | Status |
|---|---|
| `SettlementCycleGeneratedEvent` | ● |
| `SettlementPayoutApprovedEvent` | ● |
| `WalletCreditedEvent` | ● |
| `WithdrawalApprovedEvent` | ● |
| `WithdrawalRejectedEvent` | ● |
| `DepositCompletedEvent` | ● |
| `AdminDepositCompletedEvent` | ● (2 consumers) |
| `AdminWithdrawalCompletedEvent` | ● (2 consumers) |

#### `SettlementCycleGeneratedEvent(Guid CycleId, string CycleReference, DateTime StartDate, DateTime EndDate, int PayoutCount, decimal TotalAmount) : DomainEvent`
Published after a settlement cycle's payouts are calculated but before approval.
**Consumed by:** `SettlementCycleGeneratedNotificationHandler` (Notifications) — notifies affected providers a payout is prepared.

#### `SettlementPayoutApprovedEvent(Guid PayoutId, Guid CycleId, string CycleReference, Guid ProviderId, Guid BusinessId, decimal NetAmount, DateTime ApprovedAt) : DomainEvent`
Published when a single payout within a cycle is approved and the wallet transfer executes.
**Consumed by:** `SettlementPayoutApprovedNotificationHandler` (Notifications).

#### `WalletCreditedEvent(Guid WalletId, Guid OwnerId, string OwnerType, decimal Amount, WalletCreditSource CreditSource, string Reference) : DomainEvent`
`WalletCreditSource` is a real enum: `SettlementPayout | WithdrawalRefund | AdminDeposit`. A unifying "your wallet received funds" event across those three sources.
**Consumed by:** `WalletCreditedNotificationHandler` (Notifications).

#### `WithdrawalApprovedEvent(Guid WithdrawalRequestId, Guid OwnerId, string OwnerType, Guid WalletId, decimal Amount, DateTime ApprovedAt) : DomainEvent`
**Consumed by:** `WithdrawalApprovedNotificationHandler` (Notifications).

#### `WithdrawalRejectedEvent(Guid WithdrawalRequestId, Guid OwnerId, string OwnerType, decimal Amount, string RejectionReason, DateTime RejectedAt) : DomainEvent`
Published when an admin rejects a withdrawal request; the locked amount is released back to the wallet.
**Consumed by:** `WithdrawalRejectedNotificationHandler` (Notifications).

#### `DepositCompletedEvent(Guid WalletId, Guid OwnerId, string OwnerType, decimal Amount, string TransactionReference, string OwnerName, string PhoneNumber) : DomainEvent`
Published when a (business-initiated) deposit completes — e.g. a Chapa/Telebirr/CBEBirr payment-gateway webhook resolving successfully.
**Consumed by:** `DepositCompletedNotificationHandler` (Notifications).

#### `AdminDepositCompletedEvent` / `AdminWithdrawalCompletedEvent`
Both are `record : MediatR.INotification` with **init-only properties**, not positional records (the only two events in the catalog defined this way): `WalletId`, `TransactionId`, `Amount`, `Currency` (default `"ETB"`), `Reference`, `AdminUserId`, `AdminUserName`, `Reason`, `OwnerInfo` (a `WalletOwnerInfoDto`), `Timestamp` (defaults to `DateTime.UtcNow`). Published when an admin manually performs a wallet deposit/withdrawal on a business's or provider's behalf.
**Both consumed by two independent handlers, each implementing both event types:**
- `AdminTransactionNotificationHandler` (Finance, `Application/Wallet/EventHandlers/`) — resolves the real recipient user account from the wallet owner (business/provider/direct user lookup via Identity), then sends in-app + email (if available) + SMS (if available) notifications through `INotificationPublisher`. Skips entirely (logs a warning) if no user account can be resolved for the owner.
- `WalletAuditEventHandler` (Finance, same folder) — writes a `WalletEventLog` audit row (`ADMIN_DEPOSIT_COMPLETED`/`ADMIN_WITHDRAWAL_COMPLETED`, actor = the admin, full event payload serialized as JSON) — a permanent audit trail independent of the notification path.

Both handlers catch and log their own exceptions independently; a failure in one never affects the other or the underlying wallet transaction.

---

## 4. Real Event Flow Narratives

### 4.1 Award → Contract → Escrow → Vehicle Assignment → Signing → Delivery → Activation

This is the flow the previous document tried to describe as a "saga" with compensating actions. The real flow has no saga coordinator and no compensations — it's a chain of independently-reacting handlers, with one genuine race condition in the middle:

```
BidAwardedEvent (Marketplace)
   ├─→ BidAwardedEventHandler (Contracts) — sends CreateContractCommand → Contract row saved
   │       └─→ ContractCreatedEvent published
   │              ├─→ ContractCreatedEventHandler (Finance) — LOCKS ESCROW (real formula, 5-retry backoff)
   │              │       ├─→ contract.ActivateAfterEscrowLock() [status → PENDING_VEHICLE_ASSIGNMENT or PENDING_SIGNING]
   │              │       └─→ ContractEscrowLockedEvent published
   │              │              └─→ ContractEscrowLockedNotificationHandler (Notifications)
   │              └─→ ContractCreatedNotificationHandler (Notifications) — provider notified early
   ├─→ FinanceBidAwardedEventHandler (Finance) — computes an escrow amount, then almost always
   │       finds no Contract yet (race with the handler above) and returns without acting — DEAD PATH
   └─→ BidAwardedNotificationHandler (Notifications)

[Provider/admin assigns vehicles to line items — REST endpoint, not itself event-driven]
   └─→ VehicleAssignedEvent (Contracts) per vehicle
          ├─→ VehicleAssignedEventHandler (Delivery) — creates DeliverySession IF past signing gate
          └─→ VehicleAssignedNotificationHandler (Notifications)

[Once all line items are fully assigned, contract auto-transitions to PENDING_SIGNING]
[Both parties complete dual-party OTP terms acceptance — REST endpoints]
   └─→ ContractTermsAcceptedEvent (Contracts) — status SIGNED→PENDING_DELIVERY (SIGNED never persisted)
          └─→ ContractTermsAcceptedEventHandler (Delivery) — creates DeliverySession for any
                 already-assigned vehicle that doesn't have one yet (the deferred case from above)

[Provider generates + business verifies delivery OTP per vehicle — REST endpoints]
   └─→ OTPGeneratedEvent (Delivery) → RabbitMQ SMS (if enabled) + OTPGeneratedNotificationHandler
   └─→ DeliveryConfirmedEvent (Delivery) per vehicle delivered
          ├─→ DeliveryConfirmedEventHandler (Contracts)
          │       ├─→ marks assignment DELIVERED, updates line item + contract status
          │       ├─→ [FIRST delivery only] generates monthly settlement schedule
          │       └─→ [LAST delivery only] publishes ContractActivatedEvent
          │              └─→ ContractActivatedNotificationHandler (Notifications)
          ├─→ FinanceDeliveryConfirmedEventHandler (Finance) — verifies escrow, logs (no-op otherwise)
          └─→ DeliveryConfirmedNotificationHandler (Notifications)
```

**The one real race condition to know about:** `BidAwardedEvent` has two module consumers that both try to act on escrow (`BidAwardedEventHandler`/Contracts creates the contract; `FinanceBidAwardedEventHandler`/Finance tries to lock escrow directly). MediatR does not guarantee which runs first. In practice the Finance one almost always loses the race (no contract exists yet), discovers this, and no-ops — meaning its entire MasterData-policy-driven escrow calculation is dead code today. The *actual* escrow lock happens later and independently, triggered by `ContractCreatedEvent`, using a different (hardcoded) formula. This is flagged as a real bug/gap in `project-docs/18_Implementation_Coverage_Audit.md` §10.5, not something this document is proposing to fix.

### 4.2 Return → Completion (no auto-completion)

```
[Provider/business initiates return session — REST endpoint]
   └─→ ReturnSessionInitiatedEvent (Delivery) → ReturnSessionInitiatedNotificationHandler
[Provider submits return inspection checklist]
   └─→ ReturnChecklistSubmittedEvent (Delivery) → ReturnChecklistSubmittedNotificationHandler
[Checklist approved]
   └─→ ReturnChecklistApprovedEvent (Delivery) → ReturnChecklistApprovedNotificationHandler
          (prompts business to request the return OTP)
[Return OTP generated + verified — REST endpoints]
   └─→ ReturnOTPGeneratedEvent (Delivery) → single handler: RabbitMQ SMS or email fallback
   └─→ DeliveryReturnConfirmedEvent (Delivery) per vehicle returned
          ├─→ DeliveryReturnConfirmedEventHandler (Contracts)
          │       ├─→ marks assignment RETURNED, releases vehicle to APPROVED, updates line item
          │       ├─→ recomputes contract status (PARTIALLY_RETURNED while some remain out)
          │       └─→ [ALL assignments RETURNED] sends an admin IN-APP NOTIFICATION ONLY
          │              ("contract_completion_eligible_admin") — NOT a further domain event,
          │              and NOT an automatic completion or settlement trigger
          └─→ DeliveryReturnConfirmedNotificationHandler (Notifications)

[Either party then must explicitly call POST /contracts/{id}/completion/request, and the
 OTHER party (or admin) must call /completion/approve — this is a REST-driven two-party
 flow, not an event-driven one]
   └─→ ContractCompletionRequestedEvent → ContractCompletionRequestedNotificationHandler
   └─→ ContractCompletionApprovedEvent → ContractCompletionApprovedNotificationHandler
```

There is no event-driven path from "last vehicle returned" to `COMPLETED` — it always requires an explicit human action (two-party request/approve, or an admin override command), even though the admin gets proactively notified that the contract is now eligible.

### 4.3 Registration → Wallet Creation

```
UserAccountCreatedEvent (Identity) — fires for every account type
   ├─→ UserAccountCreatedWalletHandler (Finance) — NO-OP, just logs which later stage will create the wallet
   └─→ UserAccountCreatedNotificationHandler (Notifications)

[Business completes onboarding — REST endpoint, separate command]
   └─→ BusinessRegisteredEvent (Identity)
          ├─→ BusinessRegisteredWalletHandler (Finance) — creates MAIN wallet (idempotent)
          └─→ BusinessRegisteredNotificationHandler (Notifications)

[Provider registers — REST endpoint, separate command]
   └─→ ProviderRegisteredEvent (Identity)
          ├─→ ProviderRegisteredWalletHandler (Finance) — creates MAIN wallet (idempotent)
          └─→ ProviderRegisteredNotificationHandler (Notifications)
```

Wallet creation is tied to the **Business/Provider entity**, not the raw user account — deliberately, so the wallet ID matches the ID used everywhere else in Finance (`OwnerId`+`OwnerType`). `UserAccountCreatedEvent`'s wallet handler exists mainly to make that design decision visible in code and logs, not to do anything itself. As a safety net independent of any of this event chain, `GetOrCreateWalletAsync`-style calls inside `ReleaseEscrowCommand` and `ProcessDailyLedgerCommand` will create a wallet on demand if it's somehow still missing when money needs to move — this is what kept the system working during the period (before the 2026-07-13 fix) when `ProviderRegisteredEvent`/`BusinessRegisteredEvent`-equivalent wiring was broken for wallet-on-registration (see §6).

### 4.4 Notification fan-out shape (the general pattern, ~35 handler files / 40 handler classes)

Every Notifications-module handler in this catalog follows the same real shape (see `ContractCreatedNotificationHandler` for a representative full example): resolve the recipient(s) via `IIdentityUnitOfWork`/`IUserContactReader`, resolve their stored language preference, then independently check `INotificationPreferenceResolver.IsEnabled(preferences, channel, category)` for each of the 4 channels (`Email`, `Sms`, `Push`, `InApp`) against the relevant one of 8 categories (`Rfq`, `Bid`, `Contract`, `Delivery`, `Return`, `Settlement`, `Wallet`, `DirectRental`) before calling the matching `INotificationPublisher.PublishXAsync(...)` method — each call independently wrapped so a missing template, missing contact info, or provider outage silently skips only that one channel. The whole `Handle` method is wrapped in one more `try/catch` so a total failure here never propagates back into the triggering business transaction. Full detail: `backlog/mvp/epic-11-notification-system.md`.

---

## 5. Error Handling — What Actually Happens on Failure

There is no dead-letter queue, no retry-queue infrastructure, and no generic "3 attempts then escalate" policy applied uniformly across events, contrary to the previous version of this document. The real, per-category picture:

| Category | What really happens on handler failure |
|---|---|
| Escrow lock (`ContractCreatedEventHandler`) | 5-attempt exponential backoff (1s/2s/4s/8s/16s); on final failure, contract marked `ESCROW_LOCK_FAILED`, critical log, exception re-thrown. Business/admin notification on failure is a `// TODO`, not implemented. Business/admin can manually retry via `RetryEscrowLockCommand`. A background job (`EscrowTimeoutJob`, 15-min interval) auto-cancels contracts still stuck in `PENDING_ESCROW` past a configurable timeout (default 24h). |
| Wallet creation handlers (`BusinessRegisteredWalletHandler`, `ProviderRegisteredWalletHandler`) | Single attempt; exception caught, logged, swallowed — registration itself is never blocked by a wallet-creation failure. A missing wallet is backstopped later by `GetOrCreateWalletAsync` fallbacks in escrow-release and daily-ledger code. |
| Essentially every Notifications-module handler (~40 classes) | Single attempt; exception caught and logged inside the handler's own `try/catch`; the triggering business transaction is unaffected either way (it already committed — see the after-commit dispatch rule in `07_EVENT_DRIVEN_PATTERNS.md` §2). No retry, no DLQ — a failed notification is simply lost unless a human notices the log. |
| Cross-module state-mutating handlers (`DeliveryConfirmedEventHandler`, `DeliveryReturnConfirmedEventHandler`, `VehicleAssignedEventHandler`, `ContractTermsAcceptedEventHandler`) | Mixed: several log-and-swallow (e.g. settlement-schedule generation inside `DeliveryConfirmedEventHandler` explicitly does *not* re-throw, "settlement schedule generation failure shouldn't block delivery confirmation"), while the outer `DeliveryConfirmedEventHandler.Handle` method itself re-throws on unexpected exceptions — meaning a truly unexpected failure here **can** propagate back to the original delivery-OTP-verification request. There is no consistent policy; read the specific handler before assuming it will or won't surface an error to the caller. |
| RabbitMQ publishes (`OTPGeneratedEventHandler`, `ReturnOTPGeneratedEventHandler`) | Single attempt; exception caught, logged, swallowed — no queue-level retry, no outbox. If RabbitMQ is down when an OTP is generated, the SMS silently never gets published (the email-fallback branch only triggers when `SmsEnabled` is *configured* false, not when the publish itself fails). |

**Background sweep jobs are the real "what if this never recovers" mechanism**, not event retries:
- `EscrowTimeoutJob` (every 15 min) — cancels contracts stuck in `PENDING_ESCROW`.
- `ContractEndLifecycleJob` (daily, 00:45 UTC) — moves contracts past their end date with vehicles still outstanding to `TIMEOUT_PENDING`.
- `RFQDeadlineJob` — raises `RFQExpiredEvent` for RFQs past deadline.
- `NotificationOutboxProcessorJob` — drains the **email/SMS outbox tables** (`EmailNotificationOutbox`/`SmsNotificationOutbox`), which is a Notifications-module-internal durability pattern for those two channels specifically, not a cross-module event outbox. Per epic-11's own audited gaps: there is no delivery-status webhook ingestion from the email/SMS providers, and no automated retry policy for outbox-queued sends has been confirmed — treat outbox rows as "recorded," not "guaranteed delivered."

---

## 6. Dead, Inert, and Gap Events — Consolidated

| Event | Module | Raised? | Consumed? | Note |
|---|---|:---:|:---:|---|
| `InsuranceExpiredEvent` | Identity | ✅ | ❌ | Real gap — nothing reacts to insurance expiry via this event today. |
| `TrustScoreUpdatedEvent` | Identity | ❌ | ❌ | Never raised anywhere; trust score is never recalculated in production (§3.1). |
| `VehicleRegisteredEvent` | Identity | ❌ | ❌ | Fully inert, both directions. |
| `VehicleUnassignedEvent` | Contracts | ✅ | ❌ | Documented, harmless extension point per the architecture audit. |
| `OTPVerifiedEvent` | Delivery | ✅ | ❌ | Documented, harmless extension point — real side effects happen via `DeliveryConfirmedEvent` from the same command flow instead. |
| `FinanceBidAwardedEventHandler`'s escrow calculation | (handler, not an event) | — | — | Runs, computes a real number, then almost always discards it because the contract doesn't exist yet when it queries for one. Dead in practice, not dead in the sense of "never executes." |

Two events (`ProviderRegisteredEvent`, `ProviderVerifiedEvent`) were **historically** dead (defined, handled, never raised) until the 2026-07-13 remediation added the missing `AddDomainEvent` calls in `Provider.Create`/`Provider.Verify` — they are live today and included as "●" above; kept here as a historical note since older docs/tickets may still describe them as broken.

---

## 7. Appendix: Complete Real Event List

49 events total across the 5 event-producing modules. Auth and MasterData modules produce none. Notifications produces none — it is purely a consumer, as the original document correctly noted (that one claim held up).

| # | Event | Module | Consumers (count) | Status |
|---|---|---|---|---|
| 1 | `AccountEmailOTPGeneratedEvent` | Identity | 1 | ● |
| 2 | `AccountOTPGeneratedEvent` | Identity | 1 | ● |
| 3 | `BusinessRegisteredEvent` | Identity | 2 | ● |
| 4 | `InsuranceExpiredEvent` | Identity | 0 | ○ |
| 5 | `PasswordResetOTPGeneratedEvent` | Identity | 1 | ● |
| 6 | `ProviderRegisteredEvent` | Identity | 2 | ● |
| 7 | `ProviderVerifiedEvent` | Identity | 1 | ● |
| 8 | `TrustScoreUpdatedEvent` | Identity | 0 | ○ (never raised) |
| 9 | `UserAccountCreatedEvent` | Identity | 2 | ● |
| 10 | `VehicleRegisteredEvent` | Identity | 0 | ○ (never raised) |
| 11 | `RFQCreatedEvent` | Marketplace | 1 | ● |
| 12 | `RFQPublishedEvent` | Marketplace | 1 | ● |
| 13 | `RFQExpiredEvent` | Marketplace | 1 | ● |
| 14 | `BidSubmittedEvent` | Marketplace | 1 | ● |
| 15 | `BidAwardedEvent` | Marketplace | 3 (1 effectively dead) | ● |
| 16 | `BidRejectedEvent` | Marketplace | 1 | ● |
| 17 | `BidWithdrawnEvent` | Marketplace | 1 | ● |
| 18 | `DirectRentalRequestAcceptedEvent` | Marketplace | 2 | ● |
| 19 | `DirectRentalRequestPartiallyAcceptedEvent` | Marketplace | 2 | ● |
| 20 | `DirectRentalRequestRejectedEvent` | Marketplace | 1 | ● |
| 21 | `DirectRentalRequestExpiredEvent` | Marketplace | 1 | ● |
| 22 | `DirectRentalRequestSubmittedEvent` | Marketplace | 1 | ● |
| 23 | `DirectRentalRequestCancelledEvent` | Marketplace | 1 | ● |
| 24 | `ContractCreatedEvent` | Contracts | 2 | ● |
| 25 | `ContractEscrowLockedEvent` | Contracts (raised by Finance) | 1 | ● |
| 26 | `VehicleAssignedEvent` | Contracts | 2 | ● |
| 27 | `VehicleUnassignedEvent` | Contracts | 0 | ○ |
| 28 | `ContractTermsAcceptedEvent` | Contracts | 1 | ● |
| 29 | `ContractActivatedEvent` | Contracts | 1 | ● |
| 30 | `ContractTerminatedEvent` | Contracts | 1 | ● |
| 31 | `ContractCompletionRequestedEvent` | Contracts | 1 | ● |
| 32 | `ContractCompletionApprovedEvent` | Contracts | 1 | ● |
| 33 | `OTPGeneratedEvent` | Delivery | 2 | ● |
| 34 | `OTPVerifiedEvent` | Delivery | 0 | ○ |
| 35 | `DeliveryConfirmedEvent` | Delivery | 3 | ● |
| 36 | `DeliveryReturnConfirmedEvent` | Delivery | 2 | ● |
| 37 | `ReturnOTPGeneratedEvent` | Delivery | 1 | ● |
| 38 | `ReturnSessionInitiatedEvent` | Delivery | 1 | ● |
| 39 | `DeliveryChecklistApprovedEvent` | Delivery | 1 | ● |
| 40 | `ReturnChecklistSubmittedEvent` | Delivery | 1 | ● |
| 41 | `ReturnChecklistApprovedEvent` | Delivery | 1 | ● |
| 42 | `SettlementCycleGeneratedEvent` | Finance | 1 | ● |
| 43 | `SettlementPayoutApprovedEvent` | Finance | 1 | ● |
| 44 | `WalletCreditedEvent` | Finance | 1 | ● |
| 45 | `WithdrawalApprovedEvent` | Finance | 1 | ● |
| 46 | `WithdrawalRejectedEvent` | Finance | 1 | ● |
| 47 | `DepositCompletedEvent` | Finance | 1 | ● |
| 48 | `AdminDepositCompletedEvent` | Finance | 2 | ● |
| 49 | `AdminWithdrawalCompletedEvent` | Finance | 2 | ● |

**Total real events: 49.** 44 have at least one working consumer; 5 (`InsuranceExpiredEvent`, `TrustScoreUpdatedEvent`, `VehicleRegisteredEvent`, `VehicleUnassignedEvent`, `OTPVerifiedEvent`) do not.

There is no Dispute module and no Dispute events anywhere in the codebase — `DISPUTED`/`ON_HOLD` exist only as reserved, never-set string values on `Contract.Status` (see `contract-engine-spec.md` §3.4), with no supporting entity or event of any kind behind them.

---

**For Implementation:** use §3 as the field-level reference when writing a new handler for an existing event, and §6/§7 to check whether an event you're about to depend on actually has any consumers today.

**For Testing:** verify against real handler behavior, not the guarantees this document used to (incorrectly) promise — there is no idempotency-key store, no DLQ, and no saga compensation to test. Test: after-commit dispatch and rollback-drops-events semantics (see `DomainEventDispatchTests` in `tests/Marketplace.Tests/`), the escrow 5-retry backoff, and that a throwing Notifications handler never fails the triggering command.
