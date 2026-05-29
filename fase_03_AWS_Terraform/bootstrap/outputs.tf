output "state_bucket_name" {
  description = "Nome do bucket S3 para o backend remoto. Copie para o bloco backend em ../main.tf"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_region" {
  description = "Regiao do bucket S3."
  value       = var.aws_region
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB para locking. Copie para o bloco backend em ../main.tf"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_config_snippet" {
  description = "Bloco backend pronto para copiar em ../main.tf"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.bucket}"
        key            = "fase03/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
        encrypt        = true
      }
    }
  EOT
}
