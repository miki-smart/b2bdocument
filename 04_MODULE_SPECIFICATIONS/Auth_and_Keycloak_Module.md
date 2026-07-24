# Auth & Keycloak Module — Specification

**Module Name:** Authentication (Keycloak-backed, in-process BFF)
**Version:** 2.0 (rewritten against running code)
**Last verified against code:** 2026-07-23
**Location:** `Modules/Auth/**` plus `Controllers/AuthController.cs`, `Controllers/Mobile/MobileAuthController.cs`, `Infrastructure/Keycloak/**`, `Infrastructure/Middleware/BffTokenRefreshMiddleware.cs` inside `Marketplace.API` (.NET 9 modular monolith) — this is a folder/namespace inside one deployable, not a separate service
**Related documents:** `architecture/auth-service-microservice-spec.md`, `architecture/bff-backend-for-frontend-spec.md`, `architecture/system-architecture-with-auth-bff.md` (all rewritten 2026-07-23 — primary architectural sources this spec is distilled from), `project-docs/18_Implementation_Coverage_Audit.md` §8/§10.5

---

## What changed in this rewrite

**v1.0 of this document was almost entirely fictional.** It described a standalone **BFF built on YARP** proxying to Keycloak and to a separately-deployed `Marketplace.API`, an Angular frontend, Authorization-Code-Flow-with-PKCE, a `movello-web` Keycloak client with `directAccessGrantsEnabled: false`, and JWT-Bearer middleware in the BFF that mapped `business_id`/`provider_id` into claims. **None of that exists in code.** What is actually running:

- **One process**, not two. `Marketplace.API` calls Keycloak directly — there is no separate BFF deployable and no YARP reverse-proxy configuration anywhere in the repo.
- **Login is the Resource Owner Password Credentials grant** (`grant_type=password`), not Authorization Code + PKCE. The frontend posts a plain email/password JSON body to `/web/login`; there is no redirect to a Keycloak-hosted login page.
- **The "BFF" is real but is one ASP.NET Core middleware**, `BffTokenRefreshMiddleware`, not a YARP process. It is genuinely named "BFF" in the code and genuinely does what a BFF does for cookie/token handling — see §3.
- **Email/phone verification and password reset are NOT Keycloak-native flows.** They are implemented as 6-digit OTP codes stored directly on the local `UserAccount` entity (`Modules/Identity`), verified against local DB fields — Keycloak's own `emailVerified` flag is only best-effort synced afterward via an admin-API call. This is a significant, previously-undocumented divergence — see §5.
- **MFA does not exist.** `KeycloakAuthService.VerifyMfaAsync` throws `NotSupportedException` unconditionally.
- **There is no local `login_sessions`/`mfa_challenges`/`login_attempts` schema and no risk-scoring engine.** "Sessions" shown to a user are a live read-through to Keycloak's own admin session list.
- **The frontend is React 18.3 + Vite**, not Angular — see `movello-marketplace-core/src/shared/lib/api-client.ts`, `LoginPage.tsx`.

Everything below describes the real, running implementation. No fictional YARP/PKCE/Angular content is preserved — git history has the original if needed.

---

## 1. Overview

### Purpose

The Auth module is responsible for turning a username/password (or an existing refresh token) into a validated identity the rest of `Marketplace.API` can authorize against, for both the web app (cookie-based) and the two Flutter mobile apps (bearer-token-in-body). It delegates credential storage, password hashing, and token issuance to **Keycloak** — a real, externally-deployed identity provider — but owns:

- The two HTTP surfaces (`/web/*` for the browser, `/mobile/auth/*` for the apps) that front Keycloak.
- Cookie issuance and transparent refresh for the browser (the in-process "BFF" behavior).
- A parallel, Keycloak-independent **local OTP system** (stored on `UserAccount`, in `Modules/Identity`) for email verification, phone verification, and password reset — because standard Keycloak Direct Grant has no built-in OTP-challenge mechanism the mobile/web UX needs.
- Bootstrapping Keycloak itself at startup (realm import, dev/staging fixed-user sync).

### What it is **not**

- Not a separate microservice or container — it is `Modules/Auth/` plus a handful of top-level `Controllers/`/`Infrastructure/` files inside the single `Marketplace.API` process.
- Not an OAuth2 Authorization Code / PKCE flow — it is Direct Grant (Resource Owner Password Credentials), server-side only.
- Not an MFA system — `VerifyMfaAsync` is an explicit `NotSupportedException` stub.
- Not a risk-scoring or device-fingerprinting system — no such logic exists anywhere in this module.

