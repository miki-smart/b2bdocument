# Business Portal Development Guide
## Movello Frontend - React Implementation

**Version:** 1.0  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)

---

## 📋 Table of Contents

1. [Dashboard](#dashboard)
2. [RFQ Management](#rfq-management)
3. [Bid Review & Award](#bid-review--award)
4. [Contract Management](#contract-management)
5. [Wallet Management](#wallet-management)
6. [Profile & Settings](#profile--settings)

---

## 📊 Dashboard

### Route
`/business/dashboard`

### Component
`src/features/business/dashboard/BusinessDashboard.tsx`

### Features
- **Stat Cards:**
  - Active RFQs count
  - Ongoing Contracts count
  - Wallet Balance (Available / Locked)
  - Pending Bids count
- **Quick Actions:**
  - Create RFQ button
  - View Contracts button
  - Top-up Wallet button
- **Recent Activity Table:**
  - Latest bids received
  - Contract status updates
  - Recent transactions

### Implementation

```typescript
import { useQuery } from '@tanstack/react-query';
import { StatCard } from '@/shared/components/data/stat-card';
import { businessService } from '../services/business-service';
import { walletService } from '../wallet/services/wallet-service';

export const BusinessDashboard = () => {
  const { data: stats } = useQuery({
    queryKey: ['business', 'stats'],
    queryFn: () => businessService.getDashboardStats(),
  });

  const { data: wallet } = useQuery({
    queryKey: ['wallet', 'me'],
    queryFn: () => walletService.getWallet(),
  });

  const { data: recentActivity } = useQuery({
    queryKey: ['business', 'activity'],
    queryFn: () => businessService.getRecentActivity(),
  });

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Active RFQs"
          value={stats?.activeRfqs || 0}
          icon={<FileText />}
          link="/business/rfqs"
        />
        <StatCard
          title="Ongoing Contracts"
          value={stats?.activeContracts || 0}
          icon={<FileCheck />}
          link="/business/contracts"
        />
        <StatCard
          title="Available Balance"
          value={`${formatCurrency(wallet?.availableBalance || 0)} ETB`}
          icon={<Wallet />}
          link="/business/wallet"
        />
        <StatCard
          title="Locked Balance"
          value={`${formatCurrency(wallet?.lockedBalance || 0)} ETB`}
          icon={<Lock />}
          variant="warning"
        />
      </div>

      <div className="grid md:grid-cols-2 gap-6">
        <Card>
          <CardHeader>
            <CardTitle>Quick Actions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <Button asChild className="w-full">
              <Link to="/business/rfqs/create">Create New RFQ</Link>
            </Button>
            <Button asChild variant="outline" className="w-full">
              <Link to="/business/contracts">View Contracts</Link>
            </Button>
            <Button asChild variant="outline" className="w-full">
              <Link to="/business/wallet">Top-up Wallet</Link>
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Recent Activity</CardTitle>
          </CardHeader>
          <CardContent>
            <Table>
              <TableBody>
                {recentActivity?.map((activity) => (
                  <TableRow key={activity.id}>
                    <TableCell>{activity.type}</TableCell>
                    <TableCell>{activity.description}</TableCell>
                    <TableCell>{formatDate(activity.createdAt)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      </div>
    </div>
  );
};
```

### API Endpoints
- `GET /api/businesses/{id}/dashboard-stats` - Get dashboard statistics
- `GET /api/businesses/{id}/recent-activity` - Get recent activity

---

## 📝 RFQ Management

### RFQ List Page

**Route:** `/business/rfqs`  
**Component:** `src/features/business/rfq/pages/RFQListPage.tsx`

#### Features
- **Tabs:** Draft, Published, Bidding Closed, Awarded
- **Filters:**
  - Status dropdown
  - Date range picker
  - Search by title/description
  - Vehicle type filter
- **RFQ Cards/Table:**
  - RFQ Number
  - Title
  - Status badge
  - Bid Deadline (with countdown)
  - Line Items count
  - Bid count
  - Actions: View, Edit (draft only), Delete (draft only)
- **Pagination**
- **Empty State**
- **Create RFQ Button**

#### Implementation

```typescript
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/tabs';
import { RFQCard } from '../components/RFQCard';
import { RFQFilters } from '../components/RFQFilters';
import { useRFQs } from '../hooks/useRFQs';

export const RFQListPage = () => {
  const [activeTab, setActiveTab] = useState('all');
  const [filters, setFilters] = useState<RFQFilters>({
    pageNumber: 1,
    pageSize: 20,
  });

  const { data, isLoading } = useRFQs({
    ...filters,
    status: activeTab === 'all' ? undefined : activeTab.toUpperCase(),
  });

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold">My RFQs</h1>
        <Button asChild>
          <Link to="/business/rfqs/create">Create RFQ</Link>
        </Button>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="all">All</TabsTrigger>
          <TabsTrigger value="DRAFT">Draft</TabsTrigger>
          <TabsTrigger value="PUBLISHED">Published</TabsTrigger>
          <TabsTrigger value="BIDDING">Bidding</TabsTrigger>
          <TabsTrigger value="PARTIALLY_AWARDED">Partially Awarded</TabsTrigger>
          <TabsTrigger value="AWARDED">Awarded</TabsTrigger>
          <TabsTrigger value="COMPLETED">Completed</TabsTrigger>
          <TabsTrigger value="CANCELLED">Cancelled</TabsTrigger>
        </TabsList>

        <TabsContent value={activeTab} className="space-y-4">
          <RFQFilters filters={filters} onFiltersChange={setFilters} />
          
          {isLoading ? (
            <LoadingState />
          ) : data?.data.length === 0 ? (
            <EmptyState
              title="No RFQs found"
              description="Create your first RFQ to get started"
              action={<Button asChild><Link to="/business/rfqs/create">Create RFQ</Link></Button>}
            />
          ) : (
            <>
              <div className="grid gap-4">
                {data?.data.map((rfq) => (
                  <RFQCard key={rfq.id} rfq={rfq} />
                ))}
              </div>
              <Pagination
                currentPage={data?.pagination.page || 1}
                totalPages={data?.pagination.totalPages || 1}
                onPageChange={(page) => setFilters({ ...filters, pageNumber: page })}
              />
            </>
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
};
```

### Create RFQ Wizard

**Route:** `/business/rfqs/create`  
**Component:** `src/features/business/rfq/pages/CreateRFQPage.tsx`

#### Prerequisites: Business Verification

**CRITICAL:** Before allowing RFQ creation, verify business status.

**Rule BR-001:** Business MUST have `status = VERIFIED` to create RFQ.

**Implementation:**

```typescript
// Add to CreateRFQPage.tsx
import { useAuthStore } from '@/stores/auth-store';
import { useQuery } from '@tanstack/react-query';
import { businessService } from '../services/business-service';

export const CreateRFQPage = () => {
  const { user } = useAuthStore();
  const { data: business, isLoading } = useQuery({
    queryKey: ['business', user.businessId],
    queryFn: () => businessService.getBusinessById(user.businessId),
  });

  if (isLoading) return <LoadingState />;

  // Check verification status
  if (business?.status !== 'VERIFIED') {
    return (
      <Card className="max-w-2xl mx-auto mt-8">
        <CardHeader>
          <CardTitle>Business Verification Required</CardTitle>
        </CardHeader>
        <CardContent>
          <Alert variant="warning">
            <AlertCircle className="h-4 w-4" />
            <AlertTitle>Account Not Verified</AlertTitle>
            <AlertDescription>
              Your business account must be verified before you can create RFQs.
              {business?.status === 'PENDING' && ' Your verification is currently under review.'}
              {business?.status === 'REJECTED' && ' Please contact support for assistance.'}
            </AlertDescription>
          </Alert>
          <div className="mt-4">
            <Button asChild variant="outline">
              <Link to="/business/profile">View Profile</Link>
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  // Proceed with RFQ creation wizard
  return <CreateRFQWizard />;
};
```

#### Step 1: Basic Information

**Fields:**
- Title (required, min 5 chars)
- Description (textarea, optional)
- Start Date (date picker, min: today + 3 days)
- End Date (date picker, must be after start date)
- Bid Deadline (date-time picker, must be before start date)

**Validation Schema:**

```typescript
const step1Schema = z.object({
  title: z.string().min(5, 'Title must be at least 5 characters'),
  description: z.string().optional(),
  startDate: z.date().refine(
    (date) => isAfter(date, addDays(new Date(), 3)),
    'Start date must be at least 3 days from now'
  ),
  endDate: z.date(),
  bidDeadline: z.date(),
}).refine(
  (data) => isAfter(data.endDate, data.startDate),
  { message: 'End date must be after start date', path: ['endDate'] }
).refine(
  (data) => isBefore(data.bidDeadline, data.startDate),
  { message: 'Bid deadline must be before start date', path: ['bidDeadline'] }
);
```

**Component:**

```typescript
export const CreateRFQStep1 = ({ onNext, formData, setFormData }) => {
  const { register, handleSubmit, formState: { errors }, control } = useForm({
    resolver: zodResolver(step1Schema),
    defaultValues: formData.step1 || {},
  });

  const onSubmit = (data) => {
    setFormData({ ...formData, step1: data });
    onNext();
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Basic Information</CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
          <FormField label="Title" error={errors.title?.message} required>
            <Input {...register('title')} placeholder="e.g., Monthly Vehicle Rental - December 2025" />
          </FormField>

          <FormField label="Description" error={errors.description?.message}>
            <Textarea
              {...register('description')}
              placeholder="Describe your vehicle rental requirements..."
              rows={4}
            />
          </FormField>

          <div className="grid md:grid-cols-2 gap-4">
            <FormField label="Start Date" error={errors.startDate?.message} required>
              <DatePicker
                control={control}
                name="startDate"
                minDate={addDays(new Date(), 3)}
              />
            </FormField>

            <FormField label="End Date" error={errors.endDate?.message} required>
              <DatePicker
                control={control}
                name="endDate"
              />
            </FormField>
          </div>

          <FormField label="Bid Deadline" error={errors.bidDeadline?.message} required>
            <DateTimePicker
              control={control}
              name="bidDeadline"
            />
          </FormField>

          <Alert>
            <Info className="h-4 w-4" />
            <AlertTitle>Note</AlertTitle>
            <AlertDescription>
              You can create RFQs without wallet balance. Funds are required only when awarding bids.
            </AlertDescription>
          </Alert>

          <div className="flex justify-end">
            <Button type="submit">Next: Line Items</Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
};
```

#### Step 2: Line Items

**Features:**
- Add/Remove line items dynamically
- Each line item:
  - Vehicle Type (dropdown, required)
  - Quantity (number, 1-50, required)
  - Seating Capacity (number, optional - for specific seat requirements)
  - Pickup Location (string, required)
  - Dropoff Location (string, required)
  - Pickup Date (date-time, required)
  - Dropoff Date (date-time, optional - for open-ended rentals)
  - Special Requirements (textarea, optional)
- Running total display (max 50 vehicles)
- Market price guidance per line item

**Component:**

```typescript
export const CreateRFQStep2 = ({ onNext, onBack, formData, setFormData }) => {
  const [lineItems, setLineItems] = useState<LineItem[]>(
    formData.step2?.lineItems || []
  );
  const { data: vehicleTypes } = useQuery({
    queryKey: ['vehicle-types'],
    queryFn: () => masterDataService.getVehicleTypes(),
  });

  const totalVehicles = useMemo(
    () => lineItems.reduce((sum, item) => sum + item.quantity, 0),
    [lineItems]
  );

  const addLineItem = () => {
    setLineItems([...lineItems, {
      id: generateId(),
      vehicleType: '',
      quantity: 1,
      seatingCapacity: undefined,
      pickupLocation: '',
      dropoffLocation: '',
      pickupDate: new Date(),
      dropoffDate: undefined,
      specialRequirements: '',
    }]);
  };

  const removeLineItem = (id: string) => {
    setLineItems(lineItems.filter(item => item.id !== id));
  };

  const updateLineItem = (id: string, updates: Partial<LineItem>) => {
    setLineItems(lineItems.map(item =>
      item.id === id ? { ...item, ...updates } : item
    ));
  };

  const onSubmit = () => {
    if (totalVehicles > 50) {
      toast.error('Total vehicles cannot exceed 50');
      return;
    }
    setFormData({ ...formData, step2: { lineItems } });
    onNext();
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Line Items</CardTitle>
        <CardDescription>
          Add vehicle requirements. Total vehicles: {totalVehicles} / 50
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {lineItems.map((item, index) => (
            <Card key={item.id} className="p-4">
              <div className="flex justify-between items-start mb-4">
                <h4 className="font-semibold">Line Item {index + 1}</h4>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => removeLineItem(item.id)}
                  disabled={lineItems.length === 1}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>

              <div className="grid md:grid-cols-2 gap-4">
                <FormField label="Vehicle Type" required>
                  <Select
                    value={item.vehicleType}
                    onValueChange={(value) => updateLineItem(item.id, { vehicleType: value })}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Select vehicle type" />
                    </SelectTrigger>
                    <SelectContent>
                      {vehicleTypes?.map((type) => (
                        <SelectItem key={type.code} value={type.code}>
                          {type.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>

                <FormField label="Quantity" required>
                  <Input
                    type="number"
                    min={1}
                    max={50}
                    value={item.quantity}
                    onChange={(e) => updateLineItem(item.id, {
                      quantity: parseInt(e.target.value) || 1
                    })}
                  />
                </FormField>

                <FormField label="Seating Capacity (Optional)">
                  <Input
                    type="number"
                    min={1}
                    value={item.seatingCapacity || ''}
                    onChange={(e) => updateLineItem(item.id, {
                      seatingCapacity: e.target.value ? parseInt(e.target.value) : undefined
                    })}
                    placeholder="e.g., 4, 7, 12"
                  />
                </FormField>

                <FormField label="Pickup Location" required>
                  <Input
                    value={item.pickupLocation}
                    onChange={(e) => updateLineItem(item.id, { pickupLocation: e.target.value })}
                    placeholder="Enter pickup location"
                  />
                </FormField>

                <FormField label="Dropoff Location" required>
                  <Input
                    value={item.dropoffLocation}
                    onChange={(e) => updateLineItem(item.id, { dropoffLocation: e.target.value })}
                    placeholder="Enter dropoff location"
                  />
                </FormField>

                <FormField label="Pickup Date" required>
                  <DateTimePicker
                    value={item.pickupDate}
                    onChange={(date) => updateLineItem(item.id, { pickupDate: date })}
                    minDate={new Date()}
                  />
                </FormField>

                <FormField label="Dropoff Date (Optional)">
                  <DateTimePicker
                    value={item.dropoffDate}
                    onChange={(date) => updateLineItem(item.id, { dropoffDate: date })}
                    minDate={item.pickupDate}
                  />
                </FormField>

                <FormField label="Special Requirements" className="md:col-span-2">
                  <Textarea
                    value={item.specialRequirements || ''}
                    onChange={(e) => updateLineItem(item.id, { specialRequirements: e.target.value })}
                    placeholder="Any special requirements or notes..."
                    rows={3}
                  />
                </FormField>
              </div>

              {item.vehicleType && (
                <MarketPriceGuidance vehicleType={item.vehicleType} />
              )}
            </Card>
          ))}
        </div>

        <Button
          type="button"
          variant="outline"
          onClick={addLineItem}
          disabled={totalVehicles >= 50}
          className="w-full mt-4"
        >
          <Plus className="h-4 w-4 mr-2" />
          Add Line Item
        </Button>

        <div className="flex justify-between mt-6">
          <Button type="button" variant="outline" onClick={onBack}>
            Back
          </Button>
          <Button onClick={onSubmit} disabled={lineItems.length === 0 || totalVehicles > 50}>
            Next: Review
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};
```

#### Step 3: Review & Publish

**Features:**
- Summary of all RFQ details
- Line items summary table
- Estimated market price range
- Save as Draft button
- Publish RFQ button

**Component:**

```typescript
export const CreateRFQStep3 = ({ onBack, formData, setFormData }) => {
  const navigate = useNavigate();
  const createRFQ = useCreateRFQ();
  const publishRFQ = usePublishRFQ();

  const handleSaveDraft = async () => {
    try {
      const rfq = await createRFQ.mutateAsync({
        ...formData.step1,
        lineItems: formData.step2.lineItems,
        status: 'DRAFT',
      });
      toast.success('RFQ saved as draft');
      navigate(`/business/rfqs/${rfq.id}`);
    } catch (error) {
      handleApiError(error);
    }
  };

  const handlePublish = async () => {
    try {
      const rfq = await createRFQ.mutateAsync({
        ...formData.step1,
        lineItems: formData.step2.lineItems,
        status: 'DRAFT',
      });
      await publishRFQ.mutateAsync(rfq.id);
      toast.success('RFQ published successfully');
      navigate(`/business/rfqs/${rfq.id}`);
    } catch (error) {
      handleApiError(error);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Review & Publish</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-6">
          <div>
            <h3 className="font-semibold mb-2">Basic Information</h3>
            <div className="bg-gray-50 p-4 rounded">
              <p><strong>Title:</strong> {formData.step1.title}</p>
              <p><strong>Start Date:</strong> {formatDate(formData.step1.startDate)}</p>
              <p><strong>End Date:</strong> {formatDate(formData.step1.endDate)}</p>
              <p><strong>Bid Deadline:</strong> {formatDateTime(formData.step1.bidDeadline)}</p>
            </div>
          </div>

          <div>
            <h3 className="font-semibold mb-2">Line Items</h3>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Vehicle Type</TableHead>
                  <TableHead>Quantity</TableHead>
                  <TableHead>With Driver</TableHead>
                  <TableHead>Tags</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {formData.step2.lineItems.map((item, index) => (
                  <TableRow key={index}>
                    <TableCell>{getVehicleTypeLabel(item.vehicleTypeCode)}</TableCell>
                    <TableCell>{item.quantityRequired}</TableCell>
                    <TableCell>{item.withDriver ? 'Yes' : 'No'}</TableCell>
                    <TableCell>{item.preferredTags.join(', ') || '-'}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>

          <div className="flex justify-between">
            <Button variant="outline" onClick={onBack}>
              Back
            </Button>
            <div className="flex gap-2">
              <Button variant="outline" onClick={handleSaveDraft}>
                Save as Draft
              </Button>
              <Button onClick={handlePublish}>
                Publish RFQ
              </Button>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
```

### RFQ Detail Page

**Route:** `/business/rfqs/{id}`  
**Component:** `src/features/business/rfq/pages/RFQDetailPage.tsx`

**Features:**
- Full RFQ information display
- Line items table with bid counts
- Status timeline
- Action buttons based on status:
  - Draft: Edit, Delete, Publish
  - Published: View Bids, Cancel
  - Bidding Closed: View Bids, Award
  - Awarded: View Contract

---

## 💰 Bid Review & Award

### Bid Review Page

**Route:** `/business/rfqs/{id}/bids`  
**Component:** `src/features/business/rfq/pages/BidReviewPage.tsx`

**CRITICAL FEATURE:** This is the most complex screen in the Business Portal.

#### Features
- **Grouped by Line Item** (Tabs or Accordion)
- **Blind Bidding Display:**
  - Provider Hash: "Provider •••4411"
  - Quantity Offered
  - Unit Price
  - Total Price
  - Trust Score (if available)
  - Submission Time
- **Multi-Select Checkboxes** for award selection
- **Sorting Options:**
  - Price (Low to High) - Default
  - Price (High to Low)
  - Quantity (High to Low)
  - Trust Score (High to Low)
  - Submission Time
- **Split Award Support:**
  - Can select multiple bids for same line item
  - Can specify quantity per selected bid
- **Bottom Action Bar:**
  - Selected bids count
  - Total escrow required
  - "Award Selected Bids" button

#### Implementation

```typescript
import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useRFQ } from '../hooks/useRFQ';
import { useBids } from '../hooks/useBids';
import { AwardConfirmationModal } from '../components/AwardConfirmationModal';

export const BidReviewPage = () => {
  const { id } = useParams();
  const { data: rfq } = useRFQ(id!);
  const { data: bidsData } = useBids(id!);
  const [selectedBids, setSelectedBids] = useState<Map<string, Set<string>>>(new Map());
  const [sortBy, setSortBy] = useState<'price' | 'quantity' | 'trustScore' | 'time'>('price');
  const [showAwardModal, setShowAwardModal] = useState(false);

  // Group bids by line item
  const bidsByLineItem = useMemo(() => {
    if (!bidsData) return new Map();
    
    const grouped = new Map();
    bidsData.lineItems.forEach((lineItem) => {
      const sortedBids = [...lineItem.bids].sort((a, b) => {
        switch (sortBy) {
          case 'price':
            return a.unitPrice - b.unitPrice;
          case 'quantity':
            return b.quantityOffered - a.quantityOffered;
          case 'trustScore':
            return (b.trustScore || 0) - (a.trustScore || 0);
          case 'time':
            return new Date(a.submittedAt).getTime() - new Date(b.submittedAt).getTime();
          default:
            return 0;
        }
      });
      grouped.set(lineItem.lineItemId, {
        lineItem,
        bids: sortedBids,
      });
    });
    return grouped;
  }, [bidsData, sortBy]);

  const handleBidSelect = (lineItemId: string, bidId: string) => {
    setSelectedBids((prev) => {
      const newMap = new Map(prev);
      const bids = newMap.get(lineItemId) || new Set();
      if (bids.has(bidId)) {
        bids.delete(bidId);
      } else {
        bids.add(bidId);
      }
      newMap.set(lineItemId, bids);
      return newMap;
    });
  };

  const calculateTotalEscrow = () => {
    let total = 0;
    selectedBids.forEach((bidIds, lineItemId) => {
      const lineItemData = bidsByLineItem.get(lineItemId);
      if (lineItemData) {
        bidIds.forEach((bidId) => {
          const bid = lineItemData.bids.find((b) => b.bidId === bidId);
          if (bid) {
            total += bid.totalPrice;
          }
        });
      }
    });
    return total;
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold">{rfq?.title}</h1>
          <p className="text-gray-600">RFQ Number: {rfq?.rfqNumber}</p>
        </div>
        <Select value={sortBy} onValueChange={setSortBy}>
          <SelectTrigger className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="price">Price (Low to High)</SelectItem>
            <SelectItem value="quantity">Quantity (High to Low)</SelectItem>
            <SelectItem value="trustScore">Trust Score</SelectItem>
            <SelectItem value="time">Submission Time</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <Tabs defaultValue={Array.from(bidsByLineItem.keys())[0]}>
        <TabsList>
          {Array.from(bidsByLineItem.entries()).map(([lineItemId, data]) => (
            <TabsTrigger key={lineItemId} value={lineItemId}>
              {data.lineItem.vehicleTypeCode} ({data.bids.length} bids)
            </TabsTrigger>
          ))}
        </TabsList>

        {Array.from(bidsByLineItem.entries()).map(([lineItemId, data]) => (
          <TabsContent key={lineItemId} value={lineItemId} className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>
                  {getVehicleTypeLabel(data.lineItem.vehicleTypeCode)} - 
                  Quantity Required: {data.lineItem.quantityRequired}
                </CardTitle>
              </CardHeader>
              <CardContent>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-12">
                        <Checkbox
                          checked={selectedBids.get(lineItemId)?.size === data.bids.length}
                          onCheckedChange={(checked) => {
                            if (checked) {
                              setSelectedBids((prev) => {
                                const newMap = new Map(prev);
                                newMap.set(lineItemId, new Set(data.bids.map(b => b.bidId)));
                                return newMap;
                              });
                            } else {
                              setSelectedBids((prev) => {
                                const newMap = new Map(prev);
                                newMap.delete(lineItemId);
                                return newMap;
                              });
                            }
                          }}
                        />
                      </TableHead>
                      <TableHead>Provider</TableHead>
                      <TableHead>Quantity Offered</TableHead>
                      <TableHead>Unit Price</TableHead>
                      <TableHead>Total Price</TableHead>
                      <TableHead>Trust Score</TableHead>
                      <TableHead>Submitted</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.bids.map((bid) => (
                      <TableRow key={bid.bidId}>
                        <TableCell>
                          <Checkbox
                            checked={selectedBids.get(lineItemId)?.has(bid.bidId) || false}
                            onCheckedChange={() => handleBidSelect(lineItemId, bid.bidId)}
                          />
                        </TableCell>
                        <TableCell className="font-mono">{bid.providerHash}</TableCell>
                        <TableCell>{bid.quantityOffered}</TableCell>
                        <TableCell>{formatCurrency(bid.unitPrice)} ETB</TableCell>
                        <TableCell>{formatCurrency(bid.totalPrice)} ETB</TableCell>
                        <TableCell>
                          {bid.trustScore ? (
                            <Badge variant="outline">{bid.trustScore}/100</Badge>
                          ) : (
                            '-'
                          )}
                        </TableCell>
                        <TableCell>{formatDateTime(bid.submittedAt)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          </TabsContent>
        ))}
      </Tabs>

      {/* Bottom Action Bar */}
      <div className="fixed bottom-0 left-0 right-0 bg-white border-t p-4 shadow-lg">
        <div className="max-w-7xl mx-auto flex justify-between items-center">
          <div>
            <p className="text-sm text-gray-600">
              Selected: {Array.from(selectedBids.values()).reduce((sum, set) => sum + set.size, 0)} bids
            </p>
            <p className="font-semibold">
              Total Escrow Required: {formatCurrency(calculateTotalEscrow())} ETB
            </p>
          </div>
          <Button
            onClick={() => setShowAwardModal(true)}
            disabled={selectedBids.size === 0}
            size="lg"
          >
            Award Selected Bids
          </Button>
        </div>
      </div>

      {showAwardModal && (
        <AwardConfirmationModal
          rfqId={id!}
          selectedBids={selectedBids}
          bidsData={bidsData}
          onClose={() => setShowAwardModal(false)}
        />
      )}
    </div>
  );
};
```

### Partial Award Handling

**Rule BR-007:** Business can award fewer vehicles than requested if wallet balance is insufficient.

#### Partial Award Dialog Component

```typescript
interface PartialAwardDialogProps {
  requested: number;
  affordable: number;
  required: number;
  available: number;
  onDeposit: () => void;
  onPartialAward: () => void;
  onCancel: () => void;
}

export const PartialAwardDialog = ({
  requested,
  affordable,
  required,
  available,
  onDeposit,
  onPartialAward,
  onCancel,
}: PartialAwardDialogProps) => {
  return (
    <Dialog open onOpenChange={onCancel}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Insufficient Wallet Balance</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <Alert variant="warning">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>
              Your balance is sufficient for {affordable} vehicles out of {requested} requested.
            </AlertDescription>
          </Alert>

          <div className="bg-gray-50 p-4 rounded space-y-2">
            <div className="flex justify-between">
              <span>Required Escrow:</span>
              <span className="font-semibold">{formatCurrency(required)} ETB</span>
            </div>
            <div className="flex justify-between">
              <span>Available Balance:</span>
              <span className="font-semibold">{formatCurrency(available)} ETB</span>
            </div>
            <div className="flex justify-between text-red-600">
              <span>Shortfall:</span>
              <span className="font-semibold">{formatCurrency(required - available)} ETB</span>
            </div>
          </div>

          <div className="space-y-2">
            <p className="text-sm font-medium">What would you like to do?</p>
            <div className="space-y-2">
              <Button onClick={onDeposit} className="w-full">
                Deposit Funds & Award All {requested} Vehicles
              </Button>
              <Button onClick={onPartialAward} variant="outline" className="w-full">
                Award {affordable} Vehicles Only
              </Button>
              <Button onClick={onCancel} variant="ghost" className="w-full">
                Cancel
              </Button>
            </div>
          </div>

          <Alert>
            <Info className="h-4 w-4" />
            <AlertDescription className="text-xs">
              To award the remaining {requested - affordable} vehicles, you'll need to create a new RFQ.
            </AlertDescription>
          </Alert>
        </div>
      </DialogContent>
    </Dialog>
  );
};
```

#### Integration in BidReviewPage

```typescript
const handleAwardBids = async () => {
  const totalEscrow = calculateTotalEscrow();
  const { data: wallet } = await walletService.getWallet();
  
  if (totalEscrow > wallet.availableBalance) {
    const maxAffordable = calculateMaxAffordableVehicles(wallet.availableBalance);
    
    setPartialAwardDialog({
      show: true,
      requested: selectedBids.size,
      affordable: maxAffordable,
      required: totalEscrow,
      available: wallet.availableBalance,
    });
    return;
  }
  
  // Proceed with full award
  await awardBids();
};
```

### Award Confirmation Modal

**Component:** `src/features/business/rfq/components/AwardConfirmationModal.tsx`

**CRITICAL:** This modal handles wallet validation and partial award logic.

```typescript
export const AwardConfirmationModal = ({
  rfqId,
  selectedBids,
  bidsData,
  onClose,
}) => {
  const { data: wallet } = useQuery({
    queryKey: ['wallet', 'me'],
    queryFn: () => walletService.getWallet(),
  });

  const awardMutation = useAwardBids();

  const [awardDetails, setAwardDetails] = useState<AwardDetail[]>([]);
  const [insufficientFunds, setInsufficientFunds] = useState(false);

  useEffect(() => {
    // Calculate award details
    const details: AwardDetail[] = [];
    let totalEscrow = 0;

    selectedBids.forEach((bidIds, lineItemId) => {
      const lineItemData = bidsData?.lineItems.find(li => li.lineItemId === lineItemId);
      if (lineItemData) {
        bidIds.forEach((bidId) => {
          const bid = lineItemData.bids.find(b => b.bidId === bidId);
          if (bid) {
            const quantityAwarded = bid.quantityOffered; // Can be adjusted for partial
            const escrowAmount = quantityAwarded * bid.unitPrice;
            totalEscrow += escrowAmount;
            
            details.push({
              lineItemId,
              bidId,
              providerHash: bid.providerHash,
              quantityAwarded,
              unitPrice: bid.unitPrice,
              totalAmount: escrowAmount,
            });
          }
        });
      }
    });

    setAwardDetails(details);
    
    // Check wallet balance
    if (wallet && wallet.availableBalance < totalEscrow) {
      setInsufficientFunds(true);
    } else {
      setInsufficientFunds(false);
    }
  }, [selectedBids, bidsData, wallet]);

  const handleAward = async () => {
    const awards = awardDetails.map(detail => ({
      lineItemId: detail.lineItemId,
      bidId: detail.bidId,
      quantityAwarded: detail.quantityAwarded,
    }));

    try {
      await awardMutation.mutateAsync({
        rfqId,
        awards,
      });
      toast.success('Bids awarded successfully');
      onClose();
      navigate(`/business/contracts`);
    } catch (error: any) {
      if (error.response?.data?.error?.code === 'INSUFFICIENT_FUNDS') {
        // Handle insufficient funds error
        setInsufficientFunds(true);
      } else {
        handleApiError(error);
      }
    }
  };

  const totalEscrow = awardDetails.reduce((sum, d) => sum + d.totalAmount, 0);
  const shortfall = wallet ? Math.max(0, totalEscrow - wallet.availableBalance) : 0;

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Award Bids</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {/* Wallet Balance Display */}
          <Card>
            <CardContent className="pt-6">
              <div className="grid grid-cols-3 gap-4">
                <div>
                  <p className="text-sm text-gray-600">Available Balance</p>
                  <p className="text-2xl font-bold text-green-600">
                    {formatCurrency(wallet?.availableBalance || 0)} ETB
                  </p>
                </div>
                <div>
                  <p className="text-sm text-gray-600">Required Escrow</p>
                  <p className="text-2xl font-bold">
                    {formatCurrency(totalEscrow)} ETB
                  </p>
                </div>
                {insufficientFunds && (
                  <div>
                    <p className="text-sm text-gray-600">Shortfall</p>
                    <p className="text-2xl font-bold text-red-600">
                      {formatCurrency(shortfall)} ETB
                    </p>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Insufficient Funds Warning */}
          {insufficientFunds && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertTitle>Insufficient Funds</AlertTitle>
              <AlertDescription>
                Your available balance is not sufficient to award all selected bids.
                <div className="mt-2 space-y-2">
                  <p>Options:</p>
                  <ul className="list-disc list-inside space-y-1">
                    <li>Deposit more funds to your wallet</li>
                    <li>Award partial quantity (fewer vehicles)</li>
                    <li>Cancel and select different bids</li>
                  </ul>
                </div>
              </AlertDescription>
            </Alert>
          )}

          {/* Selected Bids Table */}
          <div>
            <h3 className="font-semibold mb-2">Selected Bids</h3>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Provider</TableHead>
                  <TableHead>Line Item</TableHead>
                  <TableHead>Quantity</TableHead>
                  <TableHead>Unit Price</TableHead>
                  <TableHead>Total</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {awardDetails.map((detail, index) => (
                  <TableRow key={index}>
                    <TableCell className="font-mono">{detail.providerHash}</TableCell>
                    <TableCell>
                      {bidsData?.lineItems.find(li => li.lineItemId === detail.lineItemId)?.vehicleTypeCode}
                    </TableCell>
                    <TableCell>{detail.quantityAwarded}</TableCell>
                    <TableCell>{formatCurrency(detail.unitPrice)} ETB</TableCell>
                    <TableCell>{formatCurrency(detail.totalAmount)} ETB</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          {insufficientFunds ? (
            <>
              <Button
                variant="outline"
                onClick={() => navigate('/business/wallet')}
              >
                Top-up Wallet
              </Button>
              <Button
                variant="outline"
                onClick={() => {
                  // Show partial award dialog
                }}
              >
                Award Partial
              </Button>
            </>
          ) : (
            <Button onClick={handleAward} disabled={awardMutation.isPending}>
              {awardMutation.isPending ? 'Awarding...' : 'Confirm Award'}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
```

---

## 📄 Contract Management

### Contract List Page

**Route:** `/business/contracts`  
**Component:** `src/features/business/contracts/pages/ContractListPage.tsx`

**Features:**
- **Tabs:** Pending Activation, Active, Completed, Terminated
- **Filters:**
  - Status
  - Date range
  - Provider name
  - Contract number search
- **Contract Cards:**
  - Contract Number
  - Provider Name
  - Total Value
  - Status Badge
  - Vehicle Count (Active / Total)
  - Start & End Dates
  - Actions: View Details, Request Early Return (if active)

### Contract Detail Page

**Route:** `/business/contracts/{id}`  
**Component:** `src/features/business/contracts/pages/ContractDetailPage.tsx`

**Sections:**
1. **Contract Header** - Number, status, dates
2. **Line Items Table** - Vehicle types, quantities, amounts
3. **Vehicle Assignments** - Plate numbers, delivery status, OTP status
4. **Financial Summary** - Total, escrow, penalties
5. **Actions** - Early return, view evidence, download PDF

---

## 💳 Wallet Management

### Wallet Dashboard

**Route:** `/business/wallet`  
**Component:** `src/features/business/wallet/pages/WalletPage.tsx`

**Features:**
- **Summary Cards:**
  - Total Balance
  - Available Balance (green)
  - Locked Balance (yellow/orange)
- **Transaction History Table:**
  - Date, Type, Amount, Status, Reference
  - Filters: Date range, Type
  - Pagination
- **Deposit Funds Button**

### Deposit Funds Modal

**Component:** `src/features/business/wallet/components/DepositModal.tsx`

**Fields:**
- Amount (number input, min 100 ETB)
- Payment Method (radio: Chapa, Telebirr)

**Flow:**
1. User enters amount
2. Selects payment method
3. Clicks "Deposit"
4. API returns checkout URL
5. Redirect to payment gateway
6. Return to wallet page after payment

---

## ⚙️ Profile & Settings

### Profile Page

**Route:** `/business/profile`  
**Component:** `src/features/business/profile/ProfilePage.tsx`

**Tabs:**
1. **Details** - Editable business information
2. **Documents** - View uploaded documents, upload new
3. **Settings** - Notification preferences, change password

**Tier Display:**
- Badge showing current tier (STANDARD, BUSINESS_PRO, ENTERPRISE, GOV_NGO)
- Tier benefits listed
- Progress to next tier (if applicable)

---

## ✅ User Stories Summary

### Epic 2: RFQ Management (15 stories)
- MOV-201: Create Multi-Line RFQ ⭐ Highest Priority
- MOV-202: View and Filter RFQ List
- MOV-203: View RFQ Details
- MOV-204: Edit Draft RFQ
- MOV-205: Delete Draft RFQ
- MOV-206: Clone Existing RFQ
- MOV-207: Cancel Published RFQ
- MOV-211: RFQ Notifications
- And 7 more...

### Epic 3: Bidding & Award (10 stories)
- MOV-301: View Blind Bids ⭐ Highest Priority
- MOV-302: Award Bids with Wallet Validation ⭐ Highest Priority
- MOV-303: Bid Comparison Tool
- MOV-305: Award Partial Quantities
- MOV-306: Split Awards (Multiple Providers)
- And 5 more...

### Epic 4: Wallet Management (8 stories)
- MOV-401: View Wallet Balance
- MOV-402: Deposit Funds
- MOV-403: View Transaction History
- And 5 more...

### Epic 5: Contract Management (7 stories)
- MOV-501: View Contract List
- MOV-502: View Contract Details
- MOV-503: Request Early Return
- And 4 more...

---

## 🔍 Search & Filter Specifications

### RFQ List Filters

```typescript
interface RFQFilters {
  status?: 'DRAFT' | 'PUBLISHED' | 'BIDDING_CLOSED' | 'AWARDED';
  startDateFrom?: string; // ISO date
  startDateTo?: string;   // ISO date
  vehicleTypeCode?: string;
  search?: string;         // Full-text search
  pageNumber?: number;
  pageSize?: number;
  sortBy?: 'createdAt' | 'bidDeadline' | 'title';
  sortDescending?: boolean;
}
```

### Contract List Filters

```typescript
interface ContractFilters {
  status?: 'PENDING_ACTIVATION' | 'ACTIVE' | 'COMPLETED' | 'TERMINATED';
  startDateFrom?: string;
  startDateTo?: string;
  providerId?: string;
  contractNumber?: string;
  pageNumber?: number;
  pageSize?: number;
}
```

---

## 📄 Pagination Implementation

All list pages use server-side pagination:

```typescript
const [pagination, setPagination] = useState({
  pageNumber: 1,
  pageSize: 20,
});

const { data } = useQuery({
  queryKey: ['rfqs', filters, pagination],
  queryFn: () => rfqService.getRFQs({ ...filters, ...pagination }),
});

// Pagination component
<Pagination
  currentPage={data?.pagination.page || 1}
  totalPages={data?.pagination.totalPages || 1}
  onPageChange={(page) => setPagination({ ...pagination, pageNumber: page })}
/>
```

---

## 🧪 Testing Scenarios

### RFQ Creation
- ✅ Create RFQ with single line item
- ✅ Create RFQ with multiple line items
- ✅ Validate date constraints
- ✅ Validate vehicle quantity limit (50)
- ✅ Save as draft
- ✅ Publish RFQ
- ✅ Edit draft RFQ

### Bid Award
- ✅ Award with sufficient balance
- ✅ Award with insufficient balance (show options)
- ✅ Partial award
- ✅ Split award (multiple providers)
- ✅ Provider identity revealed after award

### Wallet
- ✅ View balance
- ✅ Deposit funds
- ✅ View transactions
- ✅ Filter transactions

---

**END OF BUSINESS PORTAL GUIDE**

*For Provider Portal, see [PROVIDER_PORTAL_GUIDE.md](./PROVIDER_PORTAL_GUIDE.md)*  
*For API details, see [API_INTEGRATION_SPEC.md](./API_INTEGRATION_SPEC.md)*

