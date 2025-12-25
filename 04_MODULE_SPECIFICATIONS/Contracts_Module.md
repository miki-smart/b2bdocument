# Contracts Module - Specification

**Module Name:** Contracts  
**Version:** 1.1 MVP  
**Date:** December 22, 2025 (Updated)  
**Database Schema:** `contracts`  
**Related Documents:** 
- MVP_AUTHORITATIVE_BUSINESS_RULES.md (Section 5, 6, 7)
- MVP_CONTRACT_STATE_MACHINE.md (Complete state definitions)

---

## 📋 Overview

### Purpose
The Contracts Module manages the **legal and operational lifecycle** of agreements between businesses and providers. It serves as the binding record for vehicle usage, enforcing terms, tracking fulfillment, and managing amendments or terminations.

### Responsibilities

✅ **Contract Lifecycle Management**
- Creation from RFQ awards
- Activation via delivery
- Completion or termination
- State machine enforcement

✅ **Vehicle Assignment**
- Linking specific vehicles to contract lines
- Tracking vehicle status within a contract
- Managing replacements

✅ **Policy Enforcement**
- Applying snapshot policies (penalties, commission)
- Calculating proration for early returns
- Enforcing SLA terms

✅ **Amendment Management**
- Handling extension requests
- Processing early returns
- Managing cancellations

---

## 🗄️ Database Schema

### Tables (9 Total)

1. `contract` - Master contract record
2. `contract_party_business` - Immutable business snapshot
3. `contract_party_provider` - Immutable provider snapshot
4. `contract_line_item` - Service/Vehicle details
5. `contract_vehicle_assignment` - Specific vehicle tracking
6. `contract_policy_snapshot` - JSON snapshot of rules
7. `contract_amendment` - Change requests
8. `contract_penalty` - Applied penalties
9. `contract_event_log` - Audit trail

---

## 🏗️ Module Structure

```
Contracts/
├── Domain/
│   ├── Entities/
│   │   ├── Contract.cs
│   │   ├── ContractLineItem.cs
│   │   ├── ContractVehicleAssignment.cs
│   │   ├── ContractPartyBusiness.cs
│   │   ├── ContractPartyProvider.cs
│   │   ├── ContractPolicySnapshot.cs
│   │   ├── ContractAmendment.cs
│   │   └── ContractPenalty.cs
│   │
│   ├── Events/
│   │   ├── ContractCreatedEvent.cs
│   │   ├── ContractActivatedEvent.cs
│   │   ├── ContractCompletedEvent.cs
│   │   ├── ContractTerminatedEvent.cs
│   │   ├── VehicleAssignedEvent.cs
│   │   └── VehicleReturnedEarlyEvent.cs
│   │
│   ├── Enums/
│   │   ├── ContractStatus.cs (PENDING_ESCROW, PENDING_VEHICLE_ASSIGNMENT, 
│   │   │                       PENDING_DELIVERY, ACTIVE, ON_HOLD, 
│   │   │                       TIMEOUT_PENDING, COMPLETED, TERMINATED, FAILED)
│   │   ├── ContractLineStatus.cs
│   │   ├── AssignmentStatus.cs
│   │   └── AmendmentType.cs
│   │
│   └── Services/
│       ├── IPenaltyCalculator.cs
│       ├── PenaltyCalculator.cs
│       ├── IContractStateManager.cs
│       ├── ContractStateManager.cs
│       ├── IContractTimeoutService.cs
│       └── ContractTimeoutService.cs
│
├── Application/
│   ├── Commands/
│   │   ├── CreateContractCommand.cs (Internal)
│   │   ├── AssignVehicleCommand.cs
│   │   ├── ReassignVehicleCommand.cs
│   │   ├── ActivateContractCommand.cs (Internal)
│   │   ├── CheckContractTimeoutsCommand.cs
│   │   ├── ProcessEarlyReturnCommand.cs
│   │   └── TerminateContractCommand.cs
│   │
│   ├── Queries/
│   │   ├── GetContractByIdQuery.cs
│   │   ├── GetBusinessContractsQuery.cs
│   │   ├── GetProviderContractsQuery.cs
│   │   └── GetActiveAssignmentsQuery.cs
│   │
│   ├── DTOs/
│   │   ├── ContractDto.cs
│   │   ├── ContractLineItemDto.cs
│   │   ├── VehicleAssignmentDto.cs
│   │   └── PenaltyDto.cs
│   │
│   └── Validators/
│       ├── AssignVehicleValidator.cs
│       └── ProcessEarlyReturnValidator.cs
│
├── Infrastructure/
│   ├── Repositories/
│   │   ├── IContractRepository.cs
│   │   ├── ContractRepository.cs
│   │   ├── IAssignmentRepository.cs
│   │   └── AssignmentRepository.cs
│   │
│   └── Services/
│       └── ContractNumberGenerator.cs
│
└── API/
    └── Controllers/
        ├── ContractsController.cs
        └── AssignmentsController.cs
```

