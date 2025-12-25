# 🤖 COMPLETE FRONTEND AI DEVELOPER PROMPT
## Movello B2B Mobility Marketplace - Full Stack Frontend

---

## 🎯 PROJECT OVERVIEW

You are building a **premium B2B Marketplace** for vehicle rentals in Ethiopia. This is a complete, production-ready frontend application using **Next.js 14+ (App Router)** with **local JSON files** as the database.

**Tech Stack:**
- **Framework:** Next.js 14+ (App Router, TypeScript, Server Actions)
- **Styling:** Tailwind CSS + Shadcn/UI components
- **Icons:** Lucide React
- **State:** Zustand or React Context
- **Forms:** React Hook Form + Zod validation
- **Data:** Local JSON files with read/write operations

---

## 🎨 DESIGN SYSTEM (STRICT ADHERENCE)

### Color Palette
```css
/* Primary Colors */
--primary-blue: #2563EB;      /* Blue-600 - Main actions */
--primary-dark: #1E40AF;      /* Blue-800 - Hover states */
--primary-light: #DBEAFE;     /* Blue-100 - Backgrounds */

/* Functional Colors */
--success: #16A34A;           /* Green-600 */
--warning: #CA8A04;           /* Yellow-600 */
--danger: #DC2626;            /* Red-600 */
--info: #0EA5E9;              /* Sky-500 */

/* Neutrals */
--text-primary: #1F2937;      /* Gray-800 */
--text-secondary: #6B7280;    /* Gray-500 */
--border: #E5E7EB;            /* Gray-200 */
--background: #F9FAFB;        /* Gray-50 */
--surface: #FFFFFF;           /* White */
```

### Typography
- **Font:** Inter (Google Fonts)
- **H1:** `text-3xl font-bold text-gray-900`
- **H2:** `text-xl font-semibold text-gray-800`
- **Body:** `text-base text-gray-600`

### Layout Structure
**Dashboard Layout:**
- **Sidebar:** Fixed left, `w-64`, Dark (`bg-slate-900`), White text
- **Header:** Fixed top, `h-16`, White bg, Shadow-sm
- **Content:** `ml-64 mt-16 p-8 bg-gray-50`

---

## 💾 MOCK DATA ARCHITECTURE

Create `src/data/` folder with these JSON files:

### 1. `users.json`
```json
{
  "users": [
    {
      "id": "user-1",
      "email": "business@test.com",
      "password": "password123",
      "role": "BUSINESS",
      "businessId": "biz-1",
      "createdAt": "2025-01-01T00:00:00Z"
    },
    {
      "id": "user-2",
      "email": "provider@test.com",
      "password": "password123",
      "role": "PROVIDER",
      "providerId": "prov-1",
      "createdAt": "2025-01-01T00:00:00Z"
    },
    {
      "id": "user-3",
      "email": "admin@test.com",
      "password": "password123",
      "role": "ADMIN",
      "createdAt": "2025-01-01T00:00:00Z"
    }
  ]
}
```

### 2. `businesses.json`
```json
{
  "businesses": [
    {
      "id": "biz-1",
      "userId": "user-1",
      "businessName": "Acme Corporation",
      "businessType": "PLC",
      "tinNumber": "1234567890",
      "status": "ACTIVE",
      "tier": "BUSINESS_PRO",
      "contactPerson": {
        "fullName": "John Doe",
        "email": "john@acme.com",
        "phone": "+251911234567"
      },
      "address": {
        "city": "Addis Ababa",
        "subcity": "Bole",
        "woreda": "03"
      },
      "documents": [
        {
          "id": "doc-1",
          "type": "BUSINESS_LICENSE",
          "fileUrl": "/uploads/license.pdf",
          "status": "VERIFIED"
        }
      ],
      "createdAt": "2025-01-01T00:00:00Z"
    }
  ]
}
```

### 3. `providers.json`
```json
{
  "providers": [
    {
      "id": "prov-1",
      "userId": "user-2",
      "name": "Ahmed Mohammed",
      "providerType": "INDIVIDUAL",
      "tinNumber": "9876543210",
      "status": "ACTIVE",
      "tier": "GOLD",
      "trustScore": 78,
      "contactInfo": {
        "email": "ahmed@example.com",
        "phone": "+251922345678"
      },
      "fleetSize": 5,
      "activeContracts": 2,
      "totalEarnings": 250000.00,
      "documents": [],
      "createdAt": "2025-01-01T00:00:00Z"
    }
  ]
}
```

