# Business Portal — As-Built Reference
## Movello Web Frontend (React 18.3 + Vite + TanStack Query + Zustand)

**Last verified against code: 2026-07-23**

> **Reframing note:** This file was originally written as a from-scratch *build guide* (the kind fed to an AI scaffolding tool such as Lovable), including illustrative code snippets for a portal that didn't exist yet. The business portal has since been built, and its real shape differs from that original assumption in several load-bearing ways — most importantly the RFQ/bid/award model. This version documents **what actually exists in code today**, verified against `marketplace-project-implementation/movello-marketplace-core/src/features/business/**` and the route table in `src/App.tsx`. Where this doc and the original guide's code samples disagree, trust this doc.

All business routes live under `/business` inside `BusinessLayout`, gated by `ProtectedRoute allowedRoles={['business']}`.

| Route | Component |
|---|---|
| `/business/dashboard` | `BusinessDashboard.tsx` |
| `/business/rfqs` | `RFQListPage.tsx` |
| `/business/rfqs/create` | `RFQCreateWizard.tsx` |
| `/business/rfqs/:id` | `RFQDetailPage.tsx` |
| `/business/rfqs/:id/edit` | `RFQCreateWizard.tsx` (same wizard, edit mode via route param) |
| `/business/rfqs/:id/bids` | `BidReviewPage.tsx` |
| `/business/contracts` | `BusinessContractListPage.tsx` |
| `/business/contracts/:id` | `ContractDetailPage.tsx` (shared with provider/admin) |
| `/business/contracts/:id/terms-preview` | `ContractTermsPreviewPage.tsx` |
| `/business/contracts/:id/delivery` | `BusinessDeliveryPage.tsx` |
| `/business/contracts/:id/return-checklist` | `ReturnChecklistPage.tsx` |
| `/business/wallet` | `BusinessWalletPage.tsx` |
| `/business/wallet/deposit-history` | `DepositHistoryPage.tsx` |
| `/business/wallet/escrow` | `BusinessEscrowWalletPage.tsx` |
| `/business/direct-rental/vehicles` | `VehicleBrowsePage.tsx` |
| `/business/direct-rental/vehicles/:id` | `BusinessVehicleDetailPage.tsx` |
| `/business/direct-rental/cart` | `CartPage.tsx` |
| `/business/direct-rental/requests` | `BusinessRequestsPage.tsx` |
| `/business/direct-rental/requests/:id` | `BusinessRequestDetailPage.tsx` |
| `/business/profile` | `ProfilePage.tsx` |
| `/business/settings` | `SettingsPage.tsx` |
| `/business/notifications` | `NotificationsPage.tsx` |

That's **6 functional areas**, not the original guide's Dashboard / RFQ / Bid Review / Contracts / Wallet / Profile six-item list in name only — the *content* of RFQ Management and Bid Review has changed shape entirely (line items + split awards), and Direct Rental is a whole seventh area the original guide never anticipated.

---

## Table of Contents

