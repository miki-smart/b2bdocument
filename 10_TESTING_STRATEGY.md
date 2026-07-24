# Testing Strategy

**Version:** 2.0
**Last verified against code:** 2026-07-23
**Original date:** November 26, 2025 (v1.0, MVP planning draft — see §0)

---

## 0. What changed in this revision

v1.0 named a toolset that isn't in this repo — Testcontainers and Playwright appear nowhere in the actual test projects — and implied a Kubernetes-scale "70/20/10 pyramid" with a nightly Playwright suite that was never built. What actually exists is a single xUnit test project for the backend (`Marketplace.Tests`) using **EF Core InMemory** (not Testcontainers) for its integration-style tests, plus a **standalone Cypress project** (`movello-marketplace-e2e`) that tests the web frontend against the real backend over HTTP — not Playwright, and explicitly not covering either Flutter mobile app. This rewrite is built from the real project files: `backend/tests/Marketplace.Tests/Marketplace.Tests.csproj` and its source tree, `backend/.github/workflows/ci-production.yml`, and `movello-marketplace-e2e/package.json`/`README.md`/`cypress/e2e/`.

---

## 1. Testing Surfaces (real, not a weighted pyramid)

| Surface | Project | Frameworks | Scope |
| --- | --- | --- | --- |
| Backend unit + "integration" | `backend/tests/Marketplace.Tests/` | xUnit, Moq, FluentAssertions, EF Core InMemory, `Microsoft.AspNetCore.Mvc.Testing` | Domain/handler/validator logic, controller-boundary behavior, architecture/convention rules, in-process HTTP tests against an in-memory DB. |
| Web + backend E2E | `movello-marketplace-e2e/` (standalone repo/folder, no shared code with the web app) | Cypress 13.6, TypeScript | Browser-driven flows against a running web app + running backend, over HTTP. Web + backend only — **not** the Flutter apps. |
| Mobile (business app, provider app) | — | — | **No automated test suite found for either Flutter app in this pass** — treat mobile QA as manual/unverified until a `flutter test` suite is located and confirmed. |

There is no weighted "70/20/10" split enforced anywhere (no code-coverage gate in CI ties a percentage to a category) — treat that framing as aspirational, not a real, measured target.

---

## 2. Backend Test Project (`Marketplace.Tests`)

### 2.1 Real dependencies (`Marketplace.Tests.csproj`)

```xml
<TargetFramework>net9.0</TargetFramework>
<PackageReference Include="FluentAssertions" Version="8.8.0" />
<PackageReference Include="Microsoft.AspNetCore.SignalR.Client" Version="9.0.0" />
<PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="9.0.0" />
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.8.0" />
<PackageReference Include="MockQueryable.Moq" Version="7.0.3" />
<PackageReference Include="Moq" Version="4.20.72" />
<PackageReference Include="xunit" Version="2.6.2" />
<PackageReference Include="Microsoft.EntityFrameworkCore.InMemory" Version="9.0.0" />
```

**Testcontainers is not a dependency of this project.** There is exactly one test project for the entire backend (`ProjectReference` to `Marketplace.API.csproj` directly) — no separate integration-test assembly.

### 2.2 Real folder structure

```text
Marketplace.Tests/
├── Common/
│   ├── Builders/       12 test-data builders (ContractBuilder, WalletAccountBuilder,
│   │                   MockRFQBuilder, MockProviderBuilder, EscrowLockBuilder, ...)
│   ├── Extensions/
│   ├── Fixtures/
│   └── Mocks/
├── Unit/
│   ├── Architecture/            ControllerArchitectureTests.cs — real convention/architecture test
│   ├── BackgroundServices/
│   ├── Infrastructure/          Persistence, Seeders
│   ├── Modules/                 Contracts, Delivery, Finance, Identity, Marketplace, MasterData, Notifications
│   │                            (each with Domain/Entities + Application/{Commands,Queries,Validators,EventHandlers})
│   └── Shared/                  Behaviors (ValidationBehavior, LoggingBehavior, QueryNoTrackingBehavior), Services
└── Integration/
    ├── BFF/                     AuthControllerTests.cs, BffTestAuthHandler.cs, BffWebApplicationFactory.cs
    ├── Infrastructure/          CustomWebApplicationFactory.cs, TestAuthHandler.cs, TestJsonOptions.cs
    ├── Mocks/                   MockAuthService.cs, TestAuthHandler.cs
    ├── Modules/
    │   ├── Contracts/           ContractCompletionIntegrationTests.cs
    │   └── Marketplace/         AdminDirectRentalControllerIntegrationTests.cs
    ├── Notifications/           NotificationHubIntegrationTests.cs (real SignalR client against a live hub)
    └── MarketplaceWebApplicationFactory.cs
```

As of this pass: **144 test source files**, **115 of which contain at least one `[Fact]`/`[Theory]`** — the suite is real and substantial, concentrated in the Finance, Contracts, Marketplace, and Identity modules (escrow, settlement, RFQ/bid, contract-completion logic).

### 2.3 Unit tests — real scope

