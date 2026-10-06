#!/usr/bin/env bash
# =============================================================================
# Point kubectl at the lab cluster and make sure the app namespace exists.
# Run after `terraform apply` has created the cluster.
#
# Usage: scripts/connect.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/env.sh
source "${SCRIPT_DIR}/env.sh"

echo "==> Fetching credentials for ${CLUSTER_NAME}"
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}"

echo "==> Ensuring namespace '${NAMESPACE}' exists"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo
kubectl get nodes 2>/dev/null || echo "(Autopilot adds nodes only when pods are scheduled)"
echo "Next: deploy with Helm (see README, step 4)."
