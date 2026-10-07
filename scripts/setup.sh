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

echo "==> Ensuring Terraform state bucket gs://${TF_STATE_BUCKET} exists"
# Terraform can't create the bucket that holds its own state, so it's created here.
if gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" >/dev/null 2>&1; then
  echo "    Bucket already exists, skipping"
else
  gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi
# Versioning keeps prior state files, so a bad apply or corrupted state can be recovered.
gcloud storage buckets update "gs://${TF_STATE_BUCKET}" --versioning >/dev/null
echo "    Versioning enabled"

echo "==> Granting Cloud Build permissions to the build service account"
# New projects run Cloud Build as the Compute Engine default service account,
# which no longer gets broad permissions automatically. Without this role,
# builds fail with "does not have storage.objects.get access".
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
BUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
BUILD_ROLE="roles/cloudbuild.builds.builder"

# The default service account appears shortly after the Compute API is enabled.
for attempt in 1 2 3 4 5 6; do
  if gcloud iam service-accounts describe "${BUILD_SA}" >/dev/null 2>&1; then
    break
  fi
  echo "    Waiting for ${BUILD_SA} to be created (attempt ${attempt}/6)"
  sleep 10
done

EXISTING_BINDING="$(gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten='bindings[].members' \
  --filter="bindings.role=${BUILD_ROLE} AND bindings.members=serviceAccount:${BUILD_SA}" \
  --format='value(bindings.role)')"
if [[ -n "${EXISTING_BINDING}" ]]; then
  echo "    ${BUILD_SA} already has ${BUILD_ROLE}, skipping"
else
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${BUILD_SA}" \
    --role="${BUILD_ROLE}" \
    --condition=None \
    --quiet >/dev/null
  echo "    Granted ${BUILD_ROLE} to ${BUILD_SA}"
fi

echo "==> Building ${IMAGE}:${IMAGE_TAG} with Cloud Build"
# A newly granted IAM role can take a minute or two to take effect, so retry.
for attempt in 1 2 3 4; do
  if gcloud builds submit "${REPO_ROOT}/${APP_NAME}/" --tag "${IMAGE}:${IMAGE_TAG}"; then
    break
  fi
  if [[ ${attempt} -eq 4 ]]; then
    echo "ERROR: Cloud Build failed after ${attempt} attempts." >&2
    exit 1
  fi
  echo "    Build failed (attempt ${attempt}/4); waiting 30s for IAM changes to propagate, then retrying"
  sleep 30
done

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
echo "      terraform -chdir=terraform init -backend-config=\"bucket=${TF_STATE_BUCKET}\""