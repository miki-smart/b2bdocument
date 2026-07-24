# Business Rules Catalog

**Version:** 2.0 MVP
**Last verified against code: 2026-07-23**
**Scope:** All Modules (backend `Marketplace.API`, web, both Flutter mobile apps)

**Canonical source:** This is a **quick-reference catalog**, not the authoritative document. The single source of truth for full rule detail, edge cases, and NOT-YET-IMPLEMENTED flags is [`MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md`](./MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md) — its `BR-0xx` numbering is the numbering actually referenced in code comments (e.g. `BR-010`, `BR-011`, `BR-025`, `BR-031A`, `BR-012`, `BR-042`). Where this catalog and that document disagree, trust the authoritative document. The short-code IDs below (`BR-ID-xx`, `BR-MK-xx`, etc.) are a legacy simple-catalog convention kept for quick lookup only — they do not appear anywhere in code.

---

## 🏢 Identity & Compliance

### BR-ID-01: Business Registration
- **TIN Validation:** Must be a unique 10-digit number.
- **Document Requirement:** Valid Business License is mandatory for activation.
- **Tier Assignment:** All new businesses start at `STANDARD` business tier (`BusinessTier` master data: `STANDARD` / `BUSINESS_PRO` / `ENTERPRISE` / `GOV_NGO`). Business tier governs **volume limits only** (max RFQs/month, max active contracts, max vehicles/RFQ) — it does **not** drive commission, penalty, or settlement rates; those are provider-tier concepts only.

### BR-ID-02: Provider Registration
- **Fleet Requirement by provider type:** Individual/Agent/Company categories exist in the provider model, but a specific numeric fleet-size gate per type (e.g. 1–5 / 6–20 / 20+) was **not confirmed as an enforced validation rule** in this pass — treat any such range as directional guidance, not a verified code gate, until re-checked.
- **Tier Assignment:** Every new provider is created with `TrustScore = 50` and tier **`SILVER`** — both hardcoded defaults in `Provider.Create()` — **not** `BRONZE`/trust score `0` as previously stated here. A dormant, unwired "hybrid" tier-calculation model exists in code (`TierCalculationService`, BR-041/BR-042 in the authoritative doc) that *would* start unverified/incomplete-profile providers at `BRONZE`, but the live registration path never calls it.

### BR-ID-03: Vehicle Compliance
- **Insurance:** Mandatory; a vehicle without valid insurance cannot be listed for bidding/Direct Rental or assigned to a contract — confirmed zero-tolerance enforcement.
- **Validity:** Insurance must be valid; an additional "+30 days buffer past delivery date" figure appears in planning docs but was not independently re-verified against a specific validator this pass.
- **Photos:** Multi-angle photo capture is expected at vehicle registration; the exact required angle count/enforcement point was not re-verified this pass — do not treat "5 angles, hard-enforced" as confirmed.

---

## 🏪 Marketplace & Bidding

### BR-MK-01: RFQ Creation
- **Wallet Balance:** ⚠️ **NO** wallet balance required to create or publish RFQs — confirmed in the `RFQ`/`RFQLineItem` entities and `RFQController` (see BR-002 in the authoritative doc).
- **Real model is header + line items, not a single vehicle-type/date-range RFQ.** Each RFQ carries one or more `RFQLineItem`s, each with its own vehicle type, quantity, term (`SHORT_TERM` ≤ 30 days / `LONG_TERM`), dates, and purpose. `SHORT_TERM` line items are hard-capped at **30 days in the entity factory itself**, not just a UI hint.
- **Quantity caps:** the web wizard enforces max 10 line items / 50 total vehicles per RFQ **client-side only** — server-side enforcement of these two specific caps was not confirmed; do not rely on them as an API-level guarantee.

