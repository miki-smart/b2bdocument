# Settlement Processing Enhancements - Addendum

**Document Version**: 1.0  
**Date**: February 19, 2026  
**Status**: Implemented  
**Related Documents**: 
- MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md
- MVP_AUTHORITATIVE_BUSINESS_RULES.md (BR-031, BR-031A)
- Finance_Module.md

---

## Purpose

This document describes **implementation enhancements** to the settlement processing system that extend beyond the original MVP specifications. These enhancements provide greater transparency, auditability, and compliance with accounting standards.

---

## Summary of Changes

### What Was Already Specified

✅ **Vehicle-Level Earnings Calculation (BR-031A)**
- Calculate earnings per vehicle based on actual delivery dates
- Formula: `VehicleEarnings = UnitPricePerDay × ActiveDaysInWindow`
- Handle partial delivery, late delivery, and early return

✅ **Double-Entry Bookkeeping Concept**
- DEBIT escrow wallet (gross amount)
- CREDIT provider wallet (net amount)
- CREDIT platform commission wallet (commission + tax)

✅ **Transaction Reference**
- Create `wallet_ledger_transaction` for settlements
- Store transaction reference

### What Was Enhanced

🆕 **Per-Vehicle Settlement Records**
- Added `settlement_payout_line_items` table
- Store individual vehicle earnings within each settlement
- Track which vehicle earned what amount

🆕 **Complete Transaction Linking**
- Populate `wallet_transaction_id` in settlement payouts
- Link every settlement to its wallet transaction
- Enable complete money flow traceability

🆕 **Enhanced Double-Entry Implementation**
- Implement actual double-entry with all three ledger entries
- Automatic wallet creation for platform accounts
- Balance verification and audit trail

---

## Database Schema Additions

### New Table: settlement_payout_line_items

```sql
CREATE TABLE wallet.settlement_payout_line_items (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    settlement_payout_id    uuid NOT NULL REFERENCES wallet.settlement_payouts(id),
    contract_id             uuid NOT NULL,
    contract_number         varchar(50) NOT NULL,
    vehicle_id              uuid,
    vehicle_plate_number    varchar(50),
    gross_amount            numeric(18,2) NOT NULL,
    commission_amount       numeric(18,2) NOT NULL,
    commission_rate         numeric(5,4) NOT NULL,
    net_amount              numeric(18,2) NOT NULL,
    period_start            timestamptz NOT NULL,
    period_end              timestamptz NOT NULL,
    days_in_period          int NOT NULL,
    is_deleted              boolean NOT NULL DEFAULT false,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now()
);
```

**Purpose**: Store detailed breakdown of settlement earnings per vehicle.

**Key Fields**:
- `vehicle_id` + `vehicle_plate_number`: Identifies the specific vehicle
- `gross_amount`, `commission_amount`, `net_amount`: Financial breakdown per vehicle
- `days_in_period`: Number of active days for this vehicle in settlement window
- `contract_id` + `contract_number`: Links to the contract

### Enhanced Table: settlement_payouts

**Added Column**:
```sql
ALTER TABLE wallet.settlement_payouts 
ADD COLUMN wallet_transaction_id uuid 
REFERENCES wallet.wallet_ledger_transaction(id);
```

**Purpose**: Link settlement payout to the wallet transaction that executed the payment.

---

## Implementation Details

### 1. Settlement Generation Process

#### Step 1: Calculate Earnings Per Vehicle

```typescript
// For each vehicle assignment in contract
for (const assignment of contract.vehicleAssignments) {
    if (!assignment.deliveredAt) continue;
    
    const vehicleStart = assignment.deliveredAt;
    const vehicleEnd = assignment.releasedAt ?? contract.endDate;
    
    // Calculate overlap with settlement window
    const activeDays = calculateActiveDaysInWindow(
        vehicleStart, vehicleEnd, 
        settlementStart, settlementEnd
    );
    
    if (activeDays > 0) {
        const vehicleEarnings = dailyRate * activeDays;
        
        // Store vehicle details for line item creation
        vehicleDetails.push({
            contractId: contract.id,
            contractNumber: contract.contractNumber,
            vehicleId: assignment.vehicleId,
            vehiclePlateNumber: assignment.vehicle.licensePlate,
            earnings: vehicleEarnings,
            days: Math.ceil(activeDays)
        });
    }
}
```

