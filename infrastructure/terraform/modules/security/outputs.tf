# Output definitions for the security module exposing critical security infrastructure components
# Includes KMS keys, certificate management endpoints, and security service configurations

# KMS key ARN output for encryption services
output "kms_key_arn" {
  description = "ARN of the KMS key used for AES-256-GCM data encryption with HSM backing"
  value       = aws_kms_key.encryption_key.arn
  sensitive   = true
}

# KMS key ID output for resource references
output "kms_key_id" {
  description = "ID of the KMS key for secure reference in other resources"
  value       = aws_kms_key.encryption_key.key_id
  sensitive   = true
}

# Certificate manager namespace output
output "cert_manager_namespace" {
  description = "Kubernetes namespace for TLS certificate automation and management"
  value       = kubernetes_namespace.security["cert-manager"].metadata[0].name
}

# Vault namespace output
output "vault_namespace" {
  description = "Kubernetes namespace for secure secret management with Vault"
  value       = kubernetes_namespace.security["vault"].metadata[0].name
}

# Vault service endpoint output
output "vault_endpoint" {
  description = "Internal endpoint URL for the Vault service with TLS 1.3 encryption"
  value       = format("https://%s.%s.svc.cluster.local:8200", 
                      helm_release.vault.metadata[0].name,
                      kubernetes_namespace.security["vault"].metadata[0].name)
  sensitive   = true
}

# Security namespaces map output
output "security_namespaces" {
  description = "Map of all security-related Kubernetes namespaces for compliance tracking"
  value       = kubernetes_namespace.security
}