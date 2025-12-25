# Marketplace Module - Specification

**Module Name:** Marketplace  
**Version:** 1.1 MVP  
**Date:** December 22, 2025 (Updated)  
**Database Schema:** `marketplace`  
**Related Documents:** MVP_AUTHORITATIVE_BUSINESS_RULES.md (Section 1, 2)

---

## 📋 Overview

### Purpose
The Marketplace Module manages the **RFQ (Request for Quote) lifecycle** and **blind bidding process**. It connects businesses seeking vehicles with providers offering them through a transparent, competitive marketplace.

### Responsibilities

✅ **RFQ Management**
- Multi-line-item RFQ creation
- RFQ publication and lifecycle
- Bid deadline management

✅ **Blind Bidding**
- Provider identity anonymization (SHA-256 hashing)
- Bid submission and validation
- Price floor/ceiling enforcement

✅ **Award Processing**
- Bid evaluation and selection
- Split awards (multiple providers per line item)
- Partial awards (based on wallet balance)
- Provider identity revelation

✅ **Market Intelligence**
- Market price tracking
- Bid statistics
- Provider matching

---

## 🗄️ Database Schema

### Tables (8 Total)

1. `rfq` - RFQ header
2. `rfq_line_item` - Vehicle requirements per RFQ
3. `rfq_bid` - Provider bid header
4. `rfq_bid_snapshot` - Anonymized bid details (blind bidding)
5. `rfq_bid_award` - Winning bids
6. `rfq_line_item_fulfillment` - Delivery tracking
7. `rfq_award_vehicle_assignment` - Specific vehicles assigned
8. `marketplace_event_log` - Audit trail

---

## 🏗️ Module Structure

```
Marketplace/
├── Domain/
│   ├── Entities/
│   │   ├── RFQ.cs
│   │   ├── RFQLineItem.cs
│   │   ├── RFQBid.cs
│   │   ├── RFQBidSnapshot.cs
│   │   ├── RFQBidAward.cs
│   │   └── MarketPriceSnapshot.cs
│   │
│   ├── Events/
│   │   ├── RFQCreatedEvent.cs
│   │   ├── RFQPublishedEvent.cs
│   │   ├── BidSubmittedEvent.cs
│   │   ├── BidAwardedEvent.cs
│   │   └── RFQClosedEvent.cs
│   │
│   ├── Enums/
│   │   ├── RFQStatus.cs
│   │   ├── BidStatus.cs
│   │   └── AwardStatus.cs
│   │
│   └── Services/
│       ├── IBlindBiddingService.cs
│       ├── BlindBiddingService.cs
│       ├── IPriceValidator.cs
│       └── PriceValidator.cs
│
├── Application/
│   ├── Commands/
│   │   ├── CreateRFQCommand.cs
│   │   ├── PublishRFQCommand.cs
│   │   ├── SubmitBidCommand.cs
│   │   ├── AwardBidCommand.cs
│   │   └── CalculateMaxAffordableCommand.cs
│   │
│   ├── Queries/
│   │   ├── GetOpenRFQsQuery.cs
│   │   ├── GetRFQByIdQuery.cs
│   │   ├── GetBidsForRFQQuery.cs
│   │   └── GetProviderBidsQuery.cs
│   │
│   ├── DTOs/
│   │   ├── RFQDto.cs
│   │   ├── RFQLineItemDto.cs
│   │   ├── BidDto.cs
│   │   └── AwardDto.cs
│   │
│   └── Validators/
│       ├── CreateRFQValidator.cs
│       ├── SubmitBidValidator.cs
│       └── AwardBidValidator.cs
│
├── Infrastructure/
│   ├── Repositories/
│   │   ├── IRFQRepository.cs
│   │   ├── RFQRepository.cs
│   │   ├── IBidRepository.cs
│   │   └── BidRepository.cs
│   │
│   └── Services/
│       └── MarketPriceService.cs
│
└── API/
    └── Controllers/
        ├── RFQController.cs
        └── BiddingController.cs
```

---

## 🔄 Key Workflows

### 1. Create RFQ

