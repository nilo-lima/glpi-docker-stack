#!/bin/bash
# =============================================================================
#  GLPI 11 — Habilitar suporte a timezones
# =============================================================================
#  Executar uma única vez, após a primeira instalação bem-sucedida.
#  Necessário para que o GLPI use timezones corretamente em datas.
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "Executando bin/console database:enable_timezones no container glpi-app..."
docker compose exec -T glpi-app /var/www/glpi/bin/console database:enable_timezones --no-interaction

echo "OK — timezones habilitados."
