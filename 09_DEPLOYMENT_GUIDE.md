# Deployment Guide

**Version:** 2.0
**Last verified against code:** 2026-07-23
**Original date:** November 26, 2025 (v1.0, MVP planning draft — see §0)

---

## 0. What changed in this revision

v1.0 described a Kubernetes-adjacent microservices topology that was never built: Traefik as an edge router, a standalone YARP "BFF" gateway service, an Angular frontend served by its own Nginx container, and one monolithic `docker-compose.yml` wiring all of it together under `movello.et` domains. None of that exists in this repo.

What is actually deployed is a **single .NET 9 modular monolith** (`Marketplace.API`) plus a **separately-deployed React web app** (`anqelbacarrental-marketplace-core`), each with its own environment-split Docker Compose files and its own GitHub Actions pipeline, talking to shared/standalone infrastructure containers (Postgres, Redis, MinIO, RabbitMQ, Keycloak). Both Flutter mobile apps are distributed through app stores, not through this deployment pipeline, and are out of scope for this document. This rewrite is built directly from the real files: `marketplace-project-implementation/backend/docker-compose*.yml`, `Dockerfile`, `.github/workflows/ci-development.yml`/`ci-production.yml`; `marketplace-project-implementation/anqelbacarrental-marketplace-core/docker-compose*.yml`, `Dockerfile`, `.github/workflows/deploy-development.yml`/`deploy-production.yml`.

---

## 1. Real Deployment Topology

```text
                        Single Production VPS
                        ─────────────────────
Internet ──▶ :5100 ──▶ marketplace-api (Marketplace.API) container
                            on Docker network "marketplace-prod-network"
                            │
                            ├──▶ postgres-prod   (internal only, no host port)
                            ├──▶ redis-prod      (internal only, no host port)
                            ├──▶ minio-prod      (127.0.0.1 only)
                            ├──▶ rabbitmq-prod   (127.0.0.1 only)
                            └──▶ keycloak        (shared container, own Postgres,
                                                   attached to both dev + prod networks)

Internet ──▶ :<web-port> ──▶ anqelbacarrental-marketplace-core (web) container
                            separate Compose project, its own Dockerfile/Nginx serve
```

There is **no shared root `docker-compose.yml`** that stands up the whole platform in one command. Backend and web are **two independent Compose projects, each with dev/prod variants**, deployed by two independent CI pipelines. There is no Traefik/Nginx-as-edge-router, no YARP gateway, and no containerized "frontend served behind the API" — the API container is the actual public edge for backend traffic (host port `5100` in the reviewed production compose), and the web app is deployed and served as its own container.

---

## 2. Backend (`Marketplace.API`) — Compose Files

All paths relative to `marketplace-project-implementation/backend/`.

| File | Role |
| --- | --- |
| `docker-compose.yml` | **Deprecated** — kept for reference only; its own header states "no longer used directly." |
| `docker-compose.development.yml` | Standalone dev backend. |
| `docker-compose.prod.yml` | Standalone production backend — builds the image from `Dockerfile`, one service (`marketplace-api`). |
| `docker-compose.infrastructure.dev.yml` | Dev-only Postgres/Redis/MinIO/RabbitMQ, host ports bound to `127.0.0.1` for local tooling access (pgAdmin, migrations). |
| `docker-compose.infrastructure.prod.yml` | Prod-only Postgres/Redis/MinIO/RabbitMQ — Postgres/Redis have **no host port binding at all**; MinIO/RabbitMQ bound to `127.0.0.1` only. |
| `docker-compose.keycloak.yml` | Shared Keycloak + its own dedicated Postgres, serving both a `marketplace-realm` (prod) and `marketplace-realm-dev` realm from one Keycloak instance, attached to both dev and prod app networks. |
| `docker-compose.debug.yml` / `Dockerfile.debug` | Debug-configuration variant (attach a debugger inside the container). |
| `docker-compose.monitoring.yml` | Optional monitoring stack — not required for a base deployment. |

### 2.1 Real production backend service definition (`docker-compose.prod.yml`)

