# Adopt the Artifact Registry repository that scripts/setup.sh creates with
# gcloud. It must exist before Terraform runs, because setup.sh builds and
# pushes the image for the Cloud Run baseline first.
#
# On the first plan/apply, Terraform imports the existing repository into
# state. Once it's in state, this block is a no-op, so it can stay in place.
# Expressions in the id require Terraform 1.6 or later.
#
# Note: plan fails if the repository doesn't exist yet, so run
# scripts/setup.sh before Terraform.
import {
  to = google_artifact_registry_repository.apps
  id = "projects/${var.project_id}/locations/${var.region}/repositories/${var.repo_name}"
}
