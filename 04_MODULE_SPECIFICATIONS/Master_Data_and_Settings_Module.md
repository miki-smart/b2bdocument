# Master Data & Settings Module - Specification

**Module Name:** Master Data & Settings  
**Version:** 1.1 MVP  
**Date:** December 22, 2025 (Updated)  
**Database Schema:** `masterdata`  
**Related Documents:** MVP_AUTHORITATIVE_BUSINESS_RULES.md (Section 9, 10)

---

## 📋 Overview

### Purpose
The Master Data & Settings Module is the **configuration backbone** of the Movello platform. It stores all slow-changing, authoritative, non-transactional data that controls core business logic including pricing, commission, tiering, escrow, settlement, contract policies, KYC/KYB requirements, and geography.

### Core Principle
**"No hardcoding of business rules in code"** - All business logic parameters are data-driven and configurable.

### Responsibilities

✅ **Lookup Management**
- Reusable enumerations (vehicle types, contract periods, etc.)
- Multi-language support for lookups
- Active/inactive status management

✅ **System Settings**
- Platform-wide configuration
- Feature flags
- Operational parameters (OTP expiry, max RFQs, etc.)

✅ **Financial Policies (Versioned)**
- Commission strategies (tier-based rates)
- Escrow policies (lock amounts, release rules)
- Settlement policies (frequency, timing)

✅ **Contract Policies (Versioned)**
- Penalty rules (early return, no-show, late delivery)
- Amendment rules
- Termination conditions

✅ **Tiering System**
- Provider tiers (Bronze → Platinum)
- Business tiers (Standard → Enterprise)
- Tier benefits and thresholds

✅ **Compliance Configuration**
- Document types required for KYC/KYB/KYV
- Verification requirements
- Compliance check rules

✅ **Geography Data**
- Countries, regions, cities
- Used for address validation

---

## 🗄️ Database Schema

### Tables (23 Total)

#### **Lookups (4 tables)**
1. `lookup_type` - Lookup categories
2. `lookup` - Lookup values
3. `lookup_type_translation` - Multi-language type names
4. `lookup_translation` - Multi-language lookup values

#### **Settings (2 tables)**
5. `settings` - System configuration
6. `settings_translation` - Multi-language settings

#### **Commission Strategy (2 tables - VERSIONED)**
7. `commission_strategy_version` - Version header
8. `commission_strategy_rule` - Tier-based rates

#### **Escrow Policy (2 tables - VERSIONED)**
9. `escrow_policy_version` - Version header
10. `escrow_policy_rule` - Lock/release rules

#### **Settlement Policy (2 tables - VERSIONED)**
11. `settlement_policy_version` - Version header
12. `settlement_policy_rule` - Frequency/timing rules

#### **Tiering (4 tables)**
13. `provider_tier` - Provider tier definitions (BRONZE, SILVER, GOLD, PLATINUM)
14. `provider_tier_rule` - **Hybrid tier thresholds** (trust score + min_active_vehicles)
15. `business_tier` - Business tier definitions (STANDARD, BUSINESS_PRO, ENTERPRISE)
16. `business_tier_rule` - Business tier thresholds (completed contracts + active fleet size)

#### **Contract Policies (2 tables - VERSIONED)**
17. `contract_policy_version` - Version header
18. `contract_policy_rule` - Penalty/amendment rules

#### **Compliance (3 tables)**
19. `document_type` - Required document types
20. `kyc_requirement` - KYC/KYB/KYV requirements
21. `profile_requirement` - **Configurable profile completion requirements** (NEW)

#### **Geography (3 tables)**
22. `country` - Countries
23. `region` - Regions/states
24. `city` - Cities

---

## 🏗️ Module Structure

