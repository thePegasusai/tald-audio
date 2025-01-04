# Output configuration for TALD UNIA GCP infrastructure
# Exposes critical infrastructure values for networking, GKE cluster, and service endpoints

# Core project information
output "project_info" {
  description = "Core project configuration information"
  value = {
    project_id  = var.project_id
    region      = var.region
    environment = var.environment
  }
}

# Network information from VPC configuration
output "network_info" {
  description = "VPC and networking configuration details"
  value = {
    vpc_name        = google_compute_network.main.name
    vpc_id          = google_compute_network.main.id
    subnet_name     = google_compute_subnetwork.main.name
    subnet_id       = google_compute_subnetwork.main.id
    firewall_rules  = [
      google_compute_firewall.allow_internal.name
    ]
  }
}

# GKE cluster information
output "gke_info" {
  description = "GKE cluster access and configuration information"
  value = {
    cluster_name            = google_container_cluster.main.name
    cluster_endpoint        = google_container_cluster.main.endpoint
    cluster_ca_certificate  = google_container_cluster.main.master_auth[0].cluster_ca_certificate
    node_pool_name         = google_container_node_pool.main.name
    node_pool_size         = google_container_node_pool.main.initial_node_count
    node_pool_machine_type = var.gke_cluster_config.machine_type
  }
  sensitive = true
}

# Service endpoints for various GCP services
output "service_endpoints" {
  description = "Connection endpoints for GCP services"
  value = {
    # Cloud SQL connection information
    cloud_sql_connection = "projects/${var.project_id}/instances/${var.project_id}-sql"
    
    # Redis host endpoint
    redis_host = "redis-${var.environment}.${var.project_id}.internal"
    
    # Cloud Storage bucket
    cloud_storage_bucket = "gs://${var.project_id}-${var.environment}-audio-storage"
    
    # Cloud TPU endpoint
    cloud_tpu_endpoint = "tpu.googleapis.com/projects/${var.project_id}/locations/${var.region}/nodes/tald-unia-tpu-${var.environment}"
    
    # Cloud CDN endpoint
    cloud_cdn_endpoint = "cdn.googleapis.com/projects/${var.project_id}/locations/global/cdnEndpoints/tald-unia-cdn-${var.environment}"
    
    # Speech-to-Text API endpoint
    speech_to_text_endpoint = "speech.googleapis.com"
    
    # Cloud Bigtable instance
    bigtable_instance = "projects/${var.project_id}/instances/tald-unia-bigtable-${var.environment}"
  }
}

# Network endpoints for service configuration
output "network_endpoints" {
  description = "Network CIDR ranges and configuration"
  value = {
    subnet_cidr   = google_compute_subnetwork.main.ip_cidr_range
    pod_cidr      = google_compute_subnetwork.main.secondary_ip_range[0].ip_cidr_range
    service_cidr  = google_compute_subnetwork.main.secondary_ip_range[1].ip_cidr_range
  }
}