# =============================================================================
# outputs.tf - Valores importantes exibidos apos terraform apply
# =============================================================================

output "ec2_public_ip" {
  description = "Elastic IP publico da EC2. Configure os A records no Cloudflare para este IP."
  value       = module.compute.public_ip
}

output "ec2_instance_id" {
  description = "ID da instancia EC2 (para stop/start manual via Console ou CLI)."
  value       = module.compute.instance_id
}

output "ssh_command" {
  description = "Comando SSH para conectar na instancia."
  value       = "ssh -i ~/.ssh/id_ed25519 admin@${module.compute.public_ip}"
}

output "ami_used" {
  description = "AMI Debian 12 utilizada."
  value       = "${module.compute.ami_name} (${module.compute.ami_id})"
}

output "glpi_url" {
  description = "URL do GLPI (disponivel apos A record no Cloudflare e bootstrap da EC2)."
  value       = "https://${var.glpi_subdomain}.${var.domain}"
}

output "grafana_url" {
  description = "URL do Grafana (disponivel apos A record no Cloudflare e bootstrap da EC2)."
  value       = "https://${var.grafana_subdomain}.${var.domain}"
}

output "s3_backup_bucket" {
  description = "Nome do bucket S3 de backups."
  value       = module.storage.bucket_name
}

output "cloudflare_dns_records" {
  description = "ACAO NECESSARIA: Criar estes A records no Cloudflare apos o apply."
  value       = <<-EOT
    Tipo  Nome                              Conteudo          Proxy
    A     glpi.grupolimajr.com.br           ${module.compute.public_ip}   DNS only (nuvem cinza)
    A     grafana.glpi.grupolimajr.com.br   ${module.compute.public_ip}   DNS only (nuvem cinza)

    IMPORTANTE: usar "DNS only" (nuvem cinza, nao laranja) para que o
    Caddy consiga emitir o certificado Let's Encrypt via HTTP-01 challenge.
  EOT
}

output "bootstrap_log" {
  description = "Comando para acompanhar o bootstrap na EC2 apos criacao."
  value       = "ssh -i ~/.ssh/id_ed25519 admin@${module.compute.public_ip} 'tail -f /var/log/glpi-bootstrap.log'"
}

output "teardown_reminder" {
  description = "Para evitar custos: pare a instancia quando nao estiver usando."
  value       = "aws ec2 stop-instances --instance-ids ${module.compute.instance_id} --region ${var.aws_region}"
}
