# API Integration Specification
## Movello Frontend - React Implementation

**Version:** 2.0
**Last verified against code: 2026-07-23** — full rewrite. The v1.0 spec described Bearer-token auth headers, a wrapped `{ success, data, meta }` response envelope, and a service/hook layer that doesn't match the real codebase. This version was checked directly against `movello-marketplace-core/src/shared/lib/api-client.ts` and the 30 files under `src/core/services/`.
**App:** `marketplace-project-implementation/movello-marketplace-core` (React 18.3 + Vite 6, TanStack Query 5)
**Base URL:** relative `/api` (same-origin — Vite dev proxy locally, nginx in Docker/production; see `VITE_API_BASE_URL` in `src/shared/constants/index.ts`)
**Related:** [AUTHENTICATION_GUIDE.md](./AUTHENTICATION_GUIDE.md), [FORM_VALIDATIONS_SPEC.md](./FORM_VALIDATIONS_SPEC.md)

---

## Table of Contents

1. [API Client Setup](#api-client-setup)
2. [Authentication Model](#authentication-model)
3. [Response & Error Format](#response--error-format)
4. [Request/Response Types](#requestresponse-types)
5. [Error Handling in Components](#error-handling-in-components)
6. [Endpoint Reference](#endpoint-reference)
7. [Pagination](#pagination)
8. [Filtering & Search](#filtering--search)
9. [React Query Integration](#react-query-integration)
10. [File Upload](#file-upload)
11. [Best Practices](#best-practices)

---

## API Client Setup

There is **one** hand-written Axios wrapper, not a generated client: `src/shared/lib/api-client.ts`, exporting a singleton `apiClient`. Every service in `src/core/services/` imports this one instance — never `axios` directly (importing `axios` directly in a component or service is a review-blocking violation per `.agent/roles/frontend-developer.md`).

Two important facts that differ from a typical REST client:

1. **`withCredentials: true`, no token anywhere in JS.** The client never reads, stores, or attaches an access token. The browser sends the `mov_access_token`/`mov_refresh_token` `HttpOnly` cookies automatically; the frontend cannot read them even if it tried. See [AUTHENTICATION_GUIDE.md](./AUTHENTICATION_GUIDE.md) for the full cookie/BFF-middleware flow.
2. **Two request paths, not one.** Most calls use the main `apiClient.get/post/put/patch/delete<T>()` methods against `/api/...`-mounted domain routes (RFQs, bids, contracts, wallet, vehicles, etc. — `baseURL` is `/api`). A second method, `apiClient.webRequest(method, url, data, config)`, targets the non-`/api` **`/web/*`** auth/session surface (`/web/login`, `/web/me`, `/web/logout`, `/web/register`, password/OTP endpoints) via a temporary Axios instance with `baseURL: ''`. Only `src/core/services/auth-service.ts` calls `webRequest`; every other service uses the main client.

**Real client (trimmed), `src/shared/lib/api-client.ts`:**

```typescript
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse, InternalAxiosRequestConfig, AxiosError } from 'axios';
import { API_BASE_URL } from '@/shared/constants';

// ProblemDetails format (RFC 7807) — what the .NET backend actually returns on error
interface ProblemDetails {
  type?: string;
  title?: string;
  status?: number;
  detail?: string;
  instance?: string;
  errors?: Record<string, string[]>;
  [key: string]: unknown;
}

class ApiClient {
  private client: AxiosInstance;

  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,       // '/api' — relative, proxied
      timeout: 30000,
      withCredentials: true,        // cookies sent automatically; no Authorization header ever set
      headers: { 'Content-Type': 'application/json' },
    });
    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor does NOT attach a token — cookies ride along automatically.
    this.client.interceptors.request.use((config) => config, (error) => Promise.reject(error));

    this.client.interceptors.response.use(
      (response) => response,
      async (error: AxiosError<ProblemDetails>) => {
        const status = error.response?.status;

        // Backend's BffTokenRefreshMiddleware already tried a silent refresh before this
        // request ever reached a controller. A 401 here means the refresh token is ALSO
        // expired — there is nothing left for the frontend to retry.
        if (status === 401) {
          const authState = getAuthState?.();
          if (authState && !authState.sessionExpiredHandlingInProgress) {
            authState.setSessionExpiredHandlingInProgress(true);
            authState.logout();
            authState.setSessionExpired(true);   // triggers <SessionExpiredDialog />
          }
          return Promise.reject(error);
        }

        // Transform RFC 7807 ProblemDetails into a plain Error the rest of the app can use
        if (error.response?.data) {
          const pd = error.response.data;
          const message = pd.detail || pd.title || (pd as { message?: string }).message || 'An error occurred';
          const transformed = new Error(message) as Error & { code?: string; details?: unknown };
          transformed.code = pd.type || `HTTP_${pd.status || status}`;
          transformed.details = pd.errors;          // field-level validation errors, if any
          return Promise.reject(transformed);
        }
        return Promise.reject(error);
      }
    );
  }

  async get<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
    return (await this.client.get<T>(url, config)).data;
  }
  async post<T>(url: string, data?: unknown, config?: AxiosRequestConfig): Promise<T> {
    return (await this.client.post<T>(url, data, config)).data;
  }
  // put / patch / delete follow the same shape

  /** Targets /web/* (non-/api) endpoints — auth/session surface only. See auth-service.ts. */
  async webRequest<T>(method: 'get' | 'post' | 'put' | 'patch' | 'delete', url: string, data?: unknown, config?: AxiosRequestConfig): Promise<T> {
    /* separate Axios instance, baseURL: '', withCredentials: true — same cookie behavior,
       different admin-401-exemption logic (see AUTHENTICATION_GUIDE.md) */
  }

  async uploadFile<T>(url: string, file: File, additionalData?: Record<string, string>): Promise<T> { /* multipart/form-data */ }
  async uploadFiles<T>(url: string, files: Record<string, File>, additionalData?: Record<string, string>): Promise<T> { /* multiple files */ }
}

export const apiClient = new ApiClient();
```

There is **no** `error-handler.ts` / centralized `handleApiError()` utility in the codebase (the v1.0 spec's `src/shared/utils/error-handler.ts` does not exist). Instead: the interceptor above already turns every failed request into a plain `Error` with a human-readable `.message` (pulled from ProblemDetails `detail`/`title`). Callers catch that error at the mutation or `try/catch` site and show it with **Sonner's `toast.error(error.message)`** — see [Error Handling in Components](#error-handling-in-components).

---

## Authentication Model

Full detail lives in [AUTHENTICATION_GUIDE.md](./AUTHENTICATION_GUIDE.md). Summary for API-calling purposes:

- **Cookie session, not Bearer tokens.** `mov_access_token` / `mov_refresh_token` are `HttpOnly` cookies set by the backend's `AuthController` (`POST /web/login`, `/web/register`, `/web/refresh`). The frontend never sees, stores, or attaches them — `withCredentials: true` is the entire client-side auth story.
- **Token refresh happens server-side, before your request arrives.** `BffTokenRefreshMiddleware` (backend, in-process — not a separate BFF service) silently refreshes an expiring access token on every `/api/*` request. The frontend's job on a 401 is simply to log out and show `SessionExpiredDialog` — never to call a `/refresh` endpoint itself (`authService.refreshToken()` still exists for backward compatibility but is a no-op that only logs a warning; it is not wired to anything).
- **This is the web pattern only.** The mobile Flutter apps get tokens back in the JSON response body from `MobileAuthController` and send them as `Authorization: Bearer` headers — that pattern does **not** apply to this web app. Never add a Bearer header or `localStorage` token here; see the Red Flags table in `.agent/roles/frontend-developer.md`.
- **Admin exemption:** the `/web/*` request path (`apiClient.webRequest`) does **not** force-logout an authenticated admin on a 401 — admins performing operational work aren't kicked out for an unrelated session hiccup. The main `/api/*` path has no such exemption.

---

## Response & Error Format

**Success responses are direct DTOs — there is no `{ success, data, meta }` envelope on the wire.** `apiClient.get<T>('/marketplace/rfqs/123')` resolves to the RFQ object itself, typed as whatever backend DTO interface the service declares (e.g. `BackendRFQDto`), not `ApiResponse<RFQ>`. `src/shared/types/api.ts` does still define an `ApiResponse<T>`/`ApiError` pair, but it is a **frontend-only convenience wrapper** that a handful of services (notably `auth-service.ts`) build client-side around a plain DTO for their own callers' convenience — it is not what the backend returns. Do not assume every service does this; most (RFQ, bid, contract, wallet, vehicle services) return the mapped domain type directly.

```typescript
// src/shared/types/api.ts — a frontend convenience shape some services choose to return,
// NOT the backend's actual wire format
export interface ApiResponse<T> {
  success: boolean;
  data: T;
  meta?: { timestamp: string; requestId: string };
}
```

**Error responses are RFC 7807 ProblemDetails**, the ASP.NET Core default:

```typescript
interface ProblemDetails {
  type?: string;      // becomes transformedError.code, e.g. "HTTP_400" if no type set
  title?: string;
  status?: number;
  detail?: string;    // primary message source
  instance?: string;
  errors?: Record<string, string[]>; // field-level validation errors (ASP.NET model validation shape)
}
```

`apiClient`'s response interceptor (see above) already converts this into a plain `Error` with `.message`, `.code`, and `.details` — components never parse `ProblemDetails` themselves.

| HTTP Status | Typical meaning in this app |
|---|---|
| 400 | Validation error — `error.details` holds the field → message[] map |
| 401 | Session/refresh token both expired — frontend force-logs-out (see Authentication Model) |
| 403 | Insufficient role/permission, or unverified email/phone gate |
| 404 | Resource not found |
| 409 | Conflict (e.g., duplicate TIN, RFQ already published) |
| 422 | Business rule violation (e.g., bid exceeds required quantity) |
| 429 | Rate limited (backend applies this on `MobileAuthController`; less relevant to web) |
| 500 | Server error |

---

## Request/Response Types

Types live in `src/core/types/` (domain types: `rfq.ts`, `bid.ts`, `contract.ts`, `business.ts`, …) and `src/shared/types/` (cross-cutting: `api.ts`, `onboarding.ts`). Each service also declares **private `Backend*Dto` interfaces** matching the real wire shape, and maps them to the domain type — never expose a raw backend DTO to a component.

### Pagination

```typescript
// src/shared/types/api.ts — matches the backend's PagedResult<T> shape after mapping
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
```

The raw backend response is actually `{ items, pageNumber, pageSize, totalPages, totalCount, hasPrevious, hasNext }` (see `BackendPagedRFQList` in `rfq-service.ts`, `BackendPagedTransactions` in `wallet-service.ts`). Services never return this shape directly — they run it through `mapPagedResponse()` (`src/shared/lib/response-mappers.ts`) to produce the `PaginatedResponse<T>` shape above. Always call the service method, never the raw backend list endpoint from a component.

### RFQ (line-item model — not a single vehicle-type/date-range shape)

The real RFQ shape is a **header + `lineItems[]`**, each line item carrying its own vehicle type, term, dates, and location — this is more granular than a naive "one RFQ = one vehicle type" model:

```typescript
// Backend DTO shape, src/core/services/rfq-service.ts
interface BackendRFQLineItemDto {
  id: string;
  rfqId: string;
  vehicleType: string;
  quantity: number;
  term: string;              // 'SHORT_TERM' | 'LONG_TERM'
  purpose: string;
  fuelType?: string | null;  // 'EV' | 'REGULAR' | 'DIESEL' | ... or null (no preference)
  requiredFrom: string;      // ISO date-time
  requiredTo: string;        // ISO date-time
  durationDays: number;      // backend-computed: Math.Ceiling((requiredTo - requiredFrom).TotalDays)
  pickupLocation?: string;
  dropoffLocation?: string;
  specifications?: string;
  targetPricePerUnit?: number;
}

interface BackendRFQDto {
  id: string;
  rfqNumber: string;
  businessId: string;
  title: string;
  status: string;            // DRAFT | PUBLISHED | BIDDING | PARTIALLY_AWARDED | AWARDED | COMPLETED | CANCELLED
  type: string;
  submissionDeadline: string;
  startDate?: string;        // computed: earliest lineItem.requiredFrom
  endDate?: string;          // computed: latest lineItem.requiredTo
  contractDurationDays?: number;
  awardedAt?: string;
  pickupCity?: string;
  dropoffCity?: string;
  isBlind: boolean;
  bidCount: number;
  lineItems: BackendRFQLineItemDto[];
  createdAt: string;
  updatedAt: string;
}
```

Bidding and awarding are **per-line-item**, with support for **split awards** — a single line item's quantity can be awarded across multiple providers (`SplitAwardDialog.tsx`, `rfq-award-service.ts`). After award, there is a **separate vehicle-assignment step** shared by web and both mobile apps (`GET /marketplace/rfq/awards/{awardId}/eligible-vehicles`, `POST/DELETE /marketplace/rfq/awards/{awardId}/vehicles`) — bidding happens at the fleet/quantity level, specific vehicles are assigned only after the award. Do not model RFQs as single-vehicle-type/date-range in any new code.

### Contract

Contract status is a **plain string column** driven by real code paths, not a fixed enum consumed anywhere outside its own definition file — the real lifecycle includes a dual-party OTP e-signature step (`PendingSigning`/`Signed`), a vehicle-assignment sub-phase, delivery + **return** OTP with an inspection checklist, and contract **extension** (not "renewal into a new contract" — there is no `renew` endpoint). See `project-docs/18_Implementation_Coverage_Audit.md` §3/§10.1 and `MVP_CONTRACT_STATE_MACHINE.md` for the authoritative state list; do not hardcode a short enum of contract statuses in new frontend code without checking that doc first.

### Wallet

```typescript
// src/core/services/wallet-service.ts (trimmed)
interface BackendWalletAccountDto {
  id: string;
  ownerId: string;
  ownerType: string;   // 'BUSINESS' | 'PROVIDER' | 'PLATFORM'
  accountType: string;
  currency: string;
  balance: number;
  lockedBalance: number;
}

interface BackendTransactionDto {
  transactionId: string;
  transactionType: string;
  transactionDate: string;
  amount: number;
  balanceAfter: number;
  description: string;
  status: string;
}
```

Deposits go through `POST /payments/intent` (Chapa/Telebirr/CBE Birr gateway integration is live, not a "future risk item"). Withdrawals go through `POST /finance/wallets/my-wallet/withdrawal`. Escrow locks are read via `GET /finance/escrow/my-locks`.

---

## Error Handling in Components

There is no `handleApiError()` utility to call. The pattern used throughout the codebase is: let `apiClient`'s interceptor turn the failure into an `Error`, catch it at the mutation/`try-catch` site, and show `error.message` via **Sonner**'s `toast` (not the `error.details` field map, in most current call sites — field-level ProblemDetails `errors` are available on `error.details` for forms that want to map them onto specific fields, but most mutations just surface the top-level message):

```typescript
// src/features/business/pages/rfq/create/RFQCreateWizard.tsx (real pattern)
import { toast } from 'sonner';

const onSubmit = async (data: Step2Data) => {
  try {
    await createRfq.mutateAsync(payload);
    toast.success('RFQ saved as draft');
  } catch (error: any) {
    toast.error(error.message || 'Failed to create RFQ');
  }
};
```

`react-hook-form`'s own `errors` object (from the Zod resolver) handles field-level client-side validation messages — see [FORM_VALIDATIONS_SPEC.md](./FORM_VALIDATIONS_SPEC.md). Server-side field errors (`error.details`, a `Record<string, string[]>`) are a secondary channel, used when a form needs to surface a uniqueness/conflict error the client couldn't have known about in advance.

---

## Endpoint Reference

This is not an exhaustive OpenAPI mirror — the source of truth is `src/core/services/*.ts` (30 files) and the backend's own controllers. Below are the real path prefixes each domain uses, confirmed from the services.

### Auth (`/web/*` — via `apiClient.webRequest`, see `auth-service.ts`)

| Endpoint | Method | Notes |
|---|---|---|
| `/web/login` | POST | Sets cookies; frontend then calls `/web/me` |
| `/web/register` | POST | Auto-login on success (cookies set) |
| `/web/me` | GET | Current user + enrichment from `/identity/businesses/me` or `/identity/providers/me` |
| `/web/logout` | POST | Best-effort; clears cookies regardless of response |
| `/web/verify-email-manual` | POST | `{ email, otpCode }` |
| `/web/verify-phone` | POST | `{ email, otpCode }` |
| `/web/resend-otp`, `/web/resend-phone-otp` | POST | |
| `/web/forgot-password` | POST | `{ email }` — sends reset OTP |
| `/web/verify-reset-otp` | POST | `{ email, otpCode }` → `{ isValid }` |
| `/web/reset-password-with-otp` | POST | `{ email, otpCode, newPassword }` |
| `/web/update-unverified-email` | POST | For accounts not yet email-verified |

### RFQ & Bidding (`/marketplace/*`, `/api` prefix — `rfq-service.ts`, `bid-service.ts`, `bid-tracking-service.ts`, `rfq-award-service.ts`, `marketplace-service.ts`)

| Endpoint | Method | Notes |
|---|---|---|
| `/marketplace/rfqs` | GET | List, paginated + filtered (see [Filtering](#filtering--search)) |
| `/marketplace/rfqs` | POST | Create |
| `/marketplace/rfqs/{id}` | GET / PUT / DELETE | |
| `/marketplace/rfqs/{id}/publish` | PUT | |
| `/marketplace/rfqs/{id}/close` | PUT | Backend calls this "close," not "cancel" |
| `/marketplace/rfqs/{id}/extend-deadline` | PUT | `{ additionalDays }`, default 3, used on expired RFQs |
| `/marketplace/bids` | GET / POST | Provider's bids / submit bid |
| `/marketplace/bids/rfq/{rfqId}` | GET | Bids for one RFQ (business-side review) |
| `/marketplace/bids/{bidId}` | GET / PUT / DELETE | Detail / edit / withdraw |
| `/marketplace/bids/{bidId}/revoke-award` | POST | |
| `/marketplace/bids/{bidId}/award-assignments` | GET | Vehicle-assignment status for a bid's award |
| `/marketplace/rfq/awards/{awardId}/eligible-vehicles` | GET | |
| `/marketplace/rfq/awards/{awardId}/vehicles` | POST / DELETE | Assign / unassign specific vehicles post-award |

### Contracts (`/contracts/*` — `contract-service.ts`)

| Endpoint | Method | Notes |
|---|---|---|
| `/contracts/{contractId}` | GET | |
| `/contracts/{contractId}/terms` | GET | Terms-acceptance status |
| `/contracts/{contractId}/terms/otp/generate` | POST | Dual-party e-signature OTP — distinct from delivery OTP |
| `/contracts/{contractId}/terms/otp/verify` | POST | |

### Wallet & Payments (`/finance/*`, `/payments/*` — `wallet-service.ts`)

| Endpoint | Method | Notes |
|---|---|---|
| `/finance/wallets/owner/{ownerId}?ownerType=...` | GET | Wallet balance |
| `/finance/wallets/owner/{ownerId}/summary?ownerType=...` | GET | Includes escrow breakdown |
| `/finance/wallets/{walletId}/transactions` | GET | Paginated ledger |
| `/finance/escrow/my-locks` | GET | Active escrow locks |
| `/finance/wallets/my-wallet/withdrawal` | POST | |
| `/payments/intent` | POST | Deposit — returns a gateway `checkoutUrl` (Chapa/Telebirr/CBE Birr) |

### Vehicles / Fleet (`/identity/*` — `fleet-service.ts`)

| Endpoint | Method | Notes |
|---|---|---|
| `/identity/vehicles/{vehicleId}` | GET / PUT | |
| `/identity/vehicles/{vehicleId}/status` | PUT | |
| `/identity/vehicles/{vehicleId}/assignments` | GET | |
| `/identity/providers/me`, `/identity/businesses/me` | GET | Current user's own profile |
| `/kyc-requirements` | GET | |

### Direct Rental (`/marketplace/cart/*`, `/admin/direct-rental/*` — `direct-rental-service.ts`)

A parallel, fixed-price (non-bidding) booking flow — browse → cart → request → provider accept/reject. Not one of the 20 backlog epics but fully built cross-surface; see `backlog/post-mvp/epic-21-direct-rental.md`.

| Endpoint | Method |
|---|---|
| `/marketplace/cart` | GET |
| `/marketplace/cart/items` | POST |
| `/marketplace/cart/submit-preview` | GET |
| `/admin/direct-rental/businesses/{businessId}/cart` | GET |

---

## Pagination

```typescript
interface PaginationParams {
  pageNumber?: number;
  pageSize?: number;
  sortBy?: string;
  sortDescending?: boolean;
}
```

Usage — pass raw params to the service, which builds the query string and unwraps the backend's `items/pageNumber/.../hasNext` shape into `PaginatedResponse<T>` via `mapPagedResponse()`:

```typescript
const { data, isLoading } = useQuery({
  queryKey: ['rfqs', filters],
  queryFn: () => rfqService.listRfqs(filters),
  staleTime: 1000 * 60 * 2,
});
// data.data -> T[], data.pagination.{page,pageSize,totalPages,totalItems,hasNext,hasPrevious}
```

---

## Filtering & Search

Real filter shape accepted by `rfqService.listRfqs()` (`src/core/services/rfq-service.ts`) — this is the actual, current filter contract, not a generic placeholder:

```typescript
interface RfqListFilters {
  page?: number;
  pageSize?: number;
  status?: string | string[];  // single status, 'ALL'/'' for no filter, or an array → repeated `statuses` params
  search?: string;
  vehicleType?: string;
  fuelType?: string;
  dateFrom?: string;
  dateTo?: string;
  sortBy?: string;
  businessId?: string;
}
```

Note the `status` handling nuance: passing an array serializes as **repeated `statuses` query params** (multi-select), a single string as `status=`, and `'ALL'`/`''` as an empty `status=` param meaning "no filter" (management/admin list views). Omitting `status` entirely lets the marketplace endpoint apply its own default (open-for-bidding) filter — do not assume "no param" and "empty string param" behave the same; they don't.

---

## React Query Integration

**Services are plain objects — never classes, never hooks.** Data fetching lives in `queryFn`, never in a `useEffect`. This is a hard convention (`.agent/roles/frontend-developer.md` §Non-Negotiables #4).

**Service layer** (`src/core/services/rfq-service.ts`, real, trimmed):

```typescript
export const rfqService = {
  listRfqs: async (filters: RfqListFilters = {}): Promise<PaginatedResponse<RFQListItem>> => {
    const params = new URLSearchParams();
    if (filters.page) params.append('pageNumber', String(filters.page));
    if (filters.pageSize) params.append('pageSize', String(filters.pageSize));
    // ... status/search/vehicleType/etc handling ...
    const backendResponse = await apiClient.get<BackendPagedRFQList>(`/marketplace/rfqs?${params}`);
    return mapPagedResponse(backendResponse, transformLineItem /* mapper */);
  },

  getRfqById: async (id: string): Promise<RFQ> => {
    const response = await apiClient.get<BackendRFQDto>(`/marketplace/rfqs/${id}`);
    return { /* map BackendRFQDto -> RFQ domain type, including lineItems.map(transformLineItem) */ } as RFQ;
  },

  createRfq: async (data: CreateRFQRequest): Promise<CreateRFQResponse> => {
    if (!data.businessId) {
      const businessProfile = await apiClient.get<{ id: string }>('/identity/businesses/me');
      data.businessId = businessProfile.id;
    }
    const response = await apiClient.post<BackendRFQDto>('/marketplace/rfqs', data);
    return { id: response.id, rfqNumber: response.rfqNumber, status: response.status as RFQStatus, createdAt: response.createdAt };
  },

  publishRfq: async (id: string) => { await apiClient.put(`/marketplace/rfqs/${id}/publish`, {}); return { success: true }; },
  cancelRfq:  async (id: string) => { await apiClient.put(`/marketplace/rfqs/${id}/close`, {}); return { success: true }; }, // backend calls it "close"
};
```

**Query hooks** (`src/features/business/pages/rfq/hooks/useRFQs.ts`, real, in full):

```typescript
export function useRFQs(filters: RFQFilters) {
  return useQuery({
    queryKey: ['rfqs', filters],
    queryFn: () => rfqService.listRfqs(filters),
    staleTime: 1000 * 60 * 2,
  });
}

export function useRFQ(id: string | undefined) {
  return useQuery({
    queryKey: ['rfq', id],
    queryFn: () => rfqService.getRfqById(id!),
    enabled: !!id,
    staleTime: 1000 * 60 * 5,
  });
}

export function useCreateRFQ() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: CreateRFQRequest) => rfqService.createRfq(data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['rfqs'] }),
  });
}

export function usePublishRFQ() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => rfqService.publishRfq(id),
    onSuccess: (_, id) => {
      queryClient.invalidateQueries({ queryKey: ['rfqs'] });
      queryClient.invalidateQueries({ queryKey: ['rfq', id] });
    },
  });
}
```

**QueryClient defaults** (`src/shared/lib/query-client.ts`, real, in full):

```typescript
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 5 * 60 * 1000, gcTime: 10 * 60 * 1000, retry: 3, refetchOnWindowFocus: false },
    mutations: { retry: 1 },
  },
});
```

Individual hooks override `staleTime` per-query where it matters (e.g. `useRFQs` uses 2 minutes, `useRFQ` uses 5) — the values above are just the fallback.

**Component** (real pattern — no `useEffect` fetch):

```tsx
export const RfqListPage = () => {
  const { data, isLoading } = useRFQs(filters);
  if (isLoading) return <LoadingSkeleton rows={5} />;
  return <DataTable columns={rfqColumns} data={data?.data ?? []} emptyMessage="No RFQs found" />;
};
```

---

## File Upload

Real signatures (`src/shared/lib/api-client.ts`):

```typescript
async uploadFile<T>(url: string, file: File, additionalData?: Record<string, string>): Promise<T>;
async uploadFiles<T>(url: string, files: Record<string, File>, additionalData?: Record<string, string>): Promise<T>;
```

Both build a `FormData` and post with `Content-Type: multipart/form-data`. `uploadFiles` is used for the multi-file cases (vehicle photo sets, document bundles) where each file needs its own field key — see [FORM_VALIDATIONS_SPEC.md](./FORM_VALIDATIONS_SPEC.md) for the Zod file-validation schemas that gate what gets uploaded.

---

## Best Practices

1. **Type every backend DTO explicitly** — a private `Backend*Dto` interface per service, mapped to the domain type. No `any`, no `as any` casts on service responses.
2. **`useQuery`/`useMutation` for all server state** — never re-host fetched data in Zustand; never fetch in `useEffect`.
3. **Services are plain objects** — `export const xService = { methodName: async (...) => {...} }`, not a class, not a hook.
4. **Invalidate the right query keys after mutations** — both the list key (`['rfqs']`) and the detail key (`['rfq', id]`) where applicable.
5. **Let the interceptor do error transformation** — catch the resulting `Error`, show `error.message` via `toast.error` (Sonner). Don't hand-parse `ProblemDetails` in components.
6. **`@/` path alias always** — `import { apiClient } from '@/shared/lib/api-client'`, never a relative `../../../shared/lib/api-client`.
7. **Never import `axios` directly** — always go through `apiClient` (or `apiClient.webRequest` for the `/web/*` surface).
8. **Respect the `/web/*` vs `/api/*` split** — auth/session calls use `webRequest`; every domain feature call uses the main client methods against `/api/...`.
9. **No manual token/refresh logic** — `authService.refreshToken()` is a deprecated no-op; token refresh is entirely the backend's `BffTokenRefreshMiddleware` responsibility.
10. **Check `src/core/services/*.ts` before assuming an endpoint shape** — this document lists the real prefixes as of 2026-07-23, but is not a substitute for reading the actual service file when precision matters (query param quirks like the `status`/`statuses` split are easy to get subtly wrong from a table alone).

---

**END OF API INTEGRATION SPEC**

*Auth flow detail: [AUTHENTICATION_GUIDE.md](./AUTHENTICATION_GUIDE.md). Form/Zod conventions: [FORM_VALIDATIONS_SPEC.md](./FORM_VALIDATIONS_SPEC.md). Architecture context: `architecture/bff-backend-for-frontend-spec.md`, `.agent/roles/frontend-developer.md`, `project-docs/18_Implementation_Coverage_Audit.md`.*
