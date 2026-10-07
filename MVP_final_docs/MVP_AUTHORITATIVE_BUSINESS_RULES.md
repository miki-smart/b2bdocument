# Anqelba Car Rental MVP - Authoritative Business Rules
## Single Source of Truth - Version 2.0

**Document Status:** AUTHORITATIVE — rewritten against running code
**Last verified against code: 2026-07-23**
**Supersedes:** All conflicting specifications in previous documents, including earlier versions of this document
**Ground truth files:** `backend/src/Marketplace.API/Modules/{Marketplace,Contracts,Finance,Identity,MasterData,Delivery}/**`, `Infrastructure/Seeders/MasterDataSeeder.cs`, and the companion docs `MVP_CONTRACT_STATE_MACHINE.md`, `project-docs/service-specs/contract-engine-spec.md`, `project-docs/service-specs/14_Wallet_Engine_Flow_Specification.md`, `project-docs/service-specs/15_Delivery_OTP_Verification_Flow_Specification.md`, `backlog/mvp/epic-{04,05,06,08,09,10,12}-*.md`, `project-docs/18_Implementation_Coverage_Audit.md`

---

## Document Control

**Purpose:** This document is the single authoritative source for business rules in the Anqelba Car Rental B2B mobility marketplace MVP, reconciled directly against the running `.NET 9` backend (a single modular monolith, `Marketplace.API`, not separate microservices), the React web portal, and both Flutter mobile apps. Where this document and code disagree in the future, **trust the code** and re-run this reconciliation — this document is a snapshot as of 2026-07-23.

**What changed in this rewrite (v1.2 → v2.0):** every rule below was individually re-verified against actual entities, command handlers, and seeded master data — not against the previous version's text. Several rules in the prior version described features that either don't exist, are dormant (built but never invoked), or use different numbers than what's actually seeded. Every such case is marked **NOT YET IMPLEMENTED** or **DORMANT** below rather than silently corrected — see Appendix A for the full list of what changed and why. Two internal `BR-ID` numbering collisions in the previous version (the same ID used for two unrelated rules) were also fixed — see Appendix A.

**Change Control:** Any changes to this document must be (1) approved by the business owner, (2) version-incremented, (3) logged in Appendix A, (4) reflected in the three companion documents that cite it (`Business_Rules.md`, `05_BUSINESS_LOGIC_FLOWS.md`, `CRITICAL_BUSINESS_RULE_UPDATE.md`, all in this same directory tree).

---

## TABLE OF CONTENTS

