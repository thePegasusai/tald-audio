# Provider configuration
# hashicorp/google ~> 4.0
# hashicorp/google-beta ~> 4.0
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
  }
}

# Local variables for resource naming and tagging
locals {
  network_name = "tald-unia-vpc-${var.environment}"
  subnet_name  = "tald-unia-subnet-${var.environment}"
  router_name  = "tald-unia-router-${var.environment}"
  nat_name     = "tald-unia-nat-${var.environment}"
  
  tags = {
    environment  = var.environment
    project      = "tald-unia"
    managed_by   = "terraform"
    component    = "audio-processing"
  }
}

# VPC Network optimized for audio processing
resource "google_compute_network" "main" {
  name                            = local.network_name
  project                         = var.project_id
  auto_create_subnetworks        = false
  routing_mode                   = "GLOBAL"
  mtu                           = 1500  # Optimized for audio packet transmission
  delete_default_routes_on_create = true
  description                    = "VPC network for TALD UNIA audio processing with optimized settings for low latency"

  lifecycle {
    prevent_destroy = true
  }
}

# Subnet configuration with secondary ranges for GKE
resource "google_compute_subnetwork" "main" {
  name                     = local.subnet_name
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range           = var.network_config.subnet_cidr
  private_ip_google_access = true
  
  # Secondary IP ranges for Kubernetes pods and services
  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = var.network_config.pod_cidr
  }
  
  secondary_ip_range {
    range_name    = "service-ranges"
    ip_cidr_range = var.network_config.service_cidr
  }

  # Enable flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling       = 0.5
    metadata           = "INCLUDE_ALL_METADATA"
  }
}

# Internal firewall rules for audio processing
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.network_name}-allow-internal"
  network = google_compute_network.main.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080", "9090"]  # HTTP/HTTPS and monitoring ports
  }

  allow {
    protocol = "udp"
    ports    = ["51820", "10000-20000"]  # Audio streaming and WebRTC ports
  }

  source_ranges = [var.network_config.subnet_cidr]
  target_tags   = ["tald-unia-nodes", "audio-processing"]
  priority      = 1000
  direction     = "INGRESS"

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router for NAT gateway
resource "google_compute_router" "main" {
  name    = local.router_name
  project = var.project_id
  region  = var.region
  network = google_compute_network.main.id

  bgp {
    asn = 64514
  }
}

# NAT gateway for outbound internet access
resource "google_compute_router_nat" "main" {
  name                               = local.nat_name
  project                           = var.project_id
  router                            = google_compute_router.main.name
  region                            = var.region
  nat_ip_allocate_option           = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Global load balancing routes
resource "google_compute_route" "global_route" {
  name        = "${local.network_name}-global-route"
  project     = var.project_id
  network     = google_compute_network.main.name
  dest_range  = "0.0.0.0/0"
  priority    = 1000
  next_hop_gateway = "default-internet-gateway"

  tags = ["tald-unia-nodes"]
}

# Outputs for use in other Terraform configurations
output "vpc_network" {
  description = "VPC network resource information"
  value = {
    network_name = google_compute_network.main.name
    network_id   = google_compute_network.main.id
    subnet_ids   = [google_compute_subnetwork.main.id]
  }
}

output "network_endpoints" {
  description = "Network endpoints for service configuration"
  value = {
    subnet_cidr = google_compute_subnetwork.main.ip_cidr_range
    pod_cidr    = google_compute_subnetwork.main.secondary_ip_range[0].ip_cidr_range
    service_cidr = google_compute_subnetwork.main.secondary_ip_range[1].ip_cidr_range
  }
}