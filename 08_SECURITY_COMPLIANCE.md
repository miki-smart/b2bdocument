# Security & Compliance Guide

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Standards:** OAuth2, OIDC, GDPR-aligned, OWASP Top 10

---

## 📋 Overview

Security is a foundational requirement for the Movello platform, given its handling of financial transactions, personal identity data (KYC), and business contracts. This document outlines the security architecture, compliance measures, and data protection strategies.

---

## 🔐 Authentication & Authorization

### 1. Identity Management (Keycloak)
- **Centralized IdP:** Keycloak handles all user authentication.
- **Protocols:** OAuth 2.0 and OpenID Connect (OIDC).
- **Flow:** Authorization Code Flow with PKCE (Proof Key for Code Exchange) for frontend clients.

### 2. BFF Pattern (Backend-for-Frontend)
- **No Tokens in Browser:** Access and Refresh tokens are **never** stored in `localStorage` or `sessionStorage`.
- **HttpOnly Cookies:** Tokens are stored in secure, httpOnly, SameSite=Strict cookies managed by the BFF (YARP).
- **CSRF Protection:** The BFF implements Anti-Forgery tokens for state-changing requests.

### 3. Role-Based Access Control (RBAC)
| Role | Description | Scope |
|------|-------------|-------|
| `platform-admin` | Full system access | Global |
| `compliance-officer` | KYC/KYB verification | Identity Module |
| `finance-officer` | Settlement & Refunds | Finance Module |
| `business-admin` | Manage RFQs, Contracts | Business Portal |
| `business-user` | View-only access | Business Portal |
| `provider-admin` | Manage Fleet, Bids | Provider Portal |
| `provider-driver` | Delivery/Return only | Provider Mobile View |

---

## 🛡️ Data Protection

### 1. Data at Rest
- **Database Encryption:** PostgreSQL TDE (Transparent Data Encryption) enabled.
- **Sensitive Fields:** Columns like `tin_number`, `phone_number` are encrypted at the application level if required by future compliance (not MVP).
- **Backups:** Encrypted backups stored in S3-compatible storage (MinIO) with retention policies.

### 2. Data in Transit
- **TLS 1.3:** Enforced for all HTTP traffic.
- **Certificate Management:** Let's Encrypt auto-renewal via Traefik/Nginx.
- **Internal Traffic:** mTLS (Mutual TLS) between services (Post-MVP).

### 3. PII (Personally Identifiable Information)
- **Minimization:** Only collect what is legally required for KYC/KYB.
- **Isolation:** Identity data stored in a separate `identity` schema.
- **Right to be Forgotten:** Soft-delete mechanism supports anonymization of PII upon request (GDPR compliance).

---

## 👁️ Audit & Logging

### 1. Audit Trails
Every critical action is logged to `*_event_log` tables in each module.

**Schema:**
```sql
CREATE TABLE event_log (
    id uuid PRIMARY KEY,
    event_type varchar(64),
    actor_id uuid,
    actor_ip varchar(45),
    resource_id uuid,
    details jsonb,
    occurred_at timestamptz
);
```

### 2. Centralized Logging (Serilog + Seq/ELK)
- **Structured Logging:** All logs are JSON formatted.
- **Correlation IDs:** `X-Request-ID` propagated across all layers to trace requests.
- **Sensitive Data Masking:** Passwords, tokens, and PII masked in logs.

---

## 🧱 Infrastructure Security

### 1. Network Security
- **Private Subnets:** Database and Redis are NOT accessible from the public internet.
- **Firewall:** Only ports 80/443 open to the world.
- **Rate Limiting:** Configured at the BFF level (YARP) to prevent DDoS.

### 2. Container Security
- **Non-Root User:** All Docker containers run as non-root users.
- **Minimal Base Images:** Using Alpine/Distroless images to reduce attack surface.
- **Vulnerability Scanning:** CI pipeline scans images for CVEs (Trivy).

---

## 🧪 Security Testing (DevSecOps)

### 1. SAST (Static Application Security Testing)
- **SonarQube:** Integrated into CI pipeline to catch code vulnerabilities.
- **Roslyn Analyzers:** .NET security rules enabled.

### 2. DAST (Dynamic Application Security Testing)
- **OWASP ZAP:** Periodic scans of the staging environment.

### 3. Dependency Scanning
- **Dependabot:** Automated PRs for vulnerable NuGet/npm packages.

---

## ✅ Compliance Checklist (MVP)

- [ ] **KYC/KYB:** Verify all businesses and providers before allowing transactions.
- [ ] **Terms of Service:** Users must accept ToS upon login.
- [ ] **Privacy Policy:** Accessible from all portals.
- [ ] **Audit Logs:** Immutable logs for all financial transactions.
- [ ] **Data Residency:** All data hosted within approved jurisdiction (if applicable).

---

**Next Document:** [09_DEPLOYMENT_GUIDE.md](./09_DEPLOYMENT_GUIDE.md)
