# Identity & Compliance Module — Specification

**Module Name:** Identity & Compliance
**Version:** 2.0 (rewritten against running code)
**Last verified against code:** 2026-07-23
**Location:** `Modules/Identity/**` inside `Marketplace.API` (.NET 9 modular monolith) — a folder/namespace inside one deployable, not a separate service; Keycloak is genuinely used for auth, but only as an external identity provider, not as a microservice this module orchestrates
**Related documents:** `backlog/mvp/epic-01-business-onboarding-kyb.md`, `backlog/mvp/epic-02-provider-onboarding-kyc.md`, `backlog/mvp/epic-12-risk-trust-scoring.md`, `project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md`, `project-docs/18_Implementation_Coverage_Audit.md` §5 and §10.2

---

## What changed in this rewrite

The previous version of this document (v1.1, dated December 2025) got the trust-score formula and tier commission rates right, but got almost everything about *how verification and compliance actually work* wrong, and presented the trust-score/tier machinery as fully live when it is not. This rewrite replaces it entirely:

- **The formal `VerificationRequest` / `ComplianceCheckLog` workflow the previous doc describes is dead code.** `VerificationRequest.Approve()`/`Reject()`, and the `SubmitVerificationRequestCommand`/`ApproveVerificationRequestCommand`/`RejectVerificationRequestCommand` handlers built around it, have **zero controller call sites** anywhere in the backend — confirmed by repo-wide search. The real admin verification flow is much simpler and goes through two different mechanisms instead (see below).
- **The real verification flow is two-layered and direct:** (1) document-level status on `BusinessDocument`/`ProviderDocument`/`VehicleDocument` (`VerifiedStatus`: `PENDING`/`VERIFIED`/`REJECTED`), updated via a single generic endpoint (`ComplianceController.UpdateDocumentVerification`, `PUT /api/identity/compliance/documents/{documentId}/status`); and (2) entity-level status on `Business`/`Provider`/`Vehicle` themselves, updated via each entity's own admin verification endpoint (`PUT .../admin/{id}/verification/status`). Neither goes through `VerificationRequest`.
- **The real audit trail is `VerificationEventLog`** (via `VerificationAuditService`), not `ComplianceCheckLog` — `ComplianceCheckLog.Create()` also has zero call sites. `VerificationEventLog` is a flat, generic event log (entity type/ID, event type, actor, JSON event data) written on every business/provider creation, status update, and document action.
- **Trust score is fully built but never wired into production**, confirmed independently at the code level: `TrustScoreCalculator`/`ITrustScoreCalculator` has zero call sites outside its own unit tests, and `Provider.UpdateTrustScore()` is never invoked by any command/event handler. Every provider's `TrustScore` is frozen at its registration-time default of 50 unless an admin manually calls `AssignProviderTierCommand` (which doesn't even touch `TrustScore`, only the tier assignment).
- **Two competing, disagreeing tier-threshold schemes coexist in code**, and neither is wired to production either: a hardcoded `TrustScore.CalculateTier()` (Bronze <50/Silver 50–69/Gold 70–84/Platinum ≥85, used only for admin list-filtering) vs. a seeded `ProviderTierRule` + `TierCalculationService` "hybrid" model (Bronze 0–59/Silver 60–74/Gold 75–89/Platinum 90–100, plus minimum completed-contract counts) that is also DI-registered but never called.
- **`InsuranceMonitorService` is never invoked automatically.** There is no `InsuranceMonitorJob`/`BackgroundService` anywhere in `BackgroundServices/` that calls `ProcessExpiredPoliciesAsync`/`ProcessExpiringPoliciesAsync` on a schedule, unlike the previous doc's daily-cron `InsuranceMonitorService : BackgroundService`. The service exists, is registered in DI, but nothing triggers it — insurance expiry is not actually monitored in production today. On top of that, `ProcessExpiredPoliciesAsync`'s own "block the vehicle" logic is commented out (`// vehicle.Suspend(); // If such method existed`), and the "expiring soon" warning path only logs, it never publishes a notification event, despite the entity-level `InsuranceExpiredEvent` existing and having no registered handler either.
- **Business risk scoring, a fraud-detection rule engine, and a dispute engine do not exist in any form.** `RiskEvent`/`AccountFlag` are real but are generic free-text security-event/flag records (`NEW_DEVICE`, `GEO_MISMATCH`, `FAILED_LOGIN_SPREE`, `SUSPICIOUS`, `HIGH_RISK`, `DOCUMENT_EXPIRED`), not a scored 0–100 risk model. There is no `RiskScore` field anywhere on `Business`.
- **Profile completion is real and configuration-driven** (`ProfileCompletionService`, backed by `masterdata.profile_requirements`), which the previous doc's hardcoded 7-requirement list didn't reflect — requirements are admin-editable without a code change.
- **Trust score is visible to the provider themselves**, contradicting the previous doc's "admin/business-facing only" framing (and `epic-02` Story 2.6) — the provider mobile app's own dashboard renders it directly.

