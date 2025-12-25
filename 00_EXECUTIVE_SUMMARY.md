# Movello B2B Mobility Marketplace - MVP Executive Summary

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Status:** Production-Ready Specification  
**Architecture:** Modular Monolith with BFF Pattern

---

## 🎯 Executive Overview

Movello is a B2B mobility marketplace platform connecting **Business Clients** with **Vehicle Providers** through a transparent, secure, and efficient blind-bidding system. This document serves as the authoritative specification for the Minimum Viable Product (MVP) implementation.

### Vision Statement

To revolutionize B2B vehicle rental in Ethiopia by creating a trusted, transparent marketplace that eliminates inefficiencies, reduces costs, and ensures compliance through technology-driven automation.

---

## 📊 Market Opportunity

### Target Market
- **Primary:** Ethiopian businesses requiring fleet rentals (1-365 days)
- **Secondary:** Vehicle providers (individuals, agents, rental companies)
- **Market Size:** $50M+ annual B2B vehicle rental market in Addis Ababa alone

### Problem Statement
1. **Opacity:** No transparent pricing, businesses overpay
2. **Trust Deficit:** High risk of fraud, vehicle quality issues
3. **Manual Processes:** Paper-based contracts, cash payments
4. **Compliance Gaps:** Insurance lapses, unlicensed operators

### Movello Solution
- **Blind Bidding:** Competitive pricing, provider anonymity until award
- **Trust Scoring:** 0-100 provider ratings based on performance
- **Escrow System:** Automated payment protection
- **Digital Verification:** OTP-based vehicle handover, GPS tracking
- **Compliance Enforcement:** Mandatory insurance, KYC/KYB verification

---

## 🏗️ Architecture Overview

### Pattern: Modular Monolith with BFF

