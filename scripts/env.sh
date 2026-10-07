#!/usr/bin/env bash
# =============================================================================
# Lab environment variables.
#
# SOURCE this file (don't execute it) so the variables persist in your shell:
#   source scripts/env.sh
#
# Override any value by exporting it before sourcing, e.g.:
#   export PROJECT_ID=my-project REGION=us-central1 && source scripts/env.sh
# =============================================================================

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
export REGION="${REGION:-us-west1}"
export CLUSTER_NAME="${CLUSTER_NAME:-gke-lab}"
export NAMESPACE="${NAMESPACE:-hello}"
export APP_NAME="${APP_NAME:-hello-api}"
export REPO_NAME="${REPO_NAME:-apps}"
export IMAGE_TAG="${IMAGE_TAG:-v1}"
export IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${APP_NAME}"
export TF_STATE_BUCKET="${TF_STATE_BUCKET:-${PROJECT_ID}-tfstate}"

# Feed the same values to Terraform, so names are defined only here.
export TF_VAR_project_id="${PROJECT_ID}"
export TF_VAR_region="${REGION}"
export TF_VAR_cluster_name="${CLUSTER_NAME}"
export TF_VAR_namespace="${NAMESPACE}"
export TF_VAR_app_name="${APP_NAME}"
export TF_VAR_repo_name="${REPO_NAME}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "ERROR: PROJECT_ID is not set and no default gcloud project is configured." >&2
  echo "       Run: export PROJECT_ID=<your-project> && source scripts/env.sh" >&2
  # shellcheck disable=SC2317  # exit only runs when executed instead of sourced
  return 1 2>/dev/null || exit 1
fi

echo "PROJECT_ID=${PROJECT_ID}  REGION=${REGION}  CLUSTER=${CLUSTER_NAME}"
echo "IMAGE=${IMAGE}:${IMAGE_TAG}"
echo "TF_STATE_BUCKET=gs://${TF_STATE_BUCKET}"