variable "name_prefix" {
  description = "Prefixo para nomear os recursos de compute."
  type        = string
}

variable "subnet_id" {
  description = "ID da subnet publica onde a EC2 sera criada (subnet_public_a)."
  type        = string
}

variable "security_group_id" {
  description = "ID do Security Group a ser associado a EC2."
  type        = string
}

variable "instance_type" {
  description = <<-EOT
    Tipo da instancia EC2.
    Fase 2 exige minimo t3.large (8 GB RAM) para 14 containers com Prometheus TSDB e Loki.
    Use t3.medium (4 GB) apenas para testes rapidos com a stack reduzida.
  EOT
  type        = string
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  description = "Tamanho do volume raiz EBS em GB. 30 GB minimo para Docker images + Prometheus TSDB + Loki."
  type        = number
  default     = 30
}

variable "ssh_public_key" {
  description = "Conteudo da chave publica SSH (ex: conteudo de ~/.ssh/id_rsa.pub). Nao o caminho, o conteudo."
  type        = string
  sensitive   = false
}

variable "aws_region" {
  description = "Regiao AWS (usada no user_data para configurar AWS CLI)."
  type        = string
}

variable "bucket_name" {
  description = "Nome do bucket S3 de backups (injetado no user_data para configurar cron de sync)."
  type        = string
}

# ---- Variaveis de configuracao GLPI (injetadas no .env via user_data) ----

variable "glpi_domain" {
  description = "Dominio principal do GLPI (ex: glpi.exemplo.com.br)."
  type        = string
}

variable "grafana_domain" {
  description = "Dominio do Grafana (ex: grafana.glpi.exemplo.com.br)."
  type        = string
}

variable "acme_email" {
  description = "Email para notificacoes do Let's Encrypt (expiracoes, alertas)."
  type        = string
}

variable "mariadb_root_password" {
  description = "Senha root do MariaDB."
  type        = string
  sensitive   = true
}

variable "mariadb_password" {
  description = "Senha do usuario glpi no MariaDB."
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Senha do Redis. Nao use @ ou / (quebra DSN)."
  type        = string
  sensitive   = true
}

variable "mariadb_monitoring_password" {
  description = "Senha do usuario monitoring no MariaDB. Nao use @ ou / (quebra DSN MySQL)."
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Senha do admin do Grafana."
  type        = string
  sensitive   = true
}

variable "grafana_secret_key" {
  description = "Chave secreta do Grafana (32 bytes hex). Gere com: openssl rand -hex 32"
  type        = string
  sensitive   = true
}

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

variable "repo_url" {
  description = "URL do repositorio Git a ser clonado na EC2."
  type        = string
  default     = "https://github.com/nilo-lima/glpi-docker-stack.git"
}

variable "repo_branch" {
  description = "Branch do repositorio a ser clonado."
  type        = string
  default     = "main"
}

variable "common_tags" {
  description = "Tags comuns aplicadas em todos os recursos."
  type        = map(string)
  default     = {}
}