### BR-MK-02: Bidding
- **Blind Bidding:** Provider identity is masked via a SHA-256-hashed provider ID stored on `RFQBidSnapshot` — **but this is enforced only by the web UI choosing not to render `ProviderName`, not by the API.** Both `GetBidsByRFQQuery` and `GetBidQuery` return the real `ProviderName` unconditionally regardless of the bid's award status. Treat blind bidding as a real UI convention today, not yet an API-level guarantee — see epic-05 Story 5.4 for the fix (null `ProviderName` server-side unless `Status == "AWARDED"`).
- **Price Floor/Ceiling:** ⚠️ **Built but not enforced.** A `PriceValidator` service exists implementing exactly a 50%–200%-of-market-average band, and is DI-registered — but it is **never called** from `SubmitBidCommandHandler` or anywhere else in the codebase. It is also not backed by real market data: `GetMarketPriceRangeAsync` returns hardcoded default prices per vehicle type (a `// TODO: Get average price from last 30 days of contracts` marks the real calculation as unimplemented). No bid is rejected for being outside 50%–200% of anything today.
- **Eligibility:** Provider must have enough active/verified vehicles in the matching vehicle-type + fuel segment to cover the offered quantity (`IProviderValidationService`/`ProviderFleetCapacityService` — BR-004 in the authoritative doc). No specific vehicle is chosen at bid time.
- **One bid per line item per provider:** a second bid attempt against a line item the provider already bid on is rejected — the provider must edit their existing bid instead.

### BR-MK-03: Awarding
- **Wallet Balance:** ⚠️ **REQUIRED**. Business `AvailableBalance` must cover `Σ quantityAwarded × unitPrice × min(durationDays, 30)` across all awards in the request (BR-006/BR-007 in the authoritative doc).
- **Partial Award:** Allowed — a single line item's quantity can be split across multiple providers' bids in one award call (`RFQBidAward` per award), and on insufficient balance the error response includes an estimated affordable quantity so the business can adjust (BR-008/BR-009).
- **Escrow Lock:** Not "100% locked immediately at award" as a standalone step — escrow locking is triggered by **contract creation** (`ContractCreatedEvent`, fired right after the award), and the locked amount is `min(durationDays, 30)` per line item (BR-010/BR-031A), not a flat "Monthly = 1.0 / Event = 1.0" multiplier concept.
- **Open gap:** `AwardBidCommandHandler` contains a `// TODO: Publish BidAwardedEvent for each award...` comment in code — verify current wiring before assuming award → contract → escrow is fully event-driven end-to-end (see epic-05 Story 5.5).

---

## 📜 Contracts & Delivery

### BR-CT-01: Activation
- **Trigger:** Contract reaches `ACTIVE` only once **every** awarded vehicle across every line item has been delivered and OTP-confirmed — not "the first vehicle delivered." The first delivery instead triggers `PARTIALLY_DELIVERED` (on multi-vehicle contracts) and anchors the settlement schedule to that first-delivery date.
- **Requirement:** A vehicle inspection checklist must be `APPROVED` by the business before a delivery OTP can even be generated (hard-blocked server-side); OTP verification then confirms handover. There is **no photo/odometer "handover evidence" capture** in the live flow — the `DeliveryVehicleHandover` entity exists in the schema but nothing ever writes to it. The real condition-verification mechanism is the structured **vehicle inspection checklist** (bool/enum/numeric fields with server-computed warning flags), not photos.

### BR-CT-02: Early Return / Early Termination
- **Mechanism:** `ProcessEarlyTerminationCommand` computes day-based proration (`usedDays`/`totalDays`), a penalty via MasterData's `ContractPolicyVersion/Rule` engine (`EARLY_TERMINATION` scenario), and a 3-way ledger split (business refund / provider settlement / platform commission+penalty).
- **Seeded default penalty is 0% (`PenaltyType = "NONE"`).** There is **no** business-tier-based early-return penalty schedule (e.g. "Standard 25% / Business Pro 20% / Enterprise 15%") anywhere in code — `BusinessTier` governs only RFQ/contract volume limits, never penalty percentages. The `EARLY_TERMINATION` policy is admin-configurable master data, currently seeded to zero penalty for MVP.
- **Commission on early termination** uses the contract's own **snapshotted, weighted-average line-item commission rate** — a provider's tier change mid-contract does not retroactively change what's owed on an already-created contract.
- A separate notice-period-based `InitiateEarlyReturnCommand` exists in code (with a policy-driven grace-period lookup) but **has no controller endpoint and is never invoked from anywhere** — unreachable in the running system today.

### BR-CT-03: Delivery
- **OTP Expiry:** 5 minutes for both the delivery and return OTPs; 60-second resend cooldown per party for the separate contract-terms-signing OTP.
- **Lockout:** ⚠️ **Not implemented.** There is no attempts counter or 30-minute lockout field on `DeliveryOTP`/`ReturnOTP` in code — an expired or already-used OTP simply fails verification, and a fresh one must be generated. Treat "3 failed attempts = 30-minute lockout" as aspirational, not current behavior.
- **SLA "on-time" definition:** not confirmed as an enforced, code-level concept in this pass — `DeliverySLAViolation` exists in the schema but nothing writes to it.
- **No GPS/location verification anywhere** in the delivery flow — confirmed zero `Latitude`/`Longitude` references in the Delivery module; `DeliverySession.LocationAddress` exists but is always written as `null`.

