# Provider configuration for Google Cloud Platform
# Version: ~> 4.0
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Redis instance for TALD UNIA Audio System's real-time caching
resource "google_redis_instance" "tald_unia_cache" {
  # Instance naming following GCP best practices
  name           = "${var.project_id}-${var.environment}-redis"
  display_name   = "TALD UNIA Audio Cache"
  
  # Core configuration
  tier           = var.memorystore_config.tier
  memory_size_gb = var.memorystore_config.memory_size_gb
  region         = var.region
  redis_version  = var.memorystore_config.version
  
  # Security configuration
  auth_enabled      = var.memorystore_config.auth_enabled
  authorized_network = module.vpc.network_name
  connect_mode      = "PRIVATE_SERVICE_ACCESS"
  
  # Resource labels for management and cost tracking
  labels = {
    environment = var.environment
    application = "tald-unia"
    managed-by  = "terraform"
  }
  
  # Maintenance window configuration for minimal disruption
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 2
        minutes = 0
      }
    }
  }
  
  # Redis configuration optimized for audio processing
  redis_configs = {
    # LRU eviction for efficient memory management
    maxmemory-policy = "allkeys-lru"
    
    # Enable keyspace notifications for cache invalidation
    notify-keyspace-events = "Ex"
    
    # Connection timeout optimized for audio processing
    timeout = "3600"
    
    # Optimize for low latency operations
    maxmemory-samples = "7"
    
    # TCP keepalive for connection stability
    tcp-keepalive = "300"
    
    # Disable persistence for performance
    appendonly = "no"
    save = ""
  }
  
  # Location preference for high availability
  location_id = "${var.region}-a"
  alternative_location_id = "${var.region}-b"
  
  # Read replicas for scalability
  read_replicas_mode = "READ_REPLICAS_ENABLED"
  replica_count      = 1
}

# Output configuration for application integration
output "redis_instance" {
  description = "Redis instance connection details"
  value = {
    host                = google_redis_instance.tald_unia_cache.host
    port                = google_redis_instance.tald_unia_cache.port
    current_location_id = google_redis_instance.tald_unia_cache.current_location_id
  }
  sensitive = true
}

# IAM configuration for Redis instance access
resource "google_project_iam_member" "redis_access" {
  project = var.project_id
  role    = "roles/redis.viewer"
  member  = "serviceAccount:${var.project_id}-sa@${var.project_id}.iam.gserviceaccount.com"
}

# Cloud Monitoring configuration for Redis metrics
resource "google_monitoring_alert_policy" "redis_memory" {
  display_name = "Redis Memory Usage - ${var.environment}"
  project      = var.project_id
  
  conditions {
    display_name = "Memory Usage > 80%"
    condition_threshold {
      filter          = "metric.type=\"redis.googleapis.com/stats/memory/usage_ratio\" resource.type=\"redis_instance\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
    }
  }
  
  notification_channels = [
    "projects/${var.project_id}/notificationChannels/${var.notification_channel_id}"
  ]
  
  alert_strategy {
    auto_close = "1800s"
  }
}