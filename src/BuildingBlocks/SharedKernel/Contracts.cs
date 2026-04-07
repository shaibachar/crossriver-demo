using System.Text.Json;

namespace SharedKernel;

public static class SimulationSources
{
    public const string ValidatedByCrossRiver = "validated_by_crossriver";
    public const string ProjectedByEngine = "projected_by_engine";
    public const string ActualFromCrossRiver = "actual_from_crossriver";
}

public sealed record CreateSimulationScenarioRequest(
    string TenantId,
    string PartnerSchemaId,
    string Mode,
    BorrowerRequest Borrower,
    LoanIntent LoanIntent);

public sealed record BorrowerRequest(
    string? CustomerId,
    string? FirstName,
    string? LastName,
    string? Email,
    string? Phone,
    string? AddressLine1 = null,
    string? IdentificationLast4 = null);

public sealed record LoanIntent(
    decimal RequestedAmount,
    int TermMonths,
    decimal? Rate,
    string ProductType,
    string Currency,
    FundingPlan FundingPlan);

public sealed record FundingPlan(
    IReadOnlyList<string> PreferredRails,
    string? DestinationAccountRef,
    bool AllowFallbackRail);

public sealed record BorrowerSnapshot(
    string? CustomerId,
    bool HasEmail,
    bool HasPhone,
    bool HasAddress,
    bool HasIdentification,
    bool AccountReady,
    IReadOnlyList<string> MissingItems);

public sealed record SimulationScenarioDto(
    Guid Id,
    string TenantId,
    string PartnerSchemaId,
    string Status,
    string Mode,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? ExecutedAtUtc,
    string? RealLoanId,
    SimulationResult? Result);

public sealed record SimulationResult(
    Guid ScenarioId,
    string ProjectedDecision,
    string ValidationStatus,
    IReadOnlyList<ProjectedStatus> ProjectedStatuses,
    IReadOnlyList<ProjectedRailOutcome> ProjectedRails,
    IReadOnlyList<ProjectedEvent> Timeline,
    IReadOnlyList<string> Warnings,
    IReadOnlyList<ExplainabilityNote> Explainability);

public sealed record ProjectedStatus(string Name, string Source, string Confidence);

public sealed record ProjectedRailOutcome(
    string Rail,
    string Outcome,
    string Source,
    string Confidence,
    DateTimeOffset EstimatedAtUtc);

public sealed record ProjectedEvent(
    string EventType,
    DateTimeOffset EstimatedAtUtc,
    string Source,
    string Confidence,
    IReadOnlyDictionary<string, string> Metadata);

public sealed record ExplainabilityNote(string Code, string Message, string Source);

public sealed record CrossRiverDryRunRequest(
    Guid ScenarioId,
    string PartnerSchemaId,
    BorrowerRequest Borrower,
    LoanIntent LoanIntent,
    string Mode);

public sealed record CrossRiverDryRunResponse(
    bool IsApproved,
    string ValidationStatus,
    IReadOnlyList<CrossRiverRuleResult> Rules,
    JsonElement RawResponse);

public sealed record CrossRiverRuleResult(string RuleName, bool Passed, string Message);

public sealed record ProjectionRequest(
    Guid ScenarioId,
    string Mode,
    LoanIntent LoanIntent,
    BorrowerSnapshot BorrowerSnapshot,
    CrossRiverDryRunResponse DryRunResponse);

public sealed record ExecuteSimulationResponse(Guid ScenarioId, string ExecutionStatus, string RealLoanId);

public sealed record ComparisonReport(
    Guid ScenarioId,
    string? RealLoanId,
    bool StatusMatch,
    bool RailMatch,
    int TimingDeltaSeconds,
    IReadOnlyList<string> UnexpectedEvents,
    IReadOnlyList<string> Notes);
