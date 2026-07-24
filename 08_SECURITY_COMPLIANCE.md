# Security & Compliance Guide

**Version:** 2.0
**Last verified against code:** 2026-07-23
**Original date:** November 26, 2025 (v1.0, MVP planning draft — see §0)

---

## 0. What changed in this revision

v1.0 of this document described a security architecture that was never built as written: a separate YARP-based BFF gateway service, Authorization Code Flow + PKCE against a Keycloak-hosted login page, mTLS between services, Postgres TDE, application-level column encryption for `tin_number`/`phone_number`, a granular role table (`compliance-officer`, `finance-officer`, `provider-driver`, etc.), and a DevSecOps toolchain (SonarQube, OWASP ZAP, Trivy, Dependabot) that has no presence in this repo's CI.

This rewrite replaces every claim with what is actually running, verified against `Program.cs`, `Infrastructure/Authentication/KeycloakAuthenticationExtensions.cs`, `Infrastructure/Middleware/BffTokenRefreshMiddleware.cs`, `Infrastructure/Extensions/CorsExtensions.cs`, the production/dev Docker Compose files, and `realm-export.json`. It should be read alongside `architecture/auth-service-microservice-spec.md` (the authoritative auth-flow rewrite this document defers to for login/refresh/session detail) and `project-docs/18_Implementation_Coverage_Audit.md` (§5, §8, §10.2 — trust/risk scoring reality).

**Headline correction:** there is **one deployable**, `Marketplace.API`. There is no separate BFF process, no API gateway, and no microservice security boundary to reason about — every claim below is about controls inside, or directly in front of, that single ASP.NET Core process.

---

## 1. Deployment & Trust Boundary (real topology)

```text
Internet
   │
   ▼
Marketplace.API  (single ASP.NET Core process — Kestrel, port 8080 internally)
   │  ├─ Controllers/AuthController.cs               (web, cookie-based)
   │  ├─ Controllers/Mobile/MobileAuthController.cs   (mobile, bearer-in-body)
   │  ├─ Infrastructure/Middleware/BffTokenRefreshMiddleware.cs  (in-process cookie→bearer translation)
   │  ├─ JwtBearer authentication + policy-based authorization
   │  └─ ~50 other controllers across 8 modules, all in the same process
   │
   ├──▶ Keycloak (separate container, direct-grant + admin-API calls, no user-facing redirect)
   ├──▶ PostgreSQL, Redis, MinIO, RabbitMQ (internal-network only in prod, see §5.3)
   └──▶ Chapa / Telebirr / CBEBirr payment gateways (outbound calls + HMAC-verified webhooks)
```

There is **no reverse-proxy-level security enforcement** documented here beyond whatever a deployer puts in front of the container (the production Compose file exposes the API directly on a host port; TLS termination, if any, happens outside this repo). There is no Traefik, no YARP gateway, and no mTLS between "services" — there is one service.

---

## 2. Authentication

### 2.1 Identity provider

Keycloak is real and is the system of record for credentials, but it is called **server-side only**, directly by `Marketplace.API`. There is no browser redirect to a Keycloak-hosted login page and no Authorization Code Flow / PKCE anywhere in the web or mobile clients — `KeycloakAuthService` uses the **Resource Owner Password Credentials (direct) grant**: the client posts username/password to the monolith, which forwards it to Keycloak's token endpoint and returns the result. See `architecture/auth-service-microservice-spec.md` §1.3–1.4 for the full call sequence. This is a materially different flow than the Authorization Code + PKCE pattern v1.0 assumed — that flow does not exist in this codebase.

### 2.2 Web session model (cookie-based)

