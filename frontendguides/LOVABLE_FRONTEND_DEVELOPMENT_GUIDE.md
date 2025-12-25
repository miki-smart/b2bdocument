# Lovable Frontend Development Guide
## Movello B2B Mobility Marketplace - React + Vite + TypeScript

**Version:** 1.0  
**Date:** December 2025  
**Target Platform:** Lovable (React + Vite + Tailwind CSS + TypeScript)  
**Backend API:** .NET 9 Modular Monolith  
**Base URL:** `http://localhost:5207/api`

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
This guide provides complete specifications for developing the Movello B2B Mobility Marketplace frontend using React, Vite, Tailwind CSS, and TypeScript on the Lovable platform.

### Application Structure
The application consists of **three distinct portals**:

1. **Business Portal** - For businesses seeking vehicle rentals
2. **Provider Portal** - For vehicle rental providers
3. **Admin Portal** - For platform administrators

### Key Features
- Multi-step onboarding wizards with document upload
- RFQ creation and blind bidding system
- Contract management and vehicle assignment
- Wallet management with escrow locking
- Real-time notifications via WebSocket/SignalR
- OTP-based delivery verification
- Trust score and tier system
- KYC/KYB verification workflows

---

## 🛠️ Technology Stack

### Core Technologies
```json
{
  "framework": "React 18.2+",
  "buildTool": "Vite 5.0+",
  "language": "TypeScript 5.0+",
  "styling": "Tailwind CSS 3.4+",
  "packageManager": "npm or pnpm"
}
```

### State Management
```json
{
  "globalState": "Zustand",
  "serverState": "TanStack Query (React Query) v5",
  "formState": "React Hook Form",
  "validation": "Zod"
}
```

### UI Components
```json
{
  "componentLibrary": "Shadcn/UI (Radix UI Primitives)",
  "icons": "Lucide React",
  "animations": "Framer Motion",
  "charts": "Recharts",
  "datePicker": "React Day Picker"
}
```

### Development Tools
```json
{
  "linting": "ESLint + Prettier",
  "typeChecking": "TypeScript strict mode",
  "testing": "Vitest + React Testing Library",
  "e2eTesting": "Playwright (optional)"
}
```

---

## 📁 Project Structure

```
movello-frontend/
├── public/
│   ├── favicon.ico
│   └── assets/
├── src/
│   ├── app/
│   │   ├── layouts/
│   │   │   ├── PublicLayout.tsx
│   │   │   ├── BusinessLayout.tsx
│   │   │   ├── ProviderLayout.tsx
│   │   │   └── AdminLayout.tsx
│   │   ├── routes/
│   │   │   └── index.tsx
│   │   └── App.tsx
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── components/
│   │   │   ├── pages/
│   │   │   ├── hooks/
│   │   │   ├── services/
│   │   │   └── types/
│   │   ├── business/
│   │   │   ├── rfq/
│   │   │   ├── contracts/
│   │   │   ├── wallet/
│   │   │   └── dashboard/
│   │   ├── provider/
│   │   │   ├── marketplace/
│   │   │   ├── fleet/
│   │   │   ├── delivery/
│   │   │   └── wallet/
│   │   └── admin/
│   │       ├── verifications/
│   │       ├── users/
│   │       └── transactions/
│   │
│   ├── shared/
│   │   ├── components/
│   │   │   ├── ui/          # Shadcn components
│   │   │   ├── forms/       # Form components
│   │   │   ├── data/        # Table, Pagination, etc.
│   │   │   └── layout/      # Header, Sidebar, etc.
│   │   ├── hooks/
│   │   ├── utils/
│   │   ├── lib/
│   │   │   ├── api-client.ts
│   │   │   ├── query-client.ts
│   │   │   └── utils.ts
│   │   └── types/
│   │
│   ├── stores/
│   │   ├── auth-store.ts
│   │   ├── notification-store.ts
│   │   └── ui-store.ts
│   │
│   ├── styles/
│   │   ├── globals.css
│   │   └── tailwind.css
│   │
│   └── main.tsx
│
├── .env
├── .env.local
├── .gitignore
├── index.html
├── package.json
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.js
└── README.md
```

