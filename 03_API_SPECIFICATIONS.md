# Anqelba Car Rental API Specifications

**Last verified against code: 2026-07-23** — verified directly against `marketplace-project-implementation/backend/src/Marketplace.API/Controllers/**/*.cs` (every controller, all 8 modules plus the separate Mobile API surface), cross-checked with representative `Application/**/Commands` and `Queries` handlers, and with real endpoint usage in the web app (`anqelbacarrental-marketplace-core/src/core/services/*.ts`) and both Flutter apps (`anqelbacarrental-mobile/{business_app,provider_app}/lib/**/data/services/*.dart`). See `project-docs/18_Implementation_Coverage_Audit.md` for the full cross-surface audit this rewrite is based on, and `backlog/mvp/epic-05-bidding-engine.md`, `epic-06-contract-management.md`, `epic-08-wallet-escrow.md` for deep, independently-verified detail on those three modules' real behavior (this document focuses on the *routing/endpoint* surface; those epics carry the fuller behavioral detail).

**API Style:** RESTful, resource-oriented, JSON bodies (multipart for file uploads).
**Auth:** OAuth2/OIDC tokens issued by Keycloak, exchanged through the API's own `web`/`mobile` auth controllers — not a separate BFF process (see below).

---

## 1. Architecture Reality (read this before anything else in this doc)

The previous version of this document described a microservices-style platform with an API gateway, a separate BFF service, and a uniform `/api/v1` REST surface with an envelope response format. **None of that matches the running system.** The facts below are verified directly against `Program.cs`, the Keycloak auth extensions, and every controller's routing attributes.

1. **One process, one base URL per environment.** Everything lives in the single `Marketplace.API` ASP.NET Core 9 project (`Marketplace.API.csproj`) — one deployable, one port, no per-module gateway routing, no service mesh. There is a real **in-process** BFF pattern (`Infrastructure/Middleware/BffTokenRefreshMiddleware.cs`, `app.UseBffTokenRefresh()`) that transparently refreshes an expiring access token on the way through the pipeline — but it is middleware inside this one API, not a separate BFF service/process.

2. **Three route prefixes coexist, not one.** There is no single `/api/v1` convention:
   - **`web/...`** — the web/admin **auth** surface only. `AuthController` is `[Route("web")]`, not `api/auth`. So the real routes are `web/login`, `web/logout`, `web/me`, `web/register`, `web/refresh`, `web/sessions`, etc. — this is the one controller in the whole backend that doesn't start with `api/` or `mobile/`.
   - **`api/...`** — every other web/admin controller (`api/marketplace/*`, `api/contracts`, `api/finance/*`, `api/identity/*`, `api/delivery`, `api/notifications`, `api/admin/*`, plus all the MasterData/reference controllers). This is what the original doc's "Base URL: `https://api.movello.et/api/v1`" was gesturing at, except there is no `/v1` segment anywhere in code — it's just `api/...`.
   - **`mobile/...`** — the dedicated Mobile API surface (19 controllers, `Controllers/Mobile/*.cs`), used by both Flutter apps. No `api/` prefix at all — e.g. `mobile/auth/login`, `mobile/contracts/{id}`, `mobile/wallets/summary`.

3. **Web login is cookie-based, not bearer-token-in-JSON-body.** `POST web/login` sets two httpOnly cookies (`mov_access_token`, `mov_refresh_token`) via `SetTokenCookies()` and returns only `{ "message": "Login successful" }` in the body (plus a `403` with `requiresVerification`/`accountBlocked` flags for unverified/blocked accounts) — it does **not** return `accessToken`/`refreshToken` in the JSON payload as the old doc showed. `GET web/me` reads the token from the cookie first, falling back to the `Authorization` header. Mobile auth (`mobile/auth/login`) is the conventional bearer-token flow: it returns `accessToken`/`refreshToken` in the JSON body for the Flutter apps to store in secure storage, because there is no browser cookie jar on mobile.

4. **No `{success, data, meta}` envelope.** Controllers return ASP.NET's own `Ok(result)`, `CreatedAtAction(...)`, `NotFound(...)`, `BadRequest(new { message = "..." })`, etc. directly — the response body **is** the DTO (or a plain `{ message }`/`{ error }` object on failure), not wrapped in a `success`/`data`/`meta` envelope. There is no global exception-to-`ProblemDetails` envelope filter registered either; error shapes vary by handler (some throw `InvalidOperationException` caught by ASP.NET's default problem-details middleware, some manually return `BadRequest(new { message })`).

5. **Authorization is a mix of declarative `[Authorize]` and manual claim checks — and a handful of endpoints have neither.** Two different policy styles are used inconsistently across controllers: `[Authorize(Roles = "ADMIN")]` (role-string match) and `[Authorize(Policy = "AdminOnly")]` (a registered policy requiring role `admin`/`ADMIN`) are both live in different controllers for the same intent. Many endpoints only declare a bare `[Authorize]` (any authenticated user) and then manually branch on `User.FindFirstValue("user_type")` / `IUserContextService.GetUserType()` inside the action body to enforce BUSINESS-vs-PROVIDER-vs-ADMIN access (e.g. `RFQController`, `BidController`, `DirectRentalCartController`, `DirectRentalRequestController`) — the auth requirement in the tables below reflects what the code actually enforces, which is sometimes stricter or looser than the attribute alone suggests.
   - **Verified gap:** `DeliveryController` (`api/delivery`, web/admin surface) has **zero `[Authorize]` attributes anywhere in the file**, and there is no global fallback authorization policy registered (`Program.cs` calls `app.MapControllers()` with no `.RequireAuthorization()`, and `AddAuthorization()` registers only named policies, no `FallbackPolicy`). This means every endpoint on the web `DeliveryController` — OTP generate/verify, handover checklist submit/approve/reject, return-session endpoints — is reachable **without any authentication token** today. The Mobile equivalent, `MobileDeliveryController`, correctly carries a class-level `[Authorize]`.
   - **Verified gap:** `ContractsController` (`api/contracts`) also has no class-level `[Authorize]`, and two of its endpoints — `GET /api/contracts/business/{businessId}` and `GET /api/contracts/provider/{providerId}` — have no `[Authorize]` attribute of their own either. Combined with the same absence of a fallback policy, these two list endpoints are reachable by an unauthenticated caller who knows or guesses a `businessId`/`providerId` GUID. Most other actions on this controller (assignment, termination, completion, terms/OTP) do carry `[Authorize]`.
   - Both are flagged here as code-verified findings for the security backlog, not theoretical risks.

6. **Rate limiting, `/rfqs`, `/wallets/me` etc. from the old doc don't exist.** There is no evidence anywhere in the codebase of a rate-limiting middleware keyed by the patterns the old doc listed (`/auth/*`, `/rfqs`, `/bids`), and none of the resource paths in the old doc (`/rfqs`, `/rfqs/{id}/bids`, `/wallets/me`, `/settlements`) match a real route — the real paths are `api/marketplace/rfqs`, `api/marketplace/bids`, `api/finance/wallets/my-summary`, `api/finance/settlements/my-settlements`, etc., detailed below.

---

## 2. Authentication

### 2.1 Web/admin auth — `web/...` (cookie-based)

| Method | Route | Auth | Purpose |
|---|---|---|---|
| POST | `web/login` | anonymous | Sets `mov_access_token`/`mov_refresh_token` httpOnly cookies. Body-level checks: `403` + `accountBlocked:true` if suspended; `403` + `requiresVerification:true` if email/phone unverified. Returns `{ message }` only — no tokens in the body. |
| POST | `web/logout` | any | Clears cookies, revokes refresh token, detaches mobile push-token binding for the session. |
| GET | `web/me` | anonymous (self-checks cookie/header) | Returns `UserProfile`; supports silent auto-refresh so the frontend doesn't need to call `/refresh` explicitly first. |
| POST | `web/register` | anonymous | Creates a Keycloak + local `UserAccount` record. |
| POST | `web/forgot-password` | anonymous | Triggers reset flow. |
| POST | `web/verify-email-manual` | anonymous | Manual email OTP verification. |
| POST | `web/verify-phone` | anonymous | Phone OTP verification. |
| POST | `web/resend-phone-otp`, `web/resend-otp` | anonymous | Resend phone/email OTP. |
| POST | `web/update-unverified-email` | anonymous | Change email before it's verified. |
| POST | `web/verify-reset-otp` | anonymous | Verify the 6-digit password-reset OTP. |
| POST | `web/reset-password-with-otp` | anonymous | Complete password reset. |
| POST | `web/change-password` | any | Authenticated password change. |
| POST | `web/refresh` | anonymous (reads refresh cookie) | Rotates the access/refresh cookie pair. |
| GET | `web/sessions` | any | List the current user's active login sessions/devices. |
| DELETE | `web/sessions/{sessionId}` | any | Revoke one session. |
| DELETE | `web/sessions` | any | Revoke all sessions (force logout everywhere). |

