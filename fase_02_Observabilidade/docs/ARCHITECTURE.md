# 🏗️ Arquitetura — GLPI 11 + Observabilidade (Fase 2)

## Visão Geral

Stack de **14 containers** orquestrados por Docker Compose em uma única instância. Engloba todos os serviços da Fase 1 (GLPI) mais 8 serviços de observabilidade, segregados em **3 redes bridge** e distribuídos em **13 volumes nomeados**.

---

## Fluxos Principais

### Requisição HTTP (caminho feliz)

```
Cliente → DNS → IP público → host:443
       → Caddy (TLS termination, headers de segurança)
       → glpi-app (PHP-FPM via Apache, porta 80 interna)
       → MariaDB (queries SQL)
       → Redis (cache / sessão)
       → Resposta pelo mesmo caminho
```

### Acesso ao Grafana

```
Cliente → DNS → host:443
       → Caddy (bloco {$GRAFANA_DOMAIN}, TLS automático)
       → grafana:3000 (interno via frontend_net)
       → Prometheus (queries de métricas via monitoring_net)
       → Loki (queries de logs via monitoring_net)
```

### Coleta de Métricas

```
prometheus (a cada 15s)
       → node-exporter:9100   (métricas do host OS)
       → mysqld-exporter:9104 (métricas MariaDB via .my.cnf)
       → redis-exporter:9121  (métricas Redis via REDIS_PASSWORD)
       → prometheus:9090      (auto-monitoramento)
       → alertmanager:9093    (notificação de alertas disparados)
```

### Coleta de Logs

```
promtail (polling Docker socket a cada 5s)
       → descobre containers via unix:///var/run/docker.sock (read-only)
       → lê /var/lib/docker/containers/*/*-json.log (read-only)
       → enriquece com labels: job, container, service, image
       → push HTTP para loki:3100/loki/api/v1/push
```

### Backup

```
backup container (cron via BACKUP_CRON_SCHEDULE)
       → MariaDB (mariadb-dump --single-transaction)
       → volume glpi_data (tar dos arquivos GLPI, read-only)
       → /backups (gzip + verificação de integridade + rotação por retenção)
```

---

## Modelo de Redes

### `frontend_net` (bridge `glpi-dev_frontend`)

| Container | Papel na rede |
|:---|:---|
| `caddy` | Borda: TLS termination, reverse proxy |
| `glpi-app` | Destino das requisições GLPI |
| `grafana` | Destino das requisições do Grafana |

- Única rede com portas mapeadas para o host (`80`, `443`)
- Acesso externo exclusivamente via Caddy

### `backend_net` (bridge `glpi-dev_backend`)

| Container | Papel na rede |
|:---|:---|
| `glpi-app` | Acessa banco e cache |
| `glpi-cron` | Acessa banco e cache para jobs agendados |
| `mariadb` | Servidor de banco |
| `redis` | Servidor de cache e sessões |
| `backup` | Lê banco para dump |
| `mysqld-exporter` | Acessa MariaDB via protocolo MySQL |
| `redis-exporter` | Acessa Redis via protocolo Redis |

- **Nenhuma porta exposta no host**
- Comprometimento do `caddy` não dá acesso direto ao banco

### `monitoring_net` (bridge `glpi-dev_monitoring`)

| Container | Papel na rede |
|:---|:---|
| `prometheus` | Scraper central |
| `node-exporter` | Expõe métricas do host |
| `mysqld-exporter` | Expõe métricas do MariaDB |
| `redis-exporter` | Expõe métricas do Redis |
| `grafana` | Consome métricas e logs |
| `loki` | Armazena e serve logs |
| `promtail` | Envia logs para Loki |
| `alertmanager` | Recebe alertas do Prometheus |

- Isolada do `frontend_net` e `backend_net`
- `mysqld-exporter` e `redis-exporter` estão em **ambas** `monitoring_net` e `backend_net`
- `grafana` está em **ambas** `frontend_net` e `monitoring_net`

---

## Volumes

| Volume | Conteúdo | Backup? |
|:---|:---|:---|
| `mariadb_data` | Dados do banco (`/var/lib/mysql`) | ✅ via mariadb-dump |
| `redis_data` | AOF + RDB do Redis | ❌ regenerável |
| `glpi_data` | Config + plugins + arquivos GLPI | ✅ via tar |
| `caddy_data` | Certificados TLS | ⚠️ regenerável pelo Let's Encrypt |
| `caddy_config` | Estado interno do Caddy | ❌ regenerável |
| `prometheus_data` | TSDB de métricas | ❌ re-preenchido ao reconectar |
| `grafana_data` | Config, usuários, dashboards manuais | ⚠️ dashboards provisionados são recuperáveis |
| `loki_data` | Índice TSDB + chunks de logs | ❌ histórico perdido, novos logs coletados |
| `promtail_positions` | Posições de leitura por container | ❌ regenerável (re-envia logs recentes) |
| `alertmanager_data` | Silences e notificações | ❌ regenerável |