---

## 🏗️ Architecture Patterns

### Component Architecture

We follow **Atomic Design** principles:

- **Atoms**: Basic UI elements (Button, Input, Badge)
- **Molecules**: Simple combinations (FormField, SearchBar)
- **Organisms**: Complex components (DataTable, RFQCard)
- **Templates**: Page layouts
- **Pages**: Complete screens

### File Naming Conventions

- **Components**: PascalCase (e.g., `RFQCard.tsx`)
- **Hooks**: camelCase with `use` prefix (e.g., `useRFQs.ts`)
- **Utils**: camelCase (e.g., `formatCurrency.ts`)
- **Types**: PascalCase (e.g., `RFQ.ts`)
- **Stores**: kebab-case with `-store` suffix (e.g., `auth-store.ts`)

### Component Structure

```typescript
// Example: RFQCard.tsx
import { FC } from 'react';
import { RFQ } from '@/shared/types';
import { Badge } from '@/shared/components/ui/badge';
import { Card } from '@/shared/components/ui/card';

interface RFQCardProps {
  rfq: RFQ;
  onViewDetails: (id: string) => void;
}

export const RFQCard: FC<RFQCardProps> = ({ rfq, onViewDetails }) => {
  return (
    <Card>
      {/* Component implementation */}
    </Card>
  );
};
```

### Routing Structure

```typescript
// src/app/routes/index.tsx
import { createBrowserRouter } from 'react-router-dom';
import { PublicLayout } from '@/app/layouts/PublicLayout';
import { BusinessLayout } from '@/app/layouts/BusinessLayout';
import { ProviderLayout } from '@/app/layouts/ProviderLayout';
import { AdminLayout } from '@/app/layouts/AdminLayout';

export const router = createBrowserRouter([
  {
    path: '/',
    element: <PublicLayout />,
    children: [
      { path: 'login', element: <LoginPage /> },
      { path: 'register', element: <RegisterPage /> },
    ],
  },
  {
    path: '/business',
    element: <BusinessLayout />,
    children: [
      { path: 'dashboard', element: <BusinessDashboard /> },
      { path: 'rfqs', element: <RFQListPage /> },
      { path: 'rfqs/create', element: <CreateRFQPage /> },
      // ... more routes
    ],
  },
  // Provider and Admin routes...
]);
```

---

## 🎨 Component Library

### UI Primitives (Shadcn/UI)

We use Shadcn/UI components built on Radix UI:

- **Button**: Primary, Secondary, Danger, Ghost variants
- **Input**: Text, Number, Email, Password
- **Card**: Container for content sections
- **Modal/Dialog**: For confirmations and forms
- **Select**: Dropdown selections
- **Checkbox**: Multi-select options
- **Radio**: Single-select options
- **Badge**: Status indicators
- **Alert**: Error, success, warning messages
- **Skeleton**: Loading placeholders
- **Toast**: Notification messages

### Form Components

- **FormField**: Wrapper with label, input, and error
- **DatePicker**: Date selection with validation
- **FileUpload**: Drag-and-drop file upload
- **MultiSelect**: Tag-based multi-select
- **Stepper**: Multi-step form navigation

### Data Display Components

- **DataTable**: Sortable, filterable table
- **Pagination**: Page navigation controls
- **SearchBar**: Real-time search input
- **FilterPanel**: Collapsible filter sidebar
- **EmptyState**: No data placeholder
- **LoadingState**: Loading spinner/skeleton

### Layout Components

- **Header**: Top navigation bar
- **Sidebar**: Collapsible side navigation
- **PageHeader**: Page title with actions
- **ContentCard**: Main content container

### Status Components

- **StatusBadge**: Color-coded status indicators
- **ProgressBar**: Step progress indicator
- **TrustScoreGauge**: Circular trust score display
- **TierBadge**: Provider/Business tier display

---

## 🔄 State Management

### Zustand Stores

