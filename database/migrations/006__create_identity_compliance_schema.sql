-- V010__create_identity_compliance_schema.sql

CREATE SCHEMA IF NOT EXISTS identity;

-- For gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

------------------------------------------------------------
-- 1. USER IDENTITY TABLES
------------------------------------------------------------

CREATE TABLE identity.user_account (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    keycloak_id  varchar(128) NOT NULL UNIQUE,
    email        varchar(256) NOT NULL,
    phone        varchar(32),
    full_name    varchar(256),
    user_type    varchar(32) NOT NULL,  -- 'PROVIDER','BUSINESS','ADMIN',...
    status       varchar(32) NOT NULL DEFAULT 'ACTIVE', -- 'ACTIVE','SUSPENDED','DELETED'
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.user_device (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES identity.user_account(id) ON DELETE CASCADE,
    device_id    varchar(256) NOT NULL,           -- hashed fingerprint
    user_agent   text,
    ip_address   varchar(64),
    trust_score  int NOT NULL DEFAULT 0,          -- 0-100
    is_trusted   boolean NOT NULL DEFAULT false,
    last_used_at timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_device UNIQUE (user_id, device_id)
);

CREATE TABLE identity.user_login_session (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        uuid NOT NULL REFERENCES identity.user_account(id) ON DELETE CASCADE,
    device_id      varchar(256),
    ip_address     varchar(64),
    status         varchar(32) NOT NULL DEFAULT 'PENDING_MFA', -- 'PENDING_MFA','ACTIVE','TERMINATED'
    mfa_verified_at timestamptz,
    last_seen_at   timestamptz,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.user_mfa_challenge (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES identity.user_account(id) ON DELETE CASCADE,
    session_id   uuid NOT NULL REFERENCES identity.user_login_session(id) ON DELETE CASCADE,
    otp_hash     varchar(256) NOT NULL,
    channel      varchar(32) NOT NULL,           -- 'SMS','EMAIL'
    expires_at   timestamptz NOT NULL,
    attempt_count int NOT NULL DEFAULT 0,
    status       varchar(32) NOT NULL DEFAULT 'PENDING', -- 'PENDING','VERIFIED','EXPIRED'
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

------------------------------------------------------------
-- 2. PROVIDERS
------------------------------------------------------------

CREATE TABLE identity.provider (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                  uuid NOT NULL REFERENCES identity.user_account(id) ON DELETE RESTRICT,
    provider_type            varchar(32) NOT NULL,  -- 'INDIVIDUAL','AGENT','COMPANY'
    name                     varchar(256) NOT NULL,
    tin_number               varchar(64),
    business_license_number  varchar(128),
    status                   varchar(32) NOT NULL DEFAULT 'PENDING_VERIFICATION', -- 'PENDING_VERIFICATION','ACTIVE','SUSPENDED'
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.provider_profile (
    provider_id           uuid PRIMARY KEY REFERENCES identity.provider(id) ON DELETE CASCADE,
    fleet_size            int,
    years_in_operation    int,
    avg_response_time_ms  bigint,
    preferred_regions     jsonb,
    onboarding_completed  boolean NOT NULL DEFAULT false,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.provider_tier_assignment (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id     uuid NOT NULL REFERENCES identity.provider(id) ON DELETE CASCADE,
    tier_code       varchar(64) NOT NULL,    -- references masterdata.provider_tier(code) logically
    assigned_at     timestamptz NOT NULL DEFAULT now(),
    computed_score  int NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_provider_tier UNIQUE (provider_id, tier_code)
);

------------------------------------------------------------
-- 3. BUSINESS CLIENTS
------------------------------------------------------------

CREATE TABLE identity.business (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              uuid NOT NULL REFERENCES identity.user_account(id) ON DELETE RESTRICT,
    business_name        varchar(256) NOT NULL,
    business_type        varchar(64) NOT NULL,  -- 'PLC','SHARE_COMPANY','NGO','GOV', ...
    tin_number           varchar(64),
    registration_number  varchar(128),
    status               varchar(32) NOT NULL DEFAULT 'PENDING_KYB', -- 'PENDING_KYB','ACTIVE','SUSPENDED'
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.business_profile (
    business_id         uuid PRIMARY KEY REFERENCES identity.business(id) ON DELETE CASCADE,
    business_tier_code  varchar(64),  -- from masterdata.business_tier
    employee_count      int,
    rfq_limit           int,
    onboarding_completed boolean NOT NULL DEFAULT false,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

------------------------------------------------------------
-- 4. VEHICLES & VEHICLE COMPLIANCE
------------------------------------------------------------

CREATE TABLE identity.vehicle (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id        uuid NOT NULL REFERENCES identity.provider(id) ON DELETE CASCADE,
    plate_number       varchar(64) NOT NULL,
    vehicle_type_code  varchar(64) NOT NULL,  -- maps to masterdata.lookup code (VEHICLE_TYPE)
    engine_type_code   varchar(64),           -- maps to masterdata.lookup code (ENGINE_TYPE)
    seat_count         int NOT NULL,
    model_year         int,
    brand              varchar(128),
    model              varchar(128),
    tags               text[],                -- e.g. ['luxury','guest','vip']
    status             varchar(32) NOT NULL DEFAULT 'UNDER_REVIEW', -- 'UNDER_REVIEW','ACTIVE','BLOCKED'
    metadata           jsonb,
    front_image_url    text,
    back_image_url     text,
    left_image_url     text,
    right_image_url    text,
    interior_image_url text,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_vehicle_plate UNIQUE (plate_number)
);

CREATE TABLE identity.vehicle_document (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id        uuid NOT NULL REFERENCES identity.vehicle(id) ON DELETE CASCADE,
    document_type_id  uuid NOT NULL,         -- logically references masterdata.document_type(id)
    file_url          text NOT NULL,
    issued_at         timestamptz,
    expires_at        timestamptz,
    verified_status   varchar(32) NOT NULL DEFAULT 'PENDING', -- 'PENDING','VERIFIED','REJECTED'
    verifier_id       uuid,                 -- FK to identity.user_account(id) (admin), nullable
    verified_at       timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.vehicle_insurance (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id             uuid NOT NULL REFERENCES identity.vehicle(id) ON DELETE CASCADE,
    insurance_type         varchar(64) NOT NULL,     -- 'FULL','THIRD_PARTY','COMPREHENSIVE', etc.
    insurance_company_name varchar(256) NOT NULL,
    policy_number          varchar(128),
    insured_amount         numeric(18,2),
    coverage_start_date    date,
    coverage_end_date      date,
    certificate_file_url   text NOT NULL,            -- pdf/image URL
    status                 varchar(32) NOT NULL DEFAULT 'PENDING_VERIFICATION', -- 'PENDING_VERIFICATION','ACTIVE','EXPIRED'
    verifier_id            uuid,                     -- admin user
    verified_at            timestamptz,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_vehicle_insurance_expiry
    ON identity.vehicle_insurance (coverage_end_date);

------------------------------------------------------------
-- 5. DOCUMENTS FOR USERS / PROVIDERS / BUSINESSES
------------------------------------------------------------

CREATE TABLE identity.user_document (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid NOT NULL REFERENCES identity.user_account(id) ON DELETE CASCADE,
    document_type_id  uuid NOT NULL,   -- masterdata.document_type
    file_url          text NOT NULL,
    issued_at         timestamptz,
    expires_at        timestamptz,
    verified_status   varchar(32) NOT NULL DEFAULT 'PENDING', -- 'PENDING','VERIFIED','REJECTED'
    verifier_id       uuid,
    verified_at       timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.provider_document (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id       uuid NOT NULL REFERENCES identity.provider(id) ON DELETE CASCADE,
    document_type_id  uuid NOT NULL,
    file_url          text NOT NULL,
    issued_at         timestamptz,
    expires_at        timestamptz,
    verified_status   varchar(32) NOT NULL DEFAULT 'PENDING',
    verifier_id       uuid,
    verified_at       timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.business_document (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id       uuid NOT NULL REFERENCES identity.business(id) ON DELETE CASCADE,
    document_type_id  uuid NOT NULL,
    file_url          text NOT NULL,
    issued_at         timestamptz,
    expires_at        timestamptz,
    verified_status   varchar(32) NOT NULL DEFAULT 'PENDING',
    verifier_id       uuid,
    verified_at       timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

------------------------------------------------------------
-- 6. VERIFICATION WORKFLOW
------------------------------------------------------------

CREATE TABLE identity.verification_request (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_type      varchar(32) NOT NULL,   -- 'USER','PROVIDER','BUSINESS','VEHICLE'
    actor_id        uuid NOT NULL,
    status          varchar(32) NOT NULL DEFAULT 'PENDING', -- 'PENDING','IN_REVIEW','APPROVED','REJECTED'
    submitted_at    timestamptz NOT NULL DEFAULT now(),
    reviewed_at     timestamptz,
    reviewer_id     uuid,
    rejection_reason text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.compliance_check_log (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_type   varchar(32) NOT NULL,
    actor_id     uuid NOT NULL,
    check_type   varchar(64) NOT NULL,  -- 'DOCUMENT_EXPIRY_CHECK','TRUST_SCORE_RECALC', etc.
    details      jsonb,
    created_at   timestamptz NOT NULL DEFAULT now()
);

------------------------------------------------------------
-- 7. TRUST SCORE & RISK
------------------------------------------------------------

CREATE TABLE identity.provider_trust_score_history (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id           uuid NOT NULL REFERENCES identity.provider(id) ON DELETE CASCADE,
    old_score             int,
    new_score             int NOT NULL,
    reason                varchar(64) NOT NULL,     -- 'AUTOMATIC','ADMIN_ADJUSTMENT',...
    calculation_snapshot  jsonb,
    created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.risk_event (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid REFERENCES identity.user_account(id) ON DELETE CASCADE,
    event_type   varchar(64) NOT NULL,   -- 'NEW_DEVICE','GEO_MISMATCH','FAILED_LOGIN_SPREE',...
    data         jsonb,
    severity     varchar(32) NOT NULL DEFAULT 'LOW', -- 'LOW','MEDIUM','HIGH'
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.account_flag (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_type  varchar(32) NOT NULL,   -- 'PROVIDER','BUSINESS'
    actor_id    uuid NOT NULL,
    flag_type   varchar(64) NOT NULL,   -- 'SUSPICIOUS','HIGH_RISK','DOCUMENT_EXPIRED',...
    created_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz
);

CREATE INDEX idx_account_flag_actor
    ON identity.account_flag(actor_type, actor_id);
