# ⚠️ CRITICAL BUSINESS RULE UPDATE

**Date:** November 26, 2025  
**Updated By:** CTO Review  
**Impact:** High - Affects RFQ, Award, and Finance flows

---

## 🔄 **CHANGE SUMMARY**

### **Previous (INCORRECT) Flow:**
```
RFQ Creation → Escrow Check ❌ → Publish → Bidding → Award → Escrow Lock
```

### **Correct (UPDATED) Flow:**
```
RFQ Creation → Publish → Bidding → Award → Escrow Check ✅ → Escrow Lock
```

---

## ✅ **NEW BUSINESS RULES**

### **1. RFQ Creation (NO Funds Required)**

**Rule:** Businesses can create and publish RFQs **without** having funds in their wallet.

**Rationale:**
- Encourages RFQ creation (no barrier to entry)
- Businesses can explore market prices before committing funds
- Providers can bid without business having deposited yet

**Implementation:**
```typescript
// RFQ Creation - NO wallet validation
async createRFQ(command: CreateRFQCommand) {
  // Validate RFQ details
  this.validateRFQDetails(command);
  
  // ❌ REMOVED: Wallet balance check
  // ✅ NO escrow validation at this stage
  
  // Create RFQ
  const rfq = await this.rfqRepository.create(command);
  
  return rfq;
}
```

---

### **2. Award (Funds REQUIRED)**

**Rule:** Businesses **MUST** have sufficient wallet balance to award bids.

**Escrow Calculation:**
```
escrow_required = quantity_awarded × unit_price × escrow_multiplier

Where:
- escrow_multiplier = 1.0 (100% for monthly/event contracts)
```

**Validation:**
```typescript
async awardBid(command: AwardBidCommand) {
  // 1. Calculate total escrow required
  const escrowRequired = this.calculateEscrowRequired(command.awards);
  
  // 2. Get business wallet
  const wallet = await this.walletService.getBusinessWallet(command.businessId);
  
  // 3. Calculate available balance
  const availableBalance = wallet.balance - wallet.lockedBalance;
  
  // 4. Validate sufficient funds
  if (availableBalance < escrowRequired) {
    throw new InsufficientFundsException({
      required: escrowRequired,
      available: availableBalance,
      maxAffordableQuantity: this.calculateMaxAffordable(availableBalance, command)
    });
  }
  
  // 5. Proceed with award
  const award = await this.awardRepository.create(command);
  
  // 6. Publish event (Finance module will lock escrow)
  await this.eventBus.publish(new BidAwardedEvent({
    ...award,
    escrowAmount: escrowRequired
  }));
  
  return award;
}
```

---

### **3. Partial Awards (Based on Available Funds)**

**Rule:** If business has insufficient funds for full award, they can:
1. **Award partially** (what they can afford)
2. **Deposit more funds** and retry
3. **Cancel** the award

**Example Scenario:**

```
RFQ Line Item: 10 EV Sedans @ ETB 3,500 each
Total Required: ETB 35,000

Business Wallet:
- Balance: ETB 50,000
- Locked: ETB 40,000 (other contracts)
- Available: ETB 10,000

Max Affordable: FLOOR(10,000 / 3,500) = 2 vehicles

OPTION 1: Partial Award
- Award: 2 vehicles
- Escrow: ETB 7,000
- Remaining: ETB 3,000
- Status: ✅ SUCCESS
- Note: Can award remaining 8 later

OPTION 2: Deposit & Full Award
- Deposit: ETB 30,000
- New Available: ETB 40,000
- Award: 10 vehicles
- Escrow: ETB 35,000
- Status: ✅ SUCCESS
```

**UI Implementation:**
```typescript
// Frontend - Award Confirmation
if (availableBalance < totalRequired) {
  showPartialAwardDialog({
    requested: 10,
    maxAffordable: 2,
    required: 35000,
    available: 10000,
    options: [
      {
        label: 'Award 2 vehicles (what you can afford)',
        action: () => this.awardPartial(2)
      },
      {
        label: 'Deposit ETB 30,000 and award all 10',
        action: () => this.redirectToWalletTopup(30000)
      },
      {
        label: 'Cancel award',
        action: () => this.cancelAward()
      }
    ]
  });
}
```

---

### **4. Race Condition Protection**

