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

## ⚙️ System Settings

### Settings Page

**Route:** `/admin/settings`  
**Component:** `src/features/admin/settings/SettingsPage.tsx`

**Sections:**
1. **Commission Rates** - Per tier
2. **Penalty Rates** - Early return penalties
3. **Trust Score Weights** - Calculation parameters
4. **Tier Requirements** - Trust score & vehicle thresholds
5. **Market Prices** - Vehicle type price ranges

---

## ✅ User Stories Summary

### Epic 10: Admin Verification (8 stories)
- MOV-1001: Review Business KYB ⭐ Highest Priority
- MOV-1002: Review Provider KYC ⭐ Highest Priority
- MOV-1003: Approve Verification
- MOV-1004: Reject Verification
- And 4 more...

### Epic 11: Admin Monitoring (7 stories)
- MOV-1101: View Transaction List
- MOV-1102: View User List
- MOV-1103: Suspend User
- And 4 more...

---

**END OF ADMIN PORTAL GUIDE**

*For detailed user stories, see [USER_STORIES_COMPLETE.md](./USER_STORIES_COMPLETE.md)*

