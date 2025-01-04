# Output definitions for TALD UNIA Audio System monitoring infrastructure

# Monitoring namespace output
output "monitoring_namespace" {
  description = "Kubernetes namespace where monitoring components are deployed"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

# Prometheus endpoints output
output "prometheus_endpoints" {
  description = "Internal and external endpoints for Prometheus server with ports and protocols"
  value = {
    internal = "http://prometheus-server.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9090"
    external = var.prometheus_external_endpoint
    metrics  = ":9090/metrics"
    health   = ":9090/-/healthy"
  }
}

# Grafana endpoints output
output "grafana_endpoints" {
  description = "Internal and external endpoints for Grafana dashboard with ports and protocols"
  value = {
    internal = "http://grafana.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3000"
    external = var.grafana_external_endpoint
    api      = ":3000/api"
    health   = ":3000/api/health"
  }
}

# Elasticsearch endpoints output
output "elasticsearch_endpoints" {
  description = "Internal and external endpoints for Elasticsearch cluster"
  value = {
    internal = "http://elasticsearch-master.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9200"
    external = var.elasticsearch_external_endpoint
    kibana   = var.kibana_endpoint
    health   = ":9200/_cluster/health"
  }
}

# Jaeger endpoints output
output "jaeger_endpoints" {
  description = "Internal and external endpoints for Jaeger tracing services"
  value = {
    query     = "http://jaeger-query.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:16686"
    collector = "http://jaeger-collector.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:14268"
    agent     = "http://jaeger-agent.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:6831"
    health    = ":16687/health"
  }
}

# AlertManager endpoints output
output "alertmanager_endpoints" {
  description = "Internal and external endpoints for AlertManager service"
  value = {
    internal = "http://alertmanager.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9093"
    external = var.alertmanager_external_endpoint
    api      = ":9093/api/v2"
    health   = ":9093/-/healthy"
  }
}

# Monitoring credentials output
output "monitoring_credentials" {
  description = "Credentials for monitoring services access"
  sensitive   = true
  value = {
    grafana = {
      admin_username = "admin"
      admin_password = var.grafana_admin_password
    }
    elasticsearch = {
      username = var.elasticsearch_username
      password = var.elasticsearch_password
    }
  }
}

# Monitoring configuration output
output "monitoring_configuration" {
  description = "Configuration parameters for monitoring components"
  value = {
    prometheus = {
      retention_period      = "${var.prometheus_retention_days}d"
      scrape_interval      = "${var.prometheus_scrape_interval}s"
      evaluation_interval  = "${var.prometheus_evaluation_interval}s"
    }
    elasticsearch = {
      retention_policy = var.elasticsearch_retention_policy
      index_pattern   = var.elasticsearch_index_pattern
    }
    jaeger = {
      sampling_rate   = var.jaeger_sampling_rate
      retention_days  = var.jaeger_retention_days
    }
  }
}

# Resource allocation output
output "monitoring_resources" {
  description = "Resource allocations for all monitoring components"
  value = {
    prometheus    = var.prometheus_resources
    grafana      = var.grafana_resources
    elasticsearch = var.elasticsearch_resources
    jaeger       = var.jaeger_resources
    alertmanager = var.alertmanager_resources
  }
}