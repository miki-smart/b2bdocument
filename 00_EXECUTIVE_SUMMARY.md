# Anqelba Car Rental B2B Mobility Marketplace — Executive Summary

**Version:** 2.0 (rewritten against running code)
**Last verified against code:** 2026-07-23
**Original version:** 1.0, November 26, 2025 — written **before** implementation began, as a forward-looking specification. Several of its core claims (Angular frontend, a separate YARP BFF/API-gateway service, 5 modules, a week-by-week build timeline) describe a plan that was superseded during actual development and never matched what was built. This revision replaces those claims with what is verified in code today.
**Status:** Mature MVP — substantially built and in active use, with partial post-MVP work underway. This is **not** a from-scratch plan; treat this document as a description of an existing system.
**Ground truth:** `project-docs/18_Implementation_Coverage_Audit.md` (2026-07-23) — the code-grounded audit this rewrite is based on. Where this summary and that audit ever disagree, trust the audit and re-verify against code.

---

## Executive Overview

Anqelba Car Rental (Anqelba Car Rental) is a B2B mobility marketplace connecting **Business Clients** with **Vehicle Providers** through a blind-bidding RFQ system, plus a separate fixed-price **Direct Rental** booking surface. The platform spans four buildable surfaces: a single .NET backend, a React web app, and two Flutter mobile apps (business and provider).

### Vision Statement

To make B2B vehicle rental in Ethiopia transparent, trustworthy, and largely automated — competitive blind bidding instead of opaque quotes, escrow-backed contracts instead of manual invoicing, and OTP-verified handover instead of paper trails.

---

## Market Opportunity

### Target Market
- **Primary:** Ethiopian businesses requiring fleet rentals (1–365 days)
- **Secondary:** Vehicle providers (individuals, agents, rental companies)
- **Market Size:** $50M+ annual B2B vehicle rental market in Addis Ababa alone (business estimate, not a code fact)

### Problem Statement
1. **Opacity:** No transparent pricing, businesses overpay
2. **Trust Deficit:** Fraud risk, vehicle quality issues
3. **Manual Processes:** Paper-based contracts, cash payments
4. **Compliance Gaps:** Insurance lapses, unlicensed operators

### Anqelba Car Rental Solution (as actually implemented)
- **Blind Bidding:** Line-item RFQs with per-item, multi-provider split awards; provider identity is withheld by the web UI until award (the API itself does not withhold the field server-side — see the known gap noted in `backlog/mvp/epic-05-bidding-engine.md`).
- **Trust Scoring:** A real, formula-based provider trust score (0–100) and tier system (Bronze/Silver/Gold/Platinum) exists and is DI-registered — but per the audit, it currently has **zero production call sites** and every provider's score is effectively frozen at its default. There is **no** business-side risk score.
- **Escrow System:** Automated escrow lock on contract creation, with retry/backoff and a timeout-driven auto-cancel job.
- **Digital Verification:** OTP-based vehicle handover (delivery) plus a separate return-trip OTP and inspection checklist. GPS/geofence tracking does **not** exist in code (post-MVP, not started).
- **Compliance Enforcement:** Mandatory insurance and KYC/KYB verification before platform access.

---

## Architecture Overview

### Pattern: Single .NET 9 Modular Monolith — no separate BFF/gateway service

```
┌───────────────────────────────────────────────────────────────────┐
│                      CLIENT SURFACES                               │
│  React 18.3 + Vite 6 web app       Flutter mobile apps              │
│  (business/provider/admin portals   business_app · provider_app     │
│   in one SPA, role-based routing)   (flutter_riverpod, go_router)   │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ HTTPS (direct — no gateway hop)
┌───────────────────────────▼─────────────────────────────────────────┐
│                   Marketplace.API (.NET 9)                          │
│           Single deployable — one Program.cs, one csproj            │
├───────────────────────────────────────────────────────────────────┤
│  Modules/  Auth · Identity · Marketplace · Contracts ·               │
│            Finance · Delivery · MasterData · Notifications          │
│  (8 modules — see 01_ARCHITECTURE_OVERVIEW.md §1.3)                  │
├───────────────────────────────────────────────────────────────────┤
│  MediatR (in-process events, dominant) · SignalR (NotificationHub)   │
│  BffTokenRefreshMiddleware (in-process cookie↔bearer translation,    │
│  not a separate BFF service)                                        │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┬───────────────┐
        ▼                   ▼                   ▼               ▼
   PostgreSQL 16        Keycloak            Redis           MinIO
  (EF Core 9 + Npgsql) (direct-grant auth) (cache)      (S3-compatible)
                            │
                       RabbitMQ (provisioned — package + docker
                       service exist; per the coverage audit,
                       barely used in production code today)
```

