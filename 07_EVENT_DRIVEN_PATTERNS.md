# Event-Driven Patterns (MediatR)

**Last verified against code: 2026-07-23**
**Ground truth:** `marketplace-project-implementation/backend/src/Marketplace.API/Infrastructure/Persistence/MarketplaceDbContext.cs`, `Infrastructure/Repositories/UnitOfWork.cs`, `Shared/Events/DomainEvent.cs`, `Program.cs`, and every `Modules/**/Domain/Events/*.cs` / `Modules/**/Application/**/EventHandlers/*.cs` file in the backend.
**Companion document (canonical event-by-event catalog):** [`MVP_final_docs/MVP_EVENT_CATALOG_AND_HANDLERS.md`](./MVP_final_docs/MVP_EVENT_CATALOG_AND_HANDLERS.md) — this document explains the *mechanism*; that one lists every real event, its real producer, and every real consumer. Don't duplicate the catalog here — link to it.
**Related:** `architecture/backend-architecture-assessment-2026-07-12.md` (the audit that found the issues described below), `architecture/backend-remediation-roadmap-2026-07-12.md` (what was fixed and when).

> ## What changed in this rewrite
> The previous version of this document described a message-queue-shaped system that has never existed here: per-module `eventVersion`/`correlationId`/`causationId` JSON envelopes, exactly-once delivery guarantees, dead-letter queues, saga compensating actions, and per-module MediatR assembly registration (`RegisterServicesFromAssembly(typeof(IdentityModule).Assembly)`, etc., implying separately deployable module assemblies). None of that is real. What's actually running:
> - **One process, one assembly.** `Program.cs` registers MediatR once — `cfg.RegisterServicesFromAssembly(typeof(Program).Assembly)` — because `Marketplace.API` is a single project. There is no per-module assembly to register.
> - **Events are in-process C# method calls, not messages.** An event is a `record` implementing `MediatR.INotification` (or the `DomainEvent : INotification` base). Publishing it means MediatR synchronously invokes every registered `INotificationHandler<TEvent>` in the same process, same request, same .NET `Activity`/trace — there's no network hop, no broker, no serialization, and (see below) no delivery guarantee beyond "the process didn't crash."
> - **RabbitMQ exists in `docker-compose` but is used by exactly two handlers** (`OTPGeneratedEventHandler`, `ReturnOTPGeneratedEventHandler`, both in `Modules/Delivery/Application/EventHandlers/`) to fire-and-forget an SMS-gateway message. No outbox, no consumer code in this repo reads those messages back, no other event ever touches RabbitMQ. Calling this system "pub/sub" or "message-bus-based" is materially wrong — it is MediatR-in-process with a single fire-and-forget SMS side-channel.
> - **Dispatch timing was a real, since-fixed bug.** Until the 2026-07-13 remediation, `MarketplaceDbContext.SaveChangesAsync` published events immediately after `base.SaveChangesAsync()` — even inside an open `BeginTransactionAsync()` block — so notification/wallet/RabbitMQ side effects could fire on data that a subsequent rollback then erased. This is fixed (see §2 below): events raised inside an explicit transaction are now held and dispatched only after `CommitTransactionAsync` succeeds, and dropped entirely on rollback.
> - **No exactly-once delivery, no DLQ, no saga compensating actions exist anywhere in code.** Handlers are plain `try/catch`-and-log; a few (escrow lock) have bespoke retry loops written by hand, not a generic infra facility.

---

## 1. What "event-driven" actually means here

Anqelba Car Rental's backend (`Marketplace.API`) is a **.NET 9 modular monolith**: one deployable, one process, 8 module folders (Auth, Contracts, Delivery, Finance, Identity, Marketplace, MasterData, Notifications) sharing one Postgres database. Modules don't call each other's application/domain layers directly for cross-module side effects — instead:

- A module's command handler mutates its own aggregate and calls `entity.AddDomainEvent(new SomethingHappenedEvent(...))`, **or** a handler calls `_mediator.Publish(new SomethingHappenedEvent(...))` directly.
- Every other module that cares registers an `INotificationHandler<SomethingHappenedEvent>` (MediatR's term for "one event with N handlers" — this is *not* MediatR's `IRequest`/`IRequestHandler`, which is the 1:1 command/query mechanism).
- MediatR invokes all registered handlers for that event type, in-process, awaited sequentially, within the same call stack that (for a transactional command) is still inside the original HTTP request.

