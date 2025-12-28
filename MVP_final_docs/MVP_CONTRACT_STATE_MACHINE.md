# Movello MVP - Contract State Machine Specification
## Complete State Definitions, Transitions & Timeouts - Version 1.0

**Document Status:** AUTHORITATIVE  
**Date:** December 22, 2025  
**Related Documents:** 
- MVP_AUTHORITATIVE_BUSINESS_RULES.md
- MVP_EVENT_CATALOG_AND_HANDLERS.md
- MVP_MODULE_INTEGRATION_SPECIFICATION.md  
**Review Status:** ✅ Approved by Business Owner

---

## Document Purpose

This document defines the complete contract lifecycle state machine for the Movello MVP platform, including:
- All contract states and their meanings
- State transition rules and triggers
- Timeout definitions and actions
- State validation rules
- Error states and recovery procedures
- Visual state diagrams

---

## TABLE OF CONTENTS

1. [Contract State Overview](#1-contract-state-overview)
2. [Contract State Definitions](#2-contract-state-definitions)
3. [Contract Line Item State Definitions](#2a-contract-line-item-state-definitions)
4. [Vehicle Assignment State Definitions](#2b-vehicle-assignment-state-definitions)
5. [State Transition Matrix](#3-state-transition-matrix)
6. [State Machine Diagram](#4-state-machine-diagram)
7. [Timeout Rules](#5-timeout-rules)
8. [State Validation Rules](#6-state-validation-rules)
9. [Error States & Recovery](#7-error-states--recovery)
10. [State Change Event Flow](#8-state-change-event-flow)
11. [Business Rules Mapping](#9-business-rules-mapping)
12. [Status Aggregation Rules](#10-status-aggregation-rules)

---

## 1. CONTRACT STATE OVERVIEW

### 1.1 State Categories

**Pending States** (Contract Not Yet Active):
- `PENDING_ESCROW` - Waiting for escrow lock
- `PENDING_VEHICLE_ASSIGNMENT` - Waiting for vehicle assignment
- `PENDING_DELIVERY` - Waiting for delivery confirmation
- `PARTIALLY_DELIVERED` - Some vehicles delivered, waiting for remaining vehicles
- `TIMEOUT_PENDING` - Activation timeout reached

**Active States** (Contract Running):
- `ACTIVE` - Contract is active and running
- `ON_HOLD` - Contract temporarily suspended

**Completion States** (Contract Ended):
- `COMPLETED` - Contract successfully completed
- `TERMINATED` - Contract cancelled/terminated early
- `FAILED` - Contract failed during setup

**Administrative States**:
- `UNDER_DISPUTE` - Contract has active dispute
- `PENDING_ALTERATION` - Contract modification requested
- `ALTERED` - Contract has been modified

---

### 1.2 State Lifecycle Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                     CONTRACT LIFECYCLE                            │
└──────────────────────────────────────────────────────────────────┘

CREATION → PENDING_ESCROW → PENDING_VEHICLE_ASSIGNMENT → 
PENDING_DELIVERY → [PARTIALLY_DELIVERED] → ACTIVE → COMPLETED

Note: PARTIALLY_DELIVERED is optional - only occurs when contract has multiple vehicles and some but not all are delivered.

                    ↓ (if issues)
              TIMEOUT_PENDING
                    ↓
            ON_HOLD / FAILED
```

---

## 2. CONTRACT STATE DEFINITIONS

**Note:** Contract status aggregates from Contract Line Item statuses. See [Section 2A](#2a-contract-line-item-state-definitions) and [Section 10](#10-status-aggregation-rules) for details.

### 2.1 PENDING_ESCROW

**Description:** Contract created after bid award, waiting for escrow funds to be locked.

**Entry Conditions:**
- `BidAwardedEvent` received
- Contract created successfully
- Escrow lock NOT yet confirmed

**Exit Conditions:**
- `EscrowLockedEvent` received → Transition to `PENDING_VEHICLE_ASSIGNMENT`
- `EscrowLockFailedEvent` received (after retries) → Transition to `FAILED`
- Timeout (5 days) → Transition to `TIMEOUT_PENDING`

**Allowed Actions:**
- System: Retry escrow lock (background job)
- Business: Deposit funds to wallet
- Provider: None (waiting)
- Admin: Cancel contract

**Key Attributes:**
```typescript
{
  status: 'PENDING_ESCROW',
  escrowLockAttempts: number,
  lastEscrowAttemptAt: timestamp,
  createdAt: timestamp,
  timeoutAt: timestamp (createdAt + 5 days)
}
```

**Business Rule Reference:** BR-010, BR-011

---

### 2.2 PENDING_VEHICLE_ASSIGNMENT

**Description:** Escrow locked successfully, waiting for provider to assign vehicles.

**Entry Conditions:**
- `EscrowLockedEvent` received
- Contract status = `PENDING_ESCROW`
- Escrow amount locked in business wallet

**Exit Conditions:**
- All required vehicles assigned → Transition to `PENDING_DELIVERY`
- Timeout (5 days) → Transition to `TIMEOUT_PENDING`
- Provider rejects contract → Transition to `FAILED`

**Allowed Actions:**
- Provider: Assign vehicles to contract
- Provider: Request contract cancellation
- Business: View contract status
- Admin: Assign vehicles manually, cancel contract

**Key Attributes:**
```typescript
{
  status: 'PENDING_VEHICLE_ASSIGNMENT',
  escrowLockedAt: timestamp,
  requiredVehicles: number,
  assignedVehicles: number,
  assignedVehicleIds: string[],
  timeoutAt: timestamp (escrowLockedAt + 5 days)
}
```

**Business Rule Reference:** BR-013

---

### 2.3 PENDING_DELIVERY

**Description:** Vehicles assigned, waiting for delivery confirmation via OTP.

**Entry Conditions:**
- All required vehicles assigned
- Contract status = `PENDING_VEHICLE_ASSIGNMENT`
- Delivery scheduled

**Exit Conditions:**
- First vehicle delivered (OTP verified) → Transition to `PARTIALLY_DELIVERED` (if contract has multiple vehicles)
- All vehicles delivered (OTP verified) → Transition to `ACTIVE` (if all vehicles delivered in one batch or last vehicle delivered)
- `DeliveryRejectedEvent` received → Transition to `FAILED`
- Timeout (5 days from delivery date) → Transition to `TIMEOUT_PENDING`

**Allowed Actions:**
- Provider: Generate OTP, deliver vehicles, verify OTP
- Business: Inspect vehicles, share OTP if satisfied, reject if not satisfied
- Admin: Cancel contract, manually activate

**Key Attributes:**
```typescript
{
  status: 'PENDING_DELIVERY',
  vehiclesAssignedAt: timestamp,
  deliveryScheduledDate: date,
  deliveryLocation: object,
  otpAttempts: number,
  timeoutAt: timestamp (deliveryScheduledDate + 5 days)
}
```

**Business Rule Reference:** BR-014, BR-015

---

### 2.4 PARTIALLY_DELIVERED

**Description:** Some vehicles have been delivered and verified via OTP, but not all vehicles assigned to the contract have been delivered yet.

**Entry Conditions:**
- Contract status = `PENDING_DELIVERY`
- At least one vehicle delivery confirmed via OTP (`DeliveryConfirmedEvent` received)
- Not all vehicles have been delivered yet (quantityDelivered < quantityAwarded)

**Exit Conditions:**
- All vehicles delivered (last vehicle OTP verified) → Transition to `ACTIVE`
- Remaining vehicles not delivered within timeout → Transition to `TIMEOUT_PENDING` or remain `PARTIALLY_DELIVERED` until resolved
- All remaining vehicles rejected → Transition to `FAILED`

**Allowed Actions:**
- Provider: Continue delivering remaining vehicles, generate OTP for each vehicle
- Business: Inspect and accept/reject remaining vehicle deliveries
- System: Process partial activation (contract activates with delivered vehicles only)
- Admin: Cancel contract, manually activate with partial delivery

**Key Attributes:**
```typescript
{
  status: 'PARTIALLY_DELIVERED',
  firstDeliveryAt: timestamp,
  quantityAwarded: number,
  quantityDelivered: number,
  quantityActive: number,
  deliveredVehicleIds: string[],
  pendingVehicleIds: string[],
  lastDeliveryAt: timestamp,
  timeoutAt: timestamp (firstDeliveryAt + 5 days for remaining vehicles)
}
```

**Business Rule Reference:** BR-016, BR-016A

**Note:** Contracts in `PARTIALLY_DELIVERED` status are considered active for delivered vehicles. The contract operates with the subset of vehicles that have been delivered and verified. Settlement is calculated based on actual delivered vehicles.

---

### 2.5 ACTIVE

**Description:** Contract is active, all vehicles delivered and in use.

**Entry Conditions:**
- All vehicles delivered and verified via OTP (`DeliveryConfirmedEvent` received for all vehicles)
- All activation prerequisites met:
  - ✅ Escrow locked
  - ✅ Vehicles assigned
  - ✅ All deliveries confirmed
- OR contract status = `PARTIALLY_DELIVERED` and last remaining vehicle delivered

**Exit Conditions:**
- Contract end date reached + vehicle returned → Transition to `COMPLETED`
- `EarlyReturnApprovedEvent` received → Transition to `COMPLETED`
- `ContractTerminatedEvent` → Transition to `TERMINATED`
- Dispute created → Transition to `UNDER_DISPUTE`
- Contract alteration requested → Transition to `PENDING_ALTERATION`

**Allowed Actions:**
- Business: Request early return (7 day notice required), request contract alteration, raise dispute
- Provider: Request early return (7 day notice required), request contract alteration, raise dispute
- System: Process monthly settlements (for long-term contracts)
- Admin: Terminate contract, alter contract

**Key Attributes:**
```typescript
{
  status: 'ACTIVE',
  activatedAt: timestamp,
  actualStartDate: date,
  expectedEndDate: date,
  lastSettlementDate: date (for long-term contracts),
  nextSettlementDate: date (for long-term contracts),
  totalSettlementsPaid: number
}
```

**Business Rule Reference:** BR-016, BR-018

---

### 2.6 TIMEOUT_PENDING

**Description:** Contract stuck in pending state beyond timeout threshold, requires manual intervention.

**Entry Conditions:**
- Contract in any pending state for > 5 days
- System timeout job detected expired contract

**Exit Conditions:**
- Admin resolves issue → Transition to previous pending state or `FAILED`
- Business/Provider resolves issue → Transition to next pending state
- Admin cancels → Transition to `FAILED`

**Allowed Actions:**
- System: Send notifications to both parties
- Admin: Investigate, resolve, or cancel
- Business: Resolve blocking issue (deposit funds, etc.)
- Provider: Resolve blocking issue (assign vehicles, etc.)

**Key Attributes:**
```typescript
{
  status: 'TIMEOUT_PENDING',
  previousStatus: string,
  timeoutReachedAt: timestamp,
  timeoutReason: string,
  notificationsSent: number,
  lastNotificationAt: timestamp
}
```

**Business Rule Reference:** BR-017

---

### 2.7 ON_HOLD

**Description:** Contract temporarily suspended due to payment default or other issues. Awaiting provider decision on grace period.

**Entry Conditions:**
- Business failed to deposit for next billing cycle (payment default)
- Insurance expired during contract
- Dispute requires temporary suspension
- Admin manually places on hold

**Exit Conditions:**
- Provider grants grace period AND business deposits → Transition to `ACTIVE`
- Provider denies grace period OR grace period expires without payment → Transition to `TERMINATED`
- Issue resolved (for non-payment holds) → Transition to `ACTIVE`
- Admin manually reactivates or terminates

**Allowed Actions:**

**For Payment Default (Business failed to deposit):**
- **Provider (within 24 hours):** 
  - Choose "Collect vehicles now" (terminate immediately)
  - Choose "Grant grace period" (1-7 days) - provider bears risk
- **Business:** 
  - Wait for provider decision
  - If grace period granted: Deposit funds immediately
- **Admin:** Override decision, terminate, or manually resolve

**For Other Hold Reasons:**
- Business: Resolve issue (e.g., renew insurance)
- Provider: Update insurance
- Admin: Reactivate or terminate

**Notifications:**

**When ON_HOLD due to payment default:**
- **To Business:** "Payment overdue. Contract suspended. Awaiting provider's decision on whether to collect vehicles or grant grace period."
- **To Provider:** "Business [Name] failed to pay 30,000 ETB for Month 2. Choose: (1) Collect vehicles now (Recommended), OR (2) Grant grace period (1-7 days) - you bear the risk if business doesn't pay."

**If Provider Grants Grace Period:**
- **To Business:** "Provider granted you [X] days grace period. Deposit [Amount] + late fee by [Date] or vehicles will be collected. Total due: [Amount + Late Fee + Next Month Escrow]"
- **To Provider:** "Grace period active. Business has until [Date] to deposit. You will be paid for grace period days if business deposits."

**If Grace Period Expires Without Payment:**
- **To Business:** "Grace period expired. Contract terminated. Account suspended until debt cleared. Debt: [Amount] ETB."
- **To Provider:** "Business failed to pay. Contract terminated. Collect your vehicles. Outstanding debt recorded: [Amount] ETB."

**Key Attributes:**
```typescript
{
  status: 'ON_HOLD',
  holdReason: 'PAYMENT_DEFAULT' | 'INSURANCE_EXPIRED' | 'DISPUTE' | 'ADMIN',
  holdStartedAt: timestamp,
  previousStatus: string,
  
  // For payment default holds
  providerDecisionRequired: boolean,
  providerDecisionDeadline: timestamp (holdStartedAt + 24 hours),
  gracePeriodGranted: boolean | null,
  gracePeriodDays: number | null,
  gracePeriodDeadline: timestamp | null,
  gracePeriodAmount: number | null,
  lateFeeAmount: number | null
}
```

**Business Rule Reference:** BR-012, BR-028

---

### 2.8 COMPLETED

**Description:** Contract successfully completed, all obligations fulfilled.

**Entry Conditions:**
- Contract status = `ACTIVE`
- Contract end date reached
- Vehicles returned and verified
- No outstanding disputes

**Exit Conditions:**
- None (final state)

**Allowed Actions:**
- System: Process final settlement
- Business: View contract history, download documents
- Provider: View settlement details
- Admin: View audit trail

**Key Attributes:**
```typescript
{
  status: 'COMPLETED',
  completedAt: timestamp,
  actualEndDate: date,
  totalDaysActive: number,
  finalSettlementAmount: number,
  finalSettlementProcessed: boolean,
  vehiclesReturned: boolean,
  completionType: 'NORMAL' | 'EARLY_RETURN'
}
```

**Business Rule Reference:** BR-018, BR-030

---

### 2.9 TERMINATED

**Description:** Contract cancelled or terminated before normal completion.

**Entry Conditions:**
- Contract terminated by business/provider/admin
- Mutual agreement to cancel
- Force majeure or breach of contract

**Exit Conditions:**
- None (final state)

**Allowed Actions:**
- System: Process refunds/settlements
- Business: View termination details
- Provider: View termination details
- Admin: Review termination

**Key Attributes:**
```typescript
{
  status: 'TERMINATED',
  terminatedAt: timestamp,
  terminationReason: string,
  terminatedBy: 'BUSINESS' | 'PROVIDER' | 'ADMIN' | 'SYSTEM',
  daysActive: number,
  refundProcessed: boolean,
  penaltyApplied: boolean,
  penaltyAmount: number
}
```

**Business Rule Reference:** BR-020, BR-021

---

### 2.10 FAILED

**Description:** Contract setup failed, could not be activated.

**Entry Conditions:**
- Escrow lock failed (after all retries)
- Provider rejected contract
- Delivery rejected by business
- Critical validation failure

**Exit Conditions:**
- None (final state)

**Allowed Actions:**
- System: Release any locked escrow
- Business: Create new RFQ or re-award bid
- Provider: None
- Admin: Review failure reason

**Key Attributes:**
```typescript
{
  status: 'FAILED',
  failedAt: timestamp,
  failureReason: string,
  failureStage: 'ESCROW' | 'VEHICLE_ASSIGNMENT' | 'DELIVERY',
  refundProcessed: boolean
}
```

---

### 2.11 UNDER_DISPUTE

**Description:** Contract has active dispute, certain actions blocked until resolution.

**Entry Conditions:**
- Dispute created by business or provider
- Dispute category affects contract status

**Exit Conditions:**
- Dispute resolved → Transition to previous state or `ACTIVE`
- Dispute resolved with termination → Transition to `TERMINATED`

**Allowed Actions:**
- Business/Provider: Submit evidence, add comments
- System: Continue monthly settlements (if applicable)
- Admin: Resolve dispute
- Both parties: Limited actions based on dispute type

**Key Attributes:**
```typescript
{
  status: 'UNDER_DISPUTE',
  disputeId: string,
  disputeCreatedAt: timestamp,
  previousStatus: string,
  disputeCategory: string,
  blockedActions: string[]
}
```

**Business Rule Reference:** BR-034, BR-035, BR-036

---

### 2.12 PENDING_ALTERATION

**Description:** Contract modification requested, awaiting approval.

**Entry Conditions:**
- Business or provider requested contract alteration
- Contract status = `ACTIVE`

**Exit Conditions:**
- Alteration approved by both parties → Transition to `ALTERED`
- Alteration rejected → Transition to `ACTIVE`

**Allowed Actions:**
- Business/Provider: Review alteration, approve/reject
- Admin: Review alteration
- System: Continue existing contract terms

**Key Attributes:**
```typescript
{
  status: 'PENDING_ALTERATION',
  alterationRequestedAt: timestamp,
  requestedBy: 'BUSINESS' | 'PROVIDER',
  alterationType: string,
  alterationDetails: object,
  businessApproval: boolean | null,
  providerApproval: boolean | null
}
```

---

### 2.13 ALTERED

**Description:** Contract has been modified, new terms in effect.

**Entry Conditions:**
- Contract alteration approved by both parties
- Contract status = `PENDING_ALTERATION`

**Exit Conditions:**
- Continue normal lifecycle → Transition to `ACTIVE`
- Contract ends → Transition to `COMPLETED`

**Allowed Actions:**
- System: Apply new terms, process adjustments
- Business/Provider: View updated contract
- Admin: View alteration history

**Key Attributes:**
```typescript
{
  status: 'ALTERED',
  alteredAt: timestamp,
  alterationType: string,
  previousTerms: object,
  newTerms: object,
  financialAdjustment: number
}
```

**Note:** After alteration is processed, contract typically returns to `ACTIVE` status with updated terms.

---

## 3. STATE TRANSITION MATRIX

### 3.1 Valid State Transitions

| From State | To State | Trigger | Event |
|-----------|----------|---------|-------|
| `PENDING_ESCROW` | `PENDING_VEHICLE_ASSIGNMENT` | Escrow locked | `EscrowLockedEvent` |
| `PENDING_ESCROW` | `TIMEOUT_PENDING` | 5 days elapsed | System timeout job |
| `PENDING_ESCROW` | `FAILED` | Escrow lock failed (all retries) | `EscrowLockFailedEvent` |
| `PENDING_VEHICLE_ASSIGNMENT` | `PENDING_DELIVERY` | All vehicles assigned | `VehicleAssignedEvent` |
| `PENDING_VEHICLE_ASSIGNMENT` | `TIMEOUT_PENDING` | 5 days elapsed | System timeout job |
| `PENDING_VEHICLE_ASSIGNMENT` | `FAILED` | Provider rejected | `ProviderRejectedAwardEvent` |
| `PENDING_DELIVERY` | `PARTIALLY_DELIVERED` | First vehicle(s) delivered (if multiple vehicles) | `DeliveryConfirmedEvent` (partial) |
| `PENDING_DELIVERY` | `ACTIVE` | All vehicles delivered in one batch | `DeliveryConfirmedEvent` (all) |
| `PENDING_DELIVERY` | `TIMEOUT_PENDING` | 5 days elapsed | System timeout job |
| `PENDING_DELIVERY` | `FAILED` | Delivery rejected | `DeliveryRejectedEvent` |
| `PARTIALLY_DELIVERED` | `ACTIVE` | Last remaining vehicle(s) delivered | `DeliveryConfirmedEvent` (completion) |
| `PARTIALLY_DELIVERED` | `TIMEOUT_PENDING` | Remaining vehicles not delivered (5 days) | System timeout job |
| `PARTIALLY_DELIVERED` | `FAILED` | All remaining vehicles rejected | `DeliveryRejectedEvent` (all remaining) |
| `TIMEOUT_PENDING` | Previous pending state | Issue resolved | Manual resolution |
| `TIMEOUT_PENDING` | `FAILED` | Cannot be resolved | Admin cancellation |
| `ACTIVE` | `PARTIALLY_RETURNED` | First vehicle returned | `VehicleReturnedEvent` |
| `PARTIALLY_RETURNED` | `COMPLETED` | All vehicles returned | All line items completed |
| `ACTIVE` | `COMPLETED` | Contract period ended, all vehicles returned | `ContractCompletedEvent` |
| `ACTIVE` | `COMPLETED` | Early return approved, all vehicles returned | `EarlyReturnApprovedEvent` |
| `ACTIVE` | `TERMINATED` | Contract terminated | `ContractTerminatedEvent` |
| `ACTIVE` | `UNDER_DISPUTE` | Dispute created | `DisputeCreatedEvent` |
| `ACTIVE` | `PENDING_ALTERATION` | Alteration requested | `ContractAlterationRequestedEvent` |
| `ACTIVE` | `ON_HOLD` | Payment/insurance issue | System check |
| `ON_HOLD` | `ACTIVE` | Issue resolved | System verification |
| `ON_HOLD` | `TERMINATED` | Cannot resolve | Admin decision |
| `UNDER_DISPUTE` | `ACTIVE` | Dispute resolved | `DisputeResolvedEvent` |
| `UNDER_DISPUTE` | `TERMINATED` | Dispute resolved with termination | `DisputeResolvedEvent` |
| `PENDING_ALTERATION` | `ALTERED` | Both parties approved | `ContractAlteredEvent` |
| `PENDING_ALTERATION` | `ACTIVE` | Alteration rejected | Rejection action |
| `ALTERED` | `ACTIVE` | Adjustments processed | System processing |

### 3.2 Invalid State Transitions

**Cannot transition from completion states:**
- `COMPLETED` → Any state ❌
- `TERMINATED` → Any state ❌
- `FAILED` → Any state ❌

**Cannot skip pending states:**
- `PENDING_ESCROW` → `PENDING_DELIVERY` ❌ (must go through `PENDING_VEHICLE_ASSIGNMENT`)
- `PENDING_ESCROW` → `ACTIVE` ❌

---

## 4. STATE MACHINE DIAGRAM

### 4.1 Happy Path Flow

```
┌────────────────┐
│ BidAwardedEvent│
└───────┬────────┘
        │
        ▼
┌─────────────────────┐
│  PENDING_ESCROW     │
│                     │
│ Waiting for escrow  │
│ lock                │
└──────────┬──────────┘
           │ EscrowLockedEvent
           ▼
┌─────────────────────────────┐
│ PENDING_VEHICLE_ASSIGNMENT  │
│                             │
│ Waiting for provider to     │
│ assign vehicles             │
└──────────┬──────────────────┘
           │ VehicleAssignedEvent
           ▼
┌─────────────────────┐
│ PENDING_DELIVERY    │
│                     │
│ Waiting for OTP     │
│ verification        │
└──────────┬──────────┘
           │ DeliveryConfirmedEvent
           ▼
┌─────────────────────┐
│      ACTIVE         │
│                     │
│ Contract running    │
│ (Monthly settlements│
│ for long contracts) │
└──────────┬──────────┘
           │ ContractCompletedEvent
           ▼
┌─────────────────────┐
│    COMPLETED        │
│                     │
│ Final settlement    │
│ processed           │
└─────────────────────┘
```

### 4.2 Complete State Diagram with Error Paths

```
                    ┌──────────────────┐
                    │ BidAwardedEvent  │
                    └────────┬─────────┘
                             │
                             ▼
        ┌────────────────────────────────────────┐
        │         PENDING_ESCROW                 │
        │  Retry escrow lock (5 attempts)        │
        └─┬──────────┬────────────────┬─────────┘
          │          │                │
  EscrowLocked  Timeout (5d)    Lock Failed (all retries)
          │          │                │
          │          ▼                ▼
          │   ┌─────────────────┐  ┌──────────┐
          │   │TIMEOUT_PENDING  │  │ FAILED   │
          │   │                 │  └──────────┘
          │   └─────────────────┘
          │
          ▼
        ┌────────────────────────────────────────┐
        │   PENDING_VEHICLE_ASSIGNMENT           │
        │   Provider assigns vehicles            │
        └─┬──────────┬────────────────┬─────────┘
          │          │                │
  Vehicles     Timeout (5d)    Provider Rejects
  Assigned       │                │
          │          │                │
          │          ▼                ▼
          │   ┌─────────────────┐  ┌──────────┐
          │   │TIMEOUT_PENDING  │  │ FAILED   │
          │   └─────────────────┘  └──────────┘
          │
          ▼
        ┌────────────────────────────────────────┐
        │      PENDING_DELIVERY                  │
        │      OTP verification                  │
        └─┬──────────┬────────────────┬─────────┘
          │          │                │
  First Vehicle  Timeout (5d)   Business Rejects
  Delivered (if  │                │
  multiple)      │                │
          │          ▼                ▼
          │   ┌─────────────────┐  ┌──────────┐
          │   │TIMEOUT_PENDING  │  │ FAILED   │
          │   └─────────────────┘  └──────────┘
          │
          ▼
        ┌────────────────────────────────────────┐
        │    PARTIALLY_DELIVERED (optional)      │
        │    Some vehicles delivered, waiting    │
        │    for remaining vehicles              │
        └─┬──────────┬────────────────┬─────────┘
          │          │                │
  All Vehicles  Timeout (5d)   Remaining
  Delivered      │            Rejected
          │          │                │
          │          ▼                ▼
          │   ┌─────────────────┐  ┌──────────┐
          │   │TIMEOUT_PENDING  │  │ FAILED   │
          │   └─────────────────┘  └──────────┘
          │
          ▼
        ┌────────────────────────────────────────┐
        │           ACTIVE                       │
        │     Monthly settlements                │
        │     (for long contracts)               │
        └─┬────┬──────┬──────┬──────────────┬───┘
          │    │      │      │              │
    Normal End │  Dispute Payment/Ins  Alteration
          │  Early  Created  Issue      Request
          │  Return   │      │              │
          │    │      │      │              │
          │    │      ▼      ▼              ▼
          │    │  ┌──────────────┐  ┌──────────────┐
          │    │  │UNDER_DISPUTE │  │PENDING_      │
          │    │  │              │  │ALTERATION    │
          │    │  └──────┬───────┘  └───┬──────────┘
          │    │         │              │
          │    │    Resolved        Approved
          │    │         │              │
          │    │         └──────►┌──────▼──────┐
          │    │                 │   ALTERED   │
          │    │                 └──────┬──────┘
          │    │                        │
          │    │                        ▼
          │    │                  Back to ACTIVE
          │    │
          │    └────────────┐
          │                 │
          ▼                 ▼
        ┌─────────────────────┐
        │     COMPLETED       │
        │                     │
        │ Final settlement    │
        └─────────────────────┘
        
        
        Termination Path:
        ACTIVE → TERMINATED (forced cancellation)
        ON_HOLD → TERMINATED (cannot resolve)
```

---

## 5. TIMEOUT RULES

### 5.1 Timeout Configuration

| State | Timeout Duration | Action on Timeout |
|-------|-----------------|-------------------|
| `PENDING_ESCROW` | 5 days from contract creation | → `TIMEOUT_PENDING` + Notify both parties |
| `PENDING_VEHICLE_ASSIGNMENT` | 5 days from escrow lock | → `TIMEOUT_PENDING` + Notify both parties |
| `PENDING_DELIVERY` | 5 days from scheduled delivery date | → `TIMEOUT_PENDING` + Notify both parties |
| `PARTIALLY_DELIVERED` | 5 days from first delivery | → `TIMEOUT_PENDING` + Notify both parties (remaining vehicles) |
| `TIMEOUT_PENDING` | No timeout | Manual intervention required |
| `ON_HOLD` | 7 days from hold start | → `TERMINATED` (if not resolved) |
| `PENDING_ALTERATION` | 3 days from request | Auto-reject alteration, → `ACTIVE` |

### 5.2 Timeout Check Job

**Runs:** Every 1 hour

**Process:**
```typescript
@Cron('0 * * * *') // Every hour
async checkContractTimeouts() {
  const now = new Date();
  
  // Check PENDING_ESCROW timeouts
  const pendingEscrowTimeouts = await this.contractRepository.find({
    status: 'PENDING_ESCROW',
    createdAt: LessThan(new Date(now.getTime() - 5 * 24 * 60 * 60 * 1000))
  });
  
  for (const contract of pendingEscrowTimeouts) {
    await this.transitionToTimeoutPending(contract, 'ESCROW_LOCK_TIMEOUT');
  }
  
  // Check PENDING_VEHICLE_ASSIGNMENT timeouts
  const pendingVehicleTimeouts = await this.contractRepository.find({
    status: 'PENDING_VEHICLE_ASSIGNMENT',
    escrowLockedAt: LessThan(new Date(now.getTime() - 5 * 24 * 60 * 60 * 1000))
  });
  
  for (const contract of pendingVehicleTimeouts) {
    await this.transitionToTimeoutPending(contract, 'VEHICLE_ASSIGNMENT_TIMEOUT');
  }
  
  // Check PENDING_DELIVERY timeouts
  const pendingDeliveryTimeouts = await this.contractRepository.find({
    status: 'PENDING_DELIVERY',
    deliveryScheduledDate: LessThan(new Date(now.getTime() - 5 * 24 * 60 * 60 * 1000))
  });
  
  for (const contract of pendingDeliveryTimeouts) {
    await this.transitionToTimeoutPending(contract, 'DELIVERY_TIMEOUT');
  }
  
  // Check PARTIALLY_DELIVERED timeouts (remaining vehicles not delivered)
  const partiallyDeliveredTimeouts = await this.contractRepository.find({
    status: 'PARTIALLY_DELIVERED',
    firstDeliveryAt: LessThan(new Date(now.getTime() - 5 * 24 * 60 * 60 * 1000))
  });
  
  for (const contract of partiallyDeliveredTimeouts) {
    await this.transitionToTimeoutPending(contract, 'PARTIAL_DELIVERY_TIMEOUT');
  }
  
  // Check ON_HOLD timeouts
  const onHoldTimeouts = await this.contractRepository.find({
    status: 'ON_HOLD',
    holdStartedAt: LessThan(new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000))
  });
  
  for (const contract of onHoldTimeouts) {
    await this.terminateContract(contract, 'HOLD_TIMEOUT_UNRESOLVED');
  }
}
```

### 5.3 Timeout Notifications

**Notification Schedule:**

| Timeout Type | Notification Timing |
|-------------|---------------------|
| Approaching timeout | 24 hours before timeout |
| Timeout reached | Immediately when timeout detected |
| Timeout pending | Daily reminder until resolved |

**Notification Content:**
- Contract ID and details
- Current status and blocking issue
- Action required from user
- Deadline for resolution
- Consequences of non-resolution

---

## 6. STATE VALIDATION RULES

### 6.1 Validation Rules by State

#### PENDING_ESCROW Validations
```typescript
function validatePendingEscrow(contract: Contract): ValidationResult {
  const errors = [];
  
  // Must have valid business and provider
  if (!contract.businessId || !contract.providerId) {
    errors.push('Missing business or provider ID');
  }
  
  // Must have escrow amount
  if (!contract.escrowAmount || contract.escrowAmount <= 0) {
    errors.push('Invalid escrow amount');
  }
  
  // Must have valid rental period
  if (!contract.rentalPeriod || contract.rentalPeriod.startDate > contract.rentalPeriod.endDate) {
    errors.push('Invalid rental period');
  }
  
  return { valid: errors.length === 0, errors };
}
```

#### PENDING_VEHICLE_ASSIGNMENT Validations
```typescript
function validatePendingVehicleAssignment(contract: Contract): ValidationResult {
  const errors = [];
  
  // Escrow must be locked
  if (!contract.escrowLockedAt) {
    errors.push('Escrow not locked');
  }
  
  // Must have escrow transaction ID
  if (!contract.escrowTransactionId) {
    errors.push('Missing escrow transaction ID');
  }
  
  return { valid: errors.length === 0, errors };
}
```

#### PENDING_DELIVERY Validations
```typescript
function validatePendingDelivery(contract: Contract): ValidationResult {
  const errors = [];
  
  // Must have assigned vehicles
  if (contract.assignedVehicles < contract.requiredVehicles) {
    errors.push('Not all vehicles assigned');
  }
  
  // Must have delivery scheduled
  if (!contract.deliveryScheduledDate) {
    errors.push('Delivery not scheduled');
  }
  
  // All vehicles must have valid insurance
  for (const vehicleId of contract.assignedVehicleIds) {
    const vehicle = await getVehicle(vehicleId);
    if (!vehicle.insuranceValid) {
      errors.push(`Vehicle ${vehicleId} insurance invalid`);
    }
  }
  
  return { valid: errors.length === 0, errors };
}
```

#### ACTIVE Validations
```typescript
function validateActive(contract: Contract): ValidationResult {
  const errors = [];
  
  // Must have all activation prerequisites
  if (!contract.escrowLockedAt) {
    errors.push('Escrow not locked');
  }
  
  if (!contract.vehiclesDeliveredAt) {
    errors.push('Vehicles not delivered');
  }
  
  if (!contract.activatedAt) {
    errors.push('Missing activation timestamp');
  }
  
  // For long-term contracts, validate monthly settlements
  if (contract.rentalPeriod.durationDays >= 30) {
    const monthsSinceStart = calculateMonthsSinceStart(contract.activatedAt);
    if (contract.totalSettlementsPaid < monthsSinceStart) {
      errors.push('Missing monthly settlements');
    }
  }
  
  return { valid: errors.length === 0, errors };
}
```

### 6.2 Pre-Transition Validation

**Before any state transition:**
```typescript
async function validateStateTransition(
  contract: Contract, 
  fromState: ContractState, 
  toState: ContractState
): Promise<ValidationResult> {
  
  // Check if transition is valid
  const validTransitions = STATE_TRANSITION_MATRIX[fromState];
  if (!validTransitions.includes(toState)) {
    return { 
      valid: false, 
      errors: [`Invalid transition from ${fromState} to ${toState}`] 
    };
  }
  
  // Validate target state prerequisites
  const targetStateValidation = await validateState(contract, toState);
  if (!targetStateValidation.valid) {
    return targetStateValidation;
  }
  
  return { valid: true, errors: [] };
}
```

---

## 7. ERROR STATES & RECOVERY

### 7.1 Error State: FAILED

**Recovery Options:**

1. **Escrow Lock Failure:**
```typescript
async function recoverFromEscrowFailure(contract: Contract) {
  // Notify business to deposit funds
  await sendNotification(contract.businessId, {
    type: 'ESCROW_LOCK_FAILED',
    message: 'Please deposit funds to retry contract activation'
  });
  
  // Allow manual retry by business
  // Option 1: Business deposits funds → System retries escrow lock
  // Option 2: Business cancels contract → Release bid for re-award
}
```

2. **Delivery Rejection:**
```typescript
async function recoverFromDeliveryRejection(contract: Contract) {
  // Give provider option to:
  // 1. Replace vehicles
  // 2. Cancel contract
  
  await sendNotification(contract.providerId, {
    type: 'DELIVERY_REJECTED',
    message: 'Business rejected delivery. Replace vehicles or cancel?',
    actions: ['REPLACE_VEHICLES', 'CANCEL_CONTRACT']
  });
}
```

### 7.2 Error State: TIMEOUT_PENDING

**Recovery Steps:**

1. **Identify blocking issue:**
```typescript
async function identifyTimeoutReason(contract: Contract): Promise<string> {
  switch (contract.previousStatus) {
    case 'PENDING_ESCROW':
      const wallet = await getWallet(contract.businessId);
      if (wallet.balance < contract.escrowAmount) {
        return 'INSUFFICIENT_FUNDS';
      }
      return 'ESCROW_LOCK_TECHNICAL_ISSUE';
      
    case 'PENDING_VEHICLE_ASSIGNMENT':
      const assignedCount = contract.assignedVehicles;
      if (assignedCount === 0) {
        return 'NO_VEHICLES_ASSIGNED';
      }
      return 'PARTIAL_VEHICLE_ASSIGNMENT';
      
    case 'PENDING_DELIVERY':
      return 'DELIVERY_NOT_CONFIRMED';
  }
}
```

2. **Provide resolution path:**
```typescript
async function provideResolutionPath(contract: Contract, reason: string) {
  const resolutionActions = {
    'INSUFFICIENT_FUNDS': {
      party: 'BUSINESS',
      action: 'Deposit funds to wallet',
      deadline: '48 hours'
    },
    'NO_VEHICLES_ASSIGNED': {
      party: 'PROVIDER',
      action: 'Assign vehicles to contract',
      deadline: '48 hours'
    },
    'DELIVERY_NOT_CONFIRMED': {
      party: 'BOTH',
      action: 'Complete delivery and OTP verification',
      deadline: '48 hours'
    }
  };
  
  const resolution = resolutionActions[reason];
  await sendResolutionNotification(contract, resolution);
}
```

### 7.3 Error State: ON_HOLD

**Auto-Recovery Checks:**

```typescript
@Cron('0 */4 * * *') // Every 4 hours
async function checkOnHoldRecovery() {
  const onHoldContracts = await this.contractRepository.find({
    status: 'ON_HOLD'
  });
  
  for (const contract of onHoldContracts) {
    const canRecover = await this.checkRecoveryConditions(contract);
    
    if (canRecover) {
      // Auto-recover
      await this.transitionState(contract, 'ACTIVE');
      await this.publishEvent({
        eventType: 'ContractReactivatedEvent',
        payload: { contractId: contract.id, reason: contract.holdReason }
      });
    }
  }
}

async function checkRecoveryConditions(contract: Contract): Promise<boolean> {
  switch (contract.holdReason) {
    case 'INSUFFICIENT_WALLET_BALANCE':
      const wallet = await getWallet(contract.businessId);
      return wallet.balance >= contract.monthlyPayment;
      
    case 'INSURANCE_EXPIRED':
      const vehicles = await getContractVehicles(contract.id);
      return vehicles.every(v => v.insuranceValid);
      
    default:
      return false; // Requires manual review
  }
}
```

---

## 8. STATE CHANGE EVENT FLOW

### 8.1 State Transition Event Publishing

**Every state change publishes an event:**

```typescript
async function transitionContractState(
  contractId: string,
  fromState: ContractState,
  toState: ContractState,
  reason: string,
  metadata: object
): Promise<void> {
  
  // 1. Validate transition
  const validation = await validateStateTransition(contract, fromState, toState);
  if (!validation.valid) {
    throw new Error(`Invalid transition: ${validation.errors.join(', ')}`);
  }
  
  // 2. Update contract state
  await this.contractRepository.update(contractId, {
    status: toState,
    previousStatus: fromState,
    statusChangedAt: new Date(),
    statusChangeReason: reason
  });
  
  // 3. Publish state change event
  await this.eventPublisher.publish({
    eventType: 'ContractStateChangedEvent',
    aggregateId: contractId,
    payload: {
      contractId,
      fromState,
      toState,
      reason,
      changedAt: new Date(),
      metadata
    }
  });
  
  // 4. Publish specific state events
  switch (toState) {
    case 'ACTIVE':
      await this.publishEvent({ eventType: 'ContractActivatedEvent', ... });
      break;
    case 'COMPLETED':
      await this.publishEvent({ eventType: 'ContractCompletedEvent', ... });
      break;
    case 'FAILED':
      await this.publishEvent({ eventType: 'ContractFailedEvent', ... });
      break;
    // ... other states
  }
  
  // 5. Trigger state-specific actions
  await this.executeStateActions(contractId, toState);
}
```

### 8.2 State-Specific Actions

```typescript
async function executeStateActions(contractId: string, state: ContractState) {
  switch (state) {
    case 'PENDING_ESCROW':
      // Schedule escrow retry
      await this.scheduleEscrowRetry(contractId);
      break;
      
    case 'ACTIVE':
      // Schedule first settlement (if long-term contract)
      await this.scheduleMonthlySettlement(contractId);
      break;
      
    case 'TIMEOUT_PENDING':
      // Send timeout notifications
      await this.sendTimeoutNotifications(contractId);
      break;
      
    case 'COMPLETED':
      // Process final settlement
      await this.processFinalSettlement(contractId);
      break;
      
    case 'FAILED':
      // Release escrow if locked
      await this.releaseEscrow(contractId);
      break;
  }
}
```

---

## 9. BUSINESS RULES MAPPING

### 9.1 State to Business Rule Mapping

| State | Primary Business Rules | Secondary Rules |
|-------|----------------------|-----------------|
| `PENDING_ESCROW` | BR-010, BR-011 | BR-008, BR-009 |
| `PENDING_VEHICLE_ASSIGNMENT` | BR-013 | BR-004 |
| `PENDING_DELIVERY` | BR-014, BR-015 | BR-016 |
| `PARTIALLY_DELIVERED` | BR-016, BR-016A | BR-014, BR-015 |
| `TIMEOUT_PENDING` | BR-017 | - |
| `ACTIVE` | BR-016, BR-018 | BR-012, BR-028 |
| `ON_HOLD` | BR-012, BR-028 | - |
| `COMPLETED` | BR-018, BR-030, BR-031 | BR-033 |
| `TERMINATED` | BR-020, BR-021 | - |
| `FAILED` | BR-009, BR-011 | - |
| `UNDER_DISPUTE` | BR-034, BR-035, BR-036, BR-037 | - |
| `PENDING_ALTERATION` | - | - |
| `ALTERED` | - | - |

### 9.2 State Enforcement of Business Rules

**Example: ACTIVE state enforces wallet balance rule (BR-012)**

```typescript
@Cron('0 0 * * *') // Daily check at midnight
async function enforceActiveContractRules() {
  const activeContracts = await this.contractRepository.find({
    status: 'ACTIVE'
  });
  
  for (const contract of activeContracts) {
    // BR-012: Check if current escrow period ends today
    const escrowPeriodEndsToday = isEscrowPeriodEndingToday(contract);
    
    if (escrowPeriodEndsToday) {
      const wallet = await getWallet(contract.businessId);
      const nextPayment = calculateNextPayment(contract);
      
      if (wallet.balance < nextPayment) {
        // Place contract on hold - payment default
        await this.transitionState(contract, 'ON_HOLD', {
          reason: 'PAYMENT_DEFAULT',
          requiredAmount: nextPayment,
          currentBalance: wallet.balance,
          providerDecisionRequired: true,
          providerDecisionDeadline: addHours(new Date(), 24)
        });
        
        // Notify business - contract suspended
        await sendNotification(contract.businessId, {
          type: 'CONTRACT_SUSPENDED_PAYMENT_DEFAULT',
          message: `Payment overdue. Contract suspended. Required: ${nextPayment} ETB. Awaiting provider's decision.`,
          severity: 'CRITICAL'
        });
        
        // Notify provider - request decision
        await sendNotification(contract.providerId, {
          type: 'PROVIDER_DECISION_REQUIRED',
          message: `Business ${contract.businessName} failed to pay ${nextPayment} ETB for next period.`,
          actions: [
            {
              id: 'COLLECT_NOW',
              label: 'Collect Vehicles Now (Recommended)',
              description: 'Terminate contract and collect vehicles immediately'
            },
            {
              id: 'GRANT_GRACE',
              label: 'Grant Grace Period (1-7 days)',
              description: 'You bear the risk if business doesn\'t pay during grace period',
              requiresInput: 'gracePeriodDays',
              inputRange: [1, 7]
            }
          ],
          deadline: addHours(new Date(), 24)
        });
        
        // If provider doesn't respond within 24 hours, auto-terminate
        await this.scheduleJob({
          jobType: 'AUTO_TERMINATE_ON_PROVIDER_NO_RESPONSE',
          contractId: contract.id,
          executeAt: addHours(new Date(), 24)
        });
      }
    }
  }
}

// Handler for provider decision
async function handleProviderGracePeriodDecision(
  contractId: string,
  decision: 'COLLECT_NOW' | 'GRANT_GRACE',
  gracePeriodDays?: number
) {
  const contract = await this.contractRepository.findById(contractId);
  
  if (decision === 'COLLECT_NOW') {
    // Terminate immediately
    await this.transitionState(contract, 'TERMINATED', {
      reason: 'PAYMENT_DEFAULT_PROVIDER_TERMINATED',
      terminatedBy: 'PROVIDER'
    });
    
    await sendNotification(contract.businessId, {
      type: 'CONTRACT_TERMINATED',
      message: 'Provider has chosen to collect vehicles due to payment default.'
    });
    
  } else if (decision === 'GRANT_GRACE') {
    // Grant grace period
    const dailyRate = contract.totalAmount / contract.totalDays;
    const gracePeriodAmount = dailyRate * gracePeriodDays;
    const lateFee = gracePeriodAmount * 0.05; // 5% late fee
    const nextMonthEscrow = calculateNextPayment(contract);
    const totalDue = gracePeriodAmount + lateFee + nextMonthEscrow;
    
    await this.contractRepository.update(contractId, {
      gracePeriodGranted: true,
      gracePeriodDays,
      gracePeriodDeadline: addDays(new Date(), gracePeriodDays),
      gracePeriodAmount,
      lateFeeAmount: lateFee
    });
    
    await sendNotification(contract.businessId, {
      type: 'GRACE_PERIOD_GRANTED',
      message: `Provider granted you ${gracePeriodDays} days grace period. Deposit ${totalDue} ETB by ${formatDate(addDays(new Date(), gracePeriodDays))} or vehicles will be collected.`,
      breakdown: {
        gracePeriodDays: gracePeriodAmount,
        lateFee: lateFee,
        nextMonthEscrow: nextMonthEscrow,
        total: totalDue
      }
    });
    
    await sendNotification(contract.providerId, {
      type: 'GRACE_PERIOD_ACTIVE',
      message: `Grace period active for ${gracePeriodDays} days. Business must deposit by ${formatDate(addDays(new Date(), gracePeriodDays))}. If business pays, you'll receive ${gracePeriodAmount + lateFee} ETB for grace period.`
    });
    
    // Schedule auto-termination if business doesn't pay
    await this.scheduleJob({
      jobType: 'AUTO_TERMINATE_ON_GRACE_PERIOD_EXPIRY',
      contractId: contract.id,
      executeAt: addDays(new Date(), gracePeriodDays)
    });
  }
}
```

---

## APPENDIX A: State Transition Examples

### A.1 Example 1: Successful Contract Activation

```
Timeline:

Day 0, 10:00 AM: Business awards bid
  → Contract created with status: PENDING_ESCROW

Day 0, 10:01 AM: Finance locks escrow
  → Contract status: PENDING_VEHICLE_ASSIGNMENT

Day 0, 11:00 AM: Provider assigns 3 vehicles
  → Contract status: PENDING_DELIVERY

Day 2, 09:00 AM: Provider delivers vehicles, generates OTP
  → Business inspects, shares OTP
  → Provider verifies OTP
  → Contract status: ACTIVE

Day 30, 23:59 PM: Month-end settlement processed
  → Provider receives payment for first month

Day 90, 18:00 PM: Contract period ends, vehicles returned
  → Contract status: COMPLETED
  → Final settlement processed
```

### A.2 Example 2: Contract with Escrow Failure

```
Timeline:

Day 0, 10:00 AM: Business awards bid
  → Contract created with status: PENDING_ESCROW

Day 0, 10:01 AM: Finance attempts escrow lock
  → FAILED: Insufficient balance
  → Retry attempt 1 (after 30 min)

Day 0, 10:31 AM: Retry attempt 1
  → FAILED: Still insufficient balance
  → Retry attempt 2 (after 1 hour)

Day 0, 11:31 AM: Retry attempt 2
  → FAILED
  → Continue retries...

Day 5, 10:00 AM: Timeout reached (5 days elapsed)
  → Contract status: TIMEOUT_PENDING
  → Notifications sent to business and provider

Day 6, 14:00 PM: Business deposits funds
  → Manual escrow lock triggered
  → Contract status: PENDING_VEHICLE_ASSIGNMENT
  → Continues normal flow
```

### A.3 Example 3: Contract with Early Return

```
Timeline:

Day 0: Contract activated (90-day rental)
  → Contract status: ACTIVE

Day 30: Month-end settlement processed
  → Provider receives first payment

Day 50: Business requests early return (7 days notice)
  → Contract status: PENDING_ALTERATION
  → Provider receives notification

Day 51: Provider approves early return
  → Contract status: ACTIVE (continues until return date)

Day 57: Vehicles returned
  → Contract status: COMPLETED
  → Final settlement with penalty processed:
    - Remaining days: 33
    - Penalty: 0% (7 days notice)
    - Business receives refund for 33 days
    - Provider receives payment for days used
```

---

## APPENDIX B: State Machine Implementation Guide

### B.1 Database Schema for Contract State

```sql
CREATE TABLE contracts_schema.contracts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bid_id UUID NOT NULL,
  rfq_id UUID NOT NULL,
  business_id UUID NOT NULL,
  provider_id UUID NOT NULL,
  
  -- State management
  status VARCHAR(50) NOT NULL,
  previous_status VARCHAR(50),
  status_changed_at TIMESTAMP,
  status_change_reason TEXT,
  
  -- Pending escrow
  escrow_amount DECIMAL(15,2) NOT NULL,
  escrow_locked_at TIMESTAMP,
  escrow_transaction_id UUID,
  escrow_lock_attempts INTEGER DEFAULT 0,
  last_escrow_attempt_at TIMESTAMP,
  
  -- Pending vehicle assignment
  required_vehicles INTEGER NOT NULL,
  assigned_vehicles INTEGER DEFAULT 0,
  assigned_vehicle_ids UUID[],
  
  -- Pending delivery
  delivery_scheduled_date TIMESTAMP,
  delivery_location JSONB,
  otp_attempts INTEGER DEFAULT 0,
  
  -- Active
  activated_at TIMESTAMP,
  actual_start_date DATE,
  expected_end_date DATE,
  last_settlement_date DATE,
  next_settlement_date DATE,
  total_settlements_paid INTEGER DEFAULT 0,
  
  -- Timeout management
  timeout_at TIMESTAMP,
  timeout_reached_at TIMESTAMP,
  timeout_notifications_sent INTEGER DEFAULT 0,
  
  -- Completion
  completed_at TIMESTAMP,
  actual_end_date DATE,
  total_days_active INTEGER,
  final_settlement_amount DECIMAL(15,2),
  final_settlement_processed BOOLEAN DEFAULT false,
  
  -- Termination
  terminated_at TIMESTAMP,
  termination_reason TEXT,
  terminated_by VARCHAR(20),
  
  -- Failure
  failed_at TIMESTAMP,
  failure_reason TEXT,
  failure_stage VARCHAR(50),
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_contracts_status ON contracts_schema.contracts(status);
CREATE INDEX idx_contracts_business_status ON contracts_schema.contracts(business_id, status);
CREATE INDEX idx_contracts_provider_status ON contracts_schema.contracts(provider_id, status);
CREATE INDEX idx_contracts_timeout ON contracts_schema.contracts(timeout_at) WHERE status IN ('PENDING_ESCROW', 'PENDING_VEHICLE_ASSIGNMENT', 'PENDING_DELIVERY');
```

### B.2 State Machine Service Implementation

```typescript
export class ContractStateMachine {
  constructor(
    private contractRepository: ContractRepository,
    private eventPublisher: EventPublisher
  ) {}
  
  async transitionTo(
    contractId: string,
    toState: ContractState,
    reason: string,
    metadata?: object
  ): Promise<void> {
    const contract = await this.contractRepository.findById(contractId);
    
    // Validate transition
    await this.validateTransition(contract.status, toState);
    
    // Execute transition
    const updatedContract = await this.contractRepository.update(contractId, {
      status: toState,
      previousStatus: contract.status,
      statusChangedAt: new Date(),
      statusChangeReason: reason,
      ...this.getStateSpecificUpdates(toState, metadata)
    });
    
    // Publish events
    await this.publishStateChangeEvents(updatedContract, contract.status, toState);
    
    // Execute state actions
    await this.executeStateActions(updatedContract, toState);
  }
  
  private getStateSpecificUpdates(
    state: ContractState, 
    metadata: object
  ): object {
    switch (state) {
      case 'PENDING_VEHICLE_ASSIGNMENT':
        return { escrowLockedAt: new Date() };
      case 'PENDING_DELIVERY':
        return { vehiclesAssignedAt: new Date() };
      case 'ACTIVE':
        return { activatedAt: new Date(), actualStartDate: new Date() };
      case 'COMPLETED':
        return { completedAt: new Date(), actualEndDate: new Date() };
      // ... other states
      default:
        return {};
    }
  }
}
```

---

## 10. STATUS AGGREGATION RULES

### 10.1 Contract Status Aggregation from Line Items

Contract status is determined by aggregating delivery and return metrics from all Contract Line Items, with hierarchical priority rules.

#### Aggregation Logic:

```typescript
// Step 1: Filter operational line items (exclude TERMINATED and COMPLETED)
const operationalLineItems = lineItems.filter(li => 
  li.status !== 'TERMINATED' && li.status !== 'COMPLETED'
);

// Step 2: Calculate aggregated metrics
const totalAwarded = operationalLineItems.sum(li => li.quantityAwarded);
const totalDelivered = operationalLineItems.sum(li => li.quantityDelivered);
const totalReturned = operationalLineItems.sum(li => li.quantityReturned);
const totalActive = operationalLineItems.sum(li => li.quantityActive);

// Step 3: Determine contract status (hierarchical priority)
if (allLineItemsCompleted) {
  contractStatus = 'COMPLETED';
} else if (contractLevelAction) {
  // Contract-level actions override aggregation
  if (terminated) contractStatus = 'TERMINATED';
  if (onHold) contractStatus = 'ON_HOLD';
  if (timeoutPending) contractStatus = 'TIMEOUT_PENDING';
  if (disputed) contractStatus = 'DISPUTED';
} else if (hasOperationalLineItems) {
  // Operational states
  if (totalReturned > 0 && totalReturned < totalAwarded) {
    contractStatus = 'PARTIALLY_RETURNED';
  } else if (totalDelivered > 0 && totalDelivered < totalAwarded) {
    contractStatus = 'PARTIALLY_DELIVERED';
  } else if (totalDelivered == totalAwarded && totalReturned == 0) {
    contractStatus = 'ACTIVE';
  }
} else {
  // Pending states
  if (totalDelivered == 0 && totalActive > 0) {
    contractStatus = 'PENDING_DELIVERY';
  } else {
    contractStatus = 'PENDING_VEHICLE_ASSIGNMENT';
  }
}
```

#### Priority Order:

1. **Contract-Level Actions** (highest priority - override aggregation):
   - `TERMINATED` - Contract terminated (cascades to all line items)
   - `ON_HOLD` - Contract on hold (cascades to active line items)
   - `TIMEOUT_PENDING` - Contract timeout
   - `DISPUTED` - Contract under dispute

2. **Operational States** (when any line items are operational):
   - `PARTIALLY_RETURNED` - Some vehicles returned across all line items
   - `PARTIALLY_DELIVERED` - Some vehicles delivered, not all
   - `ACTIVE` - All vehicles delivered across all line items

3. **Pending States** (when no operational line items):
   - `PENDING_DELIVERY` - Vehicles assigned, waiting for delivery
   - `PENDING_VEHICLE_ASSIGNMENT` - Waiting for vehicle assignment
   - `PENDING_ESCROW` - Waiting for escrow lock

4. **Final States**:
   - `COMPLETED` - All line items completed (all vehicles returned)

### 10.2 Handling Mixed Line Item States

**Scenario: Some Line Items ACTIVE, Some COMPLETED**
- **Contract Status:** `ACTIVE` or `PARTIALLY_RETURNED` (based on active line items)
- **Business Logic:** Completed line items don't affect contract status. Contract remains operational. Settlement calculated only for active line items.

**Scenario: Some Line Items ACTIVE, Some ON_HOLD**
- **Contract Status:** `ACTIVE` (operational precedence)
- **Business Logic:** Active line items continue operations. On-hold line items are suspended. Contract is operational but flagged.

**Scenario: Some Line Items ACTIVE, Some TERMINATED**
- **Contract Status:** `ACTIVE` or `PARTIALLY_DELIVERED` (based on active line items)
- **Business Logic:** Active line items continue operations. Terminated line items excluded from calculations. Contract remains operational.

**Scenario: Mix of PENDING_ACTIVATION, PARTIALLY_DELIVERED, ACTIVE**
- **Contract Status:** `PARTIALLY_DELIVERED` (operational precedence)
- **Business Logic:** Contract is operational with partially delivered state. Business can use delivered vehicles while waiting for remaining deliveries.

### 10.3 Contract-Level Action Cascading

When contract-level actions occur, they cascade to line items:

**Contract Termination:**
```typescript
contract.Terminate() → 
  For each lineItem in contract.lineItems:
    if (lineItem.status != 'COMPLETED' && lineItem.status != 'TERMINATED')
      lineItem.Terminate()
```

**Contract On Hold:**
```typescript
contract.PutOnHold() →
  For each lineItem in contract.lineItems:
    if (lineItem.status == 'ACTIVE' || lineItem.status == 'PARTIALLY_DELIVERED' || lineItem.status == 'PARTIALLY_RETURNED')
      lineItem.status = 'ON_HOLD'
```

---

**END OF CONTRACT STATE MACHINE SPECIFICATION**

---

**For Implementation:** Use this document as reference for:
1. Contract status field values
2. State transition logic
3. Timeout handling
4. Error recovery procedures
5. State validation rules

**For Testing:** Verify:
1. All state transitions work correctly
2. Invalid transitions are blocked
3. Timeouts trigger correctly
4. State-specific validations pass
5. Events published for each transition
