# Business Analysis Questionnaire
## Movello B2B Mobility Marketplace Platform

**Purpose:** This questionnaire captures your decisions and responses for each issue identified in the comprehensive business analysis report.

**Instructions:**
- Fill in your response for each question
- Provide justification/notes where applicable
- Mark priority: 🔴 HIGH | 🟡 MEDIUM | 🟢 LOW
- Add any additional context or constraints

---

## 1. REQUIREMENT CONSISTENCY ISSUES

### Issue 1.1.1: Trust Score Calculation - Contradictory Specifications

**Context:**
- Multiple documents specify different trust score approaches
- Business_Rules.md: "Initial Score: 0 (new providers)"
- Trust Engine Spec: Complex signal-based system with decay algorithms
- CTO Analysis: "DELETE risk algorithm, replace with simple 'Verified' badge"

**Question 1.1.1:** What trust score calculation should be implemented for MVP?

- [ ] Simple calculation (completion rate, on-time rate, no-show rate) - NO decay algorithms
- [ ] Simple "Verified" badge only (no numeric score)
- [ ] Complex signal-based system with decay algorithms
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Use Simple calculation  (completion rate, on-time rate, no-show rate) - NO decay algorithms and add being verified as one criteria and to get the intial or default trust score. make it 50 point for being verified
```

**Justification/Notes:**
```
New users should have an intital trust score when they complete the verification process and get verified so the point 50 is because they might improve it by their completeion rate, ontime rate and soon to 100 or make it to zero by no show rate. Users with unverified or pending profile will have a default score of zero
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🔴] Create single authoritative document defining trust score MVP scope
- [ 🟡] Remove conflicting specifications
- [ 🔴] Update implementation plan

---

### Issue 1.1.2: RFQ Creation Wallet Requirement - Documented Contradiction

**Context:**
- CRITICAL_BUSINESS_RULE_UPDATE.md (Nov 26, 2025): "NO wallet balance required to create/publish RFQs"
- 13_Movello_Business_Rules_Specification.md (older): "Must maintain sufficient balance to fund the next billing cycle"

**Question 1.1.2:** Which rule is correct for RFQ creation?

- [ ] NO wallet balance required (as per CRITICAL_BUSINESS_RULE_UPDATE.md)
- [ ] Wallet balance required before RFQ creation
- [ ] Wallet balance required only for publishing (not creation)
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Only being verified is required for business to create RFQ, and having a balance in wallet is not required to create RFQ but a balance in wallet is required to award a bid.
```

**Justification/Notes:**
```
requiring a balance from business will make them less interested to creat RFQ for the amount they don't know. But, if we ask them to deposit for the bid they award that would be a reasonable and they will comply with it. 
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ 🔴] Update 13_Movello_Business_Rules_Specification.md to reflect decision
- [ 🟢] Add version control to business rules documents
- [🟡 ] Update API validation logic

---

### Issue 1.1.3: Escrow Lock Timing - Multiple Conflicting Definitions

**Context:**
- Business_Rules.md: "Escrow lock = Monthly cost (or full cost for short rentals)"
- Business_Logic_Flows.md: "Escrow Lock: Required before vehicle assignment"
- Finance_Module.md: Shows escrow lock happening after award
- CRITICAL_BUSINESS_RULE_UPDATE.md: "Escrow locked immediately after award"

**Question 1.1.3:** When exactly should escrow be locked in the workflow?

- [ ] Before contract creation (immediately after award)
- [ ] After contract creation but before vehicle assignment
- [ ] After vehicle assignment but before activation
- [ ] Other: _________________________________________________

**Your Decision:** 
```
After contract creation but before vehicle assignment 
```

**Proposed Sequence:**
```
1. The business should deposit for the bid they award to award a bid or they should have enough amount in their wallet
2. Contract will be created for awarded bid for each providers and 
3. upon successful contract creation escrow will be locked per contract so that the business will have a insured contract prepared with providers
4. awarded providers must assign vehicles for the contract or for the award they get
5. Contract activation will be ready by three conditions 1, Contract is Created 2, Enough amount is locked in escrow for the contract 3, Vehcile is assigned by the provider other wise the contract will not be continue or activated for vehicle handover and processing
6, upon contract activation the provider should deliver the vehicles on the requested date and should confirm delivery by OTP/QR then the contract will be started
```

**Justification/Notes:**
```
Escrow lock should be per contract as one RFQ may have multiple line item and each lineitem may have mulptiple bid award for multiple providers because of split award, we need to create a contract for each provider and each provider contract should have a guaranteed locked fund to be activated
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🔴] Define clear sequence: Award → Contract Creation → Escrow Lock  → Vehicle Assignment → Activation
- [🔴] Update all documents to reflect decision
- [🔴] Update Finance module implementation

---

## 2. MODULE RESPONSIBILITY BOUNDARIES

### Issue 1.2.1: Contract Creation Responsibility - Unclear Ownership

**Context:**
- Contracts_Module.md: "Contract Creation (Auto-triggered)" - triggered by `BidAwardedEvent`
- Business_Logic_Flows.md: Shows contract creation happening after escrow lock
- Finance module also needs to validate wallet balance before locking escrow

**Question 1.2.1:** What is the correct sequence and responsibility for contract creation?

**Proposed Sequence:**
```
1. Marketplace: Award bid → Publish `BidAwardedEvent` (includes escrow amount)
2. Finance: Receive event → Validate wallet → Lock escrow → Publish `EscrowLockedEvent`
3. Contracts: Receive `EscrowLockedEvent` → Create contract → Publish `ContractCreatedEvent`
```

**Your Decision:** 
```
Contract creation should be triggered by bidawardevent not escrowlockedevent but escrow lock should be triggered by Contract creation eevnt
```

**Error Handling:**
- What happens if Finance fails to lock escrow?
  ```
  Contract will be put in hold so that it will not be activated for vehicle assignment but contract on this status will be checked by a background service for retry
  ```

- What happens if Contracts fails to create contract after bid award?
  ```
  then the bid  award will be reverted so that the user will do a retry
  ```

**Justification/Notes:**
```
Escrow lock will happen when we have a contravt created and will do a lock so that the provider can assign vehciles
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ 🟡] Document the sequence clearly
- [ 🔴] Define rollback procedures
- [ 🟡] Update module specifications

