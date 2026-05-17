# Deploy na AWS - EC2 com TLS Real

Passos para implantar a Fase 1 em uma instância EC2, com domínio real e certificado Let's Encrypt.

> **Custo estimado:** t3.medium On-Demand (~USD 0,042/h = ~USD 1,00/dia). Desligue a instância após o teste.

---

## Pré-requisitos

- Conta AWS com permissão de criar EC2 + Security Groups
- Domínio registrado com acesso ao painel DNS (ex: `seu-dominio.com.br`)
- AWS CLI instalado e configurado localmente (`aws configure`)
- GitHub CLI instalado (`gh`) - ou o repositório já publicado

---

## 1. Criar a instância EC2

### Via Console AWS

| Campo | Valor |
|---|---|
| AMI | **Debian 12 (Bookworm)** - buscar "Debian 12" no marketplace |
| Instance type | **t3.medium** (2 vCPU, 4 GB RAM) - mínimo para GLPI em produção |
| Key pair | Criar ou selecionar um par de chaves existente (`.pem`) |
| Storage | **20 GB** gp3 (raiz) |
| Region | `us-east-1` (ou a mais próxima do usuário final) |

### Via AWS CLI

```bash
# Substituir ami-xxxxxxxxxx pela AMI Debian 12 da região escolhida
aws ec2 run-instances \
  --image-id ami-xxxxxxxxxx \
  --instance-type t3.medium \
  --key-name minha-chave \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=glpi-fase1}]' \
  --count 1
```

---

## 2. Configurar Security Group

Abrir as portas abaixo na instância (Console: EC2 → Security Groups → Inbound rules):

| Porta | Protocolo | Origem | Motivo |
|---|---|---|---|
| 22 | TCP | Seu IP (`x.x.x.x/32`) | SSH - **nunca 0.0.0.0/0** |
| 80 | TCP | 0.0.0.0/0, ::/0 | HTTP (Caddy redireciona para HTTPS) |
| 443 | TCP | 0.0.0.0/0, ::/0 | HTTPS |
| 443 | UDP | 0.0.0.0/0, ::/0 | QUIC / HTTP/3 (opcional) |

> **Banco e Redis** não precisam de regra - ficam em rede interna Docker, sem porta exposta no host.

---

## 3. Apontar DNS para a instância

No painel do seu registrador/DNS (ex: Registro.br, Route 53, Cloudflare):

```
glpi.seu-dominio.com.br.  IN  A  <IP_PUBLICO_DA_EC2>
```

Anotar o IP público:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=glpi-fase1" \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text
```

Verificar propagação antes de prosseguir:

```bash
# Aguardar até retornar o IP correto (pode levar de 1 a 30 min)
dig +short glpi.seu-dominio.com.br
```

> **Por que esperar?** O Caddy tenta obter o certificado TLS via Let's Encrypt no primeiro `up`. Se o DNS ainda não propagou, o challenge ACME falha e o Caddy retenta com backoff exponencial. Confirmar o DNS antes de subir a stack evita esse delay.

---

## 4. Preparar a instância

```bash
# Conectar via SSH
ssh -i ~/.ssh/minha-chave.pem admin@<IP_PUBLICO>

# Atualizar o sistema
sudo apt-get update && sudo apt-get upgrade -y

# Instalar Docker Engine (método oficial)
curl -fsSL https://get.docker.com | sudo sh

# Adicionar usuário ao grupo docker (evita sudo em todo comando)
sudo usermod -aG docker admin
newgrp docker   # recarrega grupos sem desconectar

# Verificar
docker version
docker compose version
```

---

## 5. Clonar o repositório

```bash
# Clonar o monorepo
git clone https://github.com/nilo-lima/glpi-docker-stack.git
cd glpi-docker-stack/fase_01_glpi_mariadb_caddy
```

---

## 6. Configurar o `.env`

```bash
cp .env.example .env
chmod 600 .env
nano .env   # ou vim .env
```

Alterações obrigatórias para a AWS:

```dotenv
# Domínio real (usado pelo Caddy para emitir certificado Let's Encrypt)
GLPI_DOMAIN=glpi.seu-dominio.com.br

# E-mail para notificações de expiração do certificado
ACME_EMAIL=seu-email@exemplo.com

# Senhas - trocar todos os valores TROCAR_*
MARIADB_ROOT_PASSWORD="senha-root-forte-aqui"
MARIADB_PASSWORD="senha-glpi-forte-aqui"
REDIS_PASSWORD="senha-redis-forte-aqui"

