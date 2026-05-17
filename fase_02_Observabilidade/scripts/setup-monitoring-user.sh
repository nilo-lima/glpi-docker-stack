#!/usr/bin/env bash
# ==============================================================================
#  Configura o usuário 'monitoring' no MariaDB e gera o .my.cnf do exporter.
#  Executar UMA VEZ após a stack estar rodando e .env preenchido.
#
#  Uso: ./scripts/setup-monitoring-user.sh
#  Pré-requisito: container mariadb em estado healthy.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
ENV_FILE="${PROJECT_ROOT}/.env"
MYCNF_FILE="${PROJECT_ROOT}/services/mysqld-exporter/config/.my.cnf"

# ---- Carrega .env ------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Erro: .env não encontrado em ${ENV_FILE}"
    exit 1
fi
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

PROJECT="${COMPOSE_PROJECT_NAME:-glpi-dev}"
MARIADB_CONTAINER="${PROJECT}-mariadb"
MONITORING_PASSWORD="${MARIADB_MONITORING_PASSWORD:-}"

if [[ -z "$MONITORING_PASSWORD" ]]; then
    echo "Erro: MARIADB_MONITORING_PASSWORD não definida no .env."
    exit 1
fi

# ---- Aguarda MariaDB ficar healthy -------------------------------------------
echo "Aguardando ${MARIADB_CONTAINER} ficar healthy..."
TIMEOUT=180
ELAPSED=0
while true; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$MARIADB_CONTAINER" 2>/dev/null || echo "not_found")
    case "$STATUS" in
        healthy)
            echo "MariaDB healthy."
            break
            ;;
        not_found|"")
            echo "Erro: container ${MARIADB_CONTAINER} não encontrado."
            echo "Suba a stack primeiro: docker compose up -d mariadb"
            exit 1
            ;;
        *)
            if [[ $ELAPSED -ge $TIMEOUT ]]; then
                echo "Erro: MariaDB não ficou healthy em ${TIMEOUT}s (status: ${STATUS})."
                echo "Diagnóstico: docker compose logs mariadb"
                exit 1
            fi
            printf "  %s (%ds/%ds) aguardando...\r" "$STATUS" "$ELAPSED" "$TIMEOUT"
            sleep 5
            ELAPSED=$((ELAPSED + 5))
            ;;
    esac
done

# ---- Cria/atualiza usuário no MariaDB ----------------------------------------
echo "Configurando usuário 'monitoring'@'%' em ${MARIADB_CONTAINER}..."

docker exec "$MARIADB_CONTAINER" mariadb \
    --user=root \
    --password="${MARIADB_ROOT_PASSWORD}" \
    --execute="
        CREATE USER IF NOT EXISTS 'monitoring'@'%' IDENTIFIED BY '${MONITORING_PASSWORD}';
        GRANT PROCESS, SELECT, REPLICATION CLIENT, SLAVE MONITOR ON *.* TO 'monitoring'@'%';
        ALTER USER 'monitoring'@'%' IDENTIFIED BY '${MONITORING_PASSWORD}';
        FLUSH PRIVILEGES;
        SELECT User, Host FROM mysql.user WHERE User='monitoring';
    "

echo "Usuário 'monitoring' configurado."

# ---- Gera .my.cnf para o mysqld-exporter ------------------------------------
echo "Gerando ${MYCNF_FILE} ..."

mkdir -p "$(dirname "$MYCNF_FILE")"
cat > "$MYCNF_FILE" <<EOF
# Gerado por setup-monitoring-user.sh — NÃO editar manualmente.
# Para regenerar: ./scripts/setup-monitoring-user.sh
[client]
user     = monitoring
host     = mariadb
port     = 3306
password = ${MONITORING_PASSWORD}
EOF
# 644: o container mysqld-exporter roda como nobody (UID 65534) e precisa ler o arquivo.
# A senha do usuário 'monitoring' tem privilégios mínimos (PROCESS, SELECT, REPLICATION CLIENT).
chmod 644 "$MYCNF_FILE"

echo ".my.cnf gerado em ${MYCNF_FILE} (chmod 644)."
echo ""
echo "Próximo passo: reiniciar o mysqld-exporter para aplicar as credenciais:"
echo "  docker compose restart mysqld-exporter"