This diagram, and every claim in this document, should be read together with:
- `architecture/modular-monolith-architecture.md` — authoritative module-boundary and extraction methodology
- `architecture/module-layout-convention.md` — authoritative per-module folder shape
- `01_ARCHITECTURE_OVERVIEW.md` (this suite) — the detailed version of the diagram above

### Key Architectural Decisions (as built, not as originally planned)

| Decision | Actual choice | Notes |
|----------|--------------|-------|
| **Pattern** | Single .NET 9 modular monolith (`Marketplace.API`) | One `.csproj` in `backend/src` besides the test project; one deployable container |
| **Backend** | .NET 9, EF Core 9 + Npgsql/PostgreSQL | Confirmed via `Marketplace.API.csproj` |
| **Web frontend** | React 18.3 + Vite 6 + TanStack Query + Zustand + shadcn/ui | **Not Angular.** Confirmed via `anqelbacarrental-marketplace-core/package.json`. A single Vite SPA with role-based routing, not 3 separate portal apps. |
| **Mobile** | Flutter only — `business_app`, `provider_app` (`flutter_riverpod`, `go_router`) | Flutter-only since inception; older mobile-spec docs' "React Native or Flutter" hedge is stale, not an open decision. |
| **Auth** | Keycloak, called **directly, in-process** by `Modules/Auth` (`KeycloakAuthService`) via Resource Owner Password Credentials grant | No separate Auth microservice, no separate BFF/gateway service. A real `BffTokenRefreshMiddleware` exists, but as in-process middleware inside the same monolith — see `architecture/auth-service-microservice-spec.md` §1. |
| **Events** | MediatR (in-process) is the dominant, actively-used mechanism | `RabbitMQ.Client` is a real package dependency and a real docker-compose service, but the coverage audit found minimal active production usage today — provisioned, not primary. |
| **Cache** | Redis | Session/cache data |
| **Storage** | MinIO | S3-compatible object storage for documents/photos |
| **Payments** | Chapa.NET SDK — Chapa/Telebirr/CBEBirr webhook processing **is live today**, not a future item | Confirmed via `Chapa.NET` package and `PaymentController.cs` |
| **Push/Notifications** | FirebaseAdmin (FCM), SMTP email, SMS (Afromessage), SignalR (`NotificationHub`) for real-time in-app | Admin-configurable multi-channel system with credential rotation — far beyond a simple "send email/SMS" MVP scope |
| **Logging** | Serilog (structured, file + console + Seq sinks) | |

---

## Product Scope: 21 Epics, 129 Stories

The product backlog (`backlog/README.md`) organizes scope as **21 epics — 12 MVP + 9 post-MVP — totaling 129 user stories.** This supersedes any earlier "20 epics" framing: **Direct Rental**, a fully-shipped fixed-price (non-bidding) vehicle-booking feature that existed in code across all four surfaces without an epic number, was formalized as **epic-21** on 2026-07-23.

### Current implementation status (condensed from the coverage audit's epic × surface matrix — see that document for the full table)

