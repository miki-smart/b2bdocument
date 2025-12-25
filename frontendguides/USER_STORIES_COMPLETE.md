# Complete User Stories Reference
## Movello Frontend - React Implementation

**Version:** 1.0  
**Source:** [MOVELLO_COMPLETE_USER_STORIES.md](./MOVELLO_COMPLETE_USER_STORIES.md)  
**Total Stories:** 90+ across 11 Epics

---

## 📋 Epic Summary

| Epic | Name | Stories | Points | Priority |
|------|------|---------|--------|----------|
| E01 | Authentication & Onboarding | 8 | 45 | Highest |
| E02 | Business - RFQ Management | 15 | 95 | Highest |
| E03 | Business - Bidding & Award | 10 | 65 | Highest |
| E04 | Business - Wallet Management | 8 | 40 | High |
| E05 | Business - Contract Management | 7 | 50 | High |
| E06 | Provider - Fleet Management | 12 | 85 | Highest |
| E07 | Provider - Marketplace & Bidding | 10 | 70 | Highest |
| E08 | Provider - Delivery & OTP | 8 | 60 | Highest |
| E09 | Provider - Wallet & Settlements | 7 | 40 | High |
| E10 | Admin - Verification | 8 | 50 | High |
| E11 | Admin - Monitoring | 7 | 45 | Medium |

**Total:** 100 stories | 645 story points

---

## 🔐 Epic 1: Authentication & Onboarding

### MOV-101: User Registration with Role Selection ⭐
- **Priority:** Highest | **Points:** 5
- **Acceptance Criteria:**
  - Role selection (Business/Provider)
  - Dynamic form fields
  - TIN validation (10 digits, unique)
  - Email validation (unique)
  - Password validation (8+ chars, uppercase, number, special)
  - Email verification sent

### MOV-102: Business Onboarding Wizard ⭐
- **Priority:** Highest | **Points:** 13
- **3-Step Wizard:**
  1. Business Details (Name, Type, TIN)
  2. Contact & Address
  3. Document Upload (4 documents)

### MOV-103: Provider Onboarding Wizard ⭐
- **Priority:** Highest | **Points:** 13
- **3-Step Wizard:**
  1. Provider Type Selection
  2. Contact Information
  3. Document Upload (varies by type)

### MOV-104: Email Verification
- **Priority:** High | **Points:** 3

### MOV-105: Login
- **Priority:** Highest | **Points:** 5

### MOV-106: Password Reset
- **Priority:** High | **Points:** 5

### MOV-107: Session Management
- **Priority:** Medium | **Points:** 3

### MOV-108: Multi-Device Session Control
- **Priority:** Medium | **Points:** 3

---

## 🏢 Epic 2: Business - RFQ Management

### MOV-201: Create Multi-Line RFQ ⭐⭐⭐
- **Priority:** Highest | **Points:** 13
- **3-Step Wizard:**
  1. Basic Information (Title, Dates, Deadline)
  2. Line Items (Add/Remove, Max 50 vehicles)
  3. Review & Publish

### MOV-202: View and Filter RFQ List
- **Priority:** High | **Points:** 5

### MOV-203: View RFQ Details
- **Priority:** High | **Points:** 3

### MOV-204: Edit Draft RFQ
- **Priority:** High | **Points:** 5

### MOV-205: Delete Draft RFQ
- **Priority:** Medium | **Points:** 2

### MOV-206: Clone Existing RFQ
- **Priority:** Medium | **Points:** 3

### MOV-207: Cancel Published RFQ
- **Priority:** High | **Points:** 5

### MOV-208: RFQ Status Timeline
- **Priority:** Medium | **Points:** 3

### MOV-209: RFQ Notifications
- **Priority:** Medium | **Points:** 3

### MOV-210: RFQ Analytics
- **Priority:** Low | **Points:** 5

### MOV-211: Save RFQ as Template
- **Priority:** Low | **Points:** 3

### MOV-212: Bulk RFQ Creation
- **Priority:** Low | **Points:** 8

### MOV-213: RFQ Export
- **Priority:** Low | **Points:** 2

### MOV-214: RFQ Search
- **Priority:** Medium | **Points:** 3

### MOV-215: RFQ Reminders
- **Priority:** Low | **Points:** 3

---

## 💰 Epic 3: Business - Bidding & Award

### MOV-301: View Blind Bids ⭐⭐⭐
- **Priority:** Highest | **Points:** 13
- **Features:**
  - Grouped by line item
  - Provider hash display
  - Sorting (price, quantity, trust score)
  - Multi-select for award

