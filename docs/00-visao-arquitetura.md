# 00 · Visão & Arquitetura Alvo

Documento base. Define **para onde** vamos antes de qualquer prompt. Não contém prompts — é referência citada por todas as fases.

---

## 1. O produto

Kairo é um app de evolução pessoal (Flutter + Supabase) com IA (Claude). Hoje é gratuito e tem 3 vetores de custo de IA sem teto. O alvo:

- **Freemium pago via Stripe**: nível Grátis (Haiku, limites baixos) + **Kairo Premium** (Sonnet no Mentor, carta semanal garantida, sem limite prático).
- **Suportar 30k MAUs** com pagamentos e webhooks concorrentes em tempo real.
- Custo de IA **previsível e blindado** contra abuso.

---

## 2. Arquitetura alvo (texto)

```
Flutter App ──auth JWT──> Supabase
   │                        ├─ Postgres + RLS (dados do usuário)
   │                        ├─ Storage (avatar)
   │                        └─ Edge Functions (Deno):
   │                             ├─ mentor-chat        (JWT do usuário)
   │                             ├─ relatorio-semanal  (JWT do usuário OU cron)
   │                             ├─ stripe-checkout    (JWT do usuário)
   │                             └─ stripe-webhook     (SEM JWT — assinatura Stripe)
   │
   ├──checkout url──> Stripe Checkout (hospedado pela Stripe)
   │
Stripe ──webhook events──> stripe-webhook ──service role──> Postgres (subscriptions)
```

**Princípio central:** o client é não-confiável. Modelo de IA, limite de uso e nível de assinatura são **sempre** decididos por uma Edge Function consultando o Postgres — nunca por flag enviada pelo app.

---

## 3. Modelo de dados de billing (alvo)

Duas tabelas novas. Schema completo é entregue na Fase 03; aqui fica o contrato que as outras fases assumem.

### 3.1 `public.subscriptions` — estado canônico da assinatura

| Coluna | Tipo | Notas |
|---|---|---|
| `user_id` | uuid PK | FK `auth.users(id)` on delete cascade. **1 linha por usuário** |
| `stripe_customer_id` | text | único, indexado |
| `stripe_subscription_id` | text | nullable até primeira assinatura |
| `status` | text | `active`,`trialing`,`past_due`,`canceled`,`incomplete`, etc. (espelha Stripe) |
| `price_id` | text | preço Stripe ativo |
| `current_period_end` | timestamptz | quando expira o acesso |
| `cancel_at_period_end` | bool | cancelamento agendado |
| `updated_at` | timestamptz | atualizado pelo webhook |

**RLS:** usuário faz `SELECT` da própria linha. **Nenhum** `INSERT/UPDATE/DELETE` pelo client — só o webhook escreve, usando **service role key** (bypassa RLS). Isso impede que o app se autoconceda Premium.

**Função canônica de gating:**
```sql
-- true se o usuário tem acesso premium AGORA
public.is_premium(uid uuid) returns boolean
  -> existe subscriptions com user_id=uid
     e status in ('active','trialing')
     e current_period_end > now()
```
Toda Edge Function que custa dinheiro chama essa lógica.

### 3.2 `public.stripe_events` — dedupe de webhook (idempotência)

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | text PK | `event.id` da Stripe |
| `type` | text | tipo do evento |
| `received_at` | timestamptz | default now() |

Sem RLS para client (sem policies = ninguém lê via API). Acessada só pelo webhook via service role.

---

## 4. Decisões de design (e o porquê)

