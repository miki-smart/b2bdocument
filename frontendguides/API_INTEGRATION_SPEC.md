# API Integration Specification
## Movello Frontend - React Implementation

**Version:** 1.0  
**Base URL:** `http://localhost:5207/api`  
**API Version:** v1  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)

---

## 📋 Table of Contents

1. [API Client Setup](#api-client-setup)
2. [Authentication](#authentication)
3. [Request/Response Types](#requestresponse-types)
4. [Error Handling](#error-handling)
5. [Endpoint Reference](#endpoint-reference)
6. [Pagination](#pagination)
7. [Filtering & Search](#filtering--search)

---

## 🔧 API Client Setup

### Base API Client

**File:** `src/shared/lib/api-client.ts`

```typescript
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from 'axios';
import { useAuthStore } from '@/stores/auth-store';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:5207/api';

class ApiClient {
  private client: AxiosInstance;

  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor - Add auth token
    this.client.interceptors.request.use(
      (config) => {
        const token = useAuthStore.getState().accessToken;
        if (token) {
          config.headers.Authorization = `Bearer ${token}`;
        }
        return config;
      },
      (error) => Promise.reject(error)
    );

    // Response interceptor - Handle errors
    this.client.interceptors.response.use(
      (response) => response,
      async (error) => {
        const originalRequest = error.config;

        // Handle 401 - Unauthorized
        if (error.response?.status === 401 && !originalRequest._retry) {
          originalRequest._retry = true;
          try {
            await useAuthStore.getState().refreshToken();
            const token = useAuthStore.getState().accessToken;
            originalRequest.headers.Authorization = `Bearer ${token}`;
            return this.client(originalRequest);
          } catch (refreshError) {
            useAuthStore.getState().logout();
            window.location.href = '/login';
            return Promise.reject(refreshError);
          }
        }

        // Handle other errors
        return Promise.reject(error);
      }
    );
  }

  async get<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
    const response: AxiosResponse<T> = await this.client.get(url, config);
    return response.data;
  }

  async post<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    const response: AxiosResponse<T> = await this.client.post(url, data, config);
    return response.data;
  }

  async put<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    const response: AxiosResponse<T> = await this.client.put(url, data, config);
    return response.data;
  }

  async patch<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    const response: AxiosResponse<T> = await this.client.patch(url, data, config);
    return response.data;
  }

  async delete<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
    const response: AxiosResponse<T> = await this.client.delete(url, config);
    return response.data;
  }

  // File upload helper
  async uploadFile<T>(
    url: string,
    file: File,
    additionalData?: Record<string, any>
  ): Promise<T> {
    const formData = new FormData();
    formData.append('file', file);
    
    if (additionalData) {
      Object.entries(additionalData).forEach(([key, value]) => {
        formData.append(key, value);
      });
    }

    const response: AxiosResponse<T> = await this.client.post(url, formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    });
    return response.data;
  }
}

export const apiClient = new ApiClient();
```

---

## 🔐 Authentication

### Standard Response Format

```typescript
interface ApiResponse<T> {
  success: boolean;
  data: T;
  meta?: {
    timestamp: string;
    requestId: string;
  };
}

interface ApiError {
  success: false;
  error: {
    code: string;
    message: string;
    details?: Array<{
      field: string;
      message: string;
    }> | Record<string, any>;
  };
  meta: {
    timestamp: string;
    requestId: string;
  };
}
```

### Authentication Headers

All authenticated requests must include:
```
Authorization: Bearer {accessToken}
Content-Type: application/json
```

---

## 📝 Request/Response Types

### Common Types

**File:** `src/shared/types/api.ts`

```typescript
// Pagination
export interface PaginationParams {
  pageNumber?: number;
  pageSize?: number;
  sortBy?: string;
  sortDescending?: boolean;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    pageSize: number;
    totalPages: number;
    totalItems: number;
    hasNext: boolean;
    hasPrevious: boolean;
  };
}

// Master Data
export interface VehicleType {
  code: string;
  label: string;
  description?: string;
}

export interface BusinessTier {
  id: string;
  code: 'STANDARD' | 'BUSINESS_PRO' | 'ENTERPRISE' | 'GOV_NGO';
  name: string;
  description?: string;
  maxRFQsPerMonth?: number; // null = unlimited
  maxActiveContracts?: number;
  maxVehiclesPerRFQ?: number;
  colorCode?: string;
  displayOrder: number;
  isActive: boolean;
}

export interface ProviderTier {
  code: 'BRONZE' | 'SILVER' | 'GOLD' | 'PLATINUM';
  name: string;
  commissionRate: number;
}
```

### RFQ Types

```typescript
export interface RFQ {
  id: string;
  rfqNumber: string;
  businessId: string;
  title: string;
  description?: string;
  status: 'DRAFT' | 'PUBLISHED' | 'BIDDING' | 'PARTIALLY_AWARDED' | 'AWARDED' | 'COMPLETED' | 'CANCELLED';
  type: 'STANDARD' | 'URGENT' | 'LONG_TERM';
  submissionDeadline: string;
  awardedAt?: string;
  pickupCity?: string;
  dropoffCity?: string;
  isBlind: boolean;
  lineItems: RFQLineItem[];
  bidCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface RFQLineItem {
  id: string;
  rfqId: string;
  vehicleType: string;
  quantity: number;
  requiredFrom: string; // ISO date-time
  requiredTo: string; // ISO date-time
  specifications?: string;
  targetPricePerUnit?: number;
  seatingCapacity?: number; // Optional - for vehicles requiring specific seat count
}

export interface CreateRFQRequest {
  title: string;
  description?: string;
  type?: 'STANDARD' | 'URGENT' | 'LONG_TERM';
  submissionDeadline: string; // ISO date-time
  pickupCity?: string;
  dropoffCity?: string;
  isBlind?: boolean; // Default: true
  lineItems: {
    vehicleType: string;
    quantity: number;
    pickupLocation: string;
    dropoffLocation: string;
    pickupDate: string; // ISO date-time
    dropoffDate?: string; // ISO date-time (optional for open-ended)
    specialRequirements?: string;
    seatingCapacity?: number; // Optional
  }[];
}

export interface RFQFilters extends PaginationParams {
  status?: 'DRAFT' | 'PUBLISHED' | 'BIDDING' | 'PARTIALLY_AWARDED' | 'AWARDED' | 'COMPLETED' | 'CANCELLED';
  type?: 'STANDARD' | 'URGENT' | 'LONG_TERM';
  startDateFrom?: string;
  startDateTo?: string;
  vehicleType?: string;
  pickupCity?: string;
  dropoffCity?: string;
  search?: string;
}
```

### Bid Types

```typescript
export interface Bid {
  id: string;
  rfqId: string;
  providerId: string;
  providerHash: string; // For blind bidding
  status: 'BIDDING' | 'AWARDED' | 'LOST' | 'REJECTED' | 'WITHDRAWN';
  totalAmount: number;
  validUntil?: string; // ISO date-time
  notes?: string;
  submittedAt: string;
  items: BidItem[];
}

export interface BidLineItem {
  lineItemId: string;
  quantityOffered: number;
  unitPrice: number;
  totalPrice: number;
  notes?: string;
}

export interface SubmitBidRequest {
  lineItemBids: {
    lineItemId: string;
    quantityOffered: number;
    unitPrice: number;
    notes?: string;
  }[];
}

export interface AwardBidRequest {
  awards: {
    lineItemId: string;
    bidId: string;
    quantityAwarded: number;
  }[];
}
```

### Contract Types

```typescript
export interface Contract {
  id: string;
  contractNumber: string;
  rfqId: string;
  rfqBidAwardId?: string;
  businessId: string;
  providerId: string;
  status: 'PENDING_ESCROW' | 'PENDING_VEHICLE_ASSIGNMENT' | 'PENDING_DELIVERY' | 'ACTIVE' | 'ON_HOLD' | 'COMPLETED' | 'TERMINATED' | 'TIMEOUT_PENDING';
  startDate: string;
  endDate: string;
  totalContractValue: number;
  businessSignedAt?: string;
  providerSignedAt?: string;
  lineItems: ContractLineItem[];
  vehicleAssignments: ContractVehicleAssignment[];
  createdAt: string;
  updatedAt: string;
}

export interface ContractLineItem {
  id: string;
  providerId: string;
  providerName: string;
  vehicleTypeCode: string;
  quantityAwarded: number;
  quantityActive: number;
  unitAmount: number;
  totalAmount: number;
  commissionRate: number;
}
```

### Wallet Types

```typescript
export interface Wallet {
  id: string;
  ownerType: 'BUSINESS' | 'PROVIDER' | 'PLATFORM';
  ownerId: string;
  balance: number;
  lockedBalance: number;
  availableBalance: number;
  currency: string;
}

export interface Transaction {
  id: string;
  reference: string;
  type: 'DEPOSIT' | 'ESCROW_LOCK' | 'SETTLEMENT' | 'REFUND' | 'WITHDRAWAL';
  amount: number;
  direction: 'CREDIT' | 'DEBIT';
  balance: number;
  status: 'PENDING' | 'COMPLETED' | 'FAILED';
  createdAt: string;
}

export interface DepositRequest {
  amount: number;
  paymentMethod: 'CHAPA' | 'TELEBIRR';
  returnUrl?: string;
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

### Error Handler Utility

**File:** `src/shared/utils/error-handler.ts`

```typescript
import { AxiosError } from 'axios';
import { toast } from '@/shared/components/ui/toast';

export interface ApiErrorResponse {
  success: false;
  error: {
    code: string;
    message: string;
    details?: any;
  };
}

export const handleApiError = (error: unknown): void => {
  if (error instanceof AxiosError) {
    const apiError = error.response?.data as ApiErrorResponse;

    if (apiError?.error) {
      switch (apiError.error.code) {
        case 'VALIDATION_ERROR':
          if (Array.isArray(apiError.error.details)) {
            apiError.error.details.forEach((detail: any) => {
              toast.error(`${detail.field}: ${detail.message}`);
            });
          } else {
            toast.error(apiError.error.message);
          }
          break;

        case 'BUSINESS_RULE_VIOLATION':
          toast.error(apiError.error.message);
          if (apiError.error.details) {
            console.error('Business rule violation details:', apiError.error.details);
          }
          break;

        case 'INSUFFICIENT_FUNDS':
          // Special handling for insufficient funds
          const details = apiError.error.details;
          toast.error(
            `Insufficient funds. Required: ${details.required} ETB, Available: ${details.available} ETB`
          );
          break;

        default:
          toast.error(apiError.error.message || 'An error occurred');
      }
    } else {
      toast.error('An unexpected error occurred');
    }
  } else {
    toast.error('Network error. Please check your connection.');
  }
};
```

---

## 📡 Endpoint Reference

### Authentication Endpoints

| Endpoint | Method | Description | Request Body | Response |
|----------|--------|-------------|--------------|----------|
| `/web/login` | POST | Login user | `{ email, password, rememberMe? }` | `{ accessToken, user, expiresIn }` |
| `/web/logout` | POST | Logout user | - | `204 No Content` |
| `/web/me` | GET | Get current user | - | `User` |
| `/web/register` | POST | Register user | `RegisterRequest` | `201 Created` |
| `/web/forgot-password` | POST | Request password reset | `{ email }` | `200 OK` |
| `/web/change-password` | POST | Change password | `{ currentPassword, newPassword }` | `200 OK` |
| `/web/refresh` | POST | Refresh token | - | `{ accessToken, expiresIn }` |

### RFQ Endpoints

| Endpoint | Method | Description | Query Params | Request Body |
|----------|--------|-------------|--------------|--------------|
| `/api/rfqs` | GET | List RFQs | `PaginationParams, RFQFilters` | - |
| `/api/rfqs` | POST | Create RFQ | - | `CreateRFQRequest` |
| `/api/rfqs/{id}` | GET | Get RFQ details | - | - |
| `/api/rfqs/{id}` | PUT | Update RFQ | - | `UpdateRFQRequest` |
| `/api/rfqs/{id}` | DELETE | Delete RFQ | - | - |
| `/api/marketplace/rfqs/{id}/publish` | PUT | Publish RFQ | - | - |
| `/api/marketplace/rfqs/{id}/close` | PUT | Close RFQ | - | - |
| `/api/marketplace/rfqs` | GET | Get RFQs (role-based) | `PaginationParams, Filters` | - |
| `/api/marketplace/rfqs/{id}` | GET | Get RFQ details | - | - |
| `/api/marketplace/rfqs/{id}` | PUT | Update RFQ | - | `UpdateRFQRequest` |
| `/api/marketplace/rfqs/{id}` | DELETE | Delete RFQ | - | - |
| `/api/marketplace/rfqs/{id}/bids` | GET | Get bids for RFQ | - | - |
| `/api/marketplace/rfqs/{id}/award` | POST | Award bids | - | `AwardBidCommand` |

### Bid Endpoints

| Endpoint | Method | Description | Request Body |
|----------|--------|-------------|--------------|
| `/api/rfqs/{rfqId}/bids` | POST | Submit bid | `SubmitBidRequest` |
| `/api/marketplace/bids` | GET | Get provider's bids | `PaginationParams` | - |
| `/api/marketplace/bids` | POST | Submit bid | - | `SubmitBidCommand` |
| `/api/marketplace/bids/{id}` | GET | Get bid details | - | - |
| `/api/marketplace/bids/{id}` | DELETE | Withdraw bid | - | - |

### Contract Endpoints

| Endpoint | Method | Description | Query Params |
|----------|--------|-------------|--------------|
| `/api/contracts` | GET | List contracts | `PaginationParams, Filters` | - |
| `/api/contracts/{id}` | GET | Get contract details | - | - |
| `/api/contracts/{contractId}/line-items/{lineItemId}/assign-vehicle` | POST | Assign vehicle | - | `AssignVehicleRequest` |
| `/api/contracts/{contractId}/line-items/{lineItemId}/early-return` | POST | Request early return | - | `EarlyReturnRequest` |

### Wallet Endpoints

| Endpoint | Method | Description | Request Body |
|----------|--------|-------------|--------------|
| `/api/wallets/me` | GET | Get wallet balance | - |
| `/api/wallets/deposit` | POST | Initiate deposit | `DepositRequest` |
| `/api/wallets/transactions` | GET | Get transactions | `PaginationParams, Filters` |
| `/api/wallets/withdraw` | POST | Request withdrawal | `{ amount }` |

### Vehicle Endpoints

| Endpoint | Method | Description | Request Body |
|----------|--------|-------------|--------------|
| `/api/identity/vehicles` | GET | List vehicles | `PaginationParams, Filters` | - |
| `/api/identity/vehicles` | POST | Register vehicle | - | `CreateVehicleRequest` |
| `/api/identity/vehicles/{id}` | GET | Get vehicle details | - | - |
| `/api/identity/vehicles/{id}` | PUT | Update vehicle | - | `UpdateVehicleRequest` |
| `/api/identity/vehicles/{id}/documents` | POST | Upload documents | - | `FormData` |
| `/api/identity/vehicles/{id}/insurance` | POST | Add insurance | - | `InsuranceRequest` |
| `/api/identity/vehicles/provider/{providerId}` | GET | Get provider's vehicles | `PaginationParams` | - |

### Delivery Endpoints

| Endpoint | Method | Description | Request Body |
|----------|--------|-------------|--------------|
| `/api/delivery/sessions/{sessionId}/otp` | POST | Generate OTP | - | - |
| `/api/delivery/sessions/{sessionId}/verify-otp` | POST | Verify OTP | - | `{ otpCode }` |
| `/api/delivery/sessions/{sessionId}/handover` | POST | Upload handover evidence | - | `FormData` |
| `/api/document-types` | GET | Get document types | `PaginationParams` | - |
| `/api/document-types` | POST | Create document type (Admin) | - | `CreateDocumentTypeCommand` |
| `/api/kyc-requirements` | GET | Get KYC requirements | `PaginationParams, entityType` | - |
| `/api/kyc-requirements` | POST | Create KYC requirement (Admin) | - | `CreateKycRequirementCommand` |
| `/api/business-tiers` | GET | Get business tiers | `PaginationParams` | - |
| `/api/business-tiers` | POST | Create business tier (Admin) | - | `CreateBusinessTierCommand` |
| `/api/provider-tiers` | GET | Get provider tiers | `PaginationParams` | - |
| `/api/provider-tiers` | POST | Create provider tier (Admin) | - | `CreateProviderTierCommand` |
| `/api/commission-strategies/versions` | GET | Get commission strategies | `PaginationParams` | - |
| `/api/admin/verifications/businesses` | GET | List businesses for verification | `PaginationParams, Filters` | - |
| `/api/admin/verifications/businesses/{id}` | GET | Get business verification details | - | - |
| `/api/admin/verifications/businesses/{id}/status` | PUT | Update business verification status | - | `UpdateStatusCommand` |
| `/api/admin/verifications/providers` | GET | List providers for verification | `PaginationParams, Filters` | - |
| `/api/admin/verifications/providers/{id}` | GET | Get provider verification details | - | - |
| `/api/admin/verifications/providers/{id}/status` | PUT | Update provider verification status | - | `UpdateStatusCommand` |
| `/api/admin/verifications/vehicles` | GET | List vehicles for verification | `PaginationParams, Filters` | - |
| `/api/admin/verifications/vehicles/{id}` | GET | Get vehicle verification details | - | - |
| `/api/admin/verifications/vehicles/{id}/status` | PUT | Update vehicle verification status | - | `UpdateStatusCommand` |
| `/api/identity/businesses` | GET | List businesses (Admin) | `PaginationParams, Filters` | - |
| `/api/identity/businesses/{id}` | GET | Get business details | - | - |
| `/api/identity/businesses/{id}` | PUT | Update business (Admin) | - | `UpdateBusinessRequest` |
| `/api/identity/providers` | GET | List providers (Admin) | `PaginationParams, Filters` | - |
| `/api/identity/providers/{id}` | GET | Get provider details | - | - |
| `/api/identity/providers/{id}` | PUT | Update provider (Admin) | - | `UpdateProviderRequest` |

---

## 📄 Pagination

### Pagination Parameters

```typescript
interface PaginationParams {
  pageNumber?: number;      // Default: 1
  pageSize?: number;         // Default: 20, Max: 100
  sortBy?: string;           // Field name to sort by
  sortDescending?: boolean;  // Default: false
}
```

### Paginated Response

```typescript
interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    pageSize: number;
    totalPages: number;
    totalItems: number;
    hasNext: boolean;
    hasPrevious: boolean;
  };
}
```

### Usage Example

```typescript
const { data, isLoading } = useQuery({
  queryKey: ['rfqs', { page: 1, pageSize: 20 }],
  queryFn: () => apiClient.get<PaginatedResponse<RFQ>>('/api/rfqs', {
    params: {
      pageNumber: 1,
      pageSize: 20,
      sortBy: 'createdAt',
      sortDescending: true,
    },
  }),
});
```

---

## 🔍 Filtering & Search

### Common Filter Parameters

```typescript
interface CommonFilters {
  search?: string;           // Full-text search
  startDateFrom?: string;    // ISO date string
  startDateTo?: string;       // ISO date string
  status?: string;           // Status filter
}
```

### RFQ Filters

```typescript
interface RFQFilters extends CommonFilters {
  vehicleTypeCode?: string;
  businessId?: string;
  bidDeadlineFrom?: string;
  bidDeadlineTo?: string;
}
```

### Contract Filters

```typescript
interface ContractFilters extends CommonFilters {
  providerId?: string;
  businessId?: string;
  contractNumber?: string;
}
```

### Vehicle Filters

```typescript
interface VehicleFilters {
  vehicleTypeCode?: string;
  engineTypeCode?: string;
  status?: 'ACTIVE' | 'ASSIGNED' | 'UNDER_REVIEW' | 'SUSPENDED';
  insuranceStatus?: 'ACTIVE' | 'EXPIRED' | 'PENDING';
  tags?: string[];
}
```

### Marketplace Filters (Provider)

```typescript
interface MarketplaceFilters {
  vehicleTypes?: string[];   // Multi-select
  duration?: 'SHORT' | 'LONG' | 'ALL';
  location?: string;
  search?: string;
  minQuantity?: number;
}
```

### Usage Example

```typescript
const filters = {
  vehicleTypes: ['EV_SEDAN', 'SUV'],
  duration: 'LONG',
  search: 'monthly rental',
  pageNumber: 1,
  pageSize: 20,
};

const { data } = useQuery({
  queryKey: ['rfqs', 'open', filters],
  queryFn: () => apiClient.get('/api/rfqs/open', { params: filters }),
});
```

---

## 🔄 React Query Integration

### Service Layer Pattern

**File:** `src/features/business/rfq/services/rfq-service.ts`

```typescript
import { apiClient } from '@/shared/lib/api-client';
import { RFQ, CreateRFQRequest, RFQFilters, PaginatedResponse } from '@/shared/types';

export const rfqService = {
  getRFQs: async (filters: RFQFilters): Promise<PaginatedResponse<RFQ>> => {
    return apiClient.get('/api/rfqs', { params: filters });
  },

  getRFQ: async (id: string): Promise<RFQ> => {
    return apiClient.get(`/api/rfqs/${id}`);
  },

  createRFQ: async (data: CreateRFQRequest): Promise<RFQ> => {
    return apiClient.post('/api/rfqs', data);
  },

  updateRFQ: async (id: string, data: Partial<CreateRFQRequest>): Promise<RFQ> => {
    return apiClient.put(`/api/rfqs/${id}`, data);
  },

  deleteRFQ: async (id: string): Promise<void> => {
    return apiClient.delete(`/api/rfqs/${id}`);
  },

  publishRFQ: async (id: string): Promise<RFQ> => {
    return apiClient.post(`/api/rfqs/${id}/publish`);
  },

  cancelRFQ: async (id: string, reason: string): Promise<void> => {
    return apiClient.post(`/api/rfqs/${id}/cancel`, { reason });
  },
};
```

### Custom Hooks

**File:** `src/features/business/rfq/hooks/useRFQs.ts`

```typescript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { rfqService } from '../services/rfq-service';
import { RFQFilters } from '@/shared/types';

export const useRFQs = (filters: RFQFilters) => {
  return useQuery({
    queryKey: ['rfqs', filters],
    queryFn: () => rfqService.getRFQs(filters),
    staleTime: 5 * 60 * 1000,
  });
};

export const useRFQ = (id: string) => {
  return useQuery({
    queryKey: ['rfq', id],
    queryFn: () => rfqService.getRFQ(id),
    enabled: !!id,
  });
};

export const useCreateRFQ = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: rfqService.createRFQ,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rfqs'] });
    },
  });
};

export const usePublishRFQ = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: rfqService.publishRFQ,
    onSuccess: (_, id) => {
      queryClient.invalidateQueries({ queryKey: ['rfqs'] });
      queryClient.invalidateQueries({ queryKey: ['rfq', id] });
    },
  });
};
```

---

## 📤 File Upload

### Upload Service

```typescript
export const fileUploadService = {
  uploadDocument: async (
    entityType: 'business' | 'provider' | 'vehicle',
    entityId: string,
    file: File,
    documentType: string
  ): Promise<{ id: string; fileUrl: string }> => {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('documentType', documentType);

    return apiClient.uploadFile(
      `/api/${entityType}s/${entityId}/documents`,
      file,
      { documentType }
    );
  },

  uploadVehiclePhotos: async (
    vehicleId: string,
    photos: {
      front: File;
      back: File;
      left: File;
      right: File;
      interior: File;
    }
  ): Promise<{ [key: string]: string }> => {
    const formData = new FormData();
    Object.entries(photos).forEach(([key, file]) => {
      formData.append(`${key}Photo`, file);
    });

    return apiClient.post(`/api/vehicles/${vehicleId}/photos`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
};
```

---

## ✅ Best Practices

1. **Always use TypeScript types** for request/response
2. **Use React Query** for server state management
3. **Handle errors consistently** using error handler utility
4. **Implement retry logic** for failed requests
5. **Cache responses** appropriately with staleTime
6. **Invalidate queries** after mutations
7. **Use optimistic updates** where appropriate
8. **Handle loading states** in UI
9. **Implement request cancellation** for long-running queries
10. **Log API errors** for debugging

---

**END OF API INTEGRATION SPEC**

*For specific endpoint implementations, refer to the backend API specification in `v1.yaml`*