### 2.2 Mobile auth — `mobile/auth/...` (bearer-token JSON)

| Method | Route | Auth | Purpose |
|---|---|---|---|
| POST | `mobile/auth/register` | anonymous | Mobile account registration. |
| POST | `mobile/auth/login` | anonymous | Returns `accessToken`/`refreshToken` in the JSON body (mobile has no cookie jar). |
| POST | `mobile/auth/refresh` | anonymous | Rotate tokens. |
| POST | `mobile/auth/logout` | anonymous (token in body) | Revoke refresh token, detach push binding. |
| POST | `mobile/auth/verify-email` | anonymous | Manual email OTP verification (mirrors web). |
| POST | `mobile/auth/resend-email-otp` | anonymous | |
| POST | `mobile/auth/verify-phone` | anonymous | |
| POST | `mobile/auth/resend-phone-otp` | anonymous | |
| POST | `mobile/auth/update-unverified-email` | anonymous | |
| POST | `mobile/auth/forgot-password` | anonymous | Kicks off the **in-app 6-digit OTP** reset flow (not an email-link flow — see `MobileMeController`/`business_app` `auth_verify_reset_otp_screen.dart`). |
| POST | `mobile/auth/verify-reset-otp` | anonymous | |
| POST | `mobile/auth/reset-password-with-otp` | anonymous | |
| POST | `mobile/auth/change-password` | `[Authorize]` | |

---

## 3. Identity Module — `api/identity/*`

### 3.1 Business — `api/identity/businesses` (`BusinessController`, `[Authorize]` class-level)

| Method | Route | Auth | Purpose |
|---|---|---|---|
| POST | `api/identity/businesses` | any (self) | Register a business for the current user. |
| GET | `api/identity/businesses/me` | any (self) | Current user's business profile. |
| GET | `api/identity/businesses/me/bank-accounts` | any (self) | List the business's bank accounts. |
| GET | `api/identity/businesses/me/bank-accounts/current` | any (self) | Currently active/primary bank account. |
| POST | `api/identity/businesses/me/bank-accounts/change/initiate` | any (self) | Start dual-OTP (email + phone) bank-account-change flow. |
| POST | `api/identity/businesses/me/bank-accounts/change/verify-email` | any (self) | |
| POST | `api/identity/businesses/me/bank-accounts/change/verify-phone` | any (self) | |
| POST | `api/identity/businesses/me/bank-accounts/change/resend-otp` | any (self) | |
| POST | `api/identity/businesses/me/bank-accounts/change/cancel` | any (self) | |
| DELETE | `api/identity/businesses/me/bank-accounts/{id}` | any (self) | |
| PUT | `api/identity/businesses/me/bank-accounts/{id}/set-primary` | any (self) | |
| GET | `api/identity/businesses/{id}` | any | Get business by id. |
| PUT | `api/identity/businesses/{id}` | any | Update business profile. |
| POST | `api/identity/businesses/{id}/documents` | any | Upload KYB document (JSON command, not multipart — the actual file goes through `FileUploadController` first). |
| GET | `api/identity/businesses/{id}/documents` | any | List documents. |
| POST | `api/identity/businesses/{id}/complete-onboarding` | any | |
| PATCH | `api/identity/businesses/{id}/onboarding-step` | any | |
| PATCH | `api/identity/businesses/{id}/preferences` | any | |
| PATCH | `api/identity/businesses/{id}/contact-person` | any | |
| GET | `api/identity/businesses/admin/list` | `Roles=ADMIN` | Admin business list/search. |
| GET | `api/identity/businesses/admin/{id}` | `Roles=ADMIN` | Admin detail view. |
| PUT | `api/identity/businesses/admin/{id}/verification/status` | `Roles=ADMIN` | KYB approve/reject. |
| POST | `api/identity/businesses/admin` | `Roles=ADMIN` | Admin-initiated business creation (on behalf of a client). |

### 3.2 Provider — `api/identity/providers` (`ProviderController`, `[Authorize]` class-level)

Mirrors the Business controller's shape: `me`, `me/bank-accounts` (+ dual-OTP change flow, delete, set-primary), `{id}` (get/update), `{id}/complete-onboarding`, `{id}/onboarding-step`, `{id}/documents` (POST/GET), `{id}/preferences`, plus provider-specific:

| Method | Route | Auth | Purpose |
|---|---|---|---|
| POST | `api/identity/providers` | any | Register provider. |
| GET | `api/identity/providers/me/dashboard-stats` | any (self) | Provider's own dashboard stat cards. |
| GET | `api/identity/providers/me/dashboard-analytics` | any (self) | Trend data behind the dashboard. |
| GET | `api/identity/providers/me/recommended-rfqs` | any (self) | RFQs matching the provider's fleet segments. |
| GET | `api/identity/providers/admin/list` | `Roles=ADMIN` | |
| GET | `api/identity/providers/admin/{id}` | `Roles=ADMIN` | |
| PUT | `api/identity/providers/admin/{id}/verification/status` | `Roles=ADMIN` | KYC approve/reject. |
| POST | `api/identity/providers/admin` | `Roles=ADMIN` | |

### 3.3 Vehicle — `api/identity/vehicles` (`VehicleController`, `[Authorize]` class-level)

| Method | Route | Auth | Purpose |
|---|---|---|---|
| POST | `api/identity/vehicles` | any | Register vehicle (`RegisterVehicleCommand`). |
| GET | `api/identity/vehicles/{id}` | any | |
| GET | `api/identity/vehicles/{id}/status-history` | any | Full status-change audit trail (statuses include the web-only-documented `DELIVERED/RETURNED/REPLACED/MAINTENANCE` values beyond the basic lifecycle). |
| GET | `api/identity/vehicles/{id}/assignments` | `ProviderUser` policy | Contract/Direct-Rental assignment history for this vehicle. |
| GET | `api/identity/vehicles/provider/{providerId}` | any | Provider's fleet list. |
| PUT | `api/identity/vehicles/{id}` | any | |
| POST | `api/identity/vehicles/{id}/documents` | any | |
| POST | `api/identity/vehicles/{id}/insurance` | any | Add insurance record. |
| POST | `api/identity/vehicles/insurance/{insuranceId}/verify` | any | |
| PUT | `api/identity/vehicles/insurance/{insuranceId}` | any | |
| POST | `api/identity/vehicles/{id}/photos` | any | Multipart: front/back/left/right/interior. |
| PUT | `api/identity/vehicles/{id}/rental-rate` | `ProviderUser` | Sets the Direct Rental fixed daily rate. |
| POST | `api/identity/vehicles/{id}/enable-direct-rental` | `ProviderUser` | |
| POST | `api/identity/vehicles/{id}/disable-direct-rental` | `ProviderUser` | |
| GET | `api/identity/vehicles/admin/list` | `Roles=ADMIN` | |
| GET | `api/identity/vehicles/admin/{id}` | `Roles=ADMIN` | |
| PUT | `api/identity/vehicles/admin/{id}/verification/status` | `Roles=ADMIN` | |
| POST | `api/identity/vehicles/admin` | `Roles=ADMIN` | Admin-created vehicle (e.g. on behalf of a provider). |
| PUT | `api/identity/vehicles/admin/{id}/direct-rental-settings` | `Roles=ADMIN` | Admin override of Direct Rental enablement/rate. |

### 3.4 Users, Compliance, Dashboard

| Method | Route | Auth | Purpose |
|---|---|---|---|
| POST | `api/identity/users` | `[Authorize]` | Create a `UserAccount` (system/admin use). |
| GET | `api/identity/users/{id}` | `[Authorize]` | |
| POST | `api/identity/users/{id}/devices` | `[Authorize]` | Register a device (web push-adjacent). |
| POST | `api/identity/users/{id}/sessions` | `[Authorize]` | |
| POST | `api/identity/users/{id}/suspend` | `[Authorize]` | |
| POST | `api/identity/users/{id}/block` | `[Authorize]` | |
| POST | `api/identity/users/{id}/reactivate` | `[Authorize]` | |
| PUT | `api/identity/compliance/documents/{documentId}/status` | `Roles=ADMIN` | Approve/reject any KYB/KYC document. |
| GET | `api/identity/dashboard/admin-stats` | `Roles=ADMIN` | |
| GET | `api/identity/dashboard/successful-contract-trend` | `Roles=ADMIN` | |
| GET | `api/identity/dashboard/business-stats` | `[Authorize]` (self) | |
| GET | `api/identity/dashboard/provider-stats` | `[Authorize]` (self) | |
| GET | `api/identity/dashboard/stats` | `Roles=ADMIN` | Platform-wide summary stats. |

---

## 4. Marketplace Module — `api/marketplace/*`