- `POST /web/login` sets two HttpOnly cookies — `mov_access_token`, `mov_refresh_token` — directly on the response. Cookie flags (`KeycloakAuthenticationExtensions.SetTokenCookies`): `HttpOnly = true` always; `Secure` follows the actual request scheme (`context.Request.IsHttps`); `SameSite = None` only when both `ASPNETCORE_ENVIRONMENT=Production` **and** the request is HTTPS, otherwise `SameSite = Lax`. Refresh-token cookie expiry is a fixed 7 days; access-token cookie expiry tracks the token's own `expires_in`.
- Tokens are **never** placed in `localStorage`/`sessionStorage` by the web app — this part of the v1.0 claim holds up in practice, just via a different mechanism (direct grant + first-party cookies, not a network hop to a BFF).
- `Infrastructure/Middleware/BffTokenRefreshMiddleware.cs` (`app.UseBffTokenRefresh()`) runs on every `/api/*` request except `/web/login|logout|register|refresh` and infra paths: if the access-token cookie is missing/expired/expiring within 2 minutes, it silently calls Keycloak's refresh grant, re-sets both cookies, and copies the (possibly refreshed) access token into the request's `Authorization: Bearer` header so downstream `[Authorize]` checks see a normal bearer token. On refresh failure it clears cookies and returns `401 {"code":"SESSION_EXPIRED"}`. This is the real, in-process form of "BFF" in this system — not a separate gateway.
- `JwtBearerEvents.OnMessageReceived` also independently reads `mov_access_token` from the cookie and attempts its own refresh if the token is within 1 minute of expiry — so there are two overlapping refresh-attempt code paths (middleware + JWT event) writing to the same two cookies.
- SignalR (`/hubs/*`) accepts the access token via an `access_token` query-string parameter, the standard pattern for WebSocket upgrades that can't carry custom headers.

### 2.3 Mobile session model (bearer-in-body)

`MobileAuthController` (`mobile/auth/*`) is functionally parallel but returns both tokens **in the JSON response body** — the code's own comment states the reason: "mobile clients cannot use httpOnly cookies." Flutter clients persist tokens in Keychain/Keystore and send `Authorization: Bearer <token>` on every subsequent call. `[EnableRateLimiting("mobile-auth")]` applies a stricter sliding-window limit to this controller (see §5.1).

### 2.4 Token validation

`AddJwtBearer` validates lifetime and signing key always; `ValidateAudience`/`ValidateIssuer`/`RequireHttpsMetadata` are **configuration-driven per environment** — production compose sets `Keycloak__ValidateIssuer=true` and points the authority at the public HTTPS Keycloak hostname (`https://auth.carclaks.com/realms/marketplace-realm`); dev/base compose defaults `ValidateIssuer` to `false` against the in-network `http://keycloak:8080/...` authority. `ClockSkew` is fixed at 5 minutes. `OnTokenValidated` additionally: extracts roles from both `resource_access.<audience>.roles` and `realm_access.roles` and re-adds them as `ClaimTypes.Role` claims (see §3); looks up the caller's `UserAccounts` row by Keycloak subject and stamps `user_type` and `user_account_id` claims from the **local** database (not Keycloak) onto the principal — authorization decisions keying off `user_type`/`user_account_id` therefore depend on the local DB row existing and staying in sync with Keycloak, not solely on the JWT's own claims.

### 2.5 MFA — confirmed not implemented

`KeycloakAuthService.VerifyMfaAsync` **throws `NotSupportedException`**, with an explicit code comment: the direct grant used for login has no OTP challenge/response step, and no Authorization Code Flow or custom Keycloak extension has been built to add one. There is:

- No SMS/TOTP/email OTP step at login, for any role, on any surface.
- No `PENDING_MFA` state, no risk-based MFA trigger.
- No `/auth/mfa/verify` or `/auth/mfa/send` endpoint anywhere in the API surface.

Do not describe MFA as implemented, planned-for-MVP, or partially built without this caveat — it exists only as a documented, unimplemented future proposal (`architecture/auth-service-microservice-spec.md` §2 preserves the original design, explicitly labeled as not built).

### 2.6 Login/session risk detection — confirmed not implemented

There is no new-device detection, IP/geo-anomaly check, failed-login-attempt scoring, or dormant-account rule anywhere in `AuthController`, `MobileAuthController`, or `KeycloakAuthService`. Login is username+password in, tokens out, gated only by the account-status/email/phone-verification flags on the local `UserAccounts` row (§2.4). "Sessions" surfaced via `/web/sessions` and `/mobile/auth/sessions` are a live read-through to Keycloak's own admin session list — there is no locally-owned `login_sessions`/`login_attempts` audit table.

---

## 3. Authorization (RBAC)

### 3.1 Real roles

Three realm roles are actually seeded in Keycloak (`realm-export.json`): **`ADMIN`**, **`BUSINESS`**, **`PROVIDER`**. There is no `compliance-officer`, `finance-officer`, `business-admin`/`business-user` split, or `provider-admin`/`provider-driver` split at the Keycloak-role level — v1.0's granular role table does not exist. Finer-grained access within a role (e.g., which user in a multi-user business account can do what) is enforced in application logic against local `UserAccounts`/business-membership data, not via additional Keycloak roles.

### 3.2 Authorization policies (`KeycloakAuthenticationExtensions.AddKeycloakAuthentication`)

