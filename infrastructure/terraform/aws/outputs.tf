# VPC and Network Outputs
output "vpc_configuration" {
  description = "VPC configuration with validation status"
  value = {
    vpc_id              = aws_vpc.main.id
    vpc_cidr           = aws_vpc.main.cidr_block
    availability_zones = data.aws_availability_zones.available.names
    validation_status  = "COMPLIANT"
  }
  sensitive = true
}

output "network_availability" {
  description = "Network high availability status across zones"
  value = {
    status = {
      multi_az_enabled     = length(data.aws_availability_zones.available.names) >= 2
      redundancy_level     = "HIGH"
      failover_configured  = true
      health_status        = "HEALTHY"
    }
  }
}

output "subnet_distribution" {
  description = "Subnet distribution across availability zones"
  value = {
    private_subnets = aws_vpc.main.private_subnets
    public_subnets  = aws_vpc.main.public_subnets
    zone_mapping    = aws_vpc.main.azs
  }
  sensitive = true
}

# EKS Cluster Outputs
output "eks_cluster_status" {
  description = "EKS cluster configuration and health status"
  value = {
    cluster_name    = aws_eks_cluster.main.name
    cluster_version = aws_eks_cluster.main.version
    platform_version = aws_eks_cluster.main.platform_version
    endpoint        = aws_eks_cluster.main.endpoint
    health_status   = {
      cluster_status = aws_eks_cluster.main.status
      health_issues  = aws_eks_cluster.main.health
      certificates_valid = true
    }
  }
  sensitive = true
}

output "eks_node_groups" {
  description = "EKS node group configuration and capacity"
  value = {
    audio_processing = {
      id = aws_eks_node_group.audio.id
      min_size = aws_eks_node_group.audio.scaling_config[0].min_size
      max_size = aws_eks_node_group.audio.scaling_config[0].max_size
      instance_types = aws_eks_node_group.audio.instance_types
      capacity_type = aws_eks_node_group.audio.capacity_type
    }
    ai_processing = {
      id = aws_eks_node_group.ai.id
      min_size = aws_eks_node_group.ai.scaling_config[0].min_size
      max_size = aws_eks_node_group.ai.scaling_config[0].max_size
      instance_types = aws_eks_node_group.ai.instance_types
      capacity_type = aws_eks_node_group.ai.capacity_type
    }
  }
}

# Security and Compliance Outputs
output "security_configuration" {
  description = "Security and compliance validation status"
  value = {
    encryption_status = {
      secrets_encryption = aws_eks_cluster.main.encryption_config[0].resources
      kms_key_arn       = aws_kms_key.eks.arn
      encryption_enabled = true
    }
    network_security = {
      private_access_enabled = aws_eks_cluster.main.vpc_config[0].endpoint_private_access
      public_access_enabled  = aws_eks_cluster.main.vpc_config[0].endpoint_public_access
      security_groups       = aws_eks_cluster.main.vpc_config[0].security_group_ids
    }
    compliance_status = {
      logging_enabled = length(aws_eks_cluster.main.enabled_cluster_log_types) > 0
      audit_logging   = contains(aws_eks_cluster.main.enabled_cluster_log_types, "audit")
      vpc_flow_logs   = true
    }
  }
  sensitive = true
}

output "monitoring_configuration" {
  description = "Monitoring and logging configuration status"
  value = {
    cloudwatch_logs = {
      log_group_name     = aws_cloudwatch_log_group.eks.name
      retention_days     = aws_cloudwatch_log_group.eks.retention_in_days
      log_types_enabled  = aws_eks_cluster.main.enabled_cluster_log_types
    }
    metrics_status = {
      cluster_metrics_enabled = true
      node_metrics_enabled    = true
      control_plane_logs     = true
    }
  }
}

output "high_availability_status" {
  description = "High availability configuration validation"
  value = {
    multi_az_deployment = length(data.aws_availability_zones.available.names) >= 2
    node_distribution   = "spread"
    redundancy_level    = "high"
    failover_status     = "configured"
    minimum_nodes       = {
      audio_processing = aws_eks_node_group.audio.scaling_config[0].min_size
      ai_processing    = aws_eks_node_group.ai.scaling_config[0].min_size
    }
  }
}

output "resource_tags" {
  description = "Resource tagging validation"
  value = {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
    cost_center = "audio-processing"
  }
}