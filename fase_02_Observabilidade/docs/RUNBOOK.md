# 📘 RUNBOOK — GLPI 11 + Observabilidade (Fase 2)

> Procedimentos operacionais do dia-a-dia, incluindo cenários de emergência.

---

## 🔥 Procedimentos de Emergência

### 1. Aplicação GLPI fora do ar

```bash
# Diagnóstico rápido
./scripts/healthcheck-all.sh
docker compose ps

# Reiniciar app
docker compose restart glpi-app caddy

# Se persistir, recriar sem destruir dados
docker compose up -d --force-recreate --no-deps glpi-app
docker compose logs -f glpi-app
```

### 2. Banco inacessível

```bash
# Verificar logs e status
docker compose logs mariadb | tail -50
docker inspect --format='{{json .State.Health}}' glpi-dev-mariadb | python3 -m json.tool

# Reinício suave
docker compose restart mariadb

# Restore do último backup (para o GLPI, restaura banco + arquivos, reinicia)
./scripts/restore.sh
```

### 3. Grafana inacessível

```bash
# Verificar se o container está healthy
docker compose ps grafana

# Verificar se o Caddy está roteando corretamente
docker compose logs caddy | grep grafana

# Reiniciar
docker compose restart grafana

# Se o volume de dados estiver corrompido (perde apenas configurações manuais;
# datasources e dashboards provisionados são recriados automaticamente)
docker compose stop grafana
docker volume rm glpi-dev_grafana_data
docker compose up -d grafana
```

### 4. Prometheus sem dados / targets down

```bash
# Listar targets e status
docker exec glpi-dev-prometheus wget -qO- \
  http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"job"'

# Ver alertas ativos
docker exec glpi-dev-prometheus wget -qO- \
  http://localhost:9090/api/v1/alerts | python3 -m json.tool

# Reiniciar exporter problemático
docker compose restart mysqld-exporter   # ou redis-exporter, node-exporter
```

### 5. Loki sem logs / Promtail com erro

```bash
# Verificar labels disponíveis (deve ter container, job, service, image)
docker exec glpi-dev-loki wget -qO- \
  http://localhost:3100/loki/api/v1/labels | python3 -m json.tool

# Verificar erros no Promtail
docker compose logs promtail | grep -v "finished transferring" | tail -20

# Reiniciar com positions limpos (re-coleta logs recentes)
docker compose stop promtail
docker volume rm glpi-dev_promtail_positions 2>/dev/null || true
docker compose up -d promtail
```

### 6. Disco cheio

```bash
# Diagnosticar
df -h
docker system df -v | grep glpi-dev

# Limpar imagens não usadas
docker image prune -f

# Limpar cache GLPI
docker compose exec glpi-app /var/www/glpi/bin/console cache:clear

# Backups antigos
ls -laSh backups/
# Reduzir BACKUP_RETENTION_DAYS no .env se necessário

# Retenção de métricas (ajustar PROMETHEUS_RETENTION no .env)
# Padrão: 30d — reduzir para 15d e recriar o container
docker compose up -d --force-recreate --no-deps prometheus
```

### 7. Certificado TLS expirou / não renova

```bash
# Caddy renova automaticamente. Verificar logs:
docker compose logs caddy | grep -i "certificate\|acme\|tls\|error"

# Forçar reload da config do Caddy
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile

# Último recurso: deletar certs e re-emitir
docker compose stop caddy
docker volume rm glpi-dev_caddy_data glpi-dev_caddy_config
docker compose up -d caddy
```

---

## 🔄 Procedimentos de Rotina

### Atualização de versão de imagem

```bash
# Sempre fazer backup antes
./scripts/backup-now.sh

# Editar .env (ex: GRAFANA_IMAGE_TAG=11.4.0 → 11.5.0)
# Depois:
docker compose pull grafana
docker compose up -d --no-deps grafana
./scripts/healthcheck-all.sh
```

### Adicionar dashboard Grafana

```bash
# Baixar JSON da Grafana.com (ex: ID 12345)
curl -fsSL "https://grafana.com/api/dashboards/12345/revisions/latest/download" \
  -o services/grafana/provisioning/dashboards/meu-dashboard.json

# Substituir variável de datasource se necessário
sed -i 's/\${DS_PROMETHEUS}/prometheus/g' services/grafana/provisioning/dashboards/meu-dashboard.json
sed -i 's/\${DS_LOKI}/loki/g' services/grafana/provisioning/dashboards/meu-dashboard.json

# Recarregar (ou aguardar 30s — o provider faz polling automático)
docker compose restart grafana
```

### Configurar Alertmanager com receiver real

