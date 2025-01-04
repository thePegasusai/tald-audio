# Terraform configuration block defining version constraints and required providers
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary AWS provider configuration
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      System      = "TALD-UNIA-Audio"
    }
  }

  # Enhanced retry configuration for API operations
  retry_mode = "adaptive"
  max_retries = 10

  # Default encryption configuration
  default_encryption_config {
    enable = true
  }

  # Provider-level timeouts and connection settings
  http_proxy               = null
  ignore_tags             = null
  max_attempts            = 10
  profile                 = null
  shared_credentials_file = null
  skip_credentials_validation = false
  skip_metadata_api_check    = false
  skip_region_validation     = false
}

# Secondary provider for multi-region deployment (US-EAST-1 for global services)
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      System      = "TALD-UNIA-Audio"
    }
  }

  retry_mode = "adaptive"
  max_retries = 10
}

# Secondary provider for disaster recovery region
provider "aws" {
  alias  = "dr-region"
  region = var.aws_region == "us-west-2" ? "us-east-2" : "us-west-2"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      System      = "TALD-UNIA-Audio"
      Purpose     = "Disaster-Recovery"
    }
  }

  retry_mode = "adaptive"
  max_retries = 10
}

# Provider configuration for edge computing regions
provider "aws" {
  alias  = "edge"
  region = "us-west-2"  # Primary edge region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      System      = "TALD-UNIA-Audio"
      Purpose     = "Edge-Computing"
    }
  }

  retry_mode = "adaptive"
  max_retries = 10

  assume_role {
    role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/EdgeComputeRole"
  }
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}