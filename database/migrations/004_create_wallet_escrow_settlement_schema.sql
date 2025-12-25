-- =============================================================================
-- Wallet, Escrow & Settlement Schema Migration
-- Movello B2B Mobility Marketplace
-- =============================================================================
-- Purpose: Create the wallet schema for financial operations, escrow management,
--          settlement cycles, commission tracking, and payment processing
-- Version: V040
-- Date: 2025-11-26
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS wallet;

-- For gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

------------------------------------------------------------
-- 1. WALLET ACCOUNTS
------------------------------------------------------------

CREATE TABLE wallet.wallet_account (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_type    varchar(32) NOT NULL,
    owner_id      uuid,
    account_type  varchar(32) NOT NULL,
    currency      varchar(8) NOT NULL DEFAULT 'ETB',
    status        varchar(32) NOT NULL DEFAULT 'ACTIVE',
    balance       numeric(18,2) NOT NULL DEFAULT 0,
    locked_balance numeric(18,2) NOT NULL DEFAULT 0,
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    created_by    uuid,
    updated_by    uuid,
    CONSTRAINT uq_wallet_account_owner_type UNIQUE (owner_type, owner_id, account_type, currency),
    CONSTRAINT chk_wallet_owner_type CHECK (owner_type IN ('BUSINESS', 'PROVIDER', 'PLATFORM')),
    CONSTRAINT chk_wallet_account_type CHECK (account_type IN ('MAIN', 'ESCROW', 'COMMISSION', 'RESERVE', 'SETTLEMENT')),
    CONSTRAINT chk_wallet_status CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CLOSED', 'FROZEN')),
    CONSTRAINT chk_wallet_balances CHECK (balance >= 0 AND locked_balance >= 0 AND locked_balance <= balance)
);

COMMENT ON TABLE wallet.wallet_account IS 'Digital wallet accounts for businesses, providers, and platform operations';
COMMENT ON COLUMN wallet.wallet_account.owner_type IS 'BUSINESS=Business client wallet, PROVIDER=Provider wallet, PLATFORM=Platform operational accounts';
COMMENT ON COLUMN wallet.wallet_account.account_type IS 'MAIN=Primary wallet, ESCROW=Locked funds, COMMISSION=Platform earnings, RESERVE=Security deposits, SETTLEMENT=Pending payouts';
COMMENT ON COLUMN wallet.wallet_account.owner_id IS 'NULL for PLATFORM-level accounts (commission, reserve pools)';
COMMENT ON COLUMN wallet.wallet_account.balance IS 'Total available balance including locked funds';
COMMENT ON COLUMN wallet.wallet_account.locked_balance IS 'Amount currently locked in escrow or pending transactions';

CREATE INDEX idx_wallet_account_owner ON wallet.wallet_account(owner_type, owner_id);
CREATE INDEX idx_wallet_account_type ON wallet.wallet_account(account_type);
CREATE INDEX idx_wallet_account_status ON wallet.wallet_account(status);
CREATE INDEX idx_wallet_account_active ON wallet.wallet_account(is_active);

------------------------------------------------------------
-- 2. LEDGER TRANSACTIONS (HEADER)
------------------------------------------------------------

CREATE TABLE wallet.wallet_ledger_transaction (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference            varchar(128) NOT NULL,
    description          text,
    transaction_type     varchar(32) NOT NULL,
    total_amount         numeric(18,2) NOT NULL,
    currency             varchar(8) NOT NULL DEFAULT 'ETB',
    status               varchar(32) NOT NULL DEFAULT 'PENDING',
    created_by_user_id   uuid,
    is_active            boolean NOT NULL DEFAULT true,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_wallet_ledger_tx_reference UNIQUE (reference),
    CONSTRAINT chk_tx_type CHECK (transaction_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'ESCROW_LOCK', 'ESCROW_RELEASE', 'COMMISSION', 'PENALTY', 'REFUND', 'SETTLEMENT')),
    CONSTRAINT chk_tx_status CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    CONSTRAINT chk_tx_amount CHECK (total_amount > 0)
);

