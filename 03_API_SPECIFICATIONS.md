# Movello MVP - API Specifications

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**API Style:** RESTful  
**Base URL:** `https://api.movello.et/api/v1`  
**Authentication:** Bearer JWT (OAuth2/OIDC via Keycloak)

---

## 📋 Table of Contents

1. [API Overview](#api-overview)
2. [Authentication](#authentication)
3. [Identity & Compliance APIs](#identity--compliance-apis)
4. [Marketplace APIs](#marketplace-apis)
5. [Contracts APIs](#contracts-apis)
6. [Finance APIs](#finance-apis)
7. [Delivery APIs](#delivery-apis)
8. [Error Handling](#error-handling)
9. [Rate Limiting](#rate-limiting)

---

## 🌐 API Overview

### Base URLs

| Environment | Base URL |
|-------------|----------|
| Development | `http://localhost:5000/api/v1` |
| Staging | `https://api-staging.movello.et/api/v1` |
| Production | `https://api.movello.et/api/v1` |

### Common Headers

```http
Authorization: Bearer {jwt_token}
Content-Type: application/json
Accept: application/json
X-Request-ID: {uuid} (optional, for tracing)
```

### Standard Response Format

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "timestamp": "2025-11-26T16:00:00Z",
    "requestId": "uuid"
  }
}
```

### Error Response Format

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input data",
    "details": [
      {
        "field": "email",
        "message": "Email is required"
      }
    ]
  },
  "meta": {
    "timestamp": "2025-11-26T16:00:00Z",
    "requestId": "uuid"
  }
}
```

---

## 🔐 Authentication

### Login Flow (via BFF)

```http
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "password123"
}

Response 200:
{
  "success": true,
  "data": {
    "accessToken": "eyJhbGc...",
    "refreshToken": "stored_in_httpOnly_cookie",
    "expiresIn": 3600,
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "roles": ["business-admin"]
    }
  }
}
```

### Token Refresh

```http
POST /auth/refresh
Cookie: refreshToken={token}

Response 200:
{
  "success": true,
  "data": {
    "accessToken": "eyJhbGc...",
    "expiresIn": 3600
  }
}
```

### Logout

```http
POST /auth/logout
Authorization: Bearer {token}

Response 204: No Content
```

---

## 👤 Identity & Compliance APIs

### Business Management

#### Register Business

```http
POST /businesses
Authorization: Bearer {token}
Content-Type: application/json

{
  "businessName": "Acme Corporation",
  "businessType": "PLC",
  "tinNumber": "1234567890",
  "registrationNumber": "REG-123",
  "contactPerson": {
    "fullName": "John Doe",
    "email": "john@acme.com",
    "phone": "+251911234567"
  },
  "address": {
    "city": "Addis Ababa",
    "subcity": "Bole",
    "woreda": "03",
    "houseNumber": "123"
  }
}

Response 201:
{
  "success": true,
  "data": {
    "id": "business-uuid",
    "businessName": "Acme Corporation",
    "status": "PENDING_KYB",
    "createdAt": "2025-11-26T16:00:00Z"
  }
}
```

#### Get Business Profile

```http
GET /businesses/{id}
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "data": {
    "id": "uuid",
    "businessName": "Acme Corporation",
    "businessType": "PLC",
    "tinNumber": "1234567890",
    "status": "ACTIVE",
    "tier": "BUSINESS_PRO",
    "wallet": {
      "balance": 150000.00,
      "lockedBalance": 50000.00
    },
    "createdAt": "2025-11-26T16:00:00Z"
  }
}
```

#### Upload Business Document

```http
POST /businesses/{id}/documents
Authorization: Bearer {token}
Content-Type: multipart/form-data

documentTypeId: uuid
file: [binary]
issuedAt: 2025-01-01
expiresAt: 2026-01-01

Response 201:
{
  "success": true,
  "data": {
    "id": "document-uuid",
    "documentType": "BUSINESS_LICENSE",
    "fileUrl": "https://storage.movello.et/docs/...",
    "status": "PENDING_VERIFICATION"
  }
}
```

---

### Provider Management

#### Register Provider

```http
POST /providers
Authorization: Bearer {token}

{
  "providerType": "INDIVIDUAL",
  "name": "Ahmed Mohammed",
  "tinNumber": "9876543210",
  "contactInfo": {
    "email": "ahmed@example.com",
    "phone": "+251922345678"
  }
}

Response 201:
{
  "success": true,
  "data": {
    "id": "provider-uuid",
    "name": "Ahmed Mohammed",
    "status": "PENDING_VERIFICATION",
    "tier": "BRONZE",
    "trustScore": 0
  }
}
```

#### Get Provider Profile

```http
GET /providers/{id}
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "data": {
    "id": "uuid",
    "name": "Ahmed Mohammed",
    "providerType": "INDIVIDUAL",
    "status": "ACTIVE",
    "tier": "GOLD",
    "trustScore": 78,
    "fleetSize": 5,
    "activeContracts": 3,
    "totalEarnings": 250000.00
  }
}
```

---

### Vehicle Management

#### Register Vehicle

```http
POST /vehicles
Authorization: Bearer {token}

{
  "providerId": "provider-uuid",
  "plateNumber": "AA-12345",
  "vehicleTypeCode": "EV_SEDAN",
  "engineTypeCode": "EV",
  "seatCount": 5,
  "brand": "BYD",
  "model": "Seagull",
  "modelYear": 2024,
  "tags": ["luxury", "guest"],
  "insurance": {
    "insuranceType": "COMPREHENSIVE",
    "companyName": "Nyala Insurance",
    "policyNumber": "POL-123456",
    "insuredAmount": 500000.00,
    "coverageStartDate": "2025-01-01",
    "coverageEndDate": "2026-01-01",
    "certificateFile": "[base64_or_url]"
  }
}

Response 201:
{
  "success": true,
  "data": {
    "id": "vehicle-uuid",
    "plateNumber": "AA-12345",
    "status": "UNDER_REVIEW",
    "insuranceStatus": "PENDING_VERIFICATION"
  }
}
```

#### Upload Vehicle Photos

```http
POST /vehicles/{id}/photos
Authorization: Bearer {token}
Content-Type: multipart/form-data

frontPhoto: [binary]
backPhoto: [binary]
leftPhoto: [binary]
rightPhoto: [binary]
interiorPhoto: [binary]

Response 200:
{
  "success": true,
  "data": {
    "frontImageUrl": "https://...",
    "backImageUrl": "https://...",
    "leftImageUrl": "https://...",
    "rightImageUrl": "https://...",
    "interiorImageUrl": "https://..."
  }
}
```

---

## 🏪 Marketplace APIs

### RFQ Management

#### Create RFQ

```http
POST /rfqs
Authorization: Bearer {token}
Roles: business-admin, business-user

{
  "title": "Monthly Vehicle Rental - December 2025",
  "description": "Need vehicles for staff transportation",
  "startDate": "2025-12-01",
  "endDate": "2025-12-31",
  "bidDeadline": "2025-11-28T23:59:59Z",
  "lineItems": [
    {
      "vehicleTypeCode": "EV_SEDAN",
      "engineTypeCode": "EV",
      "quantityRequired": 5,
      "withDriver": true,
      "preferredTags": ["luxury", "guest"]
    },
    {
      "vehicleTypeCode": "MINIBUS_12",
      "quantityRequired": 2,
      "withDriver": true
    }
  ]
}

Response 201:
{
  "success": true,
  "data": {
    "id": "rfq-uuid",
    "rfqNumber": "RFQ-2025-001",
    "status": "DRAFT",
    "lineItems": [
      {
        "id": "line-item-uuid-1",
        "vehicleTypeCode": "EV_SEDAN",
        "quantityRequired": 5
      },
      {
        "id": "line-item-uuid-2",
        "vehicleTypeCode": "MINIBUS_12",
        "quantityRequired": 2
      }
    ]
  }
}
```

#### Publish RFQ

```http
POST /rfqs/{id}/publish
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "data": {
    "id": "rfq-uuid",
    "status": "PUBLISHED",
    "publishedAt": "2025-11-26T16:00:00Z"
  }
}
```

#### Get Open RFQs (Provider View)

```http
GET /rfqs/open
Authorization: Bearer {token}
Roles: provider-admin

Query Parameters:
- vehicleTypeCode (optional)
- minQuantity (optional)
- page=1
- pageSize=20

Response 200:
{
  "success": true,
  "data": {
    "rfqs": [
      {
        "id": "uuid",
        "rfqNumber": "RFQ-2025-001",
        "title": "Monthly Vehicle Rental",
        "bidDeadline": "2025-11-28T23:59:59Z",
        "lineItems": [
          {
            "id": "uuid",
            "vehicleTypeCode": "EV_SEDAN",
            "quantityRequired": 5,
            "currentBidCount": 3
          }
        ]
      }
    ],
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "totalPages": 5,
      "totalItems": 100
    }
  }
}
```

---

### Bidding

#### Submit Bid

```http
POST /rfqs/{rfqId}/bids
Authorization: Bearer {token}
Roles: provider-admin

{
  "lineItemBids": [
    {
      "lineItemId": "line-item-uuid-1",
      "quantityOffered": 5,
      "unitPrice": 3500.00,
      "notes": "Brand new BYD Seagull EVs"
    },
    {
      "lineItemId": "line-item-uuid-2",
      "quantityOffered": 1,
      "unitPrice": 8000.00
    }
  ]
}

Response 201:
{
  "success": true,
  "data": {
    "id": "bid-uuid",
    "rfqId": "rfq-uuid",
    "status": "SUBMITTED",
    "submittedAt": "2025-11-26T16:00:00Z",
    "lineItemBids": [
      {
        "lineItemId": "uuid",
        "quantityOffered": 5,
        "unitPrice": 3500.00
      }
    ]
  }
}
```

#### Get Bids for RFQ (Business View - Blind)

```http
GET /rfqs/{id}/bids
Authorization: Bearer {token}
Roles: business-admin

Response 200:
{
  "success": true,
  "data": {
    "lineItems": [
      {
        "lineItemId": "uuid",
        "vehicleTypeCode": "EV_SEDAN",
        "quantityRequired": 5,
        "bids": [
          {
            "bidId": "bid-uuid-1",
            "providerHash": "Provider •••4411", // Anonymized
            "quantityOffered": 5,
            "unitPrice": 3500.00,
            "totalPrice": 17500.00
          },
          {
            "bidId": "bid-uuid-2",
            "providerHash": "Provider •••7823",
            "quantityOffered": 3,
            "unitPrice": 3200.00,
            "totalPrice": 9600.00
          }
        ]
      }
    ]
  }
}
```

---

### Award Management

#### Award Bid

```http
POST /rfqs/{rfqId}/awards
Authorization: Bearer {token}
Roles: business-admin

{
  "awards": [
    {
      "lineItemId": "line-item-uuid-1",
      "bidId": "bid-uuid-1",
      "quantityAwarded": 5
    },
    {
      "lineItemId": "line-item-uuid-2",
      "bidId": "bid-uuid-3",
      "quantityAwarded": 2
    }
  ]
}

Response 201:
{
  "success": true,
  "data": {
    "awards": [
      {
        "id": "award-uuid-1",
        "lineItemId": "uuid",
        "providerId": "uuid", // Now revealed
        "providerName": "Ahmed Mohammed",
        "quantityAwarded": 5,
        "unitPrice": 3500.00
      }
    ],
    "contractId": "contract-uuid" // Auto-created
  }
}
```

---

## 📜 Contracts APIs

### Contract Management

#### Get Contract

```http
GET /contracts/{id}
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "data": {
    "id": "uuid",
    "contractNumber": "CNT-2025-001",
    "rfqId": "uuid",
    "business": {
      "id": "uuid",
      "name": "Acme Corporation",
      "tier": "BUSINESS_PRO"
    },
    "status": "ACTIVE",
    "startDate": "2025-12-01",
    "endDate": "2025-12-31",
    "lineItems": [
      {
        "id": "uuid",
        "provider": {
          "id": "uuid",
          "name": "Ahmed Mohammed",
          "tier": "GOLD"
        },
        "vehicleTypeCode": "EV_SEDAN",
        "quantityAwarded": 5,
        "quantityActive": 5,
        "unitAmount": 3500.00,
        "totalAmount": 17500.00,
        "commissionRate": 0.07
      }
    ],
    "totalValue": 25500.00,
    "escrowAmount": 25500.00,
    "escrowStatus": "LOCKED"
  }
}
```

#### Get Contracts (Business View)

```http
GET /contracts
Authorization: Bearer {token}
Roles: business-admin

Query Parameters:
- status (optional): ACTIVE, COMPLETED, TERMINATED
- page=1
- pageSize=20

Response 200:
{
  "success": true,
  "data": {
    "contracts": [
      {
        "id": "uuid",
        "contractNumber": "CNT-2025-001",
        "status": "ACTIVE",
        "startDate": "2025-12-01",
        "totalValue": 25500.00,
        "activeVehicles": 7
      }
    ],
    "pagination": { ... }
  }
}
```

---

### Vehicle Assignment

#### Assign Vehicle to Contract

```http
POST /contracts/{contractId}/line-items/{lineItemId}/vehicles
Authorization: Bearer {token}
Roles: provider-admin

{
  "vehicleId": "vehicle-uuid"
}

Response 201:
{
  "success": true,
  "data": {
    "assignmentId": "assignment-uuid",
    "vehicleId": "uuid",
    "plateNumber": "AA-12345",
    "status": "PENDING_DELIVERY"
  }
}
```

---

### Early Returns

#### Request Early Return

```http
POST /contracts/vehicle-assignments/{assignmentId}/early-return
Authorization: Bearer {token}

{
  "returnReason": "CLIENT_REQUEST",
  "notes": "Vehicle no longer needed"
}

Response 200:
{
  "success": true,
  "data": {
    "assignmentId": "uuid",
    "status": "RETURN_REQUESTED",
    "prorationAmount": 15000.00,
    "refundAmount": 5000.00
  }
}
```

---

## 💰 Finance APIs

### Wallet Management

#### Get Wallet Balance

```http
GET /wallets/me
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "data": {
    "id": "wallet-uuid",
    "ownerType": "BUSINESS",
    "ownerId": "business-uuid",
    "balance": 150000.00,
    "lockedBalance": 50000.00,
    "availableBalance": 100000.00,
    "currency": "ETB"
  }
}
```

#### Deposit Funds

```http
POST /wallets/deposit
Authorization: Bearer {token}

{
  "amount": 50000.00,
  "paymentMethod": "CHAPA",
  "returnUrl": "https://app.movello.et/wallet/callback"
}

Response 201:
{
  "success": true,
  "data": {
    "paymentIntentId": "payment-uuid",
    "checkoutUrl": "https://checkout.chapa.co/...",
    "expiresAt": "2025-11-26T17:00:00Z"
  }
}
```

#### Get Transaction History

```http
GET /wallets/transactions
Authorization: Bearer {token}

Query Parameters:
- startDate (optional)
- endDate (optional)
- type (optional): DEPOSIT, ESCROW_LOCK, SETTLEMENT
- page=1
- pageSize=20

Response 200:
{
  "success": true,
  "data": {
    "transactions": [
      {
        "id": "uuid",
        "reference": "TXN-2025-001",
        "type": "ESCROW_LOCK",
        "amount": 25500.00,
        "direction": "DEBIT",
        "balance": 124500.00,
        "createdAt": "2025-11-26T16:00:00Z"
      }
    ],
    "pagination": { ... }
  }
}
```

---

### Settlement (Provider)

#### Get Settlement Cycles

```http
GET /settlements
Authorization: Bearer {token}
Roles: provider-admin

Response 200:
{
  "success": true,
  "data": {
    "cycles": [
      {
        "id": "uuid",
        "periodStart": "2025-11-01",
        "periodEnd": "2025-11-30",
        "totalGrossAmount": 105000.00,
        "totalCommissionAmount": 7350.00,
        "totalNetPayable": 97650.00,
        "status": "COMPLETED",
        "paidAt": "2025-12-01T10:00:00Z"
      }
    ]
  }
}
```

---

## 🚚 Delivery APIs

### OTP Management

#### Generate OTP

```http
POST /delivery/sessions/{sessionId}/otp
Authorization: Bearer {token}
Roles: provider-driver

Response 201:
{
  "success": true,
  "data": {
    "otpId": "otp-uuid",
    "channel": "SMS",
    "expiresAt": "2025-11-26T16:05:00Z",
    "message": "OTP sent to business contact"
  }
}
```

#### Verify OTP

```http
POST /delivery/sessions/{sessionId}/verify-otp
Authorization: Bearer {token}
Roles: business-user

{
  "otpCode": "392122"
}

Response 200:
{
  "success": true,
  "data": {
    "verified": true,
    "deliverySessionId": "uuid",
    "vehicleAssignmentId": "uuid",
    "status": "ACTIVE"
  }
}

Error 400:
{
  "success": false,
  "error": {
    "code": "INVALID_OTP",
    "message": "Invalid or expired OTP",
    "details": {
      "attemptsRemaining": 2
    }
  }
}
```

---

### Handover Evidence

#### Upload Handover Photos

```http
POST /delivery/sessions/{sessionId}/handover
Authorization: Bearer {token}
Content-Type: multipart/form-data

frontPhoto: [binary]
backPhoto: [binary]
leftPhoto: [binary]
rightPhoto: [binary]
interiorPhoto: [binary]
odometerReading: 15000
fuelLevel: FULL
notes: "Vehicle in excellent condition"

Response 201:
{
  "success": true,
  "data": {
    "handoverId": "uuid",
    "photos": {
      "front": "https://...",
      "back": "https://...",
      "left": "https://...",
      "right": "https://...",
      "interior": "https://..."
    },
    "odometerReading": 15000,
    "fuelLevel": "FULL"
  }
}
```

---

## ❌ Error Handling

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `VALIDATION_ERROR` | 400 | Invalid input data |
| `UNAUTHORIZED` | 401 | Missing or invalid token |
| `FORBIDDEN` | 403 | Insufficient permissions |
| `NOT_FOUND` | 404 | Resource not found |
| `CONFLICT` | 409 | Resource conflict (e.g., duplicate) |
| `BUSINESS_RULE_VIOLATION` | 422 | Business logic error |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `INTERNAL_SERVER_ERROR` | 500 | Server error |

### Example Error Responses

```json
// Validation Error
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Validation failed",
    "details": [
      {
        "field": "email",
        "message": "Email is required"
      },
      {
        "field": "quantityRequired",
        "message": "Must be greater than 0"
      }
    ]
  }
}

// Business Rule Violation
{
  "success": false,
  "error": {
    "code": "BUSINESS_RULE_VIOLATION",
    "message": "Cannot create RFQ: Insufficient wallet balance",
    "details": {
      "requiredBalance": 50000.00,
      "currentBalance": 30000.00
    }
  }
}
```

---

## ⏱️ Rate Limiting

### Limits

| Endpoint Pattern | Limit | Window |
|------------------|-------|--------|
| `/auth/*` | 10 requests | 1 minute |
| `/rfqs` (POST) | 20 requests | 1 hour |
| `/bids` (POST) | 50 requests | 1 hour |
| All other endpoints | 100 requests | 1 minute |

### Rate Limit Headers

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1732636800
```

### Rate Limit Exceeded Response

```json
{
  "success": false,
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests. Please try again later.",
    "details": {
      "retryAfter": 60
    }
  }
}
```

---

**Next Document:** [05_BUSINESS_LOGIC_FLOWS.md](./05_BUSINESS_LOGIC_FLOWS.md)
