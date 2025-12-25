# Finance Module - Specification

**Module Name:** Finance (Wallet & Settlement)  
**Version:** 1.1 MVP  
**Date:** December 22, 2025 (Updated)  
**Database Schema:** `wallet`  
**Related Documents:** MVP_AUTHORITATIVE_BUSINESS_RULES.md (Section 3), MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md

---

## 📋 Overview

### Purpose
The Finance Module manages all monetary transactions within the platform. It implements a **double-entry ledger system** to ensure financial integrity, managing wallets, escrow locks, settlements, and commission collection.

### Responsibilities

✅ **Wallet Management**
- Virtual wallets for Businesses, Providers, and Platform
- Deposit processing (via Payment Gateway integration)
- Balance tracking (Available vs. Locked)

✅ **Escrow Management**
- Locking funds upon Contract Award
- Releasing funds upon Settlement or Refund
- Managing "Virtual Escrow" accounts

✅ **Settlement Engine**
- Calculating provider payouts based on tiers
- Deducting commissions and penalties
- Generating payout records

✅ **Accounting Integrity**
- Double-entry ledger for every transaction
- Audit trails for all financial movements
- Reconciliation support

---

## 🗄️ Database Schema

### Tables (12 Total)

1. `wallet_account` - User/Business/Provider wallets
2. `wallet_ledger_transaction` - Transaction Header
3. `wallet_ledger_entry` - Double-entry lines (Debit/Credit)
4. `wallet_balance_snapshot` - Daily/Monthly snapshots
5. `escrow_lock` - Tracks locked funds per contract
6. `settlement_cycle` - Provider payout periods
7. `settlement_payout` - Actual payout records
8. `commission_entry` - Platform earnings
9. `payment_intent` - Incoming payment tracking
10. `refund_request` - Outgoing refund tracking
11. `wallet_event_log` - Audit trail
12. `tax_record` - VAT/TOT tracking (Placeholder for MVP)

---

## 🏗️ Module Structure

```
Finance/
├── Domain/
│   ├── Entities/
│   │   ├── WalletAccount.cs
│   │   ├── WalletLedgerTransaction.cs
│   │   ├── WalletLedgerEntry.cs
│   │   ├── EscrowLock.cs
│   │   ├── SettlementCycle.cs
│   │   └── PaymentIntent.cs
│   │
│   ├── Events/
│   │   ├── WalletDepositedEvent.cs
│   │   ├── EscrowLockedEvent.cs
│   │   ├── EscrowLockFailedEvent.cs
│   │   ├── EscrowReleasedEvent.cs
│   │   ├── SettlementProcessedEvent.cs
│   │   └── PayoutCompletedEvent.cs
│   │
│   ├── Enums/
│   │   ├── TransactionType.cs (DEPOSIT, ESCROW_LOCK, SETTLEMENT, REFUND)
│   │   ├── EntryType.cs (DEBIT, CREDIT)
│   │   ├── WalletType.cs (BUSINESS, PROVIDER, PLATFORM, ESCROW)
│   │   └── PaymentStatus.cs
│   │
│   └── Services/
│       ├── ILedgerService.cs
│       ├── LedgerService.cs
│       ├── IEscrowRetryService.cs
│       └── EscrowRetryService.cs
│
├── Application/
│   ├── Commands/
│   │   ├── CreateWalletCommand.cs
│   │   ├── DepositFundsCommand.cs
│   │   ├── LockEscrowCommand.cs
│   │   ├── ProcessSettlementCommand.cs
│   │   └── ReleaseEscrowCommand.cs
│   │
│   ├── Queries/
│   │   ├── GetWalletBalanceQuery.cs
│   │   ├── GetTransactionHistoryQuery.cs
│   │   └── GetSettlementCyclesQuery.cs
│   │
│   ├── DTOs/
│   │   ├── WalletDto.cs
│   │   ├── TransactionDto.cs
│   │   └── SettlementDto.cs
│   │
│   └── Services/
│       ├── IPaymentGateway.cs (Chapa/Telebirr Adapter)
│       └── PaymentGatewayFactory.cs
│
├── Infrastructure/
│   ├── Repositories/
│   │   ├── IWalletRepository.cs
│   │   ├── WalletRepository.cs
│   │   ├── ISettlementRepository.cs
│   │   └── SettlementRepository.cs
│   │
│   └── External/
│       ├── ChapaPaymentService.cs
│       └── TelebirrPaymentService.cs
│
└── API/
    └── Controllers/
        ├── WalletsController.cs
        ├── PaymentsController.cs
        └── SettlementsController.cs
```

