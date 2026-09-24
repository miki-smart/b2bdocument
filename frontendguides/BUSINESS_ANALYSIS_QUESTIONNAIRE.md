# Business Analysis Questionnaire — Decision Record & Code-Reality Status
## Anqelba Car Rental B2B Mobility Marketplace Platform

**Last verified against code: 2026-07-23**
**Original purpose:** a fill-in-the-blank questionnaire, one entry per open issue found in an earlier business-analysis pass, used to capture the product owner's actual decisions on ~35 requirement conflicts, module-boundary questions, flow gaps, and process risks identified across the pre-MVP documentation set.
**What changed in this rewrite:** this is a discovery/decision artifact, not a technical spec — every question below was already answered by the product owner (the original "Your Decision" responses are preserved verbatim in blockquotes throughout). Rewriting it as a spec would destroy the historical record of *why* the platform was built the way it was. Instead, each decision now carries a **Code Reality** verdict: whether what shipped matches what was decided, diverges from it, or was never built at all — checked against the current backend/web code and the 2026-07-23 implementation audit (`project-docs/18_Implementation_Coverage_Audit.md`). The blank Summary section at the end of the original (never filled in) has been completed using this same cross-check.

**Verdict legend:**
- ✅ **Implemented as decided** — code matches the recorded decision
- 🟡 **Implemented differently** — something shipped, but not quite what was decided
- ⚪ **Not implemented** — the decision was never built; treat as an open gap, not a shipped feature
- 📋 **Policy-only** — an operational/organizational decision (SLA hours, reviewer roles, review checklists) that isn't the kind of thing that shows up in code either way; noted as "not independently verifiable against code" rather than given a pass/fail
- ❔ **Not independently re-verified** — plausible given adjacent findings, but this pass didn't hit the specific code path to confirm it either way

Original priority markers (🔴/🟡/🟢) were left almost entirely unmarked in the source document (all three symbols printed, none selected, on all but one issue) — rather than guess a retroactive priority ranking from incomplete data, the Summary section at the end ranks issues by **Code Reality status** instead, which is more useful for anyone deciding what to build or fix next.

---

## 1. Requirement Consistency Issues

### Issue 1.1.1 — Trust Score Calculation

**Conflict:** `Business_Rules.md` said "Initial Score: 0"; the Trust Engine spec described a complex signal/decay system; a CTO analysis said to delete scoring entirely in favor of a "Verified" badge.

> **Decision:** Simple calculation (completion rate, on-time rate, no-show rate) — **no decay algorithms**. Being verified is itself one criterion and sets the default/initial score: **50 points for verified**, **0 for unverified/pending**. Users improve from there via completion rate, on-time rate, and no-show rate.

**Code Reality:** ✅ **Implemented as decided, with one addition.** `TrustScoreCalculator.cs` computes exactly `Base(50 if verified, 0 if not) + CompletionRate×20 + OnTimeRate×20 − NoShowRate×30 + RejectionPenalty` — the verified-base-50 idea and the three named signals are all there, plus a rejection-penalty term the decision didn't explicitly ask for but doesn't contradict. 🟡 **Caveat that matters more than the formula itself:** per the 2026-07-23 audit, this calculator has **zero production call sites** — no event handler ever invokes it, so in practice every provider's score is frozen at its registration-time default (50 or 0) and never actually moves as completion/on-time/no-show data accumulates. The decision was correctly translated into code; the code was never wired into the platform's event flow.

### Issue 1.1.2 — RFQ Creation Wallet Requirement

**Conflict:** one doc said no wallet balance is required to create/publish RFQs; an older doc said a business must maintain sufficient balance for the next billing cycle.

> **Decision:** Only being **verified** is required to create an RFQ. A wallet balance is **not** required to create an RFQ, but **is** required to award a bid. Rationale: requiring a balance up front discourages RFQ creation for an amount businesses don't yet know; requiring it at award time (when the cost is known) is the more reasonable ask.

**Code Reality:** ✅ **Implemented as decided.** RFQ creation has no wallet-balance gate anywhere in the web flow; wallet balance is checked exactly at award time, inline in `SplitAwardDialog.tsx` (`totalEscrow > availableBalance` blocks the Confirm button) — see `BUSINESS_LOGIC_IMPLEMENTATION.md` for the mechanics.

### Issue 1.1.3 — Escrow Lock Timing

