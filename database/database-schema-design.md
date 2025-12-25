# Database Schema Design - B2B Mobility Marketplace

## Database Overview

**Database Engine:** PostgreSQL 16  
**ORM:** Entity Framework Core 9  
**Architecture:** Modular Monolith with Schema Separation  
**Naming Convention:** snake_case for database, PascalCase for C# entities  

---

## Schema Organization

### PostgreSQL Schemas (Logical Separation)

```sql
CREATE SCHEMA business;      -- Business entities and KYB
CREATE SCHEMA provider;      -- Provider entities and KYC
CREATE SCHEMA rfq;           -- RFQ and bidding
CREATE SCHEMA contracts;     -- Contracts and delivery
CREATE SCHEMA finance;       -- Wallets, ledger, billing
CREATE SCHEMA risk;          -- Risk scores and trust
CREATE SCHEMA notifications; -- Notifications and templates
CREATE SCHEMA shared;        -- Shared/lookup tables
```

---

## Module 1: Business Schema

### Table: business.businesses

**Purpose:** Store business account information and KYB status

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| keycloak_user_id | VARCHAR(100) | UNIQUE, NOT NULL | Keycloak user ID |
| company_name | VARCHAR(200) | NOT NULL | Legal company name |
| registration_number | VARCHAR(50) | UNIQUE, NOT NULL | Business registration number |
| tax_number | VARCHAR(50) | UNIQUE | Tax identification number |
| email | VARCHAR(255) | UNIQUE, NOT NULL | Business email |
| phone | VARCHAR(20) | NOT NULL | Contact phone |
| industry | VARCHAR(100) | NOT NULL | Industry sector |
| company_size | VARCHAR(20) | | Small, Medium, Large |
| website | VARCHAR(255) | | Company website |
| status | VARCHAR(20) | NOT NULL | Pending, Verified, Rejected, Suspended |
| verification_status | VARCHAR(20) | NOT NULL | Unverified, InReview, Verified, Rejected |
| verification_date | TIMESTAMP | | Date of verification |
| verified_by | UUID | FK → shared.users | Admin who verified |
| rejection_reason | TEXT | | Reason if rejected |
| address_line1 | VARCHAR(255) | NOT NULL | Street address |
| address_line2 | VARCHAR(255) | | Additional address |
| city | VARCHAR(100) | NOT NULL | City |
| state | VARCHAR(100) | NOT NULL | State/Province |
| country | VARCHAR(2) | NOT NULL | ISO country code |
| postal_code | VARCHAR(20) | NOT NULL | Postal/ZIP code |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update timestamp |
| created_by | UUID | | User who created |
| updated_by | UUID | | User who last updated |
| is_deleted | BOOLEAN | NOT NULL, DEFAULT FALSE | Soft delete flag |
| deleted_at | TIMESTAMP | | Deletion timestamp |

**Indexes:**
```sql
CREATE INDEX idx_businesses_email ON business.businesses(email);
CREATE INDEX idx_businesses_status ON business.businesses(status);
CREATE INDEX idx_businesses_verification_status ON business.businesses(verification_status);
CREATE INDEX idx_businesses_created_at ON business.businesses(created_at);
CREATE INDEX idx_businesses_keycloak_user_id ON business.businesses(keycloak_user_id);
```

---

### Table: business.business_documents

**Purpose:** Store KYB documents uploaded by businesses

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| business_id | UUID | FK → businesses, NOT NULL | Business reference |
| document_type | VARCHAR(50) | NOT NULL | BusinessLicense, TaxCertificate, ProofOfAddress, Other |
| file_name | VARCHAR(255) | NOT NULL | Original file name |
| file_path | VARCHAR(500) | NOT NULL | MinIO path |
| file_size | BIGINT | NOT NULL | File size in bytes |
| mime_type | VARCHAR(100) | NOT NULL | File MIME type |
| verification_status | VARCHAR(20) | NOT NULL | Pending, Verified, Rejected |
| verified_by | UUID | FK → shared.users | Admin who verified |
| verified_at | TIMESTAMP | | Verification timestamp |
| rejection_reason | TEXT | | Reason if rejected |
| uploaded_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Upload timestamp |
| uploaded_by | UUID | NOT NULL | User who uploaded |
| is_deleted | BOOLEAN | NOT NULL, DEFAULT FALSE | Soft delete flag |

**Indexes:**
```sql
CREATE INDEX idx_business_documents_business_id ON business.business_documents(business_id);
CREATE INDEX idx_business_documents_type ON business.business_documents(document_type);
CREATE INDEX idx_business_documents_status ON business.business_documents(verification_status);
```

---

## Module 2: Provider Schema

### Table: provider.providers

