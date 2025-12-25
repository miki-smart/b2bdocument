# Identity & Compliance Module - Specification

**Module Name:** Identity & Compliance  
**Version:** 1.1 MVP  
**Date:** December 22, 2025 (Updated)  
**Database Schema:** `identity`  
**Related Documents:**
- MVP_AUTHORITATIVE_BUSINESS_RULES.md (Section 8: Trust Score, Section 9: Tier System)
- BR-025 (Trust Score Calculation)
- BR-040, BR-041, BR-042 (Provider Tier System)

---

## 📋 Overview

### Purpose
The Identity & Compliance Module is the **source of truth** for all actors in the Movello platform. It manages user accounts, business clients, vehicle providers, vehicle registry, KYC/KYB verification, insurance compliance, and trust scoring.

### Responsibilities

✅ **User Management**
- Map Keycloak identities to internal user accounts
- Manage user devices and login sessions
- Handle MFA challenges

✅ **Business Management**
- Business registration and KYB verification
- Document upload and verification workflow
- Business tier assignment

✅ **Provider Management**
- Provider registration and KYC verification
- Provider tier assignment (Bronze → Platinum)
- Trust score calculation and history

✅ **Vehicle Management**
- Vehicle registration and compliance
- Insurance tracking and expiry monitoring
- Vehicle photo evidence

✅ **Compliance**
- Document verification workflows
- Insurance validation
- Account flagging for violations

---

## 🗄️ Database Schema

### Tables (22 Total)

#### **User Identity (4 tables)**
1. `user_account` - Core user records
2. `user_device` - Device fingerprinting
3. `user_login_session` - Active sessions
4. `user_mfa_challenge` - OTP challenges

#### **Business (3 tables)**
5. `business` - Business entities
6. `business_profile` - Extended metadata
7. `business_document` - KYB documents

#### **Provider (5 tables)**
8. `provider` - Provider entities
9. `provider_profile` - Extended metadata
10. `provider_tier_assignment` - Current tier
11. `provider_document` - KYC documents
12. `provider_trust_score_history` - Score changes

#### **Vehicle (3 tables)**
13. `vehicle` - Vehicle registry
14. `vehicle_document` - Generic documents
15. `vehicle_insurance` - Insurance tracking

#### **Compliance (4 tables)**
16. `verification_request` - Verification workflows
17. `compliance_check_log` - Audit trail
18. `risk_event` - Suspicious activities
19. `account_flag` - Account warnings

---

## 🏗️ Module Structure