```yaml
services:
  marketplace-api:
    build:
      context: .
      dockerfile: Dockerfile
    image: ${BACKEND_IMAGE_NAME:-anqelbacarrental-marketplace-backend}:${BACKEND_IMAGE_TAG:-latest}
    restart: always
    env_file: [.env.production]
    environment:
      ASPNETCORE_ENVIRONMENT: Production
      ASPNETCORE_URLS: http://+:8080
      ConnectionStrings__DefaultConnection: Host=postgres;Port=5432;Database=${POSTGRES_DB};...
      ConnectionStrings__Redis: ${REDIS_CONNECTION_STRING:-redis:6379,defaultDatabase=0}
      Keycloak__Authority: ${KEYCLOAK_AUTHORITY:-https://auth.anqelbacarrental.com/realms/marketplace-realm}
      Keycloak__ValidateIssuer: ${KEYCLOAK_VALIDATE_ISSUER:-true}
      MinIO__Endpoint: minio:9000
      RabbitMQ__HostName: rabbitmq
      BlindBidding__SaltSecret: ${BLIND_BIDDING_SALT}
      PaymentProviders__Chapa__...: (public/secret/webhook/approval keys, all env-driven)
      DataProtection__Key: ${DATA_PROTECTION_KEY}
      Withdrawal__AutoApprovalThresholdETB: ${WITHDRAWAL_AUTO_APPROVAL_THRESHOLD:-5000}
    ports: ["5100:8080"]
    volumes:
      - backend_prod_logs:/app/logs
      - /srv/anqelbacarrental/uploads:/app/storage/uploads
      - ./realm-export.json:/app/realm-export.json:ro
    healthcheck:
      test: curl -f http://localhost:8080/health/live || exit 1
    mem_limit: 512m
    cpus: 0.5
    networks:
      marketplace-prod-network: { aliases: [marketplace-api] }

networks:
  marketplace-prod-network: { external: true }
```

Real, verified details worth calling out:

- **Every secret and connection string is environment-driven** (`.env.production`, not committed) — there is no hardcoded credential in the compose file itself beyond harmless local-dev fallback defaults (`postgres`/`redis:6379` etc.) that are overridden in real deployments.
- **Resource caps are real and modest**: `mem_limit: 512m`, `cpus: 0.5` on the API container — appropriate for a single-VPS MVP deployment, not a cluster.
- **`realm-export.json` is mounted read-only into the container** so `KeycloakInitializer` can import it into the shared Keycloak instance on first boot if the realm doesn't already exist.
- **Uploads persist to a host bind mount** (`/srv/anqelbacarrental/uploads`), not solely to MinIO — `LocalStorage__Path`/`LocalStorage__PublicUrl` env vars (visible in the real compose file) indicate local-disk storage is a live path alongside MinIO, not purely MinIO-backed as v1.0 implied.
- **Networks are `external: true`** — they must be created once (`docker network create marketplace-prod-network`) before the first deploy; Compose does not own their lifecycle.

### 2.2 Infrastructure isolation (production)

From `docker-compose.infrastructure.prod.yml`:

- `postgres-prod`, `redis-prod`: `expose` only — **no host port binding at all**, reachable exclusively from other containers on `marketplace-prod-network`.
- `minio-prod`, `rabbitmq-prod`: host ports bound to `127.0.0.1:<port>` only — reachable from the host machine (operator tooling) but not from the public internet.
- All four services have real `healthcheck` blocks (`pg_isready`, `redis-cli ping`, MinIO `/minio/health/live`, `rabbitmq-diagnostics ping`) and modest `mem_limit`/`cpus` caps.

### 2.3 Keycloak (shared across environments)

`docker-compose.keycloak.yml` runs **one** Keycloak container serving both `marketplace-realm` (prod) and `marketplace-realm-dev` (dev) — it is not duplicated per environment. It has its own dedicated `keycloak-postgres` on a private `marketplace-keycloak-network`, and is additionally attached to both `marketplace-dev-network` and `marketplace-prod-network` (with a `keycloak` DNS alias on each) so either backend can resolve it by container name. `KC_PROXY: edge` and `KC_HOSTNAME_STRICT: "false"` indicate it expects to sit behind a reverse proxy for its own public hostname (`auth.anqelbacarrental.com`) — that proxy is not part of this repo.

### 2.4 Dockerfile

