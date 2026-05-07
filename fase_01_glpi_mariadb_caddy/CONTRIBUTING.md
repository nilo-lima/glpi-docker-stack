# Contribuindo

Contribuições são bem-vindas - relatos de bugs, melhorias na documentação e pull requests com novas funcionalidades ou correções.

---

## Reportando um bug

Abra uma issue e inclua:

- O que você esperava que acontecesse
- O que aconteceu de fato (mensagem de erro, logs do container)
- Seu ambiente: SO, versão do Docker, `docker compose version`
- Qual fase da stack você está executando

```bash
# Informações úteis para anexar à issue
docker compose version
docker version --format '{{.Server.Version}}'
docker compose ps
docker compose logs --tail=50 <nome-do-serviço>
```

---

## Sugerindo uma melhoria

Abra uma issue descrevendo:

- O problema que você quer resolver ou a lacuna que identificou
- A abordagem que você propõe
- Os trade-offs que você está ciente

Para mudanças arquiteturais (novo serviço, alteração de rede, reestruturação de volumes), abra uma issue antes de submeter o PR para alinharmos a abordagem primeiro.

---

## Submetendo um pull request

1. Faça um fork do repositório e crie uma branch a partir de `main`.
2. Aplique suas mudanças seguindo as convenções abaixo.
3. Teste localmente: `./scripts/bootstrap.sh` deve concluir sem erros.
4. Abra o PR com uma descrição clara do quê e do porquê.

---

## Convenções

Estas regras se aplicam a todas as contribuições:

- **Sem tags `:latest` em imagens.** Sempre fixe uma versão específica (ex: `mariadb:11.4`).
- **Um serviço por container.** Não agrupe múltiplos processos.
- **Sem secrets hardcoded.** Todas as credenciais ficam no `.env`; referencie-as como `${VAR}` no `docker-compose.yml`.
- **Todo serviço novo precisa de healthcheck**, política de `restart`, rotação de logs e `cap_drop: ALL`.
- **Preserve os comentários existentes** no `docker-compose.yml` — eles documentam decisões arquiteturais, não apenas configuração.
- **Scripts shell** devem começar com `set -euo pipefail` e ser compatíveis com Bash 4+.

Consulte [`.claude/rules/devops-standards.md`](.claude/rules/devops-standards.md) para o conjunto completo de padrões.

---

## Validação rápida antes de fazer push

```bash
# Valida a config do Compose (detecta erros de sintaxe e variáveis ausentes)
docker compose config

# Sobe a stack completa
./scripts/bootstrap.sh

# Verifica se todos os containers estão saudáveis
./scripts/healthcheck-all.sh

# Testa backup e restore
./scripts/backup-now.sh
./scripts/restore.sh
```

---

## Licença

Ao contribuir, você concorda que suas contribuições serão licenciadas sob a [Licença MIT](LICENSE).