Ordinary xUnit/Moq/FluentAssertions tests against domain entities, MediatR command/query handlers (repositories mocked, often via `MockQueryable.Moq` for `IQueryable`-returning mocks), FluentValidation validators, and the three MediatR pipeline behaviors introduced by the backend remediation work (`ValidationBehaviorTests`, `LoggingBehavior`, `QueryNoTrackingBehavior` — see `architecture/backend-remediation-roadmap-2026-07-12.md` Phase 1/3). Money-path coverage is real and specifically called out in the roadmap: escrow lock/release/partial-release guard tests, deposit-funds guard tests (wallet not found, inactive, wrong account type, non-positive amount).

**A real architecture/convention test exists** — `Unit/Architecture/ControllerArchitectureTests.cs` — using reflection over the `Marketplace.API` assembly to assert a convention holds across every controller (e.g., that no controller still uses a manual `GetCurrentUserId()` helper instead of the shared `IUserContextService`, with an explicit allow-list that is checked to be empty). This is the one test in the suite that enforces a codebase-wide convention rather than a single unit's behavior — a real, if currently thin, guardrail against the kind of drift `module-layout-convention.md` and the remediation roadmap describe. There is room to grow this folder; today it holds a single test class.

### 2.4 "Integration" tests — real scope and a real caveat

The `Integration/` folder uses `Microsoft.AspNetCore.Mvc.Testing`'s `WebApplicationFactory<Program>` to boot the real `Marketplace.API` in-process and issue real HTTP requests against it — this part matches "integration test" in the normal sense (real middleware pipeline, real controllers, real MediatR/validation/authorization behavior). **However, every one of the three factories in this project (`CustomWebApplicationFactory`, `MarketplaceWebApplicationFactory`, `BffWebApplicationFactory`) overrides the `DbContext` registration to use `UseInMemoryDatabase`, not a real PostgreSQL instance.** There is no `UseNpgsql`, no `localhost:5432` connection, and no `StackExchange.Redis`/`ConnectionMultiplexer` usage anywhere in the test project — confirmed by a repo-wide search. Practically: these tests validate HTTP routing, model binding, authorization policy enforcement, and application-layer logic end-to-end through EF Core's in-memory provider — they do **not** validate real SQL behavior (constraints, migrations, provider-specific query translation) or real Redis/RabbitMQ behavior. Do not describe this suite as "real SQL queries against a containerized DB," per v1.0 — that specific claim is false for the current implementation.

The one exception to "everything HTTP-only" is `Integration/Notifications/NotificationHubIntegrationTests.cs`, which uses the real `Microsoft.AspNetCore.SignalR.Client` package to connect to and exercise the live `NotificationHub` inside the `WebApplicationFactory`-hosted app — a genuine real-time-transport integration test, not just a controller-request test.

`Integration/BFF/` specifically tests the cookie-based web auth flow (`AuthControllerTests.cs`) using a custom `BffTestAuthHandler`/`BffWebApplicationFactory` pair — i.e., the in-process `BffTokenRefreshMiddleware` behavior described in `08_SECURITY_COMPLIANCE.md` §2.2 has direct test coverage, not just unit coverage of its pieces.

### 2.5 What CI actually runs (`backend/.github/workflows/ci-production.yml`, mirrored by `ci-development.yml`)

```yaml
services:
  postgres: { image: postgres:16-alpine, ports: ["5432:5432"] }
  redis:    { image: redis:7-alpine,    ports: ["6379:6379"] }
steps:
  - dotnet restore Marketplace.sln
  - dotnet build Marketplace.sln --configuration Release
  - dotnet test Marketplace.sln --configuration Release --logger trx --results-directory TestResults
    env:
      ConnectionStrings__DefaultConnection: "Host=localhost;Port=5432;..."
      ConnectionStrings__Redis: "localhost:6379"
      BlindBidding__SaltSecret: "ci-test-salt"
```

CI **does** spin up real ephemeral Postgres and Redis service containers and points connection-string environment variables at them — but per §2.4, no test in the current suite actually connects to either: the `WebApplicationFactory`-based tests override to EF Core InMemory, and no test uses `StackExchange.Redis` directly. These two service containers exist so the app's configuration doesn't fail to resolve a connection string at startup, not because the current test suite exercises them. This is worth a cleanup/verification ticket (either the Postgres/Redis containers are genuinely unused and can be removed, or some currently-uninventoried code path does depend on them and that dependency should be made explicit) — not something to paper over in downstream docs. `.trx` results are uploaded as a CI artifact (`test-results-production`) on every run, pass or fail.

**No dedicated SAST/DAST/coverage-threshold step gates this pipeline** — `dotnet test` passing is the only gate before an image is built and (on `main`) pushed.

---

## 3. Web + Backend E2E Suite (`movello-marketplace-e2e`)

### 3.1 What it actually is

