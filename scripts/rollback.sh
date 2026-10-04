#!/usr/bin/env bash
# Points each service back at the newest task definition that runs a DIFFERENT image than the live one.
# Usage: rollback.sh <env>
set -euo pipefail
ENV=$1; CLUSTER="fin-$ENV"

image_of() {
  aws ecs describe-task-definition --task-definition "$1" --output text \
    --query 'taskDefinition.containerDefinitions[?name==`app`].image'
}

for svc in payment-service reconciliation-service; do
  LIVE_TD=$(aws ecs describe-services --cluster "$CLUSTER" --services "$svc" --output text \
    --query "services[0].deployments[?status=='PRIMARY'] | [0].taskDefinition")
  LIVE_IMG=$(image_of "$LIVE_TD")

  PREV=""
  for td in $(aws ecs list-task-definitions --family-prefix "fin-$ENV-$svc" --sort DESC \
      --max-items 10 --query 'taskDefinitionArns' --output text); do
    if [[ "$(image_of "$td")" != "$LIVE_IMG" ]]; then PREV=$td; break; fi
  done

  if [[ -z "$PREV" ]]; then
    echo "No earlier image found for $svc - nothing to roll back to"
    continue
  fi
  echo "Rolling $svc back to $PREV"
  aws ecs update-service --cluster "$CLUSTER" --service "$svc" --task-definition "$PREV" > /dev/null
done
echo "Feature flags are only changed by the Flags stage, which runs after a successful deploy."
