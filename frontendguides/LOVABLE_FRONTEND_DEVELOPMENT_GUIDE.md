# Lovable Frontend Development Guide
## Anqelba Car Rental B2B Mobility Marketplace — React + Vite + TypeScript (as built)

**Last verified against code: 2026-07-23**

> **Reframing notice.** This document was originally written (December 2025) as a **from-scratch build prompt for the Lovable AI platform** — instructions for generating a new frontend, targeting React 18.2+/Vite 5.0+, "npm or pnpm," a `src/app/routes/index.tsx` router file, a `ui-store.ts` third Zustand store, `src/styles/globals.css`, and `react-error-boundary`/optional Playwright as assumed tooling. **The app was in fact bootstrapped via Lovable early on** (`lovable-tagger`'s `componentTagger()` Vite plugin still runs in development mode as a leftover of that origin) **but has since been extensively hand-developed well beyond that scaffold**, and several structural details in the original prompt were never actually how the app was built (there is no separate router file, no `ui-store`, no `styles/` folder, no `react-error-boundary` dependency). Rather than delete this document, it has been rewritten as an **as-built development reference** — the section structure (tech stack, project structure, patterns, error handling, responsive design, accessibility, performance, build/deploy) is preserved because it's still a useful map of the codebase, but every claim has been corrected against `package.json`, `vite.config.ts`, and the real `src/` tree in `marketplace-project-implementation/anqelbacarrental-marketplace-core/`. Where this document and the code disagree in the future, trust the code and `project-docs/18_Implementation_Coverage_Audit.md`.

---

## 📋 Table of Contents

1. [Project Overview](#project-overview)
2. [Technology Stack](#technology-stack)
3. [Project Structure](#project-structure)
4. [Architecture Patterns](#architecture-patterns)
5. [Component Library](#component-library)
6. [State Management](#state-management)
7. [Error Handling](#error-handling)
8. [Responsive Design](#responsive-design)
9. [Accessibility](#accessibility)
10. [Performance Optimization](#performance-optimization)
11. [Deployment & Build](#deployment--build)
12. [Related Documentation](#related-documentation)

---

## 🎯 Project Overview

### Purpose
This guide documents how the Anqelba Car Rental B2B Mobility Marketplace frontend is actually built — React, Vite, Tailwind CSS, and TypeScript, in the single Vite project `marketplace-project-implementation/anqelbacarrental-marketplace-core/` — for anyone extending it or generating new screens consistent with the real codebase.

### Application Structure
The application is **one Vite single-page app** serving **three role-scoped portals**, not three separate deployables:

1. **Business Portal** (`src/features/business/`) — businesses seeking vehicle rentals, both via RFQ/bidding and fixed-price Direct Rental.
2. **Provider Portal** (`src/features/provider/`) — vehicle rental/fleet providers.
3. **Admin Portal** (`src/features/admin/`) — platform administrators, master-data configuration, and act-on-behalf-of operations.

Portal separation happens through `src/features/{business,provider,admin}/pages/` folders, per-portal layouts (`BusinessLayout`/`ProviderLayout`/`AdminLayout`), and `ProtectedRoute`'s `allowedRoles` prop — not through separate builds, workspaces, or routers.

### Key Features (as actually shipped, corrected from the original list)
- Multi-step onboarding wizards with document upload (business: 3 steps; provider: type-preselect + 3 further steps including vehicle registration).
- RFQ creation as a **header + line-items model** (multiple vehicle types/terms per RFQ) and blind bidding with **per-line-item split awards** (`SplitAwardDialog.tsx`) — not a single vehicle-type/quantity RFQ with whole-RFQ awarding.
- Contract management with a **dual-party OTP e-signature step** (distinct from delivery OTP), a post-award **vehicle-assignment** step, and contract **extension** (there is no "renew as new contract" flow, and no "Suspended" status).
- Wallet management with escrow locking, live Chapa/Telebirr/CBEBirr payment-gateway integration, and 17+ dedicated wallet/settlement pages across all three portals.
- Real-time notifications via **SignalR** (not raw WebSocket) plus Firebase FCM push, with a full admin-configurable multi-channel (email/SMS/FCM) settings surface.
- Delivery **and return-trip** OTP verification, each paired with a vehicle inspection checklist.
- Trust score and tier system (provider-only; computed on the backend, surfaced read-only on the frontend — there is no business-facing risk score).
- KYC/KYB verification workflows for both businesses and providers.
- A full parallel **Direct Rental** fixed-price, non-bidding booking flow (browse → cart → request → provider accept/reject) — absent from the original prompt entirely.

---

## 🛠️ Technology Stack

### Core Technologies (verified against `package.json`)
```json
{
  "framework": "React 18.3.1",
  "buildTool": "Vite 6.4 (@vitejs/plugin-react-swc)",
  "language": "TypeScript 5.8 (strict mode)",
  "styling": "Tailwind CSS 3.4 + tailwindcss-animate + @tailwindcss/typography",
  "packageManager": "npm (package-lock.json is the lockfile of record; a stray bun.lockb exists but is not used by CI/deploys)"
}
```
The original prompt's "React 18.2+ / Vite 5.0+ / npm or pnpm" is imprecise on all three counts — the real versions are pinned above, and the package manager is npm only, not a pnpm option.

### State Management (verified against `src/stores/`)
```json
{
  "globalState": "Zustand 5.0.9 — exactly 3 stores: useAuthStore, useNotificationStore, direct-rental-store",
  "serverState": "TanStack React Query 5.83",
  "formState": "React Hook Form 7.61",
  "validation": "Zod 3.25 (@hookform/resolvers)"
}
```
There is **no `ui-store.ts`** in this codebase — the original prompt's third store was never built. Ephemeral, non-auth/non-notification/non-cart UI state is local `useState`, not a global store.

### UI Components (verified against `package.json` + `src/components/ui/`)
```json
{
  "componentLibrary": "shadcn/ui conventions over Radix UI primitives (@radix-ui/react-*)",
  "icons": "lucide-react",
  "animations": "Framer Motion 12 (used selectively, not a core architectural pillar)",
  "charts": "Recharts 2.15 (dashboard-embedded only, no standalone analytics module)",
  "datePicker": "react-day-picker 8.10",
  "otpInput": "input-otp (used by the shared OTPInput component)",
  "toasts": "Sonner + shadcn Toaster"
}
```

### Development Tools (corrected — several original claims don't match `package.json`)
```json
{
  "linting": "ESLint 9 (flat config, eslint.config.js) — no Prettier dependency exists in this repo",
  "typeChecking": "TypeScript 5.8 strict mode",
  "testing": "Vitest 4 + @testing-library/react 16 + jsdom",
  "e2eTesting": "not present — no Playwright/Cypress dependency exists; treat as new scope to add, not existing optional tooling"
}
```
The original prompt listed "ESLint + Prettier" and "Playwright (optional)" — neither Prettier nor any E2E framework is an installed dependency today. Do not assume either exists without adding it first.

---

## 📁 Project Structure (verified against the real `src/` tree — corrected from the original prompt's structure)

```
anqelbacarrental-marketplace-core/
├── public/
├── src/
│   ├── App.tsx                        # single flat route table for the WHOLE app — there is
│   │                                   #  no separate src/app/routes/index.tsx; all <Route>
│   │                                   #  elements are declared directly in App.tsx
│   ├── main.tsx
│   ├── App.css                        # legacy CSS-module-era file kept from the original
│   │                                   #  Vite/shadcn scaffold; the real design system lives
│   │                                   #  in src/index.css, not src/styles/globals.css
│   ├── index.css                      # design tokens (HSL custom properties), Google Fonts
│   │                                   #  @import, @layer base/utilities, keyframes
│   ├── app/
│   │   └── layouts/                   # PublicLayout, BusinessLayout, ProviderLayout, AdminLayout
│   │                                   #  (no separate routes/ subfolder)
│   ├── core/
│   │   ├── services/                  # 30+ plain-object services (rfq-service.ts, bid-service.ts,
│   │   │                              #  contract-service.ts, wallet-service.ts,
│   │   │                              #  direct-rental-service.ts, admin-wallet-service.ts, …)
│   │   └── types/                     # rfq.ts, bid.ts, contract.ts, business.ts, auth.ts …
│   ├── features/
│   │   ├── auth/pages/                # login, register, verify-email, verify-phone, forgot-password
│   │   ├── onboarding/pages/           # business-onboarding, provider-onboarding
│   │   ├── business/pages/            # dashboard, rfq, contracts, wallet, direct-rental, profile, notifications
│   │   ├── provider/pages/             # dashboard, marketplace, bids, fleet, contracts, wallet, direct-rental, profile, notifications
│   │   └── admin/pages/                # dashboard, operations, verifications, users, wallets, settlements, master-data, notifications
│   ├── shared/
│   │   ├── components/
│   │   │   ├── auth/                  # ProtectedRoute, SessionExpiredDialog
│   │   │   ├── data/                  # DataTable, EmptyState, LoadingSkeleton, StatCard, StatusBadge
│   │   │   ├── forms/                 # FormField, ValidatedInput, FileUpload, OTPInput
│   │   │   ├── layout/, business/ (SplitAwardDialog), contracts/, wallet/, direct-rental/,
│   │   │   │                         #  onboarding/, profile/, brand/
│   │   ├── constants/                 # ROUTES and other app-wide constants
│   │   ├── lib/
│   │   │   ├── api-client.ts          # Axios wrapper — withCredentials, ProblemDetails mapping
│   │   │   ├── query-client.ts        # QueryClient defaults
│   │   │   ├── validation.ts          # Ethiopian phone/TIN/National ID validators
│   │   │   └── firebase-messaging.ts
│   │   └── types/
│   ├── stores/
│   │   ├── auth-store.ts              # useAuthStore — user + isAuthenticated only, persisted
│   │   ├── notification-store.ts      # useNotificationStore — SignalR hub lifecycle
│   │   └── direct-rental-store.ts     # Direct Rental cart/browse UI state (NOT "ui-store.ts")
│   ├── components/ui/                 # shadcn/ui primitives (button, dialog, toast, tooltip, …)
│   └── pages/, hooks/, lib/utils.ts   # a handful of top-level public pages + generic hooks/cn()
├── .env, .env.local
├── index.html
├── package.json                       # npm — not pnpm
├── tsconfig.json
├── vite.config.ts                     # dev proxy for /api, /web, /hubs (WS); SWC React plugin
├── tailwind.config.ts                 # .ts, not .js
├── eslint.config.js                   # flat ESLint config, not a legacy .eslintrc
└── README.md
```

There is no `src/styles/` folder and no separate `src/app/routes/index.tsx` in this codebase — both were part of the original prompt's proposed structure but were never built that way. Feature/business code lives under `src/features/`, `src/core/`, and `src/shared/`; `src/components/` and `src/lib/utils.ts` (outside `src/shared/`) are original shadcn-CLI scaffolding locations, harmless leftovers, not a parallel architecture.

---

## 🏗️ Architecture Patterns

### Component Architecture
The original prompt's formal **Atomic Design** taxonomy (Atoms/Molecules/Organisms/Templates/Pages) is not an enforced or documented convention in this codebase — components are pragmatic, typed function components grouped by feature/domain, not classified into a published atomic hierarchy. In practice, three informal tiers exist and are useful shorthand:
- **Primitives** — `src/components/ui/` (shadcn/ui-generated Radix wrappers: Button, Input, Badge, Dialog).
- **Composed shared components** — `src/shared/components/` (`DataTable`, `EmptyState`, `SplitAwardDialog`, `StatusBadge`, etc.) — domain-aware, reused across portals.
- **Pages** — `src/features/{portal}/pages/{feature}/` — compose the above, co-located with their own hooks and sub-components.

### File Naming Conventions (as actually used)
- **Components:** PascalCase (e.g., `SplitAwardDialog.tsx`, `RfqListPage.tsx`)
- **Hooks:** camelCase with `use` prefix (e.g., `useRFQs.ts`)
- **Services:** kebab-case with `-service` suffix, plain objects (e.g., `rfq-service.ts`, `direct-rental-service.ts`)
- **Types:** camelCase file, PascalCase exported type (e.g., `rfq.ts` exporting `RFQ`)
- **Stores:** kebab-case with `-store` suffix (e.g., `auth-store.ts`, `direct-rental-store.ts`)

### Component Structure (real shape)
```typescript
// Example: a shared component, e.g. src/shared/components/data/StatusBadge.tsx
import { FC } from 'react';
import { cn } from '@/lib/utils';

interface StatusBadgeProps {
  status: string;
  className?: string;
}

export const StatusBadge: FC<StatusBadgeProps> = ({ status, className }) => {
  return <span className={cn('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium', className)}>{status}</span>;
};
```

### Routing Structure (real shape — one flat table, not a separate router file)
```tsx
// src/App.tsx — the entire route table lives here, not in src/app/routes/index.tsx
<BrowserRouter>
  <SessionExpiredDialog />
  <Routes>
    <Route element={<PublicLayout />}>
      <Route path={ROUTES.LOGIN} element={<LoginPage />} />
      <Route path={ROUTES.REGISTER} element={<RegisterPage />} />
    </Route>

    <Route
      path={ROUTES.BUSINESS.RFQS}
      element={
        <ProtectedRoute allowedRoles={['business']}>
          <BusinessLayout />
        </ProtectedRoute>
      }
    >
      {/* nested business routes */}
    </Route>

    {/* Provider and Admin route groups, same pattern */}
  </Routes>
</BrowserRouter>
```
All page components are imported eagerly at the top of `App.tsx` — there is no route-level `React.lazy`/`Suspense` code-splitting per page in this app today (see §10, Performance).

---

## 🎨 Component Library (real components, `src/components/ui/` + `src/shared/components/`)

### UI Primitives (shadcn/ui over Radix UI — real, installed set per `package.json`)
Button, Input, Select, Checkbox, RadioGroup, Switch, Tabs, Accordion, AlertDialog, Dialog, Sheet, Popover, HoverCard, DropdownMenu, ContextMenu, Menubar, NavigationMenu, Toast (Radix) + Sonner (toast library), Tooltip, Progress, Slider, Separator, ScrollArea, Avatar, Badge, Card, Skeleton, Command (`cmdk`), Carousel (`embla-carousel-react`), resizable panels (`react-resizable-panels`), drawer (`vaul`).

### Form Components (real, `src/shared/components/forms/`)
- **FormField** — label + input + error wrapper, composed with shadcn `Form`.
- **ValidatedInput** — Zod-aware input wired to React Hook Form.
- **FileUpload** — document/photo upload (used across onboarding, vehicle registration, delivery evidence).
- **OTPInput** — 6-digit code entry (`input-otp`), used for email/phone verification, contract e-signature OTP, and delivery/return OTP — the **same input component**, but three distinct backend OTP flows behind it (verification OTP, contract e-signature OTP, delivery/return OTP are not interchangeable).
- **DatePicker** — `react-day-picker`-based date/date-range selection.

### Data Display Components (real, `src/shared/components/data/`)
- **DataTable** — sortable table with loading/empty states baked in.
- **EmptyState** — icon + title + description + optional action.
- **LoadingSkeleton** — row-count-configurable skeleton loader.
- **StatCard** — dashboard metric tile (title, value, trend, icon).
- **StatusBadge** — domain-status-to-semantic-color mapping (RFQ/bid/contract/wallet statuses).

### Layout Components (`src/app/layouts/`, `src/shared/components/layout/`)
`PublicLayout`, `BusinessLayout`, `ProviderLayout`, `AdminLayout` — each wraps a persistent dark sidebar + light header around `<Outlet />`.

### Domain-Specific Components (real, worth knowing by name)
`SplitAwardDialog` (multi-provider per-line-item award — `shared/components/business/`), `ExtendContractDialog`, `AwardVehicleAssignmentPanel`, `ReturnChecklistPage`/`VerificationChecklist`, `SegmentCapacityMeter`/`FleetCapacityConflictSheet` (fleet-capacity conflict UI), `SessionExpiredDialog` (`shared/components/auth/`).

There is no separate `TrustScoreGauge`/`TierBadge` component confirmed in the shared component set at this pass — trust/tier values are rendered inline per-page where they appear (e.g. provider dashboard stat cards), not through one shared gauge component; verify against `src/shared/components/` before assuming one exists.

---

## 🔄 State Management

### Zustand Stores (real shape — 3 stores, not 3 including a `ui-store`)

**Auth Store** (`src/stores/auth-store.ts`, real shape):
```typescript
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

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
There is **no `refreshToken` method** on this store — auth is `httpOnly` session cookies, refreshed transparently by the backend/cookie lifecycle, not a client-driven token-refresh call. The original prompt's `refreshToken: () => Promise<void>` on the store's interface does not exist in the real implementation.

**Notification Store** (`src/stores/notification-store.ts`):
- Manages the SignalR hub connection lifecycle (start on login, stop on logout) against `/hubs/notifications`.
- Tracks unread count and in-app notification list.
- Real-time updates arrive via **SignalR**, not a raw `WebSocket`/`ws://` connection as the original prompt's `.env` example implied (`VITE_WS_URL=ws://...` does not correspond to anything the SignalR client uses).

**Direct Rental Store** (`src/stores/direct-rental-store.ts`) — the store this document's prior version omitted entirely: cart/browse client-only UI state for the Direct Rental feature. Not a cache of server data — cart *contents* round-trip through `direct-rental-service.ts` and React Query once submitted.

### React Query Setup (real defaults, `src/shared/lib/query-client.ts`)
```typescript
import { QueryClient } from '@tanstack/react-query';

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,   // 5 minutes
      gcTime: 10 * 60 * 1000,     // 10 minutes (React Query 5's renamed cacheTime)
      retry: 3,
      refetchOnWindowFocus: false,
    },
    mutations: {
      retry: 1,
    },
  },
});
```

**Custom Hooks Pattern** (real shape, co-located in the feature folder — not a top-level `hooks/useRFQs.ts`):
```typescript
// features/business/pages/rfq/hooks/useRFQs.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { rfqService } from '@/core/services/rfq-service';

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

---

## ❌ Error Handling

### API Error Handling (real shape, `src/shared/lib/api-client.ts`)
The real interceptor does more than the original prompt's simple 401/403 branch — it maps RFC 7807 ProblemDetails responses to `Error` objects and guards against double-firing the logout flow:
```typescript
// Simplified from the real src/shared/lib/api-client.ts
class ApiClient {
  private client: AxiosInstance;
  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      timeout: 30000,
      withCredentials: true,           // httpOnly session cookies — no Authorization header
      headers: { 'Content-Type': 'application/json' },
    });
    this.setupInterceptors();
  }
  private setupInterceptors() {
    this.client.interceptors.response.use(
      (response) => response,
      (error) => {
        if (error.response?.status === 401 && !sessionExpiredHandlingInProgress) {
          // logs out (except admins on /web/* calls) and surfaces SessionExpiredDialog
        }
        // ProblemDetails (RFC 7807) body -> mapped to a thrown Error with the real message
        return Promise.reject(mapToError(error));
      }
    );
  }
}
export const apiClient = new ApiClient();
```
The original prompt's plain `axios.create({ baseURL: import.meta.env.VITE_API_BASE_URL })` with a bare 401/403 `toast.error` branch is a simplification that skips cookie auth (`withCredentials`), ProblemDetails mapping, and the re-entrancy guard — all real and load-bearing in the shipped app.

### Form Error Handling (real pattern — unchanged from the original prompt, this part was accurate)
```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

const rfqSchema = z.object({
  title: z.string().min(5, 'Title must be at least 5 characters'),
  lineItems: z.array(
    z.object({
      vehicleType: z.enum(['SEDAN', 'SUV', 'VAN', 'TRUCK']),
      quantity: z.coerce.number().int().positive(),
    })
  ).min(1, 'At least one line item is required'),
});

export const CreateRFQForm = () => {
  const { register, handleSubmit, formState: { errors } } = useForm({
    resolver: zodResolver(rfqSchema),
  });
  // ...
};
```
Note the corrected schema shape: an RFQ is header fields **plus a `lineItems` array** — the original prompt's flat single-vehicle-type schema does not reflect the real header + `RFQLineItem[]` model.

### Error Boundaries
**`react-error-boundary` is not an installed dependency in this repo** — the original prompt's example assumed it was. There is no confirmed route-level or app-level error-boundary component wrapping `<RouterProvider>`/`<BrowserRouter>` in the current codebase; each page handles its own React Query error state inline (`isError`/`error` from the query result). If a global error boundary is wanted, it needs to be added as new scope — either via `react-error-boundary` or a hand-rolled `componentDidCatch` boundary — not assumed to exist.

---

## 📱 Responsive Design

### Breakpoints (Tailwind — verified against `tailwind.config.ts`)
`tailwind.config.ts` does **not** override the `screens` key — Tailwind's defaults apply as-is; the only breakpoint-related customization is the `container.screens['2xl']` max-width:
```typescript
// tailwind.config.ts (real, relevant excerpt)
theme: {
  container: {
    center: true,
    padding: "2rem",
    screens: { "2xl": "1400px" },
  },
  // screens (sm/md/lg/xl/2xl breakpoints themselves) are NOT customized — Tailwind defaults:
  // sm 640px · md 768px · lg 1024px · xl 1280px · 2xl 1536px
}
```

### Mobile Adaptations
- **Sidebar:** collapses to an off-canvas pattern on mobile.
- **Tables:** wide tables scroll horizontally within their own container in most places — a full per-screen "always converts to card view on mobile" guarantee, as the original prompt claimed, is not confirmed across every table in the app; verify per screen.
- **Modals:** Radix `Dialog`/`Sheet` primitives handle mobile-appropriate sizing/behavior out of the box.
- **Touch targets:** shadcn `Button` default sizing meets common touch-target guidance; verify custom icon-only buttons independently.

### Example Responsive Component (real pattern)
```tsx
export const BusinessDashboard = () => {
  const { data: stats } = useDashboardStats();
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <StatCard title="Active RFQs" value={stats?.activeRfqs ?? 0} icon={<FileTextIcon />} />
      <StatCard title="Ongoing Contracts" value={stats?.activeContracts ?? 0} icon={<BriefcaseIcon />} />
      <StatCard title="Wallet Balance" value={formatCurrency(stats?.walletBalance)} icon={<WalletIcon />} />
    </div>
  );
};
```

---

## ♿ Accessibility

### WCAG 2.1 AA — target, not a verified audit result
This section states the app's accessibility *intent*; it has not been independently re-audited as part of this rewrite (that would require a dedicated accessibility pass, out of scope here):
- **Keyboard Navigation:** Radix primitives (which back nearly every interactive shadcn component) ship keyboard interaction patterns by default.
- **Screen Readers:** icon-only buttons should carry `aria-label` — enforce this in review, it is not automatically guaranteed by shadcn scaffolding alone.
- **Color Contrast:** the design-token pairs in `src/index.css` (e.g. `--primary`/`--primary-foreground`) were chosen with AA contrast in mind in both light and dark themes — see `UI_System_Design_Guidelines.md` for the full token table.
- **Focus Management:** shadcn `Button`/`Input` include `focus-visible:ring-2 focus-visible:ring-ring` by default — use the `ring` token, not a hardcoded `focus:ring-blue-500` as the original prompt's example showed.

### Implementation Examples (corrected to use real tokens)
```tsx
// Accessible Button — use the ring token, not a hardcoded blue
<Button aria-label="Create new RFQ">Create RFQ</Button>

// Accessible Form Field (shadcn Form + React Hook Form)
<FormField label="RFQ Title" error={errors.title?.message}>
  <Input id="title" aria-invalid={!!errors.title} {...register('title')} />
</FormField>
```

---

## ⚡ Performance Optimization

### Code Splitting (corrected — real behavior differs from the original prompt's claim)
The original prompt described route-level `React.lazy`/`Suspense` for each portal's dashboard. **That is not how the real app is built.** Every page component in `src/App.tsx` is imported eagerly at the top of the file — the **only** `lazy()` usage in the app is React Query Devtools, gated behind `import.meta.env.DEV` so it is fully excluded from production bundles:
```typescript
// src/App.tsx — the real (and only) lazy-loading in this app
const ReactQueryDevtools = import.meta.env.DEV
  ? lazy(() => import('@tanstack/react-query-devtools').then((m) => ({ default: m.ReactQueryDevtools })))
  : () => null;
```
Bundle-size management instead happens at the **build-chunking** level via Vite's `manualChunks` (see §11) — `vendor` (react/react-dom/react-router-dom), `ui` (a few Radix packages), `charts` (recharts) — not via per-route dynamic imports. If per-route code-splitting is wanted for a specific heavy page, it would be new work, not something already in place.

### Image Optimization
There is no confirmed custom `<Image>` wrapper component with built-in lazy-loading/sizing in `src/shared/components/` at this pass — the original prompt's `Image` component example is illustrative, not verified as existing. Use native `<img loading="lazy">` with explicit `width`/`height` until/unless a shared component is added.

### Memoization
`useMemo`/`useCallback` are ordinary React patterns, used where needed in list-filtering or callback-stability scenarios — no blanket project-wide policy on when to memoize is documented in code; use them where profiling shows benefit, not everywhere by default.

---

## 🚀 Deployment & Build

### Environment Variables (real resolution order, `vite.config.ts`)
Backend URL resolution order is: `BACKEND_URL` env (Docker runtime) → `VITE_BACKEND_URL` → a mode-specific default. Each Vite `--mode` (`local`, `development`, `staging`, `production`) points at a different `anqelbacarrental.com` host (or `localhost:5207` for local dev) — there is no single static `.env.local` value that covers every environment as the original prompt implied:
```bash
# .env.local (local dev only — other modes resolve their backend URL differently, see vite.config.ts)
VITE_BACKEND_URL=http://localhost:5207
```
Real-time transport is **SignalR** against `/hubs/notifications` (proxied by the dev server), not a raw `ws://` URL — the original prompt's `VITE_WS_URL=ws://localhost:5207/hub` variable does not correspond to anything the app actually reads.

### Build Configuration (real shape, `vite.config.ts`)
```typescript
// vite.config.ts (real, relevant excerpt)
export default defineConfig(({ mode }) => ({
  plugins: [
    react(),                              // @vitejs/plugin-react-swc, not @vitejs/plugin-react
    mode === 'development' && componentTagger(), // lovable-tagger — dev-only, Lovable-origin leftover
  ].filter(Boolean),
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
    dedupe: ['react', 'react-dom'],       // forces a single React instance — fixes a Radix
                                           // TooltipProvider "useRef of null" bug; keep this
  },
  server: {
    proxy: {
      '/api': { target: backendUrl, changeOrigin: true },
      '/web': { target: backendUrl, changeOrigin: true },
      '/hubs': { target: backendUrl, ws: true, changeOrigin: true },
    },
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom', 'react-router-dom'],
          ui: [/* a handful of @radix-ui/react-* packages */],
          charts: ['recharts'],
        },
      },
    },
  },
}));
```
The original prompt's plugin (`@vitejs/plugin-react`, Babel-based) is not what's installed — the real project uses the SWC variant (`@vitejs/plugin-react-swc`) for faster builds.

### Build Scripts (real, `package.json`)
```json
{
  "scripts": {
    "dev": "vite",
    "dev:local": "vite --mode localdev",
    "build": "vite build",
    "build:local": "vite build --mode local",
    "build:dev": "vite build --mode development",
    "build:staging": "vite build --mode staging",
    "build:production": "vite build --mode production",
    "lint": "eslint .",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest",
    "docker:local": "docker-compose --profile local up --build"
  }
}
```
Note the real `build` script is `vite build` directly — there is **no `tsc &&` type-check step chained in front of it** as the original prompt showed; type errors surface via `npm run lint`/IDE/CI separately, not as a build-blocking `tsc` pass in the `build` script itself. Multiple Docker Compose profiles (`local`/`dev`/`staging`/`production`) exist alongside the plain npm scripts.

---

## 📚 Related Documentation

For detailed implementation guides in this same directory, refer to:

1. **[AUTHENTICATION_GUIDE.md](./AUTHENTICATION_GUIDE.md)** — Auth flows and session management
2. **[ONBOARDING_GUIDE.md](./ONBOARDING_GUIDE.md)** — Onboarding wizards and document upload
3. **[BUSINESS_PORTAL_GUIDE.md](./BUSINESS_PORTAL_GUIDE.md)** — Business portal screens and flows
4. **[PROVIDER_PORTAL_GUIDE.md](./PROVIDER_PORTAL_GUIDE.md)** — Provider portal screens and flows
5. **[ADMIN_PORTAL_GUIDE.md](./ADMIN_PORTAL_GUIDE.md)** — Admin portal screens
6. **[API_INTEGRATION_SPEC.md](./API_INTEGRATION_SPEC.md)** — API client and endpoints
7. **[FORM_VALIDATIONS_SPEC.md](./FORM_VALIDATIONS_SPEC.md)** — Validation schemas
8. **[SEARCH_FILTER_PAGINATION.md](./SEARCH_FILTER_PAGINATION.md)** — Search, filter, and pagination
9. **[BUSINESS_LOGIC_IMPLEMENTATION.md](./BUSINESS_LOGIC_IMPLEMENTATION.md)** — Business rules implementation
10. **[USER_STORIES_COMPLETE.md](./USER_STORIES_COMPLETE.md)** — User stories with acceptance criteria
11. **[REALTIME_FEATURES.md](./REALTIME_FEATURES.md)** — SignalR/notification integration

And in the parent `MVP_MODULAR/` directory: **`06_FRONTEND_ARCHITECTURE.md`**, **`FRONTEND_AI_PROMPT.md`**, **`UI_DESIGN_GENERATION_PROMPT.md`**, **`UI_System_Design_Guidelines.md`** (all rewritten the same day as this document), plus `.agent/roles/frontend-developer.md` and `markdown-documentations/Frontend_Architecture_Guide.md` at the repo root level for the fullest architecture reference.

**Note:** the sibling documents in this folder listed above (2–5, 8–11) were not part of this rewrite pass and may still contain claims from the original Lovable-prompt era (e.g. package-manager choice, store count, router structure) inherited from when they were written alongside this guide — cross-check them against `package.json`/`src/` directly rather than assuming they were corrected as part of this task.

---

**END OF MAIN GUIDE**

*For feature-specific implementation details, refer to the related documentation files listed above — verify each independently against code before trusting version/structure claims not corrected in this pass.*
