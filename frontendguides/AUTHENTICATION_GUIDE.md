# Authentication & Authorization Guide

## Anqelba Car Rental Frontend - React Implementation

**Version:** 2.0
**Last verified against code: 2026-07-23** — full rewrite. The v1.0 guide described in-memory access tokens, a `refreshToken()` call the frontend is expected to invoke, and a `requiredRoles` prop on `ProtectedRoute`. None of that matches the real code. This version was checked against `anqelbacarrental-marketplace-core/src/stores/auth-store.ts`, `src/core/services/auth-service.ts`, `src/shared/components/auth/ProtectedRoute.tsx`, `src/shared/lib/api-client.ts`, and the backend's `architecture/auth-service-microservice-spec.md` / `architecture/bff-backend-for-frontend-spec.md` (both rewritten 2026-07-23).
**Related:** [API_INTEGRATION_SPEC.md](./API_INTEGRATION_SPEC.md), [FORM_VALIDATIONS_SPEC.md](./FORM_VALIDATIONS_SPEC.md)

---

## Table of Contents

1. [Authentication Flow](#authentication-flow)
2. [Login Implementation](#login-implementation)
3. [Auth Store](#auth-store)
4. [Registration Flow](#registration-flow)
5. [Email / Phone Verification](#email--phone-verification)
6. [Password Reset (OTP-Based)](#password-reset-otp-based)
7. [Session Expiry Handling](#session-expiry-handling)
8. [Route Protection](#route-protection)
9. [Role-Based Access Control](#role-based-access-control)
10. [What NOT to Do](#what-not-to-do)

---

## Authentication Flow

### The real architecture, in one paragraph

There is **one** backend process (`Marketplace.API`, a .NET 9 modular monolith) — no separate Auth microservice, no separate BFF service, no API Gateway. Keycloak is the real identity provider, called directly by the backend. What the backend calls its "BFF" is `Infrastructure/Middleware/BffTokenRefreshMiddleware.cs` — in-process middleware, not a network hop — that silently refreshes an expiring access-token cookie on every `/api/*` request before it reaches a controller. The web frontend's job is dramatically simpler than a typical OAuth2/OIDC integration: **POST credentials, receive cookies, send cookies on every subsequent request, forever, until a 401 says otherwise.** Full backend-side detail: `architecture/auth-service-microservice-spec.md` §1, `architecture/bff-backend-for-frontend-spec.md` §1.

### What is explicitly NOT true (corrections vs. common assumptions)

- **No redirect to a Keycloak-hosted login page.** `LoginPage.tsx` is a normal in-app email/password form. Keycloak is only ever called server-side (Resource Owner Password Credentials grant), never via an Authorization Code redirect the browser participates in.
- **No access token in JS memory, ever.** Not in a variable, not in Zustand, not in `sessionStorage`. Tokens are `HttpOnly` cookies (`mov_access_token`, `mov_refresh_token`) the frontend cannot read even if it wanted to.
- **No frontend-initiated refresh call.** `authService.refreshToken()` still exists in `auth-service.ts` but is a deprecated no-op (`console.warn('refreshToken() called - BFF handles token refresh automatically')`). Refresh is entirely server-side, transparent, and happens on `/api/*` requests, not on a schedule the frontend manages.
- **This is the web-only pattern.** The Flutter mobile apps use `MobileAuthController`, which returns tokens **in the JSON response body** (comment in the backend code: "mobile clients cannot use httpOnly cookies") and are stored in Keychain/Keystore, sent as `Authorization: Bearer` headers. If you are writing code for `anqelbacarrental-marketplace-core`, that pattern is irrelevant — do not add a Bearer header here.

### Flow diagram (as implemented)

```
User submits email/password (LoginPage.tsx, Zod-validated)
  ↓
authService.login() → apiClient.webRequest('post', '/web/login', { username: email, password })
  ↓
Backend: AuthController → KeycloakAuthService.LoginAsync() → Keycloak direct grant
  ↓
Backend sets mov_access_token / mov_refresh_token as HttpOnly cookies on the response
  ↓
Frontend calls authService.getCurrentUser() → webRequest('get', '/web/me')
  ↓
Backend decodes the access-token cookie's `sub` claim, enriches from local user_accounts + Keycloak Admin API
  ↓
Frontend maps the response to a `User` object, attaches businessProfile/providerProfile
  (via GET /identity/businesses/me or /identity/providers/me)
  ↓
useAuthStore sets { user, isAuthenticated: true } — Zustand persists ONLY this to localStorage, never tokens
  ↓
getRedirectPathByRole(user) → verification gate → onboarding gate → role dashboard
```

On every later `/api/*` call, the backend's `BffTokenRefreshMiddleware` silently refreshes the cookie pair if the access token is expired or expiring within 2 minutes. The frontend never orchestrates this — it just keeps calling `apiClient` as normal. A `401` reaching the frontend means the refresh token is *also* expired; there is nothing left to retry client-side.

---

## Login Implementation

**File:** `src/features/auth/pages/login/LoginPage.tsx` (real, Zod schema shown in full):

```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useAuthStore, getRedirectPathByRole } from '@/stores/auth-store';

const loginSchema = z.object({
  email: z.string().email('Please enter a valid email address'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
  rememberMe: z.boolean().optional(),
});

type LoginFormValues = z.infer<typeof loginSchema>;

export const LoginPage: FC = () => {
  const { login, isLoading, clearError } = useAuthStore();
  const { register, handleSubmit, formState: { errors } } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { rememberMe: false },
  });

  const onSubmit = async (data: LoginFormValues) => {
    try {
      await login({ email: data.email, password: data.password });
      const user = useAuthStore.getState().user;
      const redirectPath = from || getRedirectPathByRole(user) || ROUTES.HOME;
      navigate(redirectPath, { replace: true });
    } catch (err: unknown) {
      // backend returns 403 + requiresVerification for unverified accounts (still logged in
      // via cookies!) rather than a plain 401 — the frontend redirects to the verify screen
      // instead of showing a generic error in that case. See real onSubmit for the full branch.
    }
  };
  // ...
};
```

**Real, notable detail:** an unverified account still gets its cookies set on login (per `architecture/auth-service-microservice-spec.md` §1.4: "tokens are still set so the client can complete verification without a second login"). The backend returns `403` with `requiresVerification: true` plus `isEmailVerified`/`isPhoneVerified` flags; `LoginPage.tsx` branches on this to redirect to `/verify-email` or `/verify-phone` rather than treating it as a failed login.

**Auth service** (`src/core/services/auth-service.ts`, real):

```typescript
export const authService = {
  async login(credentials: LoginRequest): Promise<ApiResponse<LoginResponse>> {
    // Backend expects { username, password } — frontend uses { email, password }
    const backendCredentials = { username: credentials.email, password: credentials.password };
    await apiClient.webRequest('post', '/web/login', backendCredentials); // sets cookies
    const userResponse = await authService.getCurrentUser();              // GET /web/me
    return { success: true, data: { user: userResponse.data } };
  },

  async getCurrentUser(): Promise<ApiResponse<User>> {
    const backendResponse = await apiClient.webRequest<BackendUserProfile>('get', '/web/me');
    // backendResponse.roles is an array like ["default-roles-marketplace-realm", "PROVIDER"] —
    // find the real role, don't just take roles[0]
    const role = backendResponse.roles.find(r => ['ADMIN','PROVIDER','BUSINESS'].includes(r.toUpperCase()))
      ?.toLowerCase() ?? 'business';
    const user: User = {
      id: backendResponse.id,
      email: backendResponse.email,
      role: role as 'business' | 'provider' | 'admin',
      isEmailVerified: backendResponse.isEmailVerified ?? backendResponse.emailVerified ?? false, // local DB wins over Keycloak flag
      isPhoneVerified: backendResponse.isPhoneVerified ?? false,
      profileComplete: backendResponse.profileComplete ?? false,
      // ...
    };
    // Attach role-specific profile (best-effort — 404 is expected for users mid-onboarding)
    if (user.role === 'business') { /* GET /identity/businesses/me */ }
    if (user.role === 'provider') { /* GET /identity/providers/me */ }
    return { success: true, data: user };
  },

  async logout(): Promise<void> {
    try { await apiClient.webRequest('post', '/web/logout', {}); }
    catch (error) { console.error('Logout error:', error); } // must not block client-side logout
  },

  /** @deprecated BFF handles token refresh automatically — do not call this. */
  async refreshToken(): Promise<void> {
    console.warn('refreshToken() called - BFF handles token refresh automatically');
  },
};
```

**Login/session endpoints actually called** (all under `/web/*`, via `apiClient.webRequest`):

| Endpoint | Method | Purpose |
|---|---|---|
| `/web/login` | POST | `{ username, password }` (mapped from frontend's `email`) — sets cookies |
| `/web/me` | GET | Current user profile; decodes access-token cookie server-side |
| `/web/logout` | POST | Best-effort; clears cookies regardless of outcome |
| `/web/register` | POST | Auto-login on success (cookies set) |
| `/web/verify-email-manual` | POST | `{ email, otpCode }` |
| `/web/verify-phone` | POST | `{ email, otpCode }` |
| `/web/resend-otp`, `/web/resend-phone-otp` | POST | |
| `/web/forgot-password` | POST | `{ email }` |
| `/web/verify-reset-otp` | POST | `{ email, otpCode }` → `{ isValid }` |
| `/web/reset-password-with-otp` | POST | `{ email, otpCode, newPassword }` |
| `/web/update-unverified-email` | POST | For accounts not yet email-verified |

There is no `/web/refresh` call the frontend makes, no `/web/sessions` multi-device UI in the current web app (session/device management exists in the **mobile** apps' profile sections, not on web), and no `PermissionGuard`/`usePermissions` hook layer in the codebase — role checks are done via `ProtectedRoute`'s `allowedRoles` and inline `user.role === '...'` checks, not a generic permission-resource-action system.

---

## Auth Store

**File:** `src/stores/auth-store.ts` (real, in full apart from comments trimmed):

```typescript
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
  sessionExpired: boolean;
  sessionExpiredHandlingInProgress: boolean;
  login: (credentials: LoginCredentials) => Promise<void>;
  register: (credentials: RegisterCredentials) => Promise<void>;
  logout: () => void;
  setUser: (user: User) => void;
  clearError: () => void;
  checkAuth: () => Promise<void>;
  setSessionExpired: (value: boolean) => void;
  setSessionExpiredHandlingInProgress: (value: boolean) => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      user: null,
      isAuthenticated: false,
      // ... isLoading, error, sessionExpired, sessionExpiredHandlingInProgress: false

      login: async (credentials) => {
        set({ isLoading: true, error: null });
        try {
          const response = await authService.login({ email: credentials.email, password: credentials.password });
          set({ user: response.data.user, isAuthenticated: true, isLoading: false, error: null });
          set({ sessionExpiredHandlingInProgress: false });
          useNotificationStore.getState().startHub(queryClient); // SignalR hub for real-time notifications
          useNotificationStore.getState().fetchSummary();
        } catch (error) {
          set({ isLoading: false, error: error instanceof Error ? error.message : 'Login failed. Please try again.' });
          throw error;
        }
      },

      logout: () => {
        authService.logout(); // fire-and-forget POST /web/logout
        useNotificationStore.getState().stopHub();
        set({ user: null, isAuthenticated: false, error: null });
      },

      checkAuth: async () => {
        try {
          const response = await authService.getCurrentUser(); // GET /web/me — relies on cookies
          set({ user: response.data, isAuthenticated: true });
          useNotificationStore.getState().startHub(queryClient);
        } catch {
          get().logout(); // request failed → not authenticated
        }
      },
    }),
    {
      name: AUTH_STORAGE_KEY,  // 'anqelbacarrental-auth'
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ user: state.user, isAuthenticated: state.isAuthenticated }), // NEVER tokens
    }
  )
);
```

**Critical point:** `partialize` persists only `user` and `isAuthenticated` to `localStorage` — never a token, because there is no token in this store at all. This is the entire reason `checkAuth()`/`/web/me` exists: on page reload, Zustand rehydrates a (possibly stale) `user` object from `localStorage`, but the app still needs a live `/web/me` call (cookie-authenticated) to confirm the session is actually still valid.

**Role-based redirect helper** (`getRedirectPathByRole`, same file, real):

```typescript
export const getRedirectPathByRole = (user: User | null): string => {
  if (!user) return '/login';
  if (user.role !== 'admin') {
    if (!user.isEmailVerified) return `/verify-email?email=${encodeURIComponent(user.email)}`;
    if (PHONE_VERIFICATION_REQUIRED && !user.isPhoneVerified) return `/verify-phone?email=...&phone=...`;
  }
  if (user.profileComplete === false) {
    switch (user.role) {
      case 'business': return '/business/onboarding';
      case 'provider': return '/provider/onboarding';
      default: return '/admin/dashboard'; // admin has no onboarding
    }
  }
  switch (user.role) {
    case 'business': return '/business/dashboard';
    case 'provider': return '/provider/dashboard';
    case 'admin': return '/admin/dashboard';
    default: return '/login';
  }
};
```

`PHONE_VERIFICATION_REQUIRED` is a build-time feature flag (`VITE_PHONE_VERIFICATION_REQUIRED`) mirroring a backend settings flag — phone verification is currently gated behind SMS provider readiness (`SMS_ENABLED`), not always-on.

---

## Registration Flow

Registration is a **single-form, role-selecting form** (`business` | `provider` chosen inline via radio-style cards), not a separate role-selection landing page followed by two different multi-step forms. Real schema, `src/features/auth/pages/register/RegisterPage.tsx`:

```typescript
const ethiopianPhoneRegex = /^\+251(9\d{8}|11\d{7})$/; // mobile (9xxxxxxxx) or landline (11xxxxxxx)

const registerSchema = z.object({
  firstName: z.string().trim().min(2).max(50),
  lastName: z.string().trim().min(2).max(50),
  email: z.string().trim().email().max(255),
  phoneNumber: z.string().trim().regex(ethiopianPhoneRegex, 'Phone must be Ethiopian format: +2519XXXXXXXX'),
  companyName: z.string().trim().min(2).max(100),
  password: z.string()
    .min(8, 'Password must be at least 8 characters')
    .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
    .regex(/[0-9]/, 'Password must contain at least one number')
    .regex(/[!@#$%^&*(),.?":{}|<>]/, 'Password must contain at least one special character'),
  confirmPassword: z.string(),
  acceptTerms: z.boolean().refine((val) => val === true, { message: 'You must accept the terms and conditions' }),
}).refine((data) => data.password === data.confirmPassword, {
  message: 'Passwords do not match',
  path: ['confirmPassword'],
});
```

Note: **no async TIN/email-uniqueness `refine()` in the registration form itself** — uniqueness is enforced server-side and surfaced as a `409`/`EMAIL_ALREADY_EXISTS` error after submit, not as an inline async Zod check. `authService.register()` translates a `409` (or an error code containing `EMAIL`) into `{ code: 'EMAIL_ALREADY_EXISTS' }` for the UI to display. Registration is followed by the separate **onboarding wizards** (`src/features/onboarding/pages/business-onboarding/`, `.../provider-onboarding/`) which collect business/provider-specific detail (TIN, address, documents) — registration itself only collects the account-level fields above plus `role` and `companyName`.

---

## Email / Phone Verification

Both use a 6-digit OTP entered in-app (`InputOTP` component) — **not** an email-link flow:

- Email: `POST /web/verify-email-manual` `{ email, otpCode }`, resend via `POST /web/resend-otp`.
- Phone: `POST /web/verify-phone` `{ email, otpCode }`, resend via `POST /web/resend-phone-otp`. Gated behind `PHONE_VERIFICATION_REQUIRED`.
- In local/dev environments, `DEV_OTP_CODE` (`src/shared/constants/index.ts`) pre-fills `"123456"` in the OTP input to speed up manual testing — it is empty string in any other `APP_ENV`.

`ProtectedRoute` (see below) enforces both gates for every non-admin authenticated route — a logged-in-but-unverified user is redirected to the relevant verify screen before reaching any dashboard route, regardless of how they arrived.

---

## Password Reset (OTP-Based)

**Not** a single-step "email me a link" flow — it's a 3-step in-app wizard (`src/features/auth/pages/forgot-password/ForgotPasswordPage.tsx`, real):

```typescript
type Step = 'email' | 'check-code' | 'reset';

const forgotPasswordSchema = z.object({
  email: z.string().trim().email('Please enter a valid email address').max(255),
});

const resetPasswordSchema = z.object({
  newPassword: z.string().min(8, 'Password must be at least 8 characters'),
  confirmPassword: z.string(),
}).refine((data) => data.newPassword === data.confirmPassword, {
  message: 'Passwords do not match',
  path: ['confirmPassword'],
});
```

Flow: `email` step calls `authService.forgotPassword(email)` (`POST /web/forgot-password`) → `check-code` step collects a 6-digit OTP and calls `authService.verifyResetOtp(email, otpCode)` (`POST /web/verify-reset-otp`) → `reset` step collects the new password and calls `authService.resetPasswordWithOtp(email, otpCode, newPassword)` (`POST /web/reset-password-with-otp`). A 60-second resend cooldown (`COOLDOWN_SECONDS`) gates the resend button between attempts. This is the same OTP-first pattern the business mobile app uses (`auth_check_email_screen.dart` → `auth_verify_reset_otp_screen.dart` → `auth_reset_password_screen.dart`) — treat the two as consistent, not the web-vs-mobile divergence some older docs describe.

There is a separate **change-password** flow (for an already-authenticated user changing their own password) that follows the same password-strength Zod rules but takes `currentPassword` instead of an OTP — see [FORM_VALIDATIONS_SPEC.md](./FORM_VALIDATIONS_SPEC.md).

---

## Session Expiry Handling

There is no client-side idle/inactivity timer (`useSessionTimeout` with `mousedown`/`keydown` listeners, as v1.0 described, does not exist in this codebase — session lifetime is entirely controlled by the backend's cookie expiry and refresh-token validity). What actually happens:

1. `apiClient`'s response interceptor catches a `401` on any `/api/*` call.
2. It reads `getAuthState()` (wired up from `auth-store.ts` via `setAuthStoreGetter`), and if a session-expiry handling isn't already in progress, calls `logout()` and sets `sessionExpired: true`.
3. `sessionExpiredHandlingInProgress` is a guard flag to stop concurrent in-flight requests from all independently triggering the same logout/redirect sequence.
4. `<SessionExpiredDialog />` (`src/shared/components/auth/SessionExpiredDialog.tsx`) is the UI that reacts to `sessionExpired` and prompts the user to log in again — it is not a "5 minutes left, extend your session?" warning dialog; by the time it shows, the refresh token is already expired and the session is unrecoverable client-side.
5. **Admin exemption:** the `webRequest` (`/web/*`) 401 handler explicitly skips force-logout when `authState.user?.role === 'admin'` — admins aren't kicked out of the console by an unrelated `/web/*` hiccup. This exemption does not apply to the main `/api/*` client.

---

## Route Protection

**File:** `src/shared/components/auth/ProtectedRoute.tsx` (real, in full):

```typescript
interface ProtectedRouteProps {
  children: ReactNode;
  allowedRoles?: UserRole[];   // NOTE: prop is `allowedRoles`, not `requiredRoles`
}

export const ProtectedRoute: FC<ProtectedRouteProps> = ({ children, allowedRoles }) => {
  const { isAuthenticated, user } = useAuthStore();
  const location = useLocation();

  if (!isAuthenticated) {
    return <Navigate to={ROUTES.LOGIN} state={{ from: location }} replace />;
  }

  if (user && user.role !== 'admin') {
    if (!user.isEmailVerified) {
      return <Navigate to={`${ROUTES.VERIFY_EMAIL}?email=${encodeURIComponent(user.email)}`} replace />;
    }
    if (!user.isPhoneVerified && PHONE_VERIFICATION_REQUIRED) {
      return <Navigate to={`${ROUTES.VERIFY_PHONE}?email=...&phone=...`} replace />;
    }
  }

  if (allowedRoles && user && !allowedRoles.includes(user.role)) {
    // Redirect to THAT user's own dashboard — never a generic "/unauthorized" page
    switch (user.role) {
      case 'business': return <Navigate to={ROUTES.BUSINESS.DASHBOARD} replace />;
      case 'provider': return <Navigate to={ROUTES.PROVIDER.DASHBOARD} replace />;
      case 'admin':    return <Navigate to={ROUTES.ADMIN.DASHBOARD} replace />;
      default:         return <Navigate to={ROUTES.LOGIN} replace />;
    }
  }

  return <>{children}</>;
};
```

**Route configuration** (`src/App.tsx`, real pattern — a single flat route tree, not per-portal routers):

```tsx
<Route path="/business/*" element={
  <ProtectedRoute allowedRoles={['business']}>
    <BusinessLayout />
  </ProtectedRoute>
}>
  {/* business routes */}
</Route>

<Route path="/provider/*" element={
  <ProtectedRoute allowedRoles={['provider']}>
    <ProviderLayout />
  </ProtectedRoute>
}>
  {/* provider routes */}
</Route>

<Route path="/admin/*" element={
  <ProtectedRoute allowedRoles={['admin']}>
    <AdminLayout />
  </ProtectedRoute>
}>
  {/* admin routes */}
</Route>
```

There is no `/unauthorized` route in the real app — a role mismatch always redirects to the *authenticated user's own* dashboard, not a generic error page. Do not build a `PermissionGuard`/`/unauthorized` pattern that doesn't exist; if a component needs to conditionally render for a role, check `user.role` directly from `useAuthStore()`.

---

## Role-Based Access Control

The real app has **three flat roles** — `'business' | 'provider' | 'admin'` — no separate `business-admin`/`business-user`/`provider-admin` sub-roles, and no generic `usePermissions()`/`hasRole()`/`canAccess(resource, action)` hook layer. Access control is:

1. **Route-level:** `ProtectedRoute`'s `allowedRoles` prop (defense in depth — the backend enforces roles independently via Keycloak-issued JWT claims on `[Authorize(Roles = "...")]` controllers; the frontend redirect is a UX convenience, not the security boundary).
2. **Component-level:** plain conditional rendering off `useAuthStore().user.role`, e.g. `{user.role === 'admin' && <AdminOnlyButton />}` — there is no `<PermissionGuard requiredRole="admin">` wrapper component in this codebase.
3. **Verification-gate-level:** the email/phone verification checks baked directly into `ProtectedRoute` (see above) rather than a separate guard component.

If a future feature needs more granular in-role permissions (e.g. a business sub-role that can create RFQs but not manage the wallet), that does not exist today — build it as a new field on `User`, not by inventing a Keycloak sub-role scheme without checking `architecture/auth-service-microservice-spec.md` first.

---

## What NOT to Do

Straight from `.agent/roles/frontend-developer.md`'s Red Flags table — these are review-blocking in this codebase:

| Pattern | Why it's wrong here |
|---|---|
| `localStorage.setItem('token', ...)` / any token in `localStorage`/`sessionStorage` | Auth is cookie-based; storing a token client-side is a security regression, not an optimization |
| `axios.defaults.headers.Authorization = 'Bearer ...'` | This header does nothing against this backend for the web app — cookies are the whole story |
| Calling `authService.refreshToken()` from application code | Deprecated no-op; refresh is entirely server-side via `BffTokenRefreshMiddleware` |
| A client-side idle/inactivity timer that calls `logout()` | Doesn't exist in the real app; session lifetime is cookie/refresh-token-driven, not JS-timer-driven |
| `requiredRoles` prop on `ProtectedRoute` | The real prop is `allowedRoles` |
| Redirecting a role mismatch to `/unauthorized` | Real behavior redirects to the user's own dashboard; there is no unauthorized page |
| `PermissionGuard`/`usePermissions().canAccess(resource, action)` | Does not exist; use `allowedRoles` on routes and direct `user.role` checks in components |
| Assuming the mobile Bearer-token pattern applies to web | Mobile and web use genuinely different auth transports — see Authentication Flow above |

---

**END OF AUTHENTICATION GUIDE**

*Backend detail: `architecture/auth-service-microservice-spec.md`, `architecture/bff-backend-for-frontend-spec.md`. Frontend conventions: `.agent/roles/frontend-developer.md`, `markdown-documentations/Frontend_Architecture_Guide.md`. Drift history: `project-docs/18_Implementation_Coverage_Audit.md` §8, §10.5.*
