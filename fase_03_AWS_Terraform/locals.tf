# =============================================================================
# locals.tf - Convencoes de nomenclatura e tags obrigatorias
# =============================================================================
# Centraliza nomes e tags para consistencia entre todos os modulos.
# Todo recurso AWS DEVE referenciar local.common_tags via `tags = local.common_tags`
# (ou merge com tags especificas do recurso).

locals {
  # Prefixo para todos os nomes de recursos (evita colisoes em conta compartilhada)
  name_prefix = "${var.project_name}-${var.environment}"

  # Tags obrigatorias em todos os recursos AWS
  # Permite filtrar custo por projeto no AWS Cost Explorer
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Phase       = "3"
    Repository  = "glpi-docker-stack"
  }

  # AZs usadas neste projeto (2 publicas para futura HA, 1 privada para dados)
  az_a = "${var.aws_region}a"
  az_b = "${var.aws_region}b"
}