---

## Segurança em Camadas

| Camada | Mecanismo |
|:---|:---|
| **Borda** | Caddy: TLS 1.2+, HSTS, X-Frame-Options, X-Content-Type-Options |
| **Rede** | 3 redes bridge segregadas; banco, cache e monitoring sem porta no host |
| **Container** | `no-new-privileges:true`, `cap_drop: ALL`, `cap_add` mínimo documentado |
| **Credenciais exporters** | Usuário `monitoring` com `PROCESS, SELECT, REPLICATION CLIENT, SLAVE MONITOR` apenas |
| **Senha do exporter** | Armazenada em `.my.cnf` (chmod 644) em vez de `DATA_SOURCE_NAME` — evita parsing de `@`/`#` |
| **Secrets** | `.env` com `chmod 600`, `.gitignore` blindado, `.my.cnf` gitignored |
| **Logs** | Rotação configurada (10 MB × 5 arquivos); logs em stdout/stderr |
| **Recursos** | `mem_limit` explícito em todos os containers |

---

## Decisões Arquiteturais

### ADR-001 — Stack unificada (não externa)

A Fase 2 foi projetada como stack **independente e auto-suficiente**, incluindo todos os serviços da Fase 1. Isso elimina dependência de redes externas (`external: true`), simplifica o bootstrap (um único `docker compose up -d`) e garante que as redes tenham os nomes corretos sem depender do estado da Fase 1.

Custo: duplicação dos serviços GLPI se ambas as fases forem executadas simultaneamente. Mitigação: usar `COMPOSE_PROJECT_NAME` diferente por fase.

### ADR-002 — Credenciais do mysqld-exporter via `.my.cnf`

O `prom/mysqld-exporter` suporta dois métodos de credenciais:
1. `DATA_SOURCE_NAME` como variável de ambiente (DSN URL)
2. Arquivo `--config.my-cnf` (formato MySQL client)

Senhas com `@` ou `#` quebram o parsing de DSN URL (o `@` é o separador de credenciais em URLs). O método `.my.cnf` não tem essa restrição e é mais adequado para senhas geradas com `openssl rand`. O arquivo é gitignored e gerado pelo script `setup-monitoring-user.sh`.

### ADR-003 — Healthcheck do promtail via `bash /dev/tcp`

`grafana/promtail:3.3.2` é baseado em Debian slim sem `wget` ou `curl`. O healthcheck padrão `wget -qO- http://localhost:9080/ready` falha com exit 127. A alternativa é usar `bash -c "echo > /dev/tcp/localhost/9080"` — bash está disponível na imagem e `/dev/tcp` funciona como pseudo-arquivo de socket TCP.

### ADR-004 — Healthcheck desabilitado no redis-exporter

`oliver006/redis_exporter:v1.66.0` usa imagem scratch (apenas o binário Go estático). Não há shell, wget, curl ou qualquer utilitário disponível. A saúde do exporter é monitorada indiretamente pelo Prometheus: se o scrape de `:9121/metrics` falhar, o alerta `TargetDown` dispara.

### ADR-005 — Filtragem Promtail por projeto Docker Compose

Promtail 3.x Docker SD não expõe `__meta_docker_container_state` (ao contrário do que a documentação de versões anteriores sugeria). Usar `action: keep` nessa label causa descarte silencioso de todos os targets. O filtro correto é por `__meta_docker_container_label_com_docker_compose_project`, que garante que apenas containers deste projeto sejam coletados.

### ADR-006 — Label `job` no Promtail para compatibilidade Grafana

Dashboards da comunidade Grafana (ex: Loki quickstart ID 13639) usam `{job="$app"}` como seletor padrão. Adicionamos `job` como label no Promtail mapeado do nome do serviço Docker Compose, permitindo que dashboards da comunidade funcionem sem modificação (além da substituição do datasource template `${DS_LOKI}` → `loki`).

---

## Diagrama de Dependências de Startup

```
mariadb ──────────────────┐
                          ▼
redis ────────────────► glpi-app ──────────────► caddy
                          │
                          └──────────────────► glpi-cron
                          │
mariadb ──────────────► backup

mariadb ──────────────► mysqld-exporter ──┐
redis ────────────────► redis-exporter ───┤
                                          ▼
prometheus ────────────────────────────► grafana
loki ──────────────────────────────────► grafana
                          ▲
promtail ─────────────────┘ (envia para loki)
```

Todos os `depends_on` usam `condition: service_healthy` — cada serviço só sobe após seu(s) dependente(s) estarem healthy.
