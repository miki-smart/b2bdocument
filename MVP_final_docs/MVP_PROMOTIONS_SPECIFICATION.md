# Anqelba Car Rental MVP — Promotions Specification
## Hot Deals (vehicles) & Featured Listings (vehicles and RFQs) — Version 1.0

**Document Status:** AUTHORITATIVE (design) — decided by the business owner on 2026-10-07; implementation in progress. Re-verify every section against code once the backend PRs (§12) are merged to `development`.

**Related documents:**
- [MVP_AUTHORITATIVE_BUSINESS_RULES.md](./MVP_AUTHORITATIVE_BUSINESS_RULES.md) §20 — the rules in short form (`BR-PROMO-*`)
- [MVP_DIRECT_RENTAL_SPECIFICATION.md](./MVP_DIRECT_RENTAL_SPECIFICATION.md) — cart, submit and request lifecycle a deal price flows through
- [MVP_GUEST_MODE_SPECIFICATION.md](./MVP_GUEST_MODE_SPECIFICATION.md) — the public (signed-out) app pages that show promotions
- Design: "Anqelba Public Discovery" canvas (business public Vehicles and provider public Market, search open and closed)

---

## 1. Purpose & Scope

Promotions make the public pages attract people: businesses come for **Hot deals** and **Featured vehicles**, providers come for **Featured RFQs**. Both are shown on every public surface — the marketing website, the web portal and both mobile apps — and on the signed-in browse screens.

| Promotion | Applies to | Who creates it | Goes live when |
|---|---|---|---|
| **Hot deal** | A direct-rental vehicle | The vehicle's **provider** proposes a lower daily rate for a date range | An **admin approves** it and its start date arrives |
| **Featured** | A direct-rental vehicle or an open RFQ | An **admin** picks it, with an order and an optional end date | Immediately (or at its start time) |

**Out of scope (later):** paid promotion (the featured model reserves `Source = PAID`), deals on RFQs, coupon codes, notifications to businesses about deals.

## 2. Hot Deals

### 2.1 Lifecycle

```
PENDING_REVIEW ──approve──▶ APPROVED ──end date passes──▶ EXPIRED
      │                        │
      │                        ├──admin ends──▶ ENDED
      │                        ├──provider withdraws──▶ WITHDRAWN
      │                        └──vehicle stops being rentable / rate changed by admin──▶ ENDED
      ├──admin rejects (reason)──▶ REJECTED
      ├──provider withdraws──▶ WITHDRAWN
      └──end date passes before review──▶ EXPIRED
```

"Scheduled" (approved, start date in the future) and "live" (approved, inside its dates) are **derived**, not stored.

### 2.2 Proposal rules (provider)

1. The provider owns the vehicle and the vehicle is **rentable** (the shared `RentableVehicles` rule: `APPROVED`, active, not in maintenance, direct rental on, rate > 0, provider `VERIFIED`).
2. **Deal rate** < normal rate, and the discount is at least `HOT_DEAL_MIN_DISCOUNT_PERCENT` (default **10%**): `dealRate ≤ normalRate × (1 − min%)`.
3. **Dates** are Addis Ababa calendar days: start is today or later and at most `HOT_DEAL_MAX_LEAD_DAYS` (default **30**) ahead; end ≥ start; length (end − start + 1) at most `HOT_DEAL_MAX_DURATION_DAYS` (default **14**).
4. **One open deal per vehicle** (`PENDING_REVIEW` or `APPROVED`); a second proposal is refused with `HOT_DEAL_ALREADY_OPEN`.
5. The normal rate at the time of the proposal is stored (`NormalRateAtProposal`) for the record.

### 2.3 Review (admin)

- **Approve:** every proposal rule is checked again against the vehicle's current rate and state, and the end date must still be in the future.
- **Reject:** a reason is required; the provider sees it and may propose again.
- **End:** an approved (scheduled or live) deal can be ended early with a reason.

### 2.4 What changes while a deal is open

- The **provider cannot change the vehicle's normal rate** while a deal is open (`HOT_DEAL_OPEN`) — the struck-through price must stay honest. They withdraw the deal first.
- An **admin** rate change or turning direct rental off **ends** the deal (`RATE_CHANGED`, `DIRECT_RENTAL_DISABLED`).
- A vehicle that stops being rentable (maintenance, blocked, provider no longer verified) loses its deal (`VEHICLE_UNAVAILABLE`).

### 2.5 Live definition

A deal is **live** when: `APPROVED`, now ≥ start (00:00 Addis on the start day) and now < end (00:00 Addis on the day after the end day), the vehicle is rentable, and the deal rate is still below the normal rate. Every read applies this test, so a deal never shows or prices after it ends even if the expiry job has not run yet.

## 3. Pricing with a Hot Deal

