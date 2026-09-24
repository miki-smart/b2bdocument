# Admin Portal — As-Built Reference
## Anqelba Car Rental Web Frontend (React 18.3 + Vite + TanStack Query + Zustand)

**Last verified against code: 2026-07-23**

> **Reframing note:** This file was originally written as a from-scratch *build guide* (the kind fed to an AI scaffolding tool such as Lovable). The admin portal has been built for a long time and has grown far beyond that original scope. This version is a **reference of what actually exists in code today** — real routes, real components, real flows — verified against `marketplace-project-implementation/anqelbacarrental-marketplace-core/src/features/admin/**` and the route table in `src/App.tsx`. Treat code as the source of truth if this drifts again; re-derive from `project-docs/18_Implementation_Coverage_Audit.md` first.

All admin routes live under `/admin` inside `AdminLayout`, gated by `ProtectedRoute allowedRoles={['admin']}`. The admin portal is dramatically larger than the original guide's 5 sections (Dashboard, KYC/KYB, User Management, Transaction Monitoring, System Settings) — in practice it has **seven** functional areas: Dashboard, Verifications (incl. admin-initiated onboarding), Master Data / Settings, Users, Operations (RFQ/Bids/Contracts/Settlements/Wallet Accounts/Monitoring/Direct Rental), Wallets, Finance, and Notifications (Templates/Providers). This doc is organized around those seven, each with its real route table.

---

## Table of Contents

