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
8. *(reservado p/ Fase 03 — `08_subscriptions.sql`, billing Stripe)*
9. `09_cron_relatorios.sql` — fila + dispatcher pg_cron/pg_net que mata o burst de domingo
10. `10_indices_revisao.sql` — auditoria de índices p/ 30k MAUs (sem efeito; registro de cobertura)

> Após rodar o `09`, é obrigatório setar 2 GUC com `ALTER DATABASE postgres SET …` (ver cabeçalho do arquivo e `docs/06-runbook-deploy.md §6`). Sem isso o dispatcher é no-op silencioso por design.

## Banco vazio? Rode tudo de uma vez

No SQL Editor do Supabase, abra um query novo e cole o conteúdo dos arquivos em sequência. Todos são idempotentes (`if not exists`, `on conflict do nothing`, `drop policy if exists`), então rodar duas vezes não quebra nada.

## RLS

Toda tabela tem **Row Level Security ativo**. Cada usuário só enxerga / altera as próprias linhas via `auth.uid()`. Sem service-role-key no client.

## Edge Functions

Os arquivos SQL **não** incluem as edge functions. Elas vivem em `supabase/functions/`:

- `mentor-chat` — proxy para Claude (Haiku/Sonnet) com rate-limit (60/h)
- `relatorio-semanal` — gera a carta semanal usando Sonnet

Deploy pelas funções:

```bash
supabase functions deploy mentor-chat
supabase functions deploy relatorio-semanal
```

Variáveis de ambiente exigidas no Supabase (Project Settings → Edge Functions → Secrets):

- `ANTHROPIC_API_KEY`
- `SUPABASE_URL` (auto)
- `SUPABASE_ANON_KEY` (auto)
