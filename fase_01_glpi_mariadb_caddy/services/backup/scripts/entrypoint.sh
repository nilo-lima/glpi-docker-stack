#!/bin/bash
# =============================================================================
#  Backup Container — Entrypoint
# =============================================================================
#  Roda um loop que respeita o cron schedule definido em $BACKUP_CRON_SCHEDULE.
#  Como o container roda como não-root, evitamos crond do BusyBox e usamos
#  uma implementação simples baseada em sleep + parser de cron expression.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"

: "${BACKUP_CRON_SCHEDULE:=0 3 * * *}"

log() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

log "Backup runner iniciado"
log "Cron schedule: ${BACKUP_CRON_SCHEDULE}"
log "Retenção: ${BACKUP_RETENTION_DAYS} dias"
log "Destino: /backups"

# -----------------------------------------------------------------------------
# Parser simplificado de cron (suporta o caso comum: H M * * *)
# Para expressões complexas, considere migrar para supercronic.
# -----------------------------------------------------------------------------
cron_minute=$(echo "${BACKUP_CRON_SCHEDULE}" | awk '{print $1}')
cron_hour=$(echo "${BACKUP_CRON_SCHEDULE}" | awk '{print $2}')

# Validação básica
if ! [[ "$cron_minute" =~ ^[0-9]+$ ]] || ! [[ "$cron_hour" =~ ^[0-9]+$ ]]; then
    log "ERRO: BACKUP_CRON_SCHEDULE deve ser do formato 'M H * * *' (ex: '0 3 * * *')"
    exit 1
fi

log "Próximo backup: ${cron_hour}:${cron_minute} todo dia"

# Loop principal
while true; do
    now_minute=$(date +%-M)
    now_hour=$(date +%-H)

    if [[ "$now_minute" == "$cron_minute" && "$now_hour" == "$cron_hour" ]]; then
        log "Disparando backup agendado..."
        if "${BACKUP_SCRIPT}"; then
            log "Backup concluído com sucesso"
        else
            log "ERRO: Backup falhou (exit $?)"
        fi
        # Espera 61s para não disparar duas vezes no mesmo minuto
        sleep 61
    fi

    sleep 30
done
