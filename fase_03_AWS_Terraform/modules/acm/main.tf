# =============================================================================
# modules/acm/main.tf
# =============================================================================
# Provisiona um certificado TLS wildcard no AWS Certificate Manager (ACM)
# e valida automaticamente via DNS no Route 53.
#
# NOTA IMPORTANTE - Por que ACM sem ALB?
# ----------------------------------------
# O ACM sozinho nao substitui o Caddy (Let's Encrypt) nesta fase porque:
#   - Certificados ACM so sao utilizaveis em servicos AWS (ALB, CloudFront, API Gateway)
#   - Nao e possivel exportar/instalar um certificado ACM em uma EC2 diretamente
#
# O certificado e provisionado aqui por dois motivos:
#   1. Aprendizado: provisionar + validar um ACM cert e um conceito chave do Terraform/AWS
#   2. Preparacao: quando o ALB for adicionado em uma fase futura, o cert ja existe e esta validado
#
# Em producao nesta fase: o Caddy continua sendo o TLS terminator com Let's Encrypt.
# =============================================================================

# Certificado wildcard para o dominio base + wildcard
# Cobre: exemplo.com.br E *.exemplo.com.br (glpi., grafana.glpi., etc.)
resource "aws_acm_certificate" "main" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"

  # Novo certificado criado antes de destruir o antigo (zero-downtime em renovacoes)
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-acm-cert"
    Note = "pronto-para-ALB-fase-futura"
  })
}

# Registros DNS de validacao no Route 53
# O ACM gera CNAMEs que provam que somos donos do dominio
# O Terraform cria esses CNAMEs automaticamente na zona Route 53
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Aguarda a validacao completar (pode levar ate 5 minutos)
# Sem isso, o apply termina antes do cert estar pronto para uso
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}
