using System.Text.Json;
using Observability;
using SharedKernel;

var builder = WebApplication.CreateBuilder(args);
builder.AddDemoServiceDefaults("crossriver-adapter");

var app = builder.Build();
app.UseDemoServiceDefaults();

app.MapPost("/internal/crossriver/preapproval/dryrun", (CrossRiverDryRunRequest request) =>
{
    var failedRules = new List<CrossRiverRuleResult>();

    if (request.Mode.Equals("validation_failure", StringComparison.OrdinalIgnoreCase))
    {
        failedRules.Add(new CrossRiverRuleResult("borrower.email.required", false, "Borrower email is required."));
    }

    if (request.LoanIntent.RequestedAmount <= 0)
    {
        failedRules.Add(new CrossRiverRuleResult("loan.amount.positive", false, "Requested amount must be greater than zero."));
    }

    if (request.LoanIntent.TermMonths <= 0)
    {
        failedRules.Add(new CrossRiverRuleResult("loan.term.positive", false, "Term must be greater than zero months."));
    }

    var rules = new List<CrossRiverRuleResult>
    {
        new("partner.schema.accepted", true, "Partner schema payload shape is accepted."),
        new("loan.product.supported", true, "Loan product is supported in the mock sandbox.")
    };
    rules.AddRange(failedRules);

    var approved = failedRules.Count == 0;
    var raw = JsonSerializer.SerializeToElement(new
    {
        source = "mock-crossriver",
        request.PartnerSchemaId,
        approved,
        decision = approved ? "approve" : "manual_review",
        generatedAtUtc = DateTimeOffset.UtcNow
    });

    return Results.Ok(new CrossRiverDryRunResponse(
        approved,
        approved ? "validated" : "failed",
        rules,
        raw));
});

app.MapPost("/internal/crossriver/loans", (SimulationScenarioDto scenario) =>
{
    return Results.Ok(new { realLoanId = $"mock-loan-{scenario.Id:N}"[..22], status = "created" });
});

app.MapPut("/internal/crossriver/loans/{id}/funding-info", (string id) =>
{
    return Results.Ok(new { realLoanId = id, fundingStatus = "configured" });
});

app.MapGet("/internal/crossriver/loans/{id}/details", (string id) =>
{
    return Results.Ok(new { realLoanId = id, loanStatus = "active", source = SimulationSources.ActualFromCrossRiver });
});

app.Run();
