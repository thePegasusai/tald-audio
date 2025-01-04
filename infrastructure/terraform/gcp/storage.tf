# Configure GCP providers
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

# Cloud Storage bucket for audio samples with lifecycle management and CORS
resource "google_storage_bucket" "audio_samples" {
  name                        = "${var.project_id}-audio-samples-${var.environment}"
  location                    = var.region
  storage_class              = "STANDARD"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
      with_state = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
    purpose     = "audio-storage"
  }
}

# Cloud Storage bucket for AI models
resource "google_storage_bucket" "ai_models" {
  name                        = "${var.project_id}-ai-models-${var.environment}"
  location                    = var.region
  storage_class              = "STANDARD"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
    purpose     = "model-storage"
  }
}

# Cloud Bigtable instance for time-series audio processing data
resource "google_bigtable_instance" "audio_processing" {
  name                = "${var.project_id}-bt-${var.environment}"
  deletion_protection = true

  cluster {
    cluster_id   = "audio-processing-cluster"
    zone         = "${var.region}-a"
    num_nodes    = var.bigtable_config["autoscaling_min_nodes"]
    storage_type = var.bigtable_config["storage_type"]
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
    purpose     = "audio-processing"
  }
}

# Cloud Bigtable table for audio metrics with column family configuration
resource "google_bigtable_table" "audio_metrics" {
  name          = "audio-metrics"
  instance_name = google_bigtable_instance.audio_processing.name

  column_family {
    family = "metrics"
    gc_policy {
      max_age = "168h"  # 7 days retention
    }
  }
}

# Output the created storage resource names for reference
output "storage_resources" {
  value = {
    audio_bucket_name       = google_storage_bucket.audio_samples.name
    model_bucket_name       = google_storage_bucket.ai_models.name
    bigtable_instance_name = google_bigtable_instance.audio_processing.name
  }
  description = "Names of created storage resources"
}