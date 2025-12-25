-- =============================================================================
-- Marketplace & Bidding Schema Migration
-- Movello B2B Mobility Marketplace
-- =============================================================================
-- Purpose: Create the marketplace schema for RFQs, bids, awards, and fulfillment
-- Version: V020
-- Date: 2025-11-25
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS marketplace;

-- Required for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

------------------------------------------------------------
-- 1. RFQ (Header)
------------------------------------------------------------

CREATE TABLE marketplace.rfq (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id         uuid NOT NULL,
    title               varchar(256),
    description         text,
    request_date        timestamptz NOT NULL DEFAULT now(),
    location_country    varchar(64),
    location_region     varchar(64),
    location_city       varchar(64),
    expected_start_date date NOT NULL,
    min_provider_tier   varchar(64),
    status              varchar(32) NOT NULL DEFAULT 'OPEN',
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    created_by          uuid,
    updated_by          uuid,
    CONSTRAINT chk_rfq_status CHECK (status IN ('DRAFT', 'OPEN', 'CLOSED', 'CANCELLED', 'AWARDED'))
);

COMMENT ON TABLE marketplace.rfq IS 'RFQ header containing business request details';
COMMENT ON COLUMN marketplace.rfq.business_id IS 'Reference to identity.business_client';
COMMENT ON COLUMN marketplace.rfq.status IS 'DRAFT=Not published, OPEN=Accepting bids, CLOSED=Bidding ended, AWARDED=All items awarded';
COMMENT ON COLUMN marketplace.rfq.min_provider_tier IS 'Minimum provider tier required to bid (e.g., SILVER, GOLD)';

------------------------------------------------------------
-- 2. RFQ Line Items
------------------------------------------------------------

CREATE TABLE marketplace.rfq_line_item (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_id                 uuid NOT NULL REFERENCES marketplace.rfq(id) ON DELETE CASCADE,
    vehicle_type_code      varchar(64) NOT NULL,
    engine_type_code       varchar(64),
    seat_count             int,
    quantity               int NOT NULL,
    model_year_min         int,
    model_year_max         int,
    with_driver            boolean NOT NULL DEFAULT false,
    contract_period_code   varchar(64) NOT NULL,
    contract_period_count  int NOT NULL,
    description            text,
    status                 varchar(32) NOT NULL DEFAULT 'OPEN',
    is_active              boolean NOT NULL DEFAULT true,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    created_by             uuid,
    updated_by             uuid,
    CONSTRAINT chk_line_item_status CHECK (status IN ('DRAFT', 'OPEN', 'CLOSED', 'CANCELLED', 'AWARDED', 'PARTIALLY_AWARDED')),
    CONSTRAINT chk_quantity_positive CHECK (quantity > 0),
    CONSTRAINT chk_period_count_positive CHECK (contract_period_count > 0),
    CONSTRAINT chk_model_year_range CHECK (model_year_max IS NULL OR model_year_max >= model_year_min)
);

COMMENT ON TABLE marketplace.rfq_line_item IS 'Individual line items within an RFQ specifying vehicle requirements';
COMMENT ON COLUMN marketplace.rfq_line_item.vehicle_type_code IS 'Links to masterdata.lookup (VEHICLE_TYPE)';
COMMENT ON COLUMN marketplace.rfq_line_item.engine_type_code IS 'Links to masterdata.lookup (ENGINE_TYPE)';
COMMENT ON COLUMN marketplace.rfq_line_item.contract_period_code IS 'Links to masterdata.lookup (CONTRACT_PERIOD) - DAY, WEEK, MONTH, etc.';
COMMENT ON COLUMN marketplace.rfq_line_item.contract_period_count IS 'Number of periods (e.g., 3 MONTH means 3 months)';
COMMENT ON COLUMN marketplace.rfq_line_item.with_driver IS 'Whether the vehicle must come with a driver';

------------------------------------------------------------
-- 3. Provider Bids
------------------------------------------------------------

