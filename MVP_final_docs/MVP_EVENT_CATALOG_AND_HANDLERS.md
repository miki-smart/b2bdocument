# Movello MVP - Event Catalog and Handler Specifications
## Event-Driven Architecture Reference - Version 1.0

**Document Status:** AUTHORITATIVE  
**Date:** December 21, 2025  
**Related Documents:** MVP_AUTHORITATIVE_BUSINESS_RULES.md  
**Review Status:** ✅ Approved by Business Owner

---

## Document Purpose

This document defines ALL events in the Movello MVP platform, including:
- Event schemas and payloads
- Publishing modules
- Subscribing modules and handlers
- Retry policies and error handling
- Idempotency requirements
- Event ordering and dependencies

---

## TABLE OF CONTENTS

1. [Event Architecture Principles](#1-event-architecture-principles)
2. [Event Processing Guarantees](#2-event-processing-guarantees)
3. [Event Catalog by Module](#3-event-catalog-by-module)
4. [Event Schemas](#4-event-schemas)
5. [Event Handler Specifications](#5-event-handler-specifications)
6. [Retry Policies](#6-retry-policies)
7. [Error Handling & Dead Letter Queue](#7-error-handling--dead-letter-queue)
8. [Event Ordering & Saga Patterns](#8-event-ordering--saga-patterns)

---

## 1. EVENT ARCHITECTURE PRINCIPLES

### 1.1 When to Use Events

**Use Events For:**
- ✅ State changes (Create, Update, Delete operations)
- ✅ Cross-module notifications
- ✅ Triggering workflows in other modules
- ✅ Audit trail and event sourcing

**Do NOT Use Events For:**
- ❌ Data fetching (use direct database reads)
- ❌ Validation checks (use synchronous queries)
- ❌ Master data lookups (use direct reads or cache)

### 1.2 Event Naming Convention

**Pattern:** `{Entity}{Action}Event`

**Examples:**
- `BidAwardedEvent` (Bid was awarded)
- `ContractCreatedEvent` (Contract was created)
- `EscrowLockedEvent` (Escrow was locked)

### 1.3 Event Structure

**All events MUST include:**
```json
{
  "eventId": "uuid",           // Unique event identifier
  "eventType": "string",       // Event type name
  "eventVersion": "1.0",       // Event schema version
  "timestamp": "ISO8601",      // Event creation timestamp
  "correlationId": "uuid",     // Trace ID for end-to-end tracking
  "causationId": "uuid",       // ID of event that caused this event
  "aggregateId": "uuid",       // ID of main entity (contract, bid, etc.)
  "aggregateType": "string",   // Type of entity (Contract, Bid, etc.)
  "payload": { },              // Event-specific data
  "metadata": {
    "publisherId": "string",   // Module that published event
    "userId": "uuid",          // User who triggered action (if applicable)
    "sessionId": "uuid"        // User session (if applicable)
  }
}
```

---

## 2. EVENT PROCESSING GUARANTEES

### 2.1 Delivery Guarantee

**Type:** Exactly-Once Delivery

**Implementation:**
- All events have unique `eventId` (UUID)
- All event handlers check for duplicate `eventId` before processing
- Idempotency keys stored in handler module database
- If `eventId` already processed → Skip and acknowledge

### 2.2 Idempotency Requirements

**Rule:** ALL event handlers MUST be idempotent

**Implementation Pattern:**
```javascript
async function handleEvent(event) {
  // Check if already processed
  const processed = await checkIdempotency(event.eventId);
  if (processed) {
    logger.info(`Event ${event.eventId} already processed. Skipping.`);
    return; // Acknowledge without processing
  }
  
  // Process event
  try {
    await processEventLogic(event);
    
    // Store idempotency key
    await storeIdempotencyKey(event.eventId, event.timestamp);
    
    // Acknowledge event
    await acknowledgeEvent(event);
  } catch (error) {
    // Handle error (see section 7)
    await handleEventError(event, error);
  }
}
```

### 2.3 Event Ordering

**Rule:** Strict ordering required within aggregate

**Implementation:**
- Events for same `aggregateId` (e.g., same contract) MUST be processed in order
- Events for different aggregates can be processed in parallel
- Use message queue partitioning by `aggregateId` to ensure ordering

**Example:**
- `ContractCreatedEvent` (contractId=123) MUST be processed before `EscrowLockedEvent` (contractId=123)
- `ContractCreatedEvent` (contractId=123) can be processed in parallel with `ContractCreatedEvent` (contractId=456)

---

## 3. EVENT CATALOG BY MODULE

### 3.1 Marketplace Module Events

| Event Name | Trigger | Published By | Subscribing Modules |
|-----------|---------|--------------|---------------------|
| `RFQCreatedEvent` | Business creates RFQ | Marketplace | Identity (audit) |
| `RFQPublishedEvent` | Business publishes RFQ | Marketplace | Notifications |
| `BidSubmittedEvent` | Provider submits bid | Marketplace | Identity (trust score), Notifications |
| `BidWithdrawnEvent` | Provider withdraws bid | Marketplace | Notifications |
| `BidAwardedEvent` | Business awards bid | Marketplace | Contracts, Finance, Identity, Notifications |
| `BidRejectedEvent` | Business doesn't award bid | Marketplace | Notifications |
| `ProviderRejectedAwardEvent` | Provider rejects after award | Marketplace | Contracts, Finance, Identity, Notifications |
| `RFQCancelledEvent` | Business cancels RFQ | Marketplace | Contracts, Finance, Notifications |

### 3.2 Contracts Module Events

| Event Name | Trigger | Published By | Subscribing Modules |
|-----------|---------|--------------|---------------------|
| `ContractCreatedEvent` | Contract created after award | Contracts | Finance, Delivery, Identity, Notifications |
| `ContractCreationFailedEvent` | Contract creation fails | Contracts | Marketplace, Finance, Notifications |
| `VehicleAssignedEvent` | Provider assigns vehicle | Contracts | Delivery, Identity, Notifications |
| `VehicleAssignmentFailedEvent` | Vehicle assignment validation fails | Contracts | Delivery, Notifications |
| `ContractActivatedEvent` | Contract meets activation criteria | Contracts | Finance, Delivery, Identity, Notifications |
| `ContractActivationTimeoutEvent` | Contract stuck in pending > 5 days | Contracts | Notifications, Support |
| `ContractCompletedEvent` | Contract rental period ends | Contracts | Finance, Identity, Notifications |
| `ContractAlteredEvent` | Contract modified (vehicle swap, etc.) | Contracts | Finance, Delivery, Notifications |
| `EarlyReturnRequestedEvent` | Business/Provider requests early return | Contracts | Finance, Notifications |
| `EarlyReturnApprovedEvent` | Both parties approve early return | Contracts | Finance, Delivery, Identity, Notifications |
| `ContractTerminatedEvent` | Contract cancelled/terminated | Contracts | Finance, Marketplace, Notifications |

### 3.3 Finance Module Events

| Event Name | Trigger | Published By | Subscribing Modules |
|-----------|---------|--------------|---------------------|
| `WalletDepositedEvent` | Business deposits to wallet | Finance | Identity, Notifications |
| `EscrowLockedEvent` | Funds locked for contract | Finance | Contracts, Identity, Notifications |
| `EscrowLockFailedEvent` | Escrow lock fails (insufficient funds) | Finance | Contracts, Marketplace, Notifications |
| `EscrowReleasedEvent` | Escrow released back to wallet | Finance | Identity, Notifications |
| `SettlementProcessedEvent` | Provider payment processed | Finance | Identity, Notifications |
| `SettlementFailedEvent` | Settlement processing fails | Finance | Support, Notifications |
| `RefundProcessedEvent` | Business refund processed | Finance | Identity, Notifications |
| `MonthEndSettlementEvent` | Scheduled monthly settlement | Finance (scheduled job) | Finance (settlement processor) |

### 3.4 Delivery Module Events

| Event Name | Trigger | Published By | Subscribing Modules |
|-----------|---------|--------------|---------------------|
| `DeliveryScheduledEvent` | Delivery date/location set | Delivery | Contracts, Notifications |
| `OTPGeneratedEvent` | Provider requests OTP | Delivery | Notifications |
| `DeliveryConfirmedEvent` | Provider enters OTP successfully | Delivery | Contracts, Identity, Notifications |
| `DeliveryRejectedEvent` | Business rejects delivery (no OTP shared) | Delivery | Contracts, Marketplace, Notifications |
| `DeliveryNoShowEvent` | Business no-show at delivery | Delivery | Contracts, Identity, Notifications |
| `VehicleReturnedEvent` | Vehicle returned at contract end | Delivery | Contracts, Finance, Notifications |

### 3.5 Identity Module Events

| Event Name | Trigger | Published By | Subscribing Modules |
|-----------|---------|--------------|---------------------|
| `BusinessVerifiedEvent` | Business KYB verification complete | Identity | Marketplace, Notifications |
| `ProviderVerifiedEvent` | Provider KYC verification complete | Identity | Marketplace, Notifications |
| `BusinessSuspendedEvent` | Business account suspended | Identity | Marketplace, Contracts, Finance |
| `ProviderSuspendedEvent` | Provider account suspended | Identity | Marketplace, Contracts, Finance |
| `TrustScoreUpdatedEvent` | Trust score recalculated | Identity | Marketplace, Notifications |
| `InsuranceExpiringEvent` | Vehicle insurance expiring (30/7 days) | Identity | Marketplace, Contracts, Notifications |
| `InsuranceExpiredEvent` | Vehicle insurance expired | Identity | Marketplace, Contracts, Notifications |
| `VehicleVerifiedEvent` | Vehicle verification complete | Identity | Marketplace, Notifications |
| `VehicleSuspendedEvent` | Vehicle suspended (insurance expired) | Identity | Marketplace, Contracts, Notifications |

### 3.6 Dispute Module Events

| Event Name | Trigger | Published By | Subscribing Modules |
|-----------|---------|--------------|---------------------|
| `DisputeCreatedEvent` | Party creates dispute | Disputes | Contracts, Finance, Notifications, Support |
| `DisputeEvidenceSubmittedEvent` | Party submits evidence | Disputes | Notifications, Support |
| `DisputeResolvedEvent` | Dispute resolved by support | Disputes | Contracts, Finance, Identity, Notifications |
| `DisputeEscalatedEvent` | Dispute escalated to senior support | Disputes | Support, Notifications |

### 3.7 Notifications Module Events

**Note:** Notifications module is a pure consumer - it does NOT publish events. It subscribes to events from all modules and sends notifications (email, SMS, in-app).

---

## 4. EVENT SCHEMAS

### 4.1 Marketplace Module Event Schemas

#### `BidAwardedEvent`
```json
{
  "eventId": "550e8400-e29b-41d4-a716-446655440000",
  "eventType": "BidAwardedEvent",
  "eventVersion": "1.0",
  "timestamp": "2025-12-21T10:30:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": null,
  "aggregateId": "bid-67890",
  "aggregateType": "Bid",
  "payload": {
    "bidId": "bid-67890",
    "rfqId": "rfq-12345",
    "lineItemId": "lineitem-001",
    "providerId": "provider-456",
    "businessId": "business-789",
    "awardedQuantity": 3,
    "totalAmount": 150000.00,
    "currency": "ETB",
    "escrowAmount": 50000.00,
    "rentalPeriod": {
      "startDate": "2025-12-25",
      "endDate": "2026-03-25",
      "durationDays": 90
    },
    "vehicleSpecs": {
      "type": "SEDAN",
      "features": ["AC", "GPS"]
    }
  },
  "metadata": {
    "publisherId": "marketplace-service",
    "userId": "business-user-123",
    "sessionId": "session-abc123"
  }
}
```

#### `ProviderRejectedAwardEvent`
```json
{
  "eventId": "650e8400-e29b-41d4-a716-446655440001",
  "eventType": "ProviderRejectedAwardEvent",
  "eventVersion": "1.0",
  "timestamp": "2025-12-21T11:00:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "550e8400-e29b-41d4-a716-446655440000",
  "aggregateId": "bid-67890",
  "aggregateType": "Bid",
  "payload": {
    "bidId": "bid-67890",
    "rfqId": "rfq-12345",
    "lineItemId": "lineitem-001",
    "providerId": "provider-456",
    "businessId": "business-789",
    "rejectionReason": "VEHICLE_MAINTENANCE",
    "rejectionDetails": "Vehicle in unscheduled maintenance after accident",
    "isFirstTimeRejection": true
  },
  "metadata": {
    "publisherId": "marketplace-service",
    "userId": "provider-user-456",
    "sessionId": "session-def456"
  }
}
```

---

### 4.2 Contracts Module Event Schemas

#### `ContractCreatedEvent`
```json
{
  "eventId": "750e8400-e29b-41d4-a716-446655440002",
  "eventType": "ContractCreatedEvent",
  "eventVersion": "1.0",
  "timestamp": "2025-12-21T10:31:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "550e8400-e29b-41d4-a716-446655440000",
  "aggregateId": "contract-11111",
  "aggregateType": "Contract",
  "payload": {
    "contractId": "contract-11111",
    "bidId": "bid-67890",
    "rfqId": "rfq-12345",
    "lineItemId": "lineitem-001",
    "providerId": "provider-456",
    "businessId": "business-789",
    "status": "PENDING_ESCROW",
    "vehicleQuantity": 3,
    "totalAmount": 150000.00,
    "escrowAmount": 50000.00,
    "currency": "ETB",
    "rentalPeriod": {
      "startDate": "2025-12-25",
      "endDate": "2026-03-25",
      "durationDays": 90
    },
    "vehicleSpecs": {
      "type": "SEDAN",
      "features": ["AC", "GPS"]
    },
    "deliveryLocation": {
      "address": "123 Main St, Addis Ababa",
      "coordinates": {
        "lat": 9.0320,
        "lng": 38.7469
      }
    },
    "terms": {
      "earlyReturnPenalty": "CONFIGURABLE",
      "insuranceRequired": true,
      "kmLimit": null
    }
  },
  "metadata": {
    "publisherId": "contracts-service",
    "userId": "system",
    "sessionId": null
  }
}
```

#### `ContractActivatedEvent`
```json
{
  "eventId": "850e8400-e29b-41d4-a716-446655440003",
  "eventType": "ContractActivatedEvent",
  "eventVersion": "1.0",
  "timestamp": "2025-12-25T09:00:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "delivery-confirmed-event-id",
  "aggregateId": "contract-11111",
  "aggregateType": "Contract",
  "payload": {
    "contractId": "contract-11111",
    "providerId": "provider-456",
    "businessId": "business-789",
    "status": "ACTIVE",
    "activationTimestamp": "2025-12-25T09:00:00Z",
    "escrowLocked": true,
    "vehiclesDelivered": true,
    "vehicleIds": ["vehicle-001", "vehicle-002", "vehicle-003"],
    "actualStartDate": "2025-12-25",
    "expectedEndDate": "2026-03-25"
  },
  "metadata": {
    "publisherId": "contracts-service",
    "userId": "system",
    "sessionId": null
  }
}
```

#### `ContractCompletedEvent`
```json
{
  "eventId": "950e8400-e29b-41d4-a716-446655440004",
  "eventType": "ContractCompletedEvent",
  "eventVersion": "1.0",
  "timestamp": "2026-03-25T17:00:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "vehicle-returned-event-id",
  "aggregateId": "contract-11111",
  "aggregateType": "Contract",
  "payload": {
    "contractId": "contract-11111",
    "providerId": "provider-456",
    "businessId": "business-789",
    "status": "COMPLETED",
    "completionTimestamp": "2026-03-25T17:00:00Z",
    "startDate": "2025-12-25",
    "endDate": "2026-03-25",
    "actualDays": 90,
    "totalAmount": 150000.00,
    "escrowAmount": 50000.00,
    "currency": "ETB",
    "settlementData": {
      "grossAmount": 150000.00,
      "commissionRate": 0.10,
      "commissionAmount": 15000.00,
      "taxRate": 0.02,
      "taxAmount": 3000.00,
      "netSettlement": 132000.00,
      "providerTier": "SILVER"
    },
    "performanceMetrics": {
      "onTimeDelivery": true,
      "noShowCount": 0,
      "disputeCount": 0
    }
  },
  "metadata": {
    "publisherId": "contracts-service",
    "userId": "system",
    "sessionId": null
  }
}
```

#### `EarlyReturnApprovedEvent`
```json
{
  "eventId": "a50e8400-e29b-41d4-a716-446655440005",
  "eventType": "EarlyReturnApprovedEvent",
  "eventVersion": "1.0",
  "timestamp": "2026-02-20T14:30:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "early-return-requested-event-id",
  "aggregateId": "contract-11111",
  "aggregateType": "Contract",
  "payload": {
    "contractId": "contract-11111",
    "providerId": "provider-456",
    "businessId": "business-789",
    "originalEndDate": "2026-03-25",
    "earlyReturnDate": "2026-02-25",
    "noticePeriodDays": 5,
    "penaltyRate": 0.02,
    "remainingAmount": 50000.00,
    "penaltyAmount": 1000.00,
    "refundToBusiness": 49000.00,
    "additionalPaymentToProvider": 1000.00,
    "reason": "Business downsizing, vehicles no longer needed",
    "businessApprovalTimestamp": "2026-02-20T10:00:00Z",
    "providerApprovalTimestamp": "2026-02-20T14:30:00Z"
  },
  "metadata": {
    "publisherId": "contracts-service",
    "userId": "provider-user-456",
    "sessionId": "session-ghi789"
  }
}
```

---

### 4.3 Finance Module Event Schemas

#### `EscrowLockedEvent`
```json
{
  "eventId": "b50e8400-e29b-41d4-a716-446655440006",
  "eventType": "EscrowLockedEvent",
  "eventVersion": "1.0",
  "timestamp": "2025-12-21T10:32:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "750e8400-e29b-41d4-a716-446655440002",
  "aggregateId": "contract-11111",
  "aggregateType": "Contract",
  "payload": {
    "contractId": "contract-11111",
    "businessId": "business-789",
    "providerId": "provider-456",
    "escrowAmount": 50000.00,
    "currency": "ETB",
    "lockTimestamp": "2025-12-21T10:32:00Z",
    "lockReason": "MONTHLY_ESCROW",
    "walletBalanceBefore": 200000.00,
    "walletBalanceAfter": 150000.00,
    "escrowTransactionId": "escrow-tx-99999"
  },
  "metadata": {
    "publisherId": "finance-service",
    "userId": "system",
    "sessionId": null
  }
}
```

#### `EscrowLockFailedEvent`
```json
{
  "eventId": "c50e8400-e29b-41d4-a716-446655440007",
  "eventType": "EscrowLockFailedEvent",
  "eventVersion": "1.0",
  "timestamp": "2025-12-21T10:32:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "750e8400-e29b-41d4-a716-446655440002",
  "aggregateId": "contract-11111",
  "aggregateType": "Contract",
  "payload": {
    "contractId": "contract-11111",
    "businessId": "business-789",
    "providerId": "provider-456",
    "escrowAmount": 50000.00,
    "currency": "ETB",
    "failureReason": "INSUFFICIENT_FUNDS",
    "walletBalance": 30000.00,
    "shortfall": 20000.00,
    "retryCount": 1,
    "maxRetries": 5,
    "nextRetryTimestamp": "2025-12-21T11:02:00Z"
  },
  "metadata": {
    "publisherId": "finance-service",
    "userId": "system",
    "sessionId": null
  }
}
```

#### `MonthEndSettlementEvent`
```json
{
  "eventId": "d50e8400-e29b-41d4-a716-446655440008",
  "eventType": "MonthEndSettlementEvent",
  "eventVersion": "1.0",
  "timestamp": "2026-01-31T23:59:00Z",
  "correlationId": "month-end-settlement-jan-2026",
  "causationId": null,
  "aggregateId": "contract-11111",
  "aggregateType": "Contract",
  "payload": {
    "contractId": "contract-11111",
    "providerId": "provider-456",
    "businessId": "business-789",
    "settlementPeriod": {
      "month": "JANUARY",
      "year": 2026,
      "startDate": "2026-01-01",
      "endDate": "2026-01-31",
      "daysInPeriod": 31
    },
    "contractStartDate": "2025-12-25",
    "contractEndDate": "2026-03-25",
    "proRataCalculation": {
      "totalContractValue": 150000.00,
      "totalDays": 90,
      "dailyRate": 1666.67,
      "daysInJanuary": 31,
      "settlementAmount": 51666.77
    },
    "commissionData": {
      "commissionRate": 0.10,
      "providerTier": "SILVER"
    }
  },
  "metadata": {
    "publisherId": "finance-service-scheduler",
    "userId": "system",
    "sessionId": null
  }
}
```

---

### 4.4 Delivery Module Event Schemas

#### `DeliveryConfirmedEvent`
```json
{
  "eventId": "e50e8400-e29b-41d4-a716-446655440009",
  "eventType": "DeliveryConfirmedEvent",
  "eventVersion": "1.0",
  "timestamp": "2025-12-25T09:00:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "otp-generated-event-id",
  "aggregateId": "contract-11111",
  "aggregateType": "Contract",
  "payload": {
    "contractId": "contract-11111",
    "providerId": "provider-456",
    "businessId": "business-789",
    "deliveryTimestamp": "2025-12-25T09:00:00Z",
    "vehicleIds": ["vehicle-001", "vehicle-002", "vehicle-003"],
    "deliveryLocation": {
      "address": "123 Main St, Addis Ababa",
      "coordinates": {
        "lat": 9.0320,
        "lng": 38.7469
      }
    },
    "otpVerification": {
      "otpId": "otp-12345",
      "generatedTimestamp": "2025-12-25T08:45:00Z",
      "verifiedTimestamp": "2025-12-25T09:00:00Z",
      "attempts": 1
    },
    "businessContactPerson": {
      "name": "John Doe",
      "phone": "+251911223344",
      "email": "john@business.com"
    },
    "providerDriver": {
      "name": "Ahmed Ali",
      "phone": "+251922334455",
      "licenseNumber": "DL-123456"
    }
  },
  "metadata": {
    "publisherId": "delivery-service",
    "userId": "provider-user-456",
    "sessionId": "session-jkl012"
  }
}
```

#### `DeliveryRejectedEvent`
```json
{
  "eventId": "f50e8400-e29b-41d4-a716-446655440010",
  "eventType": "DeliveryRejectedEvent",
  "eventVersion": "1.0",
  "timestamp": "2025-12-25T09:30:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "otp-generated-event-id",
  "aggregateId": "contract-11111",
  "aggregateType": "Contract",
  "payload": {
    "contractId": "contract-11111",
    "providerId": "provider-456",
    "businessId": "business-789",
    "rejectionTimestamp": "2025-12-25T09:30:00Z",
    "rejectionReason": "VEHICLE_CONDITION_MISMATCH",
    "rejectionDetails": "Vehicle has visible damage on front bumper, not matching contract specs",
    "rejectionPhotos": [
      "https://storage.movello.com/disputes/photo1.jpg",
      "https://storage.movello.com/disputes/photo2.jpg"
    ],
    "deliveryLocation": {
      "address": "123 Main St, Addis Ababa",
      "coordinates": {
        "lat": 9.0320,
        "lng": 38.7469
      }
    },
    "businessContactPerson": {
      "name": "John Doe",
      "phone": "+251911223344"
    }
  },
  "metadata": {
    "publisherId": "delivery-service",
    "userId": "business-user-123",
    "sessionId": "session-mno345"
  }
}
```

---

### 4.5 Identity Module Event Schemas

#### `TrustScoreUpdatedEvent`
```json
{
  "eventId": "g50e8400-e29b-41d4-a716-446655440011",
  "eventType": "TrustScoreUpdatedEvent",
  "eventVersion": "1.0",
  "timestamp": "2026-03-25T17:05:00Z",
  "correlationId": "rfq-12345-award-flow",
  "causationId": "950e8400-e29b-41d4-a716-446655440004",
  "aggregateId": "provider-456",
  "aggregateType": "Provider",
  "payload": {
    "providerId": "provider-456",
    "previousScore": 72,
    "newScore": 78,
    "scoreDelta": 6,
    "recalculationTrigger": "CONTRACT_COMPLETED",
    "triggerEventId": "950e8400-e29b-41d4-a716-446655440004",
    "calculationData": {
      "baseScore": 50,
      "completionRate": 0.95,
      "completionPoints": 19,
      "onTimeRate": 0.90,
      "onTimePoints": 18,
      "noShowRate": 0.05,
      "noShowPenalty": -9,
      "rejectionPenalty": 0,
      "totalScore": 78
    },
    "contractStats": {
      "totalContracts": 20,
      "completedContracts": 19,
      "onTimeDeliveries": 18,
      "noShows": 1,
      "rejections": 0
    }
  },
  "metadata": {
    "publisherId": "identity-service",
    "userId": "system",
    "sessionId": null
  }
}
```

#### `InsuranceExpiringEvent`
```json
{
  "eventId": "h50e8400-e29b-41d4-a716-446655440012",
  "eventType": "InsuranceExpiringEvent",
  "eventVersion": "1.0",
  "timestamp": "2026-01-01T00:00:00Z",
  "correlationId": "insurance-expiry-check-jan-2026",
  "causationId": null,
  "aggregateId": "vehicle-001",
  "aggregateType": "Vehicle",
  "payload": {
    "vehicleId": "vehicle-001",
    "providerId": "provider-456",
    "insuranceExpiryDate": "2026-01-31",
    "daysUntilExpiry": 30,
    "urgencyLevel": "WARNING",
    "insurancePolicyNumber": "INS-2025-12345",
    "insuranceProvider": "Ethiopian Insurance Corporation",
    "vehicleDetails": {
      "make": "Toyota",
      "model": "Corolla",
      "year": 2023,
      "plateNumber": "AA-3-12345"
    },
    "activeContracts": [
      {
        "contractId": "contract-11111",
        "businessId": "business-789",
        "endDate": "2026-03-25"
      }
    ]
  },
  "metadata": {
    "publisherId": "identity-service-scheduler",
    "userId": "system",
    "sessionId": null
  }
}
```

---

### 4.6 Dispute Module Event Schemas

#### `DisputeCreatedEvent`
```json
{
  "eventId": "i50e8400-e29b-41d4-a716-446655440013",
  "eventType": "DisputeCreatedEvent",
  "eventVersion": "1.0",
  "timestamp": "2026-02-10T15:00:00Z",
  "correlationId": "dispute-settlement-disagreement-001",
  "causationId": null,
  "aggregateId": "dispute-88888",
  "aggregateType": "Dispute",
  "payload": {
    "disputeId": "dispute-88888",
    "contractId": "contract-11111",
    "initiatedBy": "PROVIDER",
    "providerId": "provider-456",
    "businessId": "business-789",
    "category": "SETTLEMENT_AMOUNT_DISAGREEMENT",
    "description": "Settlement calculation incorrect, commission rate should be 8% not 10% per contract terms",
    "disputedAmount": 3000.00,
    "evidence": [
      {
        "type": "DOCUMENT",
        "url": "https://storage.movello.com/disputes/contract-signed.pdf",
        "description": "Original signed contract showing 8% commission"
      }
    ],
    "status": "OPEN",
    "priority": "HIGH",
    "resolutionDeadline": "2026-02-12T15:00:00Z"
  },
  "metadata": {
    "publisherId": "disputes-service",
    "userId": "provider-user-456",
    "sessionId": "session-pqr678"
  }
}
```

---

## 5. EVENT HANDLER SPECIFICATIONS

### 5.1 BidAwardedEvent Handlers

**Publishing Module:** Marketplace

#### Handler 1: Contracts Module - Create Contract
```javascript
Module: Contracts
Handler: ContractCreationHandler
Priority: CRITICAL
Order: 1 (must run first)

async function handleBidAwardedEvent(event) {
  const { bidId, rfqId, providerId, businessId, totalAmount, escrowAmount } = event.payload;
  
  // Check idempotency
  if (await isAlreadyProcessed(event.eventId)) return;
  
  try {
    // Create contract
    const contract = await createContract({
      bidId,
      rfqId,
      providerId,
      businessId,
      totalAmount,
      escrowAmount,
      status: 'PENDING_ESCROW'
    });
    
    // Publish ContractCreatedEvent
    await publishEvent({
      eventType: 'ContractCreatedEvent',
      correlationId: event.correlationId,
      causationId: event.eventId,
      aggregateId: contract.id,
      payload: contract
    });
    
    // Store idempotency key
    await storeIdempotencyKey(event.eventId);
    
  } catch (error) {
    // Publish failure event
    await publishEvent({
      eventType: 'ContractCreationFailedEvent',
      correlationId: event.correlationId,
      causationId: event.eventId,
      payload: { bidId, error: error.message }
    });
    throw error; // Will retry
  }
}
```

#### Handler 2: Finance Module - Prepare for Escrow Lock
```javascript
Module: Finance
Handler: EscrowPreparationHandler
Priority: MEDIUM
Order: 2 (after contract created)

async function handleBidAwardedEvent(event) {
  const { businessId, escrowAmount } = event.payload;
  
  if (await isAlreadyProcessed(event.eventId)) return;
  
  // Log escrow requirement for tracking
  await logEscrowRequirement({
    businessId,
    escrowAmount,
    eventId: event.eventId,
    correlationId: event.correlationId
  });
  
  await storeIdempotencyKey(event.eventId);
}
```

#### Handler 3: Identity Module - Update Business Stats
```javascript
Module: Identity
Handler: BusinessStatsHandler
Priority: LOW
Order: N/A (can run anytime)

async function handleBidAwardedEvent(event) {
  const { businessId } = event.payload;
  
  if (await isAlreadyProcessed(event.eventId)) return;
  
  // Update business stats (total awards, spend)
  await updateBusinessStats(businessId, {
    totalAwards: { increment: 1 },
    lastAwardDate: event.timestamp
  });
  
  await storeIdempotencyKey(event.eventId);
}
```

---

### 5.2 ContractCreatedEvent Handlers

**Publishing Module:** Contracts

#### Handler 1: Finance Module - Lock Escrow
```javascript
Module: Finance
Handler: EscrowLockHandler
Priority: CRITICAL
Order: 1 (must run first)

async function handleContractCreatedEvent(event) {
  const { contractId, businessId, escrowAmount } = event.payload;
  
  if (await isAlreadyProcessed(event.eventId)) return;
  
  try {
    // Validate wallet balance
    const wallet = await getWallet(businessId);
    if (wallet.balance < escrowAmount) {
      throw new Error(`Insufficient balance. Required: ${escrowAmount}, Available: ${wallet.balance}`);
    }
    
    // Lock escrow
    const escrowTx = await lockEscrow({
      contractId,
      businessId,
      amount: escrowAmount
    });
    
    // Publish success event
    await publishEvent({
      eventType: 'EscrowLockedEvent',
      correlationId: event.correlationId,
      causationId: event.eventId,
      aggregateId: contractId,
      payload: {
        contractId,
        businessId,
        escrowAmount,
        escrowTransactionId: escrowTx.id,
        walletBalanceBefore: wallet.balance,
        walletBalanceAfter: wallet.balance - escrowAmount
      }
    });
    
    await storeIdempotencyKey(event.eventId);
    
  } catch (error) {
    // Publish failure event
    await publishEvent({
      eventType: 'EscrowLockFailedEvent',
      correlationId: event.correlationId,
      causationId: event.eventId,
      aggregateId: contractId,
      payload: {
        contractId,
        businessId,
        escrowAmount,
        failureReason: error.message,
        retryCount: 1
      }
    });
    throw error; // Will retry
  }
}
```

---

### 5.3 EscrowLockedEvent Handlers

**Publishing Module:** Finance

#### Handler 1: Contracts Module - Update Contract Status
```javascript
Module: Contracts
Handler: ContractEscrowConfirmationHandler
Priority: CRITICAL
Order: 1

async function handleEscrowLockedEvent(event) {
  const { contractId } = event.payload;
  
  if (await isAlreadyProcessed(event.eventId)) return;
  
  // Update contract status
  await updateContractStatus(contractId, {
    status: 'PENDING_VEHICLE_ASSIGNMENT',
    escrowLockedAt: event.timestamp,
    escrowTransactionId: event.payload.escrowTransactionId
  });
  
  await storeIdempotencyKey(event.eventId);
}
```

---

### 5.4 DeliveryConfirmedEvent Handlers

**Publishing Module:** Delivery

#### Handler 1: Contracts Module - Activate Contract
```javascript
Module: Contracts
Handler: ContractActivationHandler
Priority: CRITICAL
Order: 1

async function handleDeliveryConfirmedEvent(event) {
  const { contractId, vehicleId } = event.payload;
  
  if (await isAlreadyProcessed(event.eventId)) return;
  
  // Check activation prerequisites
  const contract = await getContract(contractId);
  
  // Update vehicle delivery status
  await markVehicleDelivered(contractId, vehicleId, event.timestamp);
  
  // Calculate delivery metrics
  const deliveryMetrics = await calculateDeliveryMetrics(contractId);
  const { quantityAwarded, quantityDelivered, quantityActive } = deliveryMetrics;
  
  if (contract.escrowLocked && contract.vehiclesAssigned) {
    // Determine contract status based on delivery progress
    let newStatus = contract.status;
    
    if (quantityDelivered === 0) {
      newStatus = 'PENDING_DELIVERY';
    } else if (quantityDelivered < quantityAwarded) {
      // Some but not all vehicles delivered
      newStatus = 'PARTIALLY_DELIVERED';
      
      // Update contract status to PARTIALLY_DELIVERED if not already
      if (contract.status !== 'PARTIALLY_DELIVERED') {
        await updateContractStatus(contractId, {
          status: 'PARTIALLY_DELIVERED',
          firstDeliveryAt: event.timestamp,
          quantityDelivered: quantityDelivered,
          quantityActive: quantityActive
        });
        
        // Publish partial activation event (optional, for tracking)
        await publishEvent({
          eventType: 'ContractPartiallyActivatedEvent',
          correlationId: event.correlationId,
          causationId: event.eventId,
          aggregateId: contractId,
          payload: {
            contractId,
            quantityDelivered,
            quantityAwarded,
            status: 'PARTIALLY_DELIVERED'
          }
        });
      } else {
        // Update delivery metrics
        await updateContractStatus(contractId, {
          quantityDelivered: quantityDelivered,
          quantityActive: quantityActive,
          lastDeliveryAt: event.timestamp
        });
      }
    } else if (quantityDelivered === quantityAwarded) {
      // All vehicles delivered - fully activate contract
      newStatus = 'ACTIVE';
      
      await updateContractStatus(contractId, {
        status: 'ACTIVE',
        activatedAt: event.timestamp,
        actualStartDate: event.timestamp,
        quantityDelivered: quantityDelivered,
        quantityActive: quantityActive
      });
      
      // Publish full activation event
      await publishEvent({
        eventType: 'ContractActivatedEvent',
        correlationId: event.correlationId,
        causationId: event.eventId,
        aggregateId: contractId,
        payload: {
          contractId,
          providerId: contract.providerId,
          businessId: contract.businessId,
          status: 'ACTIVE',
          activationTimestamp: event.timestamp,
          quantityDelivered,
          quantityAwarded
        }
      });
    }
  }
  
  await storeIdempotencyKey(event.eventId);
}

// Helper function to calculate delivery metrics
async function calculateDeliveryMetrics(contractId) {
  const contract = await getContractWithLineItems(contractId);
  
  let totalAwarded = 0;
  let totalDelivered = 0;
  let totalActive = 0;
  
  for (const lineItem of contract.lineItems) {
    totalAwarded += lineItem.quantityAwarded;
    totalDelivered += lineItem.quantityDelivered || 0;
    totalActive += lineItem.quantityActive || 0;
  }
  
  return {
    quantityAwarded: totalAwarded,
    quantityDelivered: totalDelivered,
    quantityActive: totalActive
  };
}
```

#### Handler 2: Identity Module - Update Trust Score (On-Time Delivery)
```javascript
Module: Identity
Handler: TrustScoreDeliveryHandler
Priority: MEDIUM
Order: 2

async function handleDeliveryConfirmedEvent(event) {
  const { providerId, contractId } = event.payload;
  
  if (await isAlreadyProcessed(event.eventId)) return;
  
  // Check if delivery was on time
  const contract = await getContract(contractId);
  const onTime = isDeliveryOnTime(event.timestamp, contract.expectedDeliveryDate);
  
  // Recalculate trust score
  await recalculateTrustScore(providerId, {
    deliveryCompleted: true,
    onTime
  });
  
  await storeIdempotencyKey(event.eventId);
}
```

---

### 5.5 ContractCompletedEvent Handlers

**Publishing Module:** Contracts

#### Handler 1: Finance Module - Process Settlement
```javascript
Module: Finance
Handler: SettlementHandler
Priority: CRITICAL
Order: 1

async function handleContractCompletedEvent(event) {
  const { contractId, providerId, settlementData } = event.payload;
  
  if (await isAlreadyProcessed(event.eventId)) return;
  
  try {
    // Check contract duration for settlement timing
    const { actualDays } = event.payload;
    
    if (actualDays < 30) {
      // Short-term contract - process settlement immediately
      await processSettlement({
        contractId,
        providerId,
        amount: settlementData.netSettlement,
        settlementType: 'CONTRACT_COMPLETION'
      });
      
      await publishEvent({
        eventType: 'SettlementProcessedEvent',
        correlationId: event.correlationId,
        causationId: event.eventId,
        aggregateId: contractId,
        payload: { contractId, providerId, amount: settlementData.netSettlement }
      });
    } else {
      // Long-term contract - final settlement for remaining days
      // (Monthly settlements already processed via MonthEndSettlementEvent)
      const remainingDays = calculateRemainingDaysAfterLastMonthEnd(event.payload);
      
      if (remainingDays > 0) {
        const finalAmount = calculateProRataAmount(settlementData, remainingDays);
        
        await processSettlement({
          contractId,
          providerId,
          amount: finalAmount,
          settlementType: 'FINAL_SETTLEMENT'
        });
      }
    }
    
    await storeIdempotencyKey(event.eventId);
    
  } catch (error) {
    await publishEvent({
      eventType: 'SettlementFailedEvent',
      payload: { contractId, error: error.message }
    });
    throw error;
  }
}
```

#### Handler 2: Identity Module - Update Trust Score (Completion)
```javascript
Module: Identity
Handler: TrustScoreCompletionHandler
Priority: MEDIUM
Order: 2

async function handleContractCompletedEvent(event) {
  const { providerId, businessId, performanceMetrics } = event.payload;
  
  if (await isAlreadyProcessed(event.eventId)) return;
  
  // Update provider trust score
  await recalculateTrustScore(providerId, {
    contractCompleted: true,
    onTimeDelivery: performanceMetrics.onTimeDelivery,
    noShowCount: performanceMetrics.noShowCount
  });
  
  // Update business trust score (future feature)
  // await recalculateTrustScore(businessId, { contractCompleted: true });
  
  await storeIdempotencyKey(event.eventId);
}
```

---

### 5.6 MonthEndSettlementEvent Handlers

**Publishing Module:** Finance (Scheduled Job)

#### Handler 1: Finance Module - Process Monthly Settlement
```javascript
Module: Finance
Handler: MonthlySettlementHandler
Priority: CRITICAL
Order: 1

async function handleMonthEndSettlementEvent(event) {
  const { contractId, providerId, proRataCalculation, commissionData } = event.payload;
  
  if (await isAlreadyProcessed(event.eventId)) return;
  
  try {
    // Calculate net settlement with commission and tax
    const grossAmount = proRataCalculation.settlementAmount;
    const commission = grossAmount * commissionData.commissionRate;
    const tax = grossAmount * 0.02; // 2% tax
    const netSettlement = grossAmount - commission - tax;
    
    // Process settlement
    await processSettlement({
      contractId,
      providerId,
      amount: netSettlement,
      settlementType: 'MONTHLY_SETTLEMENT',
      settlementPeriod: event.payload.settlementPeriod
    });
    
    // Publish success event
    await publishEvent({
      eventType: 'SettlementProcessedEvent',
      correlationId: event.correlationId,
      causationId: event.eventId,
      aggregateId: contractId,
      payload: {
        contractId,
        providerId,
        amount: netSettlement,
        settlementType: 'MONTHLY',
        period: event.payload.settlementPeriod
      }
    });
    
    await storeIdempotencyKey(event.eventId);
    
  } catch (error) {
    await publishEvent({
      eventType: 'SettlementFailedEvent',
      payload: { contractId, error: error.message }
    });
    throw error;
  }
}
```

---

## 6. RETRY POLICIES

### 6.1 Retry Configuration

**All events have retry policies with exponential backoff:**

```javascript
const RETRY_CONFIG = {
  maxRetries: 5,
  initialDelay: 1000, // 1 second
  maxDelay: 300000,   // 5 minutes
  backoffMultiplier: 2,
  jitter: true        // Add randomness to avoid thundering herd
};

function calculateRetryDelay(attemptNumber) {
  const delay = Math.min(
    RETRY_CONFIG.initialDelay * Math.pow(RETRY_CONFIG.backoffMultiplier, attemptNumber - 1),
    RETRY_CONFIG.maxDelay
  );
  
  // Add jitter (±20%)
  if (RETRY_CONFIG.jitter) {
    const jitter = delay * 0.2 * (Math.random() - 0.5);
    return delay + jitter;
  }
  
  return delay;
}
```

**Retry Schedule:**
- Attempt 1: Immediate
- Attempt 2: 1 second
- Attempt 3: 2 seconds
- Attempt 4: 4 seconds
- Attempt 5: 8 seconds
- Attempt 6: 16 seconds (capped at 5 minutes for longer retries)

### 6.2 Retry Decision Matrix

| Event Type | Retry on Failure | Max Retries | Move to DLQ After |
|-----------|-----------------|-------------|-------------------|
| BidAwardedEvent | ✅ Yes | 5 | 5 failures |
| ContractCreatedEvent | ✅ Yes | 5 | 5 failures |
| EscrowLockedEvent | ✅ Yes | 5 | 5 failures |
| EscrowLockFailedEvent | ✅ Yes (background retry) | 5 | 5 failures |
| DeliveryConfirmedEvent | ✅ Yes | 5 | 5 failures |
| ContractCompletedEvent | ✅ Yes | 5 | 5 failures |
| SettlementProcessedEvent | ✅ Yes | 5 | 5 failures |
| NotificationEvent | ✅ Yes | 3 | 3 failures (non-critical) |
| TrustScoreUpdatedEvent | ✅ Yes | 3 | 3 failures (non-critical) |

---

## 7. ERROR HANDLING & DEAD LETTER QUEUE

### 7.1 Error Handling Strategy

**Critical Events (ContractCreatedEvent, EscrowLockedEvent, SettlementProcessedEvent):**
1. Retry with exponential backoff (5 attempts)
2. If all retries fail → Move to Dead Letter Queue (DLQ)
3. Alert on-call engineer
4. Manual intervention required

**Non-Critical Events (TrustScoreUpdatedEvent, NotificationEvent):**
1. Retry with exponential backoff (3 attempts)
2. If all retries fail → Move to DLQ
3. Log error (no alert)
4. Process in batch later

### 7.2 Dead Letter Queue Processing

**DLQ Consumer:**
```javascript
// Background job runs every 1 hour
async function processDLQ() {
  const dlqMessages = await fetchDLQMessages(limit: 100);
  
  for (const message of dlqMessages) {
    try {
      // Check if event is still valid
      if (isEventStale(message)) {
        await archiveMessage(message);
        continue;
      }
      
      // Retry processing
      await retryEventProcessing(message);
      
      // If successful, remove from DLQ
      await removeFom DLQ(message);
      
    } catch (error) {
      // Still failing - keep in DLQ
      await incrementDLQRetryCount(message);
      
      // If too many DLQ retries, escalate
      if (message.dlqRetryCount > 10) {
        await createSupportTicket(message);
      }
    }
  }
}
```

---

## 8. EVENT ORDERING & SAGA PATTERNS

### 8.1 Saga: Award → Contract → Escrow → Delivery → Activation

**Saga Coordinator:** Contracts Module

**Saga Steps:**

```
Step 1: BidAwardedEvent (Marketplace)
  ↓
Step 2: ContractCreatedEvent (Contracts)
  ↓ [Compensating Action: Cancel Contract if next step fails]
Step 3: EscrowLockedEvent (Finance)
  ↓ [Compensating Action: Release Escrow if next step fails]
Step 4: VehicleAssignedEvent (Contracts)
  ↓ [Compensating Action: Unassign Vehicles if delivery fails]
Step 5: DeliveryConfirmedEvent (Delivery)
  ↓
Step 6: ContractActivatedEvent (Contracts)
```

**Compensating Actions:**

If **EscrowLockFailedEvent** occurs:
```javascript
async function compensateContractCreation(event) {
  // Update contract status to PENDING_ESCROW
  await updateContractStatus(event.payload.contractId, {
    status: 'PENDING_ESCROW',
    escrowLockRetryCount: event.payload.retryCount
  });
  
  // Background retry (see BR-011)
  await scheduleEscrowRetry(event.payload.contractId, event.payload.nextRetryTimestamp);
}
```

If **DeliveryRejectedEvent** occurs:
```javascript
async function compensateVehicleAssignment(event) {
  const { contractId } = event.payload;
  
  // Release escrow
  await publishEvent({
    eventType: 'EscrowReleasedEvent',
    payload: { contractId, reason: 'DELIVERY_REJECTED' }
  });
  
  // Unassign vehicles
  await unassignVehicles(contractId);
  
  // Give provider option to replace or cancel
  await notifyProviderForReplacement(contractId);
}
```

---

### 8.2 Event Version Management

**Event Versioning Strategy:**

Each event has `eventVersion` field (e.g., "1.0", "1.1", "2.0")

**Version Compatibility:**
- **Minor version changes (1.0 → 1.1):** Backward compatible (new optional fields)
- **Major version changes (1.0 → 2.0):** Breaking changes (field renamed/removed)

**Handler Compatibility:**
```javascript
async function handleContractCreatedEvent(event) {
  switch (event.eventVersion) {
    case '1.0':
      return handleV1_0(event);
    case '1.1':
      return handleV1_1(event);
    case '2.0':
      return handleV2_0(event);
    default:
      throw new Error(`Unsupported event version: ${event.eventVersion}`);
  }
}
```

---

## APPENDIX A: Event Flow Diagrams

### A.1 Happy Path: Award to Activation

```
[Business Awards Bid]
        ↓
    BidAwardedEvent (Marketplace)
        ↓
    ContractCreatedEvent (Contracts)
        ↓
    EscrowLockedEvent (Finance)
        ↓
    VehicleAssignedEvent (Contracts)
        ↓
    DeliveryConfirmedEvent (Delivery)
        ↓
    ContractActivatedEvent (Contracts)
```

### A.2 Error Path: Escrow Lock Fails

```
[Business Awards Bid]
        ↓
    BidAwardedEvent (Marketplace)
        ↓
    ContractCreatedEvent (Contracts)
        ↓
    EscrowLockFailedEvent (Finance)
        ↓
    [Contract Status → PENDING_ESCROW]
        ↓
    [Background Retry Every 30 Minutes]
        ↓
    [After 5 Retries → Notify Business & Provider]
```

---

## APPENDIX B: Complete Event List

| # | Event Name | Module | Priority |
|---|-----------|--------|----------|
| 1 | RFQCreatedEvent | Marketplace | LOW |
| 2 | RFQPublishedEvent | Marketplace | MEDIUM |
| 3 | BidSubmittedEvent | Marketplace | LOW |
| 4 | BidWithdrawnEvent | Marketplace | LOW |
| 5 | **BidAwardedEvent** | Marketplace | **CRITICAL** |
| 6 | BidRejectedEvent | Marketplace | LOW |
| 7 | ProviderRejectedAwardEvent | Marketplace | HIGH |
| 8 | RFQCancelledEvent | Marketplace | MEDIUM |
| 9 | **ContractCreatedEvent** | Contracts | **CRITICAL** |
| 10 | ContractCreationFailedEvent | Contracts | HIGH |
| 11 | VehicleAssignedEvent | Contracts | HIGH |
| 12 | VehicleAssignmentFailedEvent | Contracts | HIGH |
| 13 | **ContractActivatedEvent** | Contracts | **CRITICAL** |
| 14 | ContractActivationTimeoutEvent | Contracts | HIGH |
| 15 | **ContractCompletedEvent** | Contracts | **CRITICAL** |
| 16 | ContractAlteredEvent | Contracts | HIGH |
| 17 | EarlyReturnRequestedEvent | Contracts | MEDIUM |
| 18 | EarlyReturnApprovedEvent | Contracts | HIGH |
| 19 | ContractTerminatedEvent | Contracts | HIGH |
| 20 | WalletDepositedEvent | Finance | MEDIUM |
| 21 | **EscrowLockedEvent** | Finance | **CRITICAL** |
| 22 | EscrowLockFailedEvent | Finance | HIGH |
| 23 | EscrowReleasedEvent | Finance | MEDIUM |
| 24 | SettlementProcessedEvent | Finance | CRITICAL |
| 25 | SettlementFailedEvent | Finance | HIGH |
| 26 | RefundProcessedEvent | Finance | MEDIUM |
| 27 | **MonthEndSettlementEvent** | Finance | **CRITICAL** |
| 28 | DeliveryScheduledEvent | Delivery | MEDIUM |
| 29 | OTPGeneratedEvent | Delivery | MEDIUM |
| 30 | **DeliveryConfirmedEvent** | Delivery | **CRITICAL** |
| 31 | DeliveryRejectedEvent | Delivery | HIGH |
| 32 | DeliveryNoShowEvent | Delivery | HIGH |
| 33 | VehicleReturnedEvent | Delivery | MEDIUM |
| 34 | BusinessVerifiedEvent | Identity | MEDIUM |
| 35 | ProviderVerifiedEvent | Identity | MEDIUM |
| 36 | BusinessSuspendedEvent | Identity | HIGH |
| 37 | ProviderSuspendedEvent | Identity | HIGH |
| 38 | TrustScoreUpdatedEvent | Identity | LOW |
| 39 | InsuranceExpiringEvent | Identity | HIGH |
| 40 | InsuranceExpiredEvent | Identity | CRITICAL |
| 41 | VehicleVerifiedEvent | Identity | MEDIUM |
| 42 | VehicleSuspendedEvent | Identity | HIGH |
| 43 | DisputeCreatedEvent | Disputes | HIGH |
| 44 | DisputeEvidenceSubmittedEvent | Disputes | MEDIUM |
| 45 | DisputeResolvedEvent | Disputes | HIGH |
| 46 | DisputeEscalatedEvent | Disputes | HIGH |

**Total Events:** 46

---

**END OF EVENT CATALOG DOCUMENT**

---

**For Implementation:** Use this document as reference for:
1. Event schema definitions
2. Handler implementation
3. Retry policy configuration
4. Error handling strategies
5. Event ordering requirements

**For Testing:** Verify:
1. Idempotency (duplicate events ignored)
2. Retry mechanisms (events retried on failure)
3. Event ordering (within aggregates)
4. Saga compensating actions
5. DLQ processing
