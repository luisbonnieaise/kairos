# 06 · Runbook de Deploy & Go-Live

Operação. Use como **checklist final**. Algumas seções são preenchidas/expandidas pelos prompts das fases anteriores (indicado). Não faça go-live de pagamento com qualquer item ☐ pendente.

---

## 1. Ordem de deploy

```
1. SQL (SQL Editor do Supabase, NA ORDEM):
   01_profiles → 02_mensagens → 03_praticas → 04_reflexoes →
   05_relatorios_semanais → 06_storage_avatares → 07_uso_ia →
   08_subscriptions → 09_cron_relatorios → 10_indices_revisao
   (todos idempotentes; rodar de novo não quebra)
2. Secrets das Edge Functions (seção 2) ANTES de deployar funções.
3. Deploy das Edge Functions (seção 3).
4. Configuração Stripe (seção 4) + Supabase Auth (seção 5).
5. Build do app apontando para o .env de produção.
6. Validações (seção 7) → só então abrir tráfego.
```

---

## 2. Matriz de secrets

Edge Function secrets (`supabase secrets set ...` ou painel):

| Secret | Obrigatório p/ | Origem |
|---|---|---|
| `ANTHROPIC_API_KEY` | mentor-chat, relatorio-semanal | Anthropic Console |
| `STRIPE_SECRET_KEY` | stripe-checkout, stripe-webhook | Stripe (modo live no go-live) |
| `STRIPE_WEBHOOK_SECRET` | stripe-webhook | Stripe → endpoint do webhook |
| `STRIPE_PRICE_PREMIUM` | stripe-checkout | ID do `price` recorrente |
| `SUPABASE_SERVICE_ROLE_KEY` | webhook, gating, cron | Supabase (auto/painel) |
| `CRON_SECRET` | relatorio-semanal (cron) | gerar string aleatória forte |

App `.env` (somente públicos): `SUPABASE_URL`, `SUPABASE_KEY` (anon). **Nunca** colocar os de cima no `.env`/bundle.

---

## 3. Deploy das Edge Functions

```bash
supabase functions deploy mentor-chat
supabase functions deploy relatorio-semanal
supabase functions deploy stripe-checkout
supabase functions deploy stripe-webhook --no-verify-jwt   # <- obrigatório
```

> `stripe-webhook` **precisa** de `--no-verify-jwt` (Stripe não envia JWT Supabase; a segurança é a verificação de assinatura). As demais ficam com verify-jwt padrão.

---

## 4. Configuração Stripe (painel)

- [ ] Produto "Kairo Premium" + `price` recorrente (mensal; anual opcional). Copiar price id → `STRIPE_PRICE_PREMIUM`.
- [ ] Webhook endpoint → URL pública de `stripe-webhook`. Eventos: `checkout.session.completed`, `customer.subscription.created|updated|deleted`, `invoice.payment_failed`. Copiar signing secret → `STRIPE_WEBHOOK_SECRET`.
- [ ] Customer Portal habilitado (se a 3.5 implementar portal).
- [ ] Esquema de deep link de retorno (success/cancel) — **preencher aqui o esquema escolhido na 3.6:** `__________`.
- [ ] Trocar chaves test → live no go-live; refazer webhook secret no modo live.

### Validação Stripe (roteiro — preenchido pelo PROMPT 3.7)

- [ ] `stripe listen --forward-to <url stripe-webhook>` + `stripe trigger ...`
- [ ] Reenviar mesmo evento 2x → 1 linha em `stripe_events`, estado correto.
- [ ] `updated` e `deleted` quase juntos → converge ao estado real (re-fetch).

---

## 5. Supabase Auth (painel) — preenchido pelo PROMPT 2.3

- [ ] Confirmação de e-mail: decisão registrada → **LIGADA / DESLIGADA:** `____` (fluxo 2.1 cobre ambos).
- [ ] Leaked password protection (HaveIBeenPwned) **ligado**.
- [ ] Site URL + Redirect URLs (deep link de reset/confirmação) corretos.
- [ ] Rate limits de Auth revisados para 30k MAUs.

---

## 6. Cron — preenchido pelo PROMPT 4.1

- [ ] `pg_cron`/`pg_net` habilitados; `09_cron_relatorios.sql` aplicado.
- [ ] `CRON_SECRET` setado nos secrets e usado pela função SQL de enfileiramento.
- [ ] Horário/fuso do job definido: `__________`.
- [ ] Execução manual de teste validada (gerou cartas, idempotente, espalhada).

---

## 7. Validações pré-go-live (gate final)