### 4. `vehicles.json`
```json
{
  "vehicles": [
    {
      "id": "veh-1",
      "providerId": "prov-1",
      "plateNumber": "AA-12345",
      "vehicleTypeCode": "EV_SEDAN",
      "engineTypeCode": "EV",
      "brand": "BYD",
      "model": "Seagull",
      "modelYear": 2024,
      "seatCount": 5,
      "status": "ACTIVE",
      "tags": ["luxury", "guest"],
      "insurance": {
        "type": "COMPREHENSIVE",
        "companyName": "Nyala Insurance",
        "policyNumber": "POL-123",
        "coverageStartDate": "2025-01-01",
        "coverageEndDate": "2026-01-01",
        "status": "ACTIVE"
      },
      "photos": {
        "front": "/uploads/veh-1-front.jpg",
        "back": "/uploads/veh-1-back.jpg",
        "left": "/uploads/veh-1-left.jpg",
        "right": "/uploads/veh-1-right.jpg",
        "interior": "/uploads/veh-1-interior.jpg"
      },
      "currentContractId": null,
      "createdAt": "2025-01-01T00:00:00Z"
    }
  ]
}
```

### 5. `rfqs.json`
```json
{
  "rfqs": [
    {
      "id": "rfq-1",
      "rfqNumber": "RFQ-2025-001",
      "businessId": "biz-1",
      "title": "Monthly Vehicle Rental - December 2025",
      "description": "Need vehicles for staff transportation",
      "status": "PUBLISHED",
      "startDate": "2025-12-01",
      "endDate": "2025-12-31",
      "bidDeadline": "2025-11-28T23:59:59Z",
      "publishedAt": "2025-11-20T10:00:00Z",
      "lineItems": [
        {
          "id": "line-1",
          "vehicleTypeCode": "EV_SEDAN",
          "engineTypeCode": "EV",
          "quantityRequired": 5,
          "withDriver": true,
          "preferredTags": ["luxury"],
          "bidCount": 3
        },
        {
          "id": "line-2",
          "vehicleTypeCode": "MINIBUS_12",
          "quantityRequired": 2,
          "withDriver": true,
          "bidCount": 2
        }
      ],
      "createdAt": "2025-11-20T09:00:00Z"
    }
  ]
}
```

### 6. `bids.json`
```json
{
  "bids": [
    {
      "id": "bid-1",
      "rfqId": "rfq-1",
      "providerId": "prov-1",
      "providerHash": "Provider •••4411",
      "status": "SUBMITTED",
      "submittedAt": "2025-11-21T14:00:00Z",
      "lineItemBids": [
        {
          "lineItemId": "line-1",
          "quantityOffered": 5,
          "unitPrice": 3500.00,
          "totalPrice": 17500.00,
          "notes": "Brand new BYD EVs"
        }
      ]
    }
  ]
}
```

### 7. `contracts.json`
```json
{
  "contracts": [
    {
      "id": "contract-1",
      "contractNumber": "CNT-2025-001",
      "rfqId": "rfq-1",
      "businessId": "biz-1",
      "status": "ACTIVE",
      "startDate": "2025-12-01",
      "endDate": "2025-12-31",
      "totalValue": 25500.00,
      "escrowAmount": 25500.00,
      "escrowStatus": "LOCKED",
      "lineItems": [
        {
          "id": "contract-line-1",
          "providerId": "prov-1",
          "providerName": "Ahmed Mohammed",
          "vehicleTypeCode": "EV_SEDAN",
          "quantityAwarded": 5,
          "quantityActive": 5,
          "unitAmount": 3500.00,
          "totalAmount": 17500.00,
          "commissionRate": 0.06
        }
      ],
      "createdAt": "2025-11-26T10:00:00Z"
    }
  ]
}
```

### 8. `assignments.json`
```json
{
  "assignments": [
    {
      "id": "assign-1",
      "contractId": "contract-1",
      "contractLineItemId": "contract-line-1",
      "vehicleId": "veh-1",
      "plateNumber": "AA-12345",
      "status": "ACTIVE",
      "assignedAt": "2025-11-26T11:00:00Z",
      "deliverySessionId": "delivery-1",
      "startDateActual": "2025-12-01T08:00:00Z",
      "endDateActual": null
    }
  ]
}
```

### 9. `delivery_sessions.json`
```json
{
  "deliverySessions": [
    {
      "id": "delivery-1",
      "assignmentId": "assign-1",
      "contractId": "contract-1",
      "vehicleId": "veh-1",
      "businessContactPhone": "+251911234567",
      "status": "COMPLETED",
      "otp": {
        "code": "123456",
        "expiresAt": "2025-12-01T08:05:00Z",
        "isUsed": true,
        "attempts": 1
      },
      "handoverEvidence": {
        "odometerReading": 12500,
        "fuelLevel": "FULL",
        "photos": {
          "front": "/uploads/handover-front.jpg"
        },
        "notes": "Vehicle in excellent condition",
        "capturedAt": "2025-12-01T08:10:00Z"
      },
      "createdAt": "2025-11-26T11:00:00Z"
    }
  ]
}
```

