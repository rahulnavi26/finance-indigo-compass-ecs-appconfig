# infra/terraform/alb.tf - public ALB with path-based routing (/payments, /reconciliation)

resource "aws_lb" "public" {
  name                       = "fin-${var.env}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.vpc.public_subnets
  drop_invalid_header_fields = true
  enable_deletion_protection = var.env == "prod"
}

resource "aws_lb_target_group" "svc" {
  for_each = var.services

  name        = "fin-${var.env}-${each.value.short_name}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip" # Fargate tasks register by IP

  deregistration_delay = 30

  health_check {
    path                = each.value.health_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# --- Listeners ---------------------------------------------------------------
# No certificate: plain HTTP (demo). With a certificate: HTTPS plus an HTTP redirect.

resource "aws_lb_listener" "http" {
  count = var.certificate_arn == "" ? 1 : 0

  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "http_redirect" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

locals {
  main_listener_arn = var.certificate_arn != "" ? aws_lb_listener.https[0].arn : aws_lb_listener.http[0].arn
  app_host          = var.app_domain != "" ? var.app_domain : aws_lb.public.dns_name
  app_scheme        = var.certificate_arn != "" ? "https" : "http"
}

resource "aws_lb_listener_rule" "svc" {
  for_each = var.services

  listener_arn = local.main_listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.paths
    }
  }
}