**Purpose:** Store provider account information and KYC status

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| keycloak_user_id | VARCHAR(100) | UNIQUE, NOT NULL | Keycloak user ID |
| provider_type | VARCHAR(20) | NOT NULL | Individual, Company |
| company_name | VARCHAR(200) | | Company name (if applicable) |
| first_name | VARCHAR(100) | NOT NULL | First name |
| last_name | VARCHAR(100) | NOT NULL | Last name |
| email | VARCHAR(255) | UNIQUE, NOT NULL | Provider email |
| phone | VARCHAR(20) | NOT NULL | Contact phone |
| id_number | VARCHAR(50) | UNIQUE, NOT NULL | National ID/Passport |
| driver_license_number | VARCHAR(50) | UNIQUE, NOT NULL | Driver's license |
| license_expiry_date | DATE | NOT NULL | License expiry |
| business_registration_number | VARCHAR(50) | UNIQUE | If company |
| tax_number | VARCHAR(50) | | Tax ID |
| status | VARCHAR(20) | NOT NULL | Pending, Verified, Rejected, Suspended |
| verification_status | VARCHAR(20) | NOT NULL | Unverified, InReview, Verified, Rejected |
| verification_date | TIMESTAMP | | Date of verification |
| verified_by | UUID | FK → shared.users | Admin who verified |
| rejection_reason | TEXT | | Reason if rejected |
| address_line1 | VARCHAR(255) | NOT NULL | Street address |
| address_line2 | VARCHAR(255) | | Additional address |
| city | VARCHAR(100) | NOT NULL | City |
| state | VARCHAR(100) | NOT NULL | State/Province |
| country | VARCHAR(2) | NOT NULL | ISO country code |
| postal_code | VARCHAR(20) | NOT NULL | Postal/ZIP code |
| bank_account_name | VARCHAR(200) | | Bank account name |
| bank_account_number | VARCHAR(50) | | Encrypted account number |
| bank_name | VARCHAR(100) | | Bank name |
| bank_branch | VARCHAR(100) | | Bank branch |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update timestamp |
| is_deleted | BOOLEAN | NOT NULL, DEFAULT FALSE | Soft delete flag |

**Indexes:**
```sql
CREATE INDEX idx_providers_email ON provider.providers(email);
CREATE INDEX idx_providers_status ON provider.providers(status);
CREATE INDEX idx_providers_verification_status ON provider.providers(verification_status);
CREATE INDEX idx_providers_created_at ON provider.providers(created_at);
```

---

### Table: provider.provider_documents

**Purpose:** Store KYC documents uploaded by providers

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| provider_id | UUID | FK → providers, NOT NULL | Provider reference |
| document_type | VARCHAR(50) | NOT NULL | NationalID, DriverLicense, BusinessLicense, Other |
| file_name | VARCHAR(255) | NOT NULL | Original file name |
| file_path | VARCHAR(500) | NOT NULL | MinIO path |
| file_size | BIGINT | NOT NULL | File size in bytes |
| mime_type | VARCHAR(100) | NOT NULL | File MIME type |
| verification_status | VARCHAR(20) | NOT NULL | Pending, Verified, Rejected |
| verified_by | UUID | FK → shared.users | Admin who verified |
| verified_at | TIMESTAMP | | Verification timestamp |
| rejection_reason | TEXT | | Reason if rejected |
| uploaded_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Upload timestamp |
| is_deleted | BOOLEAN | NOT NULL, DEFAULT FALSE | Soft delete flag |

**Indexes:**
```sql
CREATE INDEX idx_provider_documents_provider_id ON provider.provider_documents(provider_id);
CREATE INDEX idx_provider_documents_type ON provider.provider_documents(document_type);
```

---

### Table: provider.vehicles

**Purpose:** Store vehicle information registered by providers

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| provider_id | UUID | FK → providers, NOT NULL | Provider reference |
| vehicle_type | VARCHAR(50) | NOT NULL | Sedan, SUV, Van, Truck, Bus |
| make | VARCHAR(100) | NOT NULL | Vehicle manufacturer |
| model | VARCHAR(100) | NOT NULL | Vehicle model |
| year | INTEGER | NOT NULL | Manufacturing year |
| color | VARCHAR(50) | NOT NULL | Vehicle color |
| license_plate | VARCHAR(20) | UNIQUE, NOT NULL | License plate number |
| vin | VARCHAR(17) | UNIQUE | Vehicle identification number |
| seating_capacity | INTEGER | NOT NULL | Number of seats |
| fuel_type | VARCHAR(20) | NOT NULL | Petrol, Diesel, Electric, Hybrid |
| transmission | VARCHAR(20) | NOT NULL | Manual, Automatic |
| mileage | INTEGER | | Current mileage (km) |
| features | JSONB | | Additional features (JSON) |
| daily_rate | DECIMAL(10,2) | | Suggested daily rate |
| status | VARCHAR(20) | NOT NULL | Available, Rented, Maintenance, Inactive |
| verification_status | VARCHAR(20) | NOT NULL | Pending, Verified, Rejected |
| verified_by | UUID | FK → shared.users | Admin who verified |
| verified_at | TIMESTAMP | | Verification timestamp |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update timestamp |
| is_deleted | BOOLEAN | NOT NULL, DEFAULT FALSE | Soft delete flag |

