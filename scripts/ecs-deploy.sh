#!/usr/bin/env bash
# Registers a new task definition revision (new image + IMAGE_TAG only) and updates the services.
# Usage: ecs-deploy.sh <env> <ecr-registry> <image-tag>
set -euo pipefail
ENV=$1; REG=$2; TAG=$3; CLUSTER="fin-$ENV"

for svc in payment-service reconciliation-service; do
  CUR=$(aws ecs describe-task-definition --task-definition "fin-$ENV-$svc" \
    --query taskDefinition)
  # Change only the app image and the IMAGE_TAG variable (so /version reports the new build)
  NEW=$(echo "$CUR" | jq --arg IMG "$REG/fin/$svc:$TAG" --arg TAG "$TAG" '
    .containerDefinitions |= map(
      if .name == "app" then
        .image = $IMG
        | .environment = ((.environment // []) | map(select(.name != "IMAGE_TAG")) + [{name: "IMAGE_TAG", value: $TAG}])
      else . end)
    | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
          .compatibilities, .registeredAt, .registeredBy)')
  ARN=$(aws ecs register-task-definition --cli-input-json "$NEW" \
    --query taskDefinition.taskDefinitionArn --output text)
  echo "$svc -> $ARN"
  aws ecs update-service --cluster "$CLUSTER" --service "$svc" \
    --task-definition "$ARN" > /dev/null
done

for svc in payment-service reconciliation-service; do
  aws ecs wait services-stable --cluster "$CLUSTER" --services "$svc"
  # services-stable also succeeds after an automatic rollback - so check what is really live
  read -r LIVE_TD STATE <<< "$(aws ecs describe-services --cluster "$CLUSTER" \
    --services "$svc" --output text \
    --query "services[0].deployments[?status=='PRIMARY'] | [0].[taskDefinition,rolloutState]")"
  IMG=$(aws ecs describe-task-definition --task-definition "$LIVE_TD" --output text \
    --query 'taskDefinition.containerDefinitions[?name==`app`].image')
  echo "$svc live: $IMG ($STATE)"
  if [[ "$STATE" != "COMPLETED" || "$IMG" != *":$TAG" ]]; then
    echo "##vso[task.logissue type=error]$svc rolled back by circuit breaker/alarm"; exit 1
  fi
done