There is no message broker in this path, no serialization boundary, no separate consumer process, and no "subscription" concept beyond "a class exists that implements `INotificationHandler<T>`."

### Two raise mechanisms coexist (a real inconsistency, not a design choice)
- `entity.AddDomainEvent(...)` — the DDD-correct path. The entity (via `BaseEntity`) collects events in `DomainEvents`; `MarketplaceDbContext.SaveChangesAsync` pulls them off every tracked entity after `base.SaveChangesAsync()` succeeds.
- `_mediator.Publish(new XEvent(...))` directly from a command/event handler — bypasses persistence entirely; fires whenever the code executes, whether or not a save ever happens.

The 2026-07-12 audit counted 19 `AddDomainEvent` call sites vs. 38 direct `_mediator.Publish` sites. The 2026-07-13 remediation confirmed all 38 direct-publish sites in transactional handlers already publish **after** `CommitTransactionAsync`, so they were commit-safe even before the dispatch fix — migrating them to `AddDomainEvent` is a queued consistency cleanup (Phase 3 of the roadmap), not a correctness fix.

### Two base event types coexist (also real, also unreconciled)
- `Marketplace.API.Shared.Events.DomainEvent` — an abstract `record : INotification` with `EventId`/`OccurredAt`. Used by, e.g., `BusinessRegisteredEvent`, `ProviderRegisteredEvent`, `ContractTerminatedEvent`, `SettlementCycleGeneratedEvent`.
- `Marketplace.API.Shared.Common.IDomainEvent` — a near-empty marker interface (`: INotification`, no members). Some events implement `MediatR.INotification` directly instead of either base type (e.g. `ContractCreatedEvent`, `ContractActivatedEvent`, `VehicleAssignedEvent`, `DeliveryConfirmedEvent`).

Practically: it doesn't matter which of the three shapes a given event uses — MediatR dispatches all of them identically, since all three ultimately implement `INotification`. It's a hygiene inconsistency flagged in the architecture assessment, not a functional split.

---

## 2. Dispatch timing — after-commit, since 2026-07-13

This was the single most consequential fix in the July 2026 remediation. Ground truth is `MarketplaceDbContext.cs` + `UnitOfWork.cs`:

```csharp
// MarketplaceDbContext.cs (paraphrased from the real file)
private readonly List<DomainEvent> _pendingEvents = new();

public override async Task<int> SaveChangesAsync(CancellationToken ct = default)
{
    var result = await base.SaveChangesAsync(ct);   // 1. persist first
    var domainEvents = CollectDomainEventsFromTrackedEntities();

    if (Database.CurrentTransaction != null)
        _pendingEvents.AddRange(domainEvents);       // 2a. inside an explicit tx: hold
    else
        await DispatchDomainEventsAsync(domainEvents, ct); // 2b. no tx: dispatch now

    return result;
}

internal async Task DispatchPendingEventsAsync(CancellationToken ct = default) { /* called by CommitTransactionAsync */ }
internal void ClearPendingEvents() => _pendingEvents.Clear(); // called by RollbackTransactionAsync
```

```csharp
// UnitOfWork.cs
public async Task CommitTransactionAsync(CancellationToken ct = default)
{
    await _transaction.CommitAsync(ct);
    await _context.DispatchPendingEventsAsync(ct);   // events fire only after commit succeeds
}

public async Task RollbackTransactionAsync(CancellationToken ct = default)
{
    await _transaction.RollbackAsync(ct);
    _context.ClearPendingEvents();                   // events never fire
}
```

