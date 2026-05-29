# Fase 3 - AWS + Terraform

> Infraestrutura como Codigo (IaC) para deploy da stack GLPI 11 na AWS.
> Automatiza o processo manual documentado em `fase_02_Observabilidade/docs/AWS-DEPLOY.md`.

---

## O que esta fase faz

Provisiona com Terraform:

| Recurso | Tipo | Proposito |
|---|---|---|
| VPC (10.0.0.0/16) | `aws_vpc` | Isolamento de rede |
| Subnets (public x2, private x1) | `aws_subnet` | Segregacao por tier |
| Internet Gateway + Route Tables | `aws_internet_gateway` | Roteamento para internet |
| Security Group | `aws_security_group` | Firewall: SSH restrito, HTTP/HTTPS aberto |
| EC2 t3.large (Debian 12) | `aws_instance` | Host Docker com 14 containers |
| Elastic IP | `aws_eip` | IP fixo para DNS permanente |
| IAM Role + Instance Profile | `aws_iam_role` | Acesso S3 sem credenciais estaticas |
| S3 Bucket | `aws_s3_bucket` | Backups off-site com lifecycle automatico |
| Route 53 Hosted Zone | `aws_route53_zone` | DNS gerenciado |
| Route 53 A Records | `aws_route53_record` | glpi.dominio + grafana.glpi.dominio -> EIP |
| ACM Certificate | `aws_acm_certificate` | TLS wildcard (pronto para ALB futuro) |
| DynamoDB (bootstrap) | `aws_dynamodb_table` | State locking do Terraform |

**O que NAO muda:** Os 14 containers da Fase 2 rodam exatamente como estao,
via `docker compose up -d` no `user_data` da EC2.

---

## Estimativa de custo

| Recurso | USD/mes |
|---|---|
| EC2 t3.large | ~60,00 |
| EBS gp3 30 GB | ~2,40 |
| S3 + Route 53 + ACM | ~0,65 |
| **Total (24h/dia)** | **~63,00** |

**Para minimizar:** Para a EC2 quando nao usar. Custo residual: ~3/mes (EBS + R53).

---

## Independencia total da Fase 2

A Fase 3 e autossuficiente. Nenhum arquivo de `fase_02_Observabilidade/` e
referenciado. A stack Docker foi copiada para `stack/` e e mantida
independentemente a partir daqui.

## Estrutura de diretorios

```
fase_03_AWS_Terraform/
├── main.tf                    # Chama todos os modulos
├── variables.tf               # Variaveis de entrada
├── outputs.tf                 # IP, URLs, bucket, nameservers
├── versions.tf                # Versoes pinadas (terraform + aws provider)
├── locals.tf                  # Prefixos e tags comuns
├── terraform.tfvars.example   # Template de configuracao (copie para .tfvars)
│
├── modules/
│   ├── vpc/                   # VPC + subnets + IGW + routing
│   ├── security_groups/       # SG da EC2 (22 restrito, 80/443 aberto)
│   ├── compute/               # EC2 + EIP + IAM + user_data.sh.tpl
│   ├── storage/               # S3 bucket de backups + lifecycle
│   ├── dns/                   # Route 53 hosted zone + A records
│   └── acm/                   # Certificado TLS wildcard (para ALB futuro)
│
├── bootstrap/                 # Pre-requisito: S3 state bucket + DynamoDB lock
│
├── stack/                     # Stack Docker - AUTOSSUFICIENTE (sem dependencia da Fase 2)
│   ├── docker-compose.yml     # 14 containers
│   ├── .env.example           # Template (o .env e gerado pelo user_data)
│   ├── services/              # Configs de todos os containers
│   └── scripts/               # bootstrap, backup, restore, healthcheck
│
├── scripts/
│   └── teardown.sh            # Teardown guiado com backup automatico
└── docs/
    ├── ARCHITECTURE.md        # Diagrama, ADRs, principio de independencia
    └── RUNBOOK.md             # Deploy, update, teardown, troubleshooting
```

---

## Inicio rapido (10 minutos)

### 1. Pre-requisitos

```bash
# Terraform >= 1.9
terraform version

# AWS CLI autenticado
aws sts get-caller-identity

# Chave SSH
ls ~/.ssh/id_rsa.pub || ssh-keygen -t rsa -b 4096
```

### 2. Bootstrap (uma vez por conta AWS)

```bash
cd bootstrap/
terraform init && terraform apply
# Anote o output: state_bucket_name e dynamodb_table_name
```

### 3. Configurar backend (em versions.tf)

Descomente o bloco `backend "s3"` em `versions.tf` com os valores do bootstrap.

### 4. Configurar variaveis

```bash
cp terraform.tfvars.example terraform.tfvars
chmod 600 terraform.tfvars
# Edite: domain, admin_cidr_blocks, ssh_public_key, senhas
```

### 5. Deploy

```bash
terraform init
terraform plan -out=fase3.tfplan
terraform apply fase3.tfplan
```

### 6. Pos-deploy

```bash
# Copie os nameservers do output para o registrador do dominio
terraform output route53_nameservers

# Acompanhe o bootstrap da EC2 (~3-5 min)
ssh -i ~/.ssh/id_rsa admin@$(terraform output -raw ec2_public_ip) \
  'tail -f /var/log/glpi-bootstrap.log'
```

---

## Documentacao completa

- `docs/ARCHITECTURE.md` - Diagrama detalhado, ADRs e estimativa de custo
- `docs/RUNBOOK.md` - Deploy, atualizacoes, teardown, troubleshooting
- `bootstrap/README.md` - Detalhes do bootstrap do backend S3

---

## Fases do projeto

| Fase | Status | Conteudo |
|---|---|---|
| [Fase 1](../fase_01_glpi_mariadb_caddy/) | Concluida | GLPI + MariaDB + Redis + Caddy + Backup |
| [Fase 2](../fase_02_Observabilidade/) | Concluida | Fase 1 + Prometheus + Grafana + Loki + Alertmanager |
| **Fase 3** (este diretorio) | **Em andamento** | AWS + Terraform |
