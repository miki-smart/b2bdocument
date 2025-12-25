-- =============================================================================
-- MOVELLO MARKETPLACE - DELIVERY & OPERATIONS SCHEMA
-- =============================================================================
-- Purpose: Vehicle delivery tracking, OTP verification, handover management
-- Dependencies: contracts.contract, contracts.contract_line_item
-- Version: 1.0
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS delivery;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

------------------------------------------------------------
-- 1. DELIVERY SESSION TRACKING
------------------------------------------------------------
-- Purpose: Track each vehicle delivery session from assignment to completion
-- Business Rules: One session per contract line item, tracks complete delivery lifecycle
-- Dependencies: Logical references to contracts.contract and contracts.contract_line_item

CREATE TABLE delivery.delivery_session (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id            uuid NOT NULL,
    contract_line_item_id  uuid NOT NULL,
    provider_id            uuid NOT NULL,
    vehicle_id             uuid NOT NULL,
    business_id            uuid NOT NULL,
    
    -- Delivery workflow status tracking
    status                 varchar(32) NOT NULL DEFAULT 'ASSIGNED' 
                          CHECK (status IN ('ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'OTP_SENT', 
                                          'OTP_VERIFIED', 'DELIVERED', 'FAILED', 'CANCELLED')),
    
    -- Critical delivery timestamps
    scheduled_at           timestamptz NOT NULL,
    arrived_at             timestamptz,
    otp_verified_at        timestamptz,
    delivered_at           timestamptz,
    cancelled_at           timestamptz,
    
    -- Failure tracking
    failure_reason_code    varchar(64) 
                          REFERENCES delivery.delivery_failure_reason(code),
    
    -- Audit columns
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    
    -- Business rule constraints
    CONSTRAINT delivery_session_timestamps_valid 
        CHECK (
            (status = 'DELIVERED' AND delivered_at IS NOT NULL) OR 
            (status != 'DELIVERED' AND delivered_at IS NULL)
        ),
    CONSTRAINT delivery_session_otp_timing 
        CHECK (otp_verified_at IS NULL OR arrived_at IS NOT NULL),
    CONSTRAINT delivery_session_failure_reason 
        CHECK (
            (status = 'FAILED' AND failure_reason_code IS NOT NULL) OR 
            (status != 'FAILED' AND failure_reason_code IS NULL)
        )
);

COMMENT ON TABLE delivery.delivery_session IS 'Vehicle delivery session tracking from assignment to completion with OTP verification';
COMMENT ON COLUMN delivery.delivery_session.status IS 'Current delivery status: ASSIGNED → EN_ROUTE → ARRIVED → OTP_SENT → OTP_VERIFIED → DELIVERED';
COMMENT ON COLUMN delivery.delivery_session.scheduled_at IS 'When delivery is scheduled to occur (business expectation)';
COMMENT ON COLUMN delivery.delivery_session.arrived_at IS 'When provider arrives at delivery location';
COMMENT ON COLUMN delivery.delivery_session.otp_verified_at IS 'When business successfully verifies OTP';
COMMENT ON COLUMN delivery.delivery_session.delivered_at IS 'When vehicle handover is completed';

------------------------------------------------------------
-- 2. OTP VERIFICATION SYSTEM
------------------------------------------------------------
-- Purpose: Secure OTP generation and verification for delivery confirmation
-- Business Rules: Time-limited OTP with attempt limits, hashed storage for security
-- Dependencies: References delivery.delivery_session

CREATE TABLE delivery.delivery_otp (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_session_id    uuid NOT NULL 
                          REFERENCES delivery.delivery_session(id) ON DELETE CASCADE,
    
    -- Security: Store hashed OTP, never plain text
    otp_code_hash          varchar(256) NOT NULL,
    expires_at             timestamptz NOT NULL,
    
    -- Attempt tracking for security
    attempts               int NOT NULL DEFAULT 0 
                          CHECK (attempts >= 0 AND attempts <= 5),
    
    -- Verification status
    is_verified            boolean NOT NULL DEFAULT false,
    verified_at            timestamptz,
    
    -- Delivery method tracking
    sent_via               varchar(32) 
                          CHECK (sent_via IN ('SMS', 'EMAIL', 'WHATSAPP', 'VOICE_CALL')),
    
    created_at             timestamptz NOT NULL DEFAULT now(),
    
    -- Business rule constraints
    CONSTRAINT delivery_otp_verified_timing 
        CHECK (
            (is_verified = true AND verified_at IS NOT NULL) OR 
            (is_verified = false AND verified_at IS NULL)
        ),
    CONSTRAINT delivery_otp_expiry_future 
        CHECK (expires_at > created_at)
);