---

### Issue 1.2.2: Trust Score Calculation - Module Ownership Unclear

**Context:**
- Identity module has `TrustScoreCalculator` service
- But trust score depends on data from Contracts, Delivery, Finance modules

**Question 1.2.2:** How should Identity module access data from other modules for trust score calculation?

- [ ] Through events (subscribe to ContractCompletedEvent, DeliveryConfirmedEvent, etc.)
- [ ] Direct queries to other modules' databases
- [ ] Service interfaces (synchronous calls)
- [ ] Other: _________________________________________________

**Your Decision:** 
```
It will be through events
```

**Event Subscriptions Required:**
- [ ] ContractCompletedEvent
- [ ] DeliveryConfirmedEvent
- [ ] NoShowEvent
- [ ] DisputeResolvedEvent
- [ ] Other: _________________________________________________

**Justification/Notes:**
```
The trust score calculation will be handled in one place but triggered from multiple modules so having the trust score implementaion every where will lead to code redundancy that makes it hard to maintain
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ 🟡] Document event flow clearly
- [ 🔴] Update Identity module specification
- [ 🔴] Define trust score recalculation triggers

---

### Issue 1.2.3: Settlement Processing - Finance Module Dependency Chain

**Context:**
- Settlement requires contract completion data from Contracts module
- Settlement requires commission rates from MasterData module
- Settlement requires penalty data from Contracts module

**Question 1.2.3:** How should Finance module access data for settlement processing?

- [ ] Finance queries Contracts module via internal service interface (synchronous)
- [x] Contracts module publishes events with settlement data (asynchronous)
- [x] Finance queries MasterData module directly for commission rates
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Settlement triggered by multiple events:
1. ContractCompletedEvent → Normal settlement
2. ContractAlteredEvent → Adjustment settlement (pro-rata refunds/charges)
3. EarlyReturnEvent → Early termination settlement with penalties

Finance subscribes to all three events.
For each event, Finance:
- Reads contract data from event payload
- Queries MasterData for commission rates (direct DB read or Redis cache)
- Calculates settlement amount
- Processes payment to provider
```

**Data Access Pattern:**
```
its an event based pub/sub way where the finance module subscribe and the contract module publish to contractCompletedEvent
```

**Justification/Notes:**
```
Only the contract module can track the completenes of contracts. the responsibility of finance module will be to process finance related tasks not contract related logics. but the settlement can be triggered by contract completeion, contract alteration and some other things
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ 🔴] Document the chosen pattern clearly
- [🟡] Update Finance module specification
- [ 🔴] Define data contracts/interfaces

---

## 3. BUSINESS FLOW GAPS

### Gap 2.1.1: Business Award Flow - Missing Error Recovery

**Context:**
- Flow shows: "IF available_balance < total_escrow_required: Show error"
- Missing: Retry mechanism, partial award handling, provider rejection handling

**Question 2.1.1:** How should the system handle award failures and retries?

**Award Retry After Deposit:**
- [x] Allow business to retry award after depositing funds
- [x] Require business to manually trigger retry
- [ ] Auto-retry when balance becomes sufficient
- [ ] Other: _________________________________________________

**Your Decision:** 
```
IF available_balance < total_escrow_required: Show error but Allow business to retry award after depositing funds and for every award the need to have sufficent funds. There will not be an auto award that will lead to a dispute because of unintentional awarding
```

**Partial Award Handling:**
- If business can only afford 2 of 10 vehicles, what happens to remaining 8?
  - [x] Business deposits more funds and awards remaining OR
  - [x] Create new RFQ for remaining vehicles
  - [ ] Cancel remaining vehicles
  - [ ] Extend deadline and allow more bids
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
System informs business their balance can only award X vehicles out of Y requested.
Options:
1. Deposit more funds and award all vehicles
2. Award partial (X vehicles) → Line item status = AWARDED, unselected bids = LOST
3. Create new RFQ for remaining (Y-X) vehicles

RFQ Status Logic:
- PARTIALLY_AWARDED: If RFQ has multiple line items AND some awarded + some still bidding
- AWARDED: When ALL line items are awarded
```

**Provider Rejection After Award:**
- What if provider rejects award after being awarded?
  ```
Manual re-award process:
1. Notify business about provider rejection
2. Rejected provider excluded from future awards for this RFQ
3. Business manually selects next provider to award
4. System reactivates bids that were in LOST status for business selection

Bid Status Flow:
- BIDDING → AWARDED (selected provider)
- BIDDING → LOST (unselected providers)
- AWARDED → REJECTED (if provider rejects)
- LOST → BIDDING (if awarded provider rejects, making bids available again)

No penalty for legitimate first-time rejections (vehicle broken, maintenance, insurance expired).
  ```

**Justification/Notes:**
```
this will protect the business from awarding a bid with insufficent balance and avoid contract creation without secured fund. if there is no secured fund there will not be a vehicle assignment by providers and contract activation
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🔴] Add award retry flow after deposit
- [🟡] Add partial award confirmation dialog
- [🟡] Add provider rejection handling

---

### Gap 2.1.2: Delivery OTP Flow - Missing Failure Scenarios

**Context:**
- Flow shows: "IF INVALID: Increment attempts, IF attempts >= 3: Block for 30 minutes"
- Missing: OTP expiry handling, no-show handling, delivery rejection flow

**Question 2.1.2:** How should the system handle OTP and delivery failures?

**OTP Expiry Handling:**
- [ ] Provider can request new OTP if expired
- [ ] OTP auto-regenerates after expiry
- [ ] Business must contact provider to get new OTP
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Provider can request new OTP if expired
```

**Business No-Show for Delivery:**
- What if provider arrives but business contact person is unavailable?
  ```
  There will be a penality. business schedule a time and place for vehicle handover and assign a contact person for handover. 
  ```

**Delivery Rejection After OTP:**
- Can business reject delivery after OTP verification if vehicle condition is poor?
  - [ ] Yes, with reason required
  - [ ] No, OTP verification is final acceptance
  - [ ] Yes, but only for specific reasons (damage, wrong vehicle, etc.)
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
 No, OTP verification is final acceptance
