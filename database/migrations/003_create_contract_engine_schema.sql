-- =============================================================================
-- Contract Engine Schema Migration
-- Movello B2B Mobility Marketplace
-- =============================================================================
-- Purpose: Create the contract schema for contract lifecycle management,
--          party snapshots, amendments, penalties, and audit trails
-- Version: V030
-- Date: 2025-11-26
-- =============================================================================

-- Schema for Contract Engine
CREATE SCHEMA IF NOT EXISTS contracts;

-- For gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

------------------------------------------------------------
-- 1. CONTRACT (MASTER)
------------------------------------------------------------

CREATE TABLE contracts.contract (
    id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_id                        uuid NOT NULL,
    rfq_line_item_id              uuid NOT NULL,
    bid_award_id                  uuid NOT NULL,
    business_id                   uuid NOT NULL,
    provider_id                   uuid NOT NULL,
    contract_number               varchar(64) NOT NULL UNIQUE,
    contract_period_code          varchar(64) NOT NULL,
    contract_period_count         int NOT NULL,
    start_date                    date NOT NULL,
    end_date                      date NOT NULL,
    status                        varchar(32) NOT NULL DEFAULT 'DRAFT',
    commission_strategy_version_id uuid,
    escrow_policy_version_id       uuid,
    settlement_policy_version_id   uuid,
    contract_policy_version_id     uuid,
    notes                         text,
    is_active                     boolean NOT NULL DEFAULT true,
    created_at                    timestamptz NOT NULL DEFAULT now(),
    updated_at                    timestamptz NOT NULL DEFAULT now(),
    created_by                    uuid,
    updated_by                    uuid,
    CONSTRAINT chk_contract_status CHECK (status IN ('DRAFT', 'PENDING_ACTIVATION', 'ACTIVE', 'COMPLETED', 'TERMINATED', 'CANCELLED', 'SUSPENDED')),
    CONSTRAINT chk_contract_dates CHECK (end_date >= start_date),
    CONSTRAINT chk_contract_period_count CHECK (contract_period_count > 0)
);

COMMENT ON TABLE contracts.contract IS 'Master contract record linking RFQ awards to provider delivery commitments';
COMMENT ON COLUMN contracts.contract.contract_number IS 'Human-readable unique contract reference (e.g., CNT-2025-00001)';
COMMENT ON COLUMN contracts.contract.status IS 'DRAFT=Not finalized, PENDING_ACTIVATION=Awaiting start date, ACTIVE=In progress, COMPLETED=Normal completion, TERMINATED=Early termination, CANCELLED=Cancelled before start, SUSPENDED=Temporarily paused';
COMMENT ON COLUMN contracts.contract.commission_strategy_version_id IS 'Locked commission rules at contract creation';
COMMENT ON COLUMN contracts.contract.escrow_policy_version_id IS 'Locked escrow rules at contract creation';

CREATE INDEX idx_contract_business ON contracts.contract(business_id);
CREATE INDEX idx_contract_provider ON contracts.contract(provider_id);
CREATE INDEX idx_contract_status ON contracts.contract(status);
CREATE INDEX idx_contract_rfq_line ON contracts.contract(rfq_line_item_id);
CREATE INDEX idx_contract_dates ON contracts.contract(start_date, end_date);
CREATE INDEX idx_contract_number ON contracts.contract(contract_number);
CREATE INDEX idx_contract_active ON contracts.contract(is_active);

------------------------------------------------------------
-- 2. BUSINESS PARTY SNAPSHOT
------------------------------------------------------------

