# Core project variables
variable "project_id" {
  type        = string
  description = "The GCP project ID where resources will be created"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be between 6 and 30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  type        = string
  description = "The GCP region where resources will be created"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+\\d+$", var.region))
    error_message = "Region must be a valid GCP region name (e.g., us-central1)."
  }
}

variable "environment" {
  type        = string
  description = "The deployment environment (dev, staging, prod)"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Cloud TPU configuration for AI acceleration
variable "tpu_config" {
  type        = map(string)
  description = "Cloud TPU configuration for AI acceleration"
  default = {
    type               = "v4-8"
    accelerator_type   = "tpu-v4"
    tensorflow_version = "2.13"
    preemptible       = "false"
    reserved          = "true"
  }
}

# Cloud CDN configuration for audio content delivery
variable "cdn_config" {
  type        = map(string)
  description = "Cloud CDN configuration for audio content delivery"
  default = {
    enable_cache     = "true"
    cache_mode       = "CACHE_ALL_STATIC"
    default_ttl      = "3600"
    client_ttl       = "600"
    negative_caching = "true"
  }
}

# Speech-to-Text configuration for voice processing
variable "speech_config" {
  type        = map(string)
  description = "Speech-to-Text configuration for voice processing"
  default = {
    model                        = "premium"
    enable_speaker_diarization   = "true"
    enable_automatic_punctuation = "true"
    use_enhanced                 = "true"
  }
}

# Cloud Bigtable configuration for time-series data
variable "bigtable_config" {
  type        = map(string)
  description = "Cloud Bigtable configuration for time-series data"
  default = {
    instance_type         = "PRODUCTION"
    storage_type         = "SSD"
    autoscaling_min_nodes = "3"
    autoscaling_max_nodes = "10"
    autoscaling_cpu_target = "40"
  }
}

# Network configuration settings
variable "network_config" {
  type        = map(string)
  description = "Network configuration settings including CIDR ranges"
  default = {
    subnet_cidr   = "10.0.0.0/20"
    pod_cidr      = "10.1.0.0/16"
    service_cidr  = "10.2.0.0/20"
  }
}

# GKE cluster configuration settings
variable "gke_cluster_config" {
  type        = map(string)
  description = "GKE cluster configuration settings"
  default = {
    service_account  = "tald-unia-gke@${var.project_id}.iam.gserviceaccount.com"
    min_node_count   = "3"
    max_node_count   = "10"
    machine_type     = "n2-standard-4"
    disk_size_gb     = "100"
    disk_type        = "pd-ssd"
    auto_repair      = "true"
    auto_upgrade     = "true"
    max_surge        = "1"
    max_unavailable  = "0"
  }
}