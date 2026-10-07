#!/usr/bin/env bash
# =============================================================================
# Remove everything the lab created: Helm release, Cloud Run service, and all
# Terraform-managed infrastructure (cluster, network, service accounts, and
# the Artifact Registry repository with its images).
#
# Usage: scripts/teardown.sh          (asks for confirmation)
#        scripts/teardown.sh --yes    (no prompt)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck source=scripts/env.sh
source "${SCRIPT_DIR}/env.sh"

if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Destroy all lab resources in project ${PROJECT_ID}? Type 'yes' to continue: " answer
  if [[ "${answer}" != "yes" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "==> Uninstalling Helm release (if present)"
helm uninstall "${APP_NAME}" -n "${NAMESPACE}" 2>/dev/null || echo "    No Helm release found, skipping"

echo "==> Deleting Cloud Run service (if present)"
if gcloud run services describe "${APP_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  gcloud run services delete "${APP_NAME}" --region "${REGION}" --quiet
else
  echo "    No Cloud Run service found, skipping"
fi

echo "==> Destroying Terraform-managed infrastructure"
terraform -chdir="${REPO_ROOT}/terraform" destroy -auto-approve   # variables come from TF_VAR_* in env.sh

echo
echo "Teardown complete."