variable "name_prefix" {
  description = "Prefixo para nomear os recursos de DNS."
  type        = string
}

variable "domain" {
  description = "Dominio base (ex: exemplo.com.br). Deve existir no registrador de dominio."
  type        = string
}

variable "create_zone" {
  description = <<-EOT
    Se true, cria uma nova hosted zone no Route 53.
    Se false, usa uma hosted zone ja existente (data source).
    Use true para dominios novos ou ja gerenciados no Route 53.
    Use false se a zona ja foi criada manualmente e voce quer apenas adicionar records.
  EOT
  type        = bool
  default     = true
}

variable "glpi_subdomain" {
  description = "Subdominio para o GLPI (ex: 'glpi' resulta em glpi.dominio.com)."
  type        = string
  default     = "glpi"
}

variable "grafana_subdomain" {
  description = "Subdominio para o Grafana (ex: 'grafana.glpi' resulta em grafana.glpi.dominio.com)."
  type        = string
  default     = "grafana.glpi"
}

variable "ec2_public_ip" {
  description = "Elastic IP da EC2. Os A records apontarao para este IP."
  type        = string
}

variable "dns_ttl" {
  description = "TTL dos A records em segundos. 300s (5 min) para facilitar mudancas iniciais."
  type        = number
  default     = 300
}

variable "common_tags" {
  description = "Tags comuns aplicadas em todos os recursos."
  type        = map(string)
  default     = {}
}
