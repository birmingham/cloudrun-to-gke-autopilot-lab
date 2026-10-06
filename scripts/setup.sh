#!/usr/bin/env bash
# =============================================================================
# One-time project setup, image build, and Cloud Run baseline deploy.
# Safe to rerun: each step checks current state before acting, including
# authentication (you're only prompted to log in when credentials are missing).
#
# Usage: scripts/setup.sh [image-tag]     (default tag: v1)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"

# Allow the tag to be passed as the first argument.
if [[ $# -ge 1 ]]; then
  export IMAGE_TAG="$1"
fi

# shellcheck source=scripts/env.sh
source "${SCRIPT_DIR}/env.sh"

echo "==> Checking gcloud user login"
if [[ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)" ]]; then
  echo "    Logged in as $(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
else
  gcloud auth login
fi

echo "==> Checking Application Default Credentials (used by Terraform)"
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "    Application Default Credentials found"
else
  gcloud auth application-default login
fi

echo "==> Setting gcloud project"
gcloud config set project "${PROJECT_ID}" --quiet

echo "==> Setting ADC quota project"
gcloud auth application-default set-quota-project "${PROJECT_ID}" --quiet \
  || echo "    Could not set quota project (non-fatal); Terraform may show a quota warning"

echo "==> Enabling required APIs"
gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  compute.googleapis.com

echo "==> Ensuring Artifact Registry repository '${REPO_NAME}' exists"
if gcloud artifacts repositories describe "${REPO_NAME}" --location="${REGION}" >/dev/null 2>&1; then
  echo "    Repository already exists, skipping"
else
  gcloud artifacts repositories create "${REPO_NAME}" \
    --repository-format=docker \
    --location="${REGION}"
fi

echo "==> Building ${IMAGE}:${IMAGE_TAG} with Cloud Build"
gcloud builds submit "${REPO_ROOT}/${APP_NAME}/" --tag "${IMAGE}:${IMAGE_TAG}"

echo "==> Deploying Cloud Run baseline"
gcloud run deploy "${APP_NAME}" \
  --image "${IMAGE}:${IMAGE_TAG}" \
  --region "${REGION}" \
  --concurrency 80 \
  --min-instances 1 \
  --max-instances 10 \
  --allow-unauthenticated

echo
echo "Done. Cloud Run URL:"
gcloud run services describe "${APP_NAME}" --region "${REGION}" --format='value(status.url)'
echo
echo "Next: provision the cluster with Terraform (see README, step 2)."
