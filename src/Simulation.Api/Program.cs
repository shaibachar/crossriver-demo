using System.Collections.Concurrent;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Observability;
using Simulation.Api.Infrastructure;
using SharedKernel;

var builder = WebApplication.CreateBuilder(args);
builder.AddDemoServiceDefaults("simulation-api");
builder.Services.AddSingleton<SimulationScenarioStore>();
builder.Services.AddDbContext<SimulationDbContext>(options =>
{
    options.UseNpgsql(builder.Configuration.GetConnectionString("Postgres")
        ?? "Host=localhost;Port=5432;Database=simulation;Username=postgres;Password=postgres");
});
builder.Services.AddHttpClient("crossriver", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:CrossRiverAdapter"] ?? "http://localhost:5101");
    client.DefaultRequestHeaders.Add("X-Api-Key", builder.Configuration["Auth:ApiKey"] ?? "demo-api-key");
});
builder.Services.AddHttpClient("projection", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:ProjectionEngine"] ?? "http://localhost:5102");
    client.DefaultRequestHeaders.Add("X-Api-Key", builder.Configuration["Auth:ApiKey"] ?? "demo-api-key");
});
builder.Services.AddHttpClient("execution", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:ExecutionService"] ?? "http://localhost:5103");
    client.DefaultRequestHeaders.Add("X-Api-Key", builder.Configuration["Auth:ApiKey"] ?? "demo-api-key");
});

var app = builder.Build();
app.UseDemoServiceDefaults();

app.MapPost("/simulation-scenarios", async (
    CreateSimulationScenarioRequest request,
    SimulationScenarioStore store,
    SimulationDbContext dbContext,
    IHttpClientFactory httpClientFactory,
    CancellationToken cancellationToken) =>
{
    var scenarioId = Guid.NewGuid();
    MetricsSnapshot.IncrementSimulationCreated();

    var borrowerSnapshot = BuildBorrowerSnapshot(request.Borrower, request.LoanIntent);
    var dryRun = await httpClientFactory.CreateClient("crossriver")
        .PostAsJsonAsync("/internal/crossriver/preapproval/dryrun", new CrossRiverDryRunRequest(
            scenarioId,
            request.PartnerSchemaId,
            request.Borrower,
            request.LoanIntent,
            request.Mode), cancellationToken);
    dryRun.EnsureSuccessStatusCode();
    var dryRunResponse = await dryRun.Content.ReadFromJsonAsync<CrossRiverDryRunResponse>(cancellationToken)
        ?? throw new InvalidOperationException("Cross River dry-run returned no body.");

    var projection = await httpClientFactory.CreateClient("projection")
        .PostAsJsonAsync("/internal/projections", new ProjectionRequest(
            scenarioId,
            request.Mode,
            request.LoanIntent,
            borrowerSnapshot,
            dryRunResponse), cancellationToken);
    projection.EnsureSuccessStatusCode();
    var result = await projection.Content.ReadFromJsonAsync<SimulationResult>(cancellationToken)
        ?? throw new InvalidOperationException("Projection Engine returned no body.");

    var scenario = new StoredSimulationScenario(
        scenarioId,
        request.TenantId,
        request.PartnerSchemaId,
        "projected",
        request.Mode,
        DateTimeOffset.UtcNow,
        null,
        null,
        request,
        borrowerSnapshot,
        result);

    store.Upsert(scenario);
    dbContext.SimulationScenarios.Add(new SimulationScenarioRecord
    {
        Id = scenario.Id,
        TenantId = scenario.TenantId,
        PartnerSchemaId = scenario.PartnerSchemaId,
        Status = scenario.Status,
        Mode = scenario.Mode,
        CreatedAtUtc = scenario.CreatedAtUtc,
        ExecutedAtUtc = scenario.ExecutedAtUtc,
        RealLoanId = scenario.RealLoanId
    });
    await dbContext.SaveChangesAsync(cancellationToken);

    dbContext.SimulationResults.Add(new SimulationResultRecord
    {
        Id = Guid.NewGuid(),
        ScenarioId = scenario.Id,
        ResultJson = JsonSerializer.Serialize(result),
        CreatedAtUtc = DateTimeOffset.UtcNow
    });
    await dbContext.SaveChangesAsync(cancellationToken);
    MetricsSnapshot.IncrementSimulationCompleted();
    return Results.Created($"/simulation-scenarios/{scenarioId}", result);
});

app.MapGet("/simulation-scenarios/{id:guid}", (Guid id, SimulationScenarioStore store) =>
{
    return store.TryGet(id, out var scenario)
        ? Results.Ok(ToDto(scenario))
        : Results.NotFound();
});

app.MapGet("/simulation-scenarios/{id:guid}/timeline", (Guid id, SimulationScenarioStore store) =>
{
    return store.TryGet(id, out var scenario)
        ? Results.Ok(scenario.Result.Timeline)
        : Results.NotFound();
});