**Indexes:**
```sql
CREATE INDEX idx_vehicles_provider_id ON provider.vehicles(provider_id);
CREATE INDEX idx_vehicles_status ON provider.vehicles(status);
CREATE INDEX idx_vehicles_type ON provider.vehicles(vehicle_type);
CREATE INDEX idx_vehicles_license_plate ON provider.vehicles(license_plate);
CREATE INDEX idx_vehicles_verification_status ON provider.vehicles(verification_status);
```

---

### Table: provider.vehicle_images

**Purpose:** Store vehicle photos

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| vehicle_id | UUID | FK → vehicles, NOT NULL | Vehicle reference |
| image_type | VARCHAR(20) | NOT NULL | Front, Back, Left, Right, Interior, Other |
| file_path | VARCHAR(500) | NOT NULL | MinIO path |
| is_primary | BOOLEAN | NOT NULL, DEFAULT FALSE | Primary image flag |
| display_order | INTEGER | NOT NULL, DEFAULT 0 | Display order |
| uploaded_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Upload timestamp |

**Indexes:**
```sql
CREATE INDEX idx_vehicle_images_vehicle_id ON provider.vehicle_images(vehicle_id);
```

---

### Table: provider.insurance_policies

**Purpose:** Store vehicle insurance information

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| vehicle_id | UUID | FK → vehicles, NOT NULL | Vehicle reference |
| provider_id | UUID | FK → providers, NOT NULL | Provider reference |
| insurance_company | VARCHAR(200) | NOT NULL | Insurance company name |
| policy_number | VARCHAR(100) | UNIQUE, NOT NULL | Policy number |
| policy_type | VARCHAR(50) | NOT NULL | Comprehensive, ThirdParty, Commercial |
| coverage_amount | DECIMAL(12,2) | NOT NULL | Coverage amount |
| start_date | DATE | NOT NULL | Policy start date |
| end_date | DATE | NOT NULL | Policy end date |
| document_path | VARCHAR(500) | NOT NULL | Policy document path |
| verification_status | VARCHAR(20) | NOT NULL | Pending, Verified, Rejected, Expired |
| verified_by | UUID | FK → shared.users | Admin who verified |
| verified_at | TIMESTAMP | | Verification timestamp |
| rejection_reason | TEXT | | Reason if rejected |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update timestamp |
| is_deleted | BOOLEAN | NOT NULL, DEFAULT FALSE | Soft delete flag |

**Indexes:**
```sql
CREATE INDEX idx_insurance_vehicle_id ON provider.insurance_policies(vehicle_id);
CREATE INDEX idx_insurance_provider_id ON provider.insurance_policies(provider_id);
CREATE INDEX idx_insurance_end_date ON provider.insurance_policies(end_date);
CREATE INDEX idx_insurance_status ON provider.insurance_policies(verification_status);
```

---

## Module 3: RFQ Schema

### Table: rfq.rfqs

**Purpose:** Store Request for Quotation from businesses

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| business_id | UUID | FK → business.businesses, NOT NULL | Business reference |
| rfq_number | VARCHAR(20) | UNIQUE, NOT NULL | Auto-generated RFQ number |
| title | VARCHAR(255) | NOT NULL | RFQ title |
| description | TEXT | NOT NULL | Detailed requirements |
| vehicle_type | VARCHAR(50) | NOT NULL | Required vehicle type |
| quantity | INTEGER | NOT NULL | Number of vehicles |
| rental_type | VARCHAR(20) | NOT NULL | ShortTerm, LongTerm |
| start_date | DATE | NOT NULL | Rental start date |
| end_date | DATE | NOT NULL | Rental end date |
| duration_days | INTEGER | NOT NULL | Calculated duration |
| pickup_location | VARCHAR(255) | NOT NULL | Pickup address |
| dropoff_location | VARCHAR(255) | | Dropoff address (if different) |
| additional_requirements | TEXT | | Special requirements |
| budget_min | DECIMAL(12,2) | | Minimum budget |
| budget_max | DECIMAL(12,2) | | Maximum budget |
| status | VARCHAR(20) | NOT NULL | Draft, Published, Closed, Awarded, Cancelled |
| published_at | TIMESTAMP | | Publication timestamp |
| bidding_deadline | TIMESTAMP | NOT NULL | Bid submission deadline |
| closed_at | TIMESTAMP | | Closing timestamp |
| awarded_bid_id | UUID | FK → bids | Winning bid |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update timestamp |
| is_deleted | BOOLEAN | NOT NULL, DEFAULT FALSE | Soft delete flag |

**Indexes:**
```sql
CREATE INDEX idx_rfqs_business_id ON rfq.rfqs(business_id);
CREATE INDEX idx_rfqs_status ON rfq.rfqs(status);
CREATE INDEX idx_rfqs_published_at ON rfq.rfqs(published_at);
CREATE INDEX idx_rfqs_bidding_deadline ON rfq.rfqs(bidding_deadline);
CREATE INDEX idx_rfqs_rfq_number ON rfq.rfqs(rfq_number);
```

---

### Table: rfq.bids