---

## 🔄 Key Workflows

### 1. Contract Creation (Auto-triggered)

```csharp
// Event Handler consuming BidAwardedEvent
public class BidAwardedEventHandler : INotificationHandler<BidAwardedEvent>
{
    private readonly IContractRepository _contractRepository;
    private readonly IIdentityService _identityService; // Internal service to get snapshots
    private readonly IMasterDataService _masterDataService; // Internal service to get policies
    private readonly IMediator _mediator;

    public async Task Handle(BidAwardedEvent notification, CancellationToken cancellationToken)
    {
        // 1. Check if contract exists for this RFQ/Business pair (or create new)
        // For MVP, 1 Award = 1 Contract usually, or 1 RFQ = Multiple Contracts (per provider)
        
        // 2. Get Snapshots
        var business = await _identityService.GetBusinessSnapshotAsync(notification.BusinessId);
        var provider = await _identityService.GetProviderSnapshotAsync(notification.ProviderId);
        var policy = await _masterDataService.GetActiveContractPolicyAsync();
        
        // 3. Create Contract Header
        var contract = new Contract
        {
            Id = Guid.NewGuid(),
            ContractNumber = ContractNumberGenerator.Generate(),
            RFQId = notification.RFQId,
            BusinessId = notification.BusinessId,
            ProviderId = notification.ProviderId,
            Status = ContractStatus.PENDING_ESCROW,  // BR-016: Waiting for escrow lock
            TotalAmount = notification.TotalAmount,
            EscrowAmount = notification.EscrowAmount,  // From BidAwardedEvent
            CreatedAt = DateTime.UtcNow,
            ActivationTimeoutAt = DateTime.UtcNow.AddDays(5)  // BR-017: 5-day timeout
        };
        
        // 4. Create Party Snapshots
        var businessParty = new ContractPartyBusiness
        {
            ContractId = contract.Id,
            BusinessName = business.Name,
            TierCode = business.TierCode,
            ContactInfo = business.ContactInfo
        };
        
        var providerParty = new ContractPartyProvider
        {
            ContractId = contract.Id,
            ProviderName = provider.Name,
            TierCode = provider.TierCode,
            TrustScore = provider.TrustScore
        };
        
        // 5. Create Line Item
        var lineItem = new ContractLineItem
        {
            Id = Guid.NewGuid(),
            ContractId = contract.Id,
            RFQLineItemId = notification.LineItemId,
            QuantityAwarded = notification.QuantityAwarded,
            QuantityActive = 0,
            UnitAmount = notification.UnitPrice,
            TotalAmount = notification.TotalAmount,
            CommissionRate = provider.CommissionRate, 
            Status = ContractLineStatus.PendingActivation
        };
        
        // 6. Create Policy Snapshot
        var policySnapshot = new ContractPolicySnapshot
        {
            ContractId = contract.Id,
            PolicyVersionId = policy.VersionId,
            RulesJson = JsonSerializer.Serialize(policy.Rules)
        };
        
        // 7. Save Transactionally
        await _contractRepository.CreateContractAsync(contract, businessParty, providerParty, lineItem, policySnapshot);
        
        // 8. Publish Event
        await _mediator.Publish(new ContractCreatedEvent
        {
            ContractId = contract.Id,
            BusinessId = contract.BusinessId,
            ProviderId = contract.ProviderId,
            TotalAmount = contract.TotalAmount,
            EscrowAmount = contract.EscrowAmount
        });
    }
}
```

---

### 2. Contract State Machine & Activation (BR-016, BR-017)

#### Contract State Definitions

```csharp
public enum ContractStatus
{
    PENDING_ESCROW,                // Waiting for escrow lock
    PENDING_VEHICLE_ASSIGNMENT,    // Escrow locked, waiting for vehicle assignment
    PENDING_DELIVERY,              // Vehicle assigned, waiting for delivery confirmation
    ACTIVE,                        // Contract is active (escrow locked + delivery confirmed)
    ON_HOLD,                       // Contract suspended (e.g., payment default)
    TIMEOUT_PENDING,               // Activation timeout reached (5 days)
    COMPLETED,                     // Contract successfully completed
    TERMINATED,                    // Contract cancelled/terminated early
    FAILED                         // Contract failed during setup
}
```

#### Dual-Condition Activation Logic (BR-016)

