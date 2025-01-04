# Configure Terraform settings and required providers
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
  }
}

# Configure the Google Cloud Provider for standard resources
provider "google" {
  project                 = var.project_id
  region                  = var.region
  zone                    = "${var.region}-a"
  request_timeout         = "60s"
  user_project_override   = true
  billing_project        = var.project_id
}

# Configure the Google Beta Provider for preview features
provider "google-beta" {
  project                 = var.project_id
  region                  = var.region
  zone                    = "${var.region}-a"
  request_timeout         = "60s"
  user_project_override   = true
  billing_project        = var.project_id
}