### MOV-302: Award Bids with Wallet Validation ⭐⭐⭐
- **Priority:** Highest | **Points:** 13
- **Critical Features:**
  - Wallet balance check
  - Insufficient funds handling
  - Partial award option
  - Provider identity revealed after award

### MOV-303: Bid Comparison Tool
- **Priority:** High | **Points:** 8

### MOV-304: Award History
- **Priority:** Medium | **Points:** 3

### MOV-305: Award Partial Quantities
- **Priority:** High | **Points:** 8

### MOV-306: Split Awards (Multiple Providers)
- **Priority:** High | **Points:** 8

### MOV-307: Bid Analytics
- **Priority:** Low | **Points:** 5

### MOV-308: Auto-Award (Future)
- **Priority:** Low | **Points:** 8

### MOV-309: Bid Notifications
- **Priority:** Medium | **Points:** 3

### MOV-310: Award Confirmation Email
- **Priority:** Medium | **Points:** 2

---

## 💳 Epic 4: Business - Wallet Management

### MOV-401: View Wallet Balance
- **Priority:** High | **Points:** 3

### MOV-402: Deposit Funds
- **Priority:** High | **Points:** 8
- **Payment Methods:** Chapa, Telebirr

### MOV-403: View Transaction History
- **Priority:** High | **Points:** 5

### MOV-404: Transaction Filters
- **Priority:** Medium | **Points:** 3

### MOV-405: Transaction Export
- **Priority:** Low | **Points:** 3

### MOV-406: Wallet Notifications
- **Priority:** Medium | **Points:** 3

### MOV-407: Payment Method Management
- **Priority:** Low | **Points:** 5

### MOV-408: Wallet Analytics
- **Priority:** Low | **Points:** 5

---

## 📄 Epic 5: Business - Contract Management

### MOV-501: View Contract List
- **Priority:** High | **Points:** 5

### MOV-502: View Contract Details
- **Priority:** High | **Points:** 5

### MOV-503: Request Early Return
- **Priority:** High | **Points:** 8
- **Features:**
  - Penalty calculation
  - Notice period validation
  - Refund amount display

### MOV-504: View Delivery Evidence
- **Priority:** Medium | **Points:** 3

### MOV-505: Download Contract PDF
- **Priority:** Medium | **Points:** 3

### MOV-506: Contract Notifications
- **Priority:** Medium | **Points:** 3

### MOV-507: Contract Analytics
- **Priority:** Low | **Points:** 5

---

## 🚗 Epic 6: Provider - Fleet Management

### MOV-601: Register Vehicle ⭐⭐⭐
- **Priority:** Highest | **Points:** 13
- **3-Step Wizard:**
  1. Vehicle Information
  2. Photo Upload (5 photos)
  3. Insurance Information

### MOV-602: View Vehicle List
- **Priority:** High | **Points:** 5

### MOV-603: Edit Vehicle Information
- **Priority:** High | **Points:** 5

### MOV-604: Upload Vehicle Photos
- **Priority:** High | **Points:** 5

### MOV-605: Add/Update Insurance
- **Priority:** High | **Points:** 8

### MOV-606: Mark Vehicle as Maintenance
- **Priority:** Medium | **Points:** 3

### MOV-607: Delete Vehicle
- **Priority:** Medium | **Points:** 3

### MOV-608: Vehicle Analytics
- **Priority:** Low | **Points:** 5

### MOV-609: Bulk Vehicle Upload
- **Priority:** Low | **Points:** 8

### MOV-610: Vehicle History
- **Priority:** Medium | **Points:** 3

### MOV-611: Insurance Expiry Alerts
- **Priority:** Medium | **Points:** 5

### MOV-612: Vehicle Status Dashboard
- **Priority:** Medium | **Points:** 5

---

## 🛒 Epic 7: Provider - Marketplace & Bidding

### MOV-701: Browse Marketplace RFQs ⭐⭐⭐
- **Priority:** Highest | **Points:** 13
- **Features:**
  - Filters (Vehicle Type, Duration, Location)
  - Search by title
  - Sort options
  - RFQ cards with bid counts

### MOV-702: Submit Bid ⭐⭐⭐
- **Priority:** Highest | **Points:** 13
- **Features:**
  - Per line item bidding
  - Price validation (market range)
  - Vehicle availability check
  - Quantity validation

### MOV-703: View My Bids
- **Priority:** High | **Points:** 5

### MOV-704: Withdraw Bid
- **Priority:** High | **Points:** 3

### MOV-705: Bid History
- **Priority:** Medium | **Points:** 3

