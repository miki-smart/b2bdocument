-- =============================================================================
-- Master Data Schema Migration
-- Movello B2B Mobility Marketplace
-- =============================================================================
-- Purpose: Create the master data schema with all lookup, configuration,
--          policy, and geography tables
-- Version: V001
-- Date: 2025-11-25
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS masterdata;

-- Required for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

------------------------------------------------------------
-- 1. LOOKUP + LOCALIZATION
------------------------------------------------------------

CREATE TABLE masterdata.lookup_type (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code          varchar(64) NOT NULL UNIQUE,
    name          varchar(128) NOT NULL,
    description   text,
    is_active     boolean NOT NULL DEFAULT true,
    display_order int NOT NULL DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    created_by    uuid,
    updated_by    uuid
);

COMMENT ON TABLE masterdata.lookup_type IS 'Defines categories of lookup values (enumeration families)';
COMMENT ON COLUMN masterdata.lookup_type.code IS 'Unique code used in APIs and code (e.g., VEHICLE_TYPE, CONTRACT_PERIOD)';
COMMENT ON COLUMN masterdata.lookup_type.display_order IS 'Controls display order in admin UI and dropdowns';

CREATE TABLE masterdata.lookup (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    lookup_type_id  uuid NOT NULL REFERENCES masterdata.lookup_type(id),
    code            varchar(64) NOT NULL,
    value           varchar(256) NOT NULL,
    metadata        jsonb,
    sort_order      int NOT NULL DEFAULT 0,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    CONSTRAINT uq_lookup_type_code UNIQUE (lookup_type_id, code)
);

COMMENT ON TABLE masterdata.lookup IS 'Individual lookup values under each lookup type';
COMMENT ON COLUMN masterdata.lookup.code IS 'Stable code used in contracts and APIs (e.g., EV_SEDAN, MINIBUS_12)';
COMMENT ON COLUMN masterdata.lookup.metadata IS 'Optional JSON for extra attributes (e.g., seat ranges, specs)';
COMMENT ON COLUMN masterdata.lookup.sort_order IS 'Controls display order within the lookup type';

CREATE TABLE masterdata.lookup_type_translation (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    lookup_type_id  uuid NOT NULL REFERENCES masterdata.lookup_type(id) ON DELETE CASCADE,
    language        varchar(8) NOT NULL,
    name            varchar(128) NOT NULL,
    description     text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    CONSTRAINT uq_lttype_lang UNIQUE (lookup_type_id, language)
);

COMMENT ON TABLE masterdata.lookup_type_translation IS 'Localized names and descriptions for lookup types';

CREATE TABLE masterdata.lookup_translation (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    lookup_id   uuid NOT NULL REFERENCES masterdata.lookup(id) ON DELETE CASCADE,
    language    varchar(8) NOT NULL,
    value       varchar(256) NOT NULL,
    metadata    jsonb,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    created_by  uuid,
    updated_by  uuid,
    CONSTRAINT uq_lookup_lang UNIQUE (lookup_id, language)
);

COMMENT ON TABLE masterdata.lookup_translation IS 'Localized values for lookup entries';

------------------------------------------------------------
-- 2. SETTINGS
------------------------------------------------------------

CREATE TABLE masterdata.settings (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    key          varchar(128) NOT NULL UNIQUE,
    value        text NOT NULL,
    value_type   varchar(32) NOT NULL, -- 'NUMBER','STRING','BOOLEAN','JSON'
    description  text,
    is_active    boolean NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    created_by   uuid,
    updated_by   uuid
);

COMMENT ON TABLE masterdata.settings IS 'Global configuration values for timeouts, thresholds, and feature toggles';
COMMENT ON COLUMN masterdata.settings.value_type IS 'Indicates how to parse the value: STRING, NUMBER, BOOLEAN, JSON';

CREATE TABLE masterdata.settings_translation (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    settings_id     uuid NOT NULL REFERENCES masterdata.settings(id) ON DELETE CASCADE,
    language        varchar(8) NOT NULL,
    display_name    varchar(256) NOT NULL,
    display_desc    text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    CONSTRAINT uq_settings_lang UNIQUE (settings_id, language)
);

COMMENT ON TABLE masterdata.settings_translation IS 'Localized labels and descriptions for settings (admin UI display)';

------------------------------------------------------------
-- 3. COMMISSION STRATEGY
------------------------------------------------------------

