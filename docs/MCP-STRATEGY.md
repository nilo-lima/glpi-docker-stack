# 🔌 Estratégia de MCPs

> Análise crítica de quais MCPs valem a pena para este projeto e **quando** ativá-los.
> Princípio: **MCP só agrega quando dá ao Claude acesso a algo que ele não tem por padrão e que você vai usar de verdade.**

---

## Filosofia

Claude Code já vem com capacidades nativas:
- **Bash** — pode rodar `docker compose ps`, `docker logs`, `kubectl`, `terraform plan`, etc.
- **File read/write/edit** — manipula arquivos diretamente
- **Web search/fetch** — busca informações públicas

Um MCP só vale se traz uma das três coisas:

1. **Acesso a estado em tempo real** que não é exposto via shell (ex: API do GitHub, Terraform Registry)
2. **Operações estruturadas** que seriam frágeis via shell scripting (ex: parsing de JSON complexo da AWS)
3. **Sandboxing/segurança** (ex: rodar SQL contra um banco com permissões limitadas)

Se um MCP só "embala" o que `bash` já faz, é **overhead** — consome contexto do Claude, expõe superfície de ataque, e atrapalha mais do que ajuda.

---

## Análise por MCP

### ✅ Vale a pena — quando chegarmos lá

#### `hashicorp/terraform-mcp-server` (Fase 3)
- **O que faz:** consulta a Terraform Registry em tempo real (versões atuais de providers, módulos validados, schema correto)
- **Por que vale:** sem ele, o Claude gera Terraform com versões obsoletas (training cutoff). Problema real e documentado.
- **Quando ativar:** ao iniciar a Fase 3 (migração para AWS)
- **Riscos:** baixo — read-only por padrão. Para HCP Terraform Cloud, requer `TFE_TOKEN` (escopar permissions com cuidado).
- **Como instalar:**
  ```bash
  claude mcp add terraform -s project -- \
    docker run -i --rm hashicorp/terraform-mcp-server:0.3.0
  ```

#### `github/github-mcp-server` (quando criar CI/CD)
- **O que faz:** ler/criar issues, PRs, releases; ler GitHub Actions logs
- **Por que vale:** permite que o Claude opere no fluxo de PR/issue sem você sair do terminal. Útil para automação de releases.
- **Quando ativar:** quando criar GitHub Actions para o projeto (build/test do Dockerfile do backup, lint do compose, etc.)
- **Riscos:** **médios** — requer Personal Access Token. Use **fine-grained PAT** com escopo restrito ao repo do projeto.
- **Como instalar:**
  ```bash
  claude mcp add github -s project -- \
    docker run -i --rm \
    -e GITHUB_PERSONAL_ACCESS_TOKEN=$GH_TOKEN \
    ghcr.io/github/github-mcp-server
  ```

---

### ⚠️ Pode considerar — depende do estilo de operação

#### `ckreiling/mcp-server-docker` ou `QuantGeekDev/docker-mcp`
- **O que fazem:** gerenciamento de containers via linguagem natural
- **Análise:** Claude Code já faz tudo isso via `bash`. Os MCPs Docker fazem sentido para **Claude Desktop** (que não tem bash). Para Claude Code rodando ao lado da sua stack, é redundante.
- **Veredicto:** ❌ pular para o nosso caso.

---

### ❌ NÃO recomendados (apesar do hype na comunidade)

#### AWS MCP Servers (45+) da awslabs
- **Por que não:** A maioria duplica `aws-cli` (que o Claude usa via bash). Adicionar 45 MCPs polui o contexto e cria confusão.
- **Quando reconsiderar:** se decidir que o Claude vai operar a conta AWS de forma autônoma (não recomendado em produção sem revisão humana).
- **Se for usar:** ative **apenas os 2–3 que realmente importam** (ex: `cost-analysis-mcp-server` para análise de custos, `iam-mcp-server` para revisão de policies).

#### Docker MCP Toolkit (Docker Desktop)
- **Por que não:** o servidor de produção é Debian on-premise, não Docker Desktop.
- **Onde faz sentido:** seu workstation pessoal de desenvolvimento, **não** o servidor de produção.

#### Filesystem MCP / Terminal MCP
- **Por que não:** Claude Code já tem isso nativo. Redundância 100%.

---

## Configuração no projeto

Quando ativarmos algum MCP, ele será adicionado em `.mcp.json` na raiz do projeto, **versionado** no git. Secrets (tokens) ficam em `.claude/settings.local.json`, **gitignored**.

Estrutura esperada quando MCPs forem ativados:

```json
{
  "mcpServers": {
    "terraform": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "hashicorp/terraform-mcp-server:0.3.0"]
    }
  }
}
```

E em `.claude/settings.local.json` (gitignored):

```json
{
  "env": {
    "TFE_TOKEN": "seu-token-aqui",
    "GITHUB_PERSONAL_ACCESS_TOKEN": "seu-pat-aqui"
  }
}
```

---

## Decisão atual (Fase 1)

**Nenhum MCP ativo.** O bash do Claude Code resolve 100% das operações desta fase:
- `docker compose ps/logs/exec/up/down`
- Edição de arquivos do projeto
- Execução dos scripts em `scripts/`

Adicionar MCPs agora seria sobrecarga sem benefício.

---

## Resumo executivo

| Fase | MCPs ativos | Justificativa |
|---|---|---|
| **Fase 1** (atual) | nenhum | bash basta |
| **Fase 2** (Observabilidade) | nenhum (provavelmente) | bash + curl resolvem; talvez `prometheus-mcp` se quiser fazer queries PromQL via Claude |
| **Fase 3** (AWS) | `terraform-mcp-server`, eventualmente `github-mcp-server` | versões atuais do Terraform Registry e operação no fluxo de PR |