```

**Vehicle Condition Mismatch:**
- What if vehicle condition doesn't match expectations?
  ```
  Then the business shouldn't confirm the delivery through OTP, ask provider for another vehicle replacement, if that is not worked it will raise a dispute and can award another provider. and contract will be altered after the dispute is settled (if the business decide to award another provider)
  ```

**Justification/Notes:**
```
OTP verification means the business confirmed the vehicle fulfilled their expectation. After they confirmed through OTP then having a damage or some issues will not be accepted but they can do an early return request which can be handled by another flow. But they can reject the delivery if they are not satisfied by the car. 
OTP also can be expired because of different network issue like late delivery of the message to the business
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ 🔴] Add OTP regeneration flow
- [ 🟡] Add delivery rejection flow
- [ 🟡] Add no-show handling

---

### Gap 2.1.3: Early Return Flow - Incomplete Penalty Application

**Context:**
- Flow shows penalty calculation but doesn't specify approval workflow, dispute handling, damage assessment

**Question 2.1.3:** How should early returns be processed and approved?

**Early Return Approval:**
- [ ] Auto-approved (no approval needed)
- [ ] Business approval required
- [ ] Provider approval required
- [ ] Both business and provider must approve
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Both should approve
```

**Provider Dispute of Early Return:**
- What if provider disputes the early return reason?
  ```
  To avoid disputes early return will require an early return notice of a week. requesting for early return for less than a week would be penalized based on the notice time they gave. 
  ```

**Damage Assessment:**
- What if vehicle is damaged during early return?
  ```
  Then the business will cover the damage price and that will be enforced by law enfoement and for that the provider should rais a dispute
  ```

**Penalty Communication:**
- How is penalty communicated to business?
  - [ ] Email notification
  - [ ] In-app notification
  - [ ] SMS notification
  - [ ] All of the above
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
All of the above
```

**Justification/Notes:**
```
We have user communication preference SMS and email will be supported but the in-app is default
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ 🟢] Define early return approval workflow
- [ 🟢] Add damage assessment process
- [ 🟢] Add dispute escalation path

---

## 4. APPROVAL PROCESSES

### Missing 2.2.1: Document Verification Approval Process

**Context:**
- Documents state: "Compliance Officer Reviews" but don't specify reviewer roles, criteria, SLA, rejection process, appeal process

**Question 2.2.1:** Define the document verification approval process.

**Reviewer Roles:**
- Who can review documents?
  ```
  Compliance Officer
  ```

**Review Criteria:**
- What is the checklist for document review?
  ```
  1, Business lifetime
  2, Business license accuracy
  3, Business Capital
  4, Car ownership (Libre)
  5, Vehicle Insurance
  6, Attorney document check
  7, Insurance expiry
  ```

**SLA (Service Level Agreement):**
- How long should review take?
  - [ ] 24 hours
  - [ ] 48 hours
  - [ ] 72 hours
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
48 hours
```

**Rejection Process:**
- Can documents be rejected with feedback?
  - [ ] Yes, with detailed feedback
  - ] Yes, with standard rejection reasons
  - [ ] No, only approve or request resubmission
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Yes, with standard rejection reasons
```

**Appeal Process:**
- What is the appeal process if documents are rejected?
  ```
  We don't have appeal process at all
  ```

**Reviewer Unavailability:**
- What happens if reviewer is unavailable?
  ```
  There should be one. and review will be continued when its available
  ```

**Justification/Notes:**
```
The rejection reasons will be with a predefined rejection reasons so that the user will fullfill them 
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🟡 ] Create Document Verification SOP
- [🔴 ] Define reviewer roles and checklist
- [ 🔴] Add to Identity module specification

---

### Missing 2.2.2: Insurance Verification Approval Process

**Context:**
- Documents state: "Insurance must be valid for at least 30 days"
- Missing: Verification method, authenticity check, fraud detection, timeline

**Question 2.2.2:** Define the insurance verification process.

**Verification Method:**
- [ ] Manual verification (MVP)
- [ ] Automated API integration (POST-MVP)
- [ ] Hybrid (automated + manual review)
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Manual Verification for MVP then we will have Hybrid
```

**Authenticity Verification:**
- How is insurance authenticity verified?
  ```
  Manual
  ```

**Fraud Detection:**
- What if insurance certificate is fake?
  ```
  We will flag that vehicle as suspended
  ```

**Verification Timeline:**
- How long does verification take?
  ```
  48 hrs
  ```

**Verification Checklist:**
- What are the verification criteria?
  ```
 Expiration time, Insurance type, insurace coverage amount
  ```

**Justification/Notes:**
```
on mvp level we ill do the manual verification then we will API check with supported insurance companies
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🟢] Define insurance verification process
- [🟢] Add verification checklist
- [🟢] Add fraud detection criteria

---

### Missing 2.2.3: Settlement Approval Process

**Context:**
- Documents state: "Automatic Processing" but don't specify approval workflow, dispute handling, large payout handling

**Question 2.2.3:** Define the settlement approval workflow.

**Approval Method:**
- [ ] Auto-approve all settlements
- [ ] Manual approval for all settlements
- [ ] Auto-approve below threshold, manual above threshold
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Auto-approve below threshold, manual above threshold
```

**Approval Threshold:**
- If using threshold-based approval, what is the threshold?
  ```
  100,000
  ```

**Disputed Settlement:**
- What if settlement amount is disputed?
  ```
  We will avoid dispute from settlement upon contract creation. but the dispute will be handled by dispute handler. 
  ```

**Flagged Provider:**
- What if provider account is flagged?
  - [ ] Auto-approve (flag doesn't affect settlement)
  - [ ] Manual review required
  - [ ] Hold settlement until flag is resolved
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Manual review required
```

**Large Payout Workflow:**
- What is the approval workflow for large payouts?
  ```
  Finance officer will review them and approve them for release
  ```