CREATE TABLE masterdata.commission_strategy_version (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_number  int NOT NULL,
    name            varchar(128) NOT NULL,
    description     text,
    effective_from  timestamptz NOT NULL,
    effective_to    timestamptz,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    CONSTRAINT uq_commission_version UNIQUE (version_number),
    CONSTRAINT chk_commission_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

COMMENT ON TABLE masterdata.commission_strategy_version IS 'Versioned commission models for provider payouts - critical for financial audit trail';
COMMENT ON COLUMN masterdata.commission_strategy_version.created_by IS 'User who approved this commission strategy version';

CREATE TABLE masterdata.commission_strategy_rule (
    id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy_version_id       uuid NOT NULL REFERENCES masterdata.commission_strategy_version(id) ON DELETE CASCADE,
    provider_tier_code        varchar(64) NOT NULL,
    region_code               varchar(64),
    vehicle_category_code     varchar(64),
    commission_type           varchar(32) NOT NULL DEFAULT 'PERCENTAGE', -- or 'FLAT'
    rate_percentage           numeric(5,4),
    flat_amount               numeric(18,2),
    min_commission_amount     numeric(18,2),
    max_commission_amount     numeric(18,2),
    is_default                boolean NOT NULL DEFAULT false,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    created_by                uuid,
    updated_by                uuid,
    CONSTRAINT chk_commission_type CHECK (commission_type IN ('PERCENTAGE', 'FLAT', 'HYBRID'))
);

COMMENT ON TABLE masterdata.commission_strategy_rule IS 'Specific commission rules per tier, region, vehicle category';

CREATE INDEX idx_commission_rule_lookup
ON masterdata.commission_strategy_rule(strategy_version_id, provider_tier_code, region_code, vehicle_category_code);

------------------------------------------------------------
-- 4. ESCROW POLICY
------------------------------------------------------------

CREATE TABLE masterdata.escrow_policy_version (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_number  int NOT NULL,
    name            varchar(128) NOT NULL,
    description     text,
    effective_from  timestamptz NOT NULL,
    effective_to    timestamptz,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    CONSTRAINT uq_escrow_policy_version UNIQUE (version_number),
    CONSTRAINT chk_escrow_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

COMMENT ON TABLE masterdata.escrow_policy_version IS 'Versioned escrow and deposit policy models';

CREATE TABLE masterdata.escrow_policy_rule (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    escrow_policy_version_id uuid NOT NULL REFERENCES masterdata.escrow_policy_version(id) ON DELETE CASCADE,
    business_tier_code       varchar(64),
    contract_period_code     varchar(64),
    lock_period_days         int NOT NULL,
    min_lock_ratio           numeric(5,4),
    max_lock_ratio           numeric(5,4),
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    created_by               uuid,
    updated_by               uuid,
    CONSTRAINT chk_lock_ratios CHECK (min_lock_ratio <= max_lock_ratio)
);

COMMENT ON TABLE masterdata.escrow_policy_rule IS 'Escrow lock amounts and periods per business tier and contract type';

------------------------------------------------------------
-- 5. SETTLEMENT POLICY
------------------------------------------------------------

CREATE TABLE masterdata.settlement_policy_version (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_number  int NOT NULL,
    name            varchar(128) NOT NULL,
    description     text,
    effective_from  timestamptz NOT NULL,
    effective_to    timestamptz,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    CONSTRAINT uq_settlement_policy_version UNIQUE (version_number),
    CONSTRAINT chk_settlement_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

COMMENT ON TABLE masterdata.settlement_policy_version IS 'Versioned settlement and payout policy models';

CREATE TABLE masterdata.settlement_policy_rule (
    id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    settlement_policy_version_id uuid NOT NULL REFERENCES masterdata.settlement_policy_version(id) ON DELETE CASCADE,
    provider_tier_code           varchar(64),
    settlement_frequency         varchar(32) NOT NULL, -- 'DAILY','WEEKLY','MONTHLY'
    payout_delay_days            int NOT NULL DEFAULT 0,
    min_payout_amount            numeric(18,2),
    created_at                   timestamptz NOT NULL DEFAULT now(),
    updated_at                   timestamptz NOT NULL DEFAULT now(),
    created_by                   uuid,
    updated_by                   uuid,
    CONSTRAINT chk_settlement_frequency CHECK (settlement_frequency IN ('DAILY', 'WEEKLY', 'BIWEEKLY', 'MONTHLY'))
);

COMMENT ON TABLE masterdata.settlement_policy_rule IS 'Payout frequency, delays, and minimums per provider tier';

------------------------------------------------------------
-- 6. TIERING
------------------------------------------------------------

CREATE TABLE masterdata.provider_tier (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code            varchar(64) NOT NULL UNIQUE,
    name            varchar(128) NOT NULL,
    description     text,
    display_order   int NOT NULL DEFAULT 0,
    color_code      varchar(20),
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid
);

COMMENT ON TABLE masterdata.provider_tier IS 'Provider tier categories (Bronze, Silver, Gold, Platinum)';
COMMENT ON COLUMN masterdata.provider_tier.color_code IS 'Hex color code for UI display (e.g., #FFD700 for Gold)';

CREATE TABLE masterdata.provider_tier_rule (
    id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_tier_id          uuid NOT NULL REFERENCES masterdata.provider_tier(id) ON DELETE CASCADE,
    min_trust_score           int NOT NULL,
    max_trust_score           int NOT NULL,
    min_active_vehicles       int DEFAULT 0,
    min_completed_contracts   int DEFAULT 0,
    max_cancellation_rate     numeric(5,4),
    min_on_time_rate          numeric(5,4),
    is_default_for_new        boolean NOT NULL DEFAULT false,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    created_by                uuid,
    updated_by                uuid,
    CONSTRAINT chk_trust_score_range CHECK (min_trust_score <= max_trust_score)
);

COMMENT ON TABLE masterdata.provider_tier_rule IS 'Qualification rules for provider tier promotion/demotion (hybrid: trust score + active fleet)';
COMMENT ON COLUMN masterdata.provider_tier_rule.min_active_vehicles IS 'Minimum number of vehicles in active contracts required for this tier';

CREATE TABLE masterdata.business_tier (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code                    varchar(64) NOT NULL UNIQUE,
    name                    varchar(128) NOT NULL,
    description             text,
    max_rfqs_per_month      int,
    max_active_contracts    int,
    max_vehicles_per_rfq    int,
    display_order           int NOT NULL DEFAULT 0,
    is_active               boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    created_by              uuid,
    updated_by              uuid
);

COMMENT ON TABLE masterdata.business_tier IS 'Business client tier categories (Standard, Business Pro, Enterprise, Gov/NGO)';
COMMENT ON COLUMN masterdata.business_tier.max_rfqs_per_month IS 'NULL means unlimited for Enterprise/Gov tiers';

CREATE TABLE masterdata.business_tier_rule (
    id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    business_tier_id          uuid NOT NULL REFERENCES masterdata.business_tier(id) ON DELETE CASCADE,
    min_completed_contracts   int DEFAULT 0,
    max_completed_contracts   int,
    min_active_fleet_size     int DEFAULT 0,
    max_active_fleet_size     int,
    is_default_for_new        boolean NOT NULL DEFAULT false,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    created_by                uuid,
    updated_by                uuid,
    CONSTRAINT chk_completed_contracts_range CHECK (min_completed_contracts <= COALESCE(max_completed_contracts, 999999)),
    CONSTRAINT chk_fleet_size_range CHECK (min_active_fleet_size <= COALESCE(max_active_fleet_size, 999999))
);

COMMENT ON TABLE masterdata.business_tier_rule IS 'Qualification rules for business tier assignment (hybrid: contract history + active fleet)';
COMMENT ON COLUMN masterdata.business_tier_rule.min_active_fleet_size IS 'Minimum number of vehicles in active contracts required for this tier';
COMMENT ON COLUMN masterdata.business_tier_rule.max_active_fleet_size IS 'Maximum fleet size for this tier (NULL = unlimited)';

------------------------------------------------------------
-- 7. CONTRACT POLICIES
------------------------------------------------------------

CREATE TABLE masterdata.contract_policy_version (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_number  int NOT NULL,
    name            varchar(128) NOT NULL,
    description     text,
    effective_from  timestamptz NOT NULL,
    effective_to    timestamptz,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    CONSTRAINT uq_contract_policy_version UNIQUE (version_number),
    CONSTRAINT chk_contract_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

COMMENT ON TABLE masterdata.contract_policy_version IS 'Versioned contract cancellation and penalty policies';

CREATE TABLE masterdata.contract_policy_rule (
    id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_policy_version_id uuid NOT NULL REFERENCES masterdata.contract_policy_version(id) ON DELETE CASCADE,
    scenario_code              varchar(64) NOT NULL, -- e.g. 'EARLY_RETURN','NO_SHOW'
    business_tier_code         varchar(64),
    provider_tier_code         varchar(64),
    penalty_type               varchar(32) NOT NULL, -- 'PERCENTAGE','FLAT','NONE'
    penalty_value              numeric(18,4),
    max_penalty_amount         numeric(18,2),
    grace_period_hours         int,
    apply_to_party             varchar(32) NOT NULL, -- 'PROVIDER','BUSINESS','BOTH'
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    created_by                 uuid,
    updated_by                 uuid,
    CONSTRAINT chk_penalty_type CHECK (penalty_type IN ('PERCENTAGE', 'FLAT', 'NONE')),
    CONSTRAINT chk_apply_to_party CHECK (apply_to_party IN ('PROVIDER', 'BUSINESS', 'BOTH', 'PLATFORM'))
);

COMMENT ON TABLE masterdata.contract_policy_rule IS 'Penalty rules for cancellation, no-show, early/late return scenarios';
COMMENT ON COLUMN masterdata.contract_policy_rule.scenario_code IS 'E.g., NO_SHOW, EARLY_RETURN, LATE_RETURN, BUSINESS_CANCEL_BEFORE_START';

------------------------------------------------------------
-- 8. COMPLIANCE / KYC
------------------------------------------------------------

CREATE TABLE masterdata.document_type (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code            varchar(64) NOT NULL UNIQUE,
    name            varchar(128) NOT NULL,
    description     text,
    category        varchar(50),
    is_personal     boolean NOT NULL DEFAULT false,
    is_business     boolean NOT NULL DEFAULT false,
    is_vehicle      boolean NOT NULL DEFAULT false,
    requires_expiry boolean NOT NULL DEFAULT true,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    CONSTRAINT chk_document_category CHECK (category IN ('KYC', 'KYB', 'VEHICLE', 'INSURANCE', 'OTHER'))
);

COMMENT ON TABLE masterdata.document_type IS 'Master list of document types for compliance and verification';

CREATE TABLE masterdata.kyc_requirement (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_type           varchar(32) NOT NULL, -- 'PROVIDER','BUSINESS','DRIVER','VEHICLE_OWNER'
    actor_subtype        varchar(64),
    tier_code            varchar(64),
    document_type_id     uuid NOT NULL REFERENCES masterdata.document_type(id),
    is_mandatory         boolean NOT NULL DEFAULT true,
    min_validity_days    int,
    is_active            boolean NOT NULL DEFAULT true,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    created_by           uuid,
    updated_by           uuid,
    CONSTRAINT uq_kyc_combo UNIQUE (actor_type, actor_subtype, tier_code, document_type_id),
    CONSTRAINT chk_actor_type CHECK (actor_type IN ('PROVIDER', 'BUSINESS', 'VEHICLE', 'DRIVER'))
);

COMMENT ON TABLE masterdata.kyc_requirement IS 'Defines which documents are required per actor type, category, and tier';

------------------------------------------------------------
-- 9. GEO / LOCATION
------------------------------------------------------------

CREATE TABLE masterdata.country (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code             varchar(3) NOT NULL UNIQUE,
    name             varchar(128) NOT NULL,
    iso_alpha2       varchar(2),
    iso_alpha3       varchar(3),
    phone_code       varchar(8),
    currency         varchar(8),
    display_order    int NOT NULL DEFAULT 0,
    is_active        boolean NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    created_by       uuid,
    updated_by       uuid
);

COMMENT ON TABLE masterdata.country IS 'Supported countries for deployment and operations';

CREATE TABLE masterdata.region (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    country_id     uuid NOT NULL REFERENCES masterdata.country(id) ON DELETE CASCADE,
    code           varchar(64) NOT NULL,
    name           varchar(128) NOT NULL,
    display_order  int NOT NULL DEFAULT 0,
    is_active      boolean NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    created_by     uuid,
    updated_by     uuid,
    CONSTRAINT uq_region_country_code UNIQUE (country_id, code)
);

COMMENT ON TABLE masterdata.region IS 'Regions, states, or provinces within countries';

CREATE TABLE masterdata.city (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    region_id      uuid NOT NULL REFERENCES masterdata.region(id) ON DELETE CASCADE,
    name           varchar(128) NOT NULL,
    code           varchar(64),
    latitude       numeric(10,8),
    longitude      numeric(11,8),
    display_order  int NOT NULL DEFAULT 0,
    is_active      boolean NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    created_by     uuid,
    updated_by     uuid,
    CONSTRAINT uq_city_region_code UNIQUE (region_id, code)
);

COMMENT ON TABLE masterdata.city IS 'Cities for RFQ locality, vehicle location, and reporting';

------------------------------------------------------------
-- 10. INDEXES
------------------------------------------------------------

-- Lookup indexes
CREATE INDEX idx_lookup_type_code ON masterdata.lookup_type(code);
CREATE INDEX idx_lookup_type_active ON masterdata.lookup_type(is_active);
CREATE INDEX idx_lookup_type_id ON masterdata.lookup(lookup_type_id);
CREATE INDEX idx_lookup_code ON masterdata.lookup(code);
CREATE INDEX idx_lookup_active ON masterdata.lookup(is_active);

-- Settings indexes
CREATE INDEX idx_settings_key ON masterdata.settings(key);
CREATE INDEX idx_settings_active ON masterdata.settings(is_active);

-- Policy version indexes
CREATE INDEX idx_commission_version_active ON masterdata.commission_strategy_version(is_active);
CREATE INDEX idx_commission_version_dates ON masterdata.commission_strategy_version(effective_from, effective_to);
CREATE INDEX idx_escrow_version_active ON masterdata.escrow_policy_version(is_active);
CREATE INDEX idx_settlement_version_active ON masterdata.settlement_policy_version(is_active);
CREATE INDEX idx_contract_version_active ON masterdata.contract_policy_version(is_active);

-- Policy rule indexes
CREATE INDEX idx_commission_rule_version ON masterdata.commission_strategy_rule(strategy_version_id);
CREATE INDEX idx_commission_rule_tier ON masterdata.commission_strategy_rule(provider_tier_code);
CREATE INDEX idx_escrow_rule_version ON masterdata.escrow_policy_rule(escrow_policy_version_id);
CREATE INDEX idx_settlement_rule_version ON masterdata.settlement_policy_rule(settlement_policy_version_id);
CREATE INDEX idx_contract_rule_version ON masterdata.contract_policy_rule(contract_policy_version_id);
CREATE INDEX idx_contract_rule_scenario ON masterdata.contract_policy_rule(scenario_code);

-- Tier indexes
CREATE INDEX idx_provider_tier_code ON masterdata.provider_tier(code);
CREATE INDEX idx_provider_tier_active ON masterdata.provider_tier(is_active);
CREATE INDEX idx_business_tier_code ON masterdata.business_tier(code);
CREATE INDEX idx_business_tier_active ON masterdata.business_tier(is_active);

-- Document indexes
CREATE INDEX idx_document_type_code ON masterdata.document_type(code);
CREATE INDEX idx_document_type_category ON masterdata.document_type(category);
CREATE INDEX idx_document_type_active ON masterdata.document_type(is_active);
CREATE INDEX idx_kyc_requirement_actor ON masterdata.kyc_requirement(actor_type);
CREATE INDEX idx_kyc_requirement_document ON masterdata.kyc_requirement(document_type_id);
CREATE INDEX idx_kyc_requirement_active ON masterdata.kyc_requirement(is_active);

-- Geography indexes
CREATE INDEX idx_country_code ON masterdata.country(code);
CREATE INDEX idx_country_active ON masterdata.country(is_active);
CREATE INDEX idx_region_country ON masterdata.region(country_id);
CREATE INDEX idx_region_code ON masterdata.region(code);
CREATE INDEX idx_region_active ON masterdata.region(is_active);
CREATE INDEX idx_city_region ON masterdata.city(region_id);
CREATE INDEX idx_city_code ON masterdata.city(code);
CREATE INDEX idx_city_active ON masterdata.city(is_active);
CREATE INDEX idx_city_coordinates ON masterdata.city(latitude, longitude);

------------------------------------------------------------
-- 11. AUDIT TRIGGERS
------------------------------------------------------------

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION masterdata.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to all tables
CREATE TRIGGER trg_lookup_type_updated_at BEFORE UPDATE ON masterdata.lookup_type FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_lookup_updated_at BEFORE UPDATE ON masterdata.lookup FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_lookup_type_translation_updated_at BEFORE UPDATE ON masterdata.lookup_type_translation FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_lookup_translation_updated_at BEFORE UPDATE ON masterdata.lookup_translation FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_settings_updated_at BEFORE UPDATE ON masterdata.settings FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_settings_translation_updated_at BEFORE UPDATE ON masterdata.settings_translation FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_commission_strategy_version_updated_at BEFORE UPDATE ON masterdata.commission_strategy_version FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_commission_strategy_rule_updated_at BEFORE UPDATE ON masterdata.commission_strategy_rule FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_escrow_policy_version_updated_at BEFORE UPDATE ON masterdata.escrow_policy_version FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_escrow_policy_rule_updated_at BEFORE UPDATE ON masterdata.escrow_policy_rule FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_settlement_policy_version_updated_at BEFORE UPDATE ON masterdata.settlement_policy_version FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_settlement_policy_rule_updated_at BEFORE UPDATE ON masterdata.settlement_policy_rule FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_provider_tier_updated_at BEFORE UPDATE ON masterdata.provider_tier FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_provider_tier_rule_updated_at BEFORE UPDATE ON masterdata.provider_tier_rule FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_business_tier_updated_at BEFORE UPDATE ON masterdata.business_tier FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_contract_policy_version_updated_at BEFORE UPDATE ON masterdata.contract_policy_version FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_contract_policy_rule_updated_at BEFORE UPDATE ON masterdata.contract_policy_rule FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_document_type_updated_at BEFORE UPDATE ON masterdata.document_type FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_kyc_requirement_updated_at BEFORE UPDATE ON masterdata.kyc_requirement FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_country_updated_at BEFORE UPDATE ON masterdata.country FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_region_updated_at BEFORE UPDATE ON masterdata.region FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_city_updated_at BEFORE UPDATE ON masterdata.city FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();
CREATE TRIGGER trg_business_tier_rule_updated_at BEFORE UPDATE ON masterdata.business_tier_rule FOR EACH ROW EXECUTE FUNCTION masterdata.update_updated_at_column();

------------------------------------------------------------
-- 12. SEED DATA
------------------------------------------------------------

-- Provider Tiers
INSERT INTO masterdata.provider_tier (id, code, name, display_order, is_active) VALUES
(gen_random_uuid(), 'BRONZE', 'Bronze Provider', 1, true),
(gen_random_uuid(), 'SILVER', 'Silver Provider', 2, true),
(gen_random_uuid(), 'GOLD', 'Gold Provider', 3, true),
(gen_random_uuid(), 'PLATINUM', 'Platinum Provider', 4, true);

-- Provider Tier Rules (hybrid: trust score + active fleet)
INSERT INTO masterdata.provider_tier_rule (id, provider_tier_id, min_trust_score, max_trust_score, min_active_vehicles, min_completed_contracts, is_default_for_new)
SELECT 
    gen_random_uuid(),
    pt.id,
    0, 49, 0, 0, true
FROM masterdata.provider_tier pt WHERE pt.code = 'BRONZE';

INSERT INTO masterdata.provider_tier_rule (id, provider_tier_id, min_trust_score, max_trust_score, min_active_vehicles, min_completed_contracts, is_default_for_new)
SELECT 
    gen_random_uuid(),
    pt.id,
    50, 69, 5, 0, false
FROM masterdata.provider_tier pt WHERE pt.code = 'SILVER';

INSERT INTO masterdata.provider_tier_rule (id, provider_tier_id, min_trust_score, max_trust_score, min_active_vehicles, min_completed_contracts, is_default_for_new)
SELECT 
    gen_random_uuid(),
    pt.id,
    70, 84, 15, 0, false
FROM masterdata.provider_tier pt WHERE pt.code = 'GOLD';

INSERT INTO masterdata.provider_tier_rule (id, provider_tier_id, min_trust_score, max_trust_score, min_active_vehicles, min_completed_contracts, is_default_for_new)
SELECT 
    gen_random_uuid(),
    pt.id,
    85, 100, 30, 0, false
FROM masterdata.provider_tier pt WHERE pt.code = 'PLATINUM';

-- Business Tiers
INSERT INTO masterdata.business_tier (id, code, name, max_rfqs_per_month, display_order, is_active) VALUES
(gen_random_uuid(), 'STANDARD', 'Standard Business', 10, 1, true),
(gen_random_uuid(), 'BUSINESS_PRO', 'Business Pro', 50, 2, true),
(gen_random_uuid(), 'PREMIUM', 'Premium Business', 200, 3, true),
(gen_random_uuid(), 'ENTERPRISE', 'Enterprise', NULL, 4, true);

-- Business Tier Rules (hybrid: contract history + active fleet)
INSERT INTO masterdata.business_tier_rule (id, business_tier_id, min_completed_contracts, max_completed_contracts, min_active_fleet_size, max_active_fleet_size, is_default_for_new)
SELECT 
    gen_random_uuid(),
    bt.id,
    0, NULL, 1, 9, true
FROM masterdata.business_tier bt WHERE bt.code = 'STANDARD';

INSERT INTO masterdata.business_tier_rule (id, business_tier_id, min_completed_contracts, max_completed_contracts, min_active_fleet_size, max_active_fleet_size, is_default_for_new)
SELECT 
    gen_random_uuid(),
    bt.id,
    10, NULL, 10, 29, false
FROM masterdata.business_tier bt WHERE bt.code = 'BUSINESS_PRO';

INSERT INTO masterdata.business_tier_rule (id, business_tier_id, min_completed_contracts, max_completed_contracts, min_active_fleet_size, max_active_fleet_size, is_default_for_new)
SELECT 
    gen_random_uuid(),
    bt.id,
    20, NULL, 30, 99, false
FROM masterdata.business_tier bt WHERE bt.code = 'PREMIUM';

INSERT INTO masterdata.business_tier_rule (id, business_tier_id, min_completed_contracts, max_completed_contracts, min_active_fleet_size, max_active_fleet_size, is_default_for_new)
SELECT 
    gen_random_uuid(),
    bt.id,
    0, NULL, 100, NULL, false
FROM masterdata.business_tier bt WHERE bt.code = 'ENTERPRISE';

-- Commission Strategy Rules (tier-based rates)
-- Note: commission_strategy_version must exist first (created via application)
-- This is example seed data for reference:
/*
INSERT INTO masterdata.commission_strategy_rule (id, version_id, provider_tier_id, rate_percentage, minimum_amount, maximum_amount, is_active)
VALUES
(gen_random_uuid(), '<version_id>', (SELECT id FROM masterdata.provider_tier WHERE code = 'BRONZE'), 10.00, NULL, NULL, true),
(gen_random_uuid(), '<version_id>', (SELECT id FROM masterdata.provider_tier WHERE code = 'SILVER'), 8.00, NULL, NULL, true),
(gen_random_uuid(), '<version_id>', (SELECT id FROM masterdata.provider_tier WHERE code = 'GOLD'), 6.00, NULL, NULL, true),
(gen_random_uuid(), '<version_id>', (SELECT id FROM masterdata.provider_tier WHERE code = 'PLATINUM'), 5.00, NULL, NULL, true);
*/

-- OTP Configuration
INSERT INTO masterdata.settings (id, key, value, value_type, description, is_active) VALUES
(gen_random_uuid(), 'otp.expiry_minutes', '15', 'NUMBER', 'OTP expiry time in minutes', true),
(gen_random_uuid(), 'otp.max_attempts', '3', 'NUMBER', 'Maximum OTP verification attempts', true),
(gen_random_uuid(), 'otp.resend_cooldown_seconds', '60', 'NUMBER', 'Cooldown period before resending OTP', true);

-- Trust Score Configuration
INSERT INTO masterdata.settings (id, key, value, value_type, description, is_active) VALUES
(gen_random_uuid(), 'trust_score.initial_verified', '50', 'NUMBER', 'Initial trust score for verified providers', true),
(gen_random_uuid(), 'trust_score.initial_unverified', '0', 'NUMBER', 'Initial trust score for unverified providers', true),
(gen_random_uuid(), 'trust_score.on_time_bonus', '2', 'NUMBER', 'Trust score bonus for on-time delivery', true),
(gen_random_uuid(), 'trust_score.late_penalty', '5', 'NUMBER', 'Trust score penalty for late delivery', true),
(gen_random_uuid(), 'trust_score.cancellation_penalty', '10', 'NUMBER', 'Trust score penalty for provider cancellation', true);

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