**Auth Store** (`stores/auth-store.ts`):
```typescript
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  login: (credentials: LoginCredentials) => Promise<void>;
  logout: () => void;
  refreshToken: () => Promise<void>;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      user: null,
      isAuthenticated: false,
      login: async (credentials) => {
        // Implementation
      },
      logout: () => {
        set({ user: null, isAuthenticated: false });
      },
    }),
    { name: 'auth-storage' }
  )
);
```

**Notification Store** (`stores/notification-store.ts`):
- Manages in-app notifications
- Unread count
- Real-time updates via WebSocket

### React Query Setup

**Query Client Configuration** (`lib/query-client.ts`):
```typescript
import { QueryClient } from '@tanstack/react-query';

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000, // 5 minutes
      gcTime: 10 * 60 * 1000, // 10 minutes (formerly cacheTime)
      retry: 3,
      refetchOnWindowFocus: false,
    },
    mutations: {
      retry: 1,
    },
  },
});
```

**Custom Hooks Pattern**:
```typescript
// hooks/useRFQs.ts
import { useQuery } from '@tanstack/react-query';
import { rfqService } from '@/features/business/rfq/services/rfq-service';

export const useRFQs = (filters: RFQFilters) => {
  return useQuery({
    queryKey: ['rfqs', filters],
    queryFn: () => rfqService.getRFQs(filters),
    staleTime: 5 * 60 * 1000,
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
```

---

## ❌ Error Handling

### API Error Handling

**Error Interceptor** (`lib/api-client.ts`):
```typescript
import axios from 'axios';
import { toast } from '@/shared/components/ui/toast';

const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL,
});

apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // Handle unauthorized
      useAuthStore.getState().logout();
    } else if (error.response?.status === 403) {
      toast.error('You do not have permission to perform this action');
    } else if (error.response?.data?.error) {
      toast.error(error.response.data.error.message);
    } else {
      toast.error('An unexpected error occurred');
    }
    return Promise.reject(error);
  }
);
```

### Form Error Handling

```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

const rfqSchema = z.object({
  title: z.string().min(5, 'Title must be at least 5 characters'),
  startDate: z.date().refine((date) => date >= addDays(new Date(), 3), {
    message: 'Start date must be at least 3 days from now',
  }),
});

export const CreateRFQForm = () => {
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm({
    resolver: zodResolver(rfqSchema),
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <FormField
        label="Title"
        error={errors.title?.message}
        {...register('title')}
      />
    </form>
  );
};
```

### Error Boundaries

```typescript
import { ErrorBoundary } from 'react-error-boundary';

function ErrorFallback({ error, resetErrorBoundary }) {
  return (
    <div role="alert">
      <h2>Something went wrong:</h2>
      <pre>{error.message}</pre>
      <button onClick={resetErrorBoundary}>Try again</button>
    </div>
  );
}

export const App = () => {
  return (
    <ErrorBoundary FallbackComponent={ErrorFallback}>
      <RouterProvider router={router} />
    </ErrorBoundary>
  );
};
```

---

## 📱 Responsive Design

### Breakpoints (Tailwind)

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      screens: {
        'sm': '640px',   // Mobile landscape
        'md': '768px',   // Tablet
        'lg': '1024px',  // Desktop
        'xl': '1280px',  // Large desktop
        '2xl': '1536px', // Extra large
      },
    },
  },
};
```

### Mobile Adaptations

- **Sidebar**: Collapsible hamburger menu on mobile
- **Tables**: Convert to card view on mobile
- **Multi-column layouts**: Stack vertically on mobile
- **Modals**: Full-screen on mobile
- **Touch targets**: Minimum 44x44px

### Example Responsive Component

```typescript
export const Dashboard = () => {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <StatCard title="Active RFQs" value={12} />
      <StatCard title="Contracts" value={5} />
      <StatCard title="Wallet Balance" value="150,000 ETB" />
      <StatCard title="Pending Bids" value={3} />
    </div>
  );
};
```

---

## ♿ Accessibility

### WCAG 2.1 AA Compliance

- **Keyboard Navigation**: All interactive elements accessible via keyboard
- **Screen Readers**: Proper ARIA labels and roles
- **Color Contrast**: Minimum 4.5:1 for text
- **Focus Management**: Visible focus indicators
- **Alt Text**: All images have descriptive alt text

### Implementation Examples

```typescript
// Accessible Button
<button
  type="button"
  aria-label="Create new RFQ"
  className="focus:outline-none focus:ring-2 focus:ring-blue-500"