```
┌─────────────────────────────────────────────────────────────┐
│                    Angular 19 Frontend                      │
│              (Business Portal | Provider Portal)            │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│           BFF (Backend-for-Frontend) - YARP                 │
│        (API Gateway + Auth Aggregation + Routing)           │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│              Marketplace.API (.NET 9)                       │
│                  Modular Monolith                           │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ Identity │  │Marketplace│  │Contracts │  │ Finance  │   │
│  │  Module  │  │  Module  │  │  Module  │  │  Module  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│  ┌──────────┐                                               │
│  │ Delivery │                                               │
│  │  Module  │                                               │
│  └──────────┘                                               │
├─────────────────────────────────────────────────────────────┤
│         MediatR (In-Process Event Bus)                      │
├─────────────────────────────────────────────────────────────┤
│      Single PostgreSQL 16 DB (6 Schemas)                    │
│  masterdata | identity | marketplace | contracts            │
│  wallet | delivery                                          │
└─────────────────────────────────────────────────────────────┘
         │              │              │
    ┌────▼────┐    ┌───▼────┐    ┌───▼────┐
    │Keycloak │    │ Redis  │    │ MinIO  │
    │  Auth   │    │ Cache  │    │Storage │
    └─────────┘    └────────┘    └────────┘
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Pattern** | Modular Monolith | 30-50% faster MVP development, easier debugging, clear microservices migration path |
| **Backend** | .NET 9 (C# 13) | Performance, async/await, LINQ, strong typing, EF Core 9 |
| **Frontend** | Angular 19 + Signals | Modern reactive state, standalone components, TypeScript 5.6 |
| **Database** | PostgreSQL 16 | ACID compliance, JSONB support, schema separation, proven reliability |
| **Auth** | Keycloak + BFF | Industry-standard OAuth2/OIDC, centralized identity, BFF for token management |
| **Events** | MediatR (in-process) | Simple for monolith, easy migration to RabbitMQ for microservices |
| **Cache** | Redis 7 | Session storage, rate limiting, temporary data |
| **Storage** | MinIO | S3-compatible, self-hosted, cost-effective for MVP |
| **Real-time** | SignalR | WebSocket support for live bid updates, notifications |

---

## 🎯 MVP Scope Definition

### Tier 1: Core Features (MUST-HAVE)

#### 1. Identity & Compliance
- ✅ Business registration with KYB (Know Your Business)
- ✅ Provider registration with KYC (Know Your Customer)
- ✅ Vehicle registration with mandatory insurance verification
- ✅ Document upload and admin verification workflow
- ✅ Trust score calculation (0-100 scale)

#### 2. Marketplace & Bidding
- ✅ Multi-line-item RFQ creation
- ✅ Blind bidding (provider identity hashed until award)
- ✅ Split awards (multiple providers per line item)
- ✅ Bid validation (price floors, vehicle eligibility)

#### 3. Contract Management
- ✅ Automated contract generation from awards
- ✅ Multi-provider contract support
- ✅ Vehicle assignment tracking
- ✅ Partial fulfillment handling
- ✅ Early return processing with proration

#### 4. Delivery & Verification
- ✅ OTP-based vehicle handover (6-digit, 5-minute expiry)
- ✅ Photo evidence capture (4 angles + interior)
- ✅ Odometer and fuel level recording
- ✅ Return inspection workflow

#### 5. Finance & Wallet
- ✅ Digital wallet (Business & Provider)
- ✅ Escrow lock/release automation
- ✅ Monthly settlement cycles
- ✅ Tier-based commission (5-10%)
- ✅ Payment integration (Chapa, Telebirr)
- ✅ Refund processing

#### 6. Notifications
- ✅ Email notifications (SendGrid)
- ✅ SMS notifications (Twilio/Africa's Talking)
- ✅ In-app notifications (SignalR)
- ✅ Event-driven triggers

### Tier 2: Enhanced Features (INCLUDED IN MVP)

- ✅ **Partial Fulfillment:** Under-delivery, early returns, vehicle-level tracking
- ✅ **Trust Score Calculation:** Automated scoring based on:
  - Contract completion rate
  - On-time delivery rate
  - Cancellation rate
  - Average ratings
  - No-show incidents

### Post-MVP (Excluded)

- ❌ GPS/Geofence tracking (PLC providers only)
- ❌ Group bidding (provider consortiums)
- ❌ Instant payouts
- ❌ Provider loan facilities
- ❌ Insurance marketplace
- ❌ Mobile applications (iOS/Android)
- ❌ Advanced analytics dashboards

---

## 📦 Module Breakdown

### 1. Identity & Compliance Module
**Responsibility:** User management, KYC/KYB, vehicle compliance, trust scoring

**Entities:**
- `user_account` (Keycloak mapping)
- `business` (Business clients)
- `provider` (Vehicle providers)
- `vehicle` (Vehicle registry)
- `vehicle_insurance` (Insurance tracking)
- `provider_trust_score_history`

**Key Features:**
- Document verification workflow
- Insurance expiry monitoring
- Trust score calculation engine
- Tier assignment (Bronze → Platinum)

---

### 2. Marketplace Module
**Responsibility:** RFQ management, blind bidding, award processing

**Entities:**
- `rfq` (Request for Quote header)
- `rfq_line_item` (Vehicle requirements)
- `rfq_bid` (Provider bids)
- `rfq_bid_snapshot` (Blind bidding anonymization)
- `rfq_bid_award` (Winning bids)

**Key Features:**
- Multi-line-item RFQ creation
- Blind bidding with hashed provider IDs
- Split award support
- Market price tracking

---

### 3. Contracts Module
**Responsibility:** Contract lifecycle, vehicle assignments, amendments

**Entities:**
- `contract` (Contract header)
- `contract_line_item` (Per-provider line items)
- `contract_vehicle_assignment` (Per-vehicle tracking)
- `contract_amendment` (Change requests)
- `contract_penalty` (Violations)

**Key Features:**
- Automated contract generation
- Partial fulfillment tracking
- Early return processing
- Amendment workflows

---

### 4. Finance Module
**Responsibility:** Wallets, escrow, settlement, commission

**Entities:**
- `wallet_account` (Digital wallets)
- `wallet_ledger_transaction` (Double-entry ledger)
- `escrow_lock` (Contract security deposits)
- `settlement_cycle` (Provider payouts)
- `commission_entry` (Platform earnings)

**Key Features:**
- Double-entry accounting
- Automated escrow management
- Monthly settlement cycles
- Tier-based commission (5-10%)
- Payment gateway integration

---

### 5. Delivery Module
**Responsibility:** Vehicle handover, OTP verification, returns

**Entities:**
- `delivery_session` (Delivery tracking)
- `delivery_otp` (OTP generation/verification)
- `delivery_vehicle_handover` (Evidence capture)
- `delivery_return_session` (Return processing)

**Key Features:**
- 6-digit OTP (SHA-256 hashed, 5-min expiry)
- Photo evidence (5 angles)
- Odometer/fuel tracking
- Return inspection

---

## 🔐 Security & Compliance

### Authentication & Authorization
- **OAuth2/OIDC** via Keycloak
- **Role-Based Access Control (RBAC)**
  - `business-admin`, `business-user`
  - `provider-admin`, `provider-driver`
  - `platform-admin`, `compliance-officer`
- **BFF Pattern** for token management and API aggregation

### Data Protection
- **Encryption at Rest:** PostgreSQL TDE (Transparent Data Encryption)
- **Encryption in Transit:** TLS 1.3 for all communications
- **PII Protection:** Hashed provider IDs during blind bidding
- **Audit Trails:** All financial and contract changes logged

### Compliance
- **KYC/KYB:** Mandatory verification before platform access
- **Insurance:** Zero-tolerance policy, contracts blocked without valid insurance
- **Financial:** Double-entry ledger, immutable transaction records
- **GDPR-Ready:** Data export, deletion workflows (future)

---

## 📈 Performance & Scalability

### Target Metrics (MVP)
- **Concurrent Users:** 500+
- **RFQs per Day:** 100+
- **Contracts per Month:** 500+
- **API Response Time:** <200ms (p95)
- **Database Queries:** <50ms (p95)
- **Uptime:** 99.5%

### Scalability Strategy
1. **Horizontal Scaling:** Stateless API servers behind load balancer
2. **Database:** Read replicas for reporting queries
3. **Caching:** Redis for session data, frequently accessed lookups
4. **CDN:** Static assets (images, documents) via CloudFlare
5. **Future:** Extract high-load modules to microservices

---

## 🚀 Deployment Architecture

### Development Environment
```
Docker Compose:
- marketplace-api (1 container)
- postgres (1 container)
- keycloak (1 container)
- redis (1 container)
- minio (1 container)
- bff (1 container)
```

### Production Environment (MVP)
```
Single Server (DigitalOcean/AWS):
- 8 vCPU, 16GB RAM
- Docker Compose orchestration
- Nginx reverse proxy
- Let's Encrypt SSL
- Automated backups (daily)
```

### CI/CD Pipeline
```
GitHub → GitHub Actions → Docker Build → Deploy to Production
- Automated tests on PR
- Staging deployment on merge to develop
- Production deployment on merge to main
```

---

## 📊 Success Metrics

### Business Metrics
- **GMV (Gross Merchandise Value):** $100K+ in first 3 months
- **Active Businesses:** 50+ registered, 20+ transacting
- **Active Providers:** 100+ registered, 50+ with active contracts
- **Platform Commission:** 7% average (tier-based 5-10%)

### Technical Metrics
- **API Uptime:** 99.5%+
- **Bug Escape Rate:** <5% to production
- **Test Coverage:** 70%+ (unit + integration)
- **Deployment Frequency:** Weekly releases

### User Experience Metrics
- **RFQ to Award Time:** <24 hours average
- **Contract Activation Time:** <2 hours (after OTP verification)
- **Settlement Processing:** 100% on-time monthly payouts
- **Trust Score Accuracy:** <10% dispute rate

---

## 🗓️ Implementation Timeline

### Phase 1: Foundation (Weeks 1-2) - COMPLETED
- ✅ Architecture finalization
- ✅ Database schema design
- ✅ Development environment setup
- ✅ Keycloak configuration

### Phase 2: Core Modules (Weeks 3-6) - IN PROGRESS
- 🔄 Identity & Compliance Module (70% complete)
- 🔄 Marketplace Module (structure only)
- 🔄 Contracts Module (structure only)
- 🔄 Finance Module (structure only)
- 🔄 Delivery Module (structure only)

### Phase 3: Integration (Weeks 7-8)
- ⏳ Module integration via MediatR
- ⏳ BFF implementation
- ⏳ Payment gateway integration
- ⏳ Notification system

### Phase 4: Testing & Hardening (Weeks 9-10)
- ⏳ Unit test coverage (70%+)
- ⏳ Integration testing
- ⏳ Security audit
- ⏳ Performance optimization

### Phase 5: Beta Launch (Week 11)
- ⏳ Pilot with 5 businesses, 10 providers
- ⏳ Bug fixes and refinements
- ⏳ User feedback incorporation

### Phase 6: Production Launch (Week 12)
- ⏳ Public launch
- ⏳ Marketing campaign
- ⏳ Onboarding support

---

## 💰 Cost Structure

### Development Costs (One-Time)
- **Engineering Team:** 3 developers × 12 weeks = $60K
- **Design & UX:** $5K
- **Infrastructure Setup:** $2K
- **Total:** $67K

### Monthly Operating Costs (MVP)
- **Server Hosting:** $200/month (DigitalOcean)
- **Keycloak/Auth:** $0 (self-hosted)
- **Email (SendGrid):** $50/month
- **SMS (Africa's Talking):** $100/month
- **Payment Gateway Fees:** 2.5% of GMV
- **Monitoring (Sentry):** $50/month
- **Total:** ~$400/month + variable payment fees

### Revenue Model
- **Platform Commission:** 5-10% per transaction (tier-based)
- **Target:** $100K GMV/month = $7K commission revenue
- **Break-even:** Month 2-3

---

## 🎯 Next Steps

### Immediate Actions (This Week)
1. ✅ Finalize MVP specifications (this document)
2. ⏳ Complete database migrations
3. ⏳ Implement remaining module structures
4. ⏳ Set up BFF layer

### Short-Term (Next 2 Weeks)
1. ⏳ Complete Identity & Compliance Module
2. ⏳ Complete Marketplace Module
3. ⏳ Complete Contracts Module
4. ⏳ Integrate payment gateways

### Medium-Term (Next 4 Weeks)
1. ⏳ Complete Finance Module
2. ⏳ Complete Delivery Module
3. ⏳ End-to-end testing
4. ⏳ Beta launch preparation

---

## 📚 Documentation Index

This executive summary is part of a comprehensive documentation suite:

1. **00_EXECUTIVE_SUMMARY.md** ← You are here
2. **01_ARCHITECTURE_OVERVIEW.md** - Detailed technical architecture
3. **02_DATABASE_SCHEMA_DESIGN.md** - Complete database specifications
4. **03_API_SPECIFICATIONS.md** - RESTful API documentation
5. **04_MODULE_SPECIFICATIONS/** - Per-module detailed specs
   - Identity_and_Compliance_Module.md
   - Marketplace_Module.md
   - Contracts_Module.md
   - Finance_Module.md
   - Delivery_Module.md
   - Master_Data_and_Settings_Module.md
   - Auth_and_Keycloak_Module.md
6. **05_BUSINESS_LOGIC_FLOWS.md** - End-to-end workflows
7. **06_FRONTEND_ARCHITECTURE.md** - Angular 19 implementation
8. **07_EVENT_DRIVEN_PATTERNS.md** - MediatR event specifications
9. **08_SECURITY_COMPLIANCE.md** - Security and compliance details
10. **09_DEPLOYMENT_GUIDE.md** - Infrastructure and deployment
11. **10_TESTING_STRATEGY.md** - QA and testing approach
12. **Business_Rules.md** - Complete business rules reference
13. **UI_System_Design_Guidelines.md** - Design system and components

---

## ✅ Sign-Off

**Prepared By:** CTO & Technical Architecture Team  
**Reviewed By:** Product Management, Engineering Leads  
**Approved By:** CEO, Board of Directors  
**Date:** November 26, 2025  
**Version:** 1.0 MVP  
**Status:** ✅ **APPROVED FOR IMPLEMENTATION**

---

**This document represents the authoritative specification for Movello MVP. All development work must align with these specifications. Any deviations require formal change request and approval.**

**Next Document:** [01_ARCHITECTURE_OVERVIEW.md](./01_ARCHITECTURE_OVERVIEW.md)