**Justification/Notes:**
```
finance officer will check and approve them to avoid liquidation. but the main target is to creat transparency 
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🟢] Define settlement approval workflow
- [ 🟢] Specify thresholds and flags
- [🔴] Update Finance module specification

---

## 5. PRE-ACTION REQUIREMENTS

### Issue 2.3.1: RFQ Creation Prerequisites - Incomplete Checklist

**Context:**
- Current: "Wallet Balance: ⚠️ NO wallet balance required"
- Missing: Business status, onboarding completion, Terms of Service acceptance, suspension check

**Question 2.3.1:** What are the complete prerequisites for RFQ creation?

**Prerequisites Checklist:**
- [ ] Business must be VERIFIED (status = ACTIVE)
- [ ] Business must have completed onboarding
- [ ] Business must have accepted Terms of Service
- [ ] Business must not be suspended or flagged
- [ ] Business must have valid contact information
- [ ] Other: _________________________________________________

**Your Decision:** 
```
- [ ] Business must be VERIFIED (status = ACTIVE)
```

**Validation Rules:**
- How should these be validated at API level?
  ```
  so the business will be verified by compliance officer if the busines provided all the informations then the status will be set verified so checking that is enough
  ```

**Justification/Notes:**
```
Unverified business means incompleted profile and that would break the KYC verified business principle
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🟡] Add complete prerequisite checklist
- [🟡] Document validation rules in API specification
- [🔴] Update RFQ creation endpoint

---

### Issue 2.3.2: Bid Submission Prerequisites - Missing Vehicle Availability Check

**Context:**
- Current: "Provider must have sufficient *active* and *unassigned* vehicles"
- Missing: Real-time availability check, insurance validity check, provider account status check

**Question 2.3.2:** What validations should occur at bid submission and award time?

**Pre-Bid Validation:**
- [ ] Real-time vehicle availability check
- [ ] Insurance validity check (must be valid through delivery date)
- [ ] Provider account status check (not suspended)
- [ ] Provider trust score check (minimum threshold)
- [ ] Other: _________________________________________________

**Your Decision:** 
```
- [ ] Real-time vehicle availability check (the provider should have active or unassigned vehicles by the requestd vehicle specs)
- [ ] Insurance validity check (must be valid through delivery date for the active vehicles)
- [ ] Provider account status check (not suspended)
- [ ] Provider trust score check (minimum threshold)

```

**Re-Validation at Award Time:**
- Should validations be re-checked at award time?
  - [ ] Yes, re-validate all checks
  - [ ] No, bid-time validation is sufficient
  - [ ] Yes, but only critical checks (availability, insurance)
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
[ ] Yes, re-validate all checks
```

**Vehicle Availability Between Bid and Award:**
- What if vehicle becomes unavailable between bid submission and award?
  ```
  Everytime we will check if the provider has a valid vehicle for the request bid. 
  ```

**Justification/Notes:**
```
If the provider doesn't fullfill those criteria we protect them from bidding to avoid failed delivery and business disatisfaction and to avoid fraud
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🔴] Add pre-bid validation checklist
- [🔴] Add re-validation at award time
- [🔴] Update bid submission endpoint

---

### Issue 2.3.3: Contract Activation Prerequisites - Dual Requirement Unclear

**Context:**
- Current: "Contract becomes active only when **BOTH** conditions are met: Escrow Lock + Vehicle Delivery"
- Missing: Failure handling, timeout, rollback procedures

**Question 2.3.3:** How should contract activation handle failures and timeouts?

**Failure Scenarios:**
- What if escrow lock succeeds but delivery fails?
  ```
  Penality of providers will be appplied and reactivation of other providers bid for the same RFQ but the failed provider will be excluded
  ```

- What if delivery succeeds but escrow lock fails?
  ```
  escrow lock will happend before delivery but after contract creation
  ```

**Timeout Handling:**
- How long can contract stay in PENDING_ACTIVATION?
  - [ ] 3 days
  - [ ] 7 days
  - [ ] 14 days
  - [ ] No timeout
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
5 days
```

**Timeout Action:**
- What happens if timeout is reached?
  - [ ] Auto-cancel contract
  - [ ] Notify business and provider
  - [ ] Escalate to support
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Notify business and provider
```

**Rollback Procedures:**
- What is the rollback procedure for each failure scenario?
  ```
 contract cancellation and or RFQ activation
  ```

**Justification/Notes:**
```
if the contract is not activated with in 5 days we will count that the delivery is not happened or the escrow fund is not happened which needs to lead contract termination 
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🔴] Define contract activation state machine clearly
- [🔴] Add timeout handling
- [🔴] Add rollback procedures

---

## 6. EVENT-DRIVEN WORKFLOW ISSUES

### Gap 3.1.1: Missing Critical Events

**Context:**
- Event catalog exists but missing error events, timeout events, edge case events

**Question 3.1.1:** Which missing events should be added to the event catalog?

**Missing Events to Add:**
- [ ] EscrowLockFailedEvent - What if escrow lock fails after award?
- [ ] ProviderRejectedAwardEvent - What if provider rejects after award?
- [ ] DeliveryRejectedEvent - What if business rejects delivery after OTP?
- [ ] InsuranceExpiringEvent - 30-day warning
- [ ] ContractActivationTimeoutEvent - Contract stuck in pending
- [ ] SettlementDisputedEvent - Provider disputes settlement amount
- [ ] Other: _________________________________________________

**Your Decision:** 
```
- [ ] EscrowLockFailedEvent - What if escrow lock fails after award?
- [ ] ProviderRejectedAwardEvent - What if provider rejects after award?
- [ ] DeliveryRejectedEvent - What if business rejects delivery after OTP?
- [ ] InsuranceExpiringEvent - 30-day warning
- [ ] ContractActivationTimeoutEvent - Contract stuck in pending
- [ ] SettlementDisputedEvent - Provider disputes settlement amount
- [ ] EscrowLockedEvent  what will happen when escrow is locked or deposited?
```

**Event Handlers:**
```

- [ ] EscrowLockFailedEvent - Contract will be put in pending status
- [ ]EscrowLockedEvent - Contract will be put in funded status
- [ ] ProviderRejectedAwardEvent - What if provider rejects after award?
- [ ] DeliveryRejectedEvent - What if business rejects delivery after OTP?
- [ ] InsuranceExpiringEvent - 30-day warning
- [ ] ContractActivationTimeoutEvent - Contract stuck in pending
- [ ] SettlementDisputedEvent - Provider disputes settlement amount
  
  ```

**Event Retry Policies:**
- Should events have retry policies?
  - [ ] Yes, all events
  - [ ] Yes, only critical events
  - [ ] No retry
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Yes, all events 
```

