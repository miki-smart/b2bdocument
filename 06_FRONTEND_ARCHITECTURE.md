# Frontend Architecture — React 18 + Vite (as built)

**Last verified against code: 2026-07-23**

> **Correction notice.** The prior version of this document (November 26, 2025) described an **Angular 19 + Signals** architecture — standalone components, `NgModule`-free lazy-loaded feature modules, a `Service-with-Signals` store pattern, `CanActivateFn` route guards, `HttpClient`-based services. **No Angular code has ever existed in this repository.** The real web frontend, `marketplace-project-implementation/anqelbacarrental-marketplace-core/`, is and has only ever been **React 18.3 + Vite 6 + TypeScript**, using TanStack React Query 5 for server state and Zustand 5 for the small amount of global client state. This rewrite replaces the prior content in full, verified directly against `package.json`, `vite.config.ts`, and the `src/` tree. See `project-docs/18_Implementation_Coverage_Audit.md` §8/§10 for the correction record, and treat `.agent/roles/frontend-developer.md`, `markdown-documentations/Frontend_Architecture_Guide.md`, and `markdown-documentations/FRONTEND_AUDIT_REPORT.md` (all rewritten the same day) as the fuller companion references for this stack.

**Framework:** React 18.3.1
**Build tool:** Vite 6.4 (`@vitejs/plugin-react-swc`)
**Language:** TypeScript 5.8, strict mode
**Server state:** TanStack React Query 5.83
**Global client state:** Zustand 5.0.9 (3 stores only — not a general-purpose store)
**Styling:** Tailwind CSS 3.4 + shadcn/ui (Radix UI primitives)

---

## 1. Overview

The Anqelba Car Rental web frontend is **one Vite single-page application**, not a multi-app workspace and not three separately deployed frontends. All three role-scoped portals — Business, Provider, Admin — are served from the same bundle, the same React Router route table, and the same build output. What separates them is folder structure and route guards, not build boundaries:

1. **Feature folders** — `src/features/{business,provider,admin}/pages/` each hold that portal's pages (provider and admin also have portal-scoped `components/`).
2. **Layout components** — `BusinessLayout`, `ProviderLayout`, `AdminLayout`, `PublicLayout` in `src/app/layouts/`, selected per route group in the flat route table in `src/App.tsx`.
3. **`ProtectedRoute` + `allowedRoles`** — a single route-guard component (`src/shared/components/auth/ProtectedRoute.tsx`) gates every authenticated route and redirects a user who hits the wrong portal to their own dashboard, rather than to a generic "unauthorized" page.

