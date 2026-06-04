terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.38"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azurerm" {
  alias = "aad_storage"
  features {}
  storage_use_azuread = true
}

# Only used to mint a fresh ECR authorization token at apply time so
# `az acr import` can pull the private ECR image into ACR. No AWS
# resources are created.
provider "aws" {
  region     = var.ecr_source_credentials != null ? var.ecr_source_credentials.region : "us-east-1"
  access_key = var.ecr_source_credentials != null ? var.ecr_source_credentials.access_key : null
  secret_key = var.ecr_source_credentials != null ? var.ecr_source_credentials.secret_key : null
}