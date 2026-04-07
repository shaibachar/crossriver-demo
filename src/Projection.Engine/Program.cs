using Observability;
using SharedKernel;

var builder = WebApplication.CreateBuilder(args);
builder.AddDemoServiceDefaults("projection-engine");

var app = builder.Build();
app.UseDemoServiceDefaults();

app.MapPost("/internal/projections", (ProjectionRequest request) =>
{
    var now = DateTimeOffset.UtcNow;
    var timeline = new List<ProjectedEvent>
    {
        new("application.validated", now, SimulationSources.ValidatedByCrossRiver, "high", new Dictionary<string, string>
        {
            ["validationStatus"] = request.DryRunResponse.ValidationStatus
        })
    };

    var statuses = new List<ProjectedStatus>
    {
        new(request.DryRunResponse.IsApproved ? "validated" : "manual_review", SimulationSources.ValidatedByCrossRiver, "high")
    };

    var rails = new List<ProjectedRailOutcome>();
    var warnings = new List<string>();
    var notes = request.DryRunResponse.Rules
        .Select(rule => new ExplainabilityNote(rule.RuleName, rule.Message, rule.Passed ? SimulationSources.ValidatedByCrossRiver : SimulationSources.ProjectedByEngine))
        .ToList();

    var decision = request.DryRunResponse.IsApproved ? "approve" : "manual_review";

    if (!request.DryRunResponse.IsApproved)
    {
        timeline.Add(new("application.rejected", now.AddSeconds(1), SimulationSources.ProjectedByEngine, "medium", new Dictionary<string, string>
        {
            ["reason"] = "dry-run failed one or more rules"
        }));
    }
    else
    {
        timeline.Add(new("loan.created", now.AddSeconds(2), SimulationSources.ProjectedByEngine, "medium", new Dictionary<string, string>
        {
            ["mode"] = request.Mode
        }));

        var preferredRail = request.LoanIntent.FundingPlan.PreferredRails.FirstOrDefault() ?? "ACH";
        var fundingTime = preferredRail.Equals("ACH", StringComparison.OrdinalIgnoreCase)
            ? now.AddHours(4)
            : now.AddMinutes(2);

        var railOutcome = request.Mode.ToLowerInvariant() switch
        {
            "ach_return" => "ACH fails after initiation",
            "fallback_to_rtp" => "ACH unavailable, RTP fallback succeeds",
            "delayed_funding" => $"{preferredRail} delayed to next business window",
            _ => $"{preferredRail} succeeds"
        };

        rails.Add(new ProjectedRailOutcome(preferredRail, railOutcome, SimulationSources.ProjectedByEngine, "medium", fundingTime));
        timeline.Add(new("funding.projected", fundingTime, SimulationSources.ProjectedByEngine, "medium", new Dictionary<string, string>
        {
            ["rail"] = preferredRail,
            ["outcome"] = railOutcome
        }));

        statuses.Add(new("projected_funding", SimulationSources.ProjectedByEngine, "medium"));
        if (preferredRail.Equals("ACH", StringComparison.OrdinalIgnoreCase))
        {
            warnings.Add("ACH may shift to next business window if submitted after cutoff.");
        }
    }

    foreach (var missingItem in request.BorrowerSnapshot.MissingItems)
    {
        warnings.Add($"Borrower readiness is missing {missingItem}.");
    }

    return Results.Ok(new SimulationResult(
        request.ScenarioId,
        decision,
        request.DryRunResponse.ValidationStatus,
        statuses,
        rails,
        timeline,
        warnings,
        notes));
});

app.Run();
