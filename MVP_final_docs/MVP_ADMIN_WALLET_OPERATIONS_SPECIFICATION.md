# Movello MVP - Admin Wallet Operations Specification
## Admin-Controlled Wallet & Escrow Management - Version 2.0

**Document Status:** AUTHORITATIVE
**Last verified against code: 2026-07-23** — verified directly against `Modules/Finance/Application/Wallet/Commands/AdminDepositFundsCommand.cs`, `AdminWithdrawFundsCommand.cs`, `Modules/Finance/Application/Wallet/DTOs/AdminWalletDtos.cs`, `Modules/Finance/Application/Wallet/EventHandlers/WalletAuditEventHandler.cs`, `AdminTransactionNotificationHandler.cs`, `Modules/Finance/Domain/Entities/WalletEventLog.cs`, `Controllers/Finance/AdminWalletController.cs`, `Controllers/Finance/EscrowController.cs`, `Modules/Finance/Application/Escrow/Commands/FreezeEscrowCommand.cs`, `UnfreezeEscrowCommand.cs`, `ProcessEarlyTerminationCommand.cs`, and the web admin surface (`movello-marketplace-core/src/core/services/admin-wallet-service.ts`, `src/features/admin/pages/wallets/AdminWalletDetailPage.tsx`, `AllWalletsPage.tsx`, `PlatformWalletDashboard.tsx`). Version 1.0 (February 20, 2026) described this as a **temporary** stopgap ("until payment gateway integration is finalized") scoped narrowly to admin deposit/withdraw. Both premises are now stale: automated payment gateways (Chapa/Telebirr/CBE Birr) have been live for some time (see `backlog/mvp/epic-08-wallet-escrow.md`), yet admin-direct deposit/withdraw was never removed — it is a permanent, actively-used support/correction tool, not a bridge feature. This rewrite also expands scope to cover the escrow freeze/unfreeze/early-termination admin surface, which v1.0 explicitly excluded but which is the other half of "admin-controlled wallet management" as it actually exists in code today.

**Related documents:**
- `backlog/mvp/epic-08-wallet-escrow.md` — Story 8.7 (freeze/unfreeze/early-termination) and Story 8.9 (admin wallet operations), full epic-level DoD tracking (rewritten 2026-07-23)
- `project-docs/service-specs/14_Wallet_Engine_Flow_Specification.md` — full wallet/escrow pipeline this document's operations plug into (rewritten 2026-07-23)
- `project-docs/18_Implementation_Coverage_Audit.md` §10.3, §10.5 — cross-cutting findings referenced below (platform wallet lookup inconsistency, no dispute-engine entity)

**Scope:**
- Admin-initiated wallet deposits and withdrawals (any wallet, any account type — see §1.2 correction)
- Admin wallet status suspend/activate
- Admin escrow freeze/unfreeze (dispute holds) and early-termination processing
- Audit logging for compliance (`wallet_event_logs`)
- Notifications to the wallet owner (in-app always; email/SMS conditionally — see §1.3 correction)
- Authorization and security controls (and a real gap found in this pass — see §1.4)

**Out of scope (unchanged from v1.0):**
- User-initiated deposits via payment gateway (see `epic-08-wallet-escrow.md` Story 8.3)
- Automated settlement operations (see `SETTLEMENT_ENHANCEMENTS_ADDENDUM.md`, rewritten alongside this document)
- Bulk/batch operations (not built)

---

## TABLE OF CONTENTS