```text
AdminOnly          → RequireRole("admin", "ADMIN")
BusinessUser       → RequireRole("business", "BUSINESS", "admin", "ADMIN")
ProviderUser       → RequireRole("provider", "PROVIDER", "admin", "ADMIN")
BusinessOrProvider → RequireRole("business","BUSINESS","provider","PROVIDER","admin","ADMIN")
CanCreateRFQ       → permission claim "rfq:create"      OR role business/admin
CanSubmitBid       → permission claim "bid:submit"      OR role provider/admin
CanManageContracts → permission claim "contract:manage" OR role admin
CanViewFinancials  → permission claim "finance:view"    OR role admin
```

Roles are matched case-insensitively by design (both `"business"` and `"BUSINESS"` are accepted) because role casing has drifted across environments — a deliberate defensive check, not an oversight.

### 3.3 What controllers actually use

A repo-wide scan of `[Authorize(Roles = "...")]` attributes across all controllers found only two literal values in use: **`"ADMIN"`** (the large majority — master-data/admin controllers such as `BusinessTiersController`, `CommissionStrategiesController`, `ContractPoliciesController`, `CountriesController`, `EscrowPoliciesController`, `DocumentTypesController`, `AdminBankController`, plus selected admin actions inside `ContractsController`/`BusinessController`) and **`"ADMIN,SuperAdmin"`** on two endpoints in `ContractsController`. `SuperAdmin` is **not** a role seeded in `realm-export.json` — treat those two endpoints as effectively admin-only in practice; this is worth a cleanup ticket, not a documentation fix.

Every non-admin business/provider-facing controller instead relies on the named policies above (`BusinessUser`, `ProviderUser`, `CanCreateRFQ`, etc.) or plain `[Authorize]` (any authenticated principal) combined with **handler-level ownership checks** — e.g., "does this RFQ belong to the caller's business ID," resolved from the `user_account_id` claim stamped in §2.4, not from a Keycloak role. Do not describe RBAC in this system as "a role gates everything" — most business-logic-level authorization is ownership/ID-based inside command/query handlers, with Keycloak roles only drawing the coarse business/provider/admin line.

---

## 4. Data Protection

### 4.1 At rest

- **No column-level/field-level PII encryption.** `tin_number`, `phone_number`, and other identity fields are stored as plain columns in PostgreSQL. The one real application-level encryption service, `Shared/Services/DataProtectionEncryptionService` (backed by `AddDataProtection().UseEphemeralDataProtectionProvider()` plus a custom `FixedKeyDataProtectionProvider` seeded from a required 32-byte `DataProtection:Key`), is used exclusively to encrypt **notification-channel provider credentials** (SMS/Email/FCM secrets in `SmsProviderConfig`/`EmailProviderConfig`/`FcmProviderConfig`) — not identity/KYC PII. Do not claim TDE or column encryption is in place for business/provider identity data.
- **No database-level TDE.** Nothing in `docker-compose*.yml` or the unmodified `postgres:16-alpine` images enables Transparent Data Encryption; disk-level protection is whatever the host/volume layer provides, not configured by this codebase.
- **No automated backup job found.** No `pg_dump`/backup script, cron entry, or CI step performing scheduled database or MinIO backups exists anywhere in the reviewed Compose files, Dockerfiles, or GitHub Actions workflows. Treat "encrypted backups to MinIO with retention policies" as aspirational, not implemented.
- **Object storage (MinIO):** used for uploaded documents (KYC/KYB documents, delivery/inspection proofs). Production compose binds MinIO's API/console ports to `127.0.0.1` only (no public exposure) and the API reaches it over the internal Docker network; `MinIO__UseSSL` is `false` internally.

### 4.2 In transit

- The API container listens on plain HTTP internally (`ASPNETCORE_URLS=http://+:8080`); `app.UseHttpsRedirection()` is registered, and `ForwardedHeaders` middleware runs before it so the app correctly interprets HTTPS termination performed upstream — but **no reverse proxy, TLS certificate management, or HSTS configuration exists inside this repo**. Whatever sits in front of the container owns TLS termination; that layer isn't part of this codebase.
- **No mTLS.** There are no "services" to mutually authenticate — one process talks to Postgres/Redis/MinIO/RabbitMQ/Keycloak over the internal Docker network, none of which have TLS configured between them in the reviewed Compose files.

### 4.3 Blind bidding (a real, narrower "data protection" control this system implements)

