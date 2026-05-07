# 📘 RUNBOOK — GLPI 11 Production

> Procedimentos operacionais do dia-a-dia, incluindo cenários de emergência.

---

## 🔥 Procedimentos de Emergência

### 1. Aplicação fora do ar

```bash
# Diagnóstico rápido
./scripts/healthcheck-all.sh

# Reiniciar app web
docker compose restart glpi-app caddy

# Se persistir, recriar
docker compose up -d --force-recreate glpi-app
```

### 2. Banco corrompido / inacessível

```bash
# 1. Verificar logs
docker compose logs mariadb | tail -100

# 2. Tentar reinício suave
docker compose restart mariadb

# 3. Se não recuperar: restore do último backup
#    O script para glpi-app/glpi-cron, restaura banco + arquivos,
#    reinicia os containers e limpa o cache automaticamente.
./scripts/restore.sh
```

### 3. Disco cheio

```bash
# Verificar uso
df -h
docker system df

# Limpar
docker image prune -f
docker compose exec glpi-app /var/www/glpi/bin/console cache:clear

# Backups antigos (se necessário, reduzir retenção)
ls -laSh backups/

# Logs do Docker (rotação já configurada, mas verificar)
journalctl --vacuum-time=7d   # se host usa systemd
```

### 4. Certificado TLS expirou / não renova

```bash
# Caddy renova automaticamente. Se algo falhou:
docker compose logs caddy | grep -i "certificate\|acme\|tls"

# Forçar reload da config
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile

# Em último caso, deletar certs e re-emitir
docker compose down
docker volume rm glpi-prod_caddy_data
docker compose up -d caddy
```

---

## 🔄 Procedimentos de Rotina

### Atualização do GLPI (minor/patch)

```bash
# 1. Backup ANTES de atualizar
./scripts/backup-now.sh

# 2. Editar .env: aumentar GLPI_IMAGE_TAG (ex: 11.0.7 -> 11.0.8)

# 3. Pull e up
docker compose pull glpi-app glpi-cron
docker compose up -d glpi-app glpi-cron

# 4. GLPI executa auto-update (verifique logs)
docker compose logs -f glpi-app

# 5. Validar
./scripts/healthcheck-all.sh
```

### Atualização do MariaDB

⚠️ **Major version bumps (ex: 11.4 → 11.5) requerem leitura de release notes.**

```bash
# 1. Backup OBRIGATÓRIO
./scripts/backup-now.sh

# 2. Editar .env: MARIADB_IMAGE_TAG

# 3. Update (MARIADB_AUTO_UPGRADE=1 já configurado)
docker compose pull mariadb
docker compose up -d mariadb

# 4. Validar
docker compose exec mariadb mariadb -u root -p -e "SHOW VARIABLES LIKE 'version';"
```

### Rotação de senhas

```bash
# 1. Gerar nova senha (sem caracteres problemáticos para URLs: @, #, %)
NEW_PASS=$(openssl rand -base64 24 | tr -d '@#%')

# 2. Trocar no banco
docker compose exec mariadb mariadb -u root -p \
    -e "ALTER USER 'glpi'@'%' IDENTIFIED BY '$NEW_PASS'; FLUSH PRIVILEGES;"

# 3. Atualizar .env — SEMPRE entre aspas duplas
#    MARIADB_PASSWORD="<nova_senha>"
#    Se trocar REDIS_PASSWORD, idem: REDIS_PASSWORD="<nova_senha>"

# 4. Recriar containers que usam a senha
docker compose up -d --force-recreate glpi-app glpi-cron backup

# 5. Se trocou REDIS_PASSWORD: atualizar o DSN no GLPI (URL-encoding automático)
./scripts/configure-redis-cache.sh
```

---

## 📊 Monitoramento Manual

### Métricas chave

```bash
# Conexões ativas no MariaDB
docker compose exec mariadb mariadb -u root -p \
    -e "SHOW STATUS LIKE 'Threads_connected';"

# Tamanho do banco
docker compose exec mariadb mariadb -u root -p \
    -e "SELECT table_schema 'DB',
        ROUND(SUM(data_length+index_length)/1024/1024,2) 'Size_MB'
        FROM information_schema.TABLES
        WHERE table_schema='glpi';"

# Memória do Redis
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" INFO memory | grep used_memory_human

# Sessões ativas no Redis
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" -n 0 DBSIZE
```

### Logs estruturados (preparados para Loki/Fase 2)

```bash
# Filtrar por nível
docker compose logs glpi-app 2>&1 | jq 'select(.level=="error")' 2>/dev/null

# Acessos do Caddy
docker compose logs caddy 2>&1 | jq 'select(.msg=="handled request") | {ts, request: .request.uri, status}' 2>/dev/null
```

---

## 🧪 Testes de Disaster Recovery

**Recomendado: trimestral.**

```bash
# 1. Backup antes do teste (para não perder dados reais)
./scripts/backup-now.sh

# 2. Simular perda total
docker compose down -v
docker volume prune -f

# 3. Subir serviços de dados (GLPI precisa de ambos ao iniciar)
docker compose up -d mariadb redis

# 4. Aguardar MariaDB healthy (restore.sh precisa do banco disponível)
until [ "$(docker inspect --format='{{.State.Health.Status}}' \
    "$(docker compose ps -q mariadb)")" = "healthy" ]; do
  echo "Aguardando MariaDB..."; sleep 5
done

# 5. Restaurar — o script para/inicia glpi-app e glpi-cron automaticamente
./scripts/restore.sh

# 6. Iniciar serviços restantes (caddy, backup)
docker compose up -d

# 7. Validar dados
./scripts/healthcheck-all.sh
# Login no GLPI e checar tickets/usuários
```
