# ─────────────────────────────────────────────────────────
#  ECS Cluster
# ─────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.name_prefix}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ─────────────────────────────────────────────────────────
#  CloudWatch log group shared by all ECS services
# ─────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30
  tags              = { Name = "${local.name_prefix}-ecs-logs" }
}

# ─────────────────────────────────────────────────────────
#  AWS Cloud Map – private DNS namespace
#  Services register as <name>.<namespace>.local
#  and are reachable within the VPC at that address.
# ─────────────────────────────────────────────────────────
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = local.sd_namespace
  description = "Service discovery for ${local.name_prefix}"
  vpc         = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-sd-namespace" }
}
