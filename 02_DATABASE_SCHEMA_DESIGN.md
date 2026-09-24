# Anqelba Car Rental Database Schema Design

**Last verified against code:** 2026-07-23
**Database:** PostgreSQL 16 · **ORM:** EF Core 9 (Npgsql) · **Migration count:** 35 (`InitialCreate` 2026-02-12 → `AddContractTermsVersioningAndAcceptance` 2026-07-08)
**Ground truth used:** `backend/src/Marketplace.API/Migrations/MarketplaceDbContextModelSnapshot.cs` (the compiled, current-state EF model — authoritative over any single migration file, since migrations are cumulative and a few tables were dropped/recreated along the way), cross-checked against `Modules/*/Domain/Entities/*.cs` and `Modules/*/Infrastructure/Configurations/*.cs`.

This document supersedes the November 2025 draft entirely. That draft invented a `masterdata/identity/marketplace/contracts/wallet/delivery` table set that only vaguely resembles the real one (fictional tables like `wallet_ledger_transaction`, invented `provider_tier_rule` column names, an "80 tables" claim) and was never generated from real migrations. Every table, column, type, index, and FK below is read directly from the compiled model.

---

## 1. Real Schema Inventory

The database has **7 real PostgreSQL schemas** (via `migrationBuilder.EnsureSchema`) holding **119 tables** total. There is no `business`, `provider`, `rfq`, `risk`, `finance`, or `shared` schema — those were names invented by the earlier draft.

| Schema | Owning module | Tables | Notes |
|---|---|---:|---|
| `masterdata` | MasterData | 26 | Lookups, geography, versioned policy engines (commission/contract/escrow/settlement), tiers, document types, KYC/profile requirements, checklist templates |
| `identity` | Identity | 24 | Users, Business, Provider, Vehicle, bank accounts, documents, verification, trust score history, risk/account flags, sessions/MFA |
| `marketplace` | Marketplace | 17 | RFQ/line-item/bid/award/split-award, Direct Rental cart/request |
| `contracts` | Contracts | 12 | Contract lifecycle, line items, vehicle assignments, terms e-signature, amendments/penalties, status history |
| `wallet` | **Finance** | 19 | Finance module's tables live in a schema literally named `wallet`, not `finance` — a real, if confusing, naming mismatch between module and schema |
| `delivery` | Delivery | 10 | OTP delivery/return sessions, handover, inspection checklist, SLA violations |
| `notifications` | Notifications | 11 | Email/SMS/in-app notifications + outbox + provider configs + templates |
| — | **Auth** | 0 | Auth module owns **no tables at all**. It is Keycloak-integration + `BffTokenRefreshMiddleware` sitting on top of `identity.user_accounts` — confirmed by an empty `Modules/Auth/Domain` (no `Domain` folder exists under `Modules/Auth/`) |

**Total: 119 tables**, not the "80+" the prior draft claimed.

---

## 2. Cross-Cutting Findings (read this before the table reference)

### 2.1 Column naming is camelCase, not snake_case — despite `EFCore.NamingConventions` being referenced

`Marketplace.API.csproj` references `EFCore.NamingConventions 9.0.0`, and project memory / prior docs assumed it was active. **It is never invoked.** `MarketplaceDbContext.OnConfiguring` and `Program.cs` both carry the explicit comment:

> `// Note: We use explicit [Column("camelCase")] attributes on entities` / `// No global naming convention is applied - column names are specified directly`

Verified in code: table names are snake_case (`rfq_bids`, `contract_line_items`) via explicit `[Table("...")]` data-annotation attributes **and** a duplicate `builder.ToTable("...", "schema")` Fluent API call per entity (both are present for essentially every entity — genuinely redundant, not an either/or). Column names, however, are **camelCase** (`businessId`, `createdAt`, `contractNumber`), set via `[Column("camelCase")]` attributes on the entity properties — there is no naming-convention transform. So: **table names are snake_case, column names are camelCase, in the same database.**

### 2.2 A handful of tables use snake_case columns anyway — a second inconsistency inside the inconsistency

Five tables buck the camelCase-column pattern and use snake_case throughout: `contract_status_history`, `vehicle_status_history`, `rfq_status_history`, `direct_rental_request_status_history`, `settlement_status_history` (columns: `changed_at`, `contract_id`/`rfq_id`/`vehicle_id`/`request_id`/`settlement_cycle_id`, `from_status`, `to_status`, `trigger`, `triggered_by_user_id`, `triggered_by_user_type`). These five "status history" audit tables were all added together in migration `AddStatusHistoryTables` (2026-05-15) and are internally consistent with each other, just inconsistent with the other 114 tables.

One further one-off: `contract_vehicle_assignments.contractlineitemid` — no camelCase, no snake_case, just all-lowercase run together. Cross-checked against `ContractVehicleAssignment.cs`: the C# property is `ContractLineItemId`, correctly camelCase in code; the actual migration produced this one irregular column name regardless. Anyone hand-writing SQL against this table needs to know it's `contractlineitemid`, not `contractLineItemId`.

### 2.3 Data annotations *and* Fluent API are both used, contradicting the architecture doc

