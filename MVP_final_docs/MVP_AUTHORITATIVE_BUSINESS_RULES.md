# Movello MVP - Authoritative Business Rules
## Single Source of Truth - Version 1.0

**Document Status:** AUTHORITATIVE  
**Date:** December 21, 2025  
**Supersedes:** All conflicting specifications in previous documents  
**Review Status:** ✅ Approved by Business Owner

---

## Document Control

**Purpose:** This document serves as the single authoritative source for all business rules in the Movello B2B Mobility Marketplace MVP. In case of conflicts with other documents, THIS DOCUMENT TAKES PRECEDENCE.

**Change Control:** Any changes to this document must be:
1. Approved by business owner
2. Version incremented
3. Change log updated
4. Conflicting documents updated or deprecated

---

## TABLE OF CONTENTS

1. [RFQ & Bidding Rules](#1-rfq--bidding-rules)
2. [Award & Contract Creation](#2-award--contract-creation)
3. [Escrow & Financial Rules](#3-escrow--financial-rules)
4. [Vehicle Assignment & Delivery](#4-vehicle-assignment--delivery)
5. [Contract Activation & Lifecycle](#5-contract-activation--lifecycle)
6. [Early Return & Penalties](#6-early-return--penalties)
7. [Provider Rejection Handling](#7-provider-rejection-handling)
8. [Trust Score Calculation](#8-trust-score-calculation)
9. [Provider Tier System](#9-provider-tier-system)
10. [Business Tier System](#10-business-tier-system)
11. [Compliance & Verification](#11-compliance--verification)
12. [Settlement Processing](#12-settlement-processing)
13. [Dispute Resolution](#13-dispute-resolution)
14. [Status Definitions](#14-status-definitions)

---

## 1. RFQ & BIDDING RULES

### 1.1 RFQ Creation Prerequisites

**Rule BR-001: Business Verification Required**
- Business MUST have `status = VERIFIED` to create RFQ
- Unverified or pending businesses CANNOT create RFQ
- System MUST validate business status before allowing RFQ creation

**Rule BR-002: No Wallet Balance Required for RFQ Creation**
- ❌ **DEPRECATED RULE:** "Business must maintain sufficient balance to fund next billing cycle"
- ✅ **CURRENT RULE:** NO wallet balance required to create or publish RFQ
- Wallet balance is only required at BID AWARD time (see BR-008)

**Rule BR-003: RFQ Line Item Structure**
- Each RFQ must have at least 1 line item
- Each line item specifies: Vehicle type, quantity, rental period, budget constraints
- Line items are independently biddable and awardable

---

### 1.2 Bid Submission Prerequisites

**Rule BR-004: Provider Pre-Bid Validation**

Provider MUST meet ALL criteria to submit bid:

1. **Account Status:** Provider status = VERIFIED (not suspended/blocked)
2. **Vehicle Availability:** Provider must have at least 1 active and unassigned vehicle matching:
   - Vehicle type (sedan, SUV, minibus, etc.)
   - Availability through delivery date
   - **Note:** Provider can bid for more vehicles than they currently have available. Business may choose to split awards among multiple providers or award partial quantities.
3. **Insurance Validity:** All vehicles provider intends to use must have valid insurance through delivery date + 30 days buffer
4. **Trust Score:** Provider must meet minimum trust score threshold (if configured)

**Validation Timing:**
- Pre-bid validation: At bid submission time
- Re-validation: At award time (see BR-009)

---

### 1.3 Bid Modification & Withdrawal

**Rule BR-005: Bid Modification Rules**
- Provider can modify bid UNTIL bidding deadline
- Provider can withdraw bid UNTIL award is made
- After award, provider cannot withdraw (see Provider Rejection rules)

---

## 2. AWARD & CONTRACT CREATION

### 2.1 Award Prerequisites

**Rule BR-006: Award Validation Checks**

Before business can award bid, system MUST validate:
1. ✅ RFQ status = ACTIVE or BIDDING
2. ✅ Business wallet balance ≥ total escrow required for all selected awards
3. ✅ Provider still meets pre-bid validation criteria (see BR-004)
4. ✅ Vehicles still available and unassigned

**If validation fails:**
- Display error message to business
- Allow business to:
  - Deposit funds (if balance insufficient)
  - Select fewer bids (partial award)
  - Cancel award attempt

---

### 2.2 Partial Award Handling

**Rule BR-007: Partial Award Business Logic**

**Scenario:** Business wants to award 10 vehicles but only has balance for 2 vehicles.

**System Behavior:**
1. Display message: "Your balance is sufficient for 2 vehicles out of 10 requested. Please deposit more funds or award 2 vehicles."
2. Business options:
   - **Option A:** Deposit funds → Retry award for all 10 vehicles
   - **Option B:** Award 2 vehicles only
   - **Option C:** Cancel award

**If Business selects Option B (Award 2 vehicles):**
- Selected provider(s): Bids → `AWARDED` status
- Unselected provider(s): Bids → `LOST` status
- Line item: Status → `AWARDED`
- RFQ Status Logic (see BR-013 for details):
  - If RFQ has only 1 line item → RFQ status = `AWARDED`
  - If RFQ has multiple line items:
    - Some awarded + some bidding → RFQ status = `PARTIALLY_AWARDED`
    - All awarded → RFQ status = `AWARDED`

**To award remaining 8 vehicles:**
- Business must create NEW RFQ for remaining quantity

---

### 2.3 Award Workflow Sequence

**Rule BR-008: Canonical Award → Contract → Escrow Flow**

**OFFICIAL SEQUENCE (supersedes all conflicting documents):**

```
Step 1: Business Awards Bid
   ↓
Step 2: System validates wallet balance (BR-006)
   ↓
Step 3: System publishes BidAwardedEvent
   ↓
Step 4: Contract Module creates contract (ContractCreatedEvent)
   ↓
Step 5: Finance Module locks escrow (EscrowLockedEvent)
   ↓
Step 6: Provider assigns vehicles
   ↓
Step 7: Provider delivers vehicles (OTP/QR confirmation)
   ↓
Step 8: Contract activation (when all conditions met)
```

**Critical Clarification:**
- ❌ **NOT:** BidAwardedEvent → EscrowLockedEvent → ContractCreatedEvent
- ✅ **CORRECT:** BidAwardedEvent → ContractCreatedEvent → EscrowLockedEvent

---

### 2.4 Award Failure Handling

**Rule BR-009: Award Validation Failure Recovery**

| Failure Point | System Action | Business Action |
|--------------|---------------|-----------------|
| Insufficient balance | Show error with balance details | Deposit funds, retry award |
| Provider validation fails | Show error, exclude provider | Select different provider |
| Vehicle unavailable | Show error, exclude provider | Select different provider |
| Contract creation fails | Revert bid to BIDDING status | Retry award |
| Escrow lock fails | Contract → PENDING status, background retry | Notified, wait for retry |

---

## 3. ESCROW & FINANCIAL RULES

### 3.1 Escrow Lock Timing

**Rule BR-010: Escrow Lock Trigger**

**When:** AFTER contract creation (triggered by ContractCreatedEvent)  
**Amount:** Determined by rental period:
- **Monthly rentals:** Lock 1 month's cost
- **Rentals < 1 month:** Lock full rental cost

**Before vehicle assignment:**
- Contract status = `PENDING_VEHICLE_ASSIGNMENT` (escrow locked, waiting for vehicles)

---

### 3.2 Escrow Lock Failure Handling

**Rule BR-011: Escrow Lock Failure Recovery**

**If escrow lock fails:**
1. Contract status → `PENDING_ESCROW` (holding state)
2. Background service retries escrow lock every 30 minutes (max 5 attempts)
3. After 5 failed attempts:
   - Notify business: "Escrow lock failed. Please check wallet balance."
   - Notify provider: "Contract on hold due to payment issue."
4. Contract activation blocked until escrow successfully locked

---

### 3.3 Wallet Balance Requirements

**Rule BR-012: When Wallet Balance is Required**

| Action | Wallet Balance Required? |
|--------|--------------------------|
| Browse marketplace | ❌ No |
| Create RFQ | ❌ No |
| Publish RFQ | ❌ No |
| Receive bids | ❌ No |
| **Award bid** | ✅ **YES** - Must cover escrow for all selected awards |
| Contract activation | ✅ YES - Escrow must be locked |
| **Contract continuation** | ✅ **YES** - Must maintain sufficient balance to fund next billing cycle |

**If business fails to deposit for next billing cycle (Payment Default):**

**Step 1: Advance Notifications (Days 20-30 of Month 1)**
- Day 20: Reminder - "Deposit for Month 2 due in 10 days"
- Day 25: Urgent - "Deposit 30,000 ETB by Day 30 to continue contract"
- Day 28: Final warning - "Deposit by Day 30 or contract will be suspended"
- Day 29: Last day - "Deposit by Day 30 or vehicles will be collected"
- Day 30, 18:00: "6 hours remaining to deposit"

**Step 2: Contract Suspension (Day 31, immediately after escrow period ends)**
1. Contract status → `ON_HOLD`
2. System notifies business: "Payment overdue. Contract suspended. Wait for provider's decision."
3. System notifies provider with two options:
   - **Option A (Recommended):** "Collect vehicles now" → Contract terminated immediately
   - **Option B:** "Grant grace period (1-7 days)" → Provider bears the risk

**Step 3: Provider Decision Required Within 24 Hours**

**If Provider Chooses: Collect Vehicles Immediately**
- Contract status → `TERMINATED`
- Settlement processed for completed period only
- Provider collects vehicles
- Business can create new RFQ (trust score impacted)

**If Provider Chooses: Grant Grace Period (e.g., 2 days)**
- Contract remains `ON_HOLD` for grace period duration
- Business notified: "Provider granted you 2 days grace period. Deposit by Day 32 or vehicles will be collected."
- Grace period timer starts

**During Grace Period:**
- Vehicles remain with business
- Business can still use vehicles
- Daily usage charges accumulate

**Grace Period Outcome 1: Business Deposits During Grace Period**
- Business must pay:
  - Grace period days (e.g., 2 days × 1,000 ETB = 2,000 ETB)
  - Late payment fee: 5% of grace period amount
  - Next month escrow (e.g., 30,000 ETB)
- Example total: 2,000 + 100 (late fee) + 30,000 = 32,100 ETB
- Contract status → `ACTIVE`
- Provider receives grace period payment immediately

**Grace Period Outcome 2: Business Fails to Deposit After Grace Period**
- Contract status → `TERMINATED`
- Business account → `SUSPENDED`
- Outstanding debt created: Grace period days owed to provider
- Business cannot use platform until debt cleared
- Provider collects vehicles
- Settlement includes debt record

**Debt Collection Process:**
- Debt amount = Grace period days × daily rate
- Business must clear debt to reactivate account
- Provider can escalate to dispute if debt not paid within 30 days
- System tracks debt in business profile

**Provider Protection:**
- If provider grants grace period, provider accepts the risk
- Provider can choose immediate collection to avoid risk
- System recommends immediate collection (Option A) as default
- Grace period is entirely provider's discretion

---

## 4. VEHICLE ASSIGNMENT & DELIVERY

### 4.1 Vehicle Assignment Prerequisites

**Rule BR-013: Pre-Assignment Validation**

Provider can ONLY assign vehicle if:
1. ✅ Contract status = `PENDING_VEHICLE_ASSIGNMENT`
2. ✅ Escrow is locked (EscrowLockedEvent received)
3. ✅ Vehicle status = `ACTIVE` and `UNASSIGNED`
4. ✅ Vehicle insurance valid through delivery date + 30 days
5. ✅ Vehicle matches contract specifications (type, features)

**If validation fails:**
- Block assignment
- Display error to provider
- Notify provider to resolve issue (renew insurance, activate vehicle, etc.)

---

### 4.2 Delivery & OTP Verification

**Rule BR-014: Delivery Confirmation Process**

**Provider Responsibilities:**
1. Deliver vehicle to business location on scheduled date/time
2. Request OTP via provider app (specifies business phone/email for OTP delivery)
3. System sends OTP to business AND displays OTP to provider
4. Provider verifies business has received OTP (business tells provider the code verbally/shows it)
5. Provider enters the OTP in provider app to confirm delivery

**Business Responsibilities:**
1. Inspect vehicle condition (check against contract specs)
2. Receive OTP via SMS/email from system
3. If satisfied: Share OTP with provider verbally or show on phone
4. If not satisfied: Reject delivery (DO NOT share OTP with provider)

**OTP Flow Explanation:**
- System sends OTP to business contact (SMS/Email)
- System also shows same OTP to provider in app
- Provider must enter this OTP to confirm delivery
- This ensures business is present and agrees to accept vehicle (by sharing the OTP)

**OTP Validation Rules:**
- OTP validity duration is configurable (default: 15 minutes)
- Max 3 incorrect attempts → Block for 30 minutes
- After 3 blocks → Escalate to support

**OTP Expiry Handling:**
- Provider can request new OTP if expired
- Previous OTP invalidated immediately

**Configuration:**
- OTP expiry time retrieved from MasterData settings (`otp.expiry.minutes`)
- Default value: 15 minutes if not configured

---

### 4.3 Delivery Rejection

**Rule BR-015: Business Rejection of Delivery**

**Business can reject delivery BEFORE OTP entry if:**
- Vehicle condition doesn't match expectations
- Wrong vehicle delivered
- Vehicle damaged or dirty
- Insurance documents not provided

**Rejection Process:**
1. Business selects rejection reason in app
2. Provider options:
   - Replace vehicle (if available)
   - Cancel contract (mutual agreement)
3. If no resolution within 24 hours:
   - Escalate to dispute resolution (see BR-030)

**After OTP Entry:**
- ❌ Delivery rejection NOT allowed
- ✅ OTP entry = Final acceptance of vehicle condition
- For issues after OTP: Use early return or dispute process

---

## 5. CONTRACT ACTIVATION & LIFECYCLE

### 5.1 Contract Activation Prerequisites

**Rule BR-016: Dual Condition for Activation**

Contract becomes `ACTIVE` ONLY when **BOTH** conditions met:
1. ✅ Escrow locked (EscrowLockedEvent received)
2. ✅ Delivery confirmed (DeliveryConfirmedEvent received via OTP)

**Contract States Before Activation:**
- `PENDING_ESCROW` - Contract created, waiting for escrow lock
- `PENDING_VEHICLE_ASSIGNMENT` - Escrow locked, waiting for vehicle assignment
- `PENDING_DELIVERY` - Vehicle assigned, waiting for delivery confirmation
- `ACTIVE` - All conditions met, contract running

---

### 5.2 Contract Activation Timeout

**Rule BR-017: Timeout Handling**

**Timeout Period:** 5 days from contract creation

**If contract not activated within 5 days:**
1. System sends notifications:
   - To business: "Contract not activated. Escrow: [status], Delivery: [status]"
   - To provider: "Contract not activated. Please complete [pending action]"
2. Contract status → `TIMEOUT_PENDING`
3. Manual intervention required (support team)

**No automatic cancellation** - Protect against accidental contract termination

---

### 5.3 Contract Completion

**Rule BR-018: Contract Completion Trigger**

Contract status → `COMPLETED` when:
- Rental period ends (scheduled end date reached)
- Vehicle returned and verified
- No outstanding disputes

**Settlement Processing:**
- Triggered by `ContractCompletedEvent` (see BR-026)

---

## 6. EARLY RETURN & PENALTIES

### 6.1 Early Return Request Process

**Rule BR-019: Early Return Approval Requirements**

**Who Can Request:** Either business OR provider can initiate early return request

**Approval:** BOTH business and provider must approve

**Notice Period:** Requesting party must give 7+ days notice to avoid penalty

**Notice Period Penalty Structure (Configurable):**

| Notice Period | Penalty Rate |
|--------------|--------------|
| 7+ days before return | 0% penalty |
| 3-6 days before return | 2% of remaining amount |
| 0-2 days before return (same day) | 15% of remaining amount |

**Penalty Applied To:** Remaining rental amount (from return date to contract end date)

**Configuration:**
- Penalty can be configured as fixed amount OR percentage
- System admin can adjust rates via MasterData configuration
- No waiver process for MVP
- No negotiation for any tier (Enterprise/GOV_NGO)

---

### 6.2 Early Return with Damage

**Rule BR-020: Damage During Early Return**

**If vehicle damaged during rental:**
- Business covers damage cost (enforced by law)
- Provider must raise dispute with evidence (photos, inspection report)
- Damage cost deducted from business wallet or invoiced separately
- Early return penalty still applies (separate from damage cost)

---

### 6.3 Early Return Settlement

**Rule BR-021: Settlement Calculation**

**Formula:**
```
Remaining Amount = (Total Contract Cost / Total Days) × (Days from Return to End Date)
Penalty Amount = Remaining Amount × Penalty Rate (based on notice period)
Refund to Business = Remaining Amount - Penalty Amount
Payment to Provider = Already Paid Amount + Penalty Amount
```

**Settlement Trigger:** `EarlyReturnEvent` published after both parties approve

---

## 7. PROVIDER REJECTION HANDLING

### 7.1 Legitimate Rejection Scenarios

**Rule BR-022: No-Penalty Rejection Reasons**

Provider can reject award WITHOUT penalty for first-time rejection if:
1. Vehicle broken or in maintenance
2. Insurance expired (provider must provide proof)
3. Force majeure (accident, natural disaster, etc.)

**Appeal Process:**
- First-time rejection: Allowed with reason
- Repeated rejections: Penalty applies (trust score impact)

---

### 7.2 Provider Rejection Workflow

**Rule BR-023: Manual Re-Award Process**

**When provider rejects award:**

**Step 1: Provider Action**
- Provider selects rejection reason via app
- Rejection reason stored for audit

**Step 2: System Actions**
- Bid status: `AWARDED` → `REJECTED`
- Notify business: "Provider [name] rejected award. Reason: [reason]"
- Rejected provider excluded from this RFQ (cannot bid again)
- Reactivate other bids: `LOST` → `BIDDING` (make available for selection)

**Step 3: Business Action (Manual)**
- Review rejection reason
- Select next provider from available bids
- Award bid manually

**Step 4: Re-Validation**
- System re-validates provider (see BR-006)
- Proceed with award workflow (see BR-008)

---

### 7.3 Rejection Impact on Trust Score

**Rule BR-024: Trust Score Penalty for Rejections**

| Rejection Count | Penalty | Additional Action |
|----------------|---------|-------------------|
| 1st rejection (legitimate) | No penalty | Warning notification |
| 2nd rejection (within 30 days) | -5 points | Final warning |
| 3rd+ rejection (within 30 days) | -10 points | Account review, possible suspension |

---

## 8. TRUST SCORE CALCULATION

### 8.1 Trust Score Formula (MVP)

**Rule BR-025: Simple Trust Score Calculation**

**Initial Score:**
- Verified users: **50 points** (baseline for verified providers/businesses)
- Unverified/Pending: **0 points**

**Calculation Formula:**
```
Trust Score = Base Score (50) 
            + (Completion Rate × 20) 
            + (On-Time Rate × 20) 
            - (No-Show Rate × 30)
            + (Rejection Penalty - see BR-024)

Where:
- Completion Rate = Completed Contracts / Total Contracts (0-1)
- On-Time Rate = On-Time Deliveries / Total Deliveries (0-1)
- No-Show Rate = No-Shows / Total Scheduled (0-1)

Score Range: 0-100 (capped)
```

**❌ NOT Included in MVP:**
- Signal-based decay algorithms
- Complex weighting systems
- Historical trend analysis

**Recalculation Triggers:**
- Contract completion
- Delivery confirmation
- No-show incident
- Provider rejection (see BR-024)
- Dispute resolution

---

### 8.2 Trust Score Display

**Rule BR-026: Trust Score Visibility**

- Displayed to businesses when viewing provider bids
- Displayed to providers in profile dashboard
- Updated in real-time after recalculation
- Historical score graph available (POST-MVP)

---

## 9. PROVIDER TIER SYSTEM

### 9.1 Provider Tier Overview

**Rule BR-040: Provider Tier Structure**

Provider tiers determine commission rates and platform benefits. Tiers are calculated based on **TWO factors**:
1. Trust Score (primary factor)
2. Active Fleet Size (number of vehicles currently assigned to active contracts)

**Tier Levels:**

| Tier | Base Trust Score | Active Fleet Requirement | Commission Rate | Benefits |
|------|------------------|-------------------------|-----------------|----------|
| **BRONZE** | 0-49 | Any | 10% | Basic access |
| **SILVER** | 50-69 | 5+ active vehicles | 8% | Priority support |
| **GOLD** | 70-84 | 15+ active vehicles | 6% | Featured listing |
| **PLATINUM** | 85-100 | 30+ active vehicles | 5% | Premium benefits |

---

### 9.2 Initial Provider Tier Assignment

**Rule BR-041: New Provider Tier Assignment**

**Verified Providers:**
- Initial trust score: **50 points**
- Initial tier: **SILVER** (if profile 100% complete)
- Commission rate: 8%

**Unverified/Pending Providers:**
- Initial trust score: **0 points**
- Initial tier: **BRONZE**
- Commission rate: 10%
- Cannot bid until verified

**Profile Completion Impact:**
```typescript
function determineInitialTier(provider: Provider): ProviderTier {
  if (provider.status !== 'VERIFIED') {
    return 'BRONZE'; // Unverified = Bronze
  }
  
  const profileCompletion = calculateProfileCompletion(provider);
  
  if (profileCompletion < 100) {
    return 'BRONZE'; // Incomplete profile = Bronze
  }
  
  // Verified + 100% complete = Silver (starting trust score = 50)
  return 'SILVER';
}

function calculateProfileCompletion(provider: Provider): number {
  const requiredFields = [
    provider.businessLicense,
    provider.tinCertificate,
    provider.bankAccount,
    provider.phoneVerified,
    provider.emailVerified,
    provider.hasActiveVehicles,
    provider.insuranceDocuments
  ];
  
  const completed = requiredFields.filter(field => field).length;
  return (completed / requiredFields.length) * 100;
}
```

---

### 9.3 Provider Tier Calculation Logic

**Rule BR-042: Hybrid Tier Determination**

Provider tier is determined by **BOTH** trust score AND active fleet size. A provider must meet BOTH criteria to qualify for higher tiers.

**Tier Determination Algorithm:**
```typescript
function calculateProviderTier(provider: Provider): ProviderTier {
  const trustScore = provider.trustScore;
  const activeVehicles = getActiveVehicleCount(provider.id);
  
  // Tier requirements (BOTH must be met)
  const tierRequirements = {
    PLATINUM: { minScore: 85, minVehicles: 30 },
    GOLD: { minScore: 70, minVehicles: 15 },
    SILVER: { minScore: 50, minVehicles: 5 },
    BRONZE: { minScore: 0, minVehicles: 0 }
  };
  
  // Check tiers from highest to lowest
  if (trustScore >= 85 && activeVehicles >= 30) return 'PLATINUM';
  if (trustScore >= 70 && activeVehicles >= 15) return 'GOLD';
  if (trustScore >= 50 && activeVehicles >= 5) return 'SILVER';
  
  return 'BRONZE';
}

function getActiveVehicleCount(providerId: string): number {
  // Count vehicles currently assigned to ACTIVE contracts
  return db.query(`
    SELECT COUNT(DISTINCT va.vehicle_id)
    FROM contracts_schema.vehicle_assignments va
    JOIN contracts_schema.contracts c ON va.contract_id = c.id
    WHERE c.provider_id = $1 
      AND c.status = 'ACTIVE'
      AND va.status = 'ACTIVE'
  `, [providerId]);
}
```

**Examples:**
```
Provider A:
- Trust Score: 75
- Active Vehicles: 20
- Tier: GOLD ✅ (meets both: score ≥70, vehicles ≥15)

Provider B:
- Trust Score: 90
- Active Vehicles: 8
- Tier: SILVER ❌ (high score but only 8 vehicles, doesn't meet GOLD requirement of 15+)

Provider C:
- Trust Score: 55
- Active Vehicles: 25
- Tier: SILVER ❌ (enough vehicles but score too low for GOLD)
```

---

### 9.4 Tier Upgrade & Downgrade

**Rule BR-043: Automatic Tier Recalculation**

**Recalculation Triggers:**
- Trust score changes (after contract completion, disputes, etc.)
- Active vehicle count changes (contracts start/end)
- Monthly review (1st of each month)

**Upgrade Process:**
```typescript
async function checkTierUpgrade(providerId: string) {
  const provider = await getProvider(providerId);
  const currentTier = provider.tier;
  const newTier = calculateProviderTier(provider);
  
  if (newTier !== currentTier) {
    // Create tier change record
    await createTierChangeRecord({
      providerId,
      oldTier: currentTier,
      newTier: newTier,
      reason: 'AUTOMATIC_RECALCULATION',
      trustScore: provider.trustScore,
      activeVehicles: getActiveVehicleCount(providerId),
      changedAt: new Date()
    });
    
    // Update provider tier
    await updateProviderTier(providerId, newTier);
    
    // Notify provider
    await notifyTierChange(providerId, currentTier, newTier);
    
    // Publish event
    await publishEvent('TierChangedEvent', { providerId, oldTier: currentTier, newTier });
  }
}
```

**Tier Downgrade Protection:**
- If trust score drops but vehicle count stays high: Tier may be maintained temporarily (grace period of 30 days)
- If both drop: Immediate downgrade
- Providers notified 7 days before scheduled downgrade

---

### 9.5 Tier Benefits

**Rule BR-044: Tier-Based Benefits**

**Commission Rates:**
- BRONZE: 10%
- SILVER: 8%
- GOLD: 6%
- PLATINUM: 5%

**Configuration Source:**
- Commission rates stored in: `masterdata.commission_strategy_rule`
- Tier thresholds stored in: `masterdata.provider_tier_rule`
- All tier parameters are configurable (see Section 9.6 below)

**Additional Benefits by Tier:**

**SILVER:**
- Priority customer support
- Monthly settlement (instead of per-contract)
- Basic analytics dashboard

**GOLD:**
- Featured in provider listings
- Bi-weekly settlements
- Advanced analytics
- Dedicated account manager

**PLATINUM:**
- Top placement in searches
- Weekly settlements
- Custom reporting
- API access for integrations
- Flexible payment terms

---

### 9.6 Tier Configuration (Master Data)

**Rule BR-051: Configurable Tier Thresholds**

All tier thresholds and parameters are stored in Master Data and can be configured without code changes.

**Database Tables:**

**1. Provider Tier Configuration:**
```sql
-- Table: masterdata.provider_tier
-- Stores tier definitions (BRONZE, SILVER, GOLD, PLATINUM)

-- Table: masterdata.provider_tier_rule  
-- Stores tier qualification rules
COLUMNS:
- min_trust_score (e.g., 50 for SILVER)
- max_trust_score (e.g., 69 for SILVER)
- min_completed_contracts (optional)
- max_cancellation_rate (optional)
- min_on_time_rate (optional)

-- Note: Active fleet size threshold is currently hardcoded in business logic
-- Future: Move to provider_tier_rule as min_active_vehicles column
```

**2. Commission Configuration:**
```sql
-- Table: masterdata.commission_strategy_version
-- Stores versioned commission strategies

-- Table: masterdata.commission_strategy_rule
-- Stores commission rates per tier
COLUMNS:
- provider_tier_code (BRONZE, SILVER, GOLD, PLATINUM)
- commission_type (PERCENTAGE)
- rate_percentage (0.10 = 10%)
```

**3. Business Tier Configuration:**
```sql
-- Table: masterdata.business_tier
-- Stores business tier definitions
COLUMNS:
- code (STANDARD, BUSINESS_PRO, PREMIUM, ENTERPRISE)
- max_rfqs_per_month (20, 50, 100, NULL)
- max_active_contracts (optional limit)
- max_vehicles_per_rfq (optional limit)

-- Note: Fleet size and completed contract thresholds are currently in business logic
-- Future: Add business_tier_rule table for configurable thresholds
```

**Configuration Management:**
- Admin UI for updating tier thresholds (POST-MVP)
- API endpoints for tier configuration (POST-MVP)
- Current: Database updates via SQL migrations

**Cache Strategy:**
- Tier rules cached in Redis for performance
- Cache invalidated on tier configuration changes
- TTL: 1 hour

---

## 10. BUSINESS TIER SYSTEM

### 10.1 Business Tier Overview

**Rule BR-045: Business Tier Structure**

Business tiers determine platform access limits and benefits. Tiers are calculated based on **TWO factors**:
1. Trust Score / Contract History
2. Active Fleet Size (number of vehicles currently under contract)

**Tier Levels:**

| Tier | Criteria | Active Fleet Requirement | RFQ Limit | Benefits |
|------|----------|-------------------------|-----------|----------|
| **STANDARD** | New businesses | 1-9 vehicles | 20/month | Basic access |
| **BUSINESS_PRO** | 10+ completed contracts | 10-29 vehicles | 50/month | Priority support |
| **PREMIUM** | Strong activity | 30-99 vehicles | 100/month | Featured status |
| **ENTERPRISE** | High volume | 100+ vehicles | Unlimited | Custom terms |

**Key Principle:** Fleet size in active contracts matters more than company registration status. A small registered company with 5 vehicles ranks lower than an active business with 50 vehicles under contract.

---

### 10.2 Initial Business Tier Assignment

**Rule BR-046: New Business Tier Assignment**

**All New Businesses:**
- Initial tier: **STANDARD**
- RFQ limit: 20 per month
- Trust score: 50 (after verification)

**Verification Required:**
- Must complete KYB verification before creating RFQ
- Profile completion required (100%)

---

### 10.3 Business Tier Calculation Logic

**Rule BR-047: Hybrid Business Tier Determination**

Business tier is determined by **BOTH** completed contract history AND current active fleet size.

**Tier Determination Algorithm:**
```typescript
function calculateBusinessTier(business: Business): BusinessTier {
  const completedContracts = getCompletedContractCount(business.id);
  const activeVehicles = getActiveFleetSize(business.id);
  const trustScore = business.trustScore;
  
  // ENTERPRISE: 100+ active vehicles (regardless of company size)
  if (activeVehicles >= 100) {
    return 'ENTERPRISE';
  }
  
  // PREMIUM: 30+ active vehicles + good history
  if (activeVehicles >= 30 && completedContracts >= 20) {
    return 'PREMIUM';
  }
  
  // BUSINESS_PRO: 10+ active vehicles + 10+ completed contracts
  if (activeVehicles >= 10 && completedContracts >= 10) {
    return 'BUSINESS_PRO';
  }
  
  // STANDARD: Default for new or small businesses
  return 'STANDARD';
}

function getActiveFleetSize(businessId: string): number {
  // Count total vehicles currently under active contracts
  return db.query(`
    SELECT COUNT(DISTINCT va.vehicle_id)
    FROM contracts_schema.vehicle_assignments va
    JOIN contracts_schema.contracts c ON va.contract_id = c.id
    WHERE c.business_id = $1 
      AND c.status = 'ACTIVE'
      AND va.status = 'ACTIVE'
  `, [businessId]);
}
```

**Examples:**
```
Business A (Small registered enterprise):
- Completed Contracts: 15
- Active Fleet: 5 vehicles
- Tier: STANDARD ❌ (despite being "enterprise" - fleet too small)

Business B (Active logistics company):
- Completed Contracts: 25
- Active Fleet: 45 vehicles
- Tier: PREMIUM ✅ (high activity = premium status)

Business C (Major organization):
- Completed Contracts: 50
- Active Fleet: 120 vehicles
- Tier: ENTERPRISE ✅ (100+ vehicles = enterprise automatically)

Business D (Growing startup):
- Completed Contracts: 12
- Active Fleet: 15 vehicles
- Tier: BUSINESS_PRO ✅ (meets both criteria)
```

---

### 10.4 Business Tier Upgrade

**Rule BR-048: Automatic Business Tier Upgrade**

**Upgrade Triggers:**
- New contract activated (increases active fleet count)
- Contract completed (increases completed contract count)
- Monthly review (1st of each month)

**Upgrade Process:**
```typescript
async function checkBusinessTierUpgrade(businessId: string) {
  const business = await getBusiness(businessId);
  const currentTier = business.tier;
  const newTier = calculateBusinessTier(business);
  
  if (newTier !== currentTier && getTierRank(newTier) > getTierRank(currentTier)) {
    // Create tier upgrade record
    await createBusinessTierChange({
      businessId,
      oldTier: currentTier,
      newTier: newTier,
      completedContracts: getCompletedContractCount(businessId),
      activeFleet: getActiveFleetSize(businessId),
      upgradedAt: new Date()
    });
    
    // Update tier
    await updateBusinessTier(businessId, newTier);
    
    // Notify business
    await notifyBusinessTierUpgrade(businessId, currentTier, newTier);
    
    // Publish event
    await publishEvent('BusinessTierUpgradedEvent', { businessId, oldTier: currentTier, newTier });
  }
}

function getTierRank(tier: BusinessTier): number {
  const ranks = { STANDARD: 1, BUSINESS_PRO: 2, PREMIUM: 3, ENTERPRISE: 4 };
  return ranks[tier];
}
```

**Immediate Upgrade Scenarios:**
- Business reaches 100 active vehicles → Instant ENTERPRISE upgrade
- Business reaches 30 active vehicles + 20 completed contracts → Instant PREMIUM upgrade

---

### 10.5 Business Tier Benefits

**Rule BR-049: Business Tier Benefits**

**RFQ Limits:**
- STANDARD: 20 RFQs per month
- BUSINESS_PRO: 50 RFQs per month
- PREMIUM: 100 RFQs per month
- ENTERPRISE: Unlimited RFQs

**Additional Benefits:**

**BUSINESS_PRO:**
- Priority bid visibility
- Extended payment terms (NET 30)
- Monthly consolidated invoicing
- Basic fleet analytics

**PREMIUM:**
- Dedicated account manager
- Custom contract templates
- Advanced fleet analytics
- API access
- Bulk operations

**ENTERPRISE:**
- White-glove service
- Custom SLA agreements
- Volume discounts (negotiated)
- Integration support
- Priority customer support 24/7
- Custom reporting

---

### 10.6 Tier Downgrade Rules

**Rule BR-050: Business Tier Downgrade**

**Downgrade Triggers:**
- Active fleet size drops below tier threshold for 60+ consecutive days
- Poor payment history (3+ late payments)
- Trust score drops below 40

**Downgrade Protection:**
- 60-day grace period before downgrade
- Notification sent at 30 days and 7 days before downgrade
- Business can prevent downgrade by increasing active contracts

**Exception:**
- Seasonal businesses: Can request tier retention during off-season (manual review)

---

## 11. COMPLIANCE & VERIFICATION

### 9.1 KYC/KYB Verification

**Rule BR-027: Mandatory Verification Before Platform Access**

**Business Verification Checklist (Manual for MVP):**
1. Business lifetime (minimum 1 year operational)
2. Business license accuracy and validity
3. Business capital verification
4. Attorney document check
5. Contact information verification

**Provider Verification Checklist (Manual for MVP):**
1. Vehicle ownership documentation (Libre)
2. Vehicle insurance (valid, covers commercial use)
3. Driver license verification
4. Business/individual legal documents

**Verification Timeline:** 48 hours SLA

**Rejection:**
- Standard rejection reasons provided
- Provider/Business can resubmit corrected documents
- No appeal process (MVP)

---

### 9.2 Insurance Compliance

**Rule BR-028: Zero Tolerance Insurance Policy**

**Enforcement:**
- Vehicle WITHOUT valid insurance CANNOT be listed
- Vehicle WITHOUT valid insurance CANNOT be assigned to contract
- Insurance MUST be valid through delivery date + 30 days buffer

**Expiry Monitoring:**

**Scheduled Job (Daily):**
- Check all active vehicles for insurance expiry
- Generate alerts for expiring insurance

**Notification Timeline:**
- 30 days before expiry: First notification
- 7 days before expiry: Urgent notification
- On expiry: Critical alert + vehicle suspension

**Insurance Expires During Contract:**
1. Notify provider: "Insurance expired. Renew within 48 hours."
2. Notify business: "Provider insurance expired. Contract may be affected."
3. If not renewed within 48 hours:
   - Vehicle suspended from platform
   - Contract remains active (business protected by law)
   - Provider liable for any incidents

---

### 9.3 Document Re-Verification

**Rule BR-029: Periodic Re-Verification**

**Annual Re-Verification Required For:**
- Business licenses (check validity)
- Vehicle insurance (check renewal)
- Vehicle ownership documents (check for changes)

**POST-MVP:** Automated API integration with government systems for real-time verification

---

## 10. SETTLEMENT PROCESSING

### 10.1 Settlement Triggers

**Rule BR-030: Events That Trigger Settlement**

Finance module subscribes to and processes settlement for:

1. **ContractCompletedEvent** → Settlement (timing depends on contract duration - see BR-033)
2. **ContractAlteredEvent** → Adjustment settlement (pro-rata refunds/charges)
3. **EarlyReturnEvent** → Early termination settlement (with penalties applied)
4. **MonthEndEvent** → Monthly settlement for active long-term contracts (see BR-033)

---

### 10.2 Settlement Calculation

**Rule BR-031: Settlement Amount Formula**

**Normal Settlement (ContractCompletedEvent):**
```
Gross Amount = Total Contract Value
Commission = Gross Amount × Commission Rate (from MasterData, tier-based)
Tax Withholding = Gross Amount × Tax Rate (configurable, e.g., 2%)
Net Settlement = Gross Amount - Commission - Tax Withholding

Payment to Provider = Net Settlement
```

**Early Return Settlement (EarlyReturnEvent):**
```
Already Paid = Amount paid to provider before early return
Penalty Amount = (calculated per BR-021)
Additional Payment = Penalty Amount
Total Settlement = Already Paid + Additional Payment
```

**Contract Alteration Settlement:**
- Calculate pro-rata adjustments based on changes
- Refund or charge business accordingly
- Adjust provider payment

---

### 10.3 Monthly Settlement Processing

**Rule BR-032A: End-of-Month Settlement Job**

**Scheduled Job: Runs on last day of each month**

**Process:**
1. Query all contracts with:
   - Status = `ACTIVE`
   - Duration ≥ 30 days
   - Start date ≤ last day of current month
2. For each contract:
   - Calculate days in current month (from start date or 1st of month to last day of month)
   - Calculate pro-rata settlement amount
   - Publish `MonthEndSettlementEvent` with contract details and calculated amount
3. Finance module processes settlement (see BR-032)

**First Month Calculation:**
- If contract starts mid-month (e.g., Jan 15), first settlement covers Jan 15-31
- Subsequent months cover full month (Feb 1-28, Mar 1-31, etc.)

**Final Month Calculation:**
- If contract ends mid-month (e.g., Mar 15), final settlement at contract completion covers Mar 1-15

---

### 10.4 Settlement Approval Workflow

**Rule BR-032: Threshold-Based Approval**

| Settlement Amount | Approval Required |
|-------------------|-------------------|
| < 100,000 ETB | Auto-approved (immediate processing) |
| ≥ 100,000 ETB | Manual approval by Finance Officer |
| Flagged Provider Account | Manual review required (any amount) |

**Manual Approval Process:**
1. Finance officer reviews settlement details
2. Verifies contract data, commission calculation
3. Approves or rejects with reason
4. If approved: Payment processed within 24 hours

---

### 10.4 Settlement Frequency

**Rule BR-033: Contract Duration-Based Settlement Timing**

**Settlement timing depends on contract duration, NOT provider tier:**

| Contract Duration | Settlement Timing | Settlement Event |
|------------------|-------------------|------------------|
| **< 30 days** (short-term) | At contract completion | ContractCompletedEvent |
| **≥ 30 days** (monthly/multi-month) | End of each month | MonthEndEvent (for active contracts) |
| **≥ 30 days** (final payment) | At contract completion | ContractCompletedEvent (for remaining days) |

**Examples:**

**Example 1: 15-day rental (Dec 10 - Dec 25)**
- Settlement: December 25 (contract completion)
- Provider receives full payment on December 25

**Example 2: 45-day rental (Dec 15 - Jan 30)**
- Settlement 1: December 31 (end of month) - Payment for Dec 15-31 (16 days)
- Settlement 2: January 30 (contract completion) - Payment for Jan 1-30 (30 days)

**Example 3: 3-month rental (Jan 1 - Mar 31)**
- Settlement 1: January 31 - Payment for January
- Settlement 2: February 28 - Payment for February  
- Settlement 3: March 31 - Payment for March

**Pro-Rata Calculation:**
```
Monthly Settlement Amount = (Total Contract Value / Total Days) × Days in Month
```

**NOTE:** This ensures providers receive regular monthly income for long-term contracts, improving cash flow.

---

## 11. DISPUTE RESOLUTION

### 11.1 Dispute Categories (MVP)

**Rule BR-034: Supported Dispute Types**

All 5 categories MUST be handled in MVP:

1. **Vehicle Condition Mismatch**
   - Business claims vehicle doesn't match specs
   - Evidence: Photos, contract specifications, delivery records

2. **Delivery No-Show Dispute**
   - Provider claims arrived, business claims no-show (or vice versa)
   - Evidence: GPS location, OTP attempts, communication logs

3. **Early Return Disagreement**
   - One party disputes early return terms or penalty
   - Evidence: Contract terms, notice period proof, communication logs

4. **Settlement Amount Disagreement**
   - Provider disputes calculated settlement amount
   - Evidence: Contract, commission rates, payment records

5. **Insurance Expiry During Contract**
   - Business claims provider's insurance expired during rental
   - Evidence: Insurance certificates, expiry dates, notification records

---

### 11.2 Dispute Evidence Requirements

**Rule BR-035: Required Evidence**

**All disputes must include:**
- Contract ID and details
- Party initiating dispute (business or provider)
- Dispute category (from BR-034)
- Detailed description
- Supporting evidence:
  - Photos (vehicle condition, delivery location)
  - GPS location data (delivery disputes)
  - OTP verification records
  - Communication logs (SMS, in-app messages)
  - Contract documents

---

### 11.3 Dispute Resolution Process

**Rule BR-036: Resolution Timeline and Process**

**Timeline:** 48 hours from dispute creation to resolution

**Process:**

**Step 1: Dispute Creation (Day 0)**
- Party creates dispute via app
- System notifies other party
- Both parties can submit evidence (24-hour window)

**Step 2: Evidence Review (Day 1)**
- Support team reviews all evidence
- May request additional information
- Both parties can view each other's evidence

**Step 3: Resolution (Day 2)**
- Support team makes decision based on evidence
- Decision communicated to both parties
- Action taken (refund, penalty, contract update, etc.)

**Escalation:**
- If unresolved after 48 hours → Escalate to senior support
- If still disputed → Legal arbitration (POST-MVP)

---

### 11.4 Dispute Outcomes

**Rule BR-037: Possible Dispute Resolutions**

| Dispute Type | Possible Outcomes |
|--------------|-------------------|
| Vehicle Condition Mismatch | Provider replaces vehicle OR Business accepts with discount OR Contract cancelled with full refund |
| Delivery No-Show | Penalty applied to no-show party OR Contract cancelled with refund |
| Early Return Disagreement | Penalty adjusted OR Original penalty upheld |
| Settlement Disagreement | Settlement recalculated OR Original settlement upheld |
| Insurance Expiry | Provider penalized, business compensated OR No action (if provider renewed on time) |

---

## 12. STATUS DEFINITIONS

### 12.1 RFQ Status Flow

**Rule BR-038: RFQ Status Definitions**

```
DRAFT → PUBLISHED → BIDDING → AWARDED / PARTIALLY_AWARDED → COMPLETED / CANCELLED
```

| Status | Definition | Transitions To |
|--------|-----------|----------------|
| `DRAFT` | RFQ created but not published | `PUBLISHED`, `CANCELLED` |
| `PUBLISHED` | RFQ visible to providers | `BIDDING` (after deadline starts) |
| `BIDDING` | Providers submitting bids | `AWARDED`, `PARTIALLY_AWARDED`, `CANCELLED` |
| `PARTIALLY_AWARDED` | Some line items awarded, others still bidding | `AWARDED`, `CANCELLED` |
| `AWARDED` | All line items awarded (all contracts created) | `COMPLETED` |
| `COMPLETED` | All contracts completed | (final state) |
| `CANCELLED` | RFQ cancelled by business | (final state) |

---

### 12.2 Bid Status Flow

**Rule BR-039: Bid Status Definitions**

```
BIDDING → AWARDED / LOST → REJECTED (if provider rejects) → BIDDING (re-activated)
```

| Status | Definition | Transitions To |
|--------|-----------|----------------|
| `BIDDING` | Bid submitted, awaiting award | `AWARDED`, `LOST`, `WITHDRAWN` |
| `AWARDED` | Bid selected by business | `REJECTED` (if provider rejects) |
| `LOST` | Bid not selected | `BIDDING` (if awarded bid rejected) |
| `REJECTED` | Provider rejected after award | (final state for this bid) |
| `WITHDRAWN` | Provider withdrew bid before award | (final state) |

---

### 12.3 Contract Status Flow

**Rule BR-040: Contract Status Definitions**

```
PENDING_ESCROW → PENDING_VEHICLE_ASSIGNMENT → PENDING_DELIVERY → ACTIVE → COMPLETED / TERMINATED
```

| Status | Definition | Next Status | Timeout |
|--------|-----------|-------------|---------|
| `PENDING_ESCROW` | Contract created, waiting for escrow lock | `PENDING_VEHICLE_ASSIGNMENT` | 5 days → Notify parties |
| `PENDING_VEHICLE_ASSIGNMENT` | Escrow locked, waiting for vehicle assignment | `PENDING_DELIVERY` | 5 days → Notify parties |
| `PENDING_DELIVERY` | Vehicle assigned, waiting for delivery confirmation | `ACTIVE` | 5 days → Notify parties |
| `ACTIVE` | All conditions met, contract running | `COMPLETED`, `TERMINATED` | (rental period) |
| `COMPLETED` | Rental period ended, vehicle returned | (final state) | - |
| `TERMINATED` | Contract cancelled or early return | (final state) | - |
| `TIMEOUT_PENDING` | Activation timeout reached | Manual intervention | - |

---

### 12.4 Vehicle Status Flow

**Rule BR-041: Vehicle Status Definitions**

```
PENDING_VERIFICATION → ACTIVE / REJECTED → ASSIGNED → ACTIVE (after return)
```

| Status | Definition | Transitions To |
|--------|-----------|----------------|
| `PENDING_VERIFICATION` | Vehicle submitted, awaiting insurance/document check | `ACTIVE`, `REJECTED` |
| `ACTIVE` | Vehicle verified, available for assignment | `ASSIGNED`, `SUSPENDED` |
| `ASSIGNED` | Vehicle assigned to contract | `ACTIVE` (after contract ends) |
| `SUSPENDED` | Vehicle suspended (insurance expired, maintenance, etc.) | `ACTIVE` (after issue resolved) |
| `REJECTED` | Vehicle rejected during verification | (final state) |

---

## APPENDIX A: Rule Change Log

| Version | Date | Changes | Approved By |
|---------|------|---------|-------------|
| 1.0 | Dec 21, 2025 | Initial authoritative version consolidating all business rules | Business Owner |

---

## APPENDIX B: Superseded Rules

**The following rules from previous documents are DEPRECATED and replaced by this document:**

1. ❌ `13_Movello_Business_Rules_Specification.md` - "Wallet balance required for RFQ creation" → Replaced by BR-002
2. ❌ `Business_Rules.md` - "Initial trust score = 0" → Replaced by BR-025 (verified users = 50)
3. ❌ Various documents - "Escrow lock before contract creation" → Replaced by BR-008 (contract before escrow)
4. ❌ Trust Engine Spec - "Complex signal-based decay algorithms" → Replaced by BR-025 (simple calculation)

---

**END OF AUTHORITATIVE BUSINESS RULES DOCUMENT**

---

**For Implementation Questions:** Refer to this document first. If rule is unclear or missing, escalate to business owner for clarification and document update.

**For Rule Conflicts:** This document takes precedence. Update conflicting documents to reference this authoritative version.
