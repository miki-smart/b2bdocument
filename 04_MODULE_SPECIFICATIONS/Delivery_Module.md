# Delivery Module - Specification

**Module Name:** Delivery  
**Version:** 1.1 MVP  
**Date:** December 22, 2025 (Updated)  
**Database Schema:** `delivery`  
**Dependencies:**
- Master Data Module (for OTP configuration: expiry time, max attempts, block duration)

---

## 📋 Overview

### Purpose
The Delivery Module manages the physical handover of vehicles between providers and businesses. It ensures trust and accountability through **OTP verification** and **digital evidence capture** (photos, odometer readings) at both pickup and return.

### Responsibilities

✅ **Delivery Session Management**
- Orchestrating the handover process
- Tracking session status (Pending → In Progress → Completed)
- Managing return sessions

✅ **OTP Verification**
- Generating secure 6-digit codes
- Sending codes via SMS/Email (via Notification Service)
- Verifying codes to authorize handover

✅ **Evidence Management**
- Uploading and storing vehicle photos (5 angles)
- Recording odometer and fuel levels
- capturing damage notes

✅ **SLA Tracking**
- Monitoring on-time delivery
- Tracking no-shows
- Calculating delivery delays

---

## 🗄️ Database Schema

### Tables (7 Total)

1. `delivery_session` - Handover session header
2. `delivery_otp` - Secure OTP storage
3. `delivery_vehicle_handover` - Evidence record (Pickup)
4. `delivery_return_session` - Return session header
5. `delivery_vehicle_return` - Evidence record (Return)
6. `delivery_location` - GPS coordinates (Optional for MVP)
7. `delivery_event_log` - Audit trail

---

## 🏗️ Module Structure

```
Delivery/
├── Domain/
│   ├── Entities/
│   │   ├── DeliverySession.cs
│   │   ├── DeliveryOTP.cs
│   │   ├── DeliveryVehicleHandover.cs
│   │   ├── DeliveryReturnSession.cs
│   │   └── DeliveryVehicleReturn.cs
│   │
│   ├── Events/
│   │   ├── DeliverySessionCreatedEvent.cs
│   │   ├── OTPGeneratedEvent.cs
│   │   ├── OTPVerifiedEvent.cs
│   │   ├── DeliveryConfirmedEvent.cs
│   │   └── DeliveryReturnConfirmedEvent.cs
│   │
│   ├── Enums/
│   │   ├── DeliveryStatus.cs
│   │   ├── FuelLevel.cs
│   │   └── ReturnReason.cs
│   │
│   └── Services/
│       ├── IOTPService.cs
│       └── OTPService.cs
│
├── Application/
│   ├── Commands/
│   │   ├── CreateDeliverySessionCommand.cs (Internal)
│   │   ├── GenerateOTPCommand.cs
│   │   ├── VerifyOTPCommand.cs
│   │   ├── SubmitHandoverEvidenceCommand.cs
│   │   └── SubmitReturnEvidenceCommand.cs
│   │
│   ├── Queries/
│   │   ├── GetDeliverySessionQuery.cs
│   │   ├── GetPendingDeliveriesQuery.cs
│   │   └── GetHandoverEvidenceQuery.cs
│   │
│   ├── DTOs/
│   │   ├── DeliverySessionDto.cs
│   │   ├── HandoverEvidenceDto.cs
│   │   └── OTPVerificationDto.cs
│   │
│   └── Validators/
│       ├── HandoverEvidenceValidator.cs
│       └── OTPValidator.cs
│
├── Infrastructure/
│   ├── Repositories/
│   │   ├── IDeliveryRepository.cs
│   │   └── DeliveryRepository.cs
│   │
│   └── Services/
│       └── SMSNotificationService.cs
│
└── API/
    └── Controllers/
        ├── DeliveryController.cs
        └── OTPController.cs
```

---

## 🔄 Key Workflows

### 1. OTP Generation & Verification

