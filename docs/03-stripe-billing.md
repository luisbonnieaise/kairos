# 03 · Stripe — Billing & Premium

> ⚠️ **PARCIALMENTE SUBSTITUÍDO pela Fase 07.** A decisão final do produto é **billing multiplataforma** (Stripe na web + Apple/Google IAP no app). Use [`07-billing-multiplataforma.md`](07-billing-multiplataforma.md) como spec vigente. Em particular: o Edge Function `stripe-checkout` **não é mais criado** (checkout vira rota server-side na `lp-kairo`), o paywall **não abre o navegador** (usa IAP) e `subscriptions` é **agnóstico de provider**. Os princípios de concorrência/idempotência e o gating do `mentor-chat` deste doc **permanecem válidos** e são reaproveitados pela Fase 07.

**Prioridade 🔴 P0 (monetização) + dependência da Fase 01.** Implementa **Kairo Premium** via Stripe: schema de billing, checkout, **webhook idempotente e concorrente**, sincronização canônica e gating server-side ligado ao `is_premium()` da Fase 01.

Pré-requisitos:
- Fase 01 concluída (existe `public.is_premium`).
- Ter lido [`00-visao-arquitetura.md`](00-visao-arquitetura.md) §3, §4 e §5 (concorrência).

Arquivos afetados / novos:
- Novo: `scripts/08_subscriptions.sql`
- Novo: `supabase/functions/stripe-checkout/index.ts`
- Novo: `supabase/functions/stripe-webhook/index.ts`
- Novo: `lib/core/billing.dart`
- Novo: `lib/telas/premium.dart`
- Editar: `supabase/functions/mentor-chat/index.ts` (gating real), `lib/telas/perfil.dart` (entrada do paywall)

---

## Decisões fixas (não negociar nos prompts)

| Tema | Decisão |
|---|---|
| Produto | 1 produto Stripe "Kairo Premium", 1+ `price` recorrente (mensal; opcional anual) |
| Cobrança | **Stripe Checkout** hospedado (PCI fica com a Stripe; não tocamos cartão) |
| Verdade da assinatura | Tabela `subscriptions` no Postgres, sincronizada **só** pelo webhook |
| Escrita de billing | Apenas webhook, via **service role** (RLS impede client) |
| Canonicidade | Webhook **re-busca** o objeto na Stripe e faz `UPSERT` (tolerante a fora-de-ordem/concorrência) |
| Idempotência | Tabela `stripe_events` + `INSERT ON CONFLICT DO NOTHING` |
| Auth webhook | Deploy `--no-verify-jwt`; segurança = verificação de assinatura Stripe |
| Gating | `is_premium()` (Fase 01) consultado server-side em toda função que custa $ |
| SDK | `stripe` via `https://esm.sh/stripe@<versão fixada>?target=deno` com `Stripe.createFetchHttpClient()` e `constructEventAsync` |

---

## PROMPT 3.1 — Schema de billing + RLS

```
Crie scripts/08_subscriptions.sql (mesmo estilo/banner dos demais,
idempotente). Conteúdo:

1. Tabela public.subscriptions (1 linha por usuário):
   user_id                 uuid primary key references auth.users(id) on delete cascade
   stripe_customer_id      text unique
   stripe_subscription_id  text
   status                  text not null default 'none'
   price_id                text
   current_period_end      timestamptz
   cancel_at_period_end    boolean not null default false
   updated_at              timestamptz not null default now()
   Índice em stripe_customer_id e em stripe_subscription_id.

2. RLS habilitado:
   - Policy SELECT own: auth.uid() = user_id.
   - NENHUMA policy de insert/update/delete (escrita só via service role no
     webhook, que bypassa RLS).

3. Tabela public.stripe_events:
   id           text primary key
   type         text not null
   received_at  timestamptz not null default now()
   RLS habilitado, SEM nenhuma policy (inacessível via API; só service role).

4. Atualize a função public.is_premium da Fase 01 se necessário para casar
   exatamente com estes nomes de coluna/status (active, trialing válidos;
   past_due/canceled/incomplete/none NÃO premium). Mantenha security definer.

5. Atualize scripts/README.md com o passo 8.

Apenas crie/edite arquivos. Não rode.
```

**Critérios de aceitação**
- [ ] `scripts/08_subscriptions.sql` idempotente; `subscriptions` com SELECT own e sem write policies; `stripe_events` sem policies.
- [ ] `is_premium()` coerente com os status reais.
- [ ] README de scripts atualizado.

> Rode `scripts/08_subscriptions.sql` no SQL Editor antes do PROMPT 3.4.

---

## PROMPT 3.2 — Edge Function `stripe-checkout`