**Purpose:** Store bids submitted by providers

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| rfq_id | UUID | FK → rfqs, NOT NULL | RFQ reference |
| provider_id | UUID | FK → provider.providers, NOT NULL | Provider reference |
| vehicle_id | UUID | FK → provider.vehicles, NOT NULL | Offered vehicle |
| bid_amount | DECIMAL(12,2) | NOT NULL | Total bid amount |
| daily_rate | DECIMAL(10,2) | NOT NULL | Daily rental rate |
| deposit_amount | DECIMAL(10,2) | NOT NULL | Security deposit |
| proposal | TEXT | | Provider's proposal |
| terms_and_conditions | TEXT | | Additional terms |
| status | VARCHAR(20) | NOT NULL | Submitted, Withdrawn, Awarded, Rejected |
| rank | INTEGER | | Bid ranking (calculated) |
| quality_score | DECIMAL(5,2) | | Quality score (0-100) |
| trust_score | DECIMAL(5,2) | | Provider trust score |
| final_score | DECIMAL(5,2) | | Combined score |
| submitted_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Submission timestamp |
| awarded_at | TIMESTAMP | | Award timestamp |
| rejected_at | TIMESTAMP | | Rejection timestamp |
| rejection_reason | TEXT | | Reason if rejected |
| is_deleted | BOOLEAN | NOT NULL, DEFAULT FALSE | Soft delete flag |

**Indexes:**
```sql
CREATE INDEX idx_bids_rfq_id ON rfq.bids(rfq_id);
CREATE INDEX idx_bids_provider_id ON rfq.bids(provider_id);
CREATE INDEX idx_bids_status ON rfq.bids(status);
CREATE INDEX idx_bids_rank ON rfq.bids(rank);
CREATE UNIQUE INDEX idx_bids_rfq_provider ON rfq.bids(rfq_id, provider_id) WHERE is_deleted = FALSE;
```

---

### Table: rfq.bid_history

**Purpose:** Track bid updates and withdrawals

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| bid_id | UUID | FK → bids, NOT NULL | Bid reference |
| action | VARCHAR(20) | NOT NULL | Created, Updated, Withdrawn |
| old_amount | DECIMAL(12,2) | | Previous amount |
| new_amount | DECIMAL(12,2) | | New amount |
| changed_by | UUID | NOT NULL | User who made change |
| changed_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Change timestamp |
| notes | TEXT | | Change notes |

**Indexes:**
```sql
CREATE INDEX idx_bid_history_bid_id ON rfq.bid_history(bid_id);
CREATE INDEX idx_bid_history_changed_at ON rfq.bid_history(changed_at);
```

---

## Module 4: Contracts Schema

### Table: contracts.contracts

**Purpose:** Store rental contracts

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| contract_number | VARCHAR(20) | UNIQUE, NOT NULL | Auto-generated contract number |
| rfq_id | UUID | FK → rfq.rfqs, NOT NULL | RFQ reference |
| bid_id | UUID | FK → rfq.bids, NOT NULL | Winning bid reference |
| business_id | UUID | FK → business.businesses, NOT NULL | Business reference |
| provider_id | UUID | FK → provider.providers, NOT NULL | Provider reference |
| vehicle_id | UUID | FK → provider.vehicles, NOT NULL | Vehicle reference |
| contract_type | VARCHAR(20) | NOT NULL | ShortTerm, LongTerm |
| start_date | DATE | NOT NULL | Contract start date |
| end_date | DATE | NOT NULL | Contract end date |
| daily_rate | DECIMAL(10,2) | NOT NULL | Agreed daily rate |
| total_amount | DECIMAL(12,2) | NOT NULL | Total contract value |
| deposit_amount | DECIMAL(10,2) | NOT NULL | Security deposit |
| status | VARCHAR(20) | NOT NULL | Draft, Active, Suspended, Completed, Cancelled |
| activation_date | TIMESTAMP | | Activation timestamp |
| completion_date | TIMESTAMP | | Completion timestamp |
| cancellation_date | TIMESTAMP | | Cancellation timestamp |
| cancellation_reason | TEXT | | Reason if cancelled |
| terms_and_conditions | TEXT | NOT NULL | Contract terms |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update timestamp |
| is_deleted | BOOLEAN | NOT NULL, DEFAULT FALSE | Soft delete flag |

**Indexes:**
```sql
CREATE INDEX idx_contracts_business_id ON contracts.contracts(business_id);
CREATE INDEX idx_contracts_provider_id ON contracts.contracts(provider_id);
CREATE INDEX idx_contracts_vehicle_id ON contracts.contracts(vehicle_id);
CREATE INDEX idx_contracts_status ON contracts.contracts(status);
CREATE INDEX idx_contracts_start_date ON contracts.contracts(start_date);
CREATE INDEX idx_contracts_end_date ON contracts.contracts(end_date);
CREATE INDEX idx_contracts_contract_number ON contracts.contracts(contract_number);
```

---

### Table: contracts.delivery_events

