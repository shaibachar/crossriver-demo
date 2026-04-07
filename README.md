# Cross River Loan Simulation Engine

Interview-demo implementation of a side-effect-free Cross River loan simulation platform.

## What Is Implemented

- Multi-project .NET 8 solution with separate service projects.
- Synchronous `POST /simulation-scenarios` happy-path flow.
- Mocked Cross River Adapter by default.
- Projection Engine with timeline, warnings, rail outcomes, and explainability notes.
- Execution Service stub that is the only service calling mock loan/funding endpoints.
- Webhook Ingest and Audit/Comparison service stubs.
- Nginx API gateway in Docker Compose.
- PostgreSQL, Redis, RabbitMQ, Prometheus, Grafana, Loki, and OpenTelemetry collector containers.
- Prometheus-compatible `/metrics`, `/health`, JSON console logs, correlation ID middleware, and demo `X-Api-Key` auth.
- Baseline PostgreSQL SQL migration at `deploy/postgres/001_init.sql`.

## Run Locally

```powershell
docker compose up --build
```

Gateway:

```text
http://localhost:8080
```

Direct service ports are exposed by `docker-compose.override.yml`:

```text
simulation-api      http://localhost:5100
crossriver-adapter  http://localhost:5101
projection-engine   http://localhost:5102
execution-service   http://localhost:5103
webhook-ingest      http://localhost:5104
audit-comparison    http://localhost:5105
```

## Happy Path Simulation

```powershell
$body = @{
  tenantId = "tenant-a"
  partnerSchemaId = "schema-123"
  mode = "happy_path"
  borrower = @{
    customerId = "cust-001"
    firstName = "Jane"
    lastName = "Doe"
    email = "jane@example.com"
    phone = "+15551234567"
    addressLine1 = "1 Main St"
    identificationLast4 = "1234"
  }
  loanIntent = @{
    requestedAmount = 5000
    termMonths = 12
    rate = 8.5
    productType = "installment"
    currency = "USD"
    fundingPlan = @{
      preferredRails = @("ACH", "RTP")
      destinationAccountRef = "ext-acct-777"
      allowFallbackRail = $true
    }
  }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
  -Method Post `
  -Uri http://localhost:8080/simulation-scenarios `
  -Headers @{ "X-Api-Key" = "demo-api-key" } `
  -ContentType "application/json" `
  -Body $body
```

## Build And Test

```powershell
dotnet restore
dotnet build CrossRiverDemo.sln
dotnet test CrossRiverDemo.sln
```

## Notes

- Real Cross River credentials are not required. The adapter returns deterministic mock responses.
- The first persistence slice is intentionally config/schema-ready but in-memory at runtime. The SQL baseline mirrors the design tables and is mounted into Postgres by Docker Compose.
- Full EF Core runtime wiring can be added after NuGet restore/package installation is available.