`Modules/Marketplace/Domain/Services/BlindBiddingService` masks the identity of bidding providers from businesses before award: it SHA-256-hashes `{providerId}{salt}` (`BlindBidding:SaltSecret`, a required app secret — CI sets a fixed test value, production must supply its own) and displays a masked string (`"Provider •••4411"`). Per `18_Implementation_Coverage_Audit.md` §10.3, this masking is enforced **only at the UI layer** — `GetBidsByRFQQuery`/`GetBidQuery` on the backend set the real `ProviderName` on the response unconditionally regardless of award status; the API itself does not withhold the provider's identity pre-award. This is a real, currently open gap, not hypothetical — flag it if blind-bidding integrity is treated as a compliance requirement.

### 4.4 Outbound payment webhook integrity

Chapa and CBEBirr webhook/callback handling verifies an HMAC signature before trusting gateway callbacks: `ChapaPaymentProvider`/`CBEBirrPaymentProvider` compute HMAC-SHA256 (Chapa) / HMAC-SHA512 (CBEBirr) over the raw payload using a configured `WebhookSecret`, and `HandleChapaTransferApprovalCommand` separately validates an HMAC signature against a distinct `ApprovalSecret` before acting on transfer-approval callbacks. Per the remediation roadmap, these two handlers are the **only** ones deliberately kept on the `Result<T>` (non-throwing) pattern instead of the standard exception-based error handling, so a malformed/invalid webhook returns an acknowledging 200 (or a redirect) rather than crashing the retry loop on the gateway side.

---

## 5. Network & Infrastructure Security

### 5.1 Rate limiting (real, ASP.NET Core built-in — not the bespoke risk engine v1.0 described)

`Program.cs` registers two sliding-window limiters via `AddRateLimiter`:

- `mobile-general`: 60 requests/minute, 6 segments, oldest-first queueing, `QueueLimit = 0` (reject over-limit immediately).
- `mobile-auth`: 10 requests/minute, same shape — applied via `[EnableRateLimiting("mobile-auth")]` on `MobileAuthController`.

Rejections return `429` with a `Retry-After: 60` header and a JSON body. The **web** `AuthController` carries no equivalent per-route rate-limit attribute — worth flagging as an asymmetry (mobile login is throttled tighter than web login today).

### 5.2 CORS

`Infrastructure/Extensions/CorsExtensions.cs` builds a single `"ConfigurablePolicy"` entirely from configuration (`Cors:AllowedOrigins`, `AllowCredentials`, `AllowLocalhostAnyPort`, `AllowedMethods`, `AllowedHeaders`, `ExposedHeaders`) — there is no hardcoded allow-list in code. `AllowLocalhostAnyPort=true` (used in development) additionally accepts any `localhost`/loopback-IP origin regardless of port, on top of the explicit allow-list. Credentials are only enabled when the origin list doesn't include a wildcard, matching the browser rule that `*` and credentialed CORS are mutually exclusive.

### 5.3 Network isolation (actual, from Compose files)

Production infra (`docker-compose.infrastructure.prod.yml`): **Postgres and Redis have no host port binding at all** (`expose` only, reachable only from other containers on `marketplace-prod-network`); MinIO's API/console and RabbitMQ's AMQP/management ports are bound to **`127.0.0.1` only** (host-operator access, not public). Keycloak runs behind its own dedicated Postgres on a private `marketplace-keycloak-network`, and is additionally attached to both the dev and prod app networks so each backend can resolve it by container-DNS alias — the "Keycloak has its own dedicated database, fully separate from app databases" part of the topology is real and correctly isolated. The `Marketplace.API` container is the **only** backend component with a host port binding in production (`5100:8080`) — i.e., it is the actual public edge. There is no separate edge router/gateway container in front of it anywhere in this repo's Compose files.

### 5.4 Container hardening — not verified as configured

No non-root `USER` directive, distroless/Alpine final-stage confirmation, or image-vulnerability-scanning step was found in this pass' review of `backend/Dockerfile`/`docker-compose*.yml`. Treat "non-root containers" and "minimal/distroless base images" as unverified, not confirmed controls, unless re-checked directly against the current `Dockerfile`.

### 5.5 RabbitMQ — provisioned, narrowly used

RabbitMQ is deployed in every environment (dev/prod infra Compose, health-checked via `AddRabbitMQ` in `Program.cs`) and has a generic publisher (`Shared/Services/RabbitMQ/RabbitMQPublisher`/`IRabbitMQPublisher`), but production code only calls it from two handlers today: `Modules/Delivery/Application/EventHandlers/OTPGeneratedEventHandler.cs` and `ReturnOTPGeneratedEventHandler.cs`. It is not (yet) the platform's general event bus — MediatR in-process domain events, not RabbitMQ messages, carry the vast majority of cross-module side effects (see `architecture/backend-remediation-roadmap-2026-07-12.md`). Don't describe RabbitMQ as a fully adopted messaging backbone.

