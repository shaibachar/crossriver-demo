locals {
  name_prefix = "${var.project}-${var.environment}"

  # Use the first two available AZs in the region
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Base ECR registry URL for this account and region
  ecr_base = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"

  # Cloud Map private DNS namespace
  sd_namespace = "${local.name_prefix}.local"

  # Application services – each gets an ECR repository and an ECS service
  app_services = [
    "simulation-api",
    "crossriver-adapter",
    "projection-engine",
    "execution-service",
    "webhook-ingest",
    "audit-comparison",
  ]

  # Internal service URLs resolved by AWS Cloud Map DNS
  svc_url = {
    crossriver_adapter = "http://crossriver-adapter.${local.sd_namespace}:8080"
    projection_engine  = "http://projection-engine.${local.sd_namespace}:8080"
    execution_service  = "http://execution-service.${local.sd_namespace}:8080"
  }
}
