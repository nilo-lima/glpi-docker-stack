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

  # Backend S3 - configurado apos rodar bootstrap/
  # Para usar backend local durante desenvolvimento inicial, comente este bloco.
  # Apos rodar o bootstrap, descomente e substitua os valores pelos outputs do bootstrap.
  #
  # backend "s3" {
  #   bucket         = "glpi-fase3-tfstate-<ACCOUNT_ID>"
  #   key            = "fase03/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "glpi-fase3-terraform-locks"
  #   encrypt        = true
  # }
}
