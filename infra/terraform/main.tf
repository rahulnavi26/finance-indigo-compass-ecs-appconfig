# infra/terraform/main.tf - provider, backend and shared data sources

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Bucket, key, region and lock table are supplied by the pipeline via -backend-config
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "finance-indigo-compass"
      Env       = var.env
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Where the AppConfig agent sidecar serves the flags (names match edge.yaml)
  appconfig_path = "/applications/fin-${var.env}/environments/${var.env}/configurations/flags"
}
