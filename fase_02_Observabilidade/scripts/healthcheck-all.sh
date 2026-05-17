#!/usr/bin/env bash
# ==============================================================================
#  GLPI 11 + Observabilidade — Healthcheck consolidado (14 serviços)
# ==============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

# shellcheck disable=SC1091
set -a; source .env 2>/dev/null || true; set +a

PROJECT="${COMPOSE_PROJECT_NAME:-glpi-dev}"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
FAIL=0

echo ""
echo "======================================================================"
echo "  GLPI 11 + Observabilidade — Healthcheck"
echo "  Projeto: ${PROJECT}"
echo "======================================================================"

check() {
    local svc="$1"
    local container="${PROJECT}-${2:-$1}"
    local health state

    health=$(docker compose ps --format json "$svc" 2>/dev/null \
        | grep -oP '"Health":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
    state=$(docker compose ps --format json "$svc" 2>/dev/null \
        | grep -oP '"State":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")

    if [[ "$state" == "running" && ( "$health" == "healthy" || "$health" == "" ) ]]; then
        printf "  ${GREEN}[OK]${NC}  %-20s  running %s\n" "$svc" "${health:+($health)}"
    elif [[ "$state" == "running" && "$health" == "starting" ]]; then
        printf "  ${YELLOW}[~~]${NC}  %-20s  iniciando...\n" "$svc"
    else
        printf "  ${RED}[!!]${NC}  %-20s  %s %s\n" "$svc" "$state" "${health:+($health)}"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "--- Fase 1: GLPI Stack ---"
check mariadb
check redis
check glpi-app  app
check glpi-cron cron
check caddy
check backup

echo ""
echo "--- Fase 2: Observabilidade ---"
check prometheus
check node-exporter node-exporter
check mysqld-exporter mysqld-exporter
check redis-exporter redis-exporter
check grafana
check loki
check promtail
check alertmanager

echo ""
echo "--- Status geral ---"
docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.State}}" 2>/dev/null
echo ""

# --- Conectividade interna ---
echo "--- Conectividade ---"
if docker compose exec -T glpi-app sh -c \
    'curl -fs --max-time 3 http://localhost/health -o /dev/null' 2>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC}  GLPI app responde internamente"
else
    echo -e "  ${RED}[!!]${NC}  GLPI app não responde"
    FAIL=$((FAIL + 1))
fi

if docker compose exec -T mariadb healthcheck.sh --connect >/dev/null 2>&1; then
    echo -e "  ${GREEN}[OK]${NC}  MariaDB aceita conexões"
else
    echo -e "  ${RED}[!!]${NC}  MariaDB não responde"
    FAIL=$((FAIL + 1))
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}Todos os serviços OK${NC}"
    exit 0
else
    echo -e "${RED}${FAIL} serviço(s) com problema — verifique: docker compose logs <serviço>${NC}"
    exit 1
fi
