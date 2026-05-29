# =============================================================================
# modules/security_groups/main.tf
# =============================================================================
# Security Group da EC2 - equivalente ao iptables/firewall do host na Fase 2.
#
# Regras de ingresso:
#   22/tcp   <- admin_cidr_blocks APENAS (nunca 0.0.0.0/0)
#   80/tcp   <- internet (Caddy redireciona para HTTPS)
#   443/tcp  <- internet (GLPI + Grafana via Caddy)
#   443/udp  <- internet (QUIC/HTTP3 opcional)
#
# Regras de egresso:
#   tudo    -> internet (necessario para Docker pull, ACME Let's Encrypt, apt-get)
#
# Nota: portas internas (MariaDB 3306, Redis 6379, Prometheus 9090, etc.)
# NAO sao expostas no Security Group - trafego fica dentro do host Docker.
# =============================================================================

resource "aws_security_group" "ec2" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "Security Group da EC2 GLPI Fase 3 - HTTP/HTTPS publico, SSH restrito"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ec2-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Regras de INGRESSO (inbound)
# -----------------------------------------------------------------------------

# SSH - apenas do IP/rede do administrador
# Nunca abrir para 0.0.0.0/0: risco de brute-force e acesso nao autorizado
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.admin_cidr_blocks)

  security_group_id = aws_security_group.ec2.id
  description       = "SSH para administracao - IP restrito"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-rule-ssh-${replace(each.value, "/", "-")}"
  })
}

# HTTP (IPv4) - Caddy escuta na 80 e redireciona para HTTPS
resource "aws_vpc_security_group_ingress_rule" "http_ipv4" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP IPv4 - Caddy redireciona para HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-rule-http-ipv4"
  })
}

# HTTP (IPv6)
resource "aws_vpc_security_group_ingress_rule" "http_ipv6" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP IPv6 - Caddy redireciona para HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv6         = "::/0"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-rule-http-ipv6"
  })
}

# HTTPS TCP (IPv4) - GLPI e Grafana via Caddy
resource "aws_vpc_security_group_ingress_rule" "https_tcp_ipv4" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS TCP IPv4 - GLPI e Grafana"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-rule-https-tcp-ipv4"
  })
}

# HTTPS TCP (IPv6)
resource "aws_vpc_security_group_ingress_rule" "https_tcp_ipv6" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS TCP IPv6 - GLPI e Grafana"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = "::/0"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-rule-https-tcp-ipv6"
  })
}

# HTTPS UDP (IPv4) - QUIC/HTTP3 (opcional, suportado pelo Caddy)
resource "aws_vpc_security_group_ingress_rule" "https_udp_ipv4" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS UDP IPv4 - QUIC/HTTP3"
  ip_protocol       = "udp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-rule-https-udp-ipv4"
  })
}

# HTTPS UDP (IPv6)
resource "aws_vpc_security_group_ingress_rule" "https_udp_ipv6" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS UDP IPv6 - QUIC/HTTP3"
  ip_protocol       = "udp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = "::/0"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-rule-https-udp-ipv6"
  })
}

# -----------------------------------------------------------------------------
# Regras de EGRESSO (outbound)
# -----------------------------------------------------------------------------

# Todo trafego de saida liberado (IPv4)
# Necessario para:
#   - Docker pull de imagens (Docker Hub, ghcr.io)
#   - ACME Let's Encrypt challenge (Caddy)
#   - apt-get update/upgrade
#   - AWS S3 sync (backups off-site)
#   - NTP, DNS
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.ec2.id
  description       = "Egresso total IPv4 - Docker pull, ACME, S3 sync, apt"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-rule-egress-all-ipv4"
  })
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.ec2.id
  description       = "Egresso total IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-rule-egress-all-ipv6"
  })
}
