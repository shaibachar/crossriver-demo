# ─────────────────────────────────────────────────────────
#  Application Load Balancer (public)
# ─────────────────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = { Name = "${local.name_prefix}-alb" }
}

# ─────────────────────────────────────────────────────────
#  Target groups
# ─────────────────────────────────────────────────────────
resource "aws_lb_target_group" "simulation_api" {
  name        = "${local.name_prefix}-sim-api"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "${local.name_prefix}-simulation-api-tg" }
}

resource "aws_lb_target_group" "webhook_ingest" {
  name        = "${local.name_prefix}-webhook"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "${local.name_prefix}-webhook-ingest-tg" }
}

# ─────────────────────────────────────────────────────────
#  HTTP listener (port 80)
#  Default → simulation-api
#  /webhook/* and /webhooks/* → webhook-ingest
# ─────────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.simulation_api.arn
  }
}

resource "aws_lb_listener_rule" "webhook" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webhook_ingest.arn
  }

  condition {
    path_pattern {
      values = ["/webhook/*", "/webhooks/*"]
    }
  }
}
