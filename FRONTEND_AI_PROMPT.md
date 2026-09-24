# Frontend Reference — Anqelba Car Rental B2B Mobility Marketplace (as built)

**Last verified against code: 2026-07-23**

> **Reframing notice.** This document was originally written as an **AI-generation build prompt** — literal instructions for an AI tool to scaffold a brand-new frontend from scratch, targeting **Next.js 14 (App Router)** with **local JSON files as a mock database** (`src/data/*.json`, a hand-rolled `MockService`, simulated 500ms network delays). **None of that was ever the real implementation.** The actual frontend, `marketplace-project-implementation/anqelbacarrental-marketplace-core/`, is a **React 18.3 + Vite 6 + TypeScript** single-page app that talks to a real **.NET 9 modular-monolith API** over cookie-authenticated HTTP — there is no mock JSON data layer anywhere in the shipped app, and it has evolved well beyond anything a from-scratch AI prompt would produce (dual-OTP contract e-signature, a 17-status contract lifecycle, per-line-item split awards, a full parallel "Direct Rental" fixed-price booking product, admin-configurable multi-channel notifications, live payment-gateway webhooks, and more).
>
> Rather than delete this document, it has been rewritten as an **as-built reference**: the page-by-page breakdown, business-logic patterns (blind bidding, split awards, OTP flow, escrow checks), and design-system intent are still useful documentation of what the UI does and why — they have simply been corrected to describe the real React/Vite/TanStack-Query/.NET stack and the real page set, instead of a hypothetical Next.js/mock-JSON prototype. Where this document and code disagree in the future, trust the code (`src/`) and `project-docs/18_Implementation_Coverage_Audit.md`.

---

## 1. Real Tech Stack

- **Framework:** React 18.3.1, function components + hooks only (no class components)
- **Build:** Vite 6.4 (`@vitejs/plugin-react-swc`)
- **Language:** TypeScript 5.8, strict mode — no `any`
- **Router:** React Router DOM 6.30, one flat route table in `src/App.tsx`
- **Server state:** TanStack React Query 5.83 (`useQuery`/`useMutation`) — this is what replaces the original prompt's "local JSON + MockService" idea. Every RFQ, bid, contract, wallet balance, and verification record comes from a real API call through a query hook, not a JSON file.
- **Global client state:** Zustand 5.0.9, exactly 3 stores — `useAuthStore`, `useNotificationStore`, `direct-rental-store` (cart/browse UI only)
- **Forms:** React Hook Form 7.61 + Zod 3.25 (`zodResolver` on every form)
- **UI:** Radix UI + shadcn/ui conventions (`src/components/ui/`), Tailwind CSS 3.4, `lucide-react` icons, Recharts (dashboard-embedded charts only), Framer Motion (selective), Sonner (toasts)
- **HTTP:** Axios 1.13 via one hand-written `ApiClient` (`src/shared/lib/api-client.ts`) — `withCredentials: true` (httpOnly session cookies, never a bearer token or `localStorage` token)
- **Real-time:** Microsoft SignalR 10 against `/hubs/notifications`, wrapped inside `useNotificationStore`
- **Push:** Firebase FCM 12
- **Backend:** .NET 9 modular monolith (8 modules), not a JSON file store, not a separate BFF microservice — default local API base is `http://localhost:5207`

There is **no Next.js anywhere in this codebase** — no App Router, no Server Actions, no `src/data/*.json` mock database. See `.agent/roles/frontend-developer.md` and `markdown-documentations/Frontend_Architecture_Guide.md` for the fuller architecture reference.

---

## 2. Design System (as actually implemented, `src/index.css` + `tailwind.config.ts`)

The original prompt's blue/slate palette was **never implemented**. The real design tokens are HSL CSS custom properties consumed via Tailwind's `hsl(var(--token))` pattern, with a light and dark theme (`.dark` class):

```css
/* Primary — Deep Teal (Trust & Reliability) */
--primary: 185 64% 34%;          /* #1b7f82-ish teal, not blue-600 */
--primary-foreground: 0 0% 100%;
/* + a 50–700 tint/shade scale: --primary-50 … --primary-700 */

/* Secondary — Warm Orange (Action & Energy) */
--secondary: 28 100% 54%;
--secondary-foreground: 0 0% 100%;

/* Semantic */
--success: 142 76% 36%;
--warning: 38 92% 50%;
--destructive: 0 72% 51%;
--info: 199 89% 48%;

--background: 210 20% 98%;
--foreground: 220 25% 12%;
--card: 0 0% 100%;
--muted: 210 15% 94%;
--border: 214 18% 88%;
--radius: 0.625rem;

/* Dark mode sidebar tone even in light mode — the app ships a permanently dark sidebar look */
--sidebar-background: 220 25% 10%;
--sidebar-foreground: 210 15% 85%;
```

Dark mode (`.dark`) redefines `--primary`, `--background`, `--card`, etc. to lighter/darker equivalents — `darkMode: ["class"]` in `tailwind.config.ts`.

