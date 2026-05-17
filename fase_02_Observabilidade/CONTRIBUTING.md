# Contribuindo

Contribuições são bem-vindas — relatos de bugs, melhorias na documentação e pull requests com novas funcionalidades ou correções.

---

## Reportando um bug

Abra uma issue e inclua:

- O que você esperava que acontecesse
- O que aconteceu de fato (mensagem de erro, logs do container)
- Seu ambiente: SO, versão do Docker, `docker compose version`

```bash
# Informações úteis para anexar à issue
docker compose version
docker version --format '{{.Server.Version}}'
docker compose ps
docker compose logs --tail=50 <nome-do-serviço>

# Para problemas de observabilidade, inclua também:
docker exec glpi-dev-prometheus wget -qO- \
  http://localhost:9090/api/v1/targets | python3 -m json.tool
docker exec glpi-dev-loki wget -qO- \
  http://localhost:3100/loki/api/v1/labels | python3 -m json.tool
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
3. Teste localmente: `docker compose up -d` deve concluir com todos os containers healthy.
4. Abra o PR com uma descrição clara do quê e do porquê.

---

## Convenções

### Docker e Compose

- **Sem tags `:latest` em imagens.** Sempre fixe uma versão específica.
- **Um serviço por container.** Não agrupe múltiplos processos.
- **Sem secrets hardcoded.** Credenciais ficam no `.env`; referencie como `${VAR}`.
- **Todo serviço novo precisa de healthcheck**, `restart: unless-stopped`, rotação de logs e `cap_drop: ALL`.
- **Preserve os comentários** no `docker-compose.yml` — documentam decisões, não apenas configuração.
- **Todo novo serviço precisa estar em pelo menos uma das redes** (`frontend_net`, `backend_net`, `monitoring_net`). Justifique a escolha.

### Scripts shell

- Começar com `set -euo pipefail` e ser compatíveis com Bash 4+.
- Variáveis de ambiente carregadas via `source .env` — não hardcode.

### Prometheus / Grafana

- Novas regras de alerta em `services/prometheus/config/alerts/`.
- Novos dashboards como arquivos JSON em `services/grafana/provisioning/dashboards/`.
- Substitua variáveis de template (`${DS_PROMETHEUS}`, `${DS_LOKI}`) pelos UIDs reais antes de commitar.

### Documentação

- Atualize `docs/ARCHITECTURE.md` ao adicionar ou remover serviços.
- Decisões não óbvias merecem um ADR na seção correspondente da arquitetura.

---

## Validação rápida antes de fazer push

```bash
# Valida sintaxe do Compose
docker compose config --quiet && echo "OK"

# Sobe a stack e aguarda
docker compose up -d
sleep 30
docker compose ps   # todos devem ser healthy

# Healthcheck completo
./scripts/healthcheck-all.sh

# Targets Prometheus
docker exec glpi-dev-prometheus wget -qO- \
  "http://localhost:9090/api/v1/targets" | \
  python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d['data']['activeTargets']:
    h = t['health']
    j = t['labels'].get('job', '?')
    print(f'[{h}] {j}')
    assert h == 'up', f'Target {j} não está UP'
print('Todos os targets UP.')
"

# Labels Loki
docker exec glpi-dev-loki wget -qO- \
  "http://localhost:3100/loki/api/v1/label/job/values" | \
  python3 -c "
import json, sys
d = json.load(sys.stdin)
print('Jobs no Loki:', d['data'])
assert len(d['data']) > 0, 'Nenhum log no Loki'
"
```

---

## Licença

Ao contribuir, você concorda que suas contribuições serão licenciadas sob a [Licença MIT](LICENSE).
