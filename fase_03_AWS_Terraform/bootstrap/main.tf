# =============================================================================
# bootstrap/main.tf
# =============================================================================
# Cria os pre-requisitos para o backend remoto do Terraform principal:
#   - S3 bucket para armazenar o tfstate (versionado, criptografado, privado)
#   - DynamoDB table para locking (evita applies concorrentes)
#
# Como usar:
#   cd bootstrap/
#   terraform init
#   terraform apply
#
# Apos o apply, anotar os outputs e atualizar o bloco `backend "s3"` em ../main.tf
# Este diretorio usa backend LOCAL (o estado do bootstrap nao vai para S3).
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Phase     = "3-bootstrap"
    }
  }
}

# Identificador da conta AWS (usado para nomear o bucket com unicidade global)
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# S3 bucket - armazenamento do tfstate
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  # Nome inclui account_id para garantir unicidade global no S3
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Protecao contra destruicao acidental: o estado do Terraform e critico.
  # Para destruir, altere para false e faca apply antes do destroy.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Bloqueia qualquer acesso publico - estado contem senhas e ARNs sensiveis
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: remover versoes antigas do state apos 90 dias (custo + higiene)
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# -----------------------------------------------------------------------------
# DynamoDB table - lock para evitar applies concorrentes
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # Sem custo fixo; cobra apenas por operacao
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