### 10. `wallets.json`
```json
{
  "wallets": [
    {
      "id": "wallet-1",
      "ownerType": "BUSINESS",
      "ownerId": "biz-1",
      "balance": 150000.00,
      "lockedBalance": 25500.00,
      "availableBalance": 124500.00,
      "currency": "ETB",
      "transactions": [
        {
          "id": "txn-1",
          "type": "DEPOSIT",
          "amount": 150000.00,
          "status": "COMPLETED",
          "reference": "Initial deposit",
          "createdAt": "2025-11-01T10:00:00Z"
        },
        {
          "id": "txn-2",
          "type": "ESCROW_LOCK",
          "amount": -25500.00,
          "status": "COMPLETED",
          "reference": "Contract CNT-2025-001",
          "createdAt": "2025-11-26T10:00:00Z"
        }
      ]
    },
    {
      "id": "wallet-2",
      "ownerType": "PROVIDER",
      "ownerId": "prov-1",
      "balance": 45000.00,
      "lockedBalance": 0,
      "availableBalance": 45000.00,
      "currency": "ETB",
      "transactions": [
        {
          "id": "txn-3",
          "type": "SETTLEMENT",
          "amount": 45000.00,
          "status": "COMPLETED",
          "reference": "November 2025 Settlement",
          "createdAt": "2025-11-30T23:59:59Z"
        }
      ]
    },
    {
      "id": "wallet-platform",
      "ownerType": "PLATFORM",
      "ownerId": "platform",
      "balance": 15000.00,
      "lockedBalance": 0,
      "availableBalance": 15000.00,
      "currency": "ETB",
      "commissionByTier": {
        "BRONZE": 2000.00,
        "SILVER": 3000.00,
        "GOLD": 7000.00,
        "PLATINUM": 3000.00
      },
      "transactions": []
    }
  ]
}
```

### 11. `notifications.json`
```json
{
  "notifications": [
    {
      "id": "notif-1",
      "userId": "user-1",
      "type": "BID_RECEIVED",
      "title": "New Bid Received",
      "message": "You received a new bid on RFQ-2025-001",
      "isRead": false,
      "createdAt": "2025-11-21T14:00:00Z",
      "actionUrl": "/business/rfqs/rfq-1/bids"
    }
  ]
}
```

### 12. `saved_rfqs.json`
```json
{
  "savedRfqs": [
    {
      "id": "saved-1",
      "providerId": "prov-1",
      "rfqId": "rfq-1",
      "savedAt": "2025-11-20T15:00:00Z"
    }
  ]
}
```

### 13. `master_data.json`
```json
{
  "vehicleTypes": [
    { "code": "EV_SEDAN", "label": "Electric Sedan" },
    { "code": "SEDAN", "label": "Sedan" },
    { "code": "SUV", "label": "SUV" },
    { "code": "MINIBUS_12", "label": "12-Seater Minibus" },
    { "code": "BUS_30", "label": "30-Seater Bus" }
  ],
  "engineTypes": [
    { "code": "EV", "label": "Electric" },
    { "code": "DIESEL", "label": "Diesel" },
    { "code": "PETROL", "label": "Petrol" },
    { "code": "HYBRID", "label": "Hybrid" }
  ],
  "businessTypes": [
    { "code": "PLC", "label": "Public Limited Company" },
    { "code": "NGO", "label": "Non-Governmental Organization" },
    { "code": "GOV", "label": "Government Entity" }
  ],
  "providerTypes": [
    { "code": "INDIVIDUAL", "label": "Individual" },
    { "code": "AGENT", "label": "Agent" },
    { "code": "COMPANY", "label": "Company" }
  ],
  "cities": [
    { "code": "AA", "label": "Addis Ababa" },
    { "code": "DR", "label": "Dire Dawa" },
    { "code": "MK", "label": "Mekelle" }
  ]
}
```

---

## 📄 COMPLETE PAGE LIST (45 Pages)

### **PUBLIC PAGES (3)**

#### 1. Landing Page (`/`)
- Hero section with value proposition
- How it works (3-step process for Business & Provider)
- CTA: "Register as Business" / "Register as Provider"
- Footer with links

#### 2. Login (`/auth/login`)
- Email/Password form
- "Remember me" checkbox
- "Forgot password?" link
- Auto-redirect based on role

#### 3. Forgot Password (`/auth/forgot-password`)
- Email input, Send reset link (Mock)

---

### **BUSINESS ONBOARDING (3)**

#### 4. Business Registration - Step 1 (`/auth/register/business/step-1`)
- **Fields:** Business Name, Type (Dropdown), TIN Number
- **Validation:** TIN must be 10 digits
- **Action:** Next Step

#### 5. Business Registration - Step 2 (`/auth/register/business/step-2`)
- **Fields:** Contact Person (Name, Email, Phone), Address (City, Subcity, Woreda)
- **Action:** Next Step

#### 6. Business Registration - Step 3 (`/auth/register/business/step-3`)
- **Upload:** Business License (PDF), TIN Certificate
- **Action:** Submit → Status: "Pending KYB Verification"
- **Redirect:** Login page with success message

