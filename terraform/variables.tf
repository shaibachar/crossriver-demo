variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name – used as a prefix for all resource names"
  type        = string
  default     = "crossriver"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway so private-subnet ECS tasks can reach the internet"
  type        = bool
  default     = true
}

# ── RDS ──────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance class for PostgreSQL"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial PostgreSQL database name"
  type        = string
  default     = "simulation"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "postgres"
}

# ── ElastiCache ───────────────────────────────────────────

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

# ── Amazon MQ ────────────────────────────────────────────

variable "mq_instance_type" {
  description = "Amazon MQ broker instance type"
  type        = string
  default     = "mq.t3.micro"
}

# ── ECS ──────────────────────────────────────────────────

variable "ecs_default_cpu" {
  description = "Default vCPU units for ECS Fargate tasks (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "ecs_default_memory" {
  description = "Default memory (MiB) for ECS Fargate tasks"
  type        = number
  default     = 512
}

variable "service_desired_count" {
  description = "Desired running task count per ECS service"
  type        = number
  default     = 1
}

# ── Secrets ───────────────────────────────────────────────

variable "app_api_key" {
  description = "Internal API key shared across microservices. Defaults to a placeholder if empty."
  type        = string
  sensitive   = true
  default     = ""
}

variable "crossriver_api_key" {
  description = "Real Cross River API key used by the adapter service"
  type        = string
  sensitive   = true
  default     = ""
}
