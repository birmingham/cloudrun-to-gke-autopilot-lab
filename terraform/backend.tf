# Remote state in GCS. The bucket name is supplied at init time (partial
# configuration) because backend blocks can't use variables:
#
#   terraform init -backend-config="bucket=${TF_STATE_BUCKET}"
#
# scripts/setup.sh creates the bucket with versioning and uniform access.
terraform {
  backend "gcs" {
    prefix = "cloudrun-to-gke-autopilot-lab"
  }
}
