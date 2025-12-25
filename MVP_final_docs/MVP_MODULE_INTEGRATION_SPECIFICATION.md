# Movello MVP - Module Integration Specification
## Module Communication Patterns & Dependencies - Version 1.0

**Document Status:** AUTHORITATIVE  
**Date:** December 21, 2025  
**Related Documents:** 
- MVP_AUTHORITATIVE_BUSINESS_RULES.md
- MVP_EVENT_CATALOG_AND_HANDLERS.md  
**Review Status:** ✅ Approved by Business Owner

---

## Document Purpose

This document defines how modules communicate with each other in the Movello MVP platform, including:
- Module boundaries and responsibilities
- Read patterns (synchronous database queries)
- Write patterns (asynchronous events)
- Module dependency graph
- Shared data access rules
- Master data caching strategy
- API boundaries and contracts

---

## TABLE OF CONTENTS

1. [Module Architecture Overview](#1-module-architecture-overview)
2. [Communication Pattern Decision Matrix](#2-communication-pattern-decision-matrix)
3. [Module Dependency Graph](#3-module-dependency-graph)
4. [Read Patterns (Synchronous)](#4-read-patterns-synchronous)
5. [Write Patterns (Asynchronous)](#5-write-patterns-asynchronous)
6. [Master Data Module Integration](#6-master-data-module-integration)
7. [Identity Module Integration](#7-identity-module-integration)
8. [Module API Boundaries](#8-module-api-boundaries)
9. [Data Ownership & Responsibilities](#9-data-ownership--responsibilities)

---

## 1. MODULE ARCHITECTURE OVERVIEW

### 1.1 Module List

**Core Business Modules:**
1. **Marketplace** - RFQ, Bidding, Award management
2. **Contracts** - Contract lifecycle, vehicle assignment
3. **Finance** - Wallet, escrow, settlement, payments
4. **Delivery** - Delivery scheduling, OTP verification, returns
5. **Identity** - Users, businesses, providers, vehicles, trust score, KYC/KYB
6. **Disputes** - Dispute creation, evidence, resolution

**Support Modules:**
7. **MasterData** - Lookups, configurations, commission rates, contract policies
8. **Notifications** - Email, SMS, in-app notifications (pure consumer)

### 1.2 Module Database Schema

Each module owns its database schema (logical separation):

```
movello_db
├── marketplace_schema
│   ├── rfqs
│   ├── rfq_line_items
│   ├── bids
│   └── awards
├── contracts_schema
│   ├── contracts
│   ├── contract_vehicles
│   └── contract_alterations
├── finance_schema
│   ├── wallets
│   ├── transactions
│   ├── escrow_locks
│   └── settlements
├── delivery_schema
│   ├── deliveries
│   ├── otp_verifications
│   └── vehicle_returns
├── identity_schema
│   ├── users
│   ├── businesses
│   ├── providers
│   ├── vehicles
│   ├── insurance_records
│   └── trust_scores
├── disputes_schema
│   ├── disputes
│   ├── dispute_evidence
│   └── dispute_resolutions
├── masterdata_schema
│   ├── lookups
│   ├── lookup_types
│   ├── commission_strategies
│   ├── contract_policies
│   └── vehicle_types
└── notifications_schema
    ├── notification_queue
    └── notification_logs
```

### 1.3 Architecture Principles

**Principle 1: No Direct Writes Across Modules**
- ❌ Module A cannot INSERT/UPDATE/DELETE in Module B's database schema
- ✅ Module A publishes event → Module B subscribes and updates its own schema

**Principle 2: Read-Only Queries Allowed**
- ✅ Modules can SELECT from Identity and MasterData schemas (read-only)
- ✅ No foreign key constraints across module schemas
- ✅ Eventual consistency accepted for cross-module data

**Principle 3: Event-Driven State Changes**
- ✅ All CUD (Create, Update, Delete) operations trigger events
- ✅ Other modules subscribe to events for state synchronization
- ✅ MasterData is exception - no events (static config data)

---

## 2. COMMUNICATION PATTERN DECISION MATRIX

### 2.1 When to Use Each Pattern

| Use Case | Pattern | Example |
|----------|---------|---------|
| **Data Fetching** | Direct DB Read | Finance queries Identity for business name |
| **Validation Check** | Direct DB Read | Marketplace checks if provider is verified |
| **Lookup/Config** | Redis Cache + DB Read | Get commission rate from MasterData |
| **State Change** | Publish Event | Award bid → Publish BidAwardedEvent |
| **Cross-Module Notification** | Publish Event | Contract created → Notify Finance |
| **Multi-Step Workflow** | Saga Pattern | Award → Contract → Escrow → Delivery |

### 2.2 Decision Flowchart

```
┌─────────────────────────────┐
│ Need to communicate with    │
│ another module?             │
└────────────┬────────────────┘
             │
             ▼
    ┌────────────────┐
    │ Is it a read   │ YES  ┌──────────────────────────┐
    │ operation?     ├─────►│ Use Direct DB Query      │
    └────────┬───────┘      │ (SELECT from schema)     │
             │ NO            └──────────────────────────┘
             ▼
    ┌────────────────┐
    │ Is it MasterData│ YES  ┌──────────────────────────┐
    │ lookup?        ├─────►│ Use Redis Cache + DB     │
    └────────┬───────┘      │ (GET from cache)         │
             │ NO            └──────────────────────────┘
             ▼
    ┌────────────────┐
    │ Is it CUD      │ YES  ┌──────────────────────────┐
    │ operation?     ├─────►│ Publish Event            │
    └────────┬───────┘      │ (Event-driven)           │
             │ NO            └──────────────────────────┘
             ▼
    ┌────────────────┐
    │ Is it workflow │ YES  ┌──────────────────────────┐
    │ orchestration? ├─────►│ Use Saga Pattern         │
    └────────────────┘      │ (Event chain)            │
                            └──────────────────────────┘
```

---

## 3. MODULE DEPENDENCY GRAPH

### 3.1 Read Dependencies (Direct Database Queries)

**Who Can Query Whom (Read-Only):**

```
┌──────────────┐
│  MasterData  │◄──────────────┐
└──────┬───────┘               │
       │                       │
       │ READ                  │ READ
       │                       │
       ▼                       │
┌──────────────┐       ┌───────┴──────┐
│   Identity   │◄──────┤  Marketplace │
└──────┬───────┘       └───────┬──────┘
       │                       │
       │ READ                  │ READ
       │                       │
       ▼                       ▼
┌──────────────┐       ┌──────────────┐
│   Finance    │       │  Contracts   │
└──────────────┘       └──────────────┘
       │                       │
       │ READ                  │ READ
       │                       │
       └───────►┌──────────────┐◄──────┘
                │  Delivery    │
                └──────────────┘
```

**Read Dependency Table:**

| Module | Can Read From |
|--------|---------------|
| Marketplace | Identity, MasterData |
| Contracts | Identity, MasterData |
| Finance | Identity, MasterData |
| Delivery | Identity, MasterData, Contracts |
| Identity | MasterData |
| Disputes | Identity, MasterData, Contracts |
| Notifications | All modules (read-only for notification content) |

**Rules:**
- ✅ All modules can read from MasterData
- ✅ All modules can read from Identity (business, provider, vehicle data)
- ✅ No circular read dependencies
- ❌ Contracts CANNOT read from Marketplace (use events)
- ❌ Finance CANNOT read from Contracts (use events)

---

### 3.2 Write Dependencies (Event-Driven)

**Event Publishing Flow:**

```
Marketplace ──BidAwardedEvent──► Contracts
                                      │
                                      ├──ContractCreatedEvent──► Finance
                                      │
                                      └──ContractCreatedEvent──► Delivery

Finance ──EscrowLockedEvent──► Contracts
                                      │
                                      └──Update Status

Delivery ──DeliveryConfirmedEvent──► Contracts
                                           │
                                           ├──ContractActivatedEvent──► Finance
                                           │
                                           └──ContractActivatedEvent──► Identity

Contracts ──ContractCompletedEvent──► Finance (Settlement)
          │                           └─► Identity (Trust Score)
          │
          └──EarlyReturnApprovedEvent──► Finance (Settlement)
                                          └─► Identity (Trust Score)

Identity ──InsuranceExpiredEvent──► Marketplace (Suspend Vehicle)
                                    └─► Contracts (Notify Active Contracts)
```

**Event Publishing Table:**

| Publishing Module | Event | Subscribing Modules |
|------------------|-------|---------------------|
| Marketplace | BidAwardedEvent | Contracts, Finance, Identity |
| Contracts | ContractCreatedEvent | Finance, Delivery, Identity |
| Contracts | ContractActivatedEvent | Finance, Delivery, Identity |
| Contracts | ContractCompletedEvent | Finance, Identity |
| Finance | EscrowLockedEvent | Contracts, Identity |
| Finance | EscrowLockFailedEvent | Contracts, Marketplace |
| Delivery | DeliveryConfirmedEvent | Contracts, Identity |
| Identity | InsuranceExpiredEvent | Marketplace, Contracts |

---

## 4. READ PATTERNS (SYNCHRONOUS)

### 4.1 Direct Database Query Pattern

**Use Case:** Module needs data from Identity or MasterData for immediate use (validation, display, calculation)

**Implementation:**

```typescript
// Example: Finance module queries Identity for business name

// finance-service/src/services/wallet.service.ts
import { getIdentityDataSource } from '@shared/database';

class WalletService {
  async getBusinessWalletBalance(businessId: string): Promise<WalletBalanceDto> {
    // Query Finance schema for wallet
    const wallet = await this.walletRepository.findOne({ businessId });
    
    // Query Identity schema for business name (read-only)
    const identityDb = getIdentityDataSource();
    const business = await identityDb.query(
      'SELECT name, email FROM identity_schema.businesses WHERE id = $1',
      [businessId]
    );
    
    return {
      businessId,
      businessName: business[0].name,
      balance: wallet.balance,
      currency: wallet.currency
    };
  }
}
```

**Rules:**
- ✅ Use read-only database connection
- ✅ Use prepared statements to prevent SQL injection
- ✅ Handle case when data not found (eventual consistency)
- ❌ Never use transactions across schemas
- ❌ Never write to other module's schema

---

### 4.2 Identity Module Read Patterns

**Common Queries:**

#### Query 1: Get Business Details
```sql
-- Used by: Marketplace, Contracts, Finance, Delivery
SELECT 
  id,
  name,
  email,
  phone,
  status,
  verification_status,
  trust_score
FROM identity_schema.businesses
WHERE id = $1;
```

#### Query 2: Get Provider Details
```sql
-- Used by: Marketplace, Contracts, Finance, Delivery
SELECT 
  id,
  business_name,
  email,
  phone,
  status,
  verification_status,
  trust_score,
  tier
FROM identity_schema.providers
WHERE id = $1;
```

#### Query 3: Get Vehicle Details with Insurance
```sql
-- Used by: Marketplace, Contracts, Delivery
SELECT 
  v.id,
  v.provider_id,
  v.make,
  v.model,
  v.year,
  v.plate_number,
  v.vehicle_type,
  v.status,
  i.policy_number,
  i.expiry_date,
  i.insurance_provider
FROM identity_schema.vehicles v
LEFT JOIN identity_schema.insurance_records i ON v.id = i.vehicle_id
WHERE v.id = $1 AND i.is_active = true;
```

#### Query 4: Check Provider Verification Status
```sql
-- Used by: Marketplace (bid submission validation)
SELECT 
  status,
  verification_status,
  trust_score
FROM identity_schema.providers
WHERE id = $1;
```

#### Query 5: Get Available Vehicles for Provider
```sql
-- Used by: Marketplace (bid creation)
SELECT 
  v.id,
  v.make,
  v.model,
  v.vehicle_type,
  v.status
FROM identity_schema.vehicles v
INNER JOIN identity_schema.insurance_records i ON v.id = i.vehicle_id
WHERE v.provider_id = $1
  AND v.status = 'ACTIVE'
  AND i.is_active = true
  AND i.expiry_date >= CURRENT_DATE + INTERVAL '30 days';
```

---

### 4.3 MasterData Module Read Patterns

**Common Queries:**

#### Query 1: Get Commission Rate by Provider Tier
```sql
-- Used by: Finance (settlement calculation)
SELECT 
  commission_rate
FROM masterdata_schema.commission_strategies
WHERE provider_tier = $1 AND is_active = true;
```

#### Query 2: Get Vehicle Type Details
```sql
-- Used by: Marketplace, Contracts
SELECT 
  id,
  name,
  category,
  features
FROM masterdata_schema.vehicle_types
WHERE id = $1;
```

#### Query 3: Get Contract Policy by Type
```sql
-- Used by: Contracts (contract creation)
SELECT 
  early_return_penalty_type,
  early_return_penalty_value,
  notice_period_penalties
FROM masterdata_schema.contract_policies
WHERE contract_type = $1 AND is_active = true;
```

#### Query 4: Get Lookup Values
```sql
-- Used by: All modules (dropdowns, validations)
SELECT 
  code,
  display_name,
  sort_order
FROM masterdata_schema.lookups
WHERE lookup_type_id = $1 AND is_active = true
ORDER BY sort_order;
```

---

### 4.4 Query Performance Guidelines

**Best Practices:**

1. **Use Indexes:**
```sql
-- Identity schema indexes
CREATE INDEX idx_businesses_status ON identity_schema.businesses(status);
CREATE INDEX idx_providers_status ON identity_schema.providers(status);
CREATE INDEX idx_vehicles_provider_status ON identity_schema.vehicles(provider_id, status);
CREATE INDEX idx_insurance_expiry ON identity_schema.insurance_records(expiry_date);
```

2. **Use Query Result Caching (Short-lived):**
```typescript
// Cache business name for 5 minutes (rarely changes)
const cacheKey = `business:${businessId}:name`;
const cached = await redis.get(cacheKey);

if (cached) return cached;

const result = await queryIdentity(businessId);
await redis.setex(cacheKey, 300, result); // 5 min TTL
return result;
```

3. **Batch Queries When Possible:**
```typescript
// Instead of N queries in loop
const businessIds = contracts.map(c => c.businessId);
const businesses = await queryIdentity(`
  SELECT id, name FROM identity_schema.businesses
  WHERE id = ANY($1)
`, [businessIds]);
```

---

## 5. WRITE PATTERNS (ASYNCHRONOUS)

### 5.1 Event Publishing Pattern

**Use Case:** Module changes state and needs to notify other modules

**Implementation:**

```typescript
// Example: Marketplace publishes BidAwardedEvent

// marketplace-service/src/services/award.service.ts
import { EventPublisher } from '@shared/events';

class AwardService {
  constructor(
    private eventPublisher: EventPublisher,
    private bidRepository: BidRepository
  ) {}

  async awardBid(bidId: string, userId: string): Promise<void> {
    // 1. Update local state
    const bid = await this.bidRepository.findById(bidId);
    bid.status = 'AWARDED';
    await this.bidRepository.save(bid);

    // 2. Publish event
    await this.eventPublisher.publish({
      eventType: 'BidAwardedEvent',
      eventVersion: '1.0',
      aggregateId: bidId,
      aggregateType: 'Bid',
      payload: {
        bidId: bid.id,
        rfqId: bid.rfqId,
        lineItemId: bid.lineItemId,
        providerId: bid.providerId,
        businessId: bid.businessId,
        awardedQuantity: bid.quantity,
        totalAmount: bid.totalAmount,
        escrowAmount: bid.escrowAmount,
        rentalPeriod: bid.rentalPeriod,
        vehicleSpecs: bid.vehicleSpecs
      },
      metadata: {
        publisherId: 'marketplace-service',
        userId
      }
    });
  }
}
```

**Event Publishing Rules:**

1. ✅ **Update local state FIRST, then publish event**
2. ✅ **Include all necessary data in event payload** (avoid requiring subscribers to query back)
3. ✅ **Use database transaction + outbox pattern** for guaranteed delivery
4. ❌ **Never publish event before local state update** (can cause inconsistency)

---

### 5.2 Transactional Outbox Pattern

**Problem:** What if event publish fails after database commit?

**Solution:** Store events in database, then publish asynchronously

**Implementation:**

```typescript
// Outbox table in each module schema
CREATE TABLE marketplace_schema.event_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type VARCHAR(100) NOT NULL,
  event_version VARCHAR(10) NOT NULL,
  aggregate_id VARCHAR(100) NOT NULL,
  aggregate_type VARCHAR(50) NOT NULL,
  payload JSONB NOT NULL,
  metadata JSONB NOT NULL,
  published BOOLEAN DEFAULT false,
  published_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_outbox_published ON marketplace_schema.event_outbox(published, created_at);
```

```typescript
// Service implementation with outbox
class AwardService {
  async awardBid(bidId: string, userId: string): Promise<void> {
    await this.dataSource.transaction(async (txn) => {
      // 1. Update bid status
      await txn.query(
        'UPDATE marketplace_schema.bids SET status = $1 WHERE id = $2',
        ['AWARDED', bidId]
      );

      // 2. Insert event into outbox (same transaction)
      await txn.query(
        `INSERT INTO marketplace_schema.event_outbox 
         (event_type, event_version, aggregate_id, aggregate_type, payload, metadata)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        ['BidAwardedEvent', '1.0', bidId, 'Bid', eventPayload, metadata]
      );
    });
    // Transaction commits - both updates guaranteed atomic
  }
}

// Background worker publishes events from outbox
class EventOutboxPublisher {
  async publishPendingEvents(): Promise<void> {
    // Run every 5 seconds
    const events = await this.eventOutboxRepository.find({
      published: false,
      createdAt: LessThan(new Date(Date.now() - 1000)) // 1 sec delay
    });

    for (const event of events) {
      try {
        await this.eventPublisher.publish(event);
        
        // Mark as published
        await this.eventOutboxRepository.update(event.id, {
          published: true,
          publishedAt: new Date()
        });
      } catch (error) {
        // Retry next iteration
        logger.error(`Failed to publish event ${event.id}`, error);
      }
    }
  }
}
```

**Benefits:**
- ✅ Guaranteed event delivery (at-least-once)
- ✅ No lost events if message broker is down
- ✅ Audit trail of all events

---

### 5.3 Event Subscription Pattern

**Use Case:** Module subscribes to events from other modules

**Implementation:**

```typescript
// Example: Contracts subscribes to BidAwardedEvent

// contracts-service/src/handlers/bid-awarded.handler.ts
import { EventSubscriber, On } from '@shared/events';

@EventSubscriber()
export class BidAwardedEventHandler {
  constructor(
    private contractService: ContractService,
    private idempotencyService: IdempotencyService
  ) {}

  @On('BidAwardedEvent')
  async handle(event: BidAwardedEvent): Promise<void> {
    // Check idempotency
    if (await this.idempotencyService.isProcessed(event.eventId)) {
      logger.info(`Event ${event.eventId} already processed. Skipping.`);
      return;
    }

    try {
      // Create contract
      const contract = await this.contractService.createFromBid(event.payload);

      // Store idempotency key
      await this.idempotencyService.markProcessed(event.eventId, contract.id);

      logger.info(`Contract ${contract.id} created from bid ${event.payload.bidId}`);
    } catch (error) {
      logger.error(`Failed to handle BidAwardedEvent ${event.eventId}`, error);
      throw error; // Will trigger retry
    }
  }
}
```

**Idempotency Implementation:**

```sql
-- Idempotency table in each module schema
CREATE TABLE contracts_schema.event_idempotency (
  event_id UUID PRIMARY KEY,
  event_type VARCHAR(100) NOT NULL,
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  result_id VARCHAR(100) -- ID of created entity (e.g., contract ID)
);

CREATE INDEX idx_event_idempotency_type ON contracts_schema.event_idempotency(event_type);
```

---

## 6. MASTER DATA MODULE INTEGRATION

### 6.1 Master Data Caching Strategy

**Cache All MasterData in Redis (MVP):**

```typescript
// masterdata-service/src/cache/cache-loader.service.ts

class MasterDataCacheLoader {
  async loadAllToCache(): Promise<void> {
    // Load commission rates
    const commissionRates = await this.commissionRepository.findAll();
    for (const rate of commissionRates) {
      await redis.set(
        `masterdata:commission:${rate.providerTier}`,
        JSON.stringify(rate),
        'EX',
        86400 // 24 hour TTL
      );
    }

    // Load vehicle types
    const vehicleTypes = await this.vehicleTypeRepository.findAll();
    await redis.set(
      'masterdata:vehicle-types',
      JSON.stringify(vehicleTypes),
      'EX',
      86400
    );

    // Load contract policies
    const contractPolicies = await this.contractPolicyRepository.findAll();
    for (const policy of contractPolicies) {
      await redis.set(
        `masterdata:contract-policy:${policy.contractType}`,
        JSON.stringify(policy),
        'EX',
        86400
      );
    }

    // Load lookups by type
    const lookupTypes = await this.lookupTypeRepository.findAll();
    for (const type of lookupTypes) {
      const lookups = await this.lookupRepository.find({ typeId: type.id });
      await redis.set(
        `masterdata:lookups:${type.code}`,
        JSON.stringify(lookups),
        'EX',
        86400
      );
    }

    logger.info('Master data loaded to cache');
  }

  // Run on startup and every 6 hours
  async scheduleRefresh(): Promise<void> {
    await this.loadAllToCache();
    setInterval(() => this.loadAllToCache(), 6 * 60 * 60 * 1000);
  }
}
```

### 6.2 Accessing Master Data from Other Modules

**Pattern 1: Cache-Aside with Fallback**

```typescript
// finance-service/src/services/master-data.service.ts

class MasterDataService {
  async getCommissionRate(providerTier: string): Promise<number> {
    // Try cache first
    const cacheKey = `masterdata:commission:${providerTier}`;
    const cached = await redis.get(cacheKey);
    
    if (cached) {
      const data = JSON.parse(cached);
      return data.commissionRate;
    }

    // Cache miss - query database
    const result = await this.dataSource.query(
      `SELECT commission_rate 
       FROM masterdata_schema.commission_strategies 
       WHERE provider_tier = $1 AND is_active = true`,
      [providerTier]
    );

    if (result.length === 0) {
      throw new Error(`Commission rate not found for tier: ${providerTier}`);
    }

    // Update cache
    await redis.set(cacheKey, JSON.stringify(result[0]), 'EX', 86400);

    return result[0].commission_rate;
  }

  async getVehicleTypes(): Promise<VehicleType[]> {
    const cacheKey = 'masterdata:vehicle-types';
    const cached = await redis.get(cacheKey);
    
    if (cached) return JSON.parse(cached);

    // Cache miss
    const result = await this.dataSource.query(
      'SELECT * FROM masterdata_schema.vehicle_types WHERE is_active = true'
    );

    await redis.set(cacheKey, JSON.stringify(result), 'EX', 86400);
    return result;
  }
}
```

### 6.3 Cache Invalidation on MasterData Update

**Admin updates MasterData → Invalidate cache:**

```typescript
// masterdata-service/src/services/commission.service.ts

class CommissionStrategyService {
  async updateCommissionRate(
    providerTier: string, 
    newRate: number
  ): Promise<void> {
    // 1. Update database
    await this.commissionRepository.update(
      { providerTier },
      { commissionRate: newRate }
    );

    // 2. Invalidate cache
    const cacheKey = `masterdata:commission:${providerTier}`;
    await redis.del(cacheKey);

    // 3. Reload to cache
    const updated = await this.commissionRepository.findOne({ providerTier });
    await redis.set(cacheKey, JSON.stringify(updated), 'EX', 86400);

    logger.info(`Commission rate updated for ${providerTier}: ${newRate}`);
  }
}
```

**Why MasterData doesn't publish events:**
- ❌ Changes are infrequent (admin-driven configuration)
- ❌ No need for real-time synchronization
- ✅ Cache invalidation + TTL is sufficient
- ✅ Other modules always query latest via cache-aside pattern

---

## 7. IDENTITY MODULE INTEGRATION

### 7.1 Identity as Shared Data Source

**Identity module is the single source of truth for:**
- Businesses (KYB data, status, trust score)
- Providers (KYC data, status, trust score, tier)
- Vehicles (ownership, insurance, status)
- Users (authentication, roles, permissions)

**All modules can READ from Identity, but only Identity can WRITE to Identity schema.**

---

### 7.2 Trust Score Updates via Events

**Identity module subscribes to events to update trust score:**

```typescript
// identity-service/src/handlers/trust-score-update.handler.ts

@EventSubscriber()
export class TrustScoreUpdateHandler {
  @On('ContractCompletedEvent')
  async handleContractCompleted(event: ContractCompletedEvent): Promise<void> {
    const { providerId, performanceMetrics } = event.payload;

    // Recalculate trust score
    const newScore = await this.trustScoreService.recalculate(providerId, {
      contractCompleted: true,
      onTime: performanceMetrics.onTimeDelivery,
      noShowCount: performanceMetrics.noShowCount
    });

    // Publish TrustScoreUpdatedEvent
    await this.eventPublisher.publish({
      eventType: 'TrustScoreUpdatedEvent',
      aggregateId: providerId,
      payload: {
        providerId,
        previousScore: event.payload.previousTrustScore,
        newScore,
        recalculationTrigger: 'CONTRACT_COMPLETED'
      }
    });
  }

  @On('DeliveryConfirmedEvent')
  async handleDeliveryConfirmed(event: DeliveryConfirmedEvent): Promise<void> {
    const { providerId } = event.payload;

    // Update on-time delivery count
    await this.trustScoreService.incrementOnTimeDelivery(providerId);
  }

  @On('ProviderRejectedAwardEvent')
  async handleProviderRejection(event: ProviderRejectedAwardEvent): Promise<void> {
    const { providerId, isFirstTimeRejection } = event.payload;

    if (!isFirstTimeRejection) {
      // Apply penalty
      await this.trustScoreService.applyRejectionPenalty(providerId);
    }
  }
}
```

---

### 7.3 Insurance Expiry Monitoring

**Identity module runs scheduled job to check insurance expiry:**

```typescript
// identity-service/src/jobs/insurance-monitor.job.ts

@Cron('0 0 * * *') // Daily at midnight
export class InsuranceMonitorJob {
  async checkExpiringInsurance(): Promise<void> {
    // Find insurance expiring in 30 days
    const expiring30Days = await this.insuranceRepository.find({
      expiryDate: Between(
        new Date(),
        new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
      ),
      isActive: true
    });

    for (const insurance of expiring30Days) {
      await this.eventPublisher.publish({
        eventType: 'InsuranceExpiringEvent',
        aggregateId: insurance.vehicleId,
        payload: {
          vehicleId: insurance.vehicleId,
          providerId: insurance.providerId,
          expiryDate: insurance.expiryDate,
          daysUntilExpiry: calculateDays(insurance.expiryDate),
          urgencyLevel: 'WARNING'
        }
      });
    }

    // Find insurance expiring in 7 days
    const expiring7Days = await this.insuranceRepository.find({
      expiryDate: Between(
        new Date(),
        new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
      ),
      isActive: true
    });

    for (const insurance of expiring7Days) {
      await this.eventPublisher.publish({
        eventType: 'InsuranceExpiringEvent',
        aggregateId: insurance.vehicleId,
        payload: {
          vehicleId: insurance.vehicleId,
          providerId: insurance.providerId,
          expiryDate: insurance.expiryDate,
          daysUntilExpiry: calculateDays(insurance.expiryDate),
          urgencyLevel: 'URGENT'
        }
      });
    }

    // Find expired insurance
    const expired = await this.insuranceRepository.find({
      expiryDate: LessThan(new Date()),
      isActive: true
    });

    for (const insurance of expired) {
      // Suspend vehicle
      await this.vehicleRepository.update(insurance.vehicleId, {
        status: 'SUSPENDED'
      });

      // Publish event
      await this.eventPublisher.publish({
        eventType: 'InsuranceExpiredEvent',
        aggregateId: insurance.vehicleId,
        payload: {
          vehicleId: insurance.vehicleId,
          providerId: insurance.providerId,
          expiryDate: insurance.expiryDate,
          urgencyLevel: 'CRITICAL'
        }
      });
    }
  }
}
```

---

## 8. MODULE API BOUNDARIES

### 8.1 Internal API vs Events

**Each module exposes:**
1. **REST API** - For external clients (frontend, mobile apps)
2. **Internal Service Interface** - For read-only queries from other modules (optional)
3. **Event Handlers** - For subscribing to events

**API Gateway routes requests to appropriate module:**

```
┌──────────────┐
│  API Gateway │
└───────┬──────┘
        │
        ├─── POST /rfqs ──────────► Marketplace Service
        ├─── POST /bids ──────────► Marketplace Service
        ├─── GET /contracts ──────► Contracts Service
        ├─── GET /wallet ─────────► Finance Service
        └─── GET /profile ────────► Identity Service
```

### 8.2 Module API Contracts

**Marketplace Module API:**
```
# RFQ Management
POST   /api/v1/marketplace/rfqs                      # Create new RFQ
GET    /api/v1/marketplace/rfqs                      # List all RFQs (with filters)
GET    /api/v1/marketplace/rfqs/:id                  # Get RFQ details
PATCH  /api/v1/marketplace/rfqs/:id                  # Update RFQ (before publish)
DELETE /api/v1/marketplace/rfqs/:id                  # Delete RFQ (draft only)
POST   /api/v1/marketplace/rfqs/:id/publish          # Publish RFQ
POST   /api/v1/marketplace/rfqs/:id/cancel           # Cancel RFQ

# Bidding
POST   /api/v1/marketplace/bids                      # Submit bid
GET    /api/v1/marketplace/bids                      # List bids (filtered by RFQ/provider)
GET    /api/v1/marketplace/bids/:id                  # Get bid details
PATCH  /api/v1/marketplace/bids/:id                  # Update bid (before award)
DELETE /api/v1/marketplace/bids/:id                  # Withdraw bid

# Awards
POST   /api/v1/marketplace/awards                    # Award bid(s)
GET    /api/v1/marketplace/awards                    # List awards
GET    /api/v1/marketplace/awards/:id                # Get award details
```

**Contracts Module API:**
```
# Contract Management
GET    /api/v1/contracts                             # List contracts (filtered by business/provider)
GET    /api/v1/contracts/:id                         # Get contract details
PATCH  /api/v1/contracts/:id                         # Update contract (allowed modifications)
POST   /api/v1/contracts/:id/accept                  # Provider accepts contract
POST   /api/v1/contracts/:id/approve                 # Business approves contract alteration

# Vehicle Assignment
POST   /api/v1/contracts/:id/assign-vehicle          # Assign vehicle to contract
DELETE /api/v1/contracts/:id/vehicles/:vehicleId     # Unassign vehicle

# Contract Actions
POST   /api/v1/contracts/:id/early-return            # Request early return
POST   /api/v1/contracts/:id/terminate               # Terminate contract
POST   /api/v1/contracts/:id/alter                   # Request contract alteration

# Contract Reports
GET    /api/v1/contracts/:id/history                 # Get contract history/audit trail
GET    /api/v1/contracts/:id/documents               # Get contract documents
```

**Finance Module API:**
```
# Wallet Management
GET    /api/v1/finance/wallet                        # Get user wallet balance
POST   /api/v1/finance/wallet/deposit                # Deposit funds
POST   /api/v1/finance/wallet/withdraw               # Withdraw funds (provider)
GET    /api/v1/finance/wallet/balance                # Get current balance

# Transactions
GET    /api/v1/finance/transactions                  # List transactions (filtered)
GET    /api/v1/finance/transactions/:id              # Get transaction details

# Escrow Management
GET    /api/v1/finance/escrow                        # Get all escrow locks for user
GET    /api/v1/finance/escrow/contract/:contractId   # Get escrow for specific contract
GET    /api/v1/finance/escrow/summary                # Get escrow summary for user

# Admin Escrow Endpoints
GET    /api/v1/finance/admin/escrow                  # Get all escrow locks (Admin)
GET    /api/v1/finance/admin/escrow/business/:id     # Get escrow for all contracts of business
GET    /api/v1/finance/admin/escrow/provider/:id     # Get escrow for all contracts of provider
GET    /api/v1/finance/admin/escrow/contracts        # Get escrow for all contracts

# Settlements
GET    /api/v1/finance/settlements                   # List settlements (filtered by provider)
GET    /api/v1/finance/settlements/:id               # Get settlement details
POST   /api/v1/finance/settlements/:id/approve       # Approve settlement (manual review)
POST   /api/v1/finance/settlements/:id/reject        # Reject settlement

# Refunds
POST   /api/v1/finance/refunds                       # Process refund
GET    /api/v1/finance/refunds                       # List refunds
GET    /api/v1/finance/refunds/:id                   # Get refund details
```

**Delivery Module API:**
```
# OTP Management
POST   /api/v1/delivery/otp/generate                 # Generate OTP for delivery
POST   /api/v1/delivery/otp/verify                   # Verify OTP
POST   /api/v1/delivery/otp/resend                   # Resend OTP

# Delivery Management
GET    /api/v1/delivery/deliveries                   # List deliveries (filtered)
GET    /api/v1/delivery/deliveries/:id               # Get delivery details
GET    /api/v1/delivery/deliveries/contract/:id      # Get deliveries for contract
GET    /api/v1/delivery/deliveries/vehicle/:id       # Get deliveries for vehicle
POST   /api/v1/delivery/deliveries/:id/schedule      # Schedule delivery
POST   /api/v1/delivery/deliveries/:id/reject        # Reject delivery

# Vehicle Returns
POST   /api/v1/delivery/returns                      # Initiate vehicle return
GET    /api/v1/delivery/returns/:id                  # Get return details
POST   /api/v1/delivery/returns/:id/confirm          # Confirm vehicle return
```

**Identity Module API:**
```
# Profile Management
GET    /api/v1/identity/profile                      # Get user profile
PUT    /api/v1/identity/profile                      # Update user profile
PATCH  /api/v1/identity/profile                      # Partial update profile

# Business Details
GET    /api/v1/identity/businesses/:id               # Get business basic info
GET    /api/v1/identity/businesses/:id/details       # Get complete business details
                                                      # (info, trust score, verification, profile completeness)
PUT    /api/v1/identity/businesses/:id               # Update business info

# Provider Details
GET    /api/v1/identity/providers/:id                # Get provider basic info
GET    /api/v1/identity/providers/:id/details        # Get complete provider details
                                                      # (info, trust score, verification, vehicles count, profile completeness)
PUT    /api/v1/identity/providers/:id                # Update provider info

# Vehicle Management
POST   /api/v1/identity/vehicles                     # Add new vehicle
GET    /api/v1/identity/vehicles                     # List vehicles (filtered by provider)
GET    /api/v1/identity/vehicles/:id                 # Get vehicle basic info
GET    /api/v1/identity/vehicles/:id/details         # Get complete vehicle details
                                                      # (vehicle info, provider, insurance, recent contracts, status)
PUT    /api/v1/identity/vehicles/:id                 # Update vehicle info
PATCH  /api/v1/identity/vehicles/:id                 # Partial update vehicle
DELETE /api/v1/identity/vehicles/:id                 # Remove vehicle

# Insurance Management
POST   /api/v1/identity/vehicles/:id/insurance       # Add insurance for vehicle
PUT    /api/v1/identity/vehicles/:id/insurance/:insuranceId  # Update insurance
DELETE /api/v1/identity/vehicles/:id/insurance/:insuranceId  # Remove insurance
GET    /api/v1/identity/vehicles/:id/insurance       # Get all insurance records for vehicle

# Trust Score
GET    /api/v1/identity/trust-score                  # Get user trust score
GET    /api/v1/identity/trust-score/history          # Get trust score history

# Verification
POST   /api/v1/identity/verification/submit          # Submit documents for verification
GET    /api/v1/identity/verification/status          # Get verification status
```

**Disputes Module API:**
```
# Dispute Management
POST   /api/v1/disputes                              # Create new dispute
GET    /api/v1/disputes                              # List disputes (filtered)
GET    /api/v1/disputes/:id                          # Get dispute details
PATCH  /api/v1/disputes/:id                          # Update dispute

# Evidence
POST   /api/v1/disputes/:id/evidence                 # Submit evidence
GET    /api/v1/disputes/:id/evidence                 # List evidence
DELETE /api/v1/disputes/:id/evidence/:evidenceId     # Remove evidence

# Resolution
POST   /api/v1/disputes/:id/resolve                  # Resolve dispute (support team)
POST   /api/v1/disputes/:id/escalate                 # Escalate dispute
POST   /api/v1/disputes/:id/comment                  # Add comment to dispute
```

**MasterData Module API:**
```
# Lookups
GET    /api/v1/masterdata/lookups                    # Get all lookups (filtered by type)
GET    /api/v1/masterdata/lookups/types              # Get all lookup types
GET    /api/v1/masterdata/lookups/type/:code         # Get lookups by type code
POST   /api/v1/masterdata/lookups                    # Create new lookup (Admin)
PUT    /api/v1/masterdata/lookups/:id                # Update lookup (Admin)
DELETE /api/v1/masterdata/lookups/:id                # Delete lookup (Admin)

# Commission Strategies
GET    /api/v1/masterdata/commission-strategies      # List all commission strategies
GET    /api/v1/masterdata/commission-strategies/:id  # Get commission strategy details
POST   /api/v1/masterdata/commission-strategies      # Create commission strategy (Admin)
PUT    /api/v1/masterdata/commission-strategies/:id  # Update commission strategy (Admin)
DELETE /api/v1/masterdata/commission-strategies/:id  # Delete commission strategy (Admin)

# Vehicle Types
GET    /api/v1/masterdata/vehicle-types              # List all vehicle types
GET    /api/v1/masterdata/vehicle-types/:id          # Get vehicle type details
POST   /api/v1/masterdata/vehicle-types              # Create vehicle type (Admin)
PUT    /api/v1/masterdata/vehicle-types/:id          # Update vehicle type (Admin)
DELETE /api/v1/masterdata/vehicle-types/:id          # Delete vehicle type (Admin)

# Contract Policies
GET    /api/v1/masterdata/contract-policies          # List all contract policies
GET    /api/v1/masterdata/contract-policies/:id      # Get contract policy details
POST   /api/v1/masterdata/contract-policies          # Create contract policy (Admin)
PUT    /api/v1/masterdata/contract-policies/:id      # Update contract policy (Admin)
DELETE /api/v1/masterdata/contract-policies/:id      # Delete contract policy (Admin)

# Payment Configurations
GET    /api/v1/masterdata/payment-config             # Get payment configurations
PUT    /api/v1/masterdata/payment-config             # Update payment configuration (Admin)

# System Settings
GET    /api/v1/masterdata/settings                   # Get all system settings
GET    /api/v1/masterdata/settings/:key              # Get specific setting
PUT    /api/v1/masterdata/settings/:key              # Update setting (Admin)

# Cache Management
POST   /api/v1/masterdata/cache/refresh              # Refresh cache (Admin)
DELETE /api/v1/masterdata/cache/clear                # Clear cache (Admin)
```

---

## 9. DATA OWNERSHIP & RESPONSIBILITIES

### 9.1 Module Ownership Table

| Module | Owns Data | Responsibilities |
|--------|-----------|------------------|
| **Marketplace** | RFQs, Bids, Awards | RFQ lifecycle, bidding process, award validation |
| **Contracts** | Contracts, Vehicle assignments | Contract lifecycle, activation logic, early returns |
| **Finance** | Wallets, Transactions, Escrow, Settlements | Payment processing, escrow management, settlements |
| **Delivery** | Deliveries, OTP verifications | Delivery scheduling, OTP generation/verification |
| **Identity** | Users, Businesses, Providers, Vehicles, Trust Scores | KYC/KYB, vehicle verification, trust score calculation |
| **Disputes** | Disputes, Evidence, Resolutions | Dispute creation, evidence collection, resolution |
| **MasterData** | Lookups, Commission rates, Policies | Configuration management, lookup data |
| **Notifications** | Notification queue, logs | Email/SMS/in-app notification delivery |

### 9.2 Data Synchronization Examples

**Example 1: Provider Name Change**

```
User updates profile in Identity module
         ↓
Identity updates providers table
         ↓
Identity publishes ProviderProfileUpdatedEvent (optional, if needed)
         ↓
Other modules query Identity for latest name when needed
```

**No synchronization needed** - other modules always query Identity directly for latest data.

---

**Example 2: Contract Completion Updates Trust Score**

```
Contract completes
         ↓
Contracts publishes ContractCompletedEvent
         ↓
Identity subscribes and recalculates trust score
         ↓
Identity publishes TrustScoreUpdatedEvent
         ↓
Marketplace displays updated score on next query
```

---

### 9.3 Data Consistency Model

**Consistency Types:**

1. **Strong Consistency (within module):**
   - All writes within same module are immediately consistent
   - Use database transactions for multi-table updates

2. **Eventual Consistency (cross-module):**
   - Data synchronized via events
   - Slight delay acceptable (seconds to minutes)
   - Example: Trust score update after contract completion

3. **Read-Your-Writes (user experience):**
   - User sees their own changes immediately
   - Other users may see changes after event processing

**Handling Eventual Consistency:**

```typescript
// Example: Display contract with latest business name

async getContractDetails(contractId: string): Promise<ContractDto> {
  // Get contract (local data - strongly consistent)
  const contract = await this.contractRepository.findById(contractId);

  // Query Identity for business name (may be slightly stale, but acceptable)
  const business = await this.queryIdentity(contract.businessId);

  return {
    ...contract,
    businessName: business.name,
    businessEmail: business.email
  };
}
```

---

## APPENDIX A: Communication Pattern Examples

### A.1 Example: Finance Processes Settlement

**Scenario:** Contract completed, Finance needs to process settlement

**Steps:**

1. **Contracts module publishes event:**
```typescript
await eventPublisher.publish({
  eventType: 'ContractCompletedEvent',
  aggregateId: contractId,
  payload: {
    contractId,
    providerId,
    businessId,
    totalAmount: 150000,
    settlementData: {
      grossAmount: 150000,
      providerTier: 'SILVER'
    }
  }
});
```

2. **Finance module receives event:**
```typescript
@On('ContractCompletedEvent')
async handleContractCompleted(event) {
  // Query MasterData for commission rate (read from cache)
  const commissionRate = await this.masterDataService.getCommissionRate(
    event.payload.settlementData.providerTier
  );

  // Query Identity for provider payment details (read from DB)
  const provider = await this.queryIdentity(event.payload.providerId);

  // Calculate settlement
  const settlement = calculateSettlement(
    event.payload.totalAmount,
    commissionRate,
    TAX_RATE
  );

  // Process payment
  await this.processSettlement(settlement, provider.paymentDetails);
}
```

**Data Access:**
- ✅ Event payload (push)
- ✅ MasterData query (pull, cached)
- ✅ Identity query (pull, direct DB)

---

### A.2 Example: Marketplace Validates Bid Submission

**Scenario:** Provider submits bid, Marketplace validates

**Steps:**

1. **Provider submits bid via API:**
```http
POST /api/v1/marketplace/bids
{
  "rfqId": "rfq-123",
  "lineItemId": "line-001",
  "quantity": 3,
  "pricePerVehicle": 5000
}
```

2. **Marketplace validates (synchronous reads):**
```typescript
async validateBidSubmission(providerId: string, rfqId: string): Promise<void> {
  // Query Identity for provider status
  const provider = await this.queryIdentity(`
    SELECT status, verification_status, trust_score
    FROM identity_schema.providers
    WHERE id = $1
  `, [providerId]);

  if (provider.status !== 'ACTIVE') {
    throw new Error('Provider account is not active');
  }

  if (provider.verification_status !== 'VERIFIED') {
    throw new Error('Provider is not verified');
  }

  // Query Identity for available vehicles
  const vehicles = await this.queryIdentity(`
    SELECT COUNT(*) as count
    FROM identity_schema.vehicles v
    INNER JOIN identity_schema.insurance_records i ON v.id = i.vehicle_id
    WHERE v.provider_id = $1
      AND v.status = 'ACTIVE'
      AND i.is_active = true
      AND i.expiry_date >= CURRENT_DATE + INTERVAL '30 days'
  `, [providerId]);

  if (vehicles[0].count === 0) {
    throw new Error('No available vehicles with valid insurance');
  }

  // Validation passed
}
```

3. **Marketplace creates bid (write to local DB):**
```typescript
const bid = await this.bidRepository.create({
  rfqId,
  providerId,
  quantity,
  pricePerVehicle,
  status: 'BIDDING'
});
```

4. **Marketplace publishes event:**
```typescript
await this.eventPublisher.publish({
  eventType: 'BidSubmittedEvent',
  aggregateId: bid.id,
  payload: { ...bid }
});
```

**Data Access:**
- ✅ Identity queries (pull, direct DB, read-only)
- ✅ Local write (bid created in Marketplace schema)
- ✅ Event publish (push to subscribers)

---

## APPENDIX B: Module Integration Checklist

**For each new module feature, verify:**

- [ ] **Read Dependencies**
  - [ ] Identified all data needed from other modules
  - [ ] Using direct DB queries for Identity/MasterData reads
  - [ ] Using Redis cache for MasterData lookups
  - [ ] Handling eventual consistency gracefully

- [ ] **Write Dependencies**
  - [ ] Publishing events for all state changes
  - [ ] Including all necessary data in event payload
  - [ ] Using transactional outbox pattern
  - [ ] No direct writes to other module schemas

- [ ] **Event Handlers**
  - [ ] Implemented idempotency checks
  - [ ] Handling errors with retry logic
  - [ ] No blocking operations in event handlers
  - [ ] Proper logging and monitoring

- [ ] **API Boundaries**
  - [ ] Exposing only necessary APIs
  - [ ] Following REST conventions
  - [ ] API documentation updated
  - [ ] Authentication/authorization implemented

---

**END OF MODULE INTEGRATION SPECIFICATION**

---

**For Implementation:** Use this document as reference for:
1. Deciding when to use events vs queries
2. Implementing cross-module data access
3. Setting up event handlers
4. Configuring MasterData caching
5. Understanding module boundaries

**For Architecture Reviews:** Verify:
1. No circular write dependencies
2. Events used for state changes
3. Queries used for data fetching
4. Idempotency implemented
5. Proper error handling