```
Identity/
├── Domain/
│   ├── Entities/
│   │   ├── UserAccount.cs
│   │   ├── Business.cs
│   │   ├── BusinessProfile.cs
│   │   ├── Provider.cs
│   │   ├── ProviderProfile.cs
│   │   ├── ProviderTierAssignment.cs
│   │   ├── Vehicle.cs
│   │   ├── VehicleInsurance.cs
│   │   ├── VerificationRequest.cs
│   │   └── ProviderTrustScoreHistory.cs
│   │
│   ├── Events/
│   │   ├── BusinessRegisteredEvent.cs
│   │   ├── BusinessVerifiedEvent.cs
│   │   ├── ProviderRegisteredEvent.cs
│   │   ├── ProviderVerifiedEvent.cs
│   │   ├── VehicleRegisteredEvent.cs
│   │   ├── InsuranceExpiredEvent.cs
│   │   ├── TrustScoreUpdatedEvent.cs
│   │   └── TierChangedEvent.cs
│   │
│   ├── Enums/
│   │   ├── UserType.cs
│   │   ├── UserStatus.cs
│   │   ├── BusinessType.cs
│   │   ├── ProviderType.cs
│   │   ├── ProviderTier.cs
│   │   ├── VehicleStatus.cs
│   │   └── VerificationStatus.cs
│   │
│   └── ValueObjects/
│       ├── Address.cs
│       ├── ContactInfo.cs
│       └── TrustScore.cs
│
├── Application/
│   ├── Commands/
│   │   ├── Business/
│   │   │   ├── RegisterBusinessCommand.cs
│   │   │   ├── UploadBusinessDocumentCommand.cs
│   │   │   └── VerifyBusinessCommand.cs
│   │   ├── Provider/
│   │   │   ├── RegisterProviderCommand.cs
│   │   │   ├── UploadProviderDocumentCommand.cs
│   │   │   └── VerifyProviderCommand.cs
│   │   ├── Vehicle/
│   │   │   ├── RegisterVehicleCommand.cs
│   │   │   ├── UploadVehiclePhotosCommand.cs
│   │   │   └── UpdateInsuranceCommand.cs
│   │   └── TrustScore/
│   │       └── RecalculateTrustScoreCommand.cs
│   │
│   ├── Queries/
│   │   ├── GetBusinessByIdQuery.cs
│   │   ├── GetProviderByIdQuery.cs
│   │   ├── GetProviderTrustScoreQuery.cs
│   │   ├── GetVehicleByIdQuery.cs
│   │   └── GetPendingVerificationsQuery.cs
│   │
│   ├── DTOs/
│   │   ├── BusinessDto.cs
│   │   ├── ProviderDto.cs
│   │   ├── VehicleDto.cs
│   │   └── TrustScoreDto.cs
│   │
│   ├── Validators/
│   │   ├── RegisterBusinessValidator.cs
│   │   ├── RegisterProviderValidator.cs
│   │   └── RegisterVehicleValidator.cs
│   │
│   └── Services/
│       ├── ITrustScoreCalculator.cs
│       ├── TrustScoreCalculator.cs       ├── IProviderValidationService.cs
       ├── ProviderValidationService.cs│       ├── IInsuranceMonitor.cs
│       └── InsuranceMonitor.cs
│
├── Infrastructure/
│   ├── Data/
│   │   ├── Configurations/
│   │   │   ├── UserAccountConfiguration.cs
│   │   │   ├── BusinessConfiguration.cs
│   │   │   ├── ProviderConfiguration.cs
│   │   │   └── VehicleConfiguration.cs
│   │   └── IdentityDbContext.cs (part of MarketplaceDbContext)
│   │
│   ├── Repositories/
│   │   ├── IBusinessRepository.cs
│   │   ├── BusinessRepository.cs
│   │   ├── IProviderRepository.cs
│   │   ├── ProviderRepository.cs
│   │   ├── IVehicleRepository.cs
│   │   └── VehicleRepository.cs
│   │
│   └── Services/
│       └── KeycloakUserService.cs
│
└── API/
    └── Controllers/
        ├── BusinessController.cs
        ├── ProviderController.cs
        ├── VehicleController.cs
        └── ComplianceController.cs
```

---

## 🔄 Key Workflows

### 1. Business Registration & KYB

```csharp
// Command
public class RegisterBusinessCommand : IRequest<Guid>
{
    public string BusinessName { get; set; }
    public string BusinessType { get; set; }
    public string TinNumber { get; set; }
    public string RegistrationNumber { get; set; }
    public ContactInfo ContactInfo { get; set; }
    public Address Address { get; set; }
}

// Handler
public class RegisterBusinessCommandHandler : IRequestHandler<RegisterBusinessCommand, Guid>
{
    private readonly IBusinessRepository _businessRepository;
    private readonly IMediator _mediator;
    
    public async Task<Guid> Handle(RegisterBusinessCommand request, CancellationToken cancellationToken)
    {
        // 1. Validate TIN uniqueness
        var existingBusiness = await _businessRepository.GetByTinAsync(request.TinNumber);
        if (existingBusiness != null)
            throw new BusinessException("TIN already registered");
        
        // 2. Create business entity
        var business = new Business
        {
            Id = Guid.NewGuid(),
            BusinessName = request.BusinessName,
            BusinessType = request.BusinessType,
            TinNumber = request.TinNumber,
            Status = BusinessStatus.PendingKYB,
            CreatedAt = DateTime.UtcNow
        };
        
        // 3. Create business profile
        var profile = new BusinessProfile
        {
            BusinessId = business.Id,
            BusinessTierCode = "STANDARD", // Default tier
            OnboardingCompleted = false
        };
        
        // 4. Create verification request
        var verificationRequest = new VerificationRequest
        {
            ActorType = "BUSINESS",
            ActorId = business.Id,
            Status = VerificationStatus.Pending
        };
        
        // 5. Save to database
        await _businessRepository.AddAsync(business);
        await _businessRepository.AddProfileAsync(profile);
        await _businessRepository.AddVerificationRequestAsync(verificationRequest);
        
        // 6. Publish event
        await _mediator.Publish(new BusinessRegisteredEvent
        {
            BusinessId = business.Id,
            BusinessName = business.BusinessName,
            Email = request.ContactInfo.Email
        });
        
        return business.Id;
    }
}

// Event Handler (Finance Module listens)
public class BusinessRegisteredEventHandler : INotificationHandler<BusinessRegisteredEvent>
{
    private readonly IWalletService _walletService;
    
    public async Task Handle(BusinessRegisteredEvent notification, CancellationToken cancellationToken)
    {
        // Create wallet for business
        await _walletService.CreateWalletAsync(
            ownerType: "BUSINESS",
            ownerId: notification.BusinessId,
            accountType: "MAIN"
        );
    }
}
```

