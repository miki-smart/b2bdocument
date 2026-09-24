# Provider Portal — As-Built Reference

## Anqelba Car Rental Web Frontend (React 18.3 + Vite + TanStack Query + Zustand)

**Last verified against code: 2026-07-23**

> **Reframing note:** This file was originally written as a from-scratch *build guide* (the kind fed to an AI scaffolding tool such as Lovable), with illustrative code for a portal that didn't exist yet. The provider portal has since been built, and diverges from that original assumption in several load-bearing ways — the bidding model, the two-phase vehicle-assignment flow, and an entire fleet-capacity/Direct-Rental layer the original guide never anticipated. This version documents **what actually exists in code today**, verified against `marketplace-project-implementation/anqelbacarrental-marketplace-core/src/features/provider/**` and the route table in `src/App.tsx`.

All provider routes live under `/provider` inside `ProviderLayout`, gated by `ProtectedRoute allowedRoles={['provider']}`.

| Route | Component |
|---|---|
| `/provider/dashboard` | `ProviderDashboard.tsx` |
| `/provider/marketplace` | `MarketplacePage.tsx` |
| `/provider/marketplace/:id` | `RFQDetailPage.tsx` |
| `/provider/marketplace/:id/bid/:lineItemId` | `BidSubmissionPage.tsx` |
| `/provider/marketplace/:id/bid/:lineItemId/edit/:bidId` | `BidSubmissionPage.tsx` (edit mode) |
| `/provider/bids` | `MyBidsPage.tsx` |
| `/provider/bids/:bidId/assign` | `AwardAssignPage.tsx` |
| `/provider/fleet` | `FleetListPage.tsx` |
| `/provider/fleet/capacity` | `FleetCapacityOverviewPage.tsx` |
| `/provider/fleet/add` | `AddVehiclePage.tsx` |
| `/provider/fleet/:id` | `VehicleDetailPage.tsx` |
| `/provider/fleet/:id/edit` | `AddVehiclePage.tsx` (edit mode) |
| `/provider/contracts` | `ProviderContractListPage.tsx` |
| `/provider/contracts/:id` | `ContractDetailPage.tsx` (shared with business/admin) |
| `/provider/contracts/:id/terms-preview` | `ContractTermsPreviewPage.tsx` |
| `/provider/contracts/:id/assign` | `AssignVehiclesPage.tsx` |
| `/provider/contracts/:id/delivery` | `ProviderDeliveryPage.tsx` |
| `/provider/direct-rental/requests` | `ProviderRequestsPage.tsx` |
| `/provider/direct-rental/requests/:id/respond` | `ProviderRequestResponsePage.tsx` |
| `/provider/wallet` | `ProviderWalletPage.tsx` |
| `/provider/wallet/settlements` | `ProviderSettlementsPage.tsx` |
| `/provider/wallet/settlements/:payoutId` | `SettlementDetailPage.tsx` |
| `/provider/wallet/invoices` | `ProviderInvoicesPage.tsx` |
| `/provider/wallet/invoices/:id` | `ProviderInvoiceDetailPage.tsx` |
| `/provider/profile` | `ProfilePage.tsx` |
| `/provider/settings` | `SettingsPage.tsx` |
| `/provider/notifications` | `NotificationsPage.tsx` |

That's more than double the original guide's ~6-page footprint. The two biggest structural corrections: (1) bidding is at the **fleet/quantity level with no vehicle chosen at bid time**, and (2) vehicle assignment is a **two-phase, two-screen process** (assign to the RFQ award, then assign to the contract), both unlike the original guide's single "Vehicle Assignment Page."

---

## Table of Contents