```
MasterData/
├── Domain/
│   ├── Entities/
│   │   ├── LookupType.cs
│   │   ├── Lookup.cs
│   │   ├── Settings.cs
│   │   ├── CommissionStrategyVersion.cs
│   │   ├── CommissionStrategyRule.cs
│   │   ├── EscrowPolicyVersion.cs
│   │   ├── EscrowPolicyRule.cs
│   │   ├── SettlementPolicyVersion.cs
│   │   ├── SettlementPolicyRule.cs
│   │   ├── ProviderTier.cs
│   │   ├── ProviderTierRule.cs
│   │   ├── BusinessTier.cs
│   │   ├── BusinessTierRule.cs
│   │   ├── ContractPolicyVersion.cs
│   │   ├── ContractPolicyRule.cs
│   │   ├── DocumentType.cs
│   │   ├── ProfileRequirement.cs
│   │   ├── KYCRequirement.cs
│   │   ├── Country.cs
│   │   ├── Region.cs
│   │   └── City.cs
│   │
│   ├── Events/
│   │   ├── CommissionStrategyUpdatedEvent.cs
│   │   ├── SettingsChangedEvent.cs
│   │   ├── PolicyVersionCreatedEvent.cs
│   │   ├── ProviderTierRuleUpdatedEvent.cs
│   │   └── BusinessTierRuleUpdatedEvent.cs
│   │
│   └── Services/
│       ├── IVersioningService.cs
│       ├── VersioningService.cs
│       ├── ITierCalculationService.cs
│       └── TierCalculationService.cs
│
├── Application/
│   ├── Commands/
│   │   ├── CreateLookupCommand.cs
│   │   ├── UpdateSettingCommand.cs
│   │   ├── CreateCommissionStrategyVersionCommand.cs
│   │   ├── CreateContractPolicyVersionCommand.cs
│   │   └── ActivatePolicyVersionCommand.cs
│   │
│   ├── Queries/
│   │   ├── GetLookupsByTypeQuery.cs
│   │   ├── GetSettingQuery.cs
│   │   ├── GetActiveCommissionStrategyQuery.cs
│   │   ├── GetActiveContractPolicyQuery.cs
│   │   ├── GetProviderTierQuery.cs
│   │   ├── GetProviderTierRulesQuery.cs
│   │   ├── GetBusinessTierRulesQuery.cs
│   │   ├── GetCommissionRateByTierQuery.cs
│   │   └── GetCitiesByRegionQuery.cs
│   │
│   ├── DTOs/
│   │   ├── LookupDto.cs
│   │   ├── SettingDto.cs
│   │   ├── CommissionStrategyDto.cs
│   │   ├── ContractPolicyDto.cs
│   │   ├── ProviderTierRuleDto.cs
│   │   └── BusinessTierRuleDto.cs
│   │
│   └── Services/
│       ├── ILookupService.cs
│       ├── LookupService.cs
│       ├── ISettingsService.cs
│       └── SettingsService.cs
│
├── Infrastructure/
│   ├── Repositories/
│   │   ├── ILookupRepository.cs
│   │   ├── LookupRepository.cs
│   │   ├── ISettingsRepository.cs
│   │   ├── SettingsRepository.cs
│   │   ├── IPolicyRepository.cs
│   │   └── PolicyRepository.cs
│   │
│   └── Caching/
│       └── MasterDataCache.cs
│
└── API/
    └── Controllers/
        ├── LookupsController.cs
        ├── SettingsController.cs
        ├── PoliciesController.cs
        └── GeographyController.cs
```

---

## 🔄 Key Workflows

### 1. Lookup Management

```csharp
// Query: Get Lookups by Type
public class GetLookupsByTypeQuery : IRequest<List<LookupDto>>
{
    public string TypeCode { get; set; }
    public bool IncludeInactive { get; set; } = false;
}

// Handler
public class GetLookupsByTypeQueryHandler : IRequestHandler<GetLookupsByTypeQuery, List<LookupDto>>
{
    private readonly ILookupRepository _lookupRepository;
    private readonly IMemoryCache _cache;
    
    public async Task<List<LookupDto>> Handle(GetLookupsByTypeQuery request, CancellationToken cancellationToken)
    {
        // Check cache first
        var cacheKey = $"lookups:{request.TypeCode}:{request.IncludeInactive}";
        
        if (_cache.TryGetValue(cacheKey, out List<LookupDto> cachedLookups))
        {
            return cachedLookups;
        }
        
        // Get from database
        var lookupType = await _lookupRepository.GetLookupTypeByCodeAsync(request.TypeCode);
        
        if (lookupType == null)
            throw new NotFoundException($"Lookup type '{request.TypeCode}' not found");
        
        var lookups = await _lookupRepository.GetLookupsByTypeIdAsync(
            lookupType.Id,
            request.IncludeInactive
        );
        
        var result = lookups.Select(l => new LookupDto
        {
            Id = l.Id,
            Code = l.Code,
            Value = l.Value,
            Metadata = l.Metadata,
            SortOrder = l.SortOrder,
            IsActive = l.IsActive
        }).ToList();
        
        // Cache for 1 hour (lookups rarely change)
        _cache.Set(cacheKey, result, TimeSpan.FromHours(1));
        
        return result;
    }
}

// Example Usage
var vehicleTypes = await _mediator.Send(new GetLookupsByTypeQuery 
{ 
    TypeCode = "VEHICLE_TYPE" 
});

// Returns:
// [
//   { Code: "EV_SEDAN", Value: "Electric Sedan", ... },
//   { Code: "MINIBUS_12", Value: "12-Seater Minibus", ... },
//   { Code: "SUV", Value: "SUV", ... }
// ]
```

---

### 2. Settings Management

