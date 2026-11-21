#!/usr/bin/env bash
# Generates new random credentials for every warehouse overlay and seals them
# with the public sealing certificate. Only the private key can decrypt them;
# the plaintext never touches the disk.
#
#   SEALING_CERT  public certificate (default: bootstrap/sealed-secrets/sealing-key.crt)
#
# Needs kubectl, kubeseal and openssl.
set -euo pipefail
cd "$(dirname "$0")/.."

CERT="${SEALING_CERT:-bootstrap/sealed-secrets/sealing-key.crt}"

random_password() {
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
}

seal() {
  kubeseal --cert "$CERT" --format yaml | sed '/^---$/d'
}

for env in dev prod; do
  ns="warehouse-$env"
  out="apps/warehouse/overlays/$env/sealed-secrets.yaml"
  {
    echo "# Credentials for namespace $ns, sealed by scripts/seal-secrets.sh with"
    echo "# bootstrap/sealed-secrets/sealing-key.crt. See README, \"Secrets\"."
    echo "---"
    kubectl create secret generic warehouse-db-credentials --namespace "$ns" \
        --type=kubernetes.io/basic-auth \
        --from-literal=username=warehouse \
        --from-literal=password="$(random_password)" \
        --dry-run=client -o yaml | seal
    echo "---"
    kubectl create secret generic warehouse-app-secrets --namespace "$ns" \
        --from-literal=WAREHOUSE_RIADITEL_HESLO="$(random_password)" \
        --dry-run=client -o yaml | seal
  } >"$out"
  echo "Wrote $out"
done