```csharp
// Contract becomes ACTIVE only when BOTH conditions are met:
// 1. Escrow locked (EscrowLockedEvent received)
// 2. Delivery confirmed (DeliveryConfirmedEvent received)

public class ContractStateManager : IContractStateManager
{
    private readonly IContractRepository _contractRepository;
    private readonly IMediator _mediator;
    
    public async Task TryActivateContractAsync(Guid contractId)
    {
        var contract = await _contractRepository.GetByIdAsync(contractId);
        
        // Check BOTH conditions
        bool escrowLocked = contract.EscrowLockedAt.HasValue;
        bool deliveryConfirmed = contract.FirstDeliveryConfirmedAt.HasValue;
        
        if (escrowLocked && deliveryConfirmed && contract.Status != ContractStatus.ACTIVE)
        {
            // BOTH conditions met - activate contract
            contract.Status = ContractStatus.ACTIVE;
            contract.ActivatedAt = DateTime.UtcNow;
            
            await _contractRepository.UpdateAsync(contract);
            
            await _mediator.Publish(new ContractActivatedEvent
            {
                ContractId = contract.Id,
                BusinessId = contract.BusinessId,
                ProviderId = contract.ProviderId,
                ActivatedAt = contract.ActivatedAt.Value
            });
        }
    }
}

// Event Handler: EscrowLockedEvent
public class EscrowLockedEventHandler : INotificationHandler<EscrowLockedEvent>
{
    private readonly IContractRepository _contractRepository;
    private readonly IContractStateManager _stateManager;
    
    public async Task Handle(EscrowLockedEvent notification, CancellationToken cancellationToken)
    {
        var contract = await _contractRepository.GetByIdAsync(notification.ContractId);
        
        // Update contract: escrow is locked
        contract.EscrowLockedAt = DateTime.UtcNow;
        
        // Transition: PENDING_ESCROW → PENDING_VEHICLE_ASSIGNMENT
        if (contract.Status == ContractStatus.PENDING_ESCROW)
        {
            contract.Status = ContractStatus.PENDING_VEHICLE_ASSIGNMENT;
        }
        
        await _contractRepository.UpdateAsync(contract);
        
        // Try to activate if delivery also confirmed
        await _stateManager.TryActivateContractAsync(contract.Id);
    }
}

// Event Handler: DeliveryConfirmedEvent
public class DeliveryConfirmedEventHandler : INotificationHandler<DeliveryConfirmedEvent>
{
    private readonly IContractRepository _contractRepository;
    private readonly IContractStateManager _stateManager;
    
    public async Task Handle(DeliveryConfirmedEvent notification, CancellationToken cancellationToken)
    {
        var assignment = await _contractRepository.GetAssignmentByIdAsync(notification.AssignmentId);
        var contract = await _contractRepository.GetByIdAsync(assignment.ContractId);
        
        // Update assignment status
        assignment.Status = AssignmentStatus.ACTIVE;
        assignment.StartDateActual = notification.DeliveredAt;
        
        // Record first delivery
        if (!contract.FirstDeliveryConfirmedAt.HasValue)
        {
            contract.FirstDeliveryConfirmedAt = notification.DeliveredAt;
            
            // Transition: PENDING_DELIVERY → Check activation
            if (contract.Status == ContractStatus.PENDING_DELIVERY)
            {
                // Will transition to ACTIVE if escrow also locked
                await _stateManager.TryActivateContractAsync(contract.Id);
            }
        }
        
        // Increment active quantity
        var lineItem = contract.LineItems.First(li => li.Id == assignment.ContractLineItemId);
        lineItem.QuantityActive++;
        
        await _contractRepository.UpdateAsync(contract);
    }
}
```

#### Contract Timeout Handling (BR-017)

```csharp
// Background Job: Check for contract timeouts every hour
public class CheckContractTimeoutsCommand : IRequest<Unit>
{
}

public class CheckContractTimeoutsCommandHandler : IRequestHandler<CheckContractTimeoutsCommand, Unit>
{
    private readonly IContractRepository _contractRepository;
    private readonly IMediator _mediator;
    
    public async Task<Unit> Handle(CheckContractTimeoutsCommand request, CancellationToken cancellationToken)
    {
        // Find contracts that exceeded 5-day activation timeout
        var timedOutContracts = await _contractRepository.GetContractsAsync(c =>
            (c.Status == ContractStatus.PENDING_ESCROW ||
             c.Status == ContractStatus.PENDING_VEHICLE_ASSIGNMENT ||
             c.Status == ContractStatus.PENDING_DELIVERY) &&
            c.ActivationTimeoutAt <= DateTime.UtcNow
        );
        
        foreach (var contract in timedOutContracts)
        {
            // Transition to TIMEOUT_PENDING
            contract.Status = ContractStatus.TIMEOUT_PENDING;
            await _contractRepository.UpdateAsync(contract);
            
            // Publish event to notify business and provider
            await _mediator.Publish(new ContractTimeoutEvent
            {
                ContractId = contract.Id,
                BusinessId = contract.BusinessId,
                ProviderId = contract.ProviderId,
                CurrentStatus = contract.Status.ToString(),
                Message = "Contract activation timeout reached (5 days). Please contact support."
            });
        }
        
        return Unit.Value;
    }
}

// Hangfire/Quartz job configuration
public class ContractTimeoutJob
{
    public static void Configure(IRecurringJobManager recurringJobManager)
    {
        // Run every hour
        recurringJobManager.AddOrUpdate<IMediator>(
            "check-contract-timeouts",
            mediator => mediator.Send(new CheckContractTimeoutsCommand(), default),
            Cron.Hourly
        );
    }
}
```