**MVP epics (01–12) — all implemented, several materially diverged from their epic docs:**
- Epics 01–03 (onboarding, vehicle/insurance): implemented across backend/web, largely as documented with some undocumented admin/lifecycle additions.
- Epics 04–05 (RFQ/Bidding): implemented, but as a **header + line-item + multi-provider split-award model** on backend/web, and a **fleet-bid-then-assign-vehicles** pattern on mobile — neither shape matches the epic text. The weighted bid-ranking formula and anti-collusion detection specified as Definition-of-Done in epic-05 **do not exist in any surface**.
- Epic 06 (Contracts): implemented, but with an **18-state string-based lifecycle** (not the enum-driven, 4-state `pending/active/suspended/completed` model the epic describes), a dual-party OTP signing step, and no "renew" concept (contract **extension** instead) — the single most-diverged epic in the backlog. See `MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md` for the authoritative state model.
- Epic 07 (OTP delivery): implemented, plus an undocumented return-trip OTP + inspection checklist system.
- Epic 08 (Wallet/Escrow) and Epic 11 (Notifications): both **dramatically exceed** their epic docs — live payment-gateway webhooks, admin-configurable multi-channel notifications, SignalR real-time hub.
- Epic 09–10 (Ledger/Settlement): implemented; provider-submitted invoice-approval flow inverts epic-09's assumption.
- Epic 12 (Trust/Risk): provider trust-score formula exists but is **not wired into production** (frozen at default); no business risk score, no fraud engine, no dispute-engine entities exist anywhere.

**Post-MVP epics (13–21):**
- Epics 13, 15, 17, 18, 19, 20 (Group Bidding, Geofence/GPS, Instant Payouts, Loans, Insurance Marketplace, API/Enterprise): **confirmed not started** — zero code on any surface.
- Epic 14 (Analytics Dashboard): **partially started** — dashboard-embedded charts on web/backend, basic stat cards on mobile; nowhere near full scope.
- Epic 16 (Mobile Applications): **the most-built post-MVP epic** — both Flutter apps exist, plus a 19-controller/100+-endpoint Mobile API surface — but still missing pieces against its own Definition of Done (biometric auth, true offline sync, RFQ templates).
- Epic 21 (Direct Rental): **fully shipped** across backend, web, and both mobile apps — cart → request → provider accept/reject, its own admin surface, its own background expiry job. Was undocumented as an epic until this pass.

---

## Module Breakdown (8 real backend modules)

Confirmed via `backend/src/Marketplace.API/Modules/` — this is the real module list; do not use any older doc's 5-module or 7-module framing.

### 1. Auth Module
Keycloak integration — direct-grant login/refresh/logout, admin-API session listing, role sync. No local session/MFA tables; MFA is explicitly unimplemented (`VerifyMfaAsync` throws `NotSupportedException`). See `architecture/auth-service-microservice-spec.md` §1 for full detail — not duplicated here.

### 2. Identity Module
Business/Provider/Vehicle registration, KYC/KYB document verification, trust-score calculation service (built, not wired to events), tier assignment, insurance tracking, security/risk events (`RiskEvent`/`AccountFlag` — generic security events, not a scored risk model).

### 3. Marketplace Module
RFQ (header + line items), blind bidding, per-line-item bids with full audit trail (`RFQBidSnapshot`/`RFQBidHistory`), multi-provider split awards, post-award vehicle-assignment endpoints shared by web and both mobile apps, Direct Rental cart/request/vehicle entities and controllers.

### 4. Contracts Module
Contract lifecycle (18 real status strings, not the 4-state model in older docs), vehicle-assignment sub-lifecycle, dual-party OTP e-signature, two-party completion flow, termination request/approve, contract extension (UI built, backend endpoint currently missing — see epic-06 §6.11). See `MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md` for the full authoritative model.

### 5. Finance Module
Digital wallets (business & provider), double-entry ledger, automated escrow lock/release with retry, monthly settlement cycles, tier-based commission, live Chapa/Telebirr/CBEBirr payment-gateway webhook processing, refunds. Two competing escrow-computation code paths and two disagreeing tier-threshold schemes coexist in code today (documented in `backlog/mvp/epic-08-wallet-escrow.md`) — a real inconsistency, not a documentation error.