```csharp
// Settings Service
public interface ISettingsService
{
    Task<T> GetSettingAsync<T>(string key);
    Task<string> GetSettingAsync(string key);
    Task UpdateSettingAsync(string key, string value);
}

// Implementation
public class SettingsService : ISettingsService
{
    private readonly ISettingsRepository _settingsRepository;
    private readonly IMemoryCache _cache;
    private readonly IMediator _mediator;
    
    public async Task<T> GetSettingAsync<T>(string key)
    {
        var value = await GetSettingAsync(key);
        
        if (string.IsNullOrEmpty(value))
            return default(T);
        
        return (T)Convert.ChangeType(value, typeof(T));
    }
    
    public async Task<string> GetSettingAsync(string key)
    {
        // Check cache
        var cacheKey = $"setting:{key}";
        
        if (_cache.TryGetValue(cacheKey, out string cachedValue))
        {
            return cachedValue;
        }
        
        // Get from database
        var setting = await _settingsRepository.GetByKeyAsync(key);
        
        if (setting == null || !setting.IsActive)
            return null;
        
        // Cache for 30 minutes
        _cache.Set(cacheKey, setting.Value, TimeSpan.FromMinutes(30));
        
        return setting.Value;
    }
    
    public async Task UpdateSettingAsync(string key, string value)
    {
        var setting = await _settingsRepository.GetByKeyAsync(key);
        
        if (setting == null)
            throw new NotFoundException($"Setting '{key}' not found");
        
        var oldValue = setting.Value;
        setting.Value = value;
        setting.UpdatedAt = DateTime.UtcNow;
        
        await _settingsRepository.UpdateAsync(setting);
        
        // Invalidate cache
        _cache.Remove($"setting:{key}");
        
        // Publish event
        await _mediator.Publish(new SettingChangedEvent
        {
            Key = key,
            OldValue = oldValue,
            NewValue = value
        });
    }
}

// Example Usage
var otpExpiryMinutes = await _settingsService.GetSettingAsync<int>("otp.expiry.minutes");
// Returns: 15 (default as per BR-014)

var maxRFQsPerMonth = await _settingsService.GetSettingAsync<int>("MAX_RFQS_PER_MONTH_STANDARD");
// Returns: 20
```

---

### 3. Commission Strategy (Versioned)

```csharp
// Create New Commission Strategy Version
public class CreateCommissionStrategyVersionCommand : IRequest<Guid>
{
    public string Name { get; set; }
    public DateTime EffectiveFrom { get; set; }
    public List<CommissionRuleDto> Rules { get; set; }
}

// Handler
public class CreateCommissionStrategyVersionCommandHandler 
    : IRequestHandler<CreateCommissionStrategyVersionCommand, Guid>
{
    private readonly IPolicyRepository _policyRepository;
    private readonly IMediator _mediator;
    
    public async Task<Guid> Handle(CreateCommissionStrategyVersionCommand request, CancellationToken cancellationToken)
    {
        // 1. Get current active version
        var currentVersion = await _policyRepository.GetActiveCommissionStrategyAsync();
        
        // 2. Validate effective date
        if (currentVersion != null && request.EffectiveFrom <= currentVersion.EffectiveFrom)
        {
            throw new BusinessException("Effective date must be after current version");
        }
        
        // 3. Calculate next version number
        var nextVersionNumber = currentVersion?.VersionNumber + 1 ?? 1;
        
        // 4. Create new version
        var version = new CommissionStrategyVersion
        {
            Id = Guid.NewGuid(),
            VersionNumber = nextVersionNumber,
            Name = request.Name,
            EffectiveFrom = request.EffectiveFrom,
            EffectiveTo = null, // Open-ended
            IsActive = false, // Not active until effective date
            CreatedAt = DateTime.UtcNow
        };
        
        await _policyRepository.AddCommissionStrategyVersionAsync(version);
        
        // 5. Create rules
        foreach (var ruleDto in request.Rules)
        {
            var rule = new CommissionStrategyRule
            {
                Id = Guid.NewGuid(),
                StrategyVersionId = version.Id,
                ProviderTierCode = ruleDto.ProviderTierCode,
                CommissionType = "PERCENTAGE",
                RatePercentage = ruleDto.RatePercentage,
                CreatedAt = DateTime.UtcNow
            };
            
            await _policyRepository.AddCommissionStrategyRuleAsync(rule);
        }
        
        // 6. Schedule activation (background job)
        if (request.EffectiveFrom <= DateTime.UtcNow)
        {
            await ActivateVersionAsync(version.Id);
        }
        
        return version.Id;
    }
    
    private async Task ActivateVersionAsync(Guid versionId)
    {
        // Deactivate current version
        var currentVersion = await _policyRepository.GetActiveCommissionStrategyAsync();
        if (currentVersion != null)
        {
            currentVersion.IsActive = false;
            currentVersion.EffectiveTo = DateTime.UtcNow;
            await _policyRepository.UpdateCommissionStrategyVersionAsync(currentVersion);
        }
        
        // Activate new version
        var newVersion = await _policyRepository.GetCommissionStrategyVersionByIdAsync(versionId);
        newVersion.IsActive = true;
        await _policyRepository.UpdateCommissionStrategyVersionAsync(newVersion);
        
        // Clear cache
        _cache.Remove("commission_strategy:active");
    }
}

// Query: Get Active Commission Strategy
public class GetActiveCommissionStrategyQuery : IRequest<CommissionStrategyDto>
{
}

// Handler
public class GetActiveCommissionStrategyQueryHandler 
    : IRequestHandler<GetActiveCommissionStrategyQuery, CommissionStrategyDto>
{
    private readonly IPolicyRepository _policyRepository;
    private readonly IMemoryCache _cache;
    
    public async Task<CommissionStrategyDto> Handle(GetActiveCommissionStrategyQuery request, CancellationToken cancellationToken)
    {
        // Check cache
        var cacheKey = "commission_strategy:active";
        
        if (_cache.TryGetValue(cacheKey, out CommissionStrategyDto cached))
        {
            return cached;
        }
        
        // Get from database
        var version = await _policyRepository.GetActiveCommissionStrategyAsync();
        
        if (version == null)
            throw new NotFoundException("No active commission strategy found");
        
        var rules = await _policyRepository.GetCommissionStrategyRulesAsync(version.Id);
        
        var result = new CommissionStrategyDto
        {
            VersionId = version.Id,
            VersionNumber = version.VersionNumber,
            Name = version.Name,
            EffectiveFrom = version.EffectiveFrom,
            Rules = rules.Select(r => new CommissionRuleDto
            {
                ProviderTierCode = r.ProviderTierCode,
                RatePercentage = r.RatePercentage
            }).ToList()
        };
        
        // Cache for 1 hour
        _cache.Set(cacheKey, result, TimeSpan.FromHours(1));
        
        return result;
    }
}

// Example: Get Commission Rate for Provider
public async Task<decimal> GetCommissionRateAsync(string providerTierCode)
{
    var strategy = await _mediator.Send(new GetActiveCommissionStrategyQuery());
    
    var rule = strategy.Rules.FirstOrDefault(r => r.ProviderTierCode == providerTierCode);
    
    if (rule == null)
        throw new NotFoundException($"No commission rule for tier '{providerTierCode}'");
    
    return rule.RatePercentage;
}

// Usage in Finance Module
var commissionRate = await GetCommissionRateAsync("GOLD");
// Returns: 0.06 (6% as per BR-040)

// Commission Rates by Tier (BR-040):
// BRONZE: 10%
// SILVER: 8%
// GOLD: 6%
// PLATINUM: 5%
```

