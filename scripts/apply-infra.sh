#!/usr/bin/env bash
# Apply stage: apply the reviewed Terraform plan, then create and execute the edge change set
# with the real ALB values. Usage: apply-infra.sh <env> <build-id> <plan-dir>
set -euo pipefail
ENV=$1; BUILD=$2; PLAN=$3
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/infra/terraform"
terraform init -input=false -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=fin/$ENV/terraform.tfstate" -backend-config="region=${AWS_REGION:-ap-south-1}" \
  -backend-config="dynamodb_table=$TF_LOCK_TABLE" -backend-config="encrypt=true"

# Applying the saved plan: exactly what was reviewed, nothing else
terraform apply -input=false "$PLAN/tfplan"

APP_URL=$(terraform output -raw app_url)
ALB_ARN=$(terraform output -raw alb_arn)
ALB_SUFFIX=$(terraform output -raw alb_arn_suffix)
echo "##vso[task.setvariable variable=APP_URL]$APP_URL"

STACK="fin-$ENV-edge"
CS="cs-$BUILD-apply"
RESULT=$(bash "$ROOT/scripts/edge-changeset.sh" "$ENV" "$CS" "$ALB_ARN" "$ALB_SUFFIX" /dev/null | tail -n 1)

if [[ "$RESULT" == "CREATE_COMPLETE" ]]; then
  STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo NONE)
  aws cloudformation execute-change-set --stack-name "$STACK" --change-set-name "$CS"
  if [[ "$STACK_STATUS" == "REVIEW_IN_PROGRESS" ]]; then
    aws cloudformation wait stack-create-complete --stack-name "$STACK"
  else
    aws cloudformation wait stack-update-complete --stack-name "$STACK"
  fi
else
  echo "No WAF/AppConfig changes for $STACK"
fi