- The **effective daily rate** of a vehicle is the live deal rate, else its normal rate. One pricing service computes it for every read and write.
- A deal live **when the business submits** prices the **whole** rental, even if the rental runs past the deal's end. The 30-day escrow cap and day counting (end date excluded) are unchanged.
- **Cart:** adding a vehicle stores the effective rate, the deal id and the normal rate. Changing the dates refreshes them.
- **Re-price at submit (decision 2026-10-07):** the cart, the submit preview and submit always use the **current** effective rate. If a deal ended (or the normal rate changed) since the vehicle was added, the cart and preview flag the item (`priceChanged`, reason `DEAL_ENDED` / `RATE_CHANGED`) and show old vs new rate. Clients send the total they showed (`expectedTotalAmount`); if it no longer matches, submit returns **409 `CART_PRICE_CHANGED`** with the changes, and the client shows them before the business confirms again. A client that sends no expected total gets the request at the re-priced amounts.
- **Request and contract:** the request vehicle stores the charged rate (`DailyRate`), the normal rate and the deal id. Contract value, escrow, early delivery, ledger and settlement work from the charged rate exactly as before.
- The **guest cart quote** prices with the effective rate.

## 4. Featured Listings

- **Targets:** a vehicle that is rentable (as for listing in the catalogue) or an RFQ that is open for bids (`PUBLISHED`, `BIDDING` or `PARTIALLY_AWARDED` with a future deadline).
- **Created by an admin** with a sort order (lower first), a start (default now) and an optional end. At most `FEATURED_MAX_VEHICLES` / `FEATURED_MAX_RFQS` (default **12** each) active at a time; a target is featured at most once at a time.
- **Shown only while the target still qualifies**: an RFQ drops out when its deadline passes or it is awarded or cancelled; a vehicle drops out when it is no longer rentable. The expiry job then ends the row (`TARGET_NOT_LISTABLE`).
- **Ending:** an admin removes it, or its end date passes (`EXPIRED`).
- Featured does **not** change price or ranking in the normal lists; it only adds the item to the Featured section and a "Featured" badge.

## 5. What Each Surface Shows

