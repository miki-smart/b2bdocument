# Master Data & Settings Module — Specification

**Module Name:** Master Data & Settings
**Version:** 2.0 (rewritten against running code)
**Last verified against code:** 2026-07-23
**Location:** `Modules/MasterData/**` inside `Marketplace.API` (.NET 9 modular monolith) — schema `masterdata` in the single shared PostgreSQL database
**Related documents:** `markdown-documentations/Master_Data_Specification.md` (design-level companion doc — accurate on schema shape and intent; this spec adds exact field lists and, critically, which pieces are actually wired into live money/legal flows vs. which are seeded-but-dormant), `backlog/mvp/epic-12-risk-trust-scoring.md` (rewritten 2026-07-23 — the tier-threshold/commission findings below are consistent with it), `project-docs/18_Implementation_Coverage_Audit.md` §5/§10.2/§10.5

---

## What changed in this rewrite

The previous version of this document (v1.1, Dec 2025) got the **shape** of the schema roughly right but invented implementation details that don't match code, and — more importantly — presented several engines as fully wired into production money/legal flows when they are actually **seeded, fully coded, and never called**. Specifically corrected in this rewrite:

- **`CommissionStrategyVersion`/`CommissionStrategyRule` is not the source of truth for commission rates at contract time.** Only **one** `CommissionStrategyRule` row exists in the seed data (a single `SILVER`, `IsDefault=true` fallback). The rate actually applied to a contract is read directly off **`ProviderTier.CommissionRate`** by tier code — the versioned strategy engine is present in the schema and has a full admin CRUD API, but the real money path bypasses it. See §5.1.
- **`EscrowPolicyRule`'s tier-aware lock-period calculation (`CalculateEscrowLockDaysAsync`) is real, fully implemented, and has exactly one caller — a handler that isn't on the live contract-creation path.** The Contracts module's own event handler that actually runs (`ContractCreatedEventHandler`) uses a hardcoded 30-day cap instead. See §5.2 and `Contracts_Module.md` §"Known Gaps".
- **`ContractPolicyRule`'s seeded per-scenario penalty rules are never read by the cross-module consumer.** `IMasterDataService.GetActiveContractPolicyAsync` (what `Modules/Contracts` actually calls at contract creation) returns a **hardcoded** dynamic object with a code comment reading *"TODO: Parse actual rules from policy.Rules collection"* — the real `ContractPolicyRule` rows (seeded, all `NONE` penalty type for MVP) are fetched but then ignored. See §5.3.
- **`BusinessTier`/`BusinessTierRule` has no assignment mechanism at all** — unlike `ProviderTier`, there is no `BusinessTierAssignment` history entity, no admin "assign business to tier" endpoint, and `TierCalculationService.CalculateBusinessTierAsync` (which *would* compute one) has zero production callers. The only real per-business tier signal is a plain `BusinessProfile.BusinessTierCode` string defaulting to `"STANDARD"` at onboarding — and the one place that reads a business's tier for money purposes (`IdentityService.GetBusinessSnapshotAsync`, used at contract creation) doesn't even read that field; it uses `business.TinNumber` as a placeholder tier code, with a code comment admitting it. See §5.4.
- **`ProviderTierRule`/`TierCalculationService` (the "hybrid" active-vehicle-count model) does not exist as described.** v1.1 documented a `min_active_vehicles` column and a fleet-size-plus-trust-score qualification rule. There is **no `MinActiveVehicles` column anywhere** in `ProviderTierRule` — the real hybrid model uses `MinTrustScore`/`MaxTrustScore` + `MinCompletedContracts` + `MaxCancellationRate` + `MinOnTimeRate`, and `TierCalculationService.CalculateProviderTierAsync` itself only actually checks the trust-score range (it accepts an `activeVehicleCount` parameter but never uses it in the qualification check). This service also has **zero production callers** — see §5.5 and `epic-12-risk-trust-scoring.md` for the full picture, including the *second*, independently-hardcoded tier-threshold scheme (`TrustScore.CalculateTier()`) that disagrees with the seeded one.
- **`ProfileRequirement` is the one engine in this whole module that is genuinely, verifiably live** — `ProfileCompletionService` (Identity module) reads `profile_requirements` at runtime to compute a provider's/business's profile-completion percentage. This is real, unlike the tier/commission/policy engines above.
- Corrected the table count and removed invented tables (v1.1 claimed 23-24 tables including a nonexistent dedicated geography CRUD API); the real table list, with real column names, is in §3.
- All fictional C#/SQL code samples (cache-based `SettingsService`, `IPolicyRepository`, `MasterDataCache`, hand-rolled SQL against `masterdata.provider_tier_rule`) have been removed — none of that code exists. Real class/method names are used throughout instead.

---

## 1. Overview

### Purpose