```csharp
// Command: Generate OTP
public class GenerateOTPCommand : IRequest<string>
{
    public Guid SessionId { get; set; }
    public Guid RequesterId { get; set; } // Provider Driver
}

// Handler
public class GenerateOTPCommandHandler : IRequestHandler<GenerateOTPCommand, string>
{
    private readonly IDeliveryRepository _repository;
    private readonly IOTPService _otpService;
    private readonly IMasterDataService _masterDataService;
    private readonly IMediator _mediator;

    public async Task<string> Handle(GenerateOTPCommand request, CancellationToken cancellationToken)
    {
        var session = await _repository.GetSessionAsync(request.SessionId);
        if (session.Status != DeliveryStatus.Pending)
            throw new BusinessException("Session not in pending state");

        // Generate 6-digit code
        var code = _otpService.GenerateCode();
        var hash = _otpService.Hash(code);
        
        // Get OTP expiry from Master Data settings (default: 15 minutes)
        var expiryMinutes = await _masterDataService.GetSettingAsync<int>("otp.expiry.minutes", 15);

        var otp = new DeliveryOTP
        {
            Id = Guid.NewGuid(),
            SessionId = request.SessionId,
            CodeHash = hash,
            ExpiresAt = DateTime.UtcNow.AddMinutes(expiryMinutes),
            CreatedAt = DateTime.UtcNow
        };

        await _repository.SaveOTPAsync(otp);

        // Publish event to send SMS to Business Contact
        await _mediator.Publish(new OTPGeneratedEvent
        {
            SessionId = request.SessionId,
            RecipientPhone = session.BusinessContactPhone,
            Code = code // Only exposed in this event for SMS sender
        });

        return "OTP Sent";
    }
}

// Command: Verify OTP
public class VerifyOTPCommand : IRequest<bool>
{
    public Guid SessionId { get; set; }
    public string Code { get; set; }
}

// Handler
public class VerifyOTPCommandHandler : IRequestHandler<VerifyOTPCommand, bool>
{
    private readonly IDeliveryRepository _repository;
    private readonly IOTPService _otpService;
    private readonly IMasterDataService _masterDataService;
    private readonly IMediator _mediator;
    
    public async Task<bool> Handle(VerifyOTPCommand request, CancellationToken cancellationToken)
    {
        var otp = await _repository.GetLatestOTPAsync(request.SessionId);
        
        if (otp == null || otp.IsUsed || otp.ExpiresAt < DateTime.UtcNow)
            throw new BusinessException("Invalid or expired OTP");
        
        // Get max attempts and block duration from Master Data settings
        var maxAttempts = await _masterDataService.GetSettingAsync<int>("otp.max.attempts", 3);
        var blockDurationMinutes = await _masterDataService.GetSettingAsync<int>("otp.block.duration.minutes", 30);

        // Check if attempts exceeded
        if (otp.Attempts >= maxAttempts)
        {
            // Block user temporarily
            var session = await _repository.GetSessionAsync(request.SessionId);
            session.BlockedUntil = DateTime.UtcNow.AddMinutes(blockDurationMinutes);
            await _repository.UpdateSessionAsync(session);
            
            throw new BusinessException($"Too many incorrect attempts. Blocked for {blockDurationMinutes} minutes.");
        }

        if (!_otpService.Verify(request.Code, otp.CodeHash))
        {
            otp.Attempts++;
            await _repository.UpdateOTPAsync(otp);
            
            var remainingAttempts = maxAttempts - otp.Attempts;
            throw new BusinessException($"Incorrect OTP. {remainingAttempts} attempts remaining.");
        }

        otp.IsUsed = true;
        otp.VerifiedAt = DateTime.UtcNow;
        await _repository.UpdateOTPAsync(otp);

        // Update Session Status
        var session = await _repository.GetSessionAsync(request.SessionId);
        session.Status = DeliveryStatus.OTPVerified;
        session.BlockedUntil = null; // Clear any blocks
        await _repository.UpdateSessionAsync(session);

        await _mediator.Publish(new OTPVerifiedEvent { SessionId = request.SessionId });

        return true;
    }
}
```

---

### 2. Handover Evidence Submission