---

### 4. Provider Tier Management

```csharp
// Query: Get Provider Tier Rules
public class GetProviderTierRulesQuery : IRequest<List<ProviderTierRuleDto>>
{
    public bool IncludeInactive { get; set; } = false;
}

// Handler
public class GetProviderTierRulesQueryHandler 
    : IRequestHandler<GetProviderTierRulesQuery, List<ProviderTierRuleDto>>
{
    private readonly IPolicyRepository _policyRepository;
    private readonly IMemoryCache _cache;
    
    public async Task<List<ProviderTierRuleDto>> Handle(
        GetProviderTierRulesQuery request, 
        CancellationToken cancellationToken)
    {
        var cacheKey = "provider_tier_rules:all";
        
        if (_cache.TryGetValue(cacheKey, out List<ProviderTierRuleDto> cached))
        {
            return cached;
        }
        
        // Get tiers and rules from database
        // NOTE: min_active_vehicles is REQUIRED column (BR-042)
        var query = @"
            SELECT 
                pt.code AS TierCode,
                pt.name AS TierName,
                ptr.min_trust_score AS MinTrustScore,
                ptr.max_trust_score AS MaxTrustScore,
                ptr.min_active_vehicles AS MinActiveVehicles,  -- HYBRID MODEL REQUIREMENT
                ptr.min_completed_contracts AS MinCompletedContracts,
                ptr.is_default_for_new AS IsDefaultForNew
            FROM masterdata.provider_tier pt
            JOIN masterdata.provider_tier_rule ptr ON pt.id = ptr.provider_tier_id
            WHERE pt.is_active = true
            ORDER BY ptr.min_trust_score DESC";
        
        var result = await _dbConnection.QueryAsync<ProviderTierRuleDto>(query);
        var ruleList = result.ToList();
        
        // Cache for 1 hour
        _cache.Set(cacheKey, ruleList, TimeSpan.FromHours(1));
        
        return ruleList;
    }
}

// DTOs
public class ProviderTierRuleDto
{
    public string TierCode { get; set; }
    public string TierName { get; set; }
    public int MinTrustScore { get; set; }
    public int MaxTrustScore { get; set; }
    public int MinActiveVehicles { get; set; }
    public int MinCompletedContracts { get; set; }
    public bool IsDefaultForNew { get; set; }
}

// Command: Update Tier Rule
public class UpdateProviderTierRuleCommand : IRequest<Unit>
{
    public string TierCode { get; set; }
    public int MinTrustScore { get; set; }
    public int MaxTrustScore { get; set; }
    public int MinActiveVehicles { get; set; }
}

// Usage: Calculate Provider Tier (HYBRID MODEL - BR-042)
// Tier determined by BOTH trust score AND active vehicle count
public async Task<string> CalculateProviderTierAsync(Guid providerId, int trustScore, int activeVehicles)
{
    var tierRules = await _mediator.Send(new GetProviderTierRulesQuery());
    
    // Hybrid Model: BOTH conditions must be met
    // Check tiers from highest to lowest
    foreach (var rule in tierRules)
    {
        bool meetsTrustScore = trustScore >= rule.MinTrustScore && 
                               trustScore <= rule.MaxTrustScore;
        
        bool meetsFleetRequirement = activeVehicles >= rule.MinActiveVehicles;
        
        // BOTH conditions must be satisfied
        if (meetsTrustScore && meetsFleetRequirement)
        {
            return rule.TierCode;
        }
    }
    
    return "BRONZE"; // Default if no rules match
}

// Example: Provider has trust_score=75, active_vehicles=10
// PLATINUM requires: trust_score >= 85 AND active_vehicles >= 30  ❌ Doesn't qualify
// GOLD requires:     trust_score >= 70 AND active_vehicles >= 15  ❌ Has 75 score but only 10 vehicles
// SILVER requires:   trust_score >= 50 AND active_vehicles >= 5   ✅ QUALIFIES (75 >= 50, 10 >= 5)
// Result: SILVER tier
```