```
Crie supabase/functions/stripe-checkout/index.ts (Deno). Requer JWT do
usuário (deploy normal, com verify-jwt).

Comportamento:
1. CORS + OPTIONS no mesmo padrão das funções existentes.
2. Exigir Authorization; criar client Supabase autenticado pelo JWT e obter
   user via auth.getUser(). 401 se inválido.
3. Inicializar Stripe com Deno.env.get('STRIPE_SECRET_KEY'),
   apiVersion fixada, httpClient = Stripe.createFetchHttpClient().
4. Garantir o stripe customer do usuário (idempotente):
   - Ler subscriptions do usuário via service role.
   - Se já houver stripe_customer_id, reutilizar.
   - Senão: stripe.customers.create({ email: user.email,
     metadata: { supabase_user_id: user.id } }) e UPSERT em subscriptions
     (user_id, stripe_customer_id, status='none') via service role.
5. Criar Checkout Session:
   - mode 'subscription', customer = customerId,
     line_items [{ price: Deno.env.get('STRIPE_PRICE_PREMIUM'), quantity:1 }],
     success_url e cancel_url vindos do corpo (validar que começam com o
     deep link/host esperado — não aceitar URL arbitrária),
     client_reference_id = user.id,
     subscription_data.metadata.supabase_user_id = user.id,
     allow_promotion_codes true.
   - Idempotência da criação: passar idempotencyKey derivada de
     user.id + price (evita sessões duplicadas em duplo clique).
6. Responder { url: session.url }. Erros: console.error server-side,
   client recebe { error: 'checkout_erro' }.

Use SUPABASE_SERVICE_ROLE_KEY só para ler/gravar subscriptions; nunca exponha
chave secreta Stripe ao client. Comentários em português, estilo do projeto.
```

**Critérios de aceitação**
- [ ] Função retorna `{url}` de Checkout válida para usuário autenticado.
- [ ] Customer reutilizado em chamadas repetidas (sem duplicar na Stripe).
- [ ] `success_url`/`cancel_url` fora do host esperado → rejeitado.
- [ ] Chave secreta Stripe nunca chega ao client.

---

## PROMPT 3.3 — Edge Function `stripe-webhook` (idempotente + concorrente)

```
Crie supabase/functions/stripe-webhook/index.ts (Deno). Esta função NÃO usa
JWT do Supabase — será deployada com --no-verify-jwt. A segurança vem da
assinatura Stripe. Siga ESTRITAMENTE os princípios de concorrência do
documento 00 §5.

Implementação:
1. Aceitar só POST. Ler o corpo como TEXTO BRUTO (req.text()) — necessário
   para verificar assinatura.
2. Verificar assinatura:
   stripe.webhooks.constructEventAsync(rawBody,
     req.headers.get('stripe-signature'),
     Deno.env.get('STRIPE_WEBHOOK_SECRET'),
     undefined, Stripe.createSubtleCryptoProvider()).
   Falha -> 400 imediatamente, NADA toca o banco.
3. Idempotência: com client service role, INSERT em stripe_events
   (id=event.id, type=event.type) com ON CONFLICT (id) DO NOTHING.
   Se nenhuma linha foi inserida (evento já visto) -> responder 200 'ok'
   sem reprocessar.
4. Processar apenas os tipos relevantes:
   checkout.session.completed,
   customer.subscription.created,
   customer.subscription.updated,
   customer.subscription.deleted,
   invoice.payment_failed.
   Outros tipos -> 200 'ok' (ignorar).
5. CANONICIDADE (anti fora-de-ordem): NÃO confie nos campos do evento.
   Resolva o customer/subscription e RE-BUSQUE o estado atual na Stripe:
   - Descubra o stripe_customer_id (do objeto do evento).
   - stripe.subscriptions.list({ customer, status:'all', limit:1 }) ou
     subscriptions.retrieve do id ativo para obter status, price,
     current_period_end, cancel_at_period_end atuais.
   - Resolva o supabase_user_id por customer.metadata.supabase_user_id
     (fallback: lookup em subscriptions por stripe_customer_id).
6. Persistir com UPSERT atômico em public.subscriptions
   ON CONFLICT (user_id) DO UPDATE SET ... updated_at=now()
   (status, stripe_subscription_id, price_id, current_period_end,
   cancel_at_period_end). Sem read-modify-write.
7. Sempre responder rápido: 200 em caso de processado/ignorado; 400 só para
   assinatura inválida; 500 só para falha real de processamento (a Stripe
   re-tenta — e a idempotência cobre o reprocesso).
8. Logs via console.error/console.log; nunca devolver detalhe ao chamador.

Comentários em português. Fixe a apiVersion igual à da 3.2.
```