A **standalone project**, deliberately kept separate from `movello-marketplace-core` (no shared code, own `package.json`) so frontend builds never carry test overhead. It drives the real web app via Cypress and asserts against the real backend API's effects — **it does not test either Flutter mobile app**, and by its own README, deliberately excludes CI/CD, Docker, and any deployment automation ("Per your requirements, this test project excludes: CI/CD pipelines... Docker containers... These tests are designed to run locally on your development machine").

- **Framework:** Cypress 13.6.0 + TypeScript 5.3, Page Object Model (`cypress/support/pages/`), 31 custom commands (`cypress/support/commands.ts`).
- **Targets:** frontend at `http://localhost:8060` (`movello-marketplace-core`, `npm run dev`), backend at `http://localhost:5207` (`dotnet run`) — both must be running locally; there is no containerized or CI-hosted variant of this suite today.
- **Test data:** fixture-driven — 4 businesses (B1–B4), 4 providers (P1–P4) with 25 vehicles each (100 total), 16 RFQs, 1 admin — plus PDF fixtures for the 7 document types used across KYC/KYB/insurance uploads.

### 3.2 Planned vs. actually implemented — a real, material gap

The suite's own README documents a **planned** scope of **80 test cases across 13 modules** (registration → wallet → vehicles → RFQ → bidding → awards → contracts → assignments → delivery → settlement → returns → edge-cases → cross-actor integration), matching the platform's real end-to-end lifecycle. As of the README's own last-updated status table, however, **only 27 of the 80 planned tests are actually implemented (34%)** — confirmed by the real file listing:

```text
cypress/e2e/
├── smoke.cy.ts              4 tests  — implemented
├── 01-registration/         9 tests  — implemented (business-registration, provider-registration, admin-verification)
├── 02-wallet/               4 tests  — implemented (wallet-operations)
├── 03-vehicles/             5 tests  — implemented (vehicle-operations)
├── 04-rfq/                  5 of 6   — implemented (rfq-operations)
├── 05-bidding/  … 13-integration/    — NOT implemented; no directories exist yet
```

Modules 5 through 13 (bidding, awards, contracts, assignments, delivery, settlement, returns, edge-cases, cross-actor integration — 53 of the 80 planned tests) have **no spec files at all** — not partially written, not stubbed, simply not started. Do not describe this suite as "80 test cases covering the full marketplace lifecycle" without this qualifier; describe it as "a 4-module (17 test) subset of a 13-module (80 test) plan, covering registration, wallet, vehicle onboarding, and RFQ creation," until the remaining modules are built.

### 3.3 Execution model

Tests are **designed to run sequentially, in module order** (`npm run test:registration` → `test:wallet` → `test:vehicles` → `test:rfq` → ...) because later modules' fixtures depend on state created by earlier ones (e.g., bidding tests would need the vehicles/RFQs the earlier modules create) — this is not a suite designed for arbitrary parallelization across modules. `npm run test:smoke` (4 tests: app loads, login works, API reachable) is the intended fast pre-flight check before a full run. There is no scheduled/nightly run of this suite configured anywhere (no CI integration exists per §3.1) — it is triggered manually by a developer today.

---

## 4. Mobile Testing — not verified in this pass

No automated test directory (`test/`, `integration_test/`) was confirmed for either `movello-mobile/business_app` or `movello-mobile/provider_app` in this pass. If a `flutter test`/`integration_test` suite exists, it was not part of the files reviewed for this rewrite — do not claim mobile test coverage numbers without checking `movello-mobile/*/test/` and `*/.github/workflows/ci.yml` (if present) directly first. Treat mobile QA as unverified rather than either "covered" or "absent" until that check is done.

---

## 5. Real vs. Aspirational Summary

| v1.0 claim | Reality |
| --- | --- |
| Testcontainers (real Postgres/Redis per test run) | Not a dependency of the test project; integration tests use EF Core InMemory (§2.4). |
| Playwright E2E | Cypress, in a separate standalone project (§3). |
| "70/20/10" weighted pyramid with a coverage gate | No coverage threshold enforced anywhere in CI; the split is not measured. |
| "Real SQL queries against a containerized DB" | EF Core InMemory-backed `WebApplicationFactory` tests — no real Postgres query execution in the current suite (§2.4). |
| Nightly nightly E2E run | No CI integration for the Cypress suite exists at all; it's run locally, on demand (§3.1, §3.3). |
| 80 E2E test cases, full lifecycle coverage | 27 of 80 implemented (34%), covering registration/wallet/vehicles/RFQ only; bidding through cross-actor-integration (modules 5–13) have zero spec files (§3.2). |
| Mobile apps covered by the same testing strategy | Not verified — no mobile automated-test evidence found in this pass (§4). |

---

## Related documents

- `09_DEPLOYMENT_GUIDE.md` §4 — the same CI workflow this document analyzes from a build/deploy angle.
- `08_SECURITY_COMPLIANCE.md` §2.2 — the BFF/cookie flow covered by `Integration/BFF/AuthControllerTests.cs`.
- `architecture/backend-remediation-roadmap-2026-07-12.md` — source of the money-path unit-test additions referenced in §2.3.

**Next Document:** [Business_Rules.md](./Business_Rules.md)
