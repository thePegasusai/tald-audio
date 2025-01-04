# Terraform variables definition file for the security module
# Configures authentication, encryption, certificate management, and security policies
# for the TALD UNIA Audio System

# Environment variable with validation
variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod"
  }
}

# Authentication and authorization configuration
variable "auth_config" {
  type = map(object({
    oauth = object({
      enabled    = bool
      provider   = string
      client_id  = string
    })
    jwt = object({
      enabled    = bool
      issuer     = string
      algorithm  = string
    })
    api_keys = object({
      enabled       = bool
      rotation_days = number
    })
  }))
  description = "Authentication and authorization configuration"
  sensitive   = true

  default = {
    oauth = {
      enabled    = true
      provider   = "auth0"
      client_id  = null # Must be provided during deployment
    }
    jwt = {
      enabled    = true
      issuer     = "tald-unia"
      algorithm  = "RS256"
    }
    api_keys = {
      enabled       = true
      rotation_days = 90
    }
  }
}

# Encryption and key management configuration
variable "encryption_config" {
  type = map(object({
    kms_key_rotation = bool
    tls_version      = string
    certificate_days = number
  }))
  description = "Encryption and key management configuration"
  sensitive   = true

  validation {
    condition     = alltrue([for k, v in var.encryption_config : v.tls_version == "1.3"])
    error_message = "TLS version must be 1.3 for all encryption configurations"
  }
}

# Security monitoring and alerting configuration
variable "security_monitoring" {
  type = object({
    enabled        = bool
    retention_days = number
    alert_endpoints = list(string)
  })
  description = "Security monitoring and alerting settings"

  validation {
    condition     = var.security_monitoring.retention_days >= 30
    error_message = "Security logs must be retained for at least 30 days"
  }
}

# Compliance and control settings
variable "compliance_controls" {
  type = map(object({
    enabled      = bool
    standard     = string
    requirements = list(string)
  }))
  description = "Compliance and control settings"

  validation {
    condition     = alltrue([for k, v in var.compliance_controls : contains(["IEC60065", "EN50332", "HDCP2.3"], v.standard)])
    error_message = "Compliance standard must be one of: IEC60065, EN50332, HDCP2.3"
  }
}

# Certificate management configuration
variable "certificate_config" {
  type = object({
    provider           = string
    domain_names      = list(string)
    organization_name = string
    country_code      = string
    auto_renewal      = bool
  })
  description = "SSL/TLS certificate management configuration"

  validation {
    condition     = var.certificate_config.provider == "acm" || var.certificate_config.provider == "lets_encrypt"
    error_message = "Certificate provider must be either 'acm' or 'lets_encrypt'"
  }
}

# Role-based access control configuration
variable "rbac_config" {
  type = map(object({
    role_name    = string
    permissions  = list(string)
    api_access   = bool
    admin_access = bool
  }))
  description = "Role-based access control configuration"

  validation {
    condition     = alltrue([for k, v in var.rbac_config : length(v.permissions) > 0])
    error_message = "Each role must have at least one permission defined"
  }
}

# Security incident response configuration
variable "incident_response_config" {
  type = object({
    enabled           = bool
    notification_channels = list(string)
    escalation_policy    = map(string)
    automated_response   = bool
  })
  description = "Security incident response configuration"
}

# Network security configuration
variable "network_security_config" {
  type = object({
    vpc_flow_logs    = bool
    waf_enabled      = bool
    ddos_protection  = bool
    network_acls     = map(list(string))
  })
  description = "Network security configuration"
}