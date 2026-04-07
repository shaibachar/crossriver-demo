resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = aws_subnet.database[*].id
  tags       = { Name = "${local.name_prefix}-db-subnets" }
}

resource "aws_db_parameter_group" "postgres16" {
  name   = "${local.name_prefix}-postgres16"
  family = "postgres16"
  tags   = { Name = "${local.name_prefix}-postgres16-params" }
}

resource "aws_db_instance" "postgres" {
  identifier        = "${local.name_prefix}-postgres"
  engine            = "postgres"
  engine_version    = "16.3"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres16.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = { Name = "${local.name_prefix}-postgres" }
}
