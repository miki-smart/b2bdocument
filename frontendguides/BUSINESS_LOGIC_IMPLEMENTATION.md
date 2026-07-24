# Business Logic Implementation Guide
## Movello Frontend - React Implementation

**Version:** 2.0
**Last verified against code: 2026-07-23**
**Primary sources:**
- `src/shared/components/business/SplitAwardDialog.tsx` (real escrow calc + wallet validation, per line item)
- `src/features/business/pages/rfq/bids/BidCard.tsx` (escrow display on individual bids)
- `src/features/business/pages/contracts/ExtendContractDialog.tsx` (real contract "renewal" — extension, not a new contract)
- `src/features/admin/pages/operations/contracts/AdminEarlyReturnPage.tsx` (real early-return flow — no client-side penalty calculator)
- `src/shared/components/business/TrustScoreDisplay.tsx` (trust score breakdown fields, matched to the real backend formula)
- `src/features/admin/pages/master-data/TiersPage.tsx` (tier admin UI — edit is a stub)
- `src/core/services/delivery-service.ts` (real OTP generate/verify endpoints)
- `backlog/mvp/epic-04-rfq-management.md`, `epic-05-bidding-engine.md`, `epic-06-contract-management.md`, `epic-12-risk-trust-scoring.md` (rewritten 2026-07-23 — authoritative on backend business rules)
- `project-docs/18_Implementation_Coverage_Audit.md` (cross-cutting divergence findings, §10 corrections)

This replaces the v1.0 guide, which described several utility modules and a UI flow (`wallet-validation.ts` with a `calculateMaxAffordableQuantity` sorting algorithm, and an `early-return.ts` with a full client-side prorated-penalty calculator) that **do not exist in the codebase** — no such files were found under `src/features/business/rfq/utils/` or `src/features/business/contracts/utils/`. The real implementations are simpler, live in different files than v1.0 claimed, and in one case (early return) the elaborate client-side math v1.0 described has no web-UI counterpart at all — the real page just submits a reason to the backend.

**Also carried over from the audit:** every RFQ/bidding business rule below now assumes the **line-item + split-award model**, not the whole-RFQ, single-award model v1.0 implied in places. If you're extending bidding/award logic, read `backlog/mvp/epic-05-bidding-engine.md` first.

---

## Table of Contents

