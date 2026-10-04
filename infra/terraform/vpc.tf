# infra/terraform/vpc.tf - network and security groups

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "fin-${var.env}"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  # Tasks have no public IP; they reach ECR, Secrets Manager and CloudWatch through NAT
  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
}

# Public ALB: the only thing exposed to the internet (WAF is attached in edge.yaml)
resource "aws_security_group" "alb" {
  name_prefix = "fin-${var.env}-alb-"
  description = "Public ALB"
  vpc_id      = module.vpc.vpc_id

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

  lifecycle {
    create_before_destroy = true
  }
}

# ECS tasks: reachable only from the ALB
resource "aws_security_group" "svc" {
  for_each = var.services

  name_prefix = "fin-${var.env}-${each.value.short_name}-"
  description = "${each.key} tasks - only the ALB may connect"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "ALB to app"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
