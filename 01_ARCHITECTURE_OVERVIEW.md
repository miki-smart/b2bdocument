# Movello MVP - Architecture Overview

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Architecture Pattern:** Modular Monolith with BFF  
**Status:** Production-Ready Specification

---

## 📋 Table of Contents

1. [Architecture Pattern](#architecture-pattern)
2. [System Components](#system-components)
3. [Module Structure](#module-structure)
4. [Communication Patterns](#communication-patterns)
5. [Data Architecture](#data-architecture)
6. [Security Architecture](#security-architecture)
7. [Deployment Architecture](#deployment-architecture)
8. [Scalability Strategy](#scalability-strategy)

---

## 🏗️ Architecture Pattern

### Modular Monolith

**Definition:** A single deployable application organized into independent, loosely-coupled modules with clear boundaries and responsibilities.

**Why Modular Monolith for MVP?**

| Aspect | Microservices | Modular Monolith | Decision |
|--------|---------------|------------------|----------|
| **Development Speed** | Slower (network, contracts) | 30-50% faster | ✅ Monolith |
| **Operational Complexity** | High (orchestration, monitoring) | Low (single deployment) | ✅ Monolith |
| **Debugging** | Complex (distributed tracing) | Simple (single process) | ✅ Monolith |
| **ACID Transactions** | Difficult (distributed) | Native (single DB) | ✅ Monolith |
| **Team Size** | Requires 10+ developers | Works with 3-5 developers | ✅ Monolith |
| **Migration Path** | N/A | Clear extraction strategy | ✅ Monolith |

**Migration Strategy:** Each module is designed with clear boundaries, making future extraction to microservices straightforward when scale demands it.

---

## 🎯 System Components

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         PRESENTATION LAYER                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────┐       ┌──────────────────────┐      │
│  │  Business Portal     │       │  Provider Portal     │      │
│  │  (Angular 19)        │       │  (Angular 19)        │      │
│  │  - RFQ Management    │       │  - Marketplace       │      │
│  │  - Bid Review        │       │  - Bid Submission    │      │
│  │  - Contract Tracking │       │  - Contract Tracking │      │
│  │  - Wallet            │       │  - Wallet            │      │
│  └──────────┬───────────┘       └──────────┬───────────┘      │
│             │                                │                  │
│             └────────────────┬───────────────┘                  │
│                              │                                  │
└──────────────────────────────┼──────────────────────────────────┘
                               │
                               │ HTTPS/WSS
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                         BFF LAYER (YARP)                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ API Gateway  │  │ Auth Proxy   │  │ WebSocket    │         │
│  │ (Routing)    │  │ (Keycloak)   │  │ (SignalR)    │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               │ Internal HTTP
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                    APPLICATION LAYER (.NET 9)                   │
├─────────────────────────────────────────────────────────────────┤
│                    Marketplace.API (Modular Monolith)           │
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐   │
│  │   Identity &   │  │  Marketplace   │  │   Contracts    │   │
│  │   Compliance   │  │    Module      │  │    Module      │   │
│  │    Module      │  │                │  │                │   │
│  │                │  │  - RFQ         │  │  - Lifecycle   │   │
│  │  - Users       │  │  - Bidding     │  │  - Amendments  │   │
│  │  - KYC/KYB     │  │  - Awards      │  │  - Penalties   │   │
│  │  - Vehicles    │  │                │  │                │   │
│  │  - Trust Score │  │                │  │                │   │
│  └────────────────┘  └────────────────┘  └────────────────┘   │
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐                        │
│  │    Finance     │  │    Delivery    │                        │
│  │    Module      │  │    Module      │                        │
│  │                │  │                │                        │
│  │  - Wallets     │  │  - OTP         │                        │
│  │  - Escrow      │  │  - Handover    │                        │
│  │  - Settlement  │  │  - Returns     │                        │
│  │  - Commission  │  │                │                        │
│  └────────────────┘  └────────────────┘                        │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│              Shared Kernel (Common, Events, Security)           │
├─────────────────────────────────────────────────────────────────┤
│                    MediatR (Event Bus)                          │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                         DATA LAYER                              │
├─────────────────────────────────────────────────────────────────┤
│                   PostgreSQL 16 (Single Database)               │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ masterdata   │  │  identity    │  │ marketplace  │         │
│  │   schema     │  │   schema     │  │   schema     │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │  contracts   │  │   wallet     │  │  delivery    │         │
│  │   schema     │  │   schema     │  │   schema     │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE SERVICES                      │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │  Keycloak    │  │    Redis     │  │    MinIO     │         │
│  │  (Auth)      │  │   (Cache)    │  │  (Storage)   │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📦 Module Structure

### 1. Identity & Compliance Module

**Responsibility:** User management, KYC/KYB verification, vehicle compliance, trust scoring

**Bounded Context:**
```
Identity/
├── Domain/
│   ├── Entities/
│   │   ├── UserAccount.cs
│   │   ├── Business.cs
│   │   ├── Provider.cs
│   │   ├── Vehicle.cs
│   │   └── VehicleInsurance.cs
│   ├── Events/
│   │   ├── BusinessVerifiedEvent.cs
│   │   ├── ProviderVerifiedEvent.cs
│   │   └── TrustScoreUpdatedEvent.cs
│   └── Enums/
│       ├── VerificationStatus.cs
│       └── ProviderTier.cs
│
├── Application/
│   ├── Commands/
│   │   ├── RegisterBusinessCommand.cs
│   │   ├── VerifyDocumentCommand.cs
│   │   └── UpdateTrustScoreCommand.cs
│   ├── Queries/
│   │   ├── GetBusinessByIdQuery.cs
│   │   └── GetProviderTrustScoreQuery.cs
│   ├── DTOs/
│   └── Validators/
│
├── Infrastructure/
│   ├── Data/
│   │   └── IdentityDbContext.cs
│   ├── Repositories/
│   └── Services/
│       └── TrustScoreCalculator.cs
│
└── API/
    └── Controllers/
        ├── BusinessController.cs
        ├── ProviderController.cs
        └── VehicleController.cs
```

**Database Schema:** `identity`

**Key Events Published:**
- `BusinessRegisteredEvent`
- `ProviderVerifiedEvent`
- `VehicleRegisteredEvent`
- `TrustScoreUpdatedEvent`
- `InsuranceExpiredEvent`

**Key Events Consumed:**
- `ContractCompletedEvent` → Update trust score
- `DeliveryConfirmedEvent` → Update trust score
- `PenaltyAppliedEvent` → Update trust score

---

### 2. Marketplace Module

**Responsibility:** RFQ management, blind bidding, award processing

**Bounded Context:**
```
Marketplace/
├── Domain/
│   ├── Entities/
│   │   ├── RFQ.cs
│   │   ├── RFQLineItem.cs
│   │   ├── RFQBid.cs
│   │   ├── RFQBidSnapshot.cs
│   │   └── RFQBidAward.cs
│   ├── Events/
│   │   ├── RFQCreatedEvent.cs
│   │   ├── BidSubmittedEvent.cs
│   │   └── BidAwardedEvent.cs
│   └── ValueObjects/
│       └── BidAmount.cs
│
├── Application/
│   ├── Commands/
│   │   ├── CreateRFQCommand.cs
│   │   ├── SubmitBidCommand.cs
│   │   └── AwardBidCommand.cs
│   ├── Queries/
│   │   ├── GetOpenRFQsQuery.cs
│   │   └── GetBidsForRFQQuery.cs
│   └── Services/
│       └── BlindBiddingService.cs
│
├── Infrastructure/
│   └── Repositories/
│
└── API/
    └── Controllers/
        ├── RFQController.cs
        └── BiddingController.cs
```

**Database Schema:** `marketplace`

**Key Events Published:**
- `RFQCreatedEvent`
- `BidSubmittedEvent`
- `BidAwardedEvent`
- `RFQClosedEvent`

**Key Events Consumed:**
- `BusinessVerifiedEvent` → Allow RFQ creation
- `ProviderVerifiedEvent` → Allow bidding
- `WalletBalanceUpdatedEvent` → Validate escrow capacity

---

### 3. Contracts Module

**Responsibility:** Contract lifecycle, vehicle assignments, amendments, penalties

**Bounded Context:**
```
Contracts/
├── Domain/
│   ├── Entities/
│   │   ├── Contract.cs
│   │   ├── ContractLineItem.cs
│   │   ├── ContractVehicleAssignment.cs
│   │   ├── ContractAmendment.cs
│   │   └── ContractPenalty.cs
│   ├── Events/
│   │   ├── ContractCreatedEvent.cs
│   │   ├── ContractActivatedEvent.cs
│   │   ├── VehicleAssignmentActivatedEvent.cs
│   │   └── ContractCompletedEvent.cs
│   └── StateMachines/
│       ├── ContractStateMachine.cs
│       └── VehicleAssignmentStateMachine.cs
│
├── Application/
│   ├── Commands/
│   │   ├── CreateContractCommand.cs
│   │   ├── ActivateContractCommand.cs
│   │   └── TerminateContractCommand.cs
│   ├── Queries/
│   │   └── GetContractByIdQuery.cs
│   └── Services/
│       └── PartialFulfillmentService.cs
│
├── Infrastructure/
│   └── Repositories/
│
└── API/
    └── Controllers/
        └── ContractController.cs
```

**Database Schema:** `contracts`

**Key Events Published:**
- `ContractCreatedEvent`
- `ContractActivatedEvent`
- `VehicleAssignmentActivatedEvent`
- `VehicleReturnedEarlyEvent`
- `ContractCompletedEvent`

**Key Events Consumed:**
- `BidAwardedEvent` → Create contract
- `DeliveryConfirmedEvent` → Activate vehicle assignment
- `ReturnCompletedEvent` → Process early return

---

### 4. Finance Module

**Responsibility:** Wallets, escrow, settlement, commission, payments

**Bounded Context:**
```
Finance/
├── Domain/
│   ├── Entities/
│   │   ├── WalletAccount.cs
│   │   ├── WalletLedgerTransaction.cs
│   │   ├── WalletLedgerEntry.cs
│   │   ├── EscrowLock.cs
│   │   ├── SettlementCycle.cs
│   │   └── CommissionEntry.cs
│   ├── Events/
│   │   ├── WalletCreatedEvent.cs
│   │   ├── EscrowLockedEvent.cs
│   │   ├── EscrowReleasedEvent.cs
│   │   └── SettlementCompletedEvent.cs
│   └── Services/
│       ├── DoubleEntryLedger.cs
│       └── CommissionCalculator.cs
│
├── Application/
│   ├── Commands/
│   │   ├── DepositFundsCommand.cs
│   │   ├── LockEscrowCommand.cs
│   │   └── ProcessSettlementCommand.cs
│   ├── Queries/
│   │   └── GetWalletBalanceQuery.cs
│   └── Services/
│       └── PaymentGatewayService.cs
│
├── Infrastructure/
│   └── ExternalServices/
│       ├── ChapaPaymentService.cs
│       └── TelebirrPaymentService.cs
│
└── API/
    └── Controllers/
        ├── WalletController.cs
        └── SettlementController.cs
```

**Database Schema:** `wallet`

**Key Events Published:**
- `WalletCreatedEvent`
- `FundsDepositedEvent`
- `EscrowLockedEvent`
- `EscrowReleasedEvent`
- `SettlementCompletedEvent`

**Key Events Consumed:**
- `BusinessRegisteredEvent` → Create wallet
- `ProviderVerifiedEvent` → Create wallet
- `ContractCreatedEvent` → Lock escrow
- `ContractCompletedEvent` → Release escrow
- `VehicleReturnedEarlyEvent` → Calculate proration

---

### 5. Delivery Module

**Responsibility:** Vehicle handover, OTP verification, returns, evidence capture

**Bounded Context:**
```
Delivery/
├── Domain/
│   ├── Entities/
│   │   ├── DeliverySession.cs
│   │   ├── DeliveryOTP.cs
│   │   ├── DeliveryVehicleHandover.cs
│   │   └── DeliveryReturnSession.cs
│   ├── Events/
│   │   ├── OTPGeneratedEvent.cs
│   │   ├── OTPVerifiedEvent.cs
│   │   ├── DeliveryConfirmedEvent.cs
│   │   └── ReturnCompletedEvent.cs
│   └── Services/
│       └── OTPGenerator.cs
│
├── Application/
│   ├── Commands/
│   │   ├── GenerateOTPCommand.cs
│   │   ├── VerifyOTPCommand.cs
│   │   └── CompleteReturnCommand.cs
│   ├── Queries/
│   │   └── GetDeliverySessionQuery.cs
│   └── Validators/
│       └── OTPValidator.cs
│
├── Infrastructure/
│   └── Services/
│       └── SMSService.cs
│
└── API/
    └── Controllers/
        └── DeliveryController.cs
```

**Database Schema:** `delivery`

**Key Events Published:**
- `OTPGeneratedEvent`
- `OTPVerifiedEvent`
- `DeliveryConfirmedEvent`
- `ReturnCompletedEvent`

**Key Events Consumed:**
- `ContractCreatedEvent` → Create delivery session
- `VehicleAssignedEvent` → Prepare for delivery

---

## 🔄 Communication Patterns

### In-Process Events (MediatR)

**Pattern:** Publish-Subscribe within the same application process

**Example Flow: Contract Creation**

```csharp
// 1. Marketplace Module publishes event
public class AwardBidCommandHandler : IRequestHandler<AwardBidCommand>
{
    private readonly IMediator _mediator;
    
    public async Task<Unit> Handle(AwardBidCommand request)
    {
        // Award bid logic...
        
        await _mediator.Publish(new BidAwardedEvent
        {
            RFQId = request.RFQId,
            LineItemId = request.LineItemId,
            ProviderId = request.ProviderId,
            Quantity = request.Quantity,
            UnitPrice = request.UnitPrice
        });
        
        return Unit.Value;
    }
}

// 2. Contracts Module subscribes
public class BidAwardedEventHandler : INotificationHandler<BidAwardedEvent>
{
    private readonly IContractService _contractService;
    
    public async Task Handle(BidAwardedEvent notification)
    {
        // Create contract from awarded bid
        await _contractService.CreateContractFromAward(notification);
    }
}

// 3. Finance Module also subscribes
public class BidAwardedFinanceHandler : INotificationHandler<BidAwardedEvent>
{
    private readonly IEscrowService _escrowService;
    
    public async Task Handle(BidAwardedEvent notification)
    {
        // Prepare escrow lock
        await _escrowService.PrepareEscrowLock(notification);
    }
}
```

**Benefits:**
- ✅ Simple: No network overhead
- ✅ Fast: In-memory communication
- ✅ Transactional: Can participate in same DB transaction
- ✅ Debuggable: Single process, easy to trace

**Limitations:**
- ❌ Single point of failure (entire app)
- ❌ Vertical scaling only (within single server)
- ❌ No independent deployment

**Migration Path to RabbitMQ:**
```csharp
// Current (MediatR)
await _mediator.Publish(new BidAwardedEvent { ... });

// Future (RabbitMQ)
await _messageBus.Publish("marketplace.bid.awarded", new BidAwardedEvent { ... });
```

---

### Cross-Module Database Access

**Pattern:** Single DbContext with schema separation

```csharp
public class MarketplaceDbContext : DbContext
{
    // Identity Module
    public DbSet<Business> Businesses { get; set; }
    public DbSet<Provider> Providers { get; set; }
    public DbSet<Vehicle> Vehicles { get; set; }
    
    // Marketplace Module
    public DbSet<RFQ> RFQs { get; set; }
    public DbSet<RFQBid> RFQBids { get; set; }
    
    // Contracts Module
    public DbSet<Contract> Contracts { get; set; }
    public DbSet<ContractLineItem> ContractLineItems { get; set; }
    
    // Finance Module
    public DbSet<WalletAccount> WalletAccounts { get; set; }
    public DbSet<EscrowLock> EscrowLocks { get; set; }
    
    // Delivery Module
    public DbSet<DeliverySession> DeliverySessions { get; set; }
    
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Schema separation
        modelBuilder.Entity<Business>().ToTable("Businesses", "identity");
        modelBuilder.Entity<Provider>().ToTable("Providers", "identity");
        modelBuilder.Entity<Vehicle>().ToTable("Vehicles", "identity");
        
        modelBuilder.Entity<RFQ>().ToTable("RFQs", "marketplace");
        modelBuilder.Entity<RFQBid>().ToTable("RFQBids", "marketplace");
        
        modelBuilder.Entity<Contract>().ToTable("Contracts", "contracts");
        modelBuilder.Entity<ContractLineItem>().ToTable("ContractLineItems", "contracts");
        
        modelBuilder.Entity<WalletAccount>().ToTable("WalletAccounts", "wallet");
        modelBuilder.Entity<EscrowLock>().ToTable("EscrowLocks", "wallet");
        
        modelBuilder.Entity<DeliverySession>().ToTable("DeliverySessions", "delivery");
    }
}
```

**ACID Transactions Across Modules:**

```csharp
public class ContractCreationService
{
    private readonly MarketplaceDbContext _dbContext;
    private readonly IMediator _mediator;
    
    public async Task CreateContractWithEscrow(CreateContractCommand command)
    {
        using var transaction = await _dbContext.Database.BeginTransactionAsync();
        
        try
        {
            // 1. Contracts Module: Create contract
            var contract = new Contract
            {
                BusinessId = command.BusinessId,
                ProviderId = command.ProviderId,
                // ...
            };
            _dbContext.Contracts.Add(contract);
            
            // 2. Finance Module: Lock escrow (same transaction!)
            var escrowLock = new EscrowLock
            {
                ContractId = contract.Id,
                Amount = command.EscrowAmount,
                Status = EscrowStatus.Locked
            };
            _dbContext.EscrowLocks.Add(escrowLock);
            
            // 3. Save all changes atomically
            await _dbContext.SaveChangesAsync();
            
            // 4. Commit transaction
            await transaction.CommitAsync();
            
            // 5. Publish events (after commit)
            await _mediator.Publish(new ContractCreatedEvent { ContractId = contract.Id });
            await _mediator.Publish(new EscrowLockedEvent { EscrowLockId = escrowLock.Id });
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }
}
```

---

## 🗄️ Data Architecture

### Database: PostgreSQL 16

**Schema Organization:**

```sql
-- 1. Master Data Schema (22 tables)
masterdata
├── lookup_type
├── lookup
├── lookup_translation
├── settings
├── commission_strategy_version
├── commission_strategy_rule
├── escrow_policy_version
├── escrow_policy_rule
├── settlement_policy_version
├── settlement_policy_rule
├── provider_tier
├── provider_tier_rule
├── business_tier
├── contract_policy_version
├── contract_policy_rule
├── document_type
├── kyc_requirement
├── country
├── region
└── city

-- 2. Identity Schema (22 tables)
identity
├── user_account
├── user_device
├── user_login_session
├── user_mfa_challenge
├── business
├── business_profile
├── business_document
├── provider
├── provider_profile
├── provider_tier_assignment
├── provider_document
├── provider_trust_score_history
├── vehicle
├── vehicle_document
├── vehicle_insurance
├── verification_request
├── compliance_check_log
├── risk_event
└── account_flag

-- 3. Marketplace Schema (8 tables)
marketplace
├── rfq
├── rfq_line_item
├── rfq_bid
├── rfq_bid_snapshot
├── rfq_bid_award
├── rfq_line_item_fulfillment
├── rfq_award_vehicle_assignment
└── marketplace_event_log

-- 4. Contracts Schema (9 tables)
contracts
├── contract
├── contract_party_business
├── contract_party_provider
├── contract_line_item
├── contract_vehicle_assignment
├── contract_policy_snapshot
├── contract_amendment
├── contract_penalty
└── contract_event_log

-- 5. Wallet Schema (12 tables)
wallet
├── wallet_account
├── wallet_ledger_transaction
├── wallet_ledger_entry
├── wallet_balance_snapshot
├── escrow_lock
├── settlement_cycle
├── settlement_payout
├── commission_entry
├── payment_intent
├── refund_request
└── wallet_event_log

-- 6. Delivery Schema (7 tables)
delivery
├── delivery_session
├── delivery_otp
├── delivery_vehicle_handover
├── delivery_return_session
├── delivery_sla_violation
├── delivery_event_log
└── delivery_geofence_event (future)
```

**Total:** 80 tables across 6 schemas

---

### Entity Relationship Principles

**1. Foreign Keys Across Schemas:**

```sql
-- Allowed: Reference by ID
CREATE TABLE contracts.contract (
    id uuid PRIMARY KEY,
    business_id uuid NOT NULL,  -- References identity.business(id)
    provider_id uuid NOT NULL,  -- References identity.provider(id)
    rfq_id uuid NOT NULL        -- References marketplace.rfq(id)
);

-- Note: No FK constraints across schemas for flexibility
-- Referential integrity enforced at application level
```

**2. Immutable Snapshots:**

```sql
-- Contract stores party details at creation time
CREATE TABLE contracts.contract_party_business (
    id uuid PRIMARY KEY,
    contract_id uuid NOT NULL,
    business_id uuid NOT NULL,
    business_name varchar(256) NOT NULL,  -- Snapshot
    tin_number varchar(64),                -- Snapshot
    tier_code varchar(64),                 -- Snapshot at contract time
    snapshot_at timestamptz NOT NULL
);
```

**3. Event Sourcing for Audit:**

```sql
-- Every module has event_log table
CREATE TABLE contracts.contract_event_log (
    id uuid PRIMARY KEY,
    contract_id uuid NOT NULL,
    event_type varchar(64) NOT NULL,
    event_payload jsonb,
    actor_id uuid,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Example events
INSERT INTO contract_event_log (contract_id, event_type, event_payload)
VALUES (
    'contract-uuid',
    'CONTRACT_ACTIVATED',
    '{"activated_by": "user-uuid", "activation_date": "2025-11-26"}'::jsonb
);
```

---

## 🔐 Security Architecture

### Authentication Flow (BFF Pattern)

```
┌─────────────┐
│   Angular   │
│   Frontend  │
└──────┬──────┘
       │ 1. Login Request
       ▼
┌─────────────────────────────────────┐
│    BFF (YARP)                       │
│                                     │
│  2. Redirect to Keycloak            │
└──────┬──────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│    Keycloak                         │
│                                     │
│  3. User authenticates              │
│  4. Returns authorization code      │
└──────┬──────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│    BFF (YARP)                       │
│                                     │
│  5. Exchange code for tokens        │
│  6. Store refresh token (httpOnly)  │
│  7. Return access token to frontend │
└──────┬──────────────────────────────┘
       │
       ▼
┌─────────────┐
│   Angular   │
│  (stores    │
│ access token│
│  in memory) │
└──────┬──────┘
       │ 8. API Request + Bearer Token
       ▼
┌─────────────────────────────────────┐
│    BFF (YARP)                       │
│                                     │
│  9. Validate token                  │
│  10. Forward to backend             │
└──────┬──────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│    Marketplace.API                  │
│                                     │
│  11. Validate JWT signature         │
│  12. Extract claims (sub, roles)    │
│  13. Authorize based on roles       │
│  14. Process request                │
└─────────────────────────────────────┘
```

**Benefits of BFF:**
- ✅ Refresh tokens never exposed to frontend
- ✅ Centralized token management
- ✅ API aggregation (future: combine multiple backend calls)
- ✅ Rate limiting at gateway level
- ✅ CORS handling

---

### Authorization (RBAC)

**Roles:**

```csharp
public static class Roles
{
    // Business Roles
    public const string BusinessAdmin = "business-admin";
    public const string BusinessUser = "business-user";
    
    // Provider Roles
    public const string ProviderAdmin = "provider-admin";
    public const string ProviderDriver = "provider-driver";
    
    // Platform Roles
    public const string PlatformAdmin = "platform-admin";
    public const string ComplianceOfficer = "compliance-officer";
    public const string FinanceOfficer = "finance-officer";
}
```

**Authorization Policies:**

```csharp
services.AddAuthorization(options =>
{
    // Business can only access their own RFQs
    options.AddPolicy("BusinessOwner", policy =>
        policy.RequireRole(Roles.BusinessAdmin, Roles.BusinessUser)
              .RequireClaim("business_id"));
    
    // Provider can only access their own bids
    options.AddPolicy("ProviderOwner", policy =>
        policy.RequireRole(Roles.ProviderAdmin, Roles.ProviderDriver)
              .RequireClaim("provider_id"));
    
    // Admin can access everything
    options.AddPolicy("PlatformAdmin", policy =>
        policy.RequireRole(Roles.PlatformAdmin));
});
```

**Controller Usage:**

```csharp
[ApiController]
[Route("api/v1/rfqs")]
[Authorize]
public class RFQController : ControllerBase
{
    [HttpPost]
    [Authorize(Policy = "BusinessOwner")]
    public async Task<IActionResult> CreateRFQ([FromBody] CreateRFQCommand command)
    {
        // Only businesses can create RFQs
        var businessId = User.FindFirst("business_id")?.Value;
        command.BusinessId = Guid.Parse(businessId);
        
        var result = await _mediator.Send(command);
        return Ok(result);
    }
    
    [HttpGet("{id}")]
    public async Task<IActionResult> GetRFQ(Guid id)
    {
        // Anyone authenticated can view RFQs
        var query = new GetRFQByIdQuery { RFQId = id };
        var result = await _mediator.Send(query);
        return Ok(result);
    }
}
```

---

## 🚀 Deployment Architecture

### Development Environment (Docker Compose)

```yaml
version: '3.8'

services:
  # Frontend (Angular 19)
  frontend:
    build: ./frontend
    ports:
      - "4200:80"
    environment:
      - API_URL=http://bff:5001
    depends_on:
      - bff
  
  # BFF (YARP)
  bff:
    build: ./bff
    ports:
      - "5001:80"
    environment:
      - KEYCLOAK_URL=http://keycloak:8080
      - BACKEND_URL=http://api:5000
    depends_on:
      - keycloak
      - api
  
  # Backend API (.NET 9)
  api:
    build: ./backend
    ports:
      - "5000:80"
    environment:
      - ConnectionStrings__DefaultConnection=Host=postgres;Database=marketplace;Username=postgres;Password=postgres
      - Redis__ConnectionString=redis:6379
      - MinIO__Endpoint=minio:9000
    depends_on:
      - postgres
      - redis
      - minio
  
  # PostgreSQL 16
  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_DB=marketplace
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/migrations:/docker-entrypoint-initdb.d
  
  # Keycloak
  keycloak:
    image: quay.io/keycloak/keycloak:25.0
    ports:
      - "8080:8080"
    environment:
      - KEYCLOAK_ADMIN=admin
      - KEYCLOAK_ADMIN_PASSWORD=admin
      - KC_DB=postgres
      - KC_DB_URL=jdbc:postgresql://postgres:5432/keycloak
      - KC_DB_USERNAME=postgres
      - KC_DB_PASSWORD=postgres
    command: start-dev
    depends_on:
      - postgres
  
  # Redis
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
  
  # MinIO
  minio:
    image: minio/minio:latest
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      - MINIO_ROOT_USER=minioadmin
      - MINIO_ROOT_PASSWORD=minioadmin
    command: server /data --console-address ":9001"
    volumes:
      - minio_data:/data

volumes:
  postgres_data:
  redis_data:
  minio_data:
```

---

### Production Environment (Docker Compose on Single Server)

```yaml
version: '3.8'

services:
  # Nginx Reverse Proxy
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
      - ./frontend/dist:/usr/share/nginx/html
    depends_on:
      - bff
  
  # BFF (YARP)
  bff:
    image: movello/bff:latest
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - KEYCLOAK_URL=https://auth.movello.et
      - BACKEND_URL=http://api:5000
    restart: unless-stopped
  
  # Backend API
  api:
    image: movello/api:latest
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ConnectionStrings__DefaultConnection=${DB_CONNECTION_STRING}
      - Redis__ConnectionString=redis:6379
      - MinIO__Endpoint=minio:9000
    restart: unless-stopped
    deploy:
      replicas: 2  # Load balanced
  
  # PostgreSQL (Managed Service Recommended)
  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_DB=marketplace
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
  
  # Keycloak
  keycloak:
    image: quay.io/keycloak/keycloak:25.0
    environment:
      - KC_DB=postgres
      - KC_DB_URL=jdbc:postgresql://postgres:5432/keycloak
      - KC_HOSTNAME=auth.movello.et
      - KC_PROXY=edge
    command: start
    restart: unless-stopped
  
  # Redis
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    restart: unless-stopped
  
  # MinIO
  minio:
    image: minio/minio:latest
    environment:
      - MINIO_ROOT_USER=${MINIO_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_PASSWORD}
    command: server /data --console-address ":9001"
    volumes:
      - minio_data:/data
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
  minio_data:
```

---

## 📈 Scalability Strategy

### Horizontal Scaling (Future)

**Phase 1: Load Balancing (Current MVP)**
```
Nginx → API (2 replicas) → Single PostgreSQL
```

**Phase 2: Database Read Replicas**
```
Nginx → API (3+ replicas) → PostgreSQL Primary
                          → PostgreSQL Read Replica 1
                          → PostgreSQL Read Replica 2
```

**Phase 3: Module Extraction**
```
Nginx → BFF → Identity Service (Microservice)
           → Marketplace Service (Microservice)
           → Contracts Service (Microservice)
           → Finance Service (Microservice)
           → Delivery Service (Microservice)
```

**Phase 4: Event-Driven Microservices**
```
Services communicate via RabbitMQ/Kafka
Each service has its own database
API Gateway (Kong/Traefik) for routing
```

---

## ✅ Architecture Validation Checklist

- [x] **Modularity:** Clear module boundaries with single responsibility
- [x] **Scalability:** Horizontal scaling path defined
- [x] **Security:** OAuth2/OIDC with BFF pattern
- [x] **Data Integrity:** ACID transactions, double-entry ledger
- [x] **Auditability:** Event logs in every module
- [x] **Testability:** Dependency injection, interface-based design
- [x] **Observability:** Structured logging (Serilog), health checks
- [x] **Resilience:** Retry policies, circuit breakers (Polly)
- [x] **Performance:** Caching (Redis), async/await patterns
- [x] **Migration Path:** Clear microservices extraction strategy

---

**Next Document:** [02_DATABASE_SCHEMA_DESIGN.md](./02_DATABASE_SCHEMA_DESIGN.md)
