using Observability;
using SharedKernel;

var builder = WebApplication.CreateBuilder(args);
builder.AddDemoServiceDefaults("execution-service");
builder.Services.AddHttpClient("crossriver", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:CrossRiverAdapter"] ?? "http://localhost:5101");
    client.DefaultRequestHeaders.Add("X-Api-Key", builder.Configuration["Auth:ApiKey"] ?? "demo-api-key");
});

var app = builder.Build();
app.UseDemoServiceDefaults();

app.MapPost("/internal/executions", async (
    SimulationScenarioDto scenario,
    IHttpClientFactory httpClientFactory,
    CancellationToken cancellationToken) =>
{
    if (!scenario.Status.Equals("projected", StringComparison.OrdinalIgnoreCase))
    {
        return Results.BadRequest(new { error = "Only projected simulations can be executed." });
    }

    if (scenario.Result is null || !scenario.Result.ProjectedDecision.Equals("approve", StringComparison.OrdinalIgnoreCase))
    {
        return Results.BadRequest(new { error = "Only approved simulations can be executed." });
    }

    var client = httpClientFactory.CreateClient("crossriver");
    var createLoan = await client.PostAsJsonAsync("/internal/crossriver/loans", scenario, cancellationToken);
    createLoan.EnsureSuccessStatusCode();

    var realLoanId = $"mock-loan-{scenario.Id:N}"[..22];
    var funding = await client.PutAsJsonAsync($"/internal/crossriver/loans/{realLoanId}/funding-info", new { scenario.Id }, cancellationToken);
    funding.EnsureSuccessStatusCode();

    return Results.Ok(new ExecuteSimulationResponse(scenario.Id, "started", realLoanId));
});

app.Run();
