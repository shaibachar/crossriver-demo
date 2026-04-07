# Design: Cross River Loan Simulation Engine

## 1. Purpose

Build a side-effect-free **Simulation Engine** as a C# microservice platform that sits above Cross River backend APIs and lets a partner:

- validate a proposed loan application without originating it
- simulate likely funding and lifecycle outcomes
- generate projected event timelines
- compare simulated outcomes with real execution later
- expose rich metrics, structured logs, and audit trails

The design should be production-style, containerized with Docker, and split into microservices.

---

## 2. Business Goal

The platform should answer:

> "If I submit this borrower and loan request now, what is likely to happen?"

without creating a real loan during simulation mode.

This system is **not** a replacement for Cross River underwriting or origination. It is a **planning, dry-run, and explainability layer**.

---

## 3. Product Scope

### In scope

- simulation scenario creation
- borrower readiness validation
- Cross River preapproval dry-run invocation
- projected origination and funding path generation
- projected lending hook timeline generation
- execution bridge from simulation to real origination
- replay and comparison of simulated vs actual outcome
- metrics, logs, tracing, correlation IDs
- Docker-based local deployment

### Out of scope for v1

- full UI
- machine-learning underwriting
- full event sourcing platform
- complete KYC/KYB implementation
- direct replacement of Cross River decisioning

---

## 4. Architecture Overview

Use a microservice architecture with the following services:

1. **API Gateway**
   - Single entry point
   - Auth, routing, rate limiting, correlation ID injection

2. **Simulation API Service**
   - Public API for simulation scenarios
   - Scenario lifecycle and orchestration

3. **CrossRiver Adapter Service**
   - Encapsulates all calls to Cross River APIs
   - Handles auth, retries, idempotency headers, request normalization

4. **Projection Engine Service**
   - Converts Cross River dry-run results into projected status flows and funding outcomes
   - Applies internal rules for timeline and failure scenarios

5. **Execution Service**
   - Converts approved simulations into real Cross River origination calls
   - Stores linkage between scenario ID and real loan ID

6. **Webhook Ingest Service**
   - Receives real lending hooks from Cross River
   - Updates actual outcomes and drives comparison logic

7. **Audit & Comparison Service**
   - Persists requests, responses, simulated events, actual events, and diffs

8. **Observability Stack**
   - Prometheus for metrics
   - Grafana dashboards
   - Loki for logs
   - OpenTelemetry collector for traces

### Supporting infrastructure

- PostgreSQL
- Redis
- RabbitMQ
- Docker Compose

---

## 5. Why Microservices

This design is intentionally microservice-based because it demonstrates:

- bounded contexts
- operational separation
- scalable async workflows
- realistic integration architecture
- observability maturity

It also lets Codex implement services independently and cleanly.

---

## 6. Primary User Flows

### Flow A: Create simulation

1. Client sends `POST /simulation-scenarios`
2. Simulation API validates payload
3. Borrower/customer/account prechecks run if configured
4. CrossRiver Adapter calls Cross River Preapproval dry-run
5. Projection Engine builds projected statuses, rails, and timeline
6. Result is stored
7. API returns simulation result

### Flow B: Execute simulation

1. Client sends `POST /simulation-scenarios/{id}/execute`
2. Execution Service loads scenario
3. CrossRiver Adapter creates real loan
4. CrossRiver Adapter configures funding rails
5. Real identifiers are stored
6. Hook events are later ingested and compared to simulation

### Flow C: Compare simulation vs actual

1. Webhook Ingest receives real hooks
2. Audit service updates actual event history
3. Comparison job calculates divergence
4. API exposes comparison report

---

## 7. Cross River APIs to Use

### 7.1 APIs used directly during simulation

#### A. Preapproval dry-run

Use this as the core simulation call.

- `POST /api/v2/applications/{partnerSchemaId}/dryrun`

Purpose:
- validate application payload against partner schema
- return synchronous rule results
- avoid actual submission side effects

#### B. Customer management APIs

Use these optionally to simulate onboarding readiness.

- `POST /core/v1/cm/customers`
- `GET /core/v1/cm/customers/{id}`
- customer phone/email/address/identification endpoints when needed

Purpose:
- verify customer record readiness
- model missing onboarding data

#### C. Accounts / subaccounts APIs

Use optionally if simulation includes funding or repayment account readiness.

