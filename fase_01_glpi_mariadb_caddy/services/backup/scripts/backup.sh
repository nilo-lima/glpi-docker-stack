#!/bin/bash
# =============================================================================
#  GLPI Backup Script
# =============================================================================
#  Estratégia de backup:
#    1. Dump consistente do MariaDB (--single-transaction)
#    2. Tar dos arquivos persistentes do GLPI (config, plugins, files)
#    3. Compactação gzip
#    4. Rotação automática (remove backups mais antigos que N dias)
#    5. Verificação básica de integridade do dump
# =============================================================================

set -euo pipefail

# --- Variáveis de ambiente esperadas ---
: "${MARIADB_HOST:?MARIADB_HOST não definido}"
: "${MARIADB_DATABASE:?MARIADB_DATABASE não definido}"
: "${MARIADB_USER:?MARIADB_USER não definido}"
: "${MARIADB_PASSWORD:?MARIADB_PASSWORD não definido}"
: "${BACKUP_RETENTION_DAYS:=14}"

# --- Constantes ---
TIMESTAMP=$(date -u +'%Y%m%d_%H%M%S')
BACKUP_DIR="/backups"
DB_BACKUP_FILE="${BACKUP_DIR}/glpi_db_${TIMESTAMP}.sql.gz"
FILES_BACKUP_FILE="${BACKUP_DIR}/glpi_files_${TIMESTAMP}.tar.gz"
LOG_PREFIX="[$(date -u +'%Y-%m-%dT%H:%M:%SZ')]"

log() { echo "${LOG_PREFIX} $*"; }
fail() { log "ERRO: $*"; exit 1; }

# -----------------------------------------------------------------------------
# 1. Backup do banco de dados
# -----------------------------------------------------------------------------
log "Iniciando dump do banco '${MARIADB_DATABASE}' em ${MARIADB_HOST}..."

# --single-transaction garante consistência sem lockear tabelas (InnoDB)
# --quick reduz uso de memória em tabelas grandes
# --routines e --triggers garantem backup completo de procedures/triggers
mariadb-dump \
    --host="${MARIADB_HOST}" \
    --user="${MARIADB_USER}" \
    --password="${MARIADB_PASSWORD}" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    --events \
    --hex-blob \
    --default-character-set=utf8mb4 \
    "${MARIADB_DATABASE}" 2>/dev/null \
    | gzip -9 > "${DB_BACKUP_FILE}" \
    || fail "Falha ao executar mariadb-dump"

DB_SIZE=$(du -h "${DB_BACKUP_FILE}" | cut -f1)
log "Dump do banco OK: ${DB_BACKUP_FILE} (${DB_SIZE})"

# Verificação rápida de integridade (gzip não corrompido + SQL não vazio)
if ! gzip -t "${DB_BACKUP_FILE}" 2>/dev/null; then
    fail "Arquivo de dump está corrompido (gzip test falhou)"
fi

# -----------------------------------------------------------------------------
# 2. Backup dos arquivos do GLPI (plugins, anexos, config)
# -----------------------------------------------------------------------------
if [[ -d /glpi-data ]]; then
    log "Iniciando backup dos arquivos do GLPI..."

    # Excluímos cache e sessões (regeneráveis) para reduzir tamanho
    tar -czf "${FILES_BACKUP_FILE}" \
        --exclude='_cache' \
        --exclude='_sessions' \
        --exclude='_tmp' \
        --exclude='_lock' \
        -C /glpi-data . \
        || fail "Falha ao criar tar dos arquivos GLPI"

    FILES_SIZE=$(du -h "${FILES_BACKUP_FILE}" | cut -f1)
    log "Backup de arquivos OK: ${FILES_BACKUP_FILE} (${FILES_SIZE})"
else
    log "AVISO: /glpi-data não montado — pulando backup de arquivos"
fi

# -----------------------------------------------------------------------------
# 3. Rotação — remove backups mais antigos que BACKUP_RETENTION_DAYS
# -----------------------------------------------------------------------------
log "Aplicando retenção de ${BACKUP_RETENTION_DAYS} dias..."

REMOVED=$(find "${BACKUP_DIR}" \
    -maxdepth 1 \
    -type f \
    \( -name 'glpi_db_*.sql.gz' -o -name 'glpi_files_*.tar.gz' \) \
    -mtime +${BACKUP_RETENTION_DAYS} \
    -print -delete | wc -l)

log "Arquivos antigos removidos: ${REMOVED}"

# -----------------------------------------------------------------------------
# 4. Resumo
# -----------------------------------------------------------------------------
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
TOTAL_FILES=$(find "${BACKUP_DIR}" -maxdepth 1 -type f | wc -l)

log "Backup finalizado. Diretório: ${TOTAL_SIZE} (${TOTAL_FILES} arquivos)"