```csharp
// Command
public class SubmitHandoverEvidenceCommand : IRequest<Guid>
{
    public Guid SessionId { get; set; }
    public string FrontPhotoUrl { get; set; }
    public string BackPhotoUrl { get; set; }
    public string LeftPhotoUrl { get; set; }
    public string RightPhotoUrl { get; set; }
    public string InteriorPhotoUrl { get; set; }
    public double OdometerReading { get; set; }
    public FuelLevel FuelLevel { get; set; }
    public string Notes { get; set; }
}

// Handler
public class SubmitHandoverEvidenceCommandHandler : IRequestHandler<SubmitHandoverEvidenceCommand, Guid>
{
    private readonly IDeliveryRepository _repository;
    private readonly IMediator _mediator;

    public async Task<Guid> Handle(SubmitHandoverEvidenceCommand request, CancellationToken cancellationToken)
    {
        var session = await _repository.GetSessionAsync(request.SessionId);
        
        // Ensure OTP was verified first
        if (session.Status != DeliveryStatus.OTPVerified)
            throw new BusinessException("OTP must be verified before handover");

        var evidence = new DeliveryVehicleHandover
        {
            Id = Guid.NewGuid(),
            SessionId = request.SessionId,
            FrontPhotoUrl = request.FrontPhotoUrl,
            BackPhotoUrl = request.BackPhotoUrl,
            LeftPhotoUrl = request.LeftPhotoUrl,
            RightPhotoUrl = request.RightPhotoUrl,
            InteriorPhotoUrl = request.InteriorPhotoUrl,
            OdometerReading = request.OdometerReading,
            FuelLevel = request.FuelLevel,
            Notes = request.Notes,
            CapturedAt = DateTime.UtcNow
        };

        await _repository.SaveHandoverAsync(evidence);

        // Complete Session
        session.Status = DeliveryStatus.Completed;
        session.CompletedAt = DateTime.UtcNow;
        await _repository.UpdateSessionAsync(session);

        // Publish Event (Contracts Module listens to Activate Contract)
        await _mediator.Publish(new DeliveryConfirmedEvent
        {
            SessionId = session.Id,
            ContractId = session.ContractId,
            VehicleId = session.VehicleId,
            HandoverId = evidence.Id,
            DeliveredAt = session.CompletedAt.Value
        });

        return evidence.Id;
    }
}
```

---

## 📡 Events Published

### DeliveryConfirmedEvent
```csharp
public class DeliveryConfirmedEvent : INotification
{
    public Guid SessionId { get; set; }
    public Guid ContractId { get; set; }
    public Guid VehicleId { get; set; }
    public Guid HandoverId { get; set; }
    public DateTime DeliveredAt { get; set; }
}
```

### DeliveryReturnConfirmedEvent
```csharp
public class DeliveryReturnConfirmedEvent : INotification
{
    public Guid SessionId { get; set; }
    public Guid ContractId { get; set; }
    public Guid VehicleId { get; set; }
    public DateTime ReturnedAt { get; set; }
    public double OdometerReading { get; set; }
}
```

---

## 📡 Events Consumed

### VehicleAssignedEvent
- **Source:** Contracts Module
- **Action:** Creates a `DeliverySession` in `Pending` state, ready for the provider to initiate delivery.

---

## ✅ Business Rules

### OTP Verification

1. **OTP Mandatory:** Handover cannot proceed without successful OTP verification.
2. **Recipient Verification:** OTP is sent ONLY to the registered business contact.
3. **Expiry Time:** OTP expiry configurable via Master Data settings (default: **15 minutes**)
   - Setting: `otp.expiry.minutes` (default: 15)
4. **Attempt Limits:** Max failed attempts configurable via Master Data (default: **3 attempts**)
   - Setting: `otp.max.attempts` (default: 3)
5. **Lockout Duration:** Failed attempt block duration configurable (default: **30 minutes**)
   - Setting: `otp.block.duration.minutes` (default: 30)
6. **OTP Format:** 6-digit numeric code

### Evidence Requirements

7. **Photo Evidence:** All 5 photo angles are mandatory (front, back, left, right, interior).
8. **Odometer Reading:** Required for both pickup and return.
9. **Fuel Level:** Must be recorded at pickup and return.
10. **Damage Notes:** Optional but recommended for accountability.

### Future Enhancements

11. **Location Verification:** (POST-MVP) GPS coordinates must match the agreed delivery location.

---

**Next Document:** [06_FRONTEND_ARCHITECTURE.md](./06_FRONTEND_ARCHITECTURE.md)
