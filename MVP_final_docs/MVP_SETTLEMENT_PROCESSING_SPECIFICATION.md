# Movello MVP - Settlement Processing Specification
## Complete Settlement Triggers, Calculations & Workflows - Version 1.0

**Document Status:** AUTHORITATIVE  
**Date:** December 22, 2025  
**Related Documents:** 
- MVP_AUTHORITATIVE_BUSINESS_RULES.md
- MVP_EVENT_CATALOG_AND_HANDLERS.md
- MVP_MODULE_INTEGRATION_SPECIFICATION.md
- MVP_CONTRACT_STATE_MACHINE.md  
**Review Status:** ✅ Approved by Business Owner

---

## Document Purpose

This document defines the complete settlement processing system for the Movello MVP platform, including:
- All settlement trigger events and timing rules
- Settlement calculation formulas (pro-rata, commissions, taxes)
- Approval workflows and thresholds
- Payment processing flows
- Grace period settlements
- Debt tracking and recovery
- Settlement reconciliation

---

## TABLE OF CONTENTS

1. [Settlement Overview](#1-settlement-overview)
2. [Settlement Types & Triggers](#2-settlement-types--triggers)
3. [Settlement Calculations](#3-settlement-calculations)
4. [Monthly Settlement Processing](#4-monthly-settlement-processing)
5. [Final Settlement Processing](#5-final-settlement-processing)
6. [Early Return Settlement](#6-early-return-settlement)
7. [Grace Period Settlement](#7-grace-period-settlement)
8. [Approval Workflows](#8-approval-workflows)
9. [Commission & Tax Processing](#9-commission--tax-processing)
10. [Debt Tracking & Recovery](#10-debt-tracking--recovery)
11. [Settlement Reconciliation](#11-settlement-reconciliation)

---

## 1. SETTLEMENT OVERVIEW

### 1.1 Settlement Categories

**By Timing:**
- **Monthly Settlement:** For contracts ≥30 days (processed at month-end)
- **Final Settlement:** Contract completion or early termination
- **Grace Period Settlement:** Additional payment when grace period used
- **Immediate Settlement:** For contracts <30 days (processed at completion)

**By Trigger:**
- **Automatic:** System-triggered based on time/events
- **Manual:** Admin-initiated for special cases
- **Event-Driven:** Triggered by specific contract events

---

### 1.2 Settlement Timing Rules (BR-033)

```typescript
function determineSettlementTiming(contract: Contract): SettlementRule {
  const durationDays = contract.totalDays;
  
  if (durationDays < 30) {
    return {
      type: 'IMMEDIATE',
      trigger: 'CONTRACT_COMPLETED',
      timing: 'At contract completion',
      frequency: 'ONCE'
    };
  } else {
    return {
      type: 'DURATION_BASED',
      monthlySettlements: true,
      trigger: 'MONTH_END',
      timing: 'Last day of each month',
      finalSettlement: true,
      finalTrigger: 'CONTRACT_COMPLETED'
    };
  }
}
```

**Examples:**
```
Contract Duration: 15 days
  → Settlement: Single payment at completion
  
Contract Duration: 45 days
  → Month 1 (Day 30): Monthly settlement for 30 days
  → Contract end (Day 45): Final settlement for 15 days
  
Contract Duration: 90 days
  → Month 1 (Day 30): Monthly settlement for 30 days
  → Month 2 (Day 60): Monthly settlement for 30 days
  → Month 3 (Day 90): Final settlement for 30 days
```

---

### 1.3 Settlement Flow Overview

```
┌─────────────────────────────────────────────────────────┐
│                  SETTLEMENT PROCESS                      │
└─────────────────────────────────────────────────────────┘

1. TRIGGER EVENT
   ↓
2. CALCULATE AMOUNTS
   - Gross amount (days × daily rate)
   - Platform commission
   - Tax withholding
   - Net to provider
   ↓
3. APPROVAL CHECK
   - Auto-approve if < threshold
   - Manual approval if ≥ threshold
   ↓
4. PROCESS PAYMENT
   - Create wallet transaction
   - Transfer to provider
   - Record settlement
   ↓
5. NOTIFICATIONS
   - Provider: Payment received
   - Business: Settlement processed
   - Admin: Settlement report
   ↓
6. RECONCILIATION
   - Update contract records
   - Update provider balance
   - Log audit trail
```

---

## 2. SETTLEMENT TYPES & TRIGGERS

### 2.1 Monthly Settlement

**Trigger Event:** `MonthEndSettlementEvent`

**When Triggered:**
- Contracts with duration ≥30 days
- Processed on the last day of each month
- For all ACTIVE contracts that span month-end

**Cron Job:**
```typescript
@Cron('0 0 * * *') // Daily at midnight
async function checkMonthlySettlements() {
  const today = new Date();
  const isLastDayOfMonth = isLastDay(today);
  
  if (!isLastDayOfMonth) return;
  
  // Get all active contracts that need monthly settlement
  const contracts = await this.contractRepository.find({
    status: 'ACTIVE',
    durationDays: GreaterThanOrEqual(30),
    // Either: Never settled OR last settlement was last month
    OR: [
      { lastSettlementDate: IsNull() },
      { lastSettlementDate: LessThan(startOfMonth(today)) }
    ]
  });
  
  for (const contract of contracts) {
    await this.processMonthlySettlement(contract);
  }
}
```

**Calculation:**
```typescript
async function processMonthlySettlement(contract: Contract) {
  const today = new Date();
  const settlementPeriodStart = contract.lastSettlementDate 
    ? addDays(contract.lastSettlementDate, 1) 
    : contract.actualStartDate;
  const settlementPeriodEnd = today;
  
  const daysInPeriod = differenceInDays(settlementPeriodEnd, settlementPeriodStart);
  const dailyRate = contract.totalAmount / contract.totalDays;
  const grossAmount = dailyRate * daysInPeriod;
  
  // Calculate deductions
  const commission = await calculateCommission(contract, grossAmount);
  const tax = await calculateTax(grossAmount);
  const netAmount = grossAmount - commission - tax;
  
  await this.createSettlement({
    contractId: contract.id,
    type: 'MONTHLY',
    periodStart: settlementPeriodStart,
    periodEnd: settlementPeriodEnd,
    daysInPeriod,
    grossAmount,
    commission,
    tax,
    netAmount,
    status: 'PENDING_APPROVAL'
  });
}
```

---

### 2.2 Final Settlement

**Trigger Event:** `ContractCompletedEvent`

**When Triggered:**
- Contract reaches end date and vehicles returned
- All contracts (short and long-term) get final settlement

**For Short-Term Contracts (<30 days):**
```typescript
// Single settlement for entire duration
const totalDays = contract.totalDays;
const grossAmount = contract.totalAmount;
const netAmount = grossAmount - commission - tax;
```

**For Long-Term Contracts (≥30 days):**
```typescript
// Final settlement for remaining period after last monthly settlement
const remainingDays = differenceInDays(
  contract.actualEndDate,
  contract.lastSettlementDate
);
const dailyRate = contract.totalAmount / contract.totalDays;
const grossAmount = dailyRate * remainingDays;
const netAmount = grossAmount - commission - tax;
```

**Example:**
```
90-day contract completed:
- Month 1 settlement: 30 days × 1,000 = 30,000 ETB (already paid)
- Month 2 settlement: 30 days × 1,000 = 30,000 ETB (already paid)
- Final settlement: 30 days × 1,000 = 30,000 ETB (paid at completion)
- Total paid to provider: 90,000 ETB
```

---

### 2.3 Early Return Settlement

**Trigger Event:** `EarlyReturnApprovedEvent`

**When Triggered:**
- Both business and provider approve early return
- Vehicles returned before contract end date

**Calculation Logic:**
```typescript
async function processEarlyReturnSettlement(contract: Contract, earlyReturnDate: Date) {
  // 1. Calculate days used
  const daysUsed = differenceInDays(earlyReturnDate, contract.actualStartDate);
  const totalDays = contract.totalDays;
  const remainingDays = totalDays - daysUsed;
  
  // 2. Calculate amounts
  const dailyRate = contract.totalAmount / totalDays;
  const amountForDaysUsed = dailyRate * daysUsed;
  const remainingAmount = dailyRate * remainingDays;
  
  // 3. Calculate penalty based on notice period
  const noticePeriodDays = differenceInDays(
    earlyReturnDate, 
    contract.earlyReturnRequestedDate
  );
  const penaltyRate = getPenaltyRate(noticePeriodDays); // See BR-019
  const penaltyAmount = remainingAmount * penaltyRate;
  
  // 4. Calculate payments
  const refundToBusiness = remainingAmount - penaltyAmount;
  const additionalToProvider = penaltyAmount;
  
  // 5. Calculate already paid amount
  const monthlySettlementsPaid = contract.totalSettlementsPaid;
  const alreadyPaidAmount = monthlySettlementsPaid * 30000; // assuming 30k per month
  
  // 6. Calculate net settlement
  const totalProviderAmount = amountForDaysUsed + additionalToProvider;
  const providerFinalPayment = totalProviderAmount - alreadyPaidAmount;
  
  return {
    daysUsed,
    remainingDays,
    noticePeriodDays,
    penaltyRate,
    grossAmountUsed: amountForDaysUsed,
    remainingAmount,
    penaltyAmount,
    refundToBusiness,
    alreadyPaidToProvider: alreadyPaidAmount,
    additionalToProvider: providerFinalPayment,
    totalProviderReceives: totalProviderAmount
  };
}

function getPenaltyRate(noticePeriodDays: number): number {
  if (noticePeriodDays >= 7) return 0.00;      // 0% penalty
  if (noticePeriodDays >= 3) return 0.02;      // 2% penalty
  return 0.15;                                  // 15% penalty
}
```

**Example Scenario:**
```
Contract: 90 days, 90,000 ETB (1,000 ETB/day)
Early return requested: Day 50 (7 days notice)
Early return date: Day 57

Calculation:
- Days used: 57 days
- Remaining days: 33 days
- Already paid (Month 1): 30,000 ETB
- Already paid (prorated Month 2): 0 ETB (not yet month-end)

Settlement:
- Amount for days used: 57,000 ETB
- Remaining amount: 33,000 ETB
- Penalty (7 days notice): 0%
- Penalty amount: 0 ETB
- Refund to business: 33,000 ETB
- Provider total: 57,000 ETB
- Provider already received: 30,000 ETB
- Provider final payment: 27,000 ETB
```

---

### 2.4 Grace Period Settlement

**Trigger Event:** Business deposits during grace period

**When Triggered:**
- Provider granted grace period
- Business makes payment within grace period
- Contract reactivated

**Calculation:**
```typescript
async function processGracePeriodSettlement(
  contract: Contract,
  gracePeriodDays: number
) {
  const dailyRate = contract.totalAmount / contract.totalDays;
  
  // 1. Grace period charges
  const gracePeriodAmount = dailyRate * gracePeriodDays;
  
  // 2. Late payment fee (5%)
  const lateFeeRate = 0.05;
  const lateFee = gracePeriodAmount * lateFeeRate;
  
  // 3. Next month escrow
  const nextMonthEscrow = dailyRate * 30;
  
  // 4. Total business must pay
  const totalDue = gracePeriodAmount + lateFee + nextMonthEscrow;
  
  // 5. Provider receives immediately
  const providerPayment = gracePeriodAmount + lateFee;
  
  // 6. Platform commission and tax
  const commission = await calculateCommission(contract, gracePeriodAmount);
  const tax = await calculateTax(gracePeriodAmount);
  const providerNet = gracePeriodAmount - commission - tax + lateFee;
  
  return {
    gracePeriodDays,
    gracePeriodAmount,
    lateFee,
    nextMonthEscrow,
    totalDue,
    providerGross: providerPayment,
    commission,
    tax,
    providerNet,
    platformRevenue: commission
  };
}
```

**Example:**
```
Contract: 1,000 ETB/day
Grace period: 2 days
Provider granted grace period

Business Payment:
- Grace period (2 days): 2,000 ETB
- Late fee (5%): 100 ETB
- Next month escrow (30 days): 30,000 ETB
- Total business pays: 32,100 ETB

Provider Receives:
- Grace period amount: 2,000 ETB
- Late fee: 100 ETB (goes to provider as compensation)
- Commission (10%): -200 ETB
- Tax (2%): -40 ETB
- Net to provider: 1,860 ETB (paid immediately)

Next month escrow (30,000 ETB) held in escrow for Month 2
```

---

### 2.5 Termination Settlement (Payment Default)

**Trigger Event:** Contract terminated due to payment default

**Scenarios:**

#### Scenario A: Provider Denied Grace Period
```typescript
// Contract terminated immediately at payment default
// No grace period, clean termination

Settlement:
- Provider paid for all completed periods (from escrow)
- No additional amounts owed
- No debt created
- Contract terminated cleanly
```

#### Scenario B: Grace Period Expired Without Payment
```typescript
async function processDefaultTerminationSettlement(
  contract: Contract,
  gracePeriodDays: number
) {
  const dailyRate = contract.totalAmount / contract.totalDays;
  
  // 1. Grace period charges (unpaid)
  const gracePeriodAmount = dailyRate * gracePeriodDays;
  const lateFee = gracePeriodAmount * 0.05;
  const totalOwed = gracePeriodAmount + lateFee;
  
  // 2. Create debt record
  const debt = {
    contractId: contract.id,
    businessId: contract.businessId,
    providerId: contract.providerId,
    amount: totalOwed,
    breakdown: {
      gracePeriodDays,
      gracePeriodAmount,
      lateFee
    },
    status: 'OUTSTANDING',
    createdAt: new Date(),
    dueDate: addDays(new Date(), 30)
  };
  
  // 3. Business account suspended
  await this.suspendBusinessAccount(contract.businessId, {
    reason: 'UNPAID_DEBT',
    debtAmount: totalOwed,
    contractId: contract.id
  });
  
  return {
    settlementType: 'TERMINATION_WITH_DEBT',
    providerPaidFromEscrow: contract.totalSettlementsPaid * 30000,
    debtCreated: totalOwed,
    businessAccountStatus: 'SUSPENDED',
    providerAction: 'COLLECT_VEHICLES'
  };
}
```

---

## 3. SETTLEMENT CALCULATIONS

### 3.1 Base Calculation Formula

```typescript
interface SettlementCalculation {
  // Period details
  periodStart: Date;
  periodEnd: Date;
  daysInPeriod: number;
  
  // Amounts
  dailyRate: number;
  grossAmount: number;
  
  // Deductions
  platformCommission: number;
  taxWithholding: number;
  
  // Net to provider
  netAmount: number;
  
  // Additional
  lateFee?: number;
  penalty?: number;
  refund?: number;
}

function calculateSettlement(
  contract: Contract,
  periodStart: Date,
  periodEnd: Date,
  additionalCharges?: AdditionalCharges
): SettlementCalculation {
  
  // 1. Calculate period
  const daysInPeriod = differenceInDays(periodEnd, periodStart);
  const dailyRate = contract.totalAmount / contract.totalDays;
  
  // 2. Calculate gross amount
  let grossAmount = dailyRate * daysInPeriod;
  
  // 3. Add additional charges
  if (additionalCharges?.lateFee) {
    grossAmount += additionalCharges.lateFee;
  }
  
  // 4. Calculate commission
  const commissionRate = await getCommissionRate(contract.providerId);
  const platformCommission = grossAmount * commissionRate;
  
  // 5. Calculate tax
  const taxRate = await getTaxRate();
  const taxWithholding = grossAmount * taxRate;
  
  // 6. Calculate net
  const netAmount = grossAmount - platformCommission - taxWithholding;
  
  return {
    periodStart,
    periodEnd,
    daysInPeriod,
    dailyRate,
    grossAmount,
    platformCommission,
    taxWithholding,
    netAmount,
    lateFee: additionalCharges?.lateFee,
    penalty: additionalCharges?.penalty,
    refund: additionalCharges?.refund
  };
}
```

---

### 3.2 Pro-Rata Calculation Examples

#### Example 1: Contract Started Mid-Month
```
Contract: 90 days starting Day 15 of January
Daily rate: 1,000 ETB/day

Month 1 Settlement (January 31):
- Start: January 15
- End: January 31
- Days: 17 days
- Gross: 17,000 ETB

Month 2 Settlement (February 28):
- Start: February 1
- End: February 28
- Days: 28 days
- Gross: 28,000 ETB

Month 3 Settlement (March 31):
- Start: March 1
- End: March 31
- Days: 31 days
- Gross: 31,000 ETB

Final Settlement (April 14):
- Start: April 1
- End: April 14
- Days: 14 days
- Gross: 14,000 ETB

Total: 17 + 28 + 31 + 14 = 90 days ✓
```

#### Example 2: Early Termination After Grace Period
```
Contract: 90 days, 90,000 ETB (1,000 ETB/day)
Month 1: 30,000 ETB paid (escrow)
Day 31: Payment default
Day 32: Provider grants 3 days grace period
Day 34: Business still hasn't paid
Day 34: Contract terminated

Settlement:
- Month 1 (Days 1-30): 30,000 ETB (already paid from escrow)
- Grace period (Days 31-34): 4,000 ETB (debt created)
- Late fee (5%): 200 ETB
- Total debt: 4,200 ETB
- Business account: SUSPENDED
- Provider: Collects vehicles + 4,200 ETB debt recorded
```

---

## 4. MONTHLY SETTLEMENT PROCESSING

### 4.1 Monthly Settlement Workflow

```typescript
async function monthlySettlementWorkflow() {
  // 1. Identify contracts for settlement
  const contracts = await getContractsForMonthlySettlement();
  
  for (const contract of contracts) {
    try {
      // 2. Calculate settlement
      const settlement = await calculateMonthlySettlement(contract);
      
      // 3. Check approval threshold
      const requiresApproval = settlement.grossAmount >= APPROVAL_THRESHOLD;
      
      if (requiresApproval) {
        // 4a. Create pending settlement for admin approval
        await createPendingSettlement(settlement, 'PENDING_APPROVAL');
        await notifyAdminForApproval(settlement);
      } else {
        // 4b. Auto-approve and process
        await processSettlement(settlement, 'AUTO_APPROVED');
      }
      
    } catch (error) {
      await handleSettlementError(contract, error);
    }
  }
}
```

### 4.2 Monthly Settlement Cron Job

```typescript
@Cron('0 0 * * *') // Every day at midnight
async function dailySettlementCheck() {
  const today = new Date();
  
  // Check if it's the last day of the month
  const isLastDay = isLastDayOfMonth(today);
  
  if (isLastDay) {
    await processMonthlySettlements();
  }
}

async function processMonthlySettlements() {
  console.log(`Processing monthly settlements for ${format(new Date(), 'MMMM yyyy')}`);
  
  // Get all active long-term contracts
  const contracts = await this.contractRepository.find({
    status: 'ACTIVE',
    totalDays: GreaterThanOrEqual(30)
  });
  
  const results = {
    total: contracts.length,
    processed: 0,
    failed: 0,
    pendingApproval: 0
  };
  
  for (const contract of contracts) {
    try {
      const settlement = await this.processMonthlySettlement(contract);
      
      if (settlement.status === 'PENDING_APPROVAL') {
        results.pendingApproval++;
      } else {
        results.processed++;
      }
      
    } catch (error) {
      results.failed++;
      await this.logSettlementError(contract.id, error);
    }
  }
  
  // Send summary report to admin
  await this.sendSettlementReport(results);
  
  return results;
}
```

---

## 5. FINAL SETTLEMENT PROCESSING

### 5.1 Final Settlement Trigger

```typescript
// Event handler for contract completion
@EventHandler('ContractCompletedEvent')
async function handleContractCompleted(event: ContractCompletedEvent) {
  const contract = await this.contractRepository.findById(event.payload.contractId);
  
  // Process final settlement
  await this.processFinalSettlement(contract);
}

async function processFinalSettlement(contract: Contract) {
  // 1. Calculate remaining period
  const lastSettlementDate = contract.lastSettlementDate || contract.actualStartDate;
  const finalDate = contract.actualEndDate;
  const remainingDays = differenceInDays(finalDate, lastSettlementDate);
  
  // 2. Calculate amounts
  const dailyRate = contract.totalAmount / contract.totalDays;
  const grossAmount = dailyRate * remainingDays;
  
  // 3. Calculate deductions
  const commission = await calculateCommission(contract, grossAmount);
  const tax = await calculateTax(grossAmount);
  const netAmount = grossAmount - commission - tax;
  
  // 4. Create settlement record
  const settlement = await this.settlementRepository.create({
    contractId: contract.id,
    type: 'FINAL',
    periodStart: addDays(lastSettlementDate, 1),
    periodEnd: finalDate,
    daysInPeriod: remainingDays,
    grossAmount,
    commission,
    tax,
    netAmount,
    status: 'PENDING_APPROVAL'
  });
  
  // 5. Auto-approve if below threshold
  if (grossAmount < APPROVAL_THRESHOLD) {
    await this.approveAndProcessSettlement(settlement);
  } else {
    await this.notifyAdminForApproval(settlement);
  }
  
  // 6. Update contract
  await this.contractRepository.update(contract.id, {
    finalSettlementProcessed: true,
    finalSettlementAmount: netAmount,
    finalSettlementId: settlement.id
  });
}
```

---

## 6. EARLY RETURN SETTLEMENT

### 6.1 Early Return Settlement Handler

```typescript
@EventHandler('EarlyReturnApprovedEvent')
async function handleEarlyReturnApproved(event: EarlyReturnApprovedEvent) {
  const { contractId, earlyReturnDate, noticePeriodDays, businessId, providerId } = event.payload;
  
  const contract = await this.contractRepository.findById(contractId);
  
  // Calculate early return settlement
  const settlement = await this.calculateEarlyReturnSettlement(
    contract,
    earlyReturnDate,
    noticePeriodDays
  );
  
  // Process dual settlements: refund + provider payment
  await this.processEarlyReturnDualSettlement(settlement);
}

async function calculateEarlyReturnSettlement(
  contract: Contract,
  earlyReturnDate: Date,
  noticePeriodDays: number
): Promise<EarlyReturnSettlement> {
  
  const dailyRate = contract.totalAmount / contract.totalDays;
  
  // 1. Calculate usage
  const daysUsed = differenceInDays(earlyReturnDate, contract.actualStartDate);
  const remainingDays = contract.totalDays - daysUsed;
  
  // 2. Calculate amounts
  const usedAmount = dailyRate * daysUsed;
  const remainingAmount = dailyRate * remainingDays;
  
  // 3. Calculate penalty
  const penaltyRate = this.getPenaltyRate(noticePeriodDays);
  const penaltyAmount = remainingAmount * penaltyRate;
  
  // 4. Calculate business refund
  const refundToBusiness = remainingAmount - penaltyAmount;
  
  // 5. Calculate provider payment
  const alreadyPaid = contract.totalSettlementsPaid * (dailyRate * 30);
  const totalProviderAmount = usedAmount + penaltyAmount;
  const providerFinalPayment = totalProviderAmount - alreadyPaid;
  
  // 6. Apply commission and tax to final payment only
  const commission = await calculateCommission(contract, providerFinalPayment);
  const tax = await calculateTax(providerFinalPayment);
  const providerNet = providerFinalPayment - commission - tax;
  
  return {
    type: 'EARLY_RETURN',
    contractId: contract.id,
    earlyReturnDate,
    daysUsed,
    remainingDays,
    noticePeriodDays,
    penaltyRate,
    dailyRate,
    usedAmount,
    remainingAmount,
    penaltyAmount,
    refundToBusiness,
    alreadyPaidToProvider: alreadyPaid,
    providerFinalPaymentGross: providerFinalPayment,
    commission,
    tax,
    providerFinalPaymentNet: providerNet
  };
}
```

---

## 7. GRACE PERIOD SETTLEMENT

### 7.1 Grace Period Payment Handler

```typescript
async function handleGracePeriodPayment(
  contractId: string,
  paymentAmount: number
) {
  const contract = await this.contractRepository.findById(contractId);
  
  // Validate contract is in grace period
  if (contract.status !== 'ON_HOLD' || !contract.gracePeriodGranted) {
    throw new Error('Contract not in grace period');
  }
  
  // Calculate expected amount
  const expected = await this.calculateGracePeriodAmount(contract);
  
  // Validate payment amount
  if (paymentAmount < expected.totalDue) {
    throw new Error(`Insufficient payment. Expected: ${expected.totalDue}, Received: ${paymentAmount}`);
  }
  
  // Process settlement
  await this.processGracePeriodSettlement(contract, expected);
}

async function processGracePeriodSettlement(
  contract: Contract,
  calculation: GracePeriodCalculation
) {
  // 1. Create settlement record
  const settlement = await this.settlementRepository.create({
    contractId: contract.id,
    type: 'GRACE_PERIOD',
    periodStart: contract.gracePeriodStartDate,
    periodEnd: new Date(),
    daysInPeriod: contract.gracePeriodDays,
    grossAmount: calculation.gracePeriodAmount,
    lateFee: calculation.lateFee,
    commission: calculation.commission,
    tax: calculation.tax,
    netAmount: calculation.providerNet,
    status: 'APPROVED'
  });
  
  // 2. Transfer to provider immediately
  await this.walletService.transfer({
    from: contract.businessId,
    to: contract.providerId,
    amount: calculation.providerNet,
    type: 'GRACE_PERIOD_SETTLEMENT',
    settlementId: settlement.id
  });
  
  // 3. Lock next month escrow
  await this.escrowService.lockEscrow({
    contractId: contract.id,
    businessId: contract.businessId,
    amount: calculation.nextMonthEscrow,
    type: 'MONTHLY_ESCROW'
  });
  
  // 4. Reactivate contract
  await this.contractStateMachine.transitionTo(
    contract.id,
    'ACTIVE',
    'GRACE_PERIOD_PAYMENT_RECEIVED'
  );
  
  // 5. Send notifications
  await this.notifyGracePeriodResolved(contract, settlement);
}
```

---

## 8. APPROVAL WORKFLOWS

### 8.1 Approval Threshold Configuration (BR-032)

```typescript
const APPROVAL_THRESHOLDS = {
  AUTO_APPROVE: 50000,      // ETB - Auto-approve settlements < 50,000
  MANAGER_APPROVE: 200000,  // ETB - Manager approval for 50k-200k
  ADMIN_APPROVE: Infinity   // ETB - Admin approval for > 200k
};

function getApprovalLevel(amount: number): ApprovalLevel {
  if (amount < APPROVAL_THRESHOLDS.AUTO_APPROVE) {
    return 'AUTO';
  } else if (amount < APPROVAL_THRESHOLDS.MANAGER_APPROVE) {
    return 'MANAGER';
  } else {
    return 'ADMIN';
  }
}
```

### 8.2 Approval Workflow

```typescript
async function processSettlementApproval(settlement: Settlement) {
  const approvalLevel = getApprovalLevel(settlement.grossAmount);
  
  switch (approvalLevel) {
    case 'AUTO':
      // Auto-approve immediately
      await this.approveSettlement(settlement, {
        approvedBy: 'SYSTEM',
        approvalLevel: 'AUTO',
        approvedAt: new Date()
      });
      await this.executeSettlementPayment(settlement);
      break;
      
    case 'MANAGER':
      // Require manager approval
      await this.requestManagerApproval(settlement);
      break;
      
    case 'ADMIN':
      // Require admin approval
      await this.requestAdminApproval(settlement);
      break;
  }
}

async function requestManagerApproval(settlement: Settlement) {
  // Update settlement status
  await this.settlementRepository.update(settlement.id, {
    status: 'PENDING_MANAGER_APPROVAL',
    approvalRequestedAt: new Date()
  });
  
  // Notify manager
  await this.notificationService.send({
    to: 'ROLE:MANAGER',
    type: 'SETTLEMENT_APPROVAL_REQUIRED',
    priority: 'HIGH',
    data: {
      settlementId: settlement.id,
      contractId: settlement.contractId,
      amount: settlement.grossAmount,
      provider: await this.getProviderDetails(settlement.providerId),
      approvalDeadline: addHours(new Date(), 24)
    }
  });
}
```

### 8.3 Manual Approval Actions

```typescript
async function approveSettlement(
  settlementId: string,
  approverId: string,
  notes?: string
) {
  const settlement = await this.settlementRepository.findById(settlementId);
  
  // Update settlement
  await this.settlementRepository.update(settlementId, {
    status: 'APPROVED',
    approvedBy: approverId,
    approvedAt: new Date(),
    approvalNotes: notes
  });
  
  // Execute payment
  await this.executeSettlementPayment(settlement);
  
  // Notify parties
  await this.notifySettlementApproved(settlement);
}

async function rejectSettlement(
  settlementId: string,
  approverId: string,
  reason: string
) {
  const settlement = await this.settlementRepository.findById(settlementId);
  
  // Update settlement
  await this.settlementRepository.update(settlementId, {
    status: 'REJECTED',
    rejectedBy: approverId,
    rejectedAt: new Date(),
    rejectionReason: reason
  });
  
  // Notify parties
  await this.notifySettlementRejected(settlement, reason);
  
  // Create investigation case
  await this.createInvestigationCase(settlement, reason);
}
```

---

## 9. COMMISSION & TAX PROCESSING

### 9.1 Commission Calculation

```typescript
async function calculateCommission(
  contract: Contract,
  grossAmount: number
): Promise<number> {
  // Get provider's current tier and commission rate
  // Note: Provider tier is calculated using hybrid model (BR-042)
  // combining trust score + active fleet size
  const provider = await this.providerRepository.findById(contract.providerId);
  
  // Tier is recalculated automatically on contract events
  // See MVP_AUTHORITATIVE_BUSINESS_RULES.md Section 9 for tier calculation logic
  const commissionRate = await this.getCommissionRateForTier(provider.tier);
  
  // Calculate commission
  const commission = grossAmount * commissionRate;
  
  return commission;
}

// Commission rates by provider tier (from MasterData)
// These rates are configurable via masterdata.commission_strategy_rule
const DEFAULT_COMMISSION_RATES = {
  BRONZE: 0.10,      // 10%
  SILVER: 0.08,      // 8%
  GOLD: 0.06,        // 6%
  PLATINUM: 0.05     // 5%
};

async function getCommissionRateForTier(tier: string): Promise<number> {
  // Query masterdata.commission_strategy_rule for active strategy
  const strategy = await this.masterDataService.getActiveCommissionStrategy();
  const rule = strategy.rules.find(r => r.providerTierCode === tier);
  
  if (!rule) {
    // Fallback to default
    return DEFAULT_COMMISSION_RATES[tier] || 0.10;
  }
  
  return rule.ratePercentage;
}
```

### 9.2 Tax Withholding Calculation

```typescript
async function calculateTax(grossAmount: number): Promise<number> {
  // Get tax rate from MasterData (configurable)
  const taxRate = await this.getTaxRate();
  
  // Calculate tax withholding
  const tax = grossAmount * taxRate;
  
  return tax;
}

async function getTaxRate(): Promise<number> {
  const config = await this.masterDataService.get('tax.withholding.rate');
  return config?.value || 0.02; // Default 2%
}
```

### 9.3 Complete Settlement Calculation Example

```typescript
// Monthly settlement for 30 days
const dailyRate = 1000;        // ETB per day
const days = 30;
const grossAmount = 30000;     // ETB

// Provider tier: SILVER (8% commission)
const commission = 30000 * 0.08 = 2400;   // ETB
const tax = 30000 * 0.02 = 600;           // ETB
const netAmount = 30000 - 2400 - 600 = 27000; // ETB

Settlement Breakdown:
- Gross amount: 30,000 ETB
- Platform commission (8%): -2,400 ETB
- Tax withholding (2%): -600 ETB
- Net to provider: 27,000 ETB
```

---

## 10. DEBT TRACKING & RECOVERY

### 10.1 Debt Creation

```typescript
async function createDebt(
  contractId: string,
  businessId: string,
  providerId: string,
  amount: number,
  reason: string
) {
  const debt = await this.debtRepository.create({
    id: generateUUID(),
    contractId,
    businessId,
    providerId,
    amount,
    reason,
    status: 'OUTSTANDING',
    createdAt: new Date(),
    dueDate: addDays(new Date(), 30),
    paymentAttempts: 0
  });
  
  // Suspend business account
  await this.businessRepository.update(businessId, {
    accountStatus: 'SUSPENDED',
    suspensionReason: 'UNPAID_DEBT',
    outstandingDebt: amount
  });
  
  // Notify both parties
  await this.notifyDebtCreated(debt);
  
  return debt;
}
```

### 10.2 Debt Payment Processing

```typescript
async function processDebtPayment(
  debtId: string,
  paymentAmount: number
) {
  const debt = await this.debtRepository.findById(debtId);
  
  // Validate amount
  if (paymentAmount < debt.amount) {
    throw new Error('Partial debt payment not allowed in MVP');
  }
  
  // Process payment
  await this.walletService.transfer({
    from: debt.businessId,
    to: debt.providerId,
    amount: paymentAmount,
    type: 'DEBT_PAYMENT',
    debtId: debt.id
  });
  
  // Update debt status
  await this.debtRepository.update(debtId, {
    status: 'PAID',
    paidAt: new Date(),
    paidAmount: paymentAmount
  });
  
  // Reactivate business account
  await this.businessRepository.update(debt.businessId, {
    accountStatus: 'ACTIVE',
    suspensionReason: null,
    outstandingDebt: 0
  });
  
  // Notify parties
  await this.notifyDebtPaid(debt);
}
```

### 10.3 Debt Escalation

```typescript
@Cron('0 0 * * *') // Daily check
async function checkOverdueDebts() {
  const overdueDebts = await this.debtRepository.find({
    status: 'OUTSTANDING',
    dueDate: LessThan(new Date())
  });
  
  for (const debt of overdueDebts) {
    const daysOverdue = differenceInDays(new Date(), debt.dueDate);
    
    if (daysOverdue === 7) {
      // 7 days overdue - send warning
      await this.sendDebtWarning(debt);
    } else if (daysOverdue === 14) {
      // 14 days overdue - send final notice
      await this.sendDebtFinalNotice(debt);
    } else if (daysOverdue === 30) {
      // 30 days overdue - escalate to dispute
      await this.escalateDebtToDispute(debt);
    }
  }
}

async function escalateDebtToDispute(debt: Debt) {
  // Create dispute on behalf of provider
  const dispute = await this.disputeService.create({
    contractId: debt.contractId,
    createdBy: 'SYSTEM',
    onBehalfOf: debt.providerId,
    category: 'NON_PAYMENT',
    description: `Automated dispute for unpaid debt of ${debt.amount} ETB. Debt overdue by 30 days.`,
    evidenceAttached: [{
      type: 'DEBT_RECORD',
      debtId: debt.id,
      amount: debt.amount,
      createdAt: debt.createdAt,
      dueDate: debt.dueDate
    }]
  });
  
  // Update debt with dispute reference
  await this.debtRepository.update(debt.id, {
    status: 'IN_DISPUTE',
    disputeId: dispute.id
  });
  
  // Notify both parties
  await this.notifyDebtEscalated(debt, dispute);
}
```

---

## 11. SETTLEMENT RECONCILIATION

### 11.1 Daily Reconciliation

```typescript
@Cron('0 1 * * *') // Daily at 1 AM
async function dailySettlementReconciliation() {
  const yesterday = subDays(new Date(), 1);
  
  // Get all settlements processed yesterday
  const settlements = await this.settlementRepository.find({
    status: 'COMPLETED',
    processedAt: Between(startOfDay(yesterday), endOfDay(yesterday))
  });
  
  // Reconciliation checks
  const reconciliation = {
    date: yesterday,
    totalSettlements: settlements.length,
    totalGrossAmount: 0,
    totalCommission: 0,
    totalTax: 0,
    totalNetPaid: 0,
    discrepancies: []
  };
  
  for (const settlement of settlements) {
    // Sum amounts
    reconciliation.totalGrossAmount += settlement.grossAmount;
    reconciliation.totalCommission += settlement.commission;
    reconciliation.totalTax += settlement.tax;
    reconciliation.totalNetPaid += settlement.netAmount;
    
    // Check for discrepancies
    const calculated = settlement.grossAmount - settlement.commission - settlement.tax;
    if (Math.abs(calculated - settlement.netAmount) > 0.01) {
      reconciliation.discrepancies.push({
        settlementId: settlement.id,
        expected: calculated,
        actual: settlement.netAmount,
        difference: calculated - settlement.netAmount
      });
    }
    
    // Verify wallet transaction exists
    const walletTx = await this.walletService.findTransaction({
      settlementId: settlement.id,
      amount: settlement.netAmount
    });
    
    if (!walletTx) {
      reconciliation.discrepancies.push({
        settlementId: settlement.id,
        issue: 'MISSING_WALLET_TRANSACTION',
        amount: settlement.netAmount
      });
    }
  }
  
  // Send reconciliation report
  await this.sendReconciliationReport(reconciliation);
  
  // Alert if discrepancies found
  if (reconciliation.discrepancies.length > 0) {
    await this.alertFinanceTeam(reconciliation);
  }
}
```

### 11.2 Monthly Settlement Report

```typescript
async function generateMonthlySettlementReport(year: number, month: number) {
  const startDate = new Date(year, month - 1, 1);
  const endDate = endOfMonth(startDate);
  
  // Get all settlements for the month
  const settlements = await this.settlementRepository.find({
    processedAt: Between(startDate, endDate),
    status: 'COMPLETED'
  });
  
  // Aggregate by type
  const byType = {
    MONTHLY: { count: 0, grossAmount: 0, commission: 0, netAmount: 0 },
    FINAL: { count: 0, grossAmount: 0, commission: 0, netAmount: 0 },
    EARLY_RETURN: { count: 0, grossAmount: 0, commission: 0, netAmount: 0 },
    GRACE_PERIOD: { count: 0, grossAmount: 0, commission: 0, netAmount: 0 }
  };
  
  for (const settlement of settlements) {
    const type = settlement.type;
    byType[type].count++;
    byType[type].grossAmount += settlement.grossAmount;
    byType[type].commission += settlement.commission;
    byType[type].netAmount += settlement.netAmount;
  }
  
  // Calculate totals
  const totals = {
    settlements: settlements.length,
    grossAmount: settlements.reduce((sum, s) => sum + s.grossAmount, 0),
    commission: settlements.reduce((sum, s) => sum + s.commission, 0),
    tax: settlements.reduce((sum, s) => sum + s.tax, 0),
    netAmount: settlements.reduce((sum, s) => sum + s.netAmount, 0)
  };
  
  // Generate report
  const report = {
    period: `${year}-${String(month).padStart(2, '0')}`,
    startDate,
    endDate,
    byType,
    totals,
    platformRevenue: totals.commission + totals.tax,
    averageSettlementAmount: totals.grossAmount / totals.settlements
  };
  
  // Save report
  await this.reportRepository.create(report);
  
  // Send to stakeholders
  await this.sendMonthlyReport(report);
  
  return report;
}
```

---

## APPENDIX A: Settlement Database Schema

```sql
CREATE TABLE finance_schema.settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id UUID NOT NULL REFERENCES contracts_schema.contracts(id),
  business_id UUID NOT NULL,
  provider_id UUID NOT NULL,
  
  -- Type and status
  type VARCHAR(50) NOT NULL, -- MONTHLY, FINAL, EARLY_RETURN, GRACE_PERIOD
  status VARCHAR(50) NOT NULL, -- PENDING_APPROVAL, APPROVED, REJECTED, COMPLETED
  
  -- Period
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  days_in_period INTEGER NOT NULL,
  
  -- Amounts
  daily_rate DECIMAL(15,2) NOT NULL,
  gross_amount DECIMAL(15,2) NOT NULL,
  platform_commission DECIMAL(15,2) NOT NULL,
  tax_withholding DECIMAL(15,2) NOT NULL,
  net_amount DECIMAL(15,2) NOT NULL,
  
  -- Additional charges
  late_fee DECIMAL(15,2) DEFAULT 0,
  penalty DECIMAL(15,2) DEFAULT 0,
  refund DECIMAL(15,2) DEFAULT 0,
  
  -- Approval
  approval_level VARCHAR(20), -- AUTO, MANAGER, ADMIN
  requires_approval BOOLEAN DEFAULT false,
  approved_by UUID,
  approved_at TIMESTAMP,
  approval_notes TEXT,
  rejected_by UUID,
  rejected_at TIMESTAMP,
  rejection_reason TEXT,
  
  -- Processing
  processed_at TIMESTAMP,
  wallet_transaction_id UUID,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE finance_schema.debts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id UUID NOT NULL,
  business_id UUID NOT NULL,
  provider_id UUID NOT NULL,
  
  -- Debt details
  amount DECIMAL(15,2) NOT NULL,
  reason VARCHAR(255) NOT NULL,
  status VARCHAR(50) NOT NULL, -- OUTSTANDING, PAID, IN_DISPUTE, WRITTEN_OFF
  
  -- Dates
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  due_date DATE NOT NULL,
  paid_at TIMESTAMP,
  paid_amount DECIMAL(15,2),
  
  -- Dispute
  dispute_id UUID,
  
  -- Payment attempts
  payment_attempts INTEGER DEFAULT 0,
  last_payment_attempt_at TIMESTAMP
);

-- Indexes
CREATE INDEX idx_settlements_contract ON finance_schema.settlements(contract_id);
CREATE INDEX idx_settlements_provider ON finance_schema.settlements(provider_id);
CREATE INDEX idx_settlements_status ON finance_schema.settlements(status);
CREATE INDEX idx_settlements_type_status ON finance_schema.settlements(type, status);
CREATE INDEX idx_settlements_period ON finance_schema.settlements(period_start, period_end);

CREATE INDEX idx_debts_business ON finance_schema.debts(business_id);
CREATE INDEX idx_debts_provider ON finance_schema.debts(provider_id);
CREATE INDEX idx_debts_status ON finance_schema.debts(status);
CREATE INDEX idx_debts_due_date ON finance_schema.debts(due_date) WHERE status = 'OUTSTANDING';
```

---

**END OF SETTLEMENT PROCESSING SPECIFICATION**

---

**For Implementation:** Use this document as reference for:
1. Settlement calculation formulas
2. Trigger events and timing
3. Approval workflow implementation
4. Commission and tax calculations
5. Debt tracking system

**For Testing:** Verify:
1. All settlement types calculate correctly
2. Monthly settlements process on schedule
3. Approval thresholds work as expected
4. Commission and tax applied correctly
5. Debt creation and tracking functions properly
