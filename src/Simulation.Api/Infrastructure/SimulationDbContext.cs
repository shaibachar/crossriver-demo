using Microsoft.EntityFrameworkCore;

namespace Simulation.Api.Infrastructure;

public sealed class SimulationDbContext(DbContextOptions<SimulationDbContext> options) : DbContext(options)
{
    public DbSet<SimulationScenarioRecord> SimulationScenarios => Set<SimulationScenarioRecord>();
    public DbSet<SimulationResultRecord> SimulationResults => Set<SimulationResultRecord>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<SimulationScenarioRecord>(entity =>
        {
            entity.ToTable("simulation_scenarios");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id");
            entity.Property(x => x.PartnerSchemaId).HasColumnName("partner_schema_id");
            entity.Property(x => x.Status).HasColumnName("status");
            entity.Property(x => x.Mode).HasColumnName("mode");
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc");
            entity.Property(x => x.ExecutedAtUtc).HasColumnName("executed_at_utc");
            entity.Property(x => x.RealLoanId).HasColumnName("real_loan_id");
        });

        modelBuilder.Entity<SimulationResultRecord>(entity =>
        {
            entity.ToTable("simulation_results");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.ScenarioId).HasColumnName("scenario_id");
            entity.Property(x => x.ResultJson).HasColumnName("result_json").HasColumnType("jsonb");
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc");
        });
    }
}

public sealed class SimulationScenarioRecord
{
    public Guid Id { get; set; }
    public string TenantId { get; set; } = default!;
    public string PartnerSchemaId { get; set; } = default!;
    public string Status { get; set; } = default!;
    public string Mode { get; set; } = default!;
    public DateTimeOffset CreatedAtUtc { get; set; }
    public DateTimeOffset? ExecutedAtUtc { get; set; }
    public string? RealLoanId { get; set; }
}

public sealed class SimulationResultRecord
{
    public Guid Id { get; set; }
    public Guid ScenarioId { get; set; }
    public string ResultJson { get; set; } = default!;
    public DateTimeOffset CreatedAtUtc { get; set; }
}
