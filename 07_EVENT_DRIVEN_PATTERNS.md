# Event-Driven Patterns (MediatR)

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Framework:** MediatR (In-Process)  
**Pattern:** Domain Events & Integration Events

---

## 📋 Overview

The Movello MVP uses a **Modular Monolith** architecture where modules communicate primarily through **in-process events** using MediatR. This decouples modules, ensuring that a change in one module (e.g., Identity) doesn't require direct synchronous calls to another (e.g., Finance).

### Key Concepts
- **Domain Events:** Things that happened *inside* an aggregate (e.g., `OrderLineAdded`). Handled within the same module.
- **Integration Events:** Things that happened that *other modules* care about (e.g., `ContractCreated`). Handled by other modules.
- **Commands:** Requests to *do* something (e.g., `CreateRFQ`). 1-to-1 mapping.
- **Queries:** Requests to *get* something (e.g., `GetRFQ`). 1-to-1 mapping.
- **Notifications:** Events broadcast to multiple handlers. 1-to-many mapping.

---

## 🏗️ Event Structure

### Base Event Class

```csharp
public abstract class DomainEvent : INotification
{
    public Guid Id { get; } = Guid.NewGuid();
    public DateTime OccurredOn { get; } = DateTime.UtcNow;
}
```

### Naming Convention
- **Past Tense:** Events represent facts that have already happened.
- **Format:** `[Entity][Action]Event`
- **Examples:** `BidSubmittedEvent`, `WalletDepositedEvent`, `UserRegisteredEvent`

---

## 🔄 Communication Patterns

### 1. Module-to-Module Communication (Async)

**Scenario:** When a `Bid` is awarded in the **Marketplace** module, the **Contracts** module needs to create a contract, and the **Finance** module needs to lock escrow.

**Publisher (Marketplace):**
```csharp
// Application/Commands/AwardBidCommandHandler.cs
await _mediator.Publish(new BidAwardedEvent 
{ 
    RFQId = rfq.Id, 
    ProviderId = providerId, 
    Amount = amount 
});
```

**Consumer 1 (Contracts):**
```csharp
// Modules/Contracts/EventHandlers/BidAwardedEventHandler.cs
public class BidAwardedEventHandler : INotificationHandler<BidAwardedEvent>
{
    public async Task Handle(BidAwardedEvent notification, CancellationToken ct)
    {
        // Create Contract Logic
    }
}
```

**Consumer 2 (Finance):**
```csharp
// Modules/Finance/EventHandlers/BidAwardedEventHandler.cs
public class BidAwardedEventHandler : INotificationHandler<BidAwardedEvent>
{
    public async Task Handle(BidAwardedEvent notification, CancellationToken ct)
    {
        // Lock Escrow Logic
    }
}
```

### 2. Request/Response (Sync) - Use Sparingly

Sometimes a module needs data *immediately* from another module (e.g., Contracts needs Provider Name from Identity).

**Pattern:** Define an interface in the *Consumer's* Domain, and implement it in the *Provider's* Infrastructure.

**Contracts Module (Consumer):**
```csharp
// Domain/Services/IProviderLookupService.cs
public interface IProviderLookupService
{
    Task<ProviderSnapshot> GetProviderAsync(Guid id);
}
```

**Identity Module (Provider):**
```csharp
// Infrastructure/Services/ProviderLookupService.cs
public class ProviderLookupService : IProviderLookupService
{
    private readonly IdentityDbContext _db;
    public async Task<ProviderSnapshot> GetProviderAsync(Guid id)
    {
        // Query DB directly
    }
}
```

---

## 📜 Event Catalog

### Identity Module
| Event | Trigger | Consumers |
|-------|---------|-----------|
| `BusinessRegisteredEvent` | Business KYB approved | Finance (Create Wallet) |
| `ProviderVerifiedEvent` | Provider KYC approved | Finance (Create Wallet) |
| `TrustScoreUpdatedEvent` | Score recalculated | Contracts (Update Snapshot) |

### Marketplace Module
| Event | Trigger | Consumers |
|-------|---------|-----------|
| `RFQPublishedEvent` | RFQ goes live | Notification (Email Providers) |
| `BidSubmittedEvent` | Provider bids | Notification (Notify Business) |
| `BidAwardedEvent` | Business awards bid | Contracts (Create), Finance (Lock Escrow) |

### Contracts Module
| Event | Trigger | Consumers |
|-------|---------|-----------|
| `ContractCreatedEvent` | Contract record created | Notification |
| `VehicleAssignedEvent` | Vehicle linked to contract | Delivery (Create Session) |
| `ContractCompletedEvent` | All vehicles returned | Finance (Settlement), Identity (Trust Score) |
| `VehicleReturnedEarlyEvent` | Early return processed | Finance (Partial Refund) |

### Delivery Module
| Event | Trigger | Consumers |
|-------|---------|-----------|
| `OTPGeneratedEvent` | OTP requested | Notification (Send SMS) |
| `DeliveryConfirmedEvent` | Handover complete | Contracts (Activate) |
| `DeliveryReturnConfirmedEvent` | Return complete | Contracts (Complete) |

### Finance Module
| Event | Trigger | Consumers |
|-------|---------|-----------|
| `EscrowLockedEvent` | Funds locked | Notification |
| `SettlementProcessedEvent` | Monthly payout done | Notification |

---

## 🛡️ Reliability & Transactionality

### The "Outbox Pattern" (Future Consideration)
For the MVP, we are using **in-process** events. This means if the `BidAwardedEventHandler` in Finance fails, the whole HTTP request *could* fail if not carefully managed.

**MVP Approach:**
1. **Single Transaction:** Since we share one DB (different schemas), we *can* wrap the Command + Event Handlers in a single transaction if critical.
2. **Fire-and-Forget:** For non-critical events (Notifications), use `Task.Run` or a background queue to avoid blocking the user.

**Post-MVP Approach:**
- Use **Outbox Pattern**: Save event to `Outbox` table in the same transaction as the entity.
- Background worker reads `Outbox` and publishes to RabbitMQ/Kafka.

---

## 🔧 Implementation Guide

### 1. Registering MediatR
In `Program.cs`:

```csharp
builder.Services.AddMediatR(cfg => {
    cfg.RegisterServicesFromAssembly(typeof(IdentityModule).Assembly);
    cfg.RegisterServicesFromAssembly(typeof(MarketplaceModule).Assembly);
    cfg.RegisterServicesFromAssembly(typeof(ContractsModule).Assembly);
    // ...
});
```

### 2. Validation Pipeline
Use MediatR Behaviors for cross-cutting concerns like validation.

```csharp
public class ValidationBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        if (_validators.Any())
        {
            var context = new ValidationContext<TRequest>(request);
            var failures = _validators
                .Select(v => v.Validate(context))
                .SelectMany(result => result.Errors)
                .Where(f => f != null)
                .ToList();

            if (failures.Count != 0) throw new ValidationException(failures);
        }
        return await next();
    }
}
```

---

**Next Document:** [08_SECURITY_COMPLIANCE.md](./08_SECURITY_COMPLIANCE.md)