---

## 6. Audit & Logging

- **Structured logging is real:** Serilog is configured; `app.UseCorrelationId()` runs early in the pipeline so a correlation ID is available for the lifetime of each request and appears in log output — the "correlation ID propagated across all layers" claim holds, correctly scoped to "all layers of this one process," not multiple services. `Shared/Behaviors/LoggingBehavior` (a MediatR pipeline behavior) logs every command/query with duration, warns above 3 seconds, and errors on failure.
- **No generic `event_log` table per module exists as v1.0 specified.** Audit-relevant history is real but module-specific and entity-scoped instead of a single generic schema — e.g., `ProviderTrustScoreHistory`, `ContractAmendment`/status-change history, `NotificationHub` delivery logs — not a uniform `event_type`/`actor_id`/`details jsonb` table. If a single unified audit-log table is a compliance requirement, it does not exist today and would need to be designed.
- **Sensitive-data log masking:** not independently verified in this pass — no masking middleware or Serilog destructuring policy for passwords/tokens/PII was located; treat as unconfirmed rather than assert it's handled.

---

## 7. Confirmed-Absent Features (do not describe as implemented, planned-for-MVP, or partially built without this caveat)

| Feature | Status |
| --- | --- |
| MFA (any channel, any role) | Not implemented — `VerifyMfaAsync` throws `NotSupportedException` (§2.5). |
| Login/session risk scoring, device/geo anomaly detection | Not implemented anywhere in the auth path (§2.6). |
| Business risk score (0–100 model) | Does not exist — zero `RiskScore` field on the `Business` entity anywhere in the backend (per `18_Implementation_Coverage_Audit.md` §5). Only a provider-side `TrustScore` exists, and per audit §10.2 it is **fully coded but never wired into production events** — every provider's score is frozen at its registration-time default of 50 today. |
| Fraud-detection rule engine, anti-collusion detection | Confirmed zero code hits across backend, web, and both mobile apps. |
| Dispute-engine entities/workflow | `Disputed`/`OnHold` exist only as unused/vestigial contract status values (per audit §10.1) with no supporting entities or workflow behind them. |
| Separate BFF/API-gateway process, per-service security boundary | Never existed as a deployable — see §0/§1. |
| mTLS between "services" | N/A — one process; no TLS between the API and its own infra containers. |
| Column/field-level PII encryption (`tin_number`, `phone_number`, etc.) | Not implemented (§4.1). |
| Postgres TDE | Not configured (§4.1). |
| Automated encrypted backups | No backup automation found in the reviewed infra/CI (§4.1). |
| SAST/DAST/dependency-scanning in CI (SonarQube, OWASP ZAP, Trivy, Dependabot) | None of these appear in `backend/.github/workflows/*.yml` — CI runs `dotnet build`/`dotnet test` only (see `09_DEPLOYMENT_GUIDE.md` §4). |

---

## 8. Compliance Checklist (MVP, corrected)

- [x] **KYC/KYB documents collected and admin-verified** before businesses/providers are marked verified (Identity module document upload + admin approval flow — real, per epics 01–02).
- [ ] **Field-level PII encryption** — not implemented; plain columns today (§4.1).
- [ ] **MFA at login** — not implemented (§2.5).
- [ ] **Automated backup/retention policy** — not found in repo (§4.1).
- [ ] **Unified compliance audit-log table** — not implemented as a single schema; per-module history only (§6).
- [ ] **Business risk scoring / fraud detection** — not implemented (§7).
- Terms of Service / Privacy Policy acceptance and data-residency requirements were **not verified in this pass** — re-check against the current web/mobile onboarding flows and hosting provider before asserting either is satisfied.

---

## Related documents

- `architecture/auth-service-microservice-spec.md` — authoritative, detailed rewrite of the real login/refresh/session/BFF flow this document summarizes in §2.
- `architecture/module-layout-convention.md`, `architecture/backend-remediation-roadmap-2026-07-12.md` — real backend conventions and the error-handling/validation-pipeline state referenced in §4.4.
- `project-docs/18_Implementation_Coverage_Audit.md` — source of the trust/risk-scoring and blind-bidding findings in §4.3 and §7.

**Next Document:** [09_DEPLOYMENT_GUIDE.md](./09_DEPLOYMENT_GUIDE.md)
