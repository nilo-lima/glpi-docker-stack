<div align="center">

# 🖥️ GLPI Docker Stack

**Stack production-grade do GLPI 11 construída em fases - do deploy local ao cloud com Terraform.**

![GLPI](https://img.shields.io/badge/GLPI-11.0.7-00A4E4?style=flat-square&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=flat-square&logo=docker&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-12_Bookworm-A81D33?style=flat-square&logo=debian&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)

</div>

---

## Sobre o Projeto

Este repositório documenta a evolução de uma stack Docker production-grade para o **GLPI 11** (Gestionnaire Libre de Parc Informatique), construída incrementalmente em fases.

Cada fase representa um marco funcional independente e validado, do deploy local com TLS automático até a infraestrutura gerenciada na AWS com Terraform.

O projeto segue princípios de **infraestrutura como código**, **defesa em profundidade** e **Single Responsibility** em cada container.

---

## Fases

| Fase | Diretório | Status | Descrição |
|:---:|:---|:---:|:---|
| 1 | [`fase_01_glpi_mariadb_caddy/`](fase_01_glpi_mariadb_caddy/) | ✅ Concluída | Stack base: GLPI 11 + MariaDB + Redis + Caddy (TLS) + Backup agendado |
| 2 | [`fase_02_Observabilidade/`](fase_02_Observabilidade/) | ✅ Concluída | Stack unificada de 14 containers: Fase 1 + Prometheus + Grafana + Loki + Promtail + Alertmanager |
| 3 | `fase_03_AWS_Terraform/` | 🔜 Planejada | VPC, EC2, RDS, ElastiCache, S3, ALB - IaC completo em Terraform |

---

## Fase 1 - Stack Base

6 containers Docker orquestrados por Docker Compose, com hardening aplicado em todos:

| Container | Tecnologia | Função |
|:---|:---|:---|
| `glpi-app` | GLPI 11.0.7 + PHP 8.3 + Apache | Aplicação web |
| `glpi-cron` | GLPI 11.0.7 | Worker dedicado de tarefas agendadas |
| `mariadb` | MariaDB 11.4 | Banco de dados |
| `redis` | Redis 7.4 Alpine | Cache e sessões PHP |
| `caddy` | Caddy 2.8 Alpine | Reverse proxy + TLS automático (Let's Encrypt) |
| `backup` | Alpine 3.20 | Dump diário do banco + arquivos com restore testado |

→ Veja o [README completo da Fase 1](fase_01_glpi_mariadb_caddy/README.md) para instalação, variáveis e operação.

---

## Fase 2 - Observabilidade

Stack unificada de **14 containers**: todos os serviços da Fase 1 + observabilidade completa. Um único `docker compose up -d` entrega GLPI funcional com métricas, dashboards e logs centralizados.

| Container | Tecnologia | Função |
|:---|:---|:---|
| *(6 serviços da Fase 1)* | - | GLPI, banco, cache, proxy, backup |
| `prometheus` | Prometheus v2.55.1 | Coleta e armazena métricas |
| `node-exporter` | node-exporter v1.8.2 | Métricas do host (CPU, RAM, disco) |
| `mysqld-exporter` | mysqld-exporter v0.16.0 | Métricas do MariaDB |
| `redis-exporter` | redis_exporter v1.66.0 | Métricas do Redis |
| `grafana` | Grafana 11.4.0 | Dashboards - acessado via Caddy com TLS |
| `loki` | Loki 3.3.2 | Agregação e armazenamento de logs |
| `promtail` | Promtail 3.3.2 | Coleta logs de todos os containers |
| `alertmanager` | Alertmanager v0.27.0 | Roteamento de alertas |

→ Veja o [README completo da Fase 2](fase_02_Observabilidade/README.md) para instalação, variáveis e operação.

---

## Estrutura do Repositório

```
.
├── fase_01_glpi_mariadb_caddy/   # Stack base (concluída)
├── fase_02_Observabilidade/      # Observabilidade (concluída)
├── fase_03_AWS_Terraform/        # AWS + IaC (planejada)
└── .github/
    └── ISSUE_TEMPLATE/           # Templates de bug report e feature request
```

Cada fase contém seu próprio `docker-compose.yml`, `README.md`, `.env.example` e scripts de automação.

---

## Como Contribuir

Veja [CONTRIBUTING.md](fase_01_glpi_mariadb_caddy/CONTRIBUTING.md) para as convenções do projeto.

---

## Licença

Distribuído sob a licença **MIT**. Veja [LICENSE](LICENSE) para mais informações.

GLPI é distribuído sob **GPL-3.0** - ver [glpi-project.org](https://www.glpi-project.org).
