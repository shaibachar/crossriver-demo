using Observability;

var builder = WebApplication.CreateBuilder(args);
builder.AddDemoServiceDefaults("webhook-ingest");

var app = builder.Build();
app.UseDemoServiceDefaults();

app.MapPost("/webhooks/crossriver/lending", async (HttpRequest request) =>
{
    using var reader = new StreamReader(request.Body);
    var payload = await reader.ReadToEndAsync();
    return Results.Accepted(value: new
    {
        status = "accepted",
        source = "mock-webhook-ingest",
        bytes = payload.Length
    });
});

app.Run();