1. [Business Rules for Admin Wallet Operations](#1-business-rules-for-admin-wallet-operations)
2. [Workflow Specifications](#2-workflow-specifications)
3. [API Endpoints](#3-api-endpoints)
4. [Escrow Admin Operations: Freeze / Unfreeze / Early Termination](#4-escrow-admin-operations-freeze--unfreeze--early-termination)
5. [Audit Requirements](#5-audit-requirements)
6. [Authorization & Security — Including a Confirmed Gap](#6-authorization--security--including-a-confirmed-gap)
7. [Notification Requirements](#7-notification-requirements)
8. [Frontend UI (as built)](#8-frontend-ui-as-built)
9. [Known Gaps & Cleanup Items](#9-known-gaps--cleanup-items)

---

## 1. BUSINESS RULES FOR ADMIN WALLET OPERATIONS

### 1.1 General Rules (deposit/withdraw)

**Rule AWO-001: Wallet Selection Prerequisite** — unchanged from v1.0, confirmed: admin always operates against a specific `walletId` already resolved via `GET /api/admin/wallets` or `GET /api/admin/wallets/{walletId}`; there is no "blind" deposit/withdraw-by-owner-lookup endpoint.

**Rule AWO-002: Operation Scope — CORRECTED.** v1.0 stated "Operations are limited to MAIN wallet accounts (not escrow, commission, or reserve wallets)." **This is not enforced in code.** `AdminDepositFundsCommandHandler` and `AdminWithdrawFundsCommandHandler` (`Modules/Finance/Application/Wallet/Commands/`) validate only that the wallet exists and `wallet.Status == "ACTIVE"` — there is no check on `wallet.AccountType` at all. An admin can deposit to or withdraw from an `ESCROW` or `COMMISSION` wallet through the exact same endpoint used for `MAIN` wallets. The web UI (`AllWalletsPage.tsx`) lists and links to every account type without restriction, and `AdminWalletDetailPage.tsx` shows the same Deposit/Withdraw buttons regardless of `AccountType`. Treat this as the actual, broader scope — not a documentation gap to silently narrow back to MAIN-only.

**Rule AWO-003: Wallet Status Validation** — confirmed: both handlers throw `BusinessRuleException` if `wallet.Status != "ACTIVE"`.

**Rule AWO-004: Balance Constraints** — confirmed with one correction: deposits have no maximum (only a `[Range(0.01, 9_999_999_999.99)]` DTO-level cap, effectively unlimited for practical purposes); withdrawals are validated against `wallet.Balance - wallet.LockedBalance` (`InsufficientBalanceException` if exceeded) — note this is a **different available-balance formula** than the one used for regular (non-admin) withdrawal requests, which also subtracts `PendingWithdrawalBalance`. An admin withdrawal does not go through `LockForWithdrawal`/`PendingWithdrawalBalance` at all — it debits `wallet.Balance` directly and immediately, with no pending state.

**Rule AWO-005: Currency Validation** — confirmed: both handlers throw `BusinessRuleException` if `request.Currency != wallet.Currency`.

### 1.2 Audit & Compliance Rules

**Rule AWO-006: Mandatory Audit Trail** — confirmed, with a schema-name correction: the audit table is `wallet_event_logs` (plural — `[Table("wallet_event_logs", Schema = "wallet")]`), not `wallet_event_log` as v1.0 stated. Every admin deposit/withdrawal publishes `AdminDepositCompletedEvent`/`AdminWithdrawalCompletedEvent`, handled by `WalletAuditEventHandler`, which writes a `WalletEventLog` row with `EventType = "ADMIN_DEPOSIT_COMPLETED"`/`"ADMIN_WITHDRAWAL_COMPLETED"`, `ActorType = "ADMIN"`, `ActorId` = the admin's user id, and a JSON `EventPayload` containing amount/currency/reference/reason/admin name/owner info. Audit-write failures are caught and logged, not rethrown — an audit-log failure does **not** roll back the underlying financial transaction (it has already committed by the time the event handler runs).

**Rule AWO-007: Reason Requirement** — confirmed at two layers: `[Required, StringLength(100)]` on `AdminDepositRequest.Reason`/`AdminWithdrawRequest.Reason` (backend DTO), and client-side validation in `AdminWalletDetailPage.tsx` (`isDepositValid`/`isWithdrawValid` both require a non-empty trimmed reason). The predefined dropdown options are real and match exactly:
- **Deposit reasons** (`DEPOSIT_REASONS` in `admin-wallet-service.ts`): "Initial funding", "Balance correction", "Refund", "Promotional credit", "Other"
- **Withdrawal reasons** (`WITHDRAWAL_REASONS`): "Payout processed", "Chargeback", "Balance correction", "Penalty enforcement", "Other"
- When "Other" is selected, the UI substitutes a free-text custom-reason field as the actual `reason` value sent to the API — the backend never sees the literal string `"Other"`.

**Rule AWO-008: Transaction Reference Format** — confirmed: `ADMIN_DEP-{yyyyMMdd}-{sequence:D3}` and `ADMIN_WITH-{yyyyMMdd}-{sequence:D3}` (`GenerateTransactionReferenceAsync`, 3-digit zero-padded sequence — v1.0 didn't specify digit count). Idempotency is checked by looking up an existing transaction with the freshly-generated reference before creating a new one; in practice, because the reference embeds a sequence generated fresh per call, a true duplicate-reference collision would require two admin calls to race for the same sequence number, not a client-supplied idempotency key.

### 1.3 Notification Rules — CORRECTED

**Rule AWO-009: Multi-Channel Notification Requirement — not "all three required" in practice.** v1.0 stated in-app + SMS + email are all mandatory for every operation. Code (`AdminTransactionNotificationHandler`) shows:
- **In-app is unconditional** — sent whenever a `UserAccountId` can be resolved for the wallet owner (business/provider/direct user lookup via `IIdentityUnitOfWork`). If no user account can be resolved at all, the entire notification is skipped (logged as a warning) — no channel fires.
- **Email is sent only if the resolved recipient has a non-blank email** on file (`userAccount?.Email ?? ownerInfo.ContactEmail`).
- **SMS is sent only if the resolved recipient has a non-blank phone number** on file.

So the real rule is: in-app always (when a user account resolves), email/SMS opportunistically (when contact info exists) — not an unconditional three-channel guarantee. Notification failures are caught per-channel and logged, never allowed to fail the underlying transaction (consistent with v1.0's intent, just confirming it holds).

**Rule AWO-010: Notification Timing** — confirmed: notifications are dispatched via `IMediator.Publish` from within the command handler, after the DB transaction has already committed — an async, event-driven pattern as v1.0 described, using the same `AdminDepositCompletedEvent`/`AdminWithdrawalCompletedEvent` that also drive the audit log (§1.2), not a separate notification-only event.

### 1.4 Authorization Rules — one confirmed, one gap found

**Rule AWO-011: Admin Role Requirement (deposit/withdraw/status)** — confirmed: `AdminWalletController` carries `[Authorize(Policy = "AdminOnly")]` at the controller level, covering deposit, withdraw, status suspend/activate, and the read endpoints.

**Rule AWO-012 — NEW FINDING, not in v1.0: the escrow freeze/unfreeze/early-termination endpoints are NOT gated by `AdminOnly`.** `Controllers/Finance/EscrowController.cs` (`[Route("api/finance/escrow")]`) carries only a bare `[Authorize]` at the controller level — no policy restriction. `FreezeEscrowCommandHandler`, `UnfreezeEscrowCommandHandler`, and `ProcessEarlyTerminationCommandHandler` perform no caller-role check internally either; they trust whatever `FrozenBy`/`UnfrozenBy`/`InitiatedBy`/`TerminatedBy` values are passed in the request body, with no verification that the caller (which could be any authenticated business or provider user, not just an admin) actually has the right to freeze/unfreeze/terminate an arbitrary contract's escrow. This is a real authorization gap in the running system, not a documentation omission — flagged here explicitly because this document's job is to describe admin-controlled wallet operations, and right now the freeze/unfreeze/early-termination trio is *not actually restricted to admins at the API layer*, only conventionally treated as admin-only because no non-admin UI calls them (see §8). **This should be raised as an engineering ticket** (add `[Authorize(Policy = "AdminOnly")]` to `EscrowController`, or at minimum to the freeze/unfreeze/early-termination actions specifically, since `my-locks`/`{contractId}` reads are legitimately used by businesses/providers viewing their own escrow) — not silently fixed by this documentation pass.

---

## 2. WORKFLOW SPECIFICATIONS

### 2.1 Admin Deposit Workflow (as built)

```
1. ADMIN NAVIGATION
   Admin → Wallet Management (/admin/wallets/all) → search/filter → select wallet row → wallet detail page

2. WALLET DETAIL VIEW (AdminWalletDetailPage.tsx)
   Shows: owner name/type/email, available/locked/pending-withdrawal/total balance, status,
   transaction history (paginated, filterable by type), and — if the owner is a business/provider —
   a linked "suspend/reactivate user account" action independent of the wallet-status action.

3. DEPOSIT INITIATION
   Admin clicks "Deposit" (disabled if wallet is not ACTIVE) → dialog opens

4. DEPOSIT FORM SUBMISSION
   Admin enters: amount (>0), reason (required, dropdown + "Other" free text), description (optional)
   Client-side validation: amount > 0 AND reason non-empty before the button enables
   POST /api/admin/wallets/{walletId}/deposit { amount, currency, description, reason }

5. BACKEND PROCESSING (AdminDepositFundsCommandHandler)
   - Validate wallet exists, Status == ACTIVE, currency matches (throws otherwise)
   - Generate reference ADMIN_DEP-{yyyyMMdd}-{seq:D3}; idempotency check by reference
   - Begin DB transaction → WalletLedgerTransaction (type DEPOSIT) → WalletLedgerEntry (CREDIT) →
     wallet.Credit(amount) → SaveChanges + commit
   - Publish AdminDepositCompletedEvent AND a generic WalletCreditedEvent(source: AdminDeposit)

6. EVENT PROCESSING (async, post-commit)
   - WalletAuditEventHandler → WalletEventLog row (actorType=ADMIN, eventType=ADMIN_DEPOSIT_COMPLETED)
   - AdminTransactionNotificationHandler → in-app (if user resolves) + email/SMS (if contact info exists)

7. UI RESPONSE
   Toast: "Deposited {amount} successfully. Ref: {reference}" → wallet + transaction queries invalidated/refetched
```

### 2.2 Admin Withdrawal Workflow (as built)

Same navigation/detail steps as §2.1. Differences from deposit:
- Withdraw button disabled if wallet is not ACTIVE **or** `availableBalance <= 0`
- Client-side: amount must also be `<= wallet.availableBalance` (UI shows an inline "Amount exceeds available balance" warning)
- Backend (`AdminWithdrawFundsCommandHandler`): validates `request.Amount <= wallet.Balance - wallet.LockedBalance`, throws `InsufficientBalanceException` otherwise; debits `wallet.Balance` directly (no `PendingWithdrawalBalance` staging, unlike the user-initiated `WithdrawalRequest` flow in `epic-08-wallet-escrow.md` Story 8.8 — this is an immediate, synchronous internal transfer, not a request/approval queue)
- Reference prefix `ADMIN_WITH-{yyyyMMdd}-{seq:D3}`

### 2.3 Wallet Suspend/Activate Workflow

Not covered by v1.0's narrower scope; confirmed as a real, distinct admin action:
- `POST /api/admin/wallets/{walletId}/status` with `{ action: "SUSPEND" | "ACTIVATE", reason? }` → `UpdateWalletStatusCommand`
- No deposit/withdraw is possible against a `SUSPENDED` wallet (both handlers check `Status == "ACTIVE"`)
- The web UI's "Suspend/Activate" button toggles between the two based on current status; a separate, independent "Suspend/Reactivate User" button (visible only for business/provider-owned wallets) calls `adminUsersService.suspendUser`/`reactivateUser` — this suspends the **user account**, not the wallet, and is a different code path entirely. Do not conflate wallet suspension with account suspension when reading admin actions in an audit log.

### 2.4 Validation Rules Summary

| Validation | Deposit | Withdrawal | Enforced where |
|------------|---------|------------|-----------------|
| Wallet exists | ✅ | ✅ | Handler |
| Wallet status = ACTIVE | ✅ | ✅ | Handler (`BusinessRuleException`) |
| Amount > 0 | ✅ (DTO `[Range(0.01, …)]`) | ✅ (DTO) | DTO validation |
| Amount ≤ available balance | ❌ not checked | ✅ (`Balance - LockedBalance`) | Handler (`InsufficientBalanceException`) |
| Reason provided | ✅ (`[Required, StringLength(100)]`) | ✅ | DTO + client UI |
| Description length ≤ 500 | ✅ (DTO) | ✅ (DTO) | DTO validation |
| Currency matches wallet | ✅ | ✅ | Handler |
| Account type restricted to MAIN | ❌ **not enforced** (§1.1 AWO-002) | ❌ **not enforced** | — |
| Admin authorization | ✅ (`AdminOnly` on controller) | ✅ | `[Authorize(Policy = "AdminOnly")]` |

---

## 3. API ENDPOINTS

All routes below are on `Controllers/Finance/AdminWalletController.cs`, `[Route("api/admin/wallets")]`, `[Authorize(Policy = "AdminOnly")]` at the controller level. **Note the actual route prefix is `api/admin/wallets`** — some other Finance-module docs (e.g. earlier drafts of `epic-08-wallet-escrow.md`) referred to this surface as `api/finance/admin-wallets`; this document reflects the real, running route.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/admin/wallets` | List/filter/search all wallets (pagination, `ownerType`, `accountType`, `status`, `search`) |
| GET | `/api/admin/wallets/platform` | Platform commission/escrow summary |
| GET | `/api/admin/wallets/statistics` | Admin dashboard statistics |
| GET | `/api/admin/wallets/{walletId}` | Single wallet detail |
| GET | `/api/admin/wallets/{walletId}/transactions` | Wallet's transaction history (paginated, filterable) |
| GET | `/api/admin/wallets/escrow/transactions` | Cross-business escrow transaction feed |
| POST | `/api/admin/wallets/{walletId}/status` | Suspend/activate a wallet |
| POST | `/api/admin/wallets/{walletId}/deposit` | Admin-direct deposit |
| POST | `/api/admin/wallets/{walletId}/withdraw` | Admin-direct withdrawal |
| GET | `/api/admin/wallets/tax-report` | Withholding tax (WHT) report |

### 3.1 Admin Deposit Endpoint

**Endpoint:** `POST /api/admin/wallets/{walletId:guid}/deposit`

**Request Body:**
```json
{
  "amount": 5000.00,
  "currency": "ETB",
  "description": "Initial funding for new business account",
  "reason": "Initial funding"
}
```

**Response** (`AdminTransactionResultDto`):
```json
{
  "transactionId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "reference": "ADMIN_DEP-20260220-001",
  "amount": 5000.00,
  "currency": "ETB",
  "completedAt": "2026-02-20T14:30:00Z",
  "updatedBalance": {
    "walletId": "...",
    "ownerId": "...",
    "ownerType": "BUSINESS",
    "balance": 15000.00,
    "lockedBalance": 0.00,
    "currency": "ETB"
  }
}
```

**HTTP Status Codes (confirmed from controller catch blocks):**
- `200 OK` — success
- `400 Bad Request` — validation error or unexpected exception (caught generically)
- `401 Unauthorized` — `UnauthorizedException` (e.g. admin id not resolvable from claims) — not just "not authenticated"
- `404 Not Found` — `NotFoundException` (wallet doesn't exist)
- `409 Conflict` — `BusinessRuleException` (e.g. wallet not ACTIVE, currency mismatch) **or**, for withdrawal only, `InsufficientBalanceException`

### 3.2 Admin Withdraw Endpoint

**Endpoint:** `POST /api/admin/wallets/{walletId:guid}/withdraw` — same request/response shape as deposit, plus `409 Conflict` on `InsufficientBalanceException`.

### 3.3 Predefined Reason Options (confirmed against `admin-wallet-service.ts`)

**Deposit reasons:** "Initial funding" · "Balance correction" · "Refund" · "Promotional credit" · "Other"

**Withdrawal reasons:** "Payout processed" · "Chargeback" · "Balance correction" · "Penalty enforcement" · "Other"

---

## 4. ESCROW ADMIN OPERATIONS: FREEZE / UNFREEZE / EARLY TERMINATION

Not part of v1.0's scope (which explicitly excluded "automated settlement operations" and said nothing about escrow disputes). Added here because these are the other real "admin wallet management" actions in the codebase, and because the authorization gap in §1.4/AWO-012 is directly relevant to anyone treating this document as the source of truth for what admins can do.

All endpoints below are on `Controllers/Finance/EscrowController.cs`, `[Route("api/finance/escrow")]`, controller-level `[Authorize]` only (**no `AdminOnly` policy** — see §1.4).

| Method | Path | Purpose | Command |
|--------|------|---------|---------|
| POST | `/api/finance/escrow/{contractId}/freeze` | Freeze an escrow lock during a dispute | `FreezeEscrowCommand(contractId, reason, frozenBy)` |
| POST | `/api/finance/escrow/{contractId}/unfreeze` | Restore a frozen lock | `UnfreezeEscrowCommand(contractId, resolution, unfrozenBy)` |
| POST | `/api/finance/escrow/{contractId}/early-termination` | Process early termination with proration/penalty | `ProcessEarlyTerminationCommand(contractId, terminatedBy, reason, initiatedBy)` |
| POST | `/api/finance/escrow/{contractId}/retry` | Retry a failed escrow lock (BR-011) | `RetryEscrowLockCommand` |
| POST | `/api/finance/escrow/{contractId}/release` | Full release (provider/commission/refund split) | `ReleaseEscrowCommand` |
| POST | `/api/finance/escrow/{contractId}/partial-release` | Partial release | `PartialReleaseEscrowCommand` |

### 4.1 Freeze (`FreezeEscrowCommandHandler`)

- Finds the contract's active lock (`Status IN (LOCKED, PARTIALLY_RELEASED)`); no active lock → returns a failure result (not an exception)
- Already `DISPUTED` → returns success with "Escrow is already frozen" (idempotent, not an error)
- On success: `escrowLock.Freeze()` (→ `DISPUTED`), records a `WalletEventLog` (`ESCROW_FROZEN`, `actorId = frozenBy`, note includes the reason and frozen amount) — **no notification is sent** to either party on freeze (confirmed: no `IMediator.Publish` call and no wired frontend toast beyond the raw API response)

### 4.2 Unfreeze (`UnfreezeEscrowCommandHandler`)

- Restores the lock from `DISPUTED` back to `LOCKED` or `PARTIALLY_RELEASED` depending on whether any amount had previously been released
- Same audit-log-only pattern as freeze; no notification wired

### 4.3 Early Termination (`ProcessEarlyTerminationCommandHandler`)

Computes and applies, in one DB transaction:
```
totalDays  = (contract.EndDate - contract.StartDate).Days, floored to minimum 1
usedDays   = min((now - contract.StartDate).Days, totalDays)
dailyRate  = contract.TotalContractValue / totalDays
usedAmount = dailyRate × usedDays

remainingValue = escrowLock.Amount   // actual locked amount, not recomputed
penalty        = MasterData.ContractPolicies.CalculatePenaltyAsync("EARLY_TERMINATION", remainingValue)
refund         = remainingValue − penalty

commissionRate      = weighted-average of contract.LineItems[].CommissionRate by TotalAmount
                       (falls back to 0.08 if the contract has no line items — a defensive default,
                       not documented in any policy)
platformCommission  = usedAmount × commissionRate
providerSettlement  = usedAmount − platformCommission
```
Ledger writes (one `WalletLedgerTransaction`, type `EARLY_TERMINATION`, reference `TRM-{yyyyMMdd}-{random6}`): DEBIT full locked amount from escrow; CREDIT business MAIN (refund, if >0); CREDIT provider MAIN (settlement, if >0); CREDIT platform wallet, looked up by `AccountType == "PLATFORM_COMMISSION"` (commission + penalty combined). Two `CommissionEntry` rows recorded (`CONTRACT_COMMISSION`, `PENALTY`). Blocked entirely if the lock is already `DISPUTED`. A `WalletEventLog` (`EARLY_TERMINATION_PROCESSED`) is written; again, **no notification** is sent to business/provider/admin.

**Cross-reference — platform wallet lookup inconsistency:** this handler looks up the platform wallet by `AccountType == "PLATFORM_COMMISSION"`, while `ReleaseEscrowCommandHandler` (regular full release) looks up `OwnerType == "PLATFORM" && AccountType == "COMMISSION"` and `ApproveSettlementPayoutCommandHandler` (settlement approval — see `SETTLEMENT_ENHANCEMENTS_ADDENDUM.md`) creates/looks up a wallet with `AccountType == "COMMISSION"` too. If these three code paths ever run against a fresh database in a different order, they could create **two different platform commission wallet rows** instead of sharing one. This is the same inconsistency already flagged in `14_Wallet_Engine_Flow_Specification.md` §8 and `project-docs/18_Implementation_Coverage_Audit.md` §10.5 — repeated here because it directly affects early-termination correctness, not just release.

### 4.4 What's Missing (confirmed absent, not just undocumented)

- **No dedicated admin dispute console.** No web page calls freeze/unfreeze/early-termination (confirmed: no hits for `freeze`, `unfreeze`, or `early-termination` anywhere under `movello-marketplace-core/src/features/admin/`). These are API-only today.
- **No notifications** on freeze, unfreeze, or early-termination completion to either the business or the provider — confirmed by reading all three handlers; none publish a notification-bound event.
- **No dispute-engine entity** backs the `DISPUTED` status — it is purely an `EscrowLock`/`Contract` status value reached via this API, with no case/ticket/investigation record anywhere (consistent with `project-docs/18_Implementation_Coverage_Audit.md` §5's finding that no dispute-engine entity exists anywhere in the backend).

---

## 5. AUDIT REQUIREMENTS

- **Table:** `wallet.wallet_event_logs` (corrected from v1.0's `wallet_event_log`)
- **Written by:** `WalletAuditEventHandler` (admin deposit/withdraw) and directly inline by the escrow command handlers (freeze/unfreeze/early-termination — these write `WalletEventLog` rows synchronously inside the same handler, not via a separate event-driven audit handler)
- **Fields:** `WalletAccountId?`, `TransactionId?`, `EventType` (upper-cased on write), `Description?`, `EventPayload` (JSON blob — free-form per event type), `ActorId?`, `ActorType` (upper-cased; `"ADMIN"` for both deposit/withdraw and escrow actions, `"SYSTEM"` for background-triggered events elsewhere in Finance)
- **No UI reads this table directly today** — the admin wallet transaction views (`AdminWalletDetailPage.tsx`) show `WalletLedgerTransaction`/`WalletLedgerEntry` rows (the financial ledger), not `WalletEventLog` rows (the audit/event log); the two are separate tables serving separate purposes, and there is no dedicated "audit log" page in the admin web app that surfaces `wallet_event_logs` for browsing.

---

## 6. AUTHORIZATION & SECURITY — INCLUDING A CONFIRMED GAP

| Surface | Policy enforced | Confirmed |
|---------|------------------|-----------|
| `AdminWalletController` (deposit/withdraw/status/list/statistics/tax-report) | `[Authorize(Policy = "AdminOnly")]`, controller-level | ✅ |
| `AdminDirectRentalController` (unrelated feature, same pattern) | `[Authorize(Policy = "AdminOnly")]` | ✅ (for comparison — see `MVP_DIRECT_RENTAL_SPECIFICATION.md`) |
| `EscrowController` (freeze/unfreeze/early-termination/lock/release/retry) | `[Authorize]` only — **no role restriction** | ❌ gap, see §1.4 AWO-012 |

**Recommendation (engineering ticket, not a doc fix):** add `[Authorize(Policy = "AdminOnly")]` to the freeze/unfreeze/early-termination actions on `EscrowController` (and arguably `retry`/`release`/`partial-release`/`lock`, though those may have legitimate system-to-system or business-initiated call sites worth checking before locking down — `my-locks` and the by-contract GET should stay open to the owning business/provider). Until fixed, the fact that only admins have ever been given a UI path to these actions is a convention, not an enforced boundary.

---

## 7. NOTIFICATION REQUIREMENTS

| Event | In-app | Email | SMS | Confirmed |
|-------|--------|-------|-----|-----------|
| Admin deposit completed | ✅ if user account resolves | ✅ if email on file | ✅ if phone on file | `AdminTransactionNotificationHandler` |
| Admin withdrawal completed | ✅ if user account resolves | ✅ if email on file | ✅ if phone on file | same handler |
| Wallet suspended/activated | ❌ not found | ❌ | ❌ | no handler located for `UpdateWalletStatusCommand` |
| Escrow frozen/unfrozen | ❌ | ❌ | ❌ | confirmed absent, §4.4 |
| Early termination processed | ❌ | ❌ | ❌ | confirmed absent, §4.4 |

Templates used for the two confirmed notification events: `admin_wallet_deposit_inapp`/`_email`/`_sms`, `admin_wallet_withdrawal_inapp`/`_email`/`_sms` (via `INotificationPublisher`, `serviceName: "finance"`).

---

## 8. FRONTEND UI (AS BUILT)

| Page | Route | What it does |
|------|-------|---------------|
| `AllWalletsPage.tsx` | `/admin/wallets/all` | Every wallet, all owner/account types, search/filter |
| `AdminWalletDetailPage.tsx` | `/admin/wallets/:walletId` | Single wallet drill-down: balance cards, transaction table (paginated, type filter), Deposit/Withdraw/Suspend-Activate dialogs, linked user-account suspend/reactivate action |
| `PlatformWalletDashboard.tsx` | `/admin/wallets/platform` | Platform commission/escrow wallet overview |
| `EscrowTransactionsPage.tsx` | `/admin/wallets/escrow-transactions` | Cross-business escrow ledger view (read-only) |
| `EscrowWalletManagementPage.tsx` | `/admin/wallets/escrow` | Escrow-specific admin tooling (read-oriented; does not expose freeze/unfreeze/early-termination — see §4.4) |
| `AdminBusinessEscrowWalletsPage.tsx` | `/admin/wallets/business-escrow` | All businesses' ESCROW wallets |
| `WithholdingTaxPage.tsx` | `/admin/wallets/tax-report` | WHT report export |

Deposit/Withdraw dialogs (both embedded in `AdminWalletDetailPage.tsx`): amount input, reason `Select` (predefined + "Other" free text), optional description `Textarea`, live "new balance" preview implied by the post-mutation refetch (not a pre-submit calculated preview, unlike v1.0's workflow description which implied the UI shows "New balance: {current ± amount}" before confirming — the current UI shows the *current* available balance in the withdraw dialog's description text, not a computed post-transaction preview).

---

## 9. KNOWN GAPS & CLEANUP ITEMS

Confirmed absent or inconsistent during this rewrite — flagged for an engineering decision, not fixed by this documentation pass:

1. **Escrow freeze/unfreeze/early-termination are not restricted to admins at the API layer** (§1.4, §6) — the single most consequential finding in this pass, since it's the one place where "admin wallet operations" as a concept isn't actually admin-only in the running system.
2. **No dedicated freeze/unfreeze/early-termination admin UI** — API-only (§4.4).
3. **No notifications on freeze/unfreeze/early-termination** — parties learn about disputes and terminations only by seeing the resulting ledger entries, not via any push/email/SMS.
4. **Platform commission wallet lookup uses inconsistent `AccountType` strings** across `ProcessEarlyTerminationCommandHandler` (`PLATFORM_COMMISSION`), `ReleaseEscrowCommandHandler` (`OwnerType=PLATFORM, AccountType=COMMISSION`), and `ApproveSettlementPayoutCommandHandler` (`AccountType=COMMISSION`) — risk of creating duplicate platform wallets (§4.3; also see `14_Wallet_Engine_Flow_Specification.md` §8 and the settlement addendum).
5. **Admin deposit/withdraw is not restricted to MAIN wallets** (§1.1 AWO-002) — confirm with product whether this breadth is intentional (a genuinely useful correction tool for escrow/commission wallets) or should be locked down.
6. **`wallet_event_logs` has no dedicated browsing UI** — it's a real, populated audit table with no admin page reading it directly (§5).

---

**END OF SPECIFICATION**
