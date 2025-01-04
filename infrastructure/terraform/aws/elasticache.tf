# AWS Provider configuration is inherited from vpc.tf

# Local variables for Redis configuration
locals {
  redis_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
    Service     = "audio-cache"
  }
  redis_family = "redis7.x"
  redis_port   = 6379
}

# Random string for auth token
resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
}

# ElastiCache subnet group for Redis cluster
resource "aws_elasticache_subnet_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-subnet"
  description = "Subnet group for TALD UNIA audio processing Redis cluster"
  subnet_ids  = var.private_subnet_ids

  tags = local.redis_tags
}

# ElastiCache parameter group with optimized settings for audio processing
resource "aws_elasticache_parameter_group" "redis" {
  family = local.redis_family
  name   = "${var.project_name}-${var.environment}-redis-params"
  description = "Redis parameters optimized for TALD UNIA audio processing"

  # Memory management
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "maxmemory-samples"
    value = "10"
  }

  # Performance optimization
  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  parameter {
    name  = "active-defrag-cycle-min"
    value = "25"
  }

  parameter {
    name  = "active-defrag-cycle-max"
    value = "75"
  }

  # Network settings
  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }

  parameter {
    name  = "client-output-buffer-limit-normal-hard-limit"
    value = "0"
  }

  parameter {
    name  = "client-output-buffer-limit-normal-soft-limit"
    value = "0"
  }

  tags = local.redis_tags
}

# Security group for Redis cluster
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Security group for Redis cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = local.redis_port
    to_port         = local.redis_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "Allow Redis traffic from application"
  }

  tags = local.redis_tags
}

# Redis replication group
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "${var.project_name}-${var.environment}-redis"
  replication_group_description = "Redis cluster for TALD UNIA audio processing"
  node_type                     = var.redis_node_type
  port                         = local.redis_port
  parameter_group_name         = aws_elasticache_parameter_group.redis.name
  subnet_group_name            = aws_elasticache_subnet_group.redis.name
  security_group_ids           = [aws_security_group.redis.id]
  
  # High availability configuration
  automatic_failover_enabled    = true
  multi_az_enabled             = true
  num_cache_clusters           = 2
  
  # Authentication and encryption
  auth_token                   = random_password.redis_auth_token.result
  transit_encryption_enabled   = true
  at_rest_encryption_enabled  = true
  
  # Maintenance and backup
  maintenance_window           = "mon:03:00-mon:04:00"
  snapshot_window             = "02:00-03:00"
  snapshot_retention_limit    = 7
  auto_minor_version_upgrade  = true

  # Notifications
  notification_topic_arn      = aws_sns_topic.redis_notifications.arn

  tags = local.redis_tags
}

# SNS topic for Redis notifications
resource "aws_sns_topic" "redis_notifications" {
  name = "${var.project_name}-${var.environment}-redis-notifications"
  tags = local.redis_tags
}

# CloudWatch alarms for Redis monitoring
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-redis-cpu"
  alarm_description   = "Redis cluster CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/ElastiCache"
  period             = "300"
  statistic          = "Average"
  threshold          = "75"
  alarm_actions      = [aws_sns_topic.redis_notifications.arn]
  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.redis.id
  }
  tags = local.redis_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${var.project_name}-${var.environment}-redis-memory"
  alarm_description   = "Redis cluster memory usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "DatabaseMemoryUsagePercentage"
  namespace          = "AWS/ElastiCache"
  period             = "300"
  statistic          = "Average"
  threshold          = "80"
  alarm_actions      = [aws_sns_topic.redis_notifications.arn]
  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.redis.id
  }
  tags = local.redis_tags
}

# Outputs
output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port number"
  value       = local.redis_port
}

output "redis_auth_token" {
  description = "Redis authentication token"
  value       = random_password.redis_auth_token.result
  sensitive   = true
}