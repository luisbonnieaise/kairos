# 08 · Guia de Consoles (Luis) — Stripe, Apple, Google, Supabase

Guia operacional **passo a passo** para configurar tudo que os webhooks da Fase 07 precisam: produtos, **API keys**, **webhooks com os eventos corretos** e secrets. Sem isso, os Edge Functions de [`07-billing-multiplataforma.md`](07-billing-multiplataforma.md) não funcionam.

> **Regra de ouro:** chave **secreta** (Stripe secret key, .p8 da Apple, JSON da service account Google, service role do Supabase) **nunca** entra no app Flutter nem em variável `NEXT_PUBLIC_*`. Só em **secrets** de Edge Function (Supabase) ou de servidor (Vercel).

**Legenda de destino do segredo:**
- 🟦 **Supabase** = Project Settings → Edge Functions → Secrets (ou `supabase secrets set`)
- ▲ **Vercel** = Project → Settings → Environment Variables (lp-kairo)
- 📱 **App** = `kairos/.env` (apenas valores públicos)

Faça **test/sandbox primeiro**, valide (PROMPT 7.11), só então repita em **produção/live**.

---

## 0. Ordem recomendada

```
1. Supabase (URLs, providers de auth, anon key)        → §4
2. Stripe (produto, prices, webhook, secrets)          → §1
3. Apple (subscription, .p8 API key, ASSN URL)         → §2
4. Google (produto, service account, Pub/Sub/RTDN)     → §3
5. Preencher a matriz de secrets                        → §5
6. Validar (runbook 7.11)
```

---

## 1. Stripe

Painel: https://dashboard.stripe.com — comece em **Test mode** (toggle no topo).

### 1.1 Produto e prices (1 produto, 6 prices)
1. **Product catalog → Add product**: nome `Kairo Premium`.
2. Crie **6 prices recorrentes** (3 moedas × 2 períodos):

| Moeda | Mensal | Anual |
|---|---|---|
| BRL | R$ 37,90 / mês | R$ 299,00 / ano |
| USD | (definir) / mês | (definir) / ano |
| EUR | (definir) / mês | (definir) / ano |

   - Para cada price: **Recurring**, intervalo Monthly ou Yearly, moeda correta.
   - O **trial de 7 dias** NÃO é configurado no price — ele vem do código (`trial_period_days: 7` no PROMPT 7.3). Não duplique.
3. Copie os **6 price IDs** (`price_...`).

### 1.2 API key (secret)
1. **Developers → API keys → Secret key** → revele e copie `sk_test_...`.
   → vai para ▲ Vercel `STRIPE_SECRET_KEY` **e** 🟦 Supabase `STRIPE_SECRET_KEY`.
   > A LP usa para criar a Session; o webhook usa para re-buscar o estado. Mesma chave.

### 1.3 Webhook (eventos corretos)
1. **Developers → Webhooks → Add endpoint**.
2. **Endpoint URL** = a URL pública do Edge Function:
   `https://<PROJECT_REF>.supabase.co/functions/v1/stripe-webhook`
3. **Select events** — marque exatamente:
   - `checkout.session.completed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.paid`
   - `invoice.payment_failed`
4. **Add endpoint** → abra o endpoint → **Signing secret** (`whsec_...`).
   → 🟦 Supabase `STRIPE_WEBHOOK_SECRET`.

### 1.4 Customer Portal (gerenciar/cancelar)
1. **Settings → Billing → Customer portal** → ativar (cancelamento, troca de plano, faturas). Útil para "Gerenciar assinatura" na web.

### 1.5 Go-live (depois de validar em test)
- Trocar o toggle para **Live**, recriar **prices** (ou ativar live), pegar **`sk_live_...`** e **recriar o webhook** no modo live (o `whsec_` é diferente). Atualizar os secrets.

**Stripe entrega:**

| Valor | Secret | Destino |
|---|---|---|
| `sk_test_...` / `sk_live_...` | `STRIPE_SECRET_KEY` | ▲ + 🟦 |
| `whsec_...` | `STRIPE_WEBHOOK_SECRET` | 🟦 |
| 6 × `price_...` | `STRIPE_PRICE_BRL_MONTHLY`/`_YEARLY`, `_USD_*`, `_EUR_*` | ▲ |

---

## 2. Apple (App Store Connect)

Pré-requisito: conta **Apple Developer Program** paga, app criado em App Store Connect com o **Bundle ID** do projeto iOS, e **Contratos Paid Apps** aceitos em **Business** (sem isso, IAP não funciona).