---

### 3. Vehicle Assignment & Reassignment

#### Initial Vehicle Assignment

Provider assigns vehicles immediately after receiving `ContractCreatedEvent`.

```csharp
public class AssignVehicleCommand : IRequest<VehicleAssignmentDto>
{
    public Guid ContractId { get; set; }
    public Guid ContractLineItemId { get; set; }
    public Guid VehicleId { get; set; }
    public DateTime DeliveryDate { get; set; }
}

public class AssignVehicleCommandHandler : IRequestHandler<AssignVehicleCommand, VehicleAssignmentDto>
{
    public async Task<VehicleAssignmentDto> Handle(AssignVehicleCommand request, CancellationToken cancellationToken)
    {
        // 1. Validate contract exists and is in correct state
        var contract = await _contractRepository.GetByIdAsync(request.ContractId);
        if (contract.Status != ContractStatus.PENDING_VEHICLE_ASSIGNMENT &&
            contract.Status != ContractStatus.PENDING_DELIVERY &&
            contract.Status != ContractStatus.ACTIVE)
        {
            throw new InvalidOperationException($"Cannot assign vehicle. Contract status: {contract.Status}");
        }
        
        // 2. Validate vehicle belongs to provider and meets requirements
        var vehicle = await _vehicleRepository.GetByIdAsync(request.VehicleId);
        if (vehicle.ProviderId != contract.ProviderId)
            throw new UnauthorizedException("Vehicle does not belong to provider");
        
        var lineItem = contract.LineItems.First(li => li.Id == request.ContractLineItemId);
        await _vehicleValidator.ValidateForServiceType(vehicle, lineItem.ServiceTypeId);
        
        // 3. Check vehicle availability for date range
        await _vehicleAvailabilityService.EnsureAvailableAsync(
            request.VehicleId,
            request.DeliveryDate,
            contract.EndDate
        );
        
        // 4. Create assignment
        var assignment = new VehicleAssignment
        {
            Id = Guid.NewGuid(),
            ContractId = request.ContractId,
            ContractLineItemId = request.ContractLineItemId,
            VehicleId = request.VehicleId,
            Status = AssignmentStatus.PENDING_DELIVERY,
            StartDatePlanned = request.DeliveryDate,
            AssignedAt = DateTime.UtcNow
        };
        
        await _contractRepository.AddAssignmentAsync(assignment);
        
        // 5. Update contract status if first assignment
        if (contract.Status == ContractStatus.PENDING_VEHICLE_ASSIGNMENT)
        {
            contract.Status = ContractStatus.PENDING_DELIVERY;
            await _contractRepository.UpdateAsync(contract);
        }
        
        // 6. Publish event
        await _mediator.Publish(new VehicleAssignedEvent
        {
            ContractId = contract.Id,
            AssignmentId = assignment.Id,
            VehicleId = request.VehicleId,
            PlannedDeliveryDate = request.DeliveryDate
        });
        
        return _mapper.Map<VehicleAssignmentDto>(assignment);
    }
}
```

#### Vehicle Reassignment (Business-Approved)

Allows provider to replace a vehicle with business approval.

