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

A geração da carta semanal saiu do client (que disparava 30k chamadas no domingo) para um par **enfileirar + dispatcher** rodando dentro do banco (`pg_cron` + `pg_net`). A Edge Function `relatorio-semanal` ganhou um **modo CRON** que entra quando o header `x-cron-secret` confere com o secret configurado — fora desse caminho, o modo usuário (JWT) continua existindo como fallback manual.

### 6.1 Setup (uma vez por ambiente)

1. **Gerar o secret** (use 32+ bytes aleatórios; nunca reuse entre ambientes):
   ```bash
   openssl rand -hex 32
   ```
2. **Setar como Edge Function secret** (a função lê de `Deno.env.get('CRON_SECRET')`):
   ```bash
   supabase secrets set CRON_SECRET=<valor-gerado>
   ```
3. **Rodar `scripts/09_cron_relatorios.sql`** no SQL Editor (idempotente). Isso cria a fila, o enfileirador, o dispatcher e agenda os dois jobs.
4. **Setar os 2 GUC** no banco — sem eles o dispatcher é **no-op silencioso por design** (evita disparo acidental antes do setup):
   ```sql
   ALTER DATABASE postgres SET app.cron_secret      = '<MESMO valor da etapa 1>';
   ALTER DATABASE postgres SET app.cron_relatorio_url
     = 'https://<projeto>.supabase.co/functions/v1/relatorio-semanal';
   -- Aplicar nas conexões atuais (próximas conexões herdam):
   SELECT pg_reload_conf();
   ```

### 6.2 Checklist

- [ ] `pg_cron`/`pg_net` habilitados; `09_cron_relatorios.sql` aplicado.
- [ ] `CRON_SECRET` setado nos Edge Function secrets.
- [ ] `app.cron_secret` e `app.cron_relatorio_url` setados via `ALTER DATABASE` (valores idênticos ao secret das funções).
- [ ] Horário/fuso do job definido: **`00:00 UTC, domingo`** (default do script — alterar via novo `cron.schedule` se necessário; documentar a expressão escolhida aqui).
- [ ] Execução manual de teste validada (ver §6.3).

### 6.3 Validar uma execução manual

```sql
-- (a) Confirma que os dois jobs estão agendados:
select jobname, schedule, active from cron.job where jobname like 'kairo_%';

-- (b) Roda o enfileirador agora (sem esperar domingo). Devolve a contagem
--     de linhas inseridas. Idempotente: rodar 2x devolve 0 da segunda vez.
select public.enfileirar_relatorios_semanais();

-- (c) Inspeciona a fila:
select status, count(*) from public.cron_relatorios_fila group by 1;

-- (d) Roda o dispatcher 1 vez (lote 5) e confirma o disparo via pg_net:
select public.dispatch_relatorios_pendentes(5);

-- (e) Verifica que as cartas vieram (idempotência por user_id/semana_inicio):
select user_id, semana_inicio, created_at
  from public.relatorios_semanais
  order by created_at desc limit 10;

-- (f) Aborta o cron rapidamente, se necessário:
-- select cron.unschedule('kairo_dispatch_relatorios_pendentes');
-- select cron.unschedule('kairo_enfileirar_relatorios_semanais');
```

> **Espalhamento** (documentado no cabeçalho de `09_cron_relatorios.sql`): dispatcher consome **50 por minuto** → ~3.000/h → 30.000 usuários em ~10h. Bem abaixo do rate limit típico da Anthropic e da concorrência da função. Ajustar via `dispatch_relatorios_pendentes(<N>)` no `cron.schedule` se o perfil de uso mudar.

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

Dimensionamento de referência para 30k MAUs. Reaferir quando o ramp passar de 10k.

### 8.1 Plano

**Pro** atende a Fase 04. Subir para **Team** quando precisar de SSO, role-based access ou suporte com SLA — não há barreira técnica de 30k MAU no Pro.