---

### 5. Business Tier Management

```csharp
// Query: Get Business Tier Rules
public class GetBusinessTierRulesQuery : IRequest<List<BusinessTierRuleDto>>
{
    public bool IncludeInactive { get; set; } = false;
}

// Handler
public class GetBusinessTierRulesQueryHandler 
    : IRequestHandler<GetBusinessTierRulesQuery, List<BusinessTierRuleDto>>
{
    private readonly IPolicyRepository _policyRepository;
    private readonly IMemoryCache _cache;
    
    public async Task<List<BusinessTierRuleDto>> Handle(
        GetBusinessTierRulesQuery request, 
        CancellationToken cancellationToken)
    {
        var cacheKey = "business_tier_rules:all";
        
        if (_cache.TryGetValue(cacheKey, out List<BusinessTierRuleDto> cached))
        {
            return cached;
        }
        
        // Get tiers and rules from database
        var query = @"
            SELECT 
                bt.code AS TierCode,
                bt.name AS TierName,
                bt.max_rfqs_per_month AS MaxRfqsPerMonth,
                btr.min_completed_contracts AS MinCompletedContracts,
                btr.max_completed_contracts AS MaxCompletedContracts,
                btr.min_active_fleet_size AS MinActiveFleetSize,
                btr.max_active_fleet_size AS MaxActiveFleetSize,
                btr.is_default_for_new AS IsDefaultForNew
            FROM masterdata.business_tier bt
            JOIN masterdata.business_tier_rule btr ON bt.id = btr.business_tier_id
            WHERE bt.is_active = true
            ORDER BY btr.min_active_fleet_size ASC";
        
        var result = await _dbConnection.QueryAsync<BusinessTierRuleDto>(query);
        var ruleList = result.ToList();
        
        // Cache for 1 hour
        _cache.Set(cacheKey, ruleList, TimeSpan.FromHours(1));
        
        return ruleList;
    }
}

// DTOs
public class BusinessTierRuleDto
{
    public string TierCode { get; set; }
    public string TierName { get; set; }
    public int? MaxRfqsPerMonth { get; set; }
    public int MinCompletedContracts { get; set; }
    public int? MaxCompletedContracts { get; set; }
    public int MinActiveFleetSize { get; set; }
    public int? MaxActiveFleetSize { get; set; }
    public bool IsDefaultForNew { get; set; }
}

// Usage: Calculate Business Tier
public async Task<string> CalculateBusinessTierAsync(
    Guid businessId, 
    int completedContracts, 
    int activeFleetSize)
{
    var tierRules = await _mediator.Send(new GetBusinessTierRulesQuery());
    
    // Special case: 100+ vehicles = automatic ENTERPRISE
    if (activeFleetSize >= 100)
    {
        return "ENTERPRISE";
    }
    
    // Check tiers from highest to lowest
    foreach (var rule in tierRules.OrderByDescending(r => r.MinActiveFleetSize))
    {
        var meetsContractRequirement = 
            completedContracts >= rule.MinCompletedContracts &&
            (rule.MaxCompletedContracts == null || completedContracts <= rule.MaxCompletedContracts);
            
        var meetsFleetRequirement = 
            activeFleetSize >= rule.MinActiveFleetSize &&
            (rule.MaxActiveFleetSize == null || activeFleetSize <= rule.MaxActiveFleetSize);
            
        if (meetsContractRequirement && meetsFleetRequirement)
        {
            return rule.TierCode;
        }
    }
    
    return "STANDARD"; // Default
}
```

---

### 6. Tier Calculation Service