CREATE TABLE marketplace.rfq_bid (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_line_item_id      uuid NOT NULL REFERENCES marketplace.rfq_line_item(id) ON DELETE CASCADE,
    provider_id           uuid NOT NULL,
    bid_amount_per_unit   numeric(18,2) NOT NULL,
    quantity_offered      int NOT NULL,
    currency              varchar(8) DEFAULT 'ETB',
    comment               text,
    is_withdrawable       boolean NOT NULL DEFAULT true,
    is_active             boolean NOT NULL DEFAULT true,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    created_by            uuid,
    updated_by            uuid,
    CONSTRAINT uq_bid_provider_line_item UNIQUE (rfq_line_item_id, provider_id),
    CONSTRAINT chk_bid_amount_positive CHECK (bid_amount_per_unit > 0),
    CONSTRAINT chk_quantity_offered_positive CHECK (quantity_offered > 0)
);

COMMENT ON TABLE marketplace.rfq_bid IS 'Provider bids on RFQ line items';
COMMENT ON COLUMN marketplace.rfq_bid.provider_id IS 'Reference to identity.provider';
COMMENT ON COLUMN marketplace.rfq_bid.bid_amount_per_unit IS 'Bid price per vehicle per period (e.g., per day)';
COMMENT ON COLUMN marketplace.rfq_bid.quantity_offered IS 'Number of vehicles provider can supply';
COMMENT ON COLUMN marketplace.rfq_bid.is_withdrawable IS 'Whether provider can withdraw this bid before award';

------------------------------------------------------------
-- 4. Blind Bidding Snapshots
------------------------------------------------------------