#### Step 2: Create Settlement Payout

```typescript
const payout = SettlementPayout.Create(
    cycleId,
    providerId,
    providerWalletId,
    grossAmount,      // Sum of all vehicle earnings
    commissionAmount, // Calculated from provider tier
    taxAmount
);
```

#### Step 3: Create Double-Entry Transaction

```typescript
// Create transaction header
const transaction = WalletLedgerTransaction.Create(
    "SET-20260219-0001",  // Unique reference
    "SETTLEMENT",
    "Settlement payout for cycle CYC-2026-W04",
    cycleId
);

// Create three ledger entries (double-entry)
// 1. DEBIT escrow (release funds)
const debitEntry = WalletLedgerEntry.Create(
    transaction.id,
    escrowWallet.id,
    "DEBIT",
    grossAmount  // Total gross from all vehicles
);

// 2. CREDIT provider (pay provider)
const creditEntry = WalletLedgerEntry.Create(
    transaction.id,
    providerWallet.id,
    "CREDIT",
    netAmount  // After commission deduction
);

// 3. CREDIT platform (collect commission)
const commissionEntry = WalletLedgerEntry.Create(
    transaction.id,
    platformCommissionWallet.id,
    "CREDIT",
    commissionAmount + taxAmount
);

// Update wallet balances
escrowWallet.Debit(grossAmount);
providerWallet.Credit(netAmount);
platformCommissionWallet.Credit(commissionAmount + taxAmount);
```

#### Step 4: Link Transaction to Payout

```typescript
payout.SetWalletTransaction(transaction.id);
```

#### Step 5: Create Line Items for Each Vehicle

```typescript
for (const detail of vehicleDetails) {
    const lineItem = SettlementPayoutLineItem.Create(
        payout.id,
        detail.contractId,
        detail.contractNumber,
        detail.vehicleId,
        detail.vehiclePlateNumber,
        detail.earnings,                    // Gross for this vehicle
        detail.earnings * commissionRate,   // Commission for this vehicle
        commissionRate,
        settlementStart,
        settlementEnd,
        detail.days
    );
    
    await repository.AddPayoutLineItemAsync(lineItem);
}
```

---

## Example Scenario

### Contract Details
- **Contract**: CNT-2026-001
- **Line Item**: 5 Minibuses @ 2,500 ETB/day
- **Settlement Period**: Jan 1 - Jan 30 (30 days)

### Vehicle Deliveries
- **Vehicle A (ABC-123)**: Delivered Jan 1 → 30 days active
- **Vehicle B (ABC-124)**: Delivered Jan 1 → 30 days active
- **Vehicle C (ABC-125)**: Delivered Jan 2 → 29 days active
- **Vehicle D (ABC-126)**: Delivered Jan 3 → 28 days active
- **Vehicle E (ABC-127)**: Delivered Jan 4 → 27 days active

### Settlement Calculation

#### Vehicle Earnings
```
Vehicle A: 2,500 × 30 = 75,000 ETB
Vehicle B: 2,500 × 30 = 75,000 ETB
Vehicle C: 2,500 × 29 = 72,500 ETB
Vehicle D: 2,500 × 28 = 70,000 ETB
Vehicle E: 2,500 × 27 = 67,500 ETB
─────────────────────────────────
Total Gross:           360,000 ETB
Commission (10%):      -36,000 ETB
Net to Provider:       324,000 ETB
```

#### Database Records Created

**1. Settlement Payout**
```sql
INSERT INTO wallet.settlement_payouts (
    settlement_cycle_id,
    provider_id,
    wallet_transaction_id,
    total_amount,
    commission_deducted,
    net_payout_amount
) VALUES (
    'cycle-uuid',
    'provider-uuid',
    'txn-uuid',
    360000.00,
    36000.00,
    324000.00
);
```

**2. Wallet Transaction**
```sql
INSERT INTO wallet.wallet_ledger_transaction (
    transaction_reference,
    transaction_type,
    description,
    related_entity_id
) VALUES (
    'SET-20260219-0001',
    'SETTLEMENT',
    'Settlement payout for cycle CYC-2026-W04',
    'cycle-uuid'
);
```