`architecture/module-layout-convention.md` (and this task's own briefing) states the codebase uses "EF Core Fluent API only, no data annotations." **This is false for entities, true only for relationships/constraints layered on top.** Every entity class carries `[Table]`, `[Column]`, `[Required]`, `[MaxLength]` attributes directly (e.g. `Modules/Marketplace/Domain/Entities/RFQBid.cs`), and a **separate** `IEntityTypeConfiguration<T>` class under each module's `Infrastructure/Configurations/` folder re-declares `ToTable`, some `Property(...).HasMaxLength(...)` (occasionally duplicating the attribute, occasionally adding something the attribute didn't specify, like `.HasPrecision(18,2)` or FK/index configuration). Net effect: table/column shape is annotation-driven; relationships, precision, and indexes are Fluent-driven. Both mechanisms are load-bearing; neither alone fully describes the schema.

### 2.4 Status/type fields: three genuinely different patterns coexist

| Pattern | Where | Example |
|---|---|---|
| **Real C# enum, EF-converted to a string column** (`.HasConversion<string>()` in the Fluent config) | Identity module only: `Business.Status` (`BusinessStatus`), `Business.BusinessType`, `Provider.Status` (`ProviderStatus`), `Vehicle.Status` (`VehicleStatus`), `ProviderTierAssignment.TierCode` (`ProviderTier`) | `BusinessConfiguration.cs`: `builder.Property(x => x.Status).HasConversion<string>()` |
| **Real C# enum, stored as `integer`** (default EF enum-to-int, no converter needed) | Marketplace only: `RFQLineItem.Term` (`RFQTerm`), `RFQLineItem.FuelType` (`FuelType?`) | `RFQLineItem.cs`: `public RFQTerm Term { get; private set; }` → column `term integer` |
| **Plain `string` property, no backing enum at all** — literal values documented only in a `//` comment, if at all | Contracts, Marketplace (RFQ/RFQBid/DirectRentalRequest/etc.), Finance/wallet — the large majority of status columns in the system | `Contract.cs`: `public string Status { get; private set; } = "DRAFT";` |

**`ContractStatus` and `ContractLineStatus` are a fourth, worse case: real C# enums exist in `Modules/Contracts/Domain/Enums/`, but `Contract.Status`/`ContractLineItem.Status` are plain strings that never reference them — the enums are dead code, referenced nowhere outside their own file.** Full detail: `MVP_MODULAR/MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md`. Do not assume any `Domain/Enums/*.cs` file in this codebase is actually wired to its entity — check the entity's property type directly before trusting an enum's member list as the real value set.

### 2.5 Cross-module foreign keys are mostly *not* enforced at the database level — by design, with one exception

Consistent with modules being isolated persistence boundaries, cross-module references are almost always a bare `Guid`/`Guid?` column with **no** `HasForeignKey`/DB constraint: `Contract.BusinessId`, `Contract.ProviderId`, `Contract.RFQId`, `Contract.RFQBidAwardId`, `Contract.DirectRentalRequestId`, `WalletAccount.OwnerId`, `EscrowLock.ContractId`, `CommissionEntry.ContractId`/`ProviderId`, `DeliverySession.ContractId`/`BusinessId`/`ProviderId`/`VehicleId`, `ContractVehicleAssignment.VehicleId` are all loose references — application code, not Postgres, enforces their integrity.

**The one confirmed exception:** `RFQ.BusinessId → identity.businesses.id` **is** a real, enforced, cascade-delete FK (`RFQConfiguration`/snapshot: `b.HasOne(...Business...).WithMany().HasForeignKey("BusinessId").OnDelete(DeleteBehavior.Cascade)`). Marketplace is the only module observed reaching across a module boundary with an actual database constraint.

### 2.6 An orphaned table: `contracts.early_return_notices` exists in the database but has zero EF mapping today

Migration `AddEarlyReturnNotice` (2026-04-11) created `early_return_notices`; migration `AddReturnOTPAndFixReturnSession` (2026-04-12) drops and recreates it (schema tweak) — so the table is still created by the cumulative migration history and would exist in any freshly-migrated database. **But `EarlyReturnNotice` does not appear anywhere in `MarketplaceDbContextModelSnapshot.cs`** — it is not a `DbSet`, not mapped by any current `IEntityTypeConfiguration`, and the domain class `Modules/Contracts/Domain/Entities/EarlyReturnNotice.cs` is unreferenced by the DbContext. This matches (and sharpens) the audit finding that `InitiateEarlyReturnCommand`/`Handler` has "no controller route, no event-handler invocation anywhere" — the backing table is not just unreachable via API, it's invisible to the ORM that would need to write to it. Treat `early_return_notices` as a **physically-present, functionally-dead table**.

### 2.7 Soft delete, audit columns, and PKs are the one genuinely consistent convention

Every one of the 119 tables has: `id uuid` PK (generated application-side, not a Postgres default — `ValueGeneratedOnAdd()` with no `HasDefaultValueSql`, so `Guid.NewGuid()` happens in the entity constructor), `createdAt timestamptz` (not nullable), `updatedAt timestamptz` (nullable), `createdBy uuid?`, `updatedBy uuid?`, `isDeleted boolean` (not nullable, defaulted in C# rather than a DB default in most tables). No table uses a Postgres `DEFAULT` for `id`/`createdAt` — defaults are set in C# before `SaveChanges`, not by the database schema itself, with the sole exception of `WalletEventLog.createdAt` (`HasDefaultValueSql("now()")`) and a handful of MasterData boolean/int columns using `HasDefaultValue(...)`.

---

## 3. Schema Reference: `masterdata` (26 tables)

Configuration, policy, and lookup data. Contains MasterData's **versioned policy engine** — every policy type follows the same `*Version` (header, effective-dated) + `*Rule` (line items scoped by tier/region/scenario) shape.

| Table | Purpose |
|---|---|
| `banks` | Ethiopian bank directory incl. Chapa payment-gateway bank code mapping |
| `business_tiers` / `business_tier_rules` | Business tier definitions + hybrid qualification rules (RFQ/contract/fleet-size thresholds) |
| `checklist_template_items` | Vehicle inspection checklist question bank (delivery/return) |
| `countries` / `regions` / `cities` | Geography hierarchy (lat/long on cities) |
| `commission_strategy_versions` / `commission_strategy_rules` | Versioned commission-rate policy, scoped by provider tier / region / vehicle category |
| `contract_policy_versions` / `contract_policy_rules` | Versioned contract business rules (penalty type/amount, grace period) by scenario code |
| `contract_terms_versions` | Versioned legal terms body signed via the dual-OTP e-signature flow (Contracts module) |
| `document_types` | KYC/KYB document type catalog with accepted formats, size limits, expiry rules |
| `escrow_policy_versions` / `escrow_policy_rules` | Versioned escrow lock-period policy by business tier / contract period |
| `kyc_requirements` | Which document types are mandatory per actor type/subtype/tier |
| `lookups` / `lookup_types` (+ translations) | Generic key-value lookup catalog (i18n-capable) |
| `profile_requirements` | Generic profile-completeness rule catalog |
| `provider_tiers` / `provider_tier_rules` | Provider tier definitions (commission rate baked directly onto the tier) + a **second, independent** trust-score/contract-count qualification scheme |
| `settings` (+ translations) | Key/value system settings, typed (`value_type`) |
| `settlement_policy_versions` / `settlement_policy_rules` | Versioned settlement cadence/payout-delay policy by provider tier |

### 3.1 `masterdata.banks` (`Bank`)
| Column | Type | Null | Notes |
|---|---|---|---|
| id | uuid | PK | |
| code | varchar(32) | NOT NULL | |
| shortName | varchar(32) | NOT NULL | |
| name | varchar(150) | NOT NULL | |
| chapaCode | varchar(32) | NULL | maps to Chapa payment-gateway bank identifier |
| logoUrl | varchar(512) | NULL | |
| isActive | boolean | NOT NULL | |
| createdAt/updatedAt/createdBy/updatedBy/isDeleted | audit columns | | |

### 3.2 `masterdata.business_tiers` (`BusinessTier`)
code, name, description, displayOrder, colorCode, maxRfqsPerMonth (int?), maxActiveContracts (int?), maxVehiclesPerRfq (int?), isActive + audit columns. 1:N → `business_tier_rules`.

### 3.3 `masterdata.business_tier_rules` (`BusinessTierRule`)
businessTierId (FK, cascade), minMonthlyRfqs/maxMonthlyRfqs (int, default 0), minActiveContracts (int, default 0), minMonthlySpend (numeric(18,2)?), isDefaultForNew (bool, default false) + audit. Indexes on `businessTierId`, `isDefaultForNew`.

### 3.4 `masterdata.checklist_template_items` (`ChecklistTemplateItem`)
code (unique), label, itemType (varchar16: e.g. BOOL), description, enumOptions (jsonb), isRequired (default true), isWarningTrigger (default false), warningThreshold, appliesToEvOnly (default false), appliesToReturn (default true), isActive (default true), sortOrder (default 0) + audit. Indexes: code unique, isActive, sortOrder.

### 3.5 `masterdata.cities` (`City`)
code, name, regionId (FK cascade), latitude numeric(10,8)?, longitude numeric(11,8)?, displayOrder (default 0), isActive (default true) + audit. Unique on (regionId, code); index on (latitude, longitude).

### 3.6 `masterdata.commission_strategy_versions` (`CommissionStrategyVersion`)
versionNumber (int), name, description, effectiveFrom/effectiveTo, isActive + audit. 1:N → `commission_strategy_rules`.

### 3.7 `masterdata.commission_strategy_rules` (`CommissionStrategyRule`)
strategyVersionId (FK cascade), providerTierId (FK cascade → `provider_tiers`), commissionType (varchar32: PERCENTAGE/FLAT/HYBRID), flatAmount, minCommissionAmount, maxCommissionAmount, regionCode, vehicleCategoryCode, isDefault + audit.

### 3.8 `masterdata.contract_policy_versions` / `contract_policy_rules`
Version: versionNumber, name, description, effectiveFrom/To, isActive + audit.
Rule: contractPolicyVersionId (FK cascade), scenarioCode (e.g. `EARLY_RETURN`), applyToParty (varchar32), businessTierCode?, providerTierCode?, penaltyType, penaltyValue, maxPenaltyAmount, gracePeriodHours (int?) + audit. `EarlyReturnNotice`'s (dead) grace-period logic reads `gracePeriodHours` from here.

### 3.9 `masterdata.contract_terms_versions` (`ContractTermsVersion`)
contentHash, name, description, sourceType (varchar32: RFQ | DIRECT_RENTAL), termsBody (text), versionNumber, effectiveFrom/To, isActive, supersedesVersionId (self-FK, restrict) + audit. Unique partial index: one active+non-deleted version per `sourceType`; unique on (sourceType, versionNumber). Referenced (restrict-delete) by `contracts.contract_terms_acceptances.termsVersionId`.

### 3.10 `masterdata.countries` / `regions` / `cities`
Countries: code(3, unique), name, isoAlpha2/3, phoneCode, currency, displayOrder, isActive + audit. 1:N → regions (FK cascade) → cities (FK cascade, see 3.5).

### 3.11 `masterdata.document_types` (`DocumentType`)
code (unique), name, category, description, acceptedFormats (text, default `[".pdf",".jpg",".jpeg",".png"]`), maxFileSizeMb (default 10), requiresExpiry, isBusiness/isPersonal/isVehicle flags, isActive (default true) + audit.

### 3.12 `masterdata.escrow_policy_versions` / `escrow_policy_rules`
Version: same version-header shape as 3.6/3.8.
Rule: escrowPolicyVersionId (FK cascade), businessTierCode?, contractPeriodCode?, lockPeriodDays (int) + audit. Note: the *actual running* escrow-lock computation in `ContractCreatedEventHandler` uses a hardcoded 30-day cap, not this table; a second, unused code path (`FinanceBidAwardedEventHandler`) does read the policy engine. Only the hardcoded path runs in production (coverage-audit §10.5) — this table is the policy-engine's intended source of truth, only partially wired into the live escrow path.

### 3.13 `masterdata.kyc_requirements` (`KYCRequirement`)
actorType (varchar32), actorSubtype?, tierCode?, documentTypeId (FK cascade), isMandatory (default true), minValidityDays?, isActive (default true) + audit. Unique on (actorType, actorSubtype, tierCode, documentTypeId).

### 3.14 `masterdata.lookups` / `lookup_types` (+ translations)
LookupType: code (unique), name, description, displayOrder, isActive + audit. 1:N → Lookup (FK cascade) and LookupTypeTranslation (FK cascade, unique per (lookupTypeId, language)).
Lookup: lookupTypeId (FK cascade), code, value, metadata (jsonb), sortOrder, isActive + audit. Unique on (lookupTypeId, code). 1:N → LookupTranslation (FK cascade, unique per (lookupId, language)).

### 3.15 `masterdata.profile_requirements` (`ProfileRequirement`)
code, displayName, description, entityType (varchar32), requirementType (varchar32), referenceCode?, isMandatory (default true), validationRule, sortOrder, isActive (default true) + audit. Unique on (entityType, code); composite index on (entityType, isActive, isMandatory).

### 3.16 `masterdata.provider_tiers` / `provider_tier_rules`
ProviderTier: code, name, description, displayOrder, colorCode, **commissionRate numeric** (baked directly on the tier — this is the seeded 10/8/6/5% Bronze/Silver/Gold/Platinum scheme referenced in project memory), isActive + audit.
ProviderTierRule: providerTierId (FK cascade), minTrustScore/maxTrustScore (int), minCompletedContracts (int), minOnTimeRate (numeric?), maxCancellationRate (numeric?), isDefaultForNew (bool) + audit. **This is the second, independent tier-qualification scheme** (`TierCalculationService`) that coexists with — and disagrees with — the hardcoded 50/70/85 admin-filter thresholds; see coverage-audit §10.2. Both are real tables/code paths; neither is wired to fire automatically on contract events.

### 3.17 `masterdata.settings` / `settings_translations`
Settings: key (unique), value (text), valueType (varchar32), description, isActive (default true) + audit. 1:N → SettingsTranslation (FK cascade, unique per (settingsId, language)).

### 3.18 `masterdata.settlement_policy_versions` / `settlement_policy_rules`
Version: same header shape.
Rule: settlementPolicyVersionId (FK cascade), providerTierCode?, settlementFrequency (varchar32), payoutDelayDays (int), minPayoutAmount? + audit. See coverage-audit §10.4 — the wallet-cluster docs and the ledger/settlement-cluster docs **disagree** on whether this tier-based cadence table is actually what drives real settlement runs, or whether `GenerateSettlementCommand` runs a flat 30-day rolling cycle regardless of tier; unresolved as of this writing.

---

## 4. Schema Reference: `identity` (24 tables)

Users, KYC/KYB, vehicles, bank accounts, sessions. The `Auth` module has no schema of its own and layers Keycloak/BFF logic on top of `user_accounts`.

### 4.1 `identity.user_accounts` (`UserAccount`)
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| keycloakUserId | varchar(255), unique | |
| email | varchar(255), unique | |
| firstName / lastName | varchar(100) | |
| phoneNumber | varchar(20)? | |
| userType | text | plain string, not enum-backed despite a `UserType` enum existing in `Domain/Enums` |
| status | text | plain string, not enum-backed despite a `UserStatus` enum existing |
| isEmailVerified / isPhoneVerified | boolean | |
| emailOtpCode/emailOtpExpiresAt, phoneOtpCode/phoneOtpExpiresAt, passwordResetOtpCode/passwordResetOtpExpiresAt | varchar(10)/timestamptz | three independent OTP mechanisms on one row |
| lastLoginAt | timestamptz? | |
| + audit columns | | |

1:1 → `businesses` (`Business.UserAccountId`, restrict-delete), 1:1 → `providers` (restrict-delete), 1:N → `user_devices` (2 relationships — see §4.18), 1:N (loose, no enforced FK except where noted) → `user_documents`/`user_login_sessions`/`user_mfa_challenges`/`risk_events`.

### 4.2 `identity.businesses` (`Business`)
businessName varchar(200), businessType (**real enum** `BusinessType`, string-converted), tinNumber varchar(10) unique, registrationNumber varchar(50), status (**real enum** `BusinessStatus`, string-converted: `PENDING/VERIFIED/REJECTED/INCOMPLETE/SUSPENDED/BLOCKED`), isActive, userAccountId (FK unique, restrict) + audit. 1:1 → `business_profiles` (cascade), 1:N → `business_documents` (cascade), 1:N → `business_bank_accounts` (cascade).

### 4.3 `identity.business_profiles` (`BusinessProfile`)
1:1 with Business (cascade). Address fields (street, houseNumber, subcity, woreda, city), contactPerson(Name/Email/Phone/Position), industry, employeeCount, licenseNumber, businessTierCode, billingAddress, legacy bankName/bankAccountNumber/accountHolderName (superseded by dedicated `business_bank_accounts`), notificationPreferences (jsonb), onboarding(Completed/Step), preferredLanguage + audit.

### 4.4 `identity.business_documents` (`BusinessDocument`)
businessId (FK cascade), documentTypeId, fileUrl (text), issuedAt/expiresAt, verifiedStatus (varchar32: PENDING/VERIFIED/REJECTED), verifiedAt, verifierId + audit.

### 4.5 `identity.providers` (`Provider`)
name varchar(200), providerType (text; a `ProviderType` enum exists but only used as an application-layer helper — the entity column is plain), tinNumber varchar(10) unique, nationalId?, licenseNumber?, businessRegistrationNumber?, isVatRegistered, country/city, contactPerson(Name/Email/NationalId), status (**real enum** `ProviderStatus`, string-converted), **trustScore int** (the live, real trust-score column referenced by `TrustScoreCalculator` — but per coverage-audit §10.2, nothing in production actually calls the updater, so this sits frozen at its registration default of 50), approvedVehicleCount/pendingVehicleCount (denormalized counters), userAccountId (FK unique, restrict) + audit. 1:1 → `provider_profiles` (cascade), 1:N → `provider_documents`/`provider_bank_accounts`/`vehicles`/`provider_tier_assignments`/`provider_trust_score_histories` (all cascade).

### 4.6 `identity.provider_profiles` (`ProviderProfile`)
1:1 with Provider (cascade). bankAccountNumber/bankName (legacy, superseded by `provider_bank_accounts`), fleetSize (int), notificationPreferences (jsonb), onboarding(Completed/Step), preferredLanguage + audit.

### 4.7 `identity.provider_documents` / `business_documents` / `user_documents` / `vehicle_documents`
All four follow an identical shape: `{owner}Id` (FK cascade to owner, `user_documents.userId` FK cascade to `user_accounts`), `documentTypeId`, `fileUrl` (text), `issuedAt`/`expiresAt`, `verifiedStatus` (varchar32), `verifiedAt`, `verifierId` + audit.

### 4.8 `identity.vehicles` (`Vehicle`)
providerId (FK cascade), licensePlate varchar(50) unique, VIN varchar(50) (indexed, not unique), make/model varchar(50), year int, color, seatingCapacity int?, type (plain string, default `SEDAN`; values SEDAN/SUV/VAN/TRUCK/BUS/PICKUP/MOTORCYCLE per code comment — a `VehicleStatus`-style separate enum exists but this `Type` field is a raw string), fuelType varchar(32)?, dailyRentalRate decimal(18,2)?, status (**real enum** `VehicleStatus`, string-converted — 24 cross-references confirm this one is actively used, unlike Contract's dead enums), isActive, isInMaintenance + maintenanceReason/maintenanceStartedAt, isAvailableForDirectRental (Direct Rental feature flag on the base Vehicle row), tags (**text[] Postgres array**, not jsonb), photo{Front/Back/Left/Right/Interior}Url + audit. 1:N → `vehicle_documents`/`vehicle_insurances` (cascade), 1:N (loose, no FK) → `vehicle_status_history`.

### 4.9 `identity.vehicle_insurances` (`VehicleInsurance`)
vehicleId (FK cascade), providerName, policyNumber, coverageType (text), coverageAmount decimal(18,2)?, documentUrl, validFrom/validTo, isActive + audit.

### 4.10 `identity.vehicle_status_history` (`VehicleStatusHistory`) — snake_case table (see §2.2)
vehicle_id (FK cascade), from_status/to_status (text), trigger (text), triggered_by_user_id/type, changed_at, notes + camelCase audit columns (only the domain-specific columns are snake_case, oddly — `createdAt`/`updatedAt`/etc. on this same table remain camelCase).

### 4.11 `identity.business_bank_accounts` / `provider_bank_accounts`
Both identical shape: {owner}Id (FK cascade), bankCode/bankName, accountNumber/accountHolderName, isActive, status (text), activatedAt, dual-channel OTP verification (emailOtpCode/Expires/Verified, phoneOtpCode/Expires/Verified, lastOtpSentAt) + audit. Composite indexes on ({owner}Id, isActive) and ({owner}Id, status).

### 4.12 `identity.account_flags` (`AccountFlag`)
actorType varchar(32), actorId, flagType varchar(64), expiresAt? + audit. Generic security-event flag record (new-device login, geo-mismatch, etc.) — **not** the scored 0–100 business-risk model that epic-12/`11_Trust_Escrow_Dispute_Engines_Spec.md` describe; no risk-score field exists anywhere on `Business`.

### 4.13 `identity.risk_events` (`RiskEvent`)
userId (FK, default restrict-delete), eventType varchar(64), severity (text; a `RiskSeverity` enum exists, unused), data (text) + audit.

### 4.14 `identity.compliance_check_logs` (`ComplianceCheckLog`)
verificationRequestId (FK cascade), checkName varchar(64), status (text), details, externalReferenceId + audit.

### 4.15 `identity.verification_requests` / `verification_event_logs`
VerificationRequest: actorType/actorId, status (text), adminNotes, assignedToUserId?, processedAt + audit. 1:N → ComplianceCheckLog (cascade).
VerificationEventLog: entityType varchar(32), entityId, eventType varchar(64), eventData (jsonb), actorId?, documentId? + audit. Heavily indexed (6 single-column + 1 composite) — this is the module's general-purpose audit trail.

### 4.16 `identity.provider_tier_assignments` (`ProviderTierAssignment`)
providerId (FK cascade), tierCode (**real enum** `ProviderTier`, stored as text via conversion), computedScore (int), assignedAt, reason? + audit.

### 4.17 `identity.provider_trust_score_histories` (`ProviderTrustScoreHistory`)
providerId (FK cascade), oldScore/newScore (int), changeReason varchar(200), description?, referenceId? + audit. The audit trail `TrustScoreCalculator` *would* write to — but see §4.5: nothing calls the calculator in production, so this table is presently empty except for manual admin tier-assignment actions.

### 4.18 `identity.user_devices` (`UserDevice`)
Two separate relationships to `UserAccount` on the same table: a shadow-FK `WithMany("Devices")` on `UserAccountId` (nullable, no delete behavior configured) *and* a real required cascade FK `WithMany()` on `UserId`. deviceId varchar(256), sessionId?, ipAddress/userAgent, isTrusted (default false), trustScore (int, default 0), pushToken (varchar 1024)/pushPlatform/pushTokenUpdatedAt/isPushActive (push-notification rebinding — the mobile-spec-doc contradiction the audit flagged: real endpoints are `mobile/notifications/push/rebind`/`unregister`, not `POST mobile/me/devices`), lastUsedAt + audit. Unique on (userId, deviceId).

### 4.19 `identity.user_login_sessions` / `user_mfa_challenges`
UserLoginSession: userId (FK cascade), deviceId?, ipAddress?, status (text: `PENDING_MFA/ACTIVE/TERMINATED`), mfaVerifiedAt?, lastSeenAt? + audit. 1:N → UserMfaChallenge (cascade).
UserMfaChallenge: sessionId (FK cascade), userId (FK cascade), channel varchar(32), otpHash varchar(256), status (text: `PENDING/VERIFIED/EXPIRED`), attemptCount (default 0), expiresAt + audit.

---

## 5. Schema Reference: `marketplace` (17 tables)

RFQ header + line-item model, per-line-item bidding with multi-provider split awards, and the Direct Rental fixed-price booking feature (epic-21).

### 5.1 `marketplace.rfqs` (`RFQ`)
businessId (**enforced FK, cascade** — the one confirmed cross-module DB constraint, §2.5), rfqNumber varchar(20), title varchar(200), type (plain string, default `STANDARD`: STANDARD/URGENT/LONG_TERM), status (plain string, default `DRAFT`: DRAFT/PUBLISHED/BIDDING/PARTIALLY_AWARDED/AWARDED/COMPLETED/CANCELLED), isBlind (boolean — the blind-bidding toggle; see §5.4 note on `ProviderName` leak), submissionDeadline, contractDurationDays?, pickupCity/dropoffCity varchar(100)? + audit. 1:N → `rfq_line_items` (cascade), 1:N → `rfq_bids` (cascade).

### 5.2 `marketplace.rfq_line_items` (`RFQLineItem`)
rfqId (FK cascade), vehicleType varchar(50), quantity (int), term (**real enum `RFQTerm`, stored as integer** — SHORT_TERM/LONG_TERM), fuelType (**real enum `FuelType?`, stored as integer?**), requiredFrom/requiredTo (timestamptz), purpose varchar(500), specifications varchar(255)?, pickupLocation/dropoffLocation varchar(100)?, targetPricePerUnit numeric? + audit.

### 5.3 `marketplace.rfq_bids` (`RFQBid`)
rfqId (FK cascade), providerId, status (plain string, default `SUBMITTED`: SUBMITTED/WITHDRAWN/REJECTED/AWARDED), totalAmount numeric(18,2), validUntil?, notes varchar(500)? + audit. Non-unique index on (rfqId, providerId) — **not unique**, per migration `RemoveUniqueConstraintFromRFQBids` (2026-02-22): one provider can legitimately hold multiple bids across different line items of the same RFQ. 1:1 → `rfq_bid_awards` (cascade), 1:N → `rfq_bid_items` (cascade), 1:N → `rfq_bid_snapshots` (cascade).

### 5.4 `marketplace.rfq_bid_items` (`RFQBidItem`)
bidId (FK cascade), rfqLineItemId (FK **restrict**, not cascade — a line item can't be deleted while bid items reference it), quantity (int), unitPrice numeric(18,2), description varchar(500)?. **Confirmed live gap (coverage-audit §10.3):** `GetBidsByRFQQuery`/`GetBidQuery` set the bid's `ProviderName` field unconditionally regardless of award status — blind bidding (`RFQ.isBlind`) is enforced only by the web UI choosing not to render the field, not by the API withholding it.

### 5.5 `marketplace.rfq_bid_snapshots` (`RFQBidSnapshot`)
rfqBidId (FK cascade), hashedProviderId varchar(128) (SHA-256-style anonymization token), bidAmountPerUnit numeric, quantityOffered (int), providerTrustScore (int), providerTierCode varchar(20)? — a point-in-time snapshot for the blind-bidding comparison view.

### 5.6 `marketplace.rfq_bid_history` (`RFQBidHistory`)
rfqBidId (FK cascade), action varchar(50), previousStatus/newStatus varchar(32) (previousStatus **nullable** — migration `AllowNullPreviousStatusInBidHistory`, 2026-05-20, for the initial "Created" row), previousTotalAmount?/newTotalAmount, changedByUserId/changedByUserType varchar(20), changeDetails varchar(1000)?, notes varchar(500)?, changedAt.

### 5.7 `marketplace.rfq_bid_awards` (`RFQBidAward`)
rfqBidId (FK cascade, **unique** — one award per bid), rfqLineItemId (FK cascade), quantityAwarded (int), agreedPricePerUnit numeric(18,2), awardedAt + audit. 1:N → `rfq_award_vehicle_assignments` (cascade).

### 5.8 `marketplace.rfq_award_vehicle_assignments` (`RFQAwardVehicleAssignment`)
rfqBidAwardId (FK cascade), vehicleId, status (plain string, default `ASSIGNED`: ASSIGNED/DELIVERED/RETURNED), assignedAt, releasedAt? + audit. This is the post-award, per-vehicle assignment step confirmed (coverage-audit §10.3) to be identical across web and both mobile apps — one three-phase pattern (bid at quantity → split award → assign vehicles), not two divergent ones as earlier drafts of the audit claimed.

### 5.9 `marketplace.rfq_line_item_fulfillments` (`RFQLineItemFulfillment`)
rfqLineItemId (FK cascade), rfqBidAwardId (FK cascade), status (plain string, default `PENDING`: PENDING/PARTIAL/FULFILLED/COMPLETED), quantityDelivered/quantityReturned (int) + audit.

### 5.10 `marketplace.rfq_status_history` (`RFQStatusHistory`) — snake_case table (see §2.2)
rfq_id (FK cascade), from_status/to_status/trigger (text), triggered_by_user_id/type, changed_at, notes.

### 5.11 `marketplace.marketplace_event_logs` (`MarketplaceEventLog`)
actorId?, eventType varchar(64), description (text), rfqId?/rfqBidId? (both loose, no FK) + audit. General-purpose module event log.

### 5.12–5.17 Direct Rental (epic-21 — fixed-price booking, not blind bidding)
- **`direct_rental_carts`** (`DirectRentalCart`): businessId + audit. 1:N → `direct_rental_cart_items` (cascade).
- **`direct_rental_cart_items`** (`DirectRentalCartItem`): cartId (FK cascade), vehicleId, providerId, make/model/plateNumber varchar(50), type varchar(32), dailyRate decimal(18,2), startDate/endDate (**date**, not timestamptz — the only two `date`-typed columns in this table set) + audit.
- **`direct_rental_requests`** (`DirectRentalRequest`): businessId, providerId, requestNumber varchar(50), status (plain string, default `PENDING`), startDate/endDate (date), totalAmount decimal(18,2), isAllOrNone (boolean — an all-or-nothing acceptance mode), expiresAt, specialInstructions?, respondedAt?/rejectionReason?/cancelledAt?/cancelReason? + audit. 1:N → `direct_rental_request_line_items` (cascade).
- **`direct_rental_request_line_items`** (`DirectRentalRequestLineItem`): directRentalRequestId (FK cascade), vehicleType varchar(32), quantity (int), status (plain string, default `PENDING`), subtotalAmount decimal(18,2), rejectionReason? + audit. 1:N → `direct_rental_request_vehicles` (cascade).
- **`direct_rental_request_vehicles`** (`DirectRentalRequestVehicle`): lineItemId (FK cascade), vehicleId, make/model/plateNumber, dailyRate/totalAmount decimal(18,2), isAccepted (bool?), rejectionReason? + audit.
- **`direct_rental_request_status_history`** (`DirectRentalRequestStatusHistory`) — snake_case table (§2.2): request_id (FK cascade), from_status/to_status/trigger, triggered_by_user_id/type, changed_at, notes.

---

## 6. Schema Reference: `contracts` (12 tables)

The real contract state machine is **18 string values**, not the 17-member `ContractStatus` C# enum (which is dead code — never referenced outside its own file). Full detail, transition matrix, and dead-code inventory: **`MVP_MODULAR/MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md`** — this section only covers the table shapes.

### 6.1 `contracts.contracts` (`Contract`)
contractNumber varchar(20) unique, businessId/providerId (loose Guids, no FK), rfqId?/rfqBidAwardId?/directRentalRequestId? (loose, nullable — a contract's origin), sourceType varchar(32) (default `RFQ`; RFQ | DIRECT_RENTAL), status (plain string, default `DRAFT`; see the state-machine doc for the real 18-value set incl. `CANCELLED`, absent from the enum), startDate/endDate (timestamptz), totalContractValue numeric, activatedAt?, finalSettlementProcessed (bool), termination(RequestedAt/RequestedBy/Reason) + audit. Navigations: `Amendments`, `BusinessParty` (1:1 required), `CompletionRequests`, `LineItems`, `Penalties`, `ProviderParty` (1:1 required), `TermsAcceptance` (1:1), `VehicleAssignments` — all cascade-delete from Contract.

### 6.2 `contracts.contract_line_items` (`ContractLineItem`)
contractId (FK cascade), rfqLineItemId?/directRentalRequestLineItemId? (loose), unitAmount/totalAmount numeric(18,2), commissionRate numeric(5,4), durationDays (int), quantityAwarded/quantityActive/quantityDelivered/quantityReturned (int), status (plain string, default `PENDING_ACTIVATION` on the backing field, always overwritten to `PENDING_VEHICLE_ASSIGNMENT` by both `Create()` factories — real 7-value set documented in the state-machine doc) + audit. 1:N → `contract_vehicle_assignments` (cascade).

### 6.3 `contracts.contract_vehicle_assignments` (`ContractVehicleAssignment`)
contractId (FK cascade), **contractlineitemid** (FK cascade — note the irregular column casing, §2.2), vehicleId (loose), status (plain string, default `ASSIGNED`; real 5-value set incl. undocumented `REMOVED` — see state-machine doc §4), assignedAt, deliveredAt?/releasedAt?, removedReason varchar(500)? + audit.

### 6.4 `contracts.contract_party_businesses` / `contract_party_providers`
Immutable point-in-time snapshots of the counterparty, taken at contract creation. Both: contractId (FK **unique** 1:1, cascade), companyName varchar(200), taxId varchar(50), address?, contactPerson(Name/Email) + audit. `ContractPartyBusiness` additionally carries `businessId`; `ContractPartyProvider` additionally carries `providerId`.

### 6.5 `contracts.contract_terms_acceptances` (`ContractTermsAcceptance`)
contractId (FK **unique** 1:1, cascade), termsVersionId (FK **restrict** → `masterdata.contract_terms_versions`), termsVersionNumber (int, denormalized), dual independent OTP channels: business{OtpCode/OtpConfirmed/OtpConfirmedAt/OtpExpiresAt/OtpLastSentAt}, provider{...same 5 fields...}, acceptedAt? + audit. This is the dual-party e-signature mechanism — entirely separate from Delivery-module OTP.

### 6.6 `contracts.contract_amendments` (`ContractAmendment`)
contractId (FK cascade), amendmentNumber varchar(20), type (plain string, default `EXTENSION`: EXTENSION/SCOPE_CHANGE/TERMINATION), status (plain string, default `DRAFT`: DRAFT/SIGNED/REJECTED), description (text), newEndDate?/newTotalValue?, signedAt? + audit. **Zero callers anywhere in the codebase** (coverage-audit §10.5/state-machine §9) — fully modeled, never created by any command.

### 6.7 `contracts.contract_penalties` (`ContractPenalty`)
contractId (FK cascade), reasonCode varchar(32), appliedToParty varchar(32), amount (numeric), status (plain string, default `PENDING`: PENDING/PAID/WAIVED/DISPUTED), description varchar(255)? + audit. Also zero callers today.

### 6.8 `contracts.contract_completion_requests` (`ContractCompletionRequest`)
contractId (FK cascade), requestedBy/requestedByParty varchar(16), requestedAt, resolution varchar(16) (default present, required), resolvedAt?/resolvedBy?/resolvedByParty varchar(16)?, rejectionReason varchar(512)? + audit. Backs the real, reachable two-party completion request/approve/reject/cancel flow (§2.11 of the state-machine doc).

### 6.9 `contracts.contract_policy_snapshots` (`ContractPolicySnapshot`)
contractId (FK cascade), policyType varchar(64), policyJson (text) — immutable snapshot of the MasterData policy in effect at contract creation, so later policy-version changes don't retroactively alter an in-flight contract.

### 6.10 `contracts.contract_event_logs` (`ContractEventLog`)
contractId (FK cascade), actorId?, eventType varchar(64), description (text) + audit. General event log, separate from…

### 6.11 `contracts.contract_status_history` (`ContractStatusHistory`) — snake_case table (§2.2)
contract_id (FK cascade), from_status/to_status/trigger (text), triggered_by_user_id/type, changed_at, notes. The queryable status-transition audit trail referenced throughout the state-machine doc (`GetContractStatusHistory`) — note `SIGNED` never appears here (overwritten before `SaveChanges`) and the `EscrowTimeoutJob`'s `CANCELLED` transition also skips writing a row here, an inconsistency flagged in the state-machine doc §2.15/§7.

---

## 7. Schema Reference: `wallet` (19 tables — this is the Finance module)

**Module/schema name mismatch:** the C# module is `Finance` (`Modules/Finance/...`); every one of its tables lives in a PostgreSQL schema literally named `wallet`. There is no separate `finance` schema.

### 7.1 `wallet.wallet_accounts` (`WalletAccount`)
ownerId (loose Guid), ownerType (plain string, default `USER`: USER/BUSINESS/PROVIDER/PLATFORM), accountType (plain string, default `MAIN`: MAIN/ESCROW/COMMISSION/TAX), currency varchar(3, default ETB), balance/lockedBalance/pendingWithdrawalBalance (numeric), status (plain string, default `ACTIVE`: ACTIVE/SUSPENDED/CLOSED), isActive (bool), **rowVersion bytea** (a real optimistic-concurrency token — `IsConcurrencyToken()`, `ValueGeneratedOnAddOrUpdate()` — the only table in the whole schema using DB-level optimistic concurrency) + audit. Per coverage-audit §10.5: the platform commission wallet is looked up with two different `AccountType` string literals (`"COMMISSION"` vs `"PLATFORM_COMMISSION"`) across two escrow-computation code paths — only one path actually runs, but the inconsistent literal is real and unresolved.

### 7.2 `wallet.escrow_locks` (`EscrowLock`)
contractId (loose), walletAccountId (FK cascade), amount/originalAmount/releasedAmount (numeric), status (plain string, default `LOCKED`: LOCKED/RELEASED/PARTIALLY_RELEASED/DISPUTED/FORFEITED — this `DISPUTED` is unrelated to `Contract.Status`'s vestigial `DISPUTED`, per state-machine §2.12), lockedAt, releasedAt?, releaseReason? (text) + audit.

### 7.3 `wallet.escrow_rollovers` (`EscrowRollover`)
contractId (loose), appliedToEscrowLockId? (FK **set-null**), amount numeric(18,2), fromCycleNumber/toCycleNumber (int), excessRefunded numeric(18,2, default 0), status (plain string, default `AVAILABLE`: AVAILABLE/APPLIED/EXCESS_REFUNDED), appliedAt? + audit. Composite indexes on (contractId, status) and (contractId, toCycleNumber). This is the "current-cycle settlement rollover" mechanism added by migration `AddEscrowRolloverAndCurrentCycleSettlement` (2026-04-27) — an `AVAILABLE` row here left unresolved blocks two-party contract completion (state-machine §8.4).

### 7.4 `wallet.monthly_settlement_schedules` (`MonthlySettlementSchedule`)
contractId (loose), escrowLockId? (FK, no delete-behavior override), cycleNumber (int), cycleStartDate/cycleEndDate, settlementDate, dailyRate/cycleAmount/daysInCycle, status (plain string, default `PENDING`: PENDING/LOCKED/SETTLED/CANCELLED), isFinalSettlement (bool), escrowLockedAt?/settledAt? + audit. A `LOCKED` or overdue-`PENDING` row here blocks contract completion (state-machine §8.4 rule 2).

### 7.5 `wallet.settlement_cycles` / `settlement_payouts` / `settlement_payout_line_items` / `settlement_status_history`
- **`settlement_cycles`** (`SettlementCycle`): cycleReference varchar(32) unique, startDate/endDate, status (plain string, default `OPEN`: OPEN/PROCESSING/CLOSED) + audit. 1:N → `settlement_payouts` (cascade). Column widened for contract-scoped cycle references by migration `ExpandSettlementCycleReferenceForContractScopedCycles` (2026-04-28).
- **`settlement_payouts`** (`SettlementPayout`): settlementCycleId (FK cascade), providerId (loose), walletAccountId (FK cascade), walletTransactionId? (FK, no override), invoiceId? (FK, no override, `WithMany("LinkedPayouts")`), totalAmount/commissionDeducted/taxDeducted/netPayoutAmount (numeric), status (plain string, default `PENDING_ADMIN_APPROVAL`) + audit. 1:N → `settlement_payout_line_items` (cascade).
- **`settlement_payout_line_items`** (`SettlementPayoutLineItem`): settlementPayoutId (FK cascade), contractId (loose)/contractNumber (denormalized), vehicleId?/vehiclePlateNumber? (denormalized), periodStart/periodEnd, daysInPeriod (int), grossAmount/commissionRate/commissionAmount/netAmount (numeric) + audit.
- **`settlement_status_history`** (`SettlementStatusHistory`) — snake_case table (§2.2): settlement_cycle_id (FK cascade), from_status/to_status/trigger, triggered_by_user_id/type, changed_at, notes.

### 7.6 `wallet.commission_entries` (`CommissionEntry`)
contractId/providerId (loose), commissionType (plain string, default `CONTRACT_COMMISSION`: CONTRACT_COMMISSION/PENALTY/SUBSCRIPTION), commissionRate/commissionAmount/grossAmount (numeric), providerTierCode varchar(32), status (plain string, default `PENDING`: PENDING/SETTLED/CANCELLED), earnedAt, settledAt?/settlementPayoutId? + audit. Four admin-report query handlers (`GetCommissionReportQuery` and three siblings) read tables like this but are wired to **zero controllers** — unreachable via any API today (coverage-audit §10.5).

### 7.7 `wallet.wallet_ledger_transactions` / `wallet_ledger_entries`
Transaction (header): reference varchar(128) unique (**"transactionReference"** is the actual `[Column]` name for the `Reference` C# property — a naming mismatch between property and column), referenceId? (loose), transactionType varchar(32), totalAmount decimal(18,2), currency varchar(8), transactionDate, description (text) + audit. 1:N → `wallet_ledger_entries` (cascade, `Entries` nav).
Entry (double-entry lines): transactionId (FK cascade), walletAccountId (FK cascade, `LedgerEntries` nav), entryType varchar(10) (DEBIT/CREDIT presumably), amount decimal(18,2), currency varchar(8), relatedType varchar(32)?, notes? + audit.

### 7.8 `wallet.wallet_balance_snapshots` (`WalletBalanceSnapshot`)
walletAccountId (FK cascade), balance/lockedBalance/availableBalance (numeric), currency (text), snapshotType varchar(32), snapshotDate + audit.

### 7.9 `wallet.wallet_event_logs` (`WalletEventLog`)
transactionId? (FK **set-null**), walletAccountId? (FK **set-null**), actorId?/actorType varchar(32, default `SYSTEM`), eventType varchar(64), description?, eventPayload (jsonb) + audit (createdAt uses `HasDefaultValueSql("now()")` — the sole DB-side timestamp default in the whole schema besides a few MasterData booleans). Four indexes incl. two composite (actorType+createdAt, walletAccountId+createdAt).

### 7.10 `wallet.payment_intents` (`PaymentIntent`)
walletAccountId (FK cascade), amount (numeric), currency (text), paymentMethod varchar(32), status (plain string, default `PENDING`: PENDING/PROCESSING/COMPLETED/FAILED/CANCELLED/EXPIRED), transactionReference varchar(100), gatewayTransactionId varchar(100)?, returnUrl?, metadata (text)?, failureReason?, expiresAt?/completedAt? + audit. Backs the live Chapa/Telebirr/CBEBirr payment-gateway webhook flow.

### 7.11 `wallet.deposit_requests` (`DepositRequest`)
walletAccountId (FK restrict), platformBankAccountId? (FK restrict), ownerId/ownerType varchar(16), amount decimal(18,2), currency varchar(8), transactionNumber varchar(128), receiptUrl varchar(500)/receiptFileName?, status (plain string, default `PENDING_REVIEW`: PENDING_REVIEW/APPROVED/REJECTED), adminReviewedAt?/adminReviewedBy?, rejectionReason?, notes? + audit. Named index `IX_deposit_requests_transaction_number`.

### 7.12 `wallet.withdrawal_requests` (`WithdrawalRequest`)
walletAccountId (FK cascade), bankAccountId, bankAccountType varchar(16), bankCode/bankName, accountNumber/accountHolderName, amount decimal(18,2), currency varchar(8), status (plain string, default `PENDING_ADMIN_APPROVAL`), transactionReference varchar(128), gatewayTransactionId varchar(128)? (moved onto this table by migration `MoveGatewayTransactionIdToWithdrawalRequest`, 2026-03-27), processingMethod varchar(20)?, adminApprovedAt?/adminApprovedBy?, adminReceiptUrl?/adminTransactionNumber?, walletTransactionId?, rejectionReason?, notes? + audit. This table was itself re-added by a dedicated hotfix migration `AddWithdrawalRequestsTableHotfix` (2026-03-28) after the original schema needed correction — a real, if unglamorous, sign of iterative schema repair.

### 7.13 `wallet.refund_requests` (`RefundRequest`)
contractId/businessId (loose), requestedAmount/approvedAmount?/penaltyAmount?/netRefundAmount? (numeric), reason varchar(1000), requestedBy, status (plain string, default `PENDING_REVIEW`: PENDING_REVIEW/APPROVED/REJECTED/PROCESSING/PROCESSED/CANCELLED), reviewedAt?/reviewedBy?, rejectionReason?, processedAt?/processedTransactionId? + audit.

### 7.14 `wallet.provider_invoices` (`ProviderInvoice`)
providerId (loose), invoiceNumber varchar(100), invoiceDate, invoiceAmount (numeric), scanUrl varchar(500), status (plain string, default `PENDING`), isReceivedByFinance (bool), notes?/rejectedReason?, uploadedAt?/uploadedBy?, approvedAt?/approvedBy? + audit. 1:N → `settlement_payouts` (`LinkedPayouts` nav, no delete-behavior override). This is the **provider-submitted** invoice-approval workflow that inverts epic-09's system-generates-invoice assumption (coverage-audit epic matrix, row 09).

### 7.15 `wallet.platform_bank_accounts` (`PlatformBankAccount`)
bankCode/bankName, accountNumber/accountHolderName, currency varchar(8), displayOrder (int), isActive (bool) + audit. Unique on (bankCode, accountNumber).

---

## 8. Schema Reference: `delivery` (10 tables)

OTP-gated delivery, plus a **separate** return-trip flow with its own OTP and vehicle inspection checklist — outside epic-07's original one-way-delivery scope.

### 8.1 `delivery.delivery_sessions` / `delivery_return_sessions`
Both: businessId/providerId/vehicleId/contractId (all loose Guids, no FK — `DeliverySession` has no ties back to `ContractVehicleAssignment` by FK either, only by convention), sessionReference varchar(20), status (plain string, default `SCHEDULED`), scheduledTime, actualTime?, driverName/driverPhone (session only)/locationAddress + audit. **Confirmed: neither table has a latitude/longitude column** — the coverage audit's finding that `15_Delivery_OTP_Verification_Flow_Specification.md`'s GPS-arrival-confirmation assumption is fictional holds at the schema level too. `DeliverySession` 1:1 → `Handover`, 1:1 → `InspectionChecklist` (restrict), 1:N → `OTPs` (cascade). `DeliveryReturnSession` 1:1 → `InspectionChecklist` (restrict), 1:N → `OTPs` (cascade).

### 8.2 `delivery.delivery_otps` / `return_otps`
Both: {session}Id (FK cascade), code varchar(6) (column width was fixed by `FixDeliveryOtpRecipientRoleColumnSize`, 2026-02-23), recipientRole varchar(32), expiresAt, isUsed (bool), usedAt? + audit. `DeliveryOTP` required-FK-references `DeliverySession`; `ReturnOTP` references `DeliveryReturnSession`. OTP codes are **never** returned by any API response — confirmed by-design via `GenerateOTPResponseDto`'s own "not exposed for security" comment (coverage-audit §10.5).

### 8.3 `delivery.delivery_vehicle_handovers` (`DeliveryVehicleHandover`)
deliverySessionId (FK **unique** 1:1, cascade), handoverType varchar(32, default `DELIVERY`), handoverTime, front/back/left/right/interiorPhotoUrl (varchar 500, all required), odometerReading (**double**, not int/decimal), fuelLevel varchar(20), notes varchar(1000)? + audit.

### 8.4 `delivery.vehicle_inspection_checklists` / `vehicle_inspection_checklist_responses`
Checklist: deliverySessionId?/returnSessionId? (both FK **unique**, restrict — a checklist attaches to exactly one of the two session types), handoverType varchar(16, default `DELIVERY`), status (plain string, default `SUBMITTED`), submittedAt/submittedByName varchar(128), reviewedByName?, hasWarningFlags (bool, default false), notes varchar(1000)? + audit. 1:N → `vehicle_inspection_checklist_responses` (cascade).
Response: checklistId (FK cascade), templateItemId (loose, references `masterdata.checklist_template_items`, no cross-module FK), responseValue varchar(500), hasWarning (bool, default false), warningNote? + audit. Unique on (checklistId, templateItemId).

### 8.5 `delivery.delivery_sla_violations` (`DeliverySLAViolation`)
deliverySessionId (FK cascade), violationType varchar(32), description (text), penaltyAmount? + audit. **Zero writers anywhere** — coverage-audit §10.5 confirms this table exists in the domain model/DbContext/migrations but nothing ever inserts into it.

### 8.6 `delivery.delivery_failure_reason` (`DeliveryFailureReason`)
code varchar(64) unique, category varchar(32, default `OPERATIONAL`), description (text), penaltyApplicable (default false), isActive (default true) + audit.

### 8.7 `delivery.delivery_event_logs` (`DeliveryEventLog`)
deliverySessionId? (loose), actorId?, eventType varchar(64), description (text) + audit. Also confirmed a zero-writer table alongside `DeliveryVehicleHandover`'s siblings per the audit — modeled, never populated.

---

## 9. Schema Reference: `notifications` (11 tables)

Full admin-configurable multi-channel notification system: email/SMS/in-app, each with a template table, a "sent" record table, and (email/SMS only) an outbox-retry table; plus provider-credential config tables for email/SMS/FCM push.

### 9.1 Provider configs: `email_provider_configs` / `sms_provider_configs` / `fcm_provider_configs`
All three: displayName varchar(128), providerType varchar(64), isEnabled (bool), settings (jsonb), + channel-specific credential fields (SMTP host/port/ssl/username/passwordEncrypted for email; baseUrl/apiKeyEncrypted/senderId for SMS; projectId/clientEmail/clientId/privateKeyEncrypted/privateKeyId/clientX509CertUrl for FCM, i.e. a full Firebase service-account credential set) + audit. Indexed on isEnabled + providerType each.

### 9.2 Templates: `email_notification_templates` / `sms_notification_templates` / `in_app_notification_templates`
All three: code varchar(100), name varchar(200), language varchar(10), {subject/body/title}Template, variables (jsonb), isActive (bool) + audit. Unique on (code, language) for all three.

### 9.3 Sent records: `email_notifications` / `sms_notifications` / `in_app_notifications`
Email: templateId (FK restrict), templateCode (denormalized), emailAddress varchar(255), subject varchar(300), body (text), sourceService varchar(64), eventType varchar(128), entityId?, payload (jsonb), deliveryStatus varchar(32), deliveredAt?/failureReason? + audit.
SMS: same shape, `phoneNumber` instead of `emailAddress`, `messageBody` instead of `subject`+`body`.
InApp: templateId (FK restrict), **userAccountId (FK restrict, required)** — the only "sent record" table with a real FK to `identity.user_accounts` (email/SMS use loose recipient addresses instead), title varchar(300), body (text), isRead (bool), readAt? + audit. Composite indexes on (userAccountId, isDeleted) and (userAccountId, isRead).

### 9.4 Outbox/retry: `email_notification_outbox` / `sms_notification_outbox`
Both: {channel}NotificationId (FK cascade to the sent-record row), retryCount (int), nextRetryAt, lastAttemptAt?/lastError?, sentAt?, status varchar(32) (via a `NotificationOutboxStatuses` string-constants class, not an enum), + duplicated copies of recipient/subject/body/payload/eventType/entityId/sourceService (denormalized for retry without a join). Composite index on (status, nextRetryAt) on both — the retry-scheduler's query shape.

---

## 10. Migration History (35 migrations, 2026-02-12 → 2026-07-08)

| Date | Migration | What changed |
|---|---|---|
| 02-12 | `InitialCreate` | All 6 original schemas + the bulk of the 119-table shape |
| 02-18 | `AddRFQLineItemNewFields` | RFQLineItem extensions |
| 02-19 | `UpdateVehicleAssignmentAndSettlementLifecycle` | Vehicle assignment + settlement status refinement |
| 02-20 | `AddContractRFQEnhancements` | Contract/RFQ shape additions |
| 02-20 | `AddAdminWalletOperationsSupport` | Admin wallet ops |
| 02-21 | `AddProviderLicenseNumber` | `providers.licenseNumber` |
| 02-22 | `RemoveUniqueConstraintFromRFQBids` | Dropped the (rfqId, providerId) unique index — multi-line-item bids per provider confirmed legitimate |
| 02-23 | `FixDeliveryOtpRecipientRoleColumnSize` | OTP column width fix |
| 03-05 | `AddNotificationChannelPersistence` | Introduced the `notifications` schema (11 tables) |
| 03-06 | `AddEmailOtpToUserAccounts` | Email OTP fields on `user_accounts` |
| 03-06 | `RemoveSmsSenderIdLengthLimit` | SMS sender-id column widened |
| 03-08 | `AddPushBindingToUserDevices` | Push token/platform fields on `user_devices` |
| 03-09 | `AddFcmProviderConfigs` | `fcm_provider_configs` table |
| 03-17 | `AddBusinessProfileExtendedFields` | Business profile address/contact fields |
| 03-18 | `AddDedicatedBankAccountTables` | `business_bank_accounts` / `provider_bank_accounts` |
| 03-25 | `AddChapaPaymentIntegration` | `payment_intents` and Chapa gateway support |
| 03-27 | `MoveGatewayTransactionIdToWithdrawalRequest` | Moved a column onto `withdrawal_requests` |
| 03-28 | `AddWithdrawalRequestsTableHotfix` | Re-adds `withdrawal_requests` — a corrective hotfix migration |
| 04-01 | `AddDepositRequestsWithdrawalLockingAndAdminProcessing` | `deposit_requests` + admin processing fields |
| 04-03 | `AddVehicleInspectionChecklist` | Checklist tables |
| 04-11 | `AddProviderVatAndInvoices` | `provider_invoices`, VAT fields |
| 04-11 | `AddEarlyReturnNotice` | Creates `early_return_notices` — **later orphaned from the EF model, see §2.6** |
| 04-12 | `AddReturnOTPAndFixReturnSession` | `return_otps`, return-session fixes; drops+recreates `early_return_notices` |
| 04-14 | `AddContractCompletionRequestsTable` | `contract_completion_requests` |
| 04-27 | `AddEscrowRolloverAndCurrentCycleSettlement` | `escrow_rollovers` |
| 04-28 | `ExpandSettlementCycleReferenceForContractScopedCycles` | Widened `settlement_cycles.cycleReference` |
| 05-03 | `BackfillNotificationPreferencesDefault` | Data backfill, not a shape change |
| 05-13 | `AddBanksTable` | `banks` |
| 05-15 | `AddStatusHistoryTables` | The 5 snake_case status-history tables (§2.2) |
| 05-20 | `AllowNullPreviousStatusInBidHistory` | Nullable `previousStatus` on `rfq_bid_history` |
| 06-13 | `AddPlatformBankAccountsAndVehicleMaintenance` | `platform_bank_accounts`, vehicle maintenance fields |
| 06-16 | `AddDirectVehicleRental` | Full Direct Rental table set (epic-21) |
| 06-26 | `AddDirectRentalContractLineItemLink` | `contract_line_items.directRentalRequestLineItemId` |
| 07-01 | `AddDirectRentalRequestStatusHistory` | Direct-rental status history |
| 07-08 | `AddContractTermsVersioningAndAcceptance` | `contract_terms_versions`, `contract_terms_acceptances` — the dual-OTP e-signature mechanism |

---

## 11. Companion Documents

- **`database/database-erd.md`** — Mermaid entity-relationship diagrams per schema, generated from the same FK data in this document.
- **`database/database-schema-design.md`** — design rationale/conventions companion: why the naming is inconsistent, the versioned-policy pattern, the soft-delete/audit-column convention, and a consolidated "trust this over the entity's own doc comment" checklist. Does not repeat this document's per-table column listings — cross-references them.
- **`MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md`** — the authoritative contract/line-item/vehicle-assignment state machine (18 real statuses, transition matrix, dead-code inventory).
- **`project-docs/18_Implementation_Coverage_Audit.md`** — the full cross-surface audit this document's drift callouts are drawn from.