COMMENT ON TABLE wallet.wallet_ledger_transaction IS 'Transaction headers for double-entry bookkeeping with idempotency';
COMMENT ON COLUMN wallet.wallet_ledger_transaction.reference IS 'Unique external reference for idempotency (e.g., DEPOSIT-2025-11-26-001)';
COMMENT ON COLUMN wallet.wallet_ledger_transaction.transaction_type IS 'High-level transaction category for reporting and reconciliation';

CREATE INDEX idx_wallet_ledger_tx_reference ON wallet.wallet_ledger_transaction(reference);
CREATE INDEX idx_wallet_ledger_tx_type ON wallet.wallet_ledger_transaction(transaction_type);
CREATE INDEX idx_wallet_ledger_tx_status ON wallet.wallet_ledger_transaction(status);
CREATE INDEX idx_wallet_ledger_tx_created ON wallet.wallet_ledger_transaction(created_at);
CREATE INDEX idx_wallet_ledger_tx_active ON wallet.wallet_ledger_transaction(is_active);

------------------------------------------------------------
-- 3. LEDGER ENTRIES (DOUBLE-ENTRY LINES)
------------------------------------------------------------

CREATE TABLE wallet.wallet_ledger_entry (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id      uuid NOT NULL REFERENCES wallet.wallet_ledger_transaction(id) ON DELETE CASCADE,
    wallet_account_id   uuid NOT NULL REFERENCES wallet.wallet_account(id) ON DELETE RESTRICT,
    direction           varchar(8) NOT NULL,
    amount              numeric(18,2) NOT NULL,
    currency            varchar(8) NOT NULL DEFAULT 'ETB',
    running_balance     numeric(18,2),
    related_type        varchar(32),
    related_id          uuid,
    notes               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_entry_direction CHECK (direction IN ('DEBIT', 'CREDIT')),
    CONSTRAINT chk_entry_amount CHECK (amount > 0),
    CONSTRAINT chk_related_type CHECK (related_type IN ('DEPOSIT', 'ESCROW_LOCK', 'ESCROW_RELEASE', 'COMMISSION', 'PAYOUT', 'REFUND', 'PENALTY', 'CONTRACT', 'SETTLEMENT'))
);

COMMENT ON TABLE wallet.wallet_ledger_entry IS 'Individual double-entry lines for each transaction maintaining accounting integrity';
COMMENT ON COLUMN wallet.wallet_ledger_entry.direction IS 'DEBIT=Money out/expense, CREDIT=Money in/revenue';
COMMENT ON COLUMN wallet.wallet_ledger_entry.running_balance IS 'Account balance after this entry (for performance)';
COMMENT ON COLUMN wallet.wallet_ledger_entry.related_type IS 'Links entry to business objects (contracts, settlements, etc.)';

CREATE INDEX idx_wallet_ledger_entry_wallet ON wallet.wallet_ledger_entry(wallet_account_id);
CREATE INDEX idx_wallet_ledger_entry_transaction ON wallet.wallet_ledger_entry(transaction_id);
CREATE INDEX idx_wallet_ledger_entry_related ON wallet.wallet_ledger_entry(related_type, related_id);
CREATE INDEX idx_wallet_ledger_entry_created ON wallet.wallet_ledger_entry(created_at);

------------------------------------------------------------
-- 4. WALLET BALANCE SNAPSHOT
------------------------------------------------------------

CREATE TABLE wallet.wallet_balance_snapshot (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_account_id uuid NOT NULL REFERENCES wallet.wallet_account(id) ON DELETE CASCADE,
    balance           numeric(18,2) NOT NULL,
    locked_balance    numeric(18,2) NOT NULL DEFAULT 0,
    available_balance numeric(18,2) NOT NULL,
    as_of             timestamptz NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_snapshot_balances CHECK (balance >= 0 AND locked_balance >= 0 AND available_balance >= 0 AND available_balance = balance - locked_balance)
);

COMMENT ON TABLE wallet.wallet_balance_snapshot IS 'Historical balance snapshots for audit trails and reporting';
COMMENT ON COLUMN wallet.wallet_balance_snapshot.available_balance IS 'Computed: balance - locked_balance for quick queries';
COMMENT ON COLUMN wallet.wallet_balance_snapshot.as_of IS 'Timestamp this snapshot represents (end of day, transaction time, etc.)';

CREATE INDEX idx_wallet_balance_snapshot_wallet ON wallet.wallet_balance_snapshot(wallet_account_id, as_of);
CREATE INDEX idx_wallet_balance_snapshot_as_of ON wallet.wallet_balance_snapshot(as_of);