```csharp
// Command
public class CreateRFQCommand : IRequest<Guid>
{
    public Guid BusinessId { get; set; }
    public string Title { get; set; }
    public string Description { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public DateTime BidDeadline { get; set; }
    public List<RFQLineItemDto> LineItems { get; set; }
}

// Handler
public class CreateRFQCommandHandler : IRequestHandler<CreateRFQCommand, Guid>
{
    private readonly IRFQRepository _rfqRepository;
    private readonly IMediator _mediator;
    
    public async Task<Guid> Handle(CreateRFQCommand request, CancellationToken cancellationToken)
    {
        // 1. Validate dates
        if (request.StartDate < DateTime.UtcNow.AddDays(3))
            throw new BusinessException("Start date must be at least 3 days from now");
        
        if (request.BidDeadline >= request.StartDate)
            throw new BusinessException("Bid deadline must be before start date");
        
        // 2. Validate line items
        if (request.LineItems.Sum(x => x.QuantityRequired) > 50)
            throw new BusinessException("Maximum 50 vehicles per RFQ");
        
        // ⚠️ NO wallet balance check here (per updated business rules)
        
        // 3. Create RFQ
        var rfq = new RFQ
        {
            Id = Guid.NewGuid(),
            BusinessId = request.BusinessId,
            Title = request.Title,
            Description = request.Description,
            StartDate = request.StartDate,
            EndDate = request.EndDate,
            BidDeadline = request.BidDeadline,
            Status = RFQStatus.Draft,
            CreatedAt = DateTime.UtcNow
        };
        
        // 4. Create line items
        var lineItems = request.LineItems.Select(li => new RFQLineItem
        {
            Id = Guid.NewGuid(),
            RFQId = rfq.Id,
            VehicleTypeCode = li.VehicleTypeCode,
            EngineTypeCode = li.EngineTypeCode,
            QuantityRequired = li.QuantityRequired,
            WithDriver = li.WithDriver,
            PreferredTags = li.PreferredTags?.ToArray()
        }).ToList();
        
        // 5. Save to database
        await _rfqRepository.AddAsync(rfq);
        await _rfqRepository.AddLineItemsAsync(lineItems);
        
        // 6. Publish event
        await _mediator.Publish(new RFQCreatedEvent
        {
            RFQId = rfq.Id,
            BusinessId = rfq.BusinessId,
            Title = rfq.Title
        });
        
        return rfq.Id;
    }
}
```

---

### 2. Publish RFQ

```csharp
// Command
public class PublishRFQCommand : IRequest<Unit>
{
    public Guid RFQId { get; set; }
    public Guid BusinessId { get; set; }
}

// Handler
public class PublishRFQCommandHandler : IRequestHandler<PublishRFQCommand, Unit>
{
    private readonly IRFQRepository _rfqRepository;
    private readonly IMediator _mediator;
    
    public async Task<Unit> Handle(PublishRFQCommand request, CancellationToken cancellationToken)
    {
        // 1. Get RFQ
        var rfq = await _rfqRepository.GetByIdAsync(request.RFQId);
        
        if (rfq == null)
            throw new NotFoundException("RFQ not found");
        
        if (rfq.BusinessId != request.BusinessId)
            throw new ForbiddenException("Not authorized");
        
        // 2. Validate status
        if (rfq.Status != RFQStatus.Draft)
            throw new BusinessException("RFQ already published");
        
        // 3. Validate has line items
        var lineItems = await _rfqRepository.GetLineItemsAsync(rfq.Id);
        if (!lineItems.Any())
            throw new BusinessException("RFQ must have at least one line item");
        
        // 4. Update status
        rfq.Status = RFQStatus.Published;
        rfq.PublishedAt = DateTime.UtcNow;
        await _rfqRepository.UpdateAsync(rfq);
        
        // 5. Publish event (Notifications module will notify eligible providers)
        await _mediator.Publish(new RFQPublishedEvent
        {
            RFQId = rfq.Id,
            BusinessId = rfq.BusinessId,
            Title = rfq.Title,
            BidDeadline = rfq.BidDeadline,
            LineItems = lineItems.Select(li => new
            {
                li.VehicleTypeCode,
                li.QuantityRequired,
                li.WithDriver
            }).ToList()
        });
        
        return Unit.Value;
    }
}
```