---

### 2. Provider Registration & KYC

```csharp
// Command
public class RegisterProviderCommand : IRequest<Guid>
{
    public string ProviderType { get; set; } // INDIVIDUAL, AGENT, COMPANY
    public string Name { get; set; }
    public string TinNumber { get; set; }
    public ContactInfo ContactInfo { get; set; }
}

// Handler
public class RegisterProviderCommandHandler : IRequestHandler<RegisterProviderCommand, Guid>
{
    private readonly IProviderRepository _providerRepository;
    private readonly IMediator _mediator;
    
    public async Task<Guid> Handle(RegisterProviderCommand request, CancellationToken cancellationToken)
    {
        // 1. Create provider entity
        var provider = new Provider
        {
            Id = Guid.NewGuid(),
            ProviderType = request.ProviderType,
            Name = request.Name,
            TinNumber = request.TinNumber,
            Status = ProviderStatus.PendingVerification
        };
        
        // 2. Create provider profile
        var profile = new ProviderProfile
        {
            ProviderId = provider.Id,
            FleetSize = 0,
            OnboardingCompleted = false
        };
        
        // 3. Determine initial tier (BR-041)
        // Verified providers with 100% profile completion: SILVER (trust score = 50)
        // Otherwise: BRONZE (trust score = 0)
        var initialTrustScore = provider.Status == ProviderStatus.Verified ? 50 : 0;
        var initialTier = DetermineInitialTier(provider, request);
        
        provider.TrustScore = initialTrustScore;
        
        var tierAssignment = new ProviderTierAssignment
        {
            ProviderId = provider.Id,
            TierCode = initialTier,
            ComputedScore = initialTrustScore,
            AssignedAt = DateTime.UtcNow
        };
        
        // 4. Initialize trust score history
        var trustScoreHistory = new ProviderTrustScoreHistory
        {
            ProviderId = provider.Id,
            OldScore = null,
            NewScore = 0,
            Reason = "INITIAL_REGISTRATION",
            CalculationSnapshot = new { message = "New provider" }
        };
        
        // 5. Save to database
        await _providerRepository.AddAsync(provider);
        await _providerRepository.AddProfileAsync(profile);
        await _providerRepository.AddTierAssignmentAsync(tierAssignment);
        await _providerRepository.AddTrustScoreHistoryAsync(trustScoreHistory);
        
        // 6. Publish event
        await _mediator.Publish(new ProviderRegisteredEvent
        {
            ProviderId = provider.Id,
            ProviderName = provider.Name,
            Email = request.ContactInfo.Email
        });
        
        return provider.Id;
    }
}
```

---

### 3. Vehicle Registration with Insurance

