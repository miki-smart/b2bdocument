# Movello — Architecture Overview

**Version:** 2.0 (rewritten against running code)
**Last verified against code:** 2026-07-23
**Original version:** 1.0, November 26, 2025 — described a YARP-based BFF/API-gateway layer and an Angular 19 frontend as if they were current. Neither was ever built; the real stack is documented below.
**Status:** Section 1 describes what is actually running today (verified against code). Section 2 preserves legitimate forward-looking extraction ideas, clearly separated and labeled as **not built**.
**Authoritative companion documents (do not duplicate — cross-reference):**
- `architecture/modular-monolith-architecture.md` — module-boundary rules, event patterns, the real "Migration Path to Microservices" methodology
- `architecture/module-layout-convention.md` — the standard `Domain/Application/Infrastructure` folder shape every module should follow
- `architecture/auth-service-microservice-spec.md` — full detail on the Auth module, Keycloak integration, and the in-process BFF middleware (only summarized here)
- `MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md` — the full Contracts-module state machine (only summarized here)
- `project-docs/18_Implementation_Coverage_Audit.md` — the audit this rewrite is grounded in

---

## Table of Contents

1. [Section 1: Current Architecture](#section-1-current-architecture)
   1.1 [Deployment Shape](#11-deployment-shape)
   1.2 [System Components](#12-system-components)
   1.3 [Module Structure](#13-module-structure)
   1.4 [Communication Patterns](#14-communication-patterns)
   1.5 [Data Architecture](#15-data-architecture)
   1.6 [Security Architecture](#16-security-architecture)
   1.7 [Deployment Architecture](#17-deployment-architecture)
   1.8 [Scalability](#18-scalability)
2. [Section 2: Proposed Future Architecture — Not Built](#section-2-proposed-future-architecture--not-built)

---

## Section 1: Current Architecture

### 1.1 Deployment Shape

There is **one** backend deployable: `Marketplace.API`. Confirmed via the backend source tree — the only two `.csproj` files under `backend/` are `src/Marketplace.API/Marketplace.API.csproj` and `tests/Marketplace.Tests/Marketplace.Tests.csproj`. One `Program.cs`, one `docker-compose` service (`marketplace-api`), one container image.

There is **no separate BFF service, no API gateway, no YARP**. The client surfaces (React web, two Flutter apps) call `Marketplace.API` directly over HTTPS. The only thing resembling a "BFF" is `Infrastructure/Middleware/BffTokenRefreshMiddleware.cs`, which runs **in-process**, inside the same monolith — see §1.6.

**Why modular monolith, not microservices:** faster iteration, native ACID transactions across what would otherwise be separate services, one process to debug/deploy/monitor, and a clean extraction path if/when a specific module needs to scale independently. Full rationale and the "when to extract" decision criteria live in `architecture/modular-monolith-architecture.md` — not repeated here.

### 1.2 System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                          │
│                                                                    │
│  React 18.3 + Vite 6 SPA              Flutter apps               │
│  (business/provider/admin portals,    business_app (6 nav tabs,  │
│   role-based routing, one build)       incl. Direct Rental)      │
│  TanStack Query · Zustand · shadcn/ui  provider_app (7 nav tabs,  │
│                                         incl. Direct Rental)      │
│                                        flutter_riverpod · go_router│
└───────────────────────────┬───────────────────────────────────────┘
                            │ HTTPS — direct calls, no gateway hop
┌───────────────────────────▼───────────────────────────────────────┐
│                 Marketplace.API (.NET 9) — single process         │
│                                                                    │
│  Controllers/            — web-facing (AuthController, etc.)      │
│  Controllers/Mobile/      — 19 controllers, 100+ endpoints,        │
│                             dedicated Mobile API surface           │
│  Modules/                                                          │
│   ├─ Auth          (Keycloak integration, no local session store) │
│   ├─ Identity       (Business/Provider/Vehicle, KYC/KYB, trust)    │
│   ├─ Marketplace    (RFQ, bidding, split awards, Direct Rental)    │
│   ├─ Contracts      (18-state lifecycle, OTP signing, extension)  │
│   ├─ Finance        (wallets, escrow, settlement, Chapa gateway)   │
│   ├─ Delivery       (handover OTP, return OTP, inspection)         │
│   ├─ MasterData     (versioned policy/rules engine, lookups)       │
│   └─ Notifications  (multi-channel admin-configurable, SignalR)    │
│                                                                    │
│  MediatR (in-process pub/sub, dominant) · SignalR NotificationHub  │
│  BffTokenRefreshMiddleware (in-process, web-cookie flow only)      │
└───────────────────────────┬───────────────────────────────────────┘
                            │
       ┌────────────────────┼─────────────────┬────────────────┐
       ▼                    ▼                  ▼                ▼
  PostgreSQL 16         Keycloak            Redis            MinIO
 (EF Core 9 + Npgsql,  (direct-grant       (cache)      (S3-compatible
  schema-per-module     auth, admin API                  object storage)
  convention)           session mgmt)
                            │
                       RabbitMQ (provisioned: package + docker-compose
                       service + health check exist; per the coverage
                       audit, not the operative event bus in practice —
                       see §1.4)
```

### 1.3 Module Structure

There are **8 modules**, confirmed directly against `backend/src/Marketplace.API/Modules/`: **Auth, Contracts, Delivery, Finance, Identity, Marketplace, MasterData, Notifications.** Any doc describing 5 modules (Identity, Marketplace, Contracts, Finance, Delivery only) or 7 modules (with a `RiskAndTrust` module that doesn't exist as its own module — trust scoring lives inside Identity) is describing an earlier, unbuilt plan.

Each module follows (or is migrating toward) the standard shape defined in `architecture/module-layout-convention.md` — `Domain/{Entities,Events,Enums,Repositories,Services}`, `Application/{Contracts,<Feature>/{Commands,Queries},EventHandlers}`, `Infrastructure/{Repositories,Configurations,Services}`. That document is the single source of truth for the folder convention; it is not re-described here. One real deviation worth calling out: `Modules/Auth/` has no `API/Controllers` folder of its own — the HTTP-facing auth endpoints (`AuthController`, `MobileAuthController`) live in the app's top-level `Controllers/` tree instead, both wired to the same `IAuthService`/`KeycloakAuthService` registration (see `architecture/auth-service-microservice-spec.md` §1.2).

**Per-module summary** (responsibilities only — see `04_MODULE_SPECIFICATIONS/` for anything module-specific that's already been reverified, and treat unreverified files there as historical per `DOCUMENTATION_PROGRESS.md`):

| Module | Responsibility | Notable real-world divergence from earlier docs |
|---|---|---|
| **Auth** | Keycloak integration (login/refresh/logout, admin-API session list/revoke) | No local session/MFA tables; MFA unimplemented (throws `NotSupportedException`) |
| **Identity** | Business/Provider/Vehicle registration, KYC/KYB, trust scoring, tiering | Trust-score formula built but **not wired** into any production event; no business-side risk score exists |
| **Marketplace** | RFQ (header + line items), blind bidding, split awards, Direct Rental | Line-item + split-award model, not epic-04/05's single-vehicle-type model; ranking algorithm & anti-collusion detection don't exist |
| **Contracts** | Contract lifecycle, vehicle assignment, OTP signing, completion/termination | 18 real string status values (not a 4-state enum-driven model) — see `MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md` |
| **Finance** | Wallets, double-entry ledger, escrow, settlement, commission, payment gateways | Live Chapa/Telebirr/CBEBirr webhooks (not "future"); two disagreeing escrow-computation code paths and two disagreeing tier-threshold schemes coexist today |
| **Delivery** | OTP handover, photo/odometer/fuel evidence, return + inspection | Return-trip OTP + inspection checklist is a parallel system, undocumented in the original delivery epic |
| **MasterData** | Versioned commission/contract/escrow/settlement policy rules, tiers, lookups, geography, banks | Admin-facing configuration UI exists on web with no explicit epic-level deliverable anywhere |
| **Notifications** | Multi-channel (email/SMS/push) admin-configurable delivery, SignalR real-time hub | 40+ admin endpoints, credential rotation, live test-send — far beyond "email/SMS, WebSocket optional" |

### 1.4 Communication Patterns

**In-process events (MediatR) — the real, dominant mechanism.** Modules publish `INotification` events and other modules' `INotificationHandler<T>` implementations react, all within the same process and (for anything writing to the DB) frequently the same transaction. Example, verified against the real contract-creation flow (see `MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md` §10 for the full event-flow diagram):

```
BidAwardedEvent (Marketplace module)
  └─▶ BidAwardedEventHandler ─▶ CreateContractCommand ─▶ ContractCreatedEvent
        └─▶ ContractCreatedEventHandler (Finance module) locks escrow,
            retrying up to 5 times with exponential backoff
```

**RabbitMQ is provisioned, not the operative bus.** `RabbitMQ.Client` is a real package dependency (`Marketplace.API.csproj`), and `rabbitmq` is a real service in `backend/docker-compose*.yml` with its own health check. This reflects genuine infrastructure investment — but per `project-docs/18_Implementation_Coverage_Audit.md`, actual cross-module communication today runs through MediatR, not through RabbitMQ. Do not assume a feature is asynchronous/durable-queued just because RabbitMQ is provisioned; verify the actual handler.

**Cross-module reads:** modules do not reach into each other's repositories directly. Per `architecture/module-layout-convention.md` rule 3, the only importable cross-module surface is `Application/Contracts/` (reader interfaces, cross-module DTOs) — this is enforced socially today, not by a build-time boundary, but it is the real convention new code should follow.

### 1.5 Data Architecture

Single PostgreSQL 16 database via EF Core 9 + Npgsql, with `EFCore.NamingConventions` mapping C# PascalCase to snake_case columns. Modules use schema separation by convention (e.g. the `contracts` schema for most Contracts-module entities), though this is not applied with total rigidity — per `backlog/mvp/epic-06-contract-management.md`, `Contract`/`ContractLineItem`/`ContractVehicleAssignment` specifically live in the default schema rather than `contracts`.

**A real, notable pattern in this codebase:** several modules define a rich C# enum for a status field, then **never reference that enum anywhere outside its own file** — the actual column is a plain string, and the running system produces more or fewer distinct values than the enum has. This is confirmed in the Contracts module (`ContractStatus` — 17 enum members, 18 real runtime values, only one of which, `CANCELLED`, is missing from the enum; several enum members are never produced by any code path). Treat any doc that presents a status enum as ground truth with suspicion until you've grepped for actual usage — see `MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md` for the full worked example.

`02_DATABASE_SCHEMA_DESIGN.md` in this suite predates the current codebase (schema/table counts there were written before implementation) and has **not** been re-verified as part of this rewrite — read it as historical/aspirational, not as a current schema reference, until it gets its own audit pass.

### 1.6 Security Architecture

Full detail lives in `architecture/auth-service-microservice-spec.md` — summarized here only to keep this document self-contained:

- **No separate Auth microservice, no separate BFF/gateway.** `Modules/Auth` + a couple of top-level `Controllers`/`Infrastructure` files, all inside the one `Marketplace.API` process.
- **Login flow (web):** `LoginPage.tsx` submits an in-app email/password form directly to `POST /web/login` (`AuthController`) — **not** a redirect to a Keycloak-hosted login page. `AuthController` calls `KeycloakAuthService`, which performs a Resource Owner Password Credentials grant directly against Keycloak, then sets `mov_access_token`/`mov_refresh_token` as HttpOnly cookies on the response.
- **Login flow (mobile):** `MobileAuthController` (`mobile/auth/*`) is functionally parallel but returns tokens **in the JSON response body** — mobile clients cannot use HttpOnly cookies — and Flutter apps store them in secure device storage.
- **The one real "BFF":** `BffTokenRefreshMiddleware`, registered as `app.UseBffTokenRefresh()`, runs on every `/api/*` request (skipping login/logout/register/refresh and infra paths). It silently refreshes an expiring access-token cookie against Keycloak and copies the (possibly refreshed) token into the request's `Authorization: Bearer` header before the standard JwtBearer middleware runs. This is genuinely a "translate a cookie into a bearer token" BFF pattern — it just happens as one middleware step inside the monolith, not as a network hop to a separate service.
- **Sessions:** Keycloak's own admin session list is the session store — there is no local `login_sessions` table. "Session management" screens on web/mobile are live reads through Keycloak's Admin REST API.
- **MFA:** not implemented. `KeycloakAuthService.VerifyMfaAsync` explicitly throws `NotSupportedException` — standard Keycloak Direct Grant has no OTP-challenge step, and no custom extension has been built.
- **RBAC:** Keycloak realm roles — `business-admin`, `business-user`, `provider-admin`, `provider-driver`, `platform-admin`, `compliance-officer`, `finance-officer` — enforced via ASP.NET Core authorization policies keyed off JWT claims.
- **No risk-scoring engine** anywhere in the login path — no new-device detection, no IP/geo-anomaly check, no failed-attempt scoring. Rate limiting is generic ASP.NET Core rate limiting on the mobile auth routes only.

### 1.7 Deployment Architecture

Confirmed via `backend/docker-compose*.yml` (separate files per concern: `development`, `prod`, `infrastructure.{dev,prod}`, `keycloak`, `monitoring`, plus a deprecated base `docker-compose.yml` kept for reference).

```
marketplace-api   — single container, the whole .NET 9 monolith
                    (env vars wire Postgres, Redis, Keycloak, MinIO,
                    RabbitMQ, and Chapa payment config directly —
                    no gateway/BFF container in between)
postgres          — single instance
keycloak          — its own compose file
redis             — cache
minio             — object storage
rabbitmq          — provisioned message broker (see §1.4 on actual usage)
```

The web app (`movello-marketplace-core`) is a **separate** Vite/React build with its own `docker-compose*.yml` files (development/production/VPS variants), typically deployed as a static build behind Nginx — independently of the backend's deployment. Mobile apps (`business_app`, `provider_app`) are native Flutter builds distributed via app stores/APK — not containerized, not part of this compose topology at all.

### 1.8 Scalability

Current strategy is conventional horizontal scaling of the single monolith (multiple `marketplace-api` replicas behind a load balancer, Postgres read replicas for reporting, Redis for shared cache/session data) — no code changes are required for this tier of scaling since the monolith is stateless per-request. The methodology for **extracting** a specific module into its own service once it needs independent scaling is defined once, authoritatively, in `architecture/modular-monolith-architecture.md`'s "Migration Path to Microservices" section — not repeated here. See Section 2 below for how that would apply to Auth specifically, and for what a previous (superseded) draft of this document proposed for the platform as a whole.

---

## Section 2: Proposed Future Architecture — Not Built

Everything in this section is a **possible future direction**, preserved because it is legitimate forward-looking design thinking — not because any of it exists in code today. Nothing below should be read as a current fact.

### 2.1 Why this section exists

Version 1.0 of this document proposed a YARP-based BFF/API-gateway service sitting in front of the monolith, plus an eventual full microservices split (Identity/Marketplace/Contracts/Finance/Delivery each as independent deployables, RabbitMQ/Kafka as the inter-service bus, a dedicated API gateway like Kong/Traefik). That gateway/BFF service was never built — see Section 1 for what actually exists instead (an in-process middleware, not a service). The underlying **extraction methodology**, however, is still a reasonable plan to revisit if/when a specific module genuinely needs independent scaling, and is documented once, authoritatively, in `architecture/modular-monolith-architecture.md`'s "Migration Path to Microservices" section (extraction triggers, step-by-step process, in-process-event → message-queue migration). This section does not repeat that content — it only notes where a future BFF/gateway would fit relative to it.

### 2.2 A dedicated Auth microservice, specifically

`architecture/auth-service-microservice-spec.md` §2 already works through a detailed, concrete proposal for extracting Auth specifically — a security-gateway service with a device/IP/geo risk engine, MFA challenge/response, and its own `auth` schema (`login_sessions`, `mfa_challenges`, `login_attempts`). That proposal is the most fully worked-out extraction candidate in the documentation set today, precisely because Auth is already a clean module boundary with a single external dependency (Keycloak). It is not repeated here — read it directly if this path is ever picked up.

### 2.3 If a BFF/gateway were reintroduced

Should the platform reach a scale where a real network-hop BFF or API gateway becomes worthwhile (e.g. to aggregate calls across multiple extracted services, or to centralize rate limiting/routing once there is more than one backend deployable), the natural trigger is the same one `modular-monolith-architecture.md` defines for module extraction generally: independent scaling needs, team size, or concurrency thresholds — not a fixed timeline. Until at least one module is actually extracted, a separate BFF/gateway process has nothing to aggregate or route between, and the in-process `BffTokenRefreshMiddleware` described in §1.6 continues to be sufficient.

### 2.4 Event bus migration (if/when extraction happens)

The one piece of this proposal already partially in place is the message broker itself: RabbitMQ is provisioned today (package + docker-compose service, see §1.4) even though MediatR remains the operative in-process bus. If/when a module is extracted, the migration is mechanically small — replace `await _mediator.Publish(new SomeEvent())` with `await _messageBus.Publish("module.event.name", new SomeEvent())` — the harder part is redesigning event handlers that currently assume same-transaction consistency (e.g. contract creation + escrow lock in one DB transaction today) to tolerate eventual consistency instead. This is a genuine design cost worth planning for before extracting any module that currently participates in a same-transaction event flow.

---

**Related documents:** `architecture/modular-monolith-architecture.md`, `architecture/module-layout-convention.md`, `architecture/auth-service-microservice-spec.md`, `MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md`, `project-docs/18_Implementation_Coverage_Audit.md`.

**Next Document:** [02_DATABASE_SCHEMA_DESIGN.md](./02_DATABASE_SCHEMA_DESIGN.md) *(not reverified in this rewrite pass — see `DOCUMENTATION_PROGRESS.md`)*
