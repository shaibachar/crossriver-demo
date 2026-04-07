using System.Diagnostics.Metrics;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Observability;

public static class ServiceDefaults
{
    public static readonly Meter Meter = new("CrossRiverDemo.SimulationEngine", "1.0.0");
    public static readonly Counter<long> HttpRequestsTotal = Meter.CreateCounter<long>("http_requests_total");
    public static readonly Counter<long> SimulationCreatedTotal = Meter.CreateCounter<long>("simulation_created_total");
    public static readonly Counter<long> SimulationCompletedTotal = Meter.CreateCounter<long>("simulation_completed_total");

    public static WebApplicationBuilder AddDemoServiceDefaults(this WebApplicationBuilder builder, string serviceName)
    {
        builder.Services.AddHealthChecks();
        builder.Services.AddHttpContextAccessor();
        builder.Logging.ClearProviders();
        builder.Logging.AddJsonConsole(options =>
        {
            options.IncludeScopes = true;
            options.TimestampFormat = "O";
        });
        builder.Services.AddSingleton(new ServiceMetadata(serviceName));
        return builder;
    }

    public static WebApplication UseDemoServiceDefaults(this WebApplication app)
    {
        app.UseMiddleware<CorrelationIdMiddleware>();
        app.UseMiddleware<DevApiKeyMiddleware>();
        app.MapHealthChecks("/health");
        app.MapGet("/metrics", () => Results.Text(MetricsSnapshot.Render(), "text/plain; version=0.0.4"));
        return app;
    }
}

public sealed record ServiceMetadata(string ServiceName);

public sealed class CorrelationIdMiddleware(RequestDelegate next, ILogger<CorrelationIdMiddleware> logger)
{
    private const string HeaderName = "X-Correlation-Id";

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = context.Request.Headers.TryGetValue(HeaderName, out var existing)
            ? existing.ToString()
            : Guid.NewGuid().ToString("N");

        context.Response.Headers[HeaderName] = correlationId;
        using (logger.BeginScope(new Dictionary<string, object> { ["correlationId"] = correlationId }))
        {
            await next(context);
        }
    }
}

public sealed class DevApiKeyMiddleware(RequestDelegate next, IConfiguration configuration)
{
    private static readonly PathString[] PublicPaths = ["/health", "/metrics"];

    public async Task InvokeAsync(HttpContext context)
    {
        if (PublicPaths.Any(path => context.Request.Path.StartsWithSegments(path)))
        {
            await next(context);
            return;
        }

        var expected = configuration["Auth:ApiKey"] ?? "demo-api-key";
        if (context.Request.Headers.TryGetValue("X-Api-Key", out var actual) && actual == expected)
        {
            await next(context);
            return;
        }

        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        await context.Response.WriteAsJsonAsync(new { error = "Missing or invalid X-Api-Key header." });
    }
}

public static class MetricsSnapshot
{
    private static long _simulationCreated;
    private static long _simulationCompleted;

    public static void IncrementSimulationCreated() => Interlocked.Increment(ref _simulationCreated);

    public static void IncrementSimulationCompleted() => Interlocked.Increment(ref _simulationCompleted);

    public static string Render()
    {
        return string.Join('\n',
            "# TYPE simulation_created_total counter",
            $"simulation_created_total {Volatile.Read(ref _simulationCreated)}",
            "# TYPE simulation_completed_total counter",
            $"simulation_completed_total {Volatile.Read(ref _simulationCompleted)}",
            string.Empty);
    }
}
