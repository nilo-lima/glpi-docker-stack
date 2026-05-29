# =============================================================================
# variables.tf - Todas as variaveis de entrada do modulo raiz
# =============================================================================
# Copie terraform.tfvars.example para terraform.tfvars e preencha os valores.
# terraform.tfvars esta no .gitignore (contem senhas).

# --- Geral ---

variable "project_name" {
  description = "Nome do projeto. Usado como prefixo em todos os recursos AWS."
  type        = string
  default     = "glpi-fase3"
}

variable "environment" {
  description = "Ambiente de deployment (prod, staging, dev)."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment deve ser 'prod', 'staging' ou 'dev'."
  }
}

variable "aws_region" {
  description = "Regiao AWS para criacao dos recursos."
  type        = string
  default     = "us-east-1"
}

# --- Rede ---

variable "vpc_cidr" {
  description = "CIDR block da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "admin_cidr_blocks" {
  description = <<-EOT
    Lista de CIDRs autorizados para SSH (porta 22).
    NUNCA use 0.0.0.0/0.
    Dica: descubra seu IP com: curl -s https://checkip.amazonaws.com
    Exemplo: ["203.0.113.10/32"]
  EOT
  type        = list(string)
}

# --- Compute ---

variable "instance_type" {
  description = "Tipo da instancia EC2. Minimo t3.large para Fase 2 completa (14 containers, 8 GB)."
  type        = string
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  description = "Tamanho do volume EBS em GB."
  type        = number
  default     = 30
}

variable "ssh_public_key" {
  description = "Conteudo da chave publica SSH (conteudo de ~/.ssh/id_rsa.pub ou equivalente)."
  type        = string
}

variable "repo_url" {
  description = "URL do repositorio Git com o projeto GLPI."
  type        = string
  default     = "https://github.com/nilo-lima/glpi-docker-stack.git"
}

variable "repo_branch" {
  description = "Branch do repositorio a ser clonado na EC2."
  type        = string
  default     = "main"
}

# --- DNS ---

variable "domain" {
  description = "Dominio base registrado (ex: exemplo.com.br). Deve existir no registrador."
  type        = string
}

variable "create_dns_zone" {
  description = "Se true, cria nova hosted zone no Route 53. Se false, usa zona existente."
  type        = bool
  default     = true
}

variable "glpi_subdomain" {
  description = "Subdominio do GLPI (default: 'glpi' -> glpi.dominio.com)."
  type        = string
  default     = "glpi"
}

variable "grafana_subdomain" {
  description = "Subdominio do Grafana (default: 'grafana.glpi' -> grafana.glpi.dominio.com)."
  type        = string
  default     = "grafana.glpi"
}

# --- Configuracao GLPI (injetadas no .env via user_data) ---

variable "acme_email" {
  description = "Email para notificacoes Let's Encrypt."
  type        = string
}

variable "mariadb_root_password" {
  description = "Senha root do MariaDB. Use caracteres alfanumericos (evite @ / # no inicio)."
  type        = string
  sensitive   = true
}

variable "mariadb_password" {
  description = "Senha do usuario 'glpi' no MariaDB."
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Senha do Redis. Nao use @ ou / (quebra DSN do redis-exporter)."
  type        = string
  sensitive   = true
}

variable "mariadb_monitoring_password" {
  description = "Senha do usuario 'monitoring' no MariaDB. Nao use @ ou / (quebra DSN MySQL)."
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Senha do admin do Grafana."
  type        = string
  sensitive   = true
}

variable "grafana_secret_key" {
  description = "Chave secreta do Grafana (32 bytes hex). Gere: openssl rand -hex 32"
  type        = string
  sensitive   = true
}

# --- Versoes de imagens Docker ---

variable "glpi_image_tag" {
  description = "Tag da imagem Docker do GLPI."
  type        = string
  default     = "11.0.7"
}

variable "mariadb_image_tag" {
  description = "Tag da imagem Docker do MariaDB."
  type        = string
  default     = "11.4"
}

variable "redis_image_tag" {
  description = "Tag da imagem Docker do Redis."
  type        = string
  default     = "7.4-alpine"
}

# --- Storage ---

variable "backup_retention_days" {
  description = "Dias de retencao de backups no S3 (0 = nunca expirar)."
  type        = number
  default     = 365
}
