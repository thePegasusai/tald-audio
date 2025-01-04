# RDS PostgreSQL configuration for TALD UNIA Audio System

# Local variables for RDS configuration
locals {
  db_name_prefix = "${var.project_name}-${var.environment}-db"
  db_port        = 5432
  db_family     = "postgres15"
  
  monitoring_role_name = "${var.project_name}-${var.environment}-rds-monitoring"
  
  backup_window      = "03:00-04:00"  # UTC
  maintenance_window = "Mon:04:00-Mon:05:00"  # UTC
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
    Service     = "database"
    Component   = "postgresql"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "postgresql" {
  name_prefix = "${local.db_name_prefix}-subnet-group"
  subnet_ids  = data.aws_subnet_ids.private.ids
  
  tags = merge(local.tags, {
    Name = "${local.db_name_prefix}-subnet-group"
  })
}

# Enhanced Monitoring IAM Role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name_prefix = local.monitoring_role_name
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# DB Parameter Group
resource "aws_db_parameter_group" "postgresql" {
  name_prefix = "${local.db_name_prefix}-params"
  family      = local.db_family
  
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"
  }
  
  parameter {
    name  = "max_connections"
    value = "1000"
  }
  
  parameter {
    name  = "work_mem"
    value = "4096"
  }
  
  parameter {
    name  = "maintenance_work_mem"
    value = "1048576"
  }
  
  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory*3/4}"
  }
  
  parameter {
    name  = "ssl"
    value = "1"
  }
  
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries taking more than 1 second
  }
  
  tags = local.tags
}

# Main RDS Instance
resource "aws_db_instance" "postgresql" {
  identifier_prefix = local.db_name_prefix
  
  # Engine configuration
  engine                      = "postgres"
  engine_version             = "15.3"
  instance_class             = var.db_instance_class
  allocated_storage          = var.db_allocated_storage
  max_allocated_storage      = var.db_allocated_storage * 2
  storage_type               = "gp3"
  storage_encrypted          = true
  
  # Network configuration
  db_subnet_group_name    = aws_db_subnet_group.postgresql.name
  vpc_security_group_ids  = [aws_security_group.vpc_endpoints.id]
  port                    = local.db_port
  publicly_accessible     = false
  
  # High availability configuration
  multi_az               = true
  availability_zone      = null  # Let AWS choose for Multi-AZ
  
  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = local.backup_window
  copy_tags_to_snapshot  = true
  delete_automated_backups = true
  deletion_protection    = true
  
  # Maintenance configuration
  auto_minor_version_upgrade  = true
  maintenance_window         = local.maintenance_window
  
  # Performance configuration
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 30
  monitoring_role_arn                  = aws_iam_role.rds_enhanced_monitoring.arn
  
  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.postgresql.name
  
  # Authentication
  username = "tald_admin"
  manage_master_user_password = true  # Use AWS Secrets Manager
  
  tags = merge(local.tags, {
    Name = local.db_name_prefix
  })
}

# CloudWatch Alarms for RDS Monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${local.db_name_prefix}-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/RDS"
  period             = "300"
  statistic          = "Average"
  threshold          = "80"
  alarm_description  = "Database CPU utilization is too high"
  alarm_actions      = []  # Add SNS topic ARN for notifications
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgresql.id
  }
  
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "database_memory" {
  alarm_name          = "${local.db_name_prefix}-freeable-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "FreeableMemory"
  namespace          = "AWS/RDS"
  period             = "300"
  statistic          = "Average"
  threshold          = "1000000000"  # 1GB in bytes
  alarm_description  = "Database freeable memory is too low"
  alarm_actions      = []  # Add SNS topic ARN for notifications
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgresql.id
  }
  
  tags = local.tags
}

# Outputs
output "db_instance_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.postgresql.endpoint
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.postgresql.arn
}

output "db_instance_id" {
  description = "The ID of the RDS instance"
  value       = aws_db_instance.postgresql.id
}