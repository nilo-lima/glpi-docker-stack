# =============================================================================
# versions.tf - Restricoes de versao do Terraform e providers
# =============================================================================
# Principio: versoes sempre pinadas. Mudanca de versao = bump explicito + commit.
# Referencia: .claude/rules/devops-standards.md

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend S3 - state remoto com locking via DynamoDB
  # Criado pelo bootstrap/ em 2026-05-28
  backend "s3" {
    bucket         = "glpi-fase3-tfstate-507687687616"
    key            = "fase03/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}