**Purpose:** Track vehicle delivery and return with OTP verification

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| contract_id | UUID | FK → contracts, NOT NULL | Contract reference |
| event_type | VARCHAR(20) | NOT NULL | Delivery, Return |
| otp_code | VARCHAR(6) | NOT NULL | 6-digit OTP |
| otp_generated_at | TIMESTAMP | NOT NULL | OTP generation time |
| otp_expires_at | TIMESTAMP | NOT NULL | OTP expiry time |
| otp_verified_at | TIMESTAMP | | OTP verification time |
| verified_by | UUID | | User who verified |
| verification_status | VARCHAR(20) | NOT NULL | Pending, Verified, Expired, Failed |
| attempt_count | INTEGER | NOT NULL, DEFAULT 0 | Verification attempts |
| location | VARCHAR(255) | | Delivery/return location |
| odometer_reading | INTEGER | | Vehicle odometer reading |
| fuel_level | VARCHAR(20) | | Fuel level (Full, Half, Quarter, Empty) |
| condition_notes | TEXT | | Vehicle condition notes |
| photos | JSONB | | Photo paths (JSON array) |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
```sql
CREATE INDEX idx_delivery_events_contract_id ON contracts.delivery_events(contract_id);
CREATE INDEX idx_delivery_events_type ON contracts.delivery_events(event_type);
CREATE INDEX idx_delivery_events_status ON contracts.delivery_events(verification_status);
```

---

### Table: contracts.contract_renewals

**Purpose:** Track contract renewal requests and approvals

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| contract_id | UUID | FK → contracts, NOT NULL | Original contract |
| new_end_date | DATE | NOT NULL | Proposed new end date |
| additional_days | INTEGER | NOT NULL | Days to extend |
| daily_rate | DECIMAL(10,2) | NOT NULL | Rate for extension |
| total_amount | DECIMAL(12,2) | NOT NULL | Additional amount |
| status | VARCHAR(20) | NOT NULL | Pending, Approved, Rejected |
| requested_by | UUID | NOT NULL | Business user |
| requested_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Request timestamp |
| approved_by | UUID | | Provider user |
| approved_at | TIMESTAMP | | Approval timestamp |
| rejection_reason | TEXT | | Reason if rejected |

**Indexes:**
```sql
CREATE INDEX idx_contract_renewals_contract_id ON contracts.contract_renewals(contract_id);
CREATE INDEX idx_contract_renewals_status ON contracts.contract_renewals(status);
```

---

## Module 5: Finance Schema

### Table: finance.wallets

**Purpose:** Store digital wallet balances for businesses and providers

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| owner_id | UUID | NOT NULL | Business or Provider ID |
| owner_type | VARCHAR(20) | NOT NULL | Business, Provider |
| balance | DECIMAL(12,2) | NOT NULL, DEFAULT 0 | Current balance |
| escrow_balance | DECIMAL(12,2) | NOT NULL, DEFAULT 0 | Locked in escrow |
| available_balance | DECIMAL(12,2) | NOT NULL, DEFAULT 0 | Available for withdrawal |
| currency | VARCHAR(3) | NOT NULL, DEFAULT 'ETB' | Currency code |
| status | VARCHAR(20) | NOT NULL | Active, Suspended, Closed |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update timestamp |

**Indexes:**
```sql
CREATE UNIQUE INDEX idx_wallets_owner ON finance.wallets(owner_id, owner_type);
CREATE INDEX idx_wallets_status ON finance.wallets(status);
```

**Constraints:**
```sql
ALTER TABLE finance.wallets ADD CONSTRAINT chk_balance_positive CHECK (balance >= 0);
ALTER TABLE finance.wallets ADD CONSTRAINT chk_escrow_positive CHECK (escrow_balance >= 0);
```

---

### Table: finance.wallet_transactions

**Purpose:** Track all wallet transactions

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| wallet_id | UUID | FK → wallets, NOT NULL | Wallet reference |
| transaction_type | VARCHAR(30) | NOT NULL | Deposit, Withdrawal, EscrowLock, EscrowRelease, Fee, Refund |
| amount | DECIMAL(12,2) | NOT NULL | Transaction amount |
| balance_before | DECIMAL(12,2) | NOT NULL | Balance before transaction |
| balance_after | DECIMAL(12,2) | NOT NULL | Balance after transaction |
| reference_type | VARCHAR(50) | | Contract, Payment, Settlement |
| reference_id | UUID | | Reference entity ID |
| description | TEXT | | Transaction description |
| status | VARCHAR(20) | NOT NULL | Pending, Completed, Failed, Reversed |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| processed_at | TIMESTAMP | | Processing timestamp |

**Indexes:**
```sql
CREATE INDEX idx_wallet_transactions_wallet_id ON finance.wallet_transactions(wallet_id);
CREATE INDEX idx_wallet_transactions_type ON finance.wallet_transactions(transaction_type);
CREATE INDEX idx_wallet_transactions_created_at ON finance.wallet_transactions(created_at);
CREATE INDEX idx_wallet_transactions_reference ON finance.wallet_transactions(reference_type, reference_id);
```

---

### Table: finance.ledger_entries

