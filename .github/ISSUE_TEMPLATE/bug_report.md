---
name: Relato de bug
about: Informe um problema para nos ajudar a melhorar
title: '[BUG] '
labels: bug
assignees: ''
---

## Descrição

Descreva o problema de forma clara e objetiva.

## Como reproduzir

Passos para reproduzir o comportamento:

1. Execute `...`
2. Observe o erro `...`

## Comportamento esperado

O que deveria acontecer.

## Comportamento atual

O que acontece de fato. Cole a mensagem de erro completa ou os logs relevantes.

## Ambiente

```bash
# Cole a saída dos comandos abaixo
docker compose version
docker version --format '{{.Server.Version}}'
uname -a
```

## Fase e serviço afetado

- [ ] Fase 1 — `glpi-app`
- [ ] Fase 1 — `glpi-cron`
- [ ] Fase 1 — `mariadb`
- [ ] Fase 1 — `redis`
- [ ] Fase 1 — `caddy`
- [ ] Fase 1 — `backup`
- [ ] Fase 2
- [ ] Fase 3
- [ ] Outro

## Logs relevantes

```
Cole aqui a saída de: docker compose logs --tail=50 <serviço>
```

## Informações adicionais

Qualquer contexto adicional que possa ajudar na investigação.