- `POST /core/v1/dda/accounts`
- `POST /core/v1/dda/subaccounts`
- `GET /core/v1/dda/subaccounts/{accountnumber}`

Purpose:
- simulate account availability
- model virtual account / subledger scenarios

### 7.2 APIs used only during execute mode

#### D. Loan creation / update

- `POST /Loan`
- `PUT /Loan`

Purpose:
- create real originated loans
- update loan data after simulation approval

#### E. Loan funding rails

- `PUT /Loan/{id}/FundingInfo`

Purpose:
- add or replace payment rails for the loan
- configure ACH, cards, RTP, wires, internal transfer, etc.

### 7.3 APIs used after execution

#### F. Loan detail retrieval

- `GET /loandetail/{id}`

Purpose:
- retrieve actual loan status details
- compare processed rails, returned rails, status updates, compliance outputs

#### G. Lending hook registration

- `POST /hooks/v2/registrations`
- `DELETE /hooks/v2/registrations`

Purpose:
- support local/sandbox integration testing
- receive real-time loan lifecycle notifications

---

## 8. Design Principles

### 8.1 Side-effect-free simulation

In simulation mode:

- do not call `POST /Loan`
- do not call `PUT /Loan/{id}/FundingInfo`
- do not move funds
- do not create irreversible backend state

### 8.2 Cross River as validation source of truth

Use Cross River Preapproval dry-run as the primary validation mechanism. Do not duplicate partner schema validation in local business logic except for lightweight request sanity checks.

### 8.3 Projection is explicit, not guaranteed

Every projected outcome must be labeled as one of:

- `validated_by_crossriver`
- `projected_by_engine`
- `actual_from_crossriver`

### 8.4 Replayability

Store every normalized request and response so the same scenario can be replayed against newer projection logic.

### 8.5 Strong observability

Every request must carry:

- correlation ID
- scenario ID
- tenant ID
- simulation mode
- idempotency key when applicable

---

## 9. Bounded Contexts and Service Responsibilities

## 9.1 API Gateway

### Responsibilities
- ingress routing
- auth validation
- correlation ID injection
- request size limits
- rate limits

### Technology
- YARP reverse proxy or Envoy/Nginx container

---

## 9.2 Simulation API Service

### Responsibilities
- manage simulation scenarios
- orchestrate validation and projection
- expose public REST APIs
- persist scenario metadata
- publish jobs to RabbitMQ

### Suggested project structure

```text
src/Simulation.Api
  Controllers/
  Application/
  Domain/
  Infrastructure/
  Contracts/
  Program.cs
```

### APIs

- `POST /simulation-scenarios`
- `GET /simulation-scenarios/{id}`
- `GET /simulation-scenarios/{id}/timeline`
- `POST /simulation-scenarios/{id}/execute`
- `POST /simulation-scenarios/{id}/replay`
- `GET /simulation-scenarios/{id}/comparison`

---

## 9.3 CrossRiver Adapter Service

### Responsibilities
- encapsulate all outbound HTTP to Cross River
- token acquisition / auth
- retry policy
- backoff policy
- header propagation
- payload normalization
- response mapping
- circuit breaker behavior

### APIs exposed internally

- `POST /internal/crossriver/preapproval/dryrun`
- `POST /internal/crossriver/customers`
- `GET /internal/crossriver/customers/{id}`
- `POST /internal/crossriver/accounts`
- `POST /internal/crossriver/subaccounts`
- `POST /internal/crossriver/loans`
- `PUT /internal/crossriver/loans/{id}`
- `PUT /internal/crossriver/loans/{id}/funding-info`
- `GET /internal/crossriver/loans/{id}/details`

### Implementation notes
- use typed `HttpClient`
- Polly for retries/circuit breaker
- support sandbox and prod config
- redact sensitive fields in logs

---

## 9.4 Projection Engine Service

### Responsibilities
- map dry-run response into a simulation result
- build projected event timeline
- estimate funding behavior by rail
- inject scenario-specific failures
- recommend alternative offers when configured

### Projection inputs
- original loan intent
- borrower snapshot
- Cross River dry-run response
- current business calendar/time
- configured rail timing rules
- failure injection mode

### Projection outputs
- projected decision
- projected statuses
- projected rails
- warnings
- explainability notes
- event timeline

### Rules examples
- if dry-run contains failed rules -> projected decision = reject/manual_review
- if ACH and after cutoff -> projected settlement window shifts to next business window
- if injected failure = `ach_return` -> add `railupdated` event and failed funding branch