```csharp
public class ReassignVehicleCommand : IRequest<VehicleAssignmentDto>
{
    public Guid AssignmentId { get; set; }
    public Guid NewVehicleId { get; set; }
    public string Reason { get; set; }
}

public class ReassignVehicleCommandHandler : IRequestHandler<ReassignVehicleCommand, VehicleAssignmentDto>
{
    private readonly IContractRepository _contractRepository;
    private readonly IVehicleRepository _vehicleRepository;
    private readonly IVehicleValidator _vehicleValidator;
    private readonly IMediator _mediator;
    
    public async Task<VehicleAssignmentDto> Handle(ReassignVehicleCommand request, CancellationToken cancellationToken)
    {
        // 1. Get existing assignment
        var assignment = await _contractRepository.GetAssignmentByIdAsync(request.AssignmentId);
        var contract = await _contractRepository.GetByIdAsync(assignment.ContractId);
        
        // 2. Can only reassign ACTIVE or PENDING_DELIVERY assignments
        if (assignment.Status != AssignmentStatus.ACTIVE &&
            assignment.Status != AssignmentStatus.PENDING_DELIVERY)
        {
            throw new InvalidOperationException($"Cannot reassign. Assignment status: {assignment.Status}");
        }
        
        // 3. Validate new vehicle belongs to provider and meets requirements
        var newVehicle = await _vehicleRepository.GetByIdAsync(request.NewVehicleId);
        if (newVehicle.ProviderId != contract.ProviderId)
            throw new UnauthorizedException("New vehicle does not belong to provider");
        
        var lineItem = contract.LineItems.First(li => li.Id == assignment.ContractLineItemId);
        await _vehicleValidator.ValidateForServiceType(newVehicle, lineItem.ServiceTypeId);
        
        // 4. Check new vehicle availability
        await _vehicleAvailabilityService.EnsureAvailableAsync(
            request.NewVehicleId,
            assignment.StartDatePlanned,
            contract.EndDate
        );
        
        // 5. Create reassignment request (requires business approval)
        var reassignmentRequest = new VehicleReassignmentRequest
        {
            Id = Guid.NewGuid(),
            AssignmentId = assignment.Id,
            OldVehicleId = assignment.VehicleId,
            NewVehicleId = request.NewVehicleId,
            Reason = request.Reason,
            Status = ReassignmentStatus.PENDING_APPROVAL,
            RequestedAt = DateTime.UtcNow
        };
        
        await _contractRepository.AddReassignmentRequestAsync(reassignmentRequest);
        
        // 6. Notify business for approval
        await _mediator.Publish(new VehicleReassignmentRequestedEvent
        {
            ReassignmentId = reassignmentRequest.Id,
            ContractId = contract.Id,
            BusinessId = contract.BusinessId,
            OldVehicleId = assignment.VehicleId,
            NewVehicleId = request.NewVehicleId,
            Reason = request.Reason
        });
        
        return new VehicleAssignmentDto
        {
            AssignmentId = assignment.Id,
            ReassignmentRequestId = reassignmentRequest.Id,
            Status = "PENDING_BUSINESS_APPROVAL"
        };
    }
}

// Business approves reassignment
public class ApproveVehicleReassignmentCommand : IRequest<Unit>
{
    public Guid ReassignmentRequestId { get; set; }
    public Guid BusinessUserId { get; set; }
    public bool Approved { get; set; }
    public string Notes { get; set; }
}

public class ApproveVehicleReassignmentCommandHandler : IRequestHandler<ApproveVehicleReassignmentCommand, Unit>
{
    public async Task<Unit> Handle(ApproveVehicleReassignmentCommand request, CancellationToken cancellationToken)
    {
        var reassignmentRequest = await _contractRepository.GetReassignmentRequestByIdAsync(request.ReassignmentRequestId);
        var assignment = await _contractRepository.GetAssignmentByIdAsync(reassignmentRequest.AssignmentId);
        
        if (request.Approved)
        {
            // Update assignment with new vehicle
            assignment.VehicleId = reassignmentRequest.NewVehicleId;
            assignment.ReassignedAt = DateTime.UtcNow;
            
            reassignmentRequest.Status = ReassignmentStatus.APPROVED;
            reassignmentRequest.ApprovedBy = request.BusinessUserId;
            reassignmentRequest.ApprovedAt = DateTime.UtcNow;
            
            await _contractRepository.UpdateAsync(assignment);
            await _contractRepository.UpdateAsync(reassignmentRequest);
            
            await _mediator.Publish(new VehicleReassignedEvent
            {
                AssignmentId = assignment.Id,
                ContractId = assignment.ContractId,
                OldVehicleId = reassignmentRequest.OldVehicleId,
                NewVehicleId = reassignmentRequest.NewVehicleId
            });
        }
        else
        {
            reassignmentRequest.Status = ReassignmentStatus.REJECTED;
            reassignmentRequest.RejectedBy = request.BusinessUserId;
            reassignmentRequest.RejectedAt = DateTime.UtcNow;
            reassignmentRequest.RejectionNotes = request.Notes;
            
            await _contractRepository.UpdateAsync(reassignmentRequest);
        }
        
        return Unit.Value;
    }
}
```

---

### 4. Early Return / Contract Return

// Handler
public class AssignVehicleCommandHandler : IRequestHandler<AssignVehicleCommand, Guid>
{
    private readonly IContractRepository _contractRepository;
    private readonly IVehicleService _vehicleService; // Check vehicle status
    private readonly IMediator _mediator;

