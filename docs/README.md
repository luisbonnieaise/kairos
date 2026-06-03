# Kairo · Documentação de Implementação

> Plano de execução para levar o Kairo de "base sólida" a **produto pronto, seguro e pago, suportando 30.000 MAUs** com pagamentos Stripe em tempo real.

Esta documentação é **executável**: cada fase tem objetivo, contexto, arquivos afetados, passo a passo e **prompts prontos** para colar no agente de implementação (Claude Code), na ordem. Cada prompt termina com critérios de aceitação verificáveis.

---

## Como usar

1. Leia [`00-visao-arquitetura.md`](00-visao-arquitetura.md) **uma vez** — ele define o alvo e o modelo de dados de billing. Tudo depende dele.
2. Execute as fases **na ordem do índice**. Não pule a Fase 1 — ela contém bloqueadores de custo.
3. Para cada fase: cole os prompts um a um. Só avance ao próximo prompt quando os critérios de aceitação do anterior passarem.
4. Marque o status na tabela abaixo conforme avança.
5. Ao terminar tudo, rode o [`06-runbook-deploy.md`](06-runbook-deploy.md) como checklist de go-live.

> **Regra de ouro:** nenhum prompt deve introduzir segredo no client nem confiar em valor enviado pelo cliente para decisões de custo, modelo de IA ou nível de assinatura. Toda decisão de dinheiro/poder acontece no servidor.

---

## Índice

| # | Documento | Objetivo | Prioridade | Status |
|---|---|---|---|---|
| 00 | [Visão & Arquitetura](00-visao-arquitetura.md) | Arquitetura alvo, modelo de dados de billing, princípios de concorrência | Base | ☐ |
| 01 | [P0 — Custo & Segurança](01-p0-custo-seguranca.md) | Fechar os 3 vetores de abuso de API + alertas de custo | 🔴 P0 | ☐ |
| 02 | [P1 — Hardening de Lançamento](02-p1-hardening.md) | Fluxo de e-mail, política de senha, vazamento de erro | 🟡 P1 | ☐ |
| 03 | [Stripe — Billing & Premium](03-stripe-billing.md) | Assinatura Kairo Premium, checkout, webhook idempotente, gating server-side | 🔴 P0 | ☐ |
| 04 | [Escala para 30k MAUs](04-escala-30k.md) | Índices, carta semanal via cron, observabilidade, modelo de custo | 🟡 P1 | ☐ |
| 05 | [Qualidade & Testes](05-qualidade-testes.md) | Testes da lógica crítica, CI, README, higiene de repo | 🟢 P2 | ☐ |
| 06 | [Runbook de Deploy & Go-Live](06-runbook-deploy.md) | Matriz de secrets, ordem de deploy, checklist final, rollback | Operação | ☐ |
| 07 | [Billing Multiplataforma](07-billing-multiplataforma.md) | **Spec vigente:** Stripe (web) + Apple IAP + Google Play, entitlement único, 3 webhooks idempotentes, conformidade | 🔴 P0 | ☐ |
| 08 | [Guia de Consoles (Luis)](08-guia-consoles-luis.md) | Passo a passo nos painéis Stripe/Apple/Google/Supabase: produtos, API keys, webhooks/eventos, matriz de secrets | Operação | ☐ |

---

## Ordem de execução recomendada

```
00 (ler)
 └─> 01 (P0: blinda custo de IA)         ─┐
 └─> 07 (Billing multiplataforma)         ├─ podem ser feitas em paralelo por 2 pessoas
      (07 depende de 01 para o gating)   ─┘   (07 SUBSTITUI a parte de checkout da 03)
 └─> 08 (Luis configura os consoles — pré-requisito p/ validar os webhooks da 07)
 └─> 02 (P1: hardening de auth/erros)
 └─> 04 (escala: cron, índices, observabilidade)
 └─> 05 (testes + higiene)
 └─> 06 (deploy + go-live checklist)
```

**Dependência dura:** o gating de modelo Sonnet reusa o ponto de decisão server-side criado na Fase 01. Faça a 01 antes da parte de gating da 07. **O doc 03 foi parcialmente substituído pela Fase 07** (billing multiplataforma); siga a 07 como spec vigente e use a 03 apenas como referência dos princípios de concorrência/idempotência.

---

## Convenções dos prompts

- `PROMPT N.M` — colar literalmente no agente. Já contém o contexto necessário.
- Blocos `Critérios de aceitação` — checklist objetivo. Se algum falhar, **não avance**.
- Caminhos sempre relativos à raiz do repositório (`c:\dev\kairo`).
- Idioma de código/commits: igual ao existente (português nos identificadores de domínio, inglês nos prompts de sistema do Claude).

---

## Glossário

| Termo | Significado |
|---|---|
| **MAU** | Monthly Active Users — meta de 30.000 |
| **P0/P1/P2** | Prioridade: P0 bloqueia escala/lançamento; P1 antes do público; P2 higiene |
| **Edge Function** | Função Deno no Supabase (`supabase/functions/`) |
| **RLS** | Row Level Security do Postgres |
| **Gating** | Decisão server-side que libera/bloqueia recurso conforme assinatura |
| **Idempotência** | Processar o mesmo evento N vezes = mesmo efeito de processar 1 vez |

