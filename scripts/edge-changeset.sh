#!/usr/bin/env bash
# Creates a CloudFormation change set for the "edge" stack (AWS WAF + AppConfig).
# Usage: edge-changeset.sh <env> <change-set-name> <alb-arn> <alb-arn-suffix> <summary-file>
# The resource summary is written to <summary-file>; the LAST line printed on stdout is
# either CREATE_COMPLETE (there are changes) or NO_CHANGES.
set -euo pipefail
ENV=$1; CS=$2; ALB_ARN=$3; ALB_SUFFIX=$4; SUMMARY=$5
STACK="fin-$ENV-edge"
cd "$(dirname "$0")/../infra/cloudformation"

# A stack that only has a pending CREATE change set is in REVIEW_IN_PROGRESS and needs another CREATE one
STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo NONE)
if [[ "$STATUS" == "NONE" || "$STATUS" == "REVIEW_IN_PROGRESS" ]]; then TYPE=CREATE; else TYPE=UPDATE; fi

# ALB details come from Terraform at run time, so they are added to the static per-env parameters
PARAMS=$(mktemp)
jq --arg arn "$ALB_ARN" --arg suffix "$ALB_SUFFIX" \
  '. + [{"ParameterKey":"AlbArn","ParameterValue":$arn},{"ParameterKey":"AlbArnSuffix","ParameterValue":$suffix}]' \
  "params/$ENV.json" > "$PARAMS"

aws cloudformation create-change-set --stack-name "$STACK" --change-set-name "$CS" \
  --change-set-type "$TYPE" --template-body file://edge.yaml \
  --parameters "file://$PARAMS" --capabilities CAPABILITY_IAM \
  --tags Key=app,Value=fin Key=build,Value="$CS" > /dev/null

if aws cloudformation wait change-set-create-complete \
    --stack-name "$STACK" --change-set-name "$CS" 2>/dev/null; then
  aws cloudformation describe-change-set --stack-name "$STACK" --change-set-name "$CS" \
    --query 'Changes[].ResourceChange.[Action,LogicalResourceId,Replacement]' \
    --output text > "$SUMMARY"
  echo CREATE_COMPLETE
else
  REASON=$(aws cloudformation describe-change-set --stack-name "$STACK" \
    --change-set-name "$CS" --query StatusReason --output text)
  if [[ "$REASON" == *"didn't contain changes"* || "$REASON" == *"No updates"* ]]; then
    echo "No WAF/AppConfig changes" > "$SUMMARY"
    aws cloudformation delete-change-set --stack-name "$STACK" --change-set-name "$CS"
    echo NO_CHANGES
  else
    echo "##vso[task.logissue type=error]Change set failed: $REASON" >&2
    exit 1
  fi
fi