**Justification/Notes:**
```
becuase we are following event based module communication and one event should trigger the other and the failuer of one event will break the whole flow. 
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🔴] Add complete event catalog including all error and edge case events
- [🔴] Document event handlers for each event
- [🔴] Define event retry policies

---

### Gap 3.1.2: Event Handler Failure Scenarios

**Context:**
- Documents show event handlers but don't specify failure handling, idempotency, timeout, event loss

**Question 3.1.2:** How should event processing handle failures and ensure reliability?

**Event Processing Guarantees:**
- [ ] At-least-once delivery (events may be processed multiple times)
- [ ] Exactly-once delivery (events processed exactly once)
- [ ] At-most-once delivery (events may be lost)
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Exactly-once delivery (events processed exactly once)
```

**Idempotency:**
- Should all events have idempotency keys?
  - [ ] Yes, all events
  - [ ] Yes, only critical events
  - [ ] No
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Yes, all events
```

**Event Handler Failure:**
- What if event handler fails?
  - [ ] Retry with exponential backoff
  - [ ] Send to dead letter queue
  - [ ] Notify admin
  - [ ] All of the above
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
All of the above
```

**Event Loss:**
- What if event is lost?
  - [ ] Event sourcing (replay events)
  - [ ] Audit trail (log all events)
  - [ ] Manual recovery process
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
 Event sourcing (replay events) and audit trail
```

**Justification/Notes:**
```
We need a mechanism to replay events so that the whole process will continue and having audit trail will help us to fix broken events 
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🔴] Define event processing guarantees
- [🔴] Add idempotency keys to all events
- [🟢] Add event retry policies and dead letter queue handling
- [🟢] Add event sourcing or audit trail

---

### Gap 3.1.3: Event Ordering and Dependencies

**Context:**
- Flow shows: `BidAwardedEvent` → Contracts creates contract → Finance locks escrow
- Missing: Event ordering requirements, versioning, sequencing, saga pattern

**Question 3.1.3:** How should event ordering and dependencies be handled?

**Event Ordering:**
- Are events required to arrive in order?
  - [ ] Yes, strict ordering required
  - ] No, handlers must handle out-of-order events
  - [ ] Partial ordering (some events must be ordered)
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Yes, strict ordering required
```

**Out-of-Order Events:**
- What if `EscrowLockedEvent` arrives before `ContractCreatedEvent`?
  ```
  every event should follow their order violation fo this would be considered as break of the whole flow. 
  ```

**Saga Pattern:**
- Should multi-step transactions use saga pattern?
  - [ ] Yes, for Award → Escrow → Contract flow
  - [ ] No, event handlers are sufficient
  - [ ] Yes, for all multi-step transactions
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Yes we need to follow Saga patter and FYI the flow is Award -> Contract creation-> Escrow -> vehicle assignment -> delivery (Handover) -> contract activation
```

**Event Versioning:**
- Should events have version numbers?
  - [ ] Yes, all events
  - [ ] Yes, only breaking changes
  - [ ] No
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
yes all 
```

**Justification/Notes:**
```
We need event versioning as the previous event might have an issue and we might do a retry by versioning it and updating its content
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ 🔴 Define event ordering requirements
- [ 🔴] Add event versioning and sequencing
- [🔴 ] Add saga pattern for multi-step transactions

---

## 7. INTEGRATION PATTERNS

### Issue 3.2.1: Module-to-Module Communication - Mixed Patterns

**Context:**
- Document shows both async events and sync service interfaces
- Missing: Clear decision matrix for when to use which pattern

**Question 3.2.1:** When should each communication pattern be used?

**Decision Matrix:**
-we use async operation everywhere  except validation checkers
  ```

**Your Decision:** 
```
 We use async operation everywhere
```

**Examples:**
- Trust score calculation: [ ] Events [ ] Service Interface
- Settlement data retrieval: [ ] Events [ ] Service Interface
- Contract creation: [ ] Events [ ] Service Interface
- Vehicle availability check: [ ] Events [ ] Service Interface

**Justification/Notes:**
```
we need sync operation for validation check but we don't need for events and CRUD operation we need async operation
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Document decision matrix for choosing pattern
- [ ] Add to architecture overview
- [ ] Update module specifications

---

### Issue 3.2.2: External Service Integration - Missing Patterns

**Context:**
- Documents mention payment gateways, SMS, Email services
- Missing: Retry policies, circuit breakers, fallbacks, rate limiting

**Question 3.2.2:** How should external service integrations handle failures?

**Retry Policies:**
- Should external service calls have retry policies?
  - [ ] Yes, all services
  - [ ] Yes, only critical services (payment)
  - [ ] No
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
No
```

**Circuit Breaker:**
- Should circuit breakers be implemented?
  - [ ] Yes, for all external services
  - [ ] Yes, only for payment gateways
  - [ ] No
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
No
```

**Fallback Mechanisms:**
- What if SMS fails?
  - [ ] Email backup
  - [ ] In-app notification
  - [ ] Retry only
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Retry only
```

**Rate Limiting:**
- Should rate limiting be implemented?
  ```
 No
  ```

**Justification/Notes:**
```
 Its out of MVP Scope 
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Add external service integration patterns document
- [ ] Define retry policies, circuit breakers, fallbacks, rate limiting
- [ ] Add to infrastructure architecture

---

## 8. COMPLIANCE & OPERATIONAL EXCELLENCE

### Gap 4.1.1: KYC/KYB Compliance - Missing Enforcement Mechanisms

**Context:**
- Documents state: "Mandatory verification before platform access"
- Missing: API-level enforcement, violation logging, grace period, audit process

**Question 4.1.1:** How should KYC/KYB compliance be enforced?

**API-Level Enforcement:**
- How should this be enforced at API level?
  - [ ] Authorization policies (middleware)
  - [ ] Service-level checks
  - [ ] Both
  - [ ] Other: Its a manual verification for MVP

**Your Decision:** 
```
Its a manual verification for MVP
```

**Grace Period:**
- Can users browse before verification?
  - [ ] Yes, browsing allowed
  - [ ] No, verification required for all access
  - [ ] Yes, but limited features only
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Yes, but limited features only
```

**Violation Logging:**
- How should compliance violations be logged?
  ```
  Its out of MVP Scope
  ```

**Audit Process:**
- How often should compliance audits be performed?
  ```
  Auditing will be, who verified a specific business and when 
  ```

**Justification/Notes:**
```
Its too early to complex this as we have 
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Define API-level enforcement (authorization policies)
- [ ] Add compliance violation logging and alerting
- [ ] Add regular compliance audit process

