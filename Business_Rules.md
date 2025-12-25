# Business Rules Catalog

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Scope:** All Modules

---

## 📋 Overview

This document serves as the **single source of truth** for all business rules, validation logic, and policy parameters in the Movello platform. These rules are enforced across the Database, API, and Frontend layers.

---

## 🏢 Identity & Compliance

### BR-ID-01: Business Registration
- **TIN Validation:** Must be a unique 10-digit number.
- **Document Requirement:** Valid Business License is mandatory for activation.
- **Tier Assignment:** All new businesses start at `STANDARD` tier.

### BR-ID-02: Provider Registration
- **Age Requirement:** Individual providers must be 21+ years old.
- **Fleet Requirement:**
  - Individual: 1-5 vehicles
  - Agent: 6-20 vehicles
  - Company: 20+ vehicles
- **Tier Assignment:** All new providers start at `BRONZE` tier (Trust Score 0).

### BR-ID-03: Vehicle Compliance
- **Insurance:** Mandatory "Comprehensive" or "Third Party" insurance.
- **Validity:** Insurance must be valid for at least 30 days from registration date.
- **Photos:** 5 angles (Front, Back, Left, Right, Interior) required.
- **Age Limit:** Vehicles older than 15 years are rejected (configurable).

---

## 🏪 Marketplace & Bidding

### BR-MK-01: RFQ Creation
- **Wallet Balance:** ⚠️ **NO** wallet balance required to create/publish RFQs.
- **Lead Time:** Start Date must be at least 3 days from publication.
- **Duration:** Minimum contract duration is 1 day.
- **Quantity:** Maximum 50 vehicles per single RFQ.

### BR-MK-02: Bidding
- **Blind Bidding:** Provider identity is hidden (`Provider •••1234`) until award.
- **Price Floor:** Bid cannot be < 50% of market average.
- **Price Ceiling:** Bid cannot be > 200% of market average.
- **Eligibility:** Provider must have sufficient *active* and *unassigned* vehicles.

### BR-MK-03: Awarding
- **Wallet Balance:** ⚠️ **REQUIRED**. Business must have `Available Balance >= Escrow Amount`.
- **Partial Award:** Allowed if funds are insufficient.
- **Escrow Lock:** 100% of contract value (Monthly) or 100% upfront (Event) locked immediately.

---

## 📜 Contracts & Delivery

### BR-CT-01: Activation
- **Trigger:** Contract activates when the **first** vehicle is delivered.
- **Requirement:** Successful OTP verification + Handover Evidence.

### BR-CT-02: Early Return
- **Proration:** Daily basis calculation (`Total Amount / Total Days * Days Used`).
- **Penalty:**
  - Standard Tier: 25% of remaining contract value.
  - Business Pro: 20% of remaining contract value.
  - Enterprise: 15% of remaining contract value.

### BR-CT-03: Delivery
- **OTP Expiry:** 5 minutes.
- **Lockout:** 3 failed attempts = 30 minute lockout.
- **SLA:** "On-time" defined as delivery within +/- 2 hours of scheduled time.

---

## 💰 Finance & Settlement

### BR-FN-01: Wallet
- **Currency:** ETB (Ethiopian Birr) only.
- **Overdraft:** Not allowed. Balance cannot go below zero.
- **Locking:** Locked funds cannot be withdrawn or used for other awards.

### BR-FN-02: Commission
- **Bronze:** 10%
- **Silver:** 8%
- **Gold:** 6%
- **Platinum:** 5%
- **Calculation:** Applied to Gross Contract Value.

### BR-FN-03: Settlement
- **Frequency:**
  - Bronze/Silver: Monthly (1st)
  - Gold: Bi-weekly (1st, 15th)
  - Platinum: Weekly (Monday)
- **Minimum Payout:** ETB 1,000.

---

## ⭐ Trust Score

### BR-TS-01: Calculation Weights
- **Completion Rate:** 30%
- **On-Time Delivery:** 25%
- **Reliability (No-shows):** 20%
- **Quality (Ratings):** 15%
- **Dispute History:** 10%

### BR-TS-02: Penalties (Score Deduction)
- **No-Show:** -10 points
- **Under-Delivery:** -5 points
- **Early Return (Provider Fault):** -5 points
- **Dispute Lost:** -15 points

---

**Next Document:** [UI_System_Design_Guidelines.md](./UI_System_Design_Guidelines.md)
