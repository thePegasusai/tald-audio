# AWS Provider configuration with version constraint
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables for common tags and configurations
locals {
  tags = {
    Environment = var.environment
    Project     = "TALD-UNIA"
    ManagedBy   = "terraform"
  }

  cluster_name = "${var.project_name}-${var.environment}-eks"
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = "${local.cluster_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

# Attach required policies to cluster role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# KMS key for EKS encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS cluster encryption"
  deletion_window_in_days = 7
  enable_key_rotation    = true

  tags = local.tags
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids              = data.aws_subnets.private.ids
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# IAM Role for Node Groups
resource "aws_iam_role" "eks_node" {
  name = "${local.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

# Attach required policies to node role
resource "aws_iam_role_policy_attachment" "eks_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])

  policy_arn = each.value
  role       = aws_iam_role.eks_node.name
}

# Node Group for Audio Processing
resource "aws_eks_node_group" "audio" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-audio"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = data.aws_subnets.private.ids

  instance_types = ["c6i.2xlarge"]
  disk_size      = 100
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 10
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "audio-processing"
    type     = "cpu-optimized"
  }

  taint {
    key    = "workload"
    value  = "audio-processing"
    effect = "NO_SCHEDULE"
  }

  tags = merge(local.tags, {
    Name = "${local.cluster_name}-audio-node"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policies
  ]
}

# Node Group for AI Processing
resource "aws_eks_node_group" "ai" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-ai"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = data.aws_subnets.private.ids

  instance_types = ["g5.xlarge"]
  disk_size      = 200
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 5
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "ai-processing"
    type     = "gpu-enabled"
  }

  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = merge(local.tags, {
    Name = "${local.cluster_name}-ai-node"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policies
  ]
}

# Security Group for EKS Cluster
resource "aws_security_group" "eks_cluster" {
  name        = "${local.cluster_name}-sg"
  description = "Security group for EKS cluster"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.cluster_name}-sg"
  })
}

# CloudWatch Log Group for EKS Cluster Logs
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 30

  tags = local.tags
}

# Outputs
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID for the cluster"
  value       = aws_security_group.eks_cluster.id
}

output "node_groups" {
  description = "Node group information"
  value = {
    audio_node_group = aws_eks_node_group.audio.id
    ai_node_group    = aws_eks_node_group.ai.id
  }
}