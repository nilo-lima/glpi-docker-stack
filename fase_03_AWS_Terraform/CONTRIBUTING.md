# Contribuindo - Fase 3

## Antes de qualquer mudanca

1. Crie uma branch: `git checkout -b feat/descricao-da-mudanca`
2. Nunca trabalhe direto na `main`

## Padroes Terraform

### Formatacao

```bash
# Sempre antes de commitar
terraform fmt -recursive
terraform validate
```

### Versoes

- **Nunca** remova constraints de versao em `versions.tf`
- Bump de versao = commit explicito com o changelog relevante

### Novos recursos

Todo novo recurso AWS deve ter:
- Comentario explicando o proposito (por que existe, nao so o que e)
- `tags = merge(var.common_tags, { Name = "..." })`
- Documentacao atualizada em `docs/ARCHITECTURE.md`

### Novos modulos

Estrutura obrigatoria:
```
modules/novo-modulo/
├── main.tf       # Recursos
├── variables.tf  # Inputs com description + validation quando aplicavel
└── outputs.tf    # Outputs com description clara
```

## Seguranca

- Senhas SEMPRE como `sensitive = true`
- NUNCA hardcode de segredos em `.tf` ou no user_data sem `sensitive`
- SSH (porta 22) NUNCA aberto para `0.0.0.0/0` (o modulo `security_groups` valida isso)
- `terraform plan` antes de todo `terraform apply` em producao

## Documentacao

- Caractere em dash (U+2014) proibido em toda documentacao. Use hifen (-).
- Cada ADR novo vai em `docs/ARCHITECTURE.md`
- Mudancas operacionais vao em `docs/RUNBOOK.md`

## Processo de mudanca

1. `terraform plan -out=mudanca.tfplan`
2. Revisar o plan (especialmente recursos marcados como "destroy")
3. `terraform apply mudanca.tfplan`
4. Verificar outputs e saude da infraestrutura
5. Commitar mudancas nos `.tf` files

## Convencoes de commit

```
feat: adiciona modulo alb para terminacao TLS
fix: corrige cidr da subnet privada
docs: atualiza ADR sobre escolha EC2 vs ECS
chore: bump aws provider 5.0 -> 5.80
```
