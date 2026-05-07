# 🏗️ Arquitetura — GLPI 11 Production Stack

## Visão geral

Stack composto por **6 containers de runtime** (glpi-app, glpi-cron, mariadb, redis, caddy, backup), todos em uma única instância Docker Compose, com **2 redes segregadas** e **5 volumes nomeados**.

## Princípios

1. **Imutabilidade** — todas as imagens com tag fixa; nunca `:latest`
2. **Single Responsibility** — cada container faz uma coisa
3. **Defesa em profundidade** — múltiplas camadas de proteção
4. **Stateless onde possível** — apenas DB, Redis e volume de files são stateful
5. **Composabilidade** — qualquer serviço pode ser substituído sem afetar os outros

## Fluxo de requisição (caminho feliz)

```
Cliente → DNS → IP público → host:443
       → Caddy (TLS termination, headers)
       → glpi-app (PHP-FPM via Apache, porta 80 interna)
       → MariaDB (queries SQL, porta 3306 interna)
       → Redis (cache hit / sessão lookup, porta 6379 interna)
       → Resposta volta pelo mesmo caminho
```

## Fluxo de tarefas agendadas

```
glpi-cron (loop interno minute-by-minute)
       → MariaDB (lê tabela glpi_crontasks)
       → Redis (cache invalidation se necessário)
       → Executa job (envio de e-mails, sync LDAP, alertas SLA, etc.)
```

## Fluxo de backup

```
backup container (cron interno baseado em BACKUP_CRON_SCHEDULE)
       → MariaDB (mariadb-dump --single-transaction)
       → /glpi-data (read-only, tar dos arquivos)
       → /backups (gzip + rotação)
```

## Fluxo de restore (`scripts/restore.sh`)

```
Operador seleciona backup de banco (por índice)
       → Script detecta backup de arquivos pelo mesmo timestamp automaticamente
       → gzip -t verifica integridade de ambos os arquivos antes de alterar qualquer dado
       → docker compose stop glpi-app glpi-cron   (app fora do ar; banco continua acessível)
       → gunzip | mariadb                          (restore do banco via pipe, sem arquivo temporário)
       → docker run --rm alpine tar -xzf ...       (extrai files no volume sem subir o glpi-app)
       → docker compose start glpi-app glpi-cron
       → aguarda glpi-app healthy (loop de verificação)
       → bin/console cache:clear
```

> **Decisão de design:** o restore dos arquivos usa um container Alpine temporário (`docker run --rm`) em vez de subir o `glpi-app`. Isso evita que o GLPI leia dados inconsistentes durante a extração e elimina dependências de permissão do container de app.

---

## Modelo de rede

### `frontend_net` (bridge `glpi-front`)
- **Membros:** `caddy`, `glpi-app`
- **Função:** isolar a borda (TLS) do front-end aplicacional
- **Externamente acessível:** apenas via portas mapeadas no `caddy`

### `backend_net` (bridge `glpi-back`)
- **Membros:** `glpi-app`, `glpi-cron`, `mariadb`, `redis`, `backup`
- **Função:** comunicação entre app, banco, cache e backup
- **Externamente acessível:** **NÃO**. Nenhuma porta do backend é mapeada para o host.

> 💡 Defesa em profundidade: comprometimento do `caddy` não dá ao atacante acesso direto ao banco — ele precisaria também comprometer o `glpi-app` para chegar ao MariaDB.

## Volumes

| Volume | Conteúdo | Tamanho típico | Backup? |
|---|---|---|---|
| `mariadb_data` | Dados do banco (`/var/lib/mysql`) | 100 MB → vários GB | ✅ via mariadb-dump |
| `redis_data` | AOF + RDB do Redis | < 100 MB | ❌ regenerável |
| `glpi_data` | Config + plugins + arquivos do GLPI | 50 MB → vários GB | ✅ via tar |
| `caddy_data` | Certificados TLS (Let's Encrypt) | < 10 MB | ⚠️ útil ter, mas regenerável |
| `caddy_config` | Estado interno do Caddy | < 1 MB | ❌ regenerável |

## Segurança em camadas

| Camada | Mecanismo |
|---|---|
| **Borda** | Caddy: TLS 1.2+, HSTS preload, headers anti-XSS/clickjacking |
| **Rede** | Segregação `frontend_net` vs `backend_net`, banco sem porta exposta |
| **Container runtime** | `no-new-privileges`, `cap_drop: ALL`, `read_only` (Redis), `tmpfs` |
| **App** | Imagem oficial não-root (`www-data`), OPcache + JIT |
| **Banco** | `local_infile=0`, `skip_name_resolve=1`, usuário não-root específico |
| **Cache** | Senha obrigatória, comandos perigosos renomeados (`FLUSHALL` etc.) |
| **Sessões** | `cookie_secure=1`, `cookie_httponly=1`, `cookie_samesite=Lax`, locking |
| **Secrets** | `.env` com `chmod 600`, gitignore blindado |
| **Logs** | Rotação configurada (10MB × 5 arquivos) — evita disco cheio |
| **Backup** | Dump consistente + integridade verificada + retenção rotacional |

## Trade-offs aceitos (e por quê)

| Trade-off | Motivo |
|---|---|
| Single host (sem HA) | Adequado para piloto on-premise; HA virá com migração para AWS (Fase 3). |
| Backup local em `./backups/` | Simplicidade. Off-site fica como recomendação operacional (rclone). |
| Caddy ao invés de WAF dedicado | Caddy é robusto e simples. WAF (CrowdSec/Cloudflare) pode ser adicionado depois. |
| Sem observabilidade nativa | Logs estruturados em JSON já preparados para Loki na Fase 2. |

## Pontos de extensão para Fase 2 (Observabilidade)

A arquitetura atual já está preparada para receber:
- **Prometheus** — exporters podem ser adicionados sem alterar serviços existentes
- **Grafana** — dashboards consumindo Prometheus
- **Loki + Promtail** — logs JSON já são compatíveis
- **Alertmanager** — integração via Prometheus

## Pontos de extensão para Fase 3 (AWS + Terraform)

- `mariadb` → substituído por **RDS MariaDB** (managed)
- `redis` → substituído por **ElastiCache** (managed)
- `backups/` → sincronizado para **S3** com lifecycle policies
- `caddy` (TLS) → substituído por **ALB + ACM**
- `glpi-app` + `glpi-cron` → ECS Fargate ou EC2 com ASG
- IaC completo em Terraform (modules: vpc, ecs, rds, elasticache, s3, alb, route53)
