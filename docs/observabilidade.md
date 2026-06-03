# Observabilidade · Kairo (30k MAUs)

Painel mínimo viável para detectar **custo descontrolado**, **abuso** e **falha silenciosa de cron** antes que vire incidente. Tudo aqui é **somente consulta** — nada cria objetos novos no banco.

A ponta de segurança *fora do app* (limites de gasto Anthropic/Supabase, alertas de billing) está em [`06-runbook-deploy.md §9`](06-runbook-deploy.md). Este documento é a ponta *dentro do app*: o que o time consulta no SQL Editor / dashboard para entender o que está acontecendo.

---

## 1. Custo de IA

A tabela `public.uso_ia` é o ledger canônico — escrito **somente pelas Edge Functions** via service role (a contagem é não-burlável). Cada linha é uma chamada faturável à Anthropic.

### 1.1 Chamadas por dia por função

```sql
select
  date_trunc('day', created_at)::date as dia,
  funcao,
  count(*) as chamadas
from public.uso_ia
where created_at >= now() - interval '30 days'
group by 1, 2
order by 1 desc, 2;
```

### 1.2 Chamadas por dia por modelo (proxy de custo)

```sql
select
  date_trunc('day', created_at)::date as dia,
  modelo,
  count(*) as chamadas
from public.uso_ia
where created_at >= now() - interval '30 days'
group by 1, 2
order by 1 desc, 2;
```

> **Cruzar com Anthropic Console:** consumo por modelo no console deve casar (±5%) com esta tabela. Divergência sistemática indica vazamento (chamada à Anthropic sem registro no ledger) — vasculhar logs das Edge Functions.

### 1.3 Top usuários por uso (últimos 7 dias)

Indica abuso pré-rate-limit (limites em [`01-p0-custo-seguranca.md`](01-p0-custo-seguranca.md): 20/h mentor não-premium; 3/24h relatório).

```sql
select
  user_id,
  funcao,
  count(*) as chamadas_7d
from public.uso_ia
where created_at >= now() - interval '7 days'
group by 1, 2
having count(*) > case when funcao = 'mentor-chat' then 200 else 10 end
order by chamadas_7d desc;
```

### 1.4 Estimativa de custo diário (calibrar tokens médios)

```sql
-- Substituir os custos por 1k tokens conforme a tabela atual da Anthropic
-- e os tokens médios efetivos observados (medir 100 chamadas reais e tirar
-- a média). Esses números são placeholders deliberados — atualizar quando
-- calibrado.
with custos as (
  select
    'claude-haiku-4-5-20251001'::text as modelo,
    1000::int as tokens_in_medio,
    300::int  as tokens_out_medio,
    0.001::numeric as usd_per_1k_in,
    0.005::numeric as usd_per_1k_out
  union all
  select 'claude-sonnet-4-6', 4000, 800, 0.003, 0.015
)
select
  date_trunc('day', u.created_at)::date as dia,
  sum(
    (c.tokens_in_medio  * c.usd_per_1k_in  / 1000.0) +
    (c.tokens_out_medio * c.usd_per_1k_out / 1000.0)
  )::numeric(10,2) as usd_estimado
from public.uso_ia u
join custos c on c.modelo = u.modelo
where u.created_at >= now() - interval '14 days'
group by 1
order by 1 desc;
```

---

## 2. Cron de cartas semanais (Fase 04)

A fila `public.cron_relatorios_fila` é o pulso do dispatcher. Em domingo, deve encher e depois drenar dentro da janela de espalhamento (~10h para 30k usuários a 50/min).

### 2.1 Estado atual da fila

```sql
select status, count(*) as linhas
from public.cron_relatorios_fila
group by status;
```

### 2.2 Taxa de drenagem da última execução

```sql
select
  semana_inicio,
  count(*) filter (where status = 'pendente') as pendentes,
  count(*) filter (where status = 'enviado')  as enviados,
  count(*) filter (where status = 'falhou')   as falharam,
  min(criado_em)::timestamptz as inicio,
  max(enviado_em)::timestamptz as fim_drenagem,
  max(enviado_em) - min(criado_em) as duracao_drenagem
from public.cron_relatorios_fila
group by semana_inicio
order by semana_inicio desc
limit 4;
```

