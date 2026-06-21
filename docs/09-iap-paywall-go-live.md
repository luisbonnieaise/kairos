# 09 · IAP, Hard Paywall & Estado de Go-Live

> **Registro de implementação** (não é spec aspiracional). Documenta o que foi
> **efetivamente construído, deployado e configurado** na virada para billing
> via In-App Purchase + paywall de entrada, e o que ainda falta para o go-live.
>
> Spec de referência: [`07-billing-multiplataforma.md`](07-billing-multiplataforma.md).
> Consoles: [`08-guia-consoles-luis.md`](08-guia-consoles-luis.md).
> **Supersede** as partes de "checkout Stripe dentro do app" dos docs 03 e 06.

**Última atualização:** 04 de junho de 2026.

---

## 1. Decisões de produto/arquitetura tomadas

| Decisão | Resultado |
|---|---|
| **Bundle ID** | `com.thekairo.app` (o `com.kairo.app` estava registrado em outra conta Apple). Alinhado em iOS/Android/macOS/codemagic. |
| **Monetização** | **Sem plano free. Só teste de 7 dias**, depois assinatura. Mensal + anual. |
| **Paywall** | **Hard paywall de entrada**: sem assinatura ativa/trial, o app não abre. |
| **Pagamento mobile** | **IAP nativo** (StoreKit/Play Billing). Stripe **só na web** (`lp-kairo`). Cartão nunca é digitado no app (regra Apple 3.1.1). |
| **Entitlement** | Fonte única `public.subscriptions`, agnóstica de provider, escrita só por service role. `is_premium` concede acesso em `active|trialing|grace`. |
| **Config do cron** | Migrada de GUC `app.*` (bloqueado pelo Supabase) para tabela `public.app_config`. |

---

## 2. O que foi construído (código)

### Cliente (Flutter)
- **`lib/core/billing.dart`** — reescrito com `in_app_purchase`: `produtos()`,
  `comprar()` (carrega `appAccountToken`/`obfuscatedAccountId = user.id`),
  `restaurar()`, listener do `purchaseStream` → `verify-purchase`. `derivarPremium`
  inclui `grace`. (Removido o fluxo antigo de Stripe Checkout no navegador.)
- **`lib/telas/portao.dart`** (novo) — `TelaPortao`: paywall obrigatório entre login
  e app. Planos com preço da loja, "começar teste grátis", **restaurar**, **sair**
  (escape exigido pela Apple), sem voltar/pular, e **divulgação de termos** (3.1.2)
  com links de Termos/Privacidade.
- **`lib/telas/premium.dart`** — paywall IAP nativo (acessível pelo Perfil), sem
  link externo de pagamento (anti-steering).
- **Roteamento** (`main.dart`, `auth.dart`, `onboarding.dart`) — as 3 entradas
  passam pelo `TelaPortao`; ninguém chega no `TelaHome` sem entitlement.