---

### Gap 4.1.2: Insurance Compliance - Missing Automated Enforcement

**Context:**
- Documents state: "Zero tolerance: No vehicle without valid insurance"
- Missing: Enforcement at assignment, expiry monitoring, auto-suspension, notification timeline

**Question 4.1.2:** How should insurance compliance be enforced and monitored?

**Enforcement at Vehicle Assignment:**
- How is this enforced when provider tries to assign vehicle to contract?
  ```
  we will check the vehcile insurance expiry and block that vehicle from being listed for assignment
  ```

**Insurance Expiry During Contract:**
- What if insurance expires during contract?
  - [ ] Auto-suspend contract
  - [ ] Notify provider and business
  - [ ] Allow contract to continue
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Notify provider and business
```

**Expiry Monitoring:**
- How is insurance expiry monitored?
  - [ ] Scheduled job (daily check)
  - [ ] Event-driven (on contract creation)
  - [ ] Both
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Both
```

**Notification Timeline:**
- When should notifications be sent?
  - [ ] 30 days before expiry
  - [ ] 7 days before expiry
  - [ ] On expiry
  - [ ] All of the above
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
All
```

**Justification/Notes:**
```
Notification needs to be sent for both business and provider. for provider to renew it. for busienss to stop driving un insured vehicles
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🟡] Define insurance validation at vehicle assignment time
- [🟢] Add scheduled job to check insurance expiry daily
- [ 🟡] Add notification workflow

---

### Gap 4.1.3: Financial Compliance - Missing Audit Trail Requirements

**Context:**
- Documents mention: "Double-entry ledger", "Audit trails"
- Missing: What events to audit, retention policy, access control, tamper protection

**Question 4.1.3:** What are the financial audit requirements?

**Events to Audit:**
- What financial events must be audited?
  - [ ] All financial events
  - [ ] Only events above threshold (e.g., ETB 10,000)
  - [ ] Only critical events (payments, settlements, escrow)
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
All
```

**Retention Policy:**
- How long are audit logs retained?
  - [ ] 1 year
  - [ ] 3 years
  - [ ] 7 years (regulatory requirement)
  - [ ] Indefinitely
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
7 years
```

**Access Control:**
- Who can access audit logs?
  - [ ] Compliance officers only
  - ] Admin users
  - [ ] Finance team
  - [ ] All of the above
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
All
```

**Tamper Protection:**
- How are audit logs protected from tampering?
  - [ ] Append-only database
  - [ ] Blockchain
  - [ ] Encrypted logs
  - [ ] All of the above
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Append only database
```

**Justification/Notes:**
```
we implement this for MVP level
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ 🔴] Define financial audit requirements
- [🟡] Add immutable audit log
- [ 🟢] Add audit log retention policy
- [ 🔴] Add access control for audit logs

---



## 9. OPERATIONAL EXCELLENCE ( Its out of MVP Scope)

### Missing 4.2.1: Incident Response Process

**Context:**
- No specification for payment gateway downtime, database unavailability, Keycloak downtime, on-call, escalation

**Question 4.2.1:** Define the incident response process.

**On-Call Rotation:**
- Who is on-call?
  ```
  [Your response here]
  ```

**Escalation Path:**
- What is the escalation path?
  ```
  [Your response here]
  ```

**Common Incidents - Runbooks:**
- Payment gateway down:
  ```
  [Your response here]
  ```

- Database unavailable:
  ```
  [Your response here]
  ```

- Keycloak down:
  ```
  [Your response here]
  ```

**Justification/Notes:**
```
[Your notes here]
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Create Incident Response Plan document
- [ ] Define on-call rotation and escalation paths
- [ ] Create runbooks for common incidents

---

### Missing 4.2.2: Data Backup and Recovery Process

**Context:**
- Documents mention: "Automated backups (daily)" but missing retention, RTO, RPO, testing schedule

**Question 4.2.2:** Define the backup and recovery strategy.

**Backup Retention Policy:**
- How long are backups retained?
  - [ ] 30 days
  - [ ] 60 days
  - [ ] 90 days
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
[Your response here]
```

**RTO (Recovery Time Objective):**
- How long to restore?
  - [ ] 1 hour
  - [ ] 4 hours
  - [ ] 24 hours
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
[Your response here]
```

**RPO (Recovery Point Objective):**
- How much data can be lost?
  - [ ] 0 (no data loss)
  - [ ] 1 hour
  - [ ] 24 hours
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
[Your response here]
```

**Backup Testing Schedule:**
- How often are backups tested?
  - [ ] Weekly
  - [ ] Monthly
  - [ ] Quarterly
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
[Your response here]
```

**Justification/Notes:**
```
[Your notes here]
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Define backup and recovery strategy
- [ ] Specify RTO, RPO, retention, testing
- [ ] Add to deployment guide

---

### Missing 4.2.3: Performance Monitoring and Alerting

**Context:**
- Documents mention: "Monitoring (Sentry)" but missing metrics, thresholds, dashboards, alert routing

**Question 4.2.3:** Define the monitoring and alerting strategy.

**Key Metrics to Monitor:**
- [ ] API response time
- [ ] Error rate
- [ ] Database query performance
- [ ] External service latency
- [ ] Business metrics (RFQ creation, bids, contracts)
- [ ] Other: _________________________________________________

**Your Decision:** 
```
[Your response here]
```

**Alert Thresholds:**
- When to page on-call?
  ```
  [Your response here - e.g., "API response time > 2s", "Error rate > 5%"]
  ```

**Dashboards Needed:**
- [ ] Technical metrics dashboard
- [ ] Business metrics dashboard
- [ ] Error tracking dashboard
- [ ] All of the above
- [ ] Other: _________________________________________________

**Your Decision:** 
```
[Your response here]
```

**Alert Routing:**
- How are alerts routed?
  - [ ] Email
  - [ ] SMS
  - [ ] PagerDuty
  - [ ] Slack
  - [ ] All of the above
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
[Your response here]
```

