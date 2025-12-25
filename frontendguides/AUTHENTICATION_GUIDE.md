# Authentication & Authorization Guide
## Movello Frontend - React Implementation

**Version:** 1.0  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)

---

## 📋 Table of Contents

1. [Authentication Flow](#authentication-flow)
2. [Login Implementation](#login-implementation)
3. [Registration Flows](#registration-flows)
4. [Password Management](#password-management)
5. [Session Management](#session-management)
6. [Route Protection](#route-protection)
7. [Role-Based Access Control](#role-based-access-control)

---

## 🔐 Authentication Flow

### Overview

The application uses **OAuth2/OIDC via Keycloak** with a **BFF (Backend for Frontend)** pattern. Authentication is handled through httpOnly cookies managed by the backend.

### Flow Diagram

```
User Login
  ↓
POST /web/login (BFF endpoint)
  ↓
BFF → Keycloak OAuth2
  ↓
BFF sets httpOnly cookie (refreshToken)
  ↓
BFF returns accessToken + user profile
  ↓
Frontend stores accessToken in memory (NOT localStorage)
  ↓
Frontend stores user in Zustand store
  ↓
Redirect to role-based dashboard
```

### API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/web/login` | POST | Authenticate user |
| `/web/logout` | POST | Terminate session |
| `/web/me` | GET | Get current user profile |
| `/web/refresh` | POST | Refresh access token |
| `/web/register` | POST | Create new user account |
| `/web/forgot-password` | POST | Request password reset |
| `/web/change-password` | POST | Change password |
| `/web/verify-email-manual` | POST | Verify email address |
| `/web/sessions` | GET | List active sessions |
| `/web/sessions/{id}` | DELETE | Terminate specific session |

---

## 🔑 Login Implementation

### Login Page Component

**File:** `src/features/auth/pages/LoginPage.tsx`

```typescript
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useAuthStore } from '@/stores/auth-store';
import { Button } from '@/shared/components/ui/button';
import { Input } from '@/shared/components/ui/input';
import { FormField } from '@/shared/components/forms/form-field';
import { authService } from '@/features/auth/services/auth-service';

const loginSchema = z.object({
  email: z.string().email('Invalid email address'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
  rememberMe: z.boolean().optional(),
});

type LoginFormData = z.infer<typeof loginSchema>;

export const LoginPage = () => {
  const navigate = useNavigate();
  const { login } = useAuthStore();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<LoginFormData>({
    resolver: zodResolver(loginSchema),
    defaultValues: {
      rememberMe: false,
    },
  });

  const onSubmit = async (data: LoginFormData) => {
    setIsLoading(true);
    setError(null);

    try {
      await login({
        email: data.email,
        password: data.password,
        rememberMe: data.rememberMe,
      });

      // Redirect based on role
      const user = useAuthStore.getState().user;
      if (user?.roles.includes('business-admin')) {
        navigate('/business/dashboard');
      } else if (user?.roles.includes('provider-admin')) {
        navigate('/provider/dashboard');
      } else if (user?.roles.includes('admin')) {
        navigate('/admin/dashboard');
      }
    } catch (err: any) {
      setError(err.message || 'Login failed. Please check your credentials.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-md w-full space-y-8 p-8 bg-white rounded-lg shadow">
        <h2 className="text-2xl font-bold text-center">Sign In</h2>
        
        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
          <FormField
            label="Email"
            error={errors.email?.message}
            {...register('email')}
          >
            <Input
              type="email"
              placeholder="Enter your email"
              autoComplete="email"
            />
          </FormField>

          <FormField
            label="Password"
            error={errors.password?.message}
            {...register('password')}
          >
            <Input
              type="password"
              placeholder="Enter your password"
              autoComplete="current-password"
            />
          </FormField>

          <div className="flex items-center justify-between">
            <label className="flex items-center">
              <input
                type="checkbox"
                {...register('rememberMe')}
                className="mr-2"
              />
              <span className="text-sm">Remember me</span>
            </label>
            <a
              href="/forgot-password"
              className="text-sm text-blue-600 hover:underline"
            >
              Forgot password?
            </a>
          </div>

          <Button
            type="submit"
            className="w-full"
            disabled={isLoading}
          >
            {isLoading ? 'Signing in...' : 'Sign In'}
          </Button>
        </form>

        <div className="text-center">
          <p className="text-sm text-gray-600">
            Don't have an account?{' '}
            <a href="/register" className="text-blue-600 hover:underline">
              Sign up
            </a>
          </p>
        </div>
      </div>
    </div>
  );
};
```

### Auth Service

**File:** `src/features/auth/services/auth-service.ts`

```typescript
import { apiClient } from '@/shared/lib/api-client';

export interface LoginCredentials {
  email: string;
  password: string;
  rememberMe?: boolean;
}

export interface User {
  id: string;
  email: string;
  roles: string[];
  businessId?: string;
  providerId?: string;
}

export interface LoginResponse {
  accessToken: string;
  user: User;
  expiresIn: number;
}

export const authService = {
  async login(credentials: LoginCredentials): Promise<LoginResponse> {
    const response = await apiClient.post<LoginResponse>('/web/login', credentials);
    return response.data;
  },

  async logout(): Promise<void> {
    await apiClient.post('/web/logout');
  },

  async getCurrentUser(): Promise<User> {
    const response = await apiClient.get<User>('/web/me');
    return response.data;
  },

  async refreshToken(): Promise<{ accessToken: string; expiresIn: number }> {
    const response = await apiClient.post<{ accessToken: string; expiresIn: number }>('/web/refresh');
    return response.data;
  },
};
```

### Auth Store

**File:** `src/stores/auth-store.ts`

```typescript
import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { authService, User, LoginCredentials } from '@/features/auth/services/auth-service';

interface AuthState {
  user: User | null;
  accessToken: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (credentials: LoginCredentials) => Promise<void>;
  logout: () => Promise<void>;
  refreshToken: () => Promise<void>;
  loadUser: () => Promise<void>;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      user: null,
      accessToken: null,
      isAuthenticated: false,
      isLoading: false,

      login: async (credentials) => {
        set({ isLoading: true });
        try {
          const response = await authService.login(credentials);
          set({
            user: response.user,
            accessToken: response.accessToken,
            isAuthenticated: true,
            isLoading: false,
          });
        } catch (error) {
          set({ isLoading: false });
          throw error;
        }
      },

      logout: async () => {
        try {
          await authService.logout();
        } finally {
          set({
            user: null,
            accessToken: null,
            isAuthenticated: false,
          });
        }
      },

      refreshToken: async () => {
        try {
          const response = await authService.refreshToken();
          set({ accessToken: response.accessToken });
        } catch (error) {
          // If refresh fails, logout user
          get().logout();
        }
      },

      loadUser: async () => {
        try {
          const user = await authService.getCurrentUser();
          set({ user, isAuthenticated: true });
        } catch (error) {
          set({ user: null, isAuthenticated: false });
        }
      },
    }),
    {
      name: 'auth-storage',
      partialize: (state) => ({
        user: state.user,
        accessToken: state.accessToken,
        isAuthenticated: state.isAuthenticated,
      }),
    }
  )
);
```

---

## 📝 Registration Flows

### Registration Page (Role Selection)

**File:** `src/features/auth/pages/RegisterPage.tsx`

```typescript
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card } from '@/shared/components/ui/card';
import { Button } from '@/shared/components/ui/button';

type UserRole = 'business' | 'provider';

export const RegisterPage = () => {
  const navigate = useNavigate();
  const [selectedRole, setSelectedRole] = useState<UserRole | null>(null);

  const handleRoleSelect = (role: UserRole) => {
    setSelectedRole(role);
    navigate(`/register/${role}`);
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-2xl w-full p-8">
        <h1 className="text-3xl font-bold text-center mb-8">
          Create Your Account
        </h1>
        <p className="text-center text-gray-600 mb-8">
          Select your account type to get started
        </p>

        <div className="grid md:grid-cols-2 gap-6">
          <Card
            className="p-6 cursor-pointer hover:border-blue-500 transition-colors"
            onClick={() => handleRoleSelect('business')}
          >
            <div className="text-center">
              <div className="text-4xl mb-4">🏢</div>
              <h3 className="text-xl font-semibold mb-2">I'm a Business</h3>
              <p className="text-gray-600 text-sm">
                Rent vehicles for your business operations
              </p>
            </div>
          </Card>

          <Card
            className="p-6 cursor-pointer hover:border-blue-500 transition-colors"
            onClick={() => handleRoleSelect('provider')}
          >
            <div className="text-center">
              <div className="text-4xl mb-4">🚗</div>
              <h3 className="text-xl font-semibold mb-2">I'm a Provider</h3>
              <p className="text-gray-600 text-sm">
                Offer your vehicles for rent and earn revenue
              </p>
            </div>
          </Card>
        </div>

        <div className="text-center mt-8">
          <p className="text-sm text-gray-600">
            Already have an account?{' '}
            <a href="/login" className="text-blue-600 hover:underline">
              Sign in
            </a>
          </p>
        </div>
      </div>
    </div>
  );
};
```

### Registration Service

**File:** `src/features/auth/services/auth-service.ts` (extended)

```typescript
export interface RegisterBusinessRequest {
  email: string;
  password: string;
  businessName: string;
  businessType: 'PLC' | 'NGO' | 'GOV';
  tinNumber: string;
  contactPerson: {
    fullName: string;
    email: string;
    phone: string;
  };
}

export interface RegisterProviderRequest {
  email: string;
  password: string;
  providerType: 'INDIVIDUAL' | 'AGENT' | 'COMPANY';
  name: string;
  tinNumber?: string;
  contactInfo: {
    email: string;
    phone: string;
  };
}

export const authService = {
  // ... existing methods

  async registerBusiness(data: RegisterBusinessRequest): Promise<void> {
    await apiClient.post('/web/register', {
      ...data,
      role: 'business',
    });
  },

  async registerProvider(data: RegisterProviderRequest): Promise<void> {
    await apiClient.post('/web/register', {
      ...data,
      role: 'provider',
    });
  },
};
```

---

## 🔒 Password Management

### Forgot Password Flow

**File:** `src/features/auth/pages/ForgotPasswordPage.tsx`

```typescript
import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { authService } from '@/features/auth/services/auth-service';

const forgotPasswordSchema = z.object({
  email: z.string().email('Invalid email address'),
});

export const ForgotPasswordPage = () => {
  const [isSubmitted, setIsSubmitted] = useState(false);
  const { register, handleSubmit, formState: { errors } } = useForm({
    resolver: zodResolver(forgotPasswordSchema),
  });

  const onSubmit = async (data: { email: string }) => {
    await authService.forgotPassword(data.email);
    setIsSubmitted(true);
  };

  if (isSubmitted) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <Card className="max-w-md w-full p-8">
          <div className="text-center">
            <div className="text-4xl mb-4">✅</div>
            <h2 className="text-2xl font-bold mb-4">Check Your Email</h2>
            <p className="text-gray-600">
              We've sent a password reset link to your email address.
              Please check your inbox and follow the instructions.
            </p>
          </div>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <Card className="max-w-md w-full p-8">
        <h2 className="text-2xl font-bold mb-6">Reset Password</h2>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <FormField
            label="Email"
            error={errors.email?.message}
            {...register('email')}
          >
            <Input type="email" placeholder="Enter your email" />
          </FormField>
          <Button type="submit" className="w-full">
            Send Reset Link
          </Button>
        </form>
      </Card>
    </div>
  );
};
```

### Change Password

**File:** `src/features/auth/components/ChangePasswordModal.tsx`

```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1, 'Current password is required'),
  newPassword: z.string()
    .min(8, 'Password must be at least 8 characters')
    .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
    .regex(/[0-9]/, 'Password must contain at least one number')
    .regex(/[^A-Za-z0-9]/, 'Password must contain at least one special character'),
  confirmPassword: z.string(),
}).refine((data) => data.newPassword === data.confirmPassword, {
  message: "Passwords don't match",
  path: ['confirmPassword'],
});

export const ChangePasswordModal = ({ isOpen, onClose }) => {
  const { register, handleSubmit, formState: { errors } } = useForm({
    resolver: zodResolver(changePasswordSchema),
  });

  const onSubmit = async (data) => {
    await authService.changePassword({
      currentPassword: data.currentPassword,
      newPassword: data.newPassword,
    });
    onClose();
  };

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Change Password</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <FormField
            label="Current Password"
            error={errors.currentPassword?.message}
            {...register('currentPassword')}
          >
            <Input type="password" />
          </FormField>
          <FormField
            label="New Password"
            error={errors.newPassword?.message}
            {...register('newPassword')}
          >
            <Input type="password" />
          </FormField>
          <FormField
            label="Confirm New Password"
            error={errors.confirmPassword?.message}
            {...register('confirmPassword')}
          >
            <Input type="password" />
          </FormField>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit">Change Password</Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
};
```

---

## 🔄 Session Management

### Session Timeout Handling

**File:** `src/features/auth/hooks/useSessionTimeout.ts`

```typescript
import { useEffect, useRef } from 'react';
import { useAuthStore } from '@/stores/auth-store';

const SESSION_TIMEOUT = 30 * 60 * 1000; // 30 minutes
const WARNING_TIME = 5 * 60 * 1000; // 5 minutes before timeout

export const useSessionTimeout = () => {
  const { refreshToken, logout } = useAuthStore();
  const timeoutRef = useRef<NodeJS.Timeout>();
  const warningRef = useRef<NodeJS.Timeout>();

  useEffect(() => {
    const resetTimeout = () => {
      // Clear existing timeouts
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
      if (warningRef.current) clearTimeout(warningRef.current);

      // Set warning timeout
      warningRef.current = setTimeout(() => {
        // Show warning dialog
        const extend = confirm(
          'Your session will expire in 5 minutes. Do you want to extend it?'
        );
        if (extend) {
          refreshToken();
          resetTimeout();
        }
      }, SESSION_TIMEOUT - WARNING_TIME);

      // Set logout timeout
      timeoutRef.current = setTimeout(() => {
        logout();
      }, SESSION_TIMEOUT);
    };

    // Track user activity
    const events = ['mousedown', 'keydown', 'scroll', 'touchstart'];
    events.forEach((event) => {
      document.addEventListener(event, resetTimeout, { passive: true });
    });

    resetTimeout();

    return () => {
      events.forEach((event) => {
        document.removeEventListener(event, resetTimeout);
      });
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
      if (warningRef.current) clearTimeout(warningRef.current);
    };
  }, [refreshToken, logout]);
};
```

### Multi-Device Session Management

**File:** `src/features/auth/components/SessionManager.tsx`

```typescript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { authService } from '@/features/auth/services/auth-service';

interface Session {
  id: string;
  device: string;
  location: string;
  lastActive: string;
  isCurrent: boolean;
}

export const SessionManager = () => {
  const queryClient = useQueryClient();

  const { data: sessions } = useQuery<Session[]>({
    queryKey: ['sessions'],
    queryFn: () => authService.getSessions(),
  });

  const terminateSession = useMutation({
    mutationFn: (sessionId: string) => authService.terminateSession(sessionId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] });
    },
  });

  const terminateAllSessions = useMutation({
    mutationFn: () => authService.terminateAllSessions(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] });
    },
  });

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h3 className="text-lg font-semibold">Active Sessions</h3>
        <Button
          variant="outline"
          onClick={() => terminateAllSessions.mutate()}
        >
          Terminate All Other Sessions
        </Button>
      </div>

      <div className="space-y-2">
        {sessions?.map((session) => (
          <Card key={session.id} className="p-4">
            <div className="flex justify-between items-center">
              <div>
                <p className="font-medium">{session.device}</p>
                <p className="text-sm text-gray-600">{session.location}</p>
                <p className="text-xs text-gray-500">
                  Last active: {new Date(session.lastActive).toLocaleString()}
                </p>
              </div>
              {session.isCurrent ? (
                <Badge>Current Session</Badge>
              ) : (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => terminateSession.mutate(session.id)}
                >
                  Terminate
                </Button>
              )}
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
};
```

---

## 🛡️ Route Protection

### Protected Route Component

**File:** `src/features/auth/components/ProtectedRoute.tsx`

```typescript
import { Navigate } from 'react-router-dom';
import { useAuthStore } from '@/stores/auth-store';

interface ProtectedRouteProps {
  children: React.ReactNode;
  requiredRoles?: string[];
}

export const ProtectedRoute = ({ children, requiredRoles }: ProtectedRouteProps) => {
  const { isAuthenticated, user } = useAuthStore();

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  if (requiredRoles && requiredRoles.length > 0) {
    const hasRole = requiredRoles.some((role) => user?.roles.includes(role));
    if (!hasRole) {
      return <Navigate to="/unauthorized" replace />;
    }
  }

  return <>{children}</>;
};
```

### Route Configuration

**File:** `src/app/routes/index.tsx` (extended)

```typescript
import { ProtectedRoute } from '@/features/auth/components/ProtectedRoute';

export const router = createBrowserRouter([
  // Public routes
  {
    path: '/',
    element: <PublicLayout />,
    children: [
      { path: 'login', element: <LoginPage /> },
      { path: 'register', element: <RegisterPage /> },
      { path: 'forgot-password', element: <ForgotPasswordPage /> },
    ],
  },
  // Business routes
  {
    path: '/business',
    element: (
      <ProtectedRoute requiredRoles={['business-admin', 'business-user']}>
        <BusinessLayout />
      </ProtectedRoute>
    ),
    children: [
      { path: 'dashboard', element: <BusinessDashboard /> },
      // ... more routes
    ],
  },
  // Provider routes
  {
    path: '/provider',
    element: (
      <ProtectedRoute requiredRoles={['provider-admin']}>
        <ProviderLayout />
      </ProtectedRoute>
    ),
    children: [
      { path: 'dashboard', element: <ProviderDashboard /> },
      // ... more routes
    ],
  },
  // Admin routes
  {
    path: '/admin',
    element: (
      <ProtectedRoute requiredRoles={['admin']}>
        <AdminLayout />
      </ProtectedRoute>
    ),
    children: [
      { path: 'dashboard', element: <AdminDashboard /> },
      // ... more routes
    ],
  },
]);
```

---

## 👥 Role-Based Access Control

### Permission Hook

**File:** `src/features/auth/hooks/usePermissions.ts`

```typescript
import { useAuthStore } from '@/stores/auth-store';

export const usePermissions = () => {
  const { user } = useAuthStore();

  const hasRole = (role: string): boolean => {
    return user?.roles.includes(role) ?? false;
  };

  const hasAnyRole = (roles: string[]): boolean => {
    return roles.some((role) => hasRole(role));
  };

  const hasAllRoles = (roles: string[]): boolean => {
    return roles.every((role) => hasRole(role));
  };

  const canAccess = (resource: string, action: string): boolean => {
    // Implement permission check logic
    // This can be extended based on your permission system
    return hasRole('admin') || hasRole(`${resource}-${action}`);
  };

  return {
    hasRole,
    hasAnyRole,
    hasAllRoles,
    canAccess,
    user,
  };
};
```

### Permission Guard Component

**File:** `src/features/auth/components/PermissionGuard.tsx`

```typescript
import { usePermissions } from '@/features/auth/hooks/usePermissions';

interface PermissionGuardProps {
  children: React.ReactNode;
  requiredRole?: string;
  requiredRoles?: string[];
  fallback?: React.ReactNode;
}

export const PermissionGuard = ({
  children,
  requiredRole,
  requiredRoles,
  fallback = null,
}: PermissionGuardProps) => {
  const { hasRole, hasAnyRole } = usePermissions();

  let hasPermission = true;

  if (requiredRole) {
    hasPermission = hasRole(requiredRole);
  } else if (requiredRoles) {
    hasPermission = hasAnyRole(requiredRoles);
  }

  return hasPermission ? <>{children}</> : <>{fallback}</>;
};
```

### Usage Example

```typescript
// In a component
<PermissionGuard requiredRole="admin">
  <AdminButton />
</PermissionGuard>

<PermissionGuard
  requiredRoles={['business-admin', 'admin']}
  fallback={<div>You don't have permission</div>}
>
  <CreateRFQButton />
</PermissionGuard>
```

---

## ✅ Validation Rules

### Email Validation
- Must be valid email format
- Must be unique in system (async check)

### Password Validation
- Minimum 8 characters
- At least one uppercase letter
- At least one number
- At least one special character

### TIN Validation (Business)
- Exactly 10 digits
- Must be unique in system (async check)
- Format: `^[0-9]{10}$`

---

## 🧪 Testing Scenarios

### Login Tests
- ✅ Successful login with valid credentials
- ✅ Failed login with invalid credentials
- ✅ Failed login with non-existent email
- ✅ Role-based redirect after login
- ✅ Remember me functionality
- ✅ Session persistence

### Registration Tests
- ✅ Business registration with valid data
- ✅ Provider registration with valid data
- ✅ Registration with duplicate email
- ✅ Registration with invalid TIN
- ✅ Email verification flow

### Password Tests
- ✅ Forgot password with valid email
- ✅ Forgot password with invalid email
- ✅ Password reset with valid token
- ✅ Password reset with expired token
- ✅ Change password with correct current password
- ✅ Change password with incorrect current password

---

**END OF AUTHENTICATION GUIDE**

*For onboarding flows, see [ONBOARDING_GUIDE.md](./ONBOARDING_GUIDE.md)*

