#!/bin/bash
# =============================================================================
# user_data.sh.tpl - Bootstrap da EC2 GLPI Fase 3
# =============================================================================
# Este script e renderizado pelo Terraform (templatefile) com as variaveis
# do tfvars e executado UMA VEZ na criacao da instancia EC2.
#
# A Fase 3 e totalmente independente da Fase 2: todos os arquivos Docker
# (docker-compose.yml, services/, scripts/) estao em stack/ dentro deste
# diretorio, sem nenhuma dependencia do diretorio fase_02_Observabilidade/.
#
# O que este script faz:
#   1. Atualiza o sistema Debian 12
#   2. Instala Docker CE (metodo oficial)
#   3. Instala AWS CLI v2
#   4. Clona o repositorio
#   5. Gera o .env em stack/ com as configuracoes do tfvars
#   6. Valida o docker-compose.yml
#   7. Sobe os 14 containers
#   8. Configura sincronizacao automatica de backups para o S3
#
# Logs: /var/log/glpi-bootstrap.log
# Status: /var/lib/glpi-bootstrap.status (success | failed)
#
# Estrutura no host apos o bootstrap:
#   /opt/glpi/
#   └── fase_03_AWS_Terraform/
#       └── stack/                  <- diretorio de trabalho do Docker Compose
#           ├── docker-compose.yml
#           ├── .env                <- gerado por este script
#           ├── services/
#           ├── scripts/
#           └── backups/            <- dumps diarios (sincronizados ao S3)
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/glpi-bootstrap.log"
STATUS_FILE="/var/lib/glpi-bootstrap.status"

# Diretorio raiz do repositorio clonado
REPO_DIR="/opt/glpi"

# Diretorio de trabalho da stack - Fase 3 e totalmente independente
STACK_DIR="$REPO_DIR/fase_03_AWS_Terraform/stack"

# Funcao de log com timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Iniciando bootstrap GLPI Fase 3 ==="
log "Instancia: $(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')"
log "Regiao: ${aws_region}"
log "Repositorio: ${repo_url} (branch: ${repo_branch})"
log "Stack dir: $STACK_DIR"

# -----------------------------------------------------------------------------
# 1. Sistema e dependencias base
# -----------------------------------------------------------------------------
log "--- [1/8] Atualizando sistema Debian 12 ---"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl \
  git \
  unzip \
  ca-certificates \
  gnupg \
  jq

# -----------------------------------------------------------------------------
# 2. Docker CE (metodo oficial - https://get.docker.com)
# -----------------------------------------------------------------------------
log "--- [2/8] Instalando Docker CE ---"
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  log "Docker CE instalado: $(docker --version)"
else
  log "Docker ja instalado: $(docker --version)"
fi

# Adiciona o usuario padrao do Debian ao grupo docker
# (usuario 'admin' na AMI Debian 12 da AWS)
if id "admin" &>/dev/null; then
  usermod -aG docker admin
  log "Usuario 'admin' adicionado ao grupo docker"
fi

# Garante que o Docker daemon esta rodando
systemctl enable --now docker
log "Docker daemon: $(systemctl is-active docker)"

# -----------------------------------------------------------------------------
# 3. AWS CLI v2
# -----------------------------------------------------------------------------
log "--- [3/8] Instalando AWS CLI v2 ---"
if ! command -v aws &>/dev/null; then
  cd /tmp
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install
  rm -rf awscliv2.zip aws/
  log "AWS CLI instalado: $(aws --version)"
else
  log "AWS CLI ja instalado: $(aws --version)"
fi

# Configura a regiao padrao (credenciais vem do IAM Instance Profile - sem aws configure)
aws configure set default.region "${aws_region}"
log "Regiao AWS configurada: ${aws_region}"

# -----------------------------------------------------------------------------
# 4. Clonar repositorio
# -----------------------------------------------------------------------------
log "--- [4/8] Clonando repositorio ---"
if [ -d "$REPO_DIR" ]; then
  log "Diretorio $REPO_DIR ja existe - pulando clone"
else
  git clone --branch "${repo_branch}" --depth 1 "${repo_url}" "$REPO_DIR"
  log "Repositorio clonado em $REPO_DIR"
fi

# Garante que o diretorio stack existe (deve existir apos o clone)
if [ ! -f "$STACK_DIR/docker-compose.yml" ]; then
  log "ERRO: $STACK_DIR/docker-compose.yml nao encontrado apos clone"
  echo "failed" > "$STATUS_FILE"
  exit 1
fi

cd "$STACK_DIR"
log "Diretorio de trabalho: $(pwd)"

# -----------------------------------------------------------------------------
# 5. Gerar arquivo .env
# Variaveis entre ${} sao substituidas pelo Terraform templatefile antes
# de o script ser enviado para a EC2. O heredoc usa aspas simples (EOF_ENV)
# para evitar expansao adicional pelo bash.
# -----------------------------------------------------------------------------
log "--- [5/8] Gerando .env ---"

cat > .env << 'EOF_ENV'
# =============================================================
# .env gerado automaticamente pelo Terraform (user_data.sh.tpl)
# Nao edite manualmente - sera sobrescrito em novo deploy
# Para ajustes pontuais, edite e reinicie: docker compose up -d
# =============================================================

# --- Projeto e dominios ---
COMPOSE_PROJECT_NAME=glpi-prod
GLPI_DOMAIN=${glpi_domain}
GRAFANA_DOMAIN=${grafana_domain}
ACME_EMAIL=${acme_email}

# --- Tags de imagem (versoes fixadas) ---
GLPI_IMAGE_TAG=${glpi_image_tag}
MARIADB_IMAGE_TAG=${mariadb_image_tag}
REDIS_IMAGE_TAG=${redis_image_tag}
CADDY_IMAGE_TAG=2.8-alpine

# --- Senhas ---
MARIADB_ROOT_PASSWORD=${mariadb_root_password}
MARIADB_PASSWORD=${mariadb_password}
REDIS_PASSWORD=${redis_password}
MARIADB_MONITORING_PASSWORD=${mariadb_monitoring_password}
GRAFANA_ADMIN_PASSWORD=${grafana_admin_password}
GRAFANA_SECRET_KEY=${grafana_secret_key}

# --- GLPI ---
GLPI_SKIP_AUTOINSTALL=false
GLPI_SKIP_AUTOUPDATE=false
GLPI_CRONTAB_ENABLED=false

# --- Backup ---
BACKUP_CRON_SCHEDULE=0 3 * * *
BACKUP_RETENTION_DAYS=14

# --- Monitoramento ---
PROMETHEUS_RETENTION=30d

# --- Timezone ---
TZ=America/Sao_Paulo

# --- Limites de memoria (t3.large: 8 GB RAM) ---
GLPI_MEMORY_LIMIT=1G
MARIADB_MEMORY_LIMIT=2G
REDIS_MEMORY_LIMIT=256M
PROMETHEUS_MEMORY_LIMIT=1G
GRAFANA_MEMORY_LIMIT=512M
LOKI_MEMORY_LIMIT=512M
ALERTMANAGER_MEMORY_LIMIT=128M
NODE_EXPORTER_MEMORY_LIMIT=64M
MYSQLD_EXPORTER_MEMORY_LIMIT=64M
REDIS_EXPORTER_MEMORY_LIMIT=64M
PROMTAIL_MEMORY_LIMIT=128M
EOF_ENV

chmod 600 .env
log ".env gerado em $STACK_DIR/.env (chmod 600)"

# -----------------------------------------------------------------------------
# 6. Validar docker-compose.yml
# -----------------------------------------------------------------------------
log "--- [6/8] Validando docker-compose.yml ---"
docker compose config --quiet && log "docker-compose.yml: sintaxe OK"

# -----------------------------------------------------------------------------
# 7. Subir a stack
# -----------------------------------------------------------------------------
log "--- [7/8] Subindo a stack GLPI (14 containers) ---"

# Sobe apenas o MariaDB primeiro para criar o usuario de monitoramento
docker compose up -d mariadb
log "MariaDB iniciado - aguardando ficar healthy..."

# Aguarda MariaDB ficar healthy (max 3 minutos)
TIMEOUT=180
ELAPSED=0
STATUS="unknown"
while [ $ELAPSED -lt $TIMEOUT ]; do
  STATUS=$(docker compose ps mariadb --format json 2>/dev/null | jq -r '.[0].Health // "unknown"' 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "healthy" ]; then
    log "MariaDB healthy apos $${ELAPSED}s"
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ "$STATUS" != "healthy" ]; then
  log "AVISO: MariaDB nao ficou healthy em $${TIMEOUT}s - continuando mesmo assim"
fi

# Cria usuario de monitoramento (mysqld-exporter depende dele)
log "Configurando usuario 'monitoring' no MariaDB..."
./scripts/setup-monitoring-user.sh >> "$LOG_FILE" 2>&1 \
  || log "AVISO: setup-monitoring-user.sh falhou - verificar manualmente depois"

# Sobe todos os 14 containers
docker compose up -d
log "Stack GLPI iniciada (14 containers)"

# -----------------------------------------------------------------------------
# 8. Sincronizacao automatica de backups para o S3
# Usa IAM Instance Profile - sem credenciais estaticas no host
# -----------------------------------------------------------------------------
log "--- [8/8] Configurando cron de backup para S3 ---"

CRON_CMD="0 4 * * * aws s3 sync $STACK_DIR/backups/ s3://${bucket_name}/backups/ --storage-class STANDARD_IA >> /var/log/glpi-s3-sync.log 2>&1"

# Adiciona ao crontab do root apenas se ainda nao existir
(crontab -l 2>/dev/null; echo "$CRON_CMD") | sort -u | crontab -
log "Cron S3 sync configurado: $CRON_CMD"

# -----------------------------------------------------------------------------
# Finalizacao
# -----------------------------------------------------------------------------
log "=== Bootstrap concluido com sucesso ==="
log ""
log "  GLPI:    https://${glpi_domain}"
log "  Grafana: https://${grafana_domain}"
log "  Stack:   $STACK_DIR"
log ""
log "Credenciais padrao GLPI: glpi / glpi  <- TROCAR IMEDIATAMENTE"
log ""
log "Proximos passos (apos propagacao DNS):"
log "  1. Aguardar DNS propagar (~5-15 min) e TLS ser emitido pelo Caddy"
log "  2. Acessar https://${glpi_domain} e completar configuracao inicial"
log "  3. cd $STACK_DIR && ./scripts/enable-timezones.sh"
log "  4. cd $STACK_DIR && ./scripts/configure-redis-cache.sh"
log "  5. Editar .env: GLPI_SKIP_AUTOINSTALL=true"
log "  6. docker compose up -d glpi-app glpi-cron"

echo "success" > "$STATUS_FILE"