**Conflict:** four different documents put escrow lock at four different points in the flow (before contract creation, after creation but before assignment, after assignment, immediately after award).

> **Decision:** After contract creation but before vehicle assignment. Proposed sequence: **deposit/award check → contract created per provider → escrow locked per contract → vehicles assigned → both parties accept terms via OTP (signing gate) → activation only once contract created + escrow locked + vehicles assigned + both signed are all true → delivery confirms via OTP/QR → active.** Escrow is per-contract (not per-RFQ) because one RFQ/line item can produce multiple provider contracts via split award.

**Code Reality:** ✅ **Implemented essentially as decided.** The real (string-valued, not enum-enforced) contract lifecycle includes `PendingEscrow`, `PendingVehicleAssignment`, and `PendingSigning → Signed` as distinct states in that order, and `Active` genuinely does gate on escrow + assignment + dual-party OTP signing all being satisfied — this is one of the more faithfully-executed decisions in the whole document. See `backlog/mvp/epic-06-contract-management.md` and `MVP_CONTRACT_STATE_MACHINE.md` for the full (18-state-in-practice) picture.

---

## 2. Module Responsibility Boundaries

### Issue 1.2.1 — Contract Creation Responsibility

> **Decision:** Contract creation should be triggered by `BidAwardedEvent`, **not** `EscrowLockedEvent` — escrow lock should instead be triggered by the contract-creation event. If Finance fails to lock escrow, the contract is put on hold and retried by a background service rather than failing outright; if contract creation itself fails after award, the award is reverted for retry.

