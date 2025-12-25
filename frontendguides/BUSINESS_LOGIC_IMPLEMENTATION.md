# Business Logic Implementation Guide
## Movello Frontend - React Implementation

**Version:** 1.0  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)  
**Reference:** [MVP_AUTHORITATIVE_BUSINESS_RULES.md](./MVP_MODULAR/MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md)

---

## 📋 Table of Contents

1. [Wallet Balance Validation](#wallet-balance-validation)
2. [Partial Award Calculation](#partial-award-calculation)
3. [Split Award Logic](#split-award-logic)
4. [Blind Bidding Implementation](#blind-bidding-implementation)
5. [OTP Flow](#otp-flow)
6. [Early Return Calculation](#early-return-calculation)
7. [Trust Score Display](#trust-score-display)
8. [Tier System Display](#tier-system-display)

---

## 💰 Wallet Balance Validation

### At Award Time

**Rule BR-006, BR-007:** Wallet balance is REQUIRED when awarding bids.

**Implementation:**

```typescript
// File: src/features/business/rfq/utils/wallet-validation.ts

export interface WalletValidationResult {
  isValid: boolean;
  requiredAmount: number;
  availableBalance: number;
  shortfall: number;
  maxAffordableQuantity?: number;
  options?: {
    action: 'DEPOSIT' | 'PARTIAL_AWARD' | 'CANCEL';
    amount?: number;
    quantity?: number;
    text: string;
  }[];
}

export const validateWalletForAward = (
  awards: AwardDetail[],
  wallet: Wallet
): WalletValidationResult => {
  // Calculate total escrow required
  const totalEscrowRequired = awards.reduce(
    (sum, award) => sum + award.totalAmount,
    0
  );

  const availableBalance = wallet.availableBalance;
  const shortfall = Math.max(0, totalEscrowRequired - availableBalance);

  if (availableBalance >= totalEscrowRequired) {
    return {
      isValid: true,
      requiredAmount: totalEscrowRequired,
      availableBalance,
      shortfall: 0,
    };
  }

  // Calculate max affordable quantity
  const maxAffordable = calculateMaxAffordableQuantity(awards, availableBalance);

  return {
    isValid: false,
    requiredAmount: totalEscrowRequired,
    availableBalance,
    shortfall,
    maxAffordableQuantity: maxAffordable.vehicleCount,
    options: [
      {
        action: 'DEPOSIT',
        amount: shortfall,
        text: `Deposit ${formatCurrency(shortfall)} ETB to award all vehicles`,
      },
      {
        action: 'PARTIAL_AWARD',
        quantity: maxAffordable.vehicleCount,
        text: `Award ${maxAffordable.vehicleCount} vehicles with current balance`,
      },
      {
        action: 'CANCEL',
        text: 'Cancel award',
      },
    ],
  };
};

const calculateMaxAffordableQuantity = (
  awards: AwardDetail[],
  availableBalance: number
): { vehicleCount: number; totalCost: number } => {
  // Sort awards by unit price (lowest first) to maximize vehicle count
  const sortedAwards = [...awards].sort((a, b) => a.unitPrice - b.unitPrice);

  let runningTotal = 0;
  let affordableVehicles = 0;

  for (const award of sortedAwards) {
    const costPerVehicle = award.unitPrice;
    const affordableFromThisAward = Math.floor(
      (availableBalance - runningTotal) / costPerVehicle
    );
    const actuallyAffordable = Math.min(
      affordableFromThisAward,
      award.quantityAwarded
    );

    affordableVehicles += actuallyAffordable;
    runningTotal += actuallyAffordable * costPerVehicle;

    if (runningTotal >= availableBalance) break;
  }

  return {
    vehicleCount: affordableVehicles,
    totalCost: runningTotal,
  };
};
```

### Usage in Award Modal

```typescript
const AwardConfirmationModal = ({ selectedBids, bidsData }) => {
  const { data: wallet } = useQuery({
    queryKey: ['wallet', 'me'],
    queryFn: () => walletService.getWallet(),
  });

  const validation = useMemo(() => {
    if (!wallet || !bidsData) return null;
    
    const awards = calculateAwardDetails(selectedBids, bidsData);
    return validateWalletForAward(awards, wallet);
  }, [wallet, selectedBids, bidsData]);

  return (
    <Dialog>
      {validation && !validation.isValid && (
        <Alert variant="destructive">
          <AlertTitle>Insufficient Funds</AlertTitle>
          <AlertDescription>
            <p>
              Required: {formatCurrency(validation.requiredAmount)} ETB
            </p>
            <p>
              Available: {formatCurrency(validation.availableBalance)} ETB
            </p>
            <p>
              Shortfall: {formatCurrency(validation.shortfall)} ETB
            </p>
            {validation.maxAffordableQuantity && (
              <p className="mt-2">
                You can award up to {validation.maxAffordableQuantity} vehicles
                with your current balance.
              </p>
            )}
          </AlertDescription>
        </Alert>
      )}
      
      {validation?.options && (
        <div className="space-y-2">
          {validation.options.map((option, index) => (
            <Button
              key={index}
              variant={option.action === 'CANCEL' ? 'outline' : 'default'}
              onClick={() => handleOption(option)}
              className="w-full"
            >
              {option.text}
            </Button>
          ))}
        </div>
      )}
    </Dialog>
  );
};
```

---

## 📊 Partial Award Calculation

### Calculate Partial Award

**Rule BR-007:** Business can award partial quantities based on available balance.

```typescript
// File: src/features/business/rfq/utils/partial-award.ts

export interface PartialAwardCalculation {
  originalAwards: AwardDetail[];
  partialAwards: AwardDetail[];
  totalVehiclesOriginal: number;
  totalVehiclesAffordable: number;
  totalCostOriginal: number;
  totalCostAffordable: number;
}

export const calculatePartialAward = (
  awards: AwardDetail[],
  availableBalance: number
): PartialAwardCalculation => {
  const sortedAwards = [...awards].sort((a, b) => a.unitPrice - b.unitPrice);
  
  const partialAwards: AwardDetail[] = [];
  let runningTotal = 0;

  for (const award of sortedAwards) {
    const costPerVehicle = award.unitPrice;
    const affordableFromThisAward = Math.floor(
      (availableBalance - runningTotal) / costPerVehicle
    );
    const actuallyAffordable = Math.min(
      affordableFromThisAward,
      award.quantityAwarded
    );

    if (actuallyAffordable > 0) {
      partialAwards.push({
        ...award,
        quantityAwarded: actuallyAffordable,
        totalAmount: actuallyAffordable * award.unitPrice,
      });
      runningTotal += actuallyAffordable * costPerVehicle;
    }

    if (runningTotal >= availableBalance) break;
  }

  return {
    originalAwards: awards,
    partialAwards,
    totalVehiclesOriginal: awards.reduce((sum, a) => sum + a.quantityAwarded, 0),
    totalVehiclesAffordable: partialAwards.reduce((sum, a) => sum + a.quantityAwarded, 0),
    totalCostOriginal: awards.reduce((sum, a) => sum + a.totalAmount, 0),
    totalCostAffordable: runningTotal,
  };
};
```

---

## 🔀 Split Award Logic

### Multiple Providers Per Line Item

**Rule:** Business can award a single line item to multiple providers.

**Implementation:**

```typescript
// File: src/features/business/rfq/utils/split-award.ts

export interface SplitAward {
  lineItemId: string;
  awards: {
    bidId: string;
    providerHash: string;
    quantityAwarded: number;
    unitPrice: number;
    totalAmount: number;
  }[];
  totalQuantityAwarded: number;
  totalAmount: number;
}

export const validateSplitAward = (
  lineItemId: string,
  awards: AwardDetail[],
  lineItem: RFQLineItem
): { isValid: boolean; error?: string } => {
  // All awards must be for the same line item
  const allSameLineItem = awards.every(a => a.lineItemId === lineItemId);
  if (!allSameLineItem) {
    return {
      isValid: false,
      error: 'All selected bids must be for the same line item',
    };
  }

  // Total quantity cannot exceed required
  const totalQuantity = awards.reduce((sum, a) => sum + a.quantityAwarded, 0);
  if (totalQuantity > lineItem.quantityRequired) {
    return {
      isValid: false,
      error: `Total quantity (${totalQuantity}) cannot exceed required quantity (${lineItem.quantityRequired})`,
    };
  }

  // Each award quantity cannot exceed bid's offered quantity
  for (const award of awards) {
    const bid = getBidById(award.bidId);
    if (award.quantityAwarded > bid.quantityOffered) {
      return {
        isValid: false,
        error: `Awarded quantity cannot exceed bid's offered quantity`,
      };
    }
  }

  return { isValid: true };
};

export const groupAwardsByLineItem = (
  awards: AwardDetail[]
): Map<string, SplitAward> => {
  const grouped = new Map<string, SplitAward>();

  awards.forEach((award) => {
    const existing = grouped.get(award.lineItemId);
    
    if (existing) {
      existing.awards.push({
        bidId: award.bidId,
        providerHash: award.providerHash,
        quantityAwarded: award.quantityAwarded,
        unitPrice: award.unitPrice,
        totalAmount: award.totalAmount,
      });
      existing.totalQuantityAwarded += award.quantityAwarded;
      existing.totalAmount += award.totalAmount;
    } else {
      grouped.set(award.lineItemId, {
        lineItemId: award.lineItemId,
        awards: [{
          bidId: award.bidId,
          providerHash: award.providerHash,
          quantityAwarded: award.quantityAwarded,
          unitPrice: award.unitPrice,
          totalAmount: award.totalAmount,
        }],
        totalQuantityAwarded: award.quantityAwarded,
        totalAmount: award.totalAmount,
      });
    }
  });

  return grouped;
};
```

---

## 🎭 Blind Bidding Implementation

### Display Hashed Provider ID

**Rule BR-004:** Provider identity is hashed until award.

**Implementation:**

```typescript
// File: src/features/business/rfq/components/BidRow.tsx

interface BidRowProps {
  bid: Bid;
  isSelected: boolean;
  onSelect: () => void;
}

export const BidRow: FC<BidRowProps> = ({ bid, isSelected, onSelect }) => {
  // Provider hash is already provided by backend
  // Format: "Provider •••4411"
  return (
    <TableRow>
      <TableCell>
        <Checkbox checked={isSelected} onCheckedChange={onSelect} />
      </TableCell>
      <TableCell className="font-mono text-sm">
        {bid.providerHash}
      </TableCell>
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
  );
};
```

### After Award - Reveal Provider

```typescript
// After award, provider identity is revealed
const { data: contract } = useContract(contractId);

// Contract line items now include providerName (revealed)
contract.lineItems.forEach((lineItem) => {
  console.log(`Provider: ${lineItem.providerName}`); // Now visible
  console.log(`Provider ID: ${lineItem.providerId}`); // Now visible
});
```

---

## 🔐 OTP Flow

### OTP Generation & Verification

**Rule BR-014:** OTP-based delivery verification.

**Implementation:**

```typescript
// File: src/features/provider/delivery/hooks/useOTPFlow.ts

export const useOTPFlow = (sessionId: string) => {
  const [otp, setOtp] = useState<string | null>(null);
  const [otpStatus, setOtpStatus] = useState<'PENDING' | 'GENERATED' | 'VERIFIED' | 'EXPIRED'>('PENDING');

  const generateOTP = useMutation({
    mutationFn: () => deliveryService.generateOTP(sessionId),
    onSuccess: (result) => {
      setOtp(result.otp);
      setOtpStatus('GENERATED');
      toast.success('OTP sent to business contact');
    },
  });

  const verifyOTP = useMutation({
    mutationFn: (code: string) => deliveryService.verifyOTP(sessionId, code),
    onSuccess: () => {
      setOtpStatus('VERIFIED');
      toast.success('OTP verified successfully');
    },
    onError: (error: any) => {
      if (error.response?.data?.error?.code === 'INVALID_OTP') {
        const attemptsRemaining = error.response.data.error.details.attemptsRemaining;
        if (attemptsRemaining === 0) {
          setOtpStatus('EXPIRED');
          toast.error('OTP expired. Please generate a new one.');
        } else {
          toast.error(`Invalid OTP. ${attemptsRemaining} attempts remaining.`);
        }
      } else {
        handleApiError(error);
      }
    },
  });

  return {
    otp,
    otpStatus,
    generateOTP: generateOTP.mutate,
    verifyOTP: verifyOTP.mutate,
    isGenerating: generateOTP.isPending,
    isVerifying: verifyOTP.isPending,
  };
};
```

### OTP Display Component

```typescript
export const OTPDisplay = ({ otp, onRegenerate }) => {
  return (
    <Card>
      <CardHeader>
        <CardTitle>OTP Generated</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="text-center space-y-4">
          <div className="text-4xl font-mono font-bold tracking-widest">
            {otp}
          </div>
          <p className="text-sm text-gray-600">
            This OTP has been sent to the business contact via SMS.
            Ask them to share the OTP with you to proceed.
          </p>
          <Button variant="outline" onClick={onRegenerate}>
            Regenerate OTP
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};
```

---

## 📅 Early Return Calculation

### Penalty Calculation

**Rule BR-019, BR-021:** Early return with notice period penalties.

**Implementation:**

```typescript
// File: src/features/business/contracts/utils/early-return.ts

import { differenceInDays, isBefore, subDays } from 'date-fns';

export interface EarlyReturnCalculation {
  totalDays: number;
  daysUsed: number;
  daysRemaining: number;
  proratedAmount: number;
  penaltyRate: number;
  penaltyAmount: number;
  refundAmount: number;
  noticePeriod: number;
  noticePeriodCategory: '7_PLUS' | '3_TO_6' | '0_TO_2';
}

export const calculateEarlyReturn = (
  contract: Contract,
  assignment: VehicleAssignment,
  returnDate: Date,
  businessTier: BusinessTier
): EarlyReturnCalculation => {
  const startDate = new Date(assignment.startDateActual);
  const endDate = new Date(contract.endDate);
  const returnDateObj = returnDate;

  const totalDays = differenceInDays(endDate, startDate);
  const daysUsed = differenceInDays(returnDateObj, startDate);
  const daysRemaining = totalDays - daysUsed;

  // Get line item amount
  const lineItem = contract.lineItems.find(
    li => li.id === assignment.contractLineItemId
  );
  const totalAmount = lineItem?.totalAmount || 0;

  // Prorated amount (amount for days used)
  const proratedAmount = (totalAmount / totalDays) * daysUsed;

  // Notice period (days before return date)
  const noticePeriod = differenceInDays(returnDateObj, new Date());

  // Determine notice period category
  let noticePeriodCategory: '7_PLUS' | '3_TO_6' | '0_TO_2';
  if (noticePeriod >= 7) {
    noticePeriodCategory = '7_PLUS';
  } else if (noticePeriod >= 3) {
    noticePeriodCategory = '3_TO_6';
  } else {
    noticePeriodCategory = '0_TO_2';
  }

  // Penalty rate based on notice period and tier
  const penaltyRate = getPenaltyRate(noticePeriodCategory, businessTier);

  // Remaining amount (what would be refunded without penalty)
  const remainingAmount = totalAmount - proratedAmount;

  // Penalty amount
  const penaltyAmount = remainingAmount * penaltyRate;

  // Refund amount (after penalty)
  const refundAmount = remainingAmount - penaltyAmount;

  return {
    totalDays,
    daysUsed,
    daysRemaining,
    proratedAmount,
    penaltyRate,
    penaltyAmount,
    refundAmount,
    noticePeriod,
    noticePeriodCategory,
  };
};

const getPenaltyRate = (
  category: '7_PLUS' | '3_TO_6' | '0_TO_2',
  tier: BusinessTier
): number => {
  // Base penalty rates
  const baseRates = {
    '7_PLUS': 0.00,    // 0% penalty
    '3_TO_6': 0.02,   // 2% penalty
    '0_TO_2': 0.15,   // 15% penalty
  };

  // Tier adjustments (Enterprise/GOV_NGO may have lower rates)
  const tierMultipliers = {
    STANDARD: 1.0,
    BUSINESS_PRO: 0.95,
    PREMIUM: 0.90,
    ENTERPRISE: 0.85,
  };

  return baseRates[category] * tierMultipliers[tier];
};
```

### Early Return Request Component

```typescript
export const EarlyReturnRequest = ({ contractId, assignmentId }) => {
  const [returnDate, setReturnDate] = useState<Date | null>(null);
  const [calculation, setCalculation] = useState<EarlyReturnCalculation | null>(null);
  const { data: contract } = useContract(contractId);
  const { data: business } = useBusiness();

  useEffect(() => {
    if (returnDate && contract && business) {
      const assignment = contract.lineItems
        .flatMap(li => li.assignments)
        .find(a => a.id === assignmentId);
      
      if (assignment) {
        const calc = calculateEarlyReturn(
          contract,
          assignment,
          returnDate,
          business.tier
        );
        setCalculation(calc);
      }
    }
  }, [returnDate, contract, business, assignmentId]);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Request Early Return</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        <FormField label="Return Date" required>
          <DatePicker
            value={returnDate}
            onChange={setReturnDate}
            minDate={new Date()}
            maxDate={new Date(contract?.endDate)}
          />
        </FormField>

        {calculation && (
          <div className="bg-gray-50 p-4 rounded space-y-2">
            <div className="flex justify-between">
              <span>Total Contract Days:</span>
              <span className="font-semibold">{calculation.totalDays} days</span>
            </div>
            <div className="flex justify-between">
              <span>Days Used:</span>
              <span className="font-semibold">{calculation.daysUsed} days</span>
            </div>
            <div className="flex justify-between">
              <span>Days Remaining:</span>
              <span className="font-semibold">{calculation.daysRemaining} days</span>
            </div>
            <div className="border-t pt-2 mt-2">
              <div className="flex justify-between">
                <span>Prorated Amount:</span>
                <span>{formatCurrency(calculation.proratedAmount)} ETB</span>
              </div>
              <div className="flex justify-between text-red-600">
                <span>Penalty ({calculation.penaltyRate * 100}%):</span>
                <span>-{formatCurrency(calculation.penaltyAmount)} ETB</span>
              </div>
              <div className="flex justify-between font-bold text-lg border-t pt-2 mt-2">
                <span>Refund Amount:</span>
                <span className="text-green-600">
                  {formatCurrency(calculation.refundAmount)} ETB
                </span>
              </div>
            </div>
          </div>
        )}

        <Button onClick={handleSubmit} disabled={!returnDate || !calculation}>
          Submit Early Return Request
        </Button>
      </CardContent>
    </Card>
  );
};
```

---

## ⭐ Trust Score Display

### Trust Score Component

**Rule BR-025:** Simple trust score calculation (0-100).

**Implementation:**

```typescript
// File: src/features/provider/profile/components/TrustScoreGauge.tsx

interface TrustScoreData {
  score: number;
  tier: ProviderTier;
  breakdown: {
    completionRate: number;
    onTimeRate: number;
    reliability: number;
    quality: number;
    disputeHistory: number;
  };
}

export const TrustScoreGauge = ({ data }: { data: TrustScoreData }) => {
  const percentage = data.score;
  const circumference = 2 * Math.PI * 45; // radius = 45
  const offset = circumference - (percentage / 100) * circumference;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Trust Score</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="flex items-center justify-center">
          <div className="relative w-48 h-48">
            <svg className="transform -rotate-90 w-48 h-48">
              <circle
                cx="96"
                cy="96"
                r="90"
                stroke="currentColor"
                strokeWidth="8"
                fill="transparent"
                className="text-gray-200"
              />
              <circle
                cx="96"
                cy="96"
                r="90"
                stroke="currentColor"
                strokeWidth="8"
                fill="transparent"
                strokeDasharray={circumference}
                strokeDashoffset={offset}
                className={`transition-all ${
                  percentage >= 85 ? 'text-green-600' :
                  percentage >= 70 ? 'text-blue-600' :
                  percentage >= 50 ? 'text-yellow-600' :
                  'text-red-600'
                }`}
              />
            </svg>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <div className="text-4xl font-bold">{data.score}</div>
              <div className="text-sm text-gray-600">/ 100</div>
              <Badge className="mt-2">{data.tier}</Badge>
            </div>
          </div>
        </div>

        <div className="mt-6 space-y-3">
          <div>
            <div className="flex justify-between text-sm mb-1">
              <span>Completion Rate</span>
              <span>{data.breakdown.completionRate}%</span>
            </div>
            <Progress value={data.breakdown.completionRate} />
          </div>
          <div>
            <div className="flex justify-between text-sm mb-1">
              <span>On-Time Delivery</span>
              <span>{data.breakdown.onTimeRate}%</span>
            </div>
            <Progress value={data.breakdown.onTimeRate} />
          </div>
          <div>
            <div className="flex justify-between text-sm mb-1">
              <span>Reliability</span>
              <span>{data.breakdown.reliability}%</span>
            </div>
            <Progress value={data.breakdown.reliability} />
          </div>
          <div>
            <div className="flex justify-between text-sm mb-1">
              <span>Quality (Ratings)</span>
              <span>{data.breakdown.quality}/5</span>
            </div>
            <Progress value={(data.breakdown.quality / 5) * 100} />
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
```

---

## 🏆 Tier System Display

### Provider Tier Display

**Rule BR-040, BR-042:** Hybrid tier determination (trust score + active fleet).

```typescript
// File: src/features/provider/profile/components/TierDisplay.tsx

interface TierInfo {
  currentTier: ProviderTier;
  trustScore: number;
  activeVehicles: number;
  nextTier?: ProviderTier;
  progressToNextTier?: {
    trustScoreNeeded: number;
    vehiclesNeeded: number;
  };
  commissionRate: number;
  benefits: string[];
}

export const TierDisplay = ({ tierInfo }: { tierInfo: TierInfo }) => {
  const tierColors = {
    BRONZE: 'bg-amber-100 text-amber-800 border-amber-300',
    SILVER: 'bg-gray-100 text-gray-800 border-gray-300',
    GOLD: 'bg-yellow-100 text-yellow-800 border-yellow-300',
    PLATINUM: 'bg-purple-100 text-purple-800 border-purple-300',
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Provider Tier</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center gap-4">
          <Badge className={`text-lg px-4 py-2 ${tierColors[tierInfo.currentTier]}`}>
            {tierInfo.currentTier}
          </Badge>
          <div>
            <p className="text-sm text-gray-600">Commission Rate</p>
            <p className="text-2xl font-bold">{tierInfo.commissionRate * 100}%</p>
          </div>
        </div>

        <div className="bg-gray-50 p-4 rounded">
          <h4 className="font-semibold mb-2">Tier Requirements</h4>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span>Trust Score:</span>
              <span className={tierInfo.trustScore >= getTierMinScore(tierInfo.currentTier) ? 'text-green-600' : 'text-red-600'}>
                {tierInfo.trustScore} / {getTierMinScore(tierInfo.currentTier)}+
              </span>
            </div>
            <div className="flex justify-between">
              <span>Active Vehicles:</span>
              <span className={tierInfo.activeVehicles >= getTierMinVehicles(tierInfo.currentTier) ? 'text-green-600' : 'text-red-600'}>
                {tierInfo.activeVehicles} / {getTierMinVehicles(tierInfo.currentTier)}+
              </span>
            </div>
          </div>
        </div>

        {tierInfo.nextTier && tierInfo.progressToNextTier && (
          <div>
            <h4 className="font-semibold mb-2">Progress to {tierInfo.nextTier}</h4>
            <div className="space-y-2">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span>Trust Score</span>
                  <span>
                    {tierInfo.trustScore} / {tierInfo.progressToNextTier.trustScoreNeeded}
                  </span>
                </div>
                <Progress
                  value={(tierInfo.trustScore / tierInfo.progressToNextTier.trustScoreNeeded) * 100}
                />
              </div>
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span>Active Vehicles</span>
                  <span>
                    {tierInfo.activeVehicles} / {tierInfo.progressToNextTier.vehiclesNeeded}
                  </span>
                </div>
                <Progress
                  value={(tierInfo.activeVehicles / tierInfo.progressToNextTier.vehiclesNeeded) * 100}
                />
              </div>
            </div>
          </div>
        )}

        <div>
          <h4 className="font-semibold mb-2">Tier Benefits</h4>
          <ul className="list-disc list-inside space-y-1 text-sm">
            {tierInfo.benefits.map((benefit, index) => (
              <li key={index}>{benefit}</li>
            ))}
          </ul>
        </div>
      </CardContent>
    </Card>
  );
};

const getTierMinScore = (tier: ProviderTier): number => {
  const requirements = {
    BRONZE: 0,
    SILVER: 50,
    GOLD: 70,
    PLATINUM: 85,
  };
  return requirements[tier];
};

const getTierMinVehicles = (tier: ProviderTier): number => {
  const requirements = {
    BRONZE: 0,
    SILVER: 5,
    GOLD: 15,
    PLATINUM: 30,
  };
  return requirements[tier];
};
```

### Business Tier Display

Similar implementation for business tiers with different criteria (completed contracts + active fleet).

---

## 📊 Market Price Guidance

### Display Market Price Range

```typescript
// File: src/features/business/rfq/components/MarketPriceGuidance.tsx

export const MarketPriceGuidance = ({ vehicleType }: { vehicleType: string }) => {
  const { data: priceRange } = useQuery({
    queryKey: ['market-prices', vehicleType],
    queryFn: () => masterDataService.getMarketPriceRange(vehicleType),
  });

  if (!priceRange) return null;

  return (
    <div className="bg-blue-50 border border-blue-200 rounded p-3 mt-2">
      <p className="text-sm font-semibold text-blue-900 mb-1">Market Price Guidance</p>
      <div className="text-xs text-blue-800 space-y-1">
        <p>Average: {formatCurrency(priceRange.average)} ETB</p>
        <p>Range: {formatCurrency(priceRange.floor)} - {formatCurrency(priceRange.ceiling)} ETB</p>
        <p className="text-blue-600 mt-2">
          Your bid price should be within this range to be considered.
        </p>
      </div>
    </div>
  );
};
```

---

## ✅ Validation Helpers

### Date Validation

```typescript
// File: src/shared/utils/date-validation.ts

export const validateRFQDates = (
  startDate: Date,
  endDate: Date,
  bidDeadline: Date
): { isValid: boolean; errors: string[] } => {
  const errors: string[] = [];
  const today = new Date();
  const minStartDate = addDays(today, 3);

  if (!isAfter(startDate, minStartDate)) {
    errors.push('Start date must be at least 3 days from now');
  }

  if (!isAfter(endDate, startDate)) {
    errors.push('End date must be after start date');
  }

  if (!isBefore(bidDeadline, startDate)) {
    errors.push('Bid deadline must be before start date');
  }

  if (isBefore(bidDeadline, today)) {
    errors.push('Bid deadline cannot be in the past');
  }

  return {
    isValid: errors.length === 0,
    errors,
  };
};
```

### Price Validation

```typescript
export const validateBidPrice = (
  price: number,
  vehicleType: string,
  priceRange: MarketPriceRange
): { isValid: boolean; error?: string } => {
  if (price < priceRange.floor) {
    return {
      isValid: false,
      error: `Price must be at least ${formatCurrency(priceRange.floor)} ETB`,
    };
  }

  if (price > priceRange.ceiling) {
    return {
      isValid: false,
      error: `Price cannot exceed ${formatCurrency(priceRange.ceiling)} ETB`,
    };
  }

  return { isValid: true };
};
```

---

**END OF BUSINESS LOGIC IMPLEMENTATION GUIDE**

*For business rules reference, see [MVP_AUTHORITATIVE_BUSINESS_RULES.md](./MVP_MODULAR/MVP_final_docs/MVP_AUTHORITATIVE_BUSINESS_RULES.md)*