**Typography:** Two font families, both loaded from Google Fonts in `index.css`:
- **Body:** `Inter` (weights 300–800) — `font-sans`
- **Headings (`h1`–`h6`) and anything using `.font-display`:** `Plus Jakarta Sans` (weights 400–800) — `font-display`, applied automatically to all heading tags via `@layer base`

**Shadows & motion:** custom `--shadow-sm/md/lg/xl/card/glow` tokens (not default Tailwind shadows), plus named gradients (`--gradient-primary`, `--gradient-secondary`, `--gradient-hero`, `--gradient-mesh`) and keyframe utilities (`fade-in`, `slide-up`, `slide-down`, `scale-in`, `shimmer`) wired into `tailwind.config.ts`'s `keyframes`/`animation` extension.

**Do not use** `#2563EB`/blue-600 as the primary color, `bg-slate-900` sidebars styled ad hoc, or plain Tailwind default shadows/border-radius when documenting or designing new screens for this app — use the CSS custom properties above via the existing Tailwind color/shadow/radius tokens (`bg-primary`, `text-primary-foreground`, `shadow-card`, `rounded-lg`, etc.).

---

## 3. Real Page Set (by portal, verified against `src/features/*/pages/`)

The original prompt's "45 pages, JSON-backed" list does not match the shipped app. The real page set (folder-level, several folders contain multiple route components):