---

## 9.5 Execution Service

### Responsibilities
- execute approved simulation as real origination
- call real loan creation APIs
- call funding rails APIs
- persist mapping from scenario to real loan
- publish execution started/completed events

### Important rule
This service is the only component allowed to call:
- `POST /Loan`
- `PUT /Loan/{id}/FundingInfo`

---

## 9.6 Webhook Ingest Service

### Responsibilities
- receive real Cross River hook callbacks
- verify authenticity if signatures are supported/configured
- normalize event payloads
- persist actual event history
- publish comparison jobs

### Public endpoint
- `POST /webhooks/crossriver/lending`

### Events of interest
- `loanstatusupdated`
- `complianceloanfailed`
- `railupdated`
- `loannoteadded`

---

## 9.7 Audit & Comparison Service

### Responsibilities
- store immutable audit records
- compute diff between projected and actual outcomes
- produce simulation accuracy reports
- expose operational reports

### Outputs
- projected vs actual status path
- projected vs actual funding rail outcomes
- projected vs actual timing difference
- missing/unexpected events

---

## 10. Domain Model

### 10.1 SimulationScenario

```csharp
public class SimulationScenario
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
```

### 10.2 BorrowerSnapshot

```csharp
public class BorrowerSnapshot
{
    public string? CustomerId { get; set; }
    public bool HasEmail { get; set; }
    public bool HasPhone { get; set; }
    public bool HasAddress { get; set; }
    public bool HasIdentification { get; set; }
    public bool AccountReady { get; set; }
    public List<string> MissingItems { get; set; } = new();
}
```

### 10.3 LoanIntent

```csharp
public class LoanIntent
{
    public decimal RequestedAmount { get; set; }
    public int TermMonths { get; set; }
    public decimal? Rate { get; set; }
    public string ProductType { get; set; } = default!;
    public string Currency { get; set; } = "USD";
    public FundingPlan FundingPlan { get; set; } = default!;
}
```

### 10.4 FundingPlan

```csharp
public class FundingPlan
{
    public List<string> PreferredRails { get; set; } = new();
    public string? DestinationAccountRef { get; set; }
    public bool AllowFallbackRail { get; set; }
}
```

### 10.5 SimulationResult

```csharp
public class SimulationResult
{
    public Guid ScenarioId { get; set; }
    public string ProjectedDecision { get; set; } = default!;
    public string ValidationStatus { get; set; } = default!;
    public List<ProjectedStatus> ProjectedStatuses { get; set; } = new();
    public List<ProjectedRailOutcome> ProjectedRails { get; set; } = new();
    public List<ProjectedEvent> Timeline { get; set; } = new();
    public List<string> Warnings { get; set; } = new();
    public List<ExplainabilityNote> Explainability { get; set; } = new();
}
```

### 10.6 ProjectedEvent

```csharp
public class ProjectedEvent
{
    public string EventType { get; set; } = default!;
    public DateTimeOffset EstimatedAtUtc { get; set; }
    public string Source { get; set; } = default!;
    public string Confidence { get; set; } = default!;
    public Dictionary<string, string> Metadata { get; set; } = new();
}
```

---

## 11. Public API Contract

## 11.1 Create simulation

### Request

```json
{
  "tenantId": "tenant-a",
  "partnerSchemaId": "schema-123",
  "mode": "happy_path",
  "borrower": {
    "customerId": "cust-001",
    "firstName": "Jane",
    "lastName": "Doe",
    "email": "jane@example.com",
    "phone": "+15551234567"
  },
  "loanIntent": {
    "requestedAmount": 5000,
    "termMonths": 12,
    "rate": 8.5,
    "productType": "installment",
    "currency": "USD",
    "fundingPlan": {
      "preferredRails": ["ACH", "RTP"],
      "destinationAccountRef": "ext-acct-777",
      "allowFallbackRail": true
    }
  }
}
```

### Response

```json
{
  "scenarioId": "9c74d4d3-bd6b-4be8-ae52-b9181cf11ab2",
  "validationStatus": "validated",
  "projectedDecision": "approve",
  "warnings": ["ACH may shift to next business window if submitted after cutoff"],
  "timeline": [
    {
      "eventType": "application.validated",
      "estimatedAtUtc": "2026-04-07T10:00:00Z",
      "source": "validated_by_crossriver",
      "confidence": "high"
    },
    {
      "eventType": "loan.created",
      "estimatedAtUtc": "2026-04-07T10:00:02Z",
      "source": "projected_by_engine",
      "confidence": "medium"
    }
  ]
}
```

