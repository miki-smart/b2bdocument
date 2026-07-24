# Movello MVP - Dispute Resolution Workflow

## Status: PROPOSED DESIGN — NOT IMPLEMENTED IN CODE

**Version:** 2.0 (rewritten against running code)
**Last verified against code: 2026-07-23**
**Document Status:** PROPOSED / FUTURE WORK — no part of this document, past §0, describes running code.
**Original version:** 1.0, dated December 2025 — presented this workflow as an authoritative, approved specification for a `Disputes` module. It was never built. Preserved only in git history; this rewrite keeps the useful design thinking but removes every claim of current implementation.
**Related documents:** [`project-docs/18_Implementation_Coverage_Audit.md`](../../../../project-docs/18_Implementation_Coverage_Audit.md) §5, §6, §10.4 (audit findings this rewrite is based on); [`project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md`](../../../../project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md) §3 (companion "Dispute & Arbitration Engine" design, same status, same date); [`backlog/mvp/epic-06-contract-management.md`](../../../../backlog/mvp/epic-06-contract-management.md) (real contract lifecycle — `DISPUTED`/`ON_HOLD` statuses); [`backlog/mvp/epic-10-monthly-renewal-settlement.md`](../../../../backlog/mvp/epic-10-monthly-renewal-settlement.md) Story 10.7 (settlement-dispute confirmation of absence); [`MVP_MODULE_INTEGRATION_SPECIFICATION.md`](./MVP_MODULE_INTEGRATION_SPECIFICATION.md) (rewritten alongside this doc — confirms there is no `Disputes` module in the real 8-module list); [`MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md`](./MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md) (confirms no `Debt` entity exists, which this design's non-payment category originally assumed)

---

## 0. Read this first

**Nothing in this document exists in the Movello codebase today.** This was the single biggest finding of the 2026-07-23 implementation coverage audit regarding disputes: there is no `Dispute` entity, no `DisputeEvidence`/`DisputeAction`-equivalent entity, no dispute controller, no dispute API endpoint, no dispute background job, no `Disputes` module, and no dispute-specific database table anywhere in the backend, web app, or either mobile app. Confirmed by repo-wide search across all four surfaces.

What *does* exist, and is the entire real footprint of "dispute" in the running system:

| What's real | Where |
|---|---|
| `DISPUTED` is a reserved value of the `ContractStatus` C# enum | `Modules/Contracts/Domain/Enums/ContractStatus.cs` |
| `ON_HOLD` is a reserved value of the same enum | same file |
| Both values are referenced defensively in a couple of guard clauses (e.g. the delivery/return status-aggregation function explicitly refuses to overwrite a `DISPUTED` status if it were ever set) and queried by one admin dashboard stat card | `Modules/Contracts/**` |
| `EscrowLock` (the real Finance-module entity, not the generic `EscrowContract` in the companion spec) has a `DISPUTED`-adjacent status value used by early-termination/freeze/partial-release commands | `Modules/Finance/Domain/Entities/EscrowLock.cs` |

That's the entirety of it. **No code path anywhere ever sets `Contract.Status` to `DISPUTED` or `ON_HOLD`** — both are enum members with zero producers, per the contract-cluster rewrite (`backlog/mvp/epic-06-contract-management.md`, `MVP_CONTRACT_STATE_MACHINE.md`). There is no `Disputes` module among the backend's real 8 (`Auth`, `Contracts`, `Delivery`, `Finance`, `Identity`, `Marketplace`, `MasterData`, `Notifications` — see `MVP_MODULE_INTEGRATION_SPECIFICATION.md` §1.1). There is no admin screen to open, evidence, or arbitrate a dispute; no evidence-upload endpoint; no SLA timer; no escalation job; no trust-score penalty wired to a dispute outcome; no financial-adjustment command scoped to "dispute resolution" as a concept. A business or provider who believes a delivery, vehicle condition, payment, or settlement is wrong today has **no in-product dispute path at all**. The only real, partially-overlapping feedback mechanisms that exist are:

- **Contract termination** (request → approve, Epic 06 Story 6.8) — either party can exit a running contract, but this ends the relationship, it does not adjudicate who was right or move money based on fault.
- **Contract completion rejection** (Epic 06 Story 6.9) — the other party can reject a completion request with a reason, which reverts the contract to `PARTIALLY_RETURNED`, but this is a binary block, not an evidence-and-arbitration workflow.
- **Provider VAT invoice approve/reject** (Epic 09 Story 9.5) — this is a withholding-tax reclaim mechanism, not a mechanism for contesting a settlement calculation.
- **Settlement payout admin approve/reject** (`MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` §3, Epic 10 Story 10.3) — an internal admin gate before money moves, not a provider- or business-facing dispute channel.

None of these give either party a structured way to raise "the vehicle wasn't as described," "the business hasn't paid," or "this settlement amount is wrong" and have it adjudicated with evidence, SLA tracking, and a financial/trust-score outcome. **That gap is real and unaddressed.** Everything below this line is retained design thinking for closing that gap — not documentation of anything running.

**How to read the rest of this document:** Section 1 states, in one place, exactly what is absent (so this file can be trusted as a negative-space reference — "is X real?" → check here first). Section 2 states the real, current risk this gap creates. Section 3 onward is the **original workflow design**, preserved close to its original form because the category/evidence/SLA/resolution thinking is still useful groundwork for a future build — but every heading from Section 3 onward is labeled **(PROPOSED)** and no code, API route, table, or job described past that point should be assumed to exist. Where the design assumes platform mechanics that don't match the real system (e.g., a symmetric business+provider trust score, GPS delivery-location data, a `Debt` entity, per-module Postgres schemas), that mismatch is called out inline rather than silently fixed, so a future implementer knows exactly what would need to be re-derived against the real `Modules/Contracts`/`Modules/Finance`/`Modules/Identity` code.

---

## 1. What's absent — the complete negative-space list

Confirmed by repo-wide search across backend, web, and both mobile apps as of 2026-07-23:

- **No `Dispute` entity, table, or migration** in any module (`Modules/Contracts`, `Modules/Finance`, `Modules/Identity`, or elsewhere). There is no `disputes` table anywhere in the single shared Postgres database.
- **No `DisputeEvidence`, `DisputeAction`, or dispute-timeline entity.**
- **No dispute API** — no `POST /disputes`, `GET /disputes/{id}`, `/evidence`, `/resolve`, `/escalate`, or any equivalent, on any controller, on any surface (web, business mobile, provider mobile, or admin).
- **No "Disputes" module at all.** The backend has 8 real module folders (`Modules/Auth`, `Modules/Contracts`, `Modules/Delivery`, `Modules/Finance`, `Modules/Identity`, `Modules/Marketplace`, `Modules/MasterData`, `Modules/Notifications`) — a `Modules/Disputes` referenced by earlier drafts of this document and by the original `MVP_MODULE_INTEGRATION_SPECIFICATION.md` text does not exist and was never built. See the rewritten `MVP_MODULE_INTEGRATION_SPECIFICATION.md` for the real module list.
- **No dispute-related domain events fire.** `DisputeCreatedEvent`, `DisputeEvidenceSubmittedEvent`, `DisputeResolvedEvent`, `DisputeEscalatedEvent` (as named in the original `MVP_EVENT_CATALOG_AND_HANDLERS.md`) do not exist as C# event classes anywhere in the codebase.
- **No SLA timer, escalation cron job, or admin "dispute queue" UI** on web or either mobile app.
- **No `Debt`/debt-tracking entity or auto-escalation-to-dispute job.** The 30-day "debt escalates to a dispute" mechanic this document originally assumed does not exist — there is no debt-tracking concept in `Modules/Finance` at all (confirmed again during the settlement-spec rewrite — see `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` §0); the closest real mechanic is `EscrowTimeoutJob` cancelling a contract stuck in `PENDING_ESCROW`, which is unrelated.
- **No dispute-driven trust-score adjustment.** Even if a dispute workflow existed, it could not currently feed into the real trust engine cleanly — the real `TrustScoreCalculator` formula (`Base + CompletionRate×20 + OnTimeRate×20 − NoShowRate×30 + RejectionPenaltyPoints`, see `project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md` §1.2) has no open slot for an arbitrary "dispute won/lost" signal the way this design's `DISPUTE_LOST`/`DISPUTE_WON` point adjustments assume; it would need a fifth term or a translation layer, not a direct plug-in. This is doubly moot today because, per that same document, the trust-score formula itself has **zero production call sites** — no code path recalculates any provider's score from real activity at all yet.
- **No business-side risk/trust score of any kind** exists to be adjusted by a dispute outcome — the real trust engine is provider-only (§1.1 of the trust/escrow spec).
- **No GPS/location data on deliveries.** `DeliverySession` has no latitude/longitude fields (confirmed in the audit and in `backlog/post-mvp/epic-15-geofence-gps-integration.md`, which is itself confirmed Not Started on every surface) — this design's "GPS logs" evidence type and "GPS proves provider was at location" auto-resolution branch have no data source to draw from even if built today.
- **No settlement-dispute path exists either**, confirmed definitively (not just "unconfirmed") by the `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` rewrite and `epic-10-monthly-renewal-settlement.md` Story 10.7: `SettlementController` has no `POST /settlements/{id}/dispute` or equivalent, and there is no dispute-related command, entity, or status in the Finance/Wallet domain at all beyond the same reserved `EscrowLock` `DISPUTED`-adjacent status noted above.

If you are checking "does the platform have a way to dispute X" for any reason — support tooling, sales conversations, a compliance review — **the answer is no, full stop**, and this document is the place that says so explicitly.

---

## 2. Why this matters (real, current risk — not proposed)

This is the one part of this document that describes a **real, current** state of affairs, not a proposal:

- A provider who believes a settlement payout under-counted their earnings has no formal recourse today (confirmed absent in `backlog/mvp/epic-10-monthly-renewal-settlement.md` Story 10.7 and `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` §8).
- A business that receives a vehicle it believes doesn't match the contract spec can request contract termination or refuse to approve completion, but cannot open a structured, evidence-backed case that results in a binding admin ruling, refund, or provider penalty.
- A provider facing a business that won't pay has no debt-escalation or dispute-filing path — the only real levers are contract termination and (if unpaid escrow ever caused a timeout) `EscrowTimeoutJob`'s cancellation of a not-yet-escrowed contract, which doesn't apply once a contract is `ACTIVE`.
- Admins have no dedicated dispute queue/inbox; anything resembling arbitration today happens outside the product (support channel, manual intervention), with no system-of-record trail.

This is flagged as an open product-prioritization decision in `project-docs/18_Implementation_Coverage_Audit.md` §9 — building it is a business call, not a documentation fix.

---

## 3. Proposed Design — Dispute Categories

**(PROPOSED — no code exists for any of this section)**

The following category taxonomy is retained from the original design as a reasonable starting point if a dispute system is built. It should be re-validated against the real contract/delivery/settlement mechanics (Epics 06, 07, 09, 10) before implementation, not built as-is.

### 3.1 Category 1: Vehicle Condition Dispute (proposed)

Dispute about vehicle quality, cleanliness, or functionality at delivery or return.

- **Who could raise it:** Business (at delivery — not as described, dirty, damaged, malfunctioning) or Provider (at return — damaged, dirty, missing items).
- **Evidence a real build would need:** photos (minimum count, timestamped), the real Delivery-module OTP confirmation timestamp for cross-reference (`Modules/Delivery`'s actual `DeliveryConfirmedEvent`/return-OTP data — not a generic "deliveryOTP: string" placeholder), and — since the real vehicle-inspection-checklist system already exists (`VehicleInspectionChecklist`, `DeliveryReturnSession`, per Epic 07) — a real build should attach that checklist's data automatically rather than re-inventing a parallel evidence format.
- **Proposed outcomes:** provider replaces vehicle / repairs at provider cost / business accepts as-is / cost-split — same shape as originally drafted, but any resulting refund or penalty would need to route through the real `Modules/Finance` escrow/wallet primitives (`EscrowLock`, `WalletLedgerTransaction`), not a generic `EscrowContract`/`LedgerEntry` model.

### 3.2 Category 2: Service Quality Dispute (proposed)

Business-only complaint about provider responsiveness, professionalism, or off-platform payment requests.

- **Proposed outcomes:** ranged from a warning (no financial impact) to contract termination + refund + provider suspension, with a trust-score penalty in between. As noted in §1, this can't cleanly plug into the real trust-score formula without extending it.

### 3.3 Category 3: Non-Payment Dispute (proposed)

Dispute about unpaid amounts. **This entire category assumed a `Debt`/grace-period mechanic that does not exist in the real codebase** — there is no grace-period, debt-tracking, or debt-escalation concept anywhere in `Modules/Finance` (confirmed again by `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md`'s rewrite — the real system has no "business suspended for unpaid debt" flow at all). A real build would need to either (a) design that debt/grace-period mechanic from scratch first, or (b) redefine this category around what actually exists today (e.g., disputing a settlement payout amount, or a Direct Rental wallet-balance gate — see `backlog/post-mvp/epic-21-direct-rental.md` Story 21.4).

### 3.4 Category 4: Delivery Issue Dispute (proposed)

Dispute about delivery timing, OTP sharing, or vehicle assignment mismatch. A real build should integrate with the actual Delivery module's OTP/checklist/`DeliverySLAViolation`/`DeliveryFailureReason` entities (which exist in the domain model and DbContext today but — per the audit — currently have **nothing writing to them**, so even the raw data this category would want to reference isn't being populated yet).

### 3.5 Category 5: Contract Terms Dispute (proposed)

Disagreement over contract interpretation, pricing, or alteration terms. Would reference the real `Contract`/`ContractLineItem`/`ContractAmendment` entities — noting that `ContractAmendment.Create()` currently has **zero callers anywhere in the codebase** (per Epic 06 Story 6.7), so "disputed amendment" isn't currently a reachable state to dispute in the first place.

---

## 4. Proposed Design — Creation, Evidence, and Validation

**(PROPOSED — illustrative pseudocode retained from the original draft; not real code, no framework/language commitment implied)**

```typescript
async function createDispute(request: DisputeCreateRequest): Promise<Dispute> {
  await validateDisputeEligibility(request);         // contract exists, requester is a party, contract not in a terminal state
  const existingDispute = await checkExistingDispute(request.contractId);
  if (existingDispute) throw new Error('Contract already has active dispute');

  const dispute = await this.disputeRepository.create({
    id: generateUUID(),
    contractId: request.contractId,
    createdBy: request.createdBy,
    creatorType: request.creatorType,   // BUSINESS | PROVIDER | SYSTEM | ADMIN
    category: request.category,
    description: request.description,
    status: 'OPEN',
    priority: calculatePriority(request.category),
    slaDeadline: addHours(new Date(), 48),
    createdAt: new Date()
  });

  await this.uploadEvidence(dispute.id, request.evidence);
  // A real implementation would transition Contract.Status to DISPUTED here via the
  // real Contracts-module domain method — which does not exist today; ContractStatus.DISPUTED
  // is a bare enum value with no state-machine transition into or out of it.
  await this.notifyCounterParty(dispute);
  await this.notifyAdminForReview(dispute);
  return dispute;
}
```

Evidence-type and per-category validation rules (minimum photo counts, file-size caps, accepted formats) from the original draft are still reasonable UX guardrails to reuse if this is built, and are omitted here in full to avoid duplicating a spec for something unbuilt — the original per-category evidence table (photos/video/documents/screenshots, size/format limits) is preserved in git history of this file if needed as a reference.

---

## 5. Proposed Design — Resolution Workflow

**(PROPOSED)**

```
1. DISPUTE CREATED
2. COUNTER-PARTY NOTIFIED (24h to respond)
3. COUNTER-PARTY SUBMITS EVIDENCE (optional)
4. ADMIN REVIEW (evidence + real platform data: contract history, wallet/ledger transactions,
   delivery/return OTP timestamps, checklist data — GPS data is NOT available, see §1)
5. RESOLUTION DECISION (party A wins / party B wins / split / need more info)
6. RESOLUTION EXECUTION (financial adjustment via real Finance-module wallet primitives,
   contract status update, trust-score impact where the real formula allows it, account
   action if warranted)
7. NOTIFICATIONS to both parties with reasoning
8. DISPUTE CLOSED
```

Resolution-criteria decision trees per category (vehicle-condition photo-timestamp cross-check, non-payment calculation verification, etc.) from the original draft remain reasonable starting logic, contingent on the category redesign noted in §3.3 for non-payment specifically.

---

## 6. Proposed Design — SLA & Escalation

**(PROPOSED)**

- Counter-party response window: 24 hours
- Admin resolution target: 48 hours (24 hours for high-priority)
- Escalation triggers: SLA breach, contract value above a threshold, repeat-offender party (3+ prior disputes), suspected fraud, complex/high-evidence-volume case
- An hourly SLA-check job and an escalation-to-senior-admin flow were originally specified; no such job exists in code (the real background-job roster is `EscrowTimeoutJob`, `ExpireDirectRentalRequestsJob`, `DailyLedgerJob`, `ContractEndLifecycleJob` — none are dispute-related).

---

## 7. Proposed Design — Resolution Outcomes & Financial Adjustment

**(PROPOSED)**

Outcome types (claimant/respondent full win, partial splits, dismissal, "need more info") and category-specific action tables (vehicle-condition penalty math, non-payment 5% dispute-processing fee, service-quality discount/warning) are retained as directional design. Any real implementation must replace generic `refundService`/`walletService.transfer`/`penaltyService`-style calls with the real Finance-module mechanics:

- Refunds/releases would need to go through `EscrowLock` state transitions and `WalletLedgerTransaction`/`WalletLedgerEntry` double-entry postings — not a generic `LedgerEntry` table.
- A "penalty" concept already exists in the domain (`ContractPenalty` — `Create`/`MarkPaid`/`Waive`/`Dispute` methods) but per Epic 06 Story 6.7, **`ContractPenalty.Create()` has zero callers anywhere today** — it would need to be wired up as part of building this, not assumed to already work.

---

## 8. Proposed Design — Trust-Score Integration

**(PROPOSED, and currently a bigger lift than it originally appeared)**

The original `DISPUTE_LOST` (−15) / `DISPUTE_WON` (+3) point-adjustment idea assumed:

1. A symmetric business + provider trust score — **only the provider side exists today.**
2. An open-ended "signal" mechanism the dispute engine could push points into — **the real formula (`Base + CompletionRate×20 + OnTimeRate×20 − NoShowRate×30 + RejectionPenaltyPoints`) has no such slot; it would need a new term or a mapping layer.**
3. That the formula is live and recalculating — **it isn't; `TrustScoreCalculator` has zero production call sites today (per `project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md` §1.2), so wiring dispute outcomes to it would be building on top of an already-dormant mechanism.**

Building dispute→trust integration therefore has two prerequisites that are themselves unbuilt: (a) wiring the trust formula into production events at all, and (b) deciding how a dispute signal composes with the existing four terms.

---

## 9. Proposed Design — Database Schema (illustrative only)

**(PROPOSED — captures the shape of tables a real build might need; not a schema that exists anywhere)**

The original draft's `disputes` / `dispute_evidence` / `dispute_timeline` table definitions (party IDs, category, status, resolution, SLA fields, evidence metadata) remain a reasonable starting point for column shape, with one correction if reused:

- The real database is **one shared Postgres database with no per-module schema isolation** (per `MVP_MODULE_INTEGRATION_SPECIFICATION.md` §1.2 and `project-docs/service-specs/contract-engine-spec.md` §7 — snake_case naming via EFCore.NamingConventions, no `contracts_schema`/`finance_schema`/`disputes_schema` split anywhere). A `disputes_schema.*` prefix, as earlier drafts of this document and the pre-rewrite `MVP_MODULE_INTEGRATION_SPECIFICATION.md` both showed, does not match how any real module is organized in this codebase; a real implementation would add plain tables (e.g. `disputes`, `dispute_evidence`, `dispute_timeline`) alongside the rest, following the existing convention.
- `contract_id` should reference the real `contracts.id` primary key as it exists today, and any `business_id`/`provider_id` columns should resolve against the real `Modules/Identity` entities, not placeholder UUIDs.

---

## 10. What a real build would actually require (summary)

If this is picked up as a project, in rough dependency order:

1. **A real `Dispute`/`DisputeEvidence` entity and migration** inside a new module (or inside `Modules/Contracts`, given the tight coupling to contract state) — none exists today.
2. **A real state-machine wiring for `Contract.Status = DISPUTED`/`ON_HOLD`** — today these are inert enum values with no transition methods on the `Contract` aggregate.
3. **A decision on how dispute resolution moves money** — against the real `EscrowLock`/`WalletLedgerTransaction` primitives in `Modules/Finance`, not a generic ledger model.
4. **Trust-score wiring** (§8) — a prerequisite piece of work that doesn't exist yet regardless of disputes.
5. **A redesign of the Non-Payment category** (§3.3) around what payment/debt mechanics actually exist, since the original assumed a `Debt` entity that was never built.
6. **A settlement-specific dispute hook**, if desired — today there is no `POST /settlements/{id}/dispute` and none of `SettlementController`'s modeled `SettlementStatusHistory` triggers cover a dispute concept (see `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` §8).
7. **Admin, business, and provider UI** on web and both mobile apps — none exists today.

None of the above should be inferred as "in progress" from this document's existence — it is a design reference only, dated 2026-07-23, for a feature that has not been started.