```csharp
// Command
public class RegisterVehicleCommand : IRequest<Guid>
{
    public Guid ProviderId { get; set; }
    public string PlateNumber { get; set; }
    public string VehicleTypeCode { get; set; }
    public string EngineTypeCode { get; set; }
    public int SeatCount { get; set; }
    public string Brand { get; set; }
    public string Model { get; set; }
    public List<string> Tags { get; set; }
    public VehicleInsuranceDto Insurance { get; set; }
}

// Handler
public class RegisterVehicleCommandHandler : IRequestHandler<RegisterVehicleCommand, Guid>
{
    private readonly IVehicleRepository _vehicleRepository;
    private readonly IMediator _mediator;
    
    public async Task<Guid> Handle(RegisterVehicleCommand request, CancellationToken cancellationToken)
    {
        // 1. Validate plate number uniqueness
        var existing = await _vehicleRepository.GetByPlateNumberAsync(request.PlateNumber);
        if (existing != null)
            throw new BusinessException("Plate number already registered");
        
        // 2. Create vehicle entity
        var vehicle = new Vehicle
        {
            Id = Guid.NewGuid(),
            ProviderId = request.ProviderId,
            PlateNumber = request.PlateNumber,
            VehicleTypeCode = request.VehicleTypeCode,
            EngineTypeCode = request.EngineTypeCode,
            SeatCount = request.SeatCount,
            Brand = request.Brand,
            Model = request.Model,
            Tags = request.Tags.ToArray(),
            Status = VehicleStatus.UnderReview
        };
        
        // 3. Create insurance record
        var insurance = new VehicleInsurance
        {
            Id = Guid.NewGuid(),
            VehicleId = vehicle.Id,
            InsuranceType = request.Insurance.InsuranceType,
            InsuranceCompanyName = request.Insurance.CompanyName,
            PolicyNumber = request.Insurance.PolicyNumber,
            InsuredAmount = request.Insurance.InsuredAmount,
            CoverageStartDate = request.Insurance.CoverageStartDate,
            CoverageEndDate = request.Insurance.CoverageEndDate,
            CertificateFileUrl = request.Insurance.CertificateFileUrl,
            Status = InsuranceStatus.PendingVerification
        };
        
        // 4. Validate insurance expiry
        if (insurance.CoverageEndDate < DateTime.UtcNow.AddDays(30))
        {
            throw new BusinessException("Insurance must be valid for at least 30 days");
        }
        
        // 5. Save to database
        await _vehicleRepository.AddAsync(vehicle);
        await _vehicleRepository.AddInsuranceAsync(insurance);
        
        // 6. Publish event
        await _mediator.Publish(new VehicleRegisteredEvent
        {
            VehicleId = vehicle.Id,
            ProviderId = vehicle.ProviderId,
            PlateNumber = vehicle.PlateNumber
        });
        
        return vehicle.Id;
    }
}
```

---

### 4. Trust Score Calculation

