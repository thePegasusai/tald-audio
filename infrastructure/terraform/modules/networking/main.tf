# Provider Configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Local Variables
locals {
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    System      = "TALD UNIA"
    Purpose     = "Audio Processing"
  }

  network_config = {
    EnableFlowLogs      = true
    EnableVPNGateway    = true
    EnableDDoSProtection = true
  }
}

# VPC Resource
resource "aws_vpc" "tald_unia" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  
  tags = merge(local.tags, {
    Name = "tald-unia-vpc-${var.environment}"
  })
}

# Flow Logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/tald-unia-flow-logs-${var.environment}"
  retention_in_days = 30
  
  tags = local.tags
}

resource "aws_flow_log" "vpc_flow_logs" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.tald_unia.id
  
  tags = local.tags
}

# Audio Processing Subnets
resource "aws_subnet" "audio_processing" {
  for_each = {
    for idx, az in var.availability_zones : 
    "audio-${idx}" => {
      az         = az
      cidr_block = cidrsubnet(var.vpc_cidr, 4, idx)
    }
  }

  vpc_id            = aws_vpc.tald_unia.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = merge(local.tags, {
    Name = "tald-unia-audio-subnet-${each.key}-${var.environment}"
    Type = "AudioProcessing"
  })
}

# Management Subnets
resource "aws_subnet" "management" {
  for_each = {
    for idx, az in var.availability_zones :
    "mgmt-${idx}" => {
      az         = az
      cidr_block = cidrsubnet(var.vpc_cidr, 4, idx + length(var.availability_zones))
    }
  }

  vpc_id            = aws_vpc.tald_unia.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = merge(local.tags, {
    Name = "tald-unia-mgmt-subnet-${each.key}-${var.environment}"
    Type = "Management"
  })
}

# Security Groups
resource "aws_security_group" "audio_streaming" {
  name        = "tald-unia-audio-streaming-${var.environment}"
  description = "Security group for TALD UNIA audio streaming"
  vpc_id      = aws_vpc.tald_unia.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for audio streaming"
  }

  ingress {
    from_port   = 4433
    to_port     = 4433
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DTLS for real-time audio"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "tald-unia-audio-sg-${var.environment}"
  })
}

# VPN Gateway
resource "aws_vpn_gateway" "main" {
  count  = var.enable_vpn ? 1 : 0
  vpc_id = aws_vpc.tald_unia.id

  tags = merge(local.tags, {
    Name = "tald-unia-vpn-gateway-${var.environment}"
  })
}

# Route Tables
resource "aws_route_table" "audio_processing" {
  vpc_id = aws_vpc.tald_unia.id

  tags = merge(local.tags, {
    Name = "tald-unia-audio-rt-${var.environment}"
    Type = "AudioProcessing"
  })
}

resource "aws_route_table" "management" {
  vpc_id = aws_vpc.tald_unia.id

  tags = merge(local.tags, {
    Name = "tald-unia-mgmt-rt-${var.environment}"
    Type = "Management"
  })
}

# Route Table Associations
resource "aws_route_table_association" "audio_processing" {
  for_each = aws_subnet.audio_processing

  subnet_id      = each.value.id
  route_table_id = aws_route_table.audio_processing.id
}

resource "aws_route_table_association" "management" {
  for_each = aws_subnet.management

  subnet_id      = each.value.id
  route_table_id = aws_route_table.management.id
}

# Network ACLs
resource "aws_network_acl" "audio_processing" {
  vpc_id     = aws_vpc.tald_unia.id
  subnet_ids = [for subnet in aws_subnet.audio_processing : subnet.id]

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    protocol   = "udp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 4433
    to_port    = 4433
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(local.tags, {
    Name = "tald-unia-audio-nacl-${var.environment}"
  })
}

# VPC Endpoints for AWS Services
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.tald_unia.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  
  tags = merge(local.tags, {
    Name = "tald-unia-s3-endpoint-${var.environment}"
  })
}

# IAM Role for Flow Logs
resource "aws_iam_role" "flow_logs" {
  name = "tald-unia-flow-logs-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "tald-unia-flow-logs-policy-${var.environment}"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Data Sources
data "aws_region" "current" {}