1. [What's Actually Real vs. What v1.0 Invented](#whats-actually-real-vs-what-v10-invented)
2. [Escrow Calculation & Wallet Validation (Split Award)](#escrow-calculation--wallet-validation-split-award)
3. [Blind Bidding — Including a Real Gap](#blind-bidding--including-a-real-gap)
4. [OTP Flow — Two Different OTPs, Not One](#otp-flow--two-different-otps-not-one)
5. [Contract "Renewal" Is Actually Extension](#contract-renewal-is-actually-extension)
6. [Early Return — No Client-Side Penalty Calculator](#early-return--no-client-side-penalty-calculator)
7. [Trust Score — Real Formula, Not Wired Into Production](#trust-score--real-formula-not-wired-into-production)
8. [Tier System — Real Commission Rates, Stub Admin UI](#tier-system--real-commission-rates-stub-admin-ui)
9. [Validation Helpers Still Worth Having](#validation-helpers-still-worth-having)

---

## What's Actually Real vs. What v1.0 Invented

| v1.0 claimed | Reality |
|---|---|
| `src/features/business/rfq/utils/wallet-validation.ts` — `validateWalletForAward()` sorts bids by unit price to compute a `maxAffordableQuantity`, offering DEPOSIT/PARTIAL_AWARD/CANCEL options | No such file. Wallet validation for award happens **inline inside `SplitAwardDialog.tsx`**, is a simple `totalEscrow > availableBalance` comparison per line item being awarded (no cross-award, price-sorted "which vehicles can I actually afford" optimizer), and blocks the Confirm button rather than offering a three-way choice menu |
| `src/features/business/rfq/utils/partial-award.ts` — `calculatePartialAward()` | No such file. Partial award is just "type a smaller quantity into the per-bid input than what's offered" in `SplitAwardDialog` — there's no separate calculation utility, the arithmetic is a few lines inline in a `useMemo` |
| `src/features/business/contracts/utils/early-return.ts` — `calculateEarlyReturn()` with tiered penalty rates by notice period × business tier, prorated refund math | No such file, and **no client-side penalty preview exists at all**. `AdminEarlyReturnPage.tsx` posts `{ vehicleId, initiatedBy, initiatorType, reason }` to `POST /contracts/{id}/line-items/{lineItemId}/early-return` and lets the backend do whatever penalty computation it does — the web UI shows no prorated amount, penalty rate, or refund figure before submitting |
| Escrow = arbitrary "totalAmount" per award, no cap mentioned | Escrow is **capped at 30 days**: `escrowDays = min(durationDays, 30)`, `escrow = escrowDays × unitPrice × quantity` — computed identically in both `SplitAwardDialog.tsx` and `BidCard.tsx` |
| OTP flow described as one generic "delivery verification" OTP | There are **two structurally different OTP mechanisms** in the real system — see [OTP Flow](#otp-flow--two-different-otps-not-one) |
| "Renewal" implemented as a new contract with same terms | No `renew` endpoint exists anywhere in the backend. The real web feature is `ExtendContractDialog.tsx` → `contractService.extendContract()`, which lengthens the **existing** contract's end date |
| Trust score gauge SVG largely matches reality | Close, but the breakdown fields it should bind to are `baseScore` / `completionRateBonus` / `onTimeRateBonus` / `noShowPenalty` / `rejectionPenalty` (matching the real backend `TrustScoreCalculator` formula) — not the five-metric `completionRate/onTimeRate/reliability/quality/disputeHistory` breakdown v1.0 described |

---

## Escrow Calculation & Wallet Validation (Split Award)

**Real rule (epic-05, epic-08):** escrow required for an award is capped at 30 days of the contract duration, even for long-term RFQs — this protects the platform from locking a business's entire wallet against a 12-month contract, while still guaranteeing at least one month of coverage per provider.

**File:** `src/shared/components/business/SplitAwardDialog.tsx`

```typescript
// Duration comes from the line item's pre-calculated durationDays, falling back to
// Math.ceil((endDate - startDate) / 1 day) — matching the backend's own calculation.
const durationDays = lineItem.durationDays > 0
  ? lineItem.durationDays
  : Math.ceil((parseISO(endDate).getTime() - parseISO(startDate).getTime()) / (1000 * 60 * 60 * 24));

// Escrow lock is capped at 30 days regardless of actual contract duration.
const escrowDays = durationDays <= 0 ? 1 : Math.min(durationDays, 30);

// Per selected bid: escrow contribution = escrowDays * unitPrice * awardedQuantity
selectedBids.forEach((bid) => {
  const qty = quantities[bid.bidId] || 0;
  total += qty;
  if (qty > 0) {
    escrow += escrowDays * bid.unitPrice * qty;
  }
  if (qty > bid.quantityOffered) {
    errors.push(`${bid.providerHash}: Cannot award more than ${bid.quantityOffered} (offered)`);
  }
});

if (total > lineItem.quantityRequired) {
  errors.push(`Total awarded (${total}) cannot exceed required quantity (${lineItem.quantityRequired})`);
}
if (availableBalance !== undefined && escrow > availableBalance) {
  errors.push(`Insufficient balance. Required: ${formatETB(escrow)}, Available: ${formatETB(availableBalance)}`);
}

const isValid = validationErrors.length === 0 && totalAwarded > 0 && totalAwarded <= lineItem.quantityRequired;
```

What this means in practice:
- **Partial award is just "award fewer than required"** — the dialog defaults every selected bid's quantity input to its full `quantityOffered`, and the business can lower any of them. There's no separate "partial award" mode or confirmation step; `totalAwarded < quantityRequired` is a perfectly valid award, it just leaves the rest of the line item open for a later award round.
- **Split award across providers happens by selecting multiple bids** for the same line item before opening this dialog (`BidReviewPage.tsx` → `handleAwardClick`), then giving each one a quantity here. There's no separate "split award mode" toggle — one bid selected is a normal award, more than one is a split award, same dialog either way.
- **There is no automatic "here's the max you can afford" suggestion.** If the total exceeds `availableBalance`, the Confirm button is simply disabled with an inline error — the business has to manually reduce quantities (or deposit more funds) and try again. There is no server-side or client-side algorithm that proposes an optimal affordable subset.
- **This same escrow formula is duplicated** (not shared via an imported utility) in `BidCard.tsx` for the per-bid escrow preview shown before a bid is even selected for award — if you change the 30-day cap or the formula, both call sites need updating.

---

## Blind Bidding — Including a Real Gap

**Rule (epic-04, epic-05):** provider identity stays hashed to the business until the corresponding bid is awarded.

**Implementation:** `BidCard.tsx`/`BidRow`-equivalents render `bid.providerHash` (format `Provider •••4411`) while a bid is in `PENDING`/`SUBMITTED`/`BIDDING` state; once a contract exists for an awarded line item, the contract detail screens show the real provider name.

**Real, confirmed gap (per `18_Implementation_Coverage_Audit.md` §10.3, carried into the epic-05 rewrite):** the backend's `GetBidsByRFQQuery`/`GetBidQuery` handlers set `ProviderName` on the DTO **unconditionally, regardless of award status** — blind bidding is enforced entirely by the web UI choosing not to render that field, not by the API withholding it. A business with browser dev tools open (or any other API consumer) can already see provider identity before award by inspecting the raw response. This is a documented, fix-required gap, not something to assume is closed — do not describe blind bidding as "enforced server-side" anywhere in new docs or code comments until this is actually fixed.

---

## OTP Flow — Two Different OTPs, Not One

There are **two independent, structurally different** OTP mechanisms in the real system. Conflating them is a common documentation error (v1.0 only described one, generically).

### 1. Delivery-confirmation OTP (`Modules/Delivery`)

**File:** `src/core/services/delivery-service.ts`

```typescript
generateOTP: (sessionId: string) => apiClient.post(`/delivery/sessions/${sessionId}/otp/generate`, {}),
verifyOTP: (sessionId: string, code: string) => apiClient.post(`/delivery/sessions/${sessionId}/otp/verify`, { code }),
// A parallel pair exists for the return leg:
generateReturnOTP: (sessionId: string) => apiClient.post(`/delivery/sessions/${sessionId}/return-otp/generate`, {}),
```

Confirms the vehicle handover (and, separately, the return handover) between provider and business. Per the audit, **the OTP code is never exposed by the API response for security** — the backend's `GenerateOTPResponseDto` intentionally omits it; delivery of the code to the business is via SMS/notification only. Treat any UI that displays a raw OTP code fetched from this endpoint as suspect and re-verify against the current backend contract before relying on it.

### 2. Contract e-signature OTP (`Modules/Contracts` — `ContractTermsAcceptance`)

A **separate**, dual-party mechanism gating `PendingSigning → Signed` in the contract lifecycle: both the business and the provider must independently generate + verify an OTP to accept contract terms before the contract can proceed toward delivery. This is not the same OTP as delivery confirmation, has its own endpoints (`terms/otp/generate` / `terms/otp/verify`), and is not documented at all in the original epic-06/epic-07 text — see `backlog/mvp/epic-06-contract-management.md` for the full state machine. `BusinessPendingOTPsPage.tsx` on the business side surfaces contracts waiting on this signing step.

**Do not merge these two into one "OTP flow" section when writing new docs or onboarding new engineers** — they hit different endpoints, gate different state transitions, and have different failure semantics.

---

## Contract "Renewal" Is Actually Extension

**Real rule (epic-06):** there is no `renew` endpoint anywhere in the backend, and no second contract is ever created for a renewal. What v1.0 (and the original epic-06 doc) called "renewal" is implemented as **extension of the existing contract**.

**File:** `src/features/business/pages/contracts/ExtendContractDialog.tsx`

```typescript
const currentEnd = parseISO(currentEndDate);
const proposedEndDate = endOfMonth(addMonths(currentEnd, extensionMonths)); // always rounds to end-of-month

await contractService.extendContract(contractId, {
  newEndDate: proposedEndDate.toISOString(),
  reason,
});
```

Key real behavior:
- **Only offered for long-term contracts** (`isLongTerm` prop) — the dialog renders a "not applicable" state otherwise.
- **Business-initiated only, no provider accept/reject step** — unlike the epic's original "provider accepts/rejects renewal" framing, extension is a unilateral request from the business (an admin approval step may exist server-side; there's no counter-party approval UI on the provider portal).
- **Always rounds the new end date to end-of-month**, regardless of how many months were requested — a 1-month extension from the 15th of a month does not add exactly 30 days, it extends through the end of the target month.
- **Same contract ID throughout** — no new contract number, no new escrow lock event distinct from whatever the extension triggers server-side.

---

## Early Return — No Client-Side Penalty Calculator

**Real rule (epic-06):** `Contract.Terminate()`/`Contract.TerminateEarly()` domain methods exist on the backend with penalty math already written, alongside `ContractPenalty`/`EarlyReturnNotice` entities — but per the audit, **`Terminate()`/`TerminateEarly()` have zero callers anywhere in the backend**, and the web UI has no client-side preview of what a return would cost.

**File:** `src/features/admin/pages/operations/contracts/AdminEarlyReturnPage.tsx`

```typescript
const initiateEarlyReturnMutation = useMutation({
  mutationFn: ({ contractId, lineItemId, vehicleId, reason, initiatorType }) =>
    apiClient.post(`/contracts/${contractId}/line-items/${lineItemId}/early-return`, {
      vehicleId,
      initiatedBy: adminUserId,
      initiatorType, // 'BUSINESS' | 'PROVIDER' | 'ADMIN'
      reason,
    }),
});
```

What this means for anyone extending early-return UI:
- **There is no prorated-amount / penalty-rate / refund preview anywhere in the web app.** The admin (or business/provider, via `initiatorType`) picks a contract, line item, and vehicle, types a free-text reason, and submits — the backend computes whatever it computes, with no client-side estimate shown first.
- **If a penalty-preview feature is requested, it does not exist yet** — this would be new work, not a bug fix, and should be scoped as such rather than assumed to be "just wiring up an existing calculation."
- **Do not resurrect the v1.0 `calculateEarlyReturn()` tiered-rate logic (7+/3-6/0-2 day notice bands, tier multipliers) as if it reflects a real, shipped calculation** — it was invented for the v1.0 doc, not observed in code. If the actual notice-period/penalty-rate policy needs documenting, source it from the backend's `ContractPolicyVersion/Rule`/`EscrowPolicyVersion/Rule` master-data tables (see `markdown-documentations/Master_Data_Specification.md`), not from client code — none of that policy logic lives in the frontend.

---

## Trust Score — Real Formula, Not Wired Into Production

**Real formula** (`TrustScoreCalculator.cs`, backend — confirmed by `backlog/mvp/epic-12-risk-trust-scoring.md`):

```
TrustScore = Base(50 if provider is verified, 0 if not)
           + CompletionRate × 20
           + OnTimeRate × 20
           − NoShowRate × 30
           + RejectionPenalty
```

**File:** `src/shared/components/business/TrustScoreDisplay.tsx`

The gauge component's tooltip breakdown is already correctly modeled on this formula, not the generic five-metric breakdown v1.0 described:

```typescript
interface TrustScoreBreakdown {
  baseScore: number;
  completionRateBonus: number;
  onTimeRateBonus: number;
  noShowPenalty: number;
  rejectionPenalty: number;
  totalScore: number;
}
```

Score bands used for color/label across the app (`getScoreColor`/`getScoreLabel`): **≥85 Excellent (emerald)**, **≥70 Good (blue)**, **≥50 Fair (amber)**, **<50 Poor (red)** — consistent between `TrustScoreDisplay` and `BidCard`/`SplitAwardDialog`'s inline usage.

**Critical caveat, confirmed by the audit (§10.2) — do not skip this when discussing trust score with anyone:** `TrustScoreCalculator`/`ITrustScoreCalculator` is fully implemented, unit-tested, and DI-registered, but has **zero production call sites**. No event handler for contract completion, on-time delivery, no-show, or bid rejection ever invokes it. In practice, **every provider's trust score is frozen at its registration-time default (50 if verified, 0 if not)** unless an admin manually triggers tier assignment. If a task assumes trust score updates automatically as a provider completes contracts, that assumption is currently false in production — flag it rather than build on top of it silently.

A second, competing tier-threshold scheme (`TierCalculationService` + seeded `ProviderTierRule` data) also exists and is also never called in production — two disagreeing threshold definitions coexist in code (hardcoded 50/70/85 for admin list-filtering vs. a seeded 60/75/90-plus-criteria scheme). Don't treat either as the single source of truth without checking which one, if either, a given feature actually reads from.

---

## Tier System — Real Commission Rates, Stub Admin UI

**Real seeded commission rates** (confirmed 2026-07-23, do not use older figures from project memory without reconciling first): **Bronze 10% / Silver 8% / Gold 6% / Platinum 5%**. **There is no "Red Zone" tier anywhere in code.**

**File:** `src/features/admin/pages/master-data/TiersPage.tsx`

The admin tier-management page's edit dialog is a **stub** — `toast.info('Update functionality coming soon')` — admins cannot actually change tier thresholds or commission rates through the UI today, despite the page appearing to offer an edit action. If asked to build tier-threshold editing, this is new work on an existing placeholder, not a bug fix.

`TierDisplay`-style components (provider-facing tier card, showing current tier, commission rate, and progress to next tier) should pull thresholds from whichever of the two competing schemes above the specific screen is wired to — check the actual query/service call before assuming a number.

---

## Validation Helpers Still Worth Having

The v1.0 doc's generic `validateRFQDates`/`validateBidPrice` helpers describe reasonable client-side guardrails (start date buffer, bid-deadline-before-start-date, price-within-market-range) that are a sound pattern in principle, but **were not confirmed to exist as standalone utility files** in this pass — if you find or add equivalent validation, prefer colocating it with the form it guards (matching the rest of this codebase's convention of inline `useMemo`/`useState`-driven validation over shared generic utility modules) rather than assuming a shared `src/shared/utils/date-validation.ts` already exists.
