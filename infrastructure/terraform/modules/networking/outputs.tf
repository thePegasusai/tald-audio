# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC hosting TALD UNIA audio processing infrastructure"
  value       = aws_vpc.tald_unia.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC for network planning and security configuration"
  value       = aws_vpc.tald_unia.cidr_block
}

# Subnet Outputs
output "public_subnet_ids" {
  description = "IDs of public subnets for load balancer and edge audio processing deployment"
  value       = [for subnet in aws_subnet.audio_processing : subnet.id if subnet.map_public_ip_on_launch]
}

output "private_subnet_ids" {
  description = "IDs of private subnets for secure audio processing service deployment"
  value       = [for subnet in aws_subnet.audio_processing : subnet.id if !subnet.map_public_ip_on_launch]
}

output "management_subnet_ids" {
  description = "IDs of management subnets for operational and monitoring services"
  value       = [for subnet in aws_subnet.management : subnet.id]
}

# Availability Zone Output
output "availability_zones" {
  description = "List of availability zones used for multi-AZ audio processing deployment"
  value       = var.availability_zones
}

# Security Group Outputs
output "security_group_ids" {
  description = "Map of security group IDs for audio streaming and management access"
  value = {
    audio_streaming = aws_security_group.audio_streaming.id
  }
}

# Network ACL Outputs
output "network_acl_ids" {
  description = "Map of network ACL IDs for subnet-level traffic protection"
  value = {
    audio_processing = aws_network_acl.audio_processing.id
  }
}

# Route Table Outputs
output "route_table_ids" {
  description = "Map of route table IDs for network traffic management"
  value = {
    audio_processing = aws_route_table.audio_processing.id
    management       = aws_route_table.management.id
  }
}

# VPN Gateway Output
output "vpn_gateway_id" {
  description = "ID of the VPN gateway for secure remote access"
  value       = var.enable_vpn ? aws_vpn_gateway.main[0].id : null
}

# Flow Logs Output
output "flow_logs_group" {
  description = "CloudWatch log group name for VPC flow logs"
  value       = aws_cloudwatch_log_group.flow_logs.name
}

# Network Performance Metrics
output "network_metrics" {
  description = "Network performance configuration and monitoring metrics"
  value = {
    flow_logs_enabled     = local.network_config.EnableFlowLogs
    ddos_protection      = local.network_config.EnableDDoSProtection
    vpc_endpoints        = length(aws_vpc_endpoint.s3[*].id)
    availability_zones   = length(var.availability_zones)
  }
}

# DNS Configuration
output "dns_config" {
  description = "DNS configuration for service discovery"
  value = {
    enable_dns_hostnames = aws_vpc.tald_unia.enable_dns_hostnames
    enable_dns_support   = aws_vpc.tald_unia.enable_dns_support
  }
}

# Tags Output
output "resource_tags" {
  description = "Common tags applied to all networking resources"
  value       = local.tags
}