**3. Ledger Entries (3 records)**
```sql
-- DEBIT escrow
INSERT INTO wallet.wallet_ledger_entry (
    transaction_id, wallet_account_id, direction, amount
) VALUES ('txn-uuid', 'escrow-wallet-uuid', 'DEBIT', 360000.00);

-- CREDIT provider
INSERT INTO wallet.wallet_ledger_entry (
    transaction_id, wallet_account_id, direction, amount
) VALUES ('txn-uuid', 'provider-wallet-uuid', 'CREDIT', 324000.00);

-- CREDIT platform
INSERT INTO wallet.wallet_ledger_entry (
    transaction_id, wallet_account_id, direction, amount
) VALUES ('txn-uuid', 'platform-commission-uuid', 'CREDIT', 36000.00);
```

**4. Payout Line Items (5 records)**
```sql
-- Vehicle A
INSERT INTO wallet.settlement_payout_line_items (
    settlement_payout_id, contract_id, vehicle_id, vehicle_plate_number,
    gross_amount, commission_amount, net_amount, days_in_period
) VALUES (
    'payout-uuid', 'contract-uuid', 'vehicle-a-uuid', 'ABC-123',
    75000.00, 7500.00, 67500.00, 30
);

-- Vehicle B
INSERT ... VALUES (..., 'ABC-124', 75000.00, 7500.00, 67500.00, 30);

-- Vehicle C (1 day less)
INSERT ... VALUES (..., 'ABC-125', 72500.00, 7250.00, 65250.00, 29);

-- Vehicle D (2 days less)
INSERT ... VALUES (..., 'ABC-126', 70000.00, 7000.00, 63000.00, 28);

-- Vehicle E (3 days less)
INSERT ... VALUES (..., 'ABC-127', 67500.00, 6750.00, 60750.00, 27);
```

---

## Benefits

### 1. Complete Transparency
- Providers can see exactly which vehicle earned what amount
- Each vehicle's contribution is clearly tracked
- Different delivery dates properly reflected in earnings

### 2. Audit Trail
- Every settlement linked to wallet transaction
- Double-entry bookkeeping maintained
- Can trace money flow from escrow → provider + platform

### 3. Dispute Resolution
- Vehicle-level breakdown available for verification
- Can cross-reference with delivery dates and contract terms
- Clear evidence for any earnings disputes

### 4. Accounting Compliance
- Proper double-entry bookkeeping
- Debits always equal credits
- Complete general ledger records

### 5. Reporting & Analytics
- Can analyze earnings by vehicle
- Can track vehicle utilization and profitability
- Can generate detailed financial reports

---

## Queries

### Get Settlement with Vehicle Breakdown

```sql
SELECT 
    sc.cycle_reference,
    sp.provider_id,
    sp.total_amount as gross,
    sp.commission_deducted,
    sp.net_payout_amount as net,
    wlt.transaction_reference,
    wlt.created_at as payment_date,
    spli.contract_number,
    spli.vehicle_plate_number,
    spli.gross_amount as vehicle_gross,
    spli.commission_amount as vehicle_commission,
    spli.net_amount as vehicle_net,
    spli.days_in_period
FROM wallet.settlement_cycles sc
JOIN wallet.settlement_payouts sp ON sp.settlement_cycle_id = sc.id
JOIN wallet.wallet_ledger_transaction wlt ON wlt.id = sp.wallet_transaction_id
JOIN wallet.settlement_payout_line_items spli ON spli.settlement_payout_id = sp.id
WHERE sp.provider_id = :providerId
ORDER BY wlt.created_at DESC, spli.vehicle_plate_number;
```

### Verify Double-Entry Balance

```sql
SELECT 
    wlt.transaction_reference,
    SUM(CASE WHEN wle.direction = 'DEBIT' THEN wle.amount ELSE 0 END) as total_debits,
    SUM(CASE WHEN wle.direction = 'CREDIT' THEN wle.amount ELSE 0 END) as total_credits,
    SUM(CASE WHEN wle.direction = 'DEBIT' THEN wle.amount ELSE 0 END) - 
    SUM(CASE WHEN wle.direction = 'CREDIT' THEN wle.amount ELSE 0 END) as balance
FROM wallet.wallet_ledger_transaction wlt
JOIN wallet.wallet_ledger_entry wle ON wle.transaction_id = wlt.id
WHERE wlt.transaction_type = 'SETTLEMENT'
GROUP BY wlt.transaction_reference
HAVING SUM(CASE WHEN wle.direction = 'DEBIT' THEN wle.amount ELSE 0 END) != 
       SUM(CASE WHEN wle.direction = 'CREDIT' THEN wle.amount ELSE 0 END);
```