---

## 2. Real Module Structure

```
Marketplace.API/
├── Controllers/
│   ├── AuthController.cs                  [Route("web")]        — browser auth (cookie-based)
│   └── Mobile/
│       └── MobileAuthController.cs        [Route("mobile/auth")] — mobile auth (token-in-body), [EnableRateLimiting("mobile-auth")]
│
├── Infrastructure/
│   ├── Keycloak/
│   │   ├── KeycloakInitializer.cs         — startup: wait for Keycloak, import realm export if missing, patch frontend URL
│   │   └── KeycloakUserSyncService.cs     — dev/staging only: syncs 3 fixed Keycloak user IDs into local user_accounts
│   └── Middleware/
│       └── BffTokenRefreshMiddleware.cs   — in-process token-refresh middleware, registered as app.UseBffTokenRefresh()
│
└── Modules/Auth/
    ├── Application/
    │   ├── Contracts/IAuthService.cs      — the interface both controllers depend on
    │   └── Models/                        — LoginRequest, TokenResponse, UserProfile, UserSession,
    │                                        CreateUserRequest, ChangePasswordRequest, ForgotPasswordRequest,
    │                                        VerifyEmailManualRequest, VerifyPhoneRequest, VerifyResetOtpRequest,
    │                                        ResetPasswordWithOtpRequest, ResendPhoneOtpRequest, UpdateUnverifiedEmailRequest
    └── Infrastructure/
        ├── Configuration/KeycloakOptions.cs
        └── Services/KeycloakAuthService.cs — the only implementation of IAuthService
```

Two things worth flagging because the folder layout is easy to misread:

- **`Modules/Auth/` has no `API/Controllers` subfolder** — unlike every other module (Contracts, Finance, MasterData, …), the HTTP-facing endpoints live in the app's top-level `Controllers/` tree, not nested under the module. Both controllers depend on the same `IAuthService`/`KeycloakAuthService` DI registration (`builder.Services.AddHttpClient<IAuthService, KeycloakAuthService>()` in `Program.cs`, one line, one process).
- **The local-OTP verification/reset commands that make login actually usable in practice live in `Modules/Identity/Application/UserAccount/Commands/`**, not in `Modules/Auth/` — `VerifyEmailOtpCommandHandler`, `VerifyPhoneOtpCommandHandler`, `ForgotPasswordCommandHandler`, `ResendEmailOtpCommandHandler`, `ResendPhoneOtpCommandHandler`, `UpdateUnverifiedEmailCommandHandler`, `VerifyResetOtpCommandHandler`, `ResetPasswordWithOtpCommandHandler` (all in `AccountOtpCommandHandlers.cs`). `Modules/Auth/` only calls into Keycloak; the actual OTP state machine belongs to `Modules/Identity`'s `UserAccount` entity. Treat this spec and `Identity_and_Compliance_Module.md` as complementary for the verification/reset story.

---

## 3. The three real components

### 3.1 `KeycloakAuthService` (`Modules/Auth/Infrastructure/Services/KeycloakAuthService.cs`)

A thin, direct wrapper around Keycloak's own REST APIs — no bespoke session/risk data model behind it.

| `IAuthService` member | What it actually calls |
|---|---|
| `LoginAsync` | `grant_type=password` direct grant to `{realm}/protocol/openid-connect/token`, with `client_id`/`client_secret` from `KeycloakOptions`. Username/password travel client → this process → Keycloak in one call. |
| `RefreshTokenAsync` | `grant_type=refresh_token` to the same token endpoint. |
| `LogoutAsync` | Keycloak's `.../protocol/openid-connect/logout`. Best-effort — a 5s timeout and any failure is logged and swallowed; cookies/local state are cleared by the caller regardless. |
| `RegisterUserAsync`, `DeleteUserAsync`, `ChangePasswordAsync`, `ResetPasswordAsync`, `VerifyEmailManualAsync`, `UpdateUserEmailAsync`, `GetUserByIdAsync`, `GetUserRolesAsync` | All via the **Keycloak Admin REST API** (`admin/realms/{realm}/...`), authenticated with a separately-obtained admin token (`GetAdminAccessTokenAsync` — password grant against the `master` realm using `AdminClientId`/`AdminUsername`/`AdminPassword`, fetched fresh on every call — **no admin-token caching**). |
| `GetUserSessionsAsync`, `RevokeSessionAsync`, `RevokeAllSessionsAsync` | Keycloak Admin API session endpoints (`GET/DELETE .../users/{id}/sessions`, `POST .../users/{id}/logout`). **Keycloak is the only session store** — there is no local `login_sessions` table. |
| `ForgotPasswordAsync` | Keycloak's `execute-actions-email` (`UPDATE_PASSWORD` action) — used **only** as an email-link fallback when a user has no phone number on file (see §5.2). |
| `VerifyMfaAsync` | Throws `NotSupportedException` unconditionally, with a code comment explaining standard Keycloak Direct Grant has no OTP-challenge/response step and no Authorization Code Flow or custom extension has been built to add one. |