**Code Reality:** ✅ **Implemented as decided.** Per the audit, `ContractCreatedEventHandler` is what actually triggers escrow locking today (via a hardcoded-constant computation path, a separate finding — see `BUSINESS_LOGIC_IMPLEMENTATION.md`'s trust-score section and the audit §10.5 for the "two escrow computation paths" note). The award→contract→escrow ordering matches this decision exactly.

### Issue 1.2.2 — Trust Score Module Ownership

> **Decision:** Identity module should access data from Contracts/Delivery/Finance via **events** (subscribing to things like `ContractCompletedEvent`, `DeliveryConfirmedEvent`, `NoShowEvent`, `DisputeResolvedEvent`), to avoid duplicating trust-score logic in every module that has relevant data.

**Code Reality:** ⚪ **Not implemented — this is the single biggest gap this document surfaces.** The event-subscription architecture for trust score was never built: no event handler anywhere calls `TrustScoreCalculator` or `Provider.UpdateTrustScore()`. The decision correctly diagnosed the right architecture (events, not duplication); it just never got wired up. This is the same gap flagged under Issue 1.1.1 above and in the audit's §10.2 — recorded twice here because it's referenced from two different original issues.

### Issue 1.2.3 — Settlement Processing Dependency Chain

> **Decision:** Settlement triggered by three events — `ContractCompletedEvent` (normal), `ContractAlteredEvent` (adjustment/pro-rata), `EarlyReturnEvent` (early termination with penalties). Finance subscribes to all three, reads contract data from the event payload, queries MasterData directly (DB or Redis) for commission rates, calculates, and pays out.

**Code Reality:** 🟡 **Implemented differently in one specific way.** Settlement generation (`GenerateSettlementCommand`) is real and event-driven in spirit, but there's an unresolved internal contradiction (audit §10.4) between whether settlement cadence is tier-based (as the wallet-epic rewrite found) or a flat rolling 30-day cycle regardless of tier (as the settlement-epic rewrite found) — this specific decision's "how settlement gets triggered" premise is sound, but the exact cadence mechanics it assumed haven't been confirmed as built one way or the other.

---

## 3. Business Flow Gaps

### Issue 2.1.1 — Award Retry & Partial Award Handling

> **Decision:** No auto-retry/auto-award — always show the error and let the business manually retry after depositing funds, to avoid unintentional awards leading to disputes. If a business can only afford part of a line item: award the affordable portion (unselected bids go `LOST`), optionally create a new RFQ for the remainder, or deposit more and award the rest. Provider rejection after award: notify the business, exclude the rejecting provider, reactivate previously-`LOST` bids for manual re-selection — no penalty for legitimate first-time rejections (vehicle broken/maintenance/insurance expired).

**Code Reality:** ✅ **Partial/split award matches the decision closely.** `SplitAwardDialog.tsx` has no auto-retry or auto-award path — insufficient balance simply disables Confirm; awarding fewer vehicles than required is a normal, unblocked outcome (see `BUSINESS_LOGIC_IMPLEMENTATION.md`). ❔ **Not independently re-verified:** the specific "provider rejects after award → excluded provider → previously-LOST bids reactivate for re-selection" flow wasn't confirmed against a specific endpoint in this pass — plausible given the bid-status model, but don't cite it as confirmed-built without checking the award/bid-status transition code directly.

### Issue 2.1.2 — Delivery OTP Failure Scenarios

> **Decision:** Provider can request a new OTP if it expires (network delays can cause this). OTP verification is **final acceptance** — no delivery rejection after OTP. If vehicle condition doesn't match expectations, the business simply doesn't confirm via OTP; can ask for a replacement vehicle, and failing that, raise a dispute (contract altered afterward if a different provider is awarded).

**Code Reality:** ✅ **Broadly consistent.** `deliveryService.generateOTP`/`verifyOTP` (`/delivery/sessions/{id}/otp/generate|verify`) support regeneration by calling generate again; the contract lifecycle has no "reject after OTP confirm" transition, consistent with "final acceptance." ⚪ **However:** the decision's fallback path — raise a dispute if a replacement vehicle doesn't work out — routes into a dispute-resolution workflow that, per Issue 5.1.4 below, **does not exist anywhere in the backend**. The "ask for replacement, then dispute" decision is only half-buildable today.

### Issue 2.1.3 — Early Return Approval & Penalty

> **Decision:** Both business and provider must approve an early return. A one-week notice period avoids most disputes; less notice is penalized based on how much notice was actually given. Damage during early return is the business's responsibility (enforced via law enforcement, provider raises a dispute). Penalty communicated via SMS, email, and in-app (in-app default).

**Code Reality:** 🟡 **Partially built, differently shaped.** `POST /contracts/{id}/line-items/{lineItemId}/early-return` exists and accepts an `initiatorType` (`BUSINESS`/`PROVIDER`/`ADMIN`) plus a reason — consistent with a multi-party-aware flow. But the web UI (`AdminEarlyReturnPage.tsx`) shows **no dual-approval step, no notice-period countdown, and no penalty preview** before submission — see `BUSINESS_LOGIC_IMPLEMENTATION.md`. Whatever approval/notice/penalty logic exists is entirely server-side and invisible to the frontend today.

---

## 4. Approval Processes

*(These three issues are organizational/operational policy — reviewer roles, SLA hours, checklists — not the kind of thing that shows up as a pass/fail in code. Marked 📋 throughout; noted where an adjacent system confirms the general shape exists.)*

### Issue 2.2.1 — Document Verification Approval

> **Decision:** Compliance Officer reviews; checklist = business lifetime, license accuracy, capital, vehicle ownership (Libre), vehicle insurance, attorney document check, insurance expiry. **48-hour SLA.** Rejection uses standard predefined reasons (not fully custom feedback). No appeal process. If the reviewer is unavailable, review simply continues once one becomes available.

**Code Reality:** 📋 Policy-only. The general shape (admin verification queue with approve/reject + standard rejection reasons) is confirmed to exist (epic-01/02, `BusinessVerificationListPage.tsx` and siblings) — the specific 48-hour SLA and exact checklist items are organizational policy, not independently checkable in code.

### Issue 2.2.2 — Insurance Verification Approval

> **Decision:** Manual verification for MVP, moving to a hybrid (manual + API) model post-MVP. Fake certificates get the vehicle flagged/suspended. 48-hour timeline. Checklist: expiration date, insurance type, coverage amount.

**Code Reality:** 📋 Policy-only / ✅ consistent with what exists — manual insurance verification via the admin vehicle-verification queue is confirmed built (epic-03); no automated insurance-API integration exists yet, consistent with "MVP = manual."

### Issue 2.2.3 — Settlement Approval Process

> **Decision:** Auto-approve below a threshold (100,000 ETB), manual approval above it. Flagged providers require manual review. Large payouts reviewed by a finance officer. Disputes are meant to be avoided at contract-creation time (via escrow), with actual disputes routed to a dispute handler.

**Code Reality:** ❔ **Not independently re-verified in this pass** — settlement/payout approval-threshold logic wasn't traced to a specific code path here. The closing reference to a "dispute handler" is the same structure Issue 5.1.4 finds **does not exist** — treat the dispute-routing half of this decision as unbuilt until proven otherwise.

---

## 5. Pre-Action Requirements

### Issue 2.3.1 — RFQ Creation Prerequisites

> **Decision:** Business must be VERIFIED (status = ACTIVE); checking that status is sufficient — an unverified business means an incomplete KYC profile.

**Code Reality:** ✅ Same decision as Issue 1.1.2 above, restated — implemented as decided.

### Issue 2.3.2 — Bid Submission Prerequisites

> **Decision:** Real-time vehicle availability check, insurance-validity check, provider-suspension check, and a trust-score minimum threshold, all at bid time — and **re-validated in full at award time**, since a vehicle can become unavailable between bid and award.

**Code Reality:** 🟡 **Partially confirmed.** Fleet-capacity-aware bidding is real — `ProviderFleetCapacityService`/`ProviderFleetController` on the backend, and `SegmentCapacityMeter`/`FleetCapacityConflictSheet`/`provider-fleet-capacity-service.ts` on the web cross-check RFQ bid commitments against Direct Rental commitments per vehicle segment — strong evidence the availability-check half of this decision shipped. ⚪ A **trust-score minimum threshold gating bids** is unlikely to be implemented given Issue 1.1.1/1.2.2's finding that trust score isn't even being updated in production — don't assume this specific criterion is enforced anywhere.

### Issue 2.3.3 — Contract Activation Timeout & Rollback

> **Decision:** Contract can sit in pending-activation for **5 days**; after that, notify business and provider (rather than silently auto-cancelling); rollback = contract cancellation / RFQ reactivation.

**Code Reality:** 🟡 **The mechanism exists; the exact parameters weren't independently re-confirmed.** The audit found an `EscrowTimeoutJob` background job that calls `Contract.Cancel()` to produce the `CANCELLED` status — confirming *a* timeout-driven cancellation job exists, consistent with the decision's intent. The specific 5-day figure and whether it notifies-without-cancelling vs. auto-cancels wasn't verified against the job's actual logic in this pass.

---

## 6. Event-Driven Workflow Issues

*(This entire section decided on an ambitious event-infrastructure architecture — sagas, exactly-once delivery, universal idempotency keys, dead-letter queues, event sourcing/replay, strict ordering, event versioning. None of this was found to exist as a formal, separate infrastructure layer anywhere in the audited codebase. The real system is simpler: MediatR-based in-process event handlers, published after the domain transaction commits, each independently try/caught with structured logging — a legitimate, working simplification, just not what was decided here.)*

### Issue 3.1.1 — Missing Critical Events

> **Decision:** Add `EscrowLockFailedEvent`, `EscrowLockedEvent`, `ProviderRejectedAwardEvent`, `DeliveryRejectedEvent`, `InsuranceExpiringEvent`, `ContractActivationTimeoutEvent`, `SettlementDisputedEvent` to the catalog, each with defined handlers; retry policies on all events.

**Code Reality:** 🟡 **Some of these events are real, at least in effect** (contract creation, escrow-lock, and timeout-driven cancellation all functionally exist per the sections above), but they weren't confirmed to exist as a formally catalogued, individually-retried event taxonomy — the real notification-side event handler roster (~35 handlers, per epic-11) is broader in event-count but was not built against this specific proposed catalog.

### Issue 3.1.2 — Event Handler Failure Guarantees

> **Decision:** Exactly-once delivery, idempotency keys on all events, retry-with-backoff + dead-letter-queue + admin-notify on handler failure, event sourcing (replay) plus an audit trail for lost events.

**Code Reality:** ⚪ **Not implemented as decided.** The real, confirmed pattern (epic-11) is per-handler try/catch with structured logging so one failure doesn't block the triggering transaction — a sound, simpler safety net, but there is no confirmed exactly-once guarantee, no universal idempotency-key scheme, no dead-letter queue, and no event-sourcing/replay mechanism anywhere in the audited backend. Notifications' own outbox tables (email/SMS) were explicitly found to have **no automated retry worker** — the opposite of "retry with exponential backoff on all events."

### Issue 3.1.3 — Event Ordering, Sagas, Versioning

> **Decision:** Strict event ordering required; a formal Saga pattern for the Award → Contract Creation → Escrow → Vehicle Assignment → Delivery → Activation chain; all events versioned.

**Code Reality:** 🟡 **The *sequence* the saga would have encoded is real and enforced** (see Issue 1.1.3/1.2.1 above — the state machine genuinely gates activation on all those steps completing in order), but it's enforced through the contract's own state machine and per-handler logic, not a formally named saga-orchestration layer, and no event-versioning scheme was found. Treat the outcome as achieved, the specific architectural mechanism as not what was decided.

---

## 7. Integration Patterns

### Issue 3.2.1 — Module Communication Pattern

> **Decision:** Async (events) everywhere except validation checks, which are synchronous.

**Code Reality:** ✅ Broadly consistent — MediatR-driven async domain events dominate the write path across modules (Marketplace→Contracts→Finance→Delivery), while read-side validation (fleet capacity, wallet balance checks) happens as direct synchronous queries, matching the decision's own distinction.

### Issue 3.2.2 — External Service Integration Resilience

> **Decision:** No retry policies, no circuit breakers, no rate limiting for external services (payment gateways, SMS, email) — "out of MVP scope." SMS failure fallback = retry only.

**Code Reality:** ✅ **Implemented as decided — confirmed by omission.** The notifications epic rewrite explicitly found **no background retry worker** for the email/SMS outbox and no delivery-status webhook ingestion — matching this decision's own "no retry policy" choice, not contradicting it. This is a rare case where an original "we're skipping this for MVP" decision and a later "this doesn't exist" audit finding are actually describing the same, intentional state.

---

## 8. Compliance & Operational Excellence

*(4.1.x: KYC/KYB, insurance, and financial-audit compliance. These map to epics 01–03 and 08–10, all confirmed ✅ implemented at the epic level per the coverage audit; the granular enforcement mechanisms/thresholds recorded here are largely 📋 policy detail not independently re-checked line-by-line in this pass.)*

### Issue 4.1.1 — KYC/KYB Enforcement

📋 General enforcement (business/provider must be verified before transacting) is confirmed built (epics 01/02/03, ✅ across backend/web). Specific mechanism details recorded in the original weren't re-traced individually.

### Issue 4.1.2 — Insurance Compliance Enforcement

📋 Same pattern as 2.2.2 above — manual verification confirmed, automated enforcement mechanics not independently re-checked.

### Issue 4.1.3 — Financial Audit Trail Requirements

❔ Not independently re-verified against a specific audit-log implementation in this pass; Wallet & Escrow (epic-08) is confirmed to have real transaction ledgers, but whether they meet this issue's specific audit-trail requirements wasn't checked line-by-line here.

---

## 9. Operational Excellence *(explicitly marked "out of MVP scope" by the original document itself)*

### Issue 4.2.1 — Incident Response, 4.2.2 — Backup/Recovery, 4.2.3 — Monitoring & Alerting

⏸ **Deferred by the original document's own scoping**, not something this rewrite needs to reconcile against code — these were recorded as post-MVP operational concerns from the start ("Its out of MVP Scope" appears verbatim in the original section header). No code-reality verdict applies; they remain open organizational decisions if and when they're prioritized.

---

## 10. Business Process Drawbacks & Risks

### Drawback 5.1.1 — Manual Verification Bottleneck

> **Decision:** Acceptable for MVP; partial automation planned post-MVP ("need to launch fast, automation is complex scope for MVP").

**Code Reality:** ✅ Matches — manual admin verification is what's actually built (epics 01/02/03); no automation has shipped, consistent with "partial automation is a post-MVP plan," not an MVP claim.

### Drawback 5.1.2 — No Real-Time Vehicle Availability

> **Decision:** Availability checked at bid time, award time, and vehicle-assignment time. Provider can reject an award **without penalty** if the vehicle turns out to be unavailable (broken/maintenance).

**Code Reality:** 🟡 The bid-time/award-time capacity-checking half is corroborated by the fleet-capacity services referenced under Issue 2.3.2. ❔ The specific "provider rejects award without penalty" mechanic wasn't independently confirmed against a specific endpoint in this pass.

### Drawback 5.1.3 — Settlement Frequency / Cash Flow

> **Decision:** Not considered a real issue, since the escrow-locked fund is already paid; keep current (monthly-for-Bronze/Silver) frequency rather than moving everyone to weekly/bi-weekly.

**Code Reality:** ⚪ **Directly touches an unresolved contradiction found during the doc-rewrite pass** (see Issue 1.2.3 / audit §10.4): whether settlement cadence is genuinely tier-based as this decision assumes, or a flat 30-day cycle regardless of tier, is disputed between two other rewritten epic docs and was not resolved before publishing. Don't cite this decision as confirmed-implemented without resolving that contradiction first.

### Drawback 5.1.4 — No Dispute Resolution Workflow

> **Decision:** MVP dispute categories = vehicle condition mismatch, delivery no-show, early-return disagreement, settlement-amount disagreement, insurance expiry during contract. Evidence = photos, GPS data, OTP records, contract docs, communication logs. 48-hour resolution target.

**Code Reality:** ⚪ **Not implemented — confirmed absent, not just unverified.** The audit is explicit: "no fraud-detection rule engine, no collusion detection, no dispute-engine entity anywhere in the backend." `Disputed`/`OnHold` exist only as unused contract status values with no supporting workflow, entities, or evidence-handling behind them. Every dispute-routing reference elsewhere in this document (Issues 2.1.2, 2.1.3, 2.2.3) ultimately depends on this workflow existing — none of those downstream flows can be fully realized until this is actually built. **This is the highest-impact open gap in the entire questionnaire.**

### Risk 5.2.1 — Partial Award Complexity

Decision: same as Issue 2.1.1 above (deposit more / new RFQ for remainder / award partial). ✅ Implemented — see Issue 2.1.1.

### Risk 5.2.2 — Provider Rejection After Award

> **Decision:** Appeal process only for first-time rejections; no penalty for legitimate rejections (broken vehicle, maintenance, expired insurance).

**Code Reality:** ❔ Not independently re-verified against a specific "appeal" endpoint or first-time-vs-repeat rejection tracking in this pass — plausible given the bid-status model referenced in Issue 2.1.1, but unconfirmed.

### Risk 5.2.3 — Early Return Penalty Fairness

> **Decision (final, superseding this issue's own original framing of "15–25%"):** Early return penalties should be **configurable** (fixed amount or percentage), with a tiered notice-period structure — 7 days' notice = 0% penalty, 3 days = 2%, same-day = 15%. No waiver process and no Enterprise/GOV_NGO penalty negotiation for MVP; system administrators adjust rates centrally based on market feedback.

**Code Reality:** 🟡 **The "configurable policy" architecture is real; the specific numbers and any client-facing preview are not.** MasterData's versioned policy/rules engine (`ContractPolicyVersion/Rule`, `EscrowPolicyVersion/Rule`, per `markdown-documentations/Master_Data_Specification.md`) is exactly the kind of admin-configurable-without-a-deploy system this decision asked for. But per `BUSINESS_LOGIC_IMPLEMENTATION.md`, the web early-return UI (`AdminEarlyReturnPage.tsx`) shows **no penalty calculator or preview at all** — whatever the live 7/3/same-day percentages actually are today lives entirely server-side and isn't independently confirmed from the frontend in this pass.

---

## 11. Module Interaction Issues

### Issue 6.1.1 — Circular Dependency Avoidance

> **Decision:** Hybrid pattern — reads are direct cross-module database queries (allowed), writes are event-only (no direct cross-module writes), all CUD operations publish events, MasterData is read-only/no-events (static config).

**Code Reality:** ✅ **Strongly confirmed, arguably the most prescient decision in the document.** The decision's own example event names (`BidAwardedEvent`, `ContractCreatedEvent`, `EscrowLockedEvent`, `ContractCompletedEvent`) are, per every other section above, **the actual real event names used in the shipped system** — this reads less like a forward-looking decision and more like an accurate prediction of what got built.

### Issue 6.1.2 — Shared Data Access Pattern

> **Decision:** Direct database reads for synchronous validation/lookups (e.g., Finance reading a business name from Identity); events for asynchronous state changes.

**Code Reality:** ✅ Consistent with confirmed behavior elsewhere in the audit — e.g. escrow computation directly looking up wallet accounts by `AccountType` string (a separate, unrelated bug the audit found — two different strings, `"COMMISSION"` vs `"PLATFORM_COMMISSION"`, used for what should be the same wallet — but the *pattern* of direct cross-module reads for lookups is exactly what that bug presupposes exists).

### Issue 6.1.3 — Master Data Access & Caching

> **Decision:** Direct queries to the MasterData database, with Redis caching for frequently-accessed data (commission rates, vehicle types, contract policies, lookups); cache invalidated on admin update; long TTL (~24h) since MasterData changes infrequently.

**Code Reality:** ❔ **Not independently re-verified.** Direct cross-module reads of MasterData are consistent with everything else in this document, but Redis caching specifically for MasterData lookups wasn't confirmed or denied in this pass — check `Modules/MasterData/` and the DI/caching setup directly before citing this as either implemented or not.

---

## Summary Section (Completed 2026-07-23 — Original Was a Blank Template)

The original document's closing "Overall Priority Assessment" and "Next Steps" sections were never filled in (placeholder brackets only, no sign-off name/date). Rather than invent a priority ranking the product owner never actually recorded, this summary ranks the ~35 issues above by **Code Reality status**, which is the more actionable framing for anyone picking this up now.

**Fully implemented as decided:**
1.1.2 (RFQ wallet requirement), 1.1.3 (escrow timing/sequence), 1.2.1 (contract-creation trigger), 2.3.1 (RFQ prerequisites), 3.2.1 (async-except-validation), 3.2.2 (no external retry/circuit-breaker — confirmed by omission), 5.1.1 (manual verification acceptable), 5.2.1 (partial award), 6.1.1 (hybrid read/write module pattern), 6.1.2 (shared data access pattern).

**Implemented, but meaningfully different from what was decided (needs a decision-owner's attention, not just a doc fix):**
1.1.1 / 1.2.2 (trust score formula built correctly, but never wired into production — every provider frozen at default), 1.2.3 (settlement-trigger pattern right, cadence mechanics disputed between two epic docs), 2.1.1 (partial/split award solid, provider-rejection-reactivation flow unconfirmed), 2.1.3 (early-return endpoint exists, but no dual-approval/notice-period/penalty-preview UI), 2.3.2 (fleet-capacity checks real, trust-score bidding threshold almost certainly not enforced given 1.1.1's finding), 2.3.3 (a timeout-cancellation job exists; exact day-count/notify-vs-cancel behavior unconfirmed), 3.1.1 / 3.1.3 (the intended event sequence and outcomes are real; the formal saga/catalog/versioning architecture is not), 5.2.3 (configurable-policy architecture exists server-side; no client-facing calculator, exact numbers unconfirmed).

**Confirmed not implemented — open gaps, not documentation problems:**
3.1.2 (no exactly-once delivery, no universal idempotency keys, no dead-letter queue, no event sourcing/replay — outbox retry explicitly confirmed absent), **5.1.4 (no dispute-resolution workflow of any kind anywhere in the backend — the single highest-impact gap in this entire document, since Issues 2.1.2, 2.1.3, and 2.2.3 all silently depend on it existing)**.

**Policy-only / not meaningfully code-verifiable (organizational decisions, not implementation gaps):**
2.2.1, 2.2.2, 2.2.3 (approval SLAs/reviewer roles/thresholds), 4.1.1, 4.1.2, 4.1.3 (compliance enforcement detail) — the general systems these policies govern are confirmed to exist; the specific numbers/roles recorded were never meant to be "in code" per se.

**Deferred by the original document's own scoping (no action needed from this rewrite):**
4.2.1, 4.2.2, 4.2.3 (incident response, backup/recovery, monitoring — explicitly marked out-of-MVP-scope in the source).

**Not independently re-verified in this pass (check the specific code path before relying on either a yes or a no):**
2.1.1's provider-rejection-reactivation mechanic, 4.1.3's audit-trail specifics, 5.1.2's reject-without-penalty mechanic, 5.2.2's appeal-process/first-time-rejection tracking, 6.1.3's Redis caching for MasterData.

**Immediate next step if someone picks this document up to plan work:** build the dispute-resolution workflow (5.1.4) first — it's both the largest confirmed gap and the one the most other recorded decisions (2.1.2, 2.1.3, 2.2.3) assume already exists. Second priority: decide whether to wire `TrustScoreCalculator` into production events at all (1.1.1/1.2.2), since several tier/commission-rate features downstream of trust score currently operate on frozen, never-updated data.

---

**Questionnaire originally completed by:** the product owner, across the Nov 2025–mid 2026 window (exact sign-off name/date were never filled into the original template).
**This status layer completed by:** documentation rewrite pass, 2026-07-23, cross-checked against `project-docs/18_Implementation_Coverage_Audit.md` and the rewritten `backlog/mvp/epic-04` through `epic-12` files.

**END OF DOCUMENT**
