resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric  = true
  special = false
}

locals {
  cluster_name = "gke-${random_string.suffix.result}"
}

resource "google_container_cluster" "primary" {
  name               = local.cluster_name
  location           = var.zone
  project            = var.project
  initial_node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  min_master_version = var.cluster_version

  # Enable VPC-native (alias IP) for pod IPs
  ip_allocation_policy {}
}