Consequences worth being explicit about:
- **No risk engine.** No new-device detection, IP/geo-anomaly check, failed-attempt scoring, or dormant-account rule anywhere in this module.
- **No local session/MFA/login-attempt tables.** Session data shown to end users is a live read-through to Keycloak's own admin session list.
- User registration always uses **email as Keycloak username** (`request.Username = request.Email`), regardless of what the caller passes.

### 3.2 `BffTokenRefreshMiddleware` (`Infrastructure/Middleware/BffTokenRefreshMiddleware.cs`)

Registered as `app.UseBffTokenRefresh()`, immediately before `app.UseAuthentication()`. The word "BFF" is the actual name in the code — its own doc comment: *"BFF (Backend for Frontend) middleware that automatically refreshes access tokens before they expire. This keeps tokens server-side in httpOnly cookies and handles refresh transparently without frontend involvement."*

On every request whose path contains `/api/` (skipping `/web/login|logout|register|refresh`, `/health`, `/swagger`, `/scalar`, `/openapi`, `/hubs`):

1. Reads `mov_access_token` / `mov_refresh_token` from the request's cookies.
2. If the access token is **missing**, **unparseable**, **expired**, or **expiring within 2 minutes**, it calls Keycloak's `refresh_token` grant **itself** — directly, via its own `HttpClientFactory.CreateClient()` and `KeycloakOptions`, not via `KeycloakAuthService` and not via a separate Auth Service.
3. On success: re-sets both cookies on the response, and rewrites the **incoming** request's `Authorization` header to `Bearer {new access token}` so the request continues into standard `UseAuthentication()`/`UseAuthorization()`/JwtBearer validation.
4. On failure (or no refresh token to fall back to): clears both cookies and **short-circuits the pipeline with a `401` + `{"code": "SESSION_EXPIRED"}`** — it does not call `_next(context)`.
5. If there's no access token and no refresh token at all, the request proceeds unauthenticated (fails normal `[Authorize]` checks downstream, as expected).

So the specific things a BFF is supposed to provide — "no JWT in localStorage," "HttpOnly secure cookies," "central token refresh so the frontend never sees a stale token" — are all real, they just happen as one middleware step inside the monolith's own request pipeline, not as a network call to a separate BFF process. Cookie issuance itself (`SetTokenCookies`/`DeleteTokenCookies`) happens in `AuthController`, not in this middleware — the middleware only *refreshes* an already-issued cookie pair.

Cookie settings (identical logic duplicated in `AuthController` and this middleware): `HttpOnly=true`; `Secure` only when the request is HTTPS; `SameSite=None` when production **and** HTTPS, else `SameSite=Lax` (chosen so same-origin dev proxying still works without `Secure`); access-token cookie expiry follows the token's own `expires_in`; the middleware's own refresh path additionally hardcodes a 7-day expiry for the refresh-token cookie (not read from the token response).

### 3.3 `KeycloakInitializer` and `KeycloakUserSyncService` (`Infrastructure/Keycloak/`)

Both are startup/bootstrap concerns, deliberately kept outside `Modules/Auth/`:

- **`KeycloakInitializer.InitializeAsync`** — polls up to 120 times (1s apart) across several candidate health endpoints until Keycloak responds, then: gets a master-realm admin token, checks if the configured realm exists, imports a realm-export JSON file if not (tries app directory, `/app/`, then absolute path), and finally patches the realm's `attributes.frontendUrl` (not the deprecated top-level `frontendUrl` field, which newer Keycloak rejects) to `http://localhost:8086` in `Local`/`Development` or `https://auth.carclaks.com` otherwise.
- **`KeycloakUserSyncService.SyncUsersAsync`** — for **exactly 3 hardcoded Keycloak user IDs per environment** (one each for ADMIN/PROVIDER/BUSINESS, different fixed GUIDs for Development/Staging/Production, matched against each environment's `realm-export*.json`), fetches the user from Keycloak and upserts a matching row into the local `user_accounts` table (creating with `UserAccount.Create(...)` if missing, updating name/email-verified flag if present but changed). This is a fixed-seed-user sync for dev/test/demo accounts, not a general Keycloak→local user-provisioning pipeline — real end-user registration goes through `CreateUserAccountCommandHandler` instead (§4).

---

## 4. Real registration & login flow

### 4.1 Registration (`POST /web/register`, `POST /mobile/auth/register`)

Both controllers delegate to the same `CreateUserAccountCommandHandler` (`Modules/Identity/Application/UserAccount/Commands/`), which:

1. Rejects if the email or phone number is already taken locally.
2. If no `KeycloakUserId` is supplied, calls `IAuthService.RegisterUserAsync` to create the user in Keycloak first (`username = email`, `emailVerified = false` at creation).
3. Creates the local `UserAccount` row (`Modules/Identity/Domain/Entities/UserAccount.cs`), status `ACTIVE` immediately (there is no "pending" account status gating registration — verification gates *login*, not account creation).
4. Generates and persists a 6-digit **email** OTP (`SetEmailOtp`, 10-minute validity) and publishes `AccountEmailOTPGeneratedEvent` for the Notifications module to send.
5. If a phone number was supplied, also generates a 6-digit **phone** OTP (`SetPhoneOtp`, 5-minute validity) and publishes `AccountOTPGeneratedEvent`.
6. Publishes `UserAccountCreatedEvent` for Finance (wallet creation) and Notifications.
7. **Rollback on failure:** if the local DB write fails after Keycloak registration succeeded, the handler calls `IAuthService.DeleteUserAsync` to roll back the Keycloak user — a genuine two-phase-commit-style compensation, not a TODO.

The web flow additionally **auto-logs-in** the user right after registration (`AuthController.Register` calls `LoginAsync` and sets cookies) so the SPA can immediately call `/web/me` and drive the verification UI without a second login. The mobile flow does **not** auto-login — `MobileAuthController.Register` returns only `{ userId, requiresEmailVerification: true }`; the app must call `/mobile/auth/login` after both verifications succeed.

### 4.2 Login gate: verification status is checked locally, not via Keycloak

`AuthController.Login` / `MobileAuthController.Login` both call `KeycloakAuthService.LoginAsync` first (this succeeds as long as the password is correct — Keycloak has no knowledge of the app's own verification state), then look up the **local** `UserAccount` row and apply gates in order:

1. `Status != ACTIVE` → **web only** returns `403 { accountBlocked: true }` and deletes the cookies just set (mobile has no equivalent explicit block-check in `MobileAuthController.Login` — it only checks email/phone verification).
2. `!IsEmailVerified` → `403` with `requiresVerification`/`requiresEmailVerification: true` (web still leaves cookies set so the SPA can drive the verify-email screen; mobile has no tokens to leave since it hadn't returned any yet).
3. `!IsPhoneVerified && FeaturesSettings.PhoneVerificationRequired` → `403` with `requiresPhoneVerification: true` (this whole gate is a feature-flagged toggle — `FeaturesSettings` — not an unconditional requirement).

Only if all gates pass does the endpoint return success: web returns `{ message }` (tokens are already in cookies from the earlier `LoginAsync` call); mobile returns `{ accessToken, refreshToken, expiresIn, tokenType: "Bearer" }` in the JSON body, per an explicit code comment ("mobile clients cannot use httpOnly cookies").

### 4.3 `GET /web/me` — deliberately manual, not `[Authorize]`

`AuthController.GetMe` is marked `[AllowAnonymous]` on purpose, with a comment explaining it "handles auth manually here to support auto-refresh": it reads the access-token cookie (falling back to an `Authorization` header for API clients), and if missing but a refresh token is present, calls `RefreshTokenAsync` itself and re-sets cookies before proceeding. It then **manually decodes the JWT's `sub` claim with `JwtSecurityTokenHandler.ReadJwtToken`** — no signature or expiry validation happens in this handler specifically (that's left to the standard JwtBearer pipeline for genuinely `[Authorize]`-protected endpoints elsewhere). A `TEST_TOKEN_{userId}_{role}` format is also special-cased here and in `GetUserIdFromToken`/`GetCurrentSessionId` — an explicit test-harness bypass, not production auth.

### 4.4 Session management (`/web/sessions`)

`GET/DELETE /web/sessions` and `DELETE /web/sessions/{id}` are `[Authorize]`-protected and proxy straight to `KeycloakAuthService.GetUserSessionsAsync`/`RevokeSessionAsync`. The current session is identified by decoding the `sid` claim out of the access-token JWT and matching it against Keycloak's own session-ID field — there is no local concept of "session" independent of Keycloak's. Revoking a session also best-effort detaches any mobile push-token binding for that session ID via `IMobilePushTokenService`. **Mobile has no equivalent session-list/revoke endpoints under `/mobile/auth/*`** — the mobile session/device-management screens (`provider_profile_sessions_screen.dart`, `business_profile_sessions_screen.dart`, per `18_Implementation_Coverage_Audit.md` §7.2) must be calling a different controller (outside this module's scope) or reusing `/web/sessions` — a direct grep against the mobile-specific `Controllers/Mobile/` tree would be needed to confirm the exact route, out of scope for this rewrite.

---

## 5. Email/phone verification and password reset — the real, non-Keycloak mechanism

This is the single most important correction in this rewrite: **verification and password reset are local-OTP flows implemented on the `UserAccount` entity (`Modules/Identity/Domain/Entities/UserAccount.cs`), not Keycloak flows.** Keycloak's own `emailVerified` flag is only synced afterward as a best-effort side effect.

### 5.1 `UserAccount`'s OTP fields (three independent OTP slots, all on the same row)

| Purpose | Code column | Expiry column | Default validity | Verify method |
|---|---|---|---|---|
| Email verification | `emailOtpCode` | `emailOtpExpiresAt` | 10 minutes | `VerifyEmailOtp(code)` |
| Phone verification | `phoneOtpCode` | `phoneOtpExpiresAt` | 5 minutes | `VerifyPhoneOtp(code)` |
| Password reset | `passwordResetOtpCode` | `passwordResetOtpExpiresAt` | 10 minutes | `VerifyPasswordResetOtp(code)` |

All three are 6-digit numeric codes (`Random.Next(100000, 999999)` — not cryptographically hashed at rest, stored as plain text in the DB column), single-use (cleared on successful verification), and independently resendable.

### 5.2 Password reset: SMS-first, email-link only as a fallback

`ForgotPasswordCommandHandler`:
- If the user has **no phone number on file** → falls back to `KeycloakAuthService.ForgotPasswordAsync`, which triggers Keycloak's native `execute-actions-email` (`UPDATE_PASSWORD`) — the **only** place in this whole flow that actually uses a Keycloak-native mechanism.
- If the user **has** a phone number → generates a `SetPasswordResetOtp` code and publishes `PasswordResetOTPGeneratedEvent` for SMS delivery — Keycloak is never called for the phone-based path.

Both `AuthController.ForgotPassword` and `MobileAuthController.ForgotPassword` always return a generic 200 regardless of whether the email exists, to avoid account enumeration.

`ResetPasswordWithOtpCommandHandler` then: verifies the OTP against `UserAccount.VerifyPasswordResetOtp`, calls `IAuthService.ResetPasswordAsync` (Keycloak admin password reset — sets `temporary=false`), and **revokes all Keycloak sessions for that user** (`RevokeAllSessionsAsync`) so a password change forces re-login everywhere. `ChangePassword` (both controllers, authenticated) does the identical Keycloak-reset + revoke-all-sessions dance, but notably **does not verify the caller's current password against Keycloak before resetting it** — `KeycloakAuthService.ChangePasswordAsync`'s own doc comment admits this ("To verify currentPassword, we would need to try a login first... We will do an Admin Reset for now") — the `CurrentPassword` field in the request is accepted but never actually checked.

### 5.3 Dev/test OTP bypass

`VerifyEmailOtpCommandHandler` and `VerifyPhoneOtpCommandHandler` both accept a configured bypass code (`DevSettings:OtpBypassCode` from `IConfiguration`) that, if it matches the submitted code, force-verifies the account (`ForceMarkEmailVerified`/`ForceMarkPhoneVerified`) **without checking expiry at all** — this exists to unblock manual/QA testing without needing a real SMS/email provider, and should not be enabled with a non-empty value in production configuration.

### 5.4 Correcting a mistyped email pre-verification

`UpdateUnverifiedEmailCommandHandler` (`POST /web/update-unverified-email`, `POST /mobile/auth/update-unverified-email`) lets a user with an **unverified** account change their email before completing verification: rejects if already verified or if the new email is taken, updates the local record (`UserAccount.UpdateEmail` — resets `IsEmailVerified=false` and clears any pending email OTP), best-effort syncs the new email to Keycloak (`UpdateUserEmailAsync`), and issues a fresh email OTP.

---

## 6. Real API surface

### 6.1 Web (`AuthController`, `[Route("web")]`) — cookie-based

| Method & Path | Auth | Purpose |
|---|---|---|
| `POST /web/login` | Anonymous | Direct-grant login, sets cookies, applies local verification gates |
| `POST /web/register` | Anonymous | Register + auto-login |
| `GET /web/me` | Manual (see §4.3) | Current profile, transparent refresh |
| `POST /web/logout` | — | Keycloak logout (best-effort) + delete cookies + detach push token for current session |
| `POST /web/refresh` | Anonymous | Explicit refresh (cookie-driven) |
| `POST /web/forgot-password` | Anonymous | SMS OTP or email-link fallback (§5.2) |
| `POST /web/verify-reset-otp` | Anonymous | Check reset OTP validity without consuming it |
| `POST /web/reset-password-with-otp` | Anonymous | Consume OTP, reset password, revoke all sessions |
| `POST /web/verify-email-manual` | Anonymous | Consume email OTP |
| `POST /web/verify-phone` | Anonymous | Consume phone OTP |
| `POST /web/resend-otp` / `POST /web/resend-phone-otp` | Anonymous | Regenerate + resend the respective OTP |
| `POST /web/update-unverified-email` | Anonymous | Correct email pre-verification (§5.4) |
| `POST /web/change-password` | Manual (cookie JWT parse) | Authenticated password change + revoke-all-sessions |
| `GET /web/sessions` | `[Authorize]` | List Keycloak sessions for current user |
| `DELETE /web/sessions/{sessionId}` | `[Authorize]` | Revoke one session (blocks revoking the current one) |
| `DELETE /web/sessions` | `[Authorize]` | Revoke all **other** sessions |

### 6.2 Mobile (`MobileAuthController`, `[Route("mobile/auth")]`) — token-in-body, `[EnableRateLimiting("mobile-auth")]`

| Method & Path | Auth | Purpose |
|---|---|---|
| `POST /mobile/auth/register` | Anonymous | Register only — no auto-login, no tokens returned |
| `POST /mobile/auth/login` | Anonymous | Returns `{ accessToken, refreshToken, expiresIn, tokenType }` on success |
| `POST /mobile/auth/refresh` | Anonymous | Body-based refresh token exchange |
| `POST /mobile/auth/logout` | Anonymous | Revokes Keycloak refresh token + deactivates the device's push token (by `pushToken` or `deviceId`) |
| `POST /mobile/auth/verify-email` / `resend-email-otp` | Anonymous | Same email-OTP mechanism as web |
| `POST /mobile/auth/verify-phone` / `resend-phone-otp` | Anonymous | Same phone-OTP mechanism as web |
| `POST /mobile/auth/update-unverified-email` | Anonymous | Same as web |
| `POST /mobile/auth/forgot-password` / `verify-reset-otp` / `reset-password-with-otp` | Anonymous | Same reset flow as web, phrased with mobile-friendly copy |
| `POST /mobile/auth/change-password` | `[Authorize]` (manual bearer-header JWT parse) | Same Keycloak-reset + revoke-all-sessions behavior as web |

Rate limiting: `mobile-auth` sliding-window policy is **10 requests/minute** per the `AddSlidingWindowLimiter` config in `Program.cs` (general mobile endpoints get 60/minute under a separate `mobile-general` policy). **`AuthController` (web) carries no equivalent per-route rate limit** — only the generic ASP.NET Core pipeline applies.

---

## 7. Known gaps (verified — zero call sites / explicit stubs)

1. **MFA does not exist.** `VerifyMfaAsync` unconditionally throws `NotSupportedException`. No `/web/mfa/*` or `/mobile/auth/mfa/*` endpoints exist anywhere.
2. **No risk/device/geo scoring anywhere in this module** — despite `architecture/auth-service-microservice-spec.md` v1.0 (now corrected) proposing exactly this. Login is username+password in, tokens out, gated only by the three local status/verification checks in §4.2.
3. **`ChangePasswordAsync` never verifies the caller's current password** against Keycloak — the `CurrentPassword` field is accepted by the request DTO and silently ignored by the implementation (admin-style reset only). This is a real security-hardening gap worth a ticket, not a documentation nuance.
4. **Admin token is fetched fresh on every Keycloak Admin API call** (`GetAdminAccessTokenAsync`) — the method's own comment says *"In a real scenario, cache this token!"* — no caching exists, meaning every admin-API-backed operation (session list, role assignment, password reset, user lookup, …) pays a full extra token round-trip to Keycloak's `master` realm.
5. **OTP codes are stored as plain 6-digit strings**, not hashed, on the `UserAccount` row — readable by anyone with DB access (consistent with the Delivery module's separate OTP system, which explicitly never returns codes over the API for the same reason, but here at-rest hashing is simply absent).
6. **`DevSettings:OtpBypassCode`** — if configured with a non-empty value, both email and phone OTP verification accept it unconditionally, bypassing expiry entirely. This must be unset (or absent) in any environment where the config could leak.
7. **Mobile has no session-list/revoke endpoints under `/mobile/auth/*`.** If the mobile "active sessions" screens documented in `18_Implementation_Coverage_Audit.md` §7.2 (`provider_profile_sessions_screen.dart`, `business_profile_sessions_screen.dart`) call a real backend endpoint, it is not exposed from this module — needs a follow-up grep against `Controllers/Mobile/` to locate.
8. **`AuthController` (web) has no per-route rate limiting** — brute-force protection on `/web/login` relies entirely on whatever generic ASP.NET Core rate limiting is configured globally, unlike the mobile controller's explicit 10/minute policy.
9. **Registration always creates the local `UserAccount` with `Status = ACTIVE` immediately** — there is no "pending verification" account status; verification gates login, not account existence. A user who never verifies still has a permanent, queryable, `ACTIVE` account row.

---

## 8. Integration points

- **Identity module:** owns `UserAccount` (the actual OTP/verification/reset state machine — see §5), `Business`/`Provider` profile linkage, and the commands this controller layer calls into (`CreateUserAccountCommand`, `VerifyEmailOtpCommand`, `VerifyPhoneOtpCommand`, `ForgotPasswordCommand`, `ResetPasswordWithOtpCommand`, `UpdateUnverifiedEmailCommand`, `ResendEmailOtpCommand`, `ResendPhoneOtpCommand`). Treat `Identity_and_Compliance_Module.md` as the companion doc for these entities/commands.
- **Notifications module:** consumes `AccountEmailOTPGeneratedEvent`, `AccountOTPGeneratedEvent`, `PasswordResetOTPGeneratedEvent` to actually deliver the OTP codes via email/SMS.
- **Finance module:** consumes `UserAccountCreatedEvent` to provision a wallet for the new user.
- **Mobile push (`IMobilePushTokenService`):** logout and session-revoke both best-effort detach push-token bindings tied to the session/device being ended.
- **Keycloak** (external): the only genuinely separate, externally-deployed component in this whole picture — identity store, password hasher, JWT issuer, and (via its Admin API) the only session store in the system.

---

## Related documents

- `architecture/auth-service-microservice-spec.md` — deeper current-vs-proposed detail on `KeycloakAuthService` and the (unbuilt) future Auth Service design.
- `architecture/bff-backend-for-frontend-spec.md` — deeper detail on `BffTokenRefreshMiddleware` and the (unbuilt) future dedicated BFF service design.
- `architecture/system-architecture-with-auth-bff.md` — system-wide current-vs-proposed diagram placing this module in context.
- `marketplace-project-implementation/MVP_MODULAR/04_MODULE_SPECIFICATIONS/Identity_and_Compliance_Module.md` — `UserAccount`, `Business`, `Provider` entity detail.
- `project-docs/18_Implementation_Coverage_Audit.md` §8/§10.5 — the audit findings that triggered this rewrite.
