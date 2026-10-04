# infra/terraform/variables.tf

variable "env" {
  description = "Environment name: dev, staging or prod"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "ecr_registry" {
  description = "ECR registry host in the tools account (set by the pipeline)"
  type        = string
}

variable "image_tag" {
  description = "Image tag used when the task definitions are first created (set by the pipeline)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for this environment's VPC"
  type        = string
}

variable "az_count" {
  description = "Number of availability zones to spread across (2 or 3)"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway (cheaper, for non-prod) instead of one per AZ"
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "ACM certificate ARN. Empty = HTTP only (demo). Set it, plus app_domain, to serve HTTPS."
  type        = string
  default     = ""
}

variable "app_domain" {
  description = "DNS name that points at the ALB and matches the certificate. Empty = use the ALB DNS name."
  type        = string
  default     = ""
}

variable "enable_secrets" {
  description = "Inject DB_PASSWORD from Secrets Manager. Set the secret value first, then turn this on."
  type        = bool
  default     = false
}

variable "services" {
  description = "One entry per service: sizing and ALB routing"
  type = map(object({
    short_name  = string       # used in target group names (AWS limit: 32 characters)
    desired     = number
    cpu         = number
    memory      = number
    paths       = list(string) # ALB path patterns
    health_path = string
    priority    = number       # ALB listener rule priority (unique)
  }))
}

variable "create_ecr" {
  description = "Create the ECR repositories (set true only when applying in the shared tools account)"
  type        = bool
  default     = false
}

variable "ecr_pull_account_ids" {
  description = "AWS account IDs allowed to pull images (dev, staging, prod). Used when create_ecr = true."
  type        = list(string)
  default     = []
}
