#!/usr/bin/env bash
# =============================================================================
# teardown.sh - Teardown guiado da infraestrutura Fase 3
# =============================================================================
# Garante que o backup final seja feito ANTES de destruir qualquer recurso.
# Nao executa terraform destroy sozinho - exige confirmacao em cada passo.
#
# Uso: ./scripts/teardown.sh
# Executar a partir do diretorio fase_03_AWS_Terraform/
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $*"; }
error(){ echo -e "${RED}[ERRO]${NC} $*" >&2; }

confirm() {
  local msg="$1"
  echo -e "${YELLOW}$msg${NC}"
  read -r -p "Confirmar? (s/N): " resposta
  [[ "$resposta" =~ ^[sS]$ ]]
}

# Verificar que estamos no diretorio correto
if [ ! -f "main.tf" ]; then
  error "Execute a partir do diretorio fase_03_AWS_Terraform/"
  exit 1
fi

# Caminho da stack dentro do repo clonado na EC2
REMOTE_STACK_DIR="/opt/glpi/fase_03_AWS_Terraform/stack"

echo ""
echo "============================================================"
echo "  TEARDOWN GUIADO - GLPI Fase 3 AWS"
echo "============================================================"
warn "Este processo vai DESTRUIR toda a infraestrutura AWS."
warn "Os dados do GLPI serao perdidos se nao forem salvos antes."
echo ""

# --- Obter informacoes da infraestrutura ---
log "Lendo outputs do Terraform..."
EC2_IP=$(terraform output -raw ec2_public_ip 2>/dev/null || echo "")
S3_BUCKET=$(terraform output -raw s3_backup_bucket 2>/dev/null || echo "")
EC2_ID=$(terraform output -raw ec2_instance_id 2>/dev/null || echo "")

if [ -z "$EC2_IP" ]; then
  warn "Nao foi possivel ler outputs (infraestrutura pode ja estar destruida)."
  if confirm "Executar 'terraform destroy' mesmo assim?"; then
    terraform destroy
  fi
  exit 0
fi

log "EC2 IP:     $EC2_IP"
log "S3 Bucket:  $S3_BUCKET"
log "EC2 ID:     $EC2_ID"
log "Stack dir:  $REMOTE_STACK_DIR (no host EC2)"
echo ""

# --- Passo 1: Backup final ---
if confirm "[PASSO 1/4] Fazer backup final da stack antes de destruir?"; then
  log "Executando backup-now.sh na EC2..."
  ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no "admin@$EC2_IP" \
    "cd $REMOTE_STACK_DIR && ./scripts/backup-now.sh"
  log "Backup concluido."
fi

# --- Passo 2: Sincronizar para S3 ---
if [ -n "$S3_BUCKET" ] && confirm "[PASSO 2/4] Sincronizar backups para S3 antes de destruir?"; then
  log "Sincronizando backups para s3://$S3_BUCKET/backups/ ..."
  ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no "admin@$EC2_IP" \
    "aws s3 sync $REMOTE_STACK_DIR/backups/ s3://$S3_BUCKET/backups/ --storage-class STANDARD_IA"
  log "Sync concluido."
fi

# --- Passo 3: Download local (opcional) ---
if confirm "[PASSO 3/4] Fazer download local dos backups para ~/backups-glpi-fase3/?"; then
  BACKUP_DIR="$HOME/backups-glpi-fase3-$(date '+%Y%m%d_%H%M%S')"
  mkdir -p "$BACKUP_DIR"
  log "Baixando backups para $BACKUP_DIR ..."
  scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -r \
    "admin@$EC2_IP:$REMOTE_STACK_DIR/backups/" \
    "$BACKUP_DIR/"
  log "Download concluido: $BACKUP_DIR"
fi

# --- Passo 4: terraform destroy ---
echo ""
warn "============================================================"
warn "  ATENCAO: Proximo passo DESTROI toda a infraestrutura!"
warn "  EC2, VPC, Security Groups, Route 53, ACM serao removidos."
warn "  O S3 state bucket (bootstrap/) NAO e destruido por padrao."
warn "  Os backups no S3 de dados continuam existindo no bucket."
warn "============================================================"
echo ""

if confirm "[PASSO 4/4] Executar 'terraform destroy'?"; then
  log "Iniciando terraform destroy..."
  terraform destroy
  log "Infraestrutura destruida com sucesso."
  echo ""
  log "Para destruir tambem o bucket de backups S3:"
  log "  aws s3 rm s3://$S3_BUCKET --recursive"
  log ""
  log "Para destruir o bucket de state do Terraform (bootstrap/):"
  log "  cd bootstrap/"
  log "  # Editar main.tf: lifecycle { prevent_destroy = false }"
  log "  terraform apply"
  log "  aws s3 rm s3://<state-bucket> --recursive"
  log "  terraform destroy"
else
  warn "terraform destroy cancelado. Infraestrutura permanece intacta."
fi