CREATE TABLE contracts.contract_party_business (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id            uuid NOT NULL REFERENCES contracts.contract(id) ON DELETE CASCADE,
    business_id            uuid NOT NULL,
    business_name          varchar(256) NOT NULL,
    business_type          varchar(64),
    tier_code              varchar(64),
    tin_number             varchar(64),
    registration_number    varchar(128),
    representative_name    varchar(256),
    representative_phone   varchar(64),
    representative_email   varchar(256),
    address_line1          varchar(256),
    address_city           varchar(128),
    address_region         varchar(128),
    address_country        varchar(128),
    snapshot_at            timestamptz NOT NULL DEFAULT now(),
    created_at             timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE contracts.contract_party_business IS 'Immutable snapshot of business client details at contract creation time';
COMMENT ON COLUMN contracts.contract_party_business.tier_code IS 'Business tier at contract creation (STANDARD, BUSINESS_PRO, ENTERPRISE, GOV_NGO)';
COMMENT ON COLUMN contracts.contract_party_business.snapshot_at IS 'Timestamp when this snapshot was captured';

CREATE INDEX idx_contract_party_business_contract ON contracts.contract_party_business(contract_id);
CREATE INDEX idx_contract_party_business_id ON contracts.contract_party_business(business_id);

------------------------------------------------------------
-- 3. PROVIDER PARTY SNAPSHOT
------------------------------------------------------------

CREATE TABLE contracts.contract_party_provider (
    id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id               uuid NOT NULL REFERENCES contracts.contract(id) ON DELETE CASCADE,
    provider_id               uuid NOT NULL,
    provider_name             varchar(256) NOT NULL,
    provider_type             varchar(32) NOT NULL,
    tier_code                 varchar(64),
    trust_score               int,
    tin_number                varchar(64),
    business_license_number   varchar(128),
    contact_phone             varchar(64),
    contact_email             varchar(256),
    address_line1             varchar(256),
    address_city              varchar(128),
    address_region            varchar(128),
    address_country           varchar(128),
    snapshot_at               timestamptz NOT NULL DEFAULT now(),
    created_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_provider_type CHECK (provider_type IN ('INDIVIDUAL', 'AGENT', 'COMPANY'))
);

COMMENT ON TABLE contracts.contract_party_provider IS 'Immutable snapshot of provider details at contract creation time';
COMMENT ON COLUMN contracts.contract_party_provider.provider_type IS 'INDIVIDUAL=Solo operator, AGENT=Fleet representative, COMPANY=Registered business entity';
COMMENT ON COLUMN contracts.contract_party_provider.tier_code IS 'Provider tier at contract creation (BRONZE, SILVER, GOLD, PLATINUM)';
COMMENT ON COLUMN contracts.contract_party_provider.trust_score IS 'Provider trust score at contract creation (0-100)';

CREATE INDEX idx_contract_party_provider_contract ON contracts.contract_party_provider(contract_id);
CREATE INDEX idx_contract_party_provider_id ON contracts.contract_party_provider(provider_id);

------------------------------------------------------------
-- 4. CONTRACT LINE ITEMS
------------------------------------------------------------

CREATE TABLE contracts.contract_line_item (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id            uuid NOT NULL REFERENCES contracts.contract(id) ON DELETE CASCADE,
    rfq_line_item_id       uuid NOT NULL,
    vehicle_type_code      varchar(64) NOT NULL,
    engine_type_code       varchar(64),
    seat_count             int,
    quantity               int NOT NULL,
    unit_amount            numeric(18,2) NOT NULL,
    currency               varchar(8) NOT NULL DEFAULT 'ETB',
    total_amount           numeric(18,2) NOT NULL,
    with_driver            boolean NOT NULL DEFAULT false,
    contract_period_code   varchar(64) NOT NULL,
    contract_period_count  int NOT NULL,
    status                 varchar(32) NOT NULL DEFAULT 'PLANNED',
    is_active              boolean NOT NULL DEFAULT true,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    created_by             uuid,
    updated_by             uuid,
    CONSTRAINT chk_line_item_status CHECK (status IN ('PLANNED', 'ACTIVE', 'COMPLETED', 'CANCELLED', 'TERMINATED', 'SUSPENDED')),
    CONSTRAINT chk_line_item_quantity CHECK (quantity > 0),
    CONSTRAINT chk_line_item_unit_amount CHECK (unit_amount >= 0),
    CONSTRAINT chk_line_item_total_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_line_item_period_count CHECK (contract_period_count > 0)
);

COMMENT ON TABLE contracts.contract_line_item IS 'Individual line items within a contract specifying vehicle quantities and pricing';
COMMENT ON COLUMN contracts.contract_line_item.quantity IS 'Number of vehicles awarded in this line item';
COMMENT ON COLUMN contracts.contract_line_item.unit_amount IS 'Price per vehicle per billing period';
COMMENT ON COLUMN contracts.contract_line_item.total_amount IS 'Precomputed total: quantity × unit_amount × contract_period_count';
COMMENT ON COLUMN contracts.contract_line_item.with_driver IS 'Whether vehicles must be provided with drivers';

CREATE INDEX idx_contract_line_item_contract ON contracts.contract_line_item(contract_id);
CREATE INDEX idx_contract_line_item_status ON contracts.contract_line_item(status);
CREATE INDEX idx_contract_line_item_vehicle_type ON contracts.contract_line_item(vehicle_type_code);
CREATE INDEX idx_contract_line_item_active ON contracts.contract_line_item(is_active);

------------------------------------------------------------
-- 5. VEHICLE ASSIGNMENT PER CONTRACT LINE ITEM
------------------------------------------------------------

CREATE TABLE contracts.contract_vehicle_assignment (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_line_item_id   uuid NOT NULL REFERENCES contracts.contract_line_item(id) ON DELETE CASCADE,
    provider_id             uuid NOT NULL,
    vehicle_id              uuid NOT NULL,
    assignment_date         timestamptz NOT NULL DEFAULT now(),
    status                  varchar(32) NOT NULL DEFAULT 'ASSIGNED',
    notes                   text,
    is_active               boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    created_by              uuid,
    updated_by              uuid,
    CONSTRAINT chk_vehicle_assignment_status CHECK (status IN ('ASSIGNED', 'CONFIRMED', 'SWAPPED', 'REJECTED', 'RELEASED', 'CANCELLED'))
);

COMMENT ON TABLE contracts.contract_vehicle_assignment IS 'Links specific vehicles to contract line items for delivery tracking';
COMMENT ON COLUMN contracts.contract_vehicle_assignment.status IS 'ASSIGNED=Provider selected vehicle, CONFIRMED=Business approved, SWAPPED=Vehicle replaced, REJECTED=Business rejected, RELEASED=Contract ended, CANCELLED=Assignment cancelled';
COMMENT ON COLUMN contracts.contract_vehicle_assignment.notes IS 'Rejection reasons, swap explanations, or other comments';

CREATE INDEX idx_contract_vehicle_assignment_line ON contracts.contract_vehicle_assignment(contract_line_item_id);
CREATE INDEX idx_contract_vehicle_assignment_vehicle ON contracts.contract_vehicle_assignment(vehicle_id);
CREATE INDEX idx_contract_vehicle_assignment_provider ON contracts.contract_vehicle_assignment(provider_id);
CREATE INDEX idx_contract_vehicle_assignment_status ON contracts.contract_vehicle_assignment(status);
CREATE INDEX idx_contract_vehicle_assignment_active ON contracts.contract_vehicle_assignment(is_active);

------------------------------------------------------------
-- 6. CONTRACT POLICY SNAPSHOT
------------------------------------------------------------

CREATE TABLE contracts.contract_policy_snapshot (
    id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id                  uuid NOT NULL REFERENCES contracts.contract(id) ON DELETE CASCADE,
    commission_strategy_version_id uuid,
    escrow_policy_version_id       uuid,
    settlement_policy_version_id   uuid,
    contract_policy_version_id     uuid,
    snapshot_json                jsonb NOT NULL,
    created_at                   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE contracts.contract_policy_snapshot IS 'Immutable snapshot of all policy rules applied to this contract at creation';
COMMENT ON COLUMN contracts.contract_policy_snapshot.snapshot_json IS 'Full resolved rule set for commission, escrow, settlement, and contract policies - used for audit and dispute resolution';

CREATE UNIQUE INDEX uq_contract_policy_snapshot_contract ON contracts.contract_policy_snapshot(contract_id);

------------------------------------------------------------
-- 7. CONTRACT AMENDMENTS
------------------------------------------------------------

CREATE TABLE contracts.contract_amendment (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id           uuid NOT NULL REFERENCES contracts.contract(id) ON DELETE CASCADE,
    amendment_type        varchar(64) NOT NULL,
    payload               jsonb NOT NULL,
    status                varchar(32) NOT NULL DEFAULT 'PENDING',
    requested_by_user_id  uuid NOT NULL,
    approved_by_user_id   uuid,
    requested_at          timestamptz NOT NULL DEFAULT now(),
    decided_at            timestamptz,
    notes                 text,
    is_active             boolean NOT NULL DEFAULT true,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    created_by            uuid,
    updated_by            uuid,
    CONSTRAINT chk_amendment_type CHECK (amendment_type IN ('EARLY_RETURN', 'EXTENSION', 'VEHICLE_SWAP', 'CANCEL_REQUEST', 'PRICE_ADJUSTMENT', 'QUANTITY_CHANGE', 'SUSPENSION_REQUEST', 'OTHER')),
    CONSTRAINT chk_amendment_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED', 'EXPIRED'))
);

COMMENT ON TABLE contracts.contract_amendment IS 'Contract change requests and their approval workflow';
COMMENT ON COLUMN contracts.contract_amendment.amendment_type IS 'Type of change: EARLY_RETURN, EXTENSION, VEHICLE_SWAP, CANCEL_REQUEST, PRICE_ADJUSTMENT, QUANTITY_CHANGE, SUSPENSION_REQUEST, OTHER';
COMMENT ON COLUMN contracts.contract_amendment.payload IS 'Structured amendment details (e.g., new end_date, vehicle_id, new_price, reason)';
COMMENT ON COLUMN contracts.contract_amendment.requested_by_user_id IS 'User (business or provider) who initiated the amendment';
COMMENT ON COLUMN contracts.contract_amendment.approved_by_user_id IS 'Admin or counterparty who approved/rejected the amendment';

CREATE INDEX idx_contract_amendment_contract ON contracts.contract_amendment(contract_id);
CREATE INDEX idx_contract_amendment_status ON contracts.contract_amendment(status);
CREATE INDEX idx_contract_amendment_type ON contracts.contract_amendment(amendment_type);
CREATE INDEX idx_contract_amendment_requested_by ON contracts.contract_amendment(requested_by_user_id);
CREATE INDEX idx_contract_amendment_active ON contracts.contract_amendment(is_active);

------------------------------------------------------------
-- 8. CONTRACT PENALTIES
------------------------------------------------------------

CREATE TABLE contracts.contract_penalty (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id             uuid NOT NULL REFERENCES contracts.contract(id) ON DELETE CASCADE,
    contract_line_item_id   uuid REFERENCES contracts.contract_line_item(id) ON DELETE SET NULL,
    policy_rule_code        varchar(64) NOT NULL,
    applied_to              varchar(32) NOT NULL,
    amount                  numeric(18,2) NOT NULL,
    currency                varchar(8) NOT NULL DEFAULT 'ETB',
    reason                  text,
    applied_at              timestamptz NOT NULL DEFAULT now(),
    is_active               boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_penalty_applied_to CHECK (applied_to IN ('BUSINESS', 'PROVIDER', 'BOTH', 'PLATFORM')),
    CONSTRAINT chk_penalty_amount CHECK (amount >= 0)
);

COMMENT ON TABLE contracts.contract_penalty IS 'Financial penalties applied to contracts for policy violations';
COMMENT ON COLUMN contracts.contract_penalty.policy_rule_code IS 'Reference to masterdata.contract_policy_rule.scenario_code (e.g., NO_SHOW, EARLY_RETURN, LATE_RETURN)';
COMMENT ON COLUMN contracts.contract_penalty.applied_to IS 'Which party bears the penalty: BUSINESS, PROVIDER, BOTH, or PLATFORM';
COMMENT ON COLUMN contracts.contract_penalty.reason IS 'Human-readable explanation of why penalty was applied';

CREATE INDEX idx_contract_penalty_contract ON contracts.contract_penalty(contract_id);
CREATE INDEX idx_contract_penalty_line_item ON contracts.contract_penalty(contract_line_item_id);
CREATE INDEX idx_contract_penalty_applied_to ON contracts.contract_penalty(applied_to);
CREATE INDEX idx_contract_penalty_active ON contracts.contract_penalty(is_active);

------------------------------------------------------------
-- 9. CONTRACT EVENT LOG (AUDIT)
------------------------------------------------------------

CREATE TABLE contracts.contract_event_log (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id          uuid NOT NULL REFERENCES contracts.contract(id) ON DELETE CASCADE,
    contract_line_item_id uuid,
    event_type           varchar(64) NOT NULL,
    event_payload        jsonb,
    actor_id             uuid,
    actor_type           varchar(32),
    created_at           timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE contracts.contract_event_log IS 'Comprehensive audit trail of all contract lifecycle events';
COMMENT ON COLUMN contracts.contract_event_log.event_type IS 'E.g., CONTRACT_CREATED, CONTRACT_ACTIVATED, VEHICLE_ASSIGNED, AMENDMENT_REQUESTED, PENALTY_APPLIED, CONTRACT_COMPLETED';
COMMENT ON COLUMN contracts.contract_event_log.actor_id IS 'User, system process, or external service that triggered the event';
COMMENT ON COLUMN contracts.contract_event_log.actor_type IS 'BUSINESS, PROVIDER, ADMIN, SYSTEM, API';

CREATE INDEX idx_contract_event_log_contract ON contracts.contract_event_log(contract_id);
CREATE INDEX idx_contract_event_log_line_item ON contracts.contract_event_log(contract_line_item_id);
CREATE INDEX idx_contract_event_log_type ON contracts.contract_event_log(event_type);
CREATE INDEX idx_contract_event_log_actor ON contracts.contract_event_log(actor_id);
CREATE INDEX idx_contract_event_log_created ON contracts.contract_event_log(created_at);

------------------------------------------------------------
-- 10. AUDIT TRIGGERS
------------------------------------------------------------

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION contracts.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers
CREATE TRIGGER trg_contract_updated_at BEFORE UPDATE ON contracts.contract FOR EACH ROW EXECUTE FUNCTION contracts.update_updated_at_column();
CREATE TRIGGER trg_contract_line_item_updated_at BEFORE UPDATE ON contracts.contract_line_item FOR EACH ROW EXECUTE FUNCTION contracts.update_updated_at_column();
CREATE TRIGGER trg_contract_vehicle_assignment_updated_at BEFORE UPDATE ON contracts.contract_vehicle_assignment FOR EACH ROW EXECUTE FUNCTION contracts.update_updated_at_column();
CREATE TRIGGER trg_contract_amendment_updated_at BEFORE UPDATE ON contracts.contract_amendment FOR EACH ROW EXECUTE FUNCTION contracts.update_updated_at_column();

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
