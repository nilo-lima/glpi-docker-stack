# Deploy na AWS - EC2 com TLS Real (Fase 2)

Passos para implantar a stack completa (GLPI + Observabilidade) em uma instância EC2, com dois subdomínios reais e certificados Let's Encrypt automáticos.

> **Custo estimado:** t3.large On-Demand (~USD 0,083/h = ~USD 2,00/dia). Desligue a instância após o teste.
> A Fase 2 exige mais recursos que a Fase 1: 14 containers, Prometheus TSDB e Loki requerem t3.large (8 GB RAM) e 30 GB de disco.

---

## Pré-requisitos

- Conta AWS com permissão de criar EC2 + Security Groups
- Domínio registrado com acesso ao painel DNS (ex: Route 53, Cloudflare, Registro.br)
- AWS CLI instalado e configurado localmente (`aws configure`)
- Dois registros DNS disponíveis no mesmo domínio (GLPI + Grafana)

---

## 1. Criar a instância EC2

### Via Console AWS

| Campo | Valor |
|---|---|
| AMI | **Debian 12 (Bookworm)** - buscar "Debian 12" no marketplace |
| Instance type | **t3.large** (2 vCPU, 8 GB RAM) - necessário para 14 containers |
| Key pair | Criar ou selecionar um par de chaves existente (`.pem`) |
| Storage | **30 GB** gp3 - Prometheus TSDB + Loki chunks crescem com o tempo |
| Region | `us-east-1` (ou a mais próxima do usuário final) |

### Via AWS CLI

```bash
# Substituir ami-xxxxxxxxxx pela AMI Debian 12 da região escolhida
# aws ec2 describe-images --owners 136693071363 \
#   --filters "Name=name,Values=debian-12-amd64-*" \
#   --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text
aws ec2 run-instances \
  --image-id ami-xxxxxxxxxx \
  --instance-type t3.large \
  --key-name minha-chave \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=glpi-fase2}]' \
  --count 1
```

---

## 2. Configurar Security Group

| Porta | Protocolo | Origem | Motivo |
|---|---|---|---|
| 22 | TCP | Seu IP (`x.x.x.x/32`) | SSH - **nunca 0.0.0.0/0** |
| 80 | TCP | 0.0.0.0/0, ::/0 | HTTP (Caddy redireciona para HTTPS) |
| 443 | TCP | 0.0.0.0/0, ::/0 | HTTPS - GLPI e Grafana passam pelo Caddy |
| 443 | UDP | 0.0.0.0/0, ::/0 | QUIC / HTTP/3 (opcional) |

> **Grafana não precisa de porta extra** - trafega por `https://grafana.seu-dominio.com.br` via Caddy na porta 443. Banco, Redis e demais serviços de monitoramento ficam sem porta exposta no host.

---

## 3. Apontar DNS para a instância

Dois registros `A` são necessários. No painel DNS do seu provedor:

```
glpi.seu-dominio.com.br.        IN  A  <IP_PUBLICO_DA_EC2>
grafana.glpi.seu-dominio.com.br. IN  A  <IP_PUBLICO_DA_EC2>
```

Anotar o IP público:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=glpi-fase2" \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text
```

Verificar propagação de **ambos** os registros antes de prosseguir:

```bash
dig +short glpi.seu-dominio.com.br
dig +short grafana.glpi.seu-dominio.com.br
# Ambos devem retornar o mesmo IP da EC2
```

> **Por que esperar?** O Caddy solicita certificados independentes para cada domínio via Let's Encrypt. Se qualquer DNS não estiver propagado, o challenge ACME falha para aquele domínio.

---

## 4. Preparar a instância

```bash
# Conectar via SSH
ssh -i ~/.ssh/minha-chave.pem admin@<IP_PUBLICO>

# Atualizar o sistema
sudo apt-get update && sudo apt-get upgrade -y

# Instalar Docker Engine (método oficial)
curl -fsSL https://get.docker.com | sudo sh

# Adicionar usuário ao grupo docker
sudo usermod -aG docker admin
newgrp docker

# Verificar
docker version
docker compose version
```

---

## 5. Clonar o repositório

```bash
git clone https://github.com/nilo-lima/glpi-docker-stack.git
cd glpi-docker-stack/fase_02_Observabilidade
```

---

## 6. Configurar o `.env`

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Alterações obrigatórias para a AWS:

```dotenv
# Dois domínios reais
GLPI_DOMAIN=glpi.seu-dominio.com.br
GRAFANA_DOMAIN=grafana.glpi.seu-dominio.com.br
ACME_EMAIL=seu-email@exemplo.com

