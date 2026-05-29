# Bootstrap - Pre-requisitos do Backend Terraform

Este diretorio cria a infraestrutura necessaria ANTES de inicializar o modulo principal.

## O que e criado

| Recurso | Nome | Proposito |
|---|---|---|
| S3 Bucket | `glpi-fase3-tfstate-<account_id>` | Armazena o `terraform.tfstate` remotamente |
| DynamoDB Table | `glpi-fase3-terraform-locks` | Previne applies concorrentes (state locking) |

## Por que bootstrap separado?

O Terraform nao pode usar o S3 como backend antes de o bucket existir. Portanto:
1. Este diretorio usa backend LOCAL (state fica em `bootstrap/terraform.tfstate`)
2. Apos o apply, o modulo principal usa backend S3

O `bootstrap/terraform.tfstate` e gerado localmente. Faca backup dele ou nao o destrua
sem querer - e o unico registro de que o S3 bucket foi criado pelo Terraform.

## Como executar (UMA VEZ por ambiente)

```bash
cd bootstrap/

# Inicializa com backend local (padrao)
terraform init

# Revisa o que sera criado (S3 + DynamoDB)
terraform plan

# Cria os recursos (leva ~30 segundos)
terraform apply

# Anota os outputs
terraform output
```

## Apos o apply

1. Copie o `backend_config_snippet` do output para o bloco `terraform {}` em `../main.tf`
2. Volte para o diretorio principal e inicialize com o backend remoto:

```bash
cd ..
terraform init
# Terraform perguntara se deseja copiar o state existente (nao ha state ainda)
```

## Destruir (cuidado)

O bucket tem `prevent_destroy = true`. Para destruir:
1. Edite `main.tf` e mude `prevent_destroy = false`
2. `terraform apply` (apenas atualiza o lifecycle, nao destroi nada)
3. Certifique-se de que o bucket esta vazio (estados sao objetos S3)
4. `terraform destroy`
