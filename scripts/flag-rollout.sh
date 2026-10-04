#!/usr/bin/env bash
# Uploads the flags file as a new AppConfig version and starts a gradual, alarm-guarded deployment.
# Usage: flag-rollout.sh <env> <flags-json>
set -euo pipefail
ENV=$1; FILE=$2; STACK="fin-$ENV-edge"
out() { aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
APP=$(out AppConfigAppId); PROFILE=$(out FlagsProfileId)
APPENV=$(out AppConfigEnvId); STRATEGY=$(out GradualStrategyId)

VER=$(aws appconfig create-hosted-configuration-version --application-id "$APP" \
  --configuration-profile-id "$PROFILE" --content-type application/json \
  --content "fileb://$FILE" /dev/null --query VersionNumber --output text)
DEP=$(aws appconfig start-deployment --application-id "$APP" --environment-id "$APPENV" \
  --deployment-strategy-id "$STRATEGY" --configuration-profile-id "$PROFILE" \
  --configuration-version "$VER" --query DeploymentNumber --output text)

while true; do
  STATE=$(aws appconfig get-deployment --application-id "$APP" --environment-id "$APPENV" \
    --deployment-number "$DEP" --query State --output text)
  echo "Flag deployment $DEP: $STATE"
  case "$STATE" in
    COMPLETE) exit 0 ;;
    ROLLED_BACK|ROLLING_BACK|REVERTED)
      echo "##vso[task.logissue type=error]Alarm fired - AppConfig rolled the flag back"
      exit 1 ;;
  esac
  sleep 30
done