---

### **PROVIDER ONBOARDING (3)**

#### 7. Provider Registration - Step 1 (`/auth/register/provider/step-1`)
- **Fields:** Provider Type, Name, TIN
- **Action:** Next

#### 8. Provider Registration - Step 2 (`/auth/register/provider/step-2`)
- **Fields:** Contact Info, Fleet Size (Estimate)
- **Action:** Next

#### 9. Provider Registration - Step 3 (`/auth/register/provider/step-3`)
- **Upload:** Driver's License, TIN Certificate
- **Action:** Submit → Status: "Pending KYC"

---

### **BUSINESS PORTAL (15)**

#### 10. Business Dashboard (`/business/dashboard`)
- **Widgets:**
  - Active RFQs count (Card)
  - Ongoing Contracts count
  - Wallet Balance (Available / Locked)
- **Quick Actions:** Create RFQ, View Contracts, Top-up Wallet
- **Recent Activity:** Table (Latest bids, contract updates)

#### 11. RFQ List (`/business/rfqs`)
- **Tabs:** Draft, Published, Bidding Closed, Awarded
- **Table:** RFQ Number, Title, Bid Deadline, Line Items Count, Status
- **Actions:** Edit (Draft only), View Bids, Delete

#### 12. Create RFQ - Step 1 (`/business/rfqs/create/step-1`)
- **Fields:** Title, Description, Start Date, End Date, Bid Deadline
- **Validation:** Start Date ≥ Today + 3 days
- **Action:** Next

#### 13. Create RFQ - Step 2 (`/business/rfqs/create/step-2`)
- **Add Line Items:**
  - Vehicle Type (Dropdown), Quantity, With Driver (Toggle), Tags (Multi-select)
  - "Add Another Line Item" button
- **Preview:** Summary table
- **Actions:** Save as Draft, Publish
- **Business Rule:** NO wallet check ✅

#### 14. RFQ Detail (`/business/rfqs/[id]`)
- RFQ details, Line items table
- **If Published:** "View Bids" button
- **If Draft:** "Edit" button

#### 15. Bid Review Page (`/business/rfqs/[id]/bids`) **[CRITICAL]**
- **Layout:** Grouped by Line Item (Accordion or Tabs)
- **Table per Line Item:**
  - Columns: Checkbox, Provider Hash (Blind), Quantity Offered, Unit Price, Total Price, Trust Score (Mock)
  - Sorting: By Price, Trust Score
- **Selection:** Multi-select checkboxes (Split Award support)
- **Bottom Bar:** "Award Selected Bids" button
- **Business Logic:**
  - Can select multiple bids for same line item
  - Can award partial quantity

#### 16. Award Confirmation Modal (`/business/rfqs/[id]/award-confirm`)
- **Summary:**
  - Selected bids table
  - Total Escrow Required: `Sum(Quantity × Unit Price)`
- **Wallet Check:**
  - Show: Available Balance, Required Escrow, Shortfall (if any)
  - **If Insufficient:**
    - Option 1: "Award Partial Quantity" (Calculate max affordable, show quantity)
    - Option 2: "Deposit More Funds" (Link to wallet)
    - Option 3: "Cancel"
- **On Success:**
  - Deduct from `availableBalance`, Add to `lockedBalance`
  - Create Contract in `contracts.json`
  - Reveal Provider Identity
  - Redirect to Contract Detail

#### 17. Contract List (`/business/contracts`)
- **Tabs:** Pending Activation, Active, Completed, Terminated
- **Table:** Contract Number, Provider(s), Start/End Date, Total Value, Status
- **Actions:** View Details, Request Early Return (Active only)

#### 18. Contract Detail (`/business/contracts/[id]`)
- Full contract details, Line items with assigned vehicles
- **Sections:**
  - Contract Info (Number, Dates, Status)
  - Line Items (Provider, Vehicle Type, Quantity, Amount)
  - Assigned Vehicles (Plate Number, Status)
- **Actions:** Sign Contract (if Pending), Request Early Return

#### 19. Contract Sign Page (`/business/contracts/[id]/sign`)
- Display contract terms (Mock legal text)
- **Signature:** Canvas or "I Agree" checkbox
- **Action:** Submit → Status: `PENDING_DELIVERY`

#### 20. Early Return Request (`/business/contracts/[id]/early-return`)
- **Select:** Vehicle(s) to return (Multi-select from active assignments)
- **Fields:** Return Reason (Dropdown), Notes
- **Calculation Preview:**
  - Days Used, Days Remaining
  - Prorated Amount, Penalty (25% for Standard tier)
  - Refund Amount
- **Action:** Submit → Create return request

#### 21. Business Wallet (`/business/wallet`)
- **Summary Cards:**
  - Total Balance
  - Available Balance (Green)
  - Locked Balance (Yellow)