```csharp
// Tier Calculation Service (Used by Identity Module)
// Implements BR-042: Hybrid Tier Determination

public interface ITierCalculationService
{
    Task<string> CalculateProviderTierAsync(int trustScore, int activeVehicles);
    Task<string> CalculateBusinessTierAsync(int completedContracts, int activeFleetSize);
    Task<int> GetActiveVehicleCountAsync(Guid providerId);
    Task<decimal> GetCommissionRateForTierAsync(string providerTierCode);
}

public class TierCalculationService : ITierCalculationService
{
    private readonly IMediator _mediator;
    private readonly IDbConnection _dbConnection;
    private readonly IMemoryCache _cache;
    
    // Calculate Provider Tier using Hybrid Model (BR-042)
    public async Task<string> CalculateProviderTierAsync(int trustScore, int activeVehicles)
    {
        var tierRules = await _mediator.Send(new GetProviderTierRulesQuery());
        
        // BOTH conditions must be met (trust score AND fleet size)
        foreach (var rule in tierRules.OrderByDescending(r => r.MinTrustScore))
        {
            bool meetsTrustScore = trustScore >= rule.MinTrustScore && 
                                   trustScore <= rule.MaxTrustScore;
            
            bool meetsFleetRequirement = activeVehicles >= rule.MinActiveVehicles;
            
            if (meetsTrustScore && meetsFleetRequirement)
            {
                return rule.TierCode;
            }
        }
        
        return "BRONZE";
    }
    
    // Count vehicles currently in ACTIVE contracts
    public async Task<int> GetActiveVehicleCountAsync(Guid providerId)
    {
        var query = @"
            SELECT COUNT(DISTINCT va.vehicle_id)
            FROM contracts.contract_vehicle_assignment va
            JOIN contracts.contract c ON va.contract_id = c.id
            WHERE c.provider_id = @ProviderId 
              AND c.status = 'ACTIVE'
              AND va.status = 'ACTIVE'";
        
        return await _dbConnection.QuerySingleAsync<int>(query, new { ProviderId = providerId });
    }
    
    // Get commission rate from active strategy
    public async Task<decimal> GetCommissionRateForTierAsync(string providerTierCode)
    {
        var cacheKey = $"commission_rate:{providerTierCode}";
        
        if (_cache.TryGetValue(cacheKey, out decimal rate))
        {
            return rate;
        }
        
        var strategy = await _mediator.Send(new GetActiveCommissionStrategyQuery());
        var rule = strategy.Rules.FirstOrDefault(r => r.ProviderTierCode == providerTierCode);
        
        if (rule == null)
            throw new NotFoundException($"No commission rate for tier {providerTierCode}");
        
        _cache.Set(cacheKey, rule.RatePercentage, TimeSpan.FromHours(1));
        return rule.RatePercentage;
    }
    
    // Calculate Business Tier
    public async Task<string> CalculateBusinessTierAsync(int completedContracts, int activeFleetSize)
    {
        var tierRules = await _mediator.Send(new GetBusinessTierRulesQuery());
        
        // Special case: 100+ vehicles = automatic ENTERPRISE
        if (activeFleetSize >= 100)
        {
            return "ENTERPRISE";
        }
        
        foreach (var rule in tierRules.OrderByDescending(r => r.MinActiveFleetSize))
        {
            var meetsContractRequirement = 
                completedContracts >= rule.MinCompletedContracts &&
                (rule.MaxCompletedContracts == null || completedContracts <= rule.MaxCompletedContracts);
                
            var meetsFleetRequirement = 
                activeFleetSize >= rule.MinActiveFleetSize &&
                (rule.MaxActiveFleetSize == null || activeFleetSize <= rule.MaxActiveFleetSize);
                
            if (meetsContractRequirement && meetsFleetRequirement)
            {
                return rule.TierCode;
            }
        }
        
        return "STANDARD";
    }
}

// Usage in Identity Module:
// When trust score changes or contract activates/completes:
var newTier = await _tierCalculationService.CalculateProviderTierAsync(
    provider.TrustScore, 
    await _tierCalculationService.GetActiveVehicleCountAsync(provider.Id)
);

if (newTier != provider.CurrentTier)
{
    // Tier changed - publish event
    await _mediator.Publish(new ProviderTierChangedEvent
    {
        ProviderId = provider.Id,
        OldTier = provider.CurrentTier,
        NewTier = newTier,
        NewCommissionRate = await _tierCalculationService.GetCommissionRateForTierAsync(newTier)
    });
}
```

---

### 7. Cache Invalidation Strategy

```csharp
// When tier rules are updated, invalidate caches
public class TierRuleUpdatedEventHandler : INotificationHandler<TierRuleUpdatedEvent>
{
    private readonly IMemoryCache _cache;
    
    public async Task Handle(TierRuleUpdatedEvent notification, CancellationToken cancellationToken)
    {
        // Invalidate tier rules cache
        if (notification.TierType == "PROVIDER")
        {
            _cache.Remove("provider_tier_rules:all");
        }
        else if (notification.TierType == "BUSINESS")
        {
            _cache.Remove("business_tier_rules:all");
        }
        
        // Trigger tier recalculation for all users of this type
        await _mediator.Publish(new RecalculateAllTiersEvent
        {
            TierType = notification.TierType
        });
    }
}
```

---

## 📡 Events Published

### SettingChangedEvent
```csharp
public class SettingChangedEvent : INotification
{
    public string Key { get; set; }
    public string OldValue { get; set; }
    public string NewValue { get; set; }
}
```