app.MapPost("/simulation-scenarios/{id:guid}/execute", async (
    Guid id,
    SimulationScenarioStore store,
    SimulationDbContext dbContext,
    IHttpClientFactory httpClientFactory,
    CancellationToken cancellationToken) =>
{
    if (!store.TryGet(id, out var scenario))
    {
        return Results.NotFound();
    }

    var response = await httpClientFactory.CreateClient("execution")
        .PostAsJsonAsync("/internal/executions", ToDto(scenario), cancellationToken);
    response.EnsureSuccessStatusCode();
    var execution = await response.Content.ReadFromJsonAsync<ExecuteSimulationResponse>(cancellationToken)
        ?? throw new InvalidOperationException("Execution Service returned no body.");

    var executedScenario = scenario with
    {
        Status = "executed",
        ExecutedAtUtc = DateTimeOffset.UtcNow,
        RealLoanId = execution.RealLoanId
    };
    store.Upsert(executedScenario);

    var scenarioRecord = await dbContext.SimulationScenarios.FindAsync([id], cancellationToken);
    if (scenarioRecord is not null)
    {
        scenarioRecord.Status = executedScenario.Status;
        scenarioRecord.ExecutedAtUtc = executedScenario.ExecutedAtUtc;
        scenarioRecord.RealLoanId = executedScenario.RealLoanId;
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    return Results.Ok(execution);
});

app.MapPost("/simulation-scenarios/{id:guid}/replay", (Guid id, SimulationScenarioStore store) =>
{
    return store.TryGet(id, out var scenario)
        ? Results.Ok(scenario.Result)
        : Results.NotFound();
});

app.MapGet("/simulation-scenarios/{id:guid}/comparison", (Guid id, SimulationScenarioStore store) =>
{
    if (!store.TryGet(id, out var scenario))
    {
        return Results.NotFound();
    }

    var report = new ComparisonReport(
        scenario.Id,
        scenario.RealLoanId,
        StatusMatch: true,
        RailMatch: scenario.Result.ProjectedRails.All(rail => rail.Outcome.Contains("succeeds", StringComparison.OrdinalIgnoreCase)),
        TimingDeltaSeconds: 0,
        UnexpectedEvents: [],
        Notes: ["Mock comparison uses projected happy-path outcomes until real webhooks are ingested."]);

    return Results.Ok(report);
});

app.Run();

static BorrowerSnapshot BuildBorrowerSnapshot(BorrowerRequest borrower, LoanIntent loanIntent)
{
    var missing = new List<string>();
    if (string.IsNullOrWhiteSpace(borrower.Email)) missing.Add("email");
    if (string.IsNullOrWhiteSpace(borrower.Phone)) missing.Add("phone");
    if (string.IsNullOrWhiteSpace(borrower.AddressLine1)) missing.Add("address");
    if (string.IsNullOrWhiteSpace(borrower.IdentificationLast4)) missing.Add("identification");
    if (string.IsNullOrWhiteSpace(loanIntent.FundingPlan.DestinationAccountRef)) missing.Add("destinationAccountRef");

    return new BorrowerSnapshot(
        borrower.CustomerId,
        !string.IsNullOrWhiteSpace(borrower.Email),
        !string.IsNullOrWhiteSpace(borrower.Phone),
        !string.IsNullOrWhiteSpace(borrower.AddressLine1),
        !string.IsNullOrWhiteSpace(borrower.IdentificationLast4),
        !string.IsNullOrWhiteSpace(loanIntent.FundingPlan.DestinationAccountRef),
        missing);
}

static SimulationScenarioDto ToDto(StoredSimulationScenario scenario)
{
    return new SimulationScenarioDto(
        scenario.Id,
        scenario.TenantId,
        scenario.PartnerSchemaId,
        scenario.Status,
        scenario.Mode,
        scenario.CreatedAtUtc,
        scenario.ExecutedAtUtc,
        scenario.RealLoanId,
        scenario.Result);
}

public sealed record StoredSimulationScenario(
    Guid Id,
    string TenantId,
    string PartnerSchemaId,
    string Status,
    string Mode,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? ExecutedAtUtc,
    string? RealLoanId,
    CreateSimulationScenarioRequest Request,
    BorrowerSnapshot BorrowerSnapshot,
    SimulationResult Result);

public sealed class SimulationScenarioStore
{
    private readonly ConcurrentDictionary<Guid, StoredSimulationScenario> _scenarios = new();

    public void Upsert(StoredSimulationScenario scenario) => _scenarios[scenario.Id] = scenario;

    public bool TryGet(Guid id, out StoredSimulationScenario scenario) => _scenarios.TryGetValue(id, out scenario!);
}