Edite `services/alertmanager/config/alertmanager.yml` e substitua o receiver `blackhole`:

```yaml
# Exemplo para e-mail
receivers:
  - name: 'email-alerts'
    email_configs:
      - to: 'admin@empresa.com'
        from: 'alertmanager@empresa.com'
        smarthost: 'smtp.empresa.com:587'
        auth_username: 'alertmanager@empresa.com'
        auth_password: 'SENHA_SMTP'

route:
  receiver: 'email-alerts'
```

```bash
docker compose restart alertmanager
```

### Backup manual imediato

```bash
./scripts/backup-now.sh
ls -lh backups/ | tail -5
```

### Restore interativo

```bash
./scripts/restore.sh
# Lista backups disponíveis com timestamps
# Para glpi-app e glpi-cron durante o restore
# Restaura banco + arquivos
# Reinicia e limpa cache automaticamente
```

### Sincronização off-site de backups

```bash
# No crontab do HOST — executar após o backup das 03:00
# 0 4 * * * rclone sync /opt/glpi/fase_02/backups/ s3:meu-bucket/glpi-backups/ --transfers=4

# Verificar
rclone ls s3:meu-bucket/glpi-backups/ | tail -10
```

---

## 🔑 Tarefas Pós-Instalação (uma vez)

### Após o GLPI concluir a instalação automática

```bash
# 1. Carregar timezone data no MariaDB
./scripts/enable-timezones.sh

# 2. Configurar Redis como backend de cache e sessões
./scripts/configure-redis-cache.sh

# 3. Travar autoinstalação para próximos boots
# Editar .env: GLPI_SKIP_AUTOINSTALL=true
docker compose up -d glpi-app glpi-cron
```

### Hardening do GLPI

No GLPI web: **Administração → Usuários**
- Troque a senha do usuário `glpi` (admin padrão)
- Desative ou altere senhas de `tech`, `normal`, `post-only`

### Configurar notificações GLPI por e-mail

No GLPI web: **Configuração → Notificações → Configurar seguimentos por email**

---

## 📊 Verificações de Saúde

```bash
# Todos os containers
./scripts/healthcheck-all.sh

# Status resumido
docker compose ps

# Targets Prometheus (todos devem ser "up")
docker exec glpi-dev-prometheus wget -qO- \
  "http://localhost:9090/api/v1/targets" | \
  python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print(f\"[{t['health']:6s}] {t['labels'].get('job','?')}\")
"

# Labels Loki (deve ter: container, image, job, service)
docker exec glpi-dev-loki wget -qO- \
  "http://localhost:3100/loki/api/v1/labels" | python3 -m json.tool

# Alertas ativos
docker exec glpi-dev-alertmanager wget -qO- \
  "http://localhost:9093/api/v2/alerts" | python3 -m json.tool
```

---

## 🔍 Consultas LogQL Úteis

```logql
# Logs de um serviço específico
{job="glpi-app"}

# Logs de múltiplos serviços
{job=~"mariadb|redis"}

# Logs com nível de erro
{job="glpi-app"} |= "error" | logfmt | level="error"

# Logs do Caddy com código HTTP >= 400
{job="caddy"} | json | status >= 400

# Todos os containers do projeto
{job=~".+"}

# Logs de um container específico
{container="glpi-dev-app"}
```

---

## 📋 Referência Rápida de Portas Internas

| Serviço | Porta interna | Protocolo |
|:---|:---|:---|
| glpi-app | 80 | HTTP |
| mariadb | 3306 | MySQL |
| redis | 6379 | Redis |
| prometheus | 9090 | HTTP |
| node-exporter | 9100 | HTTP |
| mysqld-exporter | 9104 | HTTP |
| redis-exporter | 9121 | HTTP |
| grafana | 3000 | HTTP |
| loki | 3100 | HTTP |
| promtail | 9080 | HTTP |
| alertmanager | 9093 | HTTP |

---

## 📋 Comandos Docker Úteis

```bash
# Shell nos containers
docker compose exec glpi-app bash
docker compose exec mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}"
docker compose exec redis redis-cli -a "${REDIS_PASSWORD}"

# Inspecionar saúde detalhada
docker inspect --format='{{json .State.Health}}' glpi-dev-prometheus | python3 -m json.tool

# Ver histórico de healthchecks
docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' glpi-dev-mariadb

# Acompanhar em tempo real
watch -n 5 'docker compose ps'

# Uso de memória por container
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Recriar container sem afetar outros
docker compose up -d --force-recreate --no-deps <serviço>

# Validar compose antes de aplicar
docker compose config --quiet && echo "OK"
```