---

## 🔄 Key Workflows

### 1. Escrow Lock (Critical Path)

**IMPORTANT (BR-010):** Escrow lock is triggered by `ContractCreatedEvent`, NOT `BidAwardedEvent`.

**Correct Flow:**  
BidAwardedEvent → ContractCreatedEvent → **EscrowLockedEvent**

```csharp
// Command
public class LockEscrowCommand : IRequest<bool>
{
    public Guid ContractId { get; set; }
    public Guid BusinessId { get; set; }
    public decimal Amount { get; set; }
    public int RetryAttempt { get; set; } = 0;  // For retry logic
}

// Handler
public class LockEscrowCommandHandler : IRequestHandler<LockEscrowCommand, bool>
{
    private readonly IWalletRepository _walletRepository;
    private readonly ILedgerService _ledgerService;
    private readonly IMediator _mediator;

    public async Task<bool> Handle(LockEscrowCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // 1. Get Wallets
            var businessWallet = await _walletRepository.GetByOwnerIdAsync(request.BusinessId, "BUSINESS");
            var escrowWallet = await _walletRepository.GetPlatformEscrowWalletAsync();

            // 2. Validate Balance (Race Condition Check)
            if (businessWallet.AvailableBalance < request.Amount)
            {
                // FAILURE: Insufficient funds (BR-011)
                await HandleEscrowLockFailureAsync(request, "Insufficient funds");
                return false;
            }

            // 3. Create Ledger Transaction (Double Entry)
        var transaction = new WalletLedgerTransaction
        {
            Id = Guid.NewGuid(),
            ReferenceId = request.ContractId.ToString(),
            TransactionType = TransactionType.ESCROW_LOCK,
            Description = $"Escrow lock for Contract {request.ContractId}",
            Amount = request.Amount,
            CreatedAt = DateTime.UtcNow
        };

        // DEBIT Business Wallet
        var debitEntry = new WalletLedgerEntry
        {
            WalletId = businessWallet.Id,
            EntryType = EntryType.DEBIT,
            Amount = request.Amount
        };

        // CREDIT Escrow Wallet
        var creditEntry = new WalletLedgerEntry
        {
            WalletId = escrowWallet.Id,
            EntryType = EntryType.CREDIT,
            Amount = request.Amount
        };

        // 4. Create Escrow Lock Record
        var lockRecord = new EscrowLock
        {
            Id = Guid.NewGuid(),
            ContractId = request.ContractId,
            WalletId = businessWallet.Id,
            Amount = request.Amount,
            Status = "LOCKED",
            LockedAt = DateTime.UtcNow
        };

        // 5. Execute Transactionally
        await _ledgerService.ProcessTransactionAsync(transaction, new[] { debitEntry, creditEntry });
        await _walletRepository.AddEscrowLockAsync(lockRecord);

        // 6. Publish Event
        await _mediator.Publish(new EscrowLockedEvent
        {
            ContractId = request.ContractId,
            Amount = request.Amount,
            BusinessId = request.BusinessId
        });

        return true;
        }
        catch (Exception ex)
        {
            // FAILURE: Handle escrow lock failure (BR-011)
            await HandleEscrowLockFailureAsync(request, ex.Message);
            return false;
        }
    }
    
    // ESCROW LOCK FAILURE HANDLING (BR-011)
    private async Task HandleEscrowLockFailureAsync(LockEscrowCommand request, string errorMessage)
    {
        // Publish failure event
        await _mediator.Publish(new EscrowLockFailedEvent
        {
            ContractId = request.ContractId,
            BusinessId = request.BusinessId,
            Amount = request.Amount,
            RetryAttempt = request.RetryAttempt,
            ErrorMessage = errorMessage,
            FailedAt = DateTime.UtcNow
        });
        
        // Schedule retry if not exceeded max attempts (max 5 retries)
        if (request.RetryAttempt < 5)
        {
            await _escrowRetryService.ScheduleRetryAsync(
                request.ContractId,
                request.BusinessId,
                request.Amount,
                request.RetryAttempt + 1,
                delayMinutes: 30  // Retry every 30 minutes
            );
        }
        else
        {
            // Max retries exceeded - notify business and provider
            await _mediator.Publish(new EscrowLockMaxRetriesExceededEvent
            {
                ContractId = request.ContractId,
                BusinessId = request.BusinessId,
                Message = "Escrow lock failed after 5 attempts. Please check wallet balance."
            });
        }
    }
```

