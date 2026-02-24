# Movello MVP - Admin Wallet Operations Specification
## Temporary Admin-Controlled Wallet Management - Version 1.0

**Document Status:** AUTHORITATIVE  
**Date:** February 20, 2026  
**Related Documents:** 
- MVP_AUTHORITATIVE_BUSINESS_RULES.md (Section 3: Escrow & Financial Rules)
- MVP_EVENT_CATALOG_AND_HANDLERS.md  
- MVP_MODULE_INTEGRATION_SPECIFICATION.md (Section: Finance Module)  
**Review Status:** ✅ Approved for Implementation

---

## Document Purpose

This document defines the **temporary admin wallet operations** that enable platform administrators to manually deposit and withdraw funds from business and provider wallets until payment gateway integration is finalized. This specification ensures proper audit trails, security controls, and operational transparency.

**Scope:**
- Admin-initiated wallet deposits
- Admin-initiated wallet withdrawals
- Audit logging for compliance
- Multi-channel notifications (in-app, SMS, email)
- Authorization and security controls

**Out of Scope:**
- User-initiated deposits via payment gateway (separate specification)
- Automated settlement operations (see MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md)
- Bulk/batch operations (future enhancement)

---

## TABLE OF CONTENTS

1. [Business Rules for Admin Wallet Operations](#1-business-rules-for-admin-wallet-operations)
2. [Workflow Specifications](#2-workflow-specifications)
3. [API Endpoints](#3-api-endpoints)
4. [Command Specifications](#4-command-specifications)
5. [Event Specifications](#5-event-specifications)
6. [Audit Requirements](#6-audit-requirements)
7. [Authorization & Security](#7-authorization--security)
8. [Notification Requirements](#8-notification-requirements)
9. [Entity Framework Implementation](#9-entity-framework-implementation)
10. [Frontend UI Requirements](#10-frontend-ui-requirements)
11. [Testing & Verification](#11-testing--verification)

---

## 1. BUSINESS RULES FOR ADMIN WALLET OPERATIONS

### 1.1 General Rules

**Rule AWO-001: Wallet Selection Prerequisite**
- Admin MUST select a specific wallet before performing deposit/withdrawal
- No "blind" operations without knowing wallet owner context
- Wallet selection provides full owner information (name, type, contact details)

**Rule AWO-002: Operation Scope**
- Admin can deposit to ANY active wallet (business or provider)
- Admin can withdraw from ANY active wallet with sufficient available balance
- Operations are limited to MAIN wallet accounts (not escrow, commission, or reserve wallets)

**Rule AWO-003: Wallet Status Validation**
- Operations ONLY allowed on wallets with status = `ACTIVE`
- SUSPENDED, CLOSED, or FROZEN wallets CANNOT be operated on
- System MUST validate wallet status before processing

**Rule AWO-004: Balance Constraints**
- Deposits: No maximum limit (admin has full control)
- Withdrawals: Cannot exceed available balance (`balance - locked_balance`)
- Withdrawals: Cannot withdraw locked funds (funds in escrow)
- Negative balances are NOT allowed

**Rule AWO-005: Currency Validation**
- All operations default to ETB (Ethiopian Birr)
- Currency MUST match wallet's configured currency
- Multi-currency validation if wallet supports multiple currencies

---

### 1.2 Audit & Compliance Rules

**Rule AWO-006: Mandatory Audit Trail**
- ALL admin operations MUST be recorded in `wallet_event_log` table
- Audit records MUST include:
  - Admin user ID (from JWT token)
  - Admin user name
  - Transaction amount and currency
  - Operation reason (mandatory field)
  - Operation description
  - Transaction reference (unique identifier)
  - Timestamp (ISO 8601 format)
  - Wallet owner information

**Rule AWO-007: Reason Requirement**
- Admin MUST provide a reason for every deposit/withdrawal
- Reason is a mandatory field (cannot be null or empty)
- Predefined reason options (see Section 3.2)
- Custom reason text allowed for "Other" category

**Rule AWO-008: Transaction Reference Format**
- Admin deposits: `ADMIN_DEP-{YYYYMMDD}-{sequence}`
- Admin withdrawals: `ADMIN_WITH-{YYYYMMDD}-{sequence}`
- Reference MUST be unique (idempotency key)
- Format distinguishes admin operations from user-initiated transactions

---

### 1.3 Notification Rules

**Rule AWO-009: Multi-Channel Notification Requirement**
- ALL admin wallet operations MUST trigger notifications to wallet owner
- Notification channels: In-app + SMS + Email (all three required)
- Notifications MUST include:
  - Operation type (deposit/withdrawal)
  - Amount and currency
  - Admin name (who performed operation)
  - Transaction reference
  - Reason for operation
  - New wallet balance
  - Timestamp

**Rule AWO-010: Notification Timing**
- Notifications MUST be sent after transaction is committed to database
- Use asynchronous event-driven pattern (MediatR events)
- Failed notifications MUST NOT block transaction completion
- Notification failures logged for retry

---

### 1.4 Authorization Rules

**Rule AWO-011: Admin Role Requirement**
- Only users with `admin` role can access admin wallet operations
- Role verified via Keycloak JWT token (`realm_access.roles`)
- No delegation or proxy operations allowed

**Rule AWO-012: Future Fine-Grained Permissions** (Phase 2)
- Prepare for granular permissions: `wallet:deposit`, `wallet:withdraw`
- Current implementation uses `AdminOnly` policy
- Future enhancement for role-based access control (RBAC)

---

## 2. WORKFLOW SPECIFICATIONS

### 2.1 Admin Deposit Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                   ADMIN DEPOSIT WORKFLOW                     │
└─────────────────────────────────────────────────────────────┘

1. ADMIN NAVIGATION
   └─> Admin logs into admin portal
   └─> Navigates to Wallet Management
   └─> Searches for business/provider wallet (by name, ID, or filter)
   └─> Clicks on wallet row

2. WALLET DETAILS VIEW
   └─> System loads wallet details:
       - Owner name and type (Business/Provider)
       - Current balance
       - Locked balance
       - Available balance (calculated)
       - Wallet status
       - Recent transaction history

3. DEPOSIT INITIATION
   └─> Admin clicks "Deposit Funds" button
   └─> System validates: Wallet status = ACTIVE
   └─> Deposit dialog opens

4. DEPOSIT FORM SUBMISSION
   └─> Admin enters:
       - Amount (required, > 0)
       - Currency (default: ETB)
       - Description (optional, max 500 chars)
       - Reason (required dropdown selection)
   └─> System shows preview: "New balance: {current + amount}"
   └─> Admin clicks "Confirm Deposit"

5. BACKEND PROCESSING
   └─> Validate wallet exists and is ACTIVE
   └─> Generate unique transaction reference
   └─> Begin database transaction
   └─> Create WalletLedgerTransaction (type: DEPOSIT)
   └─> Create WalletLedgerEntry (direction: CREDIT)
   └─> Update wallet balance: wallet.Credit(amount)
   └─> Commit database transaction
   └─> Publish AdminDepositCompletedEvent

6. EVENT PROCESSING (Async)
   └─> WalletAuditEventHandler:
       - Insert record into wallet_event_log
       - actor_type = 'ADMIN'
   └─> AdminTransactionNotificationHandler:
       - Send in-app notification to wallet owner
       - Send email notification
       - Send SMS notification

7. UI RESPONSE
   └─> Show success message with transaction reference
   └─> Refresh wallet details page
   └─> Updated balance displayed
   └─> Transaction appears in history with "Admin Operation" badge
```

---

### 2.2 Admin Withdrawal Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                  ADMIN WITHDRAWAL WORKFLOW                   │
└─────────────────────────────────────────────────────────────┘

1. ADMIN NAVIGATION
   └─> [Same as deposit workflow steps 1-2]

2. WITHDRAWAL INITIATION
   └─> Admin clicks "Withdraw Funds" button
   └─> System validates:
       - Wallet status = ACTIVE
       - Available balance > 0
   └─> Withdrawal dialog opens

3. WITHDRAWAL FORM SUBMISSION
   └─> Admin enters:
       - Amount (required, > 0, <= available balance)
       - Currency (default: ETB)
       - Description (optional, max 500 chars)
       - Reason (required dropdown)
   └─> System validates: amount <= (balance - locked_balance)
   └─> If locked_balance > 0, show warning:
       "Note: This wallet has {locked_balance} ETB in escrow"
   └─> System shows preview: "New balance: {current - amount}"
   └─> Admin clicks "Confirm Withdrawal"

4. BACKEND PROCESSING
   └─> Validate wallet exists and is ACTIVE
   └─> Validate: amount <= available balance
   └─> Generate unique transaction reference
   └─> Begin database transaction
   └─> Create WalletLedgerTransaction (type: WITHDRAWAL)
   └─> Create WalletLedgerEntry (direction: DEBIT)
   └─> Update wallet balance: wallet.Debit(amount)
   └─> Commit database transaction
   └─> Publish AdminWithdrawalCompletedEvent

5. EVENT PROCESSING (Async)
   └─> [Same as deposit workflow step 6]

6. UI RESPONSE
   └─> [Same as deposit workflow step 7]
```

---

### 2.3 Validation Rules Summary

| Validation | Deposit | Withdrawal |
|------------|---------|------------|
| Wallet exists | ✅ Required | ✅ Required |
| Wallet status = ACTIVE | ✅ Required | ✅ Required |
| Amount > 0 | ✅ Required | ✅ Required |
| Amount <= available balance | ❌ Not checked | ✅ Required |
| Reason provided | ✅ Required | ✅ Required |
| Description length <= 500 | ✅ Required | ✅ Required |
| Currency matches wallet | ✅ Required | ✅ Required |
| Admin authorization | ✅ Required | ✅ Required |

---

## 3. API ENDPOINTS

### 3.1 Admin Deposit Endpoint

**Endpoint:** `POST /api/admin/wallets/{walletId:guid}/deposit`

**Authorization:** Requires `AdminOnly` policy

**Route Parameters:**
- `walletId` (GUID, required) - Target wallet ID (wallet already selected by admin)

**Request Body:**
```json
{
  "amount": 5000.00,
  "currency": "ETB",
  "description": "Initial funding for new business account",
  "reason": "Initial funding"
}
```

**Response:**
```json
{
  "transactionId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "reference": "ADMIN_DEP-20260220-001",
  "amount": 5000.00,
  "currency": "ETB",
  "completedAt": "2026-02-20T14:30:00Z",
  "updatedBalance": {
    "balance": 15000.00,
    "lockedBalance": 0.00,
    "availableBalance": 15000.00,
    "currency": "ETB"
  }
}
```

**HTTP Status Codes:**
- `200 OK` - Deposit successful
- `400 Bad Request` - Validation error
- `401 Unauthorized` - Not authenticated
- `403 Forbidden` - Admin role required
- `404 Not Found` - Wallet not found
- `409 Conflict` - Wallet not active
- `500 Internal Server Error` - Unexpected error

---

### 3.2 Predefined Reason Options

**Deposit Reasons:**
- "Initial funding" - First-time wallet funding
- "Balance correction" - Correcting errors
- "Refund" - Refunding transactions
- "Promotional credit" - Marketing incentives
- "Other" - Custom reason

**Withdrawal Reasons:**
- "Payout processed" - Provider payout completed
- "Chargeback" - Reversing transactions
- "Balance correction" - Correcting errors
- "Penalty enforcement" - Contract penalties
- "Other" - Custom reason

---

## 4. IMPLEMENTATION FILES

### Backend Files to Create:

1. **Domain Entities:**
   - `Modules/Finance/Domain/Entities/WalletEventLog.cs`

2. **Domain Events:**
   - `Modules/Finance/Domain/Events/AdminDepositCompletedEvent.cs`
   - `Modules/Finance/Domain/Events/AdminWithdrawalCompletedEvent.cs`

3. **Application Commands:**
   - `Modules/Finance/Application/Wallet/Commands/AdminDepositFundsCommand.cs`
   - `Modules/Finance/Application/Wallet/Commands/AdminWithdrawFundsCommand.cs`

4. **Event Handlers:**
   - `Modules/Finance/Application/Wallet/EventHandlers/WalletAuditEventHandler.cs`
   - `Modules/Finance/Application/Wallet/EventHandlers/AdminTransactionNotificationHandler.cs`

5. **DTOs:**
   - `Modules/Finance/Application/Wallet/DTOs/AdminWalletDtos.cs`

6. **Controller Updates:**
   - Add endpoints to `Controllers/Finance/AdminWalletController.cs`

7. **DbContext Updates:**
   - Add `DbSet<WalletEventLog>` to DbContext
   - Configure entity mappings

8. **EF Core Migration:**
   - Run: `dotnet ef migrations add AddAdminWalletOperations`
   - Run: `dotnet ef database update`

### Frontend Files to Create:

1. **Services:**
   - `movello-marketplace-core/src/core/services/admin-wallet-service.ts`

2. **Components:**
   - Admin wallet details page
   - Deposit dialog component
   - Withdrawal dialog component

---

## 5. TESTING CHECKLIST

### Backend Tests:
- [ ] AdminDepositFundsCommand creates transaction
- [ ] AdminWithdrawFundsCommand creates transaction
- [ ] Validation: Cannot deposit to inactive wallet
- [ ] Validation: Cannot withdraw exceeding balance
- [ ] Idempotency: Duplicate references handled
- [ ] Audit log entries created
- [ ] Notifications sent (in-app, SMS, email)
- [ ] Authorization: Only admins can access

### Integration Tests:
- [ ] Admin deposit API updates balance
- [ ] Admin withdrawal API updates balance
- [ ] Audit log entries in database
- [ ] Transaction history shows admin operations
- [ ] Non-admin users blocked from endpoints

### End-to-End Tests:
- [ ] Admin deposits 10,000 ETB → Business receives notifications
- [ ] Admin withdraws 2,000 ETB → Provider receives notifications
- [ ] Audit log query shows admin operations
- [ ] Transaction appears with "Admin Operation" badge

---

**END OF SPECIFICATION**
