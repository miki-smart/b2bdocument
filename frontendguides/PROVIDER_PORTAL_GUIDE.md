# Provider Portal Development Guide
## Movello Frontend - React Implementation

**Version:** 1.0  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)

---

## 📋 Table of Contents

1. [Dashboard](#dashboard)
2. [Marketplace & Bidding](#marketplace--bidding)
3. [Fleet Management](#fleet-management)
4. [Contract & Delivery](#contract--delivery)
5. [Wallet & Settlements](#wallet--settlements)
6. [Profile & Settings](#profile--settings)

---

## 📊 Dashboard

### Route
`/provider/dashboard`

### Features
- **Stat Cards:**
  - Active Contracts count
  - Fleet Status (pie chart: Active/Assigned/Maintenance)
  - Wallet Balance
  - Trust Score (gauge display)
- **Quick Actions:**
  - Browse Marketplace
  - Manage Fleet
  - View Earnings
- **Recent Activity:**
  - New bids submitted
  - Contracts awarded
  - Settlements received

---

## 🛒 Marketplace & Bidding

### Marketplace Browse Page

**Route:** `/provider/marketplace`  
**Component:** `src/features/provider/marketplace/pages/MarketplacePage.tsx`

**CRITICAL FEATURE:** This is the most important screen for providers.

#### Features

**Left Sidebar Filters:**
- **Vehicle Type** (multi-select checkboxes)
  - EV_SEDAN, SEDAN, SUV, MINIBUS_12, BUS_30, etc.
- **Duration** (radio buttons)
  - Short-term (< 7 days)
  - Long-term (≥ 30 days)
  - All
- **Location** (dropdown)
  - Cities: Addis Ababa, Dire Dawa, Mekelle, etc.
- **Search by Title** (text input with debounce)

**Sorting Dropdown:**
- Posting Date (Newest First) - Default
- Posting Date (Oldest First)
- Popularity (Most Bids)
- Popularity (Least Bids)

**RFQ Cards Grid:**
- Title
- Business Name (visible)
- Date Range (Start - End)
- Line Items Summary (e.g., "5× EV Sedan, 2× Minibus")
- Bid Count per Line Item (badges)
- Bid Deadline (with countdown)
- "Bid Now" button
- "Save" icon (bookmark)

**Pagination:**
- Page numbers or "Load More" button

#### Implementation

```typescript
import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { RFQCard } from '../components/RFQCard';
import { MarketplaceFilters } from '../components/MarketplaceFilters';

export const MarketplacePage = () => {
  const [filters, setFilters] = useState<MarketplaceFilters>({
    vehicleTypes: [],
    duration: 'ALL',
    location: '',
    search: '',
    pageNumber: 1,
    pageSize: 20,
  });
  const [sortBy, setSortBy] = useState<'NEWEST' | 'OLDEST' | 'MOST_BIDS' | 'LEAST_BIDS'>('NEWEST');

  const { data, isLoading } = useQuery({
    queryKey: ['rfqs', 'open', filters, sortBy],
    queryFn: () => rfqService.getOpenRFQs({
      ...filters,
      sortBy,
      sortDescending: sortBy === 'NEWEST',
    }),
  });

  return (
    <div className="flex gap-6">
      {/* Filters Sidebar */}
      <aside className="w-64 flex-shrink-0">
        <MarketplaceFilters
          filters={filters}
          onFiltersChange={setFilters}
        />
      </aside>

      {/* Main Content */}
      <main className="flex-1">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-2xl font-bold">Browse RFQs</h1>
          <Select value={sortBy} onValueChange={setSortBy}>
            <SelectTrigger className="w-48">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="NEWEST">Newest First</SelectItem>
              <SelectItem value="OLDEST">Oldest First</SelectItem>
              <SelectItem value="MOST_BIDS">Most Bids</SelectItem>
              <SelectItem value="LEAST_BIDS">Least Bids</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {isLoading ? (
          <LoadingState />
        ) : data?.data.length === 0 ? (
          <EmptyState
            title="No RFQs found"
            description="Try adjusting your filters"
          />
        ) : (
          <>
            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
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
      </main>
    </div>
  );
};
```

### RFQ Detail & Bidding Page

**Route:** `/provider/marketplace/rfq/{id}`  
**Component:** `src/features/provider/marketplace/pages/RFQBiddingPage.tsx`

**CRITICAL:** This page allows providers to submit bids.

#### Layout
- **Left Panel:** RFQ Details
- **Right Panel:** Bidding Form

#### Bidding Form

**Per Line Item:**
- Vehicle Type (read-only)
- Quantity Required (read-only)
- Quantity to Offer (input, ≤ quantity required)
- Unit Price (input, with validation)
- Notes (optional textarea)
- Vehicle Selection (dropdown of provider's available vehicles)

**Price Validation:**
- Floor: 50% of market average
- Ceiling: 200% of market average
- Real-time feedback on price

**Eligibility Check:**
- Provider has enough active vehicles
- All vehicles have valid insurance
- Insurance covers contract period

#### Implementation

```typescript
export const RFQBiddingPage = () => {
  const { id } = useParams();
  const { data: rfq } = useRFQ(id!);
  const { data: vehicles } = useQuery({
    queryKey: ['vehicles', 'active'],
    queryFn: () => vehicleService.getActiveVehicles(),
  });
  const { data: marketPrices } = useQuery({
    queryKey: ['market-prices'],
    queryFn: () => masterDataService.getMarketPrices(),
  });

  const [lineItemBids, setLineItemBids] = useState<LineItemBid[]>([]);
  const submitBid = useSubmitBid();

  const handleBidSubmit = async () => {
    // Validate all line items
    for (const bid of lineItemBids) {
      if (!bid.quantityOffered || bid.quantityOffered <= 0) {
        toast.error(`Please specify quantity for ${bid.vehicleTypeCode}`);
        return;
      }
      if (!bid.unitPrice || bid.unitPrice <= 0) {
        toast.error(`Please specify price for ${bid.vehicleTypeCode}`);
        return;
      }

      // Check price range
      const priceRange = marketPrices?.[bid.vehicleTypeCode];
      if (priceRange) {
        if (bid.unitPrice < priceRange.floor || bid.unitPrice > priceRange.ceiling) {
          toast.error(`Price must be between ${priceRange.floor} and ${priceRange.ceiling} ETB`);
          return;
        }
      }

      // Check vehicle availability
      const availableVehicles = vehicles?.filter(v =>
        v.vehicleTypeCode === bid.vehicleTypeCode &&
        v.status === 'ACTIVE' &&
        v.currentContractId === null
      ) || [];
      
      if (availableVehicles.length < bid.quantityOffered) {
        toast.error(`You only have ${availableVehicles.length} available vehicles of type ${bid.vehicleTypeCode}`);
        return;
      }
    }

    try {
      await submitBid.mutateAsync({
        rfqId: id!,
        lineItemBids: lineItemBids.map(bid => ({
          lineItemId: bid.lineItemId,
          quantityOffered: bid.quantityOffered,
          unitPrice: bid.unitPrice,
          notes: bid.notes,
        })),
      });
      toast.success('Bid submitted successfully');
      navigate('/provider/bids');
    } catch (error) {
      handleApiError(error);
    }
  };

  return (
    <div className="grid lg:grid-cols-2 gap-6">
      {/* RFQ Details Panel */}
      <Card>
        <CardHeader>
          <CardTitle>{rfq?.title}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <p className="text-sm text-gray-600">Business</p>
            <p className="font-medium">{rfq?.businessName}</p>
          </div>
          <div>
            <p className="text-sm text-gray-600">Date Range</p>
            <p>{formatDate(rfq?.startDate)} - {formatDate(rfq?.endDate)}</p>
          </div>
          <div>
            <p className="text-sm text-gray-600">Bid Deadline</p>
            <CountdownTimer deadline={rfq?.bidDeadline} />
          </div>
          <div>
            <p className="text-sm text-gray-600">Description</p>
            <p>{rfq?.description}</p>
          </div>
        </CardContent>
      </Card>

      {/* Bidding Form Panel */}
      <Card>
        <CardHeader>
          <CardTitle>Submit Bid</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-6">
            {rfq?.lineItems.map((lineItem) => {
              const bid = lineItemBids.find(b => b.lineItemId === lineItem.id) || {
                lineItemId: lineItem.id,
                quantityOffered: 0,
                unitPrice: 0,
                notes: '',
              };
              const priceRange = marketPrices?.[lineItem.vehicleTypeCode];

              return (
                <Card key={lineItem.id} className="p-4">
                  <h4 className="font-semibold mb-4">
                    {getVehicleTypeLabel(lineItem.vehicleTypeCode)}
                  </h4>
                  
                  <div className="space-y-4">
                    <div>
                      <p className="text-sm text-gray-600">Quantity Required</p>
                      <p className="font-medium">{lineItem.quantityRequired}</p>
                    </div>

                    <FormField label="Quantity to Offer" required>
                      <Input
                        type="number"
                        min={1}
                        max={lineItem.quantityRequired}
                        value={bid.quantityOffered}
                        onChange={(e) => {
                          const value = parseInt(e.target.value) || 0;
                          setLineItemBids(prev => {
                            const updated = prev.filter(b => b.lineItemId !== lineItem.id);
                            updated.push({ ...bid, quantityOffered: value });
                            return updated;
                          });
                        }}
                      />
                    </FormField>

                    <FormField label="Unit Price (ETB)" required>
                      <Input
                        type="number"
                        min={priceRange?.floor || 0}
                        max={priceRange?.ceiling || 100000}
                        value={bid.unitPrice}
                        onChange={(e) => {
                          const value = parseFloat(e.target.value) || 0;
                          setLineItemBids(prev => {
                            const updated = prev.filter(b => b.lineItemId !== lineItem.id);
                            updated.push({ ...bid, unitPrice: value });
                            return updated;
                          });
                        }}
                      />
                      {priceRange && (
                        <p className="text-xs text-gray-500 mt-1">
                          Market range: {formatCurrency(priceRange.floor)} - {formatCurrency(priceRange.ceiling)} ETB
                        </p>
                      )}
                    </FormField>

                    <FormField label="Notes (Optional)">
                      <Textarea
                        value={bid.notes}
                        onChange={(e) => {
                          setLineItemBids(prev => {
                            const updated = prev.filter(b => b.lineItemId !== lineItem.id);
                            updated.push({ ...bid, notes: e.target.value });
                            return updated;
                          });
                        }}
                        rows={2}
                      />
                    </FormField>
                  </div>
                </Card>
              );
            })}

            <Button
              onClick={handleBidSubmit}
              disabled={submitBid.isPending || lineItemBids.length === 0}
              className="w-full"
            >
              {submitBid.isPending ? 'Submitting...' : 'Submit Bid'}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
```

### My Bids Page

**Route:** `/provider/bids`  
**Component:** `src/features/provider/bids/pages/MyBidsPage.tsx`

**Features:**
- List of all submitted bids
- **Table Columns:**
  - RFQ Title
  - Line Item
  - Quantity Offered
  - Unit Price
  - Total Price
  - Status (BIDDING, AWARDED, LOST, REJECTED, WITHDRAWN)
  - Submission Date
- **Filters:**
  - Status dropdown
  - Date range
- **Actions:**
  - View RFQ (link)
  - Withdraw Bid (if status is BIDDING)

---

## 🚗 Fleet Management

### Vehicle List Page

**Route:** `/provider/vehicles`  
**Component:** `src/features/provider/fleet/pages/VehicleListPage.tsx`

**Features:**
- **Filters:**
  - Status (Active, Assigned, Under Review, Maintenance, Suspended)
  - Vehicle Type
  - Insurance Status
- **View Toggle:**
  - Table view (desktop)
  - Card view (mobile)
- **Vehicle Cards/Table:**
  - Plate Number
  - Vehicle Type
  - Brand & Model
  - Year
  - Insurance Status (with expiry date)
  - Status Badge
  - Actions: View Details, Edit, Mark as Maintenance

### Vehicle Registration

**Route:** `/provider/vehicles/register`  
**Component:** `src/features/provider/fleet/pages/RegisterVehiclePage.tsx`

**CRITICAL:** Multi-step form with photo upload and insurance.

#### Step 1: Vehicle Information

**Fields:**
- Plate Number (required, unique, format: AA-12345)
- Vehicle Type (dropdown, required)
- Engine Type (dropdown, required)
- Brand (required)
- Model (required)
- Model Year (required, min 2010)
- Seat Count (required)
- Tags (multi-select: luxury, vip, guest, service, family)

#### Step 2: Photo Upload

**Required Photos (5):**
1. Front View (with visible plate)
2. Back View
3. Left Side
4. Right Side
5. Interior

**Validation:**
- Each photo required
- File type: JPEG, PNG
- Max size: 5MB per photo
- Front photo must show plate number clearly

#### Step 3: Insurance Information

**Fields:**
- Insurance Type (dropdown: Comprehensive, Third Party)
- Company Name (required)
- Policy Number (required)
- Insured Amount (required)
- Coverage Start Date (date picker)
- Coverage End Date (date picker, must be > today + 30 days)
- Certificate Upload (PDF, max 5MB)

**Component:**

```typescript
export const RegisterVehiclePage = () => {
  const [step, setStep] = useState(1);
  const [formData, setFormData] = useState<VehicleFormData>({});
  const [photos, setPhotos] = useState<Record<string, File>>({});
  const registerVehicle = useRegisterVehicle();

  const handleSubmit = async () => {
    try {
      // Step 1: Create vehicle
      const vehicle = await vehicleService.createVehicle({
        ...formData.vehicleInfo,
        status: 'UNDER_REVIEW',
      });

      // Step 2: Upload photos
      await vehicleService.uploadPhotos(vehicle.id, photos);

      // Step 3: Add insurance
      await vehicleService.addInsurance(vehicle.id, formData.insurance);

      toast.success('Vehicle submitted for review');
      navigate('/provider/vehicles');
    } catch (error) {
      handleApiError(error);
    }
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <Stepper currentStep={step} totalSteps={3} />
      
      {step === 1 && (
        <VehicleInfoStep
          data={formData.vehicleInfo}
          onNext={(data) => {
            setFormData({ ...formData, vehicleInfo: data });
            setStep(2);
          }}
        />
      )}
      
      {step === 2 && (
        <PhotoUploadStep
          photos={photos}
          onPhotosChange={setPhotos}
          onBack={() => setStep(1)}
          onNext={() => setStep(3)}
        />
      )}
      
      {step === 3 && (
        <InsuranceStep
          data={formData.insurance}
          onBack={() => setStep(2)}
          onSubmit={(data) => {
            setFormData({ ...formData, insurance: data });
            handleSubmit();
          }}
        />
      )}
    </div>
  );
};
```

### Vehicle Detail Page

**Route:** `/provider/vehicles/{id}`  
**Component:** `src/features/provider/fleet/pages/VehicleDetailPage.tsx`

**Sections:**
1. **Basic Information** - All vehicle details
2. **Insurance Details** - Policy info, expiry date, certificate
3. **Photo Gallery** - All 5 photos in lightbox
4. **Assignment History** - Past and current contracts
5. **Actions:**
  - Edit (if not assigned)
  - Mark as Maintenance
  - Delete (if not assigned and no history)

---

## 📦 Contract & Delivery

### Contract List Page

**Route:** `/provider/contracts`  
**Component:** `src/features/provider/contracts/pages/ContractListPage.tsx`

**Tabs:**
- Pending Assignment
- Active
- Completed

**Contract Cards:**
- Contract Number
- Business Name
- Line Items Summary
- Status Badge
- Actions: Assign Vehicles (if pending), View Details

### Vehicle Assignment Page

**Route:** `/provider/contracts/{id}/assign`  
**Component:** `src/features/provider/contracts/pages/VehicleAssignmentPage.tsx`

**CRITICAL:** This page allows providers to assign vehicles to contract line items.

#### Layout
- **Left Panel:** Required Vehicles (from contract)
  - Table: Vehicle Type, Quantity Needed, Quantity Assigned
- **Right Panel:** Available Fleet
  - Filterable by Vehicle Type
  - Table: Plate Number, Type, Model, Status
  - Checkbox selection

#### Implementation

```typescript
export const VehicleAssignmentPage = () => {
  const { id } = useParams();
  const { data: contract } = useContract(id!);
  const { data: vehicles } = useQuery({
    queryKey: ['vehicles', 'available'],
    queryFn: () => vehicleService.getAvailableVehicles(),
  });

  const [assignments, setAssignments] = useState<Map<string, string[]>>(new Map());
  const assignMutation = useAssignVehicle();

  const handleAssign = async () => {
    const assignmentRequests: AssignmentRequest[] = [];
    
    assignments.forEach((vehicleIds, lineItemId) => {
      vehicleIds.forEach((vehicleId) => {
        assignmentRequests.push({
          contractId: id!,
          contractLineItemId: lineItemId,
          vehicleId,
        });
      });
    });

    try {
      await assignMutation.mutateAsync(assignmentRequests);
      toast.success('Vehicles assigned successfully');
      navigate(`/provider/contracts/${id}`);
    } catch (error) {
      handleApiError(error);
    }
  };

  return (
    <div className="grid lg:grid-cols-2 gap-6">
      {/* Required Vehicles */}
      <Card>
        <CardHeader>
          <CardTitle>Required Vehicles</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Vehicle Type</TableHead>
                <TableHead>Required</TableHead>
                <TableHead>Assigned</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {contract?.lineItems.map((lineItem) => {
                const assigned = assignments.get(lineItem.id)?.length || 0;
                const isComplete = assigned >= lineItem.quantityAwarded;
                
                return (
                  <TableRow key={lineItem.id} className={isComplete ? 'bg-green-50' : ''}>
                    <TableCell>{getVehicleTypeLabel(lineItem.vehicleTypeCode)}</TableCell>
                    <TableCell>{lineItem.quantityAwarded}</TableCell>
                    <TableCell>
                      <span className={isComplete ? 'text-green-600 font-semibold' : ''}>
                        {assigned} / {lineItem.quantityAwarded}
                      </span>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Available Fleet */}
      <Card>
        <CardHeader>
          <CardTitle>Available Fleet</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {contract?.lineItems.map((lineItem) => {
              const availableVehicles = vehicles?.filter(v =>
                v.vehicleTypeCode === lineItem.vehicleTypeCode &&
                v.status === 'ACTIVE' &&
                v.currentContractId === null
              ) || [];

              return (
                <div key={lineItem.id} className="border rounded p-4">
                  <h4 className="font-semibold mb-2">
                    {getVehicleTypeLabel(lineItem.vehicleTypeCode)}
                  </h4>
                  <div className="space-y-2">
                    {availableVehicles.map((vehicle) => {
                      const isSelected = assignments.get(lineItem.id)?.includes(vehicle.id);
                      
                      return (
                        <label
                          key={vehicle.id}
                          className="flex items-center p-2 border rounded cursor-pointer hover:bg-gray-50"
                        >
                          <Checkbox
                            checked={isSelected || false}
                            onCheckedChange={(checked) => {
                              setAssignments((prev) => {
                                const newMap = new Map(prev);
                                const current = newMap.get(lineItem.id) || [];
                                if (checked) {
                                  newMap.set(lineItem.id, [...current, vehicle.id]);
                                } else {
                                  newMap.set(lineItem.id, current.filter(id => id !== vehicle.id));
                                }
                                return newMap;
                              });
                            }}
                            disabled={
                              !isSelected &&
                              (assignments.get(lineItem.id)?.length || 0) >= lineItem.quantityAwarded
                            }
                          />
                          <span className="ml-2">
                            {vehicle.plateNumber} - {vehicle.brand} {vehicle.model}
                          </span>
                        </label>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>

      <div className="lg:col-span-2 flex justify-end">
        <Button onClick={handleAssign} disabled={assignMutation.isPending}>
          Assign Vehicles
        </Button>
      </div>
    </div>
  );
};
```

### Delivery Session Flow

**Route:** `/provider/delivery/{sessionId}`  
**Component:** `src/features/provider/delivery/pages/DeliverySessionPage.tsx`

**CRITICAL:** Multi-step OTP verification and handover evidence flow.

#### Step 1: Generate OTP

```typescript
export const DeliveryOTPStep = ({ sessionId, onOTPGenerated }) => {
  const generateOTP = useMutation({
    mutationFn: () => deliveryService.generateOTP(sessionId),
  });

  const handleGenerate = async () => {
    try {
      const result = await generateOTP.mutateAsync();
      toast.success('OTP sent to business contact');
      onOTPGenerated(result.otp);
    } catch (error) {
      handleApiError(error);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Generate OTP</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="mb-4">
          Click the button below to generate and send OTP to the business contact.
          The OTP will also be displayed here for you to verify.
        </p>
        <Button onClick={handleGenerate} disabled={generateOTP.isPending}>
          {generateOTP.isPending ? 'Generating...' : 'Generate & Send OTP'}
        </Button>
      </CardContent>
    </Card>
  );
};
```

#### Step 2: OTP Verification

```typescript
export const OTPVerificationStep = ({ sessionId, otp, onVerified }) => {
  const [otpCode, setOtpCode] = useState(['', '', '', '', '', '']);
  const verifyOTP = useMutation({
    mutationFn: (code: string) => deliveryService.verifyOTP(sessionId, code),
  });

  const handleVerify = async () => {
    const code = otpCode.join('');
    if (code.length !== 6) {
      toast.error('Please enter 6-digit OTP');
      return;
    }

    try {
      await verifyOTP.mutateAsync(code);
      toast.success('OTP verified successfully');
      onVerified();
    } catch (error: any) {
      if (error.response?.data?.error?.code === 'INVALID_OTP') {
        toast.error(`Invalid OTP. ${error.response.data.error.details.attemptsRemaining} attempts remaining`);
      } else {
        handleApiError(error);
      }
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Verify OTP</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="mb-4">
          Enter the 6-digit OTP that was sent to the business contact.
          Ask them to share the OTP with you.
        </p>
        <div className="flex gap-2 justify-center mb-4">
          {otpCode.map((digit, index) => (
            <Input
              key={index}
              type="text"
              maxLength={1}
              value={digit}
              onChange={(e) => {
                const value = e.target.value.replace(/\D/g, '');
                setOtpCode(prev => {
                  const updated = [...prev];
                  updated[index] = value;
                  return updated;
                });
                // Auto-focus next input
                if (value && index < 5) {
                  document.getElementById(`otp-${index + 1}`)?.focus();
                }
              }}
              className="w-12 h-12 text-center text-2xl"
              id={`otp-${index}`}
            />
          ))}
        </div>
        <Button onClick={handleVerify} className="w-full" disabled={verifyOTP.isPending}>
          {verifyOTP.isPending ? 'Verifying...' : 'Verify OTP'}
        </Button>
      </CardContent>
    </Card>
  );
};
```

#### Step 3: Handover Evidence Upload

```typescript
export const HandoverEvidenceStep = ({ sessionId, onComplete }) => {
  const [photos, setPhotos] = useState<Record<string, File>>({});
  const [odometerReading, setOdometerReading] = useState('');
  const [fuelLevel, setFuelLevel] = useState<'EMPTY' | 'QUARTER' | 'HALF' | 'THREE_QUARTERS' | 'FULL'>('FULL');
  const [notes, setNotes] = useState('');
  
  const uploadEvidence = useMutation({
    mutationFn: (data: HandoverEvidence) => deliveryService.uploadHandoverEvidence(sessionId, data),
  });

  const handleSubmit = async () => {
    // Validate all photos uploaded
    const requiredPhotos = ['front', 'back', 'left', 'right', 'interior'];
    const missing = requiredPhotos.filter(key => !photos[key]);
    if (missing.length > 0) {
      toast.error(`Please upload all required photos: ${missing.join(', ')}`);
      return;
    }

    try {
      await uploadEvidence.mutateAsync({
        photos,
        odometerReading: parseInt(odometerReading),
        fuelLevel,
        notes,
      });
      toast.success('Handover evidence uploaded successfully');
      onComplete();
    } catch (error) {
      handleApiError(error);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Upload Handover Evidence</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="grid md:grid-cols-2 gap-4">
          {['front', 'back', 'left', 'right', 'interior'].map((position) => (
            <div key={position}>
              <label className="block text-sm font-medium mb-2 capitalize">
                {position} View {position === 'front' && '(with plate visible)'}
              </label>
              {photos[position] ? (
                <div className="relative">
                  <img
                    src={URL.createObjectURL(photos[position])}
                    alt={position}
                    className="w-full h-32 object-cover rounded"
                  />
                  <Button
                    variant="ghost"
                    size="sm"
                    className="absolute top-2 right-2"
                    onClick={() => {
                      setPhotos(prev => {
                        const updated = { ...prev };
                        delete updated[position];
                        return updated;
                      });
                    }}
                  >
                    <X className="h-4 w-4" />
                  </Button>
                </div>
              ) : (
                <FileUpload
                  onFileSelect={(file) => setPhotos(prev => ({ ...prev, [position]: file }))}
                  accept="image/jpeg,image/png"
                  maxSize={5 * 1024 * 1024}
                />
              )}
            </div>
          ))}
        </div>

        <div className="grid md:grid-cols-2 gap-4">
          <FormField label="Odometer Reading" required>
            <Input
              type="number"
              value={odometerReading}
              onChange={(e) => setOdometerReading(e.target.value)}
              placeholder="Enter odometer reading"
            />
          </FormField>

          <FormField label="Fuel Level" required>
            <Select value={fuelLevel} onValueChange={setFuelLevel}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="EMPTY">Empty</SelectItem>
                <SelectItem value="QUARTER">1/4 Full</SelectItem>
                <SelectItem value="HALF">1/2 Full</SelectItem>
                <SelectItem value="THREE_QUARTERS">3/4 Full</SelectItem>
                <SelectItem value="FULL">Full</SelectItem>
              </SelectContent>
            </Select>
          </FormField>
        </div>

        <FormField label="Notes (Optional)">
          <Textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Any damage or condition notes..."
            rows={3}
          />
        </FormField>

        <Button onClick={handleSubmit} className="w-full" disabled={uploadEvidence.isPending}>
          {uploadEvidence.isPending ? 'Uploading...' : 'Submit Handover Evidence'}
        </Button>
      </CardContent>
    </Card>
  );
};
```

---

## 💰 Wallet & Settlements

### Wallet Dashboard

**Route:** `/provider/wallet`  
**Component:** `src/features/provider/wallet/pages/WalletPage.tsx`

**Features:**
- **Summary Cards:**
  - Total Earnings (lifetime)
  - Available Balance (withdrawable)
  - Pending Settlement (in active contracts)
- **Transaction History Table**
- **Settlement History Link**

### Settlement History

**Route:** `/provider/wallet/settlements`  
**Component:** `src/features/provider/wallet/pages/SettlementHistoryPage.tsx`

**Table Columns:**
- Period (Month/Year)
- Gross Amount
- Commission Deducted
- Penalties
- Net Payout
- Status
- Payout Date

**Details Modal:**
- Breakdown per contract
- Commission calculation
- Penalty details

### Trust Score Display

**Component:** `src/features/provider/profile/components/TrustScoreDisplay.tsx`

**Features:**
- Circular gauge (0-100)
- Current Score
- Tier Badge
- Score Breakdown:
  - Completion Rate (30%)
  - On-Time Delivery (25%)
  - Reliability (20%)
  - Quality/Ratings (15%)
  - Dispute History (10%)
- Historical Chart (score over time)

---

## ⚙️ Profile & Settings

### Profile Page

**Route:** `/provider/profile`  
**Component:** `src/features/provider/profile/ProfilePage.tsx`

**Tabs:**
1. **Details** - Provider information
2. **Trust Score** - Score breakdown and history
3. **Documents** - Uploaded documents
4. **Settings** - Notification preferences

**Tier Display:**
- Current tier badge (BRONZE, SILVER, GOLD, PLATINUM)
- Tier benefits listed
- Progress to next tier
- Commission rate display

---

## ✅ User Stories Summary

### Epic 6: Fleet Management (12 stories)
- MOV-601: Register Vehicle ⭐ Highest Priority
- MOV-602: View Vehicle List
- MOV-603: Edit Vehicle Information
- MOV-604: Upload Vehicle Photos
- MOV-605: Add/Update Insurance
- And 7 more...

### Epic 7: Marketplace & Bidding (10 stories)
- MOV-701: Browse Marketplace RFQs ⭐ Highest Priority
- MOV-702: Submit Bid ⭐ Highest Priority
- MOV-703: View My Bids
- MOV-704: Withdraw Bid
- And 6 more...

### Epic 8: Delivery & OTP (8 stories)
- MOV-801: Assign Vehicles to Contract ⭐ Highest Priority
- MOV-802: Generate OTP ⭐ Highest Priority
- MOV-803: Verify OTP ⭐ Highest Priority
- MOV-804: Upload Handover Evidence ⭐ Highest Priority
- And 4 more...

### Epic 9: Wallet & Settlements (7 stories)
- MOV-901: View Wallet Balance
- MOV-902: View Settlement History
- MOV-903: View Trust Score
- And 4 more...

---

## 🔍 Marketplace Filter Implementation

### Filter State Management

```typescript
interface MarketplaceFilters {
  vehicleTypes: string[];      // Multi-select
  duration: 'SHORT' | 'LONG' | 'ALL';
  location: string;            // City code
  search: string;             // Title search
  pageNumber: number;
  pageSize: number;
}

// Filter component
export const MarketplaceFilters = ({ filters, onFiltersChange }) => {
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
        <div>
          <h4 className="font-semibold mb-2">Vehicle Type</h4>
          <div className="space-y-2">
            {vehicleTypes.map((type) => (
              <label key={type.code} className="flex items-center">
                <Checkbox
                  checked={filters.vehicleTypes.includes(type.code)}
                  onCheckedChange={() => handleVehicleTypeToggle(type.code)}
                />
                <span className="ml-2">{type.label}</span>
              </label>
            ))}
          </div>
        </div>

        <div>
          <h4 className="font-semibold mb-2">Duration</h4>
          <RadioGroup value={filters.duration} onValueChange={(value) => 
            onFiltersChange({ ...filters, duration: value as any, pageNumber: 1 })
          }>
            <div className="space-y-2">
              <label className="flex items-center">
                <RadioGroupItem value="SHORT" />
                <span className="ml-2">Short-term (&lt; 7 days)</span>
              </label>
              <label className="flex items-center">
                <RadioGroupItem value="LONG" />
                <span className="ml-2">Long-term (≥ 30 days)</span>
              </label>
              <label className="flex items-center">
                <RadioGroupItem value="ALL" />
                <span className="ml-2">All</span>
              </label>
            </div>
          </RadioGroup>
        </div>

        <FormField label="Location">
          <Select
            value={filters.location}
            onValueChange={(value) => onFiltersChange({ ...filters, location: value, pageNumber: 1 })}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select city" />
            </SelectTrigger>
            <SelectContent>
              {cities.map((city) => (
                <SelectItem key={city.code} value={city.code}>
                  {city.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </FormField>

        <FormField label="Search">
          <Input
            value={filters.search}
            onChange={(e) => onFiltersChange({ ...filters, search: e.target.value, pageNumber: 1 })}
            placeholder="Search by title..."
          />
        </FormField>

        <Button
          variant="outline"
          onClick={() => onFiltersChange({
            vehicleTypes: [],
            duration: 'ALL',
            location: '',
            search: '',
            pageNumber: 1,
            pageSize: 20,
          })}
          className="w-full"
        >
          Clear Filters
        </Button>
      </CardContent>
    </Card>
  );
};
```

---

## 🧪 Testing Scenarios

### Marketplace
- ✅ Browse RFQs with filters
- ✅ Search by title
- ✅ Sort by different criteria
- ✅ Save RFQ (bookmark)
- ✅ Submit bid
- ✅ Validate price range
- ✅ Validate vehicle availability

### Vehicle Registration
- ✅ Register vehicle with all required fields
- ✅ Upload all 5 photos
- ✅ Add insurance information
- ✅ Validate insurance expiry date
- ✅ Submit for review

### Delivery Flow
- ✅ Generate OTP
- ✅ Verify OTP (success)
- ✅ Verify OTP (invalid, retry)
- ✅ Upload handover evidence
- ✅ Complete delivery

---

**END OF PROVIDER PORTAL GUIDE**

*For Business Portal, see [BUSINESS_PORTAL_GUIDE.md](./BUSINESS_PORTAL_GUIDE.md)*  
*For API details, see [API_INTEGRATION_SPEC.md](./API_INTEGRATION_SPEC.md)*