| Recurso | Estimativa 30k MAUs | Pro inclui | Margem |
|---|---|---|---|
| Auth MAU | 30.000 | 100.000 | folgada |
| Edge Function invocations / mês | ~1.3M (mentor-chat ~1M, relatorio-semanal ~120k, dispatcher ~30k POSTs) | 2M | ~50% |
| DB size (ano 1) | ~35 GB (mensagens dominantes; ver §8.5) | 8 GB | excedente cobrado a US$0.125/GB·mês |
| Egress | ~60 GB/mês (avatares) | 250 GB | folgada |
| Storage | ~6 GB (30k × ~200 KB de avatar médio) | 100 GB | folgada |

> Médias derivadas das premissas da Fase 04 §1. Calibrar com `uso_ia` e `pg_stat_*` quando real >5k MAUs.

- [ ] **Plano Pro confirmado** no Project Settings → Billing.
- [ ] Cap de gasto habilitado (ver §9) — defesa contra spike de DB/egress.

### 8.2 Connection pooling — verificado

Edge Functions acessam o banco **exclusivamente via `@supabase/supabase-js` → PostgREST** (HTTP/REST). Nenhuma `pg.Client`/`postgres` direta com conexão persistente. Verificado em:
- [supabase/functions/mentor-chat/index.ts](../supabase/functions/mentor-chat/index.ts)
- [supabase/functions/relatorio-semanal/index.ts](../supabase/functions/relatorio-semanal/index.ts)

PostgREST faz pooling do lado do Supabase; cada chamada HTTP do Function gasta uma conexão por ~ms e devolve. Não há risco de esgotar `max_connections` mesmo no spike de cron (50 req/min do dispatcher + tráfego de usuário).

- [x] Confirmado: zero conexão direta persistente nas Edge Functions.

### 8.3 Storage — limpeza ao deletar conta

O cascade de `auth.users` apaga linhas em `profiles`, `mensagens`, `praticas`, `pratica_completadas`, `reflexoes`, `relatorios_semanais`, `uso_ia`, `cron_relatorios_fila` (todas referenciam `auth.users(id) on delete cascade`). **Mas objetos do bucket `profire` (avatares) NÃO são apagados por cascade SQL** — Storage é S3, não está no banco.

Hoje:
- `BancoAvatar.remover()` ([lib/core/banco.dart:110](../lib/core/banco.dart#L110)) apaga o arquivo no fluxo de "remover avatar" pela UI.
- Não há cleanup automático na rota de deletar a conta inteira.

- [ ] **TODO antes do go-live**: trigger SQL em `auth.users` (ou Edge Function admin) que, ao deletar usuário, lista e remove `profire/<user_id>/*` via Storage API. Caminho mínimo: Edge Function `delete-user` (service role) que faz `supabase.storage.from('profire').list('<user_id>/')` + `remove(...)` antes do `auth.admin.deleteUser(...)`. Fluxo da UI passa por essa função.
- [ ] Política de tamanho do avatar definida no upload (já hoje: aceita qualquer tamanho — adicionar limite de ~2 MB no cliente para conter egress/storage).

### 8.4 Backups / PITR

- [ ] **Daily backups** habilitados (default no Pro — confirmar em Project Settings → Database → Backups).
- [ ] **Point-in-Time Recovery (PITR)** habilitado antes do go-live (add-on pago no Pro). Justificativa: a tabela `relatorios_semanais` é conteúdo único gerado por IA — perda de 24h de backup diário pode significar perda de cartas que custaram chamadas pagas à Anthropic e que o usuário esperava ler.

### 8.5 Retenção e crescimento de tabela (follow-up pós-Fase 04)

A maior fonte de crescimento é `public.mensagens` (~22 GB/ano no cenário 30k MAUs). Não é desta fase, mas registrar:

- [ ] Decidir, antes do ano 2, política de retenção de `mensagens` (ex.: manter 12 meses no quente; arquivar/deletar mais antigo). O Mentor não usa histórico > N msgs no contexto — não há perda funcional.
- [ ] `uso_ia` cresce ~2 GB/ano; manter integralmente (auditoria de custo retroativa vale mais que o GB).
- [ ] `cron_relatorios_fila` cresce ~1.5M linhas/ano. Adicionar limpeza periódica de linhas `status='enviado'` > 90 dias na Fase 05 ou via cron extra.

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