### 6. Delivery Module
OTP-based vehicle handover (6-digit, SHA-256 hashed, 5-minute expiry), photo evidence capture, odometer/fuel recording, a separate return-trip OTP + vehicle inspection checklist system. `DeliveryVehicleHandover`, `DeliverySLAViolation`, `DeliveryFailureReason`, `DeliveryEventLog` entities exist in the domain/DB but nothing currently writes to them.

### 7. MasterData Module
Versioned policy/rules engine — `CommissionStrategyVersion/Rule`, `ContractPolicyVersion/Rule`, `EscrowPolicyVersion/Rule`, `SettlementPolicyVersion/Rule`, business/provider tiers, document types, geography, banks, lookups. See `markdown-documentations/Master_Data_Specification.md`.

### 8. Notifications Module
Admin-configurable multi-channel system — email (SMTP), SMS (Afromessage), push (Firebase/FCM), each with credential rotation and live test-send (`NotificationAdminController`, 40+ endpoints), plus a real-time SignalR `NotificationHub`. Far beyond epic-11's "email/SMS, WebSocket optional" scope.

---

## Security & Compliance

### Authentication & Authorization (as built)
- **Keycloak**, called directly and in-process by `Modules/Auth` — Resource Owner Password Credentials grant, not an OIDC browser redirect. Web stores tokens as HttpOnly cookies set directly by `AuthController`; mobile receives tokens in the JSON response body (no cookies) and stores them via secure device storage.
- **`BffTokenRefreshMiddleware`** — real, in-process middleware that silently refreshes an expiring access-token cookie before `[Authorize]` middleware runs. This is the actual (and only) "BFF" in the system — not a separate deployable. See `architecture/auth-service-microservice-spec.md` §1.5.
- **RBAC** via Keycloak realm roles (`business-admin`, `business-user`, `provider-admin`, `provider-driver`, `platform-admin`, etc.).
- **MFA is not implemented** — `KeycloakAuthService.VerifyMfaAsync` explicitly throws `NotSupportedException`.

### Data Protection & Compliance
- **PII/Blind bidding:** provider identity is withheld by the web UI until award; the API itself returns `ProviderName` unconditionally regardless of award status — enforcement is UI-only today, a real gap flagged in the rewritten epic-05.
- **KYC/KYB:** mandatory verification before platform access.
- **Insurance:** zero-tolerance policy enforced at vehicle-approval time.
- **Financial:** double-entry ledger; two known inconsistent code paths for escrow computation and platform-commission wallet lookup exist today (see Finance Module above) and should be reconciled by engineering, not documentation.

---

## Non-Functional Targets (design goals — not measured production metrics)

These are design targets carried from the original MVP planning pass; they have **not** been re-verified against live production telemetry as part of this rewrite. Treat them as goals, not achieved SLAs.

- Concurrent users: 500+
- RFQs/day: 100+
- Contracts/month: 500+
- API response time: <200ms (p95, target)
- Uptime: 99.5% (target)

---

## Deployment Architecture (as configured in the repo)

Confirmed via `backend/docker-compose*.yml` (split per environment: `development`, `prod`, `infrastructure.{dev,prod}`, `keycloak`, `monitoring`).

- **`marketplace-api`** — single container, the entire .NET 9 monolith. No separate BFF/gateway container exists.
- **`postgres`** — single PostgreSQL instance.
- **`keycloak`** — identity provider, its own compose file.
- **`redis`**, **`minio`**, **`rabbitmq`** — cache, object storage, and message broker (provisioned; see Events note above on actual RabbitMQ usage level).
- **Web** (`anqelbacarrental-marketplace-core`) — a separate Vite/React build with its own `docker-compose*.yml` files, deployed independently of the backend (typically behind Nginx as static assets).
- **Mobile** — Flutter apps built and distributed natively (APK/IPA via app stores), not containerized.

`02_DATABASE_SCHEMA_DESIGN.md` and `03_API_SPECIFICATIONS.md` in this documentation suite predate the current codebase and were **not** re-verified as part of this rewrite pass — read them as historical/aspirational rather than current fact until they get their own audit pass (see `DOCUMENTATION_PROGRESS.md`).

