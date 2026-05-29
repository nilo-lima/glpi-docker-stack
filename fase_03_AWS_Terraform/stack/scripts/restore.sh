#!/bin/bash
# =============================================================================
#  GLPI 11 — Restore guiado
# =============================================================================
#  Restaura banco de dados e (opcionalmente) arquivos do GLPI.
#  CUIDADO: sobrescreve dados atuais. Confirmação obrigatória.
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

# shellcheck disable=SC1091
set -a; . ./.env; set +a

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'

# -----------------------------------------------------------------------------
# 1. Selecionar backup de banco
# -----------------------------------------------------------------------------
echo "Backups de banco disponíveis:"
mapfile -t db_backups < <(ls -1t backups/glpi_db_*.sql.gz 2>/dev/null || true)

if [[ ${#db_backups[@]} -eq 0 ]]; then
    echo -e "${RED}ERRO: nenhum backup encontrado em ./backups/${NC}"
    exit 1
fi

for i in "${!db_backups[@]}"; do
    printf "  [%d] %s\n" "$i" "$(basename "${db_backups[$i]}")"
done

echo ""
read -rp "Selecione o número do backup a restaurar: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -ge ${#db_backups[@]} ]]; then
    echo -e "${RED}ERRO: seleção inválida${NC}"
    exit 1
fi

DB_BACKUP="${db_backups[$choice]}"
TIMESTAMP=$(basename "${DB_BACKUP}" | grep -oP '\d{8}_\d{6}')
FILES_BACKUP="backups/glpi_files_${TIMESTAMP}.tar.gz"

echo ""
echo "Backup de banco  : ${DB_BACKUP}"

RESTORE_FILES=false
if [[ -f "${FILES_BACKUP}" ]]; then
    echo "Backup de arquivos: ${FILES_BACKUP} (encontrado — será restaurado junto)"
    RESTORE_FILES=true
else
    echo -e "${YELLOW}Backup de arquivos: não encontrado para este timestamp (só o banco será restaurado)${NC}"
fi

# -----------------------------------------------------------------------------
# 2. Verificar integridade antes de começar
# -----------------------------------------------------------------------------
echo ""
echo "Verificando integridade do backup..."
if ! gzip -t "${DB_BACKUP}" 2>/dev/null; then
    echo -e "${RED}ERRO: arquivo de banco corrompido (gzip test falhou)${NC}"
    exit 1
fi
if [[ "${RESTORE_FILES}" == "true" ]] && ! gzip -t "${FILES_BACKUP}" 2>/dev/null; then
    echo -e "${RED}ERRO: arquivo de files corrompido (gzip test falhou)${NC}"
    exit 1
fi
echo "Integridade OK."

# -----------------------------------------------------------------------------
# 3. Confirmação
# -----------------------------------------------------------------------------
echo ""
echo -e "${RED}ATENÇÃO: o banco '${MARIADB_DATABASE}' e os arquivos do GLPI serão SOBRESCRITOS.${NC}"
echo -e "${RED}Esta operação não pode ser desfeita.${NC}"
read -rp "Digite 'RESTAURAR' para confirmar: " confirm
if [[ "$confirm" != "RESTAURAR" ]]; then
    echo "Abortado."
    exit 0
fi

# -----------------------------------------------------------------------------
# 4. Parar glpi-app e glpi-cron antes do restore
# -----------------------------------------------------------------------------
echo ""
echo "Parando glpi-app e glpi-cron..."
docker compose stop glpi-app glpi-cron

# -----------------------------------------------------------------------------
# 5. Restore do banco
# -----------------------------------------------------------------------------
echo "Restaurando banco de dados..."
gunzip -c "${DB_BACKUP}" | docker compose exec -T mariadb \
    mariadb \
        --user="${MARIADB_USER}" \
        --password="${MARIADB_PASSWORD}" \
        "${MARIADB_DATABASE}"
echo -e "${GREEN}Banco restaurado.${NC}"

# -----------------------------------------------------------------------------
# 6. Restore dos arquivos (se disponível)
# -----------------------------------------------------------------------------
if [[ "${RESTORE_FILES}" == "true" ]]; then
    echo "Restaurando arquivos do GLPI..."

    VOLUME_NAME="${COMPOSE_PROJECT_NAME:-glpi-dev}_glpi_data"
    docker run --rm \
        -v "${VOLUME_NAME}:/var/glpi" \
        -v "$(pwd)/backups:/backups:ro" \
        alpine:3.20 \
        tar -xzf "/backups/$(basename "${FILES_BACKUP}")" -C /var/glpi

    echo -e "${GREEN}Arquivos restaurados.${NC}"
fi

# -----------------------------------------------------------------------------
# 7. Reiniciar GLPI e limpar cache
# -----------------------------------------------------------------------------
echo "Reiniciando glpi-app e glpi-cron..."
docker compose start glpi-app glpi-cron

echo "Aguardando glpi-app ficar saudável..."
until docker inspect "${COMPOSE_PROJECT_NAME:-glpi-dev}-app" \
    --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "^healthy$"; do
    sleep 5
done

echo "Limpando cache do GLPI..."
docker compose exec -T glpi-app /var/www/glpi/bin/console cache:clear --no-interaction

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Restore concluído com sucesso!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "Próximos passos recomendados:"
echo "  1. Verifique o acesso: https://${GLPI_DOMAIN}"
echo "  2. Confirme que os dados foram restaurados corretamente"
echo "  3. Se restaurou em ambiente diferente, atualize a url_base:"
echo "     docker compose exec mariadb mariadb -u${MARIADB_USER} -p\"\${MARIADB_PASSWORD}\" ${MARIADB_DATABASE} \\"
echo "       -e \"UPDATE glpi_configs SET value='https://${GLPI_DOMAIN}' WHERE name='url_base';\""