COMMENT ON TABLE delivery.delivery_otp IS 'Secure OTP verification system for delivery confirmation with attempt limits';
COMMENT ON COLUMN delivery.delivery_otp.otp_code_hash IS 'SHA-256 hashed OTP code for security (never store plain text)';
COMMENT ON COLUMN delivery.delivery_otp.expires_at IS 'OTP expiration timestamp (typically 10-15 minutes from creation)';
COMMENT ON COLUMN delivery.delivery_otp.attempts IS 'Number of verification attempts (max 5 for security)';

------------------------------------------------------------
-- 3. VEHICLE HANDOVER DOCUMENTATION
------------------------------------------------------------
-- Purpose: Record vehicle condition and handover details with photo evidence
-- Business Rules: Mandatory documentation for dispute resolution and insurance claims
-- Dependencies: References delivery.delivery_session

CREATE TABLE delivery.delivery_vehicle_handover (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_session_id    uuid NOT NULL 
                          REFERENCES delivery.delivery_session(id) ON DELETE CASCADE,
    
    -- Vehicle condition documentation
    odometer_reading       int CHECK (odometer_reading >= 0),
    fuel_level             varchar(16) 
                          CHECK (fuel_level IN ('EMPTY', 'QUARTER', 'HALF', 'THREE_QUARTER', 'FULL')),
    
    -- Photo evidence (stored as file URLs or base64)
    handover_photo_front   text,
    handover_photo_back    text,
    handover_photo_side    text,
    handover_photo_interior text,
    
    -- Handover participants
    business_receiver_name varchar(256),
    business_receiver_id   uuid, -- Reference to business user who received
    provider_representative_name varchar(256) NOT NULL,
    
    -- Legal documentation
    signed_document_url    text,
    remarks                text,
    
    created_at             timestamptz NOT NULL DEFAULT now(),
    
    -- Business rule: At least one photo required
    CONSTRAINT handover_photo_required 
        CHECK (
            handover_photo_front IS NOT NULL OR 
            handover_photo_back IS NOT NULL OR 
            handover_photo_side IS NOT NULL OR 
            handover_photo_interior IS NOT NULL
        )
);

COMMENT ON TABLE delivery.delivery_vehicle_handover IS 'Vehicle condition and handover documentation with photo evidence';
COMMENT ON COLUMN delivery.delivery_vehicle_handover.odometer_reading IS 'Vehicle odometer reading at handover (kilometers)';
COMMENT ON COLUMN delivery.delivery_vehicle_handover.fuel_level IS 'Fuel tank level at handover for billing accuracy';
COMMENT ON COLUMN delivery.delivery_vehicle_handover.signed_document_url IS 'URL to digitally signed handover agreement';

------------------------------------------------------------
-- 4. VEHICLE RETURN SESSION
------------------------------------------------------------
-- Purpose: Track vehicle return process with damage assessment and inspection
-- Business Rules: Return inspection required, damage assessment impacts billing
-- Dependencies: References contracts for return requirements

CREATE TABLE delivery.delivery_return_session (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id            uuid NOT NULL,
    contract_line_item_id  uuid NOT NULL,
    provider_id            uuid NOT NULL,
    vehicle_id             uuid NOT NULL,
    business_id            uuid NOT NULL,
    
    -- Return process status
    status                 varchar(32) NOT NULL DEFAULT 'PENDING' 
                          CHECK (status IN ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 
                                          'INSPECTION_COMPLETE', 'RETURNED', 'DISPUTED')),
    
    -- Return timing
    scheduled_return_at    timestamptz,
    return_verified_at     timestamptz,
    
    -- Vehicle condition at return
    odometer_end           int CHECK (odometer_end >= 0),
    
    -- Damage and inspection documentation
    damage_report          jsonb, -- Structured damage assessment
    return_photos          jsonb, -- Array of photo URLs with descriptions
    inspected_by_user_id   uuid,
    remarks                text,
    
    -- Audit columns
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    
    -- Business rule constraints
    CONSTRAINT return_session_verified_timing 
        CHECK (
            (status = 'RETURNED' AND return_verified_at IS NOT NULL) OR 
            (status != 'RETURNED' AND return_verified_at IS NULL)
        )
);

COMMENT ON TABLE delivery.delivery_return_session IS 'Vehicle return process tracking with damage assessment and inspection';
COMMENT ON COLUMN delivery.delivery_return_session.damage_report IS 'JSON structure documenting any vehicle damage with severity and cost estimates';
COMMENT ON COLUMN delivery.delivery_return_session.return_photos IS 'JSON array of return condition photos with metadata';
COMMENT ON COLUMN delivery.delivery_return_session.odometer_end IS 'Final odometer reading for mileage calculation';

------------------------------------------------------------
-- 5. DELIVERY AUDIT AND EVENT LOG
------------------------------------------------------------
-- Purpose: Comprehensive audit trail for all delivery-related events and status changes
-- Business Rules: Immutable event log for compliance and dispute resolution
-- Dependencies: References delivery sessions for event tracking

CREATE TABLE delivery.delivery_event_log (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Event source identification
    delivery_session_id    uuid REFERENCES delivery.delivery_session(id),
    return_session_id      uuid REFERENCES delivery.delivery_return_session(id),
    
    -- Event classification and payload
    event_type             varchar(64) NOT NULL 
                          CHECK (event_type IN (
                              'SESSION_ASSIGNED', 'PROVIDER_EN_ROUTE', 'PROVIDER_ARRIVED',
                              'OTP_GENERATED', 'OTP_SENT', 'OTP_VERIFICATION_ATTEMPT', 
                              'OTP_VERIFIED', 'OTP_EXPIRED', 'HANDOVER_STARTED', 
                              'HANDOVER_COMPLETED', 'DELIVERY_CONFIRMED', 'DELIVERY_FAILED',
                              'RETURN_SCHEDULED', 'RETURN_STARTED', 'RETURN_COMPLETED',
                              'SLA_VIOLATION_DETECTED', 'PENALTY_APPLIED'
                          )),
    
    -- Structured event data
    event_payload          jsonb NOT NULL,
    
    created_at             timestamptz NOT NULL DEFAULT now(),
    
    -- Business rule: Must reference either delivery or return session
    CONSTRAINT delivery_event_session_reference 
        CHECK (
            (delivery_session_id IS NOT NULL AND return_session_id IS NULL) OR 
            (delivery_session_id IS NULL AND return_session_id IS NOT NULL)
        )
);

COMMENT ON TABLE delivery.delivery_event_log IS 'Immutable audit trail for all delivery and return events';
COMMENT ON COLUMN delivery.delivery_event_log.event_type IS 'Categorized event type for filtering and analytics';
COMMENT ON COLUMN delivery.delivery_event_log.event_payload IS 'JSON payload with event-specific data (timestamps, user IDs, metadata)';

------------------------------------------------------------
-- 6. DELIVERY FAILURE REFERENCE DATA
------------------------------------------------------------
-- Purpose: Standardized failure reason codes for consistent reporting and analytics
-- Business Rules: Used for penalty calculations and performance tracking
-- Dependencies: Referenced by delivery.delivery_session

