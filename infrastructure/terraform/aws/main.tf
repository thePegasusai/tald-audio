# Configure Terraform settings and required providers
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws" # v5.0
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random" # v3.5
      version = "~> 3.5"
    }
  }

  # Configure remote state with encryption and locking
  backend "s3" {
    bucket         = "tald-unia-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "tald-unia-terraform-locks"

    # Workspace-aware state paths
    workspace_key_prefix = "env"
  }
}

# Generate unique project ID for resource naming
resource "random_id" "project_id" {
  byte_length = 4
  prefix      = "${var.project_name}-${var.environment}-"
}

# Configure AWS Provider with enhanced settings
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = merge(
      {
        Environment = var.environment
        Project     = var.project_name
        ManagedBy   = "terraform"
        CreatedAt   = timestamp()
        Owner       = "TALD UNIA"
      },
      var.tags
    )
  }

  # Enhanced provider configuration
  assume_role {
    role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TerraformExecutionRole"
  }

  # Provider-level configuration
  skip_metadata_api_check     = true
  skip_region_validation     = false
  skip_credentials_validation = false

  # S3 endpoint configuration
  s3_use_path_style = false
  
  # Retry configuration
  retry_mode = "standard"
  max_retries = 3
}

# Secondary region provider for disaster recovery
provider "aws" {
  alias  = "secondary"
  region = "us-east-1"  # Secondary region for DR

  default_tags {
    tags = merge(
      {
        Environment = var.environment
        Project     = var.project_name
        ManagedBy   = "terraform"
        CreatedAt   = timestamp()
        Owner       = "TALD UNIA"
        Region      = "secondary"
      },
      var.tags
    )
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Local variables for resource naming and tagging
locals {
  # Common tags for all resources
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
    CreatedAt   = timestamp()
    Owner       = "TALD UNIA"
  }

  # Resource naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Region-specific configuration
  is_primary_region = var.aws_region == "us-west-2"
  
  # Availability zone configuration
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# KMS key for encryption
resource "aws_kms_key" "main" {
  description             = "KMS key for ${var.project_name} encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-kms-key"
    }
  )
}

# KMS key alias
resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}-key"
  target_key_id = aws_kms_key.main.key_id
}

# S3 bucket for application assets
resource "aws_s3_bucket" "assets" {
  bucket = "${local.name_prefix}-assets-${random_id.project_id.hex}"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-assets"
    }
  )
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Output the project ID
output "project_id" {
  value       = random_id.project_id.hex
  description = "Unique project identifier for resource naming"
}

# Output the AWS region
output "aws_region" {
  value       = var.aws_region
  description = "AWS region where resources are deployed"
}