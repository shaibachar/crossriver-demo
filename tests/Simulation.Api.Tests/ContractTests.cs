using SharedKernel;

namespace Simulation.Api.Tests;

public class ContractTests
{
    [Fact]
    public void HappyPathRequestCapturesFundingPlan()
    {
        var request = new CreateSimulationScenarioRequest(
            "tenant-a",
            "schema-123",
            "happy_path",
            new BorrowerRequest("cust-001", "Jane", "Doe", "jane@example.com", "+15551234567"),
            new LoanIntent(5000m, 12, 8.5m, "installment", "USD", new FundingPlan(["ACH", "RTP"], "ext-acct-777", true)));

        Assert.Equal("tenant-a", request.TenantId);
        Assert.Equal("ACH", request.LoanIntent.FundingPlan.PreferredRails[0]);
        Assert.True(request.LoanIntent.FundingPlan.AllowFallbackRail);
    }
}