```csharp
// Service Interface
public interface ITrustScoreCalculator
{
    Task<int> CalculateTrustScoreAsync(Guid providerId);
}

// Implementation
public class TrustScoreCalculator : ITrustScoreCalculator
{
    private readonly IProviderRepository _providerRepository;
    private readonly IContractRepository _contractRepository;
    
    public async Task<int> CalculateTrustScoreAsync(Guid providerId)
    {
        // BR-025: Simple Trust Score Calculation
        // Formula: Base (50) + (Completion Rate × 20) + (On-Time Rate × 20) - (No-Show Rate × 30) + Rejection Penalty
        
        // 1. Gather metrics
        var metrics = await GatherMetricsAsync(providerId);
        
        // 2. Base score (50 for verified providers, 0 for unverified)
        var provider = await _providerRepository.GetByIdAsync(providerId);
        double baseScore = provider.Status == ProviderStatus.Verified ? 50.0 : 0.0;
        
        // 3. Calculate component rates (0-1 range)
        double completionRate = metrics.TotalContractsAwarded > 0 
            ? (double)metrics.ContractsCompleted / metrics.TotalContractsAwarded 
            : 0.0;
        
        double onTimeRate = metrics.TotalDeliveries > 0 
            ? (double)metrics.OnTimeDeliveries / metrics.TotalDeliveries 
            : 0.0;
        
        double noShowRate = metrics.TotalScheduled > 0 
            ? (double)metrics.NoShowCount / metrics.TotalScheduled 
            : 0.0;
        
        // 4. Apply BR-025 formula
        double trustScore = baseScore
            + (completionRate * 20)
            + (onTimeRate * 20)
            - (noShowRate * 30);
        
        // 5. Apply rejection penalty (BR-024) if applicable
        // Penalty = -5 points per rejected bid
        if (metrics.RejectionCount > 0)
        {
            trustScore -= (metrics.RejectionCount * 5);
        }
        
        // 6. Clamp to 0-100
        trustScore = Math.Max(0, Math.Min(100, trustScore));
        
        return (int)Math.Round(trustScore);
    }
    
    private async Task<ProviderMetrics> GatherMetricsAsync(Guid providerId)
    {
        // Gather metrics from various sources
        // This would query Contracts, Delivery, and Marketplace modules
        return new ProviderMetrics
        {
            TotalContractsAwarded = await GetTotalContractsAwardedAsync(providerId),
            ContractsCompleted = await GetCompletedContractsAsync(providerId),
            TotalDeliveries = await GetTotalDeliveriesAsync(providerId),
            OnTimeDeliveries = await GetOnTimeDeliveriesAsync(providerId),
            TotalScheduled = await GetTotalScheduledDeliveriesAsync(providerId),
            NoShowCount = await GetNoShowCountAsync(providerId),
            RejectionCount = await GetRejectionCountAsync(providerId)
        };
    }
}

// Command
public class RecalculateTrustScoreCommand : IRequest<int>
{
    public Guid ProviderId { get; set; }
    public string Reason { get; set; }
}

// Handler
public class RecalculateTrustScoreCommandHandler : IRequestHandler<RecalculateTrustScoreCommand, int>
{
    private readonly ITrustScoreCalculator _calculator;
    private readonly IProviderRepository _providerRepository;
    private readonly IMediator _mediator;
    
    public async Task<int> Handle(RecalculateTrustScoreCommand request, CancellationToken cancellationToken)
    {
        // 1. Get current score
        var provider = await _providerRepository.GetByIdAsync(request.ProviderId);
        var oldScore = provider.TrustScore;
        
        // 2. Calculate new score
        var newScore = await _calculator.CalculateTrustScoreAsync(request.ProviderId);
        
        // 3. Store history
        var history = new ProviderTrustScoreHistory
        {
            ProviderId = request.ProviderId,
            OldScore = oldScore,
            NewScore = newScore,
            Reason = request.Reason,
            CalculationSnapshot = await GetCalculationSnapshotAsync(request.ProviderId),
            CreatedAt = DateTime.UtcNow
        };
        
        await _providerRepository.AddTrustScoreHistoryAsync(history);
        
        // 4. Update provider
        provider.TrustScore = newScore;
        await _providerRepository.UpdateAsync(provider);
        
        // 5. Check for tier change
        var newTier = DetermineTier(newScore);
        var currentTier = await _providerRepository.GetCurrentTierAsync(request.ProviderId);
        
        if (newTier != currentTier.TierCode)
        {
            // Update tier assignment
            var tierAssignment = new ProviderTierAssignment
            {
                ProviderId = request.ProviderId,
                TierCode = newTier,
                ComputedScore = newScore,
                AssignedAt = DateTime.UtcNow
            };
            
            await _providerRepository.AddTierAssignmentAsync(tierAssignment);
            
            // Publish tier changed event
            await _mediator.Publish(new TierChangedEvent
            {
                ProviderId = request.ProviderId,
                OldTier = currentTier.TierCode,
                NewTier = newTier,
                TrustScore = newScore
            });
        }
        
        // 6. Publish trust score updated event
        await _mediator.Publish(new TrustScoreUpdatedEvent
        {
            ProviderId = request.ProviderId,
            OldScore = oldScore,
            NewScore = newScore
        });
        
        return newScore;
    }
    
    private async Task<string> DetermineTierAsync(Guid providerId, int trustScore)
    {
        // BR-042: Hybrid Tier Determination
        // Provider tier requires BOTH trust score AND active fleet size
        
        // Get active vehicle count for this provider
        var activeVehicles = await GetActiveVehicleCountAsync(providerId);
        
        // Tier requirements (BOTH must be met)
        // PLATINUM: Trust Score ≥ 85 AND Active Vehicles ≥ 30
        // GOLD: Trust Score ≥ 70 AND Active Vehicles ≥ 15
        // SILVER: Trust Score ≥ 50 AND Active Vehicles ≥ 5
        // BRONZE: Default (any score, any vehicles)
        
        if (trustScore >= 85 && activeVehicles >= 30)
            return "PLATINUM";
        
        if (trustScore >= 70 && activeVehicles >= 15)
            return "GOLD";
        
        if (trustScore >= 50 && activeVehicles >= 5)
            return "SILVER";
        
        return "BRONZE";
    }
    
    private async Task<int> GetActiveVehicleCountAsync(Guid providerId)
    {
        // Count vehicles in ACTIVE contracts only
        var query = @"
            SELECT COUNT(DISTINCT va.vehicle_id)
            FROM contracts_schema.vehicle_assignments va
            JOIN contracts_schema.contracts c ON va.contract_id = c.id
            WHERE c.provider_id = @ProviderId 
              AND c.status = 'ACTIVE'
              AND va.status = 'ACTIVE'";
        
        return await _dbConnection.ExecuteScalarAsync<int>(query, new { ProviderId = providerId });
    }
}
```

