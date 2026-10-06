output "get_credentials" {
  description = "Command to configure kubectl for the cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.lab.name} --region ${var.region}"
}

output "app_gsa_email" {
  description = "Google service account the hello-api pods act as"
  value       = google_service_account.app.email
}
