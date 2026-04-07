output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer (API entry point)"
  value       = aws_lb.main.dns_name
}

output "ecr_repositories" {
  description = "ECR repository URLs – build and push images here before first deploy"
  value       = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL host"
  value       = aws_db_instance.postgres.address
}

output "redis_endpoint" {
  description = "ElastiCache Redis host"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "mq_endpoint" {
  description = "Amazon MQ RabbitMQ AMQPS endpoint"
  value       = aws_mq_broker.rabbitmq.instances[0].endpoints[0]
}

output "service_discovery_namespace" {
  description = "Cloud Map private DNS namespace for service-to-service calls"
  value       = aws_service_discovery_private_dns_namespace.main.name
}

output "db_init_hint" {
  description = "Run this psql command after first deploy to apply the database schema"
  value       = "psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d ${var.db_name} -f deploy/postgres/001_init.sql"
}