1. [Dashboard](#1-dashboard)
2. [Verifications (KYB/KYC/Vehicle)](#2-verifications-kybkycvehicle)
3. [Admin-Initiated Onboarding](#3-admin-initiated-onboarding)
4. [Master Data & Settings](#4-master-data--settings)
5. [Users](#5-users)
6. [Operations — RFQ, Bids, Contracts](#6-operations--rfq-bids-contracts)
7. [Operations — Settlements, Wallet Accounts, Monitoring](#7-operations--settlements-wallet-accounts-monitoring)
8. [Direct Rental Oversight](#8-direct-rental-oversight)
9. [Wallets](#9-wallets)
10. [Finance — Settlement/Withdrawal/Deposit/Invoice Queues](#10-finance--settlementwithdrawaldepositinvoice-queues)
11. [Notifications — Templates & Providers](#11-notifications--templates--providers)
12. [Cross-Cutting Notes & Divergences](#12-cross-cutting-notes--divergences)

---

## 1. Dashboard

**Route:** `/admin/dashboard`
**Component:** `src/features/admin/pages/dashboard/AdminDashboard.tsx`

Stat cards, charts and recent-activity feed drawing from platform-wide queries (users, transactions, verifications). Functionally similar to what the original guide described — this area has not drifted much. Treat the detailed chart/stat inventory as illustrative, not contractual; the important fact is that everything else in this document is a *sibling* of the dashboard, not a subset of it — the admin portal is not "dashboard + settings," it's the seven areas below.

---

## 2. Verifications (KYB/KYC/Vehicle)

This is the real home of what the original guide called "KYC/KYB Verification." It is list+detail per entity type, not a single unified queue with tabs.

| Route | Component |
|---|---|
| `/admin/verifications` | redirects to `/admin/verifications/businesses` |
| `/admin/verifications/businesses` | `BusinessVerificationListPage.tsx` |
| `/admin/verifications/businesses/:id` | `BusinessVerificationDetailPage.tsx` |
| `/admin/verifications/providers` | `ProviderVerificationListPage.tsx` |
| `/admin/verifications/providers/:id` | `ProviderVerificationDetailPage.tsx` |
| `/admin/verifications/providers/:id/add-vehicle` | `AdminAddVehiclePage.tsx` |
| `/admin/verifications/vehicles` | `VehicleVerificationListPage.tsx` |
| `/admin/verifications/vehicles/:id` | `VehicleVerificationDetailPage.tsx` |
| `/admin/verifications/vehicles/:id/edit` | `AdminVehicleEditPage.tsx` |

Each list page is its own dedicated page — there is **no single "Verification Queue" page with Pending/Approved/Rejected tabs** the way the original guide assumed; business, provider, and vehicle verification are three separate list+detail pairs, each with its own filters (status, search, date range).

Detail pages (`BusinessVerificationDetailPage.tsx` 366 lines, `ProviderVerificationDetailPage.tsx` 598 lines, `VehicleVerificationDetailPage.tsx` 766 lines — these are substantial, not simple approve/reject screens) render as stacked sections rather than tabs: entity info, document gallery (`DocumentGallery.tsx`/`DocumentViewer.tsx`/`PhotoGallery.tsx`/`VehiclePhotoGallery.tsx`), a `VerificationChecklist.tsx`, and action buttons (Approve, `RejectDialog.tsx` with a required reason). Supporting edit dialogs exist per entity: `EditBusinessDialog.tsx`, `EditProviderDialog.tsx`, `EditVehicleDialog.tsx`, `EditInsuranceDialog.tsx`, `AddInsuranceDialog.tsx`.

The provider detail page has an **"Add Vehicle" action** (`AdminAddVehiclePage.tsx`) that lets an admin register a vehicle on a provider's behalf — this is a real, separate page, not a modal, and isn't mentioned in the original guide.

---

## 3. Admin-Initiated Onboarding

Not in the original guide at all, and a real, fully-built feature (flagged as undocumented in the coverage audit, §1 item 1 / §8).

| Route | Component |
|---|---|
| `/admin/verifications/businesses/create` | `AdminBusinessOnboarding.tsx` |
| `/admin/verifications/providers/create` | `AdminProviderOnboarding.tsx` |

Both wizards mirror the self-service onboarding wizards (see `ONBOARDING_GUIDE.md`) but add a **pre-step** (`AdminBusinessPreStep.tsx` / equivalent for provider) that creates the login account itself (email, password, first/last name, phone, preferred language) before the same Business Info → Contact & Address → Documents → Review sequence. If the admin lands on the page with a `?businessId=`/`?providerId=` query param, the pre-step is skipped and the wizard resumes an existing draft instead of creating a new account. Onboarding created this way is tagged distinctly in status history so it's traceable as admin-initiated rather than self-service.

---

## 4. Master Data & Settings

This is the area the original guide underspecified the most — it called it "Master Data Management" with 3 sub-pages (Document Types, KYC Requirements, Business/Provider Tiers, Commission Strategies). The real surface, all under `/admin/settings/*`, has **16 distinct pages**:

| Route | Component | Purpose |
|---|---|---|
| `/admin/settings` → `/admin/settings/system` | `AdminSettingsPage.tsx` | General system settings |
| `/admin/settings/documents` | `DocumentTypesPage.tsx` | Document type catalog |
| `/admin/settings/lookups` | `LookupsPage.tsx` | Generic key/value lookup tables (fuel types, engine types, etc.) |
| `/admin/settings/banks` | `BanksPage.tsx` | Bank master list (for bank-account forms across the platform) |
| `/admin/settings/platform-bank-accounts` | `PlatformBankAccountsPage.tsx` | Anqelba Car Rental's own settlement/receiving bank accounts |
| `/admin/settings/tiers` | `TiersPage.tsx` | Business tiers (STANDARD/BUSINESS_PRO/ENTERPRISE/GOV_NGO) + Provider tiers (BRONZE/SILVER/GOLD/PLATINUM), tabbed |
| `/admin/settings/geography` | `GeographyPage.tsx` | Cities/regions used across address and location pickers |
| `/admin/settings/rules` | `RulesPage.tsx` | **Combined versioned-policy manager** — escrow / settlement / contract / commission rules in one tabbed UI, backed by `RuleForms.tsx` |
| `/admin/settings/escrow-policies` | `EscrowPoliciesPage.tsx` | Dedicated escrow policy version list (also reachable via Rules) |
| `/admin/settings/settlement-policies` | `SettlementPoliciesPage.tsx` | Dedicated settlement policy version list |
| `/admin/settings/contract-policies` | `ContractPoliciesPage.tsx` | Dedicated contract policy version list |
| `/admin/settings/contract-terms` | `ContractTermsPage.tsx` (+ `ContractTermsFormPage.tsx` new/edit, `ContractTermsPreviewPage.tsx`) | Contract terms & conditions templates shown to both parties before e-signature |
| `/admin/settings/commission-strategies` | `CommissionStrategiesPage.tsx` | Commission strategy versions per provider tier |
| `/admin/settings/financials` | `FinancialsPage.tsx` | Financial parameters |
| `/admin/settings/checklist-templates` | `ChecklistTemplatesPage.tsx` | Delivery/return vehicle-inspection checklist templates |

**Key correction vs. the original guide:** these are **versioned policies**, not simple CRUD rows. `RulesPage.tsx` and its per-policy siblings work against `PolicyVersion`/`*PolicyRule` types (`CommissionStrategyVersion/Rule`, `ContractPolicyVersion/Rule`, `EscrowPolicyVersion/Rule`, `SettlementPolicyVersion/Rule`) — an admin creates a new version, edits its rules, then **activates** a specific version number (`activatePolicy(versionNumber)`), rather than editing one live row in place. This versioning layer is real, backend-enforced, and completely absent from the original guide, which described flat `POST/PUT /api/document-types` style CRUD for everything.

**Known dead-code confirmed in code (not a documentation gap — an actual stub):** `TiersPage.tsx` is annotated `// @ts-nocheck - TODO: Fix type issues`, and its edit-tier mutation is a no-op that only calls `toast.info('Update functionality coming soon')` before resolving — **admins cannot actually edit tier thresholds or commission rates through this UI today**, only view the seeded list. Any workflow description that assumes tier editing works end-to-end is aspirational, not real.

Both `settings/rules` (combined) and the dedicated per-policy pages (`escrow-policies`, `settlement-policies`, `contract-policies`) exist and route independently — they are not duplicates by accident, they're two different entry points into the same versioned-policy data.

---

## 5. Users

| Route | Component |
|---|---|
| `/admin/users` → `/admin/users/businesses` | redirect |
| `/admin/users/businesses` | `BusinessUsersPage.tsx` |
| `/admin/users/businesses/:id` | `UserDetailPage.tsx` (`userType="business"`) |
| `/admin/users/providers` | `ProviderUsersPage.tsx` |
| `/admin/users/providers/:id` | `UserDetailPage.tsx` (`userType="provider"`) |

`UserDetailPage.tsx` is a single shared component parameterized by `userType`, not two separate detail pages. Suspend/reactivate actions live here. This is distinct from the Verifications list pages (§2) — Users is the account-management view (status, suspension, activity), Verifications is the KYC/KYB approval workflow view. They both exist and are not the same screen, contrary to the original guide's single "User Management" section.

---

## 6. Operations — RFQ, Bids, Contracts

`OperationsPage.tsx` (`/admin/operations`) is a **launcher/search hub**, not a data table. It lets an admin search a verified business (to create an RFQ on their behalf) or a verified provider + RFQ (to submit a bid on their behalf), then navigates into the dedicated pages below. This matches the original guide's intent ("RFQ/Bid on behalf of") but the actual entry point is this hub page plus a duplicate, flatter set of routes without the `/operations` prefix (both work; `/admin/rfqs`, `/admin/bids`, `/admin/contracts` are aliases that resolve to the same components as their `/admin/operations/...` counterparts).

**RFQ management:**

| Route | Component |
|---|---|
| `/admin/marketplace` (or `/operations/marketplace`) | `AdminMarketplacePage.tsx` — browse open RFQs across all businesses; `AdminBidModal.tsx` for quick bid actions |
| `/admin/rfqs/manage` (or `/operations/rfqs/manage`) | `AdminRFQManagementPage.tsx` |
| `/admin/rfqs/create` (or `/operations/rfqs/create`) | `AdminCreateRFQPage.tsx` — reuses the same `RFQCreateWizard` the business portal uses, with a `businessId` prop so the RFQ is attributed to the selected business (see BUSINESS_PORTAL_GUIDE.md for the wizard's real 3-step / line-item shape — **not** a single vehicle-type/date-range form) |
| `/admin/rfqs/:rfqId/edit` | `AdminRFQEditPage.tsx` |
| `/admin/rfqs/business/:businessId` | `AdminRFQManagementPage.tsx` filtered to one business |

**Bid management:**

| Route | Component |
|---|---|
| `/admin/bids/provider` (or `/operations/bids/provider`) | `AdminProviderBidsPage.tsx` |
| `/admin/bids/provider/:providerId` | same, filtered |
| `/admin/bids/provider/:providerId/rfq/:rfqId` | `ProviderBidLineItemsPage.tsx` — per-line-item bid detail |
| `/admin/bids/submit` (or `/operations/bids/submit`) | `AdminSubmitBidPage.tsx` — submit a bid on a provider's behalf |
| `/admin/bids/award` (or `/operations/bids/award`) | `AdminAwardBidsPage.tsx` — award bids on a business's behalf; supporting dialogs `AssignVehicleDialog.tsx`, `EditBidDialog.tsx` |

Bidding here follows the same **per-line-item, split-award-capable** model as the business portal (`BidReviewPage`/`SplitAwardDialog`) — awarding is scoped to a single RFQ line item at a time, and multiple providers can each be awarded a partial quantity of the same line item.

**Contract management:**

| Route | Component |
|---|---|
| `/admin/contracts/business` (or `/operations/contracts/business`) | `AdminBusinessContractsPage.tsx` |
| `/admin/contracts/provider` (or `/operations/contracts/provider`) | `AdminProviderContractsPage.tsx` |
| `/admin/contracts/business/:businessId/contract/:contractId` | shared `ContractDetailPage.tsx` (same component as the business/provider portals, admin-aware via `location.pathname` checks) |
| `.../contract/:contractId/delivery` | `AdminDeliveryPage.tsx` |
| `/admin/operations/contracts/assign-vehicle[/:contractId]` | `AdminAssignVehiclePage.tsx` — admin can assign vehicles to a contract on a provider's behalf |
| `/admin/operations/contracts/terminate` | `AdminContractTerminationPage.tsx` |

**What the admin can do on the shared `ContractDetailPage` that business/provider users cannot** (verified in code, `isAdmin` branches):
- **Abort Before Signing** — available only while status is `PENDING_VEHICLE_ASSIGNMENT`, `PENDING_ESCROW`, or `PENDING_SIGNING`; requires a reason; calls `contractService.abortContractBeforeSigning`.
- **Settle Current Cycle** — triggers `financeService.generateCurrentCycleSettlement` for whatever settlement cycle is currently due, independent of the automated schedule.
- **Admin Override: Complete** — force-completes a contract that's in a completion-request standoff, bypassing the normal request/approve/reject cycle between business and provider.

**Real contract lifecycle, corrected vs. the original guide:** the original guide assumed `pending → active → suspended → completed` with manual "renewal" creating a brand-new contract. The real system has no `SUSPENDED` state at all. Instead: `Contract.Status` is a plain string (not an enforced backend enum — the nominal `ContractStatus` C# enum exists but has zero references outside its own file), producing states including `PENDING_VEHICLE_ASSIGNMENT`, `PENDING_SIGNING` (a dual-party OTP e-signature step, separate from delivery OTP — both business and provider must OTP-sign contract terms), `PENDING_DELIVERY`, `PARTIALLY_DELIVERED`, `ACTIVE`, `TERMINATION_REQUESTED`, `PARTIALLY_RETURNED`, `COMPLETED`, `CANCELLED`, and others. "Renewal" does not exist as a concept anywhere — what the web app calls **extension** (`ExtendContractDialog.tsx`, business portal only) lengthens the *same* contract's end date by 1–12 months (rounded to end-of-month) and is **only available for long-term contracts**; there is no provider accept/reject step and no new contract entity created. See `BUSINESS_PORTAL_GUIDE.md` §Contracts for the full state detail and `project-docs/18_Implementation_Coverage_Audit.md` §3 and §10.1 for the full forensic history of this divergence.

Contract completion is a **request/approve/reject/cancel** negotiation between business and provider (visible on the shared detail page as color-coded banners), gated on all vehicles being returned and all settlement cycles for the contract being settled — not a simple end-date auto-completion.

---

## 7. Operations — Settlements, Wallet Accounts, Monitoring

| Route | Component |
|---|---|
| `/admin/operations/settlements` | `AdminSettlementManagementPage.tsx` |
| `/admin/operations/settlements/:payoutId` | `AdminSettlementDetailPage.tsx` |
| `/admin/operations/wallet-accounts` | `AdminWalletAccountsPage.tsx` |
| `/admin/operations/monitoring/vehicles` | `VehicleLifecycleMonitoringPage.tsx` |

`VehicleLifecycleMonitoringPage.tsx` is entirely undocumented in the original guide and in the epic backlog — it's a platform-wide view of vehicle status transitions (the real lifecycle is richer than "Active/Assigned/Maintenance": vehicles also move through `DELIVERED`, `RETURNED`, `REPLACED`, `MAINTENANCE`, driven by the delivery/return-OTP and vehicle-replace/return flows described in the provider guide).

---

## 8. Direct Rental Oversight

**Entirely absent from the original guide.** Direct Rental is a fixed-price, non-bidding vehicle booking channel parallel to RFQ bidding (browse catalog → cart → per-provider request → accept/reject at vehicle granularity → auto-created contract). Full product detail lives in `backlog/post-mvp/epic-21-direct-rental.md` and `project-docs/17_Direct_Rental_Product_Design_Brief.md`; the admin surface is:

| Route | Component |
|---|---|
| `/admin/operations/direct-rental` → `/browse` | redirect |
| `/admin/operations/direct-rental/browse` | `AdminDirectRentalBrowsePage.tsx` — full catalog, not scoped to one business |
| `/admin/operations/direct-rental/vehicles/:id` | `AdminDirectRentalVehicleDetailPage.tsx` |
| `/admin/operations/direct-rental/cart` | `AdminDirectRentalCartPage.tsx` — manage a cart **on behalf of a business** (add/update/remove items, submit-preview, submit) |
| `/admin/operations/direct-rental/requests` | `AdminDirectRentalRequestsPage.tsx` — all requests platform-wide, filterable by business/provider/status/date |
| `/admin/operations/direct-rental/requests/:id` | `AdminDirectRentalRequestManagePage.tsx` — includes the ability to **respond to a request on a provider's behalf** |

All admin Direct Rental actions are tagged `ADMIN` in the request's status-history timeline along with the acting admin's identity, so on-behalf-of actions remain auditable.

---

## 9. Wallets

Distinct from Direct Rental "cart" wallets and from Finance (§10) — this section is the platform's own ledger/account view.

| Route | Component |
|---|---|
| `/admin/wallets` → `/platform` | redirect |
| `/admin/wallets/platform` | `PlatformWalletDashboard.tsx` |
| `/admin/wallets/platform-account` | `PlatformAccountManagementPage.tsx` |
| `/admin/wallets/escrow-transactions` | `EscrowTransactionsPage.tsx` |
| `/admin/wallets/all` | `AllWalletsPage.tsx` — every business/provider wallet, one table |
| `/admin/wallets/escrow` | `EscrowWalletManagementPage.tsx` |
| `/admin/wallets/business-escrow` | `AdminBusinessEscrowWalletsPage.tsx` |
| `/admin/wallets/tax-report` | `WithholdingTaxPage.tsx` |
| `/admin/wallets/:walletId` | `AdminWalletDetailPage.tsx` |

There is no single "Transaction Monitoring" page as the original guide assumed — transaction/ledger visibility is spread across these wallet-specific pages, plus the escrow-transactions page specifically for escrow-lock/release events, plus the withholding-tax report.

---

## 10. Finance — Settlement/Withdrawal/Deposit/Invoice Queues

A separate route group from both Operations-Settlements (§7) and Wallets (§9) — this is the **approval-queue** layer for money movement that requires a human check.

| Route | Component |
|---|---|
| `/admin/finance/settlements` | `SettlementPayoutsPage.tsx` — settlement payout approval queue |
| `/admin/finance/withdrawals` | `WithdrawalRequestsPage.tsx` |
| `/admin/finance/withdrawals/:id` | `WithdrawalRequestDetailPage.tsx` |
| `/admin/finance/deposits` | `DepositRequestsPage.tsx` |
| `/admin/finance/deposits/:id` | `DepositRequestDetailPage.tsx` |
| `/admin/finance/invoices` | `AdminProviderInvoicesPage.tsx` |
| `/admin/finance/invoices/:id` | `AdminProviderInvoiceDetailPage.tsx` |

**Note on invoices:** the invoice flow is **provider-submitted**, reviewed/approved by admin here — this inverts the assumption in the MVP daily-ledger epic that the system auto-generates invoices for admin to just view. Deposit/withdrawal requests here are the manual bank-transfer path (parallel to the automated Chapa/Telebirr/CBEBirr webhook path that posts directly without an approval queue).

---

## 11. Notifications — Templates & Providers

Not mentioned at all in the original guide. Notifications is one of the areas that most exceeds its epic doc (see coverage audit §6) — this is the admin configuration surface for a full multi-channel (email/SMS/push) notification system with per-category × per-channel toggles, template management, and live provider credential configuration.

**Templates** (three channels, each with list + form pages):

| Route | Component |
|---|---|
| `/admin/notifications/templates/in-app[/new\|/:id/edit]` | `InAppTemplatesPage.tsx` / `InAppTemplateFormPage.tsx` |
| `/admin/notifications/templates/email[/new\|/:id/edit]` | `EmailTemplatesPage.tsx` / `EmailTemplateFormPage.tsx` |
| `/admin/notifications/templates/sms[/new\|/:id/edit]` | `SmsTemplatesPage.tsx` / `SmsTemplateFormPage.tsx` |

**Providers** (channel credential/config management):

| Route | Component |
|---|---|
| `/admin/notifications/providers/email` | `EmailProvidersPage.tsx` (SMTP config) |
| `/admin/notifications/providers/sms` | `SmsProvidersPage.tsx` (Afromessage-style SMS gateway config) |
| `/admin/notifications/providers/fcm` | `FcmProvidersPage.tsx` (Firebase Cloud Messaging push config) |
| `/admin/notifications/providers/fcm/token` | `FcmTokenHelperPage.tsx` — a utility page for generating/testing FCM tokens |

This whole area backs a real-time SignalR notification hub and admin-configurable per-category × per-channel toggle system on the backend (`NotificationAdminController`, 40+ endpoints) — treat any notification-related admin flow described elsewhere as "send an email on event X" as a drastic understatement of what's actually configurable here.

---

## 12. Cross-Cutting Notes & Divergences

- **No unified "Verification Queue with tabs."** Business, provider, and vehicle verification are three independent list+detail page pairs (§2), not one queue.
- **Tier editing is a UI stub.** `TiersPage.tsx`'s edit dialog does not persist anything (§4) — don't build workflows assuming it works.
- **Policies are versioned, not flat rows.** Every "Rules"/"Policy" page in Master Data works in terms of create-version → edit-rules → activate-version, not in-place edit (§4).
- **Contract state has no `SUSPENDED`, no `renew` endpoint.** "Renewal" in the UI is "extension," business-initiated, long-term-only, same contract (§6).
- **RFQ/bidding is line-item + split-award**, not single-vehicle-type/date-range with one award per RFQ, on both the business-facing and admin-on-behalf-of surfaces (§6).
- **Direct Rental is a whole parallel acquisition channel** with full admin oversight (browse/cart/requests/vehicle-detail, act-on-behalf-of) and no epic number of its own until `backlog/post-mvp/epic-21-direct-rental.md` was added — see §8.
- **Admin-initiated onboarding is a real, distinct feature** (§3), not just "the admin can view businesses/providers."
- **Notifications admin config is a first-class, large area** (§11), not a footnote under System Settings.
- Routes are frequently duplicated under both `/admin/...` and `/admin/operations/...` for the same underlying pages (RFQ, bids, contracts) — both resolve, don't assume one is stale.

For the epic-by-epic status of every area in this document (what's done, partial, or diverges from its backlog doc), see `project-docs/18_Implementation_Coverage_Audit.md`, especially §2 (coverage matrix) and §7 (undocumented features inventory).
