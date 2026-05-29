# Arquitetura - Fase 3: AWS + Terraform

> Decisoes de design e diagrama de infraestrutura.
> Para operacao dia-a-dia, ver `RUNBOOK.md`.

---

## Principio de independencia

A Fase 3 e **totalmente independente** da Fase 2. Todos os arquivos necessarios
para rodar a stack Docker estao dentro de `fase_03_AWS_Terraform/stack/`:

```
fase_03_AWS_Terraform/
├── [arquivos Terraform]   <- IaC: provisiona a infra AWS
└── stack/                 <- stack Docker autossuficiente
    ├── docker-compose.yml
    ├── .env.example
    ├── services/          <- configs de todos os 14 containers
    └── scripts/           <- bootstrap, backup, restore, healthcheck
```

O diretorio `fase_02_Observabilidade/` nao e referenciado em nenhum ponto
da Fase 3. O `user_data.sh.tpl` clona o repositorio e usa exclusivamente
`/opt/glpi/fase_03_AWS_Terraform/stack/` como diretorio de trabalho.

---

## Visao geral

A Fase 3 provisiona infraestrutura AWS para rodar a stack de 14 containers
usando Terraform como IaC. Abordagem "lift and shift": EC2 + Docker Compose,
sem reescrever os containers.

```
Internet
    |
    | :80 / :443
    v
[Elastic IP] -----> [EC2 t3.large - Debian 12]
                         |
                         | /opt/glpi/fase_03_AWS_Terraform/stack/
                         | docker compose up -d (14 containers)
                         |
                    [Caddy 2.8]  <-- TLS terminator (Let's Encrypt)
                    /          \
           [glpi-app]        [grafana]
                |                |
           [backend_net]    [monitoring_net]
           /    |    \       /   |   |   |
      [mariadb][redis][backup][prom][loki][...]

    [S3 Bucket] <-- aws s3 sync (cron 04:00 diario, IAM Instance Profile)

    [Route 53]
        glpi.dominio.com         -> Elastic IP
        grafana.glpi.dominio.com -> Elastic IP

    [ACM] (pronto para ALB futuro)
        *.dominio.com (validado via Route 53)
```

---

## Diagrama de rede AWS

```
VPC (10.0.0.0/16)
 |
 +-- Internet Gateway
 |
 +-- Subnet Publica A (10.0.1.0/24) - us-east-1a
 |       EC2 t3.large + Elastic IP
 |       Security Group: 22(admin), 80(0.0.0.0/0), 443(0.0.0.0/0)
 |
 +-- Subnet Publica B (10.0.2.0/24) - us-east-1b
 |       [Vazia - reservada para ALB em fase futura]
 |
 +-- Subnet Privada (10.0.3.0/24) - us-east-1a
         [Vazia - reservada para RDS/ElastiCache em fase futura]
         Sem rota para Internet Gateway (defesa em profundidade)
```

---

## Componentes Terraform

### Modulo `vpc`

Cria o isolamento de rede equivalente ao que o Docker Bridge faz na Fase 2.

| Docker (Fase 2) | AWS (Fase 3) |
|---|---|
| `frontend_net` (bridge) | Subnet publica A (EC2 com EIP) |
| `backend_net` (internal) | Subnet privada (sem rota IGW) |
| `monitoring_net` | Subnet publica B (reservada) |

### Modulo `security_groups`

Firewall da EC2. As portas internas (3306 MariaDB, 6379 Redis, 9090 Prometheus, etc.)
NAO sao expostas - trafego fica dentro do host Docker, sem necessidade de regra SG.

### Modulo `storage`

S3 bucket para backups off-site. Substitui o diretorio `./backups/` local da Fase 2.
A EC2 acessa via IAM Instance Profile (sem credenciais estaticas no host).

Hierarquia de custo S3:
- 0-30 dias: Standard (restore rapido)
- 30-90 dias: Standard-IA (acesso infrequente)
- 90-365 dias: Glacier (arquivamento)
- 365+ dias: Expirar (configuravel)

### Modulo `compute`

EC2 com user_data que automatiza o `AWS-DEPLOY.md` da Fase 2:
1. Instala Docker CE + AWS CLI v2
2. Clona o repositorio
3. Gera o `.env` com as variaveis do tfvars
4. Sobe a stack Fase 2 via `docker compose up -d`
5. Configura cron para S3 sync diario

IMDSv2 obrigatorio: previne SSRF attacks no metadata service da EC2.

### Modulo `dns`