------------------------------------------------------------
-- 5. ESCROW LOCKS
------------------------------------------------------------

CREATE TABLE wallet.escrow_lock (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id           uuid NOT NULL,
    business_wallet_id    uuid NOT NULL REFERENCES wallet.wallet_account(id) ON DELETE RESTRICT,
    provider_wallet_id    uuid REFERENCES wallet.wallet_account(id) ON DELETE RESTRICT,
    amount_total          numeric(18,2) NOT NULL,
    currency              varchar(8) NOT NULL DEFAULT 'ETB',
    locked_amount         numeric(18,2) NOT NULL DEFAULT 0,
    released_amount       numeric(18,2) NOT NULL DEFAULT 0,
    commission_amount     numeric(18,2) NOT NULL DEFAULT 0,
    status                varchar(32) NOT NULL DEFAULT 'PENDING_LOCK',
    lock_date             timestamptz,
    release_date          timestamptz,
    expiry_date           timestamptz,
    notes                 text,
    is_active             boolean NOT NULL DEFAULT true,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    created_by            uuid,
    updated_by            uuid,
    CONSTRAINT chk_escrow_status CHECK (status IN ('PENDING_LOCK', 'LOCKED', 'PARTIAL_RELEASED', 'FULLY_RELEASED', 'CANCELLED', 'FAILED', 'EXPIRED')),
    CONSTRAINT chk_escrow_amounts CHECK (amount_total >= 0 AND locked_amount >= 0 AND released_amount >= 0 AND commission_amount >= 0 AND locked_amount + released_amount + commission_amount <= amount_total)
);

COMMENT ON TABLE wallet.escrow_lock IS 'Escrow locks for contract security deposits and payment guarantees';
COMMENT ON COLUMN wallet.escrow_lock.provider_wallet_id IS 'Destination wallet for release (may be NULL if provider payment method is external)';
COMMENT ON COLUMN wallet.escrow_lock.commission_amount IS 'Platform commission deducted during release';
COMMENT ON COLUMN wallet.escrow_lock.lock_date IS 'When funds were successfully locked';
COMMENT ON COLUMN wallet.escrow_lock.expiry_date IS 'Automatic release date if no manual action taken';

CREATE INDEX idx_escrow_lock_contract ON wallet.escrow_lock(contract_id);
CREATE INDEX idx_escrow_lock_business ON wallet.escrow_lock(business_wallet_id);
CREATE INDEX idx_escrow_lock_provider ON wallet.escrow_lock(provider_wallet_id);
CREATE INDEX idx_escrow_lock_status ON wallet.escrow_lock(status);
CREATE INDEX idx_escrow_lock_dates ON wallet.escrow_lock(lock_date, release_date, expiry_date);
CREATE INDEX idx_escrow_lock_active ON wallet.escrow_lock(is_active);

------------------------------------------------------------
-- 6. SETTLEMENT CYCLES (PER PROVIDER)
------------------------------------------------------------

CREATE TABLE wallet.settlement_cycle (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id             uuid NOT NULL,
    period_start            timestamptz NOT NULL,
    period_end              timestamptz NOT NULL,
    status                  varchar(32) NOT NULL DEFAULT 'OPEN',
    total_gross_amount      numeric(18,2) NOT NULL DEFAULT 0,
    total_commission_amount numeric(18,2) NOT NULL DEFAULT 0,
    total_penalty_amount    numeric(18,2) NOT NULL DEFAULT 0,
    total_net_payable       numeric(18,2) NOT NULL DEFAULT 0,
    currency                varchar(8) NOT NULL DEFAULT 'ETB',
    calculation_date        timestamptz,
    payment_date            timestamptz,
    notes                   text,
    is_active               boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    created_by              uuid,
    updated_by              uuid,
    CONSTRAINT chk_settlement_status CHECK (status IN ('OPEN', 'CALCULATED', 'PAID', 'PARTIALLY_PAID', 'FAILED', 'CANCELLED')),
    CONSTRAINT chk_settlement_dates CHECK (period_end > period_start),
    CONSTRAINT chk_settlement_amounts CHECK (total_gross_amount >= 0 AND total_commission_amount >= 0 AND total_penalty_amount >= 0 AND total_net_payable >= 0)
);

