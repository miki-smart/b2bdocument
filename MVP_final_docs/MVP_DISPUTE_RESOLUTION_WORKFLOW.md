# Movello MVP - Dispute Resolution Workflow
## Complete Dispute Categories, Evidence, SLA & Resolution - Version 1.0

**Document Status:** AUTHORITATIVE  
**Date:** December 22, 2025  
**Related Documents:** 
- MVP_AUTHORITATIVE_BUSINESS_RULES.md
- MVP_EVENT_CATALOG_AND_HANDLERS.md
- MVP_MODULE_INTEGRATION_SPECIFICATION.md
- MVP_CONTRACT_STATE_MACHINE.md
- MVP_SETTLEMENT_PROCESSING_SPECIFICATION.md  
**Review Status:** ✅ Approved by Business Owner

---

## Document Purpose

This document defines the complete dispute resolution system for the Movello MVP platform, including:
- All dispute categories and definitions
- Evidence requirements per category
- Resolution workflows and decision trees
- SLA timelines (48-hour resolution target)
- Escalation procedures
- Resolution outcomes and enforcement

---

## TABLE OF CONTENTS

1. [Dispute System Overview](#1-dispute-system-overview)
2. [Dispute Categories](#2-dispute-categories)
3. [Dispute Creation Process](#3-dispute-creation-process)
4. [Evidence Requirements](#4-evidence-requirements)
5. [Resolution Workflow](#5-resolution-workflow)
6. [SLA & Timelines](#6-sla--timelines)
7. [Resolution Outcomes](#7-resolution-outcomes)
8. [Escalation Procedures](#8-escalation-procedures)
9. [Automated Dispute Handling](#9-automated-dispute-handling)
10. [Post-Resolution Actions](#10-post-resolution-actions)

---

## 1. DISPUTE SYSTEM OVERVIEW

### 1.1 Dispute Principles

**Core Principles:**
- ✅ **Fair & Transparent:** Evidence-based decisions with clear reasoning
- ✅ **Fast Resolution:** 48-hour SLA for all disputes
- ✅ **Provider-First:** Benefit of doubt goes to provider when evidence unclear
- ✅ **Zero Tolerance:** Fraud or abuse results in immediate suspension
- ✅ **Evidence Required:** No he-said-she-said - must provide proof

**Business Rule Reference:** BR-034, BR-035, BR-036, BR-037, BR-038, BR-039

---

### 1.2 Who Can Create Disputes

```typescript
enum DisputeCreator {
  BUSINESS = 'BUSINESS',        // Business user creates dispute
  PROVIDER = 'PROVIDER',        // Provider creates dispute
  SYSTEM = 'SYSTEM',            // Auto-created by system (e.g., debt escalation)
  ADMIN = 'ADMIN'               // Admin creates on behalf of party
}
```

**Rules:**
- Both business and provider can create disputes
- Only ONE active dispute per contract at a time
- System can auto-create disputes for debt escalation
- Admin can create disputes on behalf of either party

---

### 1.3 Dispute Impact on Contract

```typescript
// Contract state changes based on dispute category
function getDisputeImpact(category: DisputeCategory): ContractImpact {
  switch (category) {
    case 'VEHICLE_CONDITION':
    case 'SERVICE_QUALITY':
      return {
        contractStatus: 'UNDER_DISPUTE',
        blockActions: ['EARLY_RETURN', 'CONTRACT_ALTERATION'],
        allowActions: ['CONTINUE_OPERATIONS', 'MONTHLY_SETTLEMENT']
      };
      
    case 'NON_PAYMENT':
      return {
        contractStatus: 'UNDER_DISPUTE',
        blockActions: ['EARLY_RETURN', 'CONTRACT_ALTERATION', 'SETTLEMENT'],
        allowActions: ['EVIDENCE_SUBMISSION']
      };
      
    case 'DELIVERY_ISSUE':
      return {
        contractStatus: 'UNDER_DISPUTE',
        blockActions: ['ALL'],
        allowActions: ['EVIDENCE_SUBMISSION', 'ADMIN_RESOLUTION']
      };
      
    case 'CONTRACT_TERMS':
      return {
        contractStatus: 'UNDER_DISPUTE',
        blockActions: ['EARLY_RETURN', 'CONTRACT_ALTERATION'],
        allowActions: ['CONTINUE_OPERATIONS', 'MONTHLY_SETTLEMENT']
      };
  }
}
```

---

## 2. DISPUTE CATEGORIES

### 2.1 Category 1: Vehicle Condition Dispute

**Description:** Dispute about vehicle quality, cleanliness, or functionality at delivery or return.

**Who Can Create:**
- **Business:** Vehicle not as described, dirty, damaged, malfunctioning at delivery
- **Provider:** Vehicle returned damaged, dirty, or with issues

**Typical Scenarios:**
```
At Delivery:
- "Vehicle delivered dirty/unwashed"
- "Vehicle has mechanical issues (engine, brakes, AC not working)"
- "Vehicle exterior damaged (scratches, dents)"
- "Vehicle interior damaged (torn seats, broken features)"
- "Vehicle not matching description (different color, missing features)"

At Return:
- "Vehicle returned with new damage (scratches, dents, broken parts)"
- "Vehicle returned dirty (interior/exterior)"
- "Vehicle has mechanical issues caused by business usage"
- "Vehicle returned with missing items (spare tire, tools)"
```

**Required Evidence:**

**From Business (at delivery):**
```typescript
interface DeliveryDisputeEvidence {
  photos: Photo[];              // Min 5 photos showing issues
  photoTimestamps: Date[];      // Must be at delivery time
  videoWalkthrough?: Video;     // Optional but recommended
  deliveryOTP: string;          // Proof of delivery
  issueDescription: string;     // Detailed description
  witnessContact?: string;      // Optional witness
}
```

**From Provider (at return):**
```typescript
interface ReturnDisputeEvidence {
  photosAtDelivery: Photo[];    // Original delivery condition
  photosAtReturn: Photo[];      // Current return condition
  photoComparison: Photo[];     // Side-by-side comparison
  inspectionReport?: Document;  // Optional inspection report
  repairQuotes?: Document[];    // Quotes for repair costs
  issueDescription: string;
}
```

**Resolution Outcomes:**
- **Business wins:** Provider must replace vehicle OR business can reject delivery OR repair costs covered by provider
- **Provider wins:** Business accepts vehicle as-is OR business pays repair costs
- **Split decision:** Both parties share repair costs (rare)

---

### 2.2 Category 2: Service Quality Dispute

**Description:** Dispute about provider's service, responsiveness, or professionalism.

**Who Can Create:** Business only

**Typical Scenarios:**
```
- "Provider unresponsive to messages/calls"
- "Provider delayed delivery without notice"
- "Provider rude or unprofessional"
- "Provider failed to provide required documentation (insurance, registration)"
- "Provider changed vehicles without permission"
- "Provider requested additional payments outside platform"
```

**Required Evidence:**

```typescript
interface ServiceQualityEvidence {
  messageScreenshots?: Photo[];     // Communication logs
  callLogs?: Document;              // Phone call records
  deliverySchedule?: Document;      // Original delivery agreement
  actualDeliveryTime?: Date;        // When actually delivered
  witnesStatements?: string[];      // Written statements
  platformChatLogs?: string;        // In-app messages (auto-pulled)
}
```

**Resolution Outcomes:**
- **Minor issue:** Provider warned, no financial impact
- **Moderate issue:** Provider receives trust score penalty
- **Severe issue:** Business receives discount (5-10% of contract value), provider trust score reduced
- **Critical issue:** Contract terminated, full refund, provider suspended

---

### 2.3 Category 3: Non-Payment Dispute

**Description:** Dispute about unpaid amounts, grace period charges, or debt.

**Who Can Create:**
- **Provider:** Business hasn't paid debt, disputes amount owed
- **System:** Auto-created after 30 days of unpaid debt
- **Business:** Disputes the amount claimed by provider

**Typical Scenarios:**
```
Provider Creates:
- "Business used grace period but didn't pay"
- "Business owes for days 31-34, refuses to pay debt"
- "Business disputes late fee calculation"

Business Creates:
- "Provider claiming wrong amount"
- "Grace period calculation incorrect"
- "I paid but provider claims I didn't"

System Creates:
- "Debt outstanding for 30+ days, auto-escalated to dispute"
```

**Required Evidence:**

**From Provider:**
```typescript
interface NonPaymentEvidence {
  contractDetails: Contract;           // Original contract
  gracePeriodGranted: boolean;         // Did provider grant grace period
  gracePeriodDays: number;            // How many days
  calculationBreakdown: {
    dailyRate: number;
    daysInGracePeriod: number;
    gracePeriodAmount: number;
    lateFee: number;
    totalOwed: number;
  };
  paymentDueDate: Date;               // When payment was due
  paymentRequests: Photo[];           // Screenshots of payment requests
  businessWalletBalance?: number;     // If visible
}
```

**From Business:**
```typescript
interface PaymentDisputeEvidence {
  paymentReceipts?: Document[];       // Proof of payment
  walletTransactionHistory: Document; // Wallet history showing payment
  disputeReason: string;              // Why disputing amount
  alternativeCalculation?: {          // If disputing calculation
    dailyRate: number;
    daysInGracePeriod: number;
    proposedAmount: number;
    reasoning: string;
  };
}
```

**Resolution Outcomes:**
- **Provider wins:** Business must pay full amount + dispute processing fee (5%), account suspended until paid
- **Business wins:** Debt waived, account reactivated immediately
- **Split decision:** Adjusted amount calculated, business pays reduced amount

---

### 2.4 Category 4: Delivery Issue Dispute

**Description:** Dispute about delivery process, timing, OTP verification, or vehicle assignment.

**Who Can Create:** Both business and provider

**Typical Scenarios:**
```
Business Creates:
- "Provider didn't deliver on scheduled date"
- "Wrong vehicles delivered (different from assignment)"
- "Provider asking for OTP without delivering vehicles"
- "Provider demanding payment outside platform"

Provider Creates:
- "Business refusing to share OTP after delivery"
- "Business not available at delivery location"
- "Business requesting delivery outside agreed location"
```

**Required Evidence:**

**From Business:**
```typescript
interface BusinessDeliveryEvidence {
  scheduledDeliveryDate: Date;        // Agreed delivery date
  actualDeliveryDate?: Date;          // When actually delivered
  deliveryLocation: Location;         // Agreed location
  photos?: Photo[];                   // Photos if wrong vehicles
  vehicleAssignmentList: Vehicle[];   // Expected vehicles
  actualVehicles?: Vehicle[];         // Vehicles actually shown
  communicationLogs: string[];        // Messages about delivery
}
```

**From Provider:**
```typescript
interface ProviderDeliveryEvidence {
  deliveryAttempts: DeliveryAttempt[]; // All delivery attempts
  locationProof: Location[];           // GPS proof of arrival
  photos: Photo[];                     // Photos at delivery location
  communicationLogs: string[];         // Messages to business
  businessNoShowProof?: Document;      // If business wasn't there
}
```

**Resolution Outcomes:**
- **Business wins:** Contract can be cancelled with full refund OR new delivery scheduled
- **Provider wins:** Business must accept delivery or contract cancelled (no refund)
- **Mutual fault:** Both parties work out new delivery time, no penalties

---

### 2.5 Category 5: Contract Terms Dispute

**Description:** Dispute about contract interpretation, terms, pricing, or alterations.

**Who Can Create:** Both business and provider

**Typical Scenarios:**
```
- "Provider claims contract allows extra charges, I disagree"
- "Business demanding services not in contract"
- "Dispute over contract alteration terms"
- "Disagreement on early return penalty calculation"
- "Confusion about monthly vs. daily rate"
```

**Required Evidence:**

```typescript
interface ContractTermsEvidence {
  originalContract: Contract;         // Original signed contract
  disputedClause: string;             // Which term is disputed
  proposedInterpretation: string;     // How party interprets it
  supportingDocuments?: Document[];   // RFQ, bid, messages
  previousCommunication: string[];    // All relevant messages
  platformTerms: Document;            // Platform T&Cs (auto-attached)
}
```

**Resolution Outcomes:**
- **Clear contract terms:** Party with correct interpretation wins
- **Ambiguous terms:** Admin interprets based on platform standards
- **Error in contract:** Contract corrected, financial adjustment made if needed

---

## 3. DISPUTE CREATION PROCESS

### 3.1 Dispute Creation Flow

```typescript
async function createDispute(request: DisputeCreateRequest): Promise<Dispute> {
  // 1. Validate eligibility
  await validateDisputeEligibility(request);
  
  // 2. Check for existing disputes
  const existingDispute = await checkExistingDispute(request.contractId);
  if (existingDispute) {
    throw new Error('Contract already has active dispute');
  }
  
  // 3. Create dispute record
  const dispute = await this.disputeRepository.create({
    id: generateUUID(),
    contractId: request.contractId,
    createdBy: request.createdBy,
    creatorType: request.creatorType,
    category: request.category,
    description: request.description,
    status: 'OPEN',
    priority: calculatePriority(request.category),
    slaDeadline: addHours(new Date(), 48),
    createdAt: new Date()
  });
  
  // 4. Upload evidence
  await this.uploadEvidence(dispute.id, request.evidence);
  
  // 5. Update contract status
  await this.contractStateMachine.transitionTo(
    request.contractId,
    'UNDER_DISPUTE',
    `Dispute created: ${request.category}`
  );
  
  // 6. Notify counter-party
  await this.notifyCounterParty(dispute);
  
  // 7. Notify admin for review
  await this.notifyAdminForReview(dispute);
  
  // 8. Start SLA timer
  await this.startSLATimer(dispute.id, 48);
  
  return dispute;
}
```

### 3.2 Validation Rules

```typescript
async function validateDisputeEligibility(request: DisputeCreateRequest) {
  const contract = await this.contractRepository.findById(request.contractId);
  
  // 1. Contract must exist
  if (!contract) {
    throw new Error('Contract not found');
  }
  
  // 2. User must be party to contract
  if (request.createdBy !== contract.businessId && 
      request.createdBy !== contract.providerId) {
    throw new Error('User not party to contract');
  }
  
  // 3. Cannot dispute contracts in certain states
  const invalidStates = ['FAILED', 'TERMINATED'];
  if (invalidStates.includes(contract.status)) {
    throw new Error(`Cannot dispute contract in ${contract.status} state`);
  }
  
  // 4. Delivery disputes must be within 7 days of delivery
  if (request.category === 'DELIVERY_ISSUE') {
    const daysSinceDelivery = differenceInDays(new Date(), contract.deliveryConfirmedAt);
    if (daysSinceDelivery > 7) {
      throw new Error('Delivery disputes must be filed within 7 days');
    }
  }
  
  // 5. Vehicle condition disputes must have photos
  if (request.category === 'VEHICLE_CONDITION') {
    if (!request.evidence.photos || request.evidence.photos.length < 3) {
      throw new Error('Vehicle condition disputes require minimum 3 photos');
    }
  }
  
  // 6. Non-payment disputes must have debt record or calculation
  if (request.category === 'NON_PAYMENT') {
    if (!request.evidence.debtId && !request.evidence.calculationBreakdown) {
      throw new Error('Non-payment disputes require debt ID or calculation breakdown');
    }
  }
}
```

---

## 4. EVIDENCE REQUIREMENTS

### 4.1 Evidence Types & Validation

```typescript
interface Evidence {
  type: EvidenceType;
  files: File[];
  description: string;
  uploadedAt: Date;
  uploadedBy: string;
}

enum EvidenceType {
  PHOTO = 'PHOTO',                   // Images (JPG, PNG)
  VIDEO = 'VIDEO',                   // Videos (MP4, MOV)
  DOCUMENT = 'DOCUMENT',             // PDFs, docs
  SCREENSHOT = 'SCREENSHOT',         // Screen captures
  INVOICE = 'INVOICE',               // Financial documents
  INSPECTION_REPORT = 'INSPECTION_REPORT',
  COMMUNICATION_LOG = 'COMMUNICATION_LOG'
}

// Validation rules per category
const EVIDENCE_REQUIREMENTS = {
  VEHICLE_CONDITION: {
    required: ['PHOTO'],
    minPhotos: 3,
    maxFileSize: 10 * 1024 * 1024, // 10MB
    acceptedFormats: ['jpg', 'jpeg', 'png', 'mp4']
  },
  SERVICE_QUALITY: {
    required: ['SCREENSHOT', 'COMMUNICATION_LOG'],
    minFiles: 1,
    maxFileSize: 5 * 1024 * 1024, // 5MB
    acceptedFormats: ['jpg', 'jpeg', 'png', 'pdf']
  },
  NON_PAYMENT: {
    required: ['DOCUMENT'],
    minFiles: 1,
    maxFileSize: 5 * 1024 * 1024,
    acceptedFormats: ['pdf', 'jpg', 'png']
  },
  DELIVERY_ISSUE: {
    required: ['PHOTO'],
    minPhotos: 2,
    maxFileSize: 10 * 1024 * 1024,
    acceptedFormats: ['jpg', 'jpeg', 'png']
  },
  CONTRACT_TERMS: {
    required: ['DOCUMENT'],
    minFiles: 1,
    maxFileSize: 5 * 1024 * 1024,
    acceptedFormats: ['pdf']
  }
};
```

### 4.2 Evidence Upload & Storage

```typescript
async function uploadEvidence(
  disputeId: string,
  evidence: EvidenceUpload[]
): Promise<Evidence[]> {
  
  const uploadedEvidence = [];
  
  for (const item of evidence) {
    // 1. Validate file
    await validateEvidenceFile(item);
    
    // 2. Generate secure URL
    const fileKey = `disputes/${disputeId}/${generateUUID()}-${item.filename}`;
    
    // 3. Upload to S3 (or storage service)
    const uploadUrl = await this.storageService.upload({
      key: fileKey,
      file: item.file,
      contentType: item.mimeType,
      metadata: {
        disputeId,
        uploadedBy: item.uploadedBy,
        uploadedAt: new Date().toISOString()
      }
    });
    
    // 4. Create evidence record
    const evidenceRecord = await this.evidenceRepository.create({
      id: generateUUID(),
      disputeId,
      type: item.type,
      filename: item.filename,
      fileUrl: uploadUrl,
      fileSize: item.fileSize,
      mimeType: item.mimeType,
      description: item.description,
      uploadedBy: item.uploadedBy,
      uploadedAt: new Date()
    });
    
    uploadedEvidence.push(evidenceRecord);
  }
  
  return uploadedEvidence;
}
```

### 4.3 Counter-Evidence Submission

```typescript
async function submitCounterEvidence(
  disputeId: string,
  counterPartyId: string,
  evidence: EvidenceUpload[]
) {
  const dispute = await this.disputeRepository.findById(disputeId);
  
  // 1. Validate counter-party is allowed to submit
  const isCounterParty = await this.isCounterParty(dispute, counterPartyId);
  if (!isCounterParty) {
    throw new Error('Not authorized to submit counter-evidence');
  }
  
  // 2. Check if still within response window
  const responseDeadline = addHours(dispute.createdAt, 24);
  if (new Date() > responseDeadline) {
    throw new Error('Counter-evidence submission window closed');
  }
  
  // 3. Upload evidence
  const uploadedEvidence = await this.uploadEvidence(disputeId, evidence);
  
  // 4. Update dispute status
  await this.disputeRepository.update(disputeId, {
    counterEvidenceSubmitted: true,
    counterEvidenceSubmittedAt: new Date(),
    status: 'PENDING_REVIEW'
  });
  
  // 5. Notify admin that both parties have submitted
  await this.notifyAdminReadyForReview(dispute);
}
```

---

## 5. RESOLUTION WORKFLOW

### 5.1 Resolution Process Flow

```
┌─────────────────────────────────────────────────────────┐
│              DISPUTE RESOLUTION FLOW                     │
└─────────────────────────────────────────────────────────┘

1. DISPUTE CREATED
   ↓
2. COUNTER-PARTY NOTIFIED (24 hours to respond)
   ↓
3. COUNTER-PARTY SUBMITS EVIDENCE (optional)
   ↓
4. ADMIN REVIEW
   - Review all evidence
   - Check platform data (chat logs, transactions, GPS)
   - Apply resolution criteria
   ↓
5. RESOLUTION DECISION
   - Party A wins
   - Party B wins
   - Split decision
   - Need more information
   ↓
6. RESOLUTION EXECUTION
   - Financial adjustments
   - Contract status updates
   - Trust score impacts
   - Account suspensions (if applicable)
   ↓
7. NOTIFICATIONS
   - Both parties notified
   - Resolution reasoning provided
   - Next steps communicated
   ↓
8. DISPUTE CLOSED
```

### 5.2 Admin Review Interface

```typescript
interface DisputeReviewInterface {
  dispute: Dispute;
  contract: Contract;
  
  // Party information
  claimant: {
    id: string;
    type: 'BUSINESS' | 'PROVIDER';
    name: string;
    trustScore: number;
    evidenceSubmitted: Evidence[];
    statement: string;
  };
  
  respondent: {
    id: string;
    type: 'BUSINESS' | 'PROVIDER';
    name: string;
    trustScore: number;
    evidenceSubmitted: Evidence[];
    statement?: string;
  };
  
  // Platform data (auto-gathered)
  platformData: {
    chatLogs: ChatMessage[];
    contractHistory: ContractEvent[];
    paymentHistory: Transaction[];
    deliveryGPS?: Location[];
    vehicleHistory: VehicleEvent[];
  };
  
  // Resolution options
  resolutionOptions: ResolutionOption[];
  
  // SLA timer
  slaTimeRemaining: string;
  slaDeadline: Date;
}
```

### 5.3 Resolution Decision Tree

```typescript
async function resolveDispute(
  disputeId: string,
  adminId: string,
  resolution: DisputeResolution
): Promise<ResolvedDispute> {
  
  const dispute = await this.disputeRepository.findById(disputeId);
  
  // 1. Validate resolution
  await validateResolution(dispute, resolution);
  
  // 2. Record resolution
  const resolvedDispute = await this.disputeRepository.update(disputeId, {
    status: 'RESOLVED',
    resolvedBy: adminId,
    resolvedAt: new Date(),
    resolution: resolution.decision,
    resolutionReasoning: resolution.reasoning,
    winner: resolution.winner,
    financialAdjustment: resolution.financialAdjustment
  });
  
  // 3. Execute resolution actions
  await this.executeResolutionActions(resolvedDispute);
  
  // 4. Update contract status
  await this.updateContractAfterResolution(resolvedDispute);
  
  // 5. Process financial adjustments
  if (resolution.financialAdjustment) {
    await this.processFinancialAdjustment(resolvedDispute);
  }
  
  // 6. Update trust scores
  await this.updateTrustScores(resolvedDispute);
  
  // 7. Notify parties
  await this.notifyResolution(resolvedDispute);
  
  return resolvedDispute;
}
```

### 5.4 Resolution Criteria by Category

#### Vehicle Condition Disputes
```typescript
function resolveVehicleConditionDispute(dispute: Dispute): Resolution {
  // Decision criteria:
  // 1. Photo evidence quality and timestamps
  // 2. Delivery OTP timestamp vs photo timestamps
  // 3. Previous vehicle history
  // 4. Insurance records
  
  const evidence = analyzeEvidence(dispute);
  
  if (evidence.photoTimestamp === evidence.deliveryOTPTime) {
    // Photos taken at delivery = likely legitimate
    if (evidence.damageVisible && evidence.damageSignificant) {
      return {
        winner: dispute.claimantId,
        outcome: 'BUSINESS_WINS',
        action: 'PROVIDER_REPLACE_VEHICLE_OR_REPAIR',
        reasoning: 'Photos clearly show vehicle condition at delivery'
      };
    }
  } else {
    // Photos taken after delivery = less credible
    return {
      winner: dispute.respondentId,
      outcome: 'PROVIDER_WINS',
      action: 'BUSINESS_ACCEPTS_AS_IS',
      reasoning: 'Photos not taken at delivery time, cannot verify original condition'
    };
  }
}
```

#### Non-Payment Disputes
```typescript
function resolveNonPaymentDispute(dispute: Dispute): Resolution {
  // Decision criteria:
  // 1. Grace period was granted by provider (provider accepts risk)
  // 2. Calculation is correct per BR-012
  // 3. Payment proof from business
  
  const debtRecord = getDebtRecord(dispute.contractId);
  const calculation = verifyCalculation(debtRecord);
  
  if (!calculation.correct) {
    // Calculation error = business wins (or adjusted amount)
    return {
      winner: dispute.claimantType === 'BUSINESS' ? dispute.claimantId : dispute.respondentId,
      outcome: 'CALCULATION_ERROR',
      action: 'ADJUST_DEBT_AMOUNT',
      adjustedAmount: calculation.correctAmount,
      reasoning: `Original calculation incorrect. Correct amount: ${calculation.correctAmount} ETB`
    };
  }
  
  // Check for payment proof
  const paymentProof = getPaymentProof(dispute);
  if (paymentProof.exists) {
    return {
      winner: dispute.claimantId,
      outcome: 'BUSINESS_WINS',
      action: 'WAIVE_DEBT',
      reasoning: 'Payment receipt verified, debt waived'
    };
  }
  
  // No payment proof, calculation correct = provider wins
  return {
    winner: dispute.respondentId,
    outcome: 'PROVIDER_WINS',
    action: 'BUSINESS_MUST_PAY',
    amount: debtRecord.amount,
    additionalFee: debtRecord.amount * 0.05, // 5% dispute processing fee
    reasoning: 'No payment proof provided, debt valid per grace period terms'
  };
}
```

---

## 6. SLA & TIMELINES

### 6.1 SLA Targets

```typescript
const DISPUTE_SLA = {
  // Counter-party response window
  RESPONSE_WINDOW: 24, // hours
  
  // Admin resolution targets
  RESOLUTION_TARGET: 48, // hours
  RESOLUTION_URGENT: 24,  // hours (for high-priority)
  
  // Evidence submission deadline
  EVIDENCE_DEADLINE: 24, // hours after dispute creation
  
  // Appeal window (post-MVP feature - included for completeness)
  APPEAL_WINDOW: 72 // hours after resolution
};
```

### 6.2 SLA Timer & Escalation

```typescript
@Cron('0 * * * *') // Every hour
async function checkDisputeSLAs() {
  const now = new Date();
  
  // 1. Check for SLA breaches
  const overdueDisputes = await this.disputeRepository.find({
    status: In(['OPEN', 'PENDING_REVIEW']),
    slaDeadline: LessThan(now)
  });
  
  for (const dispute of overdueDisputes) {
    await this.escalateOverdueDispute(dispute);
  }
  
  // 2. Check approaching SLA deadlines (4 hours before)
  const approachingDeadline = addHours(now, 4);
  const urgentDisputes = await this.disputeRepository.find({
    status: In(['OPEN', 'PENDING_REVIEW']),
    slaDeadline: Between(now, approachingDeadline)
  });
  
  for (const dispute of urgentDisputes) {
    await this.sendUrgentReminder(dispute);
  }
}

async function escalateOverdueDispute(dispute: Dispute) {
  // Mark as overdue
  await this.disputeRepository.update(dispute.id, {
    slaBreached: true,
    slaBreachedAt: new Date()
  });
  
  // Notify senior admin
  await this.notificationService.send({
    to: 'ROLE:SENIOR_ADMIN',
    type: 'DISPUTE_SLA_BREACH',
    priority: 'CRITICAL',
    data: {
      disputeId: dispute.id,
      contractId: dispute.contractId,
      category: dispute.category,
      createdAt: dispute.createdAt,
      deadline: dispute.slaDeadline,
      hoursOverdue: differenceInHours(new Date(), dispute.slaDeadline)
    }
  });
  
  // Auto-compensate claimant if >72 hours overdue
  if (differenceInHours(new Date(), dispute.slaDeadline) > 72) {
    await this.autoCompensateSLABreach(dispute);
  }
}
```

### 6.3 Timeline Tracking

```typescript
interface DisputeTimeline {
  disputeId: string;
  events: DisputeEvent[];
  slaMetrics: {
    createdAt: Date;
    responseDeadline: Date;
    responseSubmittedAt?: Date;
    responseTimeTaken?: string;
    resolutionDeadline: Date;
    resolvedAt?: Date;
    resolutionTimeTaken?: string;
    slaBreached: boolean;
  };
}

interface DisputeEvent {
  timestamp: Date;
  type: string;
  actor: string;
  description: string;
  metadata?: object;
}

// Example timeline
const exampleTimeline = {
  disputeId: 'dispute-12345',
  events: [
    {
      timestamp: '2025-12-22T10:00:00Z',
      type: 'DISPUTE_CREATED',
      actor: 'business-789',
      description: 'Business created vehicle condition dispute'
    },
    {
      timestamp: '2025-12-22T10:01:00Z',
      type: 'EVIDENCE_UPLOADED',
      actor: 'business-789',
      description: 'Uploaded 5 photos showing vehicle damage'
    },
    {
      timestamp: '2025-12-22T15:30:00Z',
      type: 'COUNTER_EVIDENCE_SUBMITTED',
      actor: 'provider-456',
      description: 'Provider submitted counter-evidence with 3 photos'
    },
    {
      timestamp: '2025-12-23T09:00:00Z',
      type: 'ADMIN_REVIEW_STARTED',
      actor: 'admin-001',
      description: 'Admin began reviewing dispute'
    },
    {
      timestamp: '2025-12-23T11:30:00Z',
      type: 'DISPUTE_RESOLVED',
      actor: 'admin-001',
      description: 'Dispute resolved in favor of business'
    }
  ],
  slaMetrics: {
    createdAt: '2025-12-22T10:00:00Z',
    responseDeadline: '2025-12-23T10:00:00Z',
    responseSubmittedAt: '2025-12-22T15:30:00Z',
    responseTimeTaken: '5 hours 30 minutes',
    resolutionDeadline: '2025-12-24T10:00:00Z',
    resolvedAt: '2025-12-23T11:30:00Z',
    resolutionTimeTaken: '25 hours 30 minutes',
    slaBreached: false
  }
};
```

---

## 7. RESOLUTION OUTCOMES

### 7.1 Outcome Types

```typescript
enum ResolutionOutcome {
  CLAIMANT_WINS_FULL = 'CLAIMANT_WINS_FULL',           // 100% in favor of claimant
  RESPONDENT_WINS_FULL = 'RESPONDENT_WINS_FULL',       // 100% in favor of respondent
  PARTIAL_FAVOR_CLAIMANT = 'PARTIAL_FAVOR_CLAIMANT',   // 60-40 split
  PARTIAL_FAVOR_RESPONDENT = 'PARTIAL_FAVOR_RESPONDENT', // 40-60 split
  SPLIT_50_50 = 'SPLIT_50_50',                         // Equal split
  DISMISSED = 'DISMISSED',                              // No merit, dismissed
  NEED_MORE_INFO = 'NEED_MORE_INFO'                    // Cannot decide, need more evidence
}
```

### 7.2 Resolution Actions by Category

#### Vehicle Condition - Business Wins
```typescript
const actions = {
  IMMEDIATE: [
    'Provider must replace vehicle within 24 hours',
    'OR Business can reject delivery (full refund)',
    'OR Provider pays for repairs (business provides 2 quotes)'
  ],
  FINANCIAL: {
    businessRefund: 0, // If rejected
    providerPenalty: calculatePenalty('VEHICLE_CONDITION'),
    compensationToBusiness: contractValue * 0.10 // 10% discount
  },
  TRUST_SCORE: {
    providerImpact: -10, // points
    businessImpact: 0
  }
};
```

#### Non-Payment - Provider Wins
```typescript
const actions = {
  IMMEDIATE: [
    'Business must pay debt + 5% dispute processing fee',
    'Business account suspended until payment',
    'Provider keeps vehicles'
  ],
  FINANCIAL: {
    businessMustPay: debtAmount + (debtAmount * 0.05),
    providerReceives: debtAmount + (debtAmount * 0.05),
    platformKeeps: 0
  },
  TRUST_SCORE: {
    businessImpact: -15, // points
    providerImpact: +5   // points (for being right)
  },
  ACCOUNT_STATUS: {
    businessStatus: 'SUSPENDED',
    providerStatus: 'ACTIVE'
  }
};
```

#### Service Quality - Severe Issue
```typescript
const actions = {
  IMMEDIATE: [
    'Business receives 10% discount on contract',
    'Provider receives formal warning',
    'Provider must complete professionalism training'
  ],
  FINANCIAL: {
    businessDiscount: contractValue * 0.10,
    providerPenalty: 0, // Paid from discount
    settlementAdjustment: -0.10 // 10% reduction in provider settlement
  },
  TRUST_SCORE: {
    providerImpact: -20, // points
    businessImpact: 0
  },
  ADDITIONAL: {
    providerWarning: true,
    trainingRequired: 'PROFESSIONALISM_MODULE'
  }
};
```

### 7.3 Financial Adjustment Processing

```typescript
async function processFinancialAdjustment(resolution: ResolvedDispute) {
  const { winner, financialAdjustment } = resolution;
  
  switch (financialAdjustment.type) {
    case 'REFUND_TO_BUSINESS':
      await this.refundService.processRefund({
        businessId: resolution.businessId,
        amount: financialAdjustment.amount,
        reason: `Dispute resolution: ${resolution.disputeId}`,
        source: 'ESCROW'
      });
      break;
      
    case 'PAYMENT_TO_PROVIDER':
      await this.walletService.transfer({
        from: resolution.businessId,
        to: resolution.providerId,
        amount: financialAdjustment.amount,
        type: 'DISPUTE_RESOLUTION_PAYMENT'
      });
      break;
      
    case 'DISCOUNT_APPLIED':
      await this.contractRepository.update(resolution.contractId, {
        discountApplied: financialAdjustment.amount,
        discountReason: 'DISPUTE_RESOLUTION',
        adjustedTotalAmount: contract.totalAmount - financialAdjustment.amount
      });
      break;
      
    case 'PENALTY_CHARGED':
      await this.penaltyService.chargePenalty({
        userId: financialAdjustment.chargedTo,
        amount: financialAdjustment.amount,
        reason: `Dispute penalty: ${resolution.category}`,
        disputeId: resolution.disputeId
      });
      break;
  }
}
```

---

## 8. ESCALATION PROCEDURES

### 8.1 Escalation Triggers

```typescript
enum EscalationTrigger {
  SLA_BREACH = 'SLA_BREACH',                    // Resolution took >48 hours
  COMPLEX_CASE = 'COMPLEX_CASE',                // Requires senior review
  HIGH_VALUE = 'HIGH_VALUE',                    // Contract value >200k ETB
  REPEAT_OFFENDER = 'REPEAT_OFFENDER',          // Party has 3+ disputes
  FRAUD_SUSPECTED = 'FRAUD_SUSPECTED',          // Suspicious activity detected
  APPEAL_REQUESTED = 'APPEAL_REQUESTED'         // Party appeals resolution (post-MVP)
}

async function checkEscalationNeeded(dispute: Dispute): Promise<boolean> {
  // 1. Check contract value
  const contract = await this.contractRepository.findById(dispute.contractId);
  if (contract.totalAmount > 200000) {
    return true; // High-value escalation
  }
  
  // 2. Check repeat offender status
  const disputeHistory = await this.getDisputeHistory(dispute.claimantId);
  if (disputeHistory.length >= 3) {
    return true; // Repeat offender
  }
  
  // 3. Check fraud indicators
  const fraudScore = await this.calculateFraudScore(dispute);
  if (fraudScore > 0.7) {
    return true; // Fraud suspected
  }
  
  // 4. Check case complexity
  if (dispute.evidenceCount > 20 || dispute.category === 'CONTRACT_TERMS') {
    return true; // Complex case
  }
  
  return false;
}
```

### 8.2 Escalation Workflow

```typescript
async function escalateDispute(
  disputeId: string,
  trigger: EscalationTrigger
) {
  const dispute = await this.disputeRepository.findById(disputeId);
  
  // 1. Mark as escalated
  await this.disputeRepository.update(disputeId, {
    escalated: true,
    escalatedAt: new Date(),
    escalationReason: trigger,
    priority: 'CRITICAL'
  });
  
  // 2. Assign to senior admin
  const seniorAdmin = await this.getAvailableSeniorAdmin();
  await this.assignDispute(disputeId, seniorAdmin.id);
  
  // 3. Notify senior admin
  await this.notificationService.send({
    to: seniorAdmin.id,
    type: 'DISPUTE_ESCALATED',
    priority: 'CRITICAL',
    data: {
      disputeId,
      trigger,
      contractValue: dispute.contract.totalAmount,
      category: dispute.category,
      timeline: await this.getDisputeTimeline(disputeId)
    }
  });
  
  // 4. If fraud suspected, freeze accounts
  if (trigger === 'FRAUD_SUSPECTED') {
    await this.freezeAccounts(dispute);
  }
  
  // 5. Notify parties of escalation
  await this.notifyPartiesOfEscalation(dispute);
}
```

---

## 9. AUTOMATED DISPUTE HANDLING

### 9.1 Auto-Creation: Debt Escalation

```typescript
// From settlement processing - after 30 days of unpaid debt
@Cron('0 0 * * *') // Daily check
async function checkAutoDisputeCreation() {
  const overdueDebts = await this.debtRepository.find({
    status: 'OUTSTANDING',
    createdAt: LessThan(subDays(new Date(), 30))
  });
  
  for (const debt of overdueDebts) {
    // Auto-create dispute
    const dispute = await this.createDispute({
      contractId: debt.contractId,
      createdBy: 'SYSTEM',
      creatorType: 'SYSTEM',
      onBehalfOf: debt.providerId,
      category: 'NON_PAYMENT',
      description: `Automated dispute for unpaid debt of ${debt.amount} ETB. Debt overdue by 30 days.`,
      evidence: {
        debtRecord: debt,
        calculation: debt.breakdown,
        paymentRequests: await this.getPaymentRequests(debt.contractId)
      }
    });
    
    // Update debt with dispute reference
    await this.debtRepository.update(debt.id, {
      status: 'IN_DISPUTE',
      disputeId: dispute.id
    });
  }
}
```

### 9.2 Auto-Resolution: Clear-Cut Cases

```typescript
async function checkAutoResolution(dispute: Dispute): Promise<boolean> {
  // Only auto-resolve if evidence is overwhelming
  
  switch (dispute.category) {
    case 'NON_PAYMENT':
      // Auto-resolve if payment proof exists
      const paymentProof = await this.checkPaymentProof(dispute);
      if (paymentProof.verified) {
        await this.autoResolve(dispute, {
          winner: dispute.claimantId,
          outcome: 'CLAIMANT_WINS_FULL',
          reasoning: 'Payment receipt verified via blockchain/wallet transaction',
          action: 'WAIVE_DEBT'
        });
        return true;
      }
      break;
      
    case 'DELIVERY_ISSUE':
      // Auto-resolve if GPS proves provider was at location
      const gpsData = await this.getGPSData(dispute.contractId);
      if (gpsData.providerAtLocation && gpsData.businessNoShow) {
        await this.autoResolve(dispute, {
          winner: dispute.respondentId,
          outcome: 'RESPONDENT_WINS_FULL',
          reasoning: 'GPS data shows provider at delivery location, business no-show',
          action: 'BUSINESS_AT_FAULT'
        });
        return true;
      }
      break;
  }
  
  return false; // Cannot auto-resolve, needs manual review
}
```

---

## 10. POST-RESOLUTION ACTIONS

### 10.1 Contract Status Update

```typescript
async function updateContractAfterResolution(resolution: ResolvedDispute) {
  const contract = await this.contractRepository.findById(resolution.contractId);
  
  // Determine new contract status based on resolution
  let newStatus: ContractStatus;
  
  switch (resolution.outcome) {
    case 'CLAIMANT_WINS_FULL':
    case 'RESPONDENT_WINS_FULL':
    case 'PARTIAL_FAVOR_CLAIMANT':
    case 'PARTIAL_FAVOR_RESPONDENT':
      // Return to previous status (usually ACTIVE)
      newStatus = contract.previousStatus || 'ACTIVE';
      break;
      
    case 'DISMISSED':
      // Return to previous status
      newStatus = contract.previousStatus || 'ACTIVE';
      break;
  }
  
  // Update contract
  await this.contractStateMachine.transitionTo(
    contract.id,
    newStatus,
    `Dispute resolved: ${resolution.outcome}`
  );
  
  // Record dispute in contract history
  await this.contractRepository.update(contract.id, {
    disputeHistory: [...contract.disputeHistory, {
      disputeId: resolution.disputeId,
      category: resolution.category,
      outcome: resolution.outcome,
      resolvedAt: resolution.resolvedAt
    }]
  });
}
```

### 10.2 Trust Score Impact

```typescript
async function updateTrustScores(resolution: ResolvedDispute) {
  const impact = calculateTrustScoreImpact(resolution);
  
  // Update business trust score
  if (impact.business !== 0) {
    await this.trustScoreService.adjustScore({
      userId: resolution.businessId,
      adjustment: impact.business,
      reason: `Dispute resolution: ${resolution.category}`,
      disputeId: resolution.disputeId
    });
  }
  
  // Update provider trust score
  if (impact.provider !== 0) {
    await this.trustScoreService.adjustScore({
      userId: resolution.providerId,
      adjustment: impact.provider,
      reason: `Dispute resolution: ${resolution.category}`,
      disputeId: resolution.disputeId
    });
  }
}

function calculateTrustScoreImpact(resolution: ResolvedDispute): TrustScoreImpact {
  const impacts = {
    VEHICLE_CONDITION: {
      winnerGain: 0,
      loserLoss: -10
    },
    SERVICE_QUALITY: {
      winnerGain: 0,
      loserLoss: -20 // More severe
    },
    NON_PAYMENT: {
      winnerGain: +5,
      loserLoss: -15
    },
    DELIVERY_ISSUE: {
      winnerGain: 0,
      loserLoss: -10
    },
    CONTRACT_TERMS: {
      winnerGain: 0,
      loserLoss: -5 // Less severe
    }
  };
  
  const categoryImpact = impacts[resolution.category];
  const winner = resolution.winner;
  
  return {
    business: winner === resolution.businessId ? categoryImpact.winnerGain : categoryImpact.loserLoss,
    provider: winner === resolution.providerId ? categoryImpact.winnerGain : categoryImpact.loserLoss
  };
}
```

### 10.3 Notification Templates

```typescript
async function notifyResolution(resolution: ResolvedDispute) {
  // Notify winner
  await this.notificationService.send({
    to: resolution.winner,
    type: 'DISPUTE_RESOLVED_WON',
    priority: 'HIGH',
    template: {
      title: 'Dispute Resolved in Your Favor',
      body: `Your dispute regarding ${resolution.category} has been resolved in your favor.`,
      reasoning: resolution.resolutionReasoning,
      actions: resolution.actions,
      financialImpact: resolution.financialAdjustment
    }
  });
  
  // Notify loser
  const loser = resolution.winner === resolution.businessId 
    ? resolution.providerId 
    : resolution.businessId;
    
  await this.notificationService.send({
    to: loser,
    type: 'DISPUTE_RESOLVED_LOST',
    priority: 'HIGH',
    template: {
      title: 'Dispute Resolution',
      body: `The dispute regarding ${resolution.category} has been resolved.`,
      reasoning: resolution.resolutionReasoning,
      requiredActions: resolution.actions,
      financialImpact: resolution.financialAdjustment,
      nextSteps: resolution.nextSteps
    }
  });
}
```

---

## APPENDIX A: Dispute Database Schema

```sql
CREATE TABLE disputes_schema.disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id UUID NOT NULL REFERENCES contracts_schema.contracts(id),
  
  -- Parties
  created_by UUID NOT NULL,
  creator_type VARCHAR(20) NOT NULL, -- BUSINESS, PROVIDER, SYSTEM, ADMIN
  on_behalf_of UUID, -- If SYSTEM or ADMIN creates
  claimant_id UUID NOT NULL,
  respondent_id UUID NOT NULL,
  
  -- Dispute details
  category VARCHAR(50) NOT NULL,
  description TEXT NOT NULL,
  status VARCHAR(50) NOT NULL,
  priority VARCHAR(20) NOT NULL,
  
  -- Resolution
  resolved_by UUID,
  resolved_at TIMESTAMP,
  resolution VARCHAR(50),
  resolution_reasoning TEXT,
  winner UUID,
  outcome VARCHAR(50),
  
  -- Financial
  financial_adjustment JSONB,
  
  -- SLA
  sla_deadline TIMESTAMP NOT NULL,
  sla_breached BOOLEAN DEFAULT false,
  sla_breached_at TIMESTAMP,
  
  -- Evidence
  evidence_count INTEGER DEFAULT 0,
  counter_evidence_submitted BOOLEAN DEFAULT false,
  counter_evidence_submitted_at TIMESTAMP,
  
  -- Escalation
  escalated BOOLEAN DEFAULT false,
  escalated_at TIMESTAMP,
  escalation_reason VARCHAR(50),
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE disputes_schema.evidence (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dispute_id UUID NOT NULL REFERENCES disputes_schema.disputes(id),
  
  -- Evidence details
  type VARCHAR(50) NOT NULL,
  filename VARCHAR(255) NOT NULL,
  file_url TEXT NOT NULL,
  file_size BIGINT NOT NULL,
  mime_type VARCHAR(100) NOT NULL,
  description TEXT,
  
  -- Upload details
  uploaded_by UUID NOT NULL,
  uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE disputes_schema.dispute_timeline (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dispute_id UUID NOT NULL REFERENCES disputes_schema.disputes(id),
  
  -- Event details
  event_type VARCHAR(50) NOT NULL,
  actor_id UUID,
  actor_type VARCHAR(20),
  description TEXT NOT NULL,
  metadata JSONB,
  
  -- Timestamp
  occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_disputes_contract ON disputes_schema.disputes(contract_id);
CREATE INDEX idx_disputes_claimant ON disputes_schema.disputes(claimant_id);
CREATE INDEX idx_disputes_respondent ON disputes_schema.disputes(respondent_id);
CREATE INDEX idx_disputes_status ON disputes_schema.disputes(status);
CREATE INDEX idx_disputes_category ON disputes_schema.disputes(category);
CREATE INDEX idx_disputes_sla ON disputes_schema.disputes(sla_deadline) WHERE status IN ('OPEN', 'PENDING_REVIEW');

CREATE INDEX idx_evidence_dispute ON disputes_schema.evidence(dispute_id);
CREATE INDEX idx_timeline_dispute ON disputes_schema.dispute_timeline(dispute_id);
```

---

**END OF DISPUTE RESOLUTION WORKFLOW SPECIFICATION**

---

**For Implementation:** Use this document as reference for:
1. Dispute category definitions and validation
2. Evidence requirements and upload handling
3. Resolution decision trees
4. SLA monitoring and escalation
5. Financial adjustment processing

**For Testing:** Verify:
1. All dispute categories can be created with proper evidence
2. Counter-party response window enforced (24 hours)
3. SLA deadlines monitored and breaches handled
4. Resolutions execute all required actions
5. Trust scores updated correctly
6. Financial adjustments processed accurately