**Critérios de aceitação**
- [ ] Payload com assinatura inválida → `400`, zero escrita no banco.
- [ ] Mesmo `event.id` entregue 2x → segundo retorna `200` sem reprocessar (linha única em `stripe_events`).
- [ ] Estado em `subscriptions` reflete a Stripe mesmo se `updated` chegar antes de `created` (porque há re-fetch + upsert).
- [ ] `subscriptions` nunca escrito sem evento Stripe válido (RLS + sem policy de write garante).
- [ ] Resposta sempre < 5s.

---

## PROMPT 3.4 — Ligar o gating real no `mentor-chat` (fecha o vetor 4.1)

```
Agora que public.subscriptions existe e o webhook a mantém sincronizada,
revise supabase/functions/mentor-chat/index.ts:
- Confirme que premium = supabaseService.rpc('is_premium',{uid:user.id})
  agora reflete assinaturas reais (e não mais sempre false).
- modelo = premium ? MODELO_SONNET : MODELO_HAIKU; limite/h conforme 1.3
  (não-premium 20/h, premium 120/h).
- Adicione no JSON de resposta um campo "premium": boolean para a UI poder
  exibir o estado (sem confiar nele para segurança — é só display).
Não reintroduza confiança em flag do client para escolher modelo.
```

**Critérios de aceitação**
- [ ] Usuário com assinatura ativa recebe Sonnet; sem assinatura recebe Haiku.
- [ ] Cancelar/expirar (via webhook) → volta a Haiku automaticamente na próxima request.
- [ ] Resposta inclui `premium` apenas para display.

---

## PROMPT 3.5 — Camada de billing no client

```
Crie lib/core/billing.dart:
- Future<bool> isPremium(): chama uma RPC leve OU lê a tabela subscriptions
  (SELECT own permitido pela RLS) e deriva premium = status in
  (active,trialing) && current_period_end > now. Cacheia em memória por
  sessão; expõe método refresh().
- Future<String> iniciarCheckout(): invoca a Edge Function stripe-checkout
  passando success_url/cancel_url (deep link do app), retorna a url.
- Future<void> abrirPortal(): (opcional) se for criada uma função de
  customer portal; senão, deixar TODO documentado.
Trate erros com mensagens traduzíveis (i18n nos 4 idiomas: assinaturaErro,
etc.). Sem segredo no client.
```

**Critérios de aceitação**
- [ ] `isPremium()` deriva estado da tabela via RLS (SELECT own), com cache + refresh.
- [ ] `iniciarCheckout()` retorna URL e abre no navegador externo.
- [ ] Strings i18n nos 4 idiomas; `flutter analyze` limpo.

---

## PROMPT 3.6 — Paywall e estado Premium na UI

```
Crie lib/telas/premium.dart: tela de assinatura no estilo visual do Kairo
(KC/KT, tom zen, sem hype) explicando os benefícios do Premium
(Mentor com Sonnet, carta semanal garantida, limites ampliados), botão
"Assinar" -> billing.iniciarCheckout() -> abre Checkout no navegador.
Após retorno do deep link de sucesso, chamar billing.refresh() e mostrar
estado ativo.

Integre em lib/telas/perfil.dart: um item/seção "Kairo Premium" mostrando
status atual (Ativo até <data> / Gratuito) e levando à TelaPremium.
Configure o deep link de retorno (success_url/cancel_url) — documente o
esquema de URL escolhido em docs/06-runbook-deploy.md (seção Stripe).
Não invente preço fixo no client; o preço é definido pelo price da Stripe.
```

**Critérios de aceitação**
- [ ] Fluxo completo: Perfil → Premium → Checkout → retorno → estado "Ativo".
- [ ] Estado premium reflete a tabela (não flag local arbitrária).
- [ ] Esquema de deep link documentado no runbook.

---

## PROMPT 3.7 — Teste de concorrência do webhook (validação)

```
Adicione em docs/06-runbook-deploy.md (seção "Validação Stripe") um roteiro
de teste com a Stripe CLI:
- stripe listen --forward-to <url da função stripe-webhook>
- stripe trigger checkout.session.completed / customer.subscription.updated
  / customer.subscription.deleted
- Reenviar o MESMO evento 2x (stripe events resend) e verificar uma única
  linha em stripe_events e estado correto em subscriptions.
- Disparar updated e deleted quase juntos e confirmar convergência para o
  estado real da Stripe (re-fetch).
Apenas documentar o roteiro; sem código.
```

**Critérios de aceitação**
- [ ] Runbook contém roteiro de validação com Stripe CLI cobrindo idempotência e fora-de-ordem.

---

## Resultado da fase

Kairo Premium operante: pagamento PCI-safe via Stripe, assinatura como verdade no Postgres sincronizada por webhook **idempotente e concorrente**, e gating server-side que efetivamente fecha o vetor de custo 4.1. Cliente nunca consegue se autoconceder Premium nem forçar modelo caro.

Próximo: [`04-escala-30k.md`](04-escala-30k.md).

