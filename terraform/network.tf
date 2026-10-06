# Custom VPC with secondary ranges for pods and services (VPC-native)
resource "google_compute_network" "lab" {
  name                    = "gke-lab-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "lab" {
  name                     = "gke-lab-subnet"
  region                   = var.region
  network                  = google_compute_network.lab.id
  ip_cidr_range            = "10.40.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.48.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.52.0.0/20"
  }
}

# Outbound internet access for private nodes
resource "google_compute_router" "lab" {
  name    = "gke-lab-router"
  region  = var.region
  network = google_compute_network.lab.id
}

resource "google_compute_router_nat" "lab" {
  name                               = "gke-lab-nat"
  router                             = google_compute_router.lab.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