---

### 3. Submit Bid (Blind Bidding)

```csharp
// Service Interface
public interface IBlindBiddingService
{
    string HashProviderId(Guid providerId);
    bool VerifyProviderHash(Guid providerId, string hash);
}

// Implementation
public class BlindBiddingService : IBlindBiddingService
{
    private const string SALT = "movello-blind-bidding-salt-2025"; // Store in config
    
    public string HashProviderId(Guid providerId)
    {
        var input = $"{providerId}{SALT}";
        using var sha256 = SHA256.Create();
        var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(input));
        var hash = Convert.ToBase64String(hashBytes);
        
        // Return masked version for display: "Provider •••4411"
        return $"Provider •••{hash.Substring(hash.Length - 4)}";
    }
    
    public bool VerifyProviderHash(Guid providerId, string hash)
    {
        var computed = HashProviderId(providerId);
        return computed == hash;
    }
}

// Command
public class SubmitBidCommand : IRequest<Guid>
{
    public Guid RFQId { get; set; }
    public Guid ProviderId { get; set; }
    public List<BidLineItemDto> LineItemBids { get; set; }
}

// Handler
public class SubmitBidCommandHandler : IRequestHandler<SubmitBidCommand, Guid>
{
    private readonly IRFQRepository _rfqRepository;
    private readonly IBidRepository _bidRepository;
    private readonly IBlindBiddingService _blindBiddingService;
    private readonly IPriceValidator _priceValidator;
    private readonly IMediator _mediator;
    
    public async Task<Guid> Handle(SubmitBidCommand request, CancellationToken cancellationToken)
    {
        // 1. Validate RFQ is open for bidding
        var rfq = await _rfqRepository.GetByIdAsync(request.RFQId);
        
        if (rfq.Status != RFQStatus.Published)
            throw new BusinessException("RFQ is not open for bidding");
        
        if (DateTime.UtcNow > rfq.BidDeadline)
            throw new BusinessException("Bid deadline has passed");
        
        // 2. PRE-BID VALIDATION (BR-004)
        await ValidateProviderEligibilityAsync(request.ProviderId, request.LineItemBids, rfq);
        
        // 3. Validate prices
        foreach (var bidItem in request.LineItemBids)
        {
            var lineItem = await _rfqRepository.GetLineItemByIdAsync(bidItem.LineItemId);
            
            var isValid = await _priceValidator.ValidatePriceAsync(
                lineItem.VehicleTypeCode,
                bidItem.UnitPrice
            );
            
            if (!isValid)
                throw new BusinessException($"Price out of acceptable range for {lineItem.VehicleTypeCode}");
        }
        
        // 4. Create bid header
        var bid = new RFQBid
        {
            Id = Guid.NewGuid(),
            RFQId = request.RFQId,
            ProviderId = request.ProviderId,
            Status = BidStatus.Submitted,
            SubmittedAt = DateTime.UtcNow
        };
        
        await _bidRepository.AddAsync(bid);
        
        // 5. Create blind bid snapshots (anonymized)
        var snapshots = request.LineItemBids.Select(bidItem => new RFQBidSnapshot
        {
            Id = Guid.NewGuid(),
            RFQLineItemId = bidItem.LineItemId,
            RFQBidId = bid.Id,
            HashedProviderId = _blindBiddingService.HashProviderId(request.ProviderId),
            UnitPrice = bidItem.UnitPrice,
            QuantityOffered = bidItem.QuantityOffered,
            Notes = bidItem.Notes,
            CreatedAt = DateTime.UtcNow
        }).ToList();
        
        await _bidRepository.AddSnapshotsAsync(snapshots);
        
        // 6. Publish event
        await _mediator.Publish(new BidSubmittedEvent
        {
            BidId = bid.Id,
            RFQId = request.RFQId,
            ProviderId = request.ProviderId
        });
        
        return bid.Id;
    }
}
```

---

