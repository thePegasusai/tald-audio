# Core AWS Configuration Variables
variable "aws_region" {
  type        = string
  description = "AWS region where resources will be deployed"
  default     = "us-west-2"

  validation {
    condition     = can(regex("^(us|eu|ap|sa|ca|me|af)-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., us-west-2, eu-central-1)."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev/staging/prod)"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  type        = string
  description = "Project name for resource tagging (TALD UNIA)"
  default     = "tald-unia"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,28}[a-z0-9]$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with hyphens, 4-30 characters."
  }
}

# Networking Variables
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets (one per AZ)"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnets are required for high availability."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets (one per AZ)"
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

# EKS Cluster Variables
variable "eks_cluster_version" {
  type        = string
  description = "Kubernetes version for EKS cluster"
  default     = "1.27"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.eks_cluster_version))
    error_message = "EKS cluster version must be in the format 'X.Y'."
  }
}

variable "eks_node_instance_types" {
  type        = list(string)
  description = "EC2 instance types for EKS node groups"
  default     = ["t3.xlarge", "t3.2xlarge"]

  validation {
    condition     = length([for t in var.eks_node_instance_types : t if can(regex("^[a-z][0-9][a-z]?\\.[a-z0-9]+$", t))]) == length(var.eks_node_instance_types)
    error_message = "All instance types must be valid EC2 instance type identifiers."
  }
}

variable "eks_node_min_size" {
  type        = number
  description = "Minimum number of nodes in EKS node group"
  default     = 2

  validation {
    condition     = var.eks_node_min_size >= 2
    error_message = "Minimum node count must be at least 2 for high availability."
  }
}

variable "eks_node_max_size" {
  type        = number
  description = "Maximum number of nodes in EKS node group"
  default     = 10

  validation {
    condition     = var.eks_node_max_size >= var.eks_node_min_size
    error_message = "Maximum node count must be greater than or equal to minimum node count."
  }
}

# Database Variables
variable "db_instance_class" {
  type        = string
  description = "RDS instance class for PostgreSQL database"
  default     = "db.r6g.xlarge"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "DB instance class must be a valid RDS instance type."
  }
}

variable "db_allocated_storage" {
  type        = number
  description = "Allocated storage in GB for RDS instance"
  default     = 100

  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 GB and 65536 GB."
  }
}

# Redis Cache Variables
variable "redis_node_type" {
  type        = string
  description = "ElastiCache node type for Redis cluster"
  default     = "cache.r6g.xlarge"

  validation {
    condition     = can(regex("^cache\\.[a-z0-9]+\\.[a-z0-9]+$", var.redis_node_type))
    error_message = "Redis node type must be a valid ElastiCache instance type."
  }
}

variable "redis_num_cache_nodes" {
  type        = number
  description = "Number of cache nodes in Redis cluster"
  default     = 2

  validation {
    condition     = var.redis_num_cache_nodes >= 2
    error_message = "Redis cluster must have at least 2 nodes for high availability."
  }
}

# GPU Node Configuration
variable "enable_gpu_nodes" {
  type        = bool
  description = "Enable GPU nodes for AI processing (Warning: Significant cost impact)"
  default     = false
}

variable "gpu_node_instance_types" {
  type        = list(string)
  description = "EC2 instance types for GPU nodes"
  default     = ["p3.2xlarge", "g4dn.xlarge"]

  validation {
    condition     = length([for t in var.gpu_node_instance_types : t if can(regex("^[pg][0-9][a-z]?\\.[a-z0-9]+$", t))]) == length(var.gpu_node_instance_types)
    error_message = "GPU instance types must be valid GPU-enabled EC2 instance types (p3, p4, g4, g5)."
  }
}

# Monitoring and Logging
variable "enable_monitoring" {
  type        = bool
  description = "Enable enhanced monitoring and logging"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs"
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the allowed values by CloudWatch."
  }
}

# Backup Configuration
variable "backup_retention_period" {
  type        = number
  description = "Backup retention period in days for RDS"
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 7 and 35 days."
  }
}

# Tags
variable "tags" {
  type        = map(string)
  description = "Common tags to be applied to all resources"
  default = {
    Project     = "TALD-UNIA"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }

  validation {
    condition     = length(var.tags) > 0
    error_message = "At least one tag must be specified."
  }
}