# Database Schema Design — Conventions, Rationale & Drift Reference

**Last verified against code:** 2026-07-23
**Ground truth used:** same as the two companion documents — `backend/src/Marketplace.API/Migrations/MarketplaceDbContextModelSnapshot.cs`, `Modules/*/Domain/Entities/*.cs`, `Modules/*/Infrastructure/Configurations/*.cs`, `MarketplaceDbContext.cs`, `Program.cs`.

**Relationship to the other two database docs, so all three stop drifting from each other:**
- **`../02_DATABASE_SCHEMA_DESIGN.md`** is the exhaustive reference — every schema, every table, every column, every FK, the full migration history. Go there for "what does column X look like on table Y."
- **`database-erd.md`** is the relationship/shape view — Mermaid diagrams per schema, cross-referencing the same facts visually.
- **This document** is the "why" and "how to not get burned" layer: the actual conventions in force (as opposed to the conventions the architecture docs *claim* are in force), the versioned-policy design pattern, and a single consolidated checklist of every place this codebase's schema will mislead you if you trust a doc comment, an enum, or an old architecture doc over the compiled model. It does not restate the per-table column listings — if a fact here and a fact in `02_DATABASE_SCHEMA_DESIGN.md` ever look inconsistent, the other document's per-table section wins (it was built directly off column-by-column reads of the snapshot).

The original November 2025 version of this document described a `business/provider/rfq/contracts/finance/risk/notifications/shared` schema set with entirely invented tables (`business.businesses`, `provider.vehicles`, `risk.business_risk_scores`, `finance.wallets`) that never existed in any migration. It was written before the first migration was ever run and never reconciled afterward. Nothing in it should be trusted; it is fully superseded by this rewrite.

---

## 1. Database & Tooling Facts

