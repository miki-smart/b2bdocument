# Anqelba Car Rental MVP - Business Logic Flows

**Version:** 2.0
**Last verified against code: 2026-07-23**
**Status:** Reconciled against running code (backend `Marketplace.API` `Modules/**`, web `anqelbacarrental-marketplace-core`, both Flutter mobile apps)

**How to read this document:** every flow below describes what the code actually does today, not an aspirational design. Where a step, status, or number differs from earlier drafts of this document, a **Reality Check** note explains the correction. Where a described capability is not built at all, it is marked **NOT YET IMPLEMENTED**. The canonical, numbered rule reference is [`MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md`](./MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md) — BR-IDs referenced below (e.g. BR-010, BR-025, BR-031A) match that document and, where noted, actual code comments.

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
11. [Direct Rental (Vehicle Catalog)](#direct-rental-vehicle-catalog)

---

## 🔄 End-to-End Flow Overview

### Complete User Journey (real shape)

```
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 1: ONBOARDING                          │
└─────────────────────────────────────────────────────────────────┘
    │
    ├─► Business Registration → KYB Verification → Wallet (MAIN) Creation
    │
    └─► Provider Registration → KYC Verification → Vehicle Registration
                                                   → Insurance Verification
                                                   → Wallet (MAIN) Creation
                                                   → TrustScore = 50, Tier = SILVER (hardcoded defaults)

┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 2: MARKETPLACE (RFQ + Bidding)          │
└─────────────────────────────────────────────────────────────────┘
    │
    ├─► Business Creates RFQ (header + 1..N line items)
    │   └─► NO wallet/escrow check at creation or publish (BR-002)
    │
    ├─► Providers Submit Bids (blind at UI level — see Reality Check in §5)
    │   └─► Fleet segment eligibility check only — no specific vehicle chosen yet
    │
    └─► Business Awards Bids (wallet balance REQUIRED — BR-006)
        └─► Provider identity revealed on award
        └─► Contract auto-created (BidAwardedEvent → CreateContractCommand)

┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 3: CONTRACT, ASSIGNMENT & DELIVERY      │
└─────────────────────────────────────────────────────────────────┘
    │
    ├─► Escrow Lock (Finance module, reacting to ContractCreatedEvent, 5-retry backoff — BR-010/BR-011)
    │
    ├─► Provider Assigns Specific Vehicles to Contract Line Items
    │
    ├─► Dual-Party Contract Terms OTP (Signing Gate — distinct from delivery OTP)
    │   └─► Status: PENDING_SIGNING → (momentary, never-persisted SIGNED) → PENDING_DELIVERY
    │
    ├─► Delivery Session Created per Vehicle
    │   └─► Vehicle inspection checklist submitted + approved (hard gate — no checklist, no OTP)
    │   └─► OTP Generated & Sent (SMS/email; never returned by any API response)
    │
    ├─► Provider Verifies OTP (business tells provider the code)
    │   └─► No photo/odometer "handover evidence" captured in the live flow
    │   └─► That specific vehicle assignment → DELIVERED
    │
    └─► Contract reaches ACTIVE only once EVERY awarded vehicle is delivered

┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 4: SETTLEMENT                          │
└─────────────────────────────────────────────────────────────────┘
    │
    ├─► Daily Ledger Accrual (00:05 UTC job, double-entry, no wallet-money-release yet)
    │
    ├─► Settlement Cycle Generation — fixed 30-day rolling window per contract (NOT tier-based cadence)
    │   └─► Calculate Gross Amount from actual vehicle activity (BR-031A)
    │   └─► Deduct Commission (rate snapshotted at award time, from provider tier)
    │   └─► Deduct Withholding Tax (2% default)
    │
    ├─► Admin Approves Payout → Escrow Release (provider MAIN + platform COMMISSION + platform TAX)
    │
    └─► Trust Score Update — **NOT YET IMPLEMENTED**: the formula exists but nothing calls it on
        contract completion, delivery, no-show, or rejection today (see §10)
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
  │   ├─► Business Type (PLC, NGO, GOV, etc.)
  │   ├─► TIN Number (unique, 10 digits)
  │   ├─► Registration Number
  │   └─► Contact Info
  │
  ├─► System Creates:
  │   ├─► user_account (keycloak_id mapped)
  │   ├─► business (pending verification)
  │   ├─► business_profile
  │   └─► verification_request
  │
  ├─► Upload Required Documents
  │   ├─► Business License
  │   ├─► TIN Certificate
  │   ├─► Articles of Association
  │   └─► ID of Representative
  │
  ├─► Compliance Officer Reviews (manual for MVP)
  │   ├─► Verify Documents
  │   ├─► Check TIN with Tax Authority (manual, not an API integration)
  │   └─► Approve/Reject
  │
  ├─► IF APPROVED:
  │   ├─► business status → verified/active
  │   ├─► Create wallet_account (MAIN, ETB, balance 0)
  │   ├─► Assign business_tier = STANDARD (default)
  │   └─► Send Welcome Notification
  │
  └─► Business Can Now Create RFQs
END
```

### Business Rules

1. **TIN Validation:** Must be 10 digits, unique in system.
2. **Document Requirements:** Based on configured KYC/KYB requirement master data.
3. **Business Tier Assignment (real, live):**
   - `STANDARD`: default for all new businesses.
   - `BUSINESS_PRO` / `ENTERPRISE` / `GOV_NGO`: exist as `BusinessTier` master data rows with volume-limit fields (`MaxRFQsPerMonth`, `MaxActiveContracts`, `MaxVehiclesPerRFQ`).
   - **Reality Check:** business tier governs **volume limits only** — it does not affect commission, penalty rates, or settlement cadence anywhere in code. An automatic, activity-based tier-upgrade rule ("10 successful contracts → Business Pro") was **not confirmed as implemented** — treat any such automatic-upgrade description as aspirational unless re-verified against a real command/handler.
4. **Wallet Creation:** Automatic `MAIN` wallet upon approval (`BusinessRegisteredWalletHandler`).
5. **RFQ volume limits:** `BusinessTier.MaxRFQsPerMonth`/`MaxActiveContracts` exist as configurable fields on the master-data entity (`CanCreateRFQ`/`CanHaveContract` guard methods exist on `BusinessTier`), but whether these guards are actually invoked at RFQ-creation time was **not independently re-confirmed** this pass — do not assume enforcement is live without checking `CreateRFQCommandHandler`.

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
  ├─► System Creates (Provider.Create()):
  │   ├─► user_account
  │   ├─► provider — TrustScore = 50 (hardcoded default, NOT 0)
  │   ├─► provider_profile
  │   ├─► provider_tier_assignment = SILVER (hardcoded default, NOT Bronze) ← Reality Check below
  │   └─► verification_request
  │
  ├─► Upload Required Documents
  │   ├─► IF INDIVIDUAL: National ID, Driver's License
  │   ├─► IF AGENT: Agent Agreement, ID of Representative
  │   └─► IF COMPANY: Business License, TIN Certificate, Vehicle Ownership Proof
  │
  ├─► Compliance Officer Reviews (manual for MVP)
  │
  ├─► IF APPROVED:
  │   ├─► provider status → verified/active
  │   ├─► Create wallet_account (MAIN)
  │   └─► Can Now Register Vehicles
  │
  └─► Provider Can Now Bid on RFQs (also requires ≥1 verified, matching-type vehicle)
END
```

**Reality Check — initial trust score and tier:** `Provider.Create()` hardcodes `TrustScore = 50` and tier `SILVER` for **every** new provider, unconditionally. This directly contradicts earlier drafts of this document (and `Business_Rules.md`'s previous version) that said new providers start at `BRONZE`/trust score `0`. A separate, dormant "hybrid" tier-calculation model (`TierCalculationService`, code-commented `BR-041`/`BR-042`) *would* start unverified or incomplete-profile providers at `BRONZE` and score-gate the rest — but it has **zero production call sites**, so it never actually runs at registration time. Every provider, verified or not, starts at `SILVER`/`50` today.

### Business Rules

1. **Provider Types:** `INDIVIDUAL` / `AGENT` / `COMPANY` exist as a categorization; a specific enforced numeric fleet-size gate per type was not reconfirmed this pass.
2. **Initial Tier (real, live):** `SILVER`, trust score `50` — for every new provider, unconditionally (see Reality Check above).
3. **Tier Progression (dormant, not live):** two different, disagreeing threshold schemes exist in code (see §10) — neither auto-recalculates a provider's tier today. Tier changes today are **admin-manual only**, via `AssignProviderTierCommand`.
4. **Commission Rates (real, live, tier-based):**
   - `BRONZE`: 10%
   - `SILVER`: 8%
   - `GOLD`: 6%
   - `PLATINUM`: 5%
   - Source: seeded `ProviderTier.CommissionRate` (`MasterDataSeeder.SeedProviderTiersAsync`), admin-editable. No "Red Zone" tier exists in code.

---

## 🚙 Vehicle Registration & Insurance

### Flow Diagram

```
START
  │
  ├─► Provider Submits Vehicle Details
  │   ├─► Plate Number (unique)
  │   ├─► Vehicle Type (EV_SEDAN, MINIBUS_12, etc.)
  │   ├─► Engine/Fuel Type (EV, DIESEL, PETROL, ...)
  │   ├─► Seat Count, Brand & Model
  │   ├─► Tags (luxury, guest, vip, etc.)
  │   └─► Photos (multi-angle)
  │
  ├─► System Creates: vehicle (pending review)
  │
  ├─► Upload Insurance Certificate
  │   ├─► Insurance Type (COMPREHENSIVE, THIRD_PARTY)
  │   ├─► Company Name, Policy Number, Coverage Amount
  │   ├─► Start Date / End Date
  │   └─► Certificate document
  │
  ├─► System Creates: vehicle_insurance (pending verification)
  │
  ├─► Compliance Officer Reviews (manual for MVP)
  │
  ├─► IF APPROVED:
  │   ├─► vehicle.status = APPROVED
  │   ├─► vehicle_insurance.status = ACTIVE
  │   └─► Vehicle can now be bid, assigned to a contract, or enabled for Direct Rental
  │
  └─► Provider Must Renew Insurance Before Expiry (zero-tolerance enforcement)
END
```

### Business Rules

1. **Insurance Mandatory:** Zero tolerance — a vehicle without valid insurance cannot be listed, bid, assigned, or enabled for Direct Rental. Confirmed as an enforced gate.
2. **Expiry Monitoring / Grace Period:** an automated expiry-scan job and specific notification cadence (e.g. "30/7 days before expiry") was **not independently re-confirmed as implemented** this pass — treat any specific day-count notification schedule as directional unless re-verified against a real background job.
3. **Vehicle Tags:** used for RFQ preference matching (`luxury`/`guest`/`vip`/`service`/`family`-style tags) — the exact tag vocabulary should be confirmed against current `VehicleTag` master data before quoting it as fixed.
4. **Direct Rental opt-in:** `Vehicle.IsAvailableForDirectRental` and `DailyRentalRate` are separate, provider-controlled fields, independent of RFQ/bidding eligibility (see §11).

---

## 📝 RFQ Creation & Bidding

### RFQ Creation Flow

```
START
  │
  ├─► Business Creates RFQ
  │   ├─► Title, submission deadline, RFQ type (STANDARD/URGENT/LONG_TERM)
  │   ├─► Optional pickup/dropoff city
  │   └─► 1..N Line Items, each with:
  │       ├─► Vehicle Type, Quantity (> 0)
  │       ├─► Term (SHORT_TERM ≤ 30 days — hard-capped in the entity factory — or LONG_TERM)
  │       ├─► Purpose (required, ≤ 500 chars)
  │       ├─► requiredFrom / requiredTo dates
  │       └─► Optional: fuel type, pickup/dropoff location, specifications, target price/unit
  │
  ├─► System Validates:
  │   ├─► requiredTo > requiredFrom per line item
  │   ├─► SHORT_TERM line item duration ≤ 30 days (entity-level, not just UI)
  │   └─► ⚠️ NOTE: NO escrow/wallet balance check at RFQ creation or publish (BR-002)
  │
  ├─► System Creates: rfq (status DRAFT) + rfq_line_item rows
  │   └─► RFQ.StartDate/EndDate are COMPUTED (min/max across line items), not stored fields
  │
  ├─► Business Publishes → RFQ.status = PUBLISHED
  │   └─► RFQ does NOT move to BIDDING at publish — that happens on the FIRST bid submitted
  │
  ├─► System Notifies Matching Providers (computed live at notify time, not persisted as an eligibility list)
  │   ├─► Filter: provider has ≥1 active vehicle whose type matches any line item's vehicle type
  │   └─► 4-channel fanout (in-app/push/email/SMS), gated by each provider's own preference toggles
  │
  └─► ALL published/bidding/partially-awarded RFQs remain visible to EVERY provider on browse
      regardless of fleet match — only the notification is filtered, not visibility
END
```

**Reality Check:** the real RFQ status set is **9 values**: `DRAFT, PUBLISHED, BIDDING, BIDDING_CLOSED, PARTIALLY_AWARDED, AWARDED, EXPIRED, CANCELLED, COMPLETED` — not the simpler flow some earlier drafts implied. `RFQDeadlineJob` runs every **5 minutes** (not hourly) and auto-expires overdue RFQs; an `EXPIRED` RFQ can be revived via deadline extension (`PUT /{id}/extend-deadline`), which is not a dead end.

### Blind Bidding Flow

```
START
  │
  ├─► Provider Views Open RFQs (optionally filtered to own fleet matches via myMatchesOnly)
  │
  ├─► Provider Submits Bid Against One or More Line Items
  │   ├─► Quantity offered (≤ line item's remaining un-awarded slots)
  │   ├─► Unit price (per vehicle, per day — NOT multiplied by duration at bid time)
  │   └─► Notes (optional)
  │   └─► NO specific vehicle selected at bid time — only fleet-segment capacity is checked
  │
  ├─► System Validates:
  │   ├─► Provider verified AND has enough matching-type+fuel vehicles for the offered quantity
  │   ├─► One bid per provider per line item (second attempt rejected — must edit existing bid)
  │   ├─► ⚠️ Price floor/ceiling (50%–200% of "market average"): a validator EXISTS in code
  │   │     (`PriceValidator`) but is NEVER CALLED from the bid-submission handler — **NOT YET
  │   │     ENFORCED**, and even its market-average source is a hardcoded per-vehicle-type stub,
  │   │     not a real rolling average of contract history
  │   └─► Provider not otherwise blocked/suspended
  │
  ├─► System Creates:
  │   ├─► rfq_bid (status SUBMITTED) + rfq_bid_item per targeted line item
  │   └─► rfq_bid_snapshot — SHA-256-hashed provider ID + trust score/tier AT SUBMISSION TIME
  │
  ├─► Business Views Bids
  │   ├─► Sees: masked provider hash, trust score, tier, quantity, unit price, total
  │   └─► ⚠️ Reality Check: blind bidding is a UI convention, not an API guarantee today —
  │         `GetBidsByRFQQuery`/`GetBidQuery` return the real `ProviderName` unconditionally;
  │         the web UI simply chooses not to render it. Any other API caller can see it before award.
  │
  └─► Bidding continues until deadline; bids are visible to the business live, not gated behind close
END
```

### Award Flow

```
START
  │
  ├─► Business Reviews All Bids, Grouped by Line Item
  │   └─► Client-side sort by price/quantity/trust score/submission time
  │
  ├─► Business Selects Winners (one call, may cover multiple bids/line items)
  │   ├─► Can award to multiple providers per line item (split award)
  │   ├─► Can partial-award (e.g., 3 of 5 vehicles)
  │   └─► Cumulative awarded ≤ line item's requested quantity
  │
  ├─► System Calculates Required Escrow (BR-031A — corrected formula):
  │   └─► escrow_required = Σ (quantityAwarded × unitPrice × min(durationDays, 30)), across all awards in the request
  │
  ├─► System Checks Business Wallet AvailableBalance
  │   ├─► IF sufficient → proceed
  │   └─► IF insufficient → error response includes an estimated MAX AFFORDABLE QUANTITY
  │       (business can award partially, deposit more funds and retry, or cancel)
  │
  ├─► System Creates rfq_bid_award (per award) + rfq_line_item_fulfillment (per award)
  │   └─► Provider identity NOW REVEALED for awarded bids
  │
  ├─► RFQ transitions to AWARDED only once EVERY line item's cumulative award meets its
  │   requested quantity — otherwise it becomes/stays PARTIALLY_AWARDED (remaining slots
  │   stay biddable)
  │
  ├─► BidAwardedEvent → Contracts module creates a Contract per bid-award group
  │   └─► ⚠️ Open code gap: `AwardBidCommandHandler` contains a live
  │       `// TODO: Publish BidAwardedEvent for each award...` comment — verify current
  │       wiring before treating award→contract as unconditionally guaranteed end-to-end
  │
  ├─► Contracts Module Creates Contract(s) (status PENDING_ESCROW, always — regardless of source)
  │
  ├─► Finance Module Locks Escrow (reacting to ContractCreatedEvent, NOT a synchronous part of award)
  │   ├─► Re-validates wallet balance (second, independent check — real race-condition protection)
  │   ├─► IF sufficient: debit business MAIN, credit business ESCROW, EscrowLock created (LOCKED)
  │   └─► IF 5 retries (1s/2s/4s/8s/16s) fail: Contract → ESCROW_LOCK_FAILED
  │       (⚠️ no automatic rollback of the award/contract occurs — manual admin/business
  │       retry is required; this is a real gap, not a documented design choice)
  │
  └─► Notifications Sent — business (award confirmation), providers (won/lost)
END
```

### Partial Award Example (corrected math)

**Scenario:**
- RFQ Line Item: 10 EV Sedans needed, 30-day term
- Winning Bid: ETB 3,500/vehicle/day
- Full escrow required: `10 × 3,500 × 30 = ETB 1,050,000`

**Business Wallet:**
- Balance: ETB 1,200,000
- Locked (other contracts): ETB 1,150,000
- **Available: ETB 50,000**

**Award Options:**

```
OPTION 1: Full Award — REJECTED
- Required: ETB 1,050,000, Available: ETB 50,000 → INSUFFICIENT FUNDS

OPTION 2: Partial Award — ACCEPTED
- Max Affordable: FLOOR(50,000 / (3,500 × 30)) = 0 vehicles at this term length
  (illustrates why the min(duration,30) cap matters — a naive "10,000/3,500 = 2 vehicles"
  calculation, as shown in earlier drafts of this document, ignores the 30-day multiplier
  and understates the real escrow requirement by 30x)
- Business must either shorten the term, award fewer vehicles at a shorter effective window,
  or deposit more funds

OPTION 3: Deposit & Full Award
- Business deposits enough to cover the ETB 1,000,000 shortfall, retries award
- Result: SUCCESS
```

### Business Rules

1. **RFQ Creation:** ✅ NO wallet balance required (BR-002).
2. **Award Requirement:** ⚠️ Wallet balance REQUIRED — must cover the per-line-item escrow formula above (BR-006/BR-007).
3. **Partial Awards:** ✅ Allowed, with max-affordable-quantity guidance on shortfall (BR-008/BR-009).
4. **Blind Bidding:** Provider identity hidden **at the UI layer only** until award — not yet a backend guarantee (see Reality Check above).
5. **Split Awards:** ✅ Allowed (multiple providers per line item, one award call).
6. **Price Validation:** ⚠️ Built (`PriceValidator`, 50%/200% band) but **never invoked** — NOT YET ENFORCED, and its market-average source is a hardcoded stub, not real contract history.
7. **Escrow Formula (BR-031A):** `Σ (quantityAwarded × unitPrice × min(durationDays, 30))` — per line item, not a flat multiplier.
8. **Escrow Lock Timing:** Happens as a reaction to contract creation (`ContractCreatedEvent`), which itself happens right after award — not literally inside the award transaction.
9. **Race Condition Protection:** Two separate, real balance checks (award time, escrow-lock time) — but no automatic rollback on the second check's failure (real gap).

---

## 📜 Contract Creation & Activation

### Contract Creation (Automatic, from either an RFQ award or an accepted Direct Rental request)

```
START (Triggered by BidAwardedEvent or DirectRentalRequestAcceptedEvent)
  │
  ├─► Contracts Module Receives Event
  │   └─► IF no contract exists yet: create one
  │       ├─► contract_number = "CTR-YYMMDD-XXXX"
  │       ├─► SourceType = RFQ or DIRECT_RENTAL
  │       ├─► business_id, provider_id
  │       ├─► status = PENDING_ESCROW ← ALWAYS the initial status, regardless of source
  │       └─► CommissionRate resolved once, from the provider's tier at award time (5% fallback)
  │
  ├─► Create Immutable Party Snapshots (contract_party_business, contract_party_provider)
  │
  ├─► Create one ContractLineItem per awarded RFQ line item (or Direct Rental line)
  │   ├─► QuantityAwarded, QuantityActive = 0 initially
  │   ├─► UnitAmount, CommissionRate (snapshotted)
  │   ├─► TotalAmount = QuantityAwarded × UnitAmount × DurationDays
  │   └─► status = PENDING_VEHICLE_ASSIGNMENT (RFQ path — always starts unassigned)
  │
  ├─► Create ContractPolicySnapshot (JSON snapshot of the active contract policy)
  │
  ├─► Write ContractStatusHistory row (trigger SYSTEM_CREATE) + publish ContractCreatedEvent
  │
  └─► Finance Module Locks Escrow (BR-010/BR-011/BR-031A)
      ├─► escrowAmount = Σ per line item: UnitAmount × QuantityAwarded × min(DurationDays, 30)
      ├─► Debit business MAIN, credit business ESCROW (double-entry, same DB transaction)
      ├─► 5-attempt exponential backoff (1s, 2s, 4s, 8s, 16s) on insufficient balance
      ├─► ON SUCCESS: Contract.ActivateAfterEscrowLock() → PENDING_VEHICLE_ASSIGNMENT (RFQ)
      │   or straight to PENDING_SIGNING (Direct Rental, vehicles pre-chosen at booking)
      │   → publishes ContractEscrowLockedEvent (this is NOT contract activation)
      └─► ON 5TH FAILURE: Contract → ESCROW_LOCK_FAILED (manual retry required)
END
```

**Reality Check — status name and initial value:** the contract does **not** start at `PENDING_ACTIVATION` (an earlier draft's claim) — it always starts at `PENDING_ESCROW`. `PENDING_ACTIVATION` is one of several enum members (along with `DISPUTED`, `ON_HOLD`) that exist in the C# `ContractStatus` enum but are **never actually produced by any code path** — vestigial/reserved states. The enum itself is also **never referenced anywhere in the codebase outside its own file**: `Contract.Status` is a plain string column, and the real system produces **18** distinct string values (not 17), including `CANCELLED`, which isn't in the enum at all. See `MVP_CONTRACT_STATE_MACHINE.md` for the full reachability table.

### Vehicle Assignment, Dual-Party Signing & Delivery-Driven Activation

```
START
  │
  ├─► Provider Assigns Specific Vehicles to Contract Line Items
  │   ├─► POST /contracts/{id}/line-items/{lineItemId}/assign-vehicle (1..N vehicles per call)
  │   ├─► Vehicle must be APPROVED, owned by the awarded provider, not active on another contract
  │   └─► Once a line item's assigned quantity reaches its awarded quantity → line item status advances
  │
  ├─► Once ALL line items are fully assigned → Contract status → PENDING_SIGNING
  │
  ├─► Dual-Party Contract Terms OTP (SIGNING GATE — distinct from delivery OTP, Epic 06/07)
  │   ├─► POST /contracts/{id}/terms/otp/generate — 6-digit OTP per party, 5-min expiry, 60s resend cooldown
  │   ├─► POST /contracts/{id}/terms/otp/verify — each party verifies only their OWN code
  │   └─► Once BOTH parties confirm → Contract.MarkTermsSigned():
  │       status = "SIGNED" then IMMEDIATELY overwritten to "PENDING_DELIVERY" in the same call,
  │       before SaveChanges. "SIGNED" is NEVER a queryable/persisted row and gets NO
  │       ContractStatusHistory entry — treat it as a logical instant, not a real state.
  │
  ├─► Delivery Session Created (one per newly-assigned vehicle, ~1 day after assignment/signing)
  │
  ├─► Vehicle Inspection Checklist Gate (replaces any "photo evidence handover" concept)
  │   ├─► Provider submits structured checklist (bool/enum/numeric fields, e.g. fuel level,
  │   │   odometer, tyre condition, visible damage) — NO photo upload anywhere in this flow
  │   ├─► Business approves or rejects the checklist
  │   └─► OTP generation is HARD-BLOCKED until the checklist is APPROVED (server-enforced)
  │
  ├─► Provider requests delivery OTP → sent to BUSINESS (SMS/email)
  │   └─► Business tells the provider the code verbally; provider enters it to confirm
  │   └─► ⚠️ The OTP code is NEVER returned by any API response — delivered out-of-band only
  │   └─► ⚠️ No attempts counter/lockout exists on the OTP entity — an expired/used OTP just
  │       fails; there is no "3 attempts → 30 min block" mechanism in code
  │
  ├─► System Marks that ContractVehicleAssignment DELIVERED
  │   ├─► Increments the parent line item's QuantityDelivered
  │   └─► Contract.UpdateStatusBasedOnDelivery() recomputes contract status
  │
  ├─► ON FIRST vehicle delivered for the contract:
  │   ├─► Generate Settlement Schedule (BR-031A) — anchored to first delivery date, 30-day fixed cycles
  │   └─► Contract → PARTIALLY_DELIVERED (multi-vehicle contracts)
  │
  └─► ON LAST vehicle delivered (all awarded vehicles across all line items):
      ├─► Contract → ACTIVE
      └─► Publish ContractActivatedEvent ← the ONE true "activation" moment in the system
END
```

**Reality Check — no GPS, no photos:** confirmed zero `Latitude`/`Longitude` references anywhere in the Delivery module; `DeliverySession.LocationAddress` exists but is always written `null`. The `DeliveryVehicleHandover` entity (5-photo/odometer/fuel-level concept) exists in the schema and migrations but **nothing anywhere writes to it** — it is dead schema, superseded by the checklist system described above.

### Real Contract Status Model (18 values, string column — not the C# enum)

| Status | Meaning | Reachable today? |
|---|---|---|
| `PENDING_ESCROW` | Created, awaiting escrow lock | ✅ |
| `ESCROW_LOCK_FAILED` | 5 lock retries exhausted | ✅ |
| `PENDING_VEHICLE_ASSIGNMENT` | Escrow locked, awaiting vehicle assignment | ✅ |
| `PENDING_SIGNING` | Fully assigned, awaiting dual-party terms OTP | ✅ |
| `SIGNED` | Both parties confirmed (momentary, in-memory only) | ⚠️ never persisted |
| `PENDING_DELIVERY` | Signed, awaiting first delivery | ✅ |
| `PARTIALLY_DELIVERED` | Some but not all vehicles delivered | ✅ |
| `ACTIVE` | All vehicles delivered | ✅ |
| `TERMINATION_REQUESTED` | One party requested early termination | ✅ |
| `TERMINATED` | Termination approved (request→approve pair only) | ✅ |
| `COMPLETED` | Two-party (or admin-override) completion approved | ✅ |
| `TIMEOUT_PENDING` | End date reached, vehicles still outstanding | ✅ |
| `PARTIALLY_RETURNED` | Some/all vehicles returned; completion gate | ✅ |
| `CANCELLED` | Pre-signing abort or escrow timeout | ✅ (not in the C# enum at all) |
| `DRAFT`, `PENDING_ACTIVATION`, `DISPUTED`, `ON_HOLD` | Defined in the enum | ❌ vestigial — never produced by any transition |

**There is no `SUSPENDED` status anywhere in code, past or present.** Escrow shortfalls only block the *initial* lock (retry → `ESCROW_LOCK_FAILED` → `CANCELLED` on 24h timeout); once `ACTIVE`, nothing in the Contracts module re-checks wallet balance to suspend service. Full detail, every transition, and every dead-code caveat: [`MVP_CONTRACT_STATE_MACHINE.md`](./MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md).

---

## 🔄 Partial Fulfillment & Early Returns

### Early Termination Flow (real mechanism — not a per-vehicle "early return session with photo evidence and tiered penalty")

```
START
  │
  ├─► Business or Provider Requests Termination (POST /contracts/{id}/termination/request)
  │   └─► Command handler allows this only from ACTIVE or PARTIALLY_RETURNED
  │   └─► Contract status → TERMINATION_REQUESTED, both parties notified
  │
  ├─► Any of business/provider/admin Approves (POST /contracts/{id}/termination/approve)
  │   └─► No self-vs-other-party check here (unlike completion, see below)
  │   └─► Contract status → TERMINATED; any ACTIVE line items force-TERMINATED too
  │   └─► ⚠️ There is NO reject/withdraw endpoint for a submitted termination request
  │
  └─► Finance Module Processes Early Termination (ProcessEarlyTerminationCommand)
      ├─► usedDays = min(now - StartDate, totalDays); dailyRate = TotalContractValue / totalDays
      ├─► remainingValue = escrowLock.Amount (the actual locked amount, not a recomputation)
      ├─► penalty = MasterData EARLY_TERMINATION policy (SEEDED TO 0% / "NONE" for MVP —
      │   ⚠️ NOT a business-tier-based 25%/20%/15% schedule; BusinessTier never drives penalty rates)
      ├─► refund = remainingValue − penalty → business MAIN
      ├─► commissionRate = weighted-average of the contract's OWN line-item rates (snapshotted;
      │   a provider's tier change mid-contract does NOT change what's owed)
      ├─► providerSettlement = usedAmount − platformCommission → provider MAIN
      └─► platformCommission + penalty → platform COMMISSION wallet; blocked entirely while
          the escrow lock is DISPUTED
END
```

**Reality Check:** there is no separate `delivery_return_session` "early return" flow with its own photo-evidence capture and business-tier-based penalty schedule (25%/20%/15% by Standard/Business Pro/Enterprise) — that entire mechanism is **NOT YET IMPLEMENTED / does not match code**. The real mechanism is `ProcessEarlyTerminationCommand` (above), and the real vehicle-condition capture at any return is the same checklist system used for delivery (§7 in the companion delivery spec), not photos. A separate notice-period-based `InitiateEarlyReturnCommand` exists in code but has **no controller endpoint and is never invoked** — unreachable today.

### Under-Delivery Handling

**NOT YET IMPLEMENTED as a distinct workflow.** No dedicated "under-delivery penalty" command, entity, or UI flow (accept-partial / request-replacement-within-24h / cancel-line-item-with-no-show-penalty) was found in code. What is real: a provider can simply assign fewer vehicles than awarded, and the contract's line-item/assignment quantity tracking (`QuantityAwarded` vs `QuantityActive`/`QuantityDelivered`) reflects the shortfall — there is no automated penalty, no 24-hour replacement clock, and no automatic escrow release tied specifically to an unfulfilled quantity. Treat any specific under-delivery penalty percentage as aspirational.

### Vehicle Replacement (designed, mostly unreachable in practice)

- Before delivery is confirmed: `UnassignVehicleCommand` simply removes the assignment and frees the vehicle — this branch works today.
- After delivery: replacement **requires** a signed `SCOPE_CHANGE` `ContractAmendment` — but `ContractAmendment.Create()` has **zero callers anywhere in the codebase**, so this branch can never actually be satisfied. A separate `ReplaceVehicleCommand` exists and is fully implemented but **has no controller endpoint wired to it** — unreachable via HTTP today.
- `ContractPenalty` is a fully modeled entity (`Create`/`MarkPaid`/`Waive`/`Dispute`) but `ContractPenalty.Create()` also has **zero callers** — no flow in the system currently produces a penalty record, despite UI copy (e.g. the admin contract-termination page) implying penalties are applied.

### Business Rules (corrected)

1. **Early Termination Penalty:** MasterData-configurable, seeded to **0%** for MVP — no business-tier-based percentage schedule exists in code.
2. **Proration:** Daily basis (`usedDays`/`totalDays` against `TotalContractValue`) — confirmed real.
3. **Under-Delivery Penalty:** NOT YET IMPLEMENTED as a distinct rule/command.
4. **No-Show Penalty:** NOT YET IMPLEMENTED as a distinct rule/command with a specific percentage.
5. **Vehicle Replacement:** designed (amendment-gated) but effectively unreachable — no way to create the required amendment, and the direct replace command has no endpoint.
6. **Trust Score Impact:** the formula has a `RejectionPenaltyPoints` input for bid-award rejections only; no wired numeric impact exists for early return / under-delivery / no-show specifically, and the whole trust-score recalculation pipeline is dormant (see §10).

---

## 💰 Settlement & Payouts

### Settlement Cycle (real mechanism — fixed 30-day rolling window, not a calendar-month batch job)

```
START (GenerateSettlementCommand — admin-triggered or scheduled per due cycle, NOT "runs on the 1st")
  │
  ├─► At contract creation/activation, a MonthlySettlementSchedule is generated per contract:
  │   fixed, INCLUSIVE 30-day windows anchored to the contract's START date, capped at the
  │   contract's end date. A contract shorter than 30 days gets a single cycle. The LAST cycle
  │   is flagged IsFinalSettlement = true.
  │
  ├─► For each due (PENDING, SettlementDate ≤ today) cycle, per provider:
  │   ├─► Aggregate per-vehicle earnings from ContractVehicleAssignment.DeliveredAt/ReleasedAt
  │   │   windowed against the cycle dates — undelivered vehicles contribute 0; a vehicle
  │   │   contributes only from its actual DeliveredAt; a returned vehicle stops contributing
  │   │   after its ReturnedAt (BR-031A)
  │   ├─► commissionRate = value-weighted average of the contract's line-item rates
  │   │   (falls back to a flat 8% only if the contract somehow has no line items)
  │   ├─► taxDeducted = netBeforeTax × WITHHOLDING_TAX_RATE (2% default)
  │   ├─► netPayoutAmount = TotalAmount − CommissionDeducted − TaxDeducted
  │   └─► Payout SKIPPED if gross earnings for the window are below the minimum payout
  │       threshold (100 ETB default, MasterData-configurable — NOT ETB 1,000)
  │
  ├─► Every new payout starts PENDING_ADMIN_APPROVAL — NO wallet movement at generation time
  │
  ├─► Admin Approves Payout (ApproveSettlementPayoutCommand) — ONE atomic operation:
  │   ├─► DEBIT business ESCROW (gross earned amount, via the contract's active EscrowLock)
  │   ├─► CREDIT provider MAIN (net amount)
  │   ├─► CREDIT platform COMMISSION (commission deducted)
  │   ├─► CREDIT platform TAX (tax withheld)
  │   └─► IF this is the contract's FINAL cycle: refund unused escrow to business MAIN and
  │       release the lock; IF NOT final: release current lock and relock the unused amount
  │       toward the NEXT cycle (rollover), falling back to a refund if no next cycle exists
  │
  └─► On success: payout → COMPLETED; schedule(s) → SETTLED; on any failure: full rollback,
      payout → FAILED (no automatic retry — admin must re-attempt)
END
```

**Reality Check — settlement cadence:** a code comment on `GenerateSettlementCommand.cs` (itself labeled `BR-FN-03`) describes tier-based cadence ("Bronze/Silver monthly, Gold bi-weekly, Platinum weekly") — **this is not implemented anywhere.** There is no branching on provider tier in `SettlementScheduleService`; every contract gets the same fixed 30-day rolling window regardless of tier. Treat the flat 30-day cycle as ground truth; the tier-cadence comment is a stale/aspirational note left in the codebase itself, not a doc-vs-code drift external to it.

**Reality Check — no system-generated business invoices:** VAT-registered **providers** submit their own invoices against completed payouts to reclaim withheld tax (`ProviderInvoiceController`); there is **no system-generated, business-facing invoice** (PDF, email, sequential numbering) anywhere in the codebase — that was the original design's entire premise for this section and it does not exist.

### Business Rules (corrected)

1. **Settlement Frequency:** Fixed 30-day rolling cycle per contract — **not** tier-based cadence (see Reality Check).
2. **Commission Rates:** Bronze 10% / Silver 8% / Gold 6% / Platinum 5% — snapshotted at award time, no "Red Zone."
3. **Payout Timeline:** No wallet movement until admin approval; no fixed "3 business days" SLA was confirmed in code.
4. **Minimum Payout:** ETB 100 default (MasterData-configurable), not ETB 1,000.
5. **Tax Withholding:** 2% default (MasterData-configurable), real and live — deducted from every payout, reclaimable by VAT-registered providers via invoice.
6. **Reconciliation:** Ledger-vs-wallet reconciliation tooling is **NOT YET IMPLEMENTED** — confirmed zero reconciliation command/query/report anywhere.
7. **Settlement Dispute:** **NOT YET IMPLEMENTED** — no dispute endpoint, entity, or workflow exists for contesting a settlement calculation.

---

## ⭐ Trust Score Calculation

### The Real Formula (BR-025) — built, but dormant

```
Score = Base(50 if IsVerified else 0)
      + CompletionRate × 20      // completed contracts / total contracts, 0.0–1.0
      + OnTimeRate × 20          // on-time deliveries / total deliveries, 0.0–1.0
      − NoShowRate × 30          // no-shows / scheduled deliveries, 0.0–1.0
      + RejectionPenaltyPoints   // negative int, per bid-award rejection

Score = clamp(Score, 0, 100)
```

This is the **entire** real formula — there is **no** 5-factor weighted model (completion 30% / on-time 25% / reliability 20% / quality/ratings 15% / dispute history 10%) anywhere in code, and no rating system or dispute entity exists to feed one. `TrustScoreCalculator.cs`/`ITrustScoreCalculator` is fully implemented, unit-tested, and DI-registered.

**🚨 Critical gap — the formula is never actually invoked in production.** A repo-wide search found **zero call sites** for `ITrustScoreCalculator.CalculateScore(...)` or `Provider.UpdateTrustScore(...)` outside unit tests. No handler for contract completion, on-time delivery, no-show, or bid-award rejection ever recomputes a score. **Every provider's trust score is frozen at its registration-time default (50) unless an admin manually reassigns a tier** via `AssignProviderTierCommand` — which itself does not check the provider's actual score before accepting the admin's choice. Treat every "trust score changes when X happens" narrative anywhere in product docs as **NOT YET IMPLEMENTED** until this wiring gap is closed.

### Two Competing, Both-Dormant Tier-Threshold Schemes

| Scheme | Thresholds | Used by | Status |
|---|---|---|---|
| Hardcoded (`TrustScore.cs`) | Bronze < 50, Silver 50–69, Gold 70–84, Platinum ≥ 85 | Admin provider-list filtering (`GetByTierAsync`) | Live for filtering only, not for assignment |
| Seeded `ProviderTierRule` ("hybrid" model, BR-042) | Bronze 0–59, Silver 60–74, Gold 75–89, Platinum 90–100 — **plus** minimum completed contracts (0/10/50/100), max cancellation rate, min on-time rate per tier | `TierCalculationService.CalculateProviderTierAsync` | Fully coded, **zero production call sites** — dormant |

Both schemes disagree with each other and neither actually assigns a provider's tier today. **Real, live tier assignment is 100% manual admin action** (`AssignProviderTierCommand`) — and even the admin UI's tier-*threshold*-editing dialog is a stub (`toast.info('Update functionality coming soon')`). Whoever wires up automatic tier calculation must pick one scheme, not both.

### Trust Score Visibility (corrected — contradicts earlier "admin/business-only" assumption)

| Surface | What's shown |
|---|---|
| Provider mobile app dashboard | Provider's own live `TrustScore` + current tier — **the provider does see their own score**, contra earlier product-doc assumptions |
| Web business bid-review | Real trust score/tier snapshotted on each bid — businesses genuinely see it when evaluating bids |
| Web admin user-detail page | 🟡 Partial — the component can render a real score, but `admin-users-service.ts` currently **hardcodes `trustScore: 0`/`tier: 'SILVER'`** for both business and provider detail views |
| Business mobile app | Model deserializes `trustScore`/`providerTier` from the bid API but **no screen renders either field** — plumbing exists, UI doesn't use it yet |

### Business Rules (corrected)

1. **Initial Score:** 50 for every new provider (not 0) — see Provider Registration §3.
2. **Recalculation:** NOT YET WIRED to any production trigger — score never moves from 50 automatically today.
3. **Tier Assignment:** Manual admin action only; automatic score-driven tier changes are dormant code.
4. **Business Risk Scoring:** **NOT YET IMPLEMENTED** — confirmed zero `RiskScore` field anywhere on the `Business` entity. `RiskEvent`/`AccountFlag` exist but are generic security-event/flag records (new-device login, geo-mismatch, etc.), not a scored 0–100 risk model.
5. **Fraud Detection / Anti-Collusion:** **NOT YET IMPLEMENTED** — zero rule-engine or collusion-detection code anywhere (backend, web, or either mobile app).
6. **Dispute Resolution:** **NOT YET IMPLEMENTED** — no `Dispute` entity anywhere; `Contract.Status` values `DISPUTED`/`ON_HOLD` are bare, never-set enum members with no supporting workflow.
7. **Bid Ranking by Trust Score:** **NOT YET IMPLEMENTED** — no weighted price/trust/condition/response-time ranking formula exists on any surface; sorting is single-column client-side only.

---

## Direct Rental (Vehicle Catalog)

**Authoritative rules:** [MVP_AUTHORITATIVE_BUSINESS_RULES.md](./MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md) §19 (BR-DR-001 through BR-DR-015)
**Full spec:** [MVP_DIRECT_RENTAL_SPECIFICATION.md](./MVP_final_docs/MVP_DIRECT_RENTAL_SPECIFICATION.md)

Direct Rental is a fully-built, fixed-price, non-bidding vehicle-booking product that runs parallel to the RFQ/bidding marketplace across all four surfaces (backend, web, both mobile apps) — it now has its own post-MVP epic (`backlog/post-mvp/epic-21-direct-rental.md`) after previously having no epic number at all.

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│              DIRECT RENTAL — PARALLEL TO RFQ                    │
└─────────────────────────────────────────────────────────────────┘

PROVIDER SETUP
  ├─► Set daily rental rate (IsAvailableForDirectRental, DailyRentalRate)
  ├─► Enable direct rental (blocked while vehicle is committed to an active contract or RFQ award)
  └─► Vehicle appears in catalog once APPROVED + rate > 0

BUSINESS DISCOVERY
  ├─► Browse provider vehicles (filters, pagination) — provider identity IS visible (not blind)
  ├─► Add to cart (specific vehicle + date range)
  └─► Cart does NOT lock the vehicle for other businesses

CART SUBMIT
  ├─► Submit preview — wallet AvailableBalance ≥ cart total (BR-DR-004)
  ├─► Re-check vehicle availability inside a DB transaction (BR-DR-005)
  ├─► Group by provider → one DirectRentalRequest per provider (BR-DR-006)
  ├─► Line items grouped by vehicle type within each request (BR-DR-007)
  └─► Clear cart; status PENDING; expires in 48h (BR-DR-008)

PROVIDER RESPONSE (within 48h)
  ├─► Accept-preview checks fleet segment capacity against RFQ bids/awards (BR-DR-013)
  ├─► Per-vehicle accept/reject (+ rejection reasons, min 5 chars — BR-DR-011)
  ├─► All / partial / none → ACCEPTED | PARTIALLY_ACCEPTED | REJECTED
  └─► "All-or-none" mode: accept all or reject all, no mixing (BR-DR-007b/BR-DR-012)

ALTERNATE EXITS (while PENDING)
  ├─► Business cancels → CANCELLED (BR-DR-009)
  └─► ExpireDirectRentalRequestsJob (hourly) → EXPIRED (BR-DR-008)

CONTRACT BRIDGE
  ├─► ACCEPTED or PARTIALLY_ACCEPTED → CreateDirectRentalContractCommand (idempotent)
  ├─► Contract.SourceType = DIRECT_RENTAL
  └─► Joins the SAME status machine, escrow, delivery, and settlement pipeline as RFQ contracts
      (only difference: vehicles may already be assigned at creation, so the contract can skip
      straight to PENDING_SIGNING instead of PENDING_VEHICLE_ASSIGNMENT)
```

### Key Differences from RFQ

| Aspect | RFQ | Direct Rental |
|--------|-----|---------------|
| Vehicle selection | Type + quantity (fleet-segment bid) | Specific vehicle chosen in catalog |
| Pricing | Bid, per line item | Provider-listed daily rate, fixed |
| Provider commitment | After award + separate vehicle-assignment step | After accept on the request (vehicle already chosen) |
| Wallet check | At award (BR-006) | At cart submit (BR-DR-004) |
| Identity | Masked at UI layer until award | Provider visible in catalog from the start |
| Contract status machine | Full 18-value model | Same 18-value model (shared `Contract` aggregate) |

---

**Next Document:** [04_MODULE_SPECIFICATIONS/Identity_and_Compliance_Module.md](./04_MODULE_SPECIFICATIONS/Identity_and_Compliance_Module.md)
