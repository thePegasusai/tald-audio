# Provider configuration
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11.0"
    }
  }
}

# Create monitoring namespace with enhanced security labels
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
    labels = {
      name            = "monitoring"
      environment     = var.cluster_name
      security-tier   = "critical"
      monitoring-type = "audio-system"
    }
  }
}

# Deploy Prometheus with audio metrics collection configuration
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = "15.0.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    file("../../../kubernetes/monitoring/prometheus-values.yaml")
  ]

  set {
    name  = "server.retention"
    value = "${var.prometheus_retention_days}d"
  }

  set {
    name  = "server.global.scrape_interval"
    value = var.metrics_scrape_interval
  }

  set {
    name  = "server.resources.requests.cpu"
    value = var.prometheus_resources.requests.cpu
  }

  set {
    name  = "server.resources.requests.memory"
    value = var.prometheus_resources.requests.memory
  }

  set {
    name  = "server.resources.limits.cpu"
    value = var.prometheus_resources.limits.cpu
  }

  set {
    name  = "server.resources.limits.memory"
    value = var.prometheus_resources.limits.memory
  }
}

# Deploy Grafana with audio-specific dashboards
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "6.50.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    file("../../../kubernetes/monitoring/grafana-values.yaml")
  ]

  set_sensitive {
    name  = "adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "resources.requests.cpu"
    value = var.grafana_resources.requests.cpu
  }

  set {
    name  = "resources.requests.memory"
    value = var.grafana_resources.requests.memory
  }

  set {
    name  = "resources.limits.cpu"
    value = var.grafana_resources.limits.cpu
  }

  set {
    name  = "resources.limits.memory"
    value = var.grafana_resources.limits.memory
  }

  depends_on = [helm_release.prometheus]
}

# Deploy Elasticsearch for security monitoring and log aggregation
resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  version    = "7.17.3"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    file("../../../kubernetes/monitoring/elk-values.yaml")
  ]

  set {
    name  = "volumeClaimTemplate.resources.requests.storage"
    value = var.elasticsearch_storage_size
  }
}

# Deploy Jaeger for audio processing tracing
resource "helm_release" "jaeger" {
  name       = "jaeger"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"
  version    = "2.40.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    file("../../../kubernetes/monitoring/jaeger-values.yaml")
  ]

  set {
    name  = "storage.type"
    value = var.jaeger_storage_type
  }

  set {
    name  = "elasticsearch.host"
    value = "elasticsearch-master.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local"
  }

  depends_on = [helm_release.elasticsearch]
}

# Deploy AlertManager if enabled
resource "helm_release" "alertmanager" {
  count      = var.enable_alertmanager ? 1 : 0
  name       = "alertmanager"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "alertmanager"
  version    = "0.24.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    file("../../../kubernetes/monitoring/alertmanager-values.yaml")
  ]

  depends_on = [helm_release.prometheus]
}

# Create ConfigMap for audio metrics dashboards
resource "kubernetes_config_map" "audio_dashboards" {
  metadata {
    name      = "audio-dashboards"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "true"
    }
  }

  data = {
    "audio-metrics.json"    = file("../../../kubernetes/monitoring/dashboards/audio-metrics.json")
    "security-metrics.json" = file("../../../kubernetes/monitoring/dashboards/security-metrics.json")
  }

  depends_on = [helm_release.grafana]
}

# Export monitoring resources
output "monitoring_resources" {
  value = {
    prometheus_release    = helm_release.prometheus
    grafana_release      = helm_release.grafana
    elasticsearch_release = helm_release.elasticsearch
    jaeger_release       = helm_release.jaeger
  }
  description = "Monitoring stack resource references"
}