#!/bin/bash
# =============================================================================
#  GLPI 11 — Healthcheck consolidado
# =============================================================================
#  Verifica saúde de todos os serviços da stack.
# =============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "============================================================"
echo " GLPI 11 — Healthcheck"
echo "============================================================"
echo ""

# --- Status dos containers ---
echo "Status dos containers:"
docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.State}}"
echo ""

# --- Healthcheck individual ---
SERVICES=(mariadb redis glpi-app glpi-cron caddy backup)
FAIL=0

for svc in "${SERVICES[@]}"; do
    health=$(docker compose ps --format json "$svc" 2>/dev/null | \
        grep -oP '"Health":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
    state=$(docker compose ps --format json "$svc" 2>/dev/null | \
        grep -oP '"State":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")

    if [[ "$state" == "running" && ( "$health" == "healthy" || "$health" == "" ) ]]; then
        echo -e "  ${GREEN}✓${NC} ${svc}: ${state} ${health:+($health)}"
    elif [[ "$state" == "running" && "$health" == "starting" ]]; then
        echo -e "  ${YELLOW}…${NC} ${svc}: iniciando..."
    else
        echo -e "  ${RED}✗${NC} ${svc}: ${state} ${health:+($health)}"
        FAIL=$((FAIL+1))
    fi
done

echo ""

# --- Conectividade interna ---
echo "Conectividade interna:"
if docker compose exec -T glpi-app sh -c 'curl -fs --max-time 3 http://localhost/health -o /dev/null'; then
    echo -e "  ${GREEN}✓${NC} GLPI app responde em http://localhost (interno)"
else
    echo -e "  ${RED}✗${NC} GLPI app não responde"
    FAIL=$((FAIL+1))
fi

if docker compose exec -T mariadb healthcheck.sh --connect >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} MariaDB aceita conexões"
else
    echo -e "  ${RED}✗${NC} MariaDB não responde"
    FAIL=$((FAIL+1))
fi

# --- Volumes ---
echo ""
echo "Uso de volumes:"
docker system df -v 2>/dev/null | grep -E "(VOLUME|${COMPOSE_PROJECT_NAME:-glpi-prod})" | head -10

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}Todos os serviços OK${NC}"
    exit 0
else
    echo -e "${RED}${FAIL} serviço(s) com problema${NC}"
    exit 1
fi