### 2.1 Assinatura auto-renovável
1. **App Store Connect → seu app → Monetization → Subscriptions**.
2. **Create Subscription Group** (ex.: `Kairo Premium`).
3. Dentro do grupo, **Create Subscription**:
   - **Mensal**: Product ID `app.kairo.premium.monthly`, duração 1 mês.
   - **Anual**: Product ID `app.kairo.premium.yearly`, duração 1 ano.
   - Defina preço por território, **Localized display name**, e a descrição.
4. (Opcional) **Introductory Offer → Free trial 7 dias** se quiser paridade com a web.
5. Anote os **Product IDs** → vão no app (PROMPT 7.8) e no Play (mantenha os mesmos nomes lógicos).

> Para a Apple **revisar** o IAP, o app precisa ser submetido com a compra implementada. Em desenvolvimento, use **Sandbox** (§2.4).

### 2.2 App Store Server API — chave .p8 (re-fetch canônico)
1. **App Store Connect → Users and Access → Integrations → App Store Connect API** → aba **In-App Purchase** (chave específica de IAP) → **Generate**.
2. Baixe o **`.p8`** (só baixa **uma vez**). Anote:
   - **Issuer ID** (topo da página) → `APPLE_ISSUER_ID`
   - **Key ID** da chave → `APPLE_KEY_ID`
   - Conteúdo do `.p8` → `APPLE_PRIVATE_KEY` (cole o PEM inteiro, com `-----BEGIN PRIVATE KEY-----`).
3. `APPLE_BUNDLE_ID` = bundle id do app; `APPLE_ENV` = `Sandbox` (test) / `Production` (live).
   → todos em 🟦 Supabase.

### 2.3 App Store Server Notifications V2 (webhook)
1. **App Store Connect → seu app → General → App Information → App Store Server Notifications**.
2. **Production Server URL** e **Sandbox Server URL** =
   `https://<PROJECT_REF>.supabase.co/functions/v1/apple-webhook`
3. **Version** = **Version 2** (obrigatório — o código espera V2).
4. Salvar. Use **"Request a Test Notification"** para validar a chegada no `apple-webhook`.

> Não há "lista de eventos" para marcar na Apple como na Stripe — a Apple envia **todos** os tipos (SUBSCRIBED, DID_RENEW, EXPIRED, DID_FAIL_TO_RENEW, REFUND, etc.). O código filtra e re-busca via App Store Server API.

### 2.4 Sandbox (teste)
1. **Users and Access → Sandbox → Test Accounts** → criar um Apple ID de teste.
2. No iPhone de teste, logar a conta Sandbox em **Settings → App Store → Sandbox Account**.
3. Comprar no app (build de debug) — não cobra de verdade; renovações são aceleradas (1 mês ≈ minutos).

**Apple entrega (todos 🟦 Supabase):**

| Valor | Secret |
|---|---|
| Conteúdo do `.p8` | `APPLE_PRIVATE_KEY` |
| Issuer ID | `APPLE_ISSUER_ID` |
| Key ID | `APPLE_KEY_ID` |
| Bundle ID | `APPLE_BUNDLE_ID` |
| `Sandbox`/`Production` | `APPLE_ENV` |

Product IDs (`app.kairo.premium.monthly/yearly`) → 📱 App (config dos produtos no PROMPT 7.8).

---

## 3. Google (Play Console + Google Cloud)

Pré-requisito: conta **Google Play Console** paga, app criado com o **package name** do projeto Android, e o app publicado pelo menos em **trilha interna (internal testing)** para testar IAP.

### 3.1 Produto de assinatura
1. **Play Console → seu app → Monetize → Products → Subscriptions → Create subscription**.
2. **Product ID** `premium` (com base plans):
   - Base plan **mensal** (auto-renovável, 1 mês) — ex. `monthly`.
   - Base plan **anual** (auto-renovável, 1 ano) — ex. `yearly`.
   - (Opcional) **Offer** de free trial 7 dias.
   - Defina preços por país e ative os base plans.
3. Anote o **Product ID** e os **base plan IDs** → app (PROMPT 7.8).