The MasterData module is the **configuration backbone** of the platform: slow-changing, admin-editable, non-transactional data that other modules read (never own) to drive pricing, tiering, escrow/settlement mechanics, contract policy, KYC/KYB requirements, checklist templates, and geography/lookup reference data. Per the module's own design principle (echoed accurately in `markdown-documentations/Master_Data_Specification.md`): **"do not hardcode business rules in code."** In practice, as detailed in §5, that principle is only fully honored for a subset of the module — several of the versioned "policy engines" exist exactly as designed in the schema and admin API, but the code paths that were supposed to *consume* them at money/legal-decision time were built against a hardcoded shortcut instead, and the versioned tables were never wired up. This document treats that gap as the central fact to document, not an incidental footnote.

### Responsibilities

- **Lookup & localization** — reusable enumeration families (`lookup_types`/`lookups`) plus multi-language translation tables, consumed mainly by the Marketplace module for RFQ line-item fields (vehicle type, engine type, contract period, …).
- **Settings** — flat key/value configuration (`settings`), typed by a `valueType` discriminator (`NUMBER`/`STRING`/`BOOLEAN`/`JSON`).
- **Versioned financial policy** — `CommissionStrategyVersion/Rule`, `EscrowPolicyVersion/Rule`, `SettlementPolicyVersion/Rule` — schema and full CRUD/versioning API exist; actual production usage varies per-engine (§5).
- **Versioned contract policy** — `ContractPolicyVersion/Rule` (penalty rules per scenario/tier/party) — schema and CRUD exist; production usage is stubbed (§5.3).
- **Tiering** — `ProviderTier/ProviderTierRule` (real, admin-CRUD, commission-rate source of truth by tier code) and `BusinessTier/BusinessTierRule` (schema exists, essentially unused in practice — §5.4).
- **Contract terms versioning** — `ContractTermsVersion` (real, actively consumed by the Contracts module's dual-party OTP e-signature flow).
- **Compliance configuration** — `DocumentType`, `KYCRequirement` (real, consumed by Identity/onboarding flows) and `ProfileRequirement` (real, consumed by `ProfileCompletionService`).
- **Checklist templates** — `ChecklistTemplateItem` (real, consumed by the Delivery module's vehicle-inspection checklist).
- **Banking reference data** — `Bank` (real, replaces an earlier `BANK` lookup-type approach; maps to Chapa's numeric bank codes for payouts).
- **Geography** — `Country/Region/City` (schema exists with full navigation; city data is also separately seeded as a plain `CITY` lookup-type used by the mobile/RFQ city picker — the two geography representations coexist, see §3.7).

---

## 2. Real Module Structure

```
Modules/MasterData/
├── Domain/
│   ├── Entities/
│   │   ├── LookupType.cs, Lookup.cs, LookupTypeTranslation.cs, LookupTranslation.cs
│   │   ├── Settings.cs, SettingsTranslation.cs
│   │   ├── CommissionStrategyVersion.cs, CommissionStrategyRule.cs
│   │   ├── EscrowPolicyVersion.cs, EscrowPolicyRule.cs
│   │   ├── SettlementPolicyVersion.cs, SettlementPolicyRule.cs
│   │   ├── ContractPolicyVersion.cs, ContractPolicyRule.cs
│   │   ├── ContractTermsVersion.cs
│   │   ├── ProviderTier.cs, ProviderTierRule.cs
│   │   ├── BusinessTier.cs, BusinessTierRule.cs
│   │   ├── DocumentType.cs, KYCRequirement.cs, ProfileRequirement.cs
│   │   ├── ChecklistTemplateItem.cs
│   │   ├── Bank.cs
│   │   ├── Country.cs, Region.cs, City.cs
│   │   └── Foo.cs                          — unused placeholder entity, dead file
│   ├── Repositories/                       — I*Repository interfaces (domain-level, narrower than Application/Contracts versions)
│   └── Services/
│       └── ITierCalculationService.cs / TierCalculationService.cs   — DI-registered, zero production callers (§5.5)
│
├── Application/
│   ├── Abstractions/IMasterDataService.cs  — the cross-module surface Contracts actually calls (§5.3)
│   ├── Contracts/                          — I*Repository + IMasterDataUnitOfWork (the real cross-module contract surface)
│   ├── Lookups/, b2bSettings/, Countries/, DocumentTypes/, KycRequirements/,
│   │   CommissionStrategies/, EscrowPolicies/, SettlementPolicies/, ContractPolicies/,
│   │   ProviderTiers/, BusinessTiers/, ChecklistTemplateItems/, ContractTermsVersions/ (each under Application root)
│   │       — each a Commands/Queries/DTOs vertical slice, one per admin-manageable entity group
│   └── Shared/Mappings/                    — AutoMapper profiles, one per entity group
│
└── Infrastructure/
    ├── Configurations/                     — EF Core mappings (MasterDataConfigurations.cs, MasterDataPoliciesConfigurations.cs, ChecklistTemplateItemConfiguration.cs)
    ├── Persistence/Repositories/            — Bank, BusinessTier, ChecklistTemplateItem, DocumentType, ProfileRequirement, ProviderTier
    ├── Repositories/                        — CommissionStrategy, ContractPolicy, ContractTermsVersion, Country, EscrowPolicy, KYCRequirement, Lookup, LookupType, Settings, SettlementPolicy
    └── Services/MasterDataService.cs        — implements IMasterDataService (the stubbed contract-policy consumer, §5.3)
```

`MasterDataModuleExtensions.AddMasterDataModule` registers exactly one domain service: `ITierCalculationService` → `TierCalculationService`. Everything else in the module is repository/CQRS wiring picked up by the app's generic MediatR/AutoMapper assembly scanning — there is no bespoke caching layer (`IMemoryCache`, cache-invalidation events, etc. described in v1.1 do not exist anywhere in this module).

---

## 3. Real Database Schema (`masterdata` schema)

### 3.1 Lookup & localization
| Table | Key columns |
|---|---|
| `lookup_types` | `code`, `name`, `description`, `isActive`, `displayOrder` |
| `lookups` | `lookupTypeId` (FK), `code`, `value`, `metadata` (nullable JSON string), `sortOrder`, `isActive` |
| `lookup_type_translations` | per-language name/description for a `LookupType` |
| `lookup_translations` | per-language value for a `Lookup` |

### 3.2 Settings
| Table | Key columns |
|---|---|
| `settings` | `key`, `value` (string, parsed via `GetIntValue()`/`GetDecimalValue()`/`GetBoolValue()` helpers), `valueType` (`NUMBER`/`STRING`/`BOOLEAN`/`JSON`), `description`, `isActive` |
| `settings_translations` | per-language label/description for admin UI display only — does not affect runtime logic |

### 3.3 Commission strategy (versioned — §5.1 for real-vs-seeded usage)
| Table | Key columns |
|---|---|
| `commission_strategy_versions` | `versionNumber`, `name`, `description`, `effectiveFrom`, `effectiveTo`, `isActive` |
| `commission_strategy_rules` | `strategyVersionId` (FK), **`providerTierId`** (FK to `ProviderTier` — the rate itself now lives on `ProviderTier.CommissionRate`, not on this row), `regionCode`, `vehicleCategoryCode`, `commissionType` (`PERCENTAGE`/`FLAT`/`HYBRID`), `flatAmount`, `minCommissionAmount`, `maxCommissionAmount`, `isDefault` |

### 3.4 Escrow policy (versioned — §5.2 for real-vs-seeded usage)
| Table | Key columns |
|---|---|
| `escrow_policy_versions` | `versionNumber`, `name`, `description`, `effectiveFrom`, `effectiveTo`, `isActive` |
| `escrow_policy_rules` | `escrowPolicyVersionId` (FK), `businessTierCode` (nullable string, matched against `BusinessProfile.BusinessTierCode` when this engine *is* invoked), `contractPeriodCode` (`SHORT_TERM`/`LONG_TERM`), `lockPeriodDays` (0 = use actual contract duration) |

### 3.5 Settlement policy (versioned — §5.6 for real-vs-seeded usage)
| Table | Key columns |
|---|---|
| `settlement_policy_versions` | `versionNumber`, `name`, `description`, `effectiveFrom`, `effectiveTo`, `isActive` |
| `settlement_policy_rules` | `settlementPolicyVersionId` (FK), `providerTierCode` (nullable), `settlementFrequency` (`DAILY`/`WEEKLY`/`BIWEEKLY`/`MONTHLY`), `payoutDelayDays`, `minPayoutAmount` |

### 3.6 Contract policy (versioned — §5.3 for real-vs-seeded usage)
| Table | Key columns |
|---|---|
| `contract_policy_versions` | `versionNumber`, `name`, `description`, `effectiveFrom`, `effectiveTo`, `isActive` |
| `contract_policy_rules` | `contractPolicyVersionId` (FK), `scenarioCode` (`EARLY_TERMINATION`/`EARLY_RETURN`/`NO_SHOW`/`BREAKDOWN`/`CANCELLATION`), `businessTierCode`, `providerTierCode`, `penaltyType` (`PERCENTAGE`/`FLAT`/`NONE`), `penaltyValue`, `maxPenaltyAmount`, `gracePeriodHours`, `applyToParty` (`PROVIDER`/`BUSINESS`/`BOTH`/`PLATFORM`) |

### 3.7 Contract terms versioning (real — consumed by the Contracts module's dual-OTP signing)
| Table | Key columns |
|---|---|
| `contract_terms_versions` | `sourceType` (`RFQ`/`DIRECT_RENTAL` — separate version lineages per source), `versionNumber`, `name`, `description`, `termsBody` (raw HTML), `contentHash` (SHA-256 of `termsBody`), `effectiveFrom`, `effectiveTo`, `isActive`, `supersedesVersionId` |

### 3.8 Tiering
| Table | Key columns |
|---|---|
| `provider_tiers` | `code` (`BRONZE`/`SILVER`/`GOLD`/`PLATINUM`), `name`, `description`, `displayOrder`, `colorCode`, **`commissionRate`** (decimal 0–1 — the real, live-read commission rate per tier), `isActive` |
| `provider_tier_rules` | `providerTierId` (FK), `minTrustScore`, `maxTrustScore`, `minCompletedContracts`, `maxCancellationRate`, `minOnTimeRate`, `isDefaultForNew` — **no `minActiveVehicles` column exists** |
| `business_tiers` | `code` (`STANDARD`/`BUSINESS_PRO`/`ENTERPRISE`/`GOV_NGO`), `name`, `description`, `maxRfqsPerMonth` (nullable = unlimited), `maxActiveContracts`, `maxVehiclesPerRfq`, `displayOrder`, `colorCode`, `isActive` |
| `business_tier_rules` | `businessTierId` (FK), `minMonthlyRfqs`, `maxMonthlyRfqs`, `minActiveContracts`, `minMonthlySpend`, `isDefaultForNew` — qualification is by RFQ/contract volume and spend, **not** fleet size (v1.1's "fleet size" model was invented) |

### 3.9 Compliance
| Table | Key columns |
|---|---|
| `document_types` | `code`, `name`, `description`, `category`, `isPersonal`/`isBusiness`/`isVehicle` flags, `requiresExpiry`, `acceptedFormats` (list, default `.pdf/.jpg/.jpeg/.png`), `maxFileSizeMb` (default 10), `isActive` |
| `kyc_requirements` | `actorType` (`PROVIDER`/`BUSINESS`/`VEHICLE`/`DRIVER`), `actorSubtype` (nullable, e.g. `INDIVIDUAL`/`COMPANY`/`AGENT`), `tierCode` (nullable — additional tier-gated requirements, e.g. Gold/Platinum insurance), `documentTypeId` (FK), `isMandatory`, `minValidityDays`, `isActive` |
| `profile_requirements` | `entityType` (`PROVIDER`/`BUSINESS`), `requirementType` (`DOCUMENT`/`ATTRIBUTE`/`VERIFICATION`), `code`, `displayName`, `description`, `isMandatory`, `sortOrder`, `validationRule` (JSON, e.g. `{"property":"Profile.BankAccountNumber","checkNotNull":true}`), `referenceCode`, `isActive` — the one engine confirmed genuinely live, see §5.7 |

### 3.10 Checklist templates
| Table | Key columns |
|---|---|
| `checklist_template_items` | `code`, `label`, `description`, `itemType` (`BOOL`/`ENUM`/`NUMERIC`/`TEXT`), `enumOptions` (JSON array), `isRequired`, `appliesToEvOnly`, `appliesToReturn`, `isWarningTrigger`, `warningThreshold`, `sortOrder`, `isActive` — 18 seeded items (fuel/battery, odometer, damage, tyres, lights, dashboard warnings, interior, tools, documents, keys, driver-ID, EV charging cable/adapter) |

### 3.11 Banking reference data
| Table | Key columns |
|---|---|
| `banks` | `code` (internal, e.g. `CBE`), `chapaCode` (nullable — Chapa's numeric bank ID, admin-mapped post-seed), `shortName`, `name`, `logoUrl`, `isActive` — 14 seeded Ethiopian banks. A legacy `BANK` `LookupType` is deliberately **deactivated** (not deleted) by the seeder once this table is populated, so lookups keep historical integrity but new clients stop fetching banks via the generic lookup endpoint. |

### 3.12 Geography
| Table | Key columns |
|---|---|
| `countries` | `code`, `name`, `isoAlpha2`, `isoAlpha3`, `phoneCode`, `currency`, `displayOrder`, `isActive` — seeded with 7 countries (US, GB, TR, DE, FR, AE, SA) — **no Ethiopia row**, despite the platform being Ethiopia-first; city/region data for actual operations instead lives in the separate `CITY` lookup-type (below). |
| `regions` | `countryId` (FK), `code`, `name`, `displayOrder`, `isActive` |
| `cities` | `regionId` (FK), `name`, `code`, `latitude`/`longitude` (nullable decimals), `displayOrder`, `isActive` |

**Two coexisting geography representations:** the `Country/Region/City` entity graph above is fully modeled but seeded only with non-Ethiopian countries and has no admin-facing regions/cities CRUD controller found in `Controllers/` (only `CountriesController` exists, `api/countries`). The actual Ethiopian cities used by RFQ pickup/dropoff pickers and the mobile reference-data endpoint (`GET .../cities`, `GetLookupsByTypeCodeQuery("CITY")`) come from the **`CITY` lookup-type** instead (8 seeded cities: Addis Ababa, Dire Dawa, Mekelle, Gondar, Awasa, Bahir Dar, Jimma, Dessie). Treat `Country/Region/City` as scaffolding for future multi-country expansion, not the live geography source for Ethiopian operations today.

---

## 4. Real API Surface (Admin/config controllers, all under `Controllers/`)

| Controller | Route prefix | Notes |
|---|---|---|
| `LookupTypesController` | `api/lookup-types` | Full CRUD on types + nested lookups (`{typeId}/lookups`, `by-code/{typeCode}/lookups`) |
| `SettingsController` | `api/settings` | `GET` (list), `GET {key}`, `PUT {key}` — no create/delete, settings are seed-defined |
| `CommissionStrategiesController` | `api/commission-strategies` | Versions CRUD + activate, nested rules CRUD |
| `EscrowPoliciesController` | `api/escrow-policies` | Versions CRUD + activate, nested rules CRUD |
| `SettlementPoliciesController` | `api/settlement-policies` | Versions CRUD + activate, nested rules CRUD |
| `ContractPoliciesController` | `api/contract-policies` | Versions CRUD + activate, nested rules CRUD |
| `ContractTermsController` | `api/contract-terms` | `active`, versions CRUD + activate |
| `ProviderTiersController` | `api/provider-tiers` | Tier CRUD (Admin-only) + `POST providers/{providerId}/tier-assignment` (Admin-only, manual — §5.5) |
| `BusinessTiersController` | `api/business-tiers` | Tier CRUD only — **no assignment endpoint exists** (§5.4) |
| `DocumentTypesController` | `api/document-types` | CRUD |
| `KYCRequirementsController` | `api/kyc-requirements` | CRUD |
| `CountriesController` | `api/countries` | CRUD — no dedicated regions/cities controller found |
| `Admin/AdminChecklistTemplateController` | `api/admin/checklist-template` | CRUD + activate/deactivate |
| `Finance/AdminBankController` | (lives in Finance module's controller folder, but operates on MasterData's `Bank` entity) | Bank CRUD + Chapa-code mapping |

All admin-mutation endpoints (`POST`/`PUT`/`PUT .../activate`/`DELETE`) are `[Authorize(Roles = "ADMIN")]`; `GET` endpoints are generally open to any authenticated caller (used by RFQ creation forms, onboarding wizards, etc. across the web app and both mobile apps).

---

## 5. Engine-by-engine: seeded/CRUD-complete vs. actually wired into production decisions

This is the section that matters most for anyone deciding whether to trust "the commission is versioned" or "the escrow lock is tier-aware" as an operational fact.

### 5.1 Commission — `ProviderTier.CommissionRate` is the real source, `CommissionStrategyVersion/Rule` is dormant

Seed data (`MasterDataSeeder.SeedProviderTiersAsync` / `SeedCommissionStrategiesAsync`): `ProviderTier` gets exactly 4 rows with hardcoded commission rates — **Bronze 10%, Silver 8%, Gold 6%, Platinum 5%** (`0.10m`/`0.08m`/`0.06m`/`0.05m`). Separately, `CommissionStrategyVersion` gets exactly **one** row ("Default Commission Strategy", v1, active) with exactly **one** `CommissionStrategyRule` row (`providerTierId = SILVER`, `isDefault = true`) — i.e. the versioned rule table is seeded as a single fallback record, not a per-tier rate table (`CommissionStrategyRule.CalculateCommission()` reads the rate from `ProviderTier.CommissionRate` via its own `ProviderTier` navigation property — the rule row no longer carries its own percentage at all).

The real read path at contract creation is `IdentityService.GetProviderSnapshotAsync` (`Modules/Identity/Infrastructure/Services/IdentityService.cs`): it resolves the provider's current `ProviderTierAssignment`, then calls `_masterDataUnitOfWork.ProviderTiers.GetByCodeAsync(tierCode)` and reads `.CommissionRate` directly — **it never touches `CommissionStrategyVersion`/`CommissionStrategyRule` at all.** The admin CRUD API for commission strategies is fully functional (create/activate new versions, add per-tier/region/vehicle-category rules) but changing it has **no effect** on the commission actually applied to new contracts unless `ProviderTier.CommissionRate` itself is also edited via `ProviderTiersController`.

### 5.2 Escrow — the tier-aware calculator is real but only wired to a dead code path

`EscrowPolicyRepository.CalculateEscrowLockDaysAsync(contractDurationDays, businessTierCode)` is a fully correct implementation: looks up the active `EscrowPolicyVersion`, matches rules by `contractPeriodCode` (`SHORT_TERM` if duration < 30 days, else `LONG_TERM`) with tier-specific rules taking priority over tier-agnostic (`BusinessTierCode == null`) fallback rules, and falls back to a hardcoded 30-day cap only if no active policy/rule exists at all. Seed data: one active `EscrowPolicyVersion` with two rules — `SHORT_TERM` → `lockPeriodDays=0` (use actual duration), `LONG_TERM` → `lockPeriodDays=30` — neither rule is tier-specific in the current seed, so the tier-awareness is schema-ready but not yet exercised even by seed data.

Per `Contracts_Module.md`'s own audit finding: **`CalculateEscrowLockDaysAsync` has exactly one caller in the entire codebase — `FinanceBidAwardedEventHandler`** — and that handler is not the one that actually runs for real contract creation; the live path is `ContractCreatedEventHandler`, which computes the escrow lock with its own hardcoded 30-day-cap constant, independent of this repository entirely. So: a real, correct, tier-aware escrow calculator exists, is fully seeded, and is simply not on the path that runs.

### 5.3 Contract policy — seeded rules exist, the cross-module consumer ignores them

Seed data (`SeedContractPoliciesAsync`): one active `ContractPolicyVersion` with 5 `ContractPolicyRule` rows, **all `penaltyType = "NONE"`**, `gracePeriodHours` ranging 0–168 (`EARLY_TERMINATION`/`EARLY_RETURN`/`CANCELLATION` → 168h/7-day grace, `NO_SHOW` → 0h, `BREAKDOWN` → 24h) — i.e. an intentionally toothless MVP policy (no real penalties yet), which is itself a reasonable business decision.

The problem is structural, not just "penalties are zero": `IMasterDataService.GetActiveContractPolicyAsync` (`Modules/MasterData/Infrastructure/Services/MasterDataService.cs`) — the **only** method this module exposes for the Contracts module to consult policy at contract-creation time (used to build `ContractPolicySnapshot`) — fetches the active `ContractPolicyVersion` but then returns a **hardcoded** `rulesObject` (`CancellationPenaltyRate = 0.10m`, `EarlyReturnPenaltyRate = 0.05m`, `MinimumNoticeDays = 1`, `MaximumExtensionDays = 30`) with an explicit `// TODO: Parse actual rules from policy.Rules collection` comment. In other words: **the numbers snapshotted onto every contract's policy record today are not the seeded `ContractPolicyRule` rows at all** — they're a different, also-hardcoded set of values baked into this service, and they don't match the seed data's `NONE`-penalty scenarios. Editing `ContractPolicyRule` via the admin API changes nothing about what gets snapshotted onto new contracts until this method is rewritten to actually parse `policy.Rules`.

### 5.4 Business tiering — schema without an assignment mechanism

Unlike `ProviderTier` (which has `ProviderTierAssignment`, an append-only history entity on the `Provider` aggregate — see Identity module), **there is no `BusinessTierAssignment` entity anywhere in the codebase.** The only per-business tier signal is `BusinessProfile.BusinessTierCode` (a plain nullable string, defaulting to `"STANDARD"` at business onboarding via `BusinessProfile.Create(...)`, mutable via `BusinessProfile.UpdateTier(tierCode)` — but no controller/command in the repo actually calls `UpdateTier`, so in practice it is set once at onboarding and never changed). `BusinessTiersController` exposes tier **definition** CRUD only (`GetBusinessTiersQuery`, create/update/delete) — no `assign business to tier` endpoint exists, mirroring the gap in the domain model.

Worse for anyone assuming tier-based business rules are live: `IdentityService.GetBusinessSnapshotAsync` — the method Contracts calls at contract-creation time to snapshot the business party — does **not** read `BusinessProfile.BusinessTierCode` at all. It returns `TierCode: business.TinNumber`, with the source comment *"Using TIN as tier code for now"* — a literal placeholder that has apparently never been revisited. So even the one real field (`BusinessTierCode`) isn't reaching the one place tier would matter for money/escrow-rule matching. `TierCalculationService.CalculateBusinessTierAsync` (which computes a tier from `monthlyRFQs`/`activeContracts`/`monthlySpend` against `BusinessTierRule`) is fully implemented but — like its provider-side sibling — has zero production call sites.

### 5.5 Provider tiering — real commission source, but tier *assignment* is manual-only and two disagreeing threshold schemes coexist

`ProviderTier`/`ProviderTierRule` are real and genuinely used for commission (§5.1). Tier **assignment**, however, is admin-manual only: `AssignProviderTierCommand` (`POST api/provider-tiers/providers/{providerId}/tier-assignment`) lets an admin pick any tier code directly — the handler does not check the provider's actual trust score against `ProviderTierRule` before accepting it, it just appends a new `ProviderTierAssignment` row. New providers are hardcoded to `SILVER` at registration (`Provider.Create()`), not derived from `ProviderTierRule` thresholds.

`TierCalculationService.CalculateProviderTierAsync(trustScore, activeVehicleCount)` — the method that *would* auto-derive a tier from `ProviderTierRule` — is DI-registered (`ITierCalculationService`, the module's only DI registration) but has **zero call sites in production code** anywhere in the backend (confirmed by repo-wide search). Two further details worth flagging precisely because they contradict what the method signature implies:
- It accepts `activeVehicleCount` as a parameter but **never uses it in the qualification check** — only `trustScore` against `MinTrustScore`/`MaxTrustScore` is evaluated. The seeded `ProviderTierRule` rows also carry `MinCompletedContracts`/`MaxCancellationRate`/`MinOnTimeRate` thresholds that this method likewise never checks (it only compares the trust-score range).
- Seeded thresholds: Bronze 0–59 (0+ contracts), Silver 60–74 (10+ contracts, default-for-new — despite `Provider.Create()` separately hardcoding Silver at signup rather than deriving it from this rule), Gold 75–89 (50+ contracts), Platinum 90–100 (100+ contracts) — **these disagree with a second, independently hardcoded threshold scheme** in `Domain/ValueObjects/TrustScore.cs` (Bronze <50, Silver 50–69, Gold 70–84, Platinum ≥85), which is the one actually used by `ProviderRepository.GetByTierAsync`/`GetProvidersQueryHandler` for admin provider-list tier filtering. Two disagreeing, both-dormant, both-partially-wired threshold definitions coexist in the codebase — see `epic-12-risk-trust-scoring.md` Story 12.2 for the full writeup; this module's seed data is one half of that inconsistency.

The admin `TiersPage.tsx` tier-rule edit dialog is a stub (`toast.info('Update functionality coming soon')`) — admins can view but not actually edit tier thresholds/commission through the web UI yet, only via direct API calls or DB/seed changes.

### 5.6 Settlement policy — one tier-agnostic seed rule, and the real settlement job doesn't read this table at all

Seed data (`SeedSettlementPoliciesAsync`): one active `SettlementPolicyVersion` ("T+0 Settlement Policy") with **one** `SettlementPolicyRule` — `providerTierCode = null` (applies to everyone), `settlementFrequency = WEEKLY`, `payoutDelayDays = 0`, `minPayoutAmount = 100m` — i.e. explicitly "no tier differentiation" per the seeder's own comment, contradicting `markdown-documentations/Master_Data_Specification.md`'s illustrative example of Bronze-monthly/Gold-weekly/Platinum-daily tiered cadence (that example was always aspirational, not seeded).

More importantly: `Modules/Finance/Application/Settlement/Commands/GenerateSettlementCommand.cs` (the real settlement generator) does **not query `SettlementPolicyVersion`/`SettlementPolicyRule` at all** — it computes settlements on a hardcoded rolling 30-day cycle per contract, filterable by `ProviderTierFilter` for admin ad-hoc runs but with no tier-based cadence logic. This is the same unresolved contradiction flagged in `project-docs/18_Implementation_Coverage_Audit.md` §10.4 between the wallet-cluster and settlement-cluster doc rewrites — whoever resolves it should update `SettlementPolicyRule`'s seed data (or delete the tiered-cadence code comment in Finance) to match whichever behavior is decided as correct.

### 5.7 Profile completion — the one genuinely live configuration-driven engine

`ProfileRequirement` (`profile_requirements`) is read live by `ProfileCompletionService` (`Modules/Identity/Application/Services/ProfileCompletionService.cs`) to compute a **real** 0–100% profile-completion score for both providers and businesses: it fetches all active `ProfileRequirement` rows for the given `EntityType`, and for each one dispatches on `RequirementType` — `DOCUMENT` (checks an uploaded/verified document of the referenced `DocumentType`), `ATTRIBUTE` (evaluates the row's `ValidationRule` JSON against the actual `Provider`/`Business` entity), or `VERIFICATION` (checks `IsEmailVerified`/`IsPhoneVerified` on `UserAccount`) — and returns a completion percentage plus a list of missing-field display names, falling back to 100% if no requirements are configured at all. This is the one engine in the module where "admins can add/remove a requirement without a code deploy" is actually true today, not aspirational, and its stated purpose (BR-041/BR-042: verified + 100%-complete providers start at Silver) is exactly why `profile_requirements` exists at all.

### 5.8 Contract terms versioning — real, actively consumed

`ContractTermsVersion` is genuinely read by the Contracts module's dual-party OTP e-signature flow (`ContractTermsAcceptance`, see `Contracts_Module.md` §"ContractTermsAcceptance") — a contract binds to a specific active `ContractTermsVersion` per its `SourceType` (`RFQ` or `DIRECT_RENTAL`) at signing time, and `ContentHash` (SHA-256 of the terms body) gives a tamper-evident record of exactly what text a party agreed to. Two versions are seeded (one per source type) at MVP launch.

### 5.9 Lookups, settings, document types, KYC requirements, checklist templates, banks

These are the module's most straightforwardly "as designed" pieces — real CRUD, real consumers:
- **Lookups** feed RFQ line-item dropdowns (vehicle type, engine type, contract period, payment method, notification type, RFQ/bid/contract/delivery status labels, business type, industry, city, insurance coverage type) across web and both mobile apps.
- **Settings** are read ad hoc by whichever module needs a given key (e.g. OTP expiry/attempt-limit constants, VAT/withholding-tax rates, settlement minimums/auto-approve threshold) — there is no dedicated `ISettingsService` wrapper class; consumers inject `ISettingsRepository`/`IMasterDataUnitOfWork` directly.
- **DocumentType/KYCRequirement** drive the Identity module's onboarding document-upload requirements per actor type/subtype/tier (e.g. Gold+ providers additionally require liability + passenger insurance; Platinum additionally requires cargo insurance).
- **ChecklistTemplateItem** drives the Delivery module's vehicle-inspection checklist UI on both delivery and return.
- **Bank** drives withdrawal/payout bank selection and the Chapa payout-gateway integration (`ChapaCode` mapping, admin-editable post-seed since Chapa's bank list isn't hardcoded at seed time).

---

## 6. Known Gaps (verified by code search)

1. **Commission versioning is decorative for the actual money path** — `ProviderTier.CommissionRate` is what's read; `CommissionStrategyVersion/Rule`'s admin CRUD has no effect on live contracts (§5.1).
2. **Escrow's tier-aware calculator is correct but dead-path** — only called from a handler that isn't the one that runs for real contract creation (§5.2).
3. **Contract policy penalties are double-hardcoded, not policy-driven** — the seeded `ContractPolicyRule` rows (all `NONE`) are fetched then discarded in favor of a different hardcoded rule set inside `MasterDataService.GetActiveContractPolicyAsync` (§5.3).
4. **Business tiering has no assignment mechanism and isn't read where it would matter** — no `BusinessTierAssignment` entity, no assignment endpoint, and the one contract-creation read path uses `business.TinNumber` as a tier-code placeholder instead of the real `BusinessProfile.BusinessTierCode` field (§5.4).
5. **Two independently-hardcoded, disagreeing provider tier-threshold schemes coexist** (`ProviderTierRule` seed data vs. `TrustScore.CalculateTier()`), and neither is actually used for automatic tier promotion/demotion — `TierCalculationService.CalculateProviderTierAsync` has zero production callers and doesn't even use its own `activeVehicleCount` parameter (§5.5).
6. **Settlement cadence is not tier-based in the live settlement generator**, despite `SettlementPolicyRule`'s schema supporting per-tier frequency — an unresolved cross-doc contradiction flagged in the coverage audit (§5.6).
7. **`Country/Region/City` is unused for real Ethiopian geography** — seeded with 7 non-Ethiopian countries, no admin regions/cities controller; the actual city picker uses the separate `CITY` lookup-type instead (§3.12).
8. **`Domain/Entities/Foo.cs`** is an unused placeholder entity file — safe to delete, not wired into the `DbContext` or any repository.
9. **Admin `TiersPage.tsx` tier-rule edit dialog is a stub** on the web frontend — viewing tiers works, editing thresholds through the UI does not (per `epic-12-risk-trust-scoring.md`).

---

## 7. Integration points

- **Identity module:** `IdentityService.GetProviderSnapshotAsync`/`GetBusinessSnapshotAsync` (real commission-rate + tier-code lookups, with the placeholder noted in §5.4); `ProfileCompletionService` (real `ProfileRequirement` consumer); `KYCRequirement`/`DocumentType` drive onboarding document gates.
- **Contracts module:** `IMasterDataService.GetActiveContractPolicyAsync` (stubbed, §5.3); `ContractTermsVersion` (real, dual-OTP signing); commission rate flows in via Identity, not directly from this module.
- **Finance module:** `EscrowPolicyRepository.CalculateEscrowLockDaysAsync` (real but dead-path, §5.2); `SettlementPolicyRule` (unused by the live settlement job, §5.6); `Bank`/Chapa-code mapping for payouts.
- **Marketplace module:** consumes `lookups`/`lookup_types` for RFQ line-item vehicle/engine/period fields.
- **Delivery module:** consumes `ChecklistTemplateItem` for the inspection-checklist UI.
- **Web admin (`anqelbacarrental-marketplace-core`):** full CRUD screens for tiers, commission/escrow/settlement/contract policy versions and rules, contract-terms templates, checklist templates, document types, KYC requirements, lookups, settings, banks, platform bank accounts — the admin *authoring* surface is comprehensive even where the *consumption* side (§5) is stubbed or bypassed.

## Related documents

- `markdown-documentations/Master_Data_Specification.md` — design-level companion; accurate on intent and schema shape, silent on the live-vs-dormant distinctions in §5.
- `backlog/mvp/epic-12-risk-trust-scoring.md` — the provider tier-threshold/commission findings in §5.5 are the same ones documented there in full, from the trust-score angle.
- `marketplace-project-implementation/MVP_MODULAR/04_MODULE_SPECIFICATIONS/Contracts_Module.md` — the consuming side of §5.2/§5.3/§5.8.
- `project-docs/18_Implementation_Coverage_Audit.md` §5/§10.2/§10.5 — the audit findings that triggered this rewrite.