### MOV-706: Save RFQ (Bookmark)
- **Priority:** Low | **Points:** 3

### MOV-707: Bid Analytics
- **Priority:** Low | **Points:** 5

### MOV-708: RFQ Notifications
- **Priority:** Medium | **Points:** 3

### MOV-709: Bid Templates
- **Priority:** Low | **Points:** 5

### MOV-710: Auto-Bid (Future)
- **Priority:** Low | **Points:** 8

---

## 📦 Epic 8: Provider - Delivery & OTP

### MOV-801: Assign Vehicles to Contract ⭐⭐⭐
- **Priority:** Highest | **Points:** 13
- **Features:**
  - Select vehicles per line item
  - Quantity validation
  - Vehicle availability check

### MOV-802: Generate OTP ⭐⭐⭐
- **Priority:** Highest | **Points:** 8
- **Features:**
  - OTP generation
  - SMS to business
  - OTP display for provider

### MOV-803: Verify OTP ⭐⭐⭐
- **Priority:** Highest | **Points:** 8
- **Features:**
  - 6-digit OTP input
  - 3 attempts limit
  - Expiry handling

### MOV-804: Upload Handover Evidence ⭐⭐⭐
- **Priority:** Highest | **Points:** 13
- **Features:**
  - 5 photos (front, back, left, right, interior)
  - Odometer reading
  - Fuel level
  - Notes

### MOV-805: View Delivery Sessions
- **Priority:** Medium | **Points:** 3

### MOV-806: Delivery History
- **Priority:** Medium | **Points:** 3

### MOV-807: Delivery Notifications
- **Priority:** Medium | **Points:** 3

### MOV-808: Delivery Analytics
- **Priority:** Low | **Points:** 5

---

## 💰 Epic 9: Provider - Wallet & Settlements

### MOV-901: View Wallet Balance
- **Priority:** High | **Points:** 3

### MOV-902: View Settlement History
- **Priority:** High | **Points:** 5

### MOV-903: View Trust Score
- **Priority:** High | **Points:** 5
- **Features:**
  - Circular gauge display
  - Score breakdown
  - Historical chart

### MOV-904: View Tier Information
- **Priority:** Medium | **Points:** 3

### MOV-905: Settlement Details
- **Priority:** Medium | **Points:** 3

### MOV-906: Withdrawal Request
- **Priority:** Medium | **Points:** 5

### MOV-907: Wallet Analytics
- **Priority:** Low | **Points:** 5

---

## ✅ Epic 10: Admin - Verification

### MOV-1001: Review Business KYB ⭐⭐
- **Priority:** Highest | **Points:** 13

### MOV-1002: Review Provider KYC ⭐⭐
- **Priority:** Highest | **Points:** 13

### MOV-1003: Approve Verification
- **Priority:** High | **Points:** 5

### MOV-1004: Reject Verification
- **Priority:** High | **Points:** 5

### MOV-1005: Request Additional Documents
- **Priority:** Medium | **Points:** 5

### MOV-1006: Verification Queue
- **Priority:** High | **Points:** 5

### MOV-1007: Verification History
- **Priority:** Medium | **Points:** 3

### MOV-1008: Bulk Verification
- **Priority:** Low | **Points:** 8

---

## 📊 Epic 11: Admin - Monitoring

### MOV-1101: View Transaction List
- **Priority:** High | **Points:** 5

### MOV-1102: View User List
- **Priority:** High | **Points:** 5

### MOV-1103: Suspend User
- **Priority:** High | **Points:** 3

### MOV-1104: View System Analytics
- **Priority:** Medium | **Points:** 8

### MOV-1105: Export Reports
- **Priority:** Medium | **Points:** 5

### MOV-1106: System Settings
- **Priority:** Medium | **Points:** 8

### MOV-1107: Audit Log
- **Priority:** Low | **Points:** 5

---

## 🎯 Priority Legend

- ⭐⭐⭐ **Highest Priority** - Critical for MVP
- ⭐⭐ **High Priority** - Important for MVP
- ⭐ **Medium Priority** - Nice to have
- No star - **Low Priority** - Future enhancement

---

## 📝 Implementation Notes

1. **All stories** have detailed acceptance criteria in source document
2. **UI/UX tasks** are specified for each story
3. **Frontend/Backend tasks** are separated
4. **Story points** indicate complexity (1-13)
5. **Epic dependencies** should be considered

---

**END OF USER STORIES REFERENCE**

*For detailed acceptance criteria, see [MOVELLO_COMPLETE_USER_STORIES.md](./MOVELLO_COMPLETE_USER_STORIES.md)*

