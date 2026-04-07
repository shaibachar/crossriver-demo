# ─────────────────────────────────────────────────────────
#  ALB – public HTTP/HTTPS ingress
# ─────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Internet-facing Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

# ─────────────────────────────────────────────────────────
#  ECS Fargate tasks
#  Accepts traffic from ALB and from peer tasks (service-to-service)
# ─────────────────────────────────────────────────────────
resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs"
  description = "ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Service-to-service"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ecs-sg" }
}

# ─────────────────────────────────────────────────────────
#  RDS PostgreSQL
# ─────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds"
  description = "RDS PostgreSQL – ECS access only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

# ─────────────────────────────────────────────────────────
#  ElastiCache Redis
# ─────────────────────────────────────────────────────────
resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis"
  description = "ElastiCache Redis – ECS access only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-redis-sg" }
}

# ─────────────────────────────────────────────────────────
#  Amazon MQ (RabbitMQ)
# ─────────────────────────────────────────────────────────
resource "aws_security_group" "mq" {
  name        = "${local.name_prefix}-mq"
  description = "Amazon MQ RabbitMQ – ECS access only"
  vpc_id      = aws_vpc.main.id

  # AMQP over TLS
  ingress {
    from_port       = 5671
    to_port         = 5671
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  # HTTPS management console (optional access from private subnet)
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-mq-sg" }
}
