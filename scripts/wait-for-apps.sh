#!/usr/bin/env bash
# Waits until every expected Argo CD Application is Synced and Healthy.
#   TIMEOUT  seconds to wait (default: 900)
set -euo pipefail

EXPECTED_APPS=(root sealed-secrets cloudnative-pg warehouse-dev)
TIMEOUT="${TIMEOUT:-900}"
deadline=$((SECONDS + TIMEOUT))

while true; do
  status="$(kubectl -n argocd get applications.argoproj.io \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}{end}')"
  ready=true
  for app in "${EXPECTED_APPS[@]}"; do
    grep -qx "$app Synced Healthy" <<<"$status" || ready=false
  done
  if $ready; then
    echo "All Applications are Synced and Healthy:"
    echo "$status"
    exit 0
  fi
  if ((SECONDS >= deadline)); then
    echo "Timed out after ${TIMEOUT}s. Current state:" >&2
    echo "$status" >&2
    exit 1
  fi
  echo "[$(date +%T)] waiting: $(tr '\n' ';' <<<"$status")"
  sleep 15
done