**Problem:** Multiple concurrent awards could exceed wallet balance

**Solution:** Double validation

```typescript
// Finance Module - Escrow Lock Handler
async handleBidAwardedEvent(event: BidAwardedEvent) {
  // Start transaction
  await this.db.transaction(async (trx) => {
    // 1. Lock wallet row (prevents concurrent access)
    const wallet = await this.walletRepository
      .findById(event.businessId)
      .forUpdate(); // Row-level lock
    
    // 2. Re-validate balance (race condition check)
    const availableBalance = wallet.balance - wallet.lockedBalance;
    
    if (availableBalance < event.escrowAmount) {
      // Insufficient funds - rollback everything
      await this.contractService.cancelContract(event.contractId);
      await this.awardService.cancelAward(event.awardId);
      
      throw new InsufficientFundsException(
        'Award failed: Wallet balance changed during processing'
      );
    }
    
    // 3. Lock escrow
    await this.lockEscrow({
      contractId: event.contractId,
      amount: event.escrowAmount,
      walletId: wallet.id
    });
    
    // 4. Update wallet
    wallet.lockedBalance += event.escrowAmount;
    await this.walletRepository.update(wallet);
    
    // 5. Commit transaction
    await trx.commit();
  });
}
```

---

## 📊 **UPDATED FLOW DIAGRAMS**

### **Complete Award to Escrow Flow**

```
┌─────────────────────────────────────────────────────────┐
│              BUSINESS AWARDS BID                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ Calculate Escrow      │
         │ Required              │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ Check Wallet Balance  │
         └───────────┬───────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
         ▼                       ▼
    Sufficient?              Insufficient?
         │                       │
         │                       ├─► Show Error
         │                       ├─► Suggest Partial Award
         │                       └─► Offer Deposit Option
         │
         ▼
┌─────────────────────┐
│ Create Award        │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ Publish Event       │
│ BidAwardedEvent     │
└─────────┬───────────┘
          │
          ├─────────────────────────────────────┐
          │                                     │
          ▼                                     ▼
┌─────────────────────┐              ┌─────────────────────┐
│ Contracts Module    │              │ Finance Module      │
│ Creates Contract    │              │ Locks Escrow        │
└─────────────────────┘              └─────────┬───────────┘
                                               │
                                               ▼
                                     ┌─────────────────────┐
                                     │ Re-validate Balance │
                                     │ (Race Protection)   │
                                     └─────────┬───────────┘
                                               │
                                   ┌───────────┴───────────┐
                                   │                       │
                                   ▼                       ▼
                              Still OK?                Failed?
                                   │                       │
                                   │                       ├─► Rollback Contract
                                   │                       ├─► Cancel Award
                                   │                       └─► Notify Business
                                   │
                                   ▼
                         ┌─────────────────────┐
                         │ Lock Escrow         │
                         │ Update Wallet       │
                         └─────────┬───────────┘
                                   │
                                   ▼
                         ┌─────────────────────┐
                         │ Publish             │
                         │ EscrowLockedEvent   │
                         └─────────────────────┘
```

---

## 🔧 **IMPLEMENTATION CHECKLIST**

### **Backend Changes**

- [x] ✅ Remove wallet validation from RFQ creation
- [x] ✅ Add wallet validation to award endpoint
- [x] ✅ Implement partial award calculation
- [x] ✅ Add race condition protection in escrow lock
- [x] ✅ Update BidAwardedEvent to include escrowAmount
- [ ] ⏳ Add API endpoint: `GET /awards/calculate-max-affordable`
- [ ] ⏳ Add API endpoint: `POST /awards/partial`
- [ ] ⏳ Update error responses with max affordable quantity

### **Frontend Changes**

- [ ] ⏳ Remove wallet balance check from RFQ creation UI
- [ ] ⏳ Add wallet balance display on award page
- [ ] ⏳ Implement partial award dialog
- [ ] ⏳ Add "Deposit Funds" quick action on insufficient balance
- [ ] ⏳ Show real-time wallet balance updates
- [ ] ⏳ Add award confirmation with escrow amount preview

### **Database Changes**

- [x] ✅ No schema changes required
- [x] ✅ Existing tables support this flow

### **Documentation Updates**