`backend/src/Marketplace.API/Dockerfile` is the real multi-stage .NET build referenced by CI (`docker/build-push-action` uses `file: src/Marketplace.API/Dockerfile`, `context: .`). `backend/Dockerfile` (repo-root-relative) is used by the Compose files' own `build.dockerfile: Dockerfile`/`context: .` directive — confirm which one a given Compose file references before assuming they're interchangeable; `Dockerfile.debug` is a separate debug-configuration variant, not used in the production pipeline.

---

## 3. Web Frontend (`anqelbacarrental-marketplace-core`) — Separate Deployment

All paths relative to `marketplace-project-implementation/anqelbacarrental-marketplace-core/`.

This is a **React 18.3 + Vite** SPA — not the Angular app v1.0's compose file built. It has its own Dockerfile, its own dev/production/override Compose files, and its own CI pipeline; it is not built or served by the same pipeline as the backend.

| File | Role |
| --- | --- |
| `Dockerfile` | Production image build. |
| `Dockerfile.dev` | Dev-mode image (Vite dev server). |
| `docker-compose.yml` / `docker-compose.override.yml` | Local development composition. |
| `docker-compose.development.yml` | Standalone dev deployment. |
| `docker-compose.production.yml` | Standalone production deployment — the target of `deploy-production.yml`. |
| `docker/docker-compose.vps.yml` | VPS-specific variant. |

### 3.1 Real production deploy flow (`.github/workflows/deploy-production.yml`)

Three sequential jobs on every push to `main`:

1. **`test`** — Node 20, `npm install`, `npm test`.
2. **`build-verify`** — `npm run build:production`, purely to catch build breaks before deploying (the artifact isn't reused; the VPS rebuilds).
3. **`deploy`** — SSHes into the production VPS (`appleboy/ssh-action`), clones the repo if absent, `git pull origin main`, then `docker compose -f docker-compose.production.yml down --remove-orphans && docker compose -f docker-compose.production.yml up --build -d`, followed by `docker image prune -f`.

This is a **git-pull-and-rebuild-on-the-box** deployment model, not an image-registry-push-then-pull model — the VPS builds its own image from source on every deploy. This is a materially different (simpler, but slower and less reproducible) release mechanism than the backend's registry-push flow (§4).

---

## 4. Backend CI/CD Pipeline (`.github/workflows/ci-production.yml`)

Three sequential jobs, real and verified:

1. **`build-and-test`** (every push and PR to `main`) — spins up **real ephemeral `postgres:16-alpine` and `redis:7-alpine` service containers** in the GitHub Actions runner (not Testcontainers, not mocks), runs `dotnet restore/build/test` against `Marketplace.sln` with `BlindBidding__SaltSecret=ci-test-salt` and connection strings pointed at the runner-local Postgres/Redis, uploads `.trx` test results as an artifact.
2. **`push-image`** (push to `main` only, requires the `production` GitHub Environment) — builds via `docker/build-push-action` from `src/Marketplace.API/Dockerfile`, pushes `latest` and `prod-<sha>` tags to `${{ vars.DOCKER_REGISTRY }}/<owner>/marketplace-api`, with GHA layer caching.
3. **`deploy`** (needs `push-image`, requires manual approval via the `production` GitHub Environment's required reviewers) — SSHes into the VPS and runs, in order: `git fetch/checkout/reset --hard origin/main`; creates the two Docker networks idempotently if missing; brings up Keycloak (`docker-compose.keycloak.yml`, idempotent — won't recreate if already running); brings up production infrastructure (`docker-compose.infrastructure.prod.yml`, `--remove-orphans --force-recreate`); brings up the backend itself (`docker-compose.prod.yml`, `--build -d --remove-orphans --force-recreate`).

`ci-development.yml` mirrors this for the dev branch/environment and dev Compose files/network — same three-job shape, different environment/secrets scope. This is a **registry-push-then-pull-on-server** model for the backend, in contrast to the web app's git-pull-and-rebuild model (§3.1) — the two surfaces are deployed differently from each other, not by one shared pipeline.

Notably **absent from both backend CI workflows**: SAST (SonarQube), DAST (OWASP ZAP), container image scanning (Trivy), and Dependabot-style automated dependency-update PRs. `dotnet test` is the only quality gate that blocks a merge/deploy.

---

## 5. Deployment Steps (real, from the workflows above)

### 5.1 One-time setup (per VPS)

```bash
docker network create marketplace-dev-network  2>/dev/null || true
docker network create marketplace-prod-network 2>/dev/null || true

docker compose -p marketplace-keycloak --env-file .env.keycloak \
  -f docker-compose.keycloak.yml up -d
```

### 5.2 Backend deploy (manual, mirrors the CI `deploy` job)

```bash
docker compose -p marketplace-infra-prod --env-file .env.production \
  -f docker-compose.infrastructure.prod.yml up -d --remove-orphans --force-recreate

docker compose -p marketplace-prod --env-file .env.production \
  -f docker-compose.prod.yml up --build -d --remove-orphans --force-recreate
```

### 5.3 Database migrations — confirmed automatic on startup

`Infrastructure/DatabaseInitializer.cs` calls `context.Database.MigrateAsync()` during application startup, so EF Core migrations run automatically every time the container starts — no manual `dotnet ef database update` step is required for a normal deploy. The same initializer also runs `NotificationCredentialMigrationService.MigrateAsync()` (a one-time data migration for notification-provider credentials, unrelated to schema migrations). A manual run is only needed for out-of-band troubleshooting:

```bash
docker compose -p marketplace-prod exec marketplace-api dotnet ef database update
```

### 5.4 Web frontend deploy (manual, mirrors `deploy-production.yml`'s deploy job)

```bash
docker compose -f docker-compose.production.yml down --remove-orphans
docker compose -f docker-compose.production.yml up --build -d
docker image prune -f
```

### 5.5 Keycloak configuration

Real realm import happens automatically via `KeycloakInitializer` on backend startup (imports `realm-export.json` if the realm doesn't exist, patches the frontend URL) — manual realm/client/role creation through the admin console is only needed when starting from a Keycloak instance with no realm export mounted, or when changing realm configuration beyond what's captured in `realm-export.json`. The three real seeded roles are `ADMIN`, `BUSINESS`, `PROVIDER` (see `08_SECURITY_COMPLIANCE.md` §3.1); the API authenticates against Keycloak using a single configured client (`Keycloak__Resource`/`Keycloak__Audience` = `marketplace-backend`).

---

## 6. Monitoring, Health Checks & Maintenance

### 6.1 Health endpoints (real, from `Program.cs`)

- `GET /health/live` — liveness, no dependency checks (used by the Docker `healthcheck` in every Compose file above).
- `GET /health/ready` — readiness, backed by real dependency probes: `AddNpgSql` (Postgres), `AddRedis`, `AddRabbitMQ` (opens a real AMQP connection), and `AddUrlGroup` against Keycloak's own `/health/ready` endpoint. All four are tagged `"ready"`.
- `GET /api/health` — a third health route also mapped in `Program.cs`; confirm exactly which check subset it exposes against current source before documenting it further in downstream material.

This is a materially more real and useful health-check surface than v1.0's vague "checked via API health probe" — readiness genuinely depends on Postgres, Redis, RabbitMQ, and Keycloak all being reachable, not just the process being alive.

### 6.2 Backup strategy — not automated today

No `pg_dump`/backup cron job, script, or CI step was found anywhere in the reviewed Compose files, Dockerfiles, or GitHub Actions workflows for the backend or web. Treat "daily encrypted backups to MinIO" as **not implemented** — if backup/retention is a real operational requirement, it needs to be designed and built, not assumed present. Docker named volumes (`postgres_prod_data`, `minio_prod_data`, `rabbitmq_prod_data`, `redis_prod_data`) persist data across container restarts/recreates, which is not the same thing as an off-host backup.

### 6.3 Logging

The `json-file` Docker logging driver with `max-size: 10m` / `max-file: 3` is set consistently across every service in the infra and app Compose files — a real, deliberate local log-rotation policy, independent of whatever centralized log aggregation (Serilog sinks, Seq, etc.) the application itself is configured to also emit to.

---

## Related documents

- `08_SECURITY_COMPLIANCE.md` §1, §5.3 — the same topology described from a trust-boundary/network-isolation angle.
- `architecture/auth-service-microservice-spec.md` — why Keycloak is a shared container, not a per-environment or per-service one.
- `architecture/backend-remediation-roadmap-2026-07-12.md` — backend code-quality state; not deployment-specific, but explains the "one deployable, `Marketplace.API`" framing this guide assumes throughout.

**Next Document:** [10_TESTING_STRATEGY.md](./10_TESTING_STRATEGY.md)