- **`lib/core/kairo_tema.dart`** — fix: `CupertinoPageTransitionsBuilder` importado
  de `cupertino.dart` (migrou de `material.dart` no Flutter 3.44, PR flutter#179776).
  Sem isso o build quebra no Flutter 3.44+.

### Servidor (Supabase)
- **`scripts/12_billing_multiplataforma.sql`** — schema agnóstico: colunas
  `provider/product_id/provider_sub_id` em `subscriptions`, status `grace`/`expired`,
  tabela `billing_events` (dedupe unificado), `is_premium` com `grace`, e a RPC
  **`aplicar_estado_assinatura()`** (única porta de escrita, com regra de
  convergência multiplataforma).
- **Edge Functions novas:** `verify-purchase` (desbloqueio imediato, valida
  ownership), `apple-webhook` (ASSN V2, verifica JWS + **pino do root CA** via
  `APPLE_ROOT_CA_G3`), `google-webhook` (RTDN). Helpers em `_shared/`
  (`apple.ts`, `google.ts`, `billing.ts`, `cors.ts`).
- **`stripe-webhook`** — adaptado para a RPC + `billing_events`. `stripe-checkout`
  **removido** (checkout migrou para a `lp-kairo`).
- **`mentor-chat`** — gating do hard paywall: não-assinante recebe **403
  `precisa_assinar`** (antes servia Haiku grátis).
- **`scripts/09_cron_relatorios.sql`** — config do cron via `public.app_config`
  (RLS sem policies, lida pela função `security definer`) em vez dos GUCs `app.*`.

---

## 3. Estado operacional atual (Supabase — projeto `ojagemcqbekonwqjidkp`)

### Schema — ✅ completo
Scripts **01→12 aplicados** (incl. 07/08 que não haviam sido rodados antes, e o 12).
Todas as 11 tabelas com RLS. `subscriptions` só com policy `SELECT own` (sem write).

### Edge Functions deployadas
| Função | verify_jwt | Observação |
|---|---|---|
| `apple-webhook` | **false** | ASSN V2 (Apple chama sem JWT) |
| `verify-purchase` | true | exige JWT do usuário |
| `stripe-webhook` | **false** | re-deploy (RPC + billing_events) |
| `mentor-chat` | true | re-deploy (gating hard paywall) |
| `relatorio-semanal` | true | pegou o `CRON_SECRET` |
| `google-webhook` | — | **não deployada** (Android deferido) |

### Secrets configurados
- ✅ `ANTHROPIC_API_KEY`, `CRON_SECRET`
- ✅ `APPLE_PRIVATE_KEY`, `APPLE_KEY_ID` (`9UWTFHMVZ8`), `APPLE_ISSUER_ID`,
  `APPLE_BUNDLE_ID` (`com.thekairo.app`), `APPLE_ENV` (`Sandbox`), `APPLE_ROOT_CA_G3`
- ❌ `GOOGLE_*` (deferido), `STRIPE_SECRET_KEY`/`STRIPE_WEBHOOK_SECRET` (só p/ canal web)

### Cron das cartas semanais — ✅ configurado
- `pg_cron`/`pg_net` ativos; 2 jobs agendados (enfileirar domingo 00:00 UTC; dispatch/min).
- `public.app_config` com `cron_secret` + `cron_relatorio_url`. **Cartas voltam a
  fluir a partir do próximo domingo** (ou enfileiramento manual — ver `06 §6.3`).

> ⚠️ **Validação sandbox ainda não feita.** As integrações Apple/Google foram
> escritas conforme os contratos das APIs mas **nunca rodaram com compra real**.
> Tratar a 1ª rodada de sandbox como "a validar" (verificação JWS/x5c da Apple,
> re-fetch do Google).

---

## 4. Checklist de go-live restante

**Apple (console):**
- [ ] **Free Trial de 7 dias** (Introductory Offer) nos produtos `app.kairo.premium.monthly` e `.yearly`.
- [ ] **App Store Server Notifications V2** → `https://ojagemcqbekonwqjidkp.supabase.co/functions/v1/apple-webhook`.
- [ ] Contrato **Paid Apps** aceito (Business).

**App / build:**
- [ ] Build no Mac → **TestFlight** → **teste sandbox**: comprar → `verify-purchase` libera Premium em segundos.
- [ ] URLs reais de Termos/Privacidade no `portao.dart` (hoje placeholders `kairo.app/...`), após a `lp-kairo` publicar `/termos` e `/privacidade`.

**Auth no Studio (§5 do runbook — pendências reais encontradas):**
- [ ] **Site URL** está `http://localhost:3000` → trocar pela URL de produção.
- [ ] **Leaked password protection** desligada → ligar.
- [ ] **Confirm email** desligada → decidir (recomendado ligar).
- [ ] Redirect URLs com o domínio.

**Android (deferido):**
- [ ] `google-webhook` deploy + secrets `GOOGLE_*` + produto/base plans + RTDN.

**Go-live polish:**
- [ ] `delete-user` (limpeza de avatares no Storage ao deletar conta — `06 §8.3`).
- [ ] Plano Pro + backups/PITR; spend caps Anthropic/Supabase (`06 §8/§9`).

**Segurança (pós-sessão):**
- [ ] **Revogar a access token do Supabase** usada nesta sessão.
- [ ] **Regenerar a chave IAP** `SubscriptionKey_9UWTFHMVZ8` (vazou parcialmente em log) e re-setar `APPLE_PRIVATE_KEY`/`APPLE_KEY_ID`.
- [ ] Não commitar credenciais reais de tester em `APP_STORE_REVIEW_NOTES.md`.

---

## 5. Documentos legais

Rascunhos sob medida em [`legal/privacidade.md`](legal/privacidade.md) e
[`legal/termos.md`](legal/termos.md) (placeholders `{{...}}` a preencher). A
`lp-kairo` publica em `/privacidade` e `/termos`. Cobrem requisitos de loja +
LGPD/GDPR essencial; recomenda-se revisão jurídica. Inclui isenção de IA (o Mentor
não é aconselhamento profissional) + nota de crise.
