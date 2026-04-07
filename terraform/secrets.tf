# ─── Database password ─────────────────────────────────────────────────────────
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${local.name_prefix}/db-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

# ─── Full DB connection string (populated after RDS is created) ─────────────
resource "aws_secretsmanager_secret" "db_conn" {
  name                    = "${local.name_prefix}/db-connection-string"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_conn" {
  secret_id     = aws_secretsmanager_secret.db_conn.id
  secret_string = "Host=${aws_db_instance.postgres.address};Port=5432;Database=${var.db_name};Username=${var.db_username};Password=${random_password.db.result}"
}

# ─── Internal service API key ──────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "app_api_key" {
  name                    = "${local.name_prefix}/app-api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_api_key" {
  secret_id     = aws_secretsmanager_secret.app_api_key.id
  secret_string = var.app_api_key != "" ? var.app_api_key : "demo-api-key-please-rotate"
}

# ─── Cross River API key ───────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "cr_api_key" {
  name                    = "${local.name_prefix}/crossriver-api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "cr_api_key" {
  secret_id     = aws_secretsmanager_secret.cr_api_key.id
  secret_string = var.crossriver_api_key != "" ? var.crossriver_api_key : "replace-with-real-crossriver-key"
}

# ─── Amazon MQ password ────────────────────────────────────────────────────────
resource "random_password" "mq" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "mq_password" {
  name                    = "${local.name_prefix}/mq-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mq_password" {
  secret_id     = aws_secretsmanager_secret.mq_password.id
  secret_string = random_password.mq.result
}

# ─── Full RabbitMQ AMQP URL (populated after broker is created) ───────────────
resource "aws_secretsmanager_secret" "mq_url" {
  name                    = "${local.name_prefix}/rabbitmq-url"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mq_url" {
  secret_id = aws_secretsmanager_secret.mq_url.id
  # Insert credentials into the broker-provided endpoint URL
  # Before: amqps://b-xxx.mq.us-east-1.amazonaws.com:5671
  # After:  amqps://crossriver:<password>@b-xxx.mq.us-east-1.amazonaws.com:5671
  secret_string = replace(
    aws_mq_broker.rabbitmq.instances[0].endpoints[0],
    "amqps://",
    "amqps://crossriver:${random_password.mq.result}@"
  )
}