>
  Create RFQ
</button>

// Accessible Form Field
<div>
  <label htmlFor="title" className="sr-only">
    RFQ Title
  </label>
  <input
    id="title"
    aria-describedby="title-error"
    aria-invalid={!!errors.title}
  />
  {errors.title && (
    <span id="title-error" role="alert" className="text-red-500">
      {errors.title.message}
    </span>
  )}
</div>
```

---

## ⚡ Performance Optimization

### Code Splitting

```typescript
// Lazy load routes
import { lazy, Suspense } from 'react';

const BusinessDashboard = lazy(() => import('@/features/business/dashboard'));
const ProviderDashboard = lazy(() => import('@/features/provider/dashboard'));

export const App = () => {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <Routes>
        <Route path="/business/dashboard" element={<BusinessDashboard />} />
      </Routes>
    </Suspense>
  );
};
```

### Image Optimization

```typescript
import { Image } from '@/shared/components/ui/image';

// Use optimized image component
<Image
  src="/vehicle-photo.jpg"
  alt="Vehicle front view"
  width={800}
  height={600}
  loading="lazy"
/>
```

### Memoization

```typescript
import { useMemo, useCallback } from 'react';

export const RFQList = ({ rfqs, filters }) => {
  const filteredRFQs = useMemo(() => {
    return rfqs.filter(rfq => {
      // Filter logic
    });
  }, [rfqs, filters]);

  const handleViewDetails = useCallback((id: string) => {
    navigate(`/business/rfqs/${id}`);
  }, []);

  return (
    // Component
  );
};
```

---

## 🚀 Deployment & Build

### Environment Variables

```bash
# .env.local
VITE_API_BASE_URL=http://localhost:5207/api
VITE_WS_URL=ws://localhost:5207/hub
VITE_ENVIRONMENT=development
```

### Build Configuration

```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom'],
          router: ['react-router-dom'],
          query: ['@tanstack/react-query'],
        },
      },
    },
  },
});
```

### Build Scripts

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "lint": "eslint . --ext ts,tsx --report-unused-disable-directives --max-warnings 0"
  }
}
```

---

## 📚 Related Documentation

For detailed implementation guides, refer to:

1. **[AUTHENTICATION_GUIDE.md](./AUTHENTICATION_GUIDE.md)** - Auth flows and session management
2. **[ONBOARDING_GUIDE.md](./ONBOARDING_GUIDE.md)** - Onboarding wizards and document upload
3. **[BUSINESS_PORTAL_GUIDE.md](./BUSINESS_PORTAL_GUIDE.md)** - Business portal screens and flows
4. **[PROVIDER_PORTAL_GUIDE.md](./PROVIDER_PORTAL_GUIDE.md)** - Provider portal screens and flows
5. **[ADMIN_PORTAL_GUIDE.md](./ADMIN_PORTAL_GUIDE.md)** - Admin portal screens
6. **[API_INTEGRATION_SPEC.md](./API_INTEGRATION_SPEC.md)** - API client and endpoints
7. **[FORM_VALIDATIONS_SPEC.md](./FORM_VALIDATIONS_SPEC.md)** - Validation schemas
8. **[SEARCH_FILTER_PAGINATION.md](./SEARCH_FILTER_PAGINATION.md)** - Search, filter, and pagination
9. **[BUSINESS_LOGIC_IMPLEMENTATION.md](./BUSINESS_LOGIC_IMPLEMENTATION.md)** - Business rules implementation
10. **[USER_STORIES_COMPLETE.md](./USER_STORIES_COMPLETE.md)** - All user stories with acceptance criteria
11. **[REALTIME_FEATURES.md](./REALTIME_FEATURES.md)** - WebSocket integration
12. **[TESTING_GUIDE.md](./TESTING_GUIDE.md)** - Testing requirements

---

**END OF MAIN GUIDE**

*For feature-specific implementation details, refer to the related documentation files listed above.*