COMMENT ON TABLE wallet.settlement_cycle IS 'Provider settlement periods with earnings calculation and payout tracking';
COMMENT ON COLUMN wallet.settlement_cycle.total_gross_amount IS 'Total earnings before commissions and penalties';
COMMENT ON COLUMN wallet.settlement_cycle.total_net_payable IS 'Final amount to pay: gross - commission - penalties';
COMMENT ON COLUMN wallet.settlement_cycle.calculation_date IS 'When amounts were calculated and locked';

CREATE INDEX idx_settlement_cycle_provider ON wallet.settlement_cycle(provider_id, period_start, period_end);
CREATE INDEX idx_settlement_cycle_status ON wallet.settlement_cycle(status);
CREATE INDEX idx_settlement_cycle_dates ON wallet.settlement_cycle(period_start, period_end);
CREATE INDEX idx_settlement_cycle_active ON wallet.settlement_cycle(is_active);

------------------------------------------------------------
-- 7. SETTLEMENT PAYOUTS
------------------------------------------------------------

CREATE TABLE wallet.settlement_payout (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    settlement_cycle_id    uuid NOT NULL REFERENCES wallet.settlement_cycle(id) ON DELETE CASCADE,
    provider_id            uuid NOT NULL,
    wallet_transaction_id  uuid REFERENCES wallet.wallet_ledger_transaction(id) ON DELETE RESTRICT,
    amount                 numeric(18,2) NOT NULL,
    currency               varchar(8) NOT NULL DEFAULT 'ETB',
    status                 varchar(32) NOT NULL DEFAULT 'PENDING',
    payment_method         varchar(64),
    payment_reference      varchar(128),
    payment_details        jsonb,
    failure_reason         text,
    is_active              boolean NOT NULL DEFAULT true,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    created_by             uuid,
    updated_by             uuid,
    CONSTRAINT chk_payout_status CHECK (status IN ('PENDING', 'PROCESSING', 'PAID', 'FAILED', 'CANCELLED')),
    CONSTRAINT chk_payout_amount CHECK (amount > 0)
);

COMMENT ON TABLE wallet.settlement_payout IS 'Individual payout transactions within settlement cycles';
COMMENT ON COLUMN wallet.settlement_payout.payment_method IS 'BANK_TRANSFER, MOBILE_MONEY, CHAPA, TELEBIRR, etc.';
COMMENT ON COLUMN wallet.settlement_payout.payment_details IS 'Method-specific details (account numbers, phone numbers, etc.)';
COMMENT ON COLUMN wallet.settlement_payout.failure_reason IS 'Explanation if status=FAILED';

CREATE INDEX idx_settlement_payout_cycle ON wallet.settlement_payout(settlement_cycle_id);
CREATE INDEX idx_settlement_payout_provider ON wallet.settlement_payout(provider_id);
CREATE INDEX idx_settlement_payout_status ON wallet.settlement_payout(status);
CREATE INDEX idx_settlement_payout_transaction ON wallet.settlement_payout(wallet_transaction_id);
CREATE INDEX idx_settlement_payout_active ON wallet.settlement_payout(is_active);

------------------------------------------------------------
-- 8. COMMISSION ENTRIES
------------------------------------------------------------

CREATE TABLE wallet.commission_entry (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id            uuid NOT NULL,
    provider_id            uuid NOT NULL,
    settlement_cycle_id    uuid REFERENCES wallet.settlement_cycle(id),
    amount                 numeric(18,2) NOT NULL,
    currency               varchar(8) NOT NULL DEFAULT 'ETB',
    source                 varchar(32) NOT NULL,
    commission_rate        numeric(5,4),
    base_amount            numeric(18,2),
    billing_date           date NOT NULL,
    notes                  text,
    is_active              boolean NOT NULL DEFAULT true,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_commission_source CHECK (source IN ('CONTRACT_RENTAL', 'INSTANT_PAYOUT_FEE', 'PENALTY', 'LATE_FEE', 'OTHER')),
    CONSTRAINT chk_commission_amount CHECK (amount >= 0),
    CONSTRAINT chk_commission_rate CHECK (commission_rate IS NULL OR (commission_rate >= 0 AND commission_rate <= 1))
);

