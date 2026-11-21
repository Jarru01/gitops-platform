#!/usr/bin/env bash
# Creates the kind cluster, installs Argo CD and hands the rest to GitOps: Argo
# CD then deploys everything under clusters/kind from this Git repository.
#
#   SEALED_SECRETS_KEY  path to the sealing private key
#                       (default: ~/.config/gitops-platform/sealed-secrets.key)
#   TARGET_REVISION     Git branch, tag or commit Argo CD deploys (default: main)
#
# Used both for local runs and by .github/workflows/e2e.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=gitops-platform
KEY_FILE="${SEALED_SECRETS_KEY:-$HOME/.config/gitops-platform/sealed-secrets.key}"
CERT_FILE=bootstrap/sealed-secrets/sealing-key.crt
TARGET_REVISION="${TARGET_REVISION:-main}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Sealing key not found at $KEY_FILE." >&2
  echo "Set SEALED_SECRETS_KEY, or create your own key and reseal the secrets (README, \"Secrets\")." >&2
  exit 1
fi

echo "==> kind cluster"
if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --config bootstrap/kind-config.yaml --wait 120s
fi
kubectl config use-context "kind-$CLUSTER"

echo "==> Sealed Secrets key"
# Created before the controller starts, so the controller adopts this key
# instead of generating a new one, and the SealedSecrets in Git decrypt.
kubectl -n kube-system create secret tls sealed-secrets-key \
    --cert="$CERT_FILE" --key="$KEY_FILE" --dry-run=client -o yaml \
  | kubectl label --local -f - sealedsecrets.bitnami.com/sealed-secrets-key=active -o yaml \
  | kubectl apply -f -

echo "==> Argo CD"
kubectl apply --server-side --force-conflicts -k bootstrap/argocd
kubectl wait --for condition=established --timeout=120s crd/applications.argoproj.io
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=600s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=600s

echo "==> Root application (revision $TARGET_REVISION)"
sed -e "s|targetRevision: main|targetRevision: $TARGET_REVISION|" \
    -e "s|value: main|value: $TARGET_REVISION|" \
    bootstrap/root-app.yaml | kubectl apply -f -

scripts/wait-for-apps.sh
