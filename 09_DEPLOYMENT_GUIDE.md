# Deployment Guide - Docker Compose

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Environment:** Docker Compose (Local & Production)

---

## 📋 Overview

The Movello MVP is deployed using **Docker Compose** for simplicity and portability. This single-node deployment strategy is sufficient for the MVP scale and allows for easy migration to Kubernetes (K8s) in the future.

### Services
1.  **Traefik:** Reverse Proxy & Load Balancer (Edge Router)
2.  **BFF (YARP):** Backend-for-Frontend Gateway
3.  **Marketplace.API:** Modular Monolith Backend
4.  **Keycloak:** Identity Provider
5.  **PostgreSQL:** Primary Database
6.  **Redis:** Distributed Cache & SignalR Backplane
7.  **MinIO:** S3-compatible Object Storage
8.  **Seq:** Centralized Logging (Optional for Prod)

---

## 🐳 Docker Compose Configuration

### `docker-compose.yml`

```yaml
version: '3.8'

services:
  # ----------------------------------------------------------------
  # EDGE ROUTER (Traefik)
  # ----------------------------------------------------------------
  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080" # Dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - movello-net

  # ----------------------------------------------------------------
  # BACKEND (Modular Monolith)
  # ----------------------------------------------------------------
  api:
    image: movello/api:latest
    build:
      context: .
      dockerfile: src/Movello.API/Dockerfile
    environment:
      - ConnectionStrings__DefaultConnection=Host=postgres;Database=movello;Username=postgres;Password=secure_password
      - Redis__ConnectionString=redis:6379
      - Keycloak__Authority=http://keycloak:8080/realms/movello
    depends_on:
      - postgres
      - redis
      - keycloak
    networks:
      - movello-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`api.movello.et`)"

  # ----------------------------------------------------------------
  # BFF (YARP Gateway)
  # ----------------------------------------------------------------
  bff:
    image: movello/bff:latest
    build:
      context: .
      dockerfile: src/Movello.BFF/Dockerfile
    environment:
      - Keycloak__Authority=http://keycloak:8080/realms/movello
      - ReverseProxy__Clusters__api-cluster__Destinations__d1__Address=http://api:8080
    depends_on:
      - api
      - keycloak
    networks:
      - movello-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.bff.rule=Host(`app.movello.et`)"

  # ----------------------------------------------------------------
  # FRONTEND (Angular Nginx)
  # ----------------------------------------------------------------
  frontend:
    image: movello/frontend:latest
    build:
      context: ./frontend
      dockerfile: Dockerfile
    networks:
      - movello-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(`app.movello.et`) && PathPrefix(`/`)"

  # ----------------------------------------------------------------
  # INFRASTRUCTURE
  # ----------------------------------------------------------------
  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=secure_password
      - POSTGRES_DB=movello
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - movello-net

  redis:
    image: redis:7-alpine
    networks:
      - movello-net

  keycloak:
    image: quay.io/keycloak/keycloak:24.0
    command: start-dev
    environment:
      - KC_DB=postgres
      - KC_DB_URL=jdbc:postgresql://postgres:5432/keycloak
      - KC_DB_USERNAME=postgres
      - KC_DB_PASSWORD=secure_password
      - KEYCLOAK_ADMIN=admin
      - KEYCLOAK_ADMIN_PASSWORD=admin
    ports:
      - "8180:8080"
    depends_on:
      - postgres
    networks:
      - movello-net

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=minioadmin
      - MINIO_ROOT_PASSWORD=minioadmin
    volumes:
      - minio_data:/data
    networks:
      - movello-net

volumes:
  postgres_data:
  minio_data:

networks:
  movello-net:
```

---

## 🚀 Deployment Steps

### 1. Prerequisites
- Docker & Docker Compose installed
- Domain names configured (DNS A records pointing to server IP)
- SSL Certificates (if not using Traefik Let's Encrypt)

### 2. Build & Run
```bash
# Build images
docker-compose build

# Start services in background
docker-compose up -d

# Check logs
docker-compose logs -f
```

### 3. Database Migration
The API container is configured to run migrations on startup automatically for the MVP.
```bash
# Manual migration if needed
docker-compose exec api dotnet ef database update
```

### 4. Keycloak Configuration
1. Access Keycloak Admin Console: `http://auth.movello.et`
2. Login with `admin/admin`
3. Create Realm `movello`
4. Create Client `movello-web`
5. Create Roles & Users

---

## 🔄 CI/CD Pipeline (GitHub Actions)

```yaml
name: Build and Deploy

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Build Docker Images
      run: |
        docker build -t movello/api:latest -f src/Movello.API/Dockerfile .
        docker build -t movello/bff:latest -f src/Movello.BFF/Dockerfile .
        docker build -t movello/frontend:latest -f frontend/Dockerfile ./frontend

    - name: Push to Registry
      run: |
        # Login and Push logic here
```

---

## 📈 Monitoring & Maintenance

### Health Checks
- **API:** `http://api.movello.et/health`
- **Database:** Checked via API health probe
- **Redis:** Checked via API health probe

### Backup Strategy
- **PostgreSQL:** Daily `pg_dump` to S3 (MinIO).
- **MinIO:** Sync to offsite storage.

---

**Next Document:** [10_TESTING_STRATEGY.md](./10_TESTING_STRATEGY.md)