    public async Task<Guid> Handle(AssignVehicleCommand request, CancellationToken cancellationToken)
    {
        // 1. Validate Contract
        var contract = await _contractRepository.GetByIdAsync(request.ContractId);
        if (contract.ProviderId != request.ProviderId)
            throw new ForbiddenException("Not authorized");
            
        // 2. Validate Line Item
        var lineItem = contract.LineItems.FirstOrDefault(x => x.Id == request.LineItemId);
        if (lineItem == null) throw new NotFoundException("Line item not found");
        
        if (lineItem.Assignments.Count >= lineItem.QuantityAwarded)
            throw new BusinessException("All vehicles already assigned");

        // 3. Validate Vehicle (Call Identity Module via Interface/HTTP)
        var vehicle = await _vehicleService.GetVehicleAsync(request.VehicleId);
        if (vehicle.Status != "ACTIVE")
            throw new BusinessException("Vehicle is not active");
            
        // 4. Create Assignment
        var assignment = new ContractVehicleAssignment
        {
            Id = Guid.NewGuid(),
            ContractId = contract.Id,
            ContractLineItemId = lineItem.Id,
            VehicleId = request.VehicleId,
            PlateNumber = vehicle.PlateNumber,
            Status = AssignmentStatus.PendingDelivery,
            AssignedAt = DateTime.UtcNow
        };
        
        await _contractRepository.AddAssignmentAsync(assignment);
        
        // 5. Publish Event (Delivery Module listens to create Delivery Session)
        await _mediator.Publish(new VehicleAssignedEvent
        {
            AssignmentId = assignment.Id,
            ContractId = contract.Id,
            VehicleId = request.VehicleId,
            BusinessId = contract.BusinessId,
            ProviderId = contract.ProviderId
        });
        
        return assignment.Id;
    }
}
```

---

### 3. Early Return Processing

```csharp
// Command
public class ProcessEarlyReturnCommand : IRequest<Unit>
{
    public Guid AssignmentId { get; set; }
    public DateTime ReturnDate { get; set; }
    public string Reason { get; set; }
}

// Handler
public class ProcessEarlyReturnCommandHandler : IRequestHandler<ProcessEarlyReturnCommand, Unit>
{
    private readonly IContractRepository _contractRepository;
    private readonly IPenaltyCalculator _penaltyCalculator;
    private readonly IMediator _mediator;