1. [RFQ & Bidding Rules](#1-rfq--bidding-rules)
2. [Award & Contract Creation](#2-award--contract-creation)
3. [Escrow & Financial Rules](#3-escrow--financial-rules)
4. [Vehicle Assignment & Delivery](#4-vehicle-assignment--delivery)
5. [Contract Activation & Lifecycle](#5-contract-activation--lifecycle)
6. [Early Return & Termination Penalties](#6-early-return--termination-penalties)
7. [Provider Rejection Handling](#7-provider-rejection-handling)
8. [Trust Score Calculation](#8-trust-score-calculation)
9. [Provider Tier System](#9-provider-tier-system)
10. [Business Tier System](#10-business-tier-system)
11. [Compliance & Verification](#11-compliance--verification)
12. [Settlement Processing](#12-settlement-processing)
13. [Dispute Resolution](#13-dispute-resolution)
14. [Status Definitions](#14-status-definitions)
15. [Vehicle Assignment Lifecycle](#15-vehicle-assignment-lifecycle)
16. [Contract Completion Rules](#16-contract-completion-rules)
17. [Settlement Calculation with Vehicle Lifecycle](#17-settlement-calculation-with-vehicle-lifecycle)
18. [Contract Extension Rules](#18-contract-extension-rules)
19. [Direct Rental (Vehicle Catalog)](#19-direct-rental-vehicle-catalog)
20. [Promotions: Hot Deals & Featured Listings](#20-promotions-hot-deals--featured-listings)

---

## 1. RFQ & BIDDING RULES

### 1.1 RFQ Creation Prerequisites

**Rule BR-001: Business Verification Required**
- Business must be verified/active to create an RFQ. Unverified or pending businesses cannot create one.

**Rule BR-002: No Wallet Balance Required for RFQ Creation**
- ✅ **Confirmed live:** NO wallet balance is required to create or publish an RFQ. Confirmed zero wallet-lookup calls anywhere in `RFQ`/`RFQLineItem` entity factories or `RFQController`. Wallet balance is only required at **award** time (BR-006).

**Rule BR-003: RFQ Line Item Structure (real model: header + line items)**
- An RFQ is a **header + one or more `RFQLineItem`s** — not a single vehicle-type/date-range request. Each line item independently specifies vehicle type, quantity, term (`SHORT_TERM` ≤ 30 days — **hard-capped in the entity factory itself**, not just a UI hint — or `LONG_TERM`), required purpose (≤ 500 chars), `requiredFrom`/`requiredTo` dates, and optional fuel type/location/specifications/target price.
- `RFQ.StartDate`/`EndDate` are **computed** (min/max across line items), not stored fields.
- Real RFQ status set is **9 values**: `DRAFT, PUBLISHED, BIDDING, BIDDING_CLOSED, PARTIALLY_AWARDED, AWARDED, EXPIRED, CANCELLED, COMPLETED` (see §14.1).
- Line items are independently biddable and awardable; a line item can be **partially awarded** across multiple providers (see §2).

---

### 1.2 Bid Submission Prerequisites

**Rule BR-004: Provider Pre-Bid Validation**

Real code comment: *"BR-004: Comprehensive provider eligibility validation"* (`SubmitBidCommand.cs`), enforced by `IProviderValidationService`/`ProviderFleetCapacityService`.

Provider must meet ALL criteria to submit a bid:
1. **Account Status:** Provider verified (not suspended/blocked).
2. **Fleet Segment Capacity:** enough active/verified vehicles in the matching vehicle-type + fuel segment to cover the **quantity offered** — **no specific vehicle is chosen at bid time**, only a capacity check against the provider's matching-fleet count net of vehicles already committed to other open bids/awards/Direct Rental requests.
3. **One bid per line item:** a second bid attempt against a line item the provider already bid on is rejected — the provider must edit the existing bid instead (`PUT /bids/{id}`).
4. **Trust score gate:** no minimum trust-score threshold was confirmed as an enforced bid-submission gate in code this pass — treat "trust score must meet a minimum" as unconfirmed/aspirational unless re-verified.

**Validation Timing:** re-validated at update time (excluding the bid's own existing reservation) and again at award time (BR-006).

**⚠️ Price Floor/Ceiling — built, but NOT ENFORCED (NOT YET LIVE):** a `PriceValidator` domain service exists implementing exactly a 50%–200%-of-"market average" band and is DI-registered in `Program.cs` — but it is **never called** from `SubmitBidCommandHandler` or anywhere else in the codebase (confirmed: `IPriceValidator`/`ValidatePriceAsync` has zero call sites outside its own registration). Its market-average source is also a hardcoded per-vehicle-type stub (`GetDefaultPrice()`), not a real rolling average of contract history — the intended "average of last 30 days of contracts" calculation is marked `// TODO` in the service itself. **No bid is rejected for price today, at any level.**

---

### 1.3 Bid Modification & Withdrawal

**Rule BR-005: Bid Modification Rules**
- Provider can modify a bid (`PUT /bids/{id}`) while it is `SUBMITTED`/`PENDING` and the RFQ is still `PUBLISHED`/`BIDDING`/`PARTIALLY_AWARDED`, before the deadline. This is a **partial-update model** — items omitted from the update payload are left unchanged, not removed. Every update is recorded in `RFQBidHistory` with a JSON diff.
- Provider can withdraw a bid (`DELETE /bids/{id}`) any time before award; an already-`AWARDED` bid cannot be withdrawn. No structured withdrawal-reason field exists.
- **Resubmission after withdrawal IS allowed** (a real, deliberate code path — `SubmitBidCommand` hard-deletes the prior `WITHDRAWN` row before inserting the new bid) — this is **not** blocked, contrary to some earlier drafts of this rule.

---

## 2. AWARD & CONTRACT CREATION

### 2.1 Award Prerequisites

**Rule BR-006: Award Validation — Wallet Balance Check**

Real code comment: *"BR-006, BR-007, BR-008, BR-009: Validate wallet balance with affordability calculation"* (`AwardBidCommand.cs`, `IWalletCalculationService.cs`).

Before a business can award a bid, the system validates:
1. RFQ status is `PUBLISHED`/`BIDDING`/`PARTIALLY_AWARDED` (not already fully `AWARDED`).
2. Business wallet `AvailableBalance` ≥ total escrow required for **all** selected awards in the request (formula: BR-007).
3. Each targeted bid actually contains the targeted line item and is still `SUBMITTED`.
4. Provider fleet segment capacity for each provider's new award quantity.

If validation fails, the business can: deposit funds and retry, select fewer/partial awards (BR-008), or cancel the award attempt.

**Rule BR-007: Escrow / Max-Affordable-Quantity Formula**

Real code comment: *"BR-007: Calculate max affordable quantity = floor(walletBalance / (pricePerVehicle × contractDuration))"* (`IWalletCalculationService.cs`).

```
Per award: lineItemEscrow = quantityAwarded × unitPrice × min(durationDays, 30)
Total escrow required = Σ lineItemEscrow (across every award in the request)

maxAffordableQuantity = FLOOR(availableBalance / (unitPrice × min(durationDays, 30)))
```
**This is the same `min(durationDays, 30)` cap used for the actual escrow lock (BR-031A)** — the max-affordable-quantity guidance and the real lock amount are computed consistently, not with two different formulas.

**Rule BR-008: Partial Award Support**

Real code comment: *"BR-008: Provide partial award option if possible"* (`AwardBidCommand.cs`).

- `POST /api/marketplace/bids/award` (`AwardBidCommand`) accepts a flat list of `{bidId, lineItemId, quantityAwarded}` — one call can award pieces of a single line item to several different providers' bids, as long as cumulative awarded quantity (this request + prior awards) doesn't exceed the line item's requested quantity.
- If the business's `AvailableBalance` covers only part of the request, the system computes and returns `maxAffordableQuantity` (BR-007) so the business can award that smaller quantity instead of an all-or-nothing rejection.
- RFQ transitions to `AWARDED` only once **every** line item's cumulative awarded quantity meets its requested quantity; otherwise it becomes/stays `PARTIALLY_AWARDED` (remaining slots stay biddable).

**Rule BR-009: Clear Funding Guidance on Total Shortfall**

Real code comment: *"BR-009: Clear funding guidance when no partial award possible"* (`AwardBidCommand.cs`, `WalletCalculationService.cs`).

When `maxAffordableQuantity == 0` (business can't afford even one unit), the system throws with an explicit shortfall figure rather than a generic rejection, so the UI can prompt a specific deposit amount.

---

### 2.2 Award Workflow Sequence

**Rule BR-008a (workflow, not a distinct numbered code rule): Canonical Award → Contract → Escrow Flow**

```
Step 1: Business awards bid(s) — POST /api/marketplace/bids/award
Step 2: System validates wallet balance (BR-006/BR-007)
Step 3: RFQBidAward + RFQLineItemFulfillment rows created; RFQ status recomputed
Step 4: BidAwardedEvent → Contracts module → CreateContractCommand → Contract created (status PENDING_ESCROW)
Step 5: ContractCreatedEvent → Finance module locks escrow (BR-010/BR-011), 5-attempt retry
Step 6: Provider assigns specific vehicles to the contract's line items
Step 7: Dual-party contract-terms OTP signing (§5) → delivery OTP flow (§4)
Step 8: Contract reaches ACTIVE once every awarded vehicle is delivered
```

**Confirmed correct sequence:** `BidAwardedEvent → ContractCreatedEvent → EscrowLock` — escrow locking is a reaction to contract creation, not a step of the award call itself, and not something that happens before a contract exists.

**⚠️ Known code gap:** `AwardBidCommandHandler` contains a live `// TODO: Publish BidAwardedEvent for each award to trigger: Contract creation / Escrow lock / Notification` comment. Verify current wiring before treating this sequence as unconditionally guaranteed end-to-end in every code path (see epic-05 Story 5.5).

### 2.3 Award Failure Handling

**Rule BR-009a: Award Validation Failure Recovery**

| Failure Point | System Action | Business Action |
|--------------|---------------|-----------------|
| Insufficient balance | Error with `maxAffordableQuantity`/shortfall (BR-007/BR-009) | Deposit funds, retry, or award partial quantity |
| Bid no longer `SUBMITTED`/wrong line item | Validation error, that award excluded | Select a different bid |
| Escrow lock fails after contract creation | Contract → `ESCROW_LOCK_FAILED` (see BR-011) | Business deposits; admin/business triggers manual retry — **no automatic rollback of the contract or award occurs** |

---

## 3. ESCROW & FINANCIAL RULES

### 3.1 Escrow Lock Timing & Amount

**Rule BR-010: Automatic Escrow Locking on Contract Creation**

Real code comment: *"BR-010: Automatic escrow locking on contract creation"* (`ContractCreatedEventHandler.cs`, `ContractCreatedEvent.cs`).

- **When:** triggered by `ContractCreatedEvent`, immediately after contract creation — not before it, and not synchronously inside the award call.
- **Amount (BR-031A, the same formula used for BR-007's max-affordable guidance):** `Σ over line items of (UnitAmount × QuantityAwarded × min(DurationDays, 30))`. Contracts ≤30 days lock their full value; contracts >30 days lock only the first 30 days at creation (subsequent cycles are locked later via `LockNextCycleEscrowCommand` during settlement rollover — §12).
- Funds physically move `MAIN → ESCROW` via a real double-entry `WalletLedgerTransaction`/two `WalletLedgerEntry` rows — the escrow wallet is a genuine `WalletAccount` row (`AccountType = "ESCROW"`), not a virtual flag.
- On success: `Contract.ActivateAfterEscrowLock()` → `PENDING_VEHICLE_ASSIGNMENT` (RFQ path) or straight to `PENDING_SIGNING` (Direct Rental, vehicles pre-assigned at booking) → publishes `ContractEscrowLockedEvent` (this is **not** contract activation — see §5).

**Rule BR-011: Escrow Lock Failure Recovery**

Real code comment: *"BR-011: 5-retry logic with exponential backoff for escrow failures"* / *"Backoff: 1s, 2s, 4s, 8s, 16s (total: 31 seconds)"* (`ContractCreatedEventHandler.cs`).

- On insufficient balance, the lock is retried **5 times with exponential backoff: 1s, 2s, 4s, 8s, 16s** — this happens synchronously inside the initial event handling, **not** "every 30 minutes" as an earlier version of this document stated, and it is **not** a background-job polling loop.
- After the 5th failure: `Contract.MarkAsEscrowLockFailed()` sets status to `ESCROW_LOCK_FAILED` (not "`PENDING_ESCROW` holding state" as an earlier draft said — `ESCROW_LOCK_FAILED` is its own distinct, real status string).
- **No automated business/admin notification fires on this transition** — the handler only logs a `LogCritical` line; two `// TODO` comments for business/admin notification and an admin task queue remain unimplemented.
- Manual recovery: `RetryEscrowLockCommand` (`POST /api/finance/escrow/{contractId}/retry`) pre-validates balance, then `Contract.ResetForEscrowRetry()` returns the contract to `PENDING_ESCROW` and republishes `ContractCreatedEvent`.
- A separate background job, `EscrowTimeoutJob` (every 15 minutes, **not** part of the 5-retry sequence), cancels any contract still stuck in `PENDING_ESCROW` past a configurable timeout (`ESCROW_RELEASE_DELAY_HOURS` MasterData setting, default 24 hours) via `Contract.Cancel()` → status `CANCELLED` (a real, reachable status **not present in the C# `ContractStatus` enum at all**).

### 3.2 Wallet Balance Requirements

**Rule BR-064: When Wallet Balance Is Required (renumbered from a colliding BR-012 in v1.2 — see Appendix A)**

| Action | Wallet Balance Required? |
|--------|--------------------------|
| Browse marketplace / create RFQ / publish RFQ / receive bids | ❌ No (BR-002) |
| **Award a bid** | ✅ **Yes** — must cover escrow for all selected awards (BR-006/BR-007) |
| Escrow lock at contract creation | ✅ Yes — re-validated independently, with retry (BR-010/BR-011) |
| **Ongoing contract "continuation" balance / next-cycle funding** | ⚠️ **NOT ENFORCED as a suspension trigger.** See the Reality Check below — there is no live mechanism that pauses or collects an active contract for insufficient balance. |

**🚨 Major correction from v1.2 — the "Payment Default" grace-period saga is NOT YET IMPLEMENTED.** The previous version of this document described an elaborate flow: T-10/T-5/T-2/T-1/T-6h reminder notifications, a `Day 31` automatic contract suspension to a `SUSPENDED`/`ON_HOLD` status, a provider choice between "collect vehicles" or "grant a 1–7 day grace period," daily usage accrual during grace, a 5% late fee, debt tracking, and account suspension on non-payment. **None of this exists in code.** Confirmed facts:
- **There is no `SUSPENDED` contract status anywhere in code, past or present.**
- `Contract.Status` values `ON_HOLD` and `DISPUTED` are defined in the (unused) C# enum and guarded against in the delivery/return status-aggregation function, but **nothing anywhere ever sets a contract to either value** — they are vestigial/reserved.
- Once a contract reaches `ACTIVE`, **nothing in the Contracts module re-checks the business's wallet balance to suspend, pause, or collect the vehicle for non-payment.** Escrow is only locked once (at creation, plus rollover at settlement time — §12) and settlement debits the already-locked escrow, not a live balance check against the business's spendable funds.
- There is no "debt record," no "grace period," no "late payment fee," and no automated reminder-notification cadence for ongoing-contract funding anywhere in the Finance module.
- **Recommendation:** if this payment-default protection is still a wanted product capability, it needs to be designed and built as new work — do not assume any part of the elaborate flow above is live, and do not build new features on top of it as though it exists.

---

## 4. VEHICLE ASSIGNMENT & DELIVERY

### 4.1 Vehicle Assignment Prerequisites

**Rule BR-013: Pre-Assignment Validation**

Provider can assign a vehicle to a contract line item only if:
1. Contract status is one of `PENDING_VEHICLE_ASSIGNMENT`, `PENDING_ACTIVATION`* , `PENDING_SIGNING`, `PARTIALLY_DELIVERED`, `PARTIALLY_RETURNED` (`ContractAssignmentRules.AssignableContractStatuses`) — *`PENDING_ACTIVATION` is listed in the rule table but is unreachable at the contract level (§14.3), so this branch is harmless dead code.
2. Vehicle status is `APPROVED` and owned by the awarded provider.
3. Vehicle is not already `ASSIGNED`/`DELIVERED` on a different contract or a different line item of the same contract.
4. Vehicle insurance is currently valid (zero-tolerance gate, BR-028).

`POST /contracts/{id}/line-items/{lineItemId}/assign-vehicle` accepts 1..N vehicle IDs per call and is idempotent per vehicle. Once a line item's assigned quantity reaches its awarded quantity, the line item advances; once **every** line item is fully assigned, the contract advances to `PENDING_SIGNING`.

### 4.2 Dual-Party Contract Terms Signing (distinct from delivery OTP)

**Rule BR-013a: Signing Gate**

- `POST /contracts/{id}/terms/otp/generate` creates/refreshes a `ContractTermsAcceptance` bound to the active `ContractTermsVersion`, generating an independent 6-digit OTP per party (5-minute validity, 60-second resend cooldown per party).
- `POST /contracts/{id}/terms/otp/verify` lets only the authenticated caller's own party confirm their own code — no cross-party verification path exists.
- Once **both** parties confirm, `Contract.MarkTermsSigned()` sets status to `"SIGNED"` then **immediately overwrites it to `"PENDING_DELIVERY"` in the same method call, before `SaveChanges`** — `SIGNED` is never a persisted, queryable row and gets no `ContractStatusHistory` entry. Treat it as a logical instant in the narrative, not a real database state.
- This is a **completely separate mechanism** from the delivery-confirmation OTP below — different entity (`ContractTermsAcceptance` vs. `DeliveryOTP`), different endpoints, different purpose (terms agreement vs. proof of physical handover).

### 4.3 Delivery & OTP Verification

**Rule BR-014: Delivery Confirmation Process (checklist-gated, not photo-gated)**

The real condition-verification mechanism is a **vehicle inspection checklist**, not a 5-photo/odometer "handover evidence" record (that entity, `DeliveryVehicleHandover`, exists in the schema/migrations but **nothing anywhere writes to it** — dead schema).

**Process:**
1. Provider (delivery) submits a structured checklist (`POST /delivery/sessions/{id}/checklist`) — bool/enum/numeric fields (fuel level, odometer, tyre condition, visible damage, lights, spare tyre, documents-in-vehicle, etc.), no photo upload. All `IsRequired` items (minus EV-only items on non-EV vehicles) must have a response.
2. Business approves or rejects the checklist (`POST /delivery/checklists/{id}/approve|reject`). A rejection carries an optional reason; the provider fixes the checklist and submits it again (BR-015).
3. **OTP generation is hard-blocked server-side until the checklist is `APPROVED`** — enforced in `GenerateOTPCommandHandler`, not just a UI convention.
4. Provider requests the delivery OTP (`POST /delivery/sessions/{id}/otp/generate`) — a 6-digit, cryptographically random code, **5-minute expiry**, sent via SMS (or email fallback) to the **business** — it is **never returned in any API response** (`GenerateOTPResponseDto.Code` is always an empty string by design).
5. The business reads/shows the code to the provider; the provider enters it (`POST /delivery/sessions/{id}/otp/verify`) to confirm delivery.

**⚠️ OTP Lockout — NOT IMPLEMENTED.** There is no attempts counter or lockout field on `DeliveryOTP`/`ReturnOTP` in code. An expired or already-used OTP simply fails verification with an error; a fresh OTP must be generated. Treat "3 incorrect attempts → 30-minute block, then escalate to support" as **aspirational, not current behavior**.

**Configuration:** OTP expiry is a fixed 5 minutes in the real delivery/return flow (not a MasterData-configurable `otp.expiry.minutes` setting defaulting to 15 minutes, as an earlier draft claimed — that configurable-setting claim was not found in code).

**No GPS, no arrival radius, no location verification anywhere in this flow** — confirmed zero `Latitude`/`Longitude` references in the Delivery module; `DeliverySession.LocationAddress` exists but every session-creation path writes it as `null`.

### 4.4 Delivery / Checklist Rejection

**Rule BR-015: Rejecting a Checklist, and Resubmitting It**

The party that reviews a checklist can reject it: the **business** rejects the provider's delivery checklist, and the **provider** rejects the business's return checklist (mobile: `POST mobile/delivery/checklists/{id}/reject` and `POST mobile/delivery/returns/checklists/{id}/reject`, body `{reviewedByName, reason?}`).

- **Before OTP only.** Checklist approval gates OTP generation entirely (BR-014), so a rejection always happens before any code is sent.
- **The reason is kept** (`reviewReason`, up to 500 characters, optional) and returned with the checklist.
- **The submitter is told.** The provider gets `delivery_checklist_rejected`; the business gets `return_checklist_rejected` (in-app/push and email). Both include the contract number, the plate and the reason.
- **Fix and resubmit.** The submitter sends a corrected checklist for the same session through the usual submit endpoint. The rejected checklist is kept as history. A session has at most one live (not rejected) checklist, so a second submission while one is waiting for review is refused. The session's checklist endpoint returns the latest one.
- **No limit and no automation.** There is no cap on resubmissions and no automatic "replace the vehicle, cancel the contract, or escalate to a dispute after 24h" pipeline; dispute escalation is **NOT YET IMPLEMENTED** (§13). If the two parties cannot agree, the provider can still replace the vehicle (new session, new checklist).
- **After OTP verification:** delivery is final for that vehicle — there is no "reject after OTP" path. Post-delivery issues are handled through the early-termination flow (§6) or (once built) a dispute process, not a delivery-rejection reversal.

---

## 5. CONTRACT ACTIVATION & LIFECYCLE

### 5.1 The Real 18-Value Status Model

**Rule BR-016: Contract Status Is a Plain String, Not the C# Enum**

`Contract.Status` is a plain `string` column. A C# `ContractStatus` enum exists (17 members) but is **referenced nowhere in the codebase outside its own file** — confirmed zero usages. The real system produces **18** distinct string values (one, `CANCELLED`, isn't in the enum at all):

| # | Status | In enum? | Reachable? |
|---|---|---|---|
| 1 | `DRAFT` | ✅ | ❌ backing-field default only, always overwritten before save |
| 2 | `PENDING_ESCROW` | ✅ | ✅ initial status for every contract, regardless of source |
| 3 | `ESCROW_LOCK_FAILED` | ✅ | ✅ |
| 4 | `PENDING_VEHICLE_ASSIGNMENT` | ✅ | ✅ |
| 5 | `PENDING_ACTIVATION` | ✅ | ❌ vestigial — guarded against, never set |
| 6 | `PENDING_SIGNING` | ✅ | ✅ |
| 7 | `SIGNED` | ✅ | ⚠️ momentary, never persisted (BR-013a) |
| 8 | `PENDING_DELIVERY` | ✅ | ✅ |
| 9 | `PARTIALLY_DELIVERED` | ✅ | ✅ |
| 10 | `ACTIVE` | ✅ | ✅ |
| 11 | `TERMINATION_REQUESTED` | ✅ | ✅ |
| 12 | `TERMINATED` | ✅ | ✅ (request→approve pair only) |
| 13 | `COMPLETED` | ✅ | ✅ |
| 14 | `DISPUTED` | ✅ | ❌ vestigial — never set |
| 15 | `ON_HOLD` | ✅ | ❌ vestigial — never set |
| 16 | `TIMEOUT_PENDING` | ✅ | ✅ |
| 17 | `PARTIALLY_RETURNED` | ✅ | ✅ |
| 18 | `CANCELLED` | ❌ not in enum | ✅ |

**There is no `SUSPENDED` status anywhere in code, past or present.** See BR-064 for the confirmed absence of any wallet-driven suspension mechanism.

### 5.2 Contract Activation

**Rule BR-017: Contract Activation Conditions**

Activation to `ACTIVE` requires **every** awarded vehicle across **every** line item to be delivered and OTP-confirmed — not "escrow locked + ≥1 vehicle assigned + ≥1 delivery" as an earlier draft implied.

- **Single-vehicle contracts:** first (and only) delivery → `ACTIVE` directly.
- **Multi-vehicle contracts:** first delivery(ies) → `PARTIALLY_DELIVERED`; the delivery that completes the last remaining vehicle → `ACTIVE`, and only at that exact moment is `ContractActivatedEvent` published — the one true "activation" event in the system.
- On the **first** delivery for a contract (regardless of how many more remain), the full settlement schedule is generated, anchored to that first-delivery date (BR-031A) — not to contract creation and not to the eventual `ACTIVE` moment.
- No explicit business "accept partial delivery" action is required — status updates automatically from delivered/returned quantities (`Contract.UpdateStatusBasedOnDelivery()`).

**Rule BR-018: No Fixed Activation Timeout to Cancellation**

There is **no** 5-day "activate-or-notify-then-manually-intervene" timeout tied to escrow-lock/assignment/signing/delivery stages specifically. The only real time-boxed stage is the **pre-escrow** window (`EscrowTimeoutJob`, 24h default, → `CANCELLED`). A contract can sit in `PENDING_VEHICLE_ASSIGNMENT`, `PENDING_SIGNING`, or `PENDING_DELIVERY` indefinitely with no automatic timeout — this is a real gap, not a documented design choice, worth flagging for a future notification/escalation job. Separately, `ContractEndLifecycleJob` (daily, ~00:45 UTC) moves any contract **past its end date** with vehicles still outstanding to `TIMEOUT_PENDING` (§5.4) — that is a different mechanism from an "activation timeout."

### 5.3 Contract Completion

**Rule BR-019: Contract Completion Trigger (two-party, not automatic on schedule)**

`COMPLETED` is reached only via the two-party completion flow — see §16 for full prerequisites (every vehicle `RETURNED`, no unresolved settlement cycles, settlement-coverage guard, requester ≠ approver). It is **not** simply "rental period ends + vehicle returned + no disputes" as a flat trigger — there is no automatic transition to `COMPLETED` on end-date reached; `TIMEOUT_PENDING` is the real outcome of an unreturned end-dated contract (§5.4), and even a fully-returned contract stays in `PARTIALLY_RETURNED` until an explicit two-party (or admin-override) completion action.

### 5.4 Timeout Pending

**Rule BR-018a: End-of-Term Timeout**

`ContractEndLifecycleJob` (daily) scans all non-`COMPLETED`/`TERMINATED`/`CANCELLED` contracts with `EndDate.Date <= today` and, for each with outstanding (non-`RETURNED`/`REPLACED`) vehicles: sets `TIMEOUT_PENDING` (once), attempts due-settlement generation, and notifies both parties. **Genuine ambiguity, confirmed in code:** `TIMEOUT_PENDING` is in the aggregation function's protected-status list, so a contract that enters it and then has all vehicles returned has **no automated path back into the normal completion pipeline** — it needs manual/admin intervention to move forward.

---

## 6. EARLY RETURN & TERMINATION PENALTIES

### 6.1 Early Termination (the real mechanism — request/approve, then Finance processes it)

**Rule BR-020: Early Termination Request & Approval**

- Either party requests (`POST /contracts/{id}/termination/request`) — the command handler allows this only from `ACTIVE` or `PARTIALLY_RETURNED` (a narrower guard than the underlying domain method, which also nominally allows `PENDING_ESCROW`/`PENDING_ACTIVATION` — those branches are unreachable through the real endpoint).
- Any of business/provider/admin approves (`POST /contracts/{id}/termination/approve`) — **no self-vs-other-party restriction here**, unlike completion (§16). Contract → `TERMINATED`; `ACTIVE` line items force-terminated too.
- **There is no reject/withdraw endpoint** for a submitted termination request once submitted.

**Rule BR-021: Early Termination Settlement Calculation (`ProcessEarlyTerminationCommand`)**

```
totalDays  = contract.EndDate - contract.StartDate (days)
usedDays   = min(now - contract.StartDate, totalDays)
usedAmount = (contract.TotalContractValue / totalDays) × usedDays

remainingValue = escrowLock.Amount                      // the actual locked amount, not recomputed
penalty        = MasterData EARLY_TERMINATION policy applied to remainingValue
refund         = remainingValue − penalty                // → business MAIN

commissionRate     = weighted-average of the contract's OWN line-item commission rates
                      (snapshotted at contract creation — a provider's tier change mid-contract
                      does NOT retroactively change what's owed)
platformCommission = usedAmount × commissionRate
providerSettlement = usedAmount − platformCommission      // → provider MAIN
```
Two `CommissionEntry` audit rows are recorded (`CONTRACT_COMMISSION`, `PENALTY`); the escrow lock is released. **Blocked entirely** while the escrow lock is `DISPUTED`.

**🚨 Correction from v1.2 — no business-tier-based penalty schedule exists.** The previous version of this document described a notice-period-tiered penalty table (7+ days = 0%, 3–6 days = 2%, 0–2 days = 15%) and separately a business-tier-based schedule (Standard 25% / Business Pro 20% / Enterprise 15%). **Neither exists in code as an enforced, business-tier-driven rate.** What is real:
- The `EARLY_TERMINATION` penalty is resolved from MasterData's `ContractPolicyVersion/Rule` engine (scenario code `EARLY_TERMINATION`), which is admin-configurable — but the **seeded default is `PenaltyType = "NONE"` (0% penalty)** for MVP. `BusinessTier` (`STANDARD`/`BUSINESS_PRO`/`ENTERPRISE`/`GOV_NGO`) governs only RFQ/contract **volume limits** — it has no field or code path that drives a penalty rate.
- A separate notice-period-based `InitiateEarlyReturnCommand` exists in code (grace-period lookup from `ContractPolicyRule`'s `EARLY_RETURN` scenario, seeded to 168 hours / 7 days, `PenaltyType = "NONE"`) — but it **has no controller endpoint anywhere and is never invoked from any other module** — confirmed unreachable in the running system.
- **Recommendation:** if a real, live notice-period or business-tier-based penalty schedule is wanted, it must be built (either wiring the existing `InitiateEarlyReturnCommand` to an endpoint, or changing the seeded `EARLY_TERMINATION`/`EARLY_RETURN` policy rows from `NONE` to a real percentage) — do not assume either exists today.

### 6.2 Damage During Early Return

**Rule BR-022: Damage Handling — mechanism partially unconfirmed**

Vehicle condition at any return is captured via the same **checklist** system used for delivery (§4) — not photos, not a separate "damage dispute" entity. A structured, code-level "business covers damage cost, provider raises a dispute with evidence" workflow was **not confirmed as implemented** — there is no `Dispute` entity anywhere in the backend (§13), so any damage disagreement today has no formal in-product resolution path beyond the checklist's warning flags and whatever the two parties agree out-of-band.

---

## 7. PROVIDER REJECTION HANDLING — NOT YET IMPLEMENTED

**Status: confirmed absent as a bid/award-level workflow.** A repo-wide search of the Marketplace module found **no "provider rejects an already-awarded bid" command, endpoint, or status transition** — the only real post-response rejection flow in the codebase belongs to **Direct Rental** (`RespondToDirectRentalRequestCommand`, a different product surface — see §19), not RFQ/bidding. Once an `RFQBidAward` is created, there is no code path for the provider to subsequently reject it.

**Rule BR-023 (proposed, not built): No-Penalty Rejection Scenarios**
- Legitimate reasons (vehicle broken, insurance expired, force majeure) and a first-free/repeated-penalty escalation model are a reasonable design, but **no implementation exists** — keep this section as an open backlog item, not a shipped rule.

**Rule BR-024 (proposed, not built): Manual Re-Award Process**
- A "bid rejected → reactivate other bids → business manually re-awards" workflow is plausible given the split-award model already in place, but **no rejection trigger exists to start it**.

**Rule BR-024a (partially real): Trust Score Impact of Rejections**
- The trust-score formula (§8, BR-025) does have a single `RejectionPenaltyPoints` input for bid-award rejections — so the *formula* has a slot for this. But since (a) there is no rejection command to populate it and (b) the whole recalculation pipeline is dormant (§8), this input never actually fires in production today. Treat the entire "escalating rejection penalty" table as **NOT YET IMPLEMENTED**.

---

## 8. TRUST SCORE CALCULATION

### 8.1 Trust Score Formula (real, live formula — but dormant wiring)

**Rule BR-025: Trust Score Calculator**

Real code comments: *"BR-025: Trust Score Calculator"*, *"BR-025 Constants"*, *"Calculates the trust score according to BR-025 formula"* (`TrustScoreCalculator.cs`, `ITrustScoreCalculator.cs`).

```
Score = Base(50 if IsVerified else 0)
      + CompletionRate × 20      // completed contracts / total contracts, 0.0–1.0
      + OnTimeRate × 20          // on-time deliveries / total deliveries, 0.0–1.0
      − NoShowRate × 30          // no-shows / scheduled deliveries, 0.0–1.0
      + RejectionPenaltyPoints   // negative int (no live producer today — see §7)

Score = clamp(Score, 0, 100)
```

**❌ Not part of the real formula** (confirmed absent, contra v1.2's "5-factor weighted model"): a separate "quality/ratings" input, a "dispute history" input, or any weighted-percentage scheme (30/25/20/15/10). There is no rating system and no dispute entity to feed either.

`Provider.TrustScore` defaults to **50 for every new provider at registration** (not 0 for unverified — every provider, verified or not, gets the same starting value; see §9.2). Every score change is appended to `ProviderTrustScoreHistory` (old score, new score, reason, optional reference), never overwritten, and emits `TrustScoreUpdatedEvent`.

**🚨 Critical gap, unchanged from v1.2 and still open as of this rewrite:** a repo-wide search found **zero production call sites** for `ITrustScoreCalculator.CalculateScore(...)` or `Provider.UpdateTrustScore(...)` outside unit tests. No handler for contract completion, delivery outcome, no-show, or bid-award rejection recomputes a score. **Every provider's trust score is frozen at 50 unless an admin manually reassigns a tier** (§9), and that manual path doesn't even consult the formula. Treat any statement that trust score "updates after X happens" as describing intended, not current, behavior.

### 8.2 Trust Score Display

**Rule BR-026: Trust Score Visibility (corrected — contradicts the "admin/business-only" assumption in some other epic docs)**

| Surface | Real behavior |
|---|---|
| Provider mobile app dashboard (`GET /identity/providers/me/dashboard-stats`) | Shows the provider their own live `TrustScore` + tier — **real, live** |
| Provider mobile app profile / bid-detail screens | Tier badge + trust score snapshotted on their own bid — **real** |
| Web business bid review (`BidCard.tsx`) | Real trust score/tier per bid — **real, live** |
| Web admin user-detail page | 🟡 Component can render a real score, but `admin-users-service.ts` **hardcodes `trustScore: 0`, `tier: 'SILVER'`** for both business and provider detail views today |
| Business mobile app | `RfqBid.trustScore`/`providerTier` are deserialized from the API but **no screen renders either field** — plumbing without UI |

Historical score graph / trend view: **NOT YET IMPLEMENTED** on any surface (consistent with §8.1's finding that the score essentially never moves today anyway).

---

## 9. PROVIDER TIER SYSTEM

### 9.1 Provider Tier Overview

**Rule BR-040: Provider Tier Structure & Commission Rates**

Real code comment: *"BR-040: Tier-based commission rates (Bronze: 10%, Silver: 8%, Gold: 6%, Platinum: 5%)"* (`ProviderTier.cs`).

| Tier | Commission Rate (real, seeded, admin-editable) |
|------|------------------------------------------------|
| **BRONZE** | 10% |
| **SILVER** | 8% |
| **GOLD** | 6% |
| **PLATINUM** | 5% |

**There is no "Red Zone" tier anywhere in code.** These four rates are the only ones seeded in `MasterDataSeeder.SeedProviderTiersAsync()` and are what `CommissionStrategyRule.CalculateCommission()` actually reads (via `ProviderTier.CommissionRate` — the `CommissionStrategyRule`/`CommissionStrategyVersion` entities do **not** carry an independent tier-rate table of their own; only one commission rule is seeded, bound to `SILVER` as the default fallback). Fallback commission rate when no tier resolves at all: a hardcoded **5%** (`BidAwardedEventHandler.DefaultCommissionRate`).

**🚨 Correction from v1.2 — "active fleet size" is not part of the live tier-*commission* rate at all.** Commission rate is purely a function of the provider's **currently assigned tier** (whatever an admin last set, or the `SILVER` default) — it does not additionally require a minimum active-vehicle count to unlock a given commission rate. The "active fleet size" concept below (§9.3) belongs to a **separate, dormant** tier-*qualification* calculation, not to commission-rate resolution.

### 9.2 Initial Provider Tier Assignment

**Rule BR-041: New Provider Tier Assignment**

**🚨 Correction from v1.2 — the real registration path is unconditional, not profile-completion-gated.** `Provider.Create()` hardcodes **every** new provider to `TrustScore = 50` and an initial `SILVER` `ProviderTierAssignment` — regardless of verification status or profile completion. This is confirmed in the live registration code path.

A **separate, dormant** service (`TierCalculationService`/`ProfileCompletionService`, code-commented `BR-041`) *would* implement a more nuanced rule — verified + 100%-complete profile → `SILVER`, else `BRONZE` — computing profile completion from required fields (business license, TIN certificate, bank account, phone/email verified, active vehicles, insurance documents). **This service has zero production call sites** — it is fully coded, unit-testable, and entirely unused by the real registration flow. Do not assume incomplete-profile providers start at `BRONZE`; they do not, today.

### 9.3 Provider Tier Calculation Logic (dormant — not used to assign tiers today)

**Rule BR-042: Hybrid Tier Determination (DORMANT — zero production call sites)**

Real code comments: *"BR-042: Hybrid tier model (trust score + active fleet size)"*, *"BR-042: Calculate provider tier using hybrid model"* (`TierCalculationService.cs`, `ITierCalculationService.cs`, `ProviderTierRule.cs`).

This is real, fully-coded logic — it is simply **never invoked in production**. Two different threshold schemes coexist in code and disagree with each other:

**Scheme A — hardcoded (`Domain/ValueObjects/TrustScore.cs`), used only for admin list-filtering:**
| Tier | Trust Score Range |
|------|-------------------|
| BRONZE | 0–49 |
| SILVER | 50–69 |
| GOLD | 70–84 |
| PLATINUM | 85–100 |

**Scheme B — seeded `ProviderTierRule` master data, used by the dormant `TierCalculationService`:**
| Tier | Trust Score | Min. Completed Contracts | Max Cancellation Rate | Min On-Time Rate |
|------|-------------|--------------------------|------------------------|-------------------|
| BRONZE | 0–59 | 0 | 20% | 70% |
| SILVER (default for new) | 60–74 | 10 | 15% | 80% |
| GOLD | 75–89 | 50 | 10% | 90% |
| PLATINUM | 90–100 | 100 | 5% | 95% |

The active-fleet-size thresholds (5+ / 15+ / 30+ vehicles for Silver/Gold/Platinum) referenced by `TierCalculationService`'s in-code `tierRequirements` object are **real code**, but a specific `min_active_vehicles` column does **not** exist on the seeded `ProviderTierRule` table today — the seeder's own comment notes this is "currently hardcoded in business logic... Future: move to `provider_tier_rule` as `min_active_vehicles` column." Both schemes, and the dormant service that would apply either of them, have **zero production call sites** — confirmed via repo-wide search. **Real, live tier assignment is 100% manual admin action** (`AssignProviderTierCommand`), which does not check the provider's actual score/fleet size against either scheme before accepting the admin's chosen tier.

**Whoever wires up automatic tier calculation must pick ONE of these two schemes and retire the other** — shipping both risks contradictory tier outcomes for the same provider.

### 9.4 Tier Upgrade & Downgrade — NOT YET IMPLEMENTED

**Rule BR-043: Automatic Tier Recalculation — NOT YET IMPLEMENTED**

No automatic upgrade/downgrade trigger (on trust-score change, on active-vehicle-count change, or on a monthly review job) exists in code — this depends entirely on Story-level wiring work described in §8.1 and §9.3 that has not been done. Any specific downgrade-protection grace period (e.g. "30 days") described in earlier drafts is aspirational design, not implemented behavior.

### 9.5 Tier Benefits

**Rule BR-044: Tier-Based Benefits**

**Confirmed real:** the four commission rates (§9.1). **Not independently confirmed as enforced product behavior this pass:** the various "priority support / featured listing / dedicated account manager / API access" benefit lists per tier — treat these as product positioning, not verified code gates, unless a specific feature is independently confirmed elsewhere in this document.

### 9.6 Tier Configuration (Master Data)

**Rule BR-051: Configurable Tier Thresholds**

- `masterdata.provider_tier` — tier definitions + `CommissionRate` (real, live, admin-editable via `ProviderTiersController`).
- `masterdata.provider_tier_rule` — Scheme B qualification rules (§9.3) — real rows exist, but the consuming service is dormant.
- `masterdata.commission_strategy_version`/`commission_strategy_rule` — versioned commission strategy; in practice only one rule is seeded (bound to `SILVER`, `IsDefault = true`), and `CalculateCommission()` simply reads `ProviderTier.CommissionRate` regardless of strategy version — this indirection exists in the schema but doesn't currently do more than the direct `ProviderTier` lookup would.
- **Admin UI for editing tier thresholds is a stub:** the `TiersPage.tsx` edit dialog shows `toast.info('Update functionality coming soon')` — admins cannot change tier thresholds or commission rates through the UI yet, only via direct database/seed changes.

---

## 10. BUSINESS TIER SYSTEM

### 10.1 Business Tier Overview

**Rule BR-045: Business Tier Structure (volume limits only — not a commission/penalty driver)**

Real, seeded `BusinessTier` rows (`MasterDataSeeder.SeedBusinessTiersAsync()`):

| Tier | Max RFQs/Month | Max Active Contracts | Max Vehicles/RFQ |
|------|-----------------|------------------------|-------------------|
| `STANDARD` | 10 | 5 | 5 |
| `BUSINESS_PRO` | 30 | 15 | 10 |
| `ENTERPRISE` | unlimited (`null`) | unlimited | unlimited |
| `GOV_NGO` | unlimited (`null`) | unlimited | unlimited |

**🚨 Correction from v1.2 — these are NOT the RFQ-limit numbers previously documented (20/50/100/unlimited), and there is no "PREMIUM" tier in code** — only `STANDARD`/`BUSINESS_PRO`/`ENTERPRISE`/`GOV_NGO` exist. `BusinessTier.CanCreateRFQ()`/`CanHaveContract()` guard methods exist on the entity, but whether they are actually invoked at RFQ/contract-creation time was **not independently reconfirmed** this pass.

**🚨 Correction — business tier drives volume limits only.** It does **not** determine early-termination penalty rate, commission, or settlement cadence anywhere in code — those are provider-tier or MasterData-policy concepts. Any "active fleet size" or "completed contract count" hybrid *tier-qualification* model for businesses (analogous to the dormant provider one in §9.3) was **not found in code** — no `BusinessTierRule` entity with an `IsQualified`-style method was located; treat any such hybrid business-tier-determination algorithm as design speculation, not implemented logic.

### 10.2 Initial Business Tier Assignment

**Rule BR-046: New Business Tier Assignment**

All new businesses start at `STANDARD`. An automatic upgrade path based on completed-contract count or active fleet size was **not confirmed as implemented** — treat as aspirational unless a real command/handler is located.

### 10.3–10.6: Business Tier Calculation, Upgrade, Benefits, Downgrade — NOT YET IMPLEMENTED

**Rules BR-047 through BR-050 (proposed, not built):** the hybrid tier-determination algorithm, automatic upgrade triggers, tier-specific benefit lists (extended payment terms, dedicated account manager, custom SLAs, etc.), and downgrade/grace-period rules described in earlier drafts of this document were **not found implemented anywhere in code**. `BusinessTier` is a simple, admin-managed master-data row with three numeric limit fields — nothing more automated exists today. Keep these as explicit open backlog items rather than presenting them as live.

---

## 11. COMPLIANCE & VERIFICATION

### 11.1 KYC/KYB Verification

**Rule BR-027: Manual Verification Before Platform Access**

Business and provider verification is manual for MVP (compliance-officer document review) — real and consistent with the onboarding epics. A specific "48-hour SLA" and a fully itemized checklist (business lifetime ≥1 year, capital verification, attorney document check, etc.) were **not independently re-verified against code this pass** — treat itemized checklist content as directional guidance from product/ops process, not a hard-coded validation rule, unless re-checked.

### 11.2 Insurance Compliance

**Rule BR-028: Zero-Tolerance Insurance Policy**

- A vehicle without valid insurance **cannot** be listed, bid, assigned to a contract, or enabled for Direct Rental — confirmed as an enforced gate across the vehicle/marketplace/contract flows.
- A specific automated daily expiry-scan job with a fixed 30-day/7-day notification cadence and a "48-hour grace then suspend, contract stays active, provider liable" sub-flow was **not independently re-confirmed as implemented** this pass — treat the exact notification timeline as directional, not verified.

### 11.3 Document Re-Verification

**Rule BR-029: Periodic Re-Verification**

Annual re-verification of business licenses/insurance/ownership documents is a reasonable compliance practice; no automated re-verification job/reminder was confirmed in code this pass. Automated government-system integration remains **post-MVP / not implemented**.

---

## 12. SETTLEMENT PROCESSING

### 12.1 Settlement Triggers

**Rule BR-030: Real Settlement Triggers (corrected — the fictional event names below do not exist)**

**🚨 Correction from v1.2:** `ContractCompletedEvent`, `ContractAlteredEvent`, and `MonthEndEvent` — the three event names this document previously said triggered settlement — **do not exist anywhere in the Contracts module's domain events** (confirmed: the real events are `ContractCreatedEvent`, `ContractEscrowLockedEvent`, `ContractActivatedEvent`, `ContractTerminatedEvent`, `ContractCompletionRequestedEvent`, `ContractCompletionApprovedEvent`, `ContractTermsAcceptedEvent` — no `Completed`/`Altered`/`MonthEnd` variant among them).

**The real trigger is a command, not an event:** `GenerateSettlementCommand` (admin-triggered via `POST /api/finance/settlements/generate` or `.../generate-current-cycle`), which processes all contracts with a **due, `PENDING`** `MonthlySettlementSchedule` — see §12.2 for how those schedules are generated and §6 for how early termination is settled (a distinct command, `ProcessEarlyTerminationCommand`, not routed through the normal cycle machinery).

### 12.2 Settlement Cycle Generation

**Rule BR-031: Settlement Amount Formula**

```
Gross Amount (per settlement window) = Σ (UnitPricePerDay × ActiveDaysInWindow) across delivered vehicles
Commission = Gross Amount × commissionRate (value-weighted average of the contract's line-item rates,
             falling back to a flat 8% only if the contract has no line items at all)
Tax Withheld = (Gross − Commission) × WITHHOLDING_TAX_RATE (2% default, MasterData-configurable)
Net Settlement = Gross − Commission − Tax Withheld  →  paid to provider MAIN wallet
```

**Rule BR-031A: Contract-Level Schedule, Vehicle-Level Earnings (Partial Delivery/Return Safe)**

Real code comments: *"ESCROW CALCULATION (BR-010, BR-031A)"*, *"3. Generate settlement schedule on FIRST delivery (BR-031A)"* (`ContractCreatedEventHandler.cs`, `DeliveryConfirmedEventHandler.cs`).

- Settlement cycle **windows** (30-day, fixed) are generated at the **contract** level, anchored to the contract's start date (or, per Story 6.5/Delivery-spec, generation is triggered on first delivery — the schedule's date math is anchored to the first-delivery date, not contract creation).
- **Earnings** within a window are calculated from **actual vehicle activity**, not awarded quantities: `ActiveDaysInWindow` is the overlap of `[DeliveredAt, ReturnedAt)` with the settlement window. Undelivered vehicles contribute `0`; late deliveries contribute only from their real `DeliveredAt`; returned vehicles stop contributing after `ReturnedAt`/release.
- **This is the same 30-day cap concept used for the escrow lock (BR-010)** — one unifying idea (BR-031A) governs both "how much do we lock upfront" and "how do we earn it out over time."

### 12.3 Settlement Cycle Windows & Cadence

**Rule BR-032A: Rolling 30-Day Cycles, Anchored to Contract Start (NOT calendar-month, NOT tier-based)**

**🚨 Correction from v1.2 — this is the single most important settlement correction in this rewrite.** The previous version described (a) a calendar "runs on the last day of each month" job computing pro-rata amounts for that specific month, and (b) elsewhere (§12.4 in v1.2, `BR-033`) a **tier-based cadence** (Bronze/Silver monthly, Gold bi-weekly, Platinum weekly). **Neither matches code.**

**Confirmed real behavior:** `SettlementScheduleService` generates **fixed, inclusive 30-day windows** anchored to the contract's start date, capped at the contract's end date. A contract shorter than 30 days gets a single cycle. The **last** cycle is flagged `IsFinalSettlement = true`. There is **no branching on provider tier anywhere** in the schedule-generation code — every contract gets the same cadence regardless of tier. A code comment on `GenerateSettlementCommand.cs` (itself labeled `BR-FN-03`) describes the tier-based cadence table — **that comment is stale/aspirational and does not reflect what the code actually does.** Treat the fixed 30-day rolling window as ground truth; do not quote the tier-cadence comment as current behavior anywhere, including inside the codebase itself.

**Rule BR-033: Settlement Approval Workflow — Threshold-Based Auto-Approval (real, but simpler than described)**

An optional `SETTLEMENT_AUTO_APPROVE_THRESHOLD` MasterData setting exists and, if enabled, auto-approves a newly generated payout at or below the threshold immediately after generation (disabled by default). A specific "≥100,000 ETB requires manual Finance-Officer approval, flagged-account always manual" two-tier policy was **not independently confirmed** beyond this single threshold setting — treat the exact ETB cutoffs from earlier drafts as illustrative, not a verified rule.

### 12.4 Escrow Rollover & Refund at Settlement (real, detailed mechanics)

**Rule BR-033A: Cycle Terms (Normative Definitions)**
- **Current/Processable Cycle:** the earliest cycle for a contract that is `PENDING`, has `SettlementDate ≤ today`, with all earlier cycles in a terminal status (`SETTLED`/`CANCELLED`).
- **Dormant Cycle:** a later `PENDING` cycle, not yet processable.
- **Final Settlement Cycle:** the cycle flagged `IsFinalSettlement = true`.
- **Rollover-Applied Amount:** unused escrow from cycle N applied to reduce cycle N+1's lock need.
- **Rollover Excess Refund:** unused escrow beyond cycle N+1's need, refunded immediately to the business.
- **Final-Cycle Refund:** unused escrow in the final cycle, refunded directly (no rollover created).

**Rule BR-033B: Admin Settlement Action Scope**
- Default admin action is **settle the current/processable cycle** — dormant cycles may be displayed but must not be settleable.

**Rule BR-033C: Escrow Rollover and Refund Rules**
```
1. Compute unused escrow for the settled cycle (lockedAmount − contractGrossForCycle).
2. IF cycle is final: refund all unused escrow to business MAIN; release the lock.
3. IF cycle is NOT final:
   rolloverApplied = min(unusedEscrow, nextCycleEscrowNeed)
   excessRefund    = max(0, unusedEscrow − nextCycleEscrowNeed)   → refunded immediately
   walletDeduction = max(0, nextCycleEscrowNeed − rolloverApplied) → locked fresh for next cycle
   (falls back to a plain refund if no next cycle exists, e.g. contract ended early)
```

**Rule BR-033D: End-to-End Lifecycle (Actor + Trigger)**

| Step | Actor | Trigger | Outcome |
|------|-------|---------|---------|
| Delivery confirmation | Business + Provider | Delivery OTP + checklist approval | Vehicle assignment enters active service window |
| Return confirmation | Business + Provider | Return OTP + release confirmation | Vehicle service window closes (`ReturnedAt`) |
| Inspection capture | Business + Provider/Admin | Checklist submission (delivery or return) | Checklist stored, linked to session |
| Settlement generation | System/Admin | Due processable cycle | Payout created (`PENDING_ADMIN_APPROVAL`), no money moved yet |
| Settlement approval | Admin | Approve payout command | Provider payout posted; escrow release/refund/rollover applied atomically |
| Next-cycle escrow lock | System (inside approval) | Successful approval | Next-cycle lock created with rollover offset |
| Contract completion readiness | System | Completion request validation | Allowed only when required cycles are settled (§16) |

**Rule BR-033E: Contract Completion Financial Guardrail**

Contract completion is blocked while any required settlement cycle for returned vehicles lacks completed payout coverage, or while financial closure is otherwise incomplete (see §16.1's full prerequisite list, `ContractCompletionSettlementGuard`).

---

## 13. DISPUTE RESOLUTION — NOT YET IMPLEMENTED

**Status: confirmed absent on every surface.** There is **no `Dispute` entity anywhere in the backend** (repo-wide search returns zero hits for a dispute table/entity). `Contract.Status` values `DISPUTED` and `ON_HOLD` exist only as bare, never-set enum members (§5.1) — a contract can be conceptually "disputed" in narrative only; there is no evidence-collection entity, no admin arbitration screen, no resolution-to-escrow-instruction pipeline, and no trust-score-penalty wiring behind either status. `EscrowLock` and `ContractPenalty` have their **own**, unrelated `"DISPUTED"` status values (real, reachable via the freeze/dispute-flag API) — those are not the same field as `Contract.Status` and do not constitute a dispute workflow either; they just mark money as frozen pending manual, out-of-band resolution.

The five dispute categories, evidence requirements, 48-hour resolution timeline, and outcome tables from earlier drafts of this section (`BR-034` through `BR-037`) remain a reasonable **design reference** (see `project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md` for the fuller prior design thinking) but must not be presented as shipped behavior. If a business or provider wants to contest a delivery, condition, settlement amount, or contract term today, the only real in-product levers are: reject a checklist before OTP, with a reason the other party sees and answers with a corrected checklist (§4.4), the provider-invoice approve/reject flow for tax reclaim (unrelated to disputing a settlement calculation — see §12), and the admin's ability to freeze/unfreeze an escrow lock (a manual, out-of-band action, not a structured dispute workflow).

**Recommendation:** treat Stories 12.6–12.9 of `backlog/mvp/epic-12-risk-trust-scoring.md` (business risk scoring, fraud detection, dispute workflow, risk-based transaction limits) as an explicit, unresolved product-prioritization decision — the platform has operated without any of them through MVP.

---

## 14. STATUS DEFINITIONS

### 14.1 RFQ Status Flow

**Rule BR-038: RFQ Status Definitions (real: 9 values, not 7)**

```
DRAFT → PUBLISHED → BIDDING → BIDDING_CLOSED / PARTIALLY_AWARDED → AWARDED → COMPLETED
                                                                  ↘ EXPIRED (revivable) ↘ CANCELLED
```

| Status | Definition |
|--------|-----------|
| `DRAFT` | Created, not published |
| `PUBLISHED` | Visible to providers; auto-moves to `BIDDING` on the FIRST bid, not at publish time |
| `BIDDING` | ≥1 bid submitted |
| `BIDDING_CLOSED` | Business/admin manually closed bidding early (`PUT /{id}/close`) — distinct from `CANCELLED`/`EXPIRED` |
| `PARTIALLY_AWARDED` | Some line items' quantity fully awarded, others still open — remaining slots stay biddable |
| `AWARDED` | Every line item's cumulative award meets its requested quantity |
| `EXPIRED` | `RFQDeadlineJob` (every 5 minutes, not hourly) found the deadline passed — **revivable** via deadline extension, not a dead end |
| `CANCELLED` | Business/admin cancelled — allowed from any status except `AWARDED`/`COMPLETED`, including `PARTIALLY_AWARDED` (does not itself un-award or refund escrow already locked for line items awarded so far) |
| `COMPLETED` | (downstream contract completion territory, not solely an RFQ-level trigger) |

### 14.2 Bid Status Flow

**Rule BR-039: Bid Status Definitions**

```
SUBMITTED → AWARDED (per line item, may be partial) / WITHDRAWN
```
Real statuses observed in code: `SUBMITTED`, `AWARDED`, `WITHDRAWN` (and `REJECTED` only in the sense of "not selected when the RFQ reaches full `AWARDED`" — there is no provider-initiated post-award rejection status; see §7). Resubmission after withdrawal is explicitly allowed (BR-005).

### 14.3 Contract Status Flow

**Rule BR-065: Contract Status Definitions (renumbered from a colliding BR-040 in v1.2 — see Appendix A)**

See §5.1 for the full 18-value table. Summary happy path:
```
PENDING_ESCROW → PENDING_VEHICLE_ASSIGNMENT → PENDING_SIGNING → (SIGNED, momentary) → PENDING_DELIVERY
  → [PARTIALLY_DELIVERED] → ACTIVE → [PARTIALLY_RETURNED] → COMPLETED
Side branches: ESCROW_LOCK_FAILED, CANCELLED, TERMINATION_REQUESTED → TERMINATED, TIMEOUT_PENDING
```
Aggregation precedence (`Contract.UpdateStatusBasedOnDelivery()`): protected statuses (`ON_HOLD`, `TERMINATED`, `TIMEOUT_PENDING`, `DISPUTED`) are never silently overwritten; otherwise status is derived from aggregated `totalAwarded`/`totalDelivered`/`totalReturned` across operational line items, with full-return landing on `PARTIALLY_RETURNED` (deliberately, not `COMPLETED` — the two-party completion gate is never auto-bypassed). Full transition matrix: `MVP_CONTRACT_STATE_MACHINE.md`.

### 14.4 Contract Line Item Status Flow

**Rule BR-066: Contract Line Item Status Definitions (renumbered from a colliding BR-041 in v1.2)**

7 real values: `PENDING_VEHICLE_ASSIGNMENT → PENDING_ACTIVATION → PARTIALLY_DELIVERED → ACTIVE → PARTIALLY_RETURNED → COMPLETED`, plus `TERMINATED`. The separate `ContractLineStatus` C# enum has 8 members but is itself wrong — missing `PendingVehicleAssignment` (the real, heavily-used initial value) and including `OnHold`/`Disputed`, neither ever set at line-item level.

Quantity tracking: `QuantityAwarded` (immutable after creation), `QuantityDelivered` (cumulative OTP-confirmed), `QuantityActive` (currently assigned & not returned/removed), `QuantityReturned` (cumulative).

### 14.5 Vehicle Assignment Status Flow

**Rule BR-067: Vehicle Assignment Status Definitions (renumbered from a colliding BR-042 in v1.2)**

`ContractVehicleAssignment.Status` is a plain string with **no dedicated enum type**. 5 real values: `ASSIGNED → DELIVERED → RETURNED`, plus `REPLACED` (superseded by a replacement) and `REMOVED` (unassigned pre-delivery, or force-cleared by admin reset/abort — not documented in the entity's own code comment, which lists only the first four). `ContractVehicleBlockingRules.ActiveAssignmentStatuses = { ASSIGNED, DELIVERED }` — only these two hold a slot against the line item's awarded quantity and block the vehicle from reuse elsewhere.

**🚨 Correction: there is no `MAINTENANCE` status on `ContractVehicleAssignment` in real code** — an earlier draft of this document (§15 in v1.2) described a `DELIVERED → MAINTENANCE → DELIVERED` sub-flow with maintenance-period exclusion from earnings. This is **not implemented**; the real 5-value set above is exhaustive. Treat any maintenance-period-exclusion earnings math as a proposed future enhancement, not current behavior.

### 14.6 Vehicle Status Flow

**Rule BR-068: Vehicle Status Definitions (renumbered from a colliding BR-041 in v1.2)**

`APPROVED` is the real "vehicle is live and assignable" status (not a generic "ACTIVE" as some earlier drafts said) — consistent with usage throughout this document (§4.1, §19). A full enumerated status lifecycle beyond `PENDING_VERIFICATION → APPROVED/REJECTED → (assigned via contract/RFQ-award/Direct-Rental tracking, not a separate vehicle-level "ASSIGNED" status)` was not exhaustively re-verified this pass; treat vehicle-level status names other than `APPROVED` as directional unless independently reconfirmed.

---

## 15. VEHICLE ASSIGNMENT LIFECYCLE

### 15.1 Real Status Flow

**Rule BR-052: Vehicle Assignment Lifecycle (corrected to the real 5-value set)**

```
ASSIGNED → DELIVERED → RETURNED       (normal completion)
ASSIGNED → DELIVERED → REPLACED       (vehicle replacement — see 15.2, mostly unreachable in practice)
ASSIGNED → REMOVED                    (unassigned pre-delivery, or admin reset/abort)
```
See §14.5/BR-067 for the corrected 5-value table — `MAINTENANCE` is **not** a real status (correction from v1.2).

### 15.2 Vehicle Replacement Rules

**Rule BR-053: Vehicle Replacement Process — designed, largely unreachable today**

**Prerequisites (as designed):**
- Only `DELIVERED` or `ASSIGNED` vehicles can be replaced.
- Replacement vehicle must be `APPROVED`, available, and match contract specifications.
- **Post-delivery replacement requires a valid, signed `SCOPE_CHANGE` `ContractAmendment`** for the same contract.
- If the old vehicle is already delivered, its return flow must complete first (`RETURNED`, `ReleasedAt` present).

**🚨 Confirmed in code — this flow cannot actually complete today:**
- `ContractAmendment.Create()` (the entity that would produce the required `SCOPE_CHANGE` amendment) has **zero callers anywhere in the codebase** — no command, controller, or job ever creates one. This means the post-delivery replacement branch of `UnassignVehicleCommand` can never be satisfied in practice.
- A separate `ReplaceVehicleCommand`/handler exists, fully implemented (creates a new `DELIVERED` assignment, marks the old one `REPLACED`) — but **has no controller endpoint wired to it anywhere**, so it is unreachable via HTTP today.
- `ContractPenalty.Create()` (which would record a replacement/termination penalty) also has **zero callers** — no flow produces a penalty record despite UI copy in places (e.g. the admin termination page) implying penalties are applied.
- **Pre-delivery** unassignment (`UnassignVehicleCommand`'s simple-removal branch) **does work today** — this is the only reachable part of the vehicle-replacement story.

### 15.3 Maintenance Handling — NOT YET IMPLEMENTED

**Rule BR-054: Vehicle Maintenance During Contract — NOT YET IMPLEMENTED**

No `MAINTENANCE` status, maintenance-reason field, or maintenance-period-exclusion earnings calculation exists on `ContractVehicleAssignment` in real code (see the correction in §14.5). If this capability is wanted — temporarily pulling a delivered vehicle out of service without ending its assignment, and excluding that window from settlement earnings — it needs to be designed and built as new work, including new columns/status values and settlement-calculation changes.

---

## 16. CONTRACT COMPLETION RULES

### 16.1 Contract Completion Prerequisites (real — two-party flow, admin override available)

**Rule BR-055: Contract Completion Conditions**

Completion is only reachable from `PARTIALLY_RETURNED` and requires (identical checks across request/approve/admin-complete):
1. Every `ContractVehicleAssignment` (non-deleted) is `RETURNED`.
2. No `MonthlySettlementSchedule` for the contract is `LOCKED`, or `PENDING` with `SettlementDate ≤ today` (future-dated `PENDING` cycles don't block).
3. `ContractCompletionSettlementGuard`: every returned vehicle's `[DeliveredAt, ReleasedAt)` service window is covered by a `COMPLETED` settlement payout for every cycle it overlaps, and there is no unresolved `AVAILABLE` escrow rollover.
4. Requester ≠ approver/rejecter (self-approval and self-rejection are both blocked; admin is exempt).

**Flow:**
- `POST /contracts/{id}/completion/request` — either party requests; creates a `ContractCompletionRequest` (`Resolution = PENDING`); rejects if a request is already pending.
- `POST /contracts/{id}/completion/approve` — must be the **other** party (or admin); re-validates the same prerequisites; → `Contract.ApproveCompletion()` → `COMPLETED`.
- `POST /contracts/{id}/completion/reject` — the other party (or admin) can reject with a reason; contract reverts to `PARTIALLY_RETURNED`.
- `POST /contracts/{id}/completion/cancel` — only the original requester can withdraw their own pending request.
- `GET /contracts/{id}/completion/readiness` — structured readiness DTO (all-returned flag, pending-cycle count, settlement-coverage flag, blockers) for UI display without triggering a request.
- `POST /contracts/{id}/complete` (admin/super-admin) — bypasses the two-party requirement, same prerequisite checks, resolves any pending request as `ADMIN_OVERRIDE`.

**🚨 Correction from v1.2 — no separate `Contract.FinalSettlementProcessed` boolean drives completion timing** as a standalone gate distinct from the guard above; the real gate is the unified `ContractCompletionSettlementGuard` described in item 3 above, which already accounts for final-vs-non-final cycles via the settlement-coverage check. Treat "short-term settles once at completion, long-term needs its final cycle settled first" as the correct *intuition*, implemented through this one guard, not two separate mechanisms.

### 16.2 Settlement Schedule Status (real 4-value set — `LOCKED` is real, not deprecated)

**Rule BR-056: Settlement Schedule Status Flow**

**🚨 Correction from v1.2:** the previous version claimed `LOCKED` was "deprecated for simplicity," leaving only `PENDING → SETTLED`/`CANCELLED`. **This is incorrect.** `MonthlySettlementSchedule.Status` is real and includes `LOCKED` — confirmed via `ApproveSettlementPayoutCommand`, which explicitly marks `LOCKED` schedules as `SETTLED` upon payout approval, and §16.1's completion guard, which explicitly checks for no `LOCKED` schedule. The real flow is:
```
PENDING → LOCKED (once a payout is generated against it, PENDING_ADMIN_APPROVAL) → SETTLED (on payout approval)
PENDING → CANCELLED (if contract terminated early / cycle no longer applies)
```

### 16.3 Final Settlement Marker

**Rule BR-057: Final Settlement Identification**

`IsFinalSettlement = true` marks the last schedule for a contract, set at schedule-generation time. On contract extension (§18), the old final schedule is unmarked, new schedules are generated for the extension window, and the new last one is marked final.

---

## 17. SETTLEMENT CALCULATION WITH VEHICLE LIFECYCLE

### 17.1 Vehicle Earnings Calculation

**Rule BR-058: Vehicle-Level Earnings Calculation**

```
IF DeliveredAt is NULL: skip (not delivered yet, contributes 0)
ActiveStart = MAX(DeliveredAt, SettlementWindowStart)
ActiveEnd   = MIN(ReturnedAt ?? ContractEnd, SettlementWindowEnd)
IF ActiveEnd <= ActiveStart: skip (not active in this window)
DaysActive       = CEILING((ActiveEnd - ActiveStart).TotalDays)
VehicleEarnings  = DailyRate × DaysActive
```
Confirmed consistent with BR-031A: earnings are per-vehicle, only delivered vehicles count, late delivery/early return naturally shrink the earning window.

### 17.2 Replacement Handling in Settlements

**Rule BR-059: Seamless Earnings for Replacements (design intent — see §15.2 for why this is rarely reachable)**

Where a replacement *does* occur (pre-delivery unassign + new assignment — the only reachable path today, per §15.2), earnings are simply computed independently per assignment row via BR-058; there is no special "continuity" logic required or observed beyond the normal per-assignment date-window calculation.

### 17.3 Maintenance Period Exclusion — NOT YET IMPLEMENTED

**Rule BR-060: Maintenance Period Not Counted in Earnings — NOT YET IMPLEMENTED**

Depends entirely on the `MAINTENANCE` status/lifecycle described in §15.3, which does not exist in code. No earnings-exclusion-for-maintenance logic exists in the settlement calculation today.

---

## 18. CONTRACT EXTENSION RULES

### 18.1 Contract Extension Prerequisites

**Rule BR-061: Extension Eligibility (frontend fully built; backend endpoint MISSING — highest-priority gap in this document)**

- Prerequisites as designed: only contracts with `DurationDays ≥ 30` can be extended; new end date must be after the current end date; contract must not be `COMPLETED`/`TERMINATED`.
- **This is not a renewal.** There is no provider accept/reject step and no new `Contract` row created — it purely extends the existing contract in place. **There is no `renew` endpoint or concept anywhere in the codebase** — do not describe any flow as "contract renewal creates a new contract."

**🚨 Critical gap, confirmed in code:** `ExtendContractCommand`/`ExtendContractCommandHandler` is **fully implemented** (settlement-schedule regeneration logic and all), and the web app's `ExtendContractDialog.tsx` is a **fully shipped, user-facing button** calling `contractService.extendContract()` → `POST /contracts/{id}/extend`. **That route does not exist on `ContractsController` or any other controller.** Clicking "Extend Contract" in the running application has no working backend today — this is the single highest-priority gap identified anywhere in this document.

### 18.2 Contract Extension Process (as designed — backend logic ready, just not wired to a route)

**Rule BR-062: Extension Workflow**

```
1. Validate: long-term (≥30 days), new end date > current end date, not COMPLETED/TERMINATED
2. Unmark current final settlement schedule (IsFinalSettlement = false)
3. Generate new 30-day settlement schedules from (CurrentEndDate + 1 day) through NewEndDate
4. Mark the new last schedule IsFinalSettlement = true
5. Contract.EndDate = NewEndDate; extension reason recorded
```
**Known side effect, confirmed in code:** `Contract.ExtendEndDate()` also overwrites `TerminationReason` with an `"EXTENDED: ..."` audit note — the same field termination uses, so a contract's extension history and termination reason cannot cleanly coexist. Worth a follow-up fix (separate audit field) alongside wiring the missing endpoint.

### 18.3 Multiple Extensions

**Rule BR-063: Repeated Contract Extensions**

The regeneration logic in BR-062 supports being run multiple times (each extension continues the cycle-numbering chain) — but since the controller endpoint doesn't exist (BR-061), this is currently untestable end-to-end via the API; only unit/handler-level testing can exercise it today.

---

## 19. DIRECT RENTAL (VEHICLE CATALOG)

**Related specification:** [MVP_DIRECT_RENTAL_SPECIFICATION.md](./MVP_DIRECT_RENTAL_SPECIFICATION.md), [MVP_DIRECT_RENTAL_STATE_MACHINE.md](./MVP_DIRECT_RENTAL_STATE_MACHINE.md)

Direct Rental (DR) allows verified businesses to rent **specific provider-listed vehicles** without an RFQ — a fully built, fixed-price, non-bidding product parallel to the RFQ marketplace, spanning backend, web, and both mobile apps. It now has its own post-MVP epic (`backlog/post-mvp/epic-21-direct-rental.md`), having previously shipped with no epic number at all. Cart submit creates **Direct Rental Requests (DRRs)** — one per provider. Provider acceptance bridges to the **same** `Contract` aggregate and status machine described in §5, with `sourceType = DIRECT_RENTAL`.

### 19.1 Provider Catalog Rules

**Rule BR-DR-001: Business Eligibility**
- Business must be verified/active to browse the DR catalog, manage cart, submit requests, or cancel pending requests.

**Rule BR-DR-002: Vehicle Listing Eligibility**
- Vehicle must be `APPROVED`, have `IsAvailableForDirectRental = true` (provider opt-in), have `DailyRentalRate > 0`, and be owned by the listing provider.

**Rule BR-DR-015: Enable Direct Rental Guard**
- The system blocks `enable-direct-rental` while the vehicle is committed to an active contract vehicle assignment or an active RFQ award vehicle assignment.

### 19.2 Cart & Browse Rules

**Rule BR-DR-003: Cart Does Not Lock Vehicles**
- Cart items do not reserve a vehicle — other businesses may add the same vehicle to their own cart. Availability is enforced at **submit** and **cart date update** time only.

**Rule BR-DR-003a: Rental Period Validation**
- `startDate` must be today or future (UTC); `endDate` must be after `startDate`.

**Rule BR-DR-003b: Vehicle Unavailability Sources**
- A vehicle is unavailable for DR while in a non-expired `PENDING` DRR, an `ACCEPTED`/`PARTIALLY_ACCEPTED` DRR, an active contract assignment, or an active RFQ award vehicle assignment.

### 19.3 Cart Submit Rules

**Rule BR-DR-004: Wallet Balance Gate at Submit (not before)**
- Business `AvailableBalance` must be ≥ cart total at **submit** time — not required to browse or add to cart. Submit preview (`GET cart/submit-preview`) exposes `canSubmit`, `estimatedEscrowHold`, `shortfall`.

**Rule BR-DR-005: Submit-Time Availability Re-Check**
- Every cart vehicle ID is re-validated inside a DB transaction at submit — prevents a race between browse and submit.

**Rule BR-DR-006: One Request Per Provider Per Submit**
- Cart items are grouped by provider; each group produces exactly one `DirectRentalRequest`.

**Rule BR-DR-007: Line Item Grouping**
- Within each DRR, vehicles are grouped into line items by vehicle type; each specific vehicle is its own `DirectRentalRequestVehicle` row with snapshotted plate/make/model/rate/total.

**Rule BR-DR-007a: Request Number Format**
- `DR-{yyyyMMdd}-{NNN}` (daily sequence).

**Rule BR-DR-007b: All-or-None Flag**
- Business may set `isAllOrNone` on submit; if true, the provider must accept all vehicles or reject all.

### 19.4 Provider Response & Timeout Rules

**Rule BR-DR-008: 48-Hour Response Window**
- `expiresAt = createdAt + 48 hours`; `ExpireDirectRentalRequestsJob` (hourly) expires overdue `PENDING` requests and releases the vehicles.

**Rule BR-DR-009: Business Cancel (Pending Only)**
- Business may cancel their own request only while `PENDING` and before `expiresAt`.

**Rule BR-DR-010: Complete Vehicle-Level Response**
- Provider must respond accept/reject for **every** vehicle in the request.

**Rule BR-DR-011: Rejection Reasons**
- Rejected vehicles require a non-empty reason, minimum 5 characters per vehicle (10 chars for an aggregated request-level reject-all reason).

**Rule BR-DR-012: All-or-None Enforcement**
- When `isAllOrNone = true`, a mixed accept/reject response is rejected with a validation error.

### 19.5 Fleet Segment Capacity (RFQ Coexistence)

**Rule BR-DR-013: DR Accept Capacity Gate**
- Before accepting a vehicle on a DRR, the system validates fleet segment capacity (vehicle type + normalized fuel type) against overlapping RFQ bid/award commitments — the same shared-segment-pool logic used for RFQ bidding (BR-004), extended to Direct Rental. Block reasons: `DR_ACCEPT_AWARD_NOT_FULLY_ASSIGNED`, `DR_ACCEPT_VEHICLE_ON_AWARD`, `DR_ACCEPT_BID_CAPACITY`.

**Rule BR-DR-013a: Shared Segment Pool**
- Active bid quantities and unassigned award quantities consume the same segment capacity pool as Direct Rental acceptance — RFQ and DR compete for the same underlying fleet.

### 19.6 Contract Bridge Rules

**Rule BR-DR-014: Contract Creation on Acceptance**
- `ACCEPTED`/`PARTIALLY_ACCEPTED` → `CreateDirectRentalContractCommand`, `Contract.SourceType = DIRECT_RENTAL`, idempotent (re-syncs an existing contract for the same request rather than duplicating). Only vehicles with `isAccepted = true` become contract line items/assignments. Post-creation, the **same** contract lifecycle (escrow §3, delivery §4, settlement §12) applies.

**Rule BR-DR-014a: Pricing on Contract**
- Contract value derives from accepted vehicles' snapshotted `totalAmount`; commission rate from the provider's tier (5% fallback, same as RFQ — §9.1); duration = inclusive days between the request's `startDate`/`endDate`.

### 19.7 Direct Rental Status Definitions

| Status | Meaning |
|--------|---------|
| `PENDING` | Awaiting provider response (within 48h) |
| `ACCEPTED` | Provider accepted all vehicles |
| `PARTIALLY_ACCEPTED` | Provider accepted some vehicles (`isAllOrNone = false`) |
| `REJECTED` | Provider rejected all vehicles |
| `EXPIRED` | No response within 48h |
| `CANCELLED` | Business cancelled while pending |

All six are terminal except `PENDING`.

---

## 20. PROMOTIONS: HOT DEALS & FEATURED LISTINGS

**Related specification:** [MVP_PROMOTIONS_SPECIFICATION.md](./MVP_PROMOTIONS_SPECIFICATION.md)

**Status:** decided by the business owner on 2026-10-07; **implementation in progress** (backend PRs "Hot deals core", "Effective pricing", "Featured"). Re-verify against code after merge.

Promotions attract people to the public pages: businesses to **Hot deals** and **Featured vehicles**, providers to **Featured RFQs**. They are shown on the website, the portal and both apps' public and signed-in browse screens.

### 20.1 Hot Deals (vehicles)

**Rule BR-PROMO-001: Provider Proposes, Admin Approves**
- A hot deal is a lower daily rate for a date range on one direct-rental vehicle. The vehicle's **provider proposes** it; it is public only after an **admin approves** it. Admins may reject (reason required) or end it early (reason required); the provider may withdraw it while pending or approved.

**Rule BR-PROMO-002: Eligibility and Limits**
- The vehicle must be rentable (`APPROVED`, active, not in maintenance, direct rental on, rate > 0, provider `VERIFIED`) and owned by the proposing provider.
- `dealRate ≤ normalRate × (1 − HOT_DEAL_MIN_DISCOUNT_PERCENT)` (default 10%).
- Dates are Addis Ababa calendar days: start from today up to `HOT_DEAL_MAX_LEAD_DAYS` ahead (default 30); end ≥ start; at most `HOT_DEAL_MAX_DURATION_DAYS` long (default 14).
- At most **one open deal** (`PENDING_REVIEW` or `APPROVED`) per vehicle.
- Approval re-checks all of the above against the current rate.

**Rule BR-PROMO-003: Deal Statuses**
- `PENDING_REVIEW` → `APPROVED` → `EXPIRED` | `ENDED`; also `REJECTED`, `WITHDRAWN`. "Scheduled" and "live" are derived from the dates. A pending deal whose end passes expires.

**Rule BR-PROMO-004: Live Definition**
- Live = `APPROVED`, now within [00:00 Addis on the start day, 00:00 Addis after the end day), vehicle rentable, and deal rate below the normal rate. Every read applies this test; it never relies on the expiry job.

**Rule BR-PROMO-005: Honest Struck-Through Price**
- While a deal is open the provider cannot change the vehicle's normal rate (`HOT_DEAL_OPEN`). An admin rate change, turning direct rental off, or the vehicle becoming unrentable ends the deal.

### 20.2 Pricing

**Rule BR-PROMO-006: Effective Rate**
- Effective daily rate = live deal rate, else the normal rate. Catalogue lists, detail, the guest quote, cart, submit preview and submit all use it. Public DTOs report `dailyRentalRate` = effective rate, plus `normalDailyRate` and the deal.

**Rule BR-PROMO-007: Re-Price at Submit (supersedes the add-to-cart snapshot of BR-DR-007)**
- The rate shown in the cart is re-checked at submit. If a deal ended or the normal rate changed since the vehicle was added, the current effective rate applies; the cart and preview flag the change, and submit with a stale `expectedTotalAmount` returns 409 `CART_PRICE_CHANGED` so the business confirms the new price.
- A deal live at submit prices the whole rental. The request vehicle stores the charged rate, the normal rate and the deal id; contract, escrow (30-day cap) and settlement then work from the charged rate as before (BR-DR-014a).

### 20.3 Featured Listings

**Rule BR-PROMO-008: Admin-Curated**
- Admins feature direct-rental vehicles and open RFQs, with a sort order and an optional end date. At most `FEATURED_MAX_VEHICLES` and `FEATURED_MAX_RFQS` active (default 12 each); a target is featured at most once at a time. Paid featuring is reserved for later (`Source = PAID`).

**Rule BR-PROMO-009: Only While Listable**
- A featured vehicle shows only while it is rentable; a featured RFQ only while it is open for bids (`PUBLISHED`, `BIDDING`, `PARTIALLY_AWARDED`, deadline in the future). The expiry job ends rows whose target stopped qualifying or whose end date passed.

**Rule BR-PROMO-010: Featured Does Not Change Price or Normal Ranking**
- Featuring adds the item to the Featured sections and shows a badge; it does not change the price or the order of the normal lists.

### 20.4 Notifications

**Rule BR-PROMO-011: Who Is Told**
- Admins: deal proposed. Provider: deal approved, rejected (with reason), ended (by admin, rate change or vehicle unavailable), expired. Businesses are not notified about deals.

---

## APPENDIX A: Rule Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Dec 21, 2025 | Initial authoritative version consolidating all business rules |
| 1.1 | Feb 20, 2026 | Added vehicle assignment lifecycle rules, contract completion logic, settlement calc with vehicle lifecycle, contract extension rules |
| 1.2 | Jun 27, 2026 | Added §19 Direct Rental rules (BR-DR-001–BR-DR-015) |
| **2.0** | **2026-07-23** | **Full reconciliation against running code.** Every rule individually re-verified. Key corrections: (1) escrow/commission/contract-lifecycle math corrected to match code exactly (BR-007/BR-010/BR-031A cap formula, BR-011 real 1s–16s backoff timing, no "every 30 min" retry); (2) the entire "Payment Default" grace-period/suspension saga (§3.3 in v1.2) marked **NOT YET IMPLEMENTED** — no `SUSPENDED` status, no debt tracking, no grace period exists in code; (3) provider commission table confirmed as Bronze 10%/Silver 8%/Gold 6%/Platinum 5%, no "Red Zone" tier; (4) trust score formula corrected to the real 4-input formula (no 5-factor weighted model) and flagged as **dormant** (zero production call sites); (5) new provider default corrected to `SILVER`/`50`, not `BRONZE`/`0`; (6) settlement cadence corrected to a flat 30-day rolling window, not tier-based or calendar-month; (7) `LOCKED` settlement-schedule status restored as real (v1.2 incorrectly called it deprecated); (8) `MAINTENANCE` vehicle-assignment status removed as fictional (real set is `ASSIGNED/DELIVERED/RETURNED/REPLACED/REMOVED`); (9) §7 Provider Rejection Handling and §13 Dispute Resolution marked **NOT YET IMPLEMENTED** in full; (10) §18's contract-extension gap (missing `POST /contracts/{id}/extend` endpoint despite a fully-built frontend button) elevated to the top-priority flagged gap in this document; (11) fixed three internal `BR-ID` collisions from v1.2 by renumbering the non-code-referenced side of each collision: the wallet-timing rule (was `BR-012`, now `BR-064` — `BR-012` is reassigned to its real code meaning, tier-based commission-rate resolution) and the three colliding status-definition rules in old §12.3/12.4/12.5/12.6 (old `BR-040`→`BR-065`, one of two old `BR-041`s→`BR-066`, old `BR-042`→`BR-067`, the other old `BR-041`→`BR-068`) — `BR-001`–`BR-011`, `BR-025`, `BR-031A`, and `BR-040`–`BR-042` (provider-tier section) were left untouched because they match real code comments. |

---

| 2.1 | 2026-10-07 | Added §20 Promotions (BR-PROMO-001–011): provider-proposed, admin-approved **Hot deals** on direct-rental vehicles; admin-curated **Featured** vehicles and RFQs; effective-rate pricing and **re-price at submit** (supersedes the add-to-cart rate snapshot). Decided by the business owner; implementation in progress. BR-015 (checklist rejection and resubmission) was revised on 2026-10-07 in the same release. |

---

## APPENDIX B: Superseded / Corrected Claims

1. ❌ "Wallet balance required for RFQ creation" → BR-002 (confirmed absent).
2. ❌ "New providers start at BRONZE, trust score 0" → BR-041 (confirmed: `SILVER`, 50, hardcoded, unconditional).
3. ❌ "Escrow lock happens before contract creation" → BR-008a (confirmed: contract created first, escrow lock reacts to `ContractCreatedEvent`).
4. ❌ "Trust score uses a 5-factor weighted model with ratings/dispute inputs" → BR-025 (confirmed: 4-input formula only, no rating/dispute system exists).
5. ❌ "Escrow lock retries every 30 minutes" → BR-011 (confirmed: 5 attempts, 1s/2s/4s/8s/16s, inside the initial event handling — not a background poll).
6. ❌ "Settlement cadence is tier-based (weekly/bi-weekly/monthly)" → §12.3/BR-032A (confirmed: flat 30-day rolling window regardless of tier; the tier-cadence text is a stale code comment, not implemented logic).
7. ❌ "Contract 'suspends' (`SUSPENDED`/`ON_HOLD`) on payment default, with a grace-period/debt-tracking saga" → BR-064 (confirmed: no such status, mechanism, or job exists anywhere).
8. ❌ "Settlement schedule status simplified to `PENDING → SETTLED` only, `LOCKED` deprecated" → BR-056 (confirmed: `LOCKED` is real and used by the payout-approval flow).
9. ❌ "Vehicles can enter a `MAINTENANCE` status mid-contract with earnings exclusion" → §14.5/§15.3 (confirmed: not implemented; real status set has no `MAINTENANCE` value).
10. ❌ "Contract renewal creates a new contract, with provider accept/reject" → §18.1 (confirmed: no `renew` concept exists at all; the only real mechanism is in-place extension, and even that has no live backend endpoint yet).

---

**END OF AUTHORITATIVE BUSINESS RULES DOCUMENT**

**For Implementation Questions:** Refer to this document first; if a rule is unclear, missing, or looks stale relative to the code, treat the code as ground truth and flag it for a documentation update rather than assuming this document is still correct — it was last verified 2026-07-23.

**For Rule Conflicts:** This document takes precedence over `Business_Rules.md`, `05_BUSINESS_LOGIC_FLOWS.md`, and `CRITICAL_BUSINESS_RULE_UPDATE.md` (all in this same repository) for exact `BR-ID` numbering and precise formulas; those three documents should point back here rather than maintain their own competing numbering.
