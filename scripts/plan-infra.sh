#!/usr/bin/env bash
# Plan stage: Terraform plan + CloudFormation change set preview, saved for the approver.
# Usage: plan-infra.sh <env> <build-id> <staging-dir> <ecr-registry> <image-tag>
set -euo pipefail
ENV=$1; BUILD=$2; OUT=$3/plan; REGISTRY=$4; TAG=$5
mkdir -p "$OUT"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/infra/terraform"
terraform init -input=false -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=fin/$ENV/terraform.tfstate" -backend-config="region=${AWS_REGION:-ap-south-1}" \
  -backend-config="dynamodb_table=$TF_LOCK_TABLE" -backend-config="encrypt=true"
terraform validate
terraform plan -input=false -out="$OUT/tfplan" -var-file="envs/$ENV.tfvars" \
  -var="ecr_registry=$REGISTRY" -var="image_tag=$TAG"
terraform show -no-color "$OUT/tfplan" > "$OUT/tfplan.txt"

# The edge stack needs the ALB created by Terraform. On the very first run for an
# environment the ALB does not exist yet, so the preview uses placeholder values.
ALB_ARN=$(terraform output -raw alb_arn 2>/dev/null || true)
ALB_SUFFIX=$(terraform output -raw alb_arn_suffix 2>/dev/null || true)
if [[ -z "$ALB_ARN" || -z "$ALB_SUFFIX" ]]; then
  echo "ALB does not exist yet for $ENV: previewing the edge stack with placeholder ALB values"
  ALB_ARN="arn:aws:elasticloadbalancing:${AWS_REGION:-ap-south-1}:000000000000:loadbalancer/app/pending/0000000000000000"
  ALB_SUFFIX="app/pending/0000000000000000"
fi

bash "$ROOT/scripts/edge-changeset.sh" "$ENV" "cs-$BUILD-plan" "$ALB_ARN" "$ALB_SUFFIX" "$OUT/cfn-changes.txt" | tail -n 1
