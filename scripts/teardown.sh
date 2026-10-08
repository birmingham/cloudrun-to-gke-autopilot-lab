#!/usr/bin/env bash
# =============================================================================
# Remove everything the lab created: Helm release, Cloud Run service, all
# Terraform-managed infrastructure (cluster, network, service accounts, and the
# Artifact Registry repository with its images), and the Cloud Build source
# bucket. Then verify that no clusters or Cloud Run services remain.
#
# The Terraform state bucket is kept by default, since it holds the state
# history. Pass --purge-state to delete it too (only once you're done with
# the lab for good).
#
# Usage: scripts/teardown.sh [--yes] [--purge-state]
#   --yes          skip the confirmation prompt
#   --purge-state  also delete the Terraform state bucket
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck source=scripts/env.sh
source "${SCRIPT_DIR}/env.sh"

ASSUME_YES=false
PURGE_STATE=false
for arg in "$@"; do
  case "${arg}" in
    --yes)         ASSUME_YES=true ;;
    --purge-state) PURGE_STATE=true ;;
    *) echo "Unknown option: ${arg}" >&2; exit 2 ;;
  esac
done

CLOUDBUILD_BUCKET="${PROJECT_ID}_cloudbuild"

if [[ "${ASSUME_YES}" != true ]]; then
  echo "This will destroy all lab resources in project ${PROJECT_ID}."
  if [[ "${PURGE_STATE}" == true ]]; then
    echo "It will ALSO delete the Terraform state bucket gs://${TF_STATE_BUCKET}."
  fi
  read -r -p "Type 'yes' to continue: " answer
  if [[ "${answer}" != "yes" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "==> Uninstalling Helm release (if present) from context: $(kubectl config current-context 2>/dev/null || echo none)"
helm uninstall "${APP_NAME}" -n "${NAMESPACE}" 2>/dev/null || echo "    No Helm release found, skipping"

echo "==> Deleting Cloud Run service (if present)"
if gcloud run services describe "${APP_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  gcloud run services delete "${APP_NAME}" --region "${REGION}" --quiet
else
  echo "    No Cloud Run service found, skipping"
fi

echo "==> Destroying Terraform-managed infrastructure"
terraform -chdir="${REPO_ROOT}/terraform" destroy -auto-approve   # variables come from TF_VAR_* in env.sh

echo "==> Deleting Cloud Build source bucket (if present)"
# Holds the source tarballs uploaded by `gcloud builds submit`; the next build recreates it.
if gcloud storage buckets describe "gs://${CLOUDBUILD_BUCKET}" >/dev/null 2>&1; then
  gcloud storage rm --recursive "gs://${CLOUDBUILD_BUCKET}"
else
  echo "    No Cloud Build bucket found, skipping"
fi

if [[ "${PURGE_STATE}" == true ]]; then
  echo "==> Deleting Terraform state bucket (--purge-state)"
  # Runs after terraform destroy, which needs the state to know what to remove.
  if gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" >/dev/null 2>&1; then
    gcloud storage rm --recursive "gs://${TF_STATE_BUCKET}"
  else
    echo "    No state bucket found, skipping"
  fi
else
  echo "==> Keeping Terraform state bucket gs://${TF_STATE_BUCKET} (use --purge-state to delete)"
fi

echo
echo "==> Verifying teardown"
echo "--- GKE clusters in ${PROJECT_ID}:"
gcloud container clusters list --project "${PROJECT_ID}"
echo "--- Cloud Run services in ${REGION}:"
gcloud run services list --project "${PROJECT_ID}" --region "${REGION}"

REMAINING_CLUSTERS="$(gcloud container clusters list --project "${PROJECT_ID}" --format='value(name)')"
REMAINING_SERVICES="$(gcloud run services list --project "${PROJECT_ID}" --region "${REGION}" --format='value(metadata.name)')"

echo
if [[ -z "${REMAINING_CLUSTERS}" && -z "${REMAINING_SERVICES}" ]]; then
  echo "Teardown complete: no GKE clusters or Cloud Run services remain."
else
  echo "WARNING: resources still exist:" >&2
  [[ -n "${REMAINING_CLUSTERS}" ]] && echo "  GKE clusters: ${REMAINING_CLUSTERS}" >&2
  [[ -n "${REMAINING_SERVICES}" ]] && echo "  Cloud Run services: ${REMAINING_SERVICES}" >&2
  exit 1
fi