---

## Current Priorities (from the coverage audit's open-items list)

Rather than a forward "week 1 / week 2" build plan (the MVP is already substantially built), the real near-term priorities identified by the audit are:

1. **Wire the missing `POST /contracts/{contractId}/extend` endpoint** — the web "Extend Contract" button is fully built and calls a route that doesn't exist on any controller (highest-priority gap in Epic 06).
2. **Decide whether to wire `TrustScoreCalculator`/`TierCalculationService` into production events at all** — both are fully built and unit-tested but have zero call sites; every provider's trust score is currently frozen at its default.
3. **Reconcile the two disagreeing escrow-computation and settlement-cadence code paths** in Finance (see Module Breakdown above and `project-docs/18_Implementation_Coverage_Audit.md` §10.2–§10.4).
4. **Rewrite remaining stale docs** in this tree and elsewhere — several files in `04_MODULE_SPECIFICATIONS/`, `05_BUSINESS_LOGIC_FLOWS.md` onward were written pre-implementation and have not yet had an audit-driven rewrite pass (tracked in `DOCUMENTATION_PROGRESS.md`).
5. **Product decision, not engineering:** whether to build the epic-05 bid-ranking/anti-collusion logic and the epic-12 business risk score / fraud engine / dispute workflow that are specified but do not exist in any surface.

---

## Documentation Index

This executive summary is part of the `MVP_MODULAR/` documentation suite. **Currency varies by file** — see `DOCUMENTATION_PROGRESS.md` for a file-by-file status, and `project-docs/18_Implementation_Coverage_Audit.md` for the authoritative implementation-vs-doc status across the whole platform (not just this tree).

**Rewritten and verified against code as of 2026-07-23:**
1. `00_EXECUTIVE_SUMMARY.md` ← you are here
2. `01_ARCHITECTURE_OVERVIEW.md`
3. `DOCUMENTATION_PROGRESS.md`
4. `MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md` (rewritten in an earlier pass)

**Not reverified in this pass — treat as historical/pre-implementation until audited:**
- `02_DATABASE_SCHEMA_DESIGN.md`, `03_API_SPECIFICATIONS.md`
- `04_MODULE_SPECIFICATIONS/*.md` — except `Contracts_Module.md`, which **was** rewritten alongside the contract-cluster pass
- `05_BUSINESS_LOGIC_FLOWS.md` through `10_TESTING_STRATEGY.md`, `Business_Rules.md`, `UI_System_Design_Guidelines.md`, `CRITICAL_BUSINESS_RULE_UPDATE.md`
- `06_FRONTEND_ARCHITECTURE.md` in particular is named as if it still describes an Angular frontend — high suspicion of drift, flagged for priority review
- `frontendguides/*.md` (12 files) and `database/*.md`
- `MVP_final_docs/MVP_DIRECT_RENTAL_SPECIFICATION.md` / `MVP_DIRECT_RENTAL_STATE_MACHINE.md` — confirmed **accurate** per the audit (§7.1), just historically disconnected from the epic index (now linked via `backlog/post-mvp/epic-21-direct-rental.md`)
- `MVP_final_docs/MVP_ADMIN_WALLET_OPERATIONS_SPECIFICATION.md`, `MVP_AUTHORITATIVE_BUSINESS_RULES.md`, `MVP_DISPUTE_RESOLUTION_WORKFLOW.md`, `MVP_EVENT_CATALOG_AND_HANDLERS.md`, `MVP_MODULE_INTEGRATION_SPECIFICATION.md`, `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md`, `SETTLEMENT_ENHANCEMENTS_ADDENDUM.md` — not confirmed either way in this pass

---

**This document describes a system that is already largely built.** For anything not covered here in enough depth, consult `project-docs/18_Implementation_Coverage_Audit.md` first — it is the authoritative reconciliation between documentation and running code across backend, web, and both mobile apps.

**Next Document:** [01_ARCHITECTURE_OVERVIEW.md](./01_ARCHITECTURE_OVERVIEW.md)
