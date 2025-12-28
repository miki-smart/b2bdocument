# Admin Portal Development Guide
## Movello Frontend - React Implementation

**Version:** 1.0  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)

---

## 📋 Table of Contents

1. [Dashboard](#dashboard)
2. [KYC/KYB Verification](#kyckyb-verification)
3. [User Management](#user-management)
4. [Transaction Monitoring](#transaction-monitoring)
5. [System Settings](#system-settings)

---

## 📊 Dashboard

### Route
`/admin/dashboard`

### Features
- **Stat Cards:**
  - Pending Verifications (KYC/KYB)
  - Active Users (Business/Provider)
  - Total Transactions (Today/Month)
  - Platform Revenue
- **Charts:**
  - User Growth (line chart)
  - Transaction Volume (bar chart)
  - Revenue by Month (area chart)
- **Recent Activity:**
  - Latest verifications
  - Recent transactions
  - System alerts

---

## ✅ KYC/KYB Verification

### Verification Queue

**Route:** `/admin/verifications`  
**Component:** `src/features/admin/verifications/pages/VerificationQueuePage.tsx`

**Tabs:**
- Pending Business (KYB)
- Pending Provider (KYC)
- Approved
- Rejected

**Verification Card:**
- Entity Name
- Type (Business/Provider)
- Submitted Date
- Document Count
- Status Badge
- Actions: Review, Approve, Reject

### Verification Detail Page

**Route:** `/admin/verifications/{id}`  
**Component:** `src/features/admin/verifications/pages/VerificationDetailPage.tsx`

**Sections:**
1. **Entity Information**
   - Name, Type, TIN
   - Contact Information
   - Address

2. **Documents Gallery**
   - All uploaded documents
   - Document viewer (PDF/Image)
   - Download buttons

3. **Verification Actions**
   - Approve button
   - Reject button (with reason)
   - Request Additional Documents

**Implementation:**

```typescript
export const VerificationDetailPage = () => {
  const { id } = useParams();
  const { data: verification } = useQuery({
    queryKey: ['verification', id],
    queryFn: () => adminService.getVerification(id!),
  });

  const approveMutation = useMutation({
    mutationFn: () => adminService.approveVerification(id!),
    onSuccess: () => {
      toast.success('Verification approved');
      navigate('/admin/verifications');
    },
  });

  const rejectMutation = useMutation({
    mutationFn: (reason: string) => adminService.rejectVerification(id!, reason),
    onSuccess: () => {
      toast.success('Verification rejected');
      navigate('/admin/verifications');
    },
  });

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Entity Information</CardTitle>
        </CardHeader>
        <CardContent>
          {/* Display entity info */}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Documents</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid md:grid-cols-2 gap-4">
            {verification?.documents.map((doc) => (
              <DocumentViewer key={doc.id} document={doc} />
            ))}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Verification Actions</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Button
            onClick={() => approveMutation.mutate()}
            disabled={approveMutation.isPending}
            className="w-full"
          >
            Approve Verification
          </Button>
          <RejectVerificationDialog
            onReject={(reason) => rejectMutation.mutate(reason)}
          />
        </CardContent>
      </Card>
    </div>
  );
};
```

---

## 👥 User Management

### User List Page

**Route:** `/admin/users`  
**Component:** `src/features/admin/users/pages/UserListPage.tsx`

**Filters:**
- Role (Business, Provider, Admin)
- Status (Active, Suspended, Pending)
- Search by name/email
- Date range (registration)

**Table Columns:**
- Name/Email
- Role
- Status
- Registration Date
- Last Active
- Actions: View, Suspend, Activate

### User Detail Page

**Route:** `/admin/users/{id}`  
**Component:** `src/features/admin/users/pages/UserDetailPage.tsx`

**Tabs:**
1. **Profile** - User information
2. **Activity** - Login history, actions
3. **Transactions** - Financial transactions
4. **Contracts** - Active/completed contracts

---

## 💰 Transaction Monitoring

### Transaction List

**Route:** `/admin/transactions`  
**Component:** `src/features/admin/transactions/pages/TransactionListPage.tsx`

**Filters:**
- Type (Deposit, Settlement, Escrow, etc.)
- Date Range
- User (Business/Provider)
- Amount Range
- Status

**Table Columns:**
- Transaction ID
- Type
- User
- Amount
- Status
- Date
- Actions: View Details

### Transaction Detail

**Route:** `/admin/transactions/{id}`  
**Component:** `src/features/admin/transactions/pages/TransactionDetailPage.tsx`

**Display:**
- Full transaction details
- Related entities (contract, RFQ)
- Ledger entries
- Audit trail

---

## 📦 Master Data Management

### Document Types Management

**Route:** `/admin/master-data/document-types`  
**Component:** `src/features/admin/master-data/pages/DocumentTypesPage.tsx`

**Features:**
- List all document types
- Create new document type
- Update existing document type
- Activate/Deactivate document types

**API Endpoints:**
- `GET /api/document-types` - List document types
- `POST /api/document-types` - Create document type
- `PUT /api/document-types/{id}` - Update document type
- `DELETE /api/document-types/{id}` - Delete document type

**Form Fields:**
- Name (required)
- Code (required, unique)
- Description (optional)
- Max File Size (optional)
- Allowed File Types (array)
- Is Active (boolean)

### KYC Requirements Management

**Route:** `/admin/master-data/kyc-requirements`  
**Component:** `src/features/admin/master-data/pages/KYCRequirementsPage.tsx`

**Features:**
- List all KYC requirements
- Filter by entity type (BUSINESS, PROVIDER, VEHICLE)
- Create new KYC requirement
- Update existing requirement
- Set requirement as required/optional

**API Endpoints:**
- `GET /api/kyc-requirements?entityType={type}` - List requirements
- `POST /api/kyc-requirements` - Create requirement
- `PUT /api/kyc-requirements/{id}` - Update requirement
- `DELETE /api/kyc-requirements/{id}` - Delete requirement

**Form Fields:**
- Entity Type (BUSINESS, PROVIDER, VEHICLE)
- Document Type (dropdown from document types)
- Is Required (boolean)
- Description (optional)
- Max File Size (optional)
- Allowed File Types (array)

### Business Tiers Management

**Route:** `/admin/master-data/business-tiers`  
**Component:** `src/features/admin/master-data/pages/BusinessTiersPage.tsx`

**Features:**
- List all business tiers (STANDARD, BUSINESS_PRO, ENTERPRISE, GOV_NGO)
- Create new tier
- Update tier limits and benefits
- Configure tier rules

**API Endpoints:**
- `GET /api/business-tiers` - List tiers
- `POST /api/business-tiers` - Create tier
- `PUT /api/business-tiers/{id}` - Update tier
- `DELETE /api/business-tiers/{id}` - Delete tier

**Form Fields:**
- Code (required, unique: STANDARD, BUSINESS_PRO, ENTERPRISE, GOV_NGO)
- Name (required)
- Description (optional)
- Max RFQs Per Month (optional, null = unlimited)
- Max Active Contracts (optional)
- Max Vehicles Per RFQ (optional)
- Color Code (hex color for UI)
- Display Order (number)

### Provider Tiers Management

**Route:** `/admin/master-data/provider-tiers`  
**Component:** `src/features/admin/master-data/pages/ProviderTiersPage.tsx`

**Features:**
- List all provider tiers (BRONZE, SILVER, GOLD, PLATINUM)
- Create new tier
- Update commission rates per tier
- Configure tier rules

**API Endpoints:**
- `GET /api/provider-tiers` - List tiers
- `POST /api/provider-tiers` - Create tier
- `PUT /api/provider-tiers/{id}` - Update tier
- `DELETE /api/provider-tiers/{id}` - Delete tier

**Form Fields:**
- Code (required, unique: BRONZE, SILVER, GOLD, PLATINUM)
- Name (required)
- Description (optional)
- Commission Rate (required, decimal: 0.05 = 5%)
- Color Code (hex color for UI)
- Display Order (number)

### Commission Strategies Management

**Route:** `/admin/master-data/commission-strategies`  
**Component:** `src/features/admin/master-data/pages/CommissionStrategiesPage.tsx`

**Features:**
- List commission strategy versions
- Create new version
- Activate/deactivate versions
- View commission rules per tier

**API Endpoints:**
- `GET /api/commission-strategies/versions` - List strategies
- `POST /api/commission-strategies/versions` - Create strategy
- `PUT /api/commission-strategies/versions/{id}` - Update strategy

---

## 📋 RFQ Management (On Behalf of Businesses)

### RFQ List (Admin View)

**Route:** `/admin/rfqs`  
**Component:** `src/features/admin/rfqs/pages/AdminRFQListPage.tsx`

**Features:**
- View all RFQs (no limitations)
- Filter by business, status, date range
- Create RFQ on behalf of business
- Edit/Delete any RFQ
- View bid details for any RFQ

**API Endpoints:**
- `GET /api/marketplace/rfqs` - List all RFQs (admin sees all)
- `POST /api/marketplace/rfqs` - Create RFQ (must provide BusinessId)
- `PUT /api/marketplace/rfqs/{id}` - Update RFQ
- `DELETE /api/marketplace/rfqs/{id}` - Delete RFQ

**Implementation:**

```typescript
export const AdminRFQListPage = () => {
  const { data: rfqs } = useQuery({
    queryKey: ['admin', 'rfqs'],
    queryFn: () => rfqService.getAllRFQs(), // Admin endpoint
  });

  const createRFQMutation = useMutation({
    mutationFn: (data: CreateRFQRequest & { businessId: string }) => 
      rfqService.createRFQ(data),
  });

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold">RFQ Management</h1>
        <CreateRFQDialog
          onSuccess={(data) => createRFQMutation.mutate(data)}
        />
      </div>
      
      <RFQList rfqs={rfqs} showBusinessInfo={true} />
    </div>
  );
};
```

### Create RFQ on Behalf of Business

**Component:** `src/features/admin/rfqs/components/CreateRFQDialog.tsx`

**Additional Field:**
- Business Selection (required dropdown)
- All standard RFQ creation fields

---

## 💼 Bid Management (On Behalf of Providers)

### Bid List (Admin View)

**Route:** `/admin/bids`  
**Component:** `src/features/admin/bids/pages/AdminBidListPage.tsx`

**Features:**
- View all bids (no limitations)
- Filter by provider, RFQ, status
- Submit bid on behalf of provider
- Withdraw any bid
- View bid details

**API Endpoints:**
- `GET /api/marketplace/bids` - List all bids (admin sees all)
- `POST /api/marketplace/bids` - Submit bid (must provide ProviderId)
- `DELETE /api/marketplace/bids/{id}` - Withdraw bid

**Implementation:**

```typescript
export const AdminBidListPage = () => {
  const { data: bids } = useQuery({
    queryKey: ['admin', 'bids'],
    queryFn: () => bidService.getAllBids(), // Admin endpoint
  });

  const submitBidMutation = useMutation({
    mutationFn: (data: SubmitBidCommand & { providerId: string }) => 
      bidService.submitBid(data),
  });

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold">Bid Management</h1>
        <SubmitBidDialog
          onSuccess={(data) => submitBidMutation.mutate(data)}
        />
      </div>
      
      <BidList bids={bids} showProviderInfo={true} />
    </div>
  );
};
```

### Submit Bid on Behalf of Provider

**Component:** `src/features/admin/bids/components/SubmitBidDialog.tsx`

**Additional Field:**
- Provider Selection (required dropdown)
- All standard bid submission fields

---

## 🏢 Business Management

### Business List

**Route:** `/admin/businesses`  
**Component:** `src/features/admin/businesses/pages/BusinessListPage.tsx`

**Features:**
- List all businesses
- Filter by status, tier, type
- Search by name, TIN, email
- View business details
- Update business information
- Suspend/Activate business
- View business contracts and RFQs

**API Endpoints:**
- `GET /api/identity/businesses` - List businesses
- `GET /api/identity/businesses/{id}` - Get business details
- `PUT /api/identity/businesses/{id}` - Update business
- `POST /api/identity/users/{id}/suspend` - Suspend business
- `POST /api/identity/users/{id}/reactivate` - Reactivate business

**Table Columns:**
- Business Name
- TIN Number
- Email
- Status (PENDING, VERIFIED, SUSPENDED, etc.)
- Tier (STANDARD, BUSINESS_PRO, ENTERPRISE, GOV_NGO)
- Registration Date
- Actions: View, Edit, Suspend, Activate

### Business Detail Page

**Route:** `/admin/businesses/{id}`  
**Component:** `src/features/admin/businesses/pages/BusinessDetailPage.tsx`

**Tabs:**
1. **Profile** - Business information, tier, status
2. **Documents** - All uploaded documents
3. **RFQs** - Business RFQs
4. **Contracts** - Business contracts
5. **Transactions** - Financial transactions
6. **Activity** - Audit log

---

## 🚗 Provider Management

### Provider List

**Route:** `/admin/providers`  
**Component:** `src/features/admin/providers/pages/ProviderListPage.tsx`

**Features:**
- List all providers
- Filter by status, tier, type
- Search by name, TIN, email
- View provider details
- Update provider information
- Suspend/Activate provider
- View provider vehicles, bids, contracts

**API Endpoints:**
- `GET /api/identity/providers` - List providers
- `GET /api/identity/providers/{id}` - Get provider details
- `PUT /api/identity/providers/{id}` - Update provider
- `POST /api/identity/users/{id}/suspend` - Suspend provider
- `POST /api/identity/users/{id}/reactivate` - Reactivate provider

**Table Columns:**
- Provider Name
- Type (INDIVIDUAL, AGENT, COMPANY)
- TIN Number (if applicable)
- Email
- Status (PENDING, VERIFIED, SUSPENDED, etc.)
- Tier (BRONZE, SILVER, GOLD, PLATINUM)
- Trust Score
- Registration Date
- Actions: View, Edit, Suspend, Activate

### Provider Detail Page

**Route:** `/admin/providers/{id}`  
**Component:** `src/features/admin/providers/pages/ProviderDetailPage.tsx`

**Tabs:**
1. **Profile** - Provider information, tier, trust score
2. **Documents** - All uploaded documents
3. **Vehicles** - Provider's vehicle fleet
4. **Bids** - Provider's bids
5. **Contracts** - Provider's contracts
6. **Transactions** - Financial transactions
7. **Activity** - Audit log

---

## 🚙 Vehicle Management

### Vehicle List

**Route:** `/admin/vehicles`  
**Component:** `src/features/admin/vehicles/pages/VehicleListPage.tsx`

**Features:**
- List all vehicles
- Filter by provider, status, type
- Search by license plate, VIN
- View vehicle details
- Update vehicle information
- Verify/Reject vehicles
- View vehicle documents and insurance

**API Endpoints:**
- `GET /api/admin/verifications/vehicles` - List vehicles for verification
- `GET /api/identity/vehicles/{id}` - Get vehicle details
- `PUT /api/identity/vehicles/{id}` - Update vehicle
- `PUT /api/admin/verifications/vehicles/{id}/status` - Update verification status

**Table Columns:**
- License Plate
- Make/Model/Year
- Type
- Provider Name
- Status (PENDING_VERIFICATION, ACTIVE, SUSPENDED, etc.)
- Insurance Status
- Registration Date
- Actions: View, Edit, Verify, Reject

### Vehicle Detail Page

**Route:** `/admin/vehicles/{id}`  
**Component:** `src/features/admin/vehicles/pages/VehicleDetailPage.tsx`

**Sections:**
1. **Vehicle Information** - Basic details, photos
2. **Documents** - Ownership, registration documents
3. **Insurance** - Insurance policies and status
4. **Assignments** - Current/past contract assignments
5. **Verification** - Verification status and history

**Verification Actions:**
- Approve Vehicle
- Reject Vehicle (with reason)
- Request Additional Documents

---

## ⚙️ System Settings

### Settings Page

**Route:** `/admin/settings`  
**Component:** `src/features/admin/settings/SettingsPage.tsx`

**Sections:**
1. **Commission Rates** - Per tier (managed via Commission Strategies)
2. **Penalty Rates** - Early return penalties
3. **Trust Score Weights** - Calculation parameters
4. **Tier Requirements** - Trust score & vehicle thresholds
5. **Market Prices** - Vehicle type price ranges
6. **OTP Settings** - Expiry time, max attempts
7. **Settlement Settings** - Approval thresholds, frequencies

---

## ✅ User Stories Summary

### Epic 10: Admin Verification (8 stories)
- MOV-1001: Review Business KYB ⭐ Highest Priority
- MOV-1002: Review Provider KYC ⭐ Highest Priority
- MOV-1003: Approve Verification
- MOV-1004: Reject Verification
- MOV-1005: Review Vehicle Verification
- MOV-1006: Request Additional Documents
- MOV-1007: View Verification History
- MOV-1008: Bulk Verification Actions

### Epic 11: Admin Monitoring (7 stories)
- MOV-1101: View Transaction List
- MOV-1102: View User List
- MOV-1103: Suspend User
- MOV-1104: View System Analytics
- MOV-1105: View Platform Metrics
- MOV-1106: Export Reports
- MOV-1107: View Audit Logs

### Epic 12: Admin Management (NEW - 15 stories)
- MOV-1201: Manage Document Types
- MOV-1202: Manage KYC Requirements
- MOV-1203: Manage Business Tiers
- MOV-1204: Manage Provider Tiers
- MOV-1205: Manage Commission Strategies
- MOV-1206: Create RFQ on Behalf of Business
- MOV-1207: Edit RFQ on Behalf of Business
- MOV-1208: Submit Bid on Behalf of Provider
- MOV-1209: Manage Businesses (CRUD)
- MOV-1210: Manage Providers (CRUD)
- MOV-1211: Manage Vehicles (CRUD)
- MOV-1212: View Business Details
- MOV-1213: View Provider Details
- MOV-1214: View Vehicle Details
- MOV-1215: Configure System Settings

---

**END OF ADMIN PORTAL GUIDE**

*For detailed user stories, see [USER_STORIES_COMPLETE.md](./USER_STORIES_COMPLETE.md)*