### 4.1 RFQ — `api/marketplace/rfqs` (`RFQController`, `[Authorize]` class-level, manual `user_type` branching per action)

RFQ is a **header + line-items** model — every RFQ has one or more `RFQLineItem`s (vehicle type, quantity, term, purpose, required-from/to dates, optional fuel type/target price), not a single vehicle-type/date-range as older docs assumed.

| Method | Route | Auth (real) | Purpose |
|---|---|---|---|
| POST | `api/marketplace/rfqs` | BUSINESS or ADMIN (checked in-body) | Create RFQ with line items (`CreateRFQCommand`). Admin must pass `businessId` and auto-publishes; a business user's own `businessId` is forced server-side. |
| PUT | `api/marketplace/rfqs/{id}` | BUSINESS/ADMIN, owner-checked | Update (only while still editable). |
| PUT | `api/marketplace/rfqs/{id}/publish` | BUSINESS/ADMIN, owner-checked | `DRAFT → PUBLISHED`. |
| PUT | `api/marketplace/rfqs/{id}/close` | BUSINESS/ADMIN, owner-checked | Manually close bidding early. |
| PUT | `api/marketplace/rfqs/{id}/extend-deadline` | BUSINESS/ADMIN, owner-checked | Extend the submission deadline (for expired RFQs). |
| DELETE | `api/marketplace/rfqs/{id}` | BUSINESS/ADMIN, owner-checked | Cancel/delete a not-yet-awarded RFQ. |
| GET | `api/marketplace/rfqs/{id}` | anonymous (no `[Authorize]` on the action) | Get one RFQ with line items; bid-count included. |
| GET | `api/marketplace/rfqs/{id}/status-history` | `[Authorize]` | Full status audit trail. |
| GET | `api/marketplace/rfqs` | `[Authorize]` (implicit — class-level) | **The list/browse endpoint** — filterable by `status`, `statuses[]`, `search`, `vehicleType[]`, `fuelType[]`, `pickupLocation`, `dropoffLocation`, paginated. There is **no** separate `/open` route — browsing "open" RFQs is just this endpoint with a status filter. (The web frontend calls it as `GET /marketplace/rfqs?...` — confirmed in `rfq-service.ts`.) |

**Example — create RFQ (`CreateRFQCommand`, verified against code):**
```json
POST api/marketplace/rfqs
{
  "businessId": "guid (forced server-side for non-admins)",
  "title": "Monthly Vehicle Rental - December 2025",
  "submissionDeadline": "2025-11-28T23:59:59Z",
  "type": "STANDARD",
  "pickupCity": "Addis Ababa",
  "dropoffCity": "Addis Ababa",
  "lineItems": [
    {
      "vehicleType": "EV_SEDAN",
      "quantity": 5,
      "term": "SHORT_TERM",
      "purpose": "Staff transportation",
      "requiredFrom": "2025-12-01T00:00:00Z",
      "requiredTo": "2025-12-31T00:00:00Z",
      "fuelType": "EV",
      "targetPricePerUnit": 3500.00
    }
  ]
}
```
Note: there is no top-level RFQ `startDate`/`endDate` — those live per line item (`requiredFrom`/`requiredTo`); this is a real, verified divergence from the old per-RFQ date-range model.

### 4.2 Bidding — `api/marketplace/bids` (`BidController`, `[Authorize]` class-level)

Bids are per-line-item and quantity-based — **no specific vehicle is chosen at bid time**, only fleet-segment (vehicle type + fuel) capacity is checked.

| Method | Route | Auth (real) | Purpose |
|---|---|---|---|
| POST | `api/marketplace/bids` | PROVIDER or ADMIN | Submit a bid (`SubmitBidCommand`) — one or more line items, quantity + unit price (per vehicle/day) each. One bid per (provider, line item); providers may bid on multiple line items of the same RFQ in one call. |
| PUT | `api/marketplace/bids/{id}` | `[Authorize]` | Partial-update: only items present in the payload are changed; omitted items are untouched. |
| DELETE | `api/marketplace/bids/{id}` | `[Authorize]` | Withdraw (`WITHDRAWN`). Re-submission after withdrawal is explicitly allowed — the handler hard-deletes the prior withdrawn row first. |
| POST | `api/marketplace/bids/award` | `[Authorize]` | **Split-award** (`AwardBidCommand`) — a flat list of `{bidId, lineItemId, quantityAwarded}`; one call can split a single line item across several providers' bids. Validates wallet affordability (returns an estimated-affordable-quantity hint on shortfall) and provider fleet capacity. RFQ becomes `AWARDED` once every line item is fully covered, else `PARTIALLY_AWARDED`. |
| GET | `api/marketplace/bids/{id}` | `[Authorize]` | Single bid detail. **Verified gap:** `ProviderName` is populated unconditionally by the query, regardless of award status, despite the DTO's own doc comment saying "NULL if not awarded (blind bidding)" — blind bidding is enforced only by the web UI choosing not to render the field, not by the API. |
| GET | `api/marketplace/bids/rfq/{rfqId}` | `[Authorize]`, business/admin | All bids for an RFQ, grouped client-side by line item. Available **immediately after publish**, not gated behind RFQ closure. Same `ProviderName` leak as above. |
| GET | `api/marketplace/bids/provider/{providerId}` | `[Authorize]` | A provider's own bid history. |
| GET | `api/marketplace/bids/{id}/award-assignments` | `[Authorize]` | Vehicle-assignment status for every award tied to this bid. |

**Example — award, split across two providers for one line item:**
```json
POST api/marketplace/bids/award
{
  "rfqId": "guid",
  "requestingUserId": "guid",
  "userType": "BUSINESS",
  "awards": [
    { "lineItemId": "li-1", "bidId": "bid-A", "quantityAwarded": 3 },
    { "lineItemId": "li-1", "bidId": "bid-B", "quantityAwarded": 2 }
  ]
}
Response: [ "award-guid-1", "award-guid-2" ]   // list of new RFQBidAward ids, not a wrapped object
```
**Verified open item:** `AwardBidCommandHandler` contains a `// TODO: Publish BidAwardedEvent ...` comment — award→contract-creation→escrow-lock is not demonstrably event-driven from *this* handler in isolation; see Epic 06 (`ContractCreatedEventHandler`) for how contract creation actually gets triggered.

### 4.3 Post-Award Vehicle Assignment — `api/marketplace/rfq/awards` (`RfqAwardController`, `[Authorize]`, provider-only via manual check)

Identical pattern on **every** surface (backend, web, both mobile apps) — not mobile-specific, contrary to older docs.

| Method | Route | Auth (real) | Purpose |
|---|---|---|---|
| GET | `api/marketplace/rfq/awards/{awardId}/assignments` | PROVIDER | Assignment status for one award. |
| POST | `api/marketplace/rfq/awards/{awardId}/vehicles` | PROVIDER | Assign specific vehicle IDs to the award. |
| DELETE | `api/marketplace/rfq/awards/{awardId}/vehicles/{vehicleId}` | PROVIDER | Release/unassign. |
| GET | `api/marketplace/rfq/awards/{awardId}/eligible-vehicles` | PROVIDER | Candidate vehicles (matching type, `APPROVED`, not already committed). |

### 4.4 Provider Fleet Capacity — `api/marketplace/provider/fleet` (`ProviderFleetController`, `[Authorize]`)

| Method | Route | Purpose |
|---|---|---|
| GET | `api/marketplace/provider/fleet/capacity` | Snapshot of fleet capacity by vehicle-type/fuel segment. |
| POST | `api/marketplace/provider/fleet/capacity/bid-preview` | Preview capacity impact of a prospective bid before submitting. |
| GET | `api/marketplace/provider/fleet/action-items` | Fleet-capacity conflicts needing provider attention (across RFQ bids and Direct Rental commitments). |

### 4.5 Direct Rental — `api/marketplace/cart`, `api/marketplace/direct-rental/*` (epic-21, not in the original 20-epic list)

Fixed-price, non-bidding vehicle booking — browse → cart → submit → provider accepts/rejects/partially-accepts. Fully separate from the RFQ/bidding flow; converges with it only downstream, in the Contracts module (`Contract.SourceType = DIRECT_RENTAL`).

**Vehicles — `api/marketplace/direct-rental/vehicles`** (`DirectRentalVehicleController`, `[Authorize]`)

| Method | Route | Purpose |
|---|---|---|
| GET | `api/marketplace/direct-rental/vehicles` | Browse available-for-direct-rental vehicles (filterable). |
| GET | `api/marketplace/direct-rental/vehicles/{vehicleId}` | Vehicle detail with rate/availability. |

**Cart — `api/marketplace/cart`** (`DirectRentalCartController`, `[Authorize]`, BUSINESS-only via manual check)