1. [Dashboard](#1-dashboard)
2. [Marketplace & Bidding — quantity-level, no vehicle chosen at bid time](#2-marketplace--bidding--quantity-level-no-vehicle-chosen-at-bid-time)
3. [Fleet Management — vehicle lifecycle, not just CRUD](#3-fleet-management--vehicle-lifecycle-not-just-crud)
4. [Contracts & the Two-Phase Vehicle Assignment](#4-contracts--the-two-phase-vehicle-assignment)
5. [Delivery & Return](#5-delivery--return)
6. [Direct Rental (Provider Side)](#6-direct-rental-provider-side)
7. [Wallet, Settlements & Invoices](#7-wallet-settlements--invoices)
8. [Profile, Settings, Notifications, Trust Score](#8-profile-settings-notifications-trust-score)
9. [Divergences From the Original Guide](#9-divergences-from-the-original-guide)

---

## 1. Dashboard

**Route:** `/provider/dashboard` · **Component:** `src/features/provider/pages/dashboard/ProviderDashboard.tsx`

Stat cards, a recommended-RFQs list, an account-status banner (pending approval / verified / suspended, via `mapAccountStatus`), and a real analytics chart (`recharts` bar chart) driven by a date-range picker (`useProviderDashboardAnalytics`). Two action-item counters are pulled from `providerFleetCapacityService.getActionItems()` and surfaced prominently — **awards needing vehicle assignment** and **Direct Rental requests with a fleet-capacity conflict** — both concepts the original guide never had, because both depend on the fleet-capacity engine described in §3/§4/§6.

---

## 2. Marketplace & Bidding — quantity-level, no vehicle chosen at bid time

**This is the single biggest correction to the original guide**, which modeled bidding with a per-line-item **vehicle selection dropdown** at bid time. The real system never asks a provider to pick a specific vehicle when bidding — that happens later, after award (§4).

### Browse

**Route:** `/provider/marketplace` · **Component:** `MarketplacePage.tsx` (+ `RFQCard.tsx`) — filters by vehicle type, duration, location, free-text search; sort by newest/oldest/most-bids/least-bids; paginated. Broadly matches the original guide's intent.

### RFQ Detail & Bid Submission

**Route:** `/provider/marketplace/:id` → `RFQDetailPage.tsx`, then **`/provider/marketplace/:id/bid/:lineItemId`** → `BidSubmissionPage.tsx` (also reused for editing, at `.../edit/:bidId`).

Real bid form fields (`bidSchema` in `BidSubmissionPage.tsx`): `quantity`, `unitPrice`, optional `notes`, and a required `termsAccepted` checkbox. **There is no vehicle-selection field.** Instead, the page:
- Counts the provider's **active fleet vehicles matching the line item's vehicle-type + fuel-type segment** (`vehicleMatchesSegment`, normalized via `FuelTypeNormalizer`) and shows that count.
- Computes `maxBiddableQuantity = min(remainingSlots, activeFleetCount)` — the provider literally cannot offer more than they have matching, unassigned vehicles for.
- Renders a `SegmentCapacityMeter` and `SegmentChip` (from `src/features/provider/components/`) showing how much of that vehicle-type/fuel segment is already committed to other bids/awards/Direct Rental requests — this is the fleet-capacity engine, shared across RFQ bidding and Direct Rental (see §6), and it is completely absent from the original guide.
- Requires the provider to be `VERIFIED` (`isProviderVerified`) and have at least one matching active vehicle (`canBid`) before submitting.

### My Bids

**Route:** `/provider/bids` · **Component:** `MyBidsPage.tsx` — table with status filter (`ALL` plus the real bid-status set), date range, vehicle-type/fuel-type multi-select, search; actions include **View RFQ**, **Edit Bid** (real — providers, not businesses, can edit their own bid's quantity/price/notes while it's still open), and **Withdraw Bid**. The page also cross-references `providerFleetCapacityService.getActionItems()` to badge any bid whose award still needs vehicle assignment (`assignmentByBidId` map) — a direct link into §4's `AwardAssignPage`.

---

## 3. Fleet Management — vehicle lifecycle, not just CRUD

### List & Add/Edit

**Routes:** `/provider/fleet` (`FleetListPage.tsx`), `/provider/fleet/add` and `/provider/fleet/:id/edit` (both `AddVehiclePage.tsx`), `/provider/fleet/:id` (`VehicleDetailPage.tsx`), `/provider/fleet/capacity` (`FleetCapacityOverviewPage.tsx` — platform-wide view of how the provider's whole fleet is split across RFQ commitments vs. Direct Rental vs. available, entirely absent from the original guide).

`AddVehiclePage.tsx` is a **4-tab flow**, not the original guide's 3-step wizard: **Vehicle Info → Photos → Insurance → Documents**. The Photos/Insurance/Documents tabs are disabled until the vehicle record is first created from the Vehicle Info tab (`disabled={!vehicleCreated}`) — vehicle creation happens incrementally, tab by tab, with a save action per tab, not one final multi-step submit. Real fields:
- **Vehicle Info:** plate number, make, model, year (≥2000), color, vehicle type, fuel type (Petrol/Diesel/Electric/Hybrid), seat capacity (1–100), optional VIN.
- **Photos:** 5 required angles — front (plate visible), back, left, right, interior.
- **Insurance:** policy number, insurance company, coverage type, coverage amount, start date, expiry date (must be future).
- **Documents:** a distinct tab from Insurance — real document types are `VEHICLE_REGISTRATION` (Libre), `VEHICLE_INSURANCE`, and `BOLO_PLATE` (number-plate certificate), all required. The original guide only had a single "insurance certificate upload" step; the real document set is broader and Ethiopia-specific.

### Vehicle Detail — direct rental toggle and lifecycle

**Route:** `/provider/fleet/:id` · **Component:** `VehicleDetailPage.tsx`. Beyond photos/insurance/assignment-history (which the original guide anticipated), this page also:
- Lets the provider set a **daily rental rate** and **toggle Direct Rental on/off** for this specific vehicle (`directRentalService.setVehicleRentalRate`/`enableDirectRental`/`disableDirectRental`) — this is Direct Rental Story 21.1, entirely new territory vs. the original guide.
- Shows a **commitment label** ("On contract" / "On RFQ award" / "Available") computed from `providerFleetCapacityService.getCapacitySnapshot()` — i.e., the UI actively tells the provider whether a vehicle is tied up before they try to enable it for Direct Rental or bid with it elsewhere.
- Vehicle status values go beyond the original guide's `Active/Assigned/Maintenance`: the real lifecycle (driven from the contract vehicle-card actions, see §4/§5) includes `ASSIGNED`, `DELIVERED`, `RETURNED`, `REPLACED`, and `MAINTENANCE`.

### Maintenance, Replace, Remove (contract-scoped vehicle lifecycle)

These live as dialogs launched from the **contract detail page's Vehicles tab**, not the fleet pages — a vehicle's lifecycle while it's on an active contract is managed from the contract, not from Fleet:
- **`MaintenanceDialog.tsx`** — marks a specific contract-vehicle assignment for maintenance with a required reason (`contractService.markVehicleMaintenance`).
- **`ReplaceVehicleDialog.tsx`** — swaps an assigned vehicle for another of the provider's available vehicles of the same type, with a required reason (`contractService.replaceVehicle({ oldVehicleId, newVehicleId, reason })`).
- **`ReturnVehicleDialog.tsx`** — initiates an early return (`contractService.initiateReturn`); the response can carry a **`noticeRequired`** flag with an `earliestReturnDate` — a real early-return-notice mechanic (`EarlyReturnNotice` entity on the backend) not in the original guide.
- **`RemoveVehicleDialog.tsx`** — removes a not-yet-delivered vehicle assignment outright.

---

## 4. Contracts & the Two-Phase Vehicle Assignment

**Routes:** `/provider/contracts` (`ProviderContractListPage.tsx`), `/provider/contracts/:id` (shared `ContractDetailPage.tsx`), `/provider/contracts/:id/assign` (`AssignVehiclesPage.tsx`), `/provider/contracts/:id/terms-preview`, `/provider/contracts/:id/delivery`.

### List

Status filter covers the real ~15-value set (`PENDING_ESCROW, PENDING_VEHICLE_ASSIGNMENT` labeled "Needs Action", `PENDING_SIGNING, SIGNED, PENDING_ACTIVATION, PENDING_DELIVERY, PARTIALLY_DELIVERED, PARTIALLY_RETURNED, ACTIVE, ON_HOLD, COMPLETED, TERMINATED, CANCELLED, DISPUTED, TIMEOUT_PENDING`), plus business/vehicle-type/fuel-type/date filters — not the original guide's 3-tab `Pending Assignment/Active/Completed`.

### Phase 1 — assign vehicles to the RFQ award (before a contract vehicle-assignment ever happens)

**Route:** `/provider/bids/:bidId/assign` · **Component:** `AwardAssignPage.tsx` (+ `rfqAwardService`). This is reached from **My Bids**, not from Contracts. Because bidding is quantity-only (§2), once a bid is awarded — possibly split across multiple providers per line item — each provider must link specific fleet units to their award before those units count as committed. The page shows one tab per award needing assignment, an alert with the total remaining-vehicle count across all awards, and per-award vehicle pickers. This step exists specifically so the shared fleet-capacity engine (§2, §6) can track commitments **before** a contract-level vehicle assignment ever happens.

### Phase 2 — assign vehicles to the contract itself

**Route:** `/provider/contracts/:id/assign` · **Component:** `AssignVehiclesPage.tsx`. This is the step that actually moves a contract out of `PENDING_VEHICLE_ASSIGNMENT` — for each contract line item still needing vehicles, the provider selects from their available fleet (already filtered to exclude anything already assigned in this contract) up to the remaining quantity, then submits a **batch assignment** (`contractService.assignVehicle({ contractId, lineItemId, vehicleIds, driverName, driverPhone })` — driver fields exist in the payload but aren't collected by this screen's UI yet). Once every line item is fully assigned, the contract can proceed to the dual-party OTP e-signature step (`PENDING_SIGNING`) described in `BUSINESS_PORTAL_GUIDE.md` §4.

**Correction to an earlier reading of this pattern:** this is genuinely a two-step, two-screen flow (award-level assignment, then contract-level assignment) — not a single "Vehicle Assignment Page" as the original guide assumed, and not something the provider can skip by picking vehicles at bid time.

### Contract detail — provider-specific actions

On the shared `ContractDetailPage.tsx`, provider-only affordances include: **Assign Vehicles** (when the contract still needs them), **Reset Vehicle Assignments** (destructive — clears all assignments and returns the contract to `PENDING_VEHICLE_ASSIGNMENT`), and **Request Extension** (currently a stub — `toast.info('Extension request feature coming soon')`; extension is business-initiated only, see `BUSINESS_PORTAL_GUIDE.md` §4). Vehicle cards on the Vehicles tab expose the maintenance/replace/return/remove dialogs from §3, each gated on vehicle status and checklist status.

---

## 5. Delivery & Return

**Route:** `/provider/contracts/:id/delivery` · **Component:** `ProviderDeliveryPage.tsx`. Per assigned vehicle, the provider fills a delivery checklist, then requests a **delivery OTP** (`deliveryService.requestDeliveryConfirmation`/`generateOTP`) which the business must relay back for verification (`verifyOTP`) — this confirms the vehicle as `DELIVERED`. Returns are a **separate, parallel flow**: once a vehicle is `DELIVERED`, either party can initiate a return session; the provider views the return checklist the business submits and, once approved, the OTP exchange repeats for the return leg. Both OTP flows are real, distinct instances of the same mechanism — one for delivery, one for return — not a single "OTP verification" step as the original guide's single-OTP delivery flow assumed. Codes are never returned in any API response body (by design, per a "not exposed for security" comment in the backend) — the provider must always ask the counterparty to read the OTP aloud/type it in, exactly as the original guide's UX assumed, just with two independent occurrences instead of one.

---

## 6. Direct Rental (Provider Side)

**Entirely absent from the original guide.** A fixed-price, non-bidding booking channel parallel to RFQ bidding (see `BUSINESS_PORTAL_GUIDE.md` §6 and `backlog/post-mvp/epic-21-direct-rental.md` for the full picture).

| Route | Component |
|---|---|
| `/provider/direct-rental/requests` | `ProviderRequestsPage.tsx` |
| `/provider/direct-rental/requests/:id/respond` | `ProviderRequestResponsePage.tsx` |

`ProviderRequestResponsePage.tsx` is the real vehicle-level accept/reject screen: for every vehicle in the request, the provider picks accept/reject (defaulting to accept) with a required rejection reason (≥5 chars) per rejected vehicle, or a request-level reason (≥10 chars) if rejecting everything. If the request is `isAllOrNone`, accepting any vehicle commits to accepting all.

**Fleet-capacity conflict checking is real and visible here, not just in the backend:** before the provider submits their response, the page calls `directRentalService.getAcceptPreview(id)` (debounced 400ms after each response change) and renders **`FleetCapacityConflictSheet.tsx`** with conflict codes per vehicle — `DR_ACCEPT_AWARD_NOT_FULLY_ASSIGNED`, `DR_ACCEPT_VEHICLE_ON_AWARD`, `DR_ACCEPT_BID_CAPACITY` — sourced from the same `IProviderFleetCapacityService` the RFQ bidding flow uses (§2). This preview is advisory; the real gate is re-enforced server-side at submit time, so a false "safe to accept" is possible if the preview and submit-time checks ever drift (a risk called out explicitly in the epic doc).

Accepted/partially-accepted requests auto-create a contract (`Contract.SourceType = DIRECT_RENTAL`) with vehicle assignments **pre-created from the accepted vehicles** — unlike the RFQ path, Direct Rental contracts skip the two-phase vehicle-assignment dance in §4 entirely, because the specific vehicles were already chosen at accept time.

---

## 7. Wallet, Settlements & Invoices

| Route | Component |
|---|---|
| `/provider/wallet` | `ProviderWalletPage.tsx` |
| `/provider/wallet/settlements` | `ProviderSettlementsPage.tsx` |
| `/provider/wallet/settlements/:payoutId` | `SettlementDetailPage.tsx` |
| `/provider/wallet/invoices` | `ProviderInvoicesPage.tsx` |
| `/provider/wallet/invoices/:id` | `ProviderInvoiceDetailPage.tsx` |

`ProviderWalletPage.tsx` balance cards: **Available Balance**, **Pending Withdrawal**, **Total Earned (This Month)** — withdrawal-only (no deposit action; providers don't fund a wallet the way businesses do), transaction types `SETTLEMENT, WITHDRAWAL, FEE`. Settlement history is its **own dedicated route with a detail page per payout**, not just a modal breakdown as the original guide sketched. **Invoices are a wholly separate, real feature the original guide never mentioned**: the platform's invoice model is **provider-submitted, admin-reviewed** (inverting the assumption that the system just auto-generates an invoice for the provider to view) — `ProviderInvoicesPage.tsx`/`ProviderInvoiceDetailPage.tsx` are where a provider submits and tracks these, and `ADMIN_PORTAL_GUIDE.md` §10 is where they get approved.

Settlement cadence: be aware the coverage audit found **two backend code paths disagreeing** on whether settlement cadence is tier-based (Bronze/Silver monthly, Gold bi-weekly, Platinum weekly) or a flat rolling 30-day cycle per contract — this was not reconciled as of the audit date, so don't treat either description as fully authoritative without checking `GenerateSettlementCommand*.cs` directly.

---

## 8. Profile, Settings, Notifications, Trust Score

**Routes:** `/provider/profile` (`ProfilePage.tsx`), `/provider/settings` (`SettingsPage.tsx`), `/provider/notifications` (`NotificationsPage.tsx`).

`ProfilePage.tsx` has the same **seven-tab shape** as the business portal (§ProfilePage in `BUSINESS_PORTAL_GUIDE.md`): **Basic Info, Contact Person, Documents, Bank Account, Preferences, Security, Sessions** — not the original guide's four tabs (Details/Trust Score/Documents/Settings). Bank-account management on the provider side uses **dual-OTP** (email + phone) per the coverage audit, a detail the original guide didn't anticipate.

**Trust score is real, formula-based, and visible to the provider on their own dashboard/profile** — directly contradicting the original guide's (and the epic backlog's) assumption that trust score is admin/business-facing only. The formula (`TrustScoreCalculator.cs`, backend): `Base(50 if verified / 0 if not) + CompletionRate×20 + OnTimeRate×20 − NoShowRate×30 + RejectionPenalty`, mapped to a tier (Bronze/Silver/Gold/Platinum) that drives commission rate. **Important caveat found in the coverage audit's rewrite pass:** this formula has **zero production call sites** — no event handler anywhere calls it, so in practice every provider's trust score is frozen at its registration-time default (50) unless an admin manually reassigns a tier. Don't assume the score shown in the UI is live-updating from contract performance; today it is not wired up end-to-end, even though the UI component that renders it is fully built.

Seeded commission rates by tier: Bronze 10%, Silver 8%, Gold 6%, Platinum 5% — there is no "Red Zone" tier in code, despite that appearing in some business-overview material; treat the tier/commission numbers in this doc as the ones to trust.

---

## 9. Divergences From the Original Guide

- **Bidding is quantity + price only — no vehicle selection at bid time.** Vehicle assignment happens in two later phases (award-assign, then contract-assign). See §2, §4.
- **A shared fleet-capacity engine** (`SegmentCapacityMeter`, `FleetCapacityConflictSheet`, `providerFleetCapacityService`) cross-checks RFQ bids/awards against Direct Rental commitments by vehicle-type+fuel segment — entirely new territory, touching the marketplace, fleet, contracts, and Direct Rental areas alike.
- **Vehicle registration is a 4-tab incremental flow** (Vehicle Info → Photos → Insurance → Documents, each gated on the previous being saved), not a single 3-step wizard submitted once at the end.
- **Vehicle lifecycle actions (maintenance/replace/return/remove) live on the contract detail page**, not on the Fleet pages, and include a real early-return-notice mechanic.
- **Two distinct OTP flows exist** — delivery and return — not one.
- **Direct Rental (§6)** is a whole parallel acquisition channel with its own fleet-capacity-aware accept/reject screen.
- **Invoices are provider-submitted, not system-generated** — a real, separate feature from Settlements.
- **Trust score is provider-visible** but **not actually wired to live events** — the UI is real, the backend recalculation is not, per the coverage audit.
- **Profile has 7 tabs including Bank Account (dual-OTP) and Sessions**, not 4.

For the epic-level status of every area above, see `project-docs/18_Implementation_Coverage_Audit.md`, particularly §4 (RFQ/Bidding), §5 (Trust/Risk Scoring), §7.1 (Direct Rental), and §10.2/§10.3 (trust-score wiring and post-award-assignment corrections from the rewrite pass).
