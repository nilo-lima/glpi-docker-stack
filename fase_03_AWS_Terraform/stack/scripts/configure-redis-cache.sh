#!/bin/bash
# =============================================================================
#  GLPI 11 — Configurar Redis como cache
# =============================================================================
#  Executar uma única vez, após o GLPI estar instalado.
#  Configura o cache de dados do GLPI (não-sessões) para usar Redis.
#  Sessões PHP já estão configuradas via php.ini para usar Redis automaticamente.
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

# Carrega .env para obter REDIS_PASSWORD
# shellcheck disable=SC1091
set -a; . ./.env; set +a

# Caracteres especiais na senha (@ # : / etc.) precisam de URL-encoding no DSN
ENCODED_PASSWORD=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${REDIS_PASSWORD}")
DSN="redis://:${ENCODED_PASSWORD}@redis:6379/1"

echo "Configurando cache do GLPI para usar Redis..."
docker compose exec -T glpi-app \
    /var/www/glpi/bin/console cache:configure \
        --dsn="${DSN}" \
        --no-interaction

echo "OK — cache GLPI configurado para Redis (DB 1)."
echo "Sessões PHP (DB 0) e cache (DB 1) estão segregados no Redis."