| Method | Route | Purpose |
|---|---|---|
| GET | `api/marketplace/cart` | Business's own cart (returns an empty-cart shape if none exists yet, rather than 404). |
| POST | `api/marketplace/cart/items` | Add vehicle + date range to cart (`AddToCartCommand`). |
| PATCH | `api/marketplace/cart/items/{cartItemId}` | Update an item's date range. |
| DELETE | `api/marketplace/cart/items/{cartItemId}` | Remove an item (`204 No Content`). |
| GET | `api/marketplace/cart/submit-preview` | Preview wallet/escrow requirements before submitting. |
| POST | `api/marketplace/cart/submit` | Submit the cart — creates **one `DirectRentalRequest` per provider** in the cart (`SubmitCartCommand`, body: `{ isAllOrNone, specialInstructions }`), returns the created request IDs. |

**Requests — `api/marketplace/direct-rental/requests`** (`DirectRentalRequestController`, `[Authorize]`, business/provider branching)

| Method | Route | Purpose |
|---|---|---|
| GET | `api/marketplace/direct-rental/requests` | Business view = requests sent; Provider view = requests received. Filterable by status/date, paginated. |
| GET | `api/marketplace/direct-rental/requests/{requestId}` | Single request detail. |
| GET | `api/marketplace/direct-rental/requests/{requestId}/history` | Status-history timeline. |
| POST | `api/marketplace/direct-rental/requests/{requestId}/cancel` | Business cancels a still-pending request. |
| POST | `api/marketplace/direct-rental/requests/{requestId}/respond` | **Provider** responds per-vehicle — supports full acceptance, partial acceptance, or full rejection in one call (`{ vehicleResponses: [{ vehicleId, isAccepted, rejectionReason }] }`). Feeds `DirectRentalRequestAcceptedEvent`/`...PartiallyAcceptedEvent`, which the Contracts module turns into a contract. |
| GET | `api/marketplace/direct-rental/requests/{requestId}/accept-preview` | Provider-side preview of fleet-capacity conflicts before accepting. |

---

## 5. Contracts Module — `api/contracts` (`ContractsController`)

No class-level `[Authorize]` (see §1.5 for the verified auth gap on the two list endpoints). A contract is created automatically from an RFQ award or an accepted Direct Rental request — there is no "create contract" endpoint; contracts only ever originate from those two event handlers.

**Real status model:** `Contract.Status` is a plain string column with **18 real values** in production (`PENDING_ESCROW → ESCROW_LOCK_FAILED/PENDING_VEHICLE_ASSIGNMENT → PENDING_SIGNING → PENDING_DELIVERY → PARTIALLY_DELIVERED → ACTIVE → TERMINATION_REQUESTED/PARTIALLY_RETURNED → TERMINATED/COMPLETED`, plus `CANCELLED`). There is **no `SUSPENDED` status anywhere** — this differs from what older docs describe. See `backlog/mvp/epic-06-contract-management.md` for the full reachability table (which of the 18 values are actually ever set vs. vestigial).

