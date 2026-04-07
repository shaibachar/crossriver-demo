create table if not exists simulation_scenarios (
  id uuid primary key,
  tenant_id text not null,
  partner_schema_id text not null,
  status text not null,
  mode text not null,
  created_at_utc timestamptz not null,
  executed_at_utc timestamptz null,
  real_loan_id text null
);

create table if not exists simulation_requests (
  id uuid primary key,
  scenario_id uuid not null references simulation_scenarios(id),
  request_json jsonb not null,
  normalized_request_json jsonb not null,
  created_at_utc timestamptz not null
);

create table if not exists crossriver_interactions (
  id uuid primary key,
  scenario_id uuid not null references simulation_scenarios(id),
  interaction_type text not null,
  endpoint_name text not null,
  request_json jsonb not null,
  response_json jsonb not null,
  http_status integer not null,
  created_at_utc timestamptz not null
);

create table if not exists simulation_results (
  id uuid primary key,
  scenario_id uuid not null references simulation_scenarios(id),
  result_json jsonb not null,
  created_at_utc timestamptz not null
);

create table if not exists projected_events (
  id uuid primary key,
  scenario_id uuid not null references simulation_scenarios(id),
  event_type text not null,
  estimated_at_utc timestamptz not null,
  source text not null,
  confidence text not null,
  metadata_json jsonb not null
);

create table if not exists actual_events (
  id uuid primary key,
  scenario_id uuid null references simulation_scenarios(id),
  real_loan_id text null,
  event_type text not null,
  occurred_at_utc timestamptz not null,
  payload_json jsonb not null
);

create table if not exists comparison_reports (
  id uuid primary key,
  scenario_id uuid not null references simulation_scenarios(id),
  report_json jsonb not null,
  created_at_utc timestamptz not null
);