- [x] ✅ Updated 05_BUSINESS_LOGIC_FLOWS.md
- [x] ✅ Added partial award examples
- [x] ✅ Updated business rules
- [ ] ⏳ Update API specifications
- [ ] ⏳ Update frontend architecture guide

---

## 📝 **API CHANGES**

### **New Endpoint: Calculate Max Affordable**

```http
POST /api/v1/awards/calculate-max-affordable
Authorization: Bearer {token}

Request:
{
  "awards": [
    {
      "lineItemId": "uuid",
      "providerId": "uuid",
      "quantity": 10,
      "unitPrice": 3500
    }
  ]
}

Response:
{
  "success": true,
  "data": {
    "totalRequired": 35000,
    "availableBalance": 10000,
    "maxAffordableQuantity": 2,
    "partialAwardAmount": 7000,
    "shortfall": 25000,
    "canAfford": false
  }
}
```

### **Updated Endpoint: Award Bid**

```http
POST /api/v1/rfqs/{rfqId}/awards
Authorization: Bearer {token}

Request:
{
  "awards": [
    {
      "lineItemId": "uuid",
      "bidId": "uuid",
      "quantityAwarded": 2  // Partial award
    }
  ]
}

Response (Success):
{
  "success": true,
  "data": {
    "awards": [...],
    "escrowLocked": 7000,
    "remainingBalance": 3000
  }
}

Response (Insufficient Funds):
{
  "success": false,
  "error": {
    "code": "INSUFFICIENT_FUNDS",
    "message": "Insufficient wallet balance for award",
    "details": {
      "required": 35000,
      "available": 10000,
      "maxAffordableQuantity": 2,
      "shortfall": 25000,
      "suggestions": [
        "Award 2 vehicles with current balance",
        "Deposit ETB 25,000 to award all 10 vehicles"
      ]
    }
  }
}
```

---

## ✅ **TESTING SCENARIOS**

### **Test Case 1: Sufficient Funds**
```
Given: Business has ETB 50,000 available
When: Awards 5 vehicles @ ETB 3,500 each
Then: Award succeeds, escrow locked ETB 17,500
```

### **Test Case 2: Insufficient Funds**
```
Given: Business has ETB 10,000 available
When: Attempts to award 10 vehicles @ ETB 3,500 each
Then: Error shown with max affordable = 2 vehicles
```

### **Test Case 3: Partial Award**
```
Given: Business has ETB 10,000 available
When: Awards 2 vehicles @ ETB 3,500 each (partial)
Then: Award succeeds, escrow locked ETB 7,000
```

### **Test Case 4: Race Condition**
```
Given: Business has ETB 20,000 available
When: Submits 2 concurrent awards of ETB 15,000 each
Then: First succeeds, second fails with insufficient funds
```

### **Test Case 5: Deposit & Retry**
```
Given: Business has ETB 10,000 available
When: Deposits ETB 30,000
And: Retries award of 10 vehicles
Then: Award succeeds with new balance
```

---

## 🎯 **USER EXPERIENCE**

### **Business User Journey**

1. **Create RFQ** (No funds needed)
   - ✅ Fast, frictionless RFQ creation
   - ✅ Can explore market without commitment

2. **Review Bids** (See prices)
   - ✅ Compare provider offers
   - ✅ Make informed decisions

3. **Award** (Funds required)
   - ⚠️ System checks wallet balance
   - ✅ If sufficient: Award proceeds
   - ⚠️ If insufficient: 3 clear options shown

4. **Partial Award** (Smart suggestion)
   - ✅ System calculates max affordable
   - ✅ Business can award what they can afford
   - ✅ Can award remaining vehicles later

5. **Deposit** (Quick action)
   - ✅ One-click redirect to wallet
   - ✅ After deposit, return to award
   - ✅ Seamless experience

---

## 📌 **SUMMARY**

**Key Takeaways:**

1. ✅ **RFQ Creation:** No wallet balance required
2. ⚠️ **Award:** Wallet balance REQUIRED
3. ✅ **Partial Awards:** Fully supported
4. 🔒 **Race Protection:** Double validation
5. 💡 **UX:** Smart suggestions for insufficient funds

**This change improves:**
- User experience (lower barrier to RFQ creation)
- Flexibility (partial awards)
- Financial safety (escrow locked only when funds available)

---

**Document Updated:** November 26, 2025  
**Status:** ✅ APPROVED FOR IMPLEMENTATION