- **Transaction History:**
  - Table: Date, Type, Amount, Status, Reference
  - Filters: Date Range, Type (Dropdown)
  - Pagination
- **Action:** "Deposit Funds" button (Top right)

#### 22. Deposit Funds Modal (`/business/wallet/deposit`)
- **Fields:** Amount (Input), Payment Method (Chapa/Telebirr - Radio)
- **Action:** Submit → Mock success, Update `wallets.json`

#### 23. Business Profile (`/business/profile`)
- **Tabs:** Details, Documents, Settings
- **Details Tab:** Editable form (Name, Contact, Address)
- **Documents Tab:** View uploaded, Upload new
- **Tier Display:** Badge (Standard, Business Pro, Enterprise)

#### 24. Notification Center (`/business/notifications`)
- List of notifications (Unread first)
- **Columns:** Icon, Title, Message, Time
- **Actions:** Mark as Read, Mark All as Read

---

### **PROVIDER PORTAL (17)**

#### 25. Provider Dashboard (`/provider/dashboard`)
- **Widgets:**
  - Active Contracts, Fleet Status (Pie chart: Active/Assigned/Maintenance)
  - Wallet Balance, Trust Score (Gauge)
- **Quick Actions:** Browse Marketplace, Manage Fleet, View Earnings

#### 26. Marketplace - RFQ List (`/marketplace`) **[CRITICAL]**
- **Filters (Left Sidebar):**
  - Vehicle Type (Multi-select checkboxes)
  - Duration (Radio: Short-term <7 days, Long-term ≥30 days, All)
  - Location (Dropdown: Cities)
  - Search by Title (Text input with debounce)
- **Sorting (Dropdown):**
  - Posting Date (Newest First, Oldest First)
  - Popularity (Most Bids, Least Bids)
- **RFQ Cards (Grid):**
  - Title, Business Name, Date Range
  - Line Items Summary (e.g., "5× EV Sedan, 2× Minibus")
  - Bid Count per Line Item (Badge)
  - "Bid Now" button, "Save" icon (Bookmark)
- **Pagination:** Load more or Page numbers

#### 27. RFQ Detail & Bidding (`/marketplace/[id]`)
- **Left Panel:** RFQ Details (Title, Description, Dates, Business Name)
- **Right Panel:** Bidding Form
  - **Per Line Item:**
    - Vehicle Type, Quantity Required
    - Input: Quantity to Offer (≤ Required)
    - Input: Unit Price (ETB)
    - Textarea: Notes (Optional)
  - **Validation:** Provider must have `quantityOffered` active vehicles of that type
  - **Action:** "Submit Bid" → Add to `bids.json`, Increment `bidCount`

#### 28. Saved RFQs (`/provider/saved`)
- List of bookmarked RFQs
- **Actions:** View, Remove from Saved

#### 29. My Bids (`/provider/bids`)
- List of submitted bids
- **Table:** RFQ Title, Line Item, Quantity, Unit Price, Status (Submitted, Awarded, Rejected)
- **Filter:** Status

#### 30. Vehicle List (`/provider/vehicles`)
- **Filters:** Status (Active, Assigned, Under Review, Maintenance)
- **Table/Grid:** Plate Number, Type, Model, Year, Insurance Status, Status
- **Actions:** Add Vehicle, Edit, View Details, Mark as Maintenance

#### 31. Vehicle Registration (`/provider/vehicles/register`)
- **Form:**
  - Plate Number, Type (Dropdown), Make, Model, Year, Seat Count
  - Tags (Multi-select: luxury, guest, economy)
- **Insurance Section:**
  - Type (Dropdown), Company Name, Policy Number
  - Coverage Start/End Dates
  - Upload Certificate (PDF)
- **Photo Upload:** 5 file inputs (Front, Back, Left, Right, Interior)
- **Validation:**
  - Year > 2010
  - Insurance valid for ≥ 30 days from today
- **Action:** Submit → Status: `UNDER_REVIEW`

#### 32. Vehicle Detail (`/provider/vehicles/[id]`)
- **Sections:**
  - Basic Info, Insurance Details, Photos (Gallery)
- **Actions:** Edit, Mark as Maintenance, Delete (if not assigned)

#### 33. Provider Contracts (`/provider/contracts`)
- **Tabs:** Pending Assignment, Active, Completed
- **Table:** Contract Number, Business Name, Line Items, Status
- **Actions:** Assign Vehicles (Pending), View Details

#### 34. Vehicle Assignment (`/provider/contracts/[id]/assign`)
- **Left Panel:** Required Vehicles (from contract line items)
  - Table: Vehicle Type, Quantity Needed, Quantity Assigned
- **Right Panel:** Available Fleet (Filterable by Type)
  - Table: Plate Number, Type, Model, Status
- **Interaction:** Drag & Drop or Dropdown select
- **Validation:** Cannot assign vehicle with `currentContractId !== null`
- **Action:** Submit → Update `assignments.json`, Set `vehicle.currentContractId`

