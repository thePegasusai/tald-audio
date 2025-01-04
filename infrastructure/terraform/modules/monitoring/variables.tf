# Cluster configuration
variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster where monitoring will be deployed"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "Cluster name cannot be empty"
  }
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for monitoring components"
  default     = "monitoring"
}

# Prometheus configuration
variable "prometheus_retention_days" {
  type        = number
  description = "Number of days to retain Prometheus metrics data"
  default     = 30
  validation {
    condition     = var.prometheus_retention_days >= 1 && var.prometheus_retention_days <= 365
    error_message = "Prometheus retention days must be between 1 and 365"
  }
}

variable "metrics_scrape_interval" {
  type        = string
  description = "Interval at which Prometheus scrapes metrics from targets"
  default     = "15s"
  validation {
    condition     = can(regex("^[0-9]+[smh]$", var.metrics_scrape_interval))
    error_message = "Metrics scrape interval must be a valid time duration (e.g., 15s, 1m, 1h)"
  }
}

variable "prometheus_resources" {
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  description = "Resource requests and limits for Prometheus server"
  default = {
    requests = {
      cpu    = "1"
      memory = "2Gi"
    }
    limits = {
      cpu    = "2"
      memory = "4Gi"
    }
  }
}

# Grafana configuration
variable "grafana_admin_password" {
  type        = string
  description = "Admin password for Grafana dashboard access"
  sensitive   = true
  validation {
    condition     = length(var.grafana_admin_password) >= 8
    error_message = "Grafana admin password must be at least 8 characters long"
  }
}

variable "grafana_resources" {
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  description = "Resource requests and limits for Grafana"
  default = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "1"
      memory = "2Gi"
    }
  }
}

# Elasticsearch configuration
variable "elasticsearch_storage_size" {
  type        = string
  description = "Storage size for Elasticsearch data"
  default     = "50Gi"
  validation {
    condition     = can(regex("^[0-9]+[MGT]i$", var.elasticsearch_storage_size))
    error_message = "Elasticsearch storage size must be a valid Kubernetes storage size (e.g., 50Gi)"
  }
}

# Jaeger configuration
variable "jaeger_storage_type" {
  type        = string
  description = "Storage backend type for Jaeger tracing data"
  default     = "elasticsearch"
  validation {
    condition     = contains(["memory", "elasticsearch", "cassandra"], var.jaeger_storage_type)
    error_message = "Jaeger storage type must be one of: memory, elasticsearch, cassandra"
  }
}

# AlertManager configuration
variable "enable_alertmanager" {
  type        = bool
  description = "Enable or disable AlertManager deployment"
  default     = true
}