## 11.2 Execute simulation

`POST /simulation-scenarios/{id}/execute`

### Response

```json
{
  "scenarioId": "9c74d4d3-bd6b-4be8-ae52-b9181cf11ab2",
  "executionStatus": "started",
  "realLoanId": "loan-abc-123"
}
```

## 11.3 Comparison report

`GET /simulation-scenarios/{id}/comparison`

### Response

```json
{
  "scenarioId": "9c74d4d3-bd6b-4be8-ae52-b9181cf11ab2",
  "realLoanId": "loan-abc-123",
  "statusMatch": true,
  "railMatch": false,
  "timingDeltaSeconds": 420,
  "unexpectedEvents": ["railupdated"],
  "notes": ["Simulation predicted ACH success, actual flow switched to RTP fallback"]
}
```

---

## 12. Internal Event Contracts

Use RabbitMQ for internal async decoupling.

### Topics / queues

- `simulation.created`
- `simulation.validated`
- `simulation.projected`
- `simulation.execution.requested`
- `simulation.executed`
- `crossriver.hook.received`
- `simulation.comparison.requested`
- `simulation.comparison.completed`

### Example event

```json
{
  "eventName": "simulation.projected",
  "scenarioId": "9c74d4d3-bd6b-4be8-ae52-b9181cf11ab2",
  "tenantId": "tenant-a",
  "occurredAtUtc": "2026-04-07T10:00:03Z",
  "correlationId": "corr-12345"
}
```

---

## 13. Data Storage Design

Use PostgreSQL.

### Tables

#### `simulation_scenarios`
- id
- tenant_id
- partner_schema_id
- status
- mode
- created_at_utc
- executed_at_utc
- real_loan_id

#### `simulation_requests`
- id
- scenario_id
- request_json
- normalized_request_json
- created_at_utc

#### `crossriver_interactions`
- id
- scenario_id
- interaction_type
- endpoint_name
- request_json
- response_json
- http_status
- created_at_utc

#### `simulation_results`
- id
- scenario_id
- result_json
- created_at_utc

#### `projected_events`
- id
- scenario_id
- event_type
- estimated_at_utc
- source
- confidence
- metadata_json

#### `actual_events`
- id
- scenario_id
- real_loan_id
- event_type
- occurred_at_utc
- payload_json

#### `comparison_reports`
- id
- scenario_id
- report_json
- created_at_utc

---

## 14. Logging Design

Use **Serilog** with structured JSON logging.

### Log sinks
- console
- Loki
- rolling file in local development

### Mandatory log fields
- `timestamp`
- `level`
- `service`
- `environment`
- `correlationId`
- `scenarioId`
- `tenantId`
- `operationName`
- `endpoint`
- `durationMs`
- `httpStatusCode`
- `crossRiverEndpoint`
- `simulationMode`

### Log examples

```json
{
  "service": "crossriver-adapter",
  "operationName": "PreapprovalDryRun",
  "scenarioId": "9c74d4d3-bd6b-4be8-ae52-b9181cf11ab2",
  "correlationId": "corr-12345",
  "crossRiverEndpoint": "/api/v2/applications/schema-123/dryrun",
  "durationMs": 421,
  "httpStatusCode": 200,
  "level": "Information"
}
```

### Redaction rules
Never log:
- SSN/full national IDs
- full bank account numbers
- tokens/secrets
- raw sensitive attachment data

Redact or mask these fields automatically.

---

## 15. Metrics Design

Use **Prometheus** metrics.

### Business metrics
- `simulation_created_total`
- `simulation_completed_total`
- `simulation_execute_total`
- `simulation_compare_total`
- `simulation_projection_decision_total{decision}`
- `simulation_failure_injection_total{mode}`

### Integration metrics
- `crossriver_http_requests_total{endpoint,status_code}`
- `crossriver_http_duration_ms_bucket{endpoint}`
- `crossriver_http_failures_total{endpoint}`
- `crossriver_circuit_breaker_open_total{endpoint}`

### Webhook metrics
- `crossriver_hooks_received_total{event_type}`
- `crossriver_hooks_processing_failures_total`

### Quality metrics
- `simulation_status_match_ratio`
- `simulation_rail_match_ratio`
- `simulation_avg_timing_delta_seconds`

---

## 16. Tracing Design

Use **OpenTelemetry**.

### Trace spans
- `http.request`
- `simulation.create`
- `borrower.precheck`
- `crossriver.preapproval.dryrun`
- `projection.generate`
- `simulation.execute`
- `crossriver.loan.create`
- `crossriver.fundinginfo.put`
- `hook.ingest`
- `comparison.generate`

### Propagation
- W3C Trace Context
- include `traceId` and `spanId` in logs

---

## 17. Resilience Design

### Retry policy
Use Polly for transient HTTP failures on Cross River calls.

### Circuit breaker
Open breaker after repeated downstream failures.

### Timeout policy
Each outbound API call must use explicit timeout.

### Dead-letter strategy
If webhook processing fails repeatedly, send to dead-letter queue.

### Idempotency
- support idempotent create/execute requests
- persist idempotency keys in Redis/Postgres

---

## 18. Security Design

### Auth
- JWT between client and API Gateway
- service-to-service auth via internal network and shared config secrets

### Secrets
- environment variables for local
- Docker secrets if desired

### Data protection
- encrypt database volume if deployed beyond local demo
- redact sensitive PII in logs
- enable HTTPS in non-local environments

---

## 19. Configuration Design

Use `appsettings.json` + environment overrides.

### Example settings

```json
{
  "CrossRiver": {
    "BaseUrl": "https://lendingsandbox.crbcos.com/preapproval",
    "ApiScope": "coslending_preapproval_stg",
    "TimeoutSeconds": 30
  },
  "Projection": {
    "AchCutoffHourUtc": 20,
    "RtpAssumedImmediate": true
  },
  "RabbitMq": {
    "Host": "rabbitmq"
  },
  "ConnectionStrings": {
    "Postgres": "Host=postgres;Port=5432;Database=simulation;Username=postgres;Password=postgres",
    "Redis": "redis:6379"
  }
}
```

---

## 20. Docker Design

## 20.1 Services in docker-compose

- api-gateway
- simulation-api
- crossriver-adapter
- projection-engine
- execution-service
- webhook-ingest
- audit-comparison
- postgres
- redis
- rabbitmq
- prometheus
- grafana
- loki
- otel-collector

## 20.2 Required Docker files

Each microservice should have:
- `Dockerfile`
- `.dockerignore`

Root project should include:
- `docker-compose.yml`
- `docker-compose.override.yml`
- `prometheus.yml`
- `loki-config.yaml`
- `otel-collector-config.yaml`

---

## 21. Suggested Solution Structure

```text
simulation-engine/
  docker-compose.yml
  .env
  docs/
    design.md
  src/
    BuildingBlocks/
      SharedKernel/
      Observability/
      Messaging/
      Persistence/
    ApiGateway/
    Simulation.Api/
    CrossRiver.Adapter/
    Projection.Engine/
    Execution.Service/
    Webhook.Ingest/
    Audit.Comparison/
  tests/
    Simulation.Api.Tests/
    CrossRiver.Adapter.Tests/
    Projection.Engine.Tests/
    Integration.Tests/
  deploy/
    prometheus/
    grafana/
    loki/
    otel/
```

---

## 22. Matrices

## 22.1 Service Responsibility Matrix

| Capability | API Gateway | Simulation API | CrossRiver Adapter | Projection Engine | Execution Service | Webhook Ingest | Audit & Comparison |
|---|---|---|---|---|---|---|---|
| Client auth | R | C | I | I | I | I | I |
| Scenario creation | I | R | I | I | I | I | C |
| Payload validation | I | R | C | I | I | I | I |
| Cross River dry-run | I | C | R | I | I | I | I |
| Projection generation | I | C | C | R | I | I | C |
| Real loan creation | I | I | C | I | R | I | C |
| Funding rails setup | I | I | C | I | R | I | C |
| Hook ingestion | I | I | I | I | I | R | C |
| Comparison report | I | C | C | C | C | C | R |
| Metrics/logging | C | R | R | R | R | R | R |

Legend:
- R = Responsible
- C = Contributes
- I = Informed / indirect

## 22.2 Cross River API Usage Matrix

