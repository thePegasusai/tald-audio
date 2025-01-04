# Terraform configuration for TALD UNIA Audio System GCP Infrastructure
# Provider versions:
# google: ~> 4.0
# google-beta: ~> 4.0

terraform {
  required_version = ">= 1.0.0"
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

  backend "gcs" {
    bucket         = "tald-unia-terraform-state"
    prefix         = "terraform/state"
    encryption_key = "${var.state_encryption_key}"
  }
}

# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = "${var.region}-a"
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = "${var.region}-a"
}

# VPC Network Module
module "vpc" {
  source         = "./vpc"
  project_id     = var.project_id
  region         = var.region
  environment    = var.environment
  network_config = var.network_config
}

# GKE Cluster Module
module "gke" {
  source            = "./gke"
  project_id        = var.project_id
  region           = var.region
  environment      = var.environment
  gke_cluster_config = var.gke_cluster_config
  depends_on       = [module.vpc]
}

# Cloud SQL Module for Profile Storage
module "cloud_sql" {
  source          = "./cloud-sql"
  project_id      = var.project_id
  region         = var.region
  environment    = var.environment
  cloud_sql_config = var.cloud_sql_config
  depends_on     = [module.vpc]
}

# Memorystore (Redis) Module for Caching
module "memorystore" {
  source             = "./memorystore"
  project_id         = var.project_id
  region            = var.region
  environment       = var.environment
  memorystore_config = var.memorystore_config
  depends_on        = [module.vpc]
}

# Cloud TPU Module for AI Acceleration
module "tpu" {
  source      = "./tpu"
  project_id  = var.project_id
  region     = var.region
  environment = var.environment
  tpu_config  = {
    version          = "v4-8"
    accelerator_type = "v4-8"
    network         = module.vpc.network_name
  }
  depends_on = [module.vpc]
}

# Cloud CDN Module for Audio Content Delivery
module "cdn" {
  source     = "./cdn"
  project_id = var.project_id
  region    = var.region
  environment = var.environment
  cdn_config = {
    enable_global_access = true
    enable_ssl          = true
    backend_bucket      = var.audio_content_bucket
  }
}

# Output core project resource information
output "project_resources" {
  description = "Core project resource information"
  value = {
    project_id          = var.project_id
    region             = var.region
    environment        = var.environment
    tpu_service_endpoint = module.tpu.service_endpoint
    cdn_endpoints       = module.cdn.endpoints
  }
}

# Resource labels for consistent tagging
locals {
  common_labels = {
    project     = var.project_id
    environment = var.environment
    managed_by  = "terraform"
    system      = "tald-unia"
  }
}

# Enable required GCP APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "tpu.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudtrace.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudprofiler.googleapis.com",
    "clouddebugger.googleapis.com",
    "cloudkms.googleapis.com",
    "speech.googleapis.com",
    "bigtable.googleapis.com",
    "redis.googleapis.com",
    "sql-component.googleapis.com",
    "servicenetworking.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = true
  disable_on_destroy        = false
}

# Cloud Storage bucket for audio content
resource "google_storage_bucket" "audio_content" {
  name          = "${var.project_id}-audio-content"
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  labels = local.common_labels
}

# Cloud Monitoring Workspace
resource "google_monitoring_workspace" "workspace" {
  provider     = google-beta
  project      = var.project_id
  display_name = "TALD UNIA Monitoring Workspace"
  labels      = local.common_labels
}

# Cloud Monitoring Alert Policies
resource "google_monitoring_alert_policy" "cpu_usage" {
  display_name = "High CPU Usage Alert"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "CPU Usage > 70%"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.7
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
  alert_strategy {
    auto_close = "1800s"
  }

  user_labels = local.common_labels
}

# Notification channel for alerts
resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Email Notification Channel"
  type         = "email"
  labels = {
    email_address = "alerts@tald-unia.com"
  }
}