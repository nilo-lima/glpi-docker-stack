output "zone_id" {
  description = "ID da hosted zone no Route 53."
  value       = local.zone_id
}

output "nameservers" {
  description = <<-EOT
    Nameservers da zona Route 53.
    ACAO NECESSARIA: Configure estes 4 nameservers no painel do registrador do dominio
    (ex: Registro.br, GoDaddy, Namecheap). Sem isso, o Route 53 nao resolve o dominio.
  EOT
  value       = var.create_zone ? aws_route53_zone.main[0].name_servers : []
}

output "glpi_fqdn" {
  description = "FQDN do GLPI (nome completo com dominio)."
  value       = aws_route53_record.glpi.fqdn
}

output "grafana_fqdn" {
  description = "FQDN do Grafana."
  value       = aws_route53_record.grafana.fqdn
}