### 3.2 Service account (Play Developer API) — re-fetch canônico
1. **Google Cloud Console** (projeto vinculado ao Play): **APIs & Services → Library** → habilite **Google Play Android Developer API**.
2. **IAM & Admin → Service Accounts → Create service account** (ex.: `kairo-play-billing`).
3. Crie uma **chave JSON** (Keys → Add key → JSON) e baixe.
   → conteúdo do JSON em 🟦 Supabase `GOOGLE_SERVICE_ACCOUNT_JSON` (cole o JSON inteiro).
4. **Play Console → Users and permissions → Invite new user** → o e-mail da service account → permissões: **View financial data** + **Manage orders and subscriptions** (no app). Salvar e aguardar propagar (pode levar até ~24h na 1ª vez).
5. `GOOGLE_PACKAGE_NAME` = package name do app → 🟦 Supabase.

### 3.3 RTDN via Cloud Pub/Sub (webhook do Google)
O Google publica notificações num **tópico Pub/Sub**; o Pub/Sub faz **push** para o Edge Function.

1. **Google Cloud → Pub/Sub → Create topic** (ex.: `play-rtdn`).
2. **Permissão obrigatória:** no tópico, **Add principal** = `google-play-developer-notifications@system.gserviceaccount.com` com papel **Pub/Sub Publisher** (sem isso o Play não consegue publicar).
3. **Create subscription** no tópico:
   - **Delivery type = Push**.
   - **Endpoint URL** = `https://<PROJECT_REF>.supabase.co/functions/v1/google-webhook`
   - **Enable authentication** = ON → escolha/crie uma **service account** para o push; o Pub/Sub vai assinar um **OIDC token**. Defina **Audience** = a própria URL do `google-webhook`.
     → essa audience vai em 🟦 Supabase `GOOGLE_PUBSUB_AUDIENCE`.
4. **Play Console → seu app → Monetize → Monetization setup → Real-time developer notifications**:
   - **Topic name** = o nome completo do tópico: `projects/<GCP_PROJECT>/topics/play-rtdn`.
   - **Send test notification** → deve chegar no `google-webhook`.

> O `google-webhook` valida o **OIDC token** do push (assinatura Google + audience). Por isso o deploy é `--no-verify-jwt` (a verificação é própria, não o JWT do Supabase).

### 3.4 Teste
1. **Play Console → Setup → License testing** → adicione contas Gmail de teste (compras não cobram).
2. Instale o app pela **trilha interna** com a conta de teste e compre.

**Google entrega (todos 🟦 Supabase):**

| Valor | Secret |
|---|---|
| JSON da service account | `GOOGLE_SERVICE_ACCOUNT_JSON` |
| package name | `GOOGLE_PACKAGE_NAME` |
| URL do `google-webhook` (audience do push) | `GOOGLE_PUBSUB_AUDIENCE` |

Product/base plan IDs → 📱 App (PROMPT 7.8).

---

## 4. Supabase

### 4.1 Auth (mesma identidade web + app)
1. **Authentication → Providers**: habilite os **mesmos** providers no app e na LP (ex.: **Email/OTP** e, se usado, **Google**). A identidade tem que ser a mesma nos dois.
2. **Authentication → URL Configuration**: **Site URL** = domínio da LP (ex.: `https://kairoapp.com`); **Redirect URLs** = URLs de callback da LP (magic link) e o deep link do app.
3. **Leaked password protection** ligado (Fase 02).

