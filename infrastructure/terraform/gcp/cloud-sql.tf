# Provider configuration
# hashicorp/google v4.0
# hashicorp/google-beta v4.0
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

# Cloud SQL instance for TALD UNIA Audio System
resource "google_sql_database_instance" "tald_unia_db" {
  provider = google-beta
  name     = "tald-unia-db-${var.environment}"
  project  = var.project_id
  region   = var.region
  database_version = "POSTGRES_14"
  deletion_protection = true

  settings {
    tier = "db-custom-4-16384"  # 4 vCPU, 16GB RAM
    availability_type = "REGIONAL"
    
    disk_size = 100  # GB
    disk_type = "PD_SSD"
    disk_autoresize = true
    disk_autoresize_limit = 500  # GB

    backup_configuration {
      enabled                        = true
      start_time                    = "02:00"  # 2 AM UTC
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false  # Disable public IP
      private_network = var.vpc_network_id
      require_ssl     = true
      ssl_mode        = "VERIFY_X509"
    }

    database_flags {
      name  = "cloudsql.enable_pg_cron"
      value = "on"
    }
    database_flags {
      name  = "max_connections"
      value = "1000"
    }
    database_flags {
      name  = "shared_buffers"
      value = "4096MB"
    }
    database_flags {
      name  = "work_mem"
      value = "32MB"
    }
    database_flags {
      name  = "maintenance_work_mem"
      value = "512MB"
    }
    database_flags {
      name  = "effective_cache_size"
      value = "12GB"
    }
    database_flags {
      name  = "password_encryption"
      value = "scram-sha-256"
    }
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"  # Log queries taking more than 1 second
    }

    maintenance_window {
      day          = 7  # Sunday
      hour         = 3  # 3 AM UTC
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length    = 4096
      record_application_tags = true
      record_client_address  = true
    }

    user_labels = {
      environment = var.environment
      application = "tald-unia"
      managed_by  = "terraform"
    }
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      settings[0].disk_size,
      settings[0].maintenance_window,
    ]
  }
}

# Outputs for use in other Terraform configurations
output "cloud_sql_instance_name" {
  value       = google_sql_database_instance.tald_unia_db.name
  description = "The name of the Cloud SQL instance"
}

output "cloud_sql_connection_name" {
  value       = google_sql_database_instance.tald_unia_db.connection_name
  description = "The connection name of the Cloud SQL instance"
}

output "cloud_sql_private_ip" {
  value       = google_sql_database_instance.tald_unia_db.private_ip_address
  description = "The private IP address of the Cloud SQL instance"
}

output "cloud_sql_server_ca_cert" {
  value       = google_sql_database_instance.tald_unia_db.server_ca_cert
  description = "The server CA certificate for the Cloud SQL instance"
  sensitive   = true
}