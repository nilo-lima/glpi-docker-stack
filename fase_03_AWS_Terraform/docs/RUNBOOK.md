# Runbook - Fase 3: AWS + Terraform

> Operacoes do dia-a-dia: deploy, update, teardown, troubleshooting.
> A Fase 3 e totalmente independente da Fase 2. Todos os arquivos Docker
> estao em `fase_03_AWS_Terraform/stack/` e todos os caminhos abaixo
> referenciam esse diretorio.

---

## Pre-requisitos

- Terraform >= 1.9 instalado localmente
- AWS CLI v2 configurado (`aws configure` ou variavel `AWS_PROFILE`)
- Conta AWS com permissoes: EC2, VPC, S3, Route 53, ACM, IAM, DynamoDB
- Dominio registrado com acesso ao painel do registrador
- Par de chaves SSH (`~/.ssh/id_rsa` + `~/.ssh/id_rsa.pub`)

```bash
terraform version           # >= 1.9.0
aws sts get-caller-identity # confirma autenticacao
ssh-keygen -l -f ~/.ssh/id_rsa.pub
```

---

## 1. Primeiro deploy (do zero)

### 1.1 Bootstrap do backend S3

```bash
cd fase_03_AWS_Terraform/bootstrap/
terraform init
terraform plan
terraform apply
terraform output   # Anote state_bucket_name e dynamodb_table_name
```

### 1.2 Ativar backend remoto

Abra `../versions.tf`, descomente o bloco `backend "s3"` e preencha com os valores do bootstrap:

```hcl
backend "s3" {
  bucket         = "glpi-fase3-tfstate-<ACCOUNT_ID>"
  key            = "fase03/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "glpi-fase3-terraform-locks"
  encrypt        = true
}
```

### 1.3 Configurar variaveis

```bash
cd ..   # volta para fase_03_AWS_Terraform/
cp terraform.tfvars.example terraform.tfvars
chmod 600 terraform.tfvars
nano terraform.tfvars   # Preencha todos os campos TROCAR_*
```

Campos obrigatorios:
- `admin_cidr_blocks`: seu IP (`curl -s https://checkip.amazonaws.com`)
- `ssh_public_key`: conteudo de `~/.ssh/id_rsa.pub`
- `domain`: dominio registrado
- Todas as senhas

### 1.4 Deploy

```bash
terraform init
terraform validate
terraform plan -out=fase3.tfplan
terraform apply fase3.tfplan    # ~5 minutos
```

### 1.5 Pos-deploy

```bash
# 1. Ver todos os outputs
terraform output

# 2. Configurar nameservers no registrador do dominio
terraform output route53_nameservers
# Copiar os 4 NS para o painel do Registro.br / GoDaddy / Namecheap

# 3. Aguardar propagacao DNS (~5-15 min)
dig +short glpi.seu-dominio.com.br
dig +short grafana.glpi.seu-dominio.com.br
# Ambos devem retornar o Elastic IP

# 4. Acompanhar bootstrap da EC2
ssh -i ~/.ssh/id_rsa admin@$(terraform output -raw ec2_public_ip) \
  'tail -f /var/log/glpi-bootstrap.log'
# Aguardar: "=== Bootstrap concluido com sucesso ==="

# 5. Verificar os 14 containers
ssh -i ~/.ssh/id_rsa admin@$(terraform output -raw ec2_public_ip) \
  'cd /opt/glpi/fase_03_AWS_Terraform/stack && docker compose ps'
```

**Acesso inicial:**
- GLPI: `https://glpi.seu-dominio.com.br` - usuario/senha: `glpi` / `glpi` (trocar imediatamente)
- Grafana: `https://grafana.glpi.seu-dominio.com.br` - admin / `GRAFANA_ADMIN_PASSWORD`

---

## 2. Pos-instalacao GLPI (uma vez)

```bash
EC2_IP=$(terraform output -raw ec2_public_ip)
ssh -i ~/.ssh/id_rsa admin@$EC2_IP

# Entrar no diretorio da stack
cd /opt/glpi/fase_03_AWS_Terraform/stack

# Carregar timezone data no MariaDB
./scripts/enable-timezones.sh

# Configurar Redis como backend de cache e sessoes
./scripts/configure-redis-cache.sh

# Travar o autoinstall para proximos boots
nano .env
# Alterar: GLPI_SKIP_AUTOINSTALL=true
docker compose up -d glpi-app glpi-cron
```

---

## 3. Parar e retomar (economizar custos)

```bash
EC2_ID=$(terraform output -raw ec2_instance_id)

# Parar (preserva EBS ~2,40/mes; para o compute billing)
aws ec2 stop-instances --instance-ids $EC2_ID --region us-east-1

# Verificar
aws ec2 describe-instances \
  --instance-ids $EC2_ID \
  --query 'Reservations[].Instances[].State.Name' \
  --output text

# Retomar (o Elastic IP continua o mesmo - DNS nao muda)
aws ec2 start-instances --instance-ids $EC2_ID --region us-east-1
```

---

## 4. Atualizar a stack Docker na EC2

O `user_data` so roda na criacao da instancia. Para atualizar manualmente:

```bash
EC2_IP=$(terraform output -raw ec2_public_ip)
ssh -i ~/.ssh/id_rsa admin@$EC2_IP
cd /opt/glpi/fase_03_AWS_Terraform/stack

# Backup antes de qualquer mudanca
./scripts/backup-now.sh

# Pull de novas imagens e restart
docker compose pull
docker compose up -d
```

### Atualizar imagem do GLPI (ex: 11.0.7 -> 11.1.0)

