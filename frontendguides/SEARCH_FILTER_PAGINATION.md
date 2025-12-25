# Search, Filter & Pagination Guide
## Movello Frontend - React Implementation

**Version:** 1.0  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)

---

## 📋 Table of Contents

1. [Search Implementation](#search-implementation)
2. [Filter Patterns](#filter-patterns)
3. [Pagination Implementation](#pagination-implementation)
4. [URL Query Sync](#url-query-sync)
5. [State Management](#state-management)

---

## 🔍 Search Implementation

### Search Bar Component

**File:** `src/shared/components/data/search-bar.tsx`

```typescript
import { useState, useEffect } from 'react';
import { useDebounce } from '@/shared/hooks/useDebounce';
import { Search } from 'lucide-react';

interface SearchBarProps {
  placeholder?: string;
  onSearch: (query: string) => void;
  debounceMs?: number;
}

export const SearchBar: FC<SearchBarProps> = ({
  placeholder = 'Search...',
  onSearch,
  debounceMs = 300,
}) => {
  const [query, setQuery] = useState('');
  const debouncedQuery = useDebounce(query, debounceMs);

  useEffect(() => {
    onSearch(debouncedQuery);
  }, [debouncedQuery, onSearch]);

  return (
    <div className="relative">
      <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400" />
      <Input
        type="text"
        placeholder={placeholder}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        className="pl-10"
      />
    </div>
  );
};
```

### Debounce Hook

**File:** `src/shared/hooks/useDebounce.ts`

```typescript
import { useState, useEffect } from 'react';

export const useDebounce = <T,>(value: T, delay: number): T => {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => {
      clearTimeout(handler);
    };
  }, [value, delay]);

  return debouncedValue;
};
```

---

## 🔎 Filter Patterns

### Marketplace Filters (Provider)

**Component:** `src/features/provider/marketplace/components/MarketplaceFilters.tsx`

**Filter Criteria:**
- **Vehicle Types:** Multi-select checkboxes
- **Duration:** Radio buttons (Short-term, Long-term, All)
- **Location:** Dropdown (Cities)
- **Search:** Text input (debounced)

**Implementation:**

```typescript
interface MarketplaceFilters {
  vehicleTypes: string[];
  duration: 'SHORT' | 'LONG' | 'ALL';
  location: string;
  search: string;
  pageNumber: number;
  pageSize: number;
}

export const MarketplaceFilters = ({
  filters,
  onFiltersChange,
}) => {
  const { data: vehicleTypes } = useQuery({
    queryKey: ['vehicle-types'],
    queryFn: () => masterDataService.getVehicleTypes(),
  });

  const handleVehicleTypeToggle = (type: string) => {
    const updated = filters.vehicleTypes.includes(type)
      ? filters.vehicleTypes.filter(t => t !== type)
      : [...filters.vehicleTypes, type];
    onFiltersChange({ ...filters, vehicleTypes: updated, pageNumber: 1 });
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Filters</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Vehicle Types */}
        <div>
          <h4 className="font-semibold mb-2">Vehicle Type</h4>
          <div className="space-y-2 max-h-64 overflow-y-auto">
            {vehicleTypes?.map((type) => (
              <label key={type.code} className="flex items-center">
                <Checkbox
                  checked={filters.vehicleTypes.includes(type.code)}
                  onCheckedChange={() => handleVehicleTypeToggle(type.code)}
                />
                <span className="ml-2 text-sm">{type.label}</span>
              </label>
            ))}
          </div>
        </div>

        {/* Duration */}
        <div>
          <h4 className="font-semibold mb-2">Duration</h4>
          <RadioGroup
            value={filters.duration}
            onValueChange={(value) =>
              onFiltersChange({ ...filters, duration: value as any, pageNumber: 1 })
            }
          >
            <div className="space-y-2">
              <label className="flex items-center">
                <RadioGroupItem value="SHORT" />
                <span className="ml-2 text-sm">Short-term (&lt; 7 days)</span>
              </label>
              <label className="flex items-center">
                <RadioGroupItem value="LONG" />
                <span className="ml-2 text-sm">Long-term (≥ 30 days)</span>
              </label>
              <label className="flex items-center">
                <RadioGroupItem value="ALL" />
                <span className="ml-2 text-sm">All</span>
              </label>
            </div>
          </RadioGroup>
        </div>

        {/* Location */}
        <div>
          <h4 className="font-semibold mb-2">Location</h4>
          <Select
            value={filters.location}
            onValueChange={(value) =>
              onFiltersChange({ ...filters, location: value, pageNumber: 1 })
            }
          >
            <SelectTrigger>
              <SelectValue placeholder="Select city" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">All Cities</SelectItem>
              {cities.map((city) => (
                <SelectItem key={city.code} value={city.code}>
                  {city.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {/* Search */}
        <div>
          <h4 className="font-semibold mb-2">Search</h4>
          <SearchBar
            placeholder="Search by title..."
            onSearch={(query) =>
              onFiltersChange({ ...filters, search: query, pageNumber: 1 })
            }
          />
        </div>

        {/* Clear Filters */}
        <Button
          variant="outline"
          onClick={() =>
            onFiltersChange({
              vehicleTypes: [],
              duration: 'ALL',
              location: '',
              search: '',
              pageNumber: 1,
              pageSize: 20,
            })
          }
          className="w-full"
        >
          Clear All Filters
        </Button>
      </CardContent>
    </Card>
  );
};
```

### RFQ List Filters (Business)

**Filter Criteria:**
- **Status:** Dropdown (Draft, Published, Bidding Closed, Awarded)
- **Date Range:** Date picker (from/to)
- **Vehicle Type:** Dropdown
- **Search:** Text input

**Implementation:**

```typescript
interface RFQFilters {
  status?: string;
  startDateFrom?: string;
  startDateTo?: string;
  vehicleTypeCode?: string;
  search?: string;
  pageNumber: number;
  pageSize: number;
  sortBy?: string;
  sortDescending?: boolean;
}

export const RFQFilters = ({ filters, onFiltersChange }) => {
  return (
    <div className="flex flex-wrap gap-4 items-end">
      <FormField label="Status">
        <Select
          value={filters.status || 'all'}
          onValueChange={(value) =>
            onFiltersChange({ ...filters, status: value === 'all' ? undefined : value, pageNumber: 1 })
          }
        >
          <SelectTrigger className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="DRAFT">Draft</SelectItem>
            <SelectItem value="PUBLISHED">Published</SelectItem>
            <SelectItem value="BIDDING_CLOSED">Bidding Closed</SelectItem>
            <SelectItem value="AWARDED">Awarded</SelectItem>
          </SelectContent>
        </Select>
      </FormField>

      <FormField label="From Date">
        <DatePicker
          value={filters.startDateFrom ? new Date(filters.startDateFrom) : undefined}
          onChange={(date) =>
            onFiltersChange({
              ...filters,
              startDateFrom: date ? formatISO(date) : undefined,
              pageNumber: 1,
            })
          }
        />
      </FormField>

      <FormField label="To Date">
        <DatePicker
          value={filters.startDateTo ? new Date(filters.startDateTo) : undefined}
          onChange={(date) =>
            onFiltersChange({
              ...filters,
              startDateTo: date ? formatISO(date) : undefined,
              pageNumber: 1,
            })
          }
        />
      </FormField>

      <FormField label="Vehicle Type">
        <Select
          value={filters.vehicleTypeCode || 'all'}
          onValueChange={(value) =>
            onFiltersChange({
              ...filters,
              vehicleTypeCode: value === 'all' ? undefined : value,
              pageNumber: 1,
            })
          }
        >
          <SelectTrigger className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Types</SelectItem>
            {vehicleTypes?.map((type) => (
              <SelectItem key={type.code} value={type.code}>
                {type.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </FormField>

      <div className="flex-1 min-w-[200px]">
        <SearchBar
          placeholder="Search RFQs..."
          onSearch={(query) =>
            onFiltersChange({ ...filters, search: query, pageNumber: 1 })
          }
        />
      </div>
    </div>
  );
};
```

### Contract Filters

**Filter Criteria:**
- **Status:** Dropdown
- **Date Range:** Date pickers
- **Provider:** Search/Select
- **Contract Number:** Search

### Vehicle Filters (Provider)

**Filter Criteria:**
- **Status:** Dropdown (Active, Assigned, Under Review, Maintenance, Suspended)
- **Vehicle Type:** Dropdown
- **Insurance Status:** Dropdown (Active, Expired, Pending)
- **Tags:** Multi-select

---

## 📄 Pagination Implementation

### Pagination Component

**File:** `src/shared/components/data/pagination.tsx`

```typescript
import { ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight } from 'lucide-react';

interface PaginationProps {
  currentPage: number;
  totalPages: number;
  onPageChange: (page: number) => void;
  pageSize?: number;
  totalItems?: number;
}

export const Pagination: FC<PaginationProps> = ({
  currentPage,
  totalPages,
  onPageChange,
  pageSize,
  totalItems,
}) => {
  const getPageNumbers = () => {
    const pages: (number | string)[] = [];
    const maxVisible = 7;

    if (totalPages <= maxVisible) {
      // Show all pages
      for (let i = 1; i <= totalPages; i++) {
        pages.push(i);
      }
    } else {
      // Show first, last, and pages around current
      pages.push(1);
      
      if (currentPage > 3) {
        pages.push('...');
      }

      const start = Math.max(2, currentPage - 1);
      const end = Math.min(totalPages - 1, currentPage + 1);

      for (let i = start; i <= end; i++) {
        pages.push(i);
      }

      if (currentPage < totalPages - 2) {
        pages.push('...');
      }

      pages.push(totalPages);
    }

    return pages;
  };

  return (
    <div className="flex items-center justify-between">
      <div className="text-sm text-gray-600">
        {totalItems && (
          <span>
            Showing {(currentPage - 1) * (pageSize || 20) + 1} to{' '}
            {Math.min(currentPage * (pageSize || 20), totalItems)} of {totalItems} results
          </span>
        )}
      </div>

      <div className="flex items-center gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() => onPageChange(1)}
          disabled={currentPage === 1}
        >
          <ChevronsLeft className="h-4 w-4" />
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => onPageChange(currentPage - 1)}
          disabled={currentPage === 1}
        >
          <ChevronLeft className="h-4 w-4" />
        </Button>

        <div className="flex gap-1">
          {getPageNumbers().map((page, index) => {
            if (page === '...') {
              return (
                <span key={`ellipsis-${index}`} className="px-2">
                  ...
                </span>
              );
            }

            const pageNum = page as number;
            return (
              <Button
                key={pageNum}
                variant={currentPage === pageNum ? 'default' : 'outline'}
                size="sm"
                onClick={() => onPageChange(pageNum)}
              >
                {pageNum}
              </Button>
            );
          })}
        </div>

        <Button
          variant="outline"
          size="sm"
          onClick={() => onPageChange(currentPage + 1)}
          disabled={currentPage === totalPages}
        >
          <ChevronRight className="h-4 w-4" />
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => onPageChange(totalPages)}
          disabled={currentPage === totalPages}
        >
          <ChevronsRight className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
};
```

### Usage Example

```typescript
const { data } = useQuery({
  queryKey: ['rfqs', filters],
  queryFn: () => rfqService.getRFQs(filters),
});

return (
  <>
    {/* List content */}
    <Pagination
      currentPage={data?.pagination.page || 1}
      totalPages={data?.pagination.totalPages || 1}
      pageSize={data?.pagination.pageSize}
      totalItems={data?.pagination.totalItems}
      onPageChange={(page) => setFilters({ ...filters, pageNumber: page })}
    />
  </>
);
```

---

## 🔗 URL Query Sync

### Sync Filters with URL

**Hook:** `src/shared/hooks/useURLFilters.ts`

```typescript
import { useSearchParams } from 'react-router-dom';
import { useMemo } from 'react';

export const useURLFilters = <T extends Record<string, any>>(
  defaultFilters: T
): [T, (filters: T) => void] => {
  const [searchParams, setSearchParams] = useSearchParams();

  const filters = useMemo(() => {
    const params: T = { ...defaultFilters };
    
    searchParams.forEach((value, key) => {
      if (key in defaultFilters) {
        // Handle different types
        if (typeof defaultFilters[key] === 'number') {
          params[key as keyof T] = Number(value) as T[keyof T];
        } else if (typeof defaultFilters[key] === 'boolean') {
          params[key as keyof T] = (value === 'true') as T[keyof T];
        } else if (Array.isArray(defaultFilters[key])) {
          params[key as keyof T] = value.split(',') as T[keyof T];
        } else {
          params[key as keyof T] = value as T[keyof T];
        }
      }
    });

    return params;
  }, [searchParams, defaultFilters]);

  const updateFilters = (newFilters: T) => {
    const newParams = new URLSearchParams();
    
    Object.entries(newFilters).forEach(([key, value]) => {
      if (value !== undefined && value !== null && value !== '') {
        if (Array.isArray(value)) {
          if (value.length > 0) {
            newParams.set(key, value.join(','));
          }
        } else {
          newParams.set(key, String(value));
        }
      }
    });

    setSearchParams(newParams, { replace: true });
  };

  return [filters, updateFilters];
};
```

### Usage

```typescript
const [filters, setFilters] = useURLFilters<RFQFilters>({
  pageNumber: 1,
  pageSize: 20,
  status: undefined,
  search: '',
});

// Filters automatically sync with URL
// Changing filters updates URL
// Refreshing page preserves filters
```

---

## 🔄 State Management

### Filter State Pattern

```typescript
// Using React Query with filters
const { data, isLoading } = useQuery({
  queryKey: ['rfqs', filters], // Filters in query key for caching
  queryFn: () => rfqService.getRFQs(filters),
  keepPreviousData: true, // Show previous data while loading
  staleTime: 5 * 60 * 1000,
});

// Filter state in component
const [filters, setFilters] = useState<RFQFilters>({
  pageNumber: 1,
  pageSize: 20,
});

// Update filters (resets to page 1)
const handleFilterChange = (newFilters: Partial<RFQFilters>) => {
  setFilters({ ...filters, ...newFilters, pageNumber: 1 });
};
```

### Filter Chips Component

**File:** `src/shared/components/data/filter-chips.tsx`

```typescript
interface FilterChip {
  key: string;
  label: string;
  value: string;
  onRemove: () => void;
}

export const FilterChips = ({ chips }: { chips: FilterChip[] }) => {
  if (chips.length === 0) return null;

  return (
    <div className="flex flex-wrap gap-2">
      {chips.map((chip) => (
        <Badge key={chip.key} variant="secondary" className="flex items-center gap-1">
          <span>{chip.label}: {chip.value}</span>
          <button
            onClick={chip.onRemove}
            className="ml-1 hover:bg-gray-300 rounded-full p-0.5"
          >
            <X className="h-3 w-3" />
          </button>
        </Badge>
      ))}
    </div>
  );
};
```

---

## 📊 Sort Implementation

### Sortable Table Header

```typescript
interface SortableHeaderProps {
  column: string;
  currentSort: { by: string; descending: boolean };
  onSort: (column: string) => void;
  children: React.ReactNode;
}

export const SortableHeader: FC<SortableHeaderProps> = ({
  column,
  currentSort,
  onSort,
  children,
}) => {
  const isActive = currentSort.by === column;
  const isDescending = isActive && currentSort.descending;

  return (
    <TableHead>
      <button
        onClick={() => onSort(column)}
        className="flex items-center gap-1 hover:text-gray-700"
      >
        {children}
        {isActive ? (
          isDescending ? <ArrowDown className="h-4 w-4" /> : <ArrowUp className="h-4 w-4" />
        ) : (
          <ArrowUpDown className="h-4 w-4 text-gray-400" />
        )}
      </button>
    </TableHead>
  );
};
```

### Usage

```typescript
const [sort, setSort] = useState({ by: 'createdAt', descending: true });

<SortableHeader
  column="createdAt"
  currentSort={sort}
  onSort={(column) =>
    setSort({
      by: column,
      descending: sort.by === column ? !sort.descending : true,
    })
  }
>
  Created Date
</SortableHeader>
```

---

## ✅ Best Practices

1. **Debounce search** inputs (300ms default)
2. **Reset to page 1** when filters change
3. **Sync filters with URL** for shareable links
4. **Use React Query** for server state
5. **Keep previous data** while loading new page
6. **Show loading states** during filter changes
7. **Clear filters** button for better UX
8. **Filter chips** to show active filters
9. **Mobile responsive** filter panels
10. **Accessible** filter controls (keyboard navigation)

---

**END OF SEARCH/FILTER/PAGINATION GUIDE**

*For specific implementations, see portal-specific guides*