---

## Overview

### Purpose

The Identity & Compliance module is the source of truth for every actor on the platform — user accounts (mapped 1:1 to Keycloak identities), Businesses, Providers, Vehicles — and owns their onboarding, document/KYB/KYC verification, insurance compliance, provider trust scoring/tiering, and account-level risk flagging. It does not run pricing, bidding, contracts, or payments; other modules read from it (trust score, verification status, fleet availability) and it reacts to their events (e.g. contract completion — in principle, though that wiring doesn't exist today, see Known Gaps).

### Responsibilities

**User account management**
- Maps Keycloak identities (`KeycloakUserId`) to internal `UserAccount` records; tracks email/phone verification via self-service OTP (separate OTP fields for email, phone, and password reset, each with its own expiry)
- Device fingerprinting (`UserDevice`), login sessions (`UserLoginSession`), MFA challenges (`UserMfaChallenge`)
- Account lifecycle: `ACTIVE`/`DEACTIVATED`/`SUSPENDED`/`BLOCKED`, admin suspend/block/reactivate endpoints

**Business onboarding & management**
- Registration (`RegisterBusinessCommand`), multi-step onboarding tracking (`BusinessProfile.OnboardingStep`), document upload, admin verification, profile/contact-person/preferences/address updates
- Dual-OTP (email + phone) bank-account-change flow, mirroring the provider side

**Provider onboarding & management**
- Registration supporting `INDIVIDUAL`/`AGENT`/`COMPANY` provider types, document upload, admin verification, profile/preferences updates
- Trust score field + history (formula built, not wired — see below) and tier assignment (manual admin action only)
- Dual-OTP bank-account-change flow

**Vehicle & insurance management**
- Vehicle registration, 5-angle photo requirement, admin approval (gated on documents verified + active verified insurance + all 5 photos present), status lifecycle, Direct Rental listing opt-in
- Insurance policy tracking with a 30-day minimum-validity business rule enforced at bid-eligibility time — but **not** by any automated background monitor (see Known Gaps)

**Compliance**
- Document-level verification workflow (`BusinessDocument`/`ProviderDocument`/`VehicleDocument`, each with independent `VerifiedStatus`)
- Generic audit trail (`VerificationEventLog`) for every creation/status-change/document action
- Account flags (`AccountFlag`) and security risk events (`RiskEvent`) — free-text categorized records, not a scored model

**Trust & tier (provider-only)**
- `TrustScoreCalculator` implements the real BR-025 formula, fully unit-tested, but has no production trigger
- Four tiers (`BRONZE`/`SILVER`/`GOLD`/`PLATINUM`) with admin-configurable commission rates via MasterData; tier changes today are manual admin action only

---

## Database Schema

### User Identity

| Table | Purpose |
|---|---|
| `user_accounts` | Core user record mapped to Keycloak (`UserAccount`) |
| `user_devices` | Device fingerprints (`UserDevice`) |
| `user_login_sessions` | Active session tracking (`UserLoginSession`) |
| `user_mfa_challenges` | OTP/MFA challenge records (`UserMfaChallenge`) |

### Business

| Table | Purpose |
|---|---|
| `businesses` | Business entity (`Business`) |
| `business_profiles` | Extended metadata: tier code, onboarding step, contact person, preferences (`BusinessProfile`) |
| `business_documents` | KYB documents with independent `VerifiedStatus` (`BusinessDocument`) |
| `business_bank_accounts` | Bank accounts, dual-OTP change flow (`BusinessBankAccount`) |

### Provider

| Table | Purpose |
|---|---|
| `providers` | Provider entity, incl. `TrustScore` (`Provider`) |
| `provider_profiles` | Extended metadata: fleet size, onboarding step, bank details (`ProviderProfile`) |
| `provider_documents` | KYC documents with independent `VerifiedStatus` (`ProviderDocument`) |
| `provider_bank_accounts` | Bank accounts, dual-OTP change flow (`ProviderBankAccount`) |
| `provider_tier_assignments` | Append-only tier-assignment history (`ProviderTierAssignment`) |
| `provider_trust_score_histories` | Append-only trust-score change history (`ProviderTrustScoreHistory`) — never actually appended to outside admin manual calls, since nothing recomputes the score |

### Vehicle

| Table | Purpose |
|---|---|
| `vehicles` | Vehicle registry, incl. Direct Rental fields (`Vehicle`) |
| `vehicle_documents` | Generic vehicle documents with independent `VerifiedStatus` (`VehicleDocument`) |
| `vehicle_insurances` | Insurance policies (`VehicleInsurance`) |
| `vehicle_status_histories` | Vehicle status transition audit (`VehicleStatusHistory`) |

### Compliance & Risk

| Table | Purpose |
|---|---|
| `verification_requests` | Generic verification-request entity — **`Approve()`/`Reject()` and the commands built around it have zero controller call sites; dead in production** |
| `compliance_check_logs` | Per-check audit log tied to `VerificationRequest` — **`ComplianceCheckLog.Create()` has zero call sites anywhere; dead** |
| `verification_event_logs` | **The real audit trail.** Flat event log (entity type/ID, event type, actor, JSON `eventData`) written by `VerificationAuditService` on every business/provider creation, entity status update, and document verify/reject/upload action (`VerificationEventLog`) |
| `risk_events` | Free-text security events: `NEW_DEVICE`, `GEO_MISMATCH`, `FAILED_LOGIN_SPREE`, etc., with a `RiskSeverity` enum (`RiskEvent`) |
| `account_flags` | Free-text flags: `SUSPICIOUS`, `HIGH_RISK`, `DOCUMENT_EXPIRED`, etc., with optional expiry (`AccountFlag`) |

---

## Module Structure (actual folders)

```
Modules/Identity/
├── Domain/
│   ├── Entities/
│   │   ├── UserAccount.cs, UserDevice.cs, UserLoginSession.cs, UserMfaChallenge.cs
│   │   ├── Business.cs, BusinessProfile.cs, BusinessDocument.cs, BusinessBankAccount.cs
│   │   ├── Provider.cs, ProviderProfile.cs, ProviderDocument.cs, ProviderBankAccount.cs
│   │   ├── ProviderTierAssignment.cs, ProviderTrustScoreHistory.cs
│   │   ├── Vehicle.cs, VehicleDocument.cs, VehicleInsurance.cs, VehicleStatusHistory.cs
│   │   ├── VerificationRequest.cs      (dead — Approve/Reject never called from any controller)
│   │   ├── ComplianceCheckLog.cs       (dead — Create() never called)
│   │   ├── VerificationEventLog.cs     (real audit trail, written by VerificationAuditService)
│   │   ├── RiskEvent.cs, AccountFlag.cs
│   │   └── UserDocument.cs
│   ├── Enums/
│   │   ├── BusinessStatus.cs / ProviderStatus.cs / VehicleStatus.cs   (identical shape: PENDING, REJECTED, INCOMPLETE, VERIFIED/APPROVED, SUSPENDED/BLOCKED[, ASSIGNED, RETIRED for Vehicle])
│   │   ├── ProviderTier.cs (BRONZE, SILVER, GOLD, PLATINUM — no fifth tier)
│   │   ├── InsuranceStatus.cs, InsuranceType.cs, ComplianceStatus.cs, VerificationStatus.cs
│   │   ├── RiskSeverity.cs, BankAccountVerificationStatus.cs, BusinessType.cs, ProviderType.cs
│   │   └── UserType.cs, UserStatus.cs, VerificationEventType.cs
│   ├── Events/ (one file per event) BusinessRegisteredEvent, ProviderRegisteredEvent, ProviderVerifiedEvent,
│   │            TrustScoreUpdatedEvent (defined, never raised outside UpdateTrustScore, which is itself never called),
│   │            VehicleRegisteredEvent, InsuranceExpiredEvent (raised, but has no registered handler),
│   │            AccountOTPGeneratedEvent, AccountEmailOTPGeneratedEvent, PasswordResetOTPGeneratedEvent, UserAccountCreatedEvent
│   └── ValueObjects/ Address.cs, ContactInfo.cs, TrustScore.cs (score→tier mapping, scheme #1 — see Known Gaps)
│
├── Application/
│   ├── Business/Commands/  RegisterBusinessCommand, CreateBusinessByAdminCommand, UpdateBusinessCommand,
│   │                       UpdateBusinessVerificationCommand, UploadBusinessDocumentCommand,
│   │                       CompleteBusinessOnboardingCommand, UpdateBusinessOnboardingStepCommand,
│   │                       UpdateBusinessPreferencesCommand, UpdateBusinessContactPersonCommand,
│   │                       UpdateBusinessAddressCommand, BusinessBankAccountCommands (dual-OTP change flow)
│   ├── Provider/Commands/  RegisterProviderCommand, CreateProviderByAdminCommand, UpdateProviderCommand,
│   │                       UpdateProviderVerificationCommand, UploadProviderDocumentCommand,
│   │                       CompleteProviderOnboardingCommand, UpdateProviderOnboardingStepCommand,
│   │                       UpdateProviderPreferencesCommand, AssignProviderTierCommand (manual, admin-only),
│   │                       ProviderBankAccountCommands (dual-OTP change flow)
│   ├── Vehicle/Commands/   RegisterVehicleCommand, UpdateVehicleCommand, UpdateVehicleVerificationCommand,
│   │                       UploadVehicleDocumentCommand, UploadVehiclePhotosCommand,
│   │                       AddVehicleInsuranceCommand, UpdateVehicleInsuranceCommand, VerifyVehicleInsuranceCommand,
│   │                       UpdateVehicleMaintenanceStatusCommand, UpdateVehicleRentalRateCommand,
│   │                       SetVehicleDirectRentalAvailabilityCommand
│   ├── Compliance/Commands/ UpdateDocumentVerificationCommand (the real, wired document-status endpoint)
│   │                        SubmitVerificationRequestCommand, ApproveVerificationRequestCommand,
│   │                        RejectVerificationRequestCommand    (all three: dead, zero controller call sites)
│   ├── Compliance/Queries/  VerificationRequestQueries + Handlers (query side of the same dead workflow)
│   ├── UserAccount/Commands, Queries/ (create, devices, sessions, suspend/block/reactivate)
│   ├── Queries/GetBusinessDashboardStats, GetProviderDashboardStats, GetDashboardStats
│   └── Services/
│       ├── TrustScoreCalculator.cs / ITrustScoreCalculator.cs   (real formula, zero production call sites)
│       ├── ProviderValidationService.cs / IProviderValidationService.cs (real, BR-004 eligibility gate — used by Marketplace bid/award flows)
│       ├── ProfileCompletionService.cs                          (real, configuration-driven via masterdata.profile_requirements)
│       ├── InsuranceMonitorService.cs / IInsuranceMonitorService.cs (real logic, never invoked by any scheduled job)
│       └── VerificationAuditService.cs                          (the real audit-log writer, backs VerificationEventLog)
│
└── Infrastructure/
    ├── Configurations/ (EF Core mappings)
    ├── Repositories/ (Business, Provider, Vehicle, UserAccount, VerificationEventLog, etc.)
    └── Services/ (Keycloak integration)
```

Controllers live under `Marketplace.API/Controllers/Identity/`: `BusinessController`, `ProviderController`, `VehicleController`, `ComplianceController`, `UserAccountController`, `DashboardController`.

---

## Core Entities (field-level)

### Business
- `UserAccountId`, `BusinessName`, `BusinessType` (enum), `TinNumber` (exactly 10 digits, validated in `Create`/`Update`), `RegistrationNumber`, `Status` (`BusinessStatus`), `IsActive`
- `Status` values: `PENDING, REJECTED, INCOMPLETE, VERIFIED, SUSPENDED, BLOCKED`
- Methods: `Verify()` (from `PENDING`/`REJECTED`/`INCOMPLETE` only), `Reject()`, `MarkIncomplete()`, `ResubmitForVerification()` (→ `PENDING`), `Suspend()`, `Block()` (also flips `IsActive=false`), `Unblock()` (→ `VERIFIED`, `IsActive=true`), `Update()`
- `Create()` raises `BusinessRegisteredEvent`, consumed by the Finance module to open a `MAIN` wallet

### Provider
- `UserAccountId`, `Name`, `TinNumber` (optional at registration, validated 10-digit if supplied), `LicenseNumber` (optional), `ProviderType` (`INDIVIDUAL`/`AGENT`/`COMPANY`), `Status` (`ProviderStatus`, same 6 values as `BusinessStatus`), `TrustScore` (int, **default 50** at creation regardless of verification state), `IsActive`, `IsVatRegistered`
- Vehicle-count fields for admin tracking: `ApprovedVehicleCount`, `PendingVehicleCount` (incremented/decremented explicitly, not derived live)
- Individual-specific: `NationalId`. Business-specific (`AGENT`/`COMPANY`): `BusinessRegistrationNumber`, `ContactPersonName`/`Email`/`NationalId`, `City`, `Country` (default `"Ethiopia"`)
- `Create()` always assigns an initial `SILVER` `ProviderTierAssignment` with `computedScore: 50` — **not** derived from any threshold rule, a hardcoded default
- `UpdateTrustScore(newScore, reason)` — clamps 0–100, appends `ProviderTrustScoreHistory`, and auto-appends a new `ProviderTierAssignment` **only if** the tier implied by `TrustScore.CalculateTier()` (scheme #1, hardcoded) changes. **This method itself is never called anywhere outside unit tests** — see Known Gaps.
- Same status methods as `Business`: `Verify()`, `Reject()`, `MarkIncomplete()`, `ResubmitForVerification()`, `Suspend()`, `Block()`, `Unblock()`. `Verify()` raises `ProviderVerifiedEvent`.

### Vehicle
- `ProviderId`, `LicensePlate`, `VIN` (optional), `Make`, `Model`, `Year`, `Type` (string: `SEDAN`/`SUV`/`VAN`/`TRUCK`/`BUS`/`PICKUP`/`MOTORCYCLE`), `Color`, `SeatingCapacity`, `FuelType` (string, optional), `Status` (`VehicleStatus`), `IsActive`, `Tags` (Postgres `text[]`)
- `Status` values: `PENDING, REJECTED, INCOMPLETE, APPROVED, ASSIGNED, BLOCKED, RETIRED`
- 5 photo URL fields (`PhotoFrontUrl`/`BackUrl`/`RightUrl`/`LeftUrl`/`InteriorUrl`); maintenance fields (`IsInMaintenance`, `MaintenanceStartedAt`, `MaintenanceReason`)
- Direct Rental fields: `DailyRentalRate` (decimal, ≤999,999.99), `IsAvailableForDirectRental` (bool)
- `Approve()` runs `ValidateApprovalRequirements()` first, which **hard-blocks** approval unless: every non-deleted document is `VERIFIED`, at least one active insurance policy exists with `Status == VERIFIED`, and all 5 angle photos are present — returns a combined error list, not just a boolean
- `AssignToContract()`/`ReleaseFromContract()` toggle `APPROVED ⇄ ASSIGNED`; `SetStatus()` is a raw escape hatch used by the Contracts module for assignment/release bookkeeping
- `EnableDirectRental()` requires `Status == APPROVED` and a positive `DailyRentalRate`; `DisableDirectRental()` has no preconditions
- `ExpireInsurance(policyNumber)` calls the matching `VehicleInsurance.Expire()` and raises `InsuranceExpiredEvent` — but see Known Gaps for why this rarely fires in practice

### VehicleInsurance
- `VehicleId`, `ProviderName` (insurer name, not vehicle provider), `PolicyNumber`, `CoverageType` (`InsuranceType`), `Status` (`InsuranceStatus`: `PENDING`/`VERIFIED`/`EXPIRED`), `CoverageAmount` (optional), `ValidFrom`/`ValidTo`, `DocumentUrl`, `IsActive`
- `IsValidOn(date)` — true only if `IsActive && Status == VERIFIED && date` is within `[ValidFrom, ValidTo]`
- No entity-level enforcement of the 30-day minimum window at policy-creation time — that rule lives in `ProviderValidationService`/`ProfileCompletionService` at read time, not in `VehicleInsurance.Create()`

### BusinessDocument / ProviderDocument / VehicleDocument
- Each: entity-scoped ID, `DocumentTypeId` (references MasterData `document_type`), `FileUrl`, `IssuedAt`/`ExpiresAt` (optional), `VerifiedStatus` (string: `PENDING`/`VERIFIED`/`REJECTED`), `VerifierId`/`VerifiedAt`
- Methods: `Verify()`, `Reject(reason?)`, `ResetToPending()`, `UpdateFile()` (replacing a document resets it back to `PENDING`)
- These three entities — not `VerificationRequest`/`ComplianceCheckLog` — are what the real compliance workflow operates on

### VerificationRequest (dead in production)
- `ActorType` (`BUSINESS`/`PROVIDER`/`VEHICLE`), `ActorId`, `Status` (`VerificationStatus`), `AssignedToUserId`, `ProcessedAt`, `AdminNotes`
- `Approve()`/`Reject()` exist and are unit-testable, but `SubmitVerificationRequestCommand`/`ApproveVerificationRequestCommand`/`RejectVerificationRequestCommand` are never dispatched from `ComplianceController` or any other controller — confirmed by repo-wide search for their command types outside their own definition/handler files

### ComplianceCheckLog (dead in production)
- `VerificationRequestId`, `CheckName`, `Status` (`ComplianceStatus`), `Details`, `ExternalReferenceId` (for a 3rd-party KYC provider) — `Create()` has zero call sites anywhere

### VerificationEventLog (the real audit trail)
- `EntityType` (`BUSINESS`/`PROVIDER`/`VEHICLE`), `EntityId`, `DocumentId` (optional), `EventType` (`BUSINESS_CREATED`, `BUSINESS_STATUS_UPDATED`, `PROVIDER_CREATED`, `PROVIDER_STATUS_UPDATED`, `VEHICLE_STATUS_UPDATED`, `DOCUMENT_UPLOADED`/`_VERIFIED`/`_REJECTED`, `VEHICLE_DOCUMENT_UPLOADED`/`_VERIFIED`/`_REJECTED`, `BUSINESS_UPDATED`/`PROVIDER_UPDATED`/`VEHICLE_UPDATED`, etc.), `Description`, `ActorId` (admin user), `EventData` (JSONB — previous/new status, notes, rejection reason)
- Written exclusively via `VerificationAuditService`, which every admin-facing verification/update handler calls

### RiskEvent / AccountFlag
- `RiskEvent`: `UserId` (optional), `EventType` (free-text, e.g. `NEW_DEVICE`/`GEO_MISMATCH`/`FAILED_LOGIN_SPREE`), `Data` (JSON), `Severity` (`RiskSeverity` enum)
- `AccountFlag`: `ActorType` (`PROVIDER`/`BUSINESS`), `ActorId`, `FlagType` (free-text, e.g. `SUSPICIOUS`/`HIGH_RISK`/`DOCUMENT_EXPIRED`), `ExpiresAt` (optional)
- Neither is a scored risk model; there is no `RiskScore` field anywhere on `Business`

### ProviderTierAssignment (append-only)
- `ProviderId`, `TierCode` (`ProviderTier`), `AssignedAt`, `ComputedScore`, `Reason` — latest row = current tier

### ProviderTrustScoreHistory (append-only)
- `ProviderId`, `OldScore`, `NewScore`, `ChangeReason` (`CONTRACT_COMPLETION`/`CANCELLATION`/`REVIEW`/`PENALTY` — these are documented values, but since nothing calls `UpdateTrustScore()` in production, no row is ever created with any of them today), `Description` (optional), `ReferenceId` (optional)

---

## Key Workflows

### 1. Business/Provider registration
`RegisterBusinessCommand`/`RegisterProviderCommand` create the entity in `PENDING` status, raise `BusinessRegisteredEvent`/`ProviderRegisteredEvent` (the former triggers wallet creation in the Finance module). Provider registration always seeds `TrustScore = 50` and an initial `SILVER` `ProviderTierAssignment` — this is a fixed default, not a computed one (contrary to the previous doc's "verified + 100% profile completion = SILVER, otherwise BRONZE" claim, which does not exist as live logic anywhere in `RegisterProviderCommandHandler`).

### 2. Document upload and verification
`UploadBusinessDocumentCommand`/`UploadProviderDocumentCommand`/`UploadVehicleDocumentCommand` create a `PENDING` document row referencing a MasterData `DocumentType`. Admin verification goes through **one single generic endpoint**: `PUT /api/identity/compliance/documents/{documentId}/status` (`ComplianceController` → `UpdateDocumentVerificationCommand`), which dispatches on `EntityType` (`BUSINESS`/`PROVIDER`/`VEHICLE`) to call `Verify()`/`Reject()`/`ResetToPending()` on the matching document entity, logs a `VerificationEventLog` row via `VerificationAuditService`, and — when a document is verified for a Business or Provider — auto-advances their onboarding step if it's behind (Step 3 for Business, Step 2 for Provider).

### 3. Entity-level (business/provider/vehicle) admin verification
Separate from document verification: `PUT /api/identity/businesses/admin/{id}/verification/status` / the equivalent Provider/Vehicle endpoints (`UpdateBusinessVerificationCommand`/`UpdateProviderVerificationCommand`/`UpdateVehicleVerificationCommand`) directly call `Verify()`/`Reject()`/`MarkIncomplete()`/`Suspend()`/`Block()`/`ResubmitForVerification()` on the entity based on the requested target status, then log a `VerificationEventLog` row. **Neither this nor document verification ever touches `VerificationRequest`/`ComplianceCheckLog`** — those entities and their Submit/Approve/Reject commands are unreachable dead code.

### 4. Vehicle approval gate
`Vehicle.Approve()` calls `ValidateApprovalRequirements()`, which hard-blocks approval unless every non-deleted document is `VERIFIED`, at least one insurance policy is active and `VERIFIED`, and all 5 angle photos are present — returning a combined list of every unmet requirement, not a single failure.

### 5. Profile completion scoring (real, configuration-driven)
`ProfileCompletionService.CalculateProviderCompletionAsync`/`CalculateBusinessCompletionAsync` read active `masterdata.profile_requirements` rows (type `DOCUMENT`/`ATTRIBUTE`/`VERIFICATION`, per entity type), check each one against real data (verified documents by type code, bank-account presence, approved-vehicle count, insurance-validity-window, email/phone verification), and return a percentage plus a list of missing-field display names. This is admin-configurable without a code change — the previous doc's hardcoded 7-requirement list is one snapshot of what's currently seeded, not a fixed schema.

### 6. Provider bid/award eligibility gate (BR-004)
`ProviderValidationService.ValidateProviderEligibilityAsync` — called from the Marketplace module at bid submission/update/award time — checks: `Status == VERIFIED`, `TrustScore ≥ 0` (effectively always true; there's no real minimum today), at least one `APPROVED` vehicle not already assigned to an active contract, and valid insurance (≥30 days remaining) on every approved vehicle. This is the one place the 30-day insurance rule is actually enforced — at read/gate time, not via any monitoring job.

### 7. Trust score calculation — built, never triggered
`TrustScoreCalculator.CalculateScore(provider, factors)` implements BR-025 exactly: `Base(50 verified / 0 unverified) + CompletionRate×20 + OnTimeRate×20 − NoShowRate×30 + RejectionPenaltyPoints`, clamped 0–100. It is unit-tested and DI-registered, but **a repo-wide search finds no command, query, or event handler anywhere that calls it, or calls `Provider.UpdateTrustScore()`, in production.** No handler exists for contract completion, on-time delivery, no-show, or bid-award rejection that would recompute a score. Every provider's `TrustScore` therefore stays at 50 forever unless an admin manually edits it directly (there is no admin endpoint for that either — only `AssignProviderTierCommand`, which sets a tier without touching the score).

### 8. Tier assignment — manual only
`AssignProviderTierCommand` lets an admin pick a tier code directly (validated against `ProviderTier` master data) and appends a `ProviderTierAssignment` row — it does **not** check the provider's actual `TrustScore` against either threshold scheme before accepting the admin's choice. The admin `TiersPage.tsx` edit dialog on the web is a stub (`toast.info('Update functionality coming soon')`) — admins cannot edit tier thresholds/commission rates through the UI, only via direct database/seed changes.

### 9. Insurance expiry — no automated monitoring
`InsuranceMonitorService.ProcessExpiredPoliciesAsync()`/`ProcessExpiringPoliciesAsync()` are real, fully-coded, and registered in DI (`IInsuranceMonitorService`) — but **no `BackgroundService` in `BackgroundServices/` ever calls them**, and no controller endpoint does either. Insurance expiry monitoring is dead in production: expired policies are never automatically flagged, `Vehicle.ExpireInsurance()` is never invoked by any scheduled process, and even inside `ProcessExpiredPoliciesAsync` the vehicle-blocking step is commented out (`// vehicle.Suspend(); // If such method existed`). The "expiring in 30 days" path only logs a line — it never raises a notification event.

### 10. Dual-OTP bank-account change (Business and Provider, symmetric)
Both `BusinessController` and `ProviderController` expose the identical shape: `me/bank-accounts/change/initiate` → `verify-email` → `verify-phone` → (implicit commit) with `resend-otp` and `cancel` at any point before both factors are confirmed. This is a real, undocumented-by-the-old-epics flow that gates changing payout/deposit bank details behind two independently-verified OTP channels.

---

## Events

- **Published, real, and wired downstream:** `BusinessRegisteredEvent` (→ Finance module wallet creation), `ProviderRegisteredEvent`, `ProviderVerifiedEvent`, `VehicleRegisteredEvent`, `UserAccountCreatedEvent`, `AccountOTPGeneratedEvent`/`AccountEmailOTPGeneratedEvent`/`PasswordResetOTPGeneratedEvent` (→ Notifications module for OTP delivery)
- **Published but effectively orphaned:** `InsuranceExpiredEvent` — raised by `Vehicle.ExpireInsurance()`, but that method is never called by any scheduled process (see Workflow 9), so the event essentially never fires in production
- **Defined but never raised at all:** `TrustScoreUpdatedEvent` — only ever constructed inside `Provider.UpdateTrustScore()`, which itself has zero production callers

---

## APIs (controllers, actual routes)

| Controller | Base route | Key endpoints |
|---|---|---|
| `BusinessController` | `api/identity/businesses` | `GET /me`, `PUT/{id}`, `POST /{id}/documents`, `GET /{id}/documents`, `POST /{id}/complete-onboarding`, `PATCH /{id}/onboarding-step`, `PATCH /{id}/preferences`, `PATCH /{id}/contact-person`, `GET /admin/list`, `GET /admin/{id}`, `PUT /admin/{id}/verification/status`, `POST /admin` (create-on-behalf), full `me/bank-accounts/*` dual-OTP change flow |
| `ProviderController` | `api/identity/providers` | Same shape as `BusinessController` plus `GET /me/dashboard-stats`, `GET /me/dashboard-analytics`, `GET /me/recommended-rfqs`; admin list/detail/verification-status/create; dual-OTP bank-account flow |
| `VehicleController` | `api/identity/vehicles` | `POST`, `GET /{id}`, `GET /{id}/status-history`, `GET /{id}/assignments`, `GET /provider/{providerId}`, `PUT /{id}`, `POST /{id}/documents`, `POST /{id}/insurance`, `POST /insurance/{insuranceId}/verify`, `PUT /insurance/{insuranceId}`, `POST /{id}/photos`, `PUT /{id}/rental-rate`, `POST /{id}/enable-direct-rental`, `POST /{id}/disable-direct-rental`, admin list/detail/verification-status/create/direct-rental-settings |
| `ComplianceController` | `api/identity/compliance` | **One endpoint:** `PUT /documents/{documentId}/status` (admin-only, `UpdateDocumentVerificationCommand`) |
| `UserAccountController` | `api/identity/users` | `POST`, `GET /{id}`, `POST /{id}/devices`, `POST /{id}/sessions`, `POST /{id}/suspend`, `POST /{id}/block`, `POST /{id}/reactivate` |
| `DashboardController` | `api/identity/dashboard` | `GET /admin-stats`, `GET /successful-contract-trend`, `GET /business-stats`, `GET /provider-stats`, `GET /stats` |

---

## Known Gaps (verified by code search, zero call sites unless noted)

1. **Trust score is fully built but frozen in production.** `TrustScoreCalculator`/`Provider.UpdateTrustScore()` have zero call sites outside unit tests — every provider's score stays at its registration default (50) until an admin edits it directly, and there's no admin endpoint to do even that (only tier assignment, which doesn't touch the score).
2. **Two competing tier-threshold schemes coexist, neither wired to production.** Hardcoded `TrustScore.CalculateTier()` (used only by admin list-filtering) vs. seeded `ProviderTierRule`/`TierCalculationService` (a "hybrid" model with completed-contract minimums) disagree on where the Bronze/Silver/Gold/Platinum cutoffs are, and neither is invoked when trust score actually changes (because nothing changes it).
3. **`VerificationRequest`/`ComplianceCheckLog` and their Submit/Approve/Reject commands are entirely dead code** — zero controller call sites. The real workflow is document-level (`ComplianceController`) plus entity-level (`Business`/`Provider`/`Vehicle` admin verification endpoints), logged to `VerificationEventLog` instead.
4. **`InsuranceMonitorService` is never invoked by any scheduled job.** No `BackgroundService` calls `ProcessExpiredPoliciesAsync`/`ProcessExpiringPoliciesAsync`; insurance expiry is enforced only reactively, at bid/award-eligibility check time (`ProviderValidationService`), never proactively.
5. **`InsuranceExpiredEvent` has no registered handler**, and the vehicle-blocking logic inside `ProcessExpiredPoliciesAsync` is commented out even if the service were ever called.
6. **No business risk score exists anywhere.** `RiskEvent`/`AccountFlag` are free-text categorized records, not a scored 0–100 model; there is no admin UI for a business risk score because there's no data to show.
7. **No fraud-detection rule engine and no dispute engine exist anywhere** in this module or any other — `Disputed`/`OnHold` exist only as bare `ContractStatus` string values in the Contracts module with no workflow behind them.
8. **Admin `TiersPage.tsx` tier/commission-rate edit dialog is a stub** — reads real master-data tiers, but the update mutation is `toast.info('Update functionality coming soon')`; changing thresholds or commission rates requires a direct database/seed change today.
9. **Trust score is visible to the provider themselves**, contradicting the "admin/business-facing only" assumption in the original epic-02 Story 2.6 and epic-12 Story 12.2 — the provider mobile app's dashboard and profile screens render the provider's own `TrustScore`/tier directly.
10. **Business mobile app deserializes but never renders `RfqBid.trustScore`/`providerTier`** — the plumbing exists, the UI doesn't use it yet (half-migrated feature).
11. **Web admin `admin-users-service.ts`'s `getUserDetail()` hardcodes `trustScore: 0` / `tier: 'SILVER'`** for both business and provider detail views — the display component supports a real score, but this specific screen doesn't fetch one.

---

## Integration Points

- **Finance module:** consumes `BusinessRegisteredEvent` to create a `MAIN` wallet; reads `Provider.TrustScore`/tier (frozen values, in practice) and MasterData commission rates at contract-creation time.
- **Marketplace module:** reads `Provider.TrustScore`/tier live at bid submission (snapshotted into `RFQBidSnapshot`); `IProviderValidationService`/`ProviderFleetCapacityService` gate bid/award/Direct-Rental-accept eligibility on verification status, insurance validity, and fleet-segment capacity; `Vehicle.IsAvailableForDirectRental`/`EnableDirectRental()`/`DisableDirectRental()` drive the Direct Rental catalog.
- **Contracts module:** resolves commission rate from the provider's current `ProviderTierAssignment` via MasterData at contract creation (both RFQ and Direct Rental paths); reads `Vehicle`/`Provider` status for assignment/eligibility checks; calls `Vehicle.AssignToContract()`/`ReleaseFromContract()`/`SetStatus()` for vehicle lifecycle bookkeeping.
- **MasterData module:** `ProviderTier`/`ProviderTierRule`/`BusinessTier` master data (commission rates, threshold schemes), `masterdata.profile_requirements` (drives `ProfileCompletionService`), `DocumentType` lookups referenced by every document entity.
- **Notifications module:** consumes OTP-generation events (`AccountOTPGeneratedEvent`, etc.) for email/SMS delivery; would consume `InsuranceExpiredEvent`/`TrustScoreUpdatedEvent` if either were ever actually raised in a live path.
- **Auth (Keycloak):** `UserAccount.KeycloakUserId` is the join key; `Modules/Auth/` inside the same monolith handles the OAuth flow itself, out of this module's scope.
