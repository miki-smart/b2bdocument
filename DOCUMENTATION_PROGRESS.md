# MVP_MODULAR Documentation — Currency Tracker

**Last verified against code:** 2026-07-23
**Status:** Repurposed. Originally this file tracked *how many pre-implementation spec documents had been authored* (a writing-progress checklist, dated November 26, 2025, when none of the code existed yet). The product is now substantially built — 12 MVP epics and partial post-MVP work (see `00_EXECUTIVE_SUMMARY.md`) — so "% of docs written" is no longer a useful thing to track. This file now tracks **which documents in this `MVP_MODULAR/` tree have been reverified against running code, and which still reflect the pre-implementation plan.**
**Primary source of truth for implementation status:** `project-docs/18_Implementation_Coverage_Audit.md` — a 2026-07-23, code-grounded audit covering backend, web, and both Flutter mobile apps against all 21 product epics. This file only tracks documentation *currency inside this specific folder*; for "is feature X actually built," read the audit, not this file.

---

## How to read this file

- **✅ Rewritten** — re-verified against running code as part of the 2026-07-23 audit-driven rewrite pass (this file's own pass, or an earlier one covering the contract cluster). Treat as current.
- **✔️ Confirmed accurate (not rewritten)** — the audit specifically checked this file against code and found it already correct; no rewrite was needed.
- **⚠️ Not reverified** — still reflects the November 2025 pre-implementation plan. May be partially or wholly accurate by coincidence, but has not been checked against code in this pass. Do not cite it as a current spec without verifying first.
- **🔴 Known stale** — specifically flagged as likely or confirmed wrong (usually because it was written for an architecture/frontend stack that was never actually built).

---

## File-by-file status

### Root-level

| File | Status | Note |
|---|---|---|
| `00_EXECUTIVE_SUMMARY.md` | ✅ Rewritten | Corrected epic/story counts (21 epics, 129 stories), tech stack (React not Angular, no separate BFF service), and current implementation status |
| `01_ARCHITECTURE_OVERVIEW.md` | ✅ Rewritten | Corrected module list (8 real modules, not 5 or 7), removed fictional YARP/BFF-gateway topology, added current-vs-proposed split |
| `DOCUMENTATION_PROGRESS.md` | ✅ Rewritten | This file — repurposed from a doc-writing tracker into a doc-currency tracker |
| `02_DATABASE_SCHEMA_DESIGN.md` | ⚠️ Not reverified | Predates code; schema/table counts were written before any migration existed. Treat as historical/aspirational only |
| `03_API_SPECIFICATIONS.md` | ⚠️ Not reverified | Same caveat — written before real controllers existed |
| `05_BUSINESS_LOGIC_FLOWS.md` | ⚠️ Not reverified | Likely describes pre-implementation flows (e.g. RFQ escrow-check timing) that may have since changed — cross-check against `CRITICAL_BUSINESS_RULE_UPDATE.md` and the relevant epic before trusting either |
| `06_FRONTEND_ARCHITECTURE.md` | 🔴 Known stale (assumed) | Named and dated for the original plan; given that plan specified Angular 19 and the real web app is React 18.3 + Vite (`architecture` peers `.agent/roles/frontend-developer.md` and `markdown-documentations/Frontend_Architecture_Guide.md` both had this exact Angular-vs-React drift confirmed), this file should be treated as wrong until specifically re-verified. Not opened as part of this pass — flagged, not fixed |
| `07_EVENT_DRIVEN_PATTERNS.md` | ⚠️ Not reverified | Likely still frames RabbitMQ as the primary bus rather than MediatR — see `01_ARCHITECTURE_OVERVIEW.md` §1.4 for the corrected picture |
| `08_SECURITY_COMPLIANCE.md` | ⚠️ Not reverified | Cross-check against `architecture/auth-service-microservice-spec.md` (rewritten, authoritative) before trusting |
| `09_DEPLOYMENT_GUIDE.md` | ⚠️ Not reverified | Cross-check against real `backend/docker-compose*.yml` files (see `01_ARCHITECTURE_OVERVIEW.md` §1.7) — likely still describes a BFF container that doesn't exist |
| `10_TESTING_STRATEGY.md` | ⚠️ Not reverified | |
| `Business_Rules.md` | ⚠️ Not reverified | |
| `CRITICAL_BUSINESS_RULE_UPDATE.md` | ⚠️ Not reverified | Documents one specific rule change (escrow check moved from RFQ-creation to award-time); worth checking against current bidding-award code before trusting, but plausible as still-accurate given it reads as a mid-build correction rather than a day-one plan |
| `UI_System_Design_Guidelines.md` | ⚠️ Not reverified | |
| `FRONTEND_AI_PROMPT.md` | ⚠️ Not reverified | |
| `UI_DESIGN_GENERATION_PROMPT.md` | ⚠️ Not reverified | |

### `04_MODULE_SPECIFICATIONS/`

| File | Status | Note |
|---|---|---|
| `Contracts_Module.md` | ✅ Rewritten | Rewritten alongside the contract-cluster pass (with `epic-06-contract-management.md` and `MVP_CONTRACT_STATE_MACHINE.md`) — current |
| `Auth_and_Keycloak_Module.md` | ⚠️ Not reverified | Cross-check against `architecture/auth-service-microservice-spec.md` (rewritten, authoritative) — likely still describes Auth as a separate service |
| `Delivery_Module.md` | ⚠️ Not reverified | Likely missing the return-trip OTP + inspection checklist system documented in `backlog/mvp/epic-07-otp-delivery-verification.md`'s rewrite |
| `Finance_Module.md` | ⚠️ Not reverified | Cross-check against `backlog/mvp/epic-08-wallet-escrow.md` (rewritten) — likely undersells payment-gateway maturity |
| `Identity_and_Compliance_Module.md` | ⚠️ Not reverified | Cross-check against `backlog/mvp/epic-12-risk-trust-scoring.md` (rewritten) — likely presents trust scoring as live/wired when it is currently unwired from production events |
| `Marketplace_Module.md` | ⚠️ Not reverified | Cross-check against `backlog/mvp/epic-04-rfq-management.md` / `epic-05-bidding-engine.md` (both rewritten) — likely predates the line-item/split-award model |
| `Master_Data_and_Settings_Module.md` | ⚠️ Not reverified | Cross-check against `markdown-documentations/Master_Data_Specification.md` |

### `MVP_final_docs/`

| File | Status | Note |
|---|---|---|
| `MVP_CONTRACT_STATE_MACHINE.md` | ✅ Rewritten | Authoritative, current — the full 18-state Contracts lifecycle model. Cross-referenced extensively from `00_EXECUTIVE_SUMMARY.md` and `01_ARCHITECTURE_OVERVIEW.md` in this pass |
| `MVP_DIRECT_RENTAL_SPECIFICATION.md` | ✔️ Confirmed accurate | Per `project-docs/18_Implementation_Coverage_Audit.md` §7.1, this doc is real and correct — its only issue was being disconnected from the epic index, now fixed by `backlog/post-mvp/epic-21-direct-rental.md` |
| `MVP_DIRECT_RENTAL_STATE_MACHINE.md` | ✔️ Confirmed accurate | Same as above |
| `MVP_ADMIN_WALLET_OPERATIONS_SPECIFICATION.md` | ⚠️ Not reverified | |
| `MVP_AUTHORITATIVE_BUSINESS_RULES.md` | ⚠️ Not reverified | |
| `MVP_DISPUTE_RESOLUTION_WORKFLOW.md` | ⚠️ Not reverified | Cross-check against `project-docs/18_Implementation_Coverage_Audit.md` §5, §8 — no dispute-engine entities exist anywhere in code today; this doc may describe a workflow with nothing behind it, the same gap already confirmed in `project-docs/11_Trust_Escrow_Dispute_Engines_Spec.md` |
| `MVP_EVENT_CATALOG_AND_HANDLERS.md` | ⚠️ Not reverified | Cross-check against the real event-flow diagrams in `MVP_CONTRACT_STATE_MACHINE.md` §10 for at least the Contracts-module subset |
| `MVP_MODULE_INTEGRATION_SPECIFICATION.md` | ⚠️ Not reverified | |
| `MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` | ⚠️ Not reverified | Cross-check against `backlog/mvp/epic-10-monthly-renewal-settlement.md` (rewritten) — note the settlement-cadence contradiction flagged in the coverage audit §10.4 (tier-based cadence vs. rolling 30-day cycle) is still unresolved in code as of 2026-07-23 |
| `SETTLEMENT_ENHANCEMENTS_ADDENDUM.md` | ⚠️ Not reverified | Same cadence caveat as above |

### `database/`, `frontendguides/`

| File(s) | Status | Note |
|---|---|---|
| `database/database-erd.md`, `database/database-schema-design.md` | ⚠️ Not reverified | Same caveat as `02_DATABASE_SCHEMA_DESIGN.md` |
| `frontendguides/*.md` (12 files: `ADMIN_PORTAL_GUIDE.md`, `API_INTEGRATION_SPEC.md`, `AUTHENTICATION_GUIDE.md`, `BUSINESS_ANALYSIS_QUESTIONNAIRE.md`, `BUSINESS_LOGIC_IMPLEMENTATION.md`, `BUSINESS_PORTAL_GUIDE.md`, `FORM_VALIDATIONS_SPEC.md`, `LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md`, `ONBOARDING_GUIDE.md`, `PROVIDER_PORTAL_GUIDE.md`, `REALTIME_FEATURES.md`, `SEARCH_FILTER_PAGINATION.md`, `USER_STORIES_COMPLETE.md`) | ⚠️ Not reverified | Not opened as part of this pass. Given the confirmed Angular-vs-React drift found elsewhere in the repo (`.agent/roles/frontend-developer.md`, `markdown-documentations/Frontend_Architecture_Guide.md`, `markdown-documentations/FRONTEND_AUDIT_REPORT.md` — all rewritten already per `project-docs/18_Implementation_Coverage_Audit.md` §8), these guides are a reasonable next place to look for the same drift; treat with suspicion until checked |

---

## Historical snapshot (preserved for reference only — do not treat as current)

The original version of this file, dated November 26, 2025, recorded 8 of a planned 17 documents as "complete" (191.4 KB, ~5,626 lines) at a point when **zero production code existed yet** — "complete" meant "the pre-implementation spec was written," not "the feature is built and matches the spec." That distinction matters: several of those 8 "complete" documents (`00_EXECUTIVE_SUMMARY.md`, `01_ARCHITECTURE_OVERVIEW.md`, `Identity_and_Compliance_Module.md` — now `04_MODULE_SPECIFICATIONS/Identity_and_Compliance_Module.md`, `Marketplace_Module.md` — now `04_MODULE_SPECIFICATIONS/Marketplace_Module.md`) described an Angular frontend, a YARP BFF, and a 5-module backend that were never built as specified. Being "complete" as a writing task did not make them accurate, and two of the five (Executive Summary, Architecture Overview) needed a full rewrite in this pass as a direct result.

---

## Recommended order for a future rewrite pass on the remaining ⚠️ files

Highest-value first, based on how far the coverage audit found each underlying area to have diverged:

1. `04_MODULE_SPECIFICATIONS/Marketplace_Module.md` and `04_MODULE_SPECIFICATIONS/Finance_Module.md` — RFQ/bidding and wallet/escrow are among the most-diverged areas per the audit
2. `06_FRONTEND_ARCHITECTURE.md` — highest suspicion of being flatly wrong (Angular vs. React)
3. `04_MODULE_SPECIFICATIONS/Auth_and_Keycloak_Module.md` — cross-check against the already-rewritten `architecture/auth-service-microservice-spec.md`
4. `MVP_final_docs/MVP_DISPUTE_RESOLUTION_WORKFLOW.md` — likely describes a workflow with zero supporting code (no dispute-engine entities exist anywhere)
5. `MVP_final_docs/MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md` and `SETTLEMENT_ENHANCEMENTS_ADDENDUM.md` — resolve the tier-based-vs-rolling-30-day settlement cadence contradiction in code first (coverage audit §10.4), then rewrite both consistently
6. Everything else in `04_MODULE_SPECIFICATIONS/`, then `05`–`10`, then `frontendguides/`, then `database/`

---

**Next Document:** [00_EXECUTIVE_SUMMARY.md](./00_EXECUTIVE_SUMMARY.md)