#### 35. Reassign Vehicle (`/provider/contracts/[id]/reassign/[assignmentId]`)
- **Current:** Show current vehicle details
- **Select New:** Dropdown of available vehicles (same type)
- **Action:** Update assignment, Free old vehicle, Lock new vehicle

#### 36. Delivery Session List (`/provider/delivery`)
- List of pending deliveries
- **Table:** Contract, Vehicle, Business Contact, Scheduled Date, Status
- **Actions:** Start Delivery

#### 37. Start Delivery (`/provider/delivery/[sessionId]/start`)
- **Step 1:** Generate OTP
  - Display: 6-digit code in large font
  - "Send OTP to Business Contact" button (Mock SMS)
- **Action:** "Proceed to Verification"

#### 38. OTP Verification (`/provider/delivery/[sessionId]/verify`)
- **Input:** 6-digit OTP (6 separate input boxes)
- **Validation:**
  - Match against `deliverySessions[].otp.code`
  - Check `expiresAt` (5 min)
  - Track `attempts` (Max 3)
- **Lockout:** If 3 failed attempts, disable for 30 min
- **On Success:** Proceed to Evidence Upload

#### 39. Handover Evidence Upload (`/provider/delivery/[sessionId]/evidence`)
- **Uploads:** 5 vehicle photos (Front, Back, Left, Right, Interior)
- **Fields:** Odometer Reading (Number), Fuel Level (Dropdown: Empty, Quarter, Half, Three-Quarters, Full)
- **Textarea:** Notes (Optional damage notes)
- **Action:** Submit
  - Update `deliverySessions[].handoverEvidence`
  - Update `assignments[].status` to `ACTIVE`
  - Update `contracts[].status` to `ACTIVE` (if first vehicle)
  - Set `vehicle.currentContractId`

#### 40. Provider Wallet (`/provider/wallet`)
- **Summary Cards:**
  - Total Earnings (Lifetime)
  - Available Balance (Withdrawable)
  - Pending Settlement (In Active Contracts)
- **Transaction History:** Same as Business
- **Actions:** "Request Withdrawal" button

#### 41. Settlement History (`/provider/wallet/settlements`)
- **Table:** Period (Month), Gross Amount, Commission, Penalties, Net Payout, Status
- **Details Modal:** Breakdown per contract

#### 42. Provider Profile (`/provider/profile`)
- **Tabs:** Details, Trust Score, Documents
- **Trust Score Tab:**
  - Gauge (0-100) with current score
  - Breakdown: Completion Rate (30%), On-time Delivery (25%), etc.
- **Tier Display:** Badge with benefits (Bronze, Silver, Gold, Platinum)

---

### **ADMIN PORTAL (3)**

#### 43. Admin Dashboard (`/admin/dashboard`)
- **Metrics:** Total Businesses, Providers, Active Contracts, Platform Revenue
- **Pending Verifications:** Count with link

#### 44. KYC/KYB Verification Queue (`/admin/verification`)
- **Tabs:** Pending Businesses, Pending Providers
- **Table:** Name, Type, Submitted Date, Documents
- **Actions:** View Details, Approve, Reject, Request More Info

#### 45. Platform Wallet (`/admin/wallets`)
- **Summary:**
  - Total Commission Earned
  - Escrow Pool (Total locked funds across all businesses)
- **Commission by Tier (Pie Chart):**
  - Bronze: ETB X
  - Silver: ETB Y
  - Gold: ETB Z
  - Platinum: ETB W
- **Transaction History:** Platform wallet transactions

---

## 🧠 CRITICAL BUSINESS LOGIC

### 1. Marketplace Filtering & Sorting
```typescript
// Filter Logic
const filteredRfqs = rfqs.filter(rfq => {
  // Vehicle Type Filter
  if (filters.vehicleTypes.length > 0) {
    const hasMatchingType = rfq.lineItems.some(item => 
      filters.vehicleTypes.includes(item.vehicleTypeCode)
    );
    if (!hasMatchingType) return false;
  }
  
  // Duration Filter
  if (filters.duration !== 'ALL') {
    const durationDays = daysBetween(rfq.startDate, rfq.endDate);
    if (filters.duration === 'SHORT' && durationDays >= 7) return false;
    if (filters.duration === 'LONG' && durationDays < 30) return false;
  }
  
  // Location Filter
  if (filters.location && rfq.location !== filters.location) return false;
  
  // Search Filter
  if (filters.search && !rfq.title.toLowerCase().includes(filters.search.toLowerCase())) {
    return false;
  }
  
  return true;
});

// Sort Logic
const sortedRfqs = [...filteredRfqs].sort((a, b) => {
  if (sort === 'NEWEST') return new Date(b.publishedAt) - new Date(a.publishedAt);
  if (sort === 'OLDEST') return new Date(a.publishedAt) - new Date(b.publishedAt);
  if (sort === 'MOST_BIDS') return b.lineItems.reduce((sum, item) => sum + item.bidCount, 0) - a.lineItems.reduce((sum, item) => sum + item.bidCount, 0);
  if (sort === 'LEAST_BIDS') return a.lineItems.reduce((sum, item) => sum + item.bidCount, 0) - b.lineItems.reduce((sum, item) => sum + item.bidCount, 0);
});
```