| Surface | Hot deals | Featured |
|---|---|---|
| **Business app** public Vehicles (and signed-in browse) | "Hot deals" carousel (discount badge, deal price, normal price struck through, "Ends in N days"); deal badge on cards in the list; detail and cart use the deal price | "Featured vehicles" carousel, Featured badge |
| **Provider app** public Market (and signed-in Market) | — | "Featured RFQs" carousel (order size, deadline, Place bid), Featured badge |
| **Provider app** fleet vehicle | Propose a deal, see its status/reason, withdraw | — |
| **Website** home, `/fleet`, `/rfqs` | Hot deals strip and `/fleet` section; card badge, struck-through price, ends-in; booking panel uses the deal price | Featured vehicles (replaces today's round-robin pick, which stays as a fallback when nothing is featured); Featured RFQs on `/rfqs` |
| **Portal** — provider | Propose/withdraw on the vehicle's Direct rental card | — |
| **Portal** — business | Deal price and badge in browse; price-change banner in the cart | Featured badge |
| **Portal** — admin | "Hot deals" page: Pending / Live / Scheduled / Ended; Approve, Reject (reason), End | "Featured" page: Vehicles / RFQs; add, reorder, set end date, remove; "Feature" action on the RFQ and vehicle admin pages |

Search on the public app pages is a glass icon that opens a search field and an advanced filter panel with **"Hot deals only"** / **"Featured"** chips and the sorts **"Biggest saving"** (vehicles) and **"Biggest order"** (RFQs).

## 6. Data Model

**`marketplace.vehicle_hot_deals` (`VehicleHotDeal`)** — `Id`, `VehicleId`, `ProviderId`, `DealDailyRate`, `NormalRateAtProposal`, `StartDate`, `EndDate` (Addis days), `StartsAtUtc`, `EndsAtUtc` (derived), `Status`, `RejectionReason`, `ReviewedBy`, `ReviewedAt`, `EndedBy`, `EndedAt`, `EndReason`, audit fields. Filtered unique index on `VehicleId` for open deals; index on `(Status, EndsAtUtc)`.

**`marketplace.featured_listings` (`FeaturedListing`)** — `Id`, `TargetType` (`VEHICLE` | `RFQ`), `TargetId`, `SortOrder`, `StartsAtUtc`, `EndsAtUtc?`, `Status` (`ACTIVE` | `ENDED` | `EXPIRED`), `Source` (`ADMIN`; `PAID` reserved), `CreatedBy`, `EndedBy`, `EndedAt`, `EndReason`. Filtered unique index on `(TargetType, TargetId)` where `ACTIVE`.

**New columns:** `HotDealId?`, `NormalDailyRate?` on `direct_rental_cart_items` and `direct_rental_request_vehicles` (`DailyRate` stays the charged rate).

**Settings** (`masterdata.settings`, seeded if missing): `HOT_DEAL_MIN_DISCOUNT_PERCENT` = 10, `HOT_DEAL_MAX_DURATION_DAYS` = 14, `HOT_DEAL_MAX_LEAD_DAYS` = 30, `FEATURED_MAX_VEHICLES` = 12, `FEATURED_MAX_RFQS` = 12.

## 7. API

**Provider** (policy `ProviderUser`; the apps and the portal use the same paths)

| Method | Path | Purpose |
|---|---|---|
| GET | `api/identity/vehicles/{id}/hot-deals` | Current deal, history and the limits |
| POST | `api/identity/vehicles/{id}/hot-deals` | Propose `{dealDailyRate, startDate, endDate}` |
| POST | `api/identity/vehicles/{id}/hot-deals/{dealId}/withdraw` | Withdraw a pending or approved deal |

**Admin** (policy `AdminOnly`)

| Method | Path | Purpose |
|---|---|---|
| GET | `api/admin/hot-deals?status=` | List deals (`PENDING_REVIEW`, `LIVE`, `SCHEDULED`, `ENDED`) |
| POST | `api/admin/hot-deals/{id}/approve` · `/reject {reason}` · `/end {reason}` | Review and end |
| GET | `api/admin/featured?targetType=` | Active featured rows with target summaries |
| POST | `api/admin/featured` | `{targetType, targetId, sortOrder, startsAt?, endsAt?}` |
| PUT / DELETE | `api/admin/featured/{id}` | Change order or end date / end it |

**Catalogue** — the same additions on `mobile/catalogue/*` (anonymous) and `api/public/*` (website API key), and on the signed-in browse:

| Method | Path | Notes |
|---|---|---|
| GET | `vehicles/hot-deals?limit=10` | Live deals: biggest saving first, then ending soonest |
| GET | `vehicles/featured?limit=10` | By sort order |
| GET | `rfqs/featured?limit=10` | By sort order |
| GET | `vehicles?hotDealsOnly=&featuredOnly=&sortBy=saving` | New filters and sort |
| GET | `rfqs?featuredOnly=&sortBy=deadline\|orderSize` | `orderSize` = most vehicles first |

**Vehicle DTOs** (public and signed-in): `dailyRentalRate` is the **effective** rate (older clients keep pricing correctly); new `normalDailyRate`, `hotDeal { id, dealDailyRate, discountPercent, endsAt }?`, `isFeatured`. **RFQ DTOs:** new `isFeatured`.

**Cart:** items gain `currentDailyRate`, `priceChanged`, `priceChangeReason`, `hotDealEndsAt`; the submit preview gains `priceChanges[]`; submit accepts `expectedTotalAmount` and may return 409 `CART_PRICE_CHANGED`.

**Error codes:** `HOT_DEAL_ALREADY_OPEN`, `HOT_DEAL_OPEN` (rate change blocked), `HOT_DEAL_DISCOUNT_TOO_SMALL`, `HOT_DEAL_DATES_INVALID`, `HOT_DEAL_VEHICLE_NOT_RENTABLE`, `HOT_DEAL_NOT_REVIEWABLE`, `FEATURED_TARGET_NOT_LISTABLE`, `FEATURED_LIMIT_REACHED`, `FEATURED_ALREADY_ACTIVE`, `CART_PRICE_CHANGED`.

## 8. Expiry Job

`PromotionsExpiryJob` (every 5 minutes): deals past their end → `EXPIRED`; open deals on vehicles no longer rentable → `ENDED` (`VEHICLE_UNAVAILABLE`); featured rows past their end → `EXPIRED`; featured rows whose target no longer qualifies → `ENDED` (`TARGET_NOT_LISTABLE`). Reads never depend on it (§2.5, §4).

## 9. Notifications

| Event | To | Channels |
|---|---|---|
| Deal proposed | Admins | In-app |
| Deal approved | Provider | In-app/push, email |
| Deal rejected (with reason) | Provider | In-app/push, email |
| Deal ended by an admin / rate changed / vehicle unavailable | Provider | In-app/push |
| Deal expired | Provider | In-app |

Businesses are not notified about deals in this version.

## 10. Security and Fairness

- Providers act only on their own vehicles; admins only through `AdminOnly` endpoints.
- Public DTOs keep guest redaction (no provider name or plate for guests).
- The struck-through price is the real normal rate: the provider cannot raise it during a deal.
- Prices are always computed by the server; clients only display them.

## 11. Known Limits

- Deals are per vehicle only (no fleet-wide or vehicle-type deals).
- No paid featuring yet; no impressions/click tracking.
- Website pages cache catalogue data for up to 60 seconds, so a just-ended deal may show briefly; the price is re-checked at submit.

## 12. Delivery Plan

1. **Backend 1 — Hot deals core:** entity, migration, settings, provider and admin endpoints, rate-change guard, expiry job (deals), notifications. Prices unchanged.
2. **Backend 2 — Effective pricing:** pricing service, DTO fields, hot-deals catalogue endpoint and filters, cart/quote/preview/submit re-pricing, `CART_PRICE_CHANGED`.
3. **Backend 3 — Featured:** entity, migration, admin endpoints, featured catalogue endpoints, flags and filters, `orderSize` sort, expiry job (featured).
4. **Clients** after their backend PR: portal (admin pages, provider deal form, business browse and cart), website, business app, provider app.

Backend PRs are merged to `development` one at a time (shared Keycloak hazard).