**Justification/Notes:**
```
[Your notes here]
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Define monitoring and alerting strategy
- [ ] Specify key metrics, alert thresholds, dashboards, alert routing
- [ ] Add to operations documentation

---

## 10. BUSINESS PROCESS DRAWBACKS & RISKS

### Drawback 5.1.1: Manual Verification Bottleneck

**Context:**
- All KYC/KYB and insurance verification is manual
- Impact: Scalability limitation, slow onboarding, high operational cost

**Question 5.1.1:** Is manual verification acceptable for MVP, and what is the POST-MVP plan?

**MVP Acceptance:**
- [ ] Yes, acceptable for MVP
- [ ] No, must automate for MVP
- [ ] Partial automation (some checks automated)
- [ ] Other: _________________________________________________

**Your Decision:** 
```
 Acceptable for MVP
```

**POST-MVP Automation Plan:**
- What is the plan for POST-MVP?
  ```
 Partial Automation
  ```

**Justification/Notes:**
```
We ned to launch fast and automation will be complex scope for mvp
```

**Priority:** 🔴 🟡 🟢

---

### Drawback 5.1.2: No Real-Time Vehicle Availability 

**Context:**
- Vehicle availability checked at bid time, not real-time
- Impact: Potential fulfillment failures, poor user experience

**Question 5.1.2:** How should vehicle availability be handled?

**Current Approach:**
- [ ] Acceptable with re-validation at award time
- [ ] Must implement real-time availability for MVP
- [ ] Implement real-time availability for POST-MVP
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Check previous responses of mine in the above wuestions
Aailablity check will be done on bid time and award time and on vehicle assignment time for a contract
```

**Provider Rejection Handling:**
- Allow provider to reject award if vehicle unavailable?
  - [ ] Yes, with penalty
  - [ ] Yes, without penalty
  - [ ] No, provider is committed
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Yes Without penality
```

**Justification/Notes:**
```
The vehicle might br broken, or in maintaiance
```

**Priority:** 🔴 🟡 🟢

---

### Drawback 5.1.3: Settlement Frequency Creates Cash Flow Issues

**Context:**
- Bronze/Silver providers get monthly settlements
- Impact: Cash flow issues for small providers, competitive disadvantage

**Question 5.1.3:** What is the settlement frequency strategy?

**MVP Settlement Frequency:**
- [ ] Keep monthly for Bronze/Silver (as designed)
- [ ] Change to weekly for all tiers
- [ ] Change to bi-weekly for all tiers
- [ ] Other: _________________________________________________

**Your Decision:** 
```
We don't need to worry about settlement issue as we pay the escrow locked fund
```

**POST-MVP Plan:**
- [ ] Implement instant payouts (Epic 17)
- [ ] Keep current frequency
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Keep current frequency
```

**Justification/Notes:**
```
[Your notes here]
```

**Priority:** 🔴 🟡 🟢

---

### Drawback 5.1.4: No Dispute Resolution Workflow

**Context:**
- Documents mention disputes but no clear resolution process
- Impact: Unclear handling, potential conflicts, legal risk

**Question 5.1.4:** Define the dispute resolution workflow.

**Dispute Categories:**
- What are the dispute categories?
  ```
MVP Dispute Categories (ALL must be handled):
1. Vehicle condition mismatch
2. Delivery no-show (provider claims arrived, business claims no-show)
3. Early return disagreement  
4. Settlement amount disagreement
5. Insurance expiry during contract
  ```

**Evidence Requirements:**
- What evidence is required for disputes?
  ```
- Photo of the vehicles
- GPS location data
- OTP verification records
- Contract documents
- Communication logs
  ```