# Ajuste de memória para t3.medium (4 GB RAM total)
MARIADB_MEMORY_LIMIT=1g
GLPI_MEMORY_LIMIT=1g
REDIS_MEMORY_LIMIT=256m
BACKUP_MEMORY_LIMIT=128m

# Timezone
TZ=America/Sao_Paulo
```

---

## 7. Executar o bootstrap

```bash
# Validar configuração antes de subir
docker compose config

# Bootstrap completo (instala GLPI, configura Redis, habilita timezones)
./scripts/bootstrap.sh
```

O script executa em ~3–5 minutos. Ao final, todos os containers devem aparecer como `healthy`:

```bash
docker compose ps
```

---

## 8. Acessar o GLPI

Abrir no browser:

```
https://glpi.seu-dominio.com.br
```

O Caddy emite o certificado Let's Encrypt automaticamente na primeira requisição. Se o certificado ainda estiver sendo gerado, aguardar ~30s e recarregar.

Credenciais padrão:

| Campo | Valor |
|---|---|
| Usuário | `glpi` |
| Senha | `glpi` |

> **Trocar a senha imediatamente** após o primeiro login: Menu do usuário → Preferências → Senha.

---

## 9. Pós-instalação

```bash
# Marcar instalação como concluída (evita re-execução do wizard)
# Já feito pelo bootstrap.sh - confirmar:
docker compose exec glpi-app printenv GLPI_SKIP_AUTOINSTALL
# Deve retornar: true

# Verificar saúde completa
./scripts/healthcheck-all.sh

# Verificar cache Redis ativo
docker compose exec glpi-app \
  /var/www/glpi/bin/console glpi:system:status
```

---

## 10. Configurar renovação automática do certificado

O Caddy renova o certificado automaticamente - nenhuma ação necessária. Para verificar:

```bash
docker compose logs caddy | grep -i "certificate\|tls\|acme"
```

---

## 11. Teardown (evitar custos)

Quando terminar os testes, parar ou encerrar a instância:

```bash
# Parar a stack (volumes preservados)
docker compose down

# Opcional: exportar backup antes de encerrar
./scripts/backup-now.sh
# Copiar backup para local antes de terminar
scp -i ~/.ssh/minha-chave.pem \
  admin@<IP_PUBLICO>:~/glpi-docker-stack/fase_01_glpi_mariadb_caddy/backups/*.gz \
  ~/backups/
```

No Console AWS (ou CLI):

```bash
# Parar a instância (mantém o EBS - cobra ~USD 0,08/GB-mês)
aws ec2 stop-instances --instance-ids <INSTANCE_ID>

# Terminar a instância (destrói tudo - sem custo residual)
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
```

> Se planeja reutilizar: prefira **stop** (preserva o disco). Se foi apenas um teste: **terminate**.

---

## Diferenças vs ambiente local

| Aspecto | Local (PC) | AWS EC2 |
|---|---|---|
| DNS | `/etc/hosts` manual | Registro DNS real |
| TLS | Caddy interno (self-signed ou ACME staging) | Let's Encrypt produção |
| `GLPI_DOMAIN` | `glpi.local` ou `localhost` | `glpi.seu-dominio.com.br` |
| Porta 80/443 | Localhost apenas | Acessível pela internet |
| Custo | Zero | ~USD 0,042/h (t3.medium) |
| IP fixo | Sim | Muda a cada start - usar Elastic IP se precisar de IP fixo |

### Elastic IP (opcional)

Se precisar de IP fixo para o registro DNS:

```bash
# Alocar Elastic IP
aws ec2 allocate-address --domain vpc

# Associar à instância
aws ec2 associate-address \
  --instance-id <INSTANCE_ID> \
  --allocation-id <ALLOCATION_ID>
```

> Elastic IP é gratuito enquanto associado a uma instância rodando. Cobra USD 0,005/h se alocado sem instância.

---

## Troubleshooting

### Certificado TLS não gerado

```bash
docker compose logs caddy | tail -50
# Erros comuns:
# - "no such host" → DNS não propagou ainda
# - "connection refused" → porta 80 bloqueada no Security Group
# - "too many certificates" → atingiu limite do Let's Encrypt (5/semana por domínio)
```

### GLPI inacessível após bootstrap

```bash
# Verificar todos os containers
docker compose ps

# Verificar logs do container com problema
docker compose logs glpi-app | tail -50

# Rodar healthcheck completo
./scripts/healthcheck-all.sh
```

### Erro de memória (OOM)

```bash
sudo dmesg | grep -i "oom\|killed"
# Se houver kills, aumentar mem_limit no .env ou usar instância maior (t3.large)
```