| Decisão | Escolha | Motivo |
|---|---|---|
| Modelo Haiku vs Sonnet | Decidido server-side via `is_premium()` | Cliente não pode forçar modelo caro (vetor de custo 4.1) |
| Fonte de verdade da assinatura | Postgres, sincronizado por webhook | Não consultar Stripe em toda request (latência/custo); webhook mantém sincronizado |
| Canonicidade no webhook | **Re-buscar o objeto na Stripe** ao processar evento | Webhooks chegam fora de ordem e em paralelo; re-fetch elimina race de ordenação |
| Idempotência | Tabela `stripe_events` + `INSERT ... ON CONFLICT DO NOTHING` | Stripe reenvia eventos; processar 2x não pode dar Premium duplo nem erro |
| Auth do webhook | `--no-verify-jwt` + verificação de assinatura Stripe | Stripe não manda JWT Supabase; segurança vem da assinatura HMAC |
| Escrita em `subscriptions` | Só service role no webhook | RLS impede auto-promoção a Premium pelo client |
| Carta semanal em escala | `pg_cron` agendado, não on-demand no client | Evita burst de domingo e abuso de `semana_inicio` (vetor 4.2/4.4) |

---

## 5. Concorrência & tempo real (requisito explícito do cliente)

"Várias transações ao mesmo tempo" no contexto Stripe significa **muitos webhooks concorrentes**, não muitos pagamentos no nosso código (o pagamento roda na infra da Stripe). Garantias exigidas de toda implementação de webhook:

1. **Resposta rápida:** retornar `200` em < 5s. Trabalho pesado não bloqueia o ack. (Stripe re-tenta se demorar/erro.)
2. **Idempotente:** mesmo `event.id` processado N vezes = 1 efeito. Garantido pela tabela `stripe_events`.
3. **Tolerante a fora-de-ordem:** dois eventos do mesmo cliente podem chegar em paralelo. Solução: ao processar, **buscar o estado atual na Stripe** (`subscriptions.retrieve` / `customers.retrieve`) e fazer `UPSERT` do estado canônico — o último a escrever converge para a verdade da Stripe, não para a ordem de chegada.
4. **Upsert atômico:** escrita em `subscriptions` por `ON CONFLICT (user_id) DO UPDATE`. Sem read-modify-write em código.
5. **Assinatura verificada antes de qualquer DB:** evento sem assinatura válida → `400`, nada toca o banco.
6. **Sem segredo no client:** chave secreta Stripe e service role key só em secrets de Edge Function.

Com isso, a infra Supabase Edge + PostgREST escala horizontalmente; não há estado em memória entre requests, então N webhooks simultâneos não competem por recurso compartilhado além do `UPSERT` por linha (lock por linha do Postgres, barato).

---

## 6. Inventário de Edge Functions (alvo)

| Função | Auth | Custa $ | Gating | Fase |
|---|---|---|---|---|
| `mentor-chat` | JWT usuário | Sim (Claude) | Sonnet só se `is_premium`; rate limit server-side | 01 + 03 |
| `relatorio-semanal` | JWT usuário **ou** cron secret | Sim (Sonnet) | Valida data; rate limit; idempotente por semana | 01 + 04 |
| `stripe-checkout` | JWT usuário | Não | Cria/recupera customer + Checkout Session | 03 |
| `stripe-webhook` | **Sem JWT** + assinatura HMAC | Não | Sincroniza `subscriptions` | 03 |

---

## 7. Matriz de secrets (referência; setup na Fase 06)

| Secret | Onde | Usado por |
|---|---|---|
| `ANTHROPIC_API_KEY` | Edge Function secrets | mentor-chat, relatorio-semanal |
| `STRIPE_SECRET_KEY` | Edge Function secrets | stripe-checkout, stripe-webhook |
| `STRIPE_WEBHOOK_SECRET` | Edge Function secrets | stripe-webhook |
| `STRIPE_PRICE_PREMIUM` | Edge Function secrets | stripe-checkout |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secrets (auto) | stripe-webhook (bypassa RLS) |
| `CRON_SECRET` | Edge Function secrets + pg_cron | relatorio-semanal (modo cron) |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | App `.env` + Edge (auto) | client + funções |

Nada disso entra no bundle do Flutter exceto `SUPABASE_URL` e `SUPABASE_ANON_KEY` (públicos por design, protegidos por RLS).

---

Próximo: [`01-p0-custo-seguranca.md`](01-p0-custo-seguranca.md).