Hosted zone Route 53 com 2 A records apontando para o Elastic IP.
Apos o apply: copiar os nameservers do output para o registrador do dominio.

### Modulo `acm`

Certificado TLS wildcard provisionado e validado via Route 53.
Nao substitui o Caddy nesta fase - pronto para quando um ALB for adicionado.

---

## ADRs (Architecture Decision Records)

### ADR-01: EC2 + Docker Compose vs ECS Fargate

**Decisao:** EC2 + Docker Compose.

**Motivo:** O objetivo e aprendizado pratico de Terraform + AWS, nao migrar a arquitetura
dos containers. O docker-compose.yml da Fase 2 funciona sem modificacoes em uma EC2.
ECS Fargate exigiria reescrever 14 task definitions e lidar com complexidades de rede
ECS (service discovery, task networking, etc.).

**Trade-off aceito:** Sem auto-scaling automatico e sem rolling deploys.
Mitigado: instancia t3.large superdimensionada para a carga atual.

### ADR-02: MariaDB + Redis como containers vs RDS + ElastiCache

**Decisao:** Manter como containers na EC2.

**Motivo:** Custo. RDS MariaDB Multi-AZ custa ~USD 100/mes; ElastiCache ~USD 50/mes.
Para o objetivo de portfolio/aprendizado, o overhead de custo nao se justifica.
A arquitetura interna (dados, backups, seguranca) ja e production-grade na Fase 2.

**Trade-off aceito:** Sem HA automatica para banco e cache.
Mitigado: backups diarios em S3 com retencao de 365 dias.

### ADR-03: ACM sem ALB

**Decisao:** Provisionar o ACM cert mas manter o Caddy como TLS terminator.

**Motivo:** ACM certificates so funcionam com servicos AWS (ALB, CloudFront).
Nao e possivel instalar um cert ACM diretamente em uma EC2.
O Caddy com Let's Encrypt e gratuito e automatico - nao ha razao para substituir.

**Valor do ACM aqui:** Aprendizado do fluxo de provisionamento + validacao DNS,
e o cert ja estara pronto quando o ALB for adicionado.

### ADR-04: Backend S3 para tfstate vs Local

**Decisao:** Backend S3 remoto com DynamoDB locking.

**Motivo:** Boa pratica fundamental do Terraform. State local nao funciona em
equipe (nao ha "single source of truth") e e perdido com o computador.
O diretorio `bootstrap/` resolve o bootstrap paradox (precisa do S3 para armazenar
o estado, mas precisa do Terraform para criar o S3).

### ADR-05: Senhas no tfvars vs AWS Secrets Manager

**Decisao:** Senhas em `terraform.tfvars` (gitignored).

**Motivo:** Para o escopo de portfolio/aprendizado, tfvars com `sensitive = true`
e suficiente. AWS Secrets Manager custa ~USD 0,40/secret/mes e adiciona complexidade
no user_data (necessita `aws secretsmanager get-secret-value` + parsing JSON).

**Trade-off aceito:** Senhas ficam em plaintext no tfstate remoto (S3 criptografado).
Para producao real: migrar para SSM SecureString (gratis) ou Secrets Manager.

---

## Estimativa de custo

| Recurso | Custo/mes (USD) |
|---|---|
| EC2 t3.large On-Demand (us-east-1) | ~60,00 |
| EBS gp3 30 GB | ~2,40 |
| Elastic IP (associado a EC2 rodando) | 0,00 |
| S3 Standard (< 5 GB backups) | < 0,15 |
| Route 53 Hosted Zone | 0,50 |
| ACM Certificate | 0,00 |
| DynamoDB (state lock - PAY_PER_REQUEST) | < 0,01 |
| **Total estimado** | **~63/mes** |

**Para minimizar custos:**
- Parar a EC2 quando nao estiver em uso: `aws ec2 stop-instances --instance-ids <ID>`
- EBS cobra mesmo com instancia parada (~2,40/mes)
- Para custo zero: `terraform destroy` (destroi tudo exceto S3 state bucket)

---

## Fase 4 (roadmap)

Quando esta arquitetura for "promovida" para producao real:

1. **ALB** (Application Load Balancer) na frente da EC2 - usar o ACM cert ja provisionado
2. **Auto Scaling Group** (min 1, max 3) para resilencia
3. **RDS MariaDB Multi-AZ** - substituir container mariadb
4. **ElastiCache Redis** - substituir container redis
5. **NAT Gateway** - para subnets privadas terem acesso de saida (Docker pull em subnet privada)
6. **CloudWatch Alarms** - integrar com Alertmanager existente