COMMENT ON TABLE wallet.commission_entry IS 'Platform commission earnings per contract and billing period';
COMMENT ON COLUMN wallet.commission_entry.source IS 'Type of commission: CONTRACT_RENTAL, INSTANT_PAYOUT_FEE, PENALTY, LATE_FEE, OTHER';
COMMENT ON COLUMN wallet.commission_entry.commission_rate IS 'Applied rate (e.g., 0.05 for 5%) - stored for audit';
COMMENT ON COLUMN wallet.commission_entry.base_amount IS 'Amount commission was calculated from';
COMMENT ON COLUMN wallet.commission_entry.billing_date IS 'Date this commission applies to (for monthly cycles)';

CREATE INDEX idx_commission_entry_contract ON wallet.commission_entry(contract_id);
CREATE INDEX idx_commission_entry_provider ON wallet.commission_entry(provider_id);
CREATE INDEX idx_commission_entry_cycle ON wallet.commission_entry(settlement_cycle_id);
CREATE INDEX idx_commission_entry_billing_date ON wallet.commission_entry(billing_date);
CREATE INDEX idx_commission_entry_source ON wallet.commission_entry(source);
CREATE INDEX idx_commission_entry_active ON wallet.commission_entry(is_active);

------------------------------------------------------------
-- 9. PAYMENT INTENTS (BUSINESS TOP-UP)
------------------------------------------------------------

CREATE TABLE wallet.payment_intent (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id          uuid NOT NULL,
    wallet_account_id    uuid NOT NULL REFERENCES wallet.wallet_account(id) ON DELETE RESTRICT,
    amount               numeric(18,2) NOT NULL,
    currency             varchar(8) NOT NULL DEFAULT 'ETB',
    provider_code        varchar(64) NOT NULL,
    status               varchar(32) NOT NULL DEFAULT 'CREATED',
    external_reference   varchar(128),
    callback_payload     jsonb,
    success_url          varchar(512),
    cancel_url           varchar(512),
    expiry_time          timestamptz,
    completed_at         timestamptz,
    notes                text,
    is_active            boolean NOT NULL DEFAULT true,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    created_by           uuid,
    updated_by           uuid,
    CONSTRAINT chk_payment_status CHECK (status IN ('CREATED', 'PENDING', 'COMPLETED', 'FAILED', 'CANCELLED', 'EXPIRED')),
    CONSTRAINT chk_payment_amount CHECK (amount > 0)
);

COMMENT ON TABLE wallet.payment_intent IS 'Business wallet top-up payment requests through external providers';
COMMENT ON COLUMN wallet.payment_intent.provider_code IS 'Payment provider: CHAPA, TELEBIRR, CBE, BANK_TRANSFER, etc.';
COMMENT ON COLUMN wallet.payment_intent.external_reference IS 'Provider transaction ID for reconciliation';
COMMENT ON COLUMN wallet.payment_intent.callback_payload IS 'Full webhook/callback data from provider';

CREATE INDEX idx_payment_intent_business ON wallet.payment_intent(business_id, status);
CREATE INDEX idx_payment_intent_wallet ON wallet.payment_intent(wallet_account_id);
CREATE INDEX idx_payment_intent_status ON wallet.payment_intent(status);
CREATE INDEX idx_payment_intent_provider ON wallet.payment_intent(provider_code);
CREATE INDEX idx_payment_intent_external ON wallet.payment_intent(external_reference);
CREATE INDEX idx_payment_intent_active ON wallet.payment_intent(is_active);

------------------------------------------------------------
-- 10. REFUND REQUESTS
------------------------------------------------------------

CREATE TABLE wallet.refund_request (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_account_id   uuid NOT NULL REFERENCES wallet.wallet_account(id) ON DELETE RESTRICT,
    contract_id         uuid,
    amount              numeric(18,2) NOT NULL,
    currency            varchar(8) NOT NULL DEFAULT 'ETB',
    reason              text,
    status              varchar(32) NOT NULL DEFAULT 'REQUESTED',
    refund_method       varchar(64),
    refund_reference    varchar(128),
    requested_by_user_id uuid NOT NULL,
    processed_by_user_id uuid,
    requested_at         timestamptz NOT NULL DEFAULT now(),
    processed_at         timestamptz,
    notes               text,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    created_by          uuid,
    updated_by          uuid,
    CONSTRAINT chk_refund_status CHECK (status IN ('REQUESTED', 'APPROVED', 'REJECTED', 'PAID', 'FAILED', 'CANCELLED')),
    CONSTRAINT chk_refund_amount CHECK (amount > 0)
);