| Cross River API | Simulation Mode | Execute Mode | Compare Mode | Service Owner |
|---|---|---|---|---|
| `POST /api/v2/applications/{partnerSchemaId}/dryrun` | Yes | No | No | CrossRiver Adapter |
| `POST /core/v1/cm/customers` | Optional | Optional | No | CrossRiver Adapter |
| `GET /core/v1/cm/customers/{id}` | Optional | Optional | No | CrossRiver Adapter |
| `POST /core/v1/dda/accounts` | Optional | Optional | No | CrossRiver Adapter |
| `POST /core/v1/dda/subaccounts` | Optional | Optional | No | CrossRiver Adapter |
| `POST /Loan` | No | Yes | No | Execution Service via Adapter |
| `PUT /Loan` | No | Yes | No | Execution Service via Adapter |
| `PUT /Loan/{id}/FundingInfo` | No | Yes | No | Execution Service via Adapter |
| `GET /loandetail/{id}` | No | Optional | Yes | Audit & Comparison via Adapter |
| `POST /hooks/v2/registrations` | Setup only | Setup only | Setup only | Webhook Ingest / ops tooling |

## 22.3 Failure Injection Matrix

| Mode | Dry-run Result | Projected Loan Outcome | Projected Rail Outcome | Expected Hook/Event Pattern |
|---|---|---|---|---|
| `happy_path` | success | approve | first-choice rail succeeds | `loanstatusupdated` normal path |
| `validation_failure` | failed rule(s) | reject/manual_review | no funding | validation only |
| `ach_return` | success | approve | ACH fails after initiation | `railupdated` + funding anomaly |
| `compliance_failure` | success or warning | compliance fail later | funding blocked or reversed | `complianceloanfailed` |
| `delayed_funding` | success | approve | rail delayed to next window | delayed `railupdated` |
| `fallback_to_rtp` | success | approve | ACH unavailable, RTP used | alternate rail event chain |

## 22.4 Observability Matrix

| Concern | Logs | Metrics | Traces | Owner |
|---|---|---|---|---|
| Incoming API requests | Yes | Yes | Yes | API Gateway / Simulation API |
| Cross River outbound calls | Yes | Yes | Yes | CrossRiver Adapter |
| Projection rule execution | Yes | Yes | Yes | Projection Engine |
| Execution flow | Yes | Yes | Yes | Execution Service |
| Webhook handling | Yes | Yes | Yes | Webhook Ingest |
| Comparison generation | Yes | Yes | Yes | Audit & Comparison |

---

## 23. Implementation Guidance for Codex

### Mandatory technical choices
- language: **C# / .NET 8**
- architecture: **microservices**
- containerization: **Docker + Docker Compose**
- database: **PostgreSQL**
- cache/idempotency: **Redis**
- messaging: **RabbitMQ**
- logging: **Serilog**
- metrics: **prometheus-net**
- tracing: **OpenTelemetry**
- resilience: **Polly**

### Coding guidelines
- use clean architecture per service where practical
- keep DTOs separate from domain models
- use typed HttpClient for Cross River
- support cancellation tokens everywhere
- use async/await end to end
- prefer record types for immutable contracts
- add health checks for all services
- include integration tests using Dockerized dependencies where possible

### Minimum deliverables
- working docker-compose
- all microservices boot successfully
- sample simulation flow works end-to-end using mocked Cross River responses if credentials are unavailable
- metrics endpoint exposed per service
- logs emitted as structured JSON
- traces exported to local collector
- README with startup instructions

---

## 24. Non-Functional Requirements

### Availability
- local demo reliability is sufficient for interview demo
- services should restart automatically in Docker Compose

### Performance
- create simulation request target: under 2 seconds when using mocks
- comparison report target: under 1 second for small scenarios

### Scalability
- stateless services except DB-backed persistence
- RabbitMQ decoupling for async workloads

### Auditability
- all scenario transitions must be persisted
- all outbound Cross River interactions must be stored

---

## 25. Demo Scenarios

Codex should implement sample seed/demo scenarios:

1. **Happy path installment loan**
2. **Validation failure due to missing borrower field**
3. **ACH return after projected approval**
4. **Compliance failure after origination**
5. **Fallback from ACH to RTP**

---

## 26. Final Interview Positioning

This design demonstrates:

- fintech domain understanding
- safe integration with external banking APIs
- event-driven and microservice architecture
- observability maturity
- explainability and replay capability
- clean separation between validation, projection, execution, and comparison
