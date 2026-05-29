variable "name_prefix" {
  description = "Prefixo para nomear o Security Group."
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC onde o Security Group sera criado."
  type        = string
}

variable "admin_cidr_blocks" {
  description = <<-EOT
    Lista de CIDRs autorizados para acesso SSH (porta 22).
    NUNCA use 0.0.0.0/0 em producao.
    Exemplo: ["203.0.113.10/32", "198.51.100.0/24"]
  EOT
  type        = list(string)

  validation {
    condition = alltrue([
      for cidr in var.admin_cidr_blocks :
      cidr != "0.0.0.0/0" && cidr != "::/0"
    ])
    error_message = "SSH (porta 22) nao pode ser aberto para 0.0.0.0/0 ou ::/0. Especifique o IP do administrador."
  }
}

variable "common_tags" {
  description = "Tags comuns aplicadas em todos os recursos."
  type        = map(string)
  default     = {}
}
