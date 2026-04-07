resource "aws_mq_broker" "rabbitmq" {
  broker_name        = "${local.name_prefix}-rabbitmq"
  engine_type        = "RabbitMQ"
  engine_version     = "3.13"
  host_instance_type = var.mq_instance_type
  deployment_mode    = "SINGLE_INSTANCE"

  subnet_ids          = [aws_subnet.private[0].id]
  security_groups     = [aws_security_group.mq.id]
  publicly_accessible = false

  user {
    username = "crossriver"
    password = random_password.mq.result
  }

  tags = { Name = "${local.name_prefix}-rabbitmq" }
}
