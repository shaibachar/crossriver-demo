# ─────────────────────────────────────────────────────────
#  Cloud Map service registrations (one per app service)
#  ECS registers each task IP here; DNS resolves internally.
# ─────────────────────────────────────────────────────────
resource "aws_service_discovery_service" "app" {
  for_each = toset(local.app_services)
  name     = each.key

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# ─────────────────────────────────────────────────────────
#  Helper: shared logging options block
# ─────────────────────────────────────────────────────────
locals {
  log_config = { for svc in local.app_services :
    svc => {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = svc
      }
    }
  }
}

# ══════════════════════════════════════════════════════════
#  simulation-api
#  Public API – routes to crossriver-adapter, projection-engine,
#  execution-service.  Needs DB, Redis, RabbitMQ.
# ══════════════════════════════════════════════════════════
resource "aws_ecs_task_definition" "simulation_api" {
  family                   = "${local.name_prefix}-simulation-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "simulation-api"
    image     = "${aws_ecr_repository.app["simulation-api"].repository_url}:latest"
    essential = true

    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "ASPNETCORE_URLS",             value = "http://+:8080" },
      { name = "Services__CrossRiverAdapter", value = local.svc_url.crossriver_adapter },
      { name = "Services__ProjectionEngine",  value = local.svc_url.projection_engine },
      { name = "Services__ExecutionService",  value = local.svc_url.execution_service },
      { name = "Redis__Host",                 value = aws_elasticache_cluster.redis.cache_nodes[0].address },
      { name = "Redis__Port",                 value = "6379" },
    ]

    secrets = [
      { name = "Auth__ApiKey",                valueFrom = aws_secretsmanager_secret.app_api_key.arn },
      { name = "ConnectionStrings__Postgres", valueFrom = aws_secretsmanager_secret.db_conn.arn },
      { name = "RabbitMQ__Url",               valueFrom = aws_secretsmanager_secret.mq_url.arn },
    ]

    logConfiguration = local.log_config["simulation-api"]
  }])

  tags = { Name = "${local.name_prefix}-simulation-api-td" }
}

resource "aws_ecs_service" "simulation_api" {
  name            = "${local.name_prefix}-simulation-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.simulation_api.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.app["simulation-api"].arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.simulation_api.arn
    container_name   = "simulation-api"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
  tags       = { Name = "${local.name_prefix}-simulation-api" }
}

# ══════════════════════════════════════════════════════════
#  crossriver-adapter
#  Encapsulates all calls to the real Cross River APIs.
# ══════════════════════════════════════════════════════════
resource "aws_ecs_task_definition" "crossriver_adapter" {
  family                   = "${local.name_prefix}-crossriver-adapter"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_default_cpu
  memory                   = var.ecs_default_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "crossriver-adapter"
    image     = "${aws_ecr_repository.app["crossriver-adapter"].repository_url}:latest"
    essential = true

    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "ASPNETCORE_URLS", value = "http://+:8080" },
    ]

    secrets = [
      { name = "Auth__ApiKey",       valueFrom = aws_secretsmanager_secret.app_api_key.arn },
      { name = "CrossRiver__ApiKey", valueFrom = aws_secretsmanager_secret.cr_api_key.arn },
    ]

    logConfiguration = local.log_config["crossriver-adapter"]
  }])

  tags = { Name = "${local.name_prefix}-crossriver-adapter-td" }
}

resource "aws_ecs_service" "crossriver_adapter" {
  name            = "${local.name_prefix}-crossriver-adapter"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.crossriver_adapter.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.app["crossriver-adapter"].arn
  }

  tags = { Name = "${local.name_prefix}-crossriver-adapter" }
}

# ══════════════════════════════════════════════════════════
#  projection-engine
#  Converts dry-run results into projected status flows.
# ══════════════════════════════════════════════════════════
resource "aws_ecs_task_definition" "projection_engine" {
  family                   = "${local.name_prefix}-projection-engine"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_default_cpu
  memory                   = var.ecs_default_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "projection-engine"
    image     = "${aws_ecr_repository.app["projection-engine"].repository_url}:latest"
    essential = true

    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "ASPNETCORE_URLS", value = "http://+:8080" },
    ]

    secrets = [
      { name = "Auth__ApiKey", valueFrom = aws_secretsmanager_secret.app_api_key.arn },
    ]

    logConfiguration = local.log_config["projection-engine"]
  }])

  tags = { Name = "${local.name_prefix}-projection-engine-td" }
}

resource "aws_ecs_service" "projection_engine" {
  name            = "${local.name_prefix}-projection-engine"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.projection_engine.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.app["projection-engine"].arn
  }

  tags = { Name = "${local.name_prefix}-projection-engine" }
}

# ══════════════════════════════════════════════════════════
#  execution-service
#  Converts approved simulations into real origination calls.
# ══════════════════════════════════════════════════════════
resource "aws_ecs_task_definition" "execution_service" {
  family                   = "${local.name_prefix}-execution-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_default_cpu
  memory                   = var.ecs_default_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "execution-service"
    image     = "${aws_ecr_repository.app["execution-service"].repository_url}:latest"
    essential = true

    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "ASPNETCORE_URLS",             value = "http://+:8080" },
      { name = "Services__CrossRiverAdapter", value = local.svc_url.crossriver_adapter },
    ]

    secrets = [
      { name = "Auth__ApiKey",                valueFrom = aws_secretsmanager_secret.app_api_key.arn },
      { name = "ConnectionStrings__Postgres", valueFrom = aws_secretsmanager_secret.db_conn.arn },
    ]

    logConfiguration = local.log_config["execution-service"]
  }])

  tags = { Name = "${local.name_prefix}-execution-service-td" }
}

