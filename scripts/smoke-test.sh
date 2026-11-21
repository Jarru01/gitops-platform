#!/usr/bin/env bash
# Port-forwards the warehouse Service and checks that the login page answers
# with HTTP 200 and contains the login form.
set -euo pipefail

NAMESPACE="${NAMESPACE:-warehouse-dev}"
PORT="${PORT:-8080}"

kubectl -n "$NAMESPACE" rollout status deployment/warehouse --timeout=300s

log="$(mktemp)"
page="$(mktemp)"
kubectl -n "$NAMESPACE" port-forward service/warehouse "$PORT:80" >"$log" 2>&1 &
pf_pid=$!
trap 'kill "$pf_pid" 2>/dev/null || true' EXIT

code=000
for _ in $(seq 1 30); do
  code="$(curl -s -o "$page" -w '%{http_code}' "http://localhost:$PORT/" || true)"
  [[ "$code" == 200 ]] && break
  sleep 2
done

echo "GET http://localhost:$PORT/ -> HTTP $code"
if [[ "$code" != 200 ]]; then
  cat "$log" >&2
  exit 1
fi
# The login form posts to /prihlasenie (SecurityConfig.loginProcessingUrl).
grep -q 'action="/prihlasenie"' "$page"
echo "Login page served by the warehouse app."
