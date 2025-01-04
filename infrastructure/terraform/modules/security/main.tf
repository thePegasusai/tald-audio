# Provider configurations
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Local variables
locals {
  common_tags = {
    Environment       = var.environment
    Project          = var.project_name
    ManagedBy        = "terraform"
    SecurityLevel    = "high"
    ComplianceStatus = "monitored"
  }
}

# KMS key for encryption
resource "aws_kms_key" "encryption_key" {
  description             = "KMS key for TALD UNIA Audio System encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  key_usage              = "ENCRYPT_DECRYPT"
  
  tags = merge(local.common_tags, {
    Name = "tald-unia-encryption-key"
  })

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

# Security namespaces
resource "kubernetes_namespace" "security" {
  for_each = var.security_namespaces

  metadata {
    name = each.value
    labels = merge(local.common_tags, {
      "security.kubernetes.io/enforce-pod-security" = "restricted"
    })
    annotations = {
      "vault.hashicorp.com/agent-inject" = "true"
    }
  }
}

# Certificate Manager deployment
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version
  namespace  = kubernetes_namespace.security["cert-manager"].metadata[0].name

  values = [
    file("${path.module}/../../../kubernetes/security/cert-manager-values.yaml")
  ]

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = kubernetes_namespace.security["cert-manager"].metadata[0].name
  }
}

# Vault deployment
resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = var.vault_version
  namespace  = kubernetes_namespace.security["vault"].metadata[0].name

  values = [
    file("${path.module}/../../../kubernetes/security/vault-values.yaml")
  ]

  set {
    name  = "server.ha.enabled"
    value = "true"
  }

  set {
    name  = "server.auditStorage.enabled"
    value = "true"
  }
}

# Security group for encryption services
resource "aws_security_group" "encryption_services" {
  name_prefix = "tald-unia-encryption-"
  description = "Security group for encryption services"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "tald-unia-encryption-sg"
  })
}

# CloudWatch log group for security monitoring
resource "aws_cloudwatch_log_group" "security_logs" {
  name              = "/tald-unia/security-logs"
  retention_in_days = var.security_monitoring.retention_days

  tags = merge(local.common_tags, {
    Name = "tald-unia-security-logs"
  })
}

# IAM role for security services
resource "aws_iam_role" "security_services" {
  name = "tald-unia-security-services-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Security policy for KMS key usage
resource "aws_iam_role_policy" "kms_policy" {
  name = "tald-unia-kms-policy"
  role = aws_iam_role.security_services.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.encryption_key.arn]
      }
    ]
  })
}

# Outputs
output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.encryption_key.arn
}

output "vault_endpoint" {
  description = "Endpoint URL of the Vault service"
  value       = "https://vault.${var.domain_name}"
}

output "cert_manager_namespace" {
  description = "Kubernetes namespace for cert-manager"
  value       = kubernetes_namespace.security["cert-manager"].metadata[0].name
}