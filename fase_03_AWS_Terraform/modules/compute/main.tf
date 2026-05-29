# =============================================================================
# modules/compute/main.tf
# =============================================================================
# Provisiona a EC2 que roda a stack GLPI (docker-compose da Fase 2 via user_data).
#
# Componentes:
#   - AMI Debian 12 (buscada dinamicamente - sempre a mais recente da versao 12)
#   - Key Pair SSH (chave publica fornecida via variavel)
#   - IAM Role + Instance Profile (acesso ao S3 sem credenciais estaticas)
#   - EC2 t3.large (8 GB RAM, necessario para 14 containers)
#   - Elastic IP (IP fixo para DNS permanente - nao muda entre stop/start)
# =============================================================================

# Busca a AMI Debian 12 mais recente na regiao configurada
# Owner ID 136693071363 e o ID oficial da Debian no AWS Marketplace
data "aws_ami" "debian_12" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Key Pair - importa a chave publica existente (nunca gera chave privada no Terraform)
# A chave privada fica exclusivamente no computador do administrador
resource "aws_key_pair" "glpi" {
  key_name   = "${var.name_prefix}-key"
  public_key = var.ssh_public_key

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-key"
  })
}

# -----------------------------------------------------------------------------
# IAM Role - permite que a EC2 acesse o S3 sem credenciais estaticas
# O Instance Profile e o "envelope" que associa o role a instancia EC2
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ec2" {
  name        = "${var.name_prefix}-ec2-role"
  description = "Permite que a EC2 GLPI acesse o S3 para backups off-site"

  # Trust policy: apenas o servico EC2 pode assumir este role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ec2-role"
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ec2-profile"
  })
}

# Inline policy: acesso ao bucket de backups
# Escopo restrito ao bucket especifico (principio do menor privilegio)
resource "aws_iam_role_policy" "s3_backup" {
  name = "s3-backup-access"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BackupAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketLocation",
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*",
        ]
      },
      {
        Sid      = "S3ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.bucket_name}"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

# user_data renderizado a partir do template (substitui variaveis no script)
locals {
  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    aws_region                  = var.aws_region
    repo_url                    = var.repo_url
    repo_branch                 = var.repo_branch
    bucket_name                 = var.bucket_name
    glpi_domain                 = var.glpi_domain
    grafana_domain              = var.grafana_domain
    acme_email                  = var.acme_email
    mariadb_root_password       = var.mariadb_root_password
    mariadb_password            = var.mariadb_password
    redis_password              = var.redis_password
    mariadb_monitoring_password = var.mariadb_monitoring_password
    grafana_admin_password      = var.grafana_admin_password
    grafana_secret_key          = var.grafana_secret_key
    glpi_image_tag              = var.glpi_image_tag
    mariadb_image_tag           = var.mariadb_image_tag
    redis_image_tag             = var.redis_image_tag
  })
}

resource "aws_instance" "glpi" {
  ami                    = data.aws_ami.debian_12.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.glpi.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # Desabilita atribuicao automatica de IP publico (usamos Elastic IP explicitamente)
  associate_public_ip_address = false

  # Volume raiz EBS gp3 - custo mais baixo que gp2 com mesma ou maior performance
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.common_tags, {
      Name = "${var.name_prefix}-ebs-root"
    })
  }

  # Script de bootstrap: instala Docker, clona repo, sobe docker compose
  user_data                   = local.user_data
  user_data_replace_on_change = false # Nao recria instancia se user_data mudar (apenas na criacao)

  # IMDSv2 obrigatorio: previne SSRF attacks no metadata service
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ec2"
  })

  # Aguarda o Elastic IP ser associado antes de marcar como pronto
  depends_on = [aws_iam_instance_profile.ec2]
}

# Elastic IP - IP publico fixo que nao muda entre stop/start
# Permite configurar DNS permanente (A records no Route 53)
resource "aws_eip" "glpi" {
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-eip"
  })
}

resource "aws_eip_association" "glpi" {
  instance_id   = aws_instance.glpi.id
  allocation_id = aws_eip.glpi.id
}
