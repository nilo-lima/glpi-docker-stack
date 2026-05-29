output "certificate_arn" {
  description = <<-EOT
    ARN do certificado ACM validado.
    Use este ARN ao criar um ALB (aws_lb_listener https -> certificate_arn) em uma fase futura.
  EOT
  value = aws_acm_certificate_validation.main.certificate_arn
}

output "certificate_domain" {
  description = "Dominio principal do certificado."
  value       = aws_acm_certificate.main.domain_name
}

output "certificate_status" {
  description = "Status do certificado ACM (deve ser ISSUED apos validacao)."
  value       = aws_acm_certificate.main.status
}
