output "bucket_name" {
  description = "Nome do bucket S3 de backups."
  value       = aws_s3_bucket.backups.bucket
}

output "bucket_arn" {
  description = "ARN do bucket S3 de backups."
  value       = aws_s3_bucket.backups.arn
}

output "bucket_region" {
  description = "Regiao do bucket S3."
  value       = aws_s3_bucket.backups.region
}