### 4.2 Valores públicos
- **Project Settings → API**: `Project URL` e `anon public key`.
  → 📱 App `.env` (`SUPABASE_URL`, `SUPABASE_KEY`) e ▲ Vercel (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`).
- **service_role key** (mesma página) → **só** 🟦 Supabase (já disponível como secret automático nas Edge Functions). **Nunca** no app nem com `NEXT_PUBLIC`.

### 4.3 PROJECT_REF
- É o subdomínio do Project URL (`https://<PROJECT_REF>.supabase.co`). Você vai usá-lo nas URLs de webhook de Stripe/Apple/Google acima. (No projeto atual: `ojagemcqbekonwqjidkp`.)

### 4.4 Setar secrets e deployar
```bash
# secrets (repita os pares conforme a matriz §5)
supabase secrets set STRIPE_SECRET_KEY=sk_test_... STRIPE_WEBHOOK_SECRET=whsec_...
supabase secrets set APPLE_ISSUER_ID=... APPLE_KEY_ID=... APPLE_ENV=Sandbox APPLE_BUNDLE_ID=...
supabase secrets set APPLE_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
supabase secrets set GOOGLE_PACKAGE_NAME=app.kairo GOOGLE_PUBSUB_AUDIENCE=https://<REF>.supabase.co/functions/v1/google-webhook
supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON="$(cat service-account.json)"

# deploy (webhooks SEM jwt; verify-purchase COM jwt)
supabase functions deploy stripe-webhook  --no-verify-jwt
supabase functions deploy apple-webhook   --no-verify-jwt
supabase functions deploy google-webhook  --no-verify-jwt
supabase functions deploy verify-purchase
```

---

## 5. Matriz de secrets consolidada

| Secret | Valor | 🟦 Supabase | ▲ Vercel | 📱 App |
|---|---|:--:|:--:|:--:|
| `STRIPE_SECRET_KEY` | `sk_test/live_...` | ✅ | ✅ | — |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` | ✅ | — | — |
| `STRIPE_PRICE_BRL_MONTHLY` … `_EUR_YEARLY` | 6 × `price_...` | — | ✅ | — |
| `APPLE_PRIVATE_KEY` | conteúdo do `.p8` | ✅ | — | — |
| `APPLE_ISSUER_ID` / `APPLE_KEY_ID` | da chave de API | ✅ | — | — |
| `APPLE_BUNDLE_ID` / `APPLE_ENV` | bundle / Sandbox\|Production | ✅ | — | — |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | JSON da SA | ✅ | — | — |
| `GOOGLE_PACKAGE_NAME` | package name | ✅ | — | — |
| `GOOGLE_PUBSUB_AUDIENCE` | URL do google-webhook | ✅ | — | — |
| `NEXT_PUBLIC_SUPABASE_URL` / `_ANON_KEY` | API pública | — | ✅ | — |
| `SUPABASE_URL` / `SUPABASE_KEY` (anon) | API pública | — | — | ✅ |
| `SUPABASE_SERVICE_ROLE_KEY` | service role | ✅ (auto) | — | ❌ nunca |

IDs de produto (não são segredos, mas anote): Apple `app.kairo.premium.monthly/yearly`; Google `premium` + base plans `monthly/yearly`. Mantenha-os **consistentes** entre as lojas e o app.

---

## 6. Checklist de go-live (preencher)

Stripe
- [ ] Produto + 6 prices (live). Price IDs na Vercel: `____`
- [ ] Webhook live criado; `whsec_` (live) no Supabase
- [ ] `sk_live_` no Supabase e Vercel
- [ ] Customer Portal ativo

Apple
- [ ] Subscription group + mensal/anual aprovados
- [ ] `.p8` (Issuer/Key ID) no Supabase; `APPLE_ENV=Production`
- [ ] ASSN V2 (Production URL) configurado; teste recebido
- [ ] Contrato Paid Apps ativo

Google
- [ ] Subscription `premium` + base plans ativos
- [ ] Service account JSON no Supabase + permissão no Play concedida (propagada)
- [ ] Tópico Pub/Sub + publisher do Google + push autenticado (audience)
- [ ] RTDN apontando o tópico; teste recebido

Supabase / App
- [ ] Mesmos providers de auth no app e LP; Site/Redirect URLs corretos
- [ ] Secrets §5 setados; 4 funções deployadas (3 com `--no-verify-jwt`)
- [ ] Validação PROMPT 7.11 (idempotência, fora-de-ordem, convergência) ✔

---

## 7. Erros comuns (atalhos de depuração)

| Sintoma | Causa provável |
|---|---|
| Stripe webhook `400` | `STRIPE_WEBHOOK_SECRET` é de outro modo (test↔live) ou de outro endpoint |
| Apple webhook não chega | URL apontando para Sandbox em conta de produção (ou vice-versa); ASSN não está em **V2** |
| Apple `401` na Server API | `.p8`/Issuer/Key ID trocados, ou relógio do JWT fora de ~5 min |
| Google push não chega | Faltou dar **Pub/Sub Publisher** ao `google-play-developer-notifications@system.gserviceaccount.com` no tópico |
| Google `403` na Developer API | Permissão da service account no Play ainda não propagou, ou faltou "Manage orders" |
| Compra ok mas app não vira Premium | `appAccountToken`/`obfuscatedAccountId` não foi setado = `user.id`; ou `verify-purchase` não foi chamado |
| Premium some sozinho | Um provider rebaixou o outro — confirmar a regra de convergência da RPC (PROMPT 7.1) |

---

Volte ao [índice](README.md). Spec técnica em [`07-billing-multiplataforma.md`](07-billing-multiplataforma.md).