### 4. Award Bid (with Wallet Validation)

```csharp
// Command
public class AwardBidCommand : IRequest<List<Guid>>
{
    public Guid RFQId { get; set; }
    public Guid BusinessId { get; set; }
    public List<AwardDto> Awards { get; set; }
}

// Handler
public class AwardBidCommandHandler : IRequestHandler<AwardBidCommand, List<Guid>>
{
    private readonly IRFQRepository _rfqRepository;
    private readonly IBidRepository _bidRepository;
    private readonly IWalletService _walletService;
    private readonly IMediator _mediator;
    
    public async Task<List<Guid>> Handle(AwardBidCommand request, CancellationToken cancellationToken)
    {
        // 1. Validate RFQ
        var rfq = await _rfqRepository.GetByIdAsync(request.RFQId);
        
        if (rfq.BusinessId != request.BusinessId)
            throw new ForbiddenException("Not authorized");
        
        if (rfq.Status != RFQStatus.BiddingClosed && DateTime.UtcNow <= rfq.BidDeadline)
            throw new BusinessException("Bidding is still open");
        
        // 2. AWARD VALIDATION (BR-006)
        // a. Validate all bids still exist and providers still eligible
        foreach (var award in request.Awards)
        {
            var bid = await _bidRepository.GetByIdAsync(award.BidId);
            if (bid == null || bid.Status != BidStatus.Submitted)
                throw new BusinessException($"Bid {award.BidId} is no longer valid");
            
            // Re-validate provider eligibility at award time
            await ValidateProviderAtAwardTimeAsync(bid.ProviderId, award);
        }
        
        // 3. Calculate total escrow required (BR-008)
        decimal totalEscrowRequired = 0;
        var awardDetails = new List<(AwardDto award, decimal escrowAmount)>();
        
        foreach (var award in request.Awards)
        {
            var bid = await _bidRepository.GetByIdAsync(award.BidId);
            var snapshot = await _bidRepository.GetSnapshotAsync(award.LineItemId, award.BidId);
            
            var lineItem = await _rfqRepository.GetLineItemByIdAsync(award.LineItemId);
            var escrowMultiplier = await GetEscrowMultiplierAsync(lineItem.ContractPeriod);
            var escrowAmount = award.QuantityAwarded * snapshot.UnitPrice * escrowMultiplier;
            
            totalEscrowRequired += escrowAmount;
            awardDetails.Add((award, escrowAmount));
        }
        
        // 4. WALLET VALIDATION - CRITICAL (BR-006, BR-007)
        var wallet = await _walletService.GetBusinessWalletAsync(request.BusinessId);
        var availableBalance = wallet.Balance - wallet.LockedBalance;
        
        if (availableBalance < totalEscrowRequired)
        {
            // Calculate max affordable quantity (BR-007)
            var maxAffordable = await CalculateMaxAffordableQuantityAsync(
                request.Awards, 
                availableBalance
            );
            
            throw new InsufficientFundsException(new
            {
                Required = totalEscrowRequired,
                Available = availableBalance,
                Shortfall = totalEscrowRequired - availableBalance,
                MaxAffordableQuantity = maxAffordable.Quantity,
                MaxAffordableVehicles = maxAffordable.VehicleCount,
                Message = $"Your balance is sufficient for {maxAffordable.VehicleCount} vehicles out of {request.Awards.Sum(a => a.QuantityAwarded)} requested.",
                Options = new[]
                {
                    new { Action = "DEPOSIT", Amount = totalEscrowRequired - availableBalance, Text = $"Deposit ETB {totalEscrowRequired - availableBalance:N2} to award all vehicles" },
                    new { Action = "PARTIAL_AWARD", Quantity = maxAffordable.VehicleCount, Text = $"Award {maxAffordable.VehicleCount} vehicles with current balance" },
                    new { Action = "CANCEL", Text = "Cancel award" }
                }
            });
        }
        
        // 5. Create awards
        var awardIds = new List<Guid>();
        
        foreach (var awardDto in request.Awards)
        {
            var bid = await _bidRepository.GetByIdAsync(awardDto.BidId);
            var snapshot = await _bidRepository.GetSnapshotAsync(awardDto.LineItemId, awardDto.BidId);
            
            var award = new RFQBidAward
            {
                Id = Guid.NewGuid(),
                RFQLineItemId = awardDto.LineItemId,
                RFQBidId = awardDto.BidId,
                ProviderId = bid.ProviderId, // NOW REVEALED
                QuantityAwarded = awardDto.QuantityAwarded,
                UnitPrice = snapshot.UnitPrice,
                TotalAmount = awardDto.QuantityAwarded * snapshot.UnitPrice,
                AwardedAt = DateTime.UtcNow
            };
            
            await _bidRepository.AddAwardAsync(award);
            awardIds.Add(award.Id);
            
            // 5. Publish event for each award (Contracts & Finance modules listen)
            await _mediator.Publish(new BidAwardedEvent
            {
                AwardId = award.Id,
                RFQId = request.RFQId,
                LineItemId = awardDto.LineItemId,
                BidId = awardDto.BidId,
                ProviderId = bid.ProviderId,
                BusinessId = request.BusinessId,
                QuantityAwarded = award.QuantityAwarded,
                UnitPrice = award.UnitPrice,
                TotalAmount = award.TotalAmount,
                EscrowAmount = award.TotalAmount * 1.0m // 100% escrow
            });
        }
        
        // 6. Update RFQ status
        rfq.Status = RFQStatus.Awarded;
        await _rfqRepository.UpdateAsync(rfq);
        
        return awardIds;
    }
    
    // PRE-BID VALIDATION (BR-004)
    private async Task ValidateProviderEligibilityAsync(
        Guid providerId, 
        List<BidLineItemDto> bidItems, 
        RFQ rfq)
    {
        // 1. Provider account status check
        var provider = await _identityService.GetProviderAsync(providerId);
        
        if (provider.Status != ProviderStatus.VERIFIED)
            throw new BusinessException(\"Provider account must be VERIFIED to submit bids\");
        
        // 2. Vehicle availability check
        var providerVehicles = await _identityService.GetActiveVehiclesAsync(providerId);
        
        foreach (var bidItem in bidItems)
        {
            var lineItem = await _rfqRepository.GetLineItemByIdAsync(bidItem.LineItemId);
            
            // Match vehicles by type and check availability through delivery date
            var matchingVehicles = providerVehicles.Count(v => 
                v.VehicleTypeCode == lineItem.VehicleTypeCode &&
                v.Status == VehicleStatus.Active &&
                v.IsUnassigned == true
            );
            
            // Note: Provider can bid for more than they currently have
            // Business may choose to split awards or award partial quantities
            if (matchingVehicles == 0)
            {
                throw new BusinessException(\n                    $\"No active and unassigned vehicles of type {lineItem.VehicleTypeCode}. \" +\n                    \"At least 1 matching vehicle is required to bid.\"\n                );\n            }\n        }\n        \n        // 3. Insurance validity check\n        foreach (var bidItem in bidItems)\n        {
            var lineItem = await _rfqRepository.GetLineItemByIdAsync(bidItem.LineItemId);\n            var matchingVehicles = providerVehicles.Where(v => \n                v.VehicleTypeCode == lineItem.VehicleTypeCode\n            );\n            \n            var deliveryDate = rfq.StartDate;\n            var requiredCoverageEndDate = deliveryDate.AddDays(30); // +30 days buffer\n            \n            var validInsuredVehicles = matchingVehicles.Count(v =>\n                v.Insurance != null &&\n                v.Insurance.Status == InsuranceStatus.Active &&\n                v.Insurance.CoverageEndDate >= requiredCoverageEndDate\n            );\n            \n            if (validInsuredVehicles == 0)\n            {\n                throw new BusinessException(\n                    $\"All vehicles for {lineItem.VehicleTypeCode} must have valid insurance \" +\n                    $\"through {requiredCoverageEndDate:yyyy-MM-dd}\"\n                );\n            }\n        }\n        \n        // 4. Trust score check (if configured)\n        var minTrustScore = await _settingsService.GetSettingAsync<int?>(\"min.trust.score.for.bidding\");\n        if (minTrustScore.HasValue && provider.TrustScore < minTrustScore.Value)\n        {\n            throw new BusinessException(\n                $\"Minimum trust score of {minTrustScore.Value} required to bid. \" +\n                $\"Current score: {provider.TrustScore}\"\n            );\n        }\n    }\n    \n    // RE-VALIDATION AT AWARD TIME (BR-009)\n    private async Task ValidateProviderAtAwardTimeAsync(Guid providerId, AwardDto award)\n    {\n        var provider = await _identityService.GetProviderAsync(providerId);\n        \n        if (provider.Status != ProviderStatus.VERIFIED)\n        {\n            throw new BusinessException(\n                $\"Provider {provider.Name} is no longer verified. Cannot award bid.\"\n            );\n        }\n        \n        // Check vehicles still available\n        var vehicles = await _identityService.GetActiveVehiclesAsync(providerId);\n        var lineItem = await _rfqRepository.GetLineItemByIdAsync(award.LineItemId);\n        \n        var availableVehicles = vehicles.Count(v => \n            v.VehicleTypeCode == lineItem.VehicleTypeCode &&\n            v.Status == VehicleStatus.Active &&\n            v.IsUnassigned == true\n        );\n        \n        if (availableVehicles < award.QuantityAwarded)\n        {\n            throw new BusinessException(\n                $\"Provider {provider.Name} no longer has {award.QuantityAwarded} available vehicles. \" +\n                $\"Currently available: {availableVehicles}\"\n            );\n        }\n    }\n    \n    // PARTIAL AWARD CALCULATION (BR-007)\n    private async Task<(int Quantity, int VehicleCount)> CalculateMaxAffordableQuantityAsync(\n        List<AwardDto> awards, \n        decimal availableBalance)\n    {\n        decimal runningTotal = 0;\n        int affordableVehicles = 0;\n        \n        // Sort awards by unit price (lowest first) to maximize vehicle count\n        var sortedAwards = new List<(AwardDto award, decimal unitPrice, decimal escrowMultiplier)>();\n        \n        foreach (var award in awards)\n        {\n            var snapshot = await _bidRepository.GetSnapshotAsync(award.LineItemId, award.BidId);\n            var lineItem = await _rfqRepository.GetLineItemByIdAsync(award.LineItemId);\n            var escrowMultiplier = await GetEscrowMultiplierAsync(lineItem.ContractPeriod);\n            \n            sortedAwards.Add((award, snapshot.UnitPrice, escrowMultiplier));\n        }\n        \n        sortedAwards = sortedAwards.OrderBy(a => a.unitPrice).ToList();\n        \n        // Calculate how many vehicles can be afforded\n        foreach (var (award, unitPrice, escrowMultiplier) in sortedAwards)\n        {\n            var costPerVehicle = unitPrice * escrowMultiplier;\n            var affordableFromThisAward = (int)Math.Floor((availableBalance - runningTotal) / costPerVehicle);\n            \n            var actuallyAffordable = Math.Min(affordableFromThisAward, award.QuantityAwarded);\n            \n            affordableVehicles += actuallyAffordable;\n            runningTotal += actuallyAffordable * costPerVehicle;\n            \n            if (runningTotal >= availableBalance)\n                break;\n        }\n        \n        return (affordableVehicles, affordableVehicles);\n    }\n    \n    private async Task<decimal> GetEscrowMultiplierAsync(string contractPeriod)\n    {\n        // Get from settings or use defaults\n        return contractPeriod switch\n        {\n            \"MONTH\" => 1.0m,   // 100% for monthly\n            \"EVENT\" => 1.0m,   // 100% for events\n            \"WEEK\" => 0.25m,   // 25% for weekly (if supported)\n            _ => 1.0m\n        };\n    }
}
```

