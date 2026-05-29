# =============================================================================
# modules/vpc/main.tf
# =============================================================================
# Cria a rede AWS equivalente ao isolamento de rede Docker da Fase 2:
#
#   Docker (Fase 2)              AWS (Fase 3)
#   --------------------         -------------------------
#   frontend_net (bridge)   -->  Subnet publica A (EC2 com EIP)
#   backend_net (internal)  -->  Subnet privada   (RDS/Redis futuros)
#   monitoring_net          -->  Subnet publica B (reservada para futura HA)
#
# Principio de defesa em profundidade: a subnet privada nao tem rota para o IGW,
# portanto recursos nela nunca recebem trafego da internet diretamente.
# =============================================================================

# VPC principal
# dns_support e dns_hostnames habilitados: necessarios para resolucao de nomes
# de instancias EC2 e para endpoints da AWS (S3, Secrets Manager, etc.)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# Internet Gateway - permite que subnets publicas enviem/recebam trafego da internet
# A subnet privada NAO tem rota para este IGW (defesa em profundidade)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# -----------------------------------------------------------------------------
# Subnets publicas
# Usam o IGW para trafego de saida. A EC2 fica aqui com Elastic IP.
# map_public_ip_on_launch = false: instancias NAO recebem IP publico automatico;
# usamos Elastic IP explicitamente para controle e DNS estavel.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_public_a_cidr
  availability_zone       = var.az_a
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-subnet-public-a"
    Tier = "public"
  })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_public_b_cidr
  availability_zone       = var.az_b
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-subnet-public-b"
    Tier = "public"
    Note = "reservada-para-ALB-HA-futura"
  })
}

# -----------------------------------------------------------------------------
# Subnet privada
# SEM rota para o IGW: recursos aqui nao sao alcancaveis pela internet.
# Reservada para RDS MariaDB e ElastiCache quando migrar da Fase 3 para Fase 4.
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_private_cidr
  availability_zone = var.az_a

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-subnet-private"
    Tier = "private"
    Note = "reservada-RDS-ElastiCache"
  })
}

# -----------------------------------------------------------------------------
# Route tables
# -----------------------------------------------------------------------------

# Route table publica: 0.0.0.0/0 -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-rt-public"
  })
}

# Associa as duas subnets publicas com a route table publica
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Route table privada: sem rota para IGW (trafego fica dentro da VPC)
# Criada explicita para deixar claro o isolamento - nao usa a main route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-rt-private"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