**Purpose:** Daily ledger entries for active contracts

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| contract_id | UUID | FK → contracts.contracts, NOT NULL | Contract reference |
| business_id | UUID | FK → business.businesses, NOT NULL | Business reference |
| provider_id | UUID | FK → provider.providers, NOT NULL | Provider reference |
| entry_date | DATE | NOT NULL | Ledger date |
| daily_rate | DECIMAL(10,2) | NOT NULL | Daily rental rate |
| platform_commission_rate | DECIMAL(5,2) | NOT NULL | Commission % (e.g., 5.00) |
| platform_commission | DECIMAL(10,2) | NOT NULL | Commission amount |
| provider_earnings | DECIMAL(10,2) | NOT NULL | Provider net earnings |
| status | VARCHAR(20) | NOT NULL | Pending, Processed, Settled |
| processed_at | TIMESTAMP | | Processing timestamp |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
```sql
CREATE INDEX idx_ledger_contract_id ON finance.ledger_entries(contract_id);
CREATE INDEX idx_ledger_entry_date ON finance.ledger_entries(entry_date);
CREATE INDEX idx_ledger_status ON finance.ledger_entries(status);
CREATE UNIQUE INDEX idx_ledger_contract_date ON finance.ledger_entries(contract_id, entry_date);
```

---

### Table: finance.invoices

**Purpose:** Monthly invoices for businesses

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| invoice_number | VARCHAR(20) | UNIQUE, NOT NULL | Auto-generated invoice number |
| business_id | UUID | FK → business.businesses, NOT NULL | Business reference |
| billing_period_start | DATE | NOT NULL | Billing period start |
| billing_period_end | DATE | NOT NULL | Billing period end |
| subtotal | DECIMAL(12,2) | NOT NULL | Subtotal amount |
| tax_amount | DECIMAL(12,2) | NOT NULL, DEFAULT 0 | Tax amount |
| total_amount | DECIMAL(12,2) | NOT NULL | Total amount |
| status | VARCHAR(20) | NOT NULL | Draft, Sent, Paid, Overdue, Cancelled |
| due_date | DATE | NOT NULL | Payment due date |
| paid_at | TIMESTAMP | | Payment timestamp |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
```sql
CREATE INDEX idx_invoices_business_id ON finance.invoices(business_id);
CREATE INDEX idx_invoices_status ON finance.invoices(status);
CREATE INDEX idx_invoices_due_date ON finance.invoices(due_date);
CREATE INDEX idx_invoices_invoice_number ON finance.invoices(invoice_number);
```

---

### Table: finance.settlements

**Purpose:** Monthly settlements for providers

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| settlement_number | VARCHAR(20) | UNIQUE, NOT NULL | Auto-generated settlement number |
| provider_id | UUID | FK → provider.providers, NOT NULL | Provider reference |
| settlement_period_start | DATE | NOT NULL | Settlement period start |
| settlement_period_end | DATE | NOT NULL | Settlement period end |
| gross_earnings | DECIMAL(12,2) | NOT NULL | Total earnings |
| platform_commission | DECIMAL(12,2) | NOT NULL | Commission deducted |
| tax_deduction | DECIMAL(12,2) | NOT NULL, DEFAULT 0 | Tax withheld |
| net_amount | DECIMAL(12,2) | NOT NULL | Net payout amount |
| status | VARCHAR(20) | NOT NULL | Pending, Approved, Paid, Rejected |
| approved_by | UUID | FK → shared.users | Admin who approved |
| approved_at | TIMESTAMP | | Approval timestamp |
| paid_at | TIMESTAMP | | Payment timestamp |
| payment_method | VARCHAR(20) | | BankTransfer, MobileMoney |
| payment_reference | VARCHAR(100) | | Payment transaction reference |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
```sql
CREATE INDEX idx_settlements_provider_id ON finance.settlements(provider_id);
CREATE INDEX idx_settlements_status ON finance.settlements(status);
CREATE INDEX idx_settlements_settlement_number ON finance.settlements(settlement_number);
```

---

## Module 6: Risk & Trust Schema

### Table: risk.business_risk_scores

**Purpose:** Store risk assessment scores for businesses

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| business_id | UUID | FK → business.businesses, NOT NULL | Business reference |
| overall_score | DECIMAL(5,2) | NOT NULL | Overall risk score (0-100) |
| industry_risk_score | DECIMAL(5,2) | NOT NULL | Industry-based score |
| location_risk_score | DECIMAL(5,2) | NOT NULL | Location-based score |
| company_age_score | DECIMAL(5,2) | NOT NULL | Company age score |
| document_verification_score | DECIMAL(5,2) | NOT NULL | KYB verification score |
| payment_history_score | DECIMAL(5,2) | NOT NULL, DEFAULT 50 | Payment behavior score |
| risk_level | VARCHAR(20) | NOT NULL | Low, Medium, High |
| risk_factors | JSONB | | Identified risk factors (JSON) |
| assessed_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Assessment timestamp |
| assessed_by | VARCHAR(50) | NOT NULL | System, Admin |
| expires_at | TIMESTAMP | | Score expiry (re-assessment needed) |

