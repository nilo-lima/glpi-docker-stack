variable "name_prefix" {
  description = "Prefixo para nomear todos os recursos do modulo."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block da VPC. Deve ser /16 para acomodar subnets /24."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_public_a_cidr" {
  description = "CIDR da subnet publica na AZ-a (hospeda a EC2)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_public_b_cidr" {
  description = "CIDR da subnet publica na AZ-b (reservada para HA futura / ALB)."
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_private_cidr" {
  description = "CIDR da subnet privada na AZ-a (reservada para RDS/ElastiCache futuros)."
  type        = string
  default     = "10.0.3.0/24"
}

variable "az_a" {
  description = "Zona de disponibilidade A (ex: us-east-1a)."
  type        = string
}

variable "az_b" {
  description = "Zona de disponibilidade B (ex: us-east-1b)."
  type        = string
}

variable "common_tags" {
  description = "Tags comuns aplicadas em todos os recursos."
  type        = map(string)
  default     = {}
}
