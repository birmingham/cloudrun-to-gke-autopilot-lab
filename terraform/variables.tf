variable "project_id" {
  description = "GCP project ID for the lab"
  type        = string
}

variable "region" {
  description = "GCP region for the network and cluster"
  type        = string
  default     = "us-west1"
}
