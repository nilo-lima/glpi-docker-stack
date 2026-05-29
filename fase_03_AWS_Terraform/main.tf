# =============================================================================
# main.tf - Modulo raiz: chama os sub-modulos e conecta os outputs
# =============================================================================
# Ordem de criacao dos recursos (dependencias implicitas via outputs):
#   1. vpc             - rede (subnets, IGW, route tables)
#   2. security_groups - firewall (referencia vpc_id)
#   3. storage         - S3 backup (referencia ec2_role_arn do compute)
#   4. compute         - EC2 + EIP + IAM (referencia subnet + sg + bucket)
#   5. dns             - Route 53 A records (referencia ec2 public_ip)
#   6. acm             - Certificado TLS (referencia zone_id do dns)
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Identidade da conta AWS (account_id usada para nomear recursos com unicidade global)
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Modulo 1: VPC e rede
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  subnet_public_a_cidr = "10.0.1.0/24"
  subnet_public_b_cidr = "10.0.2.0/24"
  subnet_private_cidr  = "10.0.3.0/24"
  az_a                 = local.az_a
  az_b                 = local.az_b
  common_tags          = local.common_tags
}

# -----------------------------------------------------------------------------
# Modulo 2: Security Groups
# -----------------------------------------------------------------------------
module "security_groups" {
  source = "./modules/security_groups"

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  admin_cidr_blocks = var.admin_cidr_blocks
  common_tags       = local.common_tags
}

# -----------------------------------------------------------------------------
# Modulo 3: Storage (S3)
# Precisa criar antes do compute pois o IAM policy do compute referencia o bucket
# O ec2_role_arn vem do modulo compute, mas o bucket precisa existir primeiro.
# Solucao: ec2_role_arn e passado como variavel pelo modulo compute apos sua criacao.
# Na pratica, o Terraform resolve a ordem automaticamente pelo grafo de dependencias.
# -----------------------------------------------------------------------------
module "storage" {
  source = "./modules/storage"

  name_prefix                = local.name_prefix
  aws_account_id             = data.aws_caller_identity.current.account_id
  ec2_role_arn               = module.compute.ec2_role_arn
  backup_retention_days      = var.backup_retention_days
  transition_to_ia_days      = 30
  transition_to_glacier_days = 90
  common_tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# Modulo 4: Compute (EC2)
# -----------------------------------------------------------------------------
module "compute" {
  source = "./modules/compute"

  name_prefix       = local.name_prefix
  subnet_id         = module.vpc.subnet_public_a_id
  security_group_id = module.security_groups.ec2_sg_id
  instance_type     = var.instance_type
  root_volume_size_gb = var.root_volume_size_gb
  ssh_public_key    = var.ssh_public_key
  aws_region        = var.aws_region
  bucket_name       = module.storage.bucket_name
  repo_url          = var.repo_url
  repo_branch       = var.repo_branch
  common_tags       = local.common_tags

  # Configuracao GLPI (injetada no .env via user_data)
  glpi_domain                 = "${var.glpi_subdomain}.${var.domain}"
  grafana_domain              = "${var.grafana_subdomain}.${var.domain}"
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
}

# -----------------------------------------------------------------------------
# Modulo 5: DNS (Route 53) - DESABILITADO
# DNS gerenciado pelo Cloudflare. Apos o apply, criar manualmente no Cloudflare:
#   A  glpi.grupolimajr.com.br         -> EC2 public IP (output ec2_public_ip)
#   A  grafana.glpi.grupolimajr.com.br -> EC2 public IP (output ec2_public_ip)
# TLS e gerenciado pelo Caddy via Let's Encrypt (HTTP-01 challenge).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Modulo 6: ACM (Certificado TLS) - DESABILITADO
# Ja existe certificado wildcard *.grupolimajr.com.br ISSUED na conta.
# Reativar ao adicionar ALB em fase futura (importar o cert existente).
# -----------------------------------------------------------------------------