    public async Task<Unit> Handle(ProcessEarlyReturnCommand request, CancellationToken cancellationToken)
    {
        // 1. Get Assignment
        var assignment = await _contractRepository.GetAssignmentByIdAsync(request.AssignmentId);
        if (assignment.Status != AssignmentStatus.Active)
            throw new BusinessException("Assignment is not active");

        // 2. Calculate Proration & Penalty
        var contract = await _contractRepository.GetByIdAsync(assignment.ContractId);
        var lineItem = contract.LineItems.First(l => l.Id == assignment.ContractLineItemId);
        
        var calculation = _penaltyCalculator.CalculateEarlyReturn(
            contract, 
            lineItem, 
            assignment.StartDateActual.Value, 
            request.ReturnDate
        );
        
        // 3. Update Assignment
        assignment.Status = AssignmentStatus.ReturnedEarly;
        assignment.EndDateActual = request.ReturnDate;
        
        // 4. Record Penalty
        if (calculation.PenaltyAmount > 0)
        {
            var penalty = new ContractPenalty
            {
                Id = Guid.NewGuid(),
                ContractId = contract.Id,
                ContractLineItemId = lineItem.Id,
                PenaltyType = "EARLY_RETURN",
                Amount = calculation.PenaltyAmount,
                Reason = request.Reason,
                AppliedAt = DateTime.UtcNow
            };
            await _contractRepository.AddPenaltyAsync(penalty);
        }
        
        // 5. Update Line Item Counts
        lineItem.QuantityActive--;
        
        await _contractRepository.UpdateAsync(contract);
        
        // 6. Publish Event (Finance Module listens to process refund/settlement)
        await _mediator.Publish(new VehicleReturnedEarlyEvent
        {
            ContractId = contract.Id,
            AssignmentId = assignment.Id,
            RefundAmount = calculation.RefundAmount,
            PenaltyAmount = calculation.PenaltyAmount,
            ProviderId = contract.ProviderId,
            BusinessId = contract.BusinessId
        });
        
        return Unit.Value;
    }
}
```

---

## 📡 Events Published

### ContractCreatedEvent
```csharp
public class ContractCreatedEvent : INotification
{
    public Guid ContractId { get; set; }
    public Guid BusinessId { get; set; }
    public Guid ProviderId { get; set; }
    public decimal TotalAmount { get; set; }
    public decimal EscrowAmount { get; set; }
}
```
**Consumed by:** Finance Module (triggers escrow lock)

### VehicleAssignedEvent
```csharp
public class VehicleAssignedEvent : INotification
{
    public Guid AssignmentId { get; set; }
    public Guid ContractId { get; set; }
    public Guid VehicleId { get; set; }
    public Guid BusinessId { get; set; }
    public Guid ProviderId { get; set; }
    public DateTime PlannedDeliveryDate { get; set; }
}
```
**Consumed by:** Delivery Module (creates delivery task)

### ContractActivatedEvent
```csharp
public class ContractActivatedEvent : INotification
{
    public Guid ContractId { get; set; }
    public Guid BusinessId { get; set; }
    public Guid ProviderId { get; set; }
    public DateTime ActivatedAt { get; set; }
}
```
**Consumed by:** Notification Module, Finance Module

### ContractTimeoutEvent
```csharp
public class ContractTimeoutEvent : INotification
{
    public Guid ContractId { get; set; }
    public Guid BusinessId { get; set; }
    public Guid ProviderId { get; set; }
    public string CurrentStatus { get; set; }
    public string Message { get; set; }
}
```
**Consumed by:** Notification Module (alerts business and provider)

### VehicleReassignmentRequestedEvent
```csharp
public class VehicleReassignmentRequestedEvent : INotification
{
    public Guid ReassignmentId { get; set; }
    public Guid ContractId { get; set; }
    public Guid BusinessId { get; set; }
    public Guid OldVehicleId { get; set; }
    public Guid NewVehicleId { get; set; }
    public string Reason { get; set; }
}
```
**Consumed by:** Notification Module (notifies business for approval)

### VehicleReassignedEvent
```csharp
public class VehicleReassignedEvent : INotification
{
    public Guid AssignmentId { get; set; }
    public Guid ContractId { get; set; }
    public Guid OldVehicleId { get; set; }
    public Guid NewVehicleId { get; set; }
}
```
**Consumed by:** Delivery Module (updates delivery tasks)

### VehicleReturnedEarlyEvent
```csharp
public class VehicleReturnedEarlyEvent : INotification
{
    public Guid ContractId { get; set; }
    public Guid AssignmentId { get; set; }
    public decimal RefundAmount { get; set; }
    public decimal PenaltyAmount { get; set; }
    public Guid ProviderId { get; set; }
    public Guid BusinessId { get; set; }
}
```
**Consumed by:** Finance Module (processes refund/settlement)

---

## 📡 Events Consumed

### BidAwardedEvent
- **Source:** Marketplace Module
- **Action:** Creates new `Contract` in `PENDING_ESCROW` state with 5-day activation timeout.

```csharp
public class BidAwardedEventHandler : INotificationHandler<BidAwardedEvent>
{
    public async Task Handle(BidAwardedEvent notification)
    {
        var contract = new Contract
        {
            Id = Guid.NewGuid(),
            Status = ContractStatus.PENDING_ESCROW,
            ActivationTimeoutAt = DateTime.UtcNow.AddDays(5),
            CreatedAt = DateTime.UtcNow
            // ... other fields
        };
        
        await _contractRepository.AddAsync(contract);
        await _mediator.Publish(new ContractCreatedEvent { ContractId = contract.Id });
    }
}
```

### EscrowLockedEvent
- **Source:** Finance Module
- **Action:** 
  - Records escrow lock timestamp
  - Transitions `PENDING_ESCROW` → `PENDING_VEHICLE_ASSIGNMENT`
  - Attempts contract activation if delivery also confirmed

```csharp
public class EscrowLockedEventHandler : INotificationHandler<EscrowLockedEvent>
{
    private readonly IContractRepository _contractRepository;
    private readonly IContractStateManager _stateManager;
    
    public async Task Handle(EscrowLockedEvent notification)
    {
        var contract = await _contractRepository.GetByIdAsync(notification.ContractId);
        
        contract.EscrowLockedAt = DateTime.UtcNow;
        
        if (contract.Status == ContractStatus.PENDING_ESCROW)
        {
            contract.Status = ContractStatus.PENDING_VEHICLE_ASSIGNMENT;
        }
        
        await _contractRepository.UpdateAsync(contract);
        
        // Try to activate if delivery also confirmed
        await _stateManager.TryActivateContractAsync(contract.Id);
    }
}
```

### DeliveryConfirmedEvent
- **Source:** Delivery Module
- **Action:** 
  - Updates `ContractVehicleAssignment` status to `Active`.
  - Sets `StartDateActual`.
  - Records first delivery timestamp if applicable
  - Increments `QuantityActive` on line item.
  - Attempts contract activation if escrow also locked

```csharp
public class DeliveryConfirmedEventHandler : INotificationHandler<DeliveryConfirmedEvent>
{
    private readonly IContractRepository _contractRepository;
    private readonly IContractStateManager _stateManager;
    
