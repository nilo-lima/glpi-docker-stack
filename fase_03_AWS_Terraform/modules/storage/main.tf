# =============================================================================
# modules/storage/main.tf
# =============================================================================
# Bucket S3 para backups off-site - substitui o diretorio ./backups/ local da Fase 2.
#
# O backup container da Fase 2 continua rodando na EC2 e salvando em ./backups/.
# Um cron no HOST sincroniza ./backups/ -> S3 via `aws s3 sync`.
# A EC2 acessa o S3 via IAM Instance Profile (sem credenciais estaticas no host).
#
# Ciclo de vida dos objetos:
#   0-30d   -> S3 Standard     (acesso frequente em caso de restore)
#   30-90d  -> Standard-IA     (acesso infrequente, custo menor)
#   90-365d -> Glacier          (arquivamento, acesso raro)
#   >365d   -> Expirado         (configuravel via var.backup_retention_days)
# =============================================================================

resource "aws_s3_bucket" "backups" {
  # account_id garante unicidade global do nome do bucket
  bucket = "${var.name_prefix}-backups-${var.aws_account_id}"

  tags = merge(var.common_tags, {
    Name    = "${var.name_prefix}-backups"
    Purpose = "glpi-backups-offsite"
  })
}

# Versionamento - permite recuperar versoes anteriores de um backup corrompido
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Criptografia em repouso - AES-256 gerenciado pela AWS (sem custo extra)
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Bloqueia todo acesso publico - backups contem dados sensiveis do banco GLPI
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Ciclo de vida: custo decresce com o tempo, acesso fica mais raro
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  # Versoes atuais: Standard -> IA -> Glacier -> Expirar
  rule {
    id     = "backup-tiering"
    status = "Enabled"

    filter {}

    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    dynamic "expiration" {
      for_each = var.backup_retention_days > 0 ? [1] : []
      content {
        days = var.backup_retention_days
      }
    }
  }

  # Versoes nao-atuais (substituidas): expirar apos 90 dias
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket Policy - apenas o IAM Role da EC2 pode ler/escrever
# Rejeita qualquer acesso que nao venha do role correto (mesmo se credenciais vazarem)
resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  # O bucket precisa ter o public access block aplicado antes da policy
  depends_on = [aws_s3_bucket_public_access_block.backups]
}

data "aws_iam_policy_document" "bucket_policy" {
  # Nega qualquer acesso sem HTTPS (encripta dados em transito)
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Permite acesso completo apenas ao role da EC2
  statement {
    sid    = "AllowEC2RoleAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.ec2_role_arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]
  }
}
