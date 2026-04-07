using Observability;
using SharedKernel;

var builder = WebApplication.CreateBuilder(args);
builder.AddDemoServiceDefaults("audit-comparison");

var app = builder.Build();
app.UseDemoServiceDefaults();

app.MapPost("/internal/comparisons", (SimulationScenarioDto scenario) =>
{
    var report = new ComparisonReport(
        scenario.Id,
        scenario.RealLoanId,
        StatusMatch: true,
        RailMatch: true,
        TimingDeltaSeconds: 0,
        UnexpectedEvents: [],
        Notes: ["Audit comparison is stubbed until persisted actual events are wired."]);

    return Results.Ok(report);
});

app.Run();