1. Edite `terraform.tfvars`: `glpi_image_tag = "11.1.0"`
2. `terraform apply` (atualiza variaveis no state)
3. SSH na EC2, edite `.env` manualmente com a nova tag
4. `docker compose up -d glpi-app glpi-cron`

---

## 5. Rotacionar senhas

1. Atualize a senha em `terraform.tfvars`
2. SSH na EC2 e atualize o `.env`:
   ```bash
   cd /opt/glpi/fase_03_AWS_Terraform/stack
   nano .env  # Altere a senha desejada
   docker compose up -d   # Reinicia com nova senha
   ```
3. `terraform apply` para manter o state sincronizado

---

## 6. Backup manual e restore

```bash
EC2_IP=$(terraform output -raw ec2_public_ip)

# Backup imediato
ssh -i ~/.ssh/id_rsa admin@$EC2_IP \
  'cd /opt/glpi/fase_03_AWS_Terraform/stack && ./scripts/backup-now.sh'

# Sync manual para S3
S3=$(terraform output -raw s3_backup_bucket)
ssh -i ~/.ssh/id_rsa admin@$EC2_IP \
  "aws s3 sync /opt/glpi/fase_03_AWS_Terraform/stack/backups/ s3://$S3/backups/"

# Listar backups no S3
aws s3 ls s3://$S3/backups/

# Restore (interativo)
ssh -i ~/.ssh/id_rsa admin@$EC2_IP \
  'cd /opt/glpi/fase_03_AWS_Terraform/stack && ./scripts/restore.sh'
```

---

## 7. Teardown (destruir infraestrutura)

Use o script guiado que faz backup antes de destruir:

```bash
cd fase_03_AWS_Terraform/
./scripts/teardown.sh
```

Ou manualmente:

```bash
# 1. Backup final
ssh -i ~/.ssh/id_rsa admin@$(terraform output -raw ec2_public_ip) \
  'cd /opt/glpi/fase_03_AWS_Terraform/stack && ./scripts/backup-now.sh'

# 2. Sync S3
S3=$(terraform output -raw s3_backup_bucket)
ssh -i ~/.ssh/id_rsa admin@$(terraform output -raw ec2_public_ip) \
  "aws s3 sync /opt/glpi/fase_03_AWS_Terraform/stack/backups/ s3://$S3/backups/"

# 3. Destroy
terraform destroy
```

---

## 8. Troubleshooting

### Bootstrap da EC2 falhou

```bash
EC2_IP=$(terraform output -raw ec2_public_ip)

# Ver log completo
ssh -i ~/.ssh/id_rsa admin@$EC2_IP 'cat /var/log/glpi-bootstrap.log'

# Ver status
ssh -i ~/.ssh/id_rsa admin@$EC2_IP 'cat /var/lib/glpi-bootstrap.status'

# Diagnostico da stack
ssh -i ~/.ssh/id_rsa admin@$EC2_IP \
  'cd /opt/glpi/fase_03_AWS_Terraform/stack && docker compose ps && docker compose logs --tail=30'
```

### DNS nao propaga

```bash
# Verificar NS no registrador
dig NS seu-dominio.com.br +short
# Deve retornar os 4 NS do Route 53 (ns-XXXX.awsdns-YY.*)

# Consultar diretamente no Route 53 (sem cache local)
NS=$(dig NS seu-dominio.com.br +short | head -1)
dig @$NS glpi.seu-dominio.com.br +short
```

### Caddy nao emite certificado TLS

```bash
ssh -i ~/.ssh/id_rsa admin@$EC2_IP \
  'cd /opt/glpi/fase_03_AWS_Terraform/stack && docker compose logs caddy' \
  | grep -i "certificate\|acme\|tls\|error" | tail -30
# "no such host" -> DNS nao propagou; aguardar e: docker compose restart caddy
# "too many certificates" -> limite Let's Encrypt (5/semana por dominio)
```

### Lock do Terraform nao liberado

```bash
# Ver lock ativo
aws dynamodb scan \
  --table-name glpi-fase3-terraform-locks \
  --region us-east-1

# Liberar forcado (apenas se tiver certeza que nao ha outro apply rodando)
terraform force-unlock <LOCK_ID>
```

### S3 sync nao funciona

```bash
ssh -i ~/.ssh/id_rsa admin@$EC2_IP bash << 'EOF'
# Testar IAM Instance Profile
aws sts get-caller-identity

# Testar acesso ao bucket
aws s3 ls s3://$(aws s3 ls | grep glpi | awk '{print $3}' | head -1)

# Ver log do cron
cat /var/log/glpi-s3-sync.log
EOF
```

### Containers com OOM (Out of Memory)

```bash
ssh -i ~/.ssh/id_rsa admin@$EC2_IP 'sudo dmesg | grep -i "oom\|killed" | tail -20'
# Solucao: t3.large tem 8 GB; se usando t3.medium (4 GB), alguns containers
# serao mortos pelo OOM killer. Usar t3.large para a stack completa de 14 containers.
```

---

## 9. Verificacao de saude completa

```bash
EC2_IP=$(terraform output -raw ec2_public_ip)

echo "=== Containers ==="
ssh -i ~/.ssh/id_rsa admin@$EC2_IP \
  'cd /opt/glpi/fase_03_AWS_Terraform/stack && docker compose ps'

echo "=== TLS ==="
curl -sI https://$(terraform output -raw glpi_url | sed 's|https://||') \
  | grep -E "HTTP|Server"

echo "=== S3 access ==="
aws s3 ls s3://$(terraform output -raw s3_backup_bucket)/

echo "=== Backups locais ==="
ssh -i ~/.ssh/id_rsa admin@$EC2_IP \
  'ls -lh /opt/glpi/fase_03_AWS_Terraform/stack/backups/ 2>/dev/null || echo "Nenhum backup ainda"'
```