---

### 2. Settlement Processing (Monthly Job)

```csharp
// Command
public class ProcessSettlementCommand : IRequest<Unit>
{
    public Guid ProviderId { get; set; }
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
}

// Handler
public class ProcessSettlementCommandHandler : IRequestHandler<ProcessSettlementCommand, Unit>
{
    private readonly ISettlementRepository _settlementRepository;
    private readonly IWalletRepository _walletRepository;
    private readonly ILedgerService _ledgerService;
    private readonly IMediator _mediator;

    public async Task<Unit> Handle(ProcessSettlementCommand request, CancellationToken cancellationToken)
    {
        // 1. Calculate Gross Amount (from Completed Contracts)
        var contracts = await _settlementRepository.GetCompletedContractsAsync(request.ProviderId, request.PeriodStart, request.PeriodEnd);
        decimal grossAmount = contracts.Sum(c => c.TotalAmount);

        if (grossAmount <= 0) return Unit.Value;

        // 2. Get Provider's Current Tier and Commission Rate from MasterData (BR-040)
        var provider = await _identityService.GetProviderAsync(request.ProviderId);
        var commissionRate = await _masterDataService.GetCommissionRateForTierAsync(provider.TierCode);
        
        // Calculate Commission & Penalties
        decimal commissionAmount = grossAmount * commissionRate;
        decimal penalties = contracts.Sum(c => c.PenaltyAmount);
        
        decimal netPayable = grossAmount - commissionAmount - penalties;

        // 3. Get Wallets
        var providerWallet = await _walletRepository.GetByOwnerIdAsync(request.ProviderId, "PROVIDER");
        var escrowWallet = await _walletRepository.GetPlatformEscrowWalletAsync();
        var commissionWallet = await _walletRepository.GetPlatformCommissionWalletAsync();

        // 4. Create Ledger Transaction
        var transaction = new WalletLedgerTransaction
        {
            Id = Guid.NewGuid(),
            TransactionType = TransactionType.SETTLEMENT,
            Amount = grossAmount,
            Description = $"Settlement for {request.PeriodStart:MMM yyyy}"
        };

        // DEBIT Escrow (Total Gross)
        var debitEscrow = new WalletLedgerEntry { WalletId = escrowWallet.Id, EntryType = EntryType.DEBIT, Amount = grossAmount };

        // CREDIT Provider (Net Payable)
        var creditProvider = new WalletLedgerEntry { WalletId = providerWallet.Id, EntryType = EntryType.CREDIT, Amount = netPayable };

        // CREDIT Commission (Platform Earnings)
        var creditCommission = new WalletLedgerEntry { WalletId = commissionWallet.Id, EntryType = EntryType.CREDIT, Amount = commissionAmount + penalties };

        // 5. Execute
        await _ledgerService.ProcessTransactionAsync(transaction, new[] { debitEscrow, creditProvider, creditCommission });

        // 6. Create Settlement Record
        var settlement = new SettlementCycle
        {
            ProviderId = request.ProviderId,
            TotalGross = grossAmount,
            TotalCommission = commissionAmount,
            TotalNet = netPayable,
            Status = "COMPLETED"
        };
        await _settlementRepository.AddAsync(settlement);

        // 7. Publish Event
        await _mediator.Publish(new SettlementProcessedEvent
        {
            ProviderId = request.ProviderId,
            NetAmount = netPayable,
            SettlementId = settlement.Id
        });

        return Unit.Value;
    }
}
```