---

## 💰 Finance & Settlement

### BR-FN-01: Wallet
- **Currency:** ETB only.
- **Overdraft:** Not allowed — enforced entirely through domain methods (`Credit`/`Debit`/`LockForWithdrawal`/`UnlockWithdrawal`); no bare balance-assignment code path exists.
- **Locking:** Escrow-locked funds live in a real, separate `ESCROW`-type `WalletAccount` row (not a flag on the main wallet) and cannot be withdrawn or reused for another award while locked.

### BR-FN-02: Commission (BR-012 / BR-040 in the authoritative doc)
- **Bronze: 10% · Silver: 8% · Gold: 6% · Platinum: 5%** — these are the real, live, seeded `ProviderTier.CommissionRate` values (`MasterDataSeeder.SeedProviderTiersAsync`), and they are exactly what gets resolved and snapshotted onto a contract's line items at bid-award time (`BidAwardedEventHandler` → `CommissionStrategyRule.CalculateCommission()`, which itself simply reads `ProviderTier.CommissionRate` — the `CommissionStrategyRule` entity does not carry an independent per-tier rate table of its own). Fallback if no tier resolves for a provider: a hardcoded **5%** default.
- **There is no "Red Zone" tier anywhere in code**, and no 3%/4%/7%/10% commission scheme. A different set of numbers along those lines appears in some business-planning/memory notes as the *originally designed* revenue model — that is aspirational business direction, not current code behavior, and must not be quoted as a live rate.
- **Calculation:** Applied per contract line item at the rate snapshotted at award time; a mid-contract provider tier change does not retroactively change an already-created contract's rate.

### BR-FN-03: Settlement
- **Frequency:** A **fixed 30-day rolling cycle per contract**, anchored to the contract's start date — **not** tier-based cadence. A code comment on `GenerateSettlementCommand.cs` (itself labeled `BR-FN-03`) describes "Bronze/Silver monthly, Gold bi-weekly, Platinum weekly," but this is **stale/aspirational and not implemented** — there is no branching on provider tier anywhere in `SettlementScheduleService`. Treat the flat 30-day rolling window as ground truth; the tier-cadence comment is a documentation bug inside the codebase itself.
- **Minimum Payout:** ETB 100 by default (MasterData setting, admin-overridable) — not ETB 1,000.
- **Approval:** Every generated payout starts `PENDING_ADMIN_APPROVAL` — no money moves until an admin approves it (`ApproveSettlementPayoutCommand`), which performs the escrow → provider/commission/tax double-entry posting in one atomic step.
- **Withholding tax:** 2% default (MasterData setting), deducted from every payout's post-commission net amount; VAT-registered providers reclaim it via a provider-submitted invoice against their own completed payouts — there is no system-generated, business-facing invoice anywhere in the codebase (see epic-09).

---

## ⭐ Trust Score

### BR-TS-01 (BR-025 in the authoritative doc): Calculation Formula
- `Score = Base(50 if verified else 0) + CompletionRate×20 + OnTimeRate×20 − NoShowRate×30 + RejectionPenaltyPoints`, clamped to 0–100. This is **not** a 5-factor weighted-percentage model (completion 30% / on-time 25% / reliability 20% / quality 15% / dispute history 10%) — that scheme does not exist in code. `TrustScoreCalculator.cs` implements exactly the formula above, and it has no "quality/ratings" or "dispute history" input at all (no rating system or dispute entity exists to feed one).
- **Critical gap:** this formula is fully built and unit-tested but has **zero production call sites**. No handler for contract completion, on-time delivery, no-show, or bid-award rejection ever invokes it. Every provider's score is frozen at the registration default (**50**) unless an admin manually reassigns a tier via the admin endpoint. Treat trust scoring as "modeled, not live" for any decision that depends on it actually moving.

### BR-TS-02: Penalties (Score Deduction)
- The real formula has a single `RejectionPenaltyPoints` input (a negative int) for bid-award rejections. No separate, wired point values for no-show / under-delivery / early-return / dispute-loss were found feeding the live calculation — and the calculation itself is dormant anyway (see BR-TS-01), so none of these deductions currently change any provider's actual stored score.

---

**Next Document:** [MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md](./MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md)
