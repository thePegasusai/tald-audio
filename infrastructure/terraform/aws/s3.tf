# AWS S3 Configuration for TALD UNIA Audio System
# Provider version: ~> 5.0

locals {
  bucket_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Audio Samples Bucket
resource "aws_s3_bucket" "audio_samples" {
  bucket = "${local.bucket_prefix}-audio-samples"
  tags   = merge(local.common_tags, { Purpose = "Audio Sample Storage" })
}

resource "aws_s3_bucket_versioning" "audio_samples" {
  bucket = aws_s3_bucket.audio_samples.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audio_samples" {
  bucket = aws_s3_bucket.audio_samples.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audio_samples" {
  bucket = aws_s3_bucket.audio_samples.id

  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# AI Models Bucket
resource "aws_s3_bucket" "ai_models" {
  bucket = "${local.bucket_prefix}-ai-models"
  tags   = merge(local.common_tags, { Purpose = "AI Model Storage" })
}

resource "aws_s3_bucket_versioning" "ai_models" {
  bucket = aws_s3_bucket.ai_models.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ai_models" {
  bucket = aws_s3_bucket.ai_models.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_key.id
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ai_models" {
  bucket = aws_s3_bucket.ai_models.id

  rule {
    id     = "model-versioning"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }
  }
}

# User Profiles Bucket
resource "aws_s3_bucket" "user_profiles" {
  bucket = "${local.bucket_prefix}-user-profiles"
  tags   = merge(local.common_tags, { Purpose = "User Profile Storage" })
}

resource "aws_s3_bucket_versioning" "user_profiles" {
  bucket = aws_s3_bucket.user_profiles.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "user_profiles" {
  bucket = aws_s3_bucket.user_profiles.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_key.id
    }
  }
}

# KMS Key for S3 Encryption
resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                   = local.common_tags
}

resource "aws_kms_alias" "s3_key_alias" {
  name          = "alias/${var.project_name}-s3-key"
  target_key_id = aws_kms_key.s3_key.key_id
}

# Common S3 Security Configurations
resource "aws_s3_bucket_public_access_block" "all_buckets" {
  for_each = toset([
    aws_s3_bucket.audio_samples.id,
    aws_s3_bucket.ai_models.id,
    aws_s3_bucket.user_profiles.id
  ])

  bucket                  = each.key
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "all_buckets" {
  for_each = toset([
    aws_s3_bucket.audio_samples.id,
    aws_s3_bucket.ai_models.id,
    aws_s3_bucket.user_profiles.id
  ])

  bucket = each.key

  target_bucket = aws_s3_bucket.audit_logs.id
  target_prefix = "s3-access-logs/${each.key}/"
}

# Audit Logs Bucket
resource "aws_s3_bucket" "audit_logs" {
  bucket = "${local.bucket_prefix}-audit-logs"
  tags   = merge(local.common_tags, { Purpose = "Audit Logging" })
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    id     = "audit-retention"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# Bucket Policies
resource "aws_s3_bucket_policy" "enforce_ssl" {
  for_each = toset([
    aws_s3_bucket.audio_samples.id,
    aws_s3_bucket.ai_models.id,
    aws_s3_bucket.user_profiles.id,
    aws_s3_bucket.audit_logs.id
  ])

  bucket = each.key
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceSSLOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${each.key}",
          "arn:aws:s3:::${each.key}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Outputs
output "audio_samples_bucket" {
  value = {
    id                  = aws_s3_bucket.audio_samples.id
    arn                 = aws_s3_bucket.audio_samples.arn
    bucket_domain_name  = aws_s3_bucket.audio_samples.bucket_domain_name
  }
  description = "Audio samples bucket details"
}

output "ai_models_bucket" {
  value = {
    id                  = aws_s3_bucket.ai_models.id
    arn                 = aws_s3_bucket.ai_models.arn
    bucket_domain_name  = aws_s3_bucket.ai_models.bucket_domain_name
  }
  description = "AI models bucket details"
}

output "user_profiles_bucket" {
  value = {
    id                  = aws_s3_bucket.user_profiles.id
    arn                 = aws_s3_bucket.user_profiles.arn
    bucket_domain_name  = aws_s3_bucket.user_profiles.bucket_domain_name
  }
  description = "User profiles bucket details"
}