# Frontend Architecture - Angular 19 + Signals

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Framework:** Angular 19  
**State Management:** Signals (Native)  
**Styling:** Tailwind CSS

---

## 📋 Overview

The Movello frontend is a **single Angular application** structured as a modular monolith, mirroring the backend architecture. It uses **Angular Signals** for reactive state management, replacing the complexity of NgRx for the MVP. The app is divided into distinct portals based on user roles.

### Key Decisions
- **Signals over NgRx:** Simpler, less boilerplate, better performance, built-in to Angular 19.
- **Standalone Components:** No `NgModule` complexity.
- **Role-Based Portals:** Distinct layouts and routes for Business, Provider, and Admin.
- **Tailwind CSS:** Utility-first styling for rapid UI development.
- **BFF Integration:** Authentication via httpOnly cookies managed by the BFF.

---

## 🏗️ Project Structure

```
src/
├── app/
│   ├── core/                  # Singleton services, guards, interceptors
│   │   ├── auth/              # Auth logic (Signals based)
│   │   ├── interceptors/      # Http interceptors (Auth, Error)
│   │   ├── guards/            # Route guards (Role based)
│   │   └── services/          # Global services (Theme, Notification)
│   │
│   ├── shared/                # Reusable components, pipes, directives
│   │   ├── components/        # UI Lib (Button, Card, Modal, Table)
│   │   ├── directives/        # Permission directives
│   │   └── pipes/             # Currency, Date formatting
│   │
│   ├── layout/                # Main layouts
│   │   ├── public-layout/     # Landing page, Login
│   │   ├── business-layout/   # Sidebar, Header for Business
│   │   ├── provider-layout/   # Sidebar, Header for Provider
│   │   └── admin-layout/      # Admin dashboard layout
│   │
│   ├── features/              # Feature modules (Lazy Loaded)
│   │   ├── auth/              # Login, Register, Forgot Password
│   │   ├── business/          # Business Portal
│   │   │   ├── dashboard/
│   │   │   ├── rfq/           # Create, View, Award RFQs
│   │   │   ├── contracts/
│   │   │   └── wallet/
│   │   ├── provider/          # Provider Portal
│   │   │   ├── dashboard/
│   │   │   ├── marketplace/   # Browse RFQs, Bid
│   │   │   ├── fleet/         # Vehicle Management
│   │   │   └── finance/
│   │   └── admin/             # Platform Admin
│   │       ├── users/
│   │       ├── kyckyb/        # Verification Tasks
│   │       └── settings/
│   │
│   └── app.routes.ts          # Main routing configuration
│   └── app.config.ts          # Application config (Providers)
```

---

## 🚦 State Management (Signals)

We use a **Service-with-Signals** pattern. Each feature has a store service that manages its state.

### Example: RFQ Store

```typescript
import { Injectable, signal, computed, inject } from '@angular/core';
import { RfqService } from './rfq.service';
import { RFQ } from './rfq.model';

@Injectable({ providedIn: 'root' })
export class RfqStore {
  private rfqService = inject(RfqService);

  // State Signals
  private rfqsState = signal<RFQ[]>([]);
  private loadingState = signal<boolean>(false);
  private errorState = signal<string | null>(null);

  // Computed Signals (Selectors)
  readonly rfqs = computed(() => this.rfqsState());
  readonly isLoading = computed(() => this.loadingState());
  readonly error = computed(() => this.errorState());
  
  readonly openRfqs = computed(() => 
    this.rfqsState().filter(r => r.status === 'PUBLISHED')
  );

  // Actions
  async loadRfqs() {
    this.loadingState.set(true);
    try {
      const data = await this.rfqService.getRfqs().toPromise();
      this.rfqsState.set(data || []);
    } catch (err) {
      this.errorState.set('Failed to load RFQs');
    } finally {
      this.loadingState.set(false);
    }
  }

  async createRfq(rfq: Partial<RFQ>) {
    this.loadingState.set(true);
    try {
      const newRfq = await this.rfqService.create(rfq).toPromise();
      this.rfqsState.update(list => [newRfq, ...list]);
    } catch (err) {
      this.errorState.set('Creation failed');
      throw err;
    } finally {
      this.loadingState.set(false);
    }
  }
}
```