| | |
|---|---|
| Engine | PostgreSQL 16 |
| ORM | Entity Framework Core 9, Npgsql provider |
| Architecture | Modular monolith, one `MarketplaceDbContext`, 8 C# modules (Auth, Contracts, Delivery, Finance, Identity, Marketplace, MasterData, Notifications) |
| Real PostgreSQL schemas | 7: `masterdata`, `identity`, `marketplace`, `contracts`, `wallet`, `delivery`, `notifications` (Finance module's tables live in `wallet`; Auth owns no tables) |
| Table count | 119 |
| Migrations | 35, `InitialCreate` (2026-02-12) → `AddContractTermsVersioningAndAcceptance` (2026-07-08) |
| Primary keys | `uuid`, generated in C# (`Guid.NewGuid()` in entity constructors), never a Postgres `DEFAULT` |
| Query splitting | `UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery)` set globally in `Program.cs` |
| Pending-model-changes warning | explicitly suppressed (`ConfigureWarnings(...Ignore(RelationalEventId.PendingModelChangesWarning))`) — the codebase has consciously chosen to allow the model and the latest migration to drift slightly rather than fail the build over it |

---

## 2. Naming Convention: What's Actually True (Not What the Docs Claim)

This is the single most important section in this document, because two separate architecture claims about this codebase's naming are wrong, and both are wrong in a way that's easy to assume rather than verify.

### 2.1 Claim: "snake_case naming (EFCore.NamingConventions)" — **half true**

- **Table names:** genuinely snake_case (`rfq_bids`, `contract_line_items`, `wallet_ledger_transactions`). ✅ True — but achieved by every entity explicitly declaring `[Table("snake_case_name")]` and *also* a Fluent `builder.ToTable("snake_case_name", "schema")` in a separate configuration class, not by any naming-convention transform.
- **Column names:** camelCase (`businessId`, `createdAt`, `contractNumber`), not snake_case. ❌ False as commonly assumed. `EFCore.NamingConventions 9.0.0` is referenced in `Marketplace.API.csproj` but **`UseSnakeCaseNamingConvention()` (or any variant) is never called anywhere** — confirmed by grep across the whole backend, and confirmed by an explicit code comment in both `MarketplaceDbContext.OnConfiguring` and `Program.cs`: *"No global naming convention is applied - column names are specified directly."* Every column name is set by an explicit `[Column("camelCase")]` data-annotation attribute on the entity property.
- **The package reference is genuinely vestigial** — it sits in the `.csproj` with no corresponding `.UseSnakeCaseNamingConvention()` call anywhere in `Program.cs` or `MarketplaceDbContext`. Whoever removes it next should also remove the package reference (or wire it up — but that would be a breaking rename of ~114 tables' columns, not a small change).

**Practical implication:** never write raw SQL against this database assuming snake_case columns. `SELECT business_id FROM contracts.contracts` will fail; it's `SELECT "businessId" FROM contracts.contracts`.

### 2.2 Two further, smaller naming inconsistencies layered on top

1. **Five "status history" tables are snake_case throughout, columns included:** `contract_status_history`, `vehicle_status_history`, `rfq_status_history`, `direct_rental_request_status_history`, `settlement_status_history` — all added together by migration `AddStatusHistoryTables` (2026-05-15). Their columns (`changed_at`, `from_status`, `to_status`, `trigger`, `triggered_by_user_id`, `triggered_by_user_type`, plus a snake_case FK like `contract_id`/`vehicle_id`) look like they were written by someone following the *documented* (but unimplemented-elsewhere) snake_case convention, in isolation from the rest of the codebase. Even on these five tables, the shared `createdAt`/`updatedAt`/`createdBy`/`updatedBy`/`isDeleted` audit columns remain camelCase — so it's not even a clean split, just an inconsistency nested inside the inconsistency.
2. **One outright irregular column name:** `contracts.contract_vehicle_assignments.contractlineitemid` — all-lowercase, no word boundary at all. The C# property is correctly-cased `ContractLineItemId`; the actual generated column name is not. Treat this as a known landmine for anyone hand-writing SQL or a raw ADO query against that table.

### 2.3 Claim: "Fluent API only, no data annotations" — **false**

`architecture/module-layout-convention.md` states the codebase uses Fluent API exclusively. In fact, **every entity class uses data-annotation attributes directly** (`[Table]`, `[Column]`, `[Required]`, `[MaxLength]` — see e.g. `Modules/Marketplace/Domain/Entities/RFQBid.cs`), and these attributes are what actually determines column names and required/max-length constraints for the great majority of properties. A separate `IEntityTypeConfiguration<T>` class per entity (under each module's `Infrastructure/Configurations/` folder) then layers Fluent API on top — but only for things attributes can't express: relationships (`HasOne`/`HasMany`/`OnDelete`), decimal precision (`HasPrecision(18,2)`), and indexes (`HasIndex`). The two mechanisms aren't redundant alternatives chosen inconsistently per-entity; they're both used on every entity, each covering a different half of the configuration.

**If you're adding a new column:** follow the existing pattern for that entity — attribute for the property itself, then check whether the sibling `IEntityTypeConfiguration` class also needs a matching `HasMaxLength`/`HasPrecision` call (sometimes it duplicates the attribute, sometimes it adds precision the attribute can't express). Don't assume touching one file is enough.

---

## 3. Status & Enum Handling: Four Real Patterns, Not One

A prior working assumption (reasonable, since it's how most well-behaved EF Core codebases are built) was that "status" columns are backed by C# enums throughout. They are not, uniformly. Four distinct patterns coexist, and you must check the entity file directly — never infer from a `Domain/Enums/*.cs` file's existence — before trusting a status value list.

| # | Pattern | Modules where it's real | How to recognize it in code |
|---|---|---|---|
| 1 | Real enum, converted to a `varchar`/`text` column via `.HasConversion<string>()` | **Identity only**: `Business.Status`/`BusinessType`, `Provider.Status`, `Vehicle.Status`, `ProviderTierAssignment.TierCode` | The Fluent config has `.Property(x => x.Status).HasConversion<string>()`; the entity property type is the enum, not `string` |
| 2 | Real enum, stored as a plain `integer` (default EF behavior, no converter) | **Marketplace only**: `RFQLineItem.Term` (`RFQTerm`), `RFQLineItem.FuelType` (`FuelType?`) | Entity property type is the enum; snapshot shows `HasColumnType("integer")` with no `HasConversion` |
| 3 | Plain `string` property, no enum at all — value set exists only as a `//` comment (if that) | **The large majority**: Contracts, Marketplace (RFQ/RFQBid/RFQBidAward/DirectRentalRequest/etc.), Finance/`wallet` (WalletAccount/EscrowLock/WithdrawalRequest/DepositRequest/PaymentIntent/etc.) | `public string Status { get; private set; } = "SOME_DEFAULT";` — grep the entity file for the inline comment listing the real values |
| 4 | Real enum **exists**, but is dead code — the entity property is pattern-3 plain-string and never references the enum | `Contract.Status` (`ContractStatus` enum, 17 members, but the real system has 18 string values, one — `CANCELLED` — missing from the enum), `ContractLineItem.Status` (`ContractLineStatus` enum, also unreferenced) | Grep the enum type name across the codebase — if it has zero hits outside its own file, it's pattern 4, not pattern 1/2 |

**Rule of thumb for any future schema work:** before writing "the valid values for `X.Status` are members of the `XStatus` enum," `grep -rn "XStatus\."` across `Modules/` excluding the enum's own file. If that returns nothing, the enum is decorative and the real value set is whatever string literals the entity's methods actually assign — read the entity's `.cs` file end to end, not just its property declaration.

Full worked example for Contracts (18 real values, transition matrix, which enum members are vestigial vs. reachable): `../MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md`.

---

## 4. The Versioned-Policy Pattern (MasterData)

Four independent policy domains in `masterdata` — commission, contract rules, escrow, settlement — all follow the identical two-table shape:

```
{Domain}Version                  {Domain}Rule
├─ versionNumber (int)           ├─ {domain}VersionId (FK, cascade)
├─ name / description            ├─ scoping columns (tier code / region / scenario, all optional)
├─ effectiveFrom / effectiveTo   └─ the actual policy numbers (rate, days, amount, ...)
└─ isActive (bool)
```

Plus a fifth, structurally identical pair for legal terms: `ContractTermsVersion` (no separate `*Rule` table — the "rule" *is* the terms body, `termsBody text`) with a self-referential `supersedesVersionId`, so a new terms version can point back at the one it replaces and the system can serve the latest active version per `sourceType` (RFQ vs. Direct Rental) without ever mutating a version a contract has already been signed against.

**Design intent:** an already-created contract or committed policy calculation is never retroactively changed by a later admin edit to the *current* policy — every domain that matters for money (contract terms, commission, escrow lock period, settlement cadence) is versioned, and a contract snapshots the specific version it was created under (see `contracts.contract_policy_snapshots`, which stores the resolved policy as `policyJson` at contract-creation time).

**Known gap between design intent and what's wired up (see coverage-audit §10.2, §10.4, §10.5 for the full detail — summarized here because it's schema-relevant):**
- **Two independent, disagreeing tier-qualification schemes exist** for providers: `provider_tiers.commissionRate` (a flat rate baked directly onto the tier, seeded 10/8/6/5% for Bronze/Silver/Gold/Platinum) is one; `provider_tier_rules` (trust-score + completed-contract-count thresholds, a `TierCalculationService`-driven "hybrid" scheme) is the other. Neither is invoked automatically by any production event handler — a provider's tier only changes via a manual admin action.
- **The live escrow-lock computation bypasses the versioned `escrow_policy_rules` table** — `ContractCreatedEventHandler` uses a hardcoded 30-day cap constant instead. A second handler (`FinanceBidAwardedEventHandler`) *does* read the policy engine, but nothing calls it in the real flow.
- **Settlement cadence is disputed between two doc clusters** (wallet vs. ledger/settlement rewrite passes) as to whether `settlement_policy_rules`' tier-based cadence is what actually drives `GenerateSettlementCommand`, or whether that command runs a flat 30-day rolling cycle regardless of tier and the tier-based-cadence code comment is itself aspirational. Not resolved as of 2026-07-23 — whoever next touches `Modules/Finance/Application/Settlement/Commands/GenerateSettlementCommand*.cs` should settle it and update both epic docs.

Bottom line: the *tables* for a rich, versioned, tier-aware policy engine are real and correctly normalized. Whether any given policy table is actually read by the code path that needs it on a given day is a separate question you must verify per-table — don't assume "the schema supports it" means "the system does it."

---

## 5. Consistent Conventions (the parts that *do* hold up everywhere)

- **Every table** has `id uuid` PK, `createdAt timestamptz NOT NULL`, `updatedAt timestamptz NULL`, `createdBy uuid NULL`, `updatedBy uuid NULL`, `isDeleted boolean NOT NULL`. This is the one convention with no exceptions found across all 119 tables.
- **Soft delete only** — `isDeleted` is a flag, not a physical `DELETE`. No table in the schema relies on Postgres cascade-delete to actually remove historical rows; `OnDelete(Cascade)` FKs exist for referential cleanup of genuinely dependent child rows (e.g. deleting a `Contract` cascades its line items/assignments/amendments), not as a soft-delete mechanism.
- **No table-level Postgres `DEFAULT`** for `id`/`createdAt` — both are set in C# (`BaseEntity` constructor equivalent) before `SaveChanges`, with two narrow exceptions: `WalletEventLog.createdAt` (`HasDefaultValueSql("now()")`) and a handful of MasterData boolean/int columns (`ChecklistTemplateItem.isRequired`, `Country.isActive`, etc.) using `HasDefaultValue(...)`. If you're inserting rows via raw SQL or a seed script rather than through the domain entity, you must supply `id`/`createdAt` yourself almost everywhere.
- **`numeric` vs `decimal(18,2)` vs `numeric(p,s)` is genuinely inconsistent**, but not randomly — money amounts on tables added early (`InitialCreate`-era: `Contract.TotalContractValue`, most of `wallet`'s `EscrowLock`/`CommissionEntry`/`ContractPenalty`) use bare `numeric` (unconstrained precision/scale); money amounts on tables added via later migrations (`WithdrawalRequest`, `DepositRequest`, `PaymentIntent`'s `Amount`, `Vehicle.DailyRentalRate`) use explicit `decimal(18,2)`; a third group explicitly sets `.HasPrecision(18, 2)` in Fluent config (`RFQBid.TotalAmount`, `RFQBidItem.UnitPrice`, `ContractLineItem.UnitAmount`/`TotalAmount`, `EscrowRollover.Amount`). All three render as `numeric`/`numeric(18,2)` in Postgres; the practical difference is whether the *database* enforces the 2-decimal-place scale or the application does. Don't assume a bare `numeric` column silently rounds to cents — several genuinely don't at the DB level.
- **`jsonb` is used for genuinely flexible/variable-shape data only** — lookup metadata, notification payloads/preferences, checklist enum options, verification event data. It is not used as an escape hatch for relational data that should have been a child table; every place a real one-to-many relationship exists, this codebase models it as an actual child table (occasionally to excess — see `contract_status_history` existing as a full audit table rather than a JSON column on `Contract`).
- **One real Postgres array column:** `identity.vehicles.tags` is `text[]`, not `jsonb` and not a join table. It's the only `PrimitiveCollection<string[]>` in the entire schema.

---

## 6. Cross-Module Reference Policy

The modular-monolith boundary is enforced at the database level almost everywhere: a reference to an entity owned by a different module is a bare `uuid`/`uuid?` column, with **no** `HasForeignKey` and **no** Postgres FK constraint. Examples: `Contract.BusinessId`/`ProviderId`/`RFQId`/`RFQBidAwardId`/`DirectRentalRequestId`, `WalletAccount.OwnerId`, every `contractId`/`providerId`/`businessId` column in the `wallet` and `delivery` schemas, `DirectRentalCartItem.VehicleId`, `RFQBid.ProviderId`.

**The one exception, confirmed by direct inspection of the compiled model:** `marketplace.rfqs.businessId → identity.businesses.id` is a real, enforced, `OnDelete(Cascade)` foreign key. No other cross-schema reference anywhere in the 119-table set behaves this way. If you're designing a new cross-module reference, match the dominant pattern (loose Guid, no constraint, application-layer integrity) unless you have a specific, deliberate reason to reach for the one precedent that does otherwise — and if you do, document why, since it will otherwise read as an accident to the next person auditing the schema.

Within a single module's own schema, FKs are enforced consistently and almost always `Cascade` on delete, with three deliberate exceptions worth remembering:
- **`Restrict`** where a parent shouldn't disappear out from under active references it doesn't own the lifecycle of: `RFQBidItem.RFQLineItemId`, `ContractTermsAcceptance.TermsVersionId` (→ MasterData), `DeliveryOtp`/inspection-checklist FKs into their session tables, notification `templateId` FKs.
- **`SetNull`** where the child row should survive independently of its parent going away: `EscrowRollover.AppliedToEscrowLockId`, both `WalletEventLog` FKs (`TransactionId`, `WalletAccountId`).
- **No override specified** (defaults to `Restrict` in EF Core, differently from an explicit `Cascade`): `RiskEvent.UserId`, `MonthlySettlementSchedule.EscrowLockId`, `SettlementPayout.InvoiceId`/`WalletTransactionId`, `ProviderInvoice.LinkedPayouts`. These read as unintentional omissions rather than deliberate `Restrict` choices in most cases — worth a cleanup pass if anyone revisits FK behavior, since an un-configured default silently differs from every sibling relationship on the same entity that *does* specify `Cascade`.

---

## 7. Checklist: Things That Will Mislead You If You Trust the Wrong Source

Consolidated from every drift finding in this rewrite pass — use this before writing new code or docs against the schema:

1. **Don't trust `EFCore.NamingConventions` being in the `.csproj`.** It's never invoked. Columns are camelCase; verify with the actual `MarketplaceDbContextModelSnapshot.cs`, not the package list.
2. **Don't trust a `Domain/Enums/*.cs` file's member list as the real status value set** unless you've grepped for references to it outside its own file. `ContractStatus`/`ContractLineStatus` are dead code; `BusinessStatus`/`ProviderStatus`/`VehicleStatus`/`RFQTerm`/`FuelType` are real.
3. **Don't trust "Fluent API only" from the architecture doc.** Column shape comes from `[Table]`/`[Column]` attributes on the entity; only relationships/precision/indexes come from the paired `IEntityTypeConfiguration` class.
4. **Don't assume a table existing in `Migrations/*.cs` means it's live today.** `early_return_notices` is created (and recreated) by real migrations but has zero mapping in the current `MarketplaceDbContextModelSnapshot.cs` — check the snapshot, not the migration folder, for "does this table exist in the model EF actually builds."
5. **Don't assume a policy table being present means the code path that should read it does.** Escrow, tier-qualification, and settlement-cadence policy tables in `masterdata` are all confirmed cases where a hardcoded value or a second, unwired code path runs instead of the versioned table.
6. **Don't assume cross-module FKs are enforced.** They almost never are; `RFQ.BusinessId` is the sole confirmed exception.
7. **Don't assume every column on a "twin" table pair is named the same way.** `WalletLedgerTransaction`'s C# property `Reference` maps to column `transactionReference`, not `reference` — property name and column name diverge on more than one table; always check the `[Column(...)]` attribute value directly rather than assuming it matches the property name.
8. **Watch for the five snake_case-column tables** (`*_status_history`, §2.2 above) when writing any tooling (an ORM-agnostic reporting query, a migration generator, a linter) that assumes camelCase columns hold everywhere — they don't, on exactly these five.

---

## 8. Companion Documents

- **`../02_DATABASE_SCHEMA_DESIGN.md`** — full per-table, per-column reference for all 119 tables across all 7 schemas, plus the complete 35-migration history table.
- **`database-erd.md`** — Mermaid ER diagrams per schema, same relationship facts as this document's §6, drawn out visually with loose vs. enforced references distinguished.
- **`../MVP_final_docs/MVP_DIRECT_RENTAL_SPECIFICATION.md`** / **`MVP_DIRECT_RENTAL_STATE_MACHINE.md`** — Direct Rental (`marketplace.direct_rental_*` tables) product/state-machine detail beyond schema shape.
- **`../MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md`** — the full 18-state contract lifecycle this document only summarizes in §3 above.
- **`project-docs/18_Implementation_Coverage_Audit.md`** — the cross-surface audit every "confirmed gap" callout in this document is sourced from.