### CommissionStrategyActivatedEvent
```csharp
public class CommissionStrategyActivatedEvent : INotification
{
    public Guid VersionId { get; set; }
    public int VersionNumber { get; set; }
    public DateTime EffectiveFrom { get; set; }
}
```

### ProviderTierRuleUpdatedEvent
```csharp
public class ProviderTierRuleUpdatedEvent : INotification
{
    public string TierCode { get; set; }
    public int NewMinTrustScore { get; set; }
    public int NewMinActiveVehicles { get; set; }
    public DateTime UpdatedAt { get; set; }
}
```

### BusinessTierRuleUpdatedEvent
```csharp
public class BusinessTierRuleUpdatedEvent : INotification
{
    public string TierCode { get; set; }
    public int NewMinActiveFleetSize { get; set; }
    public DateTime UpdatedAt { get; set; }
}
```

```csharp
// Contract Policy Rules
public class ContractPolicyRule
{
    public Guid Id { get; set; }
    public Guid PolicyVersionId { get; set; }
    public string RuleType { get; set; } // EARLY_RETURN_PENALTY, NO_SHOW_PENALTY, etc.
    public string AppliesTo { get; set; } // BUSINESS_TIER, ALL
    public string TargetValue { get; set; } // STANDARD, BUSINESS_PRO, etc.
    public string CalculationType { get; set; } // PERCENTAGE, FIXED_AMOUNT, DAYS_BASED
    public decimal Value { get; set; }
    public string Metadata { get; set; } // JSON for complex rules
}

// Example: Get Early Return Penalty Rate
public async Task<decimal> GetEarlyReturnPenaltyRateAsync(string businessTierCode)
{
    var policy = await _mediator.Send(new GetActiveContractPolicyQuery());
    
    var rule = policy.Rules.FirstOrDefault(r => 
        r.RuleType == "EARLY_RETURN_PENALTY" &&
        (r.AppliesTo == "ALL" || 
         (r.AppliesTo == "BUSINESS_TIER" && r.TargetValue == businessTierCode))
    );
    
    if (rule == null)
        return 0.25m; // Default 25%
    
    return rule.Value;
}

// Usage in Contracts Module
var penaltyRate = await GetEarlyReturnPenaltyRateAsync("STANDARD");
// Returns: 0.25 (25% penalty)

var penaltyRate = await GetEarlyReturnPenaltyRateAsync("ENTERPRISE");
// Returns: 0.15 (15% penalty - preferential rate)
```

---

### 5. Provider Tier Definitions

```csharp
// Seed Data Example (BR-040: Hybrid Tier Model)
public static class ProviderTierSeed
{
    public static List<ProviderTier> GetTiers()
    {
        return new List<ProviderTier>
        {
            new ProviderTier
            {
                Code = "BRONZE",
                Name = "Bronze",
                MinTrustScore = 0,
                MaxTrustScore = 49,
                MinActiveVehicles = 0,  // No fleet requirement
                Benefits = new
                {
                    CommissionRate = 0.10m,  // 10%
                    SettlementFrequency = "MONTHLY",
                    PrioritySupport = false,
                    FeaturedListing = false
                }
            },
            new ProviderTier
            {
                Code = "SILVER",
                Name = "Silver",
                MinTrustScore = 50,
                MaxTrustScore = 69,
                MinActiveVehicles = 5,   // Requires 5+ active vehicles
                Benefits = new
                {
                    CommissionRate = 0.08m,  // 8%
                    SettlementFrequency = "MONTHLY",
                    PrioritySupport = false,
                    FeaturedListing = false
                }
            },
            new ProviderTier
            {
                Code = "GOLD",
                Name = "Gold",
                MinTrustScore = 70,
                MaxTrustScore = 84,
                MinActiveVehicles = 15,  // Requires 15+ active vehicles
                Benefits = new
                {
                    CommissionRate = 0.06m,  // 6%
                    SettlementFrequency = "BI_WEEKLY",
                    PrioritySupport = true,
                    FeaturedListing = true
                }
            },
            new ProviderTier
            {
                Code = "PLATINUM",
                Name = "Platinum",
                MinTrustScore = 85,
                MaxTrustScore = 100,
                MinActiveVehicles = 30,  // Requires 30+ active vehicles
                Benefits = new
                {
                    CommissionRate = 0.05m,  // 5%
                    SettlementFrequency = "WEEKLY",
                    PrioritySupport = true,
                    FeaturedListing = true,
                    InstantPayout = true
                }
            }
        };
    }
}
```

---

## 🎯 Caching Strategy