### 2. Split Award Logic
```typescript
// Data Structure
const awards = [
  {
    lineItemId: "line-1",
    bidId: "bid-1",
    quantityAwarded: 3 // Provider A gets 3 out of 5
  },
  {
    lineItemId: "line-1", // Same line item
    bidId: "bid-2",
    quantityAwarded: 2 // Provider B gets 2 out of 5
  }
];

// Validation
const totalAwarded = awards
  .filter(a => a.lineItemId === "line-1")
  .reduce((sum, a) => sum + a.quantityAwarded, 0);

if (totalAwarded > lineItem.quantityRequired) {
  throw new Error("Cannot award more than required quantity");
}
```

### 3. Wallet Balance Check at Award
```typescript
// Calculate Total Escrow
const totalEscrow = awards.reduce((sum, award) => {
  const bid = bids.find(b => b.id === award.bidId);
  const lineItemBid = bid.lineItemBids.find(lib => lib.lineItemId === award.lineItemId);
  return sum + (award.quantityAwarded * lineItemBid.unitPrice * 1.0); // 1.0 = escrow multiplier
}, 0);

// Check Balance
const wallet = wallets.find(w => w.ownerId === businessId);
if (wallet.availableBalance < totalEscrow) {
  // Calculate Max Affordable
  const maxAffordable = Math.floor(wallet.availableBalance / (unitPrice * 1.0));
  
  // Show Modal with Options
  return {
    error: "INSUFFICIENT_FUNDS",
    required: totalEscrow,
    available: wallet.availableBalance,
    shortfall: totalEscrow - wallet.availableBalance,
    maxAffordableQuantity: maxAffordable
  };
}

// Lock Escrow
wallet.lockedBalance += totalEscrow;
wallet.availableBalance -= totalEscrow;
wallet.transactions.push({
  type: "ESCROW_LOCK",
  amount: -totalEscrow,
  reference: `Contract ${contractNumber}`,
  createdAt: new Date().toISOString()
});
```

### 4. Blind Bidding
```typescript
// Before Award (Bid Review Page)
const displayBid = {
  ...bid,
  providerName: bid.providerHash, // "Provider •••4411"
  providerId: null // Hidden
};

// After Award (Contract Created)
const contract = {
  ...contractData,
  lineItems: lineItems.map(li => ({
    ...li,
    providerId: bid.providerId, // NOW REVEALED
    providerName: providers.find(p => p.id === bid.providerId).name
  }))
};
```

### 5. Vehicle Assignment Validation
```typescript
// Check if vehicle is available
const vehicle = vehicles.find(v => v.id === vehicleId);

if (vehicle.status !== 'ACTIVE') {
  throw new Error("Vehicle is not active");
}

if (vehicle.currentContractId !== null) {
  throw new Error("Vehicle is already assigned to another contract");
}

// Check insurance validity
const insuranceEndDate = new Date(vehicle.insurance.coverageEndDate);
const contractEndDate = new Date(contract.endDate);

if (insuranceEndDate < contractEndDate) {
  throw new Error("Vehicle insurance expires before contract end date");
}

// Assign
vehicle.currentContractId = contractId;
assignments.push({
  id: generateId(),
  contractId,
  vehicleId,
  status: "PENDING_DELIVERY",
  assignedAt: new Date().toISOString()
});
```

### 6. OTP Flow
```typescript
// Generate OTP
const otp = {
  code: Math.floor(100000 + Math.random() * 900000).toString(), // 6 digits
  expiresAt: new Date(Date.now() + 5 * 60 * 1000).toISOString(), // 5 min
  isUsed: false,
  attempts: 0
};

deliverySession.otp = otp;

// Verify OTP
function verifyOTP(sessionId, inputCode) {
  const session = deliverySessions.find(s => s.id === sessionId);
  
  if (session.otp.isUsed) {
    throw new Error("OTP already used");
  }
  
  if (new Date() > new Date(session.otp.expiresAt)) {
    throw new Error("OTP expired");
  }
  
  session.otp.attempts++;
  
  if (session.otp.attempts >= 3) {
    session.status = "LOCKED";
    session.lockedUntil = new Date(Date.now() + 30 * 60 * 1000).toISOString();
    throw new Error("Too many failed attempts. Locked for 30 minutes.");
  }
  
  if (session.otp.code !== inputCode) {
    throw new Error("Incorrect OTP");
  }
  
  // Success
  session.otp.isUsed = true;
  session.status = "OTP_VERIFIED";
  return true;
}
```

