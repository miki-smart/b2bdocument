# Testing Strategy

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Frameworks:** xUnit, Moq, Testcontainers, Playwright

---

## 📋 Overview

The Movello MVP employs a **Testing Pyramid** approach, prioritizing fast, reliable unit tests while ensuring critical user flows are covered by integration and end-to-end (E2E) tests.

### Testing Levels
1.  **Unit Tests (70%):** Isolated logic (Domain entities, Services, Validators).
2.  **Integration Tests (20%):** Module interactions, Database queries, API endpoints.
3.  **E2E Tests (10%):** Critical user journeys (Login → RFQ → Bid → Award).

---

## 🧪 Unit Testing (Backend)

**Tools:** xUnit, FluentAssertions, Moq

### Scope
- **Domain Entities:** Validate invariants (e.g., "Cannot award more than requested").
- **Value Objects:** Equality checks, formatting.
- **Application Handlers:** Verify flow logic, mocking repositories.
- **Validators:** Ensure FluentValidation rules work.

### Example: Domain Test
```csharp
[Fact]
public void CalculateTrustScore_ShouldCapAt100()
{
    // Arrange
    var calculator = new TrustScoreCalculator();
    var metrics = new ProviderMetrics { /* perfect scores */ };

    // Act
    var score = calculator.Calculate(metrics);

    // Assert
    score.Should().Be(100);
}
```

---

## 🔗 Integration Testing (Backend)

**Tools:** xUnit, Testcontainers (PostgreSQL, Redis), WebApplicationFactory

### Scope
- **API Endpoints:** Request/Response validation.
- **Database:** Real SQL queries against a containerized DB.
- **Event Handlers:** Verify MediatR events trigger correct side effects.

### Example: API Test with Testcontainers
```csharp
public class RfqIntegrationTests : IClassFixture<MovelloFactory>
{
    private readonly HttpClient _client;

    public RfqIntegrationTests(MovelloFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task CreateRFQ_ShouldReturnCreated()
    {
        // Arrange
        var command = new CreateRFQCommand { /* ... */ };

        // Act
        var response = await _client.PostAsJsonAsync("/api/v1/rfqs", command);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Created);
    }
}
```

---

## 🎭 E2E Testing (Frontend + Backend)

**Tools:** Playwright

### Scope
- **Critical Paths:**
  1.  Business Registration & KYB
  2.  Provider Registration & KYC
  3.  Create RFQ (Business)
  4.  Submit Bid (Provider)
  5.  Award Bid (Business)
  6.  Delivery Handover (OTP Flow)

### Example: Playwright Test
```typescript
test('Business can create RFQ', async ({ page }) => {
  await page.goto('/auth/login');
  await page.fill('#email', 'business@movello.et');
  await page.fill('#password', 'password');
  await page.click('button[type="submit"]');

  await page.click('text=Create RFQ');
  await page.fill('#title', 'Test RFQ');
  await page.click('button:has-text("Publish")');

  await expect(page.locator('.toast-success')).toBeVisible();
});
```

---

## 📊 Test Data Management

### Seed Data
- **Master Data:** Lookups, Settings, Tiers (loaded on startup).
- **Test Scenarios:** "Golden" users (Admin, Verified Business, Verified Provider) created via seed scripts for E2E tests.

### Cleanup
- **Unit/Integration:** Transaction rollback or container disposal.
- **E2E:** Database reset script runs before test suite.

---

## 🚦 CI/CD Integration

- **Pull Requests:** Run Unit Tests (Must pass).
- **Merge to Main:** Run Unit + Integration Tests.
- **Nightly:** Run E2E Tests (Long running).

---

**Next Document:** [Business_Rules.md](./Business_Rules.md)