**Resolution Timeline:**
- How long should resolution take?
  - [ ] 24 hours
  - [ ] 48 hours
  - [ ] 72 hours
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
48 hrs
```

**Escalation Path:**
- What is the escalation path?
  ```
  [skip this 
  ```

**Justification/Notes:**
```
[Your notes here]
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Define dispute resolution workflow
- [ ] Specify dispute categories, evidence requirements, resolution timeline, escalation path

---

### Risk 5.2.1: Partial Award Complexity

**Context:**
- Partial awards based on wallet balance create complexity
- Impact: Unclear business process for remaining vehicles

**Question 5.2.1:** How should partial awards be handled?

**Partial Award Handling:**
- If business can only afford 2 of 10 vehicles:
  - [ ] Business deposits more funds and awards remaining
  - [ ] Create new RFQ for remaining vehicles
  - [ ] Cancel remaining vehicles
  - [ ] Extend deadline and allow more bids
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
check above 
```

**Justification/Notes:**
```
[Your notes here]
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Define partial award handling process
- [ ] Document in business rules

---

### Risk 5.2.2: Provider Rejection After Award

**Context:**
- Documents state "No acceptance required" - provider is committed if they bid
- Impact: What if provider genuinely cannot fulfill?

**Question 5.2.2:** How should provider rejections be handled?

**Legitimate Rejection Scenarios:**
- What are legitimate rejection scenarios (force majeure)?
  ```
  Vehicle broken, vehcile in maintainance , insurance expired
  ```

**Appeal Process:**
- Should there be an appeal process for provider rejections?
  - [ ] Yes, with review process
  - [ ] No, rejection is final
  - [ ] Yes, but only for first-time rejections
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Yes, but only for first-time rejections
```

**Penalty System:**
- Should there be a tiered penalty system?
  - [ ] Yes, harsh for repeated rejections, lenient for first-time with valid reason
  - [ ] No, same penalty for all rejections
  - [ ] No penalty for legitimate rejections
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
No penalty for legitimate rejections
```

**Justification/Notes:**
```
there will not be a penality if the car is broken
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Define legitimate rejection scenarios
- [ ] Add appeal process for provider rejections
- [ ] Add tiered penalty system

---

### Risk 5.2.3: Early Return Penalty Fairness

**Context:**
- Early return penalty is tier-based (15-25% of remaining amount)
- Impact: Might be too harsh, potential disputes, could discourage usage

**Question 5.2.3:** Are early return penalties fair, and should there be waiver processes?

**Penalty Rates Review:**
- Are current penalty rates (15-25%) acceptable?
  - [x] Other: Configurable penalty system (fixed amount or percentage)

**Your Decision:** 
```
Early return penalties should be CONFIGURABLE (either fixed amount or percentage).
Notice period penalties are also configurable with tiered structure:
- 7 days notice: 0% penalty
- 3 days notice: 2% penalty  
- Same day: 15% penalty
```

**Waiver Process:**
- Should there be a waiver process for legitimate reasons?
  - [ ] Yes, for business closure, force majeure
  - [ ] No, no waivers
  - [ ] Yes, but only for Enterprise/GOV_NGO tiers
  - [x] Other: Out of MVP scope

**Your Decision:** 
```
No waiver process for MVP. Penalties apply based on configuration.
```

**Penalty Negotiation:**
- Should Enterprise/GOV_NGO tiers be able to negotiate penalties?
  - [ ] Yes
  - [x] No - Out of MVP scope
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
No penalty negotiation for MVP. All tiers follow configured penalty structure.
```

**Justification/Notes:**
```
Configurable penalty system provides flexibility without complex negotiation workflows for MVP.
System administrators can adjust penalty rates based on market feedback.
```

**Priority:** 🔴 HIGH

**Action Required:**
- [ ] Review penalty rates with business stakeholders
- [ ] Add waiver process for legitimate reasons
- [ ] Add penalty negotiation process for Enterprise/GOV_NGO tiers

---

## 11. MODULE INTERACTION ISSUES

### Issue 6.1.1: Circular Dependency Risk

**Context:**
- Identity ↔ Contracts ↔ Finance potential circular dependency
- Impact: Tight coupling, difficult to maintain

**Question 6.1.1:** How should module dependencies be structured to avoid circular dependencies?

**Dependency Rules:**
- [x] Enforce one-way dependencies for writes (via events)
- [x] Allow read-only cross-module database queries
- [x] State changes via events (create/update/delete)
- [x] Data fetching via direct database reads

**Your Decision:** 
```
Hybrid Pattern:
- READ operations: Direct database queries allowed (Finance/Contract can query Identity & MasterData tables)
- WRITE operations: Event-driven only (no direct writes to other module databases)
- State changes: Publish events for all CUD operations (Contract, Marketplace, Delivery, Finance, Identity)
- MasterData: No events (static configuration data, read-only access)
```

**Dependency Graph:**
- Draw or describe the dependency graph:
  ```
READ Dependencies (Direct DB Queries):
  MasterData ← Finance, Contract, Marketplace, Delivery, Identity (all read)
  Identity ← Finance, Contract, Marketplace, Delivery (read business/provider data)

WRITE Dependencies (Event-Driven):
  Marketplace → BidAwardedEvent → Contract, Finance
  Contract → ContractCreatedEvent → Finance, Delivery, Identity
  Finance → EscrowLockedEvent → Contract, Identity
  Delivery → DeliveryConfirmedEvent → Contract, Identity
  Contract → ContractCompletedEvent → Finance, Identity
  
No circular write dependencies. Reads are cross-module but read-only.
  ```

**Justification/Notes:**
```
[Your notes here]
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Document dependency graph clearly
- [ ] Enforce one-way dependencies only
- [ ] Update module specifications

---

### Issue 6.1.2: Shared Data Access Patterns

**Context:**
- Multiple modules need to read from Identity (Business, Provider data)
- Missing: Clear pattern for shared data access

**Question 6.1.2:** How should modules access shared data?

**Shared Data Access Pattern:**
- [x] Read-only cross-schema queries (same database, different schemas) - MVP
- [ ] Extract to shared service or API - POST-MVP
- [ ] Service interfaces (synchronous calls)
- [x] Events (asynchronous) - for state changes only
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Direct database reads for synchronous data fetching (validation, lookups).
Events for asynchronous state changes (create/update/delete operations).

Example:
- Finance needs business name → Direct query to Identity.businesses table
- Contract completed → Publish ContractCompletedEvent → Finance subscribes → Process settlement
```

**Justification/Notes:**
```
[Your notes here]
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [ ] Define shared data access pattern
- [ ] Document in architecture overview

---

### Issue 6.1.3: Master Data Module - Unclear Integration

**Context:**
- Master Data module provides lookup types, commission strategies, contract policies
- Missing: How other modules access this data

**Question 6.1.3:** How should other modules access Master Data?

**Master Data Access Pattern:**
- [ ] Direct queries to Master Data database
- [ ] Service interface (synchronous calls)
- [ ] Redis cache for frequently accessed data
- [ ] Events (asynchronous updates)
- [ ] Other: _________________________________________________

**Your Decision:** 
```
Direct queries to Master Data database
Redis cache for frequently accessed data
```

**Cache Strategy:**
- Should Master Data be cached?
  - [x] Yes, in Redis
  - [ ] No, direct queries only
  - [x] Yes, for frequently accessed data
  - [ ] Other: _________________________________________________

**Your Decision:** 
```
Cache ALL MasterData in Redis for performance:
- Commission rates
- Vehicle types  
- Contract policies
- Lookups and lookup types
```

**Cache Invalidation:**
- How should cache be invalidated?
  ```
Cache invalidation on update:
1. Admin updates MasterData via API
2. API updates database
3. API invalidates specific cache keys
4. Next read fetches fresh data and updates cache

Cache TTL: Consider long TTL (24 hours) since MasterData changes infrequently.
  ```

**Justification/Notes:**
```
if there is a change on master data that changes should be reflected other wise the system will operate by old data
```

**Priority:** 🔴 🟡 🟢

**Action Required:**
- [🟡] Define master data access pattern
- [🟡] Specify cache strategy and invalidation
- [🟡] Update module specifications

---

## SUMMARY SECTION

### Overall Priority Assessment

**Critical Issues (Must Fix Before MVP Launch):**
```
[List issue numbers that are critical]
```

**High Priority Issues (Should Fix Before MVP Launch):**
```
[List issue numbers that are high priority]
```

**Medium Priority Issues (Can Fix Post-MVP):**
```
[List issue numbers that are medium priority]
```

**Low Priority Issues (Nice to Have):**
```
[List issue numbers that are low priority]
```

---

### Next Steps

**Immediate Actions:**
```
[Your response here]
```

**Documentation Updates Required:**
```
[Your response here]
```

**Implementation Changes Required:**
```
[Your response here]
```

---

**Questionnaire Completed By:** _________________________  
**Date:** _________________________  
**Review Date:** _________________________

---

**END OF QUESTIONNAIRE**