**Rules that follow from this:**
- If a handler never opens an explicit transaction (`BeginTransactionAsync`), `SaveChangesAsync` dispatches events immediately after the save — same as before the fix, but this is safe because there's no surrounding transaction to roll back.
- If a handler *does* use `BeginTransactionAsync`/`CommitTransactionAsync` (roughly 30 handlers, mostly Finance/Contracts money-path code), events raised during that unit of work are held until `CommitTransactionAsync` succeeds, then dispatched. A failing commit or an explicit `RollbackTransactionAsync` drops them — no notification, no wallet write, no RabbitMQ publish for data that was never actually persisted.
- **Handler exceptions never fail the save.** Each dispatched event is wrapped so a throwing handler is caught and Serilog-logged, not re-thrown into the HTTP request — see the try/catch pattern in every Notifications handler and most cross-module handlers below. (Exception: the escrow-lock retry handler intentionally re-throws after exhausting retries — see §4.)

This is the correct mental model for "reliability" in this system: **not** exactly-once delivery with idempotency keys and a DLQ (there is none of that), but **at-most-once, after-commit, best-effort, per-handler-isolated** dispatch. If you need guaranteed delivery for a specific side effect, don't rely on the event bus alone — see §5 for the two real fallback patterns already in use.

---

## 3. Real example: `BidAwardedEvent` — one event, two independent module reactions that don't coordinate

This is the flow the original document used as its worked example, and it's worth keeping because it's real — but the real code reveals a **race condition**, not a clean two-consumer fan-out.

**Publisher — Marketplace module**, from the bid-award command handler:
```csharp
await _mediator.Publish(new BidAwardedEvent(bidId, rfqId, providerId));
```
(Real signature: `public record BidAwardedEvent(Guid BidId, Guid RFQId, Guid ProviderId) : DomainEvent;` — no `Amount` field; escrow amount is recomputed by each consumer from the awards, not carried on the event.)

**Consumer 1 — `Modules/Contracts/Application/EventHandlers/BidAwardedEventHandler.cs`:** reads the pending (not-yet-saved, ChangeTracker-only) awards for the bid, resolves the provider's commission rate via MasterData, and sends `CreateContractCommand`. This is the handler that actually creates the `Contract` row.

**Consumer 2 — `Modules/Finance/Application/EventHandlers/FinanceBidAwardedEventHandler.cs`:** *also* reacts to `BidAwardedEvent`, computes an escrow amount using the MasterData escrow-policy engine, then looks up a `Contract` for that RFQ/provider pair — and because Contract-module's handler for the *same event* may not have created it yet, this lookup routinely comes back empty. The handler logs "*Contract not yet created... escrow will be handled during contract creation*" and returns without doing anything.

**What actually locks escrow:** a *different* event, `ContractCreatedEvent`, published by `CreateContractCommandHandler` once the contract row is saved. `Modules/Finance/Application/EventHandlers/ContractCreatedEventHandler.cs` is the handler that really locks escrow — using a **hardcoded 30-day-cap formula** (`UnitAmount × QuantityAwarded × min(DurationDays, 30)`), not the MasterData policy engine `FinanceBidAwardedEventHandler` computed and discarded. **Two escrow-calculation code paths exist in the codebase; only one of them ever actually runs**, and they use different formulas. This is a confirmed, documented gap (`project-docs/18_Implementation_Coverage_Audit.md` §10.5) — flagged here, not fixed by this doc.

**Lesson for anyone adding a new cross-module reaction to an existing event:** don't assume other consumers of the same event have already run, or that your consumer runs in any particular order relative to them — MediatR invokes `INotificationHandler<T>` implementations in undefined order, in-process, with no coordination between them. If B genuinely depends on A having completed, make B react to an event A publishes *after* finishing its own work (as Finance actually does here, via `ContractCreatedEvent`) — don't have both react to the same upstream event and hope for the best.

---

## 4. Real example: an actual hand-written retry loop (not generic infra)

`ContractCreatedEventHandler` (Finance) is the one place in the codebase with anything resembling the original doc's "retry policy" — and it's bespoke, not a MediatR pipeline behavior or generic retry facility:

```csharp
private const int MAX_RETRY_ATTEMPTS = 5;

for (int attempt = 1; attempt <= MAX_RETRY_ATTEMPTS; attempt++)
{
    try { await LockEscrowAsync(notification, ct); return; }
    catch (Exception ex)
    {
        if (attempt == MAX_RETRY_ATTEMPTS)
        {
            await HandleEscrowLockFailureAsync(notification.ContractId, ct); // -> Contract.MarkAsEscrowLockFailed()
            throw; // re-thrown deliberately, to surface as a critical log
        }
        await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt - 1)), ct); // 1s, 2s, 4s, 8s, 16s
    }
}
```