    public async Task Handle(DeliveryConfirmedEvent notification)
    {
        var assignment = await _contractRepository.GetAssignmentByIdAsync(notification.AssignmentId);
        var contract = await _contractRepository.GetByIdAsync(assignment.ContractId);
        
        // Update assignment
        assignment.Status = AssignmentStatus.ACTIVE;
        assignment.StartDateActual = notification.DeliveredAt;
        
        // Record first delivery
        if (!contract.FirstDeliveryConfirmedAt.HasValue)
        {
            contract.FirstDeliveryConfirmedAt = notification.DeliveredAt;
        }
        
        // Increment active quantity
        var lineItem = contract.LineItems.First(li => li.Id == assignment.ContractLineItemId);
        lineItem.QuantityActive++;
        
        await _contractRepository.UpdateAsync(contract);
        
        // Try to activate if escrow also locked
        await _stateManager.TryActivateContractAsync(contract.Id);
    }
}
```

### DeliveryReturnConfirmedEvent
- **Source:** Delivery Module
- **Action:**
  - Updates `ContractVehicleAssignment` status to `Returned`.
  - Sets `EndDateActual`.
  - Decrements `QuantityActive`.
  - If all returned, sets `Contract` status to `COMPLETED`.

```csharp
public class DeliveryReturnConfirmedEventHandler : INotificationHandler<DeliveryReturnConfirmedEvent>
{
    public async Task Handle(DeliveryReturnConfirmedEvent notification)
    {
        var assignment = await _contractRepository.GetAssignmentByIdAsync(notification.AssignmentId);
        var contract = await _contractRepository.GetByIdAsync(assignment.ContractId);
        
        // Update assignment
        assignment.Status = AssignmentStatus.RETURNED;
        assignment.EndDateActual = notification.ReturnedAt;
        
        // Decrement active quantity
        var lineItem = contract.LineItems.First(li => li.Id == assignment.ContractLineItemId);
        lineItem.QuantityActive--;
        
        // Check if all vehicles returned
        if (contract.LineItems.All(li => li.QuantityActive == 0))
        {
            contract.Status = ContractStatus.COMPLETED;
            contract.CompletedAt = DateTime.UtcNow;
        }
        
        await _contractRepository.UpdateAsync(contract);
    }
}
```

---

## ✅ Business Rules

### Contract State Machine (BR-016, BR-017)

**State Progression:**
```
BidAwardedEvent → PENDING_ESCROW 
                → EscrowLockedEvent → PENDING_VEHICLE_ASSIGNMENT
                → VehicleAssignedEvent → PENDING_DELIVERY
                → DeliveryConfirmedEvent + EscrowLockedEvent → ACTIVE
```

1. **Initial State:** Contract created in `PENDING_ESCROW` status
2. **Activation Prerequisites (BR-016):** Contract becomes `ACTIVE` **only when BOTH** conditions are met:
   - ✅ Escrow locked (`EscrowLockedAt` is set)
   - ✅ First delivery confirmed (`FirstDeliveryConfirmedAt` is set)
3. **Activation Timeout (BR-017):** Contract must activate within **5 days** of creation
   - `ActivationTimeoutAt` = `CreatedAt` + 5 days
   - If timeout reached without activation → `TIMEOUT_PENDING` status
   - Background job checks timeouts every hour
4. **State Transitions:**
   - `PENDING_ESCROW` → `PENDING_VEHICLE_ASSIGNMENT` (when escrow locks)
   - `PENDING_VEHICLE_ASSIGNMENT` → `PENDING_DELIVERY` (when first vehicle assigned)
   - `PENDING_DELIVERY` → `ACTIVE` (when delivery confirmed AND escrow locked)
   - `ACTIVE` → `COMPLETED` (when all vehicles returned)
   - Any state → `TIMEOUT_PENDING` (if 5-day timeout reached)
   - Any state → `ON_HOLD` (payment default or suspension)
   - Any state → `TERMINATED` (early termination)

### Party Snapshots

5. **Immutability:** Party details (names, tiers, commission rates) are snapshot at creation. Changes to master data do not affect active contracts.
6. **Policy Snapshot:** Contract stores snapshot of penalty rules, commission rates, and SLA terms at creation time.

### Assignment Rules

7. **Assignment Limit:** Cannot assign more vehicles than `QuantityAwarded`.
8. **Vehicle Exclusivity:** A vehicle cannot be assigned to two active contracts simultaneously.
9. **Vehicle Reassignment:** Provider can request vehicle replacement. Requires business approval.
10. **Service Type Match:** Assigned vehicle must meet service type requirements (capacity, license type).

### Return & Settlement

11. **Completion:** Contract becomes `COMPLETED` when **all** assigned vehicles are returned.
12. **Proration:** Early returns are calculated on a daily basis.
13. **Penalties:** Applied based on the `ContractPolicySnapshot` stored at creation.
14. **Refund Processing:** Early return triggers refund calculation and Finance Module settlement.

---

**Next Module:** [Finance_Module.md](./Finance_Module.md)