### Public / Auth (`src/features/auth/pages/`)
Login, Register, Verify Email, Verify Phone, Forgot Password. (No standalone marketing landing page lives in this SPA's route table beyond a couple of top-level `src/pages/` entries — `Index`, `NotFound`, `ComponentShowcase`.)

### Onboarding (`src/features/onboarding/pages/`)
- **Business onboarding:** a 3-step wizard (business details → contact/address → document upload).
- **Provider onboarding:** a **type-preselect step plus 3 further steps** (provider type choice, then details/contact/fleet-estimate, document upload, vehicle registration) — richer than a flat "3 steps," and self-documented as such in the mobile design docs too.

### Business Portal (`src/features/business/pages/`)
- `dashboard/` — wallet balance, active contracts, recent RFQs.
- `rfq/` — `create/` (multi-step, line-item wizard — RFQs are **header + `RFQLineItem[]`**, i.e. multiple vehicle types/terms per RFQ, not one vehicle-type/date-range per RFQ), `list/`, `detail/`, `bids/` (bid review with **per-line-item split awards** via `SplitAwardDialog` — multiple providers can each win part of the same line item's quantity).
- `contracts/` — list, detail, delivery, return checklist, `ExtendContractDialog` (contract **extension**, not "renewal as a new contract" — there is no `renew` endpoint or flow anywhere).
- `wallet/` — `BusinessWalletPage`, `BusinessEscrowWalletPage`, `DepositHistoryPage`.
- `direct-rental/` — browse, vehicle detail, cart, requests, request detail: a **fixed-price, non-bidding** vehicle booking flow that runs in parallel to the RFQ marketplace. This whole feature area did not exist in the original prompt's page list at all.
- `profile/`, `notifications/`.

### Provider Portal (`src/features/provider/pages/`)
- `dashboard/`, `marketplace/` (RFQ browse + bid submission — provider bids **at the fleet/quantity level**, not against a specific vehicle), `bids/` (my bids **and award-assign** — after an award, the provider goes through a separate post-award vehicle-assignment step, the same pattern used on both mobile apps), `fleet/` (vehicle registration, fleet capacity overview, fleet-capacity conflict checking against Direct Rental commitments), `contracts/` (assign vehicles, delivery), `wallet/` (earnings, settlements, invoices), `direct-rental/` (requests, response), `profile/`, `notifications/`.

### Admin Portal (`src/features/admin/pages/`)
This entire portal was reduced to "3 pages" in the original prompt; the real admin surface is the largest in the app:
- `dashboard/`
- `operations/` — act on RFQs, bids, contracts, settlements, wallets, and Direct Rental on behalf of users
- `verifications/` — business/provider/vehicle KYC-KYB queues
- `users/`
- `wallets/` — `AllWalletsPage`, `AdminWalletDetailPage`, `PlatformWalletDashboard`, `EscrowWalletManagementPage`, `EscrowTransactionsPage`, `WithholdingTaxPage`, `PlatformAccountManagementPage`, `AdminBusinessEscrowWalletsPage`
- `settlements/`
- `master-data/` — tiers, escrow/contract/settlement policies, commission strategies, rules, lookups, geography, banks, platform bank accounts, checklist templates, contract-terms templates
- `notifications/` — channel-provider config (email/SMS/FCM credentials + live test-send) + template management

There is no page anywhere with a `/step-1`/`/step-2` URL segment as the original numbered list implied — multi-step flows are wizard components within one route, not separate routed pages per step.

---

## 4. Business Logic Patterns (corrected)

These patterns are worth preserving from the original prompt because they describe real product behavior — the *shape* of the logic is right, but it runs against the real API through a service + React Query hook, never against an in-memory JSON array or `localStorage`.

### 4.1 Blind bidding
Bids are shown to the business without provider identity until an award is made. **Caveat verified against the platform-wide audit:** on the backend, `GetBidsByRFQQuery`/`GetBidQuery` set `providerName` unconditionally regardless of award status — blind bidding is enforced by the **web UI simply not rendering the field**, not by the API withholding it. Do not assume the wire payload itself is blind.

```typescript
// Pattern: the UI renders a masked label, the API response already has the real name present
const displayName = isAwarded ? bid.providerName : maskProviderLabel(bid.providerId);
```

### 4.2 Split award validation (per line item, real shape)
```typescript
// AwardItem[] sent to POST /rfq/awards — one RFQ line item can have multiple AwardItems,
// one per winning provider, via SplitAwardDialog.tsx
const totalAwarded = awardItems
  .filter((a) => a.lineItemId === lineItemId)
  .reduce((sum, a) => sum + a.quantityAwarded, 0);

if (totalAwarded > lineItem.quantityRequired) {
  throw new Error('Cannot award more than the required quantity for this line item');
}
```
After award (any surface, including web) there is a **separate post-award vehicle-assignment step** — `GET /rfq/awards/{awardId}/eligible-vehicles`, `POST`/`DELETE /rfq/awards/{awardId}/vehicles` — handled by `AwardAssignPage.tsx`/`AwardVehicleAssignmentPanel.tsx`. This is not a web-only or mobile-only pattern; it is the same three-phase flow (bid at quantity level → award, possibly split → assign specific vehicles) across web and both mobile apps.

### 4.3 Escrow / wallet check at award time
The shape (compute required escrow, compare to available balance, offer a reduced-quantity or top-up path) is real, but it runs through `wallet-service.ts`/`finance-service.ts` against the live backend wallet, not a `wallets.json` mutation. A real business rule not in the original prompt: `SplitAwardDialog.tsx` surfaces a **30-day escrow-lock cap** — not documented in any epic doc, confirmed in the audit.

### 4.4 Contract signing — dual-party OTP e-signature (not a canvas signature)
The original prompt's "Sign Contract" page (checkbox or signature canvas) does not match reality. The real flow is a **dual-party OTP e-signature step** — both business and provider must generate and verify an OTP (`terms/otp/generate` / `terms/otp/verify`) before the contract moves `PendingSigning → Signed`. This is a **separate mechanism from delivery OTP** (§4.5) — do not conflate the two in any future spec.

### 4.5 Delivery OTP — plus a return-trip OTP + inspection checklist the prompt never covered
```typescript
// Shape is still useful, but this now talks to a real delivery-service.ts endpoint,
// and there is a second, symmetric return-trip flow with its own OTP + a
// vehicle inspection checklist (ReturnChecklistPage.tsx + VerificationChecklist.tsx)
// that the original prompt never anticipated at all.
```
OTP codes are never returned in any API response body (by design, not an oversight) — the frontend never has access to the code to pre-fill or display for debugging.

### 4.6 Contract lifecycle — correct the "Suspended"/"renew" assumptions entirely
The original prompt's implicit model (`PENDING_DELIVERY → ACTIVE → COMPLETED`, plus an implied suspend-on-insufficient-funds and a renew-as-new-contract flow) is wrong on both counts. The real, running system produces 18 distinct string values for `Contract.Status` (it is a plain string column, not enum-driven in practice) — **there is no "Suspended" status anywhere**, and there is **no `renew` endpoint**; "renewal" on the web is contract **extension** (`ExtendContractDialog.tsx`, lengthens the existing contract's end date). See `MVP_final_docs/MVP_CONTRACT_STATE_MACHINE.md` for the full reachability table.

### 4.7 Early return / extension proration
The proration math (days used vs. remaining, tier-scaled penalty rate) is a real pattern worth keeping, but verify current tier/penalty numbers against `markdown-documentations/Master_Data_Specification.md` and the admin master-data policy pages before hardcoding percentages in any new doc or mock — they are configurable, versioned master-data records (`ContractPolicyVersion/Rule`), not fixed constants.

---

## 5. What This Document No Longer Claims

To avoid re-introducing the errors this rewrite corrects:
- No Next.js App Router, no Server Actions, no file-system-based routing.
- No `src/data/*.json` mock database, no `MockService`, no simulated `setTimeout` delays standing in for a real API.
- No canvas/checkbox-only contract signature — it's dual-party OTP.
- No "Suspended" contract status, no "renew as new contract" flow.
- No flat single-vehicle-type RFQ model — RFQs are header + line items.
- No blue-600/slate-900 default palette — the real tokens are the deep-teal/warm-orange HSL system in `src/index.css`.
- No 3-page admin portal — admin is the largest portal in the app (8 page groups, dozens of screens).

For implementation-level detail (services, hooks, `ProtectedRoute`, red-flag review patterns), use `.agent/roles/frontend-developer.md`. For the fullest architecture writeup, use `markdown-documentations/Frontend_Architecture_Guide.md`. For current gaps/status, use `markdown-documentations/FRONTEND_AUDIT_REPORT.md` and `project-docs/18_Implementation_Coverage_Audit.md`.
