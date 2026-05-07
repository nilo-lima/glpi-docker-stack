#!/bin/bash
# =============================================================================
#  GLPI 11 — Backup manual (on-demand)
# =============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "Disparando backup manual..."
docker compose exec -T backup /opt/backup/backup.sh

echo ""
echo "Backups disponíveis:"
ls -lh backups/ | grep -v '^total' | tail -10
