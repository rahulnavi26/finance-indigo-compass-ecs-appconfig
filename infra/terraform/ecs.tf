# infra/terraform/ecs.tf - ECS cluster, task definitions and services (Fargate)

resource "aws_ecs_cluster" "main" {
  name = "fin-${var.env}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

locals {
  log_options = {
    for name in keys(var.services) : name => {
      "awslogs-group"  = aws_cloudwatch_log_group.svc[name].name
      "awslogs-region" = var.region
    }
  }
}

resource "aws_ecs_task_definition" "svc" {
  for_each = var.services

  family                   = "fin-${var.env}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name         = "app"
      image        = "${var.ecr_registry}/fin/${each.key}:${var.image_tag}"
      essential    = true
      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
      environment = [
        { name = "ENVIRONMENT", value = var.env },
        { name = "IMAGE_TAG", value = var.image_tag },
        { name = "APPCONFIG_PATH", value = local.appconfig_path },
      ]
      secrets = var.enable_secrets ? [
        { name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.svc[each.key].arn}:db_password::" },
      ] : []
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options[each.key], { "awslogs-stream-prefix" = "app" })
      }
    },
    {
      # Serves the feature flags to the app on localhost:2772
      name         = "appconfig-agent"
      image        = "public.ecr.aws/aws-appconfig/aws-appconfig-agent:2.x"
      essential    = false
      portMappings = [{ containerPort = 2772, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options[each.key], { "awslogs-stream-prefix" = "appconfig-agent" })
      }
    },
    {
      # Receives trace segments on UDP 2000 and forwards them to X-Ray
      name         = "xray-daemon"
      image        = "public.ecr.aws/xray/aws-xray-daemon:3.x"
      essential    = false
      portMappings = [{ containerPort = 2000, protocol = "udp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options[each.key], { "awslogs-stream-prefix" = "xray-daemon" })
      }
    },
  ])

  # After the first creation the pipeline owns the container definition
  # (ecs-deploy.sh registers a new revision per build with the new image).
  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "svc" {
  for_each = var.services

  name            = each.key
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.svc[each.key].arn
  desired_count   = each.value.desired
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.svc[each.key].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.svc[each.key].arn
    container_name   = "app"
    container_port   = 8000
  }

  deployment_minimum_healthy_percent = 100 # new tasks start before old ones stop
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true # failed tasks => automatic rollback
  }

  alarms {
    enable      = true
    rollback    = true # 5xx alarm => automatic rollback
    alarm_names = [aws_cloudwatch_metric_alarm.svc_5xx[each.key].alarm_name]
  }

  depends_on = [aws_lb_listener_rule.svc]

  lifecycle {
    ignore_changes = [task_definition, desired_count] # pipeline owns the image
  }
}