```csharp
public class MasterDataCache
{
    private readonly IMemoryCache _cache;
    
    // Cache durations
    private static readonly TimeSpan LOOKUP_CACHE_DURATION = TimeSpan.FromHours(1);
    private static readonly TimeSpan SETTINGS_CACHE_DURATION = TimeSpan.FromMinutes(30);
    private static readonly TimeSpan POLICY_CACHE_DURATION = TimeSpan.FromHours(1);
    
    public async Task<List<LookupDto>> GetLookupsAsync(string typeCode, Func<Task<List<LookupDto>>> factory)
    {
        var cacheKey = $"lookups:{typeCode}";
        return await _cache.GetOrCreateAsync(cacheKey, async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = LOOKUP_CACHE_DURATION;
            return await factory();
        });
    }
    
    public void InvalidateLookups(string typeCode)
    {
        _cache.Remove($"lookups:{typeCode}");
    }
    
    public void InvalidateAllLookups()
    {
        // Clear all lookup cache keys
        // Implementation depends on cache provider
    }
}
```

---

## ✅ Business Rules

1. **Versioning:** All financial policies are versioned
2. **Effective Dates:** New versions activate on effective date
3. **No Retroactive Changes:** Active contracts use policy snapshot
4. **Cache Duration:** 
   - Lookups: 1 hour
   - Settings: 30 minutes
   - Policies: 1 hour
5. **Lookup Codes:** Uppercase, underscore-separated (e.g., `EV_SEDAN`)
6. **Setting Keys:** Uppercase, underscore-separated (e.g., `OTP_EXPIRY_MINUTES`)
7. **Multi-language:** Supported for lookups and settings
8. **Soft Deletes:** Use `is_active` flag, never hard delete
9. **Audit Trail:** All changes logged with `created_by`, `updated_by`
10. **Default Values:** Always provide fallback for missing settings

---

## 📊 Seed Data Requirements

### **Critical Lookups**
- `VEHICLE_TYPE`: EV_SEDAN, SEDAN, SUV, MINIBUS_12, BUS_30, etc.
- `ENGINE_TYPE`: EV, DIESEL, PETROL, HYBRID
- `CONTRACT_PERIOD`: MONTH, EVENT, WEEK
- `INSURANCE_TYPE`: COMPREHENSIVE, THIRD_PARTY
- `BUSINESS_TYPE`: PLC, NGO, GOV, SOLE_PROPRIETOR
- `PROVIDER_TYPE`: INDIVIDUAL, AGENT, COMPANY

### **Critical Settings**
- `otp.expiry.minutes`: 15  (BR-014 - configurable OTP expiry)
- `otp.max.attempts`: 3  (max incorrect attempts before block)
- `otp.block.duration.minutes`: 30  (block duration after max attempts)
- `max.rfqs.per.month.standard`: 20
- `max.rfqs.per.month.business_pro`: 50
- `escrow.multiplier.monthly`: 1.0
- `escrow.multiplier.event`: 1.0
- `min.insurance.validity.days`: 30

### **Commission Strategy v1**
- BRONZE: 10%
- SILVER: 8%
- GOLD: 6%
- PLATINUM: 5%

### **Contract Policy v1**
- Early Return Penalty (STANDARD): 25%
- Early Return Penalty (BUSINESS_PRO): 20%
- Early Return Penalty (ENTERPRISE): 15%
- No-Show Penalty: 15%
- Under-Delivery Penalty: 10%

### **Profile Requirements (NEW - Configuration-Driven Completion)**
**Purpose:** Define mandatory requirements for provider/business profile completion  
**Entity Types:** PROVIDER, BUSINESS  
**Requirement Types:** DOCUMENT, ATTRIBUTE, VERIFICATION  

**PROVIDER Requirements (7 total):**
1. DOCUMENT - BUSINESS_LICENSE: Upload & verify business license
2. DOCUMENT - TIN_CERTIFICATE: Upload & verify TIN certificate
3. ATTRIBUTE - BANK_ACCOUNT: Complete bank account details
4. VERIFICATION - PHONE_VERIFIED: Verify phone via OTP
5. VERIFICATION - EMAIL_VERIFIED: Verify email address
6. ATTRIBUTE - APPROVED_VEHICLE: At least 1 approved vehicle
7. ATTRIBUTE - VEHICLE_INSURANCE: Valid insurance (30+ days) for all vehicles

**BUSINESS Requirements (8 total):**
1. DOCUMENT - BUSINESS_LICENSE: Upload & verify registration
2. DOCUMENT - TIN_CERTIFICATE: Upload & verify TIN certificate
3. ATTRIBUTE - CONTACT_PERSON_NAME: Provide contact person name
4. ATTRIBUTE - CONTACT_PERSON_EMAIL: Provide contact person email
5. ATTRIBUTE - CONTACT_PERSON_PHONE: Provide contact person phone
6. ATTRIBUTE - BILLING_ADDRESS: Complete billing address
7. VERIFICATION - EMAIL_VERIFIED: Verify business email
8. VERIFICATION - PHONE_VERIFIED: Verify business phone via OTP

**Benefits:**
- Admins can add/remove requirements without code deployment
- Supports dynamic validation rules (JSON format)
- Frontend can fetch requirements via API for progressive onboarding
- Used by TierCalculationService to determine initial tier (BR-041)

---

**Next Module:** [Auth_and_Keycloak_Module.md](./Auth_and_Keycloak_Module.md)
