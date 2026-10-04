# infra/terraform/iam.tf - ECS roles and secret containers

# Secret containers only. Values are set outside Terraform so they never enter state.
resource "aws_secretsmanager_secret" "svc" {
  for_each = var.services

  name                    = "fin/${var.env}/${each.key}"
  recovery_window_in_days = var.env == "prod" ? 30 : 0
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# --- Execution role: lets ECS pull images, write logs and inject secrets ----------
resource "aws_iam_role" "execution" {
  name               = "fin-${var.env}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid       = "ReadServiceSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [for secret in aws_secretsmanager_secret.svc : secret.arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "read-service-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# --- Task role: what the running containers may call --------------------------------
resource "aws_iam_role" "task" {
  name               = "fin-${var.env}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "task_appconfig" {
  statement {
    sid     = "ReadFeatureFlags"
    actions = ["appconfig:StartConfigurationSession", "appconfig:GetLatestConfiguration"]
    resources = [
      "arn:aws:appconfig:${var.region}:${data.aws_caller_identity.current.account_id}:application/*/environment/*/configuration/*",
    ]
  }
}

resource "aws_iam_role_policy" "task_appconfig" {
  name   = "read-feature-flags"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_appconfig.json
}

# X-Ray daemon sidecar permissions
resource "aws_iam_role_policy_attachment" "task_xray" {
  role       = aws_iam_role.task.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
