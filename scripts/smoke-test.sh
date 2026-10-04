#!/usr/bin/env bash
# Post-deployment checks. Usage: smoke-test.sh <base-url> <expected-image-tag>
set -euo pipefail
BASE="${1%/}"; EXPECTED="$2"

wait_for_200() {
  local path=$1 code
  for i in $(seq 1 20); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE$path" || true)
    if [[ "$code" == "200" ]]; then echo "$path -> 200"; return 0; fi
    echo "$path -> $code (attempt $i)"; sleep 6
  done
  echo "##vso[task.logissue type=error]$path unhealthy"
  return 1
}

# 1) Both services answer their health checks
for path in /payments/healthz /reconciliation/healthz; do
  wait_for_200 "$path"
done

# 2) The new build is the one serving traffic (not an old task still behind the ALB)
for svc in payments reconciliation; do
  GOT=$(curl -sf "$BASE/$svc/version" | jq -r .imageTag)
  [[ "$GOT" == "$EXPECTED" ]] || {
    echo "##vso[task.logissue type=error]$svc serves $GOT, expected $EXPECTED"; exit 1; }
done

# 3) A real request works end to end
RESP=$(curl -sf -X POST "$BASE/payments" -H 'Content-Type: application/json' \
  -d '{"amount": 10.50, "currency": "INR", "reference": "smoke-test"}')
[[ "$(echo "$RESP" | jq -r .status)" == "accepted" ]] || {
  echo "##vso[task.logissue type=error]payment was not accepted: $RESP"; exit 1; }

MATCH=$(curl -sf -X POST "$BASE/reconciliation/match" -H 'Content-Type: application/json' \
  -d '{"payments":[{"reference":"smoke","amount":1}],"bank_entries":[{"reference":"smoke","amount":1}]}')
[[ "$(echo "$MATCH" | jq -r '.matched | length')" == "1" ]] || {
  echo "##vso[task.logissue type=error]reconciliation did not match: $MATCH"; exit 1; }

echo "Smoke tests passed for $EXPECTED"
