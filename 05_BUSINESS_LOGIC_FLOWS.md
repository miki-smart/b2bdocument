# Movello MVP - Business Logic Flows

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Status:** Production-Ready Specification

---

## 📋 Table of Contents

1. [End-to-End Flow Overview](#end-to-end-flow-overview)
2. [Business Registration & KYB](#business-registration--kyb)
3. [Provider Registration & KYC](#provider-registration--kyc)
4. [Vehicle Registration & Insurance](#vehicle-registration--insurance)
5. [RFQ Creation & Bidding](#rfq-creation--bidding)
6. [Contract Creation & Activation](#contract-creation--activation)
7. [Delivery & OTP Verification](#delivery--otp-verification)
8. [Partial Fulfillment & Early Returns](#partial-fulfillment--early-returns)
9. [Settlement & Payouts](#settlement--payouts)
10. [Trust Score Calculation](#trust-score-calculation)

---

## 🔄 End-to-End Flow Overview

### Complete User Journey

```
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 1: ONBOARDING                          │
└─────────────────────────────────────────────────────────────────┘
    │
    ├─► Business Registration → KYB Verification → Wallet Creation
    │
    └─► Provider Registration → KYC Verification → Vehicle Registration
                                                   → Insurance Verification
                                                   → Wallet Creation

┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 2: MARKETPLACE                         │
└─────────────────────────────────────────────────────────────────┘
    │
    ├─► Business Creates RFQ (Multi-line items)
    │   └─► Escrow Capacity Check
    │
    ├─► Providers Submit Bids (Blind)
    │   └─► Vehicle Eligibility Check
    │   └─► Insurance Validation
    │
    └─► Business Awards Bids
        └─► Provider Identity Revealed
        └─► Contract Auto-Created

┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 3: CONTRACT & DELIVERY                 │
└─────────────────────────────────────────────────────────────────┘
    │
    ├─► Escrow Lock (Business Wallet)
    │
    ├─► Provider Assigns Vehicles
    │
    ├─► Delivery Session Created
    │   └─► OTP Generated & Sent
    │
    ├─► Business Verifies OTP
    │   └─► Handover Evidence Captured
    │   └─► Vehicle Assignment Activated
    │
    └─► Contract Becomes ACTIVE

┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 4: SETTLEMENT                          │
└─────────────────────────────────────────────────────────────────┘
    │
    ├─► Monthly Settlement Cycle
    │   └─► Calculate Gross Amount
    │   └─► Deduct Commission (Tier-based)
    │   └─► Release Escrow
    │
    ├─► Provider Payout
    │
    └─► Trust Score Update
```

---

## 👔 Business Registration & KYB

### Flow Diagram

```
START
  │
  ├─► User Signs Up (Keycloak)
  │   └─► Email Verification
  │
  ├─► User Selects "Business" Role
  │
  ├─► Submit Business Details
  │   ├─► Business Name
  │   ├─► Business Type (PLC, NGO, GOV)
  │   ├─► TIN Number
  │   ├─► Registration Number
  │   └─► Contact Info
  │
  ├─► System Creates:
  │   ├─► user_account (keycloak_id mapped)
  │   ├─► business (status = PENDING_KYB)
  │   ├─► business_profile
  │   └─► verification_request
  │
  ├─► Upload Required Documents
  │   ├─► Business License
  │   ├─► TIN Certificate
  │   ├─► Articles of Association
  │   └─► ID of Representative
  │
  ├─► Compliance Officer Reviews
  │   ├─► Verify Documents
  │   ├─► Check TIN with Tax Authority
  │   └─► Approve/Reject
  │
  ├─► IF APPROVED:
  │   ├─► business.status = ACTIVE
  │   ├─► Create wallet_account
  │   ├─► Assign business_tier (STANDARD default)
  │   └─► Send Welcome Email
  │
  └─► Business Can Now Create RFQs
END
```

### Business Rules

1. **TIN Validation:** Must be 10 digits, unique in system
2. **Document Requirements:** Based on `masterdata.kyc_requirement`
3. **Tier Assignment:** 
   - STANDARD: Default for all new businesses
   - BUSINESS_PRO: After 10 successful contracts
   - ENTERPRISE: Manual upgrade, contract required
   - GOV_NGO: Manual verification required
4. **Wallet Creation:** Automatic upon approval
5. **RFQ Limit:** 
   - STANDARD: 20 RFQs/month
   - BUSINESS_PRO: 50 RFQs/month
   - ENTERPRISE/GOV_NGO: Unlimited

---

## 🚗 Provider Registration & KYC

### Flow Diagram

```
START
  │
  ├─► User Signs Up (Keycloak)
  │
  ├─► User Selects "Provider" Role
  │
  ├─► Submit Provider Details
  │   ├─► Provider Type (INDIVIDUAL, AGENT, COMPANY)
  │   ├─► Name
  │   ├─► TIN (if applicable)
  │   └─► Contact Info
  │
  ├─► System Creates:
  │   ├─► user_account
  │   ├─► provider (status = PENDING_VERIFICATION)
  │   ├─► provider_profile
  │   ├─► provider_tier_assignment (BRONZE default)
  │   └─► verification_request
  │
  ├─► Upload Required Documents
  │   ├─► IF INDIVIDUAL:
  │   │   ├─► National ID
  │   │   └─► Driver's License
  │   ├─► IF AGENT:
  │   │   ├─► Agent Agreement
  │   │   └─► ID of Representative
  │   └─► IF COMPANY:
  │       ├─► Business License
  │       ├─► TIN Certificate
  │       └─► Vehicle Ownership Proof
  │
  ├─► Compliance Officer Reviews
  │
  ├─► IF APPROVED:
  │   ├─► provider.status = ACTIVE
  │   ├─► Create wallet_account
  │   ├─► Trust Score = 0 (initial)
  │   └─► Can Now Register Vehicles
  │
  └─► Provider Can Now Bid on RFQs
END
```

### Business Rules

1. **Provider Types:**
   - INDIVIDUAL: Solo car owner (1-5 vehicles)
   - AGENT: Fleet representative (6-20 vehicles)
   - COMPANY: Registered rental company (20+ vehicles)
2. **Initial Tier:** BRONZE (0-49 trust score)
3. **Tier Progression:**
   - SILVER: 50-69 trust score
   - GOLD: 70-84 trust score
   - PLATINUM: 85-100 trust score
4. **Commission Rates (Tier-based):**
   - BRONZE: 10%
   - SILVER: 8%
   - GOLD: 6%
   - PLATINUM: 5%

---

## 🚙 Vehicle Registration & Insurance

### Flow Diagram

```
START
  │
  ├─► Provider Submits Vehicle Details
  │   ├─► Plate Number (unique)
  │   ├─► Vehicle Type (EV_SEDAN, MINIBUS_12, etc.)
  │   ├─► Engine Type (EV, DIESEL, PETROL)
  │   ├─► Seat Count
  │   ├─► Brand & Model
  │   ├─► Tags (luxury, guest, vip)
  │   └─► Photos (5 angles)
  │
  ├─► System Creates:
  │   └─► vehicle (status = UNDER_REVIEW)
  │
  ├─► Upload Insurance Certificate
  │   ├─► Insurance Type (COMPREHENSIVE, THIRD_PARTY)
  │   ├─► Company Name
  │   ├─► Policy Number
  │   ├─► Coverage Amount
  │   ├─► Start Date
  │   ├─► End Date (CRITICAL)
  │   └─► Certificate PDF
  │
  ├─► System Creates:
  │   └─► vehicle_insurance (status = PENDING_VERIFICATION)
  │
  ├─► Compliance Officer Reviews
  │   ├─► Verify Photos Match Plate Number
  │   ├─► Check Insurance Certificate Authenticity
  │   ├─► Verify Coverage Dates
  │   └─► Check Expiry Date > 30 days from now
  │
  ├─► IF APPROVED:
  │   ├─► vehicle.status = ACTIVE
  │   ├─► vehicle_insurance.status = ACTIVE
  │   └─► Vehicle Can Now Be Assigned to Bids
  │
  ├─► System Monitors Insurance Expiry
  │   ├─► 30 days before expiry: Email warning
  │   ├─► 7 days before expiry: SMS + Email alert
  │   ├─► On expiry: vehicle.status = BLOCKED
  │   └─► Cannot be assigned to new contracts
  │
  └─► Provider Must Renew Insurance
END
```

### Business Rules

1. **Insurance Mandatory:** Zero tolerance - no insurance = no contracts
2. **Expiry Monitoring:** Automated daily job checks `coverage_end_date`
3. **Grace Period:** None - vehicle blocked immediately on expiry
4. **Renewal Process:** Upload new certificate, re-verification required
5. **Photo Requirements:**
   - Front: License plate visible
   - Back: Rear view
   - Left/Right: Side profiles
   - Interior: Cabin condition
6. **Vehicle Tags:** Used for matching RFQ preferences
   - `luxury`: High-end vehicles
   - `guest`: VIP/executive transport
   - `vip`: Premium service
   - `service`: Standard fleet
   - `family`: Family-friendly vehicles

---

## 📝 RFQ Creation & Bidding

### RFQ Creation Flow

```
START
  │
  ├─► Business Creates RFQ
  │   ├─► Title & Description
  │   ├─► Start Date & End Date
  │   ├─► Bid Deadline
  │   └─► Line Items (1-10)
  │       ├─► Vehicle Type
  │       ├─► Quantity Required
  │       ├─► With Driver (Y/N)
  │       └─► Preferred Tags
  │
  ├─► System Validates:
  │   ├─► Start Date >= Today + 3 days
  │   ├─► End Date > Start Date
  │   ├─► Bid Deadline < Start Date
  │   └─► Total Quantity <= 50 vehicles
  │   
  │   ⚠️ NOTE: NO escrow/wallet balance check at RFQ creation
  │   Businesses can create RFQs without depositing funds
  │
  ├─► System Creates:
  │   ├─► rfq (status = DRAFT)
  │   └─► rfq_line_item (for each line)
  │
  ├─► Business Reviews & Publishes
  │
  ├─► System Validates Again:
  │   └─► All validations pass
  │
  ├─► rfq.status = PUBLISHED
  │
  ├─► System Notifies Eligible Providers
  │   ├─► Filter by vehicle type availability
  │   ├─► Filter by insurance validity
  │   ├─► Filter by tier (if specified)
  │   └─► Send Email + In-App Notification
  │
  └─► Providers Can Now Bid
END
```

### Blind Bidding Flow

```
START
  │
  ├─► Provider Views Open RFQs
  │   └─► Filtered by their vehicle types
  │
  ├─► Provider Selects RFQ
  │   └─► Views Line Items
  │
  ├─► Provider Submits Bid
  │   ├─► For Each Line Item:
  │   │   ├─► Quantity Offered (≤ Quantity Required)
  │   │   ├─► Unit Price
  │   │   └─► Notes (optional)
  │   └─► Total Bid Amount Calculated
  │
  ├─► System Validates:
  │   ├─► Provider has enough ACTIVE vehicles
  │   ├─► All vehicles have valid insurance
  │   ├─► Unit Price >= Floor Price (from market data)
  │   ├─► Unit Price <= Ceiling Price (2x market average)
  │   └─► Provider not blacklisted
  │
  ├─► System Creates:
  │   ├─► rfq_bid (status = SUBMITTED)
  │   └─► rfq_bid_snapshot (with hashed provider ID)
  │       └─► hashed_provider_id = SHA256(provider_id + salt)
  │
  ├─► Business Views Bids (BLIND)
  │   ├─► Sees: "Provider •••4411"
  │   ├─► Sees: Quantity, Unit Price, Total
  │   └─► CANNOT see: Provider name, tier, trust score
  │
  └─► Bidding Continues Until Deadline
END
```

### Award Flow

```
START
  │
  ├─► Bid Deadline Passes
  │   └─► rfq.status = BIDDING_CLOSED
  │
  ├─► Business Reviews All Bids
  │   └─► Sorted by: Price (ascending), Quantity (descending)
  │
  ├─► Business Selects Winners
  │   ├─► Can award to multiple providers per line item
  │   ├─► Can partial award (e.g., 3 of 5 vehicles)
  │   └─► Total awarded ≤ Quantity required
  │
  ├─► System Calculates Required Escrow
  │   ├─► For Each Award:
  │   │   └─► escrow_required += quantity × unit_price × escrow_multiplier
  │   └─► Total Escrow Required = SUM(all awards)
  │
  ├─► System Checks Business Wallet Balance
  │   ├─► available_balance = wallet.balance - wallet.locked_balance
  │   │
  │   ├─► IF available_balance >= total_escrow_required:
  │   │   └─► ✅ Proceed with full award
  │   │
  │   ├─► IF available_balance < total_escrow_required:
  │   │   ├─► ⚠️ INSUFFICIENT FUNDS
  │   │   │
  │   │   ├─► OPTION 1: Reject Award
  │   │   │   └─► Show error: "Insufficient balance. Required: X, Available: Y"
  │   │   │
  │   │   ├─► OPTION 2: Partial Award (Recommended)
  │   │   │   ├─► Calculate max affordable quantity
  │   │   │   ├─► max_qty = FLOOR(available_balance / (unit_price × escrow_multiplier))
  │   │   │   ├─► Suggest: "You can award up to X vehicles with current balance"
  │   │   │   └─► Business adjusts award quantity
  │   │   │
  │   │   └─► OPTION 3: Deposit More Funds
  │   │       ├─► Redirect to wallet top-up
  │   │       ├─► After deposit, retry award
  │   │       └─► Award remains in PENDING state
  │   │
  │   └─► Business Confirms Award (with adjusted quantity if needed)
  │
  ├─► System Validates Final Award:
  │   ├─► Wallet balance sufficient ✅
  │   ├─► Awarded providers still ACTIVE ✅
  │   ├─► Awarded vehicles still available ✅
  │   └─► Insurance still valid ✅
  │
  ├─► System Creates:
  │   ├─► rfq_bid_award (for each award)
  │   └─► Provider identity NOW REVEALED
  │
  ├─► System Publishes Event:
  │   └─► BidAwardedEvent
  │       ├─► rfqId
  │       ├─► lineItemId
  │       ├─► providerId (now visible)
  │       ├─► quantityAwarded
  │       ├─► unitPrice
  │       └─► escrowAmount (to be locked)
  │
  ├─► Contracts Module Consumes Event
  │   └─► Auto-creates contract
  │
  ├─► Finance Module Locks Escrow (CRITICAL STEP)
  │   ├─► Validate wallet balance again (race condition check)
  │   ├─► IF sufficient:
  │   │   ├─► Debit business wallet
  │   │   ├─► Credit escrow virtual wallet
  │   │   ├─► Create escrow_lock record
  │   │   └─► Publish EscrowLockedEvent
  │   └─► IF insufficient:
  │       ├─► Rollback contract creation
  │       ├─► Cancel award
  │       └─► Notify business: "Award failed - insufficient funds"
  │
  └─► Notifications Sent
      ├─► To Business: "Award successful, escrow locked: ETB X"
      └─► To Providers: "Congratulations, you won!"
END
```

### Partial Award Example

**Scenario:**
- RFQ Line Item: 10 EV Sedans needed
- Winning Bid: ETB 3,500/vehicle
- Escrow Multiplier: 1.0 (100% upfront for monthly contracts)
- Total Required: 10 × 3,500 = ETB 35,000

**Business Wallet:**
- Balance: ETB 50,000
- Locked (other contracts): ETB 40,000
- **Available: ETB 10,000**

**Award Options:**

```
OPTION 1: Full Award (REJECTED)
- Quantity: 10 vehicles
- Required: ETB 35,000
- Available: ETB 10,000
- Result: ❌ INSUFFICIENT FUNDS

OPTION 2: Partial Award (ACCEPTED)
- Max Affordable: FLOOR(10,000 / 3,500) = 2 vehicles
- Award Quantity: 2 vehicles
- Escrow Required: 2 × 3,500 = ETB 7,000
- Remaining Balance: 10,000 - 7,000 = ETB 3,000
- Result: ✅ SUCCESS
- Note: Business can award remaining 8 vehicles later after depositing more funds

OPTION 3: Deposit & Full Award
- Business deposits: ETB 30,000
- New Available Balance: 10,000 + 30,000 = ETB 40,000
- Award Quantity: 10 vehicles
- Escrow Required: ETB 35,000
- Remaining Balance: 40,000 - 35,000 = ETB 5,000
- Result: ✅ SUCCESS
```


### Business Rules

1. **RFQ Limits:**
   - STANDARD: 20 RFQs/month
   - BUSINESS_PRO: 50 RFQs/month
   - ENTERPRISE/GOV_NGO: Unlimited
2. **RFQ Creation:** ✅ **NO wallet balance required** - businesses can create RFQs freely
3. **Award Requirement:** ⚠️ **Wallet balance REQUIRED** - must have sufficient funds to lock escrow
4. **Partial Awards:** ✅ **Allowed** - business can award based on available funds
   - System calculates max affordable quantity
   - Business can deposit more funds and award remaining vehicles later
5. **Bid Deadline:** Minimum 24 hours from publication
6. **Start Date:** Minimum 3 days from publication
7. **Blind Bidding:** Provider identity hidden until award
8. **Split Awards:** Allowed (multiple providers per line item)
9. **Price Validation:**
   - Floor: 50% of market average
   - Ceiling: 200% of market average
10. **Market Price:** Calculated from last 30 days of contracts
11. **Escrow Lock Timing:** Happens immediately after award confirmation
12. **Escrow Multiplier:**
    - Monthly contracts: 1.0 (100% of contract value)
    - Event contracts: 1.0 (100% upfront)
13. **Race Condition Protection:** Wallet balance validated twice:
    - At award submission
    - At escrow lock (prevents concurrent spending)


---

## 📜 Contract Creation & Activation

### Contract Creation (Automatic)

```
START (Triggered by BidAwardedEvent)
  │
  ├─► Contracts Module Receives Event
  │
  ├─► Check if Contract Exists
  │   └─► IF NO: Create contract
  │       ├─► contract_number = "CNT-YYYY-NNNN"
  │       ├─► rfq_id
  │       ├─► business_id
  │       ├─► status = PENDING_ACTIVATION
  │       ├─► start_date_planned
  │       ├─► end_date_planned
  │       └─► Get active commission_strategy_version
  │
  ├─► Create Immutable Party Snapshots
  │   ├─► contract_party_business
  │   │   ├─► business_name (frozen)
  │   │   ├─► tier_code (frozen)
  │   │   ├─► contact_info (frozen)
  │   │   └─► snapshot_at = now()
  │   └─► contract_party_provider
  │       ├─► provider_name (frozen)
  │       ├─► tier_code (frozen at award time)
  │       ├─► trust_score (frozen)
  │       └─► snapshot_at = now()
  │
  ├─► Create Contract Line Item
  │   ├─► contract_line_id
  │   ├─► rfq_line_item_id
  │   ├─► provider_id
  │   ├─► quantity_awarded
  │   ├─► quantity_active = 0 (initially)
  │   ├─► unit_amount
  │   ├─► total_amount = quantity × unit_amount
  │   ├─► commission_rate (from provider tier)
  │   └─► status = PENDING_ACTIVATION
  │
  ├─► Create Policy Snapshot (JSONB)
  │   └─► contract_policy_snapshot
  │       ├─► commission_rate
  │       ├─► early_return_penalty
  │       ├─► no_show_penalty
  │       ├─► late_delivery_penalty
  │       └─► settlement_frequency
  │
  ├─► Publish Events
  │   ├─► ContractCreatedEvent
  │   └─► EscrowLockRequestedEvent
  │
  ├─► Finance Module Locks Escrow
  │   ├─► Calculate escrow_amount
  │   │   └─► total_amount × escrow_policy_multiplier
  │   ├─► Debit business wallet
  │   ├─► Credit escrow virtual wallet
  │   └─► Create escrow_lock record
  │
  └─► Notify Parties
      ├─► Business: "Contract created, escrow locked"
      └─► Provider: "Contract ready, assign vehicles"
END
```

### Vehicle Assignment & Activation

```
START
  │
  ├─► Provider Assigns Vehicles to Contract Line
  │   ├─► Select vehicle_id
  │   ├─► Validate:
  │   │   ├─► Vehicle is ACTIVE
  │   │   ├─► Insurance is valid
  │   │   ├─► Not assigned to another active contract
  │   │   └─► Matches line item requirements
  │   └─► Create contract_vehicle_assignment
  │       └─► status = PENDING_DELIVERY
  │
  ├─► System Creates Delivery Session
  │   ├─► delivery_session
  │   │   ├─► contract_vehicle_assignment_id
  │   │   ├─► business_id
  │   │   ├─► provider_id
  │   │   ├─► vehicle_id
  │   │   └─► status = PENDING
  │   └─► Publish DeliverySessionCreatedEvent
  │
  ├─► Provider Initiates Delivery
  │   └─► Triggers OTP Generation
  │
  ├─► System Generates OTP
  │   ├─► Generate 6-digit code
  │   ├─► Hash with SHA-256
  │   ├─► Store in delivery_otp
  │   │   ├─► otp_code_hash
  │   │   ├─► expires_at = now() + 5 minutes
  │   │   └─► attempts = 0
  │   └─► Send OTP to Business Contact
  │       └─► Via SMS + Email
  │
  ├─► Business Receives OTP
  │   └─► Enters OTP in App
  │
  ├─► System Verifies OTP
  │   ├─► Check:
  │   │   ├─► Hash matches
  │   │   ├─► Not expired
  │   │   ├─► Attempts < 3
  │   │   └─► Not already verified
  │   ├─► IF VALID:
  │   │   ├─► delivery_otp.is_verified = true
  │   │   ├─► delivery_otp.verified_at = now()
  │   │   └─► Proceed to handover
  │   └─► IF INVALID:
  │       ├─► Increment attempts
  │       └─► IF attempts >= 3: Block for 30 minutes
  │
  ├─► Capture Handover Evidence
  │   ├─► Upload 5 photos (front, back, left, right, interior)
  │   ├─► Record odometer reading
  │   ├─► Record fuel level
  │   ├─► Optional notes
  │   └─► Store in delivery_vehicle_handover
  │
  ├─► System Activates Vehicle Assignment
  │   ├─► contract_vehicle_assignment.status = ACTIVE
  │   ├─► contract_vehicle_assignment.start_date_actual = now()
  │   ├─► Increment contract_line_item.quantity_active
  │   └─► IF first activation on line:
  │       └─► contract_line_item.status = ACTIVE
  │
  ├─► IF all line items activated:
  │   └─► contract.status = ACTIVE
  │
  └─► Publish Events
      ├─► VehicleAssignmentActivatedEvent
      ├─► ContractLineActivatedEvent
      └─► ContractActivatedEvent
END
```

### Business Rules

1. **Escrow Lock:** Required before vehicle assignment
2. **Escrow Amount:** 
   - Monthly contracts: 1 month rent
   - Event contracts: 100% upfront
3. **OTP Expiry:** 5 minutes
4. **OTP Attempts:** Maximum 3, then 30-minute lockout
5. **Photo Evidence:** Mandatory for all deliveries
6. **Activation:** Only after OTP verification + evidence capture
7. **Contract Status:**
   - PENDING_ACTIVATION: Created, escrow locked
   - ACTIVE: At least one vehicle activated
   - COMPLETED: All vehicles returned, settlement done
   - TERMINATED: Cancelled before completion

---

## 🔄 Partial Fulfillment & Early Returns

### Early Return Flow

```
START
  │
  ├─► Business Requests Early Return
  │   ├─► Select vehicle_assignment_id
  │   ├─► Provide return_reason
  │   │   ├─► CLIENT_REQUEST
  │   │   ├─► VEHICLE_ISSUE
  │   │   └─► CONTRACT_CHANGE
  │   └─► Optional notes
  │
  ├─► System Validates:
  │   ├─► Assignment is ACTIVE
  │   ├─► Not already returned
  │   └─► Business has authority
  │
  ├─► Create Return Session
  │   └─► delivery_return_session
  │       ├─► contract_vehicle_assignment_id
  │       ├─► return_reason
  │       └─► status = PENDING
  │
  ├─► Provider Brings Vehicle Back
  │   └─► Capture Return Evidence
  │       ├─► 5 photos (condition check)
  │       ├─► Odometer reading
  │       ├─► Fuel level
  │       └─► Damage notes (if any)
  │
  ├─► System Calculates Proration
  │   ├─► days_used = end_date_actual - start_date_actual
  │   ├─► days_total = end_date_planned - start_date_planned
  │   ├─► usage_ratio = days_used / days_total
  │   ├─► amount_used = total_amount × usage_ratio
  │   ├─► amount_refundable = total_amount - amount_used
  │   └─► Apply early_return_penalty (from policy)
  │       └─► penalty_amount = amount_refundable × penalty_rate
  │       └─► net_refund = amount_refundable - penalty_amount
  │
  ├─► System Updates Contract
  │   ├─► contract_vehicle_assignment.status = RETURNED_EARLY
  │   ├─► contract_vehicle_assignment.end_date_actual = now()
  │   ├─► Decrement contract_line_item.quantity_active
  │   └─► IF quantity_active > 0:
  │       └─► contract_line_item.status = PARTIAL_RETURN
  │       ELSE:
  │       └─► contract_line_item.status = COMPLETED
  │
  ├─► System Creates Penalty Record
  │   └─► contract_penalty
  │       ├─► contract_id
  │       ├─► penalty_type = EARLY_RETURN
  │       ├─► penalty_amount
  │       └─► applied_at = now()
  │
  ├─► Finance Module Processes Settlement
  │   ├─► Release escrow for used portion
  │   │   └─► amount_used - commission
  │   ├─► Refund to business
  │   │   └─► net_refund
  │   └─► Platform keeps penalty + commission
  │
  └─► Publish Events
      ├─► VehicleReturnedEarlyEvent
      └─► PartialSettlementCompletedEvent
END
```

### Under-Delivery Handling

```
START (When provider cannot fulfill full quantity)
  │
  ├─► Provider Assigns Fewer Vehicles Than Awarded
  │   └─► Example: Awarded 5, only assigns 3
  │
  ├─► System Tracks:
  │   ├─► contract_line_item.quantity_awarded = 5
  │   ├─► contract_line_item.quantity_active = 3
  │   └─► Under-delivery = 2 vehicles
  │
  ├─► Business Options:
  │   ├─► OPTION 1: Accept Partial Fulfillment
  │   │   ├─► Adjust contract amount
  │   │   ├─► Release excess escrow
  │   │   └─► Contract proceeds with 3 vehicles
  │   │
  │   ├─► OPTION 2: Request Replacement
  │   │   ├─► Provider has 24 hours to assign
  │   │   └─► IF not fulfilled: Apply penalty
  │   │
  │   └─► OPTION 3: Cancel Line Item
  │       ├─► Terminate unfulfilled portion
  │       ├─► Apply no-show penalty
  │       └─► Release escrow
  │
  ├─► System Applies Penalties (if applicable)
  │   └─► contract_penalty
  │       ├─► penalty_type = UNDER_DELIVERY
  │       ├─► penalty_amount = unfulfilled_qty × unit_price × penalty_rate
  │       └─► Deducted from provider settlement
  │
  └─► Update Trust Score
      └─► Negative impact for under-delivery
END
```

### Business Rules

1. **Early Return Penalty:**
   - STANDARD tier: 25% of remaining amount
   - BUSINESS_PRO: 20%
   - ENTERPRISE/GOV_NGO: 15%
2. **Proration:** Daily basis (days_used / days_total)
3. **Under-Delivery Penalty:** 10% of unfulfilled amount
4. **No-Show Penalty:** 15% of total contract value
5. **Grace Period:** 24 hours for replacement vehicles
6. **Trust Score Impact:**
   - Early return: -2 points
   - Under-delivery: -5 points
   - No-show: -10 points

---

## 💰 Settlement & Payouts

### Monthly Settlement Cycle

```
START (Runs on 1st of each month)
  │
  ├─► System Identifies Completed Contracts
  │   └─► WHERE end_date_actual BETWEEN last_month_start AND last_month_end
  │
  ├─► For Each Provider:
  │   ├─► Create settlement_cycle
  │   │   ├─► provider_id
  │   │   ├─► period_start = last_month_start
  │   │   ├─► period_end = last_month_end
  │   │   └─► status = PENDING
  │   │
  │   ├─► Calculate Gross Amount
  │   │   └─► SUM(contract_line_item.total_amount)
  │   │       WHERE provider_id = provider
  │   │       AND status = COMPLETED
  │   │       AND end_date_actual IN period
  │   │
  │   ├─► Calculate Commission
  │   │   ├─► Get provider tier at contract time
  │   │   ├─► commission_rate from tier
  │   │   └─► commission_amount = gross_amount × commission_rate
  │   │
  │   ├─► Deduct Penalties (if any)
  │   │   └─► SUM(contract_penalty.penalty_amount)
  │   │       WHERE provider_id = provider
  │   │       AND applied_at IN period
  │   │
  │   ├─► Calculate Net Payable
  │   │   └─► net_payable = gross_amount - commission - penalties
  │   │
  │   └─► Update settlement_cycle
  │       ├─► total_gross_amount
  │       ├─► total_commission_amount
  │       ├─► total_penalties
  │       └─► total_net_payable
  │
  ├─► Finance Module Processes Payout
  │   ├─► Create wallet_ledger_transaction
  │   │   └─► transaction_type = SETTLEMENT_PAYOUT
  │   │
  │   ├─► Double-Entry Ledger:
  │   │   ├─► DEBIT escrow_wallet (gross_amount)
  │   │   ├─► CREDIT provider_wallet (net_payable)
  │   │   └─► CREDIT platform_commission_wallet (commission + penalties)
  │   │
  │   └─► Create settlement_payout
  │       ├─► settlement_cycle_id
  │       ├─► amount = net_payable
  │       ├─► status = COMPLETED
  │       └─► paid_at = now()
  │
  ├─► Update Settlement Cycle
  │   └─► settlement_cycle.status = COMPLETED
  │
  ├─► Create Commission Entry
  │   └─► commission_entry
  │       ├─► settlement_cycle_id
  │       ├─► commission_amount
  │       └─► commission_rate
  │
  └─► Notify Provider
      └─► Email: "Settlement processed: ETB X deposited"
END
```

### Business Rules

1. **Settlement Frequency:**
   - BRONZE/SILVER: Monthly (1st of month)
   - GOLD: Bi-weekly (1st and 15th)
   - PLATINUM: Weekly (every Monday)
2. **Commission Rates:**
   - BRONZE: 10%
   - SILVER: 8%
   - GOLD: 6%
   - PLATINUM: 5%
3. **Payout Timeline:** Within 3 business days of settlement calculation
4. **Minimum Payout:** ETB 1,000 (accumulates if below)
5. **Penalties Deducted:** Before payout
6. **Tax Withholding:** 2% WHT (future feature)

---

## ⭐ Trust Score Calculation

### Calculation Algorithm

```
START (Triggered by contract completion or monthly recalculation)
  │
  ├─► Gather Provider Metrics (Last 90 Days)
  │   ├─► total_contracts_completed
  │   ├─► total_contracts_awarded
  │   ├─► on_time_deliveries
  │   ├─► total_deliveries
  │   ├─► early_returns_count
  │   ├─► no_show_count
  │   ├─► under_delivery_count
  │   ├─► average_rating (from business feedback)
  │   └─► dispute_count
  │
  ├─► Calculate Component Scores (0-100 each)
  │   │
  │   ├─► Completion Rate Score (Weight: 30%)
  │   │   └─► (contracts_completed / contracts_awarded) × 100
  │   │
  │   ├─► On-Time Delivery Score (Weight: 25%)
  │   │   └─► (on_time_deliveries / total_deliveries) × 100
  │   │
  │   ├─► Reliability Score (Weight: 20%)
  │   │   └─► 100 - (no_show_count × 10) - (under_delivery_count × 5)
  │   │
  │   ├─► Quality Score (Weight: 15%)
  │   │   └─► average_rating × 20 (rating is 1-5 scale)
  │   │
  │   └─► Dispute Score (Weight: 10%)
  │       └─► 100 - (dispute_count × 15)
  │
  ├─► Calculate Weighted Average
  │   └─► trust_score = 
  │       (completion_score × 0.30) +
  │       (on_time_score × 0.25) +
  │       (reliability_score × 0.20) +
  │       (quality_score × 0.15) +
  │       (dispute_score × 0.10)
  │
  ├─► Apply Penalties (Immediate Deductions)
  │   ├─► Early return: -2 points
  │   ├─► Under-delivery: -5 points
  │   ├─► No-show: -10 points
  │   └─► Dispute lost: -15 points
  │
  ├─► Clamp Score (0-100)
  │   └─► trust_score = MAX(0, MIN(100, trust_score))
  │
  ├─► Determine Tier
  │   ├─► IF score >= 85: PLATINUM
  │   ├─► IF score >= 70: GOLD
  │   ├─► IF score >= 50: SILVER
  │   └─► ELSE: BRONZE
  │
  ├─► Store History
  │   └─► provider_trust_score_history
  │       ├─► old_score
  │       ├─► new_score
  │       ├─► reason = "AUTOMATIC_RECALCULATION"
  │       └─► calculation_snapshot (JSON with all metrics)
  │
  ├─► IF Tier Changed:
  │   ├─► Update provider_tier_assignment
  │   ├─► Publish TierChangedEvent
  │   └─► Notify Provider
  │       └─► "Congratulations! You're now GOLD tier"
  │
  └─► Update provider.trust_score
END
```

### Trust Score Examples

**Example 1: New Provider (BRONZE)**
```json
{
  "total_contracts": 2,
  "completed": 2,
  "on_time": 2,
  "no_shows": 0,
  "early_returns": 0,
  "average_rating": 4.5,
  "disputes": 0,
  
  "completion_rate": 100,
  "on_time_rate": 100,
  "reliability": 100,
  "quality": 90,
  "dispute_score": 100,
  
  "trust_score": 98,
  "tier": "PLATINUM" // Fast track!
}
```

**Example 2: Problematic Provider**
```json
{
  "total_contracts": 20,
  "completed": 15,
  "on_time": 12,
  "no_shows": 2,
  "early_returns": 3,
  "average_rating": 3.2,
  "disputes": 1,
  
  "completion_rate": 75,
  "on_time_rate": 60,
  "reliability": 65, // Penalized for no-shows
  "quality": 64,
  "dispute_score": 85,
  
  "trust_score": 69,
  "tier": "SILVER"
}
```

### Business Rules

1. **Initial Score:** 0 (new providers)
2. **Minimum Contracts:** 5 contracts before tier promotion
3. **Recalculation Frequency:** 
   - After each contract completion
   - Monthly batch recalculation
4. **Tier Demotion:** Immediate if score drops below threshold
5. **Tier Promotion:** Requires 3 consecutive months above threshold
6. **Dispute Impact:** -15 points if provider loses dispute
7. **Recovery:** Providers can recover score through good performance

---

**Next Document:** [04_MODULE_SPECIFICATIONS/Identity_and_Compliance_Module.md](./04_MODULE_SPECIFICATIONS/Identity_and_Compliance_Module.md)