CREATE TABLE marketplace.rfq_bid_snapshot (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_bid_id           uuid NOT NULL REFERENCES marketplace.rfq_bid(id) ON DELETE CASCADE,
    rfq_line_item_id     uuid NOT NULL,
    hashed_provider_id   varchar(128) NOT NULL,
    bid_amount_per_unit  numeric(18,2) NOT NULL,
    quantity_offered     int NOT NULL,
    metadata             jsonb,
    created_at           timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE marketplace.rfq_bid_snapshot IS 'Historical snapshots for blind bidding - stores hashed provider ID until RFQ closes';
COMMENT ON COLUMN marketplace.rfq_bid_snapshot.hashed_provider_id IS 'SHA-256 hash of provider_id for anonymity during blind bidding period';
COMMENT ON COLUMN marketplace.rfq_bid_snapshot.metadata IS 'Optional additional snapshot data (trust score at bid time, etc.)';

------------------------------------------------------------
-- 5. Awards
------------------------------------------------------------

CREATE TABLE marketplace.rfq_bid_award (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_line_item_id         uuid NOT NULL REFERENCES marketplace.rfq_line_item(id) ON DELETE CASCADE,
    provider_id              uuid NOT NULL,
    bid_id                   uuid NOT NULL REFERENCES marketplace.rfq_bid(id),
    awarded_quantity         int NOT NULL,
    awarded_amount_per_unit  numeric(18,2) NOT NULL,
    award_date               timestamptz NOT NULL DEFAULT now(),
    awarded_by_user_id       uuid NOT NULL,
    status                   varchar(32) NOT NULL DEFAULT 'AWARDED',
    provider_rejection_reason text,
    rejection_timestamp      timestamptz,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    created_by               uuid,
    updated_by               uuid,
    CONSTRAINT chk_award_status CHECK (status IN ('AWARDED', 'REJECTED', 'CANCELLED', 'CONFIRMED', 'EXPIRED')),
    CONSTRAINT chk_awarded_quantity_positive CHECK (awarded_quantity > 0),
    CONSTRAINT chk_awarded_amount_positive CHECK (awarded_amount_per_unit > 0)
);

COMMENT ON TABLE marketplace.rfq_bid_award IS 'Awards issued to winning providers';
COMMENT ON COLUMN marketplace.rfq_bid_award.status IS 'AWARDED=Initial award, REJECTED=Provider declined, CANCELLED=Business cancelled, CONFIRMED=Provider accepted, EXPIRED=Response timeout';
COMMENT ON COLUMN marketplace.rfq_bid_award.awarded_by_user_id IS 'Business user who made the award decision';
COMMENT ON COLUMN marketplace.rfq_bid_award.provider_rejection_reason IS 'Provider explanation if status=REJECTED';

------------------------------------------------------------
-- 6. Fulfillment Tracking
------------------------------------------------------------

CREATE TABLE marketplace.rfq_line_item_fulfillment (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_line_item_id    uuid NOT NULL REFERENCES marketplace.rfq_line_item(id) ON DELETE CASCADE,
    total_required      int NOT NULL,
    total_awarded       int NOT NULL,
    total_fulfilled     int NOT NULL DEFAULT 0,
    status              varchar(32) NOT NULL DEFAULT 'PENDING',
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    created_by          uuid,
    updated_by          uuid,
    CONSTRAINT chk_fulfillment_status CHECK (status IN ('PENDING', 'PARTIAL', 'COMPLETE', 'CANCELLED')),
    CONSTRAINT chk_fulfillment_counts CHECK (total_fulfilled <= total_awarded AND total_awarded <= total_required)
);

COMMENT ON TABLE marketplace.rfq_line_item_fulfillment IS 'Tracks fulfillment progress for each RFQ line item';
COMMENT ON COLUMN marketplace.rfq_line_item_fulfillment.total_required IS 'Original quantity requested in line item';
COMMENT ON COLUMN marketplace.rfq_line_item_fulfillment.total_awarded IS 'Total quantity awarded across all providers';
COMMENT ON COLUMN marketplace.rfq_line_item_fulfillment.total_fulfilled IS 'Quantity actually delivered and confirmed';

------------------------------------------------------------
-- 7. Vehicle Assignment for Awarded Slots
------------------------------------------------------------

CREATE TABLE marketplace.rfq_award_vehicle_assignment (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_bid_award_id     uuid NOT NULL REFERENCES marketplace.rfq_bid_award(id) ON DELETE CASCADE,
    provider_id          uuid NOT NULL,
    vehicle_id           uuid NOT NULL,
    assignment_date      timestamptz NOT NULL DEFAULT now(),
    status               varchar(32) NOT NULL DEFAULT 'ASSIGNED',
    is_active            boolean NOT NULL DEFAULT true,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    created_by           uuid,
    updated_by           uuid,
    CONSTRAINT chk_vehicle_assignment_status CHECK (status IN ('ASSIGNED', 'CONFIRMED', 'REJECTED', 'CANCELLED'))
);

COMMENT ON TABLE marketplace.rfq_award_vehicle_assignment IS 'Links specific vehicles to awarded RFQ line items';
COMMENT ON COLUMN marketplace.rfq_award_vehicle_assignment.vehicle_id IS 'Reference to identity.vehicle';
COMMENT ON COLUMN marketplace.rfq_award_vehicle_assignment.status IS 'ASSIGNED=Provider assigned vehicle, CONFIRMED=Business approved, REJECTED=Business rejected vehicle';

------------------------------------------------------------
-- 8. Marketplace Event Log
------------------------------------------------------------

CREATE TABLE marketplace.marketplace_event_log (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_id        uuid,
    line_item_id  uuid,
    provider_id   uuid,
    business_id   uuid,
    event_type    varchar(64) NOT NULL,
    event_payload jsonb,
    created_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE marketplace.marketplace_event_log IS 'Audit trail of all marketplace events for analytics and debugging';
COMMENT ON COLUMN marketplace.marketplace_event_log.event_type IS 'E.g., RFQ_CREATED, BID_PLACED, AWARD_ISSUED, BID_WITHDRAWN, AWARD_ACCEPTED';
COMMENT ON COLUMN marketplace.marketplace_event_log.event_payload IS 'Full event data snapshot for audit purposes';

------------------------------------------------------------
-- 9. INDEXES
------------------------------------------------------------

-- RFQ indexes
CREATE INDEX idx_rfq_business ON marketplace.rfq(business_id);
CREATE INDEX idx_rfq_status ON marketplace.rfq(status);
CREATE INDEX idx_rfq_start_date ON marketplace.rfq(expected_start_date);
CREATE INDEX idx_rfq_location ON marketplace.rfq(location_country, location_region, location_city);
CREATE INDEX idx_rfq_active ON marketplace.rfq(is_active);

-- Line item indexes
CREATE INDEX idx_line_item_rfq ON marketplace.rfq_line_item(rfq_id);
CREATE INDEX idx_line_item_vehicle_type ON marketplace.rfq_line_item(vehicle_type_code);
CREATE INDEX idx_line_item_status ON marketplace.rfq_line_item(status);
CREATE INDEX idx_line_item_active ON marketplace.rfq_line_item(is_active);

-- Bid indexes
CREATE INDEX idx_bid_line_item ON marketplace.rfq_bid(rfq_line_item_id);
CREATE INDEX idx_bid_provider ON marketplace.rfq_bid(provider_id);
CREATE INDEX idx_bid_active ON marketplace.rfq_bid(is_active);
CREATE INDEX idx_bid_created ON marketplace.rfq_bid(created_at);

-- Snapshot indexes
CREATE INDEX idx_snapshot_bid ON marketplace.rfq_bid_snapshot(rfq_bid_id);
CREATE INDEX idx_snapshot_line_item ON marketplace.rfq_bid_snapshot(rfq_line_item_id);
CREATE INDEX idx_snapshot_created ON marketplace.rfq_bid_snapshot(created_at);

-- Award indexes
CREATE INDEX idx_award_line_item ON marketplace.rfq_bid_award(rfq_line_item_id);
CREATE INDEX idx_award_provider ON marketplace.rfq_bid_award(provider_id);
CREATE INDEX idx_award_bid ON marketplace.rfq_bid_award(bid_id);
CREATE INDEX idx_award_status ON marketplace.rfq_bid_award(status);
CREATE INDEX idx_award_date ON marketplace.rfq_bid_award(award_date);
CREATE INDEX idx_award_active ON marketplace.rfq_bid_award(is_active);

-- Fulfillment indexes
CREATE INDEX idx_fulfillment_line_item ON marketplace.rfq_line_item_fulfillment(rfq_line_item_id);
CREATE INDEX idx_fulfillment_status ON marketplace.rfq_line_item_fulfillment(status);
CREATE INDEX idx_fulfillment_active ON marketplace.rfq_line_item_fulfillment(is_active);

-- Vehicle assignment indexes
CREATE INDEX idx_vehicle_assign_award ON marketplace.rfq_award_vehicle_assignment(rfq_bid_award_id);
CREATE INDEX idx_vehicle_assign_provider ON marketplace.rfq_award_vehicle_assignment(provider_id);
CREATE INDEX idx_vehicle_assign_vehicle ON marketplace.rfq_award_vehicle_assignment(vehicle_id);
CREATE INDEX idx_vehicle_assign_status ON marketplace.rfq_award_vehicle_assignment(status);
CREATE INDEX idx_vehicle_assign_active ON marketplace.rfq_award_vehicle_assignment(is_active);

-- Event log indexes
CREATE INDEX idx_event_log_rfq ON marketplace.marketplace_event_log(rfq_id);
CREATE INDEX idx_event_log_line_item ON marketplace.marketplace_event_log(line_item_id);
CREATE INDEX idx_event_log_provider ON marketplace.marketplace_event_log(provider_id);
CREATE INDEX idx_event_log_business ON marketplace.marketplace_event_log(business_id);
CREATE INDEX idx_event_log_type ON marketplace.marketplace_event_log(event_type);
CREATE INDEX idx_event_log_created ON marketplace.marketplace_event_log(created_at);

------------------------------------------------------------
-- 10. AUDIT TRIGGERS
------------------------------------------------------------

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION marketplace.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers
CREATE TRIGGER trg_rfq_updated_at BEFORE UPDATE ON marketplace.rfq FOR EACH ROW EXECUTE FUNCTION marketplace.update_updated_at_column();
CREATE TRIGGER trg_rfq_line_item_updated_at BEFORE UPDATE ON marketplace.rfq_line_item FOR EACH ROW EXECUTE FUNCTION marketplace.update_updated_at_column();
CREATE TRIGGER trg_rfq_bid_updated_at BEFORE UPDATE ON marketplace.rfq_bid FOR EACH ROW EXECUTE FUNCTION marketplace.update_updated_at_column();
CREATE TRIGGER trg_rfq_bid_award_updated_at BEFORE UPDATE ON marketplace.rfq_bid_award FOR EACH ROW EXECUTE FUNCTION marketplace.update_updated_at_column();
CREATE TRIGGER trg_rfq_line_item_fulfillment_updated_at BEFORE UPDATE ON marketplace.rfq_line_item_fulfillment FOR EACH ROW EXECUTE FUNCTION marketplace.update_updated_at_column();
CREATE TRIGGER trg_rfq_award_vehicle_assignment_updated_at BEFORE UPDATE ON marketplace.rfq_award_vehicle_assignment FOR EACH ROW EXECUTE FUNCTION marketplace.update_updated_at_column();

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
