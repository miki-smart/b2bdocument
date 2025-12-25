# Movello MVP - Database Schema Design

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Database:** PostgreSQL 16  
**Total Schemas:** 6  
**Total Tables:** 80+

---

## 📋 Table of Contents

1. [Schema Overview](#schema-overview)
2. [Master Data Schema](#master-data-schema)
3. [Identity Schema](#identity-schema)
4. [Marketplace Schema](#marketplace-schema)
5. [Contracts Schema](#contracts-schema)
6. [Wallet Schema](#wallet-schema)
7. [Delivery Schema](#delivery-schema)
8. [Indexes & Performance](#indexes--performance)
9. [Migration Strategy](#migration-strategy)

---

## 🗄️ Schema Overview

### Database Organization

```
marketplace (PostgreSQL 16)
├── masterdata (22 tables)    -- Configuration, policies, lookups
├── identity (22 tables)      -- Users, businesses, providers, vehicles
├── marketplace (8 tables)    -- RFQs, bids, awards
├── contracts (9 tables)      -- Contract lifecycle
├── wallet (12 tables)        -- Finance, escrow, settlement
└── delivery (7 tables)       -- OTP, handover, returns

Total: 80 tables
```

### Design Principles

1. **Schema Separation:** Logical module boundaries
2. **Versioning:** Financial policies are versioned
3. **Immutability:** Contract snapshots never change
4. **Audit Trails:** Every schema has event_log table
5. **Double-Entry:** Wallet uses double-entry accounting
6. **Soft Deletes:** Use status flags, not DELETE

---

## 📊 Master Data Schema (22 Tables)

### Purpose
Static configuration data, business rules, policies, lookups.

### Tables

#### 1. lookup_type
```sql
CREATE TABLE masterdata.lookup_type (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(64) NOT NULL UNIQUE,
    name varchar(128) NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    display_order int NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Examples: VEHICLE_TYPE, ENGINE_TYPE, CONTRACT_PERIOD
```

#### 2. lookup
```sql
CREATE TABLE masterdata.lookup (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    lookup_type_id uuid NOT NULL REFERENCES masterdata.lookup_type(id),
    code varchar(64) NOT NULL,
    value varchar(256) NOT NULL,
    metadata jsonb,
    sort_order int NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_lookup_type_code UNIQUE (lookup_type_id, code)
);

-- Examples: EV_SEDAN, MINIBUS_12, DIESEL, MONTH
```

#### 3. settings
```sql
CREATE TABLE masterdata.settings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    key varchar(128) NOT NULL UNIQUE,
    value text NOT NULL,
    value_type varchar(32) NOT NULL, -- NUMBER, STRING, BOOLEAN, JSON
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Examples: OTP_EXPIRY_MINUTES=5, MAX_RFQS_PER_MONTH=20
```

#### 4-5. Commission Strategy (Versioned)
```sql
CREATE TABLE masterdata.commission_strategy_version (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_number int NOT NULL UNIQUE,
    name varchar(128) NOT NULL,
    effective_from timestamptz NOT NULL,
    effective_to timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE masterdata.commission_strategy_rule (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy_version_id uuid NOT NULL REFERENCES masterdata.commission_strategy_version(id),
    provider_tier_id uuid NOT NULL REFERENCES masterdata.provider_tier(id),
    commission_type varchar(32) NOT NULL DEFAULT 'PERCENTAGE',
    rate_percentage numeric(5,4) NOT NULL,
    minimum_amount numeric(10,2),
    maximum_amount numeric(10,2),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Example: BRONZE=10%, SILVER=8%, GOLD=6%, PLATINUM=5%
```

#### 6. Provider Tier
```sql
CREATE TABLE masterdata.provider_tier (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(64) NOT NULL UNIQUE,
    name varchar(128) NOT NULL,
    display_order int NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Tiers: BRONZE, SILVER, GOLD, PLATINUM
-- Commission rates: 10%, 8%, 6%, 5% respectively
```

#### 7. Provider Tier Rule
```sql
CREATE TABLE masterdata.provider_tier_rule (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_tier_id uuid NOT NULL REFERENCES masterdata.provider_tier(id),
    min_trust_score int NOT NULL,
    max_trust_score int NOT NULL,
    min_active_vehicles int NOT NULL DEFAULT 0,
    min_completed_contracts int NOT NULL DEFAULT 0,
    is_default_for_new boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_trust_score_range CHECK (min_trust_score <= max_trust_score),
    CONSTRAINT chk_trust_score_bounds CHECK (min_trust_score >= 0 AND max_trust_score <= 100)
);

-- Hybrid tier calculation: BOTH trust score AND active fleet must meet thresholds
-- BRONZE: 0-49 trust, 0+ vehicles
-- SILVER: 50-69 trust, 5+ vehicles in active contracts
-- GOLD: 70-84 trust, 15+ vehicles in active contracts
-- PLATINUM: 85-100 trust, 30+ vehicles in active contracts
```

#### 8. Business Tier
```sql
CREATE TABLE masterdata.business_tier (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(64) NOT NULL UNIQUE,
    name varchar(128) NOT NULL,
    max_rfqs_per_month int,
    display_order int NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Tiers: STANDARD, BUSINESS_PRO, PREMIUM, ENTERPRISE
-- RFQ limits: 10, 50, 200, unlimited
```

#### 9. Business Tier Rule
```sql
CREATE TABLE masterdata.business_tier_rule (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    business_tier_id uuid NOT NULL REFERENCES masterdata.business_tier(id),
    min_completed_contracts int NOT NULL DEFAULT 0,
    max_completed_contracts int,
    min_active_fleet_size int NOT NULL DEFAULT 0,
    max_active_fleet_size int,
    is_default_for_new boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_completed_contracts_range CHECK (
        max_completed_contracts IS NULL OR min_completed_contracts <= max_completed_contracts
    ),
    CONSTRAINT chk_fleet_size_range CHECK (
        max_active_fleet_size IS NULL OR min_active_fleet_size <= max_active_fleet_size
    )
);

-- Hybrid tier calculation: contract history + active fleet size
-- STANDARD: 1-9 vehicles, new businesses (0+ contracts)
-- BUSINESS_PRO: 10-29 vehicles, 10+ completed contracts
-- PREMIUM: 30-99 vehicles, 20+ completed contracts
-- ENTERPRISE: 100+ vehicles (automatic, 0+ contracts)
```
```

**See full schema:** `database/migrations/001_create_masterdata_schema.sql`

---

## 👤 Identity Schema (22 Tables)

### Purpose
User management, KYC/KYB, vehicle compliance, trust scoring.

### Core Tables

#### 1. user_account
```sql
CREATE TABLE identity.user_account (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    keycloak_id varchar(128) NOT NULL UNIQUE,
    email varchar(256) NOT NULL,
    phone varchar(32),
    full_name varchar(256),
    user_type varchar(32) NOT NULL, -- PROVIDER, BUSINESS, ADMIN
    status varchar(32) NOT NULL DEFAULT 'ACTIVE',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_keycloak ON identity.user_account(keycloak_id);
```

#### 2. business
```sql
CREATE TABLE identity.business (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.user_account(id),
    business_name varchar(256) NOT NULL,
    business_type varchar(64) NOT NULL,
    tin_number varchar(64),
    status varchar(32) NOT NULL DEFAULT 'PENDING_KYB',
    created_at timestamptz NOT NULL DEFAULT now()
);
```

#### 3. provider
```sql
CREATE TABLE identity.provider (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.user_account(id),
    provider_type varchar(32) NOT NULL, -- INDIVIDUAL, AGENT, COMPANY
    name varchar(256) NOT NULL,
    tin_number varchar(64),
    status varchar(32) NOT NULL DEFAULT 'PENDING_VERIFICATION',
    created_at timestamptz NOT NULL DEFAULT now()
);
```

#### 4. vehicle
```sql
CREATE TABLE identity.vehicle (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id uuid NOT NULL REFERENCES identity.provider(id),
    plate_number varchar(64) NOT NULL UNIQUE,
    vehicle_type_code varchar(64) NOT NULL,
    engine_type_code varchar(64),
    seat_count int NOT NULL,
    brand varchar(128),
    model varchar(128),
    tags text[], -- ['luxury', 'guest', 'vip']
    status varchar(32) NOT NULL DEFAULT 'UNDER_REVIEW',
    front_image_url text,
    back_image_url text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_vehicle_provider ON identity.vehicle(provider_id);
CREATE INDEX idx_vehicle_status ON identity.vehicle(status);
```

#### 5. vehicle_insurance (CRITICAL)
```sql
CREATE TABLE identity.vehicle_insurance (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id uuid NOT NULL REFERENCES identity.vehicle(id),
    insurance_type varchar(64) NOT NULL,
    insurance_company_name varchar(256) NOT NULL,
    policy_number varchar(128),
    insured_amount numeric(18,2),
    coverage_start_date date,
    coverage_end_date date, -- MONITORED FOR EXPIRY
    certificate_file_url text NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'PENDING_VERIFICATION',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_insurance_expiry ON identity.vehicle_insurance(coverage_end_date);
```

#### 6. provider_trust_score_history
```sql
CREATE TABLE identity.provider_trust_score_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id uuid NOT NULL REFERENCES identity.provider(id),
    old_score int,
    new_score int NOT NULL,
    reason varchar(64) NOT NULL,
    calculation_snapshot jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

**See full schema:** `database/migrations/006_create_identity_compliance_schema.sql`

---

## 🏪 Marketplace Schema (8 Tables)

### Purpose
RFQ management, blind bidding, awards.

### Core Tables

#### 1. rfq
```sql
CREATE TABLE marketplace.rfq (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id uuid NOT NULL,
    title varchar(256) NOT NULL,
    description text,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'DRAFT',
    bid_deadline timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_rfq_business ON marketplace.rfq(business_id);
CREATE INDEX idx_rfq_status ON marketplace.rfq(status);
```

#### 2. rfq_line_item
```sql
CREATE TABLE marketplace.rfq_line_item (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_id uuid NOT NULL REFERENCES marketplace.rfq(id),
    vehicle_type_code varchar(64) NOT NULL,
    engine_type_code varchar(64),
    quantity_required int NOT NULL,
    with_driver boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

#### 3. rfq_bid (Blind Bidding)
```sql
CREATE TABLE marketplace.rfq_bid (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_id uuid NOT NULL REFERENCES marketplace.rfq(id),
    provider_id uuid NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'DRAFT',
    submitted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

#### 4. rfq_bid_snapshot (Anonymization)
```sql
CREATE TABLE marketplace.rfq_bid_snapshot (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_line_item_id uuid NOT NULL REFERENCES marketplace.rfq_line_item(id),
    rfq_bid_id uuid NOT NULL REFERENCES marketplace.rfq_bid(id),
    hashed_provider_id varchar(256) NOT NULL, -- SHA-256 hash
    unit_price numeric(18,2) NOT NULL,
    quantity_offered int NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

#### 5. rfq_bid_award
```sql
CREATE TABLE marketplace.rfq_bid_award (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_line_item_id uuid NOT NULL REFERENCES marketplace.rfq_line_item(id),
    rfq_bid_id uuid NOT NULL REFERENCES marketplace.rfq_bid(id),
    provider_id uuid NOT NULL,
    quantity_awarded int NOT NULL,
    unit_price numeric(18,2) NOT NULL,
    awarded_at timestamptz NOT NULL DEFAULT now()
);
```

**See full schema:** `database/migrations/002_create_marketplace_bidding_schema.sql`

---

## 📜 Contracts Schema (9 Tables)

### Purpose
Contract lifecycle, vehicle assignments, amendments.

### Core Tables

#### 1. contract
```sql
CREATE TABLE contracts.contract (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_number varchar(64) NOT NULL UNIQUE,
    rfq_id uuid NOT NULL,
    business_id uuid NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'PENDING_ACTIVATION',
    start_date_planned date NOT NULL,
    end_date_planned date NOT NULL,
    commission_strategy_version_id uuid,
    contract_policy_version_id uuid,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

#### 2. contract_party_business (Immutable Snapshot)
```sql
CREATE TABLE contracts.contract_party_business (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id uuid NOT NULL REFERENCES contracts.contract(id),
    business_id uuid NOT NULL,
    business_name varchar(256) NOT NULL,
    tier_code varchar(64),
    snapshot_at timestamptz NOT NULL DEFAULT now()
);
```

#### 3. contract_line_item
```sql
CREATE TABLE contracts.contract_line_item (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id uuid NOT NULL REFERENCES contracts.contract(id),
    rfq_line_item_id uuid NOT NULL,
    provider_id uuid NOT NULL,
    quantity_awarded int NOT NULL,
    quantity_active int NOT NULL DEFAULT 0,
    unit_amount numeric(18,2) NOT NULL,
    total_amount numeric(18,2) NOT NULL,
    commission_rate numeric(5,4) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'PENDING_ACTIVATION'
);
```

#### 4. contract_vehicle_assignment
```sql
CREATE TABLE contracts.contract_vehicle_assignment (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_line_id uuid NOT NULL REFERENCES contracts.contract_line_item(id),
    vehicle_id uuid NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'PENDING_DELIVERY',
    start_date_actual date,
    end_date_actual date,
    return_reason varchar(128),
    created_at timestamptz NOT NULL DEFAULT now()
);
```

**See full schema:** `database/migrations/003_create_contract_engine_schema.sql`

---

## 💰 Wallet Schema (12 Tables)

### Purpose
Finance, escrow, settlement, commission (Double-Entry Accounting).

### Core Tables

#### 1. wallet_account
```sql
CREATE TABLE wallet.wallet_account (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_type varchar(32) NOT NULL, -- BUSINESS, PROVIDER, PLATFORM
    owner_id uuid NOT NULL,
    account_type varchar(32) NOT NULL, -- MAIN, ESCROW, COMMISSION
    currency varchar(3) NOT NULL DEFAULT 'ETB',
    balance numeric(18,2) NOT NULL DEFAULT 0,
    locked_balance numeric(18,2) NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_wallet_owner ON wallet.wallet_account(owner_type, owner_id);
```

#### 2. wallet_ledger_transaction (Header)
```sql
CREATE TABLE wallet.wallet_ledger_transaction (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference varchar(128) NOT NULL UNIQUE,
    transaction_type varchar(64) NOT NULL,
    total_amount numeric(18,2) NOT NULL,
    description text,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

#### 3. wallet_ledger_entry (Double-Entry Lines)
```sql
CREATE TABLE wallet.wallet_ledger_entry (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id uuid NOT NULL REFERENCES wallet.wallet_ledger_transaction(id),
    wallet_account_id uuid NOT NULL REFERENCES wallet.wallet_account(id),
    direction varchar(16) NOT NULL, -- DEBIT, CREDIT
    amount numeric(18,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_direction CHECK (direction IN ('DEBIT', 'CREDIT'))
);

-- Double-entry rule: SUM(debits) = SUM(credits) for each transaction
```

#### 4. escrow_lock
```sql
CREATE TABLE wallet.escrow_lock (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id uuid NOT NULL,
    wallet_account_id uuid NOT NULL REFERENCES wallet.wallet_account(id),
    amount numeric(18,2) NOT NULL,
    locked_at timestamptz NOT NULL DEFAULT now(),
    released_at timestamptz,
    status varchar(32) NOT NULL DEFAULT 'LOCKED'
);
```

#### 5. settlement_cycle
```sql
CREATE TABLE wallet.settlement_cycle (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id uuid NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    total_gross_amount numeric(18,2) NOT NULL,
    total_commission_amount numeric(18,2) NOT NULL,
    total_net_payable numeric(18,2) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'PENDING',
    created_at timestamptz NOT NULL DEFAULT now()
);
```

**See full schema:** `database/migrations/004_create_wallet_escrow_settlement_schema.sql`

---

## 🚚 Delivery Schema (7 Tables)

### Purpose
OTP verification, vehicle handover, returns.

### Core Tables

#### 1. delivery_session
```sql
CREATE TABLE delivery.delivery_session (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_vehicle_assignment_id uuid NOT NULL,
    business_id uuid NOT NULL,
    provider_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    session_type varchar(32) NOT NULL, -- DELIVERY, RETURN
    status varchar(32) NOT NULL DEFAULT 'PENDING',
    created_at timestamptz NOT NULL DEFAULT now()
);
```

#### 2. delivery_otp
```sql
CREATE TABLE delivery.delivery_otp (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_session_id uuid NOT NULL REFERENCES delivery.delivery_session(id),
    otp_code_hash varchar(256) NOT NULL, -- SHA-256, NEVER store plain text
    channel varchar(32) NOT NULL, -- SMS, EMAIL
    expires_at timestamptz NOT NULL,
    attempts int NOT NULL DEFAULT 0,
    is_verified boolean NOT NULL DEFAULT false,
    verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_otp_session ON delivery.delivery_otp(delivery_session_id);
```

#### 3. delivery_vehicle_handover
```sql
CREATE TABLE delivery.delivery_vehicle_handover (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_session_id uuid NOT NULL REFERENCES delivery.delivery_session(id),
    front_photo_url text,
    back_photo_url text,
    left_photo_url text,
    right_photo_url text,
    interior_photo_url text,
    odometer_reading int,
    fuel_level varchar(32),
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

**See full schema:** `database/migrations/005_create_delivery_schema.sql`

---

## 🚀 Indexes & Performance

### Critical Indexes

```sql
-- Identity
CREATE INDEX idx_user_keycloak ON identity.user_account(keycloak_id);
CREATE INDEX idx_vehicle_provider ON identity.vehicle(provider_id);
CREATE INDEX idx_insurance_expiry ON identity.vehicle_insurance(coverage_end_date);

-- Marketplace
CREATE INDEX idx_rfq_business ON marketplace.rfq(business_id);
CREATE INDEX idx_rfq_status ON marketplace.rfq(status);
CREATE INDEX idx_bid_rfq ON marketplace.rfq_bid(rfq_id);

-- Contracts
CREATE INDEX idx_contract_business ON contracts.contract(business_id);
CREATE INDEX idx_contract_status ON contracts.contract(status);

-- Wallet
CREATE INDEX idx_wallet_owner ON wallet.wallet_account(owner_type, owner_id);
CREATE INDEX idx_ledger_transaction ON wallet.wallet_ledger_entry(transaction_id);

-- Delivery
CREATE INDEX idx_otp_session ON delivery.delivery_otp(delivery_session_id);
```

---

## 📝 Migration Strategy

### Migration Files

```
database/migrations/
├── 001_create_masterdata_schema.sql
├── 002_create_marketplace_bidding_schema.sql
├── 003_create_contract_engine_schema.sql
├── 004_create_wallet_escrow_settlement_schema.sql
├── 005_create_delivery_schema.sql
└── 006_create_identity_compliance_schema.sql
```

### Execution Order

```bash
# Run in order
psql -U postgres -d marketplace -f 001_create_masterdata_schema.sql
psql -U postgres -d marketplace -f 006_create_identity_compliance_schema.sql
psql -U postgres -d marketplace -f 002_create_marketplace_bidding_schema.sql
psql -U postgres -d marketplace -f 003_create_contract_engine_schema.sql
psql -U postgres -d marketplace -f 004_create_wallet_escrow_settlement_schema.sql
psql -U postgres -d marketplace -f 005_create_delivery_schema.sql
```

---

**Next Document:** [03_API_SPECIFICATIONS.md](./03_API_SPECIFICATIONS.md)