resource "aws_ecs_service" "execution_service" {
  name            = "${local.name_prefix}-execution-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.execution_service.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.app["execution-service"].arn
  }

  tags = { Name = "${local.name_prefix}-execution-service" }
}

# ══════════════════════════════════════════════════════════
#  webhook-ingest
#  Receives real lending hooks from Cross River.
#  Exposed publicly via the ALB at /webhook/* path.
# ══════════════════════════════════════════════════════════
resource "aws_ecs_task_definition" "webhook_ingest" {
  family                   = "${local.name_prefix}-webhook-ingest"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_default_cpu
  memory                   = var.ecs_default_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "webhook-ingest"
    image     = "${aws_ecr_repository.app["webhook-ingest"].repository_url}:latest"
    essential = true

    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "ASPNETCORE_URLS", value = "http://+:8080" },
    ]

    secrets = [
      { name = "Auth__ApiKey", valueFrom = aws_secretsmanager_secret.app_api_key.arn },
      { name = "RabbitMQ__Url", valueFrom = aws_secretsmanager_secret.mq_url.arn },
    ]

    logConfiguration = local.log_config["webhook-ingest"]
  }])

  tags = { Name = "${local.name_prefix}-webhook-ingest-td" }
}

resource "aws_ecs_service" "webhook_ingest" {
  name            = "${local.name_prefix}-webhook-ingest"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.webhook_ingest.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.app["webhook-ingest"].arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.webhook_ingest.arn
    container_name   = "webhook-ingest"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
  tags       = { Name = "${local.name_prefix}-webhook-ingest" }
}

# ══════════════════════════════════════════════════════════
#  audit-comparison
#  Persists requests, events, and diffs. Needs DB.
# ══════════════════════════════════════════════════════════
resource "aws_ecs_task_definition" "audit_comparison" {
  family                   = "${local.name_prefix}-audit-comparison"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_default_cpu
  memory                   = var.ecs_default_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "audit-comparison"
    image     = "${aws_ecr_repository.app["audit-comparison"].repository_url}:latest"
    essential = true

    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "ASPNETCORE_URLS", value = "http://+:8080" },
    ]

    secrets = [
      { name = "Auth__ApiKey",                valueFrom = aws_secretsmanager_secret.app_api_key.arn },
      { name = "ConnectionStrings__Postgres", valueFrom = aws_secretsmanager_secret.db_conn.arn },
      { name = "RabbitMQ__Url",               valueFrom = aws_secretsmanager_secret.mq_url.arn },
    ]

    logConfiguration = local.log_config["audit-comparison"]
  }])

  tags = { Name = "${local.name_prefix}-audit-comparison-td" }
}

resource "aws_ecs_service" "audit_comparison" {
  name            = "${local.name_prefix}-audit-comparison"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.audit_comparison.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.app["audit-comparison"].arn
  }

  tags = { Name = "${local.name_prefix}-audit-comparison" }
}

# ══════════════════════════════════════════════════════════
#  otel-collector
#  Receives OTLP traces/metrics from all services and
#  forwards them to AWS X-Ray and CloudWatch.
# ══════════════════════════════════════════════════════════
resource "aws_cloudwatch_log_group" "otel" {
  name              = "/ecs/${local.name_prefix}/otel-collector"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "otel_collector" {
  family                   = "${local.name_prefix}-otel-collector"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "otel-collector"
    # AWS-managed OTel collector with built-in X-Ray and CloudWatch exporters
    image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
    essential = true

    portMappings = [
      { containerPort = 4317, protocol = "tcp" }, # OTLP gRPC
      { containerPort = 4318, protocol = "tcp" }, # OTLP HTTP
    ]

    # AOT_CONFIG_CONTENT overrides the default config with X-Ray + CloudWatch exporters
    environment = [
      {
        name = "AOT_CONFIG_CONTENT"
        value = yamlencode({
          receivers = {
            otlp = {
              protocols = {
                grpc = { endpoint = "0.0.0.0:4317" }
                http = { endpoint = "0.0.0.0:4318" }
              }
            }
          }
          processors = {
            batch = {}
          }
          exporters = {
            awsxray = {}
            awsemf = {
              namespace                = "CrossRiverDemo"
              log_group_name           = "/ecs/${local.name_prefix}/metrics"
              log_stream_name          = "{ServiceName}"
              resource_to_telemetry_conversion = { enabled = true }
            }
            logging = { verbosity = "normal" }
          }
          service = {
            pipelines = {
              traces  = { receivers = ["otlp"], processors = ["batch"], exporters = ["awsxray", "logging"] }
              metrics = { receivers = ["otlp"], processors = ["batch"], exporters = ["awsemf", "logging"] }
            }
          }
        })
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.otel.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "otel-collector"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-otel-collector-td" }
}

resource "aws_service_discovery_service" "otel" {
  name = "otel-collector"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_service" "otel_collector" {
  name            = "${local.name_prefix}-otel-collector"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.otel_collector.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.otel.arn
  }

  tags = { Name = "${local.name_prefix}-otel-collector" }
}
