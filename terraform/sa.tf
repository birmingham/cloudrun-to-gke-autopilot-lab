# Least-privilege service account for the cluster's nodes
resource "google_service_account" "nodes" {
  account_id   = "gke-lab-nodes"
  display_name = "GKE lab node service account"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Workload Identity: Kubernetes SA <namespace>/<app_name> acts as this Google SA
resource "google_service_account" "app" {
  account_id   = var.app_name
  display_name = "${var.app_name} workload identity"
}

resource "google_service_account_iam_member" "app_wi" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.app_name}]"

  # The workload identity pool exists only after the cluster is created.
  depends_on = [google_container_cluster.lab]
}
