# 07 · Billing Multiplataforma (Stripe web + Apple IAP + Google Play)

**Prioridade 🔴 P0 (monetização real cross-platform).** Este documento **substitui e expande** as partes do [`03-stripe-billing.md`](03-stripe-billing.md) que assumiam checkout **dentro do app**. A decisão final do produto é:

- **Stripe** → assinatura feita **no site** (`lp-kairo`), com **login Supabase antes do checkout**. Taxa menor; é o canal preferido nas campanhas.
- **Apple IAP** → compra **dentro do app iOS** (StoreKit 2). Obrigatório oferecer (Guideline 3.1.3).
- **Google Play Billing** → compra **dentro do app Android**.
- **Uma única fonte de verdade de entitlement** no Postgres (`public.subscriptions`), **agnóstica de provider**, escrita só por webhooks via service role. O app lê `is_premium()` sem nunca confiar no client.
- **Conformidade:** o app **vende via IAP** no mobile **e honra silenciosamente** um Premium comprado na web (regra multiplataforma 3.1.3(b)). **Nenhuma** menção/link ao site dentro do app (anti-steering).

> ⚠️ **Correções ao doc 03** (ver [§0](#0-o-que-muda-em-relação-ao-doc-03)): o Edge Function `stripe-checkout` **deixa de existir** (o checkout vira uma rota server-side na `lp-kairo`); o paywall do app **deixa de abrir o navegador** e passa a usar IAP; a tabela `subscriptions` deixa de ser Stripe-only.

Pré-requisitos:
- Fase 01 concluída (existe `public.is_premium`).
- Ter lido [`00-visao-arquitetura.md`](00-visao-arquitetura.md) §3, §4 e §5 (concorrência).
- Console preparado pelo Luis conforme [`08-guia-consoles-luis.md`](08-guia-consoles-luis.md) **antes** dos prompts 7.4–7.7.

---

## 0. O que muda em relação ao doc 03

| Item no doc 03 | Status agora | Onde fica |
|---|---|---|
| `scripts/08_subscriptions.sql` (Stripe-only) | **Substituído** por schema agnóstico de provider | PROMPT 7.1 |
| Edge Function `stripe-checkout` (chamada pelo app) | **Removido** | vira rota `/api/checkout` na `lp-kairo` (PROMPT 7.3) |
| Edge Function `stripe-webhook` | **Mantido**, agora chama RPC canônica | PROMPT 7.4 |
| `lib/core/billing.dart` abre Checkout no navegador | **Substituído** por IAP (StoreKit/Play Billing) | PROMPT 7.8 |
| `lib/telas/premium.dart` botão "Assinar" → navegador | **Substituído** por paywall IAP nativo | PROMPT 7.9 |
| Gating no `mentor-chat` (3.4) | **Mantido idêntico** | PROMPT 7.10 |

Os princípios de concorrência do doc 00 §5 (resposta rápida, idempotência por `event_id`, **re-fetch do estado no provider**, upsert atômico, assinatura verificada antes de tocar o banco) **valem igualmente** para os 3 webhooks.

---

## 1. Arquitetura alvo

```
lp-kairo (web) ── login Supabase ──> identidade (auth.users.id)
     │
     └─ POST /api/checkout (server) ──> Stripe Checkout Session
            client_reference_id = user.id
            subscription_data.metadata.supabase_user_id = user.id
            trial_period_days = 7, price por moeda/locale
                         │
   Stripe ──webhook────> stripe-webhook  ─┐
                                          │
 iOS  ─IAP(appAccountToken=user.id)─ Apple─ASSN v2 ─> apple-webhook  ─┼─► rpc aplicar_estado_assinatura()
                                          │                            │      (service role, upsert atômico)
 Android ─IAP(obfuscatedAccountId=user.id)─ Google─RTDN/PubSub ─> google-webhook ┘
                                          │
                                          └─ verify-purchase (JWT do app, desbloqueio imediato pós-compra)

 Flutter app ── is_premium(user.id) ──> gating server-side (Sonnet/Haiku, limites)
```

**Linking determinístico (decisão do produto):**

| Canal | Como o `user_id` viaja com a compra |
|---|---|
| Stripe (web) | `client_reference_id` + `subscription_data.metadata.supabase_user_id` na Session |
| Apple | `appAccountToken` (UUID = `user.id`) no `purchaseParam` do StoreKit |
| Google | `obfuscatedAccountId` (= `user.id`) no `purchaseParam` do Play Billing |

---

## 2. Modelo de dados (agnóstico de provider)

Uma linha por usuário (entitlement canônico). **Regra de convergência multiplataforma:** um webhook só pode **rebaixar** o entitlement se ele for o **mesmo provider** que concedeu o acesso vigente — assim a expiração de uma assinatura Apple não apaga uma Stripe ainda ativa. Isso fica centralizado numa função SQL `aplicar_estado_assinatura()` chamada pelos 3 webhooks.

```
public.subscriptions  (PK user_id — 1 linha/usuário, entitlement canônico)
  user_id               uuid PK -> auth.users(id) on delete cascade
  provider              text  default 'none'   -- none|stripe|apple|google
  status                text  default 'none'   -- none|active|trialing|past_due|canceled|expired|grace|incomplete
  product_id            text                   -- price/produto que concedeu o acesso
  current_period_end    timestamptz
  cancel_at_period_end  boolean default false
  stripe_customer_id    text unique            -- só Stripe
  provider_sub_id       text                   -- stripe sub id | apple original_transaction_id | google purchaseToken
  updated_at            timestamptz default now()

public.billing_events  (dedupe de webhook — todos os providers)
  provider     text
  event_id     text                            -- event.id (Stripe) | notificationUUID (Apple) | messageId (Google)
  type         text
  received_at  timestamptz default now()
  primary key (provider, event_id)
```

`is_premium(uid)` continua: `status in ('active','trialing','grace') and current_period_end > now()`.

---

## PROMPT 7.1 — Schema agnóstico de provider + RPC de convergência

```
Crie scripts/08_subscriptions.sql (idempotente, mesmo banner/estilo dos
scripts 01–06). Este arquivo SUBSTITUI a versão Stripe-only descrita no doc 03.

1. Tabela public.subscriptions (1 linha por usuário):
   user_id               uuid primary key references auth.users(id) on delete cascade
   provider              text not null default 'none'
   status                text not null default 'none'
   product_id            text
   current_period_end    timestamptz
   cancel_at_period_end  boolean not null default false
   stripe_customer_id    text unique
   provider_sub_id       text
   updated_at            timestamptz not null default now()
   Índices: (stripe_customer_id), (provider, provider_sub_id).

2. Tabela public.billing_events:
   provider text not null, event_id text not null, type text not null,
   received_at timestamptz not null default now(),
   primary key (provider, event_id).
   RLS habilitado, SEM nenhuma policy (inacessível via API; só service role).

3. RLS em subscriptions:
   - Policy SELECT own: auth.uid() = user_id.
   - NENHUMA policy de insert/update/delete (escrita só via service role).

4. Função public.is_premium(uid uuid) returns boolean, security definer,
   search_path = public: true se existe subscriptions com user_id=uid e
   status in ('active','trialing','grace') e current_period_end > now().
   (Se a Fase 01 já criou is_premium, substitua o corpo para casar com
   estes status/colunas.)

5. Função public.aplicar_estado_assinatura(
        p_user_id uuid, p_provider text, p_status text, p_product_id text,
        p_current_period_end timestamptz, p_cancel_at_period_end boolean,
        p_stripe_customer_id text, p_provider_sub_id text
     ) returns void, security definer, search_path = public.
   Regra de convergência (atômica, sem read-modify-write em código):
     INSERT ... ON CONFLICT (user_id) DO UPDATE SET ...
     mas só sobrescreve a linha existente quando UMA das condições vale:
       (a) o novo estado é "concede acesso" (p_status in active|trialing|grace), OU
       (b) a linha atual pertence ao MESMO provider (subscriptions.provider = p_provider).
     Caso contrário (rebaixamento vindo de provider diferente do que concede
     o acesso vigente) -> NÃO altera status/period_end (no-op), apenas garante
     a linha existir. Sempre seta updated_at = now() quando escreve.
   Implemente isso com uma única instrução INSERT ... ON CONFLICT cujo
   DO UPDATE tem WHERE com essa lógica, ou um pequeno bloco plpgsql com
   lock por linha (SELECT ... FOR UPDATE) — escolha o mais legível e
   documente o porquê em comentário.

6. Atualize scripts/README.md (passo 8) e a matriz de secrets do doc 06
   apontando para este schema.

Apenas crie/edite arquivos. Não rode.
```

**Critérios de aceitação**
- [ ] `subscriptions` com SELECT own e sem policies de escrita; `billing_events` sem policies.
- [ ] `is_premium()` coerente com os status (`active`,`trialing`,`grace`).
- [ ] `aplicar_estado_assinatura()` é idempotente e **não deixa um provider rebaixar o acesso ativo de outro**.
- [ ] Rodar o script 2x não quebra.

> Rode `scripts/08_subscriptions.sql` no SQL Editor antes dos prompts 7.4–7.7.

---

## PROMPT 7.2 — Login Supabase na `lp-kairo` (pré-checkout)

```
No projeto lp-kairo (Next.js 15 / App Router), adicione autenticação Supabase
usada SOMENTE como gate antes do checkout (mesma identidade do app Flutter).

1. Instale @supabase/supabase-js e @supabase/ssr.
2. Crie src/lib/supabase/server.ts e src/lib/supabase/client.ts seguindo o
   padrão @supabase/ssr (cookies). Use NEXT_PUBLIC_SUPABASE_URL e
   NEXT_PUBLIC_SUPABASE_ANON_KEY (adicione ao .env.example).
3. Crie um fluxo de login leve e no estilo visual da LP (washi/sumi, sem hype):
   - Magic link / OTP por e-mail e (se trivial) Google OAuth — os MESMOS
     providers habilitados no app.
   - Componente client que, ao clicar "Assinar", se não houver sessão, abre
     o login; com sessão, prossegue ao checkout.
4. NÃO exponha service role key na LP. Toda escrita de billing é feita pelos
   webhooks no Supabase, não pela LP.
5. i18n: textos de login nos 4 locales (pt/en/es/de) em src/messages/*.

Critério de identidade: o usuário que assina na web é o MESMO auth.users do
app. Documente em README da lp-kairo que o app deve usar os mesmos providers.
```

**Critérios de aceitação**
- [ ] Sem sessão → clicar "Assinar" abre login; com sessão → segue ao checkout.
- [ ] `user.id` da sessão disponível no server (para o PROMPT 7.3).
- [ ] Nenhum segredo de service role na LP; `npm run typecheck` limpo.

---

## PROMPT 7.3 — Rota de checkout server-side na `lp-kairo` (substitui o `stripe-checkout`)

```
Na lp-kairo, substitua os Stripe Payment Links estáticos (getCheckoutUrl em
src/lib/utils.ts) por uma rota server-side que cria a Checkout Session com a
identidade do usuário.

1. Instale stripe (SDK Node). Crie src/app/api/checkout/route.ts (POST):
   - Leia a sessão Supabase via @supabase/ssr (server). Sem usuário -> 401.
   - Corpo: { period: 'monthly'|'yearly' }. A MOEDA vem do locale como hoje
     (pt->BRL, en->USD, es/de->EUR); reaproveite localeCurrency.
   - Resolva o price id por (moeda, período) a partir de envs server-side
     STRIPE_PRICE_<CCY>_<PERIODO> (NÃO usar NEXT_PUBLIC para price ids).
   - Garanta o customer Stripe do usuário de forma idempotente SEM service
     role: stripe.customers.search por metadata['supabase_user_id']; se não
     existir, customers.create({ email: user.email,
     metadata: { supabase_user_id: user.id } }).
   - Crie a Checkout Session: mode 'subscription', customer,
     line_items [{ price, quantity:1 }],
     client_reference_id = user.id,
     subscription_data.metadata.supabase_user_id = user.id,
     subscription_data.trial_period_days = 7,
     allow_promotion_codes true,
     success_url / cancel_url para páginas da própria LP,
     locale conforme idioma.
     idempotencyKey derivada de user.id + price (anti duplo-clique).
   - Responda { url }. Erros: log server-side, { error: 'checkout_erro' } ao
     client.

2. Ajuste src/components/sections/Pricing.tsx e Button: o CTA passa a chamar
   a rota (com o gate de login do 7.2) em vez de href estático.

3. Atualize .env.example: remova os 6 NEXT_PUBLIC_STRIPE_LINK_* e adicione
   STRIPE_SECRET_KEY e STRIPE_PRICE_BRL_MONTHLY/_YEARLY, _USD_*, _EUR_*
   (server-side, sem NEXT_PUBLIC).

Comentários em português, estilo do projeto.
```

**Critérios de aceitação**
- [ ] Usuário logado → CTA cria Session e redireciona ao Checkout com a moeda do locale e trial de 7 dias.
- [ ] Customer reutilizado em chamadas repetidas (sem duplicar na Stripe).
- [ ] Price ids e secret key **nunca** com prefixo `NEXT_PUBLIC`.
- [ ] Payment Links estáticos removidos.

---

## PROMPT 7.4 — Edge Function `stripe-webhook` (chama a RPC canônica)

```
Crie/atualize supabase/functions/stripe-webhook/index.ts (Deno). Deploy com
--no-verify-jwt; segurança = assinatura Stripe. Siga o doc 00 §5.

1. Só POST. Ler corpo como TEXTO BRUTO (req.text()).
2. stripe.webhooks.constructEventAsync(raw, sig header,
   STRIPE_WEBHOOK_SECRET, undefined, Stripe.createSubtleCryptoProvider()).
   Falha -> 400, nada toca o banco.
3. Idempotência: client service role, INSERT em billing_events
   (provider='stripe', event_id=event.id, type=event.type)
   ON CONFLICT (provider,event_id) DO NOTHING. Se nada inserido -> 200 'ok'.
4. Tipos processados: checkout.session.completed,
   customer.subscription.created/updated/deleted, invoice.paid,
   invoice.payment_failed. Outros -> 200 'ok'.
5. CANONICIDADE (anti fora-de-ordem): NÃO confie nos campos do evento.
   Descubra o stripe_customer_id, então RE-BUSQUE na Stripe
   stripe.subscriptions.list({ customer, status:'all', limit:1 }) (ou
   retrieve) para status/price/current_period_end/cancel_at_period_end atuais.
   Resolva o supabase_user_id por subscription.metadata.supabase_user_id
   (fallback: customer.metadata.supabase_user_id; fallback final: lookup em
   subscriptions por stripe_customer_id).
6. Persistência: rpc('aplicar_estado_assinatura', { p_user_id, p_provider:
   'stripe', p_status (mapeado: trialing->trialing, active->active,
   past_due->past_due, canceled->canceled, incomplete*->incomplete),
   p_product_id: price.id, p_current_period_end, p_cancel_at_period_end,
   p_stripe_customer_id, p_provider_sub_id: subscription.id }).
7. 200 em processado/ignorado; 400 só assinatura inválida; 500 só falha real
   (Stripe re-tenta; idempotência cobre). Logs via console; nunca detalhar ao
   chamador. Fixe apiVersion.
```

**Critérios de aceitação**
- [ ] Assinatura inválida → `400`, zero escrita.
- [ ] Mesmo `event.id` 2x → 2ª vez `200` sem reprocessar.
- [ ] `updated` antes de `created` → converge ao estado real (re-fetch + RPC).
- [ ] Resposta < 5s.

---

## PROMPT 7.5 — Edge Function `apple-webhook` (App Store Server Notifications V2)

```
Crie supabase/functions/apple-webhook/index.ts (Deno). Deploy com
--no-verify-jwt; segurança = assinatura JWS da Apple. Aplique o doc 00 §5.

Contexto: recebe POST { signedPayload } (JWS compacto) das App Store Server
Notifications V2. Secrets: APPLE_BUNDLE_ID, APPLE_ISSUER_ID, APPLE_KEY_ID,
APPLE_PRIVATE_KEY (.p8), APPLE_ENV ('Sandbox'|'Production').

1. Só POST. Ler { signedPayload }.
2. VERIFICAR a assinatura do JWS: extrair a cadeia x5c do header, validar que
   a leaf encadeia até a Apple Root CA - G3 e verificar a assinatura do
   payload (use jose: importar a chave pública da leaf e compactVerify; valide
   a cadeia x5c). Falha -> 400, nada toca o banco. Documente em comentário que
   a Apple Root CA - G3 está embutida/baixada no deploy.
3. Decodificar o responseBodyV2DecodedPayload: notificationUUID,
   notificationType, subtype, data.signedTransactionInfo,
   data.signedRenewalInfo (também JWS — decodificar/verificar).
4. Idempotência: INSERT billing_events (provider='apple',
   event_id=notificationUUID, type=notificationType)
   ON CONFLICT DO NOTHING. Se nada inserido -> 200.
5. Identidade: appAccountToken (no transactionInfo) = supabase user_id.
   (fallback: lookup em subscriptions por provider_sub_id =
   originalTransactionId.)
6. CANONICIDADE: NÃO confie só na notificação. RE-BUSQUE o estado via App
   Store Server API getAllSubscriptionStatuses(originalTransactionId)
   (assine um JWT ES256 com APPLE_PRIVATE_KEY/KEY_ID/ISSUER_ID; host conforme
   APPLE_ENV). Derive status/expiresDate/autoRenewStatus atuais.
   Mapeamento -> aplicar_estado_assinatura:
     status 1 (active) + autoRenew on  -> 'active' (ou 'trialing' se em trial)
     status 1 + autoRenew off          -> 'active' com cancel_at_period_end=true
     status 4 (billing retry/grace)    -> 'grace'
     status 3 (expired)                -> 'expired'
     status 2 (revoked/refunded)       -> 'canceled'
   p_provider='apple', p_provider_sub_id=originalTransactionId,
   p_product_id=productId, p_current_period_end=expiresDate,
   p_stripe_customer_id=null.
7. 200 processado/ignorado; 400 assinatura inválida; 500 falha real (Apple
   re-tenta). Logs via console; nada vaza ao chamador.
```

**Critérios de aceitação**
- [ ] JWS com assinatura/cadeia inválida → `400`, zero escrita.
- [ ] Mesmo `notificationUUID` 2x → 2ª vez `200` sem reprocessar.
- [ ] Estado reflete o re-fetch da App Store Server API, não só o payload.
- [ ] `appAccountToken` resolve o `user_id`; expiração/refund rebaixa só se Apple for o provider vigente.

---

## PROMPT 7.6 — Edge Function `google-webhook` (RTDN via Pub/Sub)

```
Crie supabase/functions/google-webhook/index.ts (Deno). Deploy com
--no-verify-jwt; segurança = verificação do push do Pub/Sub. Aplique doc 00 §5.

Contexto: Pub/Sub PUSH entrega POST com { message: { data (base64),
messageId, publishTime }, subscription }. O data decodificado é um
DeveloperNotification com subscriptionNotification { purchaseToken,
subscriptionId, notificationType } (e/ou voidedPurchaseNotification).
Secrets: GOOGLE_PACKAGE_NAME, GOOGLE_SERVICE_ACCOUNT_JSON (chave da service
account com acesso à Play Developer API), GOOGLE_PUBSUB_AUDIENCE.

1. Só POST. Verificar a autenticidade do push:
   - Validar o token OIDC do header Authorization (Bearer) emitido pelo
     Pub/Sub: assinatura Google + audience == GOOGLE_PUBSUB_AUDIENCE
     (use jose com as chaves públicas do Google). Falha -> 401/400.
2. Decodificar message.data (base64 -> JSON). Idempotência: INSERT
   billing_events (provider='google', event_id=message.messageId,
   type=String(notificationType)) ON CONFLICT DO NOTHING. Nada inserido -> 200.
3. CANONICIDADE: obter um access token OAuth2 assinando um JWT com a service
   account (escopo androidpublisher) e trocando no token endpoint. RE-BUSCAR
   o estado em purchases.subscriptionsv2.get(packageName, purchaseToken).
   Dela: subscriptionState, lineItems[].expiryTime, canceledStateContext,
   externalAccountIdentifiers.obfuscatedExternalAccountId (= supabase user_id).
4. Identidade: obfuscatedExternalAccountId = user_id (fallback: lookup em
   subscriptions por provider_sub_id = purchaseToken).
5. Mapeamento subscriptionState -> aplicar_estado_assinatura:
     ACTIVE         -> 'active' (cancel_at_period_end conforme autoRenew)
     IN_GRACE_PERIOD-> 'grace'
     ON_HOLD/PAUSED -> 'past_due'
     CANCELED       -> 'active' com cancel_at_period_end=true (até expirar)
     EXPIRED        -> 'expired'
     (voided/refund) -> 'canceled'
   p_provider='google', p_provider_sub_id=purchaseToken,
   p_product_id=subscriptionId, p_current_period_end=expiryTime.
6. Se a compra for nova e ainda não reconhecida, ACK via
   purchases.subscriptions.acknowledge (ou subscriptionsv2 equivalente) para
   não ter reembolso automático em 3 dias. Idempotente.
7. 200 processado/ignorado; 400/401 push inválido; 500 falha real (Pub/Sub
   re-tenta). Logs via console; nada vaza.
```

**Critérios de aceitação**
- [ ] Push sem OIDC válido (audience errada) → rejeitado, zero escrita.
- [ ] Mesmo `messageId` 2x → 2ª vez `200` sem reprocessar.
- [ ] Estado reflete `subscriptionsv2.get` (re-fetch), não só a notificação.
- [ ] Compra nova é reconhecida (acknowledge) e não é reembolsada automaticamente.

---

## PROMPT 7.7 — Edge Function `verify-purchase` (desbloqueio imediato pós-compra)

```
Crie supabase/functions/verify-purchase/index.ts (Deno). Deploy NORMAL
(verify-jwt) — exige JWT do usuário. Objetivo: dar Premium imediato após a
compra IAP sem esperar a notificação assíncrona (que pode atrasar). Os
webhooks 7.5/7.6 continuam sendo a fonte de verdade para renovações/cancelamentos.

1. CORS + OPTIONS no padrão das funções existentes.
2. Exigir Authorization; auth.getUser() -> user. 401 se inválido.
3. Corpo: { provider: 'apple'|'google', token } onde token é, para Apple, o
   originalTransactionId (ou transactionId) e, para Google, o purchaseToken.
4. RE-BUSCAR o estado no provider (mesma lógica de 7.5/7.6: App Store Server
   API para Apple; subscriptionsv2.get para Google) usando os MESMOS secrets.
   VALIDE que a compra pertence a este usuário: appAccountToken /
   obfuscatedExternalAccountId == user.id. Se não bater -> 403.
5. Chamar aplicar_estado_assinatura com o estado canônico (igual aos webhooks).
   Para Google, fazer acknowledge se necessário.
6. Responder { premium: boolean, current_period_end }. Erros logados
   server-side; client recebe { error }.

Reaproveite helpers de 7.5/7.6 (extraia para um módulo compartilhado em
supabase/functions/_shared/ se reduzir duplicação).
```

**Critérios de aceitação**
- [ ] Compra recém-feita → `verify-purchase` retorna `premium:true` em segundos.
- [ ] Token de outro usuário → `403`, nada gravado.
- [ ] Mesma lógica canônica dos webhooks (sem caminho de confiança no client).

---

## PROMPT 7.8 — Camada de billing no client (IAP + leitura de entitlement)

```
Crie lib/core/billing.dart no app Flutter. Adicione in_app_purchase (e
in_app_purchase_storekit / in_app_purchase_android) ao pubspec.

1. Future<bool> isPremium(): SELECT own em public.subscriptions (RLS) e
   deriva premium = status in (active,trialing,grace) &&
   current_period_end > now. Cache em memória por sessão + refresh().
2. Future<List<ProductDetails>> produtos(): queryProductDetails com os IDs
   dos produtos de assinatura (mensal/anual) configurados nas lojas.
3. Future<void> comprar(ProductDetails p): buyNonConsumable com PurchaseParam
   carregando a identidade:
     - iOS: applicationUserName / appAccountToken = user.id (UUID).
     - Android: PurchaseParam com obfuscatedAccountId = user.id.
4. Escutar purchaseStream: em purchaseStatus.purchased/restored, enviar o
   token à Edge Function verify-purchase ({provider, token}), chamar
   completePurchase, e billing.refresh() (desbloqueio imediato).
5. Future<void> restaurar(): restorePurchases() para reassociar compras.
6. NUNCA decidir Premium localmente para liberar recurso pago — isPremium é só
   display; a verdade é server-side (mentor-chat consulta is_premium).
7. i18n nas 4 línguas (assinaturaErro, compraCancelada, restaurado, etc.).

Sem segredo no client. flutter analyze limpo.
```

**Critérios de aceitação**
- [ ] `isPremium()` deriva da tabela via RLS, com cache + refresh.
- [ ] Compra carrega `appAccountToken`/`obfuscatedAccountId = user.id`.
- [ ] Pós-compra chama `verify-purchase` e reflete Premium em segundos.
- [ ] `restaurar()` reassocia assinaturas; `flutter analyze` limpo.

---

## PROMPT 7.9 — Paywall IAP nativo + estado Premium (sem link externo)

```
Crie lib/telas/premium.dart no estilo visual do Kairo (KC/KT, tom zen, sem
hype). CONFORMIDADE (crítico):
- Mobile: mostrar SOMENTE a compra via IAP (produtos de billing.produtos()),
  botão "Assinar" -> billing.comprar(produto).
- NÃO exibir preço do site, "assine mais barato no site", nem QUALQUER link
  para a web/checkout externo (anti-steering Apple/Google).
- Botão "Restaurar compras" -> billing.restaurar().
- Se o usuário já tem Premium (inclusive comprado na web), mostrar estado
  "Ativo até <data>" e esconder a oferta de compra (honra multiplataforma).

Integre em lib/telas/perfil.dart: seção "Kairo Premium" com status atual
(Ativo até <data> / Gratuito) levando à TelaPremium.

REMOVA qualquer resquício do fluxo antigo do doc 03 que abria Checkout no
navegador. Não invente preço fixo no client — use ProductDetails das lojas.
```

**Critérios de aceitação**
- [ ] Fluxo iOS/Android: Perfil → Premium → compra IAP → estado "Ativo".
- [ ] **Zero** menção/link ao site dentro do app.
- [ ] Usuário com Premium da web vê "Ativo" no app sem oferta de compra.
- [ ] Nenhum código que abra Checkout no navegador permanece.

---

## PROMPT 7.10 — Gating real no `mentor-chat` (idêntico ao 3.4)

```
Revise supabase/functions/mentor-chat/index.ts:
- premium = supabaseService.rpc('is_premium', { uid: user.id }) (reflete os 3
  providers via subscriptions).
- modelo = premium ? MODELO_SONNET : MODELO_HAIKU; rate limit conforme Fase 01
  (não-premium 20/h, premium 120/h).
- Inclua "premium": boolean na resposta apenas para display (sem confiar nele
  para segurança). Não reintroduza confiança em flag do client.
```

**Critérios de aceitação**
- [ ] Assinatura ativa em QUALQUER provider → Sonnet; sem assinatura → Haiku.
- [ ] Expirar/cancelar em qualquer provider → volta a Haiku na próxima request.

---

## PROMPT 7.11 — Roteiro de validação dos 3 webhooks (runbook)

```
Adicione em docs/06-runbook-deploy.md uma seção "Validação Billing
Multiplataforma" com roteiros:

STRIPE (test mode):
- stripe listen --forward-to <url stripe-webhook>; stripe trigger
  checkout.session.completed / customer.subscription.updated/deleted.
- Reenviar mesmo evento 2x -> 1 linha billing_events(provider=stripe),
  estado correto. updated+deleted quase juntos -> converge (re-fetch).

APPLE (Sandbox):
- Comprar com conta Sandbox no app; conferir notificação SUBSCRIBED ->
  subscriptions.status active. Forçar renovação/expiração no Sandbox e
  conferir DID_RENEW/EXPIRED. Reenviar mesmo notificationUUID -> sem dup.
- "Request a Test Notification" no App Store Connect -> chega no apple-webhook.

GOOGLE (teste de licença / produto de teste):
- Comprar com conta de teste; conferir RTDN PURCHASED -> active e
  acknowledge feito. Cancelar no Play -> CANCELED (cancel_at_period_end),
  depois EXPIRED. Reenviar mesma messageId -> sem dup.

CONVERGÊNCIA CROSS-PROVIDER:
- Conceder Premium via Stripe; disparar EXPIRED de Apple para o mesmo user
  (sem assinatura Apple ativa) -> entitlement Stripe permanece (a RPC não
  deixa Apple rebaixar o que Stripe concede).

Apenas documentar os roteiros; sem código.
```

**Critérios de aceitação**
- [ ] Runbook cobre idempotência, fora-de-ordem e convergência cross-provider para os 3 providers.

---

## Ordem de execução desta fase

```
7.1 (schema + RPC)            ── base de tudo
 ├─ 7.2 (LP login) ─ 7.3 (LP checkout) ─ 7.4 (stripe-webhook)     [trilha Stripe/web]
 ├─ 7.5 (apple-webhook) ─┐
 ├─ 7.6 (google-webhook) ─┼─ 7.7 (verify-purchase)                [trilha IAP]
 └─ 7.8 (billing.dart) ─ 7.9 (paywall IAP) ─ 7.10 (gating)        [trilha app]
7.11 (validação)              ── gate final desta fase
```

**Dependência de console:** 7.4–7.7 só funcionam com Stripe/Apple/Google configurados pelo Luis em [`08-guia-consoles-luis.md`](08-guia-consoles-luis.md). Faça o guia 08 **antes** de validar os webhooks.

## Resultado da fase

Entitlement único e canônico no Postgres, alimentado por 3 providers via webhooks idempotentes, concorrentes e tolerantes a fora-de-ordem; compra na web (Stripe, login antes) e in-app (Apple/Google IAP), todas convergindo para `is_premium()`; app conforme às diretrizes (vende IAP, honra web, sem anti-steering). Cliente nunca se autoconcede Premium nem força modelo caro.

Próximo: [`08-guia-consoles-luis.md`](08-guia-consoles-luis.md).

