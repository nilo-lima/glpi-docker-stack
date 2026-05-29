variable "name_prefix" {
  description = "Prefixo para nomear os recursos ACM."
  type        = string
}

variable "domain" {
  description = "Dominio base para o certificado (ex: exemplo.com.br)."
  type        = string
}

variable "zone_id" {
  description = "ID da hosted zone Route 53 para criacao dos registros de validacao DNS."
  type        = string
}

variable "common_tags" {
  description = "Tags comuns aplicadas em todos os recursos."
  type        = map(string)
  default     = {}
}