### 2.3 Jobs pg_cron registrados

```sql
select jobname, schedule, active, jobid
from cron.job
where jobname like 'kairo_%';
```

### 2.4 Últimas execuções (sucesso/erro)

```sql
select
  j.jobname,
  r.status,
  r.return_message,
  r.start_time,
  r.end_time
from cron.job_run_details r
join cron.job j on j.jobid = r.jobid
where j.jobname like 'kairo_%'
order by r.start_time desc
limit 20;
```

---

## 3. Billing (Fase 03 — só após `08_subscriptions.sql`)

> As queries abaixo são **inertes** até a Fase 03 rodar. Quando rodarem, o gating server-side de [`01-p0-custo-seguranca.md`](01-p0-custo-seguranca.md) (`is_premium`) passa a habilitar Sonnet automaticamente para `subscriptions.status in ('active','trialing')`.

### 3.1 Assinaturas ativas

```sql
select status, count(*) as assinaturas
from public.subscriptions
group by status;
```

### 3.2 Receita recorrente aproximada (MRR)

Substituir o preço pelo valor mensal real do `price` Stripe (`STRIPE_PRICE_PREMIUM`).

```sql
-- placeholder: USD/mês por assinatura ativa
with preco as (select 9.99::numeric as usd_mes)
select
  count(*)             as assinantes_ativos,
  count(*) * (select usd_mes from preco) as mrr_usd
from public.subscriptions
where status in ('active','trialing')
  and current_period_end > now();
```

### 3.3 Latência do webhook (média/p95 dos últimos 7d)

A medição depende dos logs do Supabase para a função `stripe-webhook` (Studio → Edge Functions → Logs → métricas). Não há SQL puro — usar o dashboard do Supabase ou exportar.

---

## 4. Limiares de alerta sugeridos

Configurar como **alertas** nos consoles correspondentes; quando dispararem, ir ao runbook de rollback ([§10 do runbook](06-runbook-deploy.md#10-rollback)).

| Métrica | Limiar p/ alerta | Onde configurar | Reação |
|---|---|---|---|
| Gasto Anthropic / dia | `> alvo_diário × 1.5` | Anthropic Console → Billing → Usage limits | Investigar uso_ia §1.3; considerar baixar rate limits |
| Chamadas `mentor-chat` / hora (global) | `> 30k × 20 ÷ 24 × 2` | Supabase Reports / query agendada | Possível abuso coordenado; conferir top users §1.3 |
| Chamadas `relatorio-semanal` em dia não-domingo | `> 100/dia` | Query agendada | Cron caiu para modo usuário e algo dispara em massa |
| Fila cron pendente após 12h da execução | `> 10% do enfileirado` | Query §2.1/§2.2 vs. expectativa | Dispatcher travado: ver `cron.job_run_details` §2.4 |
| Erros 5xx das Edge Functions | `> 2% das requisições /5min` | Supabase → Edge Functions → Logs (alertas) | Conferir logs; rollback se for da última deploy |
| Erro webhook Stripe (Fase 03) | `> 1%` por 10 min | Stripe Dashboard + Supabase logs | Re-checar STRIPE_WEBHOOK_SECRET / signing |
| Falha de pagamento Stripe (Fase 03) | qualquer pico (diff > 3× baseline) | Stripe Dashboard | Tipicamente cartão expirado em massa; sem ação técnica |

---

## 5. Como esta página convive com os alertas externos

Esta página cobre **observabilidade dentro do banco** (uso_ia, fila de cron, subscriptions). Os alertas *fora do app* (limites de gasto, spend caps) ficam em [`06-runbook-deploy.md §9 "Alertas de custo"`](06-runbook-deploy.md#9-alertas-de-custo) e são responsabilidade do dono preencher.

Princípio: **uso_ia é a fonte da verdade interna**; Anthropic Console é a fonte externa. Discrepância sustentada entre as duas indica vazamento — vasculhar logs das Edge Functions.