---

### 5. Provider Validation Service (BR-004)

```csharp
// Service Interface
public interface IProviderValidationService
{
    Task<ProviderEligibilityResult> ValidateProviderEligibilityAsync(Guid providerId, Guid serviceTypeId);
    Task<bool> HasAvailableVehiclesAsync(Guid providerId, Guid serviceTypeId, int requiredCount);
    Task<bool> HasValidInsuranceAsync(Guid providerId);
}

// Implementation
public class ProviderValidationService : IProviderValidationService
{
    private readonly IProviderRepository _providerRepository;
    private readonly IVehicleRepository _vehicleRepository;
    
    public async Task<ProviderEligibilityResult> ValidateProviderEligibilityAsync(
        Guid providerId, 
        Guid serviceTypeId)
    {
        var provider = await _providerRepository.GetByIdAsync(providerId);
        var result = new ProviderEligibilityResult { IsEligible = true };
        
        // 1. Check provider status
        if (provider.Status != ProviderStatus.Verified)
        {
            result.IsEligible = false;
            result.Reasons.Add("Provider not verified");
        }
        
        // 2. Check vehicle availability
        var hasVehicles = await HasAvailableVehiclesAsync(providerId, serviceTypeId, 1);
        if (!hasVehicles)
        {
            result.IsEligible = false;
            result.Reasons.Add("No available vehicles matching service type");
        }
        
        // 3. Check insurance compliance
        var hasInsurance = await HasValidInsuranceAsync(providerId);
        if (!hasInsurance)
        {
            result.IsEligible = false;
            result.Reasons.Add("No vehicles with valid insurance");
        }
        
        // 4. Check trust score minimum
        if (provider.TrustScore < 0) // MVP: No minimum trust score, but check for negative
        {
            result.IsEligible = false;
            result.Reasons.Add("Trust score below platform minimum");
        }
        
        return result;
    }
    
    public async Task<bool> HasAvailableVehiclesAsync(
        Guid providerId, 
        Guid serviceTypeId, 
        int requiredCount)
    {
        var query = @"
            SELECT COUNT(DISTINCT v.id)
            FROM identity.vehicles v
            WHERE v.provider_id = @ProviderId
              AND v.status = 'AVAILABLE'
              AND v.service_type_id = @ServiceTypeId
              AND EXISTS (
                  SELECT 1 FROM identity.vehicle_insurance vi
                  WHERE vi.vehicle_id = v.id
                    AND vi.expiry_date > NOW()
                    AND vi.status = 'ACTIVE'
              )";
        
        var count = await _dbConnection.ExecuteScalarAsync<int>(query, new 
        { 
            ProviderId = providerId, 
            ServiceTypeId = serviceTypeId 
        });
        
        return count >= requiredCount;
    }
    
    public async Task<bool> HasValidInsuranceAsync(Guid providerId)
    {
        var query = @"
            SELECT EXISTS (
                SELECT 1 FROM identity.vehicles v
                JOIN identity.vehicle_insurance vi ON vi.vehicle_id = v.id
                WHERE v.provider_id = @ProviderId
                  AND vi.expiry_date > NOW()
                  AND vi.status = 'ACTIVE'
            )";
        
        return await _dbConnection.ExecuteScalarAsync<bool>(query, new { ProviderId = providerId });
    }
}

// Result DTO
public class ProviderEligibilityResult
{
    public bool IsEligible { get; set; }
    public List<string> Reasons { get; set; } = new();
}
```

