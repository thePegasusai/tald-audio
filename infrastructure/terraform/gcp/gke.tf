# Provider configuration for GCP
provider "google" {
  version = "~> 4.0"
}

provider "google-beta" {
  version = "~> 4.0"
}

# Local variables for resource naming and configuration
locals {
  cluster_name = "tald-unia-gke-${var.environment}"
  node_pool_name = "tald-unia-node-pool-${var.environment}"
  labels = {
    environment = var.environment
    project     = "tald-unia"
    managed_by  = "terraform"
    component   = "audio-processing"
  }
  monitoring_config = {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    managed_prometheus = true
  }
}

# GKE Cluster resource
resource "google_container_cluster" "main" {
  provider = google-beta
  name     = local.cluster_name
  location = var.region

  # Network configuration
  network    = google_compute_network.main.name
  subnetwork = google_compute_subnetwork.main.name

  # Initial node configuration
  initial_node_count       = 1
  remove_default_node_pool = true

  # Security configuration
  enable_shielded_nodes = true
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Network security configuration
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.0/8"
      display_name = "VPC"
    }
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block = "172.16.0.0/28"
  }

  # Monitoring configuration
  monitoring_config {
    enable_components = local.monitoring_config.enable_components
    managed_prometheus {
      enabled = local.monitoring_config.managed_prometheus
    }
  }

  # Release channel configuration
  release_channel {
    channel = "REGULAR"
  }

  # Resource labels
  resource_labels = local.labels
}

# Node Pool configuration
resource "google_container_node_pool" "main" {
  provider = google-beta
  name     = local.node_pool_name
  location = var.region
  cluster  = google_container_cluster.main.name

  initial_node_count = var.gke_cluster_config.min_node_count

  # Autoscaling configuration
  autoscaling {
    min_node_count  = var.gke_cluster_config.min_node_count
    max_node_count  = var.gke_cluster_config.max_node_count
    location_policy = "BALANCED"
  }

  # Node configuration
  node_config {
    machine_type = var.gke_cluster_config.machine_type
    service_account = var.gke_cluster_config.service_account

    # OAuth scope configuration
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Labels and metadata
    labels = local.labels
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Disk configuration
    disk_size_gb = var.gke_cluster_config.disk_size_gb
    disk_type    = var.gke_cluster_config.disk_type

    # Workload identity configuration
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Security configuration
    shielded_instance_config {
      enable_secure_boot = true
    }
  }

  # Management configuration
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Output configuration
output "gke_cluster" {
  description = "GKE cluster information"
  value = {
    cluster_name   = google_container_cluster.main.name
    endpoint       = google_container_cluster.main.endpoint
    master_version = google_container_cluster.main.master_version
    location       = google_container_cluster.main.location
  }
}