No other event handler in the codebase has this shape. Every other cross-module handler (Contracts reacting to `DeliveryConfirmedEvent`, Delivery reacting to `VehicleAssignedEvent`/`ContractTermsAcceptedEvent`, all ~40 Notifications handler classes) is a single-attempt `try/catch`-and-log — if it fails, it fails silently (logged, not retried, not re-queued). A separate background job, `EscrowTimeoutJob` (15-minute interval), independently cancels contracts still stuck in `PENDING_ESCROW` past a configurable timeout — that's the actual "what happens if escrow locking never recovers" answer, not a queue-level retry.

---

## 5. What actually provides reliability, in lieu of an outbox/DLQ

The system has **no outbox table and no dead-letter queue**. Where reliability matters, the real code uses one of these patterns instead:

1. **Idempotent fallback creation.** `GetOrCreateWalletAsync`-style calls in `ReleaseEscrowCommand` and `ProcessDailyLedgerCommand` create a wallet on demand if the event-driven creation (`ProviderRegisteredWalletHandler`/`BusinessRegisteredWalletHandler`, reacting to `ProviderRegisteredEvent`/`BusinessRegisteredEvent`) never fired or hasn't run yet. This is why the historical "dead event" bug (§6) was survivable in production before it was fixed — a second, synchronous path backstopped the async one.
2. **Idempotency guards written per-handler, not generically.** E.g. `BusinessRegisteredWalletHandler`/`ProviderRegisteredWalletHandler` check for an existing wallet before creating one — safe to re-run, but this is a hand-written `if (existingWallet != null) return;`, not a framework-level "already processed this eventId" mechanism. There is no generic idempotency-key store anywhere in the codebase; the original document's `checkIdempotency(event.eventId)` / `storeIdempotencyKey(...)` pattern does not exist.
3. **Background sweep jobs as a correctness backstop**, not a queue retry: `EscrowTimeoutJob` (escrow stuck in `PENDING_ESCROW`), `ContractEndLifecycleJob` (contract past end date with vehicles still out → `TIMEOUT_PENDING`), `RFQDeadlineJob` (raises `RFQExpiredEvent` for RFQs past deadline), `NotificationOutboxProcessorJob` (drains the email/SMS **outbox tables**, which are a Notifications-module-only pattern for those two channels — not a cross-module event outbox; see the Notifications architecture section of `backlog/mvp/epic-11-notification-system.md`).

If you're adding a new cross-module side effect and it must not be silently lost, follow one of these three patterns — don't assume the event bus itself guarantees delivery, because it explicitly does not.

---

## 6. Historical note: the "dead event" bug (fixed 2026-07-13)

Worth keeping as a cautionary example. As of the 2026-07-12 audit, four events were defined with real handlers but were **never actually raised** anywhere in the codebase (silently dead), because the raising entity method existed but nothing called it:
- `ProviderRegisteredEvent` — `ProviderRegisteredWalletHandler` existed, ready to create a wallet, but nothing called `Provider.Create`'s event-raising path. Fixed: now raised in `Provider.Create`.
- `ProviderVerifiedEvent` — same shape. Fixed: now raised in `Provider.Verify`.
- `RFQCreatedEvent` / `RFQExpiredEvent` — turned out to be a **false positive** in the original audit's grep (they were raised via a namespace-qualified `new Events.RFQCreatedEvent(...)` the grep pattern missed) — they were never actually dead. Corrected in the roadmap doc.

Two events remain genuinely "published with zero consumers" today — **not bugs, documented as intentional extension points**:
- `OTPVerifiedEvent` (published from `VerifyOTPCommandHandler`) — no handler anywhere.
- `VehicleUnassignedEvent` (published from `UnassignVehicleCommandHandler`) — no handler anywhere.

