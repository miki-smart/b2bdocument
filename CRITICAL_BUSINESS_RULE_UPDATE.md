# ⚠️ CRITICAL BUSINESS RULE UPDATE

**Originally issued:** November 26, 2025 (CTO Review)
**Last verified against code: 2026-07-23**
**Impact:** High — RFQ, Award, and Finance flows

**Status of this document:** The core rule change announced below — RFQ creation requires no wallet balance, award requires wallet balance, partial awards are supported, race conditions are guarded — **is real and confirmed live in code today.** This rewrite keeps the original announcement/rationale framing (useful context for *why* the rule is what it is) but corrects every code-level detail that has drifted: the original TypeScript/NestJS-style pseudocode does not represent the real system (the backend is .NET 9 / C#, not TypeScript), several endpoint paths shown below were never real, the escrow formula shown is an oversimplification of the real per-line-item cap, and one item in the original "implementation checklist" was never actually built. See the **Reality Check** callouts throughout. For the authoritative, numbered version of these rules, see [`MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md`](./MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md) — this rule set corresponds to **BR-002** (no wallet check at RFQ creation) and **BR-006 through BR-011** (wallet check at award, partial award, escrow lock with retry) there.

---

## 🔄 **CHANGE SUMMARY**

### **Previous (INCORRECT) Flow:**
```
RFQ Creation → Escrow Check ❌ → Publish → Bidding → Award → Escrow Lock
```

### **Correct (UPDATED) Flow — confirmed live in code:**
```
RFQ Creation → Publish → Bidding → Award (wallet balance validated) → Contract Created → Escrow Lock (Finance module, async, with retry)
```

**Reality Check:** the real sequence has one more real step than the diagram above implies: **award creates a contract first, and escrow locking happens as a reaction to contract creation** (`ContractCreatedEvent`), not as a direct synchronous step of the award call itself. See `BidAwardedEventHandler` (Contracts module) → `CreateContractCommand` → `ContractCreatedEvent` → `ContractCreatedEventHandler` (Finance module). This matters because it means award-time wallet validation and escrow-lock-time wallet validation are two genuinely separate checks, not one check reused twice — which is exactly why race-condition protection (§4 below) exists as real code, not a hypothetical.

---

## ✅ **BUSINESS RULES (as actually implemented)**

### **1. RFQ Creation (NO Funds Required)**

**Rule:** Businesses can create and publish RFQs **without** having funds in their wallet.

**Confirmed in code:** `RFQ`/`RFQLineItem` entity factories and `RFQController` perform no wallet lookup at all during creation or publish. No wallet-balance validation call exists anywhere in the RFQ creation/publish path.

**Rationale (unchanged from original):**
- Encourages RFQ creation (no barrier to entry)
- Businesses can explore market prices before committing funds
- Providers can bid without the business having deposited yet

**Reality Check on the illustrative snippet below:** the original doc showed this as NestJS/TypeScript-style pseudocode. The real implementation is C#/.NET 9 MediatR commands (`CreateRFQCommand`/`CreateRFQCommandHandler`). The shape of the rule is correct; the code syntax below is illustrative only, not a literal excerpt.

```
// Illustrative only — real handler is CreateRFQCommandHandler.cs (C#)
async createRFQ(command: CreateRFQCommand) {
  this.validateRFQDetails(command);       // vehicle type, quantity, dates, purpose, 30-day SHORT_TERM cap
  // NO wallet balance check here — confirmed absent in the real RFQ module
  const rfq = await this.rfqRepository.create(command);
  return rfq;
}
```

---

### **2. Award (Funds REQUIRED)**

**Rule:** Businesses **MUST** have sufficient wallet balance to award bids.

**Confirmed in code:** `AwardBidCommandHandler` (`Modules/Marketplace/Application/RFQBid/Commands/AwardBidCommand.cs`) calls `IWalletCalculationService` to validate `AvailableBalance` before creating any `RFQBidAward` row. The relevant code comments in that file literally read `// BR-006, BR-007, BR-008, BR-009: Validate wallet balance with affordability calculation`.

**Escrow Calculation — corrected formula (BR-031A):**
```
For each award in the request:
  lineItemEscrow = quantityAwarded × unitPrice × min(durationDays, 30)
totalEscrowRequired = Σ lineItemEscrow (across every award in the request)
```
**Reality Check:** the original doc's `escrow_multiplier = 1.0` framing was an oversimplification. The real rule is **not** a flat multiplier — it is a **per-line-item 30-day cap**: contracts of 30 days or less lock their full value; contracts longer than 30 days lock only the first 30 days at award/contract-creation time (subsequent cycles are locked later, at settlement rollover time — see Epic 10). This is why the same rule is called `BR-031A` in code comments (`ContractCreatedEventHandler.cs`, `RetryEscrowLockCommand.cs`) — it's the same 30-day-cap logic used both at initial lock and at retry.

**Validation (illustrative pseudocode, real handler is C#):**
```
async awardBid(command: AwardBidCommand) {
  // 1. Calculate total escrow required using the min(durationDays, 30) cap above
  const escrowRequired = this.calculateEscrowRequired(command.awards);

  // 2. Get business wallet, compute AvailableBalance = Balance - LockedBalance - PendingWithdrawalBalance
  const wallet = await this.walletService.getBusinessWallet(command.businessId);
  const availableBalance = wallet.availableBalance;

  // 3. Validate sufficient funds — real error carries an estimated affordable quantity (BR-008/BR-009)
  if (availableBalance < escrowRequired) {
    throw new InsufficientFundsException({
      required: escrowRequired,
      available: availableBalance,
      maxAffordableQuantity: this.calculateMaxAffordable(availableBalance, command)  // floor(balance / (unitPrice × min(duration,30)))
    });
  }

  // 4. Create the award row(s) — RFQBidAward per award, RFQLineItemFulfillment per award
  const award = await this.awardRepository.create(command);

  // 5. Real gap, confirmed in code: AwardBidCommandHandler.cs contains
  //    "// TODO: Publish BidAwardedEvent for each award to trigger: Contract creation / Escrow lock / Notification"
  //    Verify current wiring before assuming this publish step is unconditionally reached today.

  return award;
}
```

---

### **3. Partial Awards (Based on Available Funds)**

**Rule:** If a business has insufficient funds for a full award, they can:
1. **Award partially** (what they can afford)
2. **Deposit more funds** and retry
3. **Cancel** the award attempt

**Confirmed in code:** `AwardBidCommand` (`POST /api/marketplace/bids/award`) accepts a flat list of `{bidId, lineItemId, quantityAwarded}` and validates cumulative awarded quantity per line item against the line item's requested quantity — a single call can award pieces of one line item to several different providers' bids. `IWalletCalculationService.CalculateMaxAffordableQuantity` (real method name) computes the shortfall guidance shown in the error response.

**Example Scenario (numbers illustrative, mechanism real):**

```
RFQ Line Item: 10 EV Sedans @ ETB 3,500/day, 30-day term
Escrow needed for full award: 10 × 3,500 × 30 = ETB 1,050,000  (NOT simply 10 × 3,500 — see corrected formula above)

Business Wallet:
- Balance: ETB 1,200,000
- Locked (other contracts): ETB 1,150,000
- Available: ETB 50,000

Max Affordable: FLOOR(50,000 / (3,500 × 30)) = 0 vehicles at full 30-day term

OPTION 1: Partial Award (only possible if maxAffordable > 0)
- Award: as many vehicles as affordable
- Status: SUCCESS if maxAffordable ≥ 1, otherwise the API returns INSUFFICIENT_FUNDS with the shortfall

OPTION 2: Deposit & Full Award
- Deposit enough to cover the shortfall, retry award
- Status: SUCCESS
```

**Reality Check:** the original doc's illustrative numbers (10 vehicles at ETB 3,500 total, not ETB-per-day) implicitly assumed a single-day or already-multiplied unit price. The corrected worked example above uses the real `unitPrice × quantity × min(durationDays, 30)` formula so the escrow figure isn't misleading.

---

### **4. Race Condition Protection**

**Problem:** Multiple concurrent awards could exceed wallet balance.

**Confirmed in code, but implemented differently than the original snippet suggested:** the real protection is **not** a single `db.transaction` wrapping wallet-lock + contract-cancel + award-cancel in one block. It is two genuinely separate checks at two genuinely separate points in the pipeline:
1. **At award time:** `AwardBidCommandHandler` validates `AvailableBalance` against the total escrow required for the request.
2. **At contract-creation-triggered escrow-lock time:** `ContractCreatedEventHandler` (Finance module) re-validates the business `MAIN` wallet balance before debiting it, with **5-attempt exponential backoff** (1s, 2s, 4s, 8s, 16s — real, confirmed timing, not "every 30 minutes" as some older docs claim) if the lock fails. After 5 failures, `Contract.MarkAsEscrowLockFailed()` sets the contract to `ESCROW_LOCK_FAILED` — it does **not** automatically roll back/cancel the award or the contract; an admin (or the business, after topping up) must call the manual retry endpoint (`POST /api/finance/escrow/{contractId}/retry`).

**Reality Check:** the original pseudocode's "rollback everything, cancel contract, cancel award" behavior on a race-condition failure **is not what happens today**. The real failure mode leaves the contract sitting in `ESCROW_LOCK_FAILED`, requiring explicit manual intervention — there is no automatic unwind of the award or contract. Treat this as a known gap, not a documented "as designed" behavior: no automated business/admin notification fires on this state either (marked `// TODO` in the real handler).

```
// Illustrative only — real behavior is two separate checks + a stuck-state outcome, not one wrapped rollback
async handleContractCreatedEvent(event: ContractCreatedEvent) {
  const mainWallet = await getBusinessMainWallet(event.businessId);
  if (mainWallet.balance < event.escrowAmount) {
    // Retry 5x with 1s/2s/4s/8s/16s backoff, then:
    await contract.MarkAsEscrowLockFailed();   // status -> ESCROW_LOCK_FAILED
    // NOT: automatic contract/award cancellation — that does not happen today
    return;
  }
  await lockEscrow({ contractId: event.contractId, amount: event.escrowAmount, walletId: mainWallet.id });
}
```

---

## 📊 **UPDATED FLOW DIAGRAM (corrected)**

```
┌─────────────────────────────────────────────────────────┐
│              BUSINESS AWARDS BID                         │
└────────────────────┬────────────────────────────────────┘
                      │
                      ▼
          Calculate escrow required: Σ qty × unitPrice × min(duration, 30)
                      │
                      ▼
          Check wallet AvailableBalance
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
     Sufficient?              Insufficient?
          │                       │
          │                       ├─► Show error + max affordable quantity (BR-008/BR-009)
          │                       ├─► Offer partial award
          │                       └─► Offer deposit-then-retry
          ▼
   Create RFQBidAward(s) + RFQLineItemFulfillment(s)
          │
          ▼
   BidAwardedEvent → BidAwardedEventHandler (Contracts module)
          │
          ▼
   CreateContractCommand → Contract created (status PENDING_ESCROW)
          │
          ▼
   ContractCreatedEvent → ContractCreatedEventHandler (Finance module)
          │
          ▼
   Re-validate balance, lock escrow (5-attempt backoff: 1s/2s/4s/8s/16s)
          │
   ┌──────┴──────┐
   ▼             ▼
 Success      5 failures
   │             │
   ▼             ▼
 Contract →   Contract → ESCROW_LOCK_FAILED
 PENDING_VEHICLE_ASSIGNMENT   (manual admin/business retry required;
   │                           no automatic rollback, no automated
   ▼                           notification today)
 ContractEscrowLockedEvent
```

---

## 🔧 **IMPLEMENTATION STATUS (verified 2026-07-23)**

### **Backend**

- [x] RFQ creation has no wallet validation (confirmed absent)
- [x] Award endpoint validates wallet balance (`AwardBidCommandHandler`)
- [x] Partial award calculation implemented (`IWalletCalculationService`, BR-006–BR-009)
- [x] Award-time and escrow-lock-time balance checks both exist (two separate checks, not shared logic)
- [x] `BidAwardedEvent`/`ContractCreatedEvent` chain carries the escrow amount through to the Finance module
- [ ] **Automatic rollback of contract/award on escrow-lock failure — NOT implemented.** The contract is left in `ESCROW_LOCK_FAILED`; nothing automatically cancels the award or notifies either party. This is a real gap, not a documented design choice — flagged for engineering.
- [x] `GET /api/finance/escrow/{contractId}` and admin retry endpoint (`POST /api/finance/escrow/{contractId}/retry`) exist for manual recovery

### **Frontend (web)**

- [x] No wallet-balance check shown on the RFQ creation UI
- [x] Wallet balance display and partial-award dialog exist on the award page (`SplitAwardDialog.tsx`)
- [x] "Deposit funds" quick action exists on insufficient-balance error states
- [ ] Real-time/live-push wallet balance updates on the award screen — not confirmed; wallet views are query-based (TanStack Query), not SignalR-pushed, consistent with the rest of the wallet surface (see epic-08/epic-09)

### **Documentation**

- [x] This document and its companions (`05_BUSINESS_LOGIC_FLOWS.md`, `Business_Rules.md`, `MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md`) reconciled against code as of 2026-07-23

---

## 📝 **API REFERENCE (real routes)**

### **Award a bid (real endpoint)**

```http
POST /api/marketplace/bids/award
Authorization: Bearer {token}

Request:
{
  "awards": [
    { "bidId": "uuid", "lineItemId": "uuid", "quantityAwarded": 2 }
  ]
}
```

**Reality Check:** the original doc's `POST /api/v1/rfqs/{rfqId}/awards` and a standalone `POST /api/v1/awards/calculate-max-affordable` endpoint were never real routes — confirm exact paths against `Controllers/Marketplace/BidController.cs` before building against either. The one confirmed-real award endpoint is `POST /api/marketplace/bids/award` (`AwardBidCommand`), which returns the max-affordable-quantity guidance **inline in the error response** rather than via a separate pre-check endpoint.

**Response (insufficient funds, real shape approximated):**
```json
{
  "success": false,
  "error": {
    "code": "INSUFFICIENT_FUNDS",
    "message": "Insufficient wallet balance for award",
    "details": {
      "required": 1050000,
      "available": 50000,
      "maxAffordableQuantity": 0,
      "shortfall": 1000000
    }
  }
}
```

---

## ✅ **TESTING SCENARIOS (rule shape confirmed, exact ETB figures illustrative)**

### **Test Case 1: Sufficient Funds**
```
Given: Business has enough AvailableBalance
When: Awards N vehicles at unitPrice, duration ≤ 30 days
Then: Award succeeds; escrow locked = N × unitPrice × duration
```

### **Test Case 2: Insufficient Funds**
```
Given: Business AvailableBalance is less than the full escrow required
When: Attempts to award the full requested quantity
Then: Error shown with maxAffordableQuantity from IWalletCalculationService
```

### **Test Case 3: Partial Award**
```
Given: AvailableBalance covers only part of the requested quantity
When: Business awards only the affordable quantity
Then: Award succeeds for that quantity; remaining quantity stays biddable on a PARTIALLY_AWARDED RFQ
```

### **Test Case 4: Race Condition**
```
Given: Two concurrent award attempts could together exceed AvailableBalance
When: Both are submitted near-simultaneously
Then: Award-time check may pass for both, but the escrow-lock retry at contract-creation time
      re-validates balance — one may end up in ESCROW_LOCK_FAILED requiring manual retry
      (not an automatic rollback — see §4 Reality Check above)
```

### **Test Case 5: Deposit & Retry**
```
Given: Business has insufficient AvailableBalance
When: Deposits funds (bank transfer, admin-approved, or Chapa/Telebirr/CBE Birr instant top-up)
And: Retries the award or the manual escrow-retry endpoint
Then: Award/escrow-lock succeeds with the new balance
```

---

## 🎯 **USER EXPERIENCE (unchanged intent, confirmed still true)**

1. **Create RFQ** — no funds needed; fast, frictionless.
2. **Review Bids** — grouped by line item, blind (UI-level) until award.
3. **Award** — wallet balance checked; sufficient → proceeds, insufficient → partial-award/deposit/cancel options shown.
4. **Partial Award** — system suggests max affordable quantity; remaining quantity can be awarded later against the same `PARTIALLY_AWARDED` RFQ.
5. **Deposit** — quick action to top up, then retry.

---

## 📌 **SUMMARY**

1. ✅ **RFQ Creation:** No wallet balance required — confirmed live.
2. ⚠️ **Award:** Wallet balance REQUIRED — confirmed live, real error includes max-affordable guidance.
3. ✅ **Partial Awards:** Fully supported — confirmed live.
4. 🔒 **Race Protection:** Two separate real checks exist (award-time, escrow-lock-time) — but **no automatic rollback** on escrow-lock failure; a contract can be left stuck in `ESCROW_LOCK_FAILED` requiring manual admin/business intervention. This is the one meaningful correction to the original document's implied behavior.
5. 💡 **UX:** Partial-award and deposit suggestions are real, shipped UI.

**Escrow formula, corrected and final:** `escrowRequired = Σ (quantityAwarded × unitPrice × min(durationDays, 30))` — per line item, summed across the award request (BR-031A). This is the formula to use for any future documentation, estimation, or testing work on this flow.

---

**Document last verified against code:** 2026-07-23
**Status:** ✅ Core rule confirmed live · ⚠️ automatic-rollback gap flagged for engineering