# Senhas - substituir todos os valores TROCAR_*
MARIADB_ROOT_PASSWORD="senha-root-forte-aqui"
MARIADB_PASSWORD="senha-glpi-forte-aqui"
REDIS_PASSWORD="senha-redis-forte-aqui"
GRAFANA_ADMIN_PASSWORD="senha-grafana-forte-aqui"
GRAFANA_SECRET_KEY="$(openssl rand -hex 32)"

# Senha do monitoring sem @ ou / (caracteres proibidos em DSN MySQL)
# Gerar: openssl rand -base64 18 | tr -d '@/+'
MARIADB_MONITORING_PASSWORD="senha-monitoring-forte-aqui"

# Limites para t3.large (8 GB RAM)
GLPI_MEMORY_LIMIT=1G
MARIADB_MEMORY_LIMIT=2G
REDIS_MEMORY_LIMIT=256M
PROMETHEUS_MEMORY_LIMIT=1G
GRAFANA_MEMORY_LIMIT=512M
LOKI_MEMORY_LIMIT=512M
ALERTMANAGER_MEMORY_LIMIT=128M
NODE_EXPORTER_MEMORY_LIMIT=64M
MYSQLD_EXPORTER_MEMORY_LIMIT=64M
REDIS_EXPORTER_MEMORY_LIMIT=64M
PROMTAIL_MEMORY_LIMIT=128M

# Retenção de métricas e logs
PROMETHEUS_RETENTION=30d

TZ=America/Sao_Paulo
```

---

## 7. Configurar usuário de monitoramento no MariaDB

O `mysqld-exporter` usa um usuário dedicado com privilégios mínimos. Execute antes de subir a stack completa:

```bash
# Sobe apenas o MariaDB
docker compose up -d mariadb

# Aguarda healthy e cria o usuário 'monitoring' + gera .my.cnf
./scripts/setup-monitoring-user.sh
```

Saída esperada:
```
Aguardando glpi-dev-mariadb ficar healthy...
MariaDB healthy.
Usuário 'monitoring' configurado.
.my.cnf gerado em services/mysqld-exporter/config/.my.cnf (chmod 644).
```

---

## 8. Subir a stack completa

```bash
# Validar sintaxe antes de subir
docker compose config --quiet && echo "OK"

# Subir todos os 14 containers
docker compose up -d
```

A primeira execução baixa as imagens (~2 GB) e instala o GLPI (~3–5 min). Acompanhe:

```bash
docker compose logs -f glpi-app
```

---

## 9. Verificar saúde

```bash
# Todos os 14 containers devem ser healthy (redis-exporter fica só "Up")
docker compose ps

# Healthcheck completo
./scripts/healthcheck-all.sh

# Targets Prometheus (todos devem ser "up")
docker exec glpi-dev-prometheus wget -qO- \
  http://localhost:9090/api/v1/targets | \
  python3 -c "
