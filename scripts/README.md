# Scripts SQL · Kairo

Schemas Postgres do projeto Kairo (Supabase). Rodar **na ordem numerada** no SQL Editor do Supabase.

## Ordem de execução

1. `01_profiles.sql` — tabela `profiles` + trigger que cria perfil no signup
2. `02_mensagens.sql` — histórico do Mentor
3. `03_praticas.sql` — `praticas` + `pratica_completadas`
4. `04_reflexoes.sql` — Jardim (manhã/tarde/noite)
5. `05_relatorios_semanais.sql` — cartas semanais do Mentor
6. `06_storage_avatares.sql` — bucket `profire` para avatares
7. `07_uso_ia.sql` — ledger server-side de uso de IA + função `is_premium()`
8. `08_subscriptions.sql` — Kairo Premium **multiplataforma**: tabela `subscriptions` agnóstica de provider (Stripe/Apple/Google) + `billing_events` (idempotência de todos os providers) + `is_premium()` (inclui `grace`) + RPC `aplicar_estado_assinatura()` (convergência cross-provider). Substitui a versão Stripe-only do doc 03 — ver [docs/07-billing-multiplataforma.md](../docs/07-billing-multiplataforma.md). Migra bancos antigos sem perder linhas.
9. `09_cron_relatorios.sql` — fila + dispatcher pg_cron/pg_net que mata o burst de domingo
10. `10_indices_revisao.sql` — auditoria de índices p/ 30k MAUs (sem efeito; registro de cobertura)
11. `11_migracao_categorias_enum.sql` — migra `praticas.categoria` de rótulos PT para enums ASCII estáveis
12. `12_billing_multiplataforma.sql` — billing agnóstico de provider (Apple/Google/Stripe): colunas novas em `subscriptions` + `billing_events` + `is_premium()` com `grace` + RPC `aplicar_estado_assinatura()`. Aditivo sobre o `08`.

> Após rodar o `09`, é obrigatório setar 2 GUC com `ALTER DATABASE postgres SET …` (ver cabeçalho do arquivo e `docs/06-runbook-deploy.md §6`). Sem isso o dispatcher é no-op silencioso por design.

## Banco vazio? Rode tudo de uma vez

No SQL Editor do Supabase, abra um query novo e cole o conteúdo dos arquivos em sequência. Todos são idempotentes (`if not exists`, `on conflict do nothing`, `drop policy if exists`), então rodar duas vezes não quebra nada.

## RLS

Toda tabela tem **Row Level Security ativo**. Cada usuário só enxerga / altera as próprias linhas via `auth.uid()`. Sem service-role-key no client.

## Edge Functions

Os arquivos SQL **não** incluem as edge functions. Elas vivem em `supabase/functions/`:

- `mentor-chat` — proxy para Claude (Haiku/Sonnet) com gating `is_premium` e rate-limit (20/h grátis, 120/h premium)
- `relatorio-semanal` — gera a carta semanal usando Sonnet
- `stripe-webhook` — converge `subscriptions` (Stripe) via RPC; `--no-verify-jwt`
- `apple-webhook` — App Store Server Notifications V2; `--no-verify-jwt`
- `google-webhook` — Google Play RTDN (Pub/Sub); `--no-verify-jwt`
- `verify-purchase` — desbloqueio imediato pós-compra IAP (verify-jwt)

Deploy: ver comandos e flags em [docs/06-runbook-deploy.md §3](../docs/06-runbook-deploy.md).

Variáveis de ambiente exigidas no Supabase (Project Settings → Edge Functions → Secrets):

- `ANTHROPIC_API_KEY`
- `SUPABASE_URL` (auto)
- `SUPABASE_ANON_KEY` (auto)