### 7. Early Return Calculation
```typescript
function calculateEarlyReturn(assignment, returnDate) {
  const contract = contracts.find(c => c.id === assignment.contractId);
  const lineItem = contract.lineItems.find(li => li.id === assignment.contractLineItemId);
  
  const startDate = new Date(assignment.startDateActual);
  const endDate = new Date(contract.endDate);
  const returnDateObj = new Date(returnDate);
  
  const totalDays = daysBetween(startDate, endDate);
  const daysUsed = daysBetween(startDate, returnDateObj);
  const daysRemaining = totalDays - daysUsed;
  
  // Proration
  const totalAmount = lineItem.unitAmount;
  const proratedAmount = (totalAmount / totalDays) * daysUsed;
  
  // Penalty (25% for Standard tier)
  const business = businesses.find(b => b.id === contract.businessId);
  const penaltyRate = business.tier === 'STANDARD' ? 0.25 : 
                      business.tier === 'BUSINESS_PRO' ? 0.20 : 0.15;
  const penaltyAmount = (totalAmount - proratedAmount) * penaltyRate;
  
  // Refund
  const refundAmount = (totalAmount - proratedAmount) - penaltyAmount;
  
  return {
    totalDays,
    daysUsed,
    daysRemaining,
    proratedAmount,
    penaltyAmount,
    refundAmount
  };
}
```

---

## 🎯 IMPLEMENTATION CHECKLIST

### Phase 1: Setup & Core (Days 1-2)
- [ ] Initialize Next.js 14 with TypeScript
- [ ] Install Tailwind CSS + Shadcn/UI
- [ ] Create all JSON files in `src/data/`
- [ ] Build `MockService` helper (read/write JSON with 500ms delay)
- [ ] Create Layout components (Public, Dashboard)

### Phase 2: Authentication & Onboarding (Days 3-4)
- [ ] Login page with role detection
- [ ] Business onboarding (3 steps)
- [ ] Provider onboarding (3 steps)
- [ ] Auth context/store

### Phase 3: Business Core (Days 5-7)
- [ ] Business Dashboard
- [ ] RFQ Creation (2 steps)
- [ ] RFQ List & Detail
- [ ] **Bid Review Page (CRITICAL)**
- [ ] **Award Confirmation Modal (CRITICAL)**
- [ ] Contract List & Detail

### Phase 4: Provider Core (Days 8-10)
- [ ] Provider Dashboard
- [ ] **Marketplace with Filters & Sorting (CRITICAL)**
- [ ] RFQ Detail & Bidding
- [ ] Vehicle Registration
- [ ] Vehicle List & Detail
- [ ] My Bids page

### Phase 5: Fulfillment (Days 11-12)
- [ ] Vehicle Assignment (Drag & Drop)
- [ ] Delivery Session Flow
- [ ] OTP Generation & Verification
- [ ] Handover Evidence Upload

### Phase 6: Finance (Day 13)
- [ ] Business Wallet (3 cards + Transaction History)
- [ ] Provider Wallet
- [ ] Deposit Funds Modal
- [ ] Settlement History

### Phase 7: Additional Features (Day 14)
- [ ] Notification Center
- [ ] Saved RFQs
- [ ] Early Return Flow
- [ ] Profile Pages

### Phase 8: Admin (Day 15)
- [ ] Admin Dashboard
- [ ] Verification Queue
- [ ] Platform Wallet with Commission Breakdown

### Phase 9: Polish (Days 16-17)
- [ ] Responsive design (Mobile views)
- [ ] Loading states & Skeletons
- [ ] Error handling & Toast notifications
- [ ] Form validation (Zod schemas)
- [ ] Accessibility (ARIA labels, Focus states)

---

## 🚀 DELIVERABLES

1. **Fully Functional Prototype** where I can:
   - Register as Business → Create RFQ → Publish
   - Register as Provider → Browse Marketplace → Bid
   - Login as Business → Review Bids → Award (with wallet check)
   - Login as Provider → Assign Vehicles → Complete Delivery (OTP)
   - View Wallets with accurate balances

2. **Premium UI** adhering to Design System (No generic Bootstrap look)

3. **Clean Code** with TypeScript types, Reusable components

4. **README.md** with:
   - Setup instructions
   - Demo user credentials
   - Feature list

---

## 📌 FINAL NOTES

- **Simulate Delays:** Use `await new Promise(resolve => setTimeout(resolve, 500))` for all data operations to mimic API calls.
- **Optimistic Updates:** Update UI immediately, then persist to JSON.
- **Error Handling:** Use toast notifications (Sonner or React Hot Toast).
- **Validation:** Use Zod + React Hook Form for all forms.
- **Accessibility:** Ensure keyboard navigation works, Add ARIA labels.

**START BUILDING! 🚀**