Should return 0 rows (all transactions balanced).

### Trace Money Flow

```sql
-- Trace funds from escrow lock to settlement release
WITH escrow_locks AS (
    SELECT 
        el.contract_id,
        el.amount as locked_amount,
        wlt.transaction_reference as lock_ref,
        wlt.created_at as locked_at
    FROM wallet.escrow_lock el
    JOIN wallet.wallet_ledger_transaction wlt ON wlt.related_entity_id = el.contract_id
    WHERE wlt.transaction_type = 'ESCROW_LOCK'
),
settlements AS (
    SELECT 
        spli.contract_id,
        SUM(spli.gross_amount) as settled_amount,
        wlt.transaction_reference as settlement_ref,
        wlt.created_at as settled_at
    FROM wallet.settlement_payout_line_items spli
    JOIN wallet.settlement_payouts sp ON sp.id = spli.settlement_payout_id
    JOIN wallet.wallet_ledger_transaction wlt ON wlt.id = sp.wallet_transaction_id
    GROUP BY spli.contract_id, wlt.transaction_reference, wlt.created_at
)
SELECT 
    el.contract_id,
    el.locked_amount,
    el.lock_ref,
    el.locked_at,
    s.settled_amount,
    s.settlement_ref,
    s.settled_at,
    el.locked_amount - COALESCE(s.settled_amount, 0) as remaining_in_escrow
FROM escrow_locks el
LEFT JOIN settlements s ON s.contract_id = el.contract_id
ORDER BY el.locked_at DESC;
```

---

## Migration Steps

1. **Run SQL Migration**
   ```bash
   psql -U postgres -d marketplace -f \
     backend/src/Marketplace.API/Modules/Finance/Infrastructure/Migrations/20260219_AddSettlementPayoutLineItems.sql
   ```

2. **Rebuild Application**
   ```bash
   cd backend/src/Marketplace.API
   dotnet build
   ```

3. **Verify Migration**
   ```sql
   -- Check table exists
   SELECT table_name FROM information_schema.tables 
   WHERE table_schema = 'wallet' 
   AND table_name = 'settlement_payout_line_items';
   
   -- Check column exists
   SELECT column_name FROM information_schema.columns
   WHERE table_schema = 'wallet' 
   AND table_name = 'settlement_payouts'
   AND column_name = 'wallet_transaction_id';
   ```

---

## Related Files

### Backend Implementation
- `SettlementPayoutLineItem.cs` - Entity for vehicle earnings
- `SettlementPayout.cs` - Enhanced with transaction linking
- `GenerateSettlementCommand.cs` - Settlement generation logic
- `ISettlementCycleRepository.cs` - Repository interface
- `SettlementCycleRepository.cs` - Repository implementation

### Database
- `20260219_AddSettlementPayoutLineItems.sql` - Migration script

### Documentation
- `SETTLEMENT_TRANSACTION_TRACKING_IMPLEMENTATION.md` - Detailed implementation guide

---

## Compliance with Business Rules

### BR-031: Settlement Amount Formula
✅ **Compliant** - Formula correctly applied:
- Gross Amount = Sum of vehicle earnings
- Commission = Gross × Commission Rate
- Net = Gross - Commission - Tax

### BR-031A: Vehicle-Level Earnings
✅ **Enhanced** - Not only calculates per vehicle, but also **stores** per vehicle:
- Each vehicle's earnings calculated from `[DeliveredAt, ReturnedAt)`
- Handles partial delivery, late delivery, early return
- Stores individual vehicle contributions for transparency

### Double-Entry Bookkeeping
✅ **Fully Implemented**:
- Every settlement creates balanced ledger entries
- Debits = Credits (verified programmatically)
- Complete audit trail maintained

---

## Conclusion

These enhancements provide a robust, transparent, and auditable settlement system that goes beyond the original specifications while maintaining full compliance with documented business rules. The per-vehicle tracking and complete transaction linking enable better transparency, dispute resolution, and financial reporting.