**Indexes:**
```sql
CREATE INDEX idx_business_risk_business_id ON risk.business_risk_scores(business_id);
CREATE INDEX idx_business_risk_level ON risk.business_risk_scores(risk_level);
CREATE INDEX idx_business_risk_assessed_at ON risk.business_risk_scores(assessed_at);
```

---

### Table: risk.provider_trust_scores

**Purpose:** Store trust scores for providers

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| provider_id | UUID | FK → provider.providers, NOT NULL | Provider reference |
| overall_score | DECIMAL(5,2) | NOT NULL | Overall trust score (0-100) |
| completion_rate_score | DECIMAL(5,2) | NOT NULL, DEFAULT 50 | Contract completion rate |
| on_time_delivery_score | DECIMAL(5,2) | NOT NULL, DEFAULT 50 | On-time delivery rate |
| vehicle_condition_score | DECIMAL(5,2) | NOT NULL, DEFAULT 50 | Vehicle quality score |
| customer_rating_score | DECIMAL(5,2) | NOT NULL, DEFAULT 50 | Average customer ratings |
| payment_compliance_score | DECIMAL(5,2) | NOT NULL, DEFAULT 50 | Payment compliance |
| document_compliance_score | DECIMAL(5,2) | NOT NULL | Document validity score |
| trust_level | VARCHAR(20) | NOT NULL | Bronze, Silver, Gold, Platinum |
| total_contracts | INTEGER | NOT NULL, DEFAULT 0 | Total contracts completed |
| total_disputes | INTEGER | NOT NULL, DEFAULT 0 | Total disputes raised |
| calculated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Calculation timestamp |

**Indexes:**
```sql
CREATE INDEX idx_provider_trust_provider_id ON risk.provider_trust_scores(provider_id);
CREATE INDEX idx_provider_trust_level ON risk.provider_trust_scores(trust_level);
CREATE INDEX idx_provider_trust_score ON risk.provider_trust_scores(overall_score);
```

---

### Table: risk.fraud_alerts

**Purpose:** Track potential fraud and suspicious activities

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| alert_type | VARCHAR(50) | NOT NULL | BidCollusion, FakeDocuments, SuspiciousPayment, etc. |
| severity | VARCHAR(20) | NOT NULL | Low, Medium, High, Critical |
| entity_type | VARCHAR(20) | NOT NULL | Business, Provider, RFQ, Bid |
| entity_id | UUID | NOT NULL | Entity reference |
| description | TEXT | NOT NULL | Alert description |
| evidence | JSONB | | Evidence data (JSON) |
| status | VARCHAR(20) | NOT NULL | New, UnderReview, Resolved, FalsePositive |
| assigned_to | UUID | FK → shared.users | Admin assigned |
| resolved_by | UUID | FK → shared.users | Admin who resolved |
| resolved_at | TIMESTAMP | | Resolution timestamp |
| resolution_notes | TEXT | | Resolution notes |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
```sql
CREATE INDEX idx_fraud_alerts_entity ON risk.fraud_alerts(entity_type, entity_id);
CREATE INDEX idx_fraud_alerts_status ON risk.fraud_alerts(status);
CREATE INDEX idx_fraud_alerts_severity ON risk.fraud_alerts(severity);
CREATE INDEX idx_fraud_alerts_created_at ON risk.fraud_alerts(created_at);
```

---

## Module 7: Notifications Schema

### Table: notifications.notifications

**Purpose:** Store all notifications sent to users

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| recipient_id | UUID | NOT NULL | User ID (Business/Provider) |
| recipient_type | VARCHAR(20) | NOT NULL | Business, Provider, Admin |
| notification_type | VARCHAR(50) | NOT NULL | Email, SMS, InApp, Push |
| category | VARCHAR(50) | NOT NULL | Account, RFQ, Bid, Contract, Payment, Alert |
| subject | VARCHAR(255) | NOT NULL | Notification subject |
| message | TEXT | NOT NULL | Notification message |
| data | JSONB | | Additional data (JSON) |
| status | VARCHAR(20) | NOT NULL | Pending, Sent, Failed, Read |
| sent_at | TIMESTAMP | | Sent timestamp |
| read_at | TIMESTAMP | | Read timestamp |
| failed_reason | TEXT | | Failure reason |
| retry_count | INTEGER | NOT NULL, DEFAULT 0 | Retry attempts |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
```sql
CREATE INDEX idx_notifications_recipient ON notifications.notifications(recipient_id, recipient_type);
CREATE INDEX idx_notifications_status ON notifications.notifications(status);
CREATE INDEX idx_notifications_created_at ON notifications.notifications(created_at);
CREATE INDEX idx_notifications_category ON notifications.notifications(category);
```

---

### Table: notifications.notification_templates