Segurança/custo (Fase 01):
- [ ] Não-premium não consegue Sonnet (forçar flag → resposta Haiku).
- [ ] Rate limit não burlável (cliente que não salva mensagem ainda é limitado).
- [ ] `relatorio-semanal` rejeita data futura/arbitrária.
- [ ] Erros não vazam objetos de terceiros ao client.

Billing (Fase 03):
- [ ] Checkout → pagamento test → webhook → `subscriptions.status=active` → Mentor passa a Sonnet.
- [ ] Cancelamento/expiração via webhook → volta a Haiku automaticamente.
- [ ] Webhook idempotente e tolerante a fora-de-ordem (roteiro seção 4).
- [ ] `subscriptions` não escrevível pelo client (tentar UPDATE autenticado → negado por RLS).

Escala (Fase 04):
- [ ] Carta semanal só via cron espalhado; índices auditados.
- [ ] `docs/observabilidade.md` com queries de uso/custo.
- [ ] Plano Supabase adequado a 30k MAUs (seção 8).

Qualidade (Fase 05):
- [ ] CI verde (`flutter analyze`/`test`, `deno test`).
- [ ] `supabase/.temp/` fora do git; README real.

---

## 8. Capacidade Supabase (30k MAUs) — preenchido pelo PROMPT 4.4

- [ ] Plano Pro/Team confirmado (Edge invocations, DB size, egress, auth MAU).
- [ ] Acesso via PostgREST/REST nas Edge Functions (sem conexões diretas persistentes) — verificado.
- [ ] Limpeza de objetos de Storage ao deletar conta documentada/agendada.
- [ ] Backups/PITR habilitados.

---

## 9. Alertas de custo

> O código da Fase 01 fecha os vetores de custo *no app* (modelo server-side,
> rate limit não-burlável via `uso_ia`, validação de `semana_inicio`). Esta
> seção é a rede de segurança *fora do app*: limites de gasto nos provedores,
> para o caso de um vetor não previsto. Itens não-código — o dono preenche os
> alvos e marca como feito.

**Limite mensal alvo (a definir pelo dono):** `____ USD/mês` (Anthropic) ·
`____ USD/mês` (Supabase). Defina antes de abrir ao público.

- [ ] **Anthropic Console → Billing → Usage limits / Spend alerts:** definir
      limite de gasto mensal igual ao alvo acima e alerta em ~50% e ~80%.
      (https://console.anthropic.com/settings/billing)
- [ ] **Anthropic → Billing → Usage:** revisar semanalmente o consumo por
      modelo (Haiku vs. Sonnet) e cruzar com a tabela `uso_ia` (mesma contagem
      que o rate limit usa) para detectar divergência/abuso.
- [ ] **Supabase → Organization → Billing → Spend cap:** ativar spend cap e
      configurar alerta de uso de Edge Functions (invocações) e do banco.
- [ ] **Supabase → Reports/Logs:** alerta para pico anômalo de invocações de
      `mentor-chat` / `relatorio-semanal` (proxy de tentativa de abuso).
- [ ] **Stripe → alertas** de falha de pagamento / disputas (relevante a
      partir da Fase 03).
- [ ] Alerta de erro do `stripe-webhook` acima de limiar (Fase 04
      observabilidade).
- [ ] Runbook de estouro: ver §10 "Custo de IA disparando" (desligar Sonnet,
      reduzir rate limits, investigar `uso_ia`).

---

## 10. Rollback

| Cenário | Ação |
|---|---|
| Webhook com bug pós-deploy | Re-deploy versão anterior da função; Stripe re-tenta eventos não-ack — backlog é reprocessado idempotentemente |
| Custo de IA disparando | Desligar Sonnet (forçar Haiku no `mentor-chat` via flag de env) + reduzir rate limits; investigar `uso_ia` |
| Cron gerando custo excessivo | `cron.unschedule(...)` do job de relatórios; geração volta ao modo manual (com rate limit) |
| Schema problemático | Scripts são idempotentes e aditivos; reverter via migração corretiva nova (não dropar dados de usuário) |
| Stripe em modo errado (test/live) | Trocar `STRIPE_SECRET_KEY`/`STRIPE_WEBHOOK_SECRET`; recriar webhook endpoint no modo correto |

> Princípio: schema é **aditivo e idempotente**; nunca dropar tabela de usuário em rollback. Funções têm versionamento de deploy no Supabase — rollback é re-deploy.

---

Fim da documentação. Volte ao [índice](README.md) para acompanhar o status das fases.
