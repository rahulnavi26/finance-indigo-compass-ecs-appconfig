# infra/terraform/alarms.tf - log groups and alarms
# The 5xx alarm is attached to the ECS service as a deployment alarm (automatic rollback).

resource "aws_cloudwatch_log_group" "svc" {
  for_each = var.services

  name              = "/fin/${var.env}/${each.key}"
  retention_in_days = var.env == "prod" ? 365 : 14
}

resource "aws_cloudwatch_metric_alarm" "svc_5xx" {
  for_each = var.services

  alarm_name          = "fin-${var.env}-${each.key}-5xx"
  alarm_description   = "Target 5xx responses from ${each.key}; rolls back a deployment"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.public.arn_suffix
    TargetGroup  = aws_lb_target_group.svc[each.key].arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "svc_p99_latency" {
  for_each = var.services

  alarm_name          = "fin-${var.env}-${each.key}-p99-latency"
  alarm_description   = "p99 response time of ${each.key} above 1.5 seconds"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p99"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1.5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.public.arn_suffix
    TargetGroup  = aws_lb_target_group.svc[each.key].arn_suffix
  }
}
