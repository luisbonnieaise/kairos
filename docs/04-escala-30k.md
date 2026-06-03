# 04 · Escala para 30.000 MAUs

**Prioridade 🟡 P1.** Garante que dados, IA e billing aguentem 30k MAUs com custo previsível. Foco em: matar o burst de domingo, validar índices, escalar a infra Supabase e ter observabilidade.

Pré-requisitos: Fases 01 e 03 concluídas.

---

## 1. Dimensionamento (premissas a validar com o dono)

| Variável | Estimativa | Impacto |
|---|---|---|
| MAUs | 30.000 | base |
| Conversas Mentor/usuário/mês | ~20 msgs | custo Haiku/Sonnet |
| % Premium | a definir (ex. 5%) | só Premium usa Sonnet (caro) |
| Cartas semanais | até 30k/semana | **maior risco de custo/burst** |
| Webhooks Stripe | picos em renovações mensais | concorrência (coberta na Fase 03) |

Custo de IA escala com **cartas semanais** e **% Premium**. Tudo já tem teto pós-Fase 01 (rate limits + gating). Esta fase remove o burst e dá visibilidade.

---

## PROMPT 4.1 — Carta semanal via cron (mata o burst de domingo)

```
Hoje relatorio-semanal é chamada on-demand pelo client (banco.dart
BancoRelatorios.gerar), o que concentra chamadas Sonnet no domingo e abre o
vetor de data arbitrária (mitigado, não eliminado, na Fase 01).

Implemente geração agendada e idempotente:

1. Adicione à função supabase/functions/relatorio-semanal/index.ts um MODO
   CRON além do modo usuário:
   - Se o header 'x-cron-secret' == Deno.env.get('CRON_SECRET'), a função
     opera em lote: aceita { user_id, semana_inicio } no corpo e gera a
     carta daquele usuário usando client SERVICE ROLE (sem JWT de usuário),
     mantendo a MESMA idempotência por (user_id, semana_inicio).
   - Modo usuário (JWT) continua existindo como fallback manual, mas com o
     rate limit da Fase 01.

2. Crie scripts/09_cron_relatorios.sql:
   - Habilite pg_cron e pg_net (se ainda não).
   - Crie uma função public.enfileirar_relatorios_semanais() que, no fuso
     alvo, para cada usuário com atividade na semana, chama via net.http_post
     a Edge Function relatorio-semanal com o header x-cron-secret e o
     payload { user_id, semana_inicio }. Espalhe as chamadas ao longo de
     uma janela (ex.: lotes a cada minuto) para NÃO estourar rate limit da
     Anthropic nem a concorrência da função — documente a estratégia de
     espalhamento em comentário.
   - Agende com cron.schedule para rodar no domingo (definir horário/fuso;
     deixar configurável e documentado).
   - Idempotente (create if not exists, unschedule+schedule).

3. Documente em docs/06-runbook-deploy.md (seção "Cron") como setar
   CRON_SECRET e validar uma execução manual.

Não remova a possibilidade de o usuário ver a carta no app — apenas a
GERAÇÃO migra para o cron; a leitura continua via RLS.
```

**Critérios de aceitação**
- [ ] Modo cron exige `x-cron-secret`; sem ele, comportamento de usuário inalterado.
- [ ] Geração em lote idempotente: rodar o cron 2x não duplica cartas nem chama Claude de novo para semana já gerada.
- [ ] Chamadas espalhadas (não 30k simultâneas) — estratégia documentada.
- [ ] `scripts/09_cron_relatorios.sql` idempotente; README de scripts atualizado (passo 9).

---

## PROMPT 4.2 — Auditoria de índices e consultas

```
Audite as consultas de lib/core/banco.dart e das Edge Functions contra os
índices existentes (scripts 01–09). Para cada query quente, confirme que há
índice cobrindo o filtro/ordenação:

- mensagens: (user_id, created_at desc) — ok? a contagem de rate limit usa
  role; avalie índice parcial WHERE role='user' se a Fase 01 ainda contar
  mensagens em algum caminho (não deveria — confirme que migrou p/ uso_ia).
- pratica_completadas: (user_id, data) e (pratica_id, data) — confirmar uso
  em ultimos7Dias / completadasHoje.
- reflexoes: (user_id, created_at desc).
- relatorios_semanais: (user_id, semana_inicio desc) + unique
  (user_id, semana_inicio).
- subscriptions: (stripe_customer_id), (stripe_subscription_id).
- uso_ia: (user_id, funcao, created_at desc).

Entregue um arquivo scripts/10_indices_revisao.sql APENAS com
CREATE INDEX IF NOT EXISTS para índices faltantes que você identificou
(idempotente). Se nada faltar, crie o arquivo com um comentário explicando
que a auditoria não encontrou índice ausente. Não altere tabelas.
```

**Critérios de aceitação**
- [ ] Relatório textual no PR: cada query quente mapeada a um índice.
- [ ] `scripts/10_indices_revisao.sql` idempotente (ou documentando "nada faltante").
- [ ] Nenhum full-scan previsto nos caminhos de usuário com 30k MAUs.

---

## PROMPT 4.3 — Observabilidade e tetos de custo

```
Crie docs/observabilidade.md com:
- Métricas a acompanhar: chamadas/dia por funcao em public.uso_ia
  (query SQL pronta), nº de assinaturas ativas (subscriptions), taxa de erro
  de Edge Functions, latência do webhook.
- Queries SQL prontas para dashboard (uso_ia por dia/modelo; receita
  aproximada por assinaturas ativas).
- Limiares de alerta sugeridos (ex.: gasto Anthropic > X/dia, erro webhook
  > Y%).
- Ponteiro para os alertas de billing do runbook (Fase 01 §1.6 e Fase 06).
Apenas documentação + SQL de consulta (não cria objetos).
```

**Critérios de aceitação**
- [ ] `docs/observabilidade.md` com queries executáveis e limiares.

---

## PROMPT 4.4 — Plano de capacidade Supabase (documentar)

```
Adicione em docs/06-runbook-deploy.md uma seção "Capacidade Supabase (30k
MAUs)":
- Plano necessário (Pro/Team) e por quê (Edge Function invocations, DB size,
  egress, auth MAU).
- Connection pooling: confirmar que o acesso é via PostgREST/REST (sem
  conexões diretas persistentes nas Edge Functions) — registrar como
  verificado.
- Storage do bucket de avatar: política de tamanho/limpeza ao deletar conta
  (cascade já cobre linhas; objetos de Storage precisam de limpeza —
  documentar tarefa).
- Backups/PITR habilitados.
Somente documentação.
```

**Critérios de aceitação**
- [ ] Seção de capacidade com plano, pooling, storage e backups registrados.

---

## Resultado da fase

Burst de domingo eliminado (cron espalhado e idempotente), índices auditados para 30k MAUs, observabilidade e plano de capacidade documentados. Custo de IA agora é previsível e monitorável.

Próximo: [`05-qualidade-testes.md`](05-qualidade-testes.md).