---

### 5. Price Validation

```csharp
// Service Interface
public interface IPriceValidator
{
    Task<bool> ValidatePriceAsync(string vehicleTypeCode, decimal unitPrice);
    Task<MarketPriceRange> GetMarketPriceRangeAsync(string vehicleTypeCode);
}

// Implementation
public class PriceValidator : IPriceValidator
{
    private readonly IMarketPriceService _marketPriceService;
    
    public async Task<bool> ValidatePriceAsync(string vehicleTypeCode, decimal unitPrice)
    {
        var range = await GetMarketPriceRangeAsync(vehicleTypeCode);
        
        // Floor: 50% of market average
        // Ceiling: 200% of market average
        return unitPrice >= range.Floor && unitPrice <= range.Ceiling;
    }
    
    public async Task<MarketPriceRange> GetMarketPriceRangeAsync(string vehicleTypeCode)
    {
        // Get average price from last 30 days of contracts
        var marketAverage = await _marketPriceService.GetAveragePriceAsync(
            vehicleTypeCode,
            DateTime.UtcNow.AddDays(-30),
            DateTime.UtcNow
        );
        
        if (marketAverage == 0)
        {
            // No market data - use default ranges
            marketAverage = GetDefaultPrice(vehicleTypeCode);
        }
        
        return new MarketPriceRange
        {
            VehicleTypeCode = vehicleTypeCode,
            Average = marketAverage,
            Floor = marketAverage * 0.5m,
            Ceiling = marketAverage * 2.0m
        };
    }
    
    private decimal GetDefaultPrice(string vehicleTypeCode)
    {
        // Default prices for common vehicle types
        return vehicleTypeCode switch
        {
            "EV_SEDAN" => 3500m,
            "SEDAN" => 3000m,
            "SUV" => 4500m,
            "MINIBUS_12" => 8000m,
            "BUS_30" => 15000m,
            _ => 5000m
        };
    }
}
```