1. [Dashboard](#1-dashboard)
2. [RFQ Management — the real line-item model](#2-rfq-management--the-real-line-item-model)
3. [Bid Review & Award — per-line-item, split-capable](#3-bid-review--award--per-line-item-split-capable)
4. [Contract Management](#4-contract-management)
5. [Wallet Management](#5-wallet-management)
6. [Direct Rental](#6-direct-rental)
7. [Profile, Settings, Notifications](#7-profile-settings-notifications)
8. [Divergences From the Original Guide](#8-divergences-from-the-original-guide)

---

## 1. Dashboard

**Route:** `/business/dashboard` · **Component:** `src/features/business/pages/dashboard/BusinessDashboard.tsx`

Stat cards (active RFQs, ongoing contracts, wallet balance available/locked), quick actions (create RFQ, view contracts, top up wallet), and a recent-activity feed. This area is broadly consistent with what the original guide described and hasn't drifted structurally — the real divergences are downstream, in RFQ/Bid/Contract.

---

## 2. RFQ Management — the real line-item model

**This is the single biggest correction to the original guide.** The original guide modeled an RFQ as one vehicle type + one quantity + one start/end date + one bid deadline, with line items introduced only loosely in a later section. The real system has always been **header + line items** since the wizard was built, and there is no "single vehicle type" RFQ path anywhere in the UI.

### RFQ List

**Route:** `/business/rfqs` · **Component:** `src/features/business/pages/rfq/list/RFQListPage.tsx`

- Filters: full-text search, vehicle-type dropdown, date range, and a **multi-select status filter** (checkboxes in a dropdown, not tabs) covering `DRAFT, PUBLISHED, BIDDING, PARTIALLY_AWARDED, AWARDED, COMPLETED, CANCELLED, EXPIRED`. Note `PARTIALLY_AWARDED` and `EXPIRED` — neither exists in the original guide's tab list.
- Server-side pagination via `DataPagination`.
- Actions per RFQ: View, Edit (draft only), Delete/Cancel (with confirmation dialogs).

### Create/Edit RFQ Wizard

**Route:** `/business/rfqs/create` (and `/business/rfqs/:id/edit`, same component) · **Component:** `RFQCreateWizard.tsx`, composing `RFQCreateStep1.tsx` / `RFQCreateStep2.tsx` / `RFQCreateStep3.tsx`.

The wizard gates on business verification status before allowing any RFQ creation (`businessProfile.status !== 'VERIFIED'` shows a warning card with a link to `/business/profile`, matching the original guide's Rule BR-001). It also persists an in-progress draft to `localStorage` (keyed per user) so a refresh doesn't lose work, separate from the backend's own `DRAFT` RFQ status.

**Step 1 — Basic Info:** just `title` (required) and `submissionDeadline` (the bid deadline; a date-time). **There is no header-level start date, end date, description, or business-wide date range** — those all moved to the line-item level in Step 2. This is a structural change from the original guide, not a rename.

**Step 2 — Line Items** (real fields, per line item, `RFQCreateStep2.tsx`):
- `vehicleType` (dropdown, required)
- `quantity` (1–50, required)
- `term`: `SHORT_TERM` or `LONG_TERM` — **short-term is capped at 30 days**; switching an item to `SHORT_TERM` auto-clamps its end date back to start+30 if it currently exceeds that
- `purpose` (required free text, ≤500 chars) — a field the original guide never had
- `fuelType` (optional; sourced from the `ENGINE_TYPE` DB lookup via `lookupService.getFuelTypes()`, defaults to "Any")
- `requiredFrom` / `requiredTo` (per-line-item dates, not header dates; `requiredFrom` must be after the bid deadline)
- `pickupLocation` / `dropoffLocation` (free text, optional)
- `specifications` (optional, ≤200 chars)

Constraints: **max 10 line items per RFQ**, **max 50 total vehicles across all line items** (both enforced by zod schema, matching backend). Duration is computed client-side with the exact same `Math.ceil` formula the backend uses, and a badge marks a line item "(Long Term)" once duration ≥ 30 days regardless of the selected `term` value.

**Step 3 — Review & Publish** (`RFQCreateStep3.tsx`): summary table per line item, market-price guidance, "Save as Draft" vs. "Publish" — publish is skipped in-place if editing an already-published RFQ (it just updates).

### RFQ Detail

**Route:** `/business/rfqs/:id` · **Component:** `RFQDetailPage.tsx` — full line-item breakdown, bid counts, status timeline, and status-conditional actions (Edit/Delete for drafts, View Bids/Award once bidding has started, View Contract once awarded).

---

## 3. Bid Review & Award — per-line-item, split-capable

**Route:** `/business/rfqs/:id/bids` · **Component:** `src/features/business/pages/rfq/bids/BidReviewPage.tsx` (supporting: `BidCard.tsx`, and the shared `src/shared/components/business/SplitAwardDialog.tsx`)

The original guide modeled award as one action across the whole RFQ, with a single "Award Selected Bids" bar and a separate manual "Partial Award" fallback dialog for insufficient wallet balance. The real page works differently:

- Bids are grouped into **one tab per line item** (`Tabs`/`TabsList`), each tab showing that line item's required quantity, pickup/dropoff, awarded-so-far quantity (with a "Partially Awarded"/"Fully Awarded" badge once any award exists), and its own bid grid.
- **Blind bidding by convention, not by API contract:** bids display provider hash/trust score/quantity/unit price/notes/submission time, sortable by price (asc/desc, default low-to-high), quantity, trust score, or submission time — but the coverage audit found `GetBidsByRFQQuery`/`GetBidQuery` set the real provider name unconditionally in the API response regardless of award status; blind bidding is enforced only by the web UI choosing not to render the provider's real name pre-award, not by the API withholding it. Don't assume the backend is blind — it isn't.
- Selecting one or more bids within a line item and clicking **"Award Selected Bids ({count})"** (a button local to that line item, not a single global bar) opens `SplitAwardDialog.tsx`, which lets the business **specify a quantity per selected bid** and confirms the split before submitting `AwardItem[]` (each with `bidId`, `lineItemId`, `quantityAwarded`) to `bidService.awardBids`. Awarding is per line item — there is no "award the whole RFQ in one action" concept.
- **There is no separate "partial award due to insufficient wallet balance" dialog with Deposit/Award-Partial/Cancel options** the way the original guide built one. The real flow simply lets the business choose smaller quantities per bid inside the same `SplitAwardDialog`; a 30-day escrow-lock cap is also surfaced inside that dialog as a business rule not documented in any epic.
- On successful award, a toast confirms the count and the page navigates to `/business/contracts` after a short delay. "Go to Contract" quick links appear inline per line item once contracts exist for it (linking to the admin path if the viewer is an admin, business path otherwise — the component is admin-aware via `useAuthStore`).
- **Providers, not businesses, can edit their own bids** — an edit-bid dialog exists in this same component's code, but `canEditBids = false` is hardcoded for the business view; the edit-bid capability actually belongs to the provider/admin surfaces, not this page.

---

## 4. Contract Management

**Routes:** `/business/contracts` (`BusinessContractListPage.tsx`), `/business/contracts/:id` (`ContractDetailPage.tsx` — **a single component shared across business, provider, and admin routes**, branching on `location.pathname`), plus `/business/contracts/:id/terms-preview`, `/delivery`, `/return-checklist`.

### List

Filters: status (multi-select against the real 15-value set below, not the original guide's 4-tab `Pending Activation/Active/Completed/Terminated`), business/provider text search, vehicle type, fuel type, date range. Real status values seen in the filter dropdown: `PENDING_ESCROW, PENDING_VEHICLE_ASSIGNMENT, PENDING_SIGNING, SIGNED, PENDING_ACTIVATION, PENDING_DELIVERY, PARTIALLY_DELIVERED, PARTIALLY_RETURNED, ACTIVE, ON_HOLD, COMPLETED, TERMINATED, CANCELLED, DISPUTED, TIMEOUT_PENDING`.

### The real lifecycle (corrects the original guide's `pending → active → suspended → completed`)

There is **no `SUSPENDED` state**. Nominally there's a 17-member `ContractStatus` enum in the backend, but the coverage audit's rewrite pass found it has **zero references anywhere outside its own file** — `Contract.Status` is a plain string column in practice, producing **18** real values including a `CANCELLED` value the enum doesn't even define. Key real steps, in rough order:

1. **`PENDING_VEHICLE_ASSIGNMENT`** — after award, the provider must assign specific fleet vehicles to the contract's line items (see `PROVIDER_PORTAL_GUIDE.md` §Contracts) before the business can do anything else. The detail page shows a blue banner here ("Waiting for Vehicle Assignment" on the business side).
2. **`PENDING_SIGNING`** — once vehicles are assigned, a **dual-party OTP e-signature** step (distinct from delivery-confirmation OTP) requires both business and provider to accept contract terms. The business sees a green "Ready to Sign" banner and can review the assigned vehicles + terms (`ContractTermsViewer`) before signing.
3. **`SIGNED`** is real in the data model but transient in practice — set and immediately overwritten to `PENDING_DELIVERY` in the same backend call, so it is rarely if ever the value you'll observe on a live contract.
4. **`PENDING_DELIVERY` / `PARTIALLY_DELIVERED` / `ACTIVE`** — delivery proceeds vehicle-by-vehicle: provider fills a delivery checklist, business (or provider, per role) requests/verifies a delivery OTP per vehicle (`OTPInput` component, `deliveryService.generateOTP`/`verifyOTP`), and the vehicle moves to `DELIVERED`.
5. Returns are a **parallel, separate OTP + checklist flow** from delivery, tracked as `ReturnSession`s (`deliveryService.getReturnSessionsByContractId`) — the business fills a return checklist (`ReturnChecklistPage.tsx` at `/business/contracts/:id/return-checklist`, plus `ReturnConfirmationFlow.tsx`), and once approved requests a return OTP. A "Returns" tab (business-only — hidden for provider/admin views of the same page) on the contract detail page shows a live count badge of active return sessions.
6. **`PARTIALLY_RETURNED` → completion**: once all vehicles are returned, a banner appears; if any settlement cycles are still pending, it blocks completion with a specific count and a pointer to Settlement Policies. Once clear, either party can **Request Completion**, the other **Approves** or **Rejects** (with a reason) — a real negotiation, not an automatic transition. A full `completionHistory` timeline renders on the Overview tab. Admins can force this via **Admin Override: Complete**.
7. **Termination** is a **separate request/approve flow** (`AdminContractTerminationPage.tsx` on the admin side) from completion — not a status a business can set unilaterally.

### Extension (not "renewal")

`ExtendContractDialog.tsx` (business-only action, not shown to provider/admin) is the real analogue of what the original guide called "renewal" — and it is **materially different**:
- Only available when the contract `isLongTerm` — short-term contracts get a "Cannot Extend Contract" message instead of a form.
- Business picks **1–12 months**; the new end date is always **rounded to end of that month** (`endOfMonth(addMonths(currentEnd, N))`).
- A reason is required (recorded in history).
- **No provider accept/reject step, no new contract entity** — it lengthens the same contract, generates new settlement schedules for the extension period, and keeps all existing rates/terms.
- There is **no `renew` endpoint anywhere in the backend** — don't build or describe a "renewal creates a new contract" flow; it doesn't exist.

### Other real actions on this page
- **Raise Dispute** (business-only) — opens a reason dialog; note the coverage audit found no backing dispute-engine entities in the backend behind the `DISPUTED` contract status, so this is closer to a flag than a workflow today.
- **Release Payment** button appears when active/partially-delivered with `amountRemaining > 0` (present in code but effectively a manual/legacy affordance layered over the automated settlement schedule described in §5).
- Vehicle cards per assigned vehicle show role- and state-conditional actions: fill/view delivery checklist, request delivery OTP, initiate return, fill/view return checklist, request return OTP — all gated tightly on `vehicle.status` and checklist status, not just contract status.

---

## 5. Wallet Management

**Routes:** `/business/wallet` (`BusinessWalletPage.tsx`), `/business/wallet/deposit-history` (`DepositHistoryPage.tsx`), `/business/wallet/escrow` (`BusinessEscrowWalletPage.tsx` — a **dedicated escrow-detail page**, not just a stat card, reachable via a "View escrow wallet" click-through on the Locked-in-Escrow stat card).

Balance cards: **Available**, **Locked in Escrow**, **Pending Withdrawal**, **Total** — four, not the original guide's two (Available/Locked). Transaction type filter covers `DEPOSIT, WITHDRAWAL, ESCROW_LOCK, ESCROW_RELEASE, FEE`. Both **Deposit** and **Withdraw** are real actions here (`DepositDialog`/`WithdrawDialog` from `src/shared/components/wallet/components`) — the original guide only covered deposit; withdrawal to a bank account is a real business-side capability, not provider-only. Deposit supports Chapa/Telebirr-style gateway checkout (redirect + `DepositCallbackPage.tsx` at the public route `/wallet/deposit-callback`) as well as manual bank-transfer deposits tracked in Deposit History and, on the admin side, a deposit-request approval queue.

---

## 6. Direct Rental

**Entirely absent from the original guide.** A fixed-price, non-bidding booking channel that runs in parallel to RFQ bidding — browse a catalog of provider-listed vehicles at published daily rates, build a multi-provider cart, submit, and the system splits it into one request per provider. Full business-rule detail: `backlog/post-mvp/epic-21-direct-rental.md` and `MVP_MODULAR/MVP_final_docs/MVP_DIRECT_RENTAL_SPECIFICATION.md`.

| Route | Component | Notes |
|---|---|---|
| `/business/direct-rental/vehicles` | `VehicleBrowsePage.tsx` | Filter by provider, vehicle type, make/model/year, daily-rate range, seating, fuel type, free text; paginated |
| `/business/direct-rental/vehicles/:id` | `BusinessVehicleDetailPage.tsx` | Specs, provider info, daily rate, example multi-day total |
| `/business/direct-rental/cart` | `CartPage.tsx` | Multi-provider cart, grouped by provider |
| `/business/direct-rental/requests` | `BusinessRequestsPage.tsx` | Status/date filters, paginated |
| `/business/direct-rental/requests/:id` | `BusinessRequestDetailPage.tsx` | Status-history timeline, per-vehicle accept/reject outcome, "View Contract" once accepted |

**Cart mechanics (`CartPage.tsx`, verified in code):**
- Items grouped by `providerId` for display; each item snapshots vehicle, dates, and daily rate at add-time; editing dates recalculates the total.
- The cart itself **does not lock vehicles** — only a submitted request does; add-to-cart re-validates availability and can fail with a conflict error if a vehicle was locked elsewhere since being added.
- Before opening the submit dialog, a **submit-preview** call (`useCartSubmitPreview`) checks estimated wallet gating; if `canSubmit` is false, the business gets a toast quoting available balance vs. estimated escrow hold instead of a dialog with deposit/partial options.
- The submit dialog itself collects **`isAllOrNone`** (a checkbox — provider must accept every vehicle in their request or reject the whole thing) and optional **special instructions** (≤1000 chars), then calls submit, which creates one `DirectRentalRequest` per provider (numbered `DR-{yyyyMMdd}-{seq}`, 48-hour expiry) and clears the cart. A toast confirms "Created N rental request(s)" and the page navigates to the requests list.
- Requests can be cancelled by the business only while `PENDING` and before expiry; cancelling releases the vehicle locks.
- Accepted/partially-accepted requests **auto-create a contract** (`SourceType = DIRECT_RENTAL`) that then flows through the exact same contract → escrow → delivery → settlement pipeline described in §4 — Direct Rental is an acquisition channel, not a separate contract type.

---

## 7. Profile, Settings, Notifications

**Routes:** `/business/profile` (`ProfilePage.tsx`), `/business/settings` (`SettingsPage.tsx`), `/business/notifications` (`NotificationsPage.tsx`).

`ProfilePage.tsx` has **seven tabs**, not the original guide's three (Details/Documents/Settings): **Basic Info, Contact Person, Documents, Bank Account, Preferences, Security, Sessions** — bank-account management and active-session/device management are real, separate tabs here, both absent from the original guide. `SettingsPage.tsx` separately covers change-password, per-category notification-channel preferences, two-factor auth, active sessions (again), and general preferences — there is real overlap between the Profile "Security/Sessions" tabs and the Settings page; both exist and both route independently, they are not duplicates by mistake.

`NotificationsPage.tsx` is a dedicated in-app notification center/inbox, backed by the platform's real-time SignalR notification hub and the admin-configurable multi-channel (email/SMS/push) system described in `ADMIN_PORTAL_GUIDE.md` §11 — this whole area is far more built out than the original guide's assumption of a simple settings toggle.

Tier display (STANDARD/BUSINESS_PRO/ENTERPRISE/GOV_NGO) lives in the Basic Info tab of the Profile page, as a badge with tier limits — matching the original guide's intent, though tier thresholds are admin-configured versioned master data (see `ADMIN_PORTAL_GUIDE.md` §4), not hardcoded.

---

## 8. Divergences From the Original Guide

- **RFQ is header + line items**, not a single vehicle-type/date-range form. No header-level start/end date exists — dates live per line item. See §2.
- **`term` (SHORT_TERM/LONG_TERM, 30-day cap on short-term) and `purpose` (required) are real fields** the original guide never had.
- **Award is per line item with a split-award dialog**, not a single global "Award Selected Bids" action with a separate insufficient-funds dialog. See §3.
- **Blind bidding is UI-only** — the API does not withhold the provider's real name; don't assume backend-level anonymization.
- **No `SUSPENDED` contract status, no `renew` endpoint.** "Renewal" is business-initiated **extension** of the same long-term contract only. See §4.
- **Contract e-signature is a dual-party OTP step** distinct from delivery OTP, gated behind a vehicle-assignment step that must complete first.
- **Completion is a request/approve/reject negotiation** gated on full returns + settled cycles, not an automatic end-date transition.
- **Wallet has 4 balance categories and business-side withdrawal**, not 2 categories with deposit-only.
- **Direct Rental (§6) is a whole feature area** with its own cart/request/contract-creation pipeline, absent from the original guide entirely.
- **Profile has 7 tabs including Bank Account and Sessions**, not 3.
- One piece of dead code found during this rewrite: `src/features/business/pages/contracts/BusinessPendingOTPsPage.tsx` exists (a pending-delivery-OTP dashboard with countdown timers) but is not imported or routed anywhere in `App.tsx` — orphaned, not reachable from the live app.

For the epic-level status of every area above (what's fully done vs. partial vs. diverges from its backlog doc), see `project-docs/18_Implementation_Coverage_Audit.md`, particularly §3 (Contracts), §4 (RFQ/Bidding), §6 (Wallet/Notifications), and §7.1 (Direct Rental).
