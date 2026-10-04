# infra/terraform/outputs.tf - values the pipeline reads after apply

output "app_url" {
  description = "Base URL used by the smoke tests and the ZAP scan"
  value       = "${local.app_scheme}://${local.app_host}"
}

output "alb_arn" {
  description = "ALB ARN, passed to the edge (WAF) CloudFormation stack"
  value       = aws_lb.public.arn
}

output "alb_arn_suffix" {
  description = "ALB identifier used by CloudWatch alarms (app/<name>/<id>)"
  value       = aws_lb.public.arn_suffix
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}
