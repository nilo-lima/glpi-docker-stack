# =============================================================================
# modules/dns/main.tf
# =============================================================================
# Gerencia a zona DNS e os A records para GLPI e Grafana no Route 53.
#
# Fluxo DNS:
#   Registrador (ex: Registro.br)
#     └── NS records apontando para nameservers Route 53 (output deste modulo)
#           └── Route 53 Hosted Zone (dominio.com)
#                 ├── glpi.dominio.com      A -> Elastic IP da EC2
#                 └── grafana.glpi.dominio.com  A -> Elastic IP da EC2
#
# IMPORTANTE: Apos o apply, copie os nameservers do output para o painel
# do registrador do dominio. Sem isso, o Route 53 nao resolve o dominio.
# =============================================================================

# -----------------------------------------------------------------------------
# Hosted Zone (criar nova OU usar existente)
# -----------------------------------------------------------------------------

# Cria nova hosted zone (default: create_zone = true)
resource "aws_route53_zone" "main" {
  count = var.create_zone ? 1 : 0

  name    = var.domain
  comment = "Zona gerenciada pelo Terraform - projeto GLPI Fase 3"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-zone-${var.domain}"
  })
}

# Usa zona existente (create_zone = false)
data "aws_route53_zone" "existing" {
  count        = var.create_zone ? 0 : 1
  name         = var.domain
  private_zone = false
}

# Local para abstrair a diferenca entre criar/usar zona
locals {
  zone_id = var.create_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.existing[0].zone_id
}

# -----------------------------------------------------------------------------
# A records
# -----------------------------------------------------------------------------

# glpi.dominio.com -> Elastic IP da EC2
resource "aws_route53_record" "glpi" {
  zone_id = local.zone_id
  name    = "${var.glpi_subdomain}.${var.domain}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [var.ec2_public_ip]
}

# grafana.glpi.dominio.com -> mesmo Elastic IP (Caddy roteia pelo hostname)
resource "aws_route53_record" "grafana" {
  zone_id = local.zone_id
  name    = "${var.grafana_subdomain}.${var.domain}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [var.ec2_public_ip]
}
