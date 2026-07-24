# Finance Module — Specification

**Module Name:** Finance
**Version:** 2.0 (rewritten against running code)
**Last verified against code:** 2026-07-23
**Location:** `Modules/Finance/**` inside `Marketplace.API` (.NET 9 modular monolith) — this is a folder/namespace inside one deployable, not a separate "Wallet Engine" or "Settlement Engine" service
**Related documents:** `backlog/mvp/epic-08-wallet-escrow.md` (wallet/escrow user stories), `backlog/mvp/epic-09-daily-ledger-billing.md` (daily accrual + VAT invoice/WHT reclaim), `backlog/mvp/epic-10-monthly-renewal-settlement.md` (settlement cycle/payout), `project-docs/service-specs/14_Wallet_Engine_Flow_Specification.md` (full step-by-step pipeline with code snippets)

---

## What changed in this rewrite

Prior drafts of the Finance/Wallet documentation described a standalone "Wallet Engine" microservice with its own Postgres schema, talking to a separate "Contract Service"/"Settlement Engine"/"Delivery Engine" over a message bus, with payment gateways as an external "future" dependency. None of that is true of the running system. This rewrite corrects the record on every point below, verified directly against `Modules/Finance/**`:

1. **Not a microservice.** One deployable (`Marketplace.API`), one process, one PostgreSQL database. Finance's tables live under EF Core `Schema = "wallet"` (a schema-level grouping, not a separate data store) alongside a handful under `Schema = "delivery"`/default for other modules. Cross-module communication (`ContractCreatedEvent`, `DeliveryConfirmedEvent`, `BidAwardedEvent`) is in-process MediatR `INotificationHandler` dispatch, not a broker.
2. **Payment gateways are live, not future work.** Chapa, Telebirr, and CBE Birr all have real webhook-validated integrations today (`Infrastructure/Payments/`).
3. **Settlement cadence is a flat, per-contract rolling 30-day window — not tier-based.** This directly resolves the contradiction flagged in `project-docs/18_Implementation_Coverage_Audit.md` §10.4 between the (now-superseded) wallet-cluster draft and the ledger/settlement-cluster draft. Reading `Modules/Finance/Application/Services/SettlementScheduleService.cs` and `Modules/Finance/Application/Settlement/Commands/GenerateSettlementCommand.cs` directly settles it: `SettlementScheduleService.GenerateSchedule()` produces fixed, inclusive 30-day cycles anchored to the contract's first-delivery date, with **zero tier branching** anywhere in the method. `GenerateSettlementCommand`'s doc-comment still asserts "Bronze/Silver: Monthly (1st), Gold: Bi-weekly (1st,15th), Platinum: Weekly (Monday)" (BR-FN-03) — that comment is stale/aspirational and describes behavior that was never implemented; the command's actual query logic only filters `MonthlySettlementSchedule` rows by `Status == "PENDING" AND SettlementDate <= EndDate`, with an optional `ProviderTierFilter` that merely narrows *which providers'* already-due payouts a given admin-triggered run processes — it does not change *when* a cycle becomes due. **Treat the 30-day rolling window as ground truth; treat every tier-cadence claim (including this module's own code comments) as incorrect until someone actually implements it.**
4. **A fourth escrow-adjacent subsystem — refund requests — is fully modeled and completely unreachable.** `RefundRequest` (`PENDING_REVIEW → APPROVED | REJECTED → PROCESSING → PROCESSED`) plus its three command handlers (`CreateRefundRequestCommand`, `ReviewRefundRequestCommand`, `ProcessRefundCommand`) are fully implemented — but a repo-wide search found **zero controller or event-handler call sites for any of the three commands**, anywhere in the backend. This was not called out in any prior doc pass. See Known Gaps.
5. **Escrow rollover between settlement cycles is real and wired**, not a documentation placeholder: `EscrowRollover` rows are created inside `LockNextCycleEscrowCommandHandler` (called from `ApproveSettlementPayoutCommand` on every non-final settlement approval) to carry unused escrow from one 30-day cycle into the next, with an excess-refund path if the rollover exceeds the next cycle's requirement.

---

## Overview

### Purpose

The Finance module owns every fund movement on the platform: wallet accounts, escrow lock/release/freeze/early-termination, manual and gateway-based deposits, withdrawals, the daily ledger accrual job, settlement cycle/payout generation and admin approval, commission tracking, and the provider VAT-invoice/withholding-tax-reclaim flow. It does not compute commission-tier rates or contract policy rules (MasterData — Finance only *reads* those), does not own the contract lifecycle (Contracts module — Finance *reacts* to `ContractCreatedEvent`), and does not run OTP delivery verification (Delivery module — Finance's own delivery-confirmation handler is deliberately a no-op for money movement).

### Two subsystems, one module

**A. Wallet & Escrow** (epic-08 territory): `WalletAccount`, `EscrowLock`, `EscrowRollover`, `DepositRequest`, `WithdrawalRequest`, `PaymentIntent`, `RefundRequest`, `PlatformBankAccount`, `WalletLedgerTransaction`/`WalletLedgerEntry`, `WalletEventLog`, `WalletBalanceSnapshot`. Covers account creation, manual bank-transfer deposits, automated Chapa/Telebirr/CBE Birr top-ups, escrow lock at contract creation, release/partial-release/freeze/unfreeze, early termination, and withdrawal-to-bank for both businesses and providers.

**B. Daily Ledger & Settlement** (epic-09/epic-10 territory): `MonthlySettlementSchedule`, `SettlementCycle`, `SettlementPayout`, `SettlementPayoutLineItem`, `SettlementStatusHistory`, `CommissionEntry`, `ProviderInvoice`. Covers the nightly per-contract accrual job, 30-day settlement-schedule generation, admin-approved payout double-entry posting, and the provider-submitted VAT-invoice reclaim of withheld tax.

Both subsystems share the same double-entry ledger primitives (`WalletLedgerTransaction`/`WalletLedgerEntry`) and the same `IFinanceUnitOfWork`.

### Responsibilities

**Wallet lifecycle**
- Auto-creation of `MAIN` wallets on business/provider registration; lazy creation of `ESCROW` (per business, on first contract) and `PLATFORM`/`COMMISSION` (singleton, on first commission credit) wallets
- Admin-direct deposit/withdraw/suspend/activate operations, separate from user-initiated flows

**Deposits**
- Manual bank-transfer deposit requests with receipt upload, admin-reviewed (`PENDING_REVIEW → APPROVED | REJECTED`) — wallet is credited only on approval
- Automated Chapa/Telebirr/CBE Birr top-ups via `PaymentIntent`, webhook- and callback-driven, idempotent per transaction reference

**Escrow**
- Automatic lock at `ContractCreatedEvent`, ≤30-day-per-line-item cap, 5-attempt exponential-backoff retry
- Full/partial release with provider/commission/refund split; freeze/unfreeze for disputes; early termination with proration + MasterData-driven penalty + snapshotted commission rate
- Rollover of unused escrow from one 30-day settlement cycle into the next (`EscrowRollover`), with excess-refund handling if the rollover exceeds the next cycle's need

**Withdrawals**
- Provider *and* business withdrawal requests against a verified bank account, funds locked at request time, admin-approved (Chapa transfer or manual bank transfer), retryable on Chapa failure

**Daily ledger**
- Nightly (00:05 UTC) double-entry accrual of provider earnings + platform commission for every contract active that day, using the value-weighted commission rate snapshotted on the contract's own line items

**Settlement**
- 30-day rolling settlement-schedule generation per contract (anchored to first delivery), admin-triggered cycle/payout generation, admin approval gate before any escrow-to-provider money moves, minimum-payout-threshold skip, optional auto-approve-below-threshold

**Tax & invoicing**
- Withholding tax (2% default, MasterData-configurable) deducted from every payout into a dedicated platform `TAX` wallet
- Provider-submitted VAT invoice against completed payouts, admin-approved release of withheld tax back to the provider

**Refunds (modeled, unreachable — see Known Gaps)**
- `RefundRequest` entity and its full three-command workflow exist but have no way to be invoked from any surface today

---

## Database Schema

All tables below use EF Core `Schema = "wallet"` unless noted.

| Table | Purpose |
|---|---|
| `wallet_accounts` | `WalletAccount` — one row per (OwnerId, OwnerType, AccountType) |
| `escrow_locks` | `EscrowLock` — one row per contract's currently/previously locked escrow |
| `escrow_rollovers` | `EscrowRollover` — unused-escrow carry-forward between settlement cycles |
| `deposit_requests` | `DepositRequest` — manual bank-transfer deposit submissions |
| `withdrawal_requests` | `WithdrawalRequest` — provider/business cash-out requests |
| `payment_intents` | `PaymentIntent` — Chapa/Telebirr/CBE Birr/bank-transfer payment attempts |
| `platform_bank_accounts` | `PlatformBankAccount` — platform's own bank accounts shown to depositors |
| `refund_requests` | `RefundRequest` — modeled but unreachable (no controller anywhere calls its commands) |
| `wallet_ledger_transactions` | `WalletLedgerTransaction` — double-entry transaction header |
| `wallet_ledger_entries` | `WalletLedgerEntry` — individual DEBIT/CREDIT rows |
| `wallet_event_logs` | `WalletEventLog` — key financial event audit (e.g. `EARLY_TERMINATION_PROCESSED`) |
| `wallet_balance_snapshots` | `WalletBalanceSnapshot` — point-in-time balance snapshot entity |
| `monthly_settlement_schedules` | `MonthlySettlementSchedule` — per-contract 30-day cycle schedule |
| `settlement_cycles` | `SettlementCycle` — global (cross-provider) settlement run for a date window |
| `settlement_payouts` | `SettlementPayout` — one payout per provider per cycle |
| `settlement_payout_line_items` | `SettlementPayoutLineItem` — per-contract/per-vehicle breakdown of a payout |
| `settlement_status_history` | `SettlementStatusHistory` — cycle-level status audit trail |
| `commission_entries` | `CommissionEntry` — commission/penalty audit rows; only populated by refund, early-termination, and partial-release edge cases, **not** by the normal daily-accrual or settlement paths |
| `provider_invoices` | `ProviderInvoice` — VAT invoices submitted by providers to reclaim withheld tax |

---

## Module Structure (actual folders)

```
Modules/Finance/
├── Domain/
│   ├── Entities/
│   │   ├── WalletAccount.cs, EscrowLock.cs, EscrowRollover.cs
│   │   ├── DepositRequest.cs, WithdrawalRequest.cs, PaymentIntent.cs
│   │   ├── PlatformBankAccount.cs, RefundRequest.cs (no reachable write path — see Known Gaps)
│   │   ├── WalletLedgerTransaction.cs, WalletLedgerEntry.cs
│   │   ├── WalletEventLog.cs, WalletBalanceSnapshot.cs
│   │   ├── MonthlySettlementSchedule.cs, SettlementCycle.cs
│   │   ├── SettlementPayout.cs, SettlementPayoutLineItem.cs, SettlementStatusHistory.cs
│   │   ├── CommissionEntry.cs
│   │   └── ProviderInvoice.cs
│   ├── Events/ (AdminDepositCompletedEvent, AdminWithdrawalCompletedEvent, DepositCompletedEvent, FinanceNotificationEvents)
│   ├── Repositories/ (one interface per entity above)
│   └── Services/ (ISettlementScheduleService, IWalletCalculationService)
│
├── Application/
│   ├── Wallet/Commands/ (CreateWalletAccount, DepositFunds, WithdrawFunds, AdminDepositFunds, AdminWithdrawFunds, InitiateWithdrawal, UpdateWalletStatus)
│   ├── Wallet/Queries/ (GetWalletByOwner, GetWalletById, GetWalletBalance, GetWalletSummary, GetWalletTransactions, GetAllWallets, GetPlatformWallet(Accounts), GetWalletStatistics, GetWithholdingTaxReport)
│   ├── Wallet/EventHandlers/ (AdminTransactionNotificationHandler, WalletAuditEventHandler)
│   ├── Escrow/Commands/ (LockEscrow, RetryEscrowLock, ReleaseEscrow, PartialReleaseEscrow, FreezeEscrow, UnfreezeEscrow, ProcessEarlyTermination, LockNextCycleEscrow)
│   ├── Escrow/Queries/ (GetEscrowByContract, GetMyEscrowLocks, GetAdminEscrowTransactions)
│   ├── DepositRequest/Commands/ (SubmitDepositRequest, ApproveDepositRequest, RejectDepositRequest) + Queries
│   ├── Withdrawal/Commands/ (RequestWithdrawal, ApproveWithdrawalRequest, RejectWithdrawalRequest, ProcessWithdrawalViaBankTransfer, RetryWithdrawalRequest) + Queries
│   ├── Payment/Commands/ (CreatePaymentIntent, HandleChapaCallback, HandleChapaTransferApproval, ProcessPaymentWebhook)
│   ├── Refund/Commands/ (CreateRefundRequest, ReviewRefundRequest, ProcessRefund — all unreachable, see Known Gaps)
│   ├── PlatformBankAccount/Commands+Queries/ (Create, Update, Delete, ToggleStatus)
│   ├── Ledger/Commands/ (ProcessDailyLedgerCommand)
│   ├── Billing/Commands/ (ProcessMonthlyBillingCommand — legacy name; superseded in practice by the Settlement subsystem below)
│   ├── Settlement/Commands/ (GenerateSettlementSchedule, GenerateSettlement, ApproveSettlementPayout, RejectSettlementPayout, ProcessPayout)
│   ├── Settlement/Queries/ (GetMySettlements, GetAllSettlementPayouts, GetSettlementPayoutDetail, GetSettlementCycles, GetSettlementScheduleStates, GetSettlementStatusHistory, GetProviderEarnings, GetProviderUpcomingSettlements)
│   ├── Invoice/Commands/ (SubmitProviderInvoice, MarkInvoiceReceived, ApproveProviderInvoice, RejectProviderInvoice) + Queries
│   ├── Reports/Queries/ (GetCommissionReportQuery, GetTaxReportQuery, GetSettlementReportQuery, GetEscrowReportQuery — all four fully implemented, **zero controller references anywhere** — see Known Gaps)
│   ├── EventHandlers/ (BusinessRegisteredWalletHandler, ProviderRegisteredWalletHandler, UserAccountCreatedWalletHandler, FinanceBidAwardedEventHandler, ContractCreatedEventHandler, FinanceDeliveryConfirmedEventHandler)
│   └── Services/ (SettlementScheduleService, WalletCalculationService)
│
└── Infrastructure/
    ├── Configurations/FinanceConfigurations.cs (EF Core mappings, `Schema = "wallet"`)
    ├── Payments/ (ChapaPaymentProvider, TelebirrPaymentProvider, CBEBirrPaymentProvider, PaymentServiceFactory, PaymentProviderOptions)
    └── Repositories/ (one per Domain/Repositories interface)
```

Controllers live outside the module folder, under `Controllers/Finance/` (`WalletController`, `EscrowController`, `DepositRequestController`, `WithdrawalController`, `PaymentController`, `SettlementController`, `ProviderInvoiceController`, `AdminWalletController`, `AdminBankController`), `Controllers/PlatformBankAccountController.cs`/`Controllers/Admin/AdminPlatformBankAccountController.cs`, and `Controllers/Mobile/MobileWalletController.cs`/`MobilePaymentController.cs`. **No controller anywhere references the `RefundRequest` commands or the four `Reports/Queries` handlers** — see Known Gaps.

---

## Core Entities (field-level)

### WalletAccount
- `OwnerId`, `OwnerType` (`USER`|`BUSINESS`|`PROVIDER`|`PLATFORM`), `AccountType` (`MAIN`|`ESCROW`|`COMMISSION`|`TAX`), `Currency` (default `USD` at the entity level, but every real code path passes `ETB`)
- `Balance`, `LockedBalance` (defined but not the mechanism used for escrow — escrow is a separate real wallet row, not a flag on this field), `PendingWithdrawalBalance`
- `Status` (`ACTIVE`|`SUSPENDED`|`CLOSED`), `IsActive`, `RowVersion` (optimistic concurrency)
- Domain methods are the *only* way balances change: `Credit`, `Debit`, `LockForWithdrawal` (debits `Balance`, credits `PendingWithdrawalBalance`), `UnlockWithdrawal` (reverses on rejection), `FinalizeWithdrawal` (clears the pending amount once completed), `Suspend`/`Activate`

### EscrowLock
- `WalletAccountId` (must be an `ESCROW`-type account), `ContractId`, `OriginalAmount`, `Amount` (remaining locked), `ReleasedAmount`
- `Status` (`LOCKED`|`PARTIALLY_RELEASED`|`RELEASED`|`DISPUTED`|`FORFEITED`), `LockedAt`, `ReleasedAt`, `ReleaseReason`
- `PartialRelease()` reduces `Amount`/increments `ReleasedAmount`, auto-flips to `RELEASED` at zero; `Release()` releases everything at once; `Freeze()` only valid from `LOCKED`/`PARTIALLY_RELEASED`; `Unfreeze()` restores to `LOCKED` or `PARTIALLY_RELEASED` depending on whether `Amount == OriginalAmount`; `Forfeit(reason)` exists but has no confirmed caller found in this pass

### EscrowRollover
- `ContractId`, `FromCycleNumber`, `ToCycleNumber`, `Amount` (carried forward), `ExcessRefunded`, `Status` (`AVAILABLE`|`APPLIED`|`EXCESS_REFUNDED`), `AppliedToEscrowLockId`, `AppliedAt`
- Created inside `LockNextCycleEscrowCommandHandler` (called from `ApproveSettlementPayoutCommand` on every non-final settlement approval) — real and wired, not a placeholder entity

### WalletLedgerTransaction / WalletLedgerEntry
- Transaction: `Reference` (e.g. `ESC-20260723-0001`, `REL-…`, `TRM-…`), `TransactionType` (`DEPOSIT`|`WITHDRAWAL`|`ESCROW_LOCK`|`ESCROW_RELEASE`|`ESCROW_EXCESS_REFUND`|`SETTLEMENT`|`DAILY_ACCRUAL`|`WITHHOLDING_RELEASE`|`EARLY_TERMINATION`|…), `TransactionDate`, `TotalAmount`, `Currency`, `Description`, `ReferenceId` (contract/RFQ/etc.)
- Entry: `TransactionId`, `WalletAccountId`, `EntryType` (`DEBIT`|`CREDIT`), `Amount`, `RelatedType`, `Notes` — every transaction is paired with balanced debit/credit entries, insert-only, no update path

### DepositRequest
- `OwnerId`/`OwnerType` (`BUSINESS`|`PROVIDER`), `WalletAccountId`, `PlatformBankAccountId`, `Amount`, `Currency`, `TransactionNumber`, `ReceiptUrl`/`ReceiptFileName`
- `Status` (`PENDING_REVIEW`|`APPROVED`|`REJECTED`), `AdminReviewedBy`/`AdminReviewedAt`, `RejectionReason`, `Notes`
- `Approve(reviewedBy)`/`Reject(reason, reviewedBy)` — both hard-require `PENDING_REVIEW` as the starting state; wallet credit happens in the command handler, not inside this domain method

### WithdrawalRequest
- `OwnerId`/`OwnerType` (`PROVIDER`|`BUSINESS`), `WalletAccountId`, `BankAccountId`/`BankAccountType`, `Amount`, `Currency`
- Snapshotted bank details at request time: `BankCode`, `AccountNumber`, `AccountHolderName`, `BankName`
- `TransactionReference`, `GatewayTransactionId` (Chapa), `WalletTransactionId` (links to the `WITHDRAWAL_PENDING` ledger transaction created at request time)
- `Status`: `PENDING_ADMIN_APPROVAL → PENDING_TRANSFER → PENDING → COMPLETED | FAILED | REJECTED`
- `ProcessingMethod` (`CHAPA`|`BANK_TRANSFER`), `AdminReceiptUrl`/`AdminTransactionNumber` (manual path)
- Methods: `MarkPendingTransfer`, `MarkAutoApprovedPendingTransfer` (uses `Guid.Empty` as a system-approval marker), `MarkChapaPending`, `MarkCompleted`, `MarkCompletedViaBankTransfer`, `MarkFailed`, `MarkRetrying` (only from `FAILED`, clears the stale gateway reference), `Reject`, `SetGatewayTransactionId`, `SetWalletTransaction`

### PaymentIntent
- `WalletAccountId`, `TransactionReference`, `GatewayTransactionId`, `Amount`, `Currency`, `PaymentMethod` (`CHAPA`|`TELEBIRR`|`CBE_BIRR`|`BANK_TRANSFER`)
- `Status`: `PENDING → PROCESSING → COMPLETED | FAILED | CANCELLED | EXPIRED` (24-hour default expiry, `IsExpired()` helper)
- `ReturnUrl`, `Metadata`, `FailureReason`, `CompletedAt`/`ExpiresAt`

### RefundRequest (modeled, no reachable write path — see Known Gaps)
- `ContractId`, `BusinessId`, `RequestedBy`, `RequestedAmount`, `ApprovedAmount`, `PenaltyAmount`, `NetRefundAmount`, `Reason`
- `Status`: `PENDING_REVIEW → APPROVED | REJECTED`, then `APPROVED → PROCESSING → PROCESSED`, or `→ CANCELLED`
- `Approve(reviewedBy, approvedAmount, penaltyAmount)`, `Reject(reviewedBy, reason)`, `MarkProcessing()`, `MarkProcessed(transactionId)`, `Cancel()` — the full state machine is implemented and unit-testable, it simply has no caller in production code

### PlatformBankAccount
- `BankName`, `BankCode`, `AccountNumber`, `AccountHolderName`, `Currency`, `IsActive`, `DisplayOrder` — the list businesses/providers choose from when submitting a manual deposit

### MonthlySettlementSchedule
- `ContractId`, `CycleNumber` (1, 2, 3…), `CycleStartDate`/`CycleEndDate` (both inclusive), `SettlementDate` (= `CycleEndDate`), `DailyRate` (`TotalContractValue / totalInclusiveDays`), `DaysInCycle`, `CycleAmount` (`DailyRate × DaysInCycle`)
- `Status`: `PENDING → LOCKED → SETTLED`, or `CANCELLED`; `EscrowLockedAt`/`EscrowLockId`, `SettledAt`, `IsFinalSettlement` (flagged on the last generated cycle; `UnmarkAsFinal()` exists for the contract-extension case)

### SettlementCycle
- `CycleReference` (e.g. `CYC-2026-0723-0822`, optionally suffixed with a contract-number fragment), `StartDate`/`EndDate`, `Status` (`OPEN`|`PROCESSING`|`CLOSED`) — this is the *global*, cross-provider container for a settlement run, not a per-contract entity
- Navigation: `Payouts` (one per provider touched by this run)

### SettlementPayout
- `SettlementCycleId`, `ProviderId`, `WalletAccountId` (provider's MAIN wallet), `TotalAmount` (gross), `CommissionDeducted`, `TaxDeducted`, `NetPayoutAmount` (`TotalAmount − CommissionDeducted − TaxDeducted`)
- `WalletTransactionId`, `InvoiceId` (linked provider invoice, for WHT reclaim), `Status` (`PENDING_ADMIN_APPROVAL → COMPLETED | FAILED`)

### SettlementPayoutLineItem
- `SettlementPayoutId`, `ContractId`/`ContractNumber`, `VehicleId`/`VehiclePlateNumber` (nullable — plate number is not actually populated by the generation handler in this pass, only `VehicleId`), `GrossAmount`, `CommissionAmount`, `CommissionRate`, `NetAmount`, `PeriodStart`/`PeriodEnd`, `DaysInPeriod`

### CommissionEntry
- `ContractId`, `ProviderId`, `SettlementPayoutId`, `GrossAmount`, `CommissionAmount`, `CommissionRate`, `ProviderTierCode`, `CommissionType` (`CONTRACT_COMMISSION`|`PENALTY`|`SUBSCRIPTION`), `Status` (`PENDING`|`SETTLED`|`CANCELLED`), `EarnedAt`/`SettledAt`
- The entity's own doc comment cites tier rates (Bronze 10%/Silver 8%/Gold 6%/Platinum 5%) that **do not match** the rates actually snapshotted onto contract line items at bid-award time from MasterData (Platinum 3%/Gold 4%/Silver 5%/Bronze 7%/Red Zone 10%, base 5% — see `[[movello_business_overview]]`) — an unreconciled discrepancy inside the codebase itself. `CommissionEntry.Create()` is only called from `ProcessRefundCommand` (itself unreachable — see Known Gaps), `ProcessEarlyTerminationCommand`, and `PartialReleaseEscrowCommand`. The normal daily-accrual and settlement-generation paths never create a `CommissionEntry` row — they record commission purely through `WalletLedgerEntry` double-entries and `SettlementPayoutLineItem.CommissionAmount`.

### ProviderInvoice
- `ProviderId`, `InvoiceNumber`, `InvoiceDate`, `InvoiceAmount` (must equal the sum of linked payouts' `NetPayoutAmount`), `ScanUrl`
- `Status`: `PENDING → RECEIVED (optional) → APPROVED | REJECTED`; `IsReceivedByFinance`, `ApprovedBy`/`ApprovedAt`, `RejectedReason`, `UploadedBy`/`UploadedAt`
- `MarkReceived()` (only from `PENDING`), `Approve(approvedBy, notes)` (from `PENDING` or `RECEIVED`), `Reject(reason, rejectedBy)` (blocked once `APPROVED`)

---

## Key Workflows

### 1. Wallet creation
`BusinessRegisteredWalletHandler`/`ProviderRegisteredWalletHandler`/`UserAccountCreatedWalletHandler` create a `MAIN` wallet (Balance 0, `ACTIVE`) on registration. `ESCROW` and `PLATFORM`/`COMMISSION` wallets are created lazily on first use, not provisioned up front.

### 2. Manual bank-transfer deposit
Business/provider selects a `PlatformBankAccount`, submits amount + transaction number + receipt (multipart) → `DepositRequest` (`PENDING_REVIEW`, no credit yet) → admin `Approve` (credits wallet) or `Reject` (reason recorded, no credit).

### 3. Automated gateway deposit (Chapa/Telebirr/CBE Birr)
`CreatePaymentIntentCommand` creates a `PaymentIntent` and returns a checkout URL/reference. Completion arrives via provider-specific webhook (`ProcessPaymentWebhookCommand`, signature-validated per provider) and/or, for Chapa, a synchronous return-URL callback (`HandleChapaCallbackCommand`) — both paths are idempotent on transaction reference, and a `COMPLETED` status poll (`GET /api/payments/status/{ref}`) can also trigger crediting as a fallback if the webhook hasn't landed.

### 4. Escrow lock at contract creation
`ContractCreatedEventHandler` computes `Σ line item (UnitAmount × QuantityAwarded × min(DurationDays, 30))`, validates the business `MAIN` wallet balance, and — with 5-attempt exponential backoff (1/2/4/8/16s) — debits `MAIN`/credits `ESCROW` (get-or-create) as one double-entry transaction, creates the `EscrowLock` (`LOCKED`), and calls `contract.ActivateAfterEscrowLock()`. After 5 failures the contract is marked `ESCROW_LOCK_FAILED`; an admin retries via `POST /api/finance/escrow/{contractId}/retry`. A second, parallel path (`FinanceBidAwardedEventHandler`, subscribed to `BidAwardedEvent`, using MasterData's `EscrowPolicyRule` instead of the hardcoded 30-day cap) almost always finds no contract yet and exits without locking — in practice only the `ContractCreatedEvent` path ever executes the real lock. This divergence (two computation paths, only one live) is a known cleanup item, not a doc error.

### 5. Delivery confirmation — financially inert
`FinanceDeliveryConfirmedEventHandler` (subscribed to the Delivery module's `DeliveryConfirmedEvent`) only verifies the escrow lock is still `LOCKED` and logs it. No money moves. Daily ledger accrual is a separately scheduled job, not triggered by this handler.

### 6. Daily ledger accrual
`DailyLedgerJob` (hosted `BackgroundService`) computes the delay to the next 00:05 UTC and fires once per day. `ProcessDailyLedgerCommand` selects contracts where `Status == "ACTIVE" AND StartDate.Date <= today <= EndDate.Date`, computes the value-weighted commission rate across the contract's line items (falling back to 8% flat only if the contract has no line items), and posts two `DAILY_ACCRUAL` double-entry transactions per contract (escrow → provider MAIN for earnings; escrow → platform COMMISSION for commission), skipping amounts ≤ 0. The whole day's batch runs in **one** DB transaction — any single contract's failure rolls back the entire run, with no per-contract retry until the next scheduled run.

### 7. Settlement schedule generation
At contract creation/first-delivery, `SettlementScheduleService.GenerateSchedule()` walks the contract's date range in fixed 30-day inclusive windows (last window capped at `EndDate`, short contracts get one cycle), computing `DailyRate = TotalContractValue / totalInclusiveDays` and `CycleAmount = DailyRate × DaysInCycle` per cycle, flagging the last one `IsFinalSettlement`.

### 8. Settlement cycle/payout generation (admin-triggered)
`POST /api/finance/settlements/generate` (date-range mode) or `.../generate-current-cycle` (only-the-one-processable-cycle-per-contract mode) runs `GenerateSettlementCommand`: groups all due `PENDING` schedules by provider (via their contract), computes per-vehicle earnings within the cycle window (`ContractVehicleAssignment.DeliveredAt`/`ReleasedAt` windowed against cycle dates), skips a provider whose gross falls below the minimum-payout threshold (MasterData setting, default 100 ETB), deducts withholding tax (MasterData `WITHHOLDING_TAX_RATE`, default 2%) from the post-commission net, and creates one `SettlementPayout` (`PENDING_ADMIN_APPROVAL`) with per-contract/per-vehicle `SettlementPayoutLineItem`s. **No wallet movement happens at generation time** — that's deferred entirely to approval. An optional `SETTLEMENT_AUTO_APPROVE_THRESHOLD` (disabled by default) auto-approves payouts at or below the threshold immediately after generation.

### 9. Settlement payout approval (the only point money actually moves for settlement)
`ApproveSettlementPayoutCommand`, per contract touched by the payout:
- **Transaction A ("SETTLEMENT"):** DEBIT business ESCROW (gross), CREDIT provider MAIN (net), CREDIT platform COMMISSION (commission), CREDIT platform TAX (withheld tax)
- **Transaction B:** if this is the contract's final cycle, refund unused escrow (`lockedAmount − contractGross`) to business MAIN and release the lock; otherwise release the current lock and immediately lock the unused amount toward the next cycle via `LockNextCycleEscrowCommand` (creating an `EscrowRollover` row), falling back to a refund if there's no next cycle
- On success: payout → `COMPLETED`, schedules → `SETTLED`, `SettlementPayoutApprovedEvent`/`WalletCreditedEvent` published. On any failure: full rollback, payout → `FAILED`, no automatic retry.

### 10. Withdrawal (provider or business)
`RequestWithdrawalCommand`: `wallet.LockForWithdrawal(amount)` (debits `Balance`, credits `PendingWithdrawalBalance` immediately) → `WithdrawalRequest.Create()` (`PENDING_ADMIN_APPROVAL`, snapshotting the verified bank account). Admin approves → Chapa transfer (`PENDING_TRANSFER → PENDING`, webhook confirms → `COMPLETED`) or manual bank transfer (`MarkCompletedViaBankTransfer`, straight to `COMPLETED`). Admin rejects → `wallet.UnlockWithdrawal()` refunds `Balance`. A `FAILED` Chapa transfer is retryable (`MarkRetrying`, re-debits without double-refunding since the original debit already happened at request time).

### 11. Escrow freeze/unfreeze & early termination
`FreezeEscrowCommand`/`UnfreezeEscrowCommand` move the lock to/from `DISPUTED` (no money moves during a freeze; release and early-termination are both blocked while frozen). `ProcessEarlyTerminationCommand` computes days-used proration against the contract's total days, a MasterData-driven penalty (`EARLY_TERMINATION` policy), and a provider settlement using the contract's own **snapshotted, weighted-average line-item commission rate** (not the provider's current tier) — writing a single `EARLY_TERMINATION` transaction that debits the full locked escrow and credits business (refund), provider (settlement), and platform (commission + penalty combined), plus two `CommissionEntry` rows.

### 12. Provider VAT invoice / withholding-tax reclaim
Provider selects one or more of their own `COMPLETED` payouts not already linked to another invoice, submits `POST /api/finance/invoices` with an amount that must equal `Σ payouts.NetPayoutAmount` to the cent. Finance/admin optionally marks it `RECEIVED`, then `Approve`s (releases `Σ payouts.TaxDeducted` from the platform TAX wallet to the provider MAIN wallet via a `WITHHOLDING_RELEASE` transaction) or `Reject`s (reason required, blocked once approved).

---

## Known Gaps (verified by code search, zero call sites found for each)

1. **`RefundRequest`'s entire workflow is unreachable.** `CreateRefundRequestCommand`, `ReviewRefundRequestCommand`, and `ProcessRefundCommand` are fully implemented (with validators) but have **zero references from any controller or event handler** in the backend — confirmed by searching every file under `Controllers/` and `Modules/**/EventHandlers/`. A business or admin cannot trigger a refund request through any API route today; the only real "refund" money movement is the optional refund leg inside `ReleaseEscrowCommand`/`ProcessEarlyTerminationCommand`, which is a different code path entirely.
2. **Four admin reporting queries are dead.** `GetCommissionReportQuery`, `GetTaxReportQuery`, `GetSettlementReportQuery`, `GetEscrowReportQuery` (`Modules/Finance/Application/Reports/Queries/`) are fully implemented but **zero controllers reference any of them**. The live-looking `GET /api/finance/admin-wallets/tax-report` endpoint actually calls the differently-named `GetWithholdingTaxReportQuery` — an unrelated implementation with an overlapping purpose, not `GetTaxReportQuery`.
3. **Two escrow-lock computation paths coexist; only one runs.** `FinanceBidAwardedEventHandler` (MasterData `EscrowPolicyRule`-driven) almost always finds no contract yet at the point `BidAwardedEvent` fires and exits without locking; `ContractCreatedEventHandler` (hardcoded 30-day cap) is what actually locks escrow in practice. Worth a cleanup ticket, not a functional bug today.
4. **Platform commission wallet lookup is inconsistent across handlers.** `ReleaseEscrowCommandHandler` queries `OwnerType == "PLATFORM" && AccountType == "COMMISSION"`; `ProcessEarlyTerminationCommandHandler` queries `AccountType == "PLATFORM_COMMISSION"`. On a fresh database these create two different platform wallet rows instead of sharing one.
5. **`WalletAccount.AccountType` includes `TAX`**, and settlement approval does credit a platform TAX wallet correctly — but no other traced code path debits/credits it outside the settlement-approval/WHT-release pair; there is no general-purpose "tax wallet" transaction type beyond that specific flow.
6. **`CommissionEntry`'s tier-rate doc comment (Bronze 10%/Silver 8%/Gold 6%/Platinum 5%) does not match the tier rates actually snapshotted onto contract line items** (Platinum 3%/Gold 4%/Silver 5%/Bronze 7%/Red Zone 10%) — two disagreeing rate tables exist in the codebase itself, not just across docs.
7. **`CommissionEntry` is only populated for refund/early-termination/partial-release edge cases** — the normal daily-accrual and settlement-generation paths never write one, so "commission earned" has two parallel, not-fully-reconciled representations in the database (`WalletLedgerEntry`/`SettlementPayoutLineItem` vs. the rarely-used `CommissionEntry`).
8. **No settlement dispute mechanism exists.** No `POST /settlements/{id}/dispute` endpoint, no dispute entity, no adjustment/recalculation path — a provider who believes a payout is wrong has no in-product recourse beyond the unrelated invoice approve/reject flow.
9. **`SettlementCycle`'s modeled `USER_CLOSE`/`USER_REOPEN`/`USER_CANCEL`/`USER_LOCK`/`USER_UNLOCK` status-history triggers have no controller endpoints** to invoke them — only generation and payout approve/reject are reachable via API.
10. **A failed settlement approval leaves a payout `FAILED` with no automatic retry**, and if the failure happens mid-rollover, a contract's next-cycle escrow lock may be left partially incomplete — an admin must re-attempt by hand.
11. **No proactive low-balance alerting** exists anywhere — a business only discovers insufficient funds when an escrow lock or bid-award affordability check fails outright.
12. **No ledger-vs-wallet reconciliation mechanism** (discrepancy detection, reconciliation report, admin UI) exists anywhere in the Finance module.

---

## Integration Points

- **Contracts module:** publishes `ContractCreatedEvent` (triggers escrow lock) and reads settlement schedules for completion-readiness checks; Finance reads `ContractVehicleAssignment.DeliveredAt`/`ReleasedAt` directly via `IContractsUnitOfWork` to compute per-vehicle settlement earnings.
- **Delivery module:** publishes `DeliveryConfirmedEvent`, consumed by `FinanceDeliveryConfirmedEventHandler` as a no-op status check — delivery/return events never move money.
- **Marketplace module (RFQ/Bidding):** publishes `BidAwardedEvent`, consumed by `FinanceBidAwardedEventHandler` (the escrow-lock path that almost never actually fires — see Known Gaps #3).
- **MasterData module:** source of `CommissionStrategyVersion/Rule` (tier-based commission snapshotting at bid-award time), `ContractPolicyVersion/Rule` (early-termination penalty calculation), `EscrowPolicyVersion/Rule` (the escrow-lock path that doesn't actually run), and Settings (`WITHHOLDING_TAX_RATE`, `SETTLEMENT_AUTO_APPROVE_THRESHOLD`, minimum-payout amount, `ESCROW_RELEASE_DELAY_HOURS` used by `EscrowTimeoutJob`).
- **Identity module:** provider/business account and tier-assignment lookups (`GenerateSettlementCommand`'s optional `ProviderTierFilter`).
- **Notifications module:** deposit/withdrawal/escrow-event notifications (email/SMS/push — not confirmed wired for every specific event, e.g. escrow release; see epic-08 DoD).
- **Background services (not a separate module, but Finance-owned processes inside `Marketplace.API`):** `DailyLedgerJob` (nightly 00:05 UTC accrual) and `EscrowTimeoutJob` (every 15 minutes, cancels contracts stuck in `PENDING_ESCROW` past `ESCROW_RELEASE_DELAY_HOURS`, default 24h).
