# User Stories Reference
## Anqelba Car Rental Frontend - React Implementation

**Version:** 2.0
**Last verified against code: 2026-07-23**
**Source of truth:** [`backlog/README.md`](../../../backlog/README.md) + `backlog/mvp/*.md` + `backlog/post-mvp/*.md` (21 epics, 129 stories, all cross-checked against running code as of 2026-07-23)
**Reconciliation layer:** [`project-docs/18_Implementation_Coverage_Audit.md`](../../../project-docs/18_Implementation_Coverage_Audit.md) — read this before treating any single epic doc as a literal, unqualified spec

---

## This File No Longer Duplicates the Backlog

The v1.0 version of this file was a **second, independent copy** of the product backlog — its own epic list (11 epics, not the real platform's 21), its own numbering scheme (`MOV-101`, `MOV-201`, ...), its own story-point totals (100 stories / 645 points), and its own acceptance criteria, none of which trace back to `backlog/mvp/*.md` or `backlog/post-mvp/*.md`. It had drifted so far from the real backlog that it amounted to a parallel, fictional product plan rather than a frontend-implementation view of the real one.

That approach doesn't survive contact with a 21-epic, actively-audited backlog: maintaining two divergent lists of "the user stories" guarantees they disagree, and whichever one a reader picks first will mislead them about scope. **This file now points to the real backlog instead of re-describing it**, and limits itself to what's actually useful for frontend work that a plain epic list doesn't give you: which epics exist, how they map to the web app's actual page tree, and which specific claims in those epic docs you should double-check against code before building against them.

If you need acceptance criteria or Definition-of-Done checklists for a story, **go to the epic file in `backlog/`** — do not recreate them here.

---

## Table of Contents

1. [What's Actually Real vs. What v1.0 Invented](#whats-actually-real-vs-what-v10-invented)
2. [The Real 21-Epic Structure](#the-real-21-epic-structure)
3. [Epic → Web App Page Tree (Quick Orientation)](#epic--web-app-page-tree-quick-orientation)
4. [Before You Build Against Any Epic Doc: Known Divergences](#before-you-build-against-any-epic-doc-known-divergences)
5. [Confirmed Not Built (Don't Design Around These Yet)](#confirmed-not-built-dont-design-around-these-yet)

---

## What's Actually Real vs. What v1.0 Invented

| v1.0 claimed | Reality |
|---|---|
| 11 epics, ~100 stories, 645 story points, `MOV-XXX` IDs | 21 epics (12 MVP + 9 post-MVP), 129 stories, `Story X.Y` IDs — see `backlog/README.md`. There is no `MOV-` prefix anywhere in the real backlog |
| Epics grouped by role × feature (e.g. "E04: Business - Wallet Management", "E09: Provider - Wallet & Settlements" as two separate epics) | Real backlog groups by **feature area across both roles** (e.g. one `epic-08-wallet-escrow.md` covers business and provider wallet together) — the v1.0 per-role split doesn't match how the actual epics, or the actual codebase's module boundaries, are organized |
| "Direct Rental" not mentioned anywhere | Direct Rental is a full 10-story epic (`epic-21-direct-rental.md`) spanning backend, web, and both mobile apps — it shipped before it had an epic number and was invisible from every index until the 2026-07-23 audit found it; it's now formally epic 21 |
| Bidding epic DoD implies a working price/trust/condition/response-time ranking algorithm and anti-collusion detection (`MOV-707: Bid Analytics`, etc., presented as buildable/built) | Confirmed **zero code** implementing either the weighted ranking formula or anti-collusion detection, on any surface — see epic-05's own rewritten text and the audit §4 |
| Contract epic assumes `pending → active → suspended → completed`, manual renewal creates a new contract | Real lifecycle has 17–18 states, no "Suspended" state at all, and "renewal" is contract **extension** of the same contract, not a new one — see epic-06 |
| Trust score epic (`MOV-903`) frames it as something a provider doesn't see about themselves | Provider mobile app dashboard shows the provider their own live trust score and tier directly — see epic-12 |

---

## The Real 21-Epic Structure

**MVP (12 epics, 79 stories)** — `backlog/mvp/`:

| # | Epic | Stories | Web Coverage (per 2026-07-23 audit) |
|---|------|:---:|---|
| 01 | Business Onboarding & KYB | 5 | ✅ |
| 02 | Provider Onboarding & KYC | 6 | ✅ |
| 03 | Vehicle & Insurance Management | 6 | ✅ (diverges — Direct Rental fields, expanded vehicle status lifecycle undocumented in epic text) |
| 04 | RFQ Management | 7 | ✅ (diverges — line-item model, not single-vehicle-type/date-range) |
| 05 | Bidding Engine | 7 | ✅ (diverges — split awards; ranking algorithm & anti-collusion unbuilt) |
| 06 | Contract Management | 7 | ✅ (diverges — 17–18 state lifecycle, dual-OTP signing, extension not renewal; most-diverged epic on every surface) |
| 07 | OTP Delivery Verification | 7 | ✅ (diverges — return-trip OTP + inspection checklist not in original scope) |
| 08 | Wallet & Escrow | 7 | ✅ (diverges — live payment-gateway webhooks, not "future") |
| 09 | Daily Ledger & Billing | 7 | 🟡 (diverges — provider-submitted invoice-approval inverts the epic's assumption) |
| 10 | Monthly Renewal & Settlement | 7 | ✅ (dispute flow story 10.7 unbuilt) |
| 11 | Notification System | 7 | ✅ (diverges — epic undersells scope by a wide margin, see `REALTIME_FEATURES.md`) |
| 12 | Risk & Trust Scoring | 7 | 🟡 (diverges — provider-only, visible to provider self, no business risk score, no fraud engine) |

**Post-MVP (9 epics, 50 stories)** — `backlog/post-mvp/`:

| # | Epic | Stories | Status |
|---|------|:---:|---|
| 13 | Group Bidding | 5 | ⚪ Not started |
| 14 | Analytics Dashboard | 5 | 🟡 Partial (dashboard-embedded only) |
| 15 | Geofence/GPS Integration | 5 | ⚪ Not started |
| 16 | Mobile Applications | 5 | 🟡 Both apps exist, some DoD items missing (biometric auth, true offline sync, RFQ templates) |
| 17 | Instant Payouts | 5 | ⚪ Not started |
| 18 | Provider Loan Facilities | 5 | ⚪ Not started |
| 19 | Insurance Marketplace | 5 | ⚪ Not started (existing insurance UI is epic-03 document verification, not a marketplace) |
| 20 | API Integrations & Enterprise | 5 | ⚪ Not started |
| 21 | Direct Rental | 10 | ✅ Fully shipped, cross-surface — documented retroactively |

**Total: 129 stories.** For the full acceptance criteria and Definition-of-Done checklist per story, open the epic file directly.

---

## Epic → Web App Page Tree (Quick Orientation)

A frontend-focused index the real backlog doesn't provide directly — where in `src/features/` each epic's web surface actually lives, useful when picking up a story cold:

| Epic | Web feature folder(s) |
|---|---|
| 01/02 Onboarding | `src/features/auth/`, admin verification queues under `src/features/admin/pages/verifications/` |
| 03 Vehicle & Insurance | `src/features/provider/pages/fleet/`, `src/features/admin/pages/verifications/VehicleVerificationListPage.tsx` |
| 04/05 RFQ & Bidding | `src/features/business/pages/rfq/` (list, detail, create, bids/award), `src/features/provider/marketplace/` |
| 06 Contracts | `src/features/business/pages/contracts/`, `src/features/provider/.../contracts/`, `src/features/admin/pages/operations/contracts/` |
| 07 OTP/Delivery | Delivery session screens under provider/business contract detail flows; `src/core/services/delivery-service.ts` |
| 08 Wallet & Escrow | `src/features/business/pages/wallet/`, `src/features/provider/pages/wallet/` |
| 09/10 Ledger & Settlement | Billing/settlement tabs within contract and wallet feature areas |
| 11 Notifications | `src/stores/notification-store.ts`, `src/core/services/notification-hub.ts`, `NotificationDropdown.tsx`, admin `src/features/admin/pages/notifications/` |
| 12 Trust/Risk | `TrustScoreDisplay.tsx`, `src/features/admin/pages/master-data/TiersPage.tsx` |
| 14 Analytics | Dashboard-embedded charts on business/provider/admin dashboards (no standalone analytics feature folder) |
| 21 Direct Rental | `src/features/business/pages/direct-rental/`, `src/features/provider/pages/direct-rental/`, `src/features/admin/pages/direct-rental/`, backed by `direct-rental-service.ts` |

---

## Before You Build Against Any Epic Doc: Known Divergences

All 12 MVP epics and `epic-16`/`epic-21` were fully rewritten against running code on 2026-07-23 and each carries its own "Last verified against code" line — trust those over anything older. The handful of divergences most likely to bite a frontend task:

- **RFQ/Bid data model is header + `RFQLineItem[]`**, not one vehicle-type/quantity/date-range per RFQ. Every award is per-line-item, and can be **split across multiple providers** (`SplitAwardDialog.tsx`).
- **Contract status is a plain string, not an enforced enum** in practice — the C# `ContractStatus` enum has zero references outside its own file; real statuses are produced ad hoc across the codebase (18 distinct values seen in practice, including a `CANCELLED` the enum doesn't even define). See `MVP_CONTRACT_STATE_MACHINE.md`.
- **Blind bidding is UI-only.** The bid-list API returns `ProviderName` unconditionally regardless of award status; only the web client's choice not to render it keeps bids blind. See `BUSINESS_LOGIC_IMPLEMENTATION.md`.
- **Post-award vehicle assignment is a shared three-phase pattern across all four surfaces** (bid at quantity level → award, possibly split → assign specific vehicles) — it's not mobile-only, web hits the identical `GET /rfq/awards/{awardId}/eligible-vehicles` / `POST`/`DELETE /rfq/awards/{awardId}/vehicles` endpoints via `AwardAssignPage.tsx`.
- **Trust score is real but inert in production** — the formula exists, is unit-tested, and is DI-registered, but nothing calls it; every provider is frozen at its default (50 if verified, 0 if not) until an admin manually assigns a tier.
- **Settlement cadence is an unresolved internal contradiction** between the wallet epic (tier-based cadence: Bronze/Silver monthly, Gold bi-weekly, Platinum weekly) and the settlement epic (flat rolling 30-day cycle regardless of tier) — don't cite either as settled fact without checking `GenerateSettlementCommand*.cs` first.

---

## Confirmed Not Built (Don't Design Around These Yet)

Zero code hits across every surface as of 2026-07-23 — if a task references any of these as if they exist, flag it before proceeding:

- Weighted bid-ranking algorithm (price/trust/condition/response-time) and anti-collusion/bid-collusion detection (epic-05)
- Business-side risk/fraud scoring, a unified dispute-resolution workflow or dispute entity of any kind (epic-12; `Disputed`/`OnHold` exist only as unused contract status values)
- Group Bidding, Geofence/GPS Integration, Instant Payouts, Provider Loan Facilities, Insurance Marketplace, API Integrations & Enterprise (epics 13, 15, 17, 18, 19, 20)
- A `renew` endpoint or "new contract from an old one" flow of any kind (contract "renewal" is extension of the same contract — see `BUSINESS_LOGIC_IMPLEMENTATION.md`)
- Any client-side early-return penalty/refund preview calculator on web (the real UI submits a reason and lets the backend compute everything, with no preview shown)
