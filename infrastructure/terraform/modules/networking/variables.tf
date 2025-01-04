# Core VPC Configuration
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC network supporting TALD UNIA Audio System"
  
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.vpc_cidr))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block (e.g., 10.0.0.0/16)."
  }
}

variable "environment" {
  type        = string
  description = "Environment name for resource tagging and configuration (e.g., dev, staging, prod)"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones for high-availability deployment of TALD UNIA network infrastructure"
}

variable "enable_vpn" {
  type        = bool
  description = "Enable VPN gateway for secure network access with IPSec tunneling"
  default     = true
}

variable "subnet_configuration" {
  type = map(object({
    cidr_block  = string
    subnet_type = string
    route_table = map(string)
  }))
  description = "Detailed subnet configuration for audio processing, API, and management networks"
}

variable "network_acls" {
  type = map(list(object({
    rule_number = number
    protocol    = string
    action      = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  })))
  description = "Network ACL rules for securing TALD UNIA audio streaming and management traffic"
}

variable "network_performance_config" {
  type = object({
    enable_flow_logs      = bool
    monitoring_interval   = number
    latency_threshold_ms  = number
  })
  description = "Network performance monitoring configuration to ensure <10ms audio processing latency"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags for TALD UNIA network infrastructure components"
  default     = {
    Project     = "TALD-UNIA"
    ManagedBy   = "Terraform"
    Environment = "prod"
  }
}

# TLS Configuration
variable "tls_config" {
  type = object({
    minimum_protocol_version = string
    certificate_arn         = string
    security_policy         = string
  })
  description = "TLS configuration for secure audio streaming and API communication"
  
  validation {
    condition     = var.tls_config.minimum_protocol_version == "TLS1_3"
    error_message = "TLS 1.3 is required for TALD UNIA secure communication."
  }
}

# Load Balancer Configuration
variable "load_balancer_config" {
  type = object({
    internal           = bool
    type              = string
    idle_timeout      = number
    enable_deletion_protection = bool
  })
  description = "Load balancer configuration for high-availability audio processing"
}

# Flow Logs Configuration
variable "flow_logs_config" {
  type = object({
    traffic_type = string
    log_destination_type = string
    retention_days = number
  })
  description = "VPC flow logs configuration for network traffic analysis and security monitoring"
}

# DNS Configuration
variable "dns_config" {
  type = object({
    enable_private_dns = bool
    domain_name       = string
    enable_dns_hostnames = bool
  })
  description = "DNS configuration for TALD UNIA service discovery and routing"
}

# Transit Gateway Configuration
variable "transit_gateway_config" {
  type = object({
    enable_auto_accept_shared_attachments = bool
    enable_default_route_table_association = bool
    enable_dns_support = bool
  })
  description = "Transit gateway configuration for multi-region network connectivity"
}