COMMENT ON TABLE wallet.refund_request IS 'Customer refund requests with approval workflow';
COMMENT ON COLUMN wallet.refund_request.refund_method IS 'How refund will be paid: ORIGINAL_METHOD, BANK_TRANSFER, MOBILE_MONEY, etc.';
COMMENT ON COLUMN wallet.refund_request.refund_reference IS 'External transaction reference if paid outside platform';

CREATE INDEX idx_refund_request_wallet ON wallet.refund_request(wallet_account_id);
CREATE INDEX idx_refund_request_contract ON wallet.refund_request(contract_id);
CREATE INDEX idx_refund_request_status ON wallet.refund_request(status);
CREATE INDEX idx_refund_request_requested_by ON wallet.refund_request(requested_by_user_id);
CREATE INDEX idx_refund_request_processed_by ON wallet.refund_request(processed_by_user_id);
CREATE INDEX idx_refund_request_active ON wallet.refund_request(is_active);

------------------------------------------------------------
-- 11. WALLET EVENT LOG (AUDIT)
------------------------------------------------------------

CREATE TABLE wallet.wallet_event_log (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_account_id uuid,
    transaction_id    uuid,
    event_type        varchar(64) NOT NULL,
    event_payload     jsonb,
    actor_id          uuid,
    actor_type        varchar(32),
    created_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE wallet.wallet_event_log IS 'Comprehensive audit trail of all wallet and financial events';
COMMENT ON COLUMN wallet.wallet_event_log.event_type IS 'E.g., WALLET_CREATED, DEPOSIT_COMPLETED, ESCROW_LOCKED, SETTLEMENT_CALCULATED, PAYOUT_FAILED';
COMMENT ON COLUMN wallet.wallet_event_log.actor_type IS 'BUSINESS, PROVIDER, ADMIN, SYSTEM, PAYMENT_PROVIDER';

CREATE INDEX idx_wallet_event_log_wallet ON wallet.wallet_event_log(wallet_account_id);
CREATE INDEX idx_wallet_event_log_transaction ON wallet.wallet_event_log(transaction_id);
CREATE INDEX idx_wallet_event_log_type ON wallet.wallet_event_log(event_type);
CREATE INDEX idx_wallet_event_log_actor ON wallet.wallet_event_log(actor_id);
CREATE INDEX idx_wallet_event_log_created ON wallet.wallet_event_log(created_at);

------------------------------------------------------------
-- 12. AUDIT TRIGGERS
------------------------------------------------------------

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION wallet.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers
CREATE TRIGGER trg_wallet_account_updated_at BEFORE UPDATE ON wallet.wallet_account FOR EACH ROW EXECUTE FUNCTION wallet.update_updated_at_column();
CREATE TRIGGER trg_wallet_ledger_transaction_updated_at BEFORE UPDATE ON wallet.wallet_ledger_transaction FOR EACH ROW EXECUTE FUNCTION wallet.update_updated_at_column();
CREATE TRIGGER trg_escrow_lock_updated_at BEFORE UPDATE ON wallet.escrow_lock FOR EACH ROW EXECUTE FUNCTION wallet.update_updated_at_column();
CREATE TRIGGER trg_settlement_cycle_updated_at BEFORE UPDATE ON wallet.settlement_cycle FOR EACH ROW EXECUTE FUNCTION wallet.update_updated_at_column();
CREATE TRIGGER trg_settlement_payout_updated_at BEFORE UPDATE ON wallet.settlement_payout FOR EACH ROW EXECUTE FUNCTION wallet.update_updated_at_column();
CREATE TRIGGER trg_payment_intent_updated_at BEFORE UPDATE ON wallet.payment_intent FOR EACH ROW EXECUTE FUNCTION wallet.update_updated_at_column();
CREATE TRIGGER trg_refund_request_updated_at BEFORE UPDATE ON wallet.refund_request FOR EACH ROW EXECUTE FUNCTION wallet.update_updated_at_column();

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================