| Method | Route | Auth | Purpose |
|---|---|---|---|
| GET | `api/contracts/admin` | `Roles=ADMIN` | All contracts, admin filters. |
| GET | `api/contracts/{contractId}` | `[Authorize]` | Full contract detail (parties, line items, escrow, settlement schedule). |
| GET | `api/contracts/{contractId}/status-history` | `[Authorize]` | Coverage is inconsistent — not every transition writes a row (escrow-lock, delivery/return, and dual-OTP-signing transitions currently don't). |
| GET | `api/contracts/business/{businessId}` | **none** (verified gap — see §1.5) | Business's own contract list, filterable. |
| GET | `api/contracts/provider/{providerId}` | **none** (verified gap — see §1.5) | Provider's own contract list, filterable. |
| GET | `api/contracts/{contractId}/line-items/{lineItemId}/available-vehicles` | `[Authorize]` (Provider/Admin) | Candidate vehicles for assignment. |
| POST | `api/contracts/{contractId}/line-items/{lineItemId}/assign-vehicle` | `[Authorize]` (Provider/Admin) | Assign one or more vehicles to a line item. |
| POST | `api/contracts/{contractId}/line-items/{lineItemId}/unassign-vehicle` | `[Authorize]` (Provider/Admin) | Pre-delivery: simple removal (works). Post-delivery: requires `replacementVehicleId` + a signed `SCOPE_CHANGE` `amendmentId` — **verified dead branch**, nothing in the codebase ever creates a `ContractAmendment`, so this path can never actually succeed today. |
| POST | `api/contracts/{contractId}/reset-vehicle-assignments` | `[Authorize]` (Admin/Provider) | Wipes all assignments + delivery sessions, returns contract to `PENDING_VEHICLE_ASSIGNMENT`. |
| PATCH | `api/contracts/{contractId}/reset-to-pending-vehicle-assignment` | `Roles=ADMIN` | **Verified unreachable** — its precondition (`Status == PENDING_ACTIVATION`) can never be true because nothing in the codebase ever sets that status. |
| POST | `api/contracts/{contractId}/termination/request` | `[Authorize]` (Business/Provider/Admin) | Handler enforces a narrower guard (`ACTIVE`/`PARTIALLY_RETURNED` only) than the domain method technically allows. |
| POST | `api/contracts/{contractId}/termination/approve` | `[Authorize]` (Business/Provider/Admin) | Any party can approve — no self-vs-other-party check (unlike completion, below). No reject/withdraw endpoint exists. |
| POST | `api/contracts/{contractId}/terms/otp/generate` | `[Authorize]` | Dual-party contract e-signature: generates a 6-digit OTP for the calling party (5 min validity, 60s resend cooldown). Distinct from delivery OTP (Epic 07). |
| POST | `api/contracts/{contractId}/terms/otp/verify` | `[Authorize]` | Verifies only the caller's own OTP. Once both parties confirm, `PENDING_SIGNING → SIGNED → PENDING_DELIVERY` fires in one call (`SIGNED` is never a persisted, queryable row). |
| GET | `api/contracts/{contractId}/terms` | `[Authorize]` | Terms body/version + both parties' confirmation state. |
| GET | `api/contracts/{contractId}/completion/readiness` | `[Authorize]` | Structured DTO: all-returned flag, pending-settlement-cycle count, coverage flag, blockers — for UI display without triggering a request. |
| POST | `api/contracts/{contractId}/completion/request` | `[Authorize]` | Either party requests two-party completion (only reachable from `PARTIALLY_RETURNED`). |
| POST | `api/contracts/{contractId}/completion/approve` | `[Authorize]` | Must be the *other* party or admin — self-approval rejected. |
| POST | `api/contracts/{contractId}/completion/reject` | `[Authorize]` | Must be the other party or admin — self-rejection rejected. |
| POST | `api/contracts/{contractId}/completion/cancel` | `[Authorize]` | Only the original requester can withdraw. |
| POST | `api/contracts/{contractId}/complete` | `Roles=ADMIN,SuperAdmin` | Admin override — bypasses the two-party flow, resolves any pending request as `ADMIN_OVERRIDE`. |
| POST | `api/contracts/{contractId}/abort-before-signing` | `Roles=ADMIN,SuperAdmin` | Only from `PENDING_VEHICLE_ASSIGNMENT`/`PENDING_ESCROW`/`PENDING_SIGNING`; refunds escrow, sets `CANCELLED` (a status **not present in the `ContractStatus` C# enum at all** — it's a string-only value). |

**Verified, high-priority gap — no extend endpoint exists:** the web app's `ExtendContractDialog.tsx` calls `POST /contracts/{contractId}/extend`, and `ExtendContractCommand`/Handler is fully implemented — but **no controller route is wired to it anywhere in `Controllers/`**. Clicking "Extend Contract" in the running app has no working backend today. There is no "renew" endpoint or concept anywhere in the codebase either — extension only ever lengthens the existing contract in place.

**Early return** (`POST api/contracts/vehicle-assignments/{assignmentId}/early-return`) as described in the old doc's example was **not found** as a route in the current `ContractsController` — early-termination is instead handled entirely on the Finance side (`POST api/finance/escrow/{contractId}/early-termination`, §6.3), which computes proration/penalty/refund; there is no separate per-assignment early-return endpoint on the Contracts controller today.

---

## 6. Finance Module — `api/finance/*`, `api/payments`, `api/admin/wallets`, `api/admin/banks`

### 6.1 Wallets — `api/finance/wallets` (`WalletController`, `[Authorize]`)

| Method | Route | Auth | Purpose |
|---|---|---|---|
| POST | `api/finance/wallets` | `[Authorize]` | Manual wallet creation (admin/system path); `409` on duplicate owner+type. |
| GET | `api/finance/wallets/my-summary` | `[Authorize]` | `WalletSummaryDto` — MAIN + ESCROW combined view for the caller. |
| GET | `api/finance/wallets/my-balance` | `[Authorize]` | Balance/locked/pending-withdrawal/available/total. |
| GET | `api/finance/wallets/owner/{ownerId}` | `[Authorize]` | Query param `ownerType=BUSINESS\|PROVIDER\|PLATFORM`. |
| GET | `api/finance/wallets/owner/{ownerId}/summary` | `[Authorize]` | |
| GET | `api/finance/wallets/owner/{ownerId}/balance` | `[Authorize]` | |
| POST | `api/finance/wallets/{walletId}/deposit` | `Policy=AdminOnly` | Admin-direct credit (support/correction path). |
| POST | `api/finance/wallets/{walletId}/withdraw` | `Policy=AdminOnly` | Admin-direct debit. |
| GET | `api/finance/wallets/{walletId}/transactions` | `[Authorize]` | Paginated, filterable by type/date range. |
| POST | `api/finance/wallets/my-wallet/withdrawal` | `[Authorize]` | User-initiated withdrawal request (see §6.2 for the parallel `api/finance/withdrawals` route accepting the same action). |
| GET | `api/finance/wallets/platform-accounts` | `Policy=AdminOnly` | Platform wallet accounts, for audit. |

### 6.2 Withdrawals — `api/finance/withdrawals` (`WithdrawalController`, `[Authorize]`)

Both **businesses and providers** can withdraw (`WithdrawalRequest.OwnerType` is `PROVIDER` or `BUSINESS`) — this is not provider-only.

| Method | Route | Auth | Purpose |
|---|---|---|---|
| GET | `api/finance/withdrawals` | `Policy=AdminOnly` | Admin queue, filterable/sortable. |
| GET | `api/finance/withdrawals/{requestId}` | `Policy=AdminOnly` | |
| POST | `api/finance/withdrawals` | `[Authorize]` | Submit a request (`RequestWithdrawalCommand`) — funds move from `Balance` to `PendingWithdrawalBalance` immediately. |
| POST | `api/finance/withdrawals/{requestId}/approve` | `Policy=AdminOnly` | Admin approves → initiates a Chapa transfer. |
| POST | `api/finance/withdrawals/{requestId}/reject` | `Policy=AdminOnly` | Refunds the locked amount back to `Balance`. |
| POST | `api/finance/withdrawals/{requestId}/process-bank-transfer` | `Policy=AdminOnly` | Manual bank-transfer processing (receipt + transaction number upload) → `COMPLETED`. |
| POST | `api/finance/withdrawals/{requestId}/retry` | `Policy=AdminOnly` | Retry a `FAILED` Chapa transfer without double-refunding. |

### 6.3 Escrow — `api/finance/escrow` (`EscrowController`, `[Authorize]`)

| Method | Route | Purpose |
|---|---|---|
| GET | `api/finance/escrow/my-locks` | Caller's own escrow locks, paginated, status filter. |
| GET | `api/finance/escrow/{contractId}` | Escrow account for a contract. |
| POST | `api/finance/escrow/lock` | Direct lock (admin correction / non-automatic path). |
| POST | `api/finance/escrow/{contractId}/release` | Full release — splits into provider MAIN credit, platform COMMISSION credit, optional business refund, all in one double-entry transaction. |
| POST | `api/finance/escrow/{contractId}/partial-release` | Reduces the lock without fully closing it (`LOCKED → PARTIALLY_RELEASED`). |
| POST | `api/finance/escrow/{contractId}/retry` | Manually retry a failed automatic lock (after the 5-attempt exponential backoff in `ContractCreatedEventHandler` gives up). |
| POST | `api/finance/escrow/{contractId}/freeze` | Admin dispute freeze — `LOCKED`/`PARTIALLY_RELEASED → DISPUTED`. |
| POST | `api/finance/escrow/{contractId}/unfreeze` | Restore to prior state. |
| POST | `api/finance/escrow/{contractId}/early-termination` | Prorated payout: business refund + provider settlement (commission at the **contract's own snapshotted weighted-average rate**, not the provider's current tier) + platform commission/penalty. Blocked while `DISPUTED`. |

**Escrow amount rule (BR-031A):** per line item, `escrowDays = min(durationDays, 30)`; `lineItemEscrow = unitAmount × quantityAwarded × escrowDays`, summed across line items. Locking is triggered by `ContractCreatedEvent` (contract creation), **not** by delivery/OTP confirmation.

### 6.4 Deposits — `api/finance/deposit-requests` (`DepositRequestController`, `[Authorize]`) + `api/admin/deposit-requests` (`AdminDepositRequestController`, `Policy=AdminOnly`)

| Method | Route | Purpose |
|---|---|---|
| POST | `api/finance/deposit-requests` | Multipart submission: bank, transaction number, receipt file (JPG/PNG/PDF). Creates `PENDING_REVIEW` — **no wallet credit yet**. |
| GET | `api/finance/deposit-requests/my` | Caller's own history, paginated, status filter. |
| GET | `api/admin/deposit-requests` | Admin queue. |
| GET | `api/admin/deposit-requests/{id}` | |
| POST | `api/admin/deposit-requests/{id}/approve` | Credits the wallet only at approval. |
| POST | `api/admin/deposit-requests/{id}/reject` | With reason. |

### 6.5 Payments (gateways) — `api/payments` (`PaymentController`, mostly anonymous — webhooks must be, `[Authorize]` on the user-facing ones)

Chapa, Telebirr, and CBE Birr are all **live**, not a future integration.

| Method | Route | Auth | Purpose |
|---|---|---|---|
| GET | `api/payments/providers` | `[Authorize]` | List available gateways. |
| POST | `api/payments/intent` | `[Authorize]` | Create a payment intent; returns provider checkout URL/reference. |
| GET | `api/payments/status/{transactionReference}` | `[Authorize]` | Poll status; a `COMPLETED` Chapa status also triggers wallet crediting as a fallback if the webhook hasn't landed. |
| GET | `api/payments/chapa-callback` | anonymous | Chapa `return_url` — idempotent, redirects browser to `/wallet/deposit-callback`. |
| POST | `api/payments/webhook/chapa` | anonymous, signature-validated | Async webhook, `X-Chapa-Signature`. |
| POST | `api/payments/webhook/telebirr` | anonymous, signature-validated | `X-Telebirr-Signature`. |
| POST | `api/payments/webhook/cbebirr` | anonymous, signature-validated | `X-CBE-Signature`. |
| POST | `api/payments/webhook/{provider}` | anonymous | Generic fallback webhook route. |
| POST | `api/payments/webhook/chapa/transfer-approval` | anonymous | Synchronous approval callback for outbound Chapa transfers (withdrawals) — must be registered in the Chapa dashboard. |

### 6.6 Settlements — `api/finance/settlements` (`SettlementController`, `[Authorize]`)

| Method | Route | Auth | Purpose |
|---|---|---|---|
| GET | `api/finance/settlements/my-settlements` | `[Authorize]` | Caller's settlement payouts. |
| GET | `api/finance/settlements/{payoutId}/details` | `[Authorize]` | |
| GET | `api/finance/settlements/cycles` | `Policy=AdminOnly` | |
| GET | `api/finance/settlements/cycles/{cycleId}/status-history` | `Policy=AdminOnly` | |
| GET | `api/finance/settlements/schedule-states` | `Policy=AdminOnly` | |
| GET | `api/finance/settlements/payouts` | `Policy=AdminOnly` | |
| GET | `api/finance/settlements/payouts/{payoutId}` | `Policy=AdminOnly` | |
| POST | `api/finance/settlements/generate` | `Policy=AdminOnly` | Manually trigger settlement generation. |
| POST | `api/finance/settlements/generate-current-cycle` | `Policy=AdminOnly` | |
| POST | `api/finance/settlements/payouts/{payoutId}/approve` | `Policy=AdminOnly` | |
| POST | `api/finance/settlements/payouts/{payoutId}/reject` | `Policy=AdminOnly` | |

### 6.7 Provider Invoices — `api/finance/invoices` (`ProviderInvoiceController`, `[Authorize]`)

Inverts the older "system generates the invoice" assumption — **providers submit** invoices for admin approval.

| Method | Route | Purpose |
|---|---|---|
| POST | `api/finance/invoices` | Provider submits an invoice. |
| GET | `api/finance/invoices` | List (own, or admin all). |
| GET | `api/finance/invoices/{id}` | Detail. |
| POST | `api/finance/invoices/{id}/received` | Mark received (admin). |
| POST | `api/finance/invoices/{id}/approve` | |
| POST | `api/finance/invoices/{id}/reject` | |

### 6.8 Admin Wallet Operations — `api/admin/wallets` (`AdminWalletController`, `Policy=AdminOnly`) + `api/admin/banks` (`AdminBankController`, `Roles=ADMIN`)

| Method | Route | Purpose |
|---|---|---|
| GET | `api/admin/wallets` | List/filter every wallet account. |
| GET | `api/admin/wallets/platform` | Platform wallet overview. |
| GET | `api/admin/wallets/statistics` | Platform-wide financial stats. |
| GET | `api/admin/wallets/{walletId}` | |
| GET | `api/admin/wallets/{walletId}/transactions` | |
| GET | `api/admin/wallets/escrow/transactions` | Cross-business escrow feed. |
| POST | `api/admin/wallets/{walletId}/status` | Suspend/activate a wallet. |
| POST | `api/admin/wallets/{walletId}/deposit` | Admin-direct credit (audited separately from the `WalletController` equivalent — same underlying command). |
| POST | `api/admin/wallets/{walletId}/withdraw` | Admin-direct debit. |
| GET | `api/admin/wallets/tax-report` | Withholding tax report. |
| GET | `api/admin/banks` | List banks (reference data feeding bank-account forms). |
| GET | `api/admin/banks/chapa-options` | Chapa's supported bank list for transfer routing. |
| PUT | `api/admin/banks/{id}` | |
| DELETE | `api/admin/banks/{id}` | |

---

## 7. Delivery Module — `api/delivery` (`DeliveryController`)

**No `[Authorize]` anywhere in this controller — see the verified security gap in §1.5.** Two OTP mechanisms exist in the platform: this one (physical vehicle handover proof) and the Contracts module's terms-signing OTP (§5) — they are unrelated.

| Method | Route | Purpose |
|---|---|---|
| POST | `api/delivery/sessions/{sessionId}/otp/generate` | Generate delivery-confirmation OTP. |
| POST | `api/delivery/sessions/{sessionId}/otp/verify` | Verify — on success, fires `DeliveryConfirmedEvent` (drives contract activation, Epic 06 §6.5). OTP codes are never returned in any API response body, by design. |
| GET | `api/delivery/sessions/{sessionId}` | |
| GET | `api/delivery/sessions/contract/{contractId}` | All sessions for a contract. |
| GET | `api/delivery/contracts/{contractId}/timeline` | Full delivery/return timeline. |
| GET | `api/delivery/sessions/{sessionId}/otp` | Pending OTP metadata (not the code). |
| GET | `api/delivery/business/{businessId}/pending-otps` | |
| POST | `api/delivery/contracts/{contractId}/vehicles/{vehicleId}/request-confirmation` | Provider requests business to confirm delivery. |
| POST | `api/delivery/returns/{contractId}/vehicles/{vehicleId}/initiate` | Start a return session. |
| POST | `api/delivery/returns/sessions/{sessionId}/otp/generate` | Return-trip OTP (parallel to the outbound one). |
| POST | `api/delivery/returns/sessions/{sessionId}/otp/verify` | |
| GET | `api/delivery/returns/sessions/{sessionId}` | |
| GET | `api/delivery/returns/sessions/contract/{contractId}` | |
| GET | `api/delivery/checklist-template` | Vehicle-inspection checklist template (query param scopes vehicle type). |
| POST | `api/delivery/sessions/{sessionId}/checklist` | Submit outbound inspection checklist (again after a rejection; BR-015). |
| GET | `api/delivery/sessions/{sessionId}/checklist` | The latest checklist for the session (may be `REJECTED`, with `reviewReason`). |
| POST | `api/delivery/returns/sessions/{sessionId}/checklist` | Submit return inspection checklist. |
| GET | `api/delivery/returns/sessions/{sessionId}/checklist` | |
| POST | `api/delivery/checklists/{checklistId}/approve` | |
| POST | `api/delivery/checklists/{checklistId}/reject` | Body `{reviewedByName, reason?}`. Reason kept as `reviewReason`; the submitter is notified and resubmits. |

---

## 8. Notifications Module

### 8.1 User — `api/notifications` (`NotificationUserController`, `[Authorize]`)

| Method | Route | Purpose |
|---|---|---|
| GET | `api/notifications/my-notifications` | Paginated. |
| GET | `api/notifications/my-notifications/summary` | Unread count etc. |
| PUT | `api/notifications/{notificationId}/read` | |
| PUT | `api/notifications/mark-all-read` | |
| DELETE | `api/notifications/{notificationId}` | |

Real-time delivery also runs through a SignalR `NotificationHub`, not just polling — not represented as a REST route here.

### 8.2 Admin — `api/admin/notifications` (`NotificationAdminController`, `Roles=ADMIN`) — 40+ endpoints across 3 channels

A full admin-configurable multi-channel system — in-app templates, email templates, SMS templates, and per-channel provider configs (email/SMS/FCM) each with credential rotation and live test-send. Grouped by resource (all under `api/admin/notifications`):

| Resource group | Routes | Verbs |
|---|---|---|
| In-app templates | `templates/in-app`, `templates/in-app/{id}`, `templates/in-app/{id}/toggle` | GET (list/by-id), POST (create), PUT (update), PATCH (toggle) |
| Email templates | `templates/email`, `templates/email/{id}`, `templates/email/{id}/toggle` | same shape |
| SMS templates | `templates/sms`, `templates/sms/{id}`, `templates/sms/{id}/toggle` | same shape |
| Email provider config | `providers/email`, `providers/email/{id}`, `providers/email/active`, `providers/email/{id}/credentials`, `providers/email/{id}/toggle`, `providers/email/{id}/test-send`, `providers/email/test-configuration` | GET/POST/PUT/PATCH as applicable |
| SMS provider config | `providers/sms` (+ same sub-routes as email) | GET/POST/PUT/PATCH |
| FCM (push) provider config | `providers/fcm` (+ same sub-routes as email/SMS) | GET/POST/PUT/PATCH |

Real providers wired in: `AfromessageSmsChannelProvider`, `FirebasePushChannelProvider`, `SmtpEmailChannelProvider`.

---

## 9. MasterData / Reference / Admin-Config Controllers — `api/*`

All admin-authored master data used platform-wide. Most follow the same **versioned policy** shape: `versions` (list/create/update), `versions/{n}/activate`, `active` (currently-active version), `versions/{id}/rules` (list/create), `rules/{ruleId}` (update/delete).

| Controller | Base route | Notes |
|---|---|---|
| `CommissionStrategiesController` | `api/commission-strategies` | Versioned; drives provider commission-by-tier. |
| `ContractPoliciesController` | `api/contract-policies` | Versioned; drives early-termination penalty calc (§6.3). |
| `EscrowPoliciesController` | `api/escrow-policies` | Versioned. |
| `SettlementPoliciesController` | `api/settlement-policies` | Versioned. |
| `ContractTermsController` | `api/contract-terms` | `active` (by `sourceType`), `versions`, `versions/{id}` (get/create/update/activate/delete) — the terms text shown at dual-OTP signing (§5). |
| `BusinessTiersController` | `api/business-tiers` | GET (list)/POST (`Roles=ADMIN`), PUT/DELETE `{id}` (`Roles=ADMIN`). |
| `ProviderTiersController` | `api/provider-tiers` | Same CRUD shape, plus `POST providers/{providerId}/tier-assignment` (`Roles=ADMIN`) — manual tier assignment (the automatic `TrustScoreCalculator`/`TierCalculationService` paths are unwired in production — see epic-12). |
| `KYCRequirementsController` | `api/kyc-requirements` | GET (list, public), POST/PUT/DELETE `Roles=ADMIN`. |
| `DocumentTypesController` | `api/document-types` | Same shape. |
| `CountriesController` | `api/countries` | GET public; PUT/DELETE `Roles=ADMIN`. |
| `LookupTypesController` | `api/lookup-types` | GET public (paginated/filtered), POST/PUT/DELETE `Roles=ADMIN`; plus `{typeId}/lookups` and `by-code/{typeCode}/lookups` (GET public; POST/PUT/DELETE `Roles=ADMIN`) for the actual lookup values (e.g. `VEHICLE_TYPE`, `FUEL_TYPE`). |
| `SettingsController` | `api/settings` | GET (list, `Roles=ADMIN`), GET `{key}` (public), PUT `{key}` (`Roles=ADMIN`). |
| `PlatformBankAccountController` | `api/platform-bank-accounts` | GET only, **fully anonymous by design** ("businesses need to see bank details before logging in" — doc comment in code) — used to populate deposit-instruction UI. |
| `WebReferenceController` | `api/reference` | `GET api/reference/banks` — bank list for web forms. |
| `FileUploadController` | `api/files` | `POST api/files/upload` — multipart, generic document upload feeding the `documentTypeId`/`fileUrl` fields used elsewhere. |

### 9.1 Admin — `api/admin/*` surface not already covered above

| Controller | Base route | Notes |
|---|---|---|
| `AdminPlatformBankAccountController` | `api/admin/platform-bank-accounts` | Full CRUD + `PATCH {id}/status` (`Policy=AdminOnly`) — the accounts `PlatformBankAccountController` (§9) exposes publicly, read-only. |
| `AdminChecklistTemplateController` | `api/admin/checklist-template` | GET/POST/PUT + `PATCH {id}/activate`/`{id}/deactivate` (`Policy=AdminOnly`) — vehicle-inspection checklist templates used by Delivery (§7). |
| `AdminDirectRentalController` | `api/admin/direct-rental` | Admin can act **on behalf of** a business/provider: `GET vehicles`, `GET/POST/PATCH/DELETE businesses/{businessId}/cart(/items/{cartItemId})`, `GET businesses/{businessId}/cart/submit-preview`, `POST businesses/{businessId}/cart/submit`, `GET requests`, `GET requests/{requestId}`, `GET requests/{requestId}/history`, `POST requests/{requestId}/respond` — a full admin mirror of the business/provider Direct Rental flow (§4.5), all `Policy=AdminOnly`. |
| `AdminDepositRequestController` | `api/admin/deposit-requests` | See §6.4. |

---

## 10. Mobile API — `mobile/*` (19 controllers, ~150 endpoints, `Controllers/Mobile/*.cs`)

Both Flutter apps (business, provider) share this one surface — routes are role-agnostic; behavior branches on the authenticated user's type. Every controller below carries a class-level `[Authorize]` unless noted.

| Controller | Base route | Covers |
|---|---|---|
| `MobileAuthController` | `mobile/auth` | See §2.2. |
| `MobileMeController` | `mobile` | `GET mobile/me`, `GET mobile/provider/me`, `GET mobile/business/me` — "who am I" for whichever role is logged in. |
| `MobileOnboardingController` | `mobile/onboarding` | `business/register`, `business` (PUT), `business/step` (PATCH), `business/complete`, `business/contact-person` (PATCH), `business/address` (PATCH), `business/preferences` (GET/PATCH) — and the same shape under `provider/*`. |
| `MobileKYCController` | `mobile/kyc` | `business/documents` (POST/GET), `provider/documents` (POST/GET). |
| `MobileBankAccountController` (business) | `mobile/identity/businesses` | `me/bank-accounts` (GET/POST/current), dual-OTP change flow (`change/initiate`, `change/verify-email`, `change/verify-phone`, `change/resend-otp`, `change/cancel`), `me/bank-accounts/{id}` (DELETE), `{id}/set-primary` (PUT). |
| `MobileProviderBankAccountController` | `mobile/identity/providers` | Same shape as above, provider-scoped (`me/bank-accounts/{id}/verify-email`, `.../verify-phone`, `.../resend-otp` instead of the initiate/cancel flow — slightly different endpoint names from the business version, same intent). |
| `MobileRFQController` | `mobile/marketplace/rfqs` | `GET` (browse, business/provider both use this with different implicit filters), `GET recommended`, `GET my-rfqs`, `GET {id}`, `POST` (create), `PUT {id}`, `PATCH {id}/close`, `PATCH {id}/cancel`, `PUT {id}/publish`. |
| `MobileBidController` | `mobile/marketplace` | `POST bids`, `GET bids/my-bids`, `DELETE bids/{id}`, `GET rfqs/{rfqId}/bids`, `POST bids/{id}/award`, `GET rfq/awards/{awardId}/assignments`, `POST rfq/awards/{awardId}/vehicles`, `DELETE rfq/awards/{awardId}/vehicles/{vehicleId}` — full mobile mirror of the web RFQ/bid/award-assignment flow (§4.2–4.3). |
| `MobileProviderFleetController` | `mobile/marketplace/provider/fleet` | `GET capacity`, `POST capacity/bid-preview`, `GET action-items`, `GET rfq/awards/{awardId}/eligible-vehicles`. |
| `MobileVehicleController` | `mobile/vehicles` | `POST` (register), `GET my-vehicles`, `GET {id}`, `PUT {id}`, `POST {id}/photos`, `POST {id}/documents`, `POST {id}/insurance`, `PUT insurance/{insuranceId}`, `GET {id}/assignments`, `PUT {id}/maintenance-status`. **No Direct Rental enable/disable endpoints on the mobile surface** — those only exist on the web `VehicleController` (§3.3); see §11 for how mobile actually reaches Direct Rental. |
| `MobileContractController` | `mobile/contracts` | `GET my-contracts`, `GET {id}`, `GET {id}/vehicles`, `GET {contractId}/terms`, `POST {contractId}/terms/otp/generate`, `POST {contractId}/terms/otp/verify`, `GET {contractId}/line-items/{lineItemId}/available-vehicles`, `POST {contractId}/line-items/{lineItemId}/assign-vehicle`, `POST {contractId}/termination/request`, `POST {contractId}/termination/approve`, `GET {contractId}/completion/readiness`, `POST {contractId}/completion/request`, `POST {contractId}/completion/approve`, `POST {contractId}/completion/reject` — a near-complete mirror of the web `ContractsController` (§5), correctly `[Authorize]`-protected (unlike its web counterpart). |
| `MobileDeliveryController` | `mobile/delivery` | Full mirror of `api/delivery` (§7) — sessions, timeline, OTP generate/verify, returns, checklist submit/approve/reject (plus a provider-only `returns/checklists/{checklistId}/reject` for return checklists) — **and, unlike the web version, this one is `[Authorize]`-protected.** |
| `MobileWalletController` | `mobile/wallets` | `GET summary`, `GET balance`, `GET transactions` (supports a `contractId` filter the web UI doesn't expose), `GET verified-bank-accounts`, `POST withdrawal`, `GET withdrawals/my`, `GET settlements`, `GET settlements/{payoutId}`, `GET escrow-breakdown`, `GET upcoming-transactions`, `GET provider/upcoming-settlements`. 8+ distinct endpoints (older mobile spec docs undercounted this at 4). |
| `MobilePaymentController` | `mobile/payments` | `GET providers`, `POST intent`, `GET status/{transactionReference}` — mirrors §6.5's user-facing (non-webhook) endpoints; webhooks stay on `api/payments` since gateways call the web route regardless of client. |
| `MobileNotificationController` | `mobile/notifications` | `GET` (list), `GET summary`, `PUT {id}/read`, `PUT mark-all-read`, `DELETE {id}`, `POST push/rebind`, `POST push/unregister` — push-token lifecycle is mobile-only (naturally; there's no equivalent on web). Note: `push/rebind`/`push/unregister` is the real route pair — some mobile spec docs still describe a `POST mobile/me/devices` route that does not exist. |
| `MobileFileController` | `mobile/files` | `POST upload`, `POST upload-photo` — mirrors `api/files` (§9) with a photo-specific variant. |
| `MobileDashboardController` | `mobile/dashboard` | `GET stats` — role-aware (business vs. provider) dashboard stat cards. |
| `MobileReferenceDataController` | `mobile/reference` | `GET vehicle-types`, `fuel-types`, `rfq-terms`, `cities`, `business-types`, `industries`, `insurance-coverage-types`, `provider-types`, `banks`, `lookups/{typeCode}`, `all` — **no `[Authorize]` on this controller**, all public reference data. |
| `MobileCatalogueController` | `mobile/catalogue` | `GET vehicles`, `GET vehicles/{id}`, `POST cart-quote`, `GET rfqs`, `GET rfqs/{id}`, `GET bid-limits` — **`[AllowAnonymous]`**, rate-limited per IP; the guest-mode catalogue (§10.1). |

### 10.1 Guest Mode Endpoints (browse before sign-in)

**Full spec:** [MVP_GUEST_MODE_SPECIFICATION.md](./MVP_final_docs/MVP_GUEST_MODE_SPECIFICATION.md) §9 (request/response shapes, validation, outcomes). **Last verified against code: 2026-10-05**, backend branch `feature/mobile-guest-mode` (not yet merged to `development`).

Both apps call `mobile/catalogue/*` while signed out (no `Authorization` header) and two authenticated `api/...` endpoints to hand guest work to the account once it exists. Nothing here submits a cart or a bid.

| Method | Route | Auth | Purpose |
|---|---|---|---|
| GET | `mobile/catalogue/vehicles` | Anonymous, `mobile-guest` | Rentable direct-rental vehicles (`GetPublicVehiclesQuery`): `search`, `vehicleType`, `fuelType`, `minDailyRate`, `maxDailyRate`, `minSeatingCapacity`, `sortBy` (`dailyRentalRate`\|`year`), `sortDescending`, `pageNumber`, `pageSize` (1–50). No plate, VIN or provider identity; `providerCity` + opaque `providerRef`. |
| GET | `mobile/catalogue/vehicles/{id}` | Anonymous, `mobile-guest` | One vehicle; `404` when not listable. |
| POST | `mobile/catalogue/cart-quote` | Anonymous, `mobile-guest-write` | 1–20 `{vehicleId, startDate, endDate}` → per-item `OK`/`UNAVAILABLE`/`INVALID_DATES`, inclusive days, amounts, 30-day-capped escrow hold, provider groups (`Provider 1`, …). Reserves nothing. |
| GET | `mobile/catalogue/rfqs` | Anonymous, `mobile-guest` | Open RFQs, soonest deadline first: `vehicleType`, `fuelType`, `pickupCity`, `requiredFrom`, paging (1–50). No business identity, title, specifications or target price; lines carry `remainingQuantity`. |
| GET | `mobile/catalogue/rfqs/{id}` | Anonymous, `mobile-guest` | One open RFQ with line ids; `404` when it no longer takes bids. |
| GET | `mobile/catalogue/bid-limits` | Anonymous, `mobile-guest` | `{ minBidAmount }` — the minimum `SubmitBidCommand` enforces. |
| POST | `api/marketplace/cart/merge` | `[Authorize]`, `user_type == BUSINESS` | Merge the phone cart (1–20 items) into the business cart. Per item `ADDED` / `ALREADY_IN_CART` (server copy wins) / `INVALID_DATES` / `UNAVAILABLE`. Idempotent. `409 BUSINESS_PROFILE_REQUIRED` before the onboarding Company step. |
| POST | `api/marketplace/bid-drafts` | `Policy=ProviderUser` | Save a guest bid as saved bids (`{rfqId, items[{rfqLineItemId, unitPrice, quantity}], notes}`, 1–50 lines). Per line `SAVED` / `LINE_REMOVED` / `ALREADY_BID`. `409 PROVIDER_PROFILE_REQUIRED` before the onboarding Identity step; `422 RFQ_CLOSED`. |

**Rate limits** (`Program.cs`, per client IP, 1-minute sliding window): `mobile-guest` 120 requests/min, `mobile-guest-write` 30 requests/min; a rejection is `429` with `Retry-After: 60`. These named limiter policies (and the `public-*` policies of the website API) post-date §1.6 above.

**Coded errors** used by guest mode are written by `GlobalExceptionHandlerMiddleware` as `ErrorResponse` with a top-level `code` (`CodedConflictException` → `409`, `CodedRuleException` → `422`). `AddToCartCommand` (`POST api/marketplace/cart/items`) now fails with `422` and `VEHICLE_UNAVAILABLE`, `ALREADY_IN_CART` or `INVALID_DATES`.

---

## 11. Route-Prefix Exceptions — Mobile Clients Calling `api/...` Directly

The Mobile API surface (§10) does **not** cover everything both Flutter apps need. Where no `mobile/...` equivalent exists, both apps call the **web/admin `api/...` routes directly**, bypassing the `mobile/` prefix entirely. Verified by grepping both apps' `lib/**/data/services/*.dart` for literal `'api/...'` string routes (not `mobile/...`):

| Feature area | Real routes called directly from mobile | Why there's no mobile equivalent |
|---|---|---|
| **Direct Rental** (both apps) | `api/marketplace/direct-rental/requests`, `api/marketplace/direct-rental/vehicles`, `api/marketplace/cart`, `api/marketplace/cart/items`, `api/marketplace/cart/submit-preview`, `api/marketplace/cart/submit` | No `Mobile*` controller for Direct Rental exists at all — §4.5's `DirectRentalCartController`/`DirectRentalRequestController`/`DirectRentalVehicleController` are called as-is from both `business_app` and `provider_app`. |
| **Provider fleet capacity extras** (provider app) | `api/marketplace/provider/fleet/capacity`, `api/marketplace/provider/fleet/capacity/bid-preview`, `api/marketplace/provider/fleet/action-items` | `MobileProviderFleetController` (§10) only exposes `capacity`/`capacity/bid-preview`/`action-items`/`eligible-vehicles` under `mobile/marketplace/provider/fleet` — yet the provider app's `provider_fleet_capacity_service.dart` calls the **web** `ProviderFleetController` routes instead of the mobile ones for this specific service file (both routes exist and return equivalent data; this app is just using the non-mobile one here). |
| **Guest-mode hand-over** (both apps) | `api/marketplace/cart/merge` (business app); `api/marketplace/bid-drafts` (POST, GET), `api/marketplace/bid-drafts/{id}`, `.../{id}/readiness`, `.../{id}/submit` (provider app) | The merge lives on `DirectRentalCartController` and saved bids on `BidDraftController`, both shared with the website; there is no mobile mirror. See §10.1 and `MVP_final_docs/MVP_GUEST_MODE_SPECIFICATION.md`. |
| **Provider invoices** (provider app) | `api/finance/invoices` | No `MobileProviderInvoiceController`/mobile route exists — `ProviderInvoiceController` (§6.7) is called directly. |
| **Onboarding reference data** (both apps) | `api/kyc-requirements`, `api/document-types` | These specific reference lists aren't mirrored under `mobile/reference` (§10's `MobileReferenceDataController` covers vehicle/fuel/business types, cities, banks, lookups — but not KYC requirements or document types), so onboarding screens call the public web routes (§9) directly. |
| **Bank-transfer deposits** (business app) | `api/finance/deposit-requests`, `api/finance/deposit-requests/my`, `api/platform-bank-accounts` | No `MobileDepositRequestController`/mobile deposit route exists — the business app's bank-transfer deposit screens call `DepositRequestController` and `PlatformBankAccountController` (§6.4, §9) directly. Automated-gateway deposits *do* have a mobile route (`mobile/payments/intent`, §10). |
| **RFQ vehicle/fuel-type lookups** (business app, one call site) | `api/lookups/type/VEHICLE_TYPE`, `api/lookups/type/FUEL_TYPE` | One RFQ-repository call site in the business app hits a `lookups/type/{code}` shape rather than `MobileReferenceDataController`'s `mobile/reference/lookups/{typeCode}` — same data, different (non-mobile) path; worth normalizing to the mobile route since it already exists. |

**Implication for anyone building or testing an API client against this backend:** the mobile apps are not a clean "everything under `mobile/`" client — treat the `mobile/*` prefix as the *primary* surface for mobile work, but expect several real, load-bearing calls to land on plain `api/...` routes, most of which happen to be publicly-reference-data or Direct-Rental related.

---

## 12. Error Handling — Reality, Not the Old Envelope

There is **no** global `{success, error: {code, message, details}}` envelope. Responses vary by handler:

- **Validation/business-rule failures:** most commonly a plain object, e.g. `BadRequest(new { message = "..." })` or `NotFound(new { message = "..." })`. Some flows return richer shapes for a specific UI need — e.g. the award-shortfall error on `POST api/marketplace/bids/award` embeds an affordability hint directly in the exception message text, not a structured `details` array.
- **Unhandled exceptions:** fall through to ASP.NET Core's default developer/production exception behavior (no custom global exception-to-JSON middleware was found wrapping every controller).
- **Auth failures:** standard ASP.NET Core `401`/`403` from the authentication/authorization middleware — `AuthController.Login` additionally distinguishes `403` sub-cases with `accountBlocked: true` or `requiresVerification: true` flags in the body for the frontend to branch on.
- **Webhook signature failures:** `401` (Chapa/Telebirr/CBE Birr webhook signature validation, §6.5).

Do not build a client that assumes a `success`/`data` envelope on every response — inspect the HTTP status code and treat the body as the raw resource (or a raw `{ message }`/`{ error }` shape) instead.

---

## 13. Auth Reference — Attribute Styles In Use

Two different declarative styles coexist for the same intent, plus the manual-claim-check pattern described in §1.5:

| Style | Example | Meaning |
|---|---|---|
| `[Authorize(Roles = "ADMIN")]` | `VehicleController`, `BusinessController`, most MasterData controllers | Requires the `ADMIN` role claim (also accepts lowercase `admin` in some places via the Keycloak role-claim mapping). |
| `[Authorize(Policy = "AdminOnly")]` | `WithdrawalController`, `AdminWalletController`, most `Admin/*` controllers | Requires the registered `AdminOnly` policy (`RequireRole("admin", "ADMIN")` — functionally equivalent to the above, just declared differently). |
| `[Authorize(Policy = "ProviderUser")]` / `"BusinessUser"` / `"BusinessOrProvider"` | `VehicleController.GetVehicleAssignments`, a handful of others | Registered policies allowing the named role(s) **or** admin. |
| Bare `[Authorize]` + manual `User.FindFirstValue("user_type")` check in the action body | `RFQController`, `BidController`, `DirectRentalCartController`, `DirectRentalRequestController`, `RfqAwardController` | Any authenticated user can reach the action; the handler itself `Forbid()`s if the caller's `user_type` doesn't match what the operation requires. This is real access control, just not visible from the attribute alone. |
| No attribute at all, and no global fallback policy | `DeliveryController` (all actions), `ContractsController.GetContractsByBusinessId`/`GetContractsByProviderId` | **Anonymous access** — see the verified gaps in §1.5. |
