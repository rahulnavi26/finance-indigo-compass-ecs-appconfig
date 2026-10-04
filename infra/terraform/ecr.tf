# infra/terraform/ecr.tf - ECR repositories
# The shared tools account owns ECR. These resources are created only when
# create_ecr = true (apply once in the tools account). Dev/staging/prod only pull.

resource "aws_ecr_repository" "svc" {
  for_each = var.create_ecr ? var.services : {}

  name                 = "fin/${each.key}"
  image_tag_mutability = "IMMUTABLE" # a released tag can never be overwritten

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

data "aws_iam_policy_document" "ecr_cross_account_pull" {
  count = var.create_ecr && length(var.ecr_pull_account_ids) > 0 ? 1 : 0

  statement {
    sid = "AllowEnvAccountsToPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    principals {
      type        = "AWS"
      identifiers = [for id in var.ecr_pull_account_ids : "arn:aws:iam::${id}:root"]
    }
  }
}

resource "aws_ecr_repository_policy" "svc" {
  for_each = var.create_ecr && length(var.ecr_pull_account_ids) > 0 ? var.services : {}

  repository = aws_ecr_repository.svc[each.key].name
  policy     = data.aws_iam_policy_document.ecr_cross_account_pull[0].json
}

resource "aws_ecr_lifecycle_policy" "svc" {
  for_each = var.create_ecr ? var.services : {}

  repository = aws_ecr_repository.svc[each.key].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 50 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 50
      }
      action = { type = "expire" }
    }]
  })
}
