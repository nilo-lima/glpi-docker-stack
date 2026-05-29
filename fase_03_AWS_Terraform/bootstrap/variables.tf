variable "aws_region" {
  description = "Regiao AWS onde o bucket de estado e a tabela DynamoDB serao criados."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo usado nos nomes dos recursos de bootstrap."
  type        = string
  default     = "glpi-fase3"
}
