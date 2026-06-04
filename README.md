# Kairo

> Sistema pessoal de evolução: um mentor sereno, um jardim de reflexões diárias, um dôjo de práticas e uma carta semanal do Mentor. Voltado a sustentar um ritmo — sem hype, sem barulho.

App Flutter (iOS/Android) com backend em Supabase (Postgres + Edge Functions Deno), IA via Claude (Anthropic) e assinatura Premium via **In-App Purchase** (Apple/Google) no mobile + Stripe na web. O acesso é por assinatura (teste de 7 dias, sem plano free) — ver [docs/09-iap-paywall-go-live.md](docs/09-iap-paywall-go-live.md).

---

## Stack

| Camada | Tecnologia |
|---|---|
| App | Flutter 3 (Material 3), 4 idiomas (pt/en/es/de) |
| Auth & DB | Supabase (Postgres + RLS) |
| Backend | Supabase Edge Functions (Deno + TypeScript) |
| IA | Claude Haiku / Sonnet (assinantes) via API Anthropic |
| Pagamento | IAP StoreKit/Play Billing (mobile) + Stripe (web); entitlement único em `subscriptions` |
| Cron | `pg_cron` + `pg_net` no Supabase (config em `app_config`) |
| Deep link | `kairo://` (Android + iOS) |

---

## Setup local

**Pré-requisitos:** Flutter SDK 3.x (Dart `^3.11.5`), Deno (opcional, para rodar testes das Edge Functions), Supabase CLI (opcional, para deploy).

1. **Clonar e instalar deps**
   ```bash
   git clone <repo> kairo
   cd kairo
   flutter pub get
   ```

2. **`.env`** (raiz do repo — **não versionado**, ver [.gitignore](.gitignore)):
   ```ini
   SUPABASE_URL=https://<projeto>.supabase.co
   SUPABASE_KEY=<anon key>
   ```
   Estes são os únicos secrets do client e ambos são públicos por design (anon key respeita RLS). **Nunca** colocar service role / Stripe / Anthropic aqui.

3. **Rodar:**
   ```bash
   flutter run
   ```

---

## Banco de dados

Schemas em [scripts/](scripts/), idempotentes, rodam **na ordem numerada** no SQL Editor do Supabase. Detalhes em [scripts/README.md](scripts/README.md).

| # | Arquivo | O que faz |
|---|---|---|
| 01 | `01_profiles.sql` | Perfil do usuário (1-para-1 com `auth.users`) |
| 02 | `02_mensagens.sql` | Histórico do Mentor |
| 03 | `03_praticas.sql` | Práticas + completadas diárias |
| 04 | `04_reflexoes.sql` | Jardim (manhã/tarde/noite) |
| 05 | `05_relatorios_semanais.sql` | Cartas semanais |
| 06 | `06_storage_avatares.sql` | Bucket de avatares |
| 07 | `07_uso_ia.sql` | Ledger server-side de uso de IA + `is_premium()` |
| 08 | `08_subscriptions.sql` | Tabela `subscriptions` + `stripe_events` (base do billing) |
| 09 | `09_cron_relatorios.sql` | Cron de carta semanal (50/min) + `app_config` (config do cron) |
| 10 | `10_indices_revisao.sql` | Auditoria de índices para 30k MAUs |
| 11 | `11_migracao_categorias_enum.sql` | Migração de `praticas.categoria` para enums ASCII |
| 12 | `12_billing_multiplataforma.sql` | Billing agnóstico de provider (Apple/Google/Stripe): `billing_events`, `is_premium` com `grace`, RPC `aplicar_estado_assinatura` |

Toda tabela tem **RLS ativo** — cada usuário só vê/edita as próprias linhas. Tabelas de billing (`subscriptions`, `billing_events`) e o ledger (`uso_ia`) **não têm policy de write** — só o backend (via service role) escreve.

---

## Edge Functions

Vivem em [supabase/functions/](supabase/functions/) (Deno + TypeScript). Lógica pura compartilhada em [_shared/](supabase/functions/_shared/) é testável via `deno test`.

| Função | Papel |
|---|---|
| `mentor-chat` | Conversa com o Mentor; gating de assinatura (`precisa_assinar`) + rate limit via `uso_ia` |
| `relatorio-semanal` | Carta semanal (modo usuário + modo CRON com `x-cron-secret`) |
| `verify-purchase` | Desbloqueio imediato pós-compra IAP (valida ownership, escreve entitlement) |
| `apple-webhook` | App Store Server Notifications V2 (verifica JWS + pino do root CA) |
| `google-webhook` | Real-time Developer Notifications do Google Play (RTDN) |
| `stripe-webhook` | Sincroniza `subscriptions` via RPC canônica (idempotente; canal web) |

Todos os caminhos de escrita do entitlement passam pela RPC `aplicar_estado_assinatura` (`billing_events` deduplica os 3 providers). Detalhes em [docs/07](docs/07-billing-multiplataforma.md) e [docs/09](docs/09-iap-paywall-go-live.md).

Deploy + matriz de secrets em [docs/06-runbook-deploy.md](docs/06-runbook-deploy.md).

---

## Testes

```bash
# Lógica pura Flutter (datas, semana, premium derivation)
flutter test

# Lógica pura Edge Functions (validação, parsing, modelo)
deno test supabase/functions/_shared/
```

CI roda os dois em todo push/PR — ver [.github/workflows/ci.yml](.github/workflows/ci.yml).

---

## Documentação

A história inteira de "base sólida → produto pago, seguro, 30k MAUs" está em [docs/](docs/) como plano executável (com prompts prontos). Ponto de entrada: [docs/README.md](docs/README.md).

| Fase | Conteúdo |
|---|---|
| 00 | [Visão & arquitetura](docs/00-visao-arquitetura.md) |
| 01 | [P0 — Custo & segurança](docs/01-p0-custo-seguranca.md) |
| 02 | [P1 — Hardening de lançamento](docs/02-p1-hardening.md) |
| 03 | [Stripe — Billing & Premium](docs/03-stripe-billing.md) |
| 04 | [Escala 30k MAUs](docs/04-escala-30k.md) |
| 05 | [Qualidade & testes](docs/05-qualidade-testes.md) |
| 06 | [Runbook de deploy & go-live](docs/06-runbook-deploy.md) |
| — | [Observabilidade](docs/observabilidade.md) (queries de uso e cron) |

---

## Princípios

- **Sem segredo no client.** Anon key respeita RLS; tudo que custa dinheiro (modelo IA, billing) decide no servidor.
- **Idempotência onde dói.** Webhook Stripe + cron de carta + ledger `uso_ia` — todos resistem a entrega dupla, fora-de-ordem e retry.
- **Tom zen no produto.** Mentor não grita; UI sem hype; sem markdown nas respostas da IA.