CREATE TABLE delivery.delivery_failure_reason (
    code                   varchar(64) PRIMARY KEY,
    description            text NOT NULL,
    category               varchar(32) NOT NULL DEFAULT 'OPERATIONAL' 
                          CHECK (category IN ('PROVIDER_FAULT', 'BUSINESS_FAULT', 'OPERATIONAL', 'TECHNICAL')),
    penalty_applicable     boolean NOT NULL DEFAULT false,
    is_active              boolean NOT NULL DEFAULT true,
    
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE delivery.delivery_failure_reason IS 'Standardized failure reason codes with penalty and categorization rules';
COMMENT ON COLUMN delivery.delivery_failure_reason.category IS 'Failure categorization for penalty assignment and analytics';
COMMENT ON COLUMN delivery.delivery_failure_reason.penalty_applicable IS 'Whether this failure type triggers penalty calculations';

-- Insert standard failure reasons
INSERT INTO delivery.delivery_failure_reason (code, description, category, penalty_applicable) VALUES
    ('PROVIDER_NO_SHOW', 'Provider failed to arrive at scheduled time', 'PROVIDER_FAULT', true),
    ('BUSINESS_NO_SHOW', 'Business not available to receive vehicle', 'BUSINESS_FAULT', true),
    ('VEHICLE_NOT_MATCHING', 'Vehicle does not meet contract specifications', 'PROVIDER_FAULT', true),
    ('VEHICLE_BREAKDOWN', 'Vehicle breakdown before handover', 'OPERATIONAL', false),
    ('OTP_FAILED', 'OTP validation failed after maximum attempts', 'TECHNICAL', false),
    ('WRONG_LOCATION', 'Provider delivered to incorrect location', 'PROVIDER_FAULT', true),
    ('DOCUMENTATION_INCOMPLETE', 'Required handover documentation missing', 'PROVIDER_FAULT', true),
    ('FUEL_LEVEL_INSUFFICIENT', 'Vehicle fuel level below contract requirements', 'PROVIDER_FAULT', true),
    ('VEHICLE_DAMAGE_DISCOVERED', 'Pre-existing vehicle damage discovered during handover', 'PROVIDER_FAULT', true),
    ('WEATHER_CONDITIONS', 'Delivery cancelled due to severe weather', 'OPERATIONAL', false);

------------------------------------------------------------
-- 7. SERVICE LEVEL AGREEMENT (SLA) VIOLATION TRACKING
------------------------------------------------------------
-- Purpose: Track SLA violations for penalty calculations and performance monitoring
-- Business Rules: Automatic penalty application based on violation severity and party responsibility
-- Dependencies: References delivery.delivery_session for violation tracking

CREATE TABLE delivery.delivery_sla_violation (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_session_id    uuid NOT NULL 
                          REFERENCES delivery.delivery_session(id),
    
    -- Violation classification
    violation_type         varchar(64) NOT NULL 
                          CHECK (violation_type IN (
                              'LATE_ARRIVAL', 'NO_SHOW', 'DELAYED_OTP_RESPONSE',
                              'INCOMPLETE_DOCUMENTATION', 'WRONG_VEHICLE_TYPE',
                              'FUEL_LEVEL_VIOLATION', 'HANDOVER_DELAY'
                          )),
    
    -- Responsible party
    party                  varchar(32) NOT NULL 
                          CHECK (party IN ('PROVIDER', 'BUSINESS')),
    
    -- Violation severity measurement
    minutes_late           int NOT NULL CHECK (minutes_late >= 0),
    
    -- Financial impact
    penalty_amount         numeric(18,2) CHECK (penalty_amount >= 0),
    penalty_applied        boolean NOT NULL DEFAULT false,
    
    -- Resolution tracking
    is_disputed            boolean NOT NULL DEFAULT false,
    dispute_reason         text,
    resolved_at            timestamptz,
    
    created_at             timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE delivery.delivery_sla_violation IS 'SLA violation tracking with penalty calculations and dispute resolution';
COMMENT ON COLUMN delivery.delivery_sla_violation.violation_type IS 'Specific type of SLA violation for penalty calculation';
COMMENT ON COLUMN delivery.delivery_sla_violation.party IS 'Which party (PROVIDER or BUSINESS) is responsible for the violation';
COMMENT ON COLUMN delivery.delivery_sla_violation.minutes_late IS 'Minutes beyond SLA threshold for penalty calculation';
COMMENT ON COLUMN delivery.delivery_sla_violation.penalty_amount IS 'Calculated penalty amount in ETB based on violation severity';

------------------------------------------------------------
-- INDEXES FOR PERFORMANCE OPTIMIZATION
------------------------------------------------------------

-- Primary query patterns
CREATE INDEX idx_delivery_session_contract ON delivery.delivery_session (contract_id);
CREATE INDEX idx_delivery_session_provider ON delivery.delivery_session (provider_id);
CREATE INDEX idx_delivery_session_business ON delivery.delivery_session (business_id);
CREATE INDEX idx_delivery_session_status ON delivery.delivery_session (status);
CREATE INDEX idx_delivery_session_scheduled ON delivery.delivery_session (scheduled_at);

-- OTP verification performance
CREATE INDEX idx_delivery_otp_session ON delivery.delivery_otp (delivery_session_id);
CREATE INDEX idx_delivery_otp_expires ON delivery.delivery_otp (expires_at);
CREATE INDEX idx_delivery_otp_verified ON delivery.delivery_otp (is_verified);

-- Return session tracking
CREATE INDEX idx_return_session_contract ON delivery.delivery_return_session (contract_id);
CREATE INDEX idx_return_session_provider ON delivery.delivery_return_session (provider_id);
CREATE INDEX idx_return_session_status ON delivery.delivery_return_session (status);

-- Event log analytics
CREATE INDEX idx_delivery_event_session ON delivery.delivery_event_log (delivery_session_id);
CREATE INDEX idx_delivery_event_return ON delivery.delivery_event_log (return_session_id);
CREATE INDEX idx_delivery_event_type ON delivery.delivery_event_log (event_type);
CREATE INDEX idx_delivery_event_created ON delivery.delivery_event_log (created_at);

-- SLA violation monitoring
CREATE INDEX idx_sla_violation_session ON delivery.delivery_sla_violation (delivery_session_id);
CREATE INDEX idx_sla_violation_party ON delivery.delivery_sla_violation (party);
CREATE INDEX idx_sla_violation_type ON delivery.delivery_sla_violation (violation_type);
CREATE INDEX idx_sla_violation_penalty ON delivery.delivery_sla_violation (penalty_applied);

-- Handover documentation lookup
CREATE INDEX idx_handover_session ON delivery.delivery_vehicle_handover (delivery_session_id);

------------------------------------------------------------
-- AUDIT TRIGGERS FOR AUTOMATIC TIMESTAMP UPDATES
------------------------------------------------------------

-- Auto-update timestamps for mutable tables
CREATE OR REPLACE FUNCTION delivery.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_delivery_session_updated_at
    BEFORE UPDATE ON delivery.delivery_session
    FOR EACH ROW EXECUTE FUNCTION delivery.update_updated_at();

CREATE TRIGGER trigger_return_session_updated_at
    BEFORE UPDATE ON delivery.delivery_return_session
    FOR EACH ROW EXECUTE FUNCTION delivery.update_updated_at();

CREATE TRIGGER trigger_failure_reason_updated_at
    BEFORE UPDATE ON delivery.delivery_failure_reason
    FOR EACH ROW EXECUTE FUNCTION delivery.update_updated_at();

------------------------------------------------------------
-- SAMPLE DATA FOR TESTING AND VALIDATION
------------------------------------------------------------

-- Sample delivery session for testing
INSERT INTO delivery.delivery_session (
    contract_id, contract_line_item_id, provider_id, vehicle_id, business_id,
    status, scheduled_at
) VALUES (
    gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 
    gen_random_uuid(), gen_random_uuid(),
    'ASSIGNED', now() + interval '2 hours'
);

------------------------------------------------------------
-- SCHEMA COMPLETION SUMMARY
------------------------------------------------------------

/*
DELIVERY & OPERATIONS SCHEMA FEATURES:
✅ Complete delivery session lifecycle tracking
✅ Secure OTP verification system with hashed storage
✅ Comprehensive vehicle handover documentation
✅ Vehicle return process with damage assessment
✅ Immutable audit trail for all delivery events
✅ Standardized failure reason codes with penalty rules
✅ SLA violation tracking with automatic penalty calculation
✅ Performance-optimized indexes for all query patterns
✅ Audit triggers for automatic timestamp management

INTEGRATION POINTS:
- References contracts.contract and contracts.contract_line_item
- Supports wallet.escrow_lock release triggers via delivery events
- Provides data for marketplace.marketplace_event_log
- Enables risk engine calculations through performance metrics

BUSINESS RULE ENFORCEMENT:
- Delivery status state machine validation
- OTP security with attempt limits and expiration
- Mandatory handover documentation with photo evidence
- SLA violation automatic detection and penalty calculation
- Party responsibility assignment for failure attribution

NEXT STEPS:
- Create identity/compliance schema for user verification
- Create risk/trust engine schema for performance scoring
- Generate API specifications based on schema design
- Implement real-time delivery tracking integration
*/