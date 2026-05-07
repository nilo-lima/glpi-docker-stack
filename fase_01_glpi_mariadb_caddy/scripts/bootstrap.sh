#!/bin/bash
# =============================================================================
#  GLPI 11 — Bootstrap inicial
# =============================================================================
#  Prepara o host Debian 12 e provisiona a stack pela primeira vez.
#  Idempotente: pode ser executado múltiplas vezes sem efeitos colaterais.
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

# --- Cores ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }

echo "============================================================"
echo " GLPI 11 — Bootstrap"
echo "============================================================"

# -----------------------------------------------------------------------------
# 1. Validar SO (Debian 12 esperado)
# -----------------------------------------------------------------------------
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "debian" ]]; then
        warn "Distro detectada: ${ID}. Recomendado: Debian 12 (Bookworm)."
    elif [[ "${VERSION_ID:-}" != "12" ]]; then
        warn "Versão Debian: ${VERSION_ID}. Recomendado: 12 (Bookworm)."
    else
        ok "Debian 12 (Bookworm) detectado"
    fi
fi

# -----------------------------------------------------------------------------
# 2. Verificar Docker e Compose
# -----------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    fail "Docker não encontrado. Instale com: https://docs.docker.com/engine/install/debian/"
fi
ok "Docker: $(docker --version)"

if ! docker compose version >/dev/null 2>&1; then
    fail "Docker Compose v2 não encontrado. Instale o plugin docker-compose-plugin."
fi
ok "Compose: $(docker compose version --short)"

# Usuário precisa estar no grupo docker (ou ser root)
if [[ $EUID -ne 0 ]] && ! groups | grep -qw docker; then
    fail "Usuário atual não está no grupo 'docker'. Execute: sudo usermod -aG docker \$USER && newgrp docker"
fi

# -----------------------------------------------------------------------------
# 3. Criar .env se não existir
# -----------------------------------------------------------------------------
if [[ ! -f .env ]]; then
    if [[ -f .env.example ]]; then
        cp .env.example .env
        chmod 600 .env
        warn ".env criado a partir de .env.example"
        warn "EDITE .env e configure: GLPI_DOMAIN, ACME_EMAIL, senhas, etc."
        warn "Sugestão para gerar senhas: openssl rand -base64 32"
        echo ""
        read -rp "Pressione ENTER após editar .env (ou Ctrl+C para abortar)..."
    else
        fail ".env.example não encontrado"
    fi
else
    ok ".env já existe"
    chmod 600 .env
fi

# -----------------------------------------------------------------------------
# 4. Validar variáveis críticas no .env
# -----------------------------------------------------------------------------
# shellcheck disable=SC1091
set -a; . ./.env; set +a

CRITICAL_VARS=(GLPI_DOMAIN ACME_EMAIL MARIADB_ROOT_PASSWORD MARIADB_PASSWORD REDIS_PASSWORD)
for var in "${CRITICAL_VARS[@]}"; do
    val="${!var:-}"
    if [[ -z "$val" || "$val" == TROCAR_* ]]; then
        fail ".env: variável '${var}' não foi configurada (valor padrão TROCAR_*)"
    fi
done
ok "Variáveis críticas do .env OK"

# -----------------------------------------------------------------------------
# 5. Diretório de backups
# -----------------------------------------------------------------------------
mkdir -p backups
chmod 750 backups
ok "Diretório de backups pronto"

# -----------------------------------------------------------------------------
# 6. Validar docker-compose.yml
# -----------------------------------------------------------------------------
if ! docker compose config --quiet 2>&1; then
    fail "docker-compose.yml inválido (rode 'docker compose config' para detalhes)"
fi
ok "docker-compose.yml validado"

# -----------------------------------------------------------------------------
# 7. Build da imagem de backup
# -----------------------------------------------------------------------------
echo ""
echo "Buildando imagem do container de backup..."
docker compose build backup
ok "Imagem de backup construída"

# -----------------------------------------------------------------------------
# 8. Pull das imagens oficiais
# -----------------------------------------------------------------------------
echo ""
echo "Baixando imagens oficiais (versões pinadas)..."
docker compose pull mariadb redis glpi-app glpi-cron caddy
ok "Imagens baixadas"

# -----------------------------------------------------------------------------
# 9. Subir a stack
# -----------------------------------------------------------------------------
echo ""
echo "Subindo a stack..."
docker compose up -d

echo ""
echo "============================================================"
ok "Bootstrap concluído!"
echo "============================================================"
echo ""
echo "Próximos passos:"
echo "  1. Acompanhe os logs:           docker compose logs -f"
echo "  2. Verifique status:            docker compose ps"
echo "  3. Acesse o GLPI:               https://${GLPI_DOMAIN}"
echo "  4. Login inicial:               glpi / glpi  (ALTERAR IMEDIATAMENTE)"
echo "  5. Habilitar timezones:         scripts/enable-timezones.sh"
echo "  6. Configurar Redis no GLPI:    scripts/configure-redis-cache.sh"
echo ""
echo "IMPORTANTE: após primeira instalação bem-sucedida, edite .env e setar:"
echo "    GLPI_SKIP_AUTOINSTALL=true"
echo "  e rode: docker compose up -d glpi-app"
echo ""