import json, sys
for t in json.load(sys.stdin)['data']['activeTargets']:
    print(f\"[{t['health']}] {t['labels'].get('job','?')}\")
"
```

---

## 10. Pós-instalação do GLPI (uma vez)

```bash
# Habilitar timezone data no MariaDB
./scripts/enable-timezones.sh

# Configurar Redis como backend de cache e sessões
./scripts/configure-redis-cache.sh
```

Edite `.env` e trave o autoinstall para próximos boots:

```dotenv
GLPI_SKIP_AUTOINSTALL=true
```

```bash
docker compose up -d glpi-app glpi-cron
```

---

## 11. Acessar os serviços

| Serviço | URL | Credenciais padrão |
|---|---|---|
| GLPI | `https://glpi.seu-dominio.com.br` | `glpi` / `glpi` - **trocar imediatamente** |
| Grafana | `https://grafana.glpi.seu-dominio.com.br` | `admin` / `GRAFANA_ADMIN_PASSWORD` |

No Grafana, pasta **GLPI Production** contém 4 dashboards provisionados automaticamente:
- **Node Exporter Full** - CPU, RAM, disco, rede do host
- **MySQL Overview** - Queries, conexões, InnoDB do MariaDB
- **Redis Dashboard** - Memória, hit ratio, comandos
- **Logs / App** - Logs centralizados por serviço (selecionar em "App")

---

## 12. Backups off-site para S3 (recomendado)

Os backups são salvos em `./backups/` no host. Para sincronizar com S3:

```bash
# Instalar AWS CLI na instância (se não tiver)
sudo apt-get install -y awscli

# Configurar credenciais (ou usar IAM Instance Profile - recomendado)
aws configure

# Testar sincronização
aws s3 sync ./backups/ s3://meu-bucket-glpi/fase2-backups/

# Adicionar ao crontab do HOST para rodar após o backup das 03:00
# crontab -e
# 0 4 * * * aws s3 sync /home/admin/glpi-docker-stack/fase_02_Observabilidade/backups/ s3://meu-bucket-glpi/fase2-backups/ --storage-class STANDARD_IA
```

> **IAM Instance Profile** é mais seguro que `aws configure` com credenciais estáticas. Crie um role com política `AmazonS3FullAccess` (ou escopo restrito ao bucket) e associe à instância.

---

## 13. Teardown (evitar custos)

```bash
# Backup final antes de destruir
./scripts/backup-now.sh
aws s3 sync ./backups/ s3://meu-bucket-glpi/fase2-backups/

# Parar a stack
docker compose down

# Copiar backups para local antes de encerrar (opcional)
# No terminal LOCAL:
scp -i ~/.ssh/minha-chave.pem -r \
  admin@<IP_PUBLICO>:~/glpi-docker-stack/fase_02_Observabilidade/backups/ \
  ~/backups-glpi-fase2/
```

No Console AWS ou CLI:

```bash
# Parar (preserva EBS - cobra ~USD 0,08/GB-mês)
aws ec2 stop-instances --instance-ids <INSTANCE_ID>

# Terminar (destrói tudo - sem custo residual)
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
```

---

## Diferenças vs ambiente local

| Aspecto | Local | AWS EC2 |
|---|---|---|
| DNS | automático (`.localhost`) | 2 registros `A` reais |
| TLS | Caddy self-signed interno | Let's Encrypt - certificados reais |
| `GLPI_DOMAIN` | `glpi.localhost` | `glpi.seu-dominio.com.br` |
| `GRAFANA_DOMAIN` | `grafana.glpi.localhost` | `grafana.glpi.seu-dominio.com.br` |
| Custo | Zero | ~USD 0,083/h (t3.large) |
| IP fixo | Sim | Muda a cada start - usar Elastic IP para DNS permanente |
| Backups | `./backups/` local | `./backups/` + S3 off-site |

### Elastic IP (recomendado para DNS permanente)

```bash
# Alocar
aws ec2 allocate-address --domain vpc

# Associar
aws ec2 associate-address \
  --instance-id <INSTANCE_ID> \
  --allocation-id <ALLOCATION_ID>

# Atualizar os dois registros DNS com o Elastic IP
# O Elastic IP não muda entre start/stop
```

> Elastic IP é gratuito enquanto associado a uma instância **rodando**. Cobra USD 0,005/h se alocado sem instância associada.

---

## Troubleshooting

### Certificado TLS não gerado para um dos domínios

```bash
docker compose logs caddy | grep -i "certificate\|acme\|tls\|error" | tail -30
# Erros comuns:
# - "no such host" → DNS não propagou - aguardar e fazer: docker compose restart caddy
# - "connection refused on :80" → porta 80 bloqueada no Security Group
# - "too many certificates" → limite Let's Encrypt (5/semana por domínio)
```

### Containers com OOM kill (14 containers em t3.medium)

```bash
sudo dmesg | grep -i "oom\|killed"
# Solução: usar t3.large (8 GB) - t3.medium (4 GB) é insuficiente para a Fase 2
```

### setup-monitoring-user.sh: Access denied

```bash
# O MariaDB ainda não terminou a inicialização - o script aguarda até 180s.
# Se falhou antes disso, reiniciar manualmente:
docker compose restart mariadb
./scripts/setup-monitoring-user.sh
```

### Grafana sem dados no dashboard "Logs / App"

```bash
# Verificar se o Loki está recebendo dados
docker exec glpi-dev-loki wget -qO- \
  "http://localhost:3100/loki/api/v1/label/job/values" | python3 -m json.tool
# Deve listar os 14 serviços

# No dashboard, setar time range para "Last 15 minutes"
# e selecionar um serviço no dropdown "App"
```

### Prometheus targets down

```bash
# Verificar conectividade do exporter com o banco/cache
docker compose logs mysqld-exporter | tail -20
docker compose logs redis-exporter | tail -20

# Se mysqld-exporter com "permission denied":
chmod 644 services/mysqld-exporter/config/.my.cnf
docker compose restart mysqld-exporter
```

### Disco crescendo rapidamente

```bash
df -h
docker system df -v | grep glpi-dev

# Prometheus: reduzir retenção no .env (PROMETHEUS_RETENTION=15d)
# Loki: retention configurado para 31 dias em services/loki/config/loki.yml
# Backups: ajustar BACKUP_RETENTION_DAYS no .env
docker compose up -d --force-recreate --no-deps prometheus
```