### Usage in Component

```typescript
@Component({
  selector: 'app-rfq-list',
  standalone: true,
  template: `
    @if (store.isLoading()) {
      <app-spinner />
    }
    
    @if (store.error()) {
      <app-alert type="error">{{ store.error() }}</app-alert>
    }

    @for (rfq of store.openRfqs(); track rfq.id) {
      <app-rfq-card [rfq]="rfq" />
    }
  `
})
export class RfqListComponent {
  store = inject(RfqStore);

  constructor() {
    this.store.loadRfqs();
  }
}
```

---

## 🔐 Authentication & Guards

### Auth Store (Global)

```typescript
export class AuthStore {
  readonly user = signal<User | null>(null);
  readonly isAuthenticated = computed(() => !!this.user());
  
  readonly isBusiness = computed(() => 
    this.user()?.roles.includes('business-admin')
  );
}
```

### Route Guards

```typescript
export const authGuard: CanActivateFn = (route, state) => {
  const authStore = inject(AuthStore);
  const router = inject(Router);

  if (authStore.isAuthenticated()) {
    return true;
  }

  return router.createUrlTree(['/auth/login']);
};

export const roleGuard = (allowedRoles: string[]): CanActivateFn => {
  return () => {
    const authStore = inject(AuthStore);
    const userRoles = authStore.user()?.roles || [];
    return allowedRoles.some(r => userRoles.includes(r));
  };
};
```

---

## 🎨 UI Component Library (Tailwind)

We build reusable "dumb" components using Tailwind classes.

### Example: Button Component

```typescript
@Component({
  selector: 'app-btn',
  standalone: true,
  template: `
    <button 
      [type]="type" 
      [disabled]="disabled || loading"
      [class]="classes()"
      (click)="onClick.emit($event)">
      
      @if (loading) {
        <span class="animate-spin mr-2">...</span>
      }
      <ng-content></ng-content>
    </button>
  `
})
export class BtnComponent {
  @Input() variant: 'primary' | 'secondary' | 'danger' = 'primary';
  @Input() size: 'sm' | 'md' | 'lg' = 'md';
  
  classes = computed(() => {
    const base = 'font-semibold rounded transition duration-200 flex items-center justify-center';
    const variants = {
      primary: 'bg-blue-600 text-white hover:bg-blue-700',
      secondary: 'bg-gray-200 text-gray-800 hover:bg-gray-300',
      danger: 'bg-red-600 text-white hover:bg-red-700'
    };
    // ... size logic
    return `${base} ${variants[this.variant]}`;
  });
}
```

---

## 📡 API Integration

### Base Service Pattern

```typescript
@Injectable({ providedIn: 'root' })
export abstract class BaseService<T> {
  protected http = inject(HttpClient);
  protected abstract resourceUrl: string;

  getAll(): Observable<T[]> {
    return this.http.get<T[]>(`/api/v1/${this.resourceUrl}`);
  }

  getById(id: string): Observable<T> {
    return this.http.get<T>(`/api/v1/${this.resourceUrl}/${id}`);
  }

  create(item: Partial<T>): Observable<T> {
    return this.http.post<T>(`/api/v1/${this.resourceUrl}`, item);
  }
}
```

---

## 📱 Responsive Design Strategy

- **Mobile First:** Design for mobile, scale up with `md:`, `lg:` classes.
- **Layouts:**
  - **Desktop:** Sidebar navigation + Top Header.
  - **Mobile:** Bottom navigation bar or Hamburger menu.
- **Tables:** Convert to "Card View" on mobile screens.

---

## 🚀 Performance Optimization

1. **Lazy Loading:** All feature modules loaded lazily via `loadChildren`.
2. **Image Optimization:** Use `NgOptimizedImage` directive.
3. **Change Detection:** `OnPush` strategy everywhere (default with Signals).
4. **Bundle Budgets:** Strict limits on initial bundle size.

---

**Next Document:** [07_EVENT_DRIVEN_PATTERNS.md](./07_EVENT_DRIVEN_PATTERNS.md)