---

## 📡 Events Published

### EscrowLockedEvent
```csharp
public class EscrowLockedEvent : INotification
{
    public Guid ContractId { get; set; }
    public Guid BusinessId { get; set; }
    public decimal Amount { get; set; }
}
```

### EscrowLockFailedEvent
```csharp
public class EscrowLockFailedEvent : INotification
{
    public Guid ContractId { get; set; }
    public Guid BusinessId { get; set; }
    public decimal Amount { get; set; }
    public int RetryAttempt { get; set; }
    public string ErrorMessage { get; set; }
    public DateTime FailedAt { get; set; }
}
```

### EscrowLockMaxRetriesExceededEvent
```csharp
public class EscrowLockMaxRetriesExceededEvent : INotification
{
    public Guid ContractId { get; set; }
    public Guid BusinessId { get; set; }
    public string Message { get; set; }
}
```

### SettlementProcessedEvent
```csharp
public class SettlementProcessedEvent : INotification
{
    public Guid ProviderId { get; set; }
    public Guid SettlementId { get; set; }
    public decimal NetAmount { get; set; }
    public decimal CommissionRate { get; set; }  // Record rate used
    public string ProviderTierCode { get; set; }  // Record tier at settlement time
}
```

---

## 📡 Events Consumed

### ContractCreatedEvent (CRITICAL TRIGGER - BR-010)
- **Source:** Contracts Module
- **Action:** Triggers `LockEscrowCommand`.
- **Flow:** BidAwardedEvent → **ContractCreatedEvent** → EscrowLockedEvent
- **Critical:** If locking fails (insufficient funds), retry logic activates (BR-011)

```csharp
public class ContractCreatedEventHandler : INotificationHandler<ContractCreatedEvent>
{
    private readonly IMediator _mediator;
    
    public async Task Handle(ContractCreatedEvent notification, CancellationToken cancellationToken)
    {
        // Trigger escrow lock for the newly created contract
        var success = await _mediator.Send(new LockEscrowCommand
        {
            ContractId = notification.ContractId,
            BusinessId = notification.BusinessId,
            Amount = notification.EscrowAmount,
            RetryAttempt = 0
        });
        
        if (!success)
        {
            // Escrow lock failed - contract stays in PENDING_ESCROW status
            // Retry service will attempt again in 30 minutes
        }
    }
}
```

### BidAwardedEvent
- **Source:** Marketplace Module
- **Action:** NO DIRECT ACTION in Finance module (BR-010 clarification)
- **Note:** Contract module handles this event first, then publishes ContractCreatedEvent

### ContractTerminatedEvent
- **Source:** Contracts Module
- **Action:** Triggers `ReleaseEscrowCommand` to refund the business (minus penalties).

### VehicleReturnedEarlyEvent
- **Source:** Contracts Module
- **Action:** Triggers partial refund calculation and settlement.

---

## ✅ Business Rules

1. **Double-Entry:** Every transaction must have balanced Debits and Credits. Sum of Debits = Sum of Credits.
2. **Locked Balance:** `AvailableBalance = TotalBalance - LockedBalance`. Users can only spend `AvailableBalance`.
3. **Escrow Priority:** Escrow funds are legally ring-fenced. They cannot be used for platform operations until released.
4. **Commission:** Deducted at source during settlement.
5. **Negative Balance:** Wallets cannot have a negative balance (except potentially system wallets in specific recovery scenarios, but strictly blocked for user wallets).
6. **Currency:** MVP supports ETB (Ethiopian Birr) only.

---

**Next Module:** [Delivery_Module.md](./Delivery_Module.md)
