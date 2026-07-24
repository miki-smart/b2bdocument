# Search, Filter & Pagination Guide
## Movello Frontend - React Implementation

**Version:** 2.0
**Last verified against code: 2026-07-23**
**Primary sources:**
- `src/features/business/pages/rfq/list/RFQListPage.tsx` (RFQ list — status/date/vehicle-type filters, URL-partial-sync pagination)
- `src/features/business/pages/rfq/bids/BidReviewPage.tsx` (bid `sortBy` on the review screen, not a list page)
- `src/features/provider/pages/fleet/pages/FleetListPage.tsx` (fleet filters, `VehicleFilters` shape)
- `src/features/admin/pages/verifications/BusinessVerificationListPage.tsx` (admin list convention: debounced search, status tabs, `sortBy`/`sortDescending`)
- `src/shared/components/data/DataPagination.tsx` (the one real pagination component)
- `src/core/services/rfq-service.ts` (real query-param names sent to the backend)
- `src/shared/types/api.ts` (`PaginatedResponse<T>`, `PaginationParams`)

This replaces the v1.0 guide, which invented a generic `useURLFilters` hook, a `useDebounce` hook, a `SearchBar` component, and a `FilterChips` component — none of which exist anywhere in the codebase (`grep` across `src/` for all four returns zero hits). The real app does not have a single shared filter/pagination abstraction; each list page hand-rolls its own filter state, and URL-sync is applied selectively (some filters sync to the URL, most don't), not through a generic hook.

---

## Table of Contents

1. [What's Actually Real vs. What v1.0 Invented](#whats-actually-real-vs-what-v10-invented)
2. [The Real Pagination Contract](#the-real-pagination-contract)
3. [DataPagination Component](#datapagination-component)
4. [RFQ List: Filters + Partial URL Sync](#rfq-list-filters--partial-url-sync)
5. [Bid Review: Client-Side Sort (Not a List Page)](#bid-review-client-side-sort-not-a-list-page)
6. [Fleet List: Multi-Field Filter State](#fleet-list-multi-field-filter-state)
7. [Admin Lists: Debounced Search + Status Tabs](#admin-lists-debounced-search--status-tabs)
8. [Conventions to Follow When Adding a New List Page](#conventions-to-follow-when-adding-a-new-list-page)

---

## What's Actually Real vs. What v1.0 Invented

| v1.0 claimed | Reality |
|---|---|
| Shared `useDebounce<T>` hook, `SearchBar` component used everywhere | No shared debounce hook or search-bar component exists. `RFQListPage` uses an explicit search button + Enter-key handler (no debounce at all); `FleetListPage`/admin list pages roll their own `setTimeout`-based debounce inline per page |
| Shared generic `useURLFilters<T>` hook syncing an arbitrary filter object to the URL | No such hook exists. `RFQListPage` manually reads/writes specific `URLSearchParams` keys (`statuses`, `page`, `pageSize`) for **some** filters only — search text, vehicle type, and date range are **not** synced to the URL and are lost on refresh |
| Shared `FilterChips` component | Does not exist. `hasActiveFilters` is a plain boolean used to show/hide a single "Clear" button — there's no per-filter removable chip UI anywhere in the list pages surveyed |
| Backend query params named generically (`pageNumber`, `pageSize`, `status`, `search`, ...) | Real names are page-specific and not fully consistent across services — see [The Real Pagination Contract](#the-real-pagination-contract) below |
| Generic `Pagination` component reading `currentPage`/`totalPages` props only | Real component is `DataPagination` — same idea, but also owns a page-size `<Select>` and computes "Showing X-Y of Z" itself; it renders `null` if `totalPages <= 1` **and** no `onPageSizeChange` was passed |

---

## The Real Pagination Contract

**Response shape** (`src/shared/types/api.ts`):

```typescript
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

**Request shape** — this is the part that's easy to get wrong. Frontend-side filter objects use `page`/`pageSize` (e.g. `RFQFilters.page`), but the service layer translates that to the backend's actual query-string parameter names, which are **not** always the same word:

```typescript
// src/core/services/rfq-service.ts — listRfqs()
// Query params actually sent: pageNumber, pageSize, status(es), search,
// vehicleType, fuelType, dateFrom, dateTo, sortBy, businessId
if (filters.page) params.append('pageNumber', String(filters.page));      // page -> pageNumber
if (filters.pageSize) params.append('pageSize', String(filters.pageSize));
// status can be a single value ('status') OR a repeated multi-select ('statuses')
if (Array.isArray(filters.status)) {
  filters.status.forEach((s) => params.append('statuses', s));
} else if (filters.status) {
  params.append('status', filters.status);
}
if (filters.search) params.append('search', filters.search);
if (filters.vehicleType) params.append('vehicleType', filters.vehicleType);
if (filters.dateFrom) params.append('dateFrom', filters.dateFrom);
if (filters.dateTo) params.append('dateTo', filters.dateTo);
if (filters.sortBy) params.append('sortBy', filters.sortBy);
```

Admin list services (e.g. `adminVerificationService.getBusinesses`) instead pass `pageNumber`/`pageSize`/`sortBy`/`sortDescending` directly as named fields (matching `PaginationParams` in `api.ts`) rather than building a `URLSearchParams` object by hand — **two slightly different conventions coexist** (manual `URLSearchParams` building in `rfq-service.ts` vs. typed param objects elsewhere). When adding a new list, check the sibling service file for the module you're extending rather than assuming one global convention.

---

## DataPagination Component

**File:** `src/shared/components/data/DataPagination.tsx`

```typescript
interface DataPaginationProps {
  currentPage: number;
  totalPages: number;
  pageSize: number;
  totalItems: number;
  onPageChange: (page: number) => void;
  onPageSizeChange?: (size: number) => void;
  pageSizeOptions?: number[]; // default [10, 20, 50, 100]
  compact?: boolean;          // hides first/last-page buttons, shows fewer page numbers
  className?: string;
}
```

Renders `null` when `totalPages <= 1` **and** no `onPageSizeChange` is supplied — a list with a page-size selector always renders the control even with one page, but a list without one hides the whole footer once there's nothing to page through. Shows a mobile-only "`currentPage / totalPages`" indicator below the `sm:` breakpoint instead of numbered buttons.

Usage:

```typescript
{data && data.pagination.totalPages > 1 && (
  <DataPagination
    currentPage={data.pagination.page}
    totalPages={data.pagination.totalPages}
    totalItems={data.pagination.totalItems}
    pageSize={pageSize}
    onPageChange={handlePageChange}
    onPageSizeChange={handlePageSizeChange}
  />
)}
```

---

## RFQ List: Filters + Partial URL Sync

**File:** `src/features/business/pages/rfq/list/RFQListPage.tsx`

Real filter state and behavior:

```typescript
const [searchInput, setSearchInput] = useState(searchParams.get('search') || '');
const [searchQuery, setSearchQuery] = useState(searchParams.get('search') || '');
const [dateRange, setDateRange] = useState<DateRange | undefined>();       // NOT synced to URL
const [vehicleTypeFilter, setVehicleTypeFilter] = useState(searchParams.get('vehicleType') || '');
const [currentPage, setCurrentPage] = useState(Number(searchParams.get('page')) || 1);
const [pageSize, setPageSize] = useState(Number(searchParams.get('pageSize')) || 10);
const [selectedStatuses, setSelectedStatuses] = useState<RFQStatus[]>(/* read from 'statuses' repeated param, or legacy single 'status' */);
```

Key real-world details:
- **Search is explicit, not debounced.** There's a separate `searchInput` (what's typed) and `searchQuery` (what's actually queried); the query only updates on a search-icon click or Enter keypress (`handleSearch`), and a separate X button clears both and resets to page 1.
- **Only status, page, and pageSize are written back to the URL** (`newParams` built from `searchParams` + the changed key(s), then `setSearchParams(newParams)`). Search text, vehicle-type filter, and date range are component state only — refreshing the page loses them, and a shared/bookmarked link does not reproduce a search or date filter, only the status filter and pagination position.
- **Status is a multi-select** (`DropdownMenuCheckboxItem` per status), stored as repeated `?statuses=X&statuses=Y` URL params, with backward-compat reading of a legacy singular `?status=X` param into the same array.
- **`hasActiveFilters`** is a plain OR of `searchQuery || dateRange || vehicleTypeFilter || selectedStatuses.length > 0`, driving a single "Clear" button — there is no per-filter chip/pill UI.
- **Every filter change resets `currentPage` to 1** (status toggle, search, date range, vehicle type, clear-all) — this convention should be preserved in any new filter added to this page.
- The query itself: `useQuery({ queryKey: ['rfqs', filters], queryFn: () => rfqService.listRfqs(filters) })` — the whole `filters` object is the cache key, so React Query naturally re-fetches on any filter change and caches per unique filter combination. There is no `keepPreviousData`/`placeholderData` configured on this query — the grid shows its skeleton loader on every filter change rather than the previous page's data.

---

## Bid Review: Client-Side Sort (Not a List Page)

**File:** `src/features/business/pages/rfq/bids/BidReviewPage.tsx`

This page is commonly mis-described as having "filters" — it doesn't. It fetches **all** bids for one RFQ in a single call (`bidService.getRFQBids(rfqId)`, no pagination params) and applies a **client-side sort only**:

```typescript
type SortOption = 'price_asc' | 'price_desc' | 'quantity' | 'trust_score' | 'time';
const [sortBy, setSortBy] = useState<SortOption>('price_asc');

const sortBids = useCallback((bids: Bid[]): Bid[] => {
  return [...bids].sort((a, b) => {
    switch (sortBy) {
      case 'price_asc': return a.unitPrice - b.unitPrice;
      case 'price_desc': return b.unitPrice - a.unitPrice;
      case 'quantity': return b.quantityOffered - a.quantityOffered;
      case 'trust_score': return (b.trustScore || 0) - (a.trustScore || 0);
      case 'time': return new Date(a.submittedAt).getTime() - new Date(b.submittedAt).getTime();
      default: return 0;
    }
  });
}, [sortBy]);
```

Bids are grouped into per-line-item tabs (`Tabs`/`TabsList`/`TabsTrigger`, one tab per `RFQLineItem`), and the sort is applied independently within whichever tab is active (`sortBids(lineItem.bids)`), not globally across line items. There is no server-side sort endpoint involved here — sorting a few dozen bids for one RFQ client-side is a deliberate, reasonable simplification, not a gap.

---

## Fleet List: Multi-Field Filter State

**File:** `src/features/provider/pages/fleet/pages/FleetListPage.tsx`

```typescript
const [filters, setFilters] = useState<VehicleFilters>({
  status: 'ALL',
  vehicleType: 'ALL',
  directRentalAvailability: 'ALL',   // undocumented in older specs — see Direct Rental (epic-21)
  sortBy: 'createdAt',
  sortDescending: true,
  page: 1,
  pageSize: 12,
});
const [searchInput, setSearchInput] = useState('');
const [plateNumberInput, setPlateNumberInput] = useState('');
const [makeInput, setMakeInput] = useState('');
const [modelInput, setModelInput] = useState('');
```

Notable real behavior:
- Search/plate/make/model are **separate text inputs**, all held in component state, and only merged into `filters` (triggering the actual query) when `handleSearch()` fires — same "explicit apply, not live-debounced" pattern as `RFQListPage`.
- `vehicleType` options are **not hardcoded** — they come from `lookupService.getVehicleTypes()` (a master-data lookup query, `staleTime: 1000 * 60 * 30`), not a fixed `VEHICLE_TYPE_OPTIONS` array. Any new page listing vehicle types should query the lookup service, not hardcode a list.
- A second, independent query (`provider-fleet-capacity` via `providerFleetCapacityService.getCapacitySnapshot()`) cross-references which vehicles are already committed to a Direct Rental cart/RFQ award (`inactiveVehicleIds`) and is merged into the row display (`getCommitmentLabel`) — this fleet-capacity cross-check between RFQ bidding and Direct Rental is a real, undocumented-in-older-docs feature (see `project-docs/18_Implementation_Coverage_Audit.md` §7.2).
- View mode (`grid`/`list`) is local UI state, unrelated to filtering, and not persisted or URL-synced.

---

## Admin Lists: Debounced Search + Status Tabs

**File:** `src/features/admin/pages/verifications/BusinessVerificationListPage.tsx` (representative of the admin list convention; `ProviderVerificationListPage.tsx`/`VehicleVerificationListPage.tsx` follow the same shape)

```typescript
const [statusFilter, setStatusFilter] = useState<VerificationStatus | 'ALL'>('PENDING');
const [searchQuery, setSearchQuery] = useState('');
const [sortBy, setSortBy] = useState<string>('CreatedAt');
const [sortDescending, setSortDescending] = useState<boolean>(true);
const [page, setPage] = useState(1);
const [pageSize, setPageSize] = useState(10);

// Debounced search — the one place a debounce pattern is actually used, and it's
// hand-rolled per-page, not a shared hook:
const [debouncedSearch, setDebouncedSearch] = useState(searchQuery);
useMemo(() => {
  const timer = setTimeout(() => {
    setDebouncedSearch(searchQuery);
    setPage(1);
  }, 300);
  return () => clearTimeout(timer);
}, [searchQuery]);

const { data, isLoading } = useQuery({
  queryKey: ['admin-business-verifications', statusFilter, debouncedSearch, businessTypeFilter, tierFilter, sortBy, sortDescending, page, pageSize],
  queryFn: () => adminVerificationService.getBusinesses({
    pageNumber: page, pageSize,
    search: debouncedSearch || undefined,
    status: statusFilter === 'ALL' ? undefined : statusFilter,
    sortBy, sortDescending,
  }),
});
```

Differences from the RFQ list convention worth calling out if extending an admin page:
- **Status is a `Tabs` row** (`PENDING` / etc.), not a multi-select dropdown — admin verification queues are single-status-at-a-time by design.
- **Search actually is debounced here** (300ms via `useMemo` + `setTimeout`), unlike `RFQListPage`'s explicit search button. Note the debounce is implemented with `useMemo` as a side-effect trick rather than `useEffect` — copy this pattern only if you're matching this file's existing style, it's not the idiomatic React approach.
- The full query key includes every filter field individually (not one `filters` object), so cache entries are keyed the same way but constructed differently than the RFQ list.

---

## Conventions to Follow When Adding a New List Page

Based on what's actually consistent across the real pages above:

1. **Reset `page` to 1 on every filter change** — every real list page does this without exception.
2. **Use `DataPagination`**, not a hand-rolled pager — it already handles the page-size selector, ellipsis truncation, and the "Showing X-Y of Z" line.
3. **Put the whole filter object in the React Query key** (`queryKey: ['thing', filters]`) rather than individual primitives, unless the page you're extending already uses the individual-fields convention (admin lists) — match the sibling file in that feature area.
4. **Don't assume URL sync exists or is complete** — check the specific page. `RFQListPage` only syncs `statuses`/`page`/`pageSize`; most filter state elsewhere isn't URL-synced at all. If a task requires shareable/bookmarkable filter links, that needs to be added, not assumed present.
5. **Confirm the actual backend query-param names in the relevant `*-service.ts` file before wiring a new filter** — `pageNumber` vs. `page`, `statuses` (repeated) vs. `status` (single), and per-module naming are not uniform across services.
6. **Debounce only if the page needs live-as-you-type search**; the more common pattern in this codebase is an explicit search action (button/Enter), which avoids needless network chatter on every keystroke and is simpler to reason about — don't add a debounce hook by default.
