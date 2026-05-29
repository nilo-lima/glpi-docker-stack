variable "name_prefix" {
  description = "Prefixo para nomear os recursos de storage."
  type        = string
}

variable "aws_account_id" {
  description = "ID da conta AWS (usado para nomear o bucket com unicidade global)."
  type        = string
}

variable "backup_retention_days" {
  description = "Dias antes de expirar objetos no bucket de backup (0 = nunca expirar)."
  type        = number
  default     = 365

  validation {
    condition     = var.backup_retention_days >= 0
    error_message = "backup_retention_days deve ser 0 (sem expiracao) ou um numero positivo."
  }
}

variable "transition_to_ia_days" {
  description = "Dias antes de mover objetos para Standard-IA (custo menor para acesso infrequente)."
  type        = number
  default     = 30
}

variable "transition_to_glacier_days" {
  description = "Dias antes de mover objetos para Glacier (arquivamento de longo prazo)."
  type        = number
  default     = 90
}

variable "ec2_role_arn" {
  description = "ARN do IAM Role da EC2. Permite que somente a EC2 leia/escreva no bucket."
  type        = string
}

variable "common_tags" {
  description = "Tags comuns aplicadas em todos os recursos."
  type        = map(string)
  default     = {}
}