**Purpose:** Store reusable notification templates

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| template_code | VARCHAR(50) | UNIQUE, NOT NULL | Template identifier |
| template_name | VARCHAR(100) | NOT NULL | Template name |
| category | VARCHAR(50) | NOT NULL | Template category |
| notification_type | VARCHAR(20) | NOT NULL | Email, SMS, InApp |
| subject_template | VARCHAR(255) | | Subject template (for email) |
| body_template | TEXT | NOT NULL | Body template with placeholders |
| variables | JSONB | | Available variables (JSON) |
| is_active | BOOLEAN | NOT NULL, DEFAULT TRUE | Active status |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update timestamp |

**Indexes:**
```sql
CREATE INDEX idx_notification_templates_code ON notifications.notification_templates(template_code);
CREATE INDEX idx_notification_templates_category ON notifications.notification_templates(category);
```

---

## Shared Schema

### Table: shared.users

**Purpose:** Store admin/system users

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| keycloak_user_id | VARCHAR(100) | UNIQUE, NOT NULL | Keycloak user ID |
| email | VARCHAR(255) | UNIQUE, NOT NULL | User email |
| first_name | VARCHAR(100) | NOT NULL | First name |
| last_name | VARCHAR(100) | NOT NULL | Last name |
| role | VARCHAR(20) | NOT NULL | Admin, Support, Auditor |
| is_active | BOOLEAN | NOT NULL, DEFAULT TRUE | Active status |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update timestamp |

**Indexes:**
```sql
CREATE INDEX idx_users_email ON shared.users(email);
CREATE INDEX idx_users_role ON shared.users(role);
```

---

### Table: shared.audit_logs

**Purpose:** Track all important system actions

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK | Unique identifier |
| user_id | UUID | | User who performed action |
| user_type | VARCHAR(20) | | Business, Provider, Admin |
| action | VARCHAR(50) | NOT NULL | Action performed |
| entity_type | VARCHAR(50) | NOT NULL | Entity affected |
| entity_id | UUID | | Entity ID |
| old_values | JSONB | | Old values (JSON) |
| new_values | JSONB | | New values (JSON) |
| ip_address | VARCHAR(45) | | User IP address |
| user_agent | VARCHAR(255) | | User agent string |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Action timestamp |

**Indexes:**
```sql
CREATE INDEX idx_audit_logs_user ON shared.audit_logs(user_id, user_type);
CREATE INDEX idx_audit_logs_entity ON shared.audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_logs_created_at ON shared.audit_logs(created_at);
CREATE INDEX idx_audit_logs_action ON shared.audit_logs(action);
```

---

## Database Optimization Strategies

### 1. Indexing Strategy
- **Primary Keys:** All tables use UUID for global uniqueness
- **Foreign Keys:** Indexed for join performance
- **Status Fields:** Indexed for filtering
- **Date Fields:** Indexed for range queries
- **Unique Constraints:** Prevent duplicates

### 2. Partitioning (Future)
```sql
-- Partition audit_logs by month
CREATE TABLE shared.audit_logs_2025_01 PARTITION OF shared.audit_logs
FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
```

### 3. Soft Deletes
- Use `is_deleted` flag instead of hard deletes
- Maintains referential integrity
- Allows data recovery

### 4. Timestamps
- All tables have `created_at` and `updated_at`
- Automatic triggers for `updated_at`

### 5. JSONB Usage
- Store flexible data (features, evidence, metadata)
- Indexable with GIN indexes
- Queryable with JSON operators

---

## Relationships Summary

```
business.businesses (1) ──< (N) business.business_documents
business.businesses (1) ──< (N) rfq.rfqs
business.businesses (1) ──< (N) contracts.contracts
business.businesses (1) ──< (N) finance.invoices
business.businesses (1) ──< (1) finance.wallets
business.businesses (1) ──< (N) risk.business_risk_scores

provider.providers (1) ──< (N) provider.provider_documents
provider.providers (1) ──< (N) provider.vehicles
provider.providers (1) ──< (N) provider.insurance_policies
provider.providers (1) ──< (N) rfq.bids
provider.providers (1) ──< (N) contracts.contracts
provider.providers (1) ──< (N) finance.settlements
provider.providers (1) ──< (1) finance.wallets
provider.providers (1) ──< (N) risk.provider_trust_scores

provider.vehicles (1) ──< (N) provider.vehicle_images
provider.vehicles (1) ──< (N) provider.insurance_policies
provider.vehicles (1) ──< (N) rfq.bids
provider.vehicles (1) ──< (N) contracts.contracts

rfq.rfqs (1) ──< (N) rfq.bids
rfq.rfqs (1) ──< (1) contracts.contracts
rfq.bids (1) ──< (N) rfq.bid_history
rfq.bids (1) ──< (1) contracts.contracts

contracts.contracts (1) ──< (N) contracts.delivery_events
contracts.contracts (1) ──< (N) contracts.contract_renewals
contracts.contracts (1) ──< (N) finance.ledger_entries

finance.wallets (1) ──< (N) finance.wallet_transactions
```

---

## Next Steps

1. ✅ Review this schema design
2. Create EF Core entity classes
3. Create entity configurations (Fluent API)
4. Generate initial migration
5. Seed lookup data
6. Create database views for reporting

Would you like me to create the EF Core entity classes and configurations next?
