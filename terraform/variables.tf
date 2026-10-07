# These values are normally set from scripts/env.sh, which exports each one as
# a TF_VAR_* environment variable. That keeps env.sh as the single source of
# truth, so the scripts, Helm, and Terraform can't drift apart.

variable "project_id" {
  description = "GCP project ID for the lab (TF_VAR_project_id)"
  type        = string
}

variable "region" {
  description = "GCP region for the network and cluster (TF_VAR_region)"
  type        = string
  default     = "us-west1"
}

variable "cluster_name" {
  description = "GKE cluster name (TF_VAR_cluster_name)"
  type        = string
  default     = "gke-lab"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters: lowercase letters, digits, and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "namespace" {
  description = "Kubernetes namespace the app runs in, used by the Workload Identity binding (TF_VAR_namespace)"
  type        = string
  default     = "hello"
}

variable "app_name" {
  description = "App name, used for the Google and Kubernetes service accounts (TF_VAR_app_name)"
  type        = string
  default     = "hello-api"
}

variable "repo_name" {
  description = "Artifact Registry repository ID (TF_VAR_repo_name)"
  type        = string
  default     = "apps"
}