---

### 6. Initial Tier Assignment Helper (BR-041)

```csharp
// Helper method for determining initial provider tier
private string DetermineInitialTier(Provider provider, RegisterProviderCommand request)
{
    // BR-041: Initial tier assignment logic
    
    // Unverified providers always start at BRONZE
    if (provider.Status != ProviderStatus.Verified)
    {
        return "BRONZE";
    }
    
    // Calculate profile completion
    var profileCompletion = CalculateProfileCompletion(request);
    
    // Verified + 100% profile completion = SILVER (trust score = 50)
    if (profileCompletion >= 100)
    {
        return "SILVER";
    }
    
    // Verified but incomplete profile = BRONZE
    return "BRONZE";
}

private int CalculateProfileCompletion(RegisterProviderCommand request)
{
    var requiredFields = new List<bool>
    {
        !string.IsNullOrEmpty(request.BusinessLicense),
        !string.IsNullOrEmpty(request.TinCertificate),
        !string.IsNullOrEmpty(request.BankAccount),
        request.PhoneVerified,
        request.EmailVerified,
        request.HasActiveVehicles,
        request.InsuranceDocuments?.Any() == true
    };
    
    var completedCount = requiredFields.Count(f => f);
    return (completedCount * 100) / requiredFields.Count;
}
```

---

### 7. Insurance Expiry Monitoring

```csharp
// Background Service
public class InsuranceMonitorService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<InsuranceMonitorService> _logger;
    
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = _serviceProvider.CreateScope();
                var monitor = scope.ServiceProvider.GetRequiredService<IInsuranceMonitor>();
                
                await monitor.CheckExpiringInsuranceAsync();
                
                // Run daily at 9 AM
                await Task.Delay(TimeSpan.FromHours(24), stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in insurance monitoring");
            }
        }
    }
}

// Monitor Implementation
public class InsuranceMonitor : IInsuranceMonitor
{
    private readonly IVehicleRepository _vehicleRepository;
    private readonly IMediator _mediator;
    
    public async Task CheckExpiringInsuranceAsync()
    {
        var today = DateTime.UtcNow.Date;
        
        // 1. Check for expired insurance
        var expired = await _vehicleRepository.GetVehiclesWithExpiredInsuranceAsync(today);
        foreach (var vehicle in expired)
        {
            // Block vehicle
            vehicle.Status = VehicleStatus.Blocked;
            await _vehicleRepository.UpdateAsync(vehicle);
            
            // Publish event
            await _mediator.Publish(new InsuranceExpiredEvent
            {
                VehicleId = vehicle.Id,
                ProviderId = vehicle.ProviderId,
                PlateNumber = vehicle.PlateNumber
            });
        }
        
        // 2. Check for insurance expiring in 30 days
        var expiringSoon = await _vehicleRepository.GetVehiclesWithExpiringInsuranceAsync(
            today.AddDays(30)
        );
        
        foreach (var vehicle in expiringSoon)
        {
            // Send warning notification
            await _mediator.Publish(new InsuranceExpiringWarningEvent
            {
                VehicleId = vehicle.Id,
                ProviderId = vehicle.ProviderId,
                ExpiryDate = vehicle.Insurance.CoverageEndDate,
                DaysRemaining = (vehicle.Insurance.CoverageEndDate - today).Days
            });
        }
    }
}
```

---

## 📡 Events Published

### BusinessRegisteredEvent
```csharp
public class BusinessRegisteredEvent : INotification
{
    public Guid BusinessId { get; set; }
    public string BusinessName { get; set; }
    public string Email { get; set; }
}
```

### ProviderVerifiedEvent
```csharp
public class ProviderVerifiedEvent : INotification
{
    public Guid ProviderId { get; set; }
    public string ProviderName { get; set; }
    public string TierCode { get; set; }
}
```

