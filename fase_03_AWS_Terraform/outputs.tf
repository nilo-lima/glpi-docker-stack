# =============================================================================
# outputs.tf - Valores importantes exibidos apos terraform apply
# =============================================================================

output "ec2_public_ip" {
  description = "Elastic IP publico da EC2. Configure seus A records DNS para este IP."
  value       = module.compute.public_ip
}

output "ec2_instance_id" {
  description = "ID da instancia EC2 (para stop/start manual via Console ou CLI)."
  value       = module.compute.instance_id
}

output "ssh_command" {
  description = "Comando SSH para conectar na instancia."
  value       = module.compute.ssh_command
}

output "ami_used" {
  description = "AMI Debian 12 utilizada."
  value       = "${module.compute.ami_name} (${module.compute.ami_id})"
}

output "glpi_url" {
  description = "URL do GLPI (disponivel apos propagacao DNS e bootstrap da EC2)."
  value       = "https://${module.dns.glpi_fqdn}"
}

output "grafana_url" {
  description = "URL do Grafana (disponivel apos propagacao DNS e bootstrap da EC2)."
  value       = "https://${module.dns.grafana_fqdn}"
}

output "s3_backup_bucket" {
  description = "Nome do bucket S3 de backups."
  value       = module.storage.bucket_name
}

output "route53_nameservers" {
  description = <<-EOT
    ACAO NECESSARIA: Configure estes nameservers no painel do registrador do seu dominio.
    Sem isso, o Route 53 nao resolve o dominio e o Let's Encrypt nao consegue emitir o cert.
  EOT
  value = module.dns.nameservers
}

output "acm_certificate_arn" {
  description = "ARN do certificado ACM (usar ao adicionar ALB em fase futura)."
  value       = module.acm.certificate_arn
}

output "vpc_id" {
  description = "ID da VPC criada."
  value       = module.vpc.vpc_id
}

output "bootstrap_log" {
  description = "Comando para acompanhar o bootstrap na EC2 apos criacao."
  value       = "ssh -i ~/.ssh/id_rsa admin@${module.compute.public_ip} 'tail -f /var/log/glpi-bootstrap.log'"
}

output "teardown_reminder" {
  description = "Para evitar custos: pare a instancia quando nao estiver usando."
  value       = "aws ec2 stop-instances --instance-ids ${module.compute.instance_id} --region ${var.aws_region}"
}