---

## 📡 Events Published

### RFQPublishedEvent
```csharp
public class RFQPublishedEvent : INotification
{
    public Guid RFQId { get; set; }
    public Guid BusinessId { get; set; }
    public string Title { get; set; }
    public DateTime BidDeadline { get; set; }
    public List<object> LineItems { get; set; }
}
```

### BidAwardedEvent
```csharp
public class BidAwardedEvent : INotification
{
    public Guid AwardId { get; set; }
    public Guid RFQId { get; set; }
    public Guid LineItemId { get; set; }
    public Guid BidId { get; set; }
    public Guid ProviderId { get; set; }
    public Guid BusinessId { get; set; }
    public int QuantityAwarded { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal TotalAmount { get; set; }
    public decimal EscrowAmount { get; set; }
}
```

---

## 📡 Events Consumed

### BusinessVerifiedEvent
```csharp
// From Identity Module
public class BusinessVerifiedEventHandler : INotificationHandler<BusinessVerifiedEvent>
{
    public async Task Handle(BusinessVerifiedEvent notification, CancellationToken cancellationToken)
    {
        // Business can now create RFQs
        // No action needed in Marketplace module
    }
}
```

### ProviderVerifiedEvent
```csharp
// From Identity Module
public class ProviderVerifiedEventHandler : INotificationHandler<ProviderVerifiedEvent>
{
    public async Task Handle(ProviderVerifiedEvent notification, CancellationToken cancellationToken)
    {
        // Provider can now bid on RFQs
        // No action needed in Marketplace module
    }
}
```

---

## ✅ Business Rules

1. **RFQ Creation:** No wallet balance required ✅
2. **Award:** Wallet balance REQUIRED ⚠️
3. **Partial Awards:** Fully supported based on available funds
4. **Bid Deadline:** Minimum 24 hours from publication
5. **Start Date:** Minimum 3 days from publication
6. **Max Vehicles:** 50 vehicles per RFQ
7. **Blind Bidding:** Provider identity hashed until award
8. **Price Validation:**
   - Floor: 50% of market average
   - Ceiling: 200% of market average
9. **Market Price:** Calculated from last 30 days
10. **Split Awards:** Multiple providers per line item allowed
11. **Insurance Check:** All bid vehicles must have valid insurance
12. **Vehicle Availability:** Provider must have enough active vehicles

---

**Next Module:** [Contracts_Module.md](./Contracts_Module.md)