### TrustScoreUpdatedEvent
```csharp
public class TrustScoreUpdatedEvent : INotification
{
    public Guid ProviderId { get; set; }
    public int OldScore { get; set; }
    public int NewScore { get; set; }
}
```

### InsuranceExpiredEvent
```csharp
public class InsuranceExpiredEvent : INotification
{
    public Guid VehicleId { get; set; }
    public Guid ProviderId { get; set; }
    public string PlateNumber { get; set; }
}
```

---

## 📡 Events Consumed

### ContractCompletedEvent
```csharp
// From Contracts Module
public class ContractCompletedEventHandler : INotificationHandler<ContractCompletedEvent>
{
    private readonly IMediator _mediator;
    
    public async Task Handle(ContractCompletedEvent notification, CancellationToken cancellationToken)
    {
        // Recalculate trust score
        await _mediator.Send(new RecalculateTrustScoreCommand
        {
            ProviderId = notification.ProviderId,
            Reason = "CONTRACT_COMPLETED"
        });
    }
}
```

---

## ✅ Business Rules

### Trust Score & Tier System (BR-025, BR-040, BR-041, BR-042)

1. **Trust Score Formula (BR-025):**
   - Base Score: 50 (verified providers), 0 (unverified)
   - Formula: `Base (50) + (Completion Rate × 20) + (On-Time Rate × 20) - (No-Show Rate × 30) + Rejection Penalty`
   - Range: 0-100 (capped)
   - Recalculation triggers: Contract completion, delivery confirmation, no-show incident, bid rejection

2. **Initial Provider Tier (BR-041):**
   - Verified + 100% profile completion: **SILVER** (trust score = 50)
   - Unverified or incomplete profile: **BRONZE** (trust score = 0)
   - **Profile Completion System (Configuration-Driven):**
     - Requirements stored in `masterdata.profile_requirements` table
     - Three requirement types: DOCUMENT, ATTRIBUTE, VERIFICATION
     - Default Provider Requirements (7 total):
       * DOCUMENT: Business License, TIN Certificate
       * ATTRIBUTE: Bank Account Details, ≥1 Approved Vehicle, Valid Insurance (30+ days)
       * VERIFICATION: Phone Verified, Email Verified
     - Default Business Requirements (8 total):
       * DOCUMENT: Business Registration, TIN Certificate
       * ATTRIBUTE: Contact Person (Name, Email, Phone), Billing Address
       * VERIFICATION: Email Verified, Phone Verified
     - Completion percentage = (completed mandatory requirements / total mandatory requirements) × 100
     - Service: `IProfileCompletionService.CalculateProviderCompletionAsync(providerId)`
     - Returns: `ProfileCompletionResult` with percentage, missing fields list
     - **Configurable:** Admins can add/remove requirements without code changes

3. **Hybrid Tier Determination (BR-042):**
   - PLATINUM: Trust Score ≥ 85 **AND** Active Vehicles ≥ 30
   - GOLD: Trust Score ≥ 70 **AND** Active Vehicles ≥ 15
   - SILVER: Trust Score ≥ 50 **AND** Active Vehicles ≥ 5
   - BRONZE: Default (any score, any vehicles)
   - Active vehicles = vehicles assigned to ACTIVE contracts

4. **Tier Commission Rates (BR-040):**
   - BRONZE: 10%
   - SILVER: 8%
   - GOLD: 6%
   - PLATINUM: 5%

### Compliance & Validation

5. **TIN Validation:** Must be unique, 10 digits
6. **Insurance Mandatory:** Zero tolerance policy - vehicles without valid insurance cannot be assigned
7. **Insurance Expiry:** 30-day minimum validity required
8. **Provider Eligibility (BR-004):** Must be verified, have available vehicles, valid insurance, trust score ≥ 0
9. **Photo Requirements:** 5 angles for all vehicles
10. **Document Verification:** Manual review by compliance officer
11. **Account Flags:** Auto-applied for violations
12. **Vehicle Exclusivity:** A vehicle cannot be assigned to multiple active contracts simultaneously

---

**Next Module:** [Marketplace_Module.md](./Marketplace_Module.md)