There is no separate Angular-style `CanActivateFn` guard, no `NgModule`/lazy-`loadChildren` feature-module system, and no BFF service in front of the SPA — the app talks to the .NET 9 modular-monolith backend directly (proxied through Vite's dev server, or nginx in deployed environments, so that cookies stay same-origin).

---

## 2. Project Structure (verified against `src/`)

```
anqelbacarrental-marketplace-core/
├── src/
│   ├── App.tsx                     # single flat route table for the entire app
│   ├── main.tsx
│   ├── app/layouts/                # BusinessLayout, ProviderLayout, AdminLayout, PublicLayout
│   ├── core/
│   │   ├── services/               # 33 plain-object services (rfq-service.ts, bid-service.ts,
│   │   │                            #  contract-service.ts, wallet-service.ts, direct-rental-service.ts,
│   │   │                            #  admin-wallet-service.ts, provider-fleet-capacity-service.ts, …)
│   │   └── types/                  # rfq.ts, bid.ts, contract.ts, business.ts, auth.ts …
│   ├── features/
│   │   ├── auth/pages/             # login, register, verify-email, verify-phone, forgot-password
│   │   ├── onboarding/pages/       # business-onboarding (3 steps), provider-onboarding (type-preselect + 3 steps)
│   │   ├── business/pages/         # dashboard, rfq, contracts, wallet, direct-rental, profile, notifications
│   │   ├── provider/pages/          # dashboard, marketplace, bids, fleet, contracts, wallet, direct-rental, profile, notifications
│   │   └── admin/pages/             # dashboard, operations, verifications, users, wallets, settlements, master-data, notifications
│   ├── shared/
│   │   ├── components/             # auth/ProtectedRoute+SessionExpiredDialog, data/, forms/, layout/,
│   │   │                           #  business/ (SplitAwardDialog), contracts/, wallet/, direct-rental/,
│   │   │                           #  onboarding/, profile/, brand/
│   │   ├── constants/               # ROUTES and other app-wide constants
│   │   ├── lib/                     # api-client.ts, query-client.ts, validation.ts, firebase-messaging.ts
│   │   └── types/
│   ├── stores/                      # auth-store.ts, notification-store.ts, direct-rental-store.ts
│   ├── components/ui/               # shadcn/ui primitives (button, dialog, toast, tooltip, sidebar, …)
│   └── pages/, hooks/, lib/utils.ts # a handful of top-level public pages + generic shared hooks/cn()
├── vite.config.ts                   # dev proxy for /api, /web, /hubs (WS) to backend; SWC React plugin
├── tailwind.config.ts
└── package.json                     # npm — a stray bun.lockb also exists but is not used by CI/deploys
```

`src/components/` and `src/lib/utils.ts` (outside `src/shared/`) are the original shadcn-CLI scaffolding locations, not a parallel architecture layer — normal for a Lovable-initialized, then hand-developed, codebase. Feature/business code lives under `src/features/`, `src/core/`, and `src/shared/`.

---

## 3. State Management (not Signals, not NgRx)

State is split two ways only:

- **Server state → TanStack React Query 5** (`useQuery` / `useMutation`). RFQs, bids, contracts, wallet balances, verifications — anything that came from the API — lives here. Never re-hosted in Zustand.
- **Client/global state → Zustand 5**, scoped to exactly three stores:
  - `useAuthStore` — current user, `isAuthenticated`, login/logout; persisted to `localStorage` via `persist` middleware, but only `user` and `isAuthenticated` (`partialize`) — never a token.
  - `useNotificationStore` — SignalR hub connection lifecycle, unread count.
  - `direct-rental-store` — Direct Rental cart/browse UI state (client-only, ephemeral — not a cache of server data).

Everything else is local component state (`useState`) or form state (React Hook Form). There is no generic "app store," no NgRx-style reducer/action pattern, and no Angular Signals anywhere in this codebase.

### Auth store (real shape)
```typescript
// src/stores/auth-store.ts
export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      user: null,
      isAuthenticated: false,
      login: async (credentials) => {
        const response = await authService.login(credentials);
        set({ user: response.data.user, isAuthenticated: true });
        useNotificationStore.getState().startHub(queryClient);
      },
      logout: () => {
        authService.logout();
        useNotificationStore.getState().stopHub();
        set({ user: null, isAuthenticated: false });
      },
    }),
    {
      name: AUTH_STORAGE_KEY,
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ user: state.user, isAuthenticated: state.isAuthenticated }),
    }
  )
);
```

### Service + query-hook pattern (real shape)
```typescript
// core/services/rfq-service.ts — plain object, not a class, not a hook
export const rfqService = {
  getAll: async (params?: Record<string, unknown>): Promise<PaginatedResponse<RFQ>> => {
    const response = await apiClient.get<BackendPagedResult>('/api/rfqs', { params });
    return mapPagedResponse(response.data, mapRFQ);
  },
  create: async (data: CreateRFQRequest) => apiClient.post<CreateRFQResponse>('/api/rfqs', data),
};

// features/business/pages/rfq/hooks/useRFQs.ts — co-located in the feature folder
export const useRFQs = (params?: Record<string, unknown>) =>
  useQuery({ queryKey: ['rfqs', params], queryFn: () => rfqService.getAll(params) });

export const useCreateRFQ = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: rfqService.create,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['rfqs'] }),
  });
};
```

`query-client.ts` defaults: `staleTime: 5 * 60 * 1000`, `gcTime: 10 * 60 * 1000`, `retry: 3` for queries / `retry: 1` for mutations, `refetchOnWindowFocus: false`.

### Forms — React Hook Form 7 + Zod 3
```typescript
const schema = z.object({
  title: z.string().min(5, 'Title must be at least 5 characters'),
  vehicleType: z.enum(['SEDAN', 'SUV', 'VAN', 'TRUCK']),
  quantity: z.coerce.number().int().positive(),
});
type FormValues = z.infer<typeof schema>;

const form = useForm<FormValues>({ resolver: zodResolver(schema) });
```
Every form uses `zodResolver` — no inline `validate` callbacks, no manual `setError` loops.

---

## 4. Auth & Routing (cookie-based, not header-based)

**Token model:** `httpOnly` session cookies. The browser sends them automatically because `apiClient`'s Axios instance sets `withCredentials: true`. The frontend never reads, stores, or attaches a bearer token.

**`ProtectedRoute` logic** (`src/shared/components/auth/ProtectedRoute.tsx`):
1. Not authenticated → redirect to `/login`, preserving `location.state.from`.
2. Authenticated, non-admin, email not verified → redirect to `/verify-email`.
3. Authenticated, non-admin, phone not verified (when `PHONE_VERIFICATION_REQUIRED`) → redirect to `/verify-phone`.
4. `allowedRoles` provided and role doesn't match → redirect to that role's own dashboard.

```tsx
<Route
  path={ROUTES.BUSINESS.RFQS}
  element={
    <ProtectedRoute allowedRoles={['business']}>
      <BusinessLayout />
    </ProtectedRoute>
  }
/>
```

Access control is role-based (`business` | `provider` | `admin`) via `allowedRoles` — there is no granular permission-string system. On a 401, `api-client.ts`'s response interceptor logs the user out (re-entrancy-guarded) and shows `SessionExpiredDialog`; admins are exempted from forced logout on `/web/*` 401s.

---

## 5. API Integration

All API access goes through one hand-written `ApiClient` singleton (`src/shared/lib/api-client.ts`), an Axios wrapper — not raw `fetch`, not a generated SDK, not a per-feature client class:

```typescript
class ApiClient {
  private client: AxiosInstance;
  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      timeout: 30000,
      withCredentials: true,
      headers: { 'Content-Type': 'application/json' },
    });
    this.setupInterceptors(); // ProblemDetails (RFC 7807) mapping + 401 handling
  }
  async get<T>(url, config?) { /* ... */ }
  async post<T>(url, data?, config?) { /* ... */ }
  async webRequest<T>(method, url, data?, config?) { /* /web/* auth endpoints, own client instance */ }
  async uploadFile<T>(url, file, additionalData?) { /* multipart */ }
}
export const apiClient = new ApiClient();
```

33 domain services in `core/services/` (`rfqService`, `bidService`, `contractService`, `walletService`, `directRentalService`, `adminWalletService`, `providerFleetCapacityService`, …) are each a plain object of async functions built on top of this one client.

**Dev-time backend resolution** (`vite.config.ts`): `BACKEND_URL` env (Docker runtime) → `VITE_BACKEND_URL` → mode-specific default — `localdev`/`development`/`staging`/`production` each point at a different `anqelbacarrental.com` host (or `localhost:5207` for local dev). The dev/preview server proxies `/api`, `/web`, and `/hubs` (WebSocket) to the backend so cookies work same-origin under `SameSite=Lax`.

---

## 6. Real-Time Notifications

Microsoft SignalR 10 (`@microsoft/signalr`) against `/hubs/notifications`, managed **exclusively** inside `useNotificationStore` — started on login/`checkAuth` success (passing the shared `QueryClient` so server-pushed events can invalidate query keys), stopped on logout. Components never instantiate `HubConnectionBuilder` directly. Firebase FCM 12 (`shared/lib/firebase-messaging.ts`) handles push.

---

## 7. Portal Feature Set (as actually built)

- **Business** (`src/features/business/pages/`): dashboard; RFQ (`create/` 3-step wizard, `list/`, `detail/`, `bids/` — split-award review via `SplitAwardDialog`); contracts (list/detail/delivery/return-checklist/`ExtendContractDialog` — there is no "renew" flow, only extension); wallet (`BusinessWalletPage`, `BusinessEscrowWalletPage`, `DepositHistoryPage`); Direct Rental (browse/cart/requests — a fixed-price non-bidding booking flow parallel to RFQ bidding, undocumented as a numbered epic); profile; notifications.
- **Provider** (`src/features/provider/pages/`): dashboard; marketplace (RFQ browse + bid submission); bids (my bids + award-assign — a post-award vehicle-assignment step, identical in pattern to the mobile apps'); fleet (vehicle registration, fleet capacity); contracts (assign vehicles, delivery); wallet (earnings, settlements, invoices); Direct Rental (requests/response); profile; notifications.
- **Admin** (`src/features/admin/pages/`): dashboard; operations (act on RFQ/bid/contract/settlement/wallet/Direct-Rental on behalf of users); verifications (business/provider/vehicle KYC-KYB); users; wallets (platform/escrow/all wallets, withholding tax); settlements; master-data (tiers, policies, commission strategies, lookups, geography, banks, checklist templates); notifications (channel-provider config + templates).

---

## 8. Build & Testing

- **Build modes:** `local`, `development`, `staging`, `production` via `--mode`, each with its own npm script and Docker Compose profile.
- **Chunking:** `manualChunks` splits `vendor` (react/react-dom/react-router-dom), `ui` (a few Radix packages), `charts` (recharts).
- **`lovable-tagger`'s `componentTagger()`** runs only in `development` mode — a leftover of the app's original Lovable scaffolding, harmless in other modes.
- **Testing:** Vitest 4 + `@testing-library/react` + `jsdom`. No Playwright/Cypress, no Storybook, no Chromatic — if E2E or visual-regression coverage is wanted, it is new scope to add, not existing tooling to "restore."

There is **no Mapbox**, no maps feature, and no Angular idiom (`@Component`, `signal()`, `NgModule`, `inject()`) anywhere in this app.

---

## 9. Where to Go Deeper

For state-management code samples, the component library, red-flag patterns, and cross-functional notes, see `.agent/roles/frontend-developer.md` (role doc) and `markdown-documentations/Frontend_Architecture_Guide.md` (fuller architecture guide) — both rewritten and verified against code the same day as this document. `markdown-documentations/FRONTEND_AUDIT_REPORT.md` covers module-by-module implementation depth.

---

**Next Document:** [07_EVENT_DRIVEN_PATTERNS.md](./07_EVENT_DRIVEN_PATTERNS.md)