And three Identity events are defined but currently **inert** in different ways worth knowing about if you're extending Identity or Trust/Risk scoring (Epic 12):
- `InsuranceExpiredEvent` — raised (`Vehicle.cs`, when a policy's `ValidTo` passes), but has **zero registered handlers** — a real dead-event today, distinct from the two intentional no-ops above.
- `TrustScoreUpdatedEvent` and `VehicleRegisteredEvent` — defined, never raised anywhere and never handled anywhere. `TrustScoreUpdatedEvent`'s absence is the event-level symptom of the larger finding in `project-docs/18_Implementation_Coverage_Audit.md` §10.2: `TrustScoreCalculator`/`ITrustScoreCalculator` is fully built and unit-tested but has **zero production call sites** — nothing in the delivery/completion/no-show/rejection flow ever recalculates or publishes a score change.

**Takeaway:** "an event exists with this name" is not evidence it does anything. Before building against any event in this system, grep both `Domain/Events/` (is it ever raised?) and `EventHandlers/` (does anything consume it?) — exactly as this rewrite did. See the companion catalog for the full raised/consumed matrix per event.

---

## 7. Registering MediatR (the real, single-assembly form)

```csharp
// Program.cs (real, abbreviated)
builder.Services.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssembly(typeof(Program).Assembly); // one assembly — it's a monolith
    cfg.AddOpenBehavior(typeof(LoggingBehavior<,>));
    cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
    cfg.AddOpenBehavior(typeof(QueryNoTrackingBehavior<,>)); // constrained to IQuery<T>
});
```

There is no per-module `RegisterServicesFromAssembly(typeof(SomeModule).Assembly)` anywhere, because there are no per-module assemblies — every `Modules/<X>/` folder compiles into the single `Marketplace.API` binary. The three pipeline behaviors shown are real and shipped in the July 2026 remediation (Phase 1/3): `ValidationBehavior` activates the 26 previously-dead FluentValidation validators; `LoggingBehavior` logs every request's duration and flags anything over 3s; `QueryNoTrackingBehavior` disables EF change tracking for every `IQuery<T>` (156 of them). None of these behaviors run for `INotificationHandler`/event dispatch — they apply to the `IRequest`/`IRequestHandler` (command/query) side of MediatR only.

---

## 8. Request/response between modules (the non-event path)

Not every cross-module need fits "publish an event and move on" — sometimes a handler needs data from another module *synchronously*, in the same call. The real pattern, confirmed in the Contracts↔Finance/Identity/MasterData and Delivery↔Contracts handlers throughout this codebase: a public reader/contract interface defined in `Modules/<Consumer>/Application/Contracts/` (or the *owning* module's `Application/Contracts/`, per the module-layout convention), implemented in the owning module's Infrastructure, injected directly — no MediatR involved. Examples already in production: `IIdentityUnitOfWork`/`IUserContactReader` (Identity, read by Notifications and Contracts), `IContractsUnitOfWork` (read by Finance and Delivery event handlers), `IContractVehicleOccupancyReader` (Contracts, read by Marketplace's fleet-capacity services). This is the same pattern the original document described in principle — it's just implemented as per-module UoW/reader interfaces rather than a single bespoke `IProviderLookupService`-style interface per query.

---

## 9. Where to look next

- **Full event catalog** (every real event, exact field list, real producer, every real consumer, per-module): [`MVP_final_docs/MVP_EVENT_CATALOG_AND_HANDLERS.md`](./MVP_final_docs/MVP_EVENT_CATALOG_AND_HANDLERS.md).
- **Notifications module specifically** (the biggest event-driven consumer — ~35 handler files, 40 handler classes): `backlog/mvp/epic-11-notification-system.md`.
- **Contract lifecycle event flow in narrative form**: `project-docs/service-specs/contract-engine-spec.md` §6, `backlog/mvp/epic-06-contract-management.md`.
- **The architecture issues referenced throughout this document** (god `IUnitOfWork`, dual raise mechanisms, dispatch timing, CQRS-in-name-only): `architecture/backend-architecture-assessment-2026-07-12.md`.
- **What was fixed, when, and what's still open**: `architecture/backend-remediation-roadmap-2026-07-12.md`.

---

**Next Document:** [08_SECURITY_COMPLIANCE.md](./08_SECURITY_COMPLIANCE.md)
