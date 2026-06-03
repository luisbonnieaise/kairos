# 01 · P0 — Custo & Segurança

**Prioridade 🔴 P0. Bloqueia escala.** Fecha os 3 vetores onde um único cliente malicioso infla a fatura da Anthropic sem teto, e cria o ponto de gating server-side que a Fase 03 reusa.

Pré-requisito: ter lido [`00-visao-arquitetura.md`](00-visao-arquitetura.md) §4 e §5.

Arquivos afetados:
- [supabase/functions/mentor-chat/index.ts](../supabase/functions/mentor-chat/index.ts)
- [supabase/functions/relatorio-semanal/index.ts](../supabase/functions/relatorio-semanal/index.ts)
- [lib/core/claude_api.dart](../lib/core/claude_api.dart)
- Novo: `scripts/07_uso_ia.sql`

---

## Problema → Solução

| # | Vetor (hoje) | Correção |
|---|---|---|
| 4.1 | `usarSonnet` vem do client → força modelo caro | Modelo decidido server-side por `is_premium()`. Até a Fase 03 entrar, Sonnet fica **desligado para todos** no Mentor (fallback Haiku) |
| 4.3 | Rate limit conta `mensagens` (preenchida pelo client) → burlável | Ledger server-side `uso_ia`, escrito **pela própria Edge Function** |
| 4.2 | `relatorio-semanal` sem rate limit + `semana_inicio` arbitrário | Validar data (recente, dia plausível) + rate limit no `uso_ia` + idempotência já existente |
| 4.4 | Burst de domingo | Mitigado de fato na Fase 04 (cron). Aqui só o rate limit reduz o dano |

---

## PROMPT 1.1 — Ledger server-side de uso de IA

```
Crie o arquivo scripts/07_uso_ia.sql com uma tabela de auditoria/rate-limit de
chamadas de IA, escrita SOMENTE pelas Edge Functions (nunca pelo client).

Requisitos do schema:
- Tabela public.uso_ia:
  id          uuid primary key default gen_random_uuid()
  user_id     uuid not null references auth.users(id) on delete cascade
  funcao      text not null check (funcao in ('mentor-chat','relatorio-semanal'))
  modelo      text not null
  created_at  timestamptz not null default now()
- Índice (user_id, funcao, created_at desc) para a contagem por janela.
- RLS habilitado. NENHUMA policy de insert/update/delete para o client.
  Crie apenas uma policy de SELECT da própria linha (uso_ia_select_own,
  using auth.uid() = user_id) para futura tela de histórico. A escrita será
  feita pelas Edge Functions via service role (bypassa RLS) — não criar
  policy de insert.
- Idempotente (create table if not exists, drop policy if exists). Cabeçalho
  no mesmo estilo dos outros scripts (banner ASCII "Kairo · 07_uso_ia.sql").

Não rode nada — apenas crie o arquivo. Atualize scripts/README.md adicionando
o item 7 na lista de ordem de execução.
```

**Critérios de aceitação**
- [ ] `scripts/07_uso_ia.sql` existe, idempotente, mesmo estilo dos demais.
- [ ] RLS on; só policy de SELECT own; sem policy de INSERT.
- [ ] `scripts/README.md` lista o passo 7.

---

## PROMPT 1.2 — Função SQL de gating `is_premium`

```
Adicione ao FINAL de scripts/07_uso_ia.sql a função canônica de gating de
assinatura, projetada para funcionar ANTES e DEPOIS da Fase 03:

create or replace function public.is_premium(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.subscriptions s
    where s.user_id = uid
      and s.status in ('active','trialing')
      and s.current_period_end > now()
  );
$$;

Como a tabela public.subscriptions só será criada na Fase 03, proteja a função
contra "relation does not exist": envolva o select em um bloco que, se a
tabela subscriptions ainda não existir, retorne false. Implemente via
plpgsql com EXCEPTION WHEN undefined_table THEN return false; mantendo
security definer e search_path = public. A função deve ser segura para ser
chamada já agora (retornando false para todos até a Fase 03 popular billing).

Conceda execute para authenticated e service_role.
```

**Critérios de aceitação**
- [ ] `is_premium(uuid)` existe, `security definer`, `search_path = public`.
- [ ] Chamar `select public.is_premium(auth.uid())` hoje retorna `false` sem erro mesmo sem a tabela `subscriptions`.
- [ ] `grant execute` para `authenticated` e `service_role`.

> Rode `scripts/07_uso_ia.sql` no SQL Editor do Supabase antes do PROMPT 1.3.

---

## PROMPT 1.3 — `mentor-chat`: modelo server-side + rate limit real

```
Refatore supabase/functions/mentor-chat/index.ts:

1. REMOVA toda confiança em corpo.usarSonnet. O modelo passa a ser decidido
   no servidor:
   - Crie um client Supabase com SERVICE ROLE
     (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) APENAS para chamar a função
     de gating e gravar o ledger. Continue usando o client autenticado com o
     JWT do usuário para ler profiles (mantém RLS).
   - premium = resultado de: supabaseService.rpc('is_premium', { uid: user.id }).
   - modelo = premium ? MODELO_SONNET : MODELO_HAIKU.
   - Aceite um campo opcional corpo.prefereSonnet apenas como "intenção";
     ele só tem efeito se premium === true. Não-premium SEMPRE Haiku.

2. SUBSTITUA o rate limit atual (que conta a tabela mensagens) por um ledger
   confiável:
   - Antes de chamar a Anthropic, conte em public.uso_ia (via service role)
     as linhas do usuário para funcao='mentor-chat' na última 1 hora.
   - Limites: não-premium = 20/h; premium = 120/h. Se exceder, retorne 429
     com a mensagem traduzível 'rate_limit'.
   - APÓS resposta OK da Anthropic, INSIRA uma linha em public.uso_ia
     (user_id, funcao='mentor-chat', modelo) via service role. O ledger é
     escrito pela função, não pelo client — é isso que torna o limite
     não-burlável.

3. Não vaze erro cru: em falha da Anthropic, logue server-side com
   console.error e retorne { error: 'mentor_erro' } com status apropriado.
   Não retorne o objeto claudeData.

4. Mantenha CORS, validação de tamanho/role e o system prompt existentes.

Mantenha o estilo e os comentários em português do arquivo.
```

**Critérios de aceitação**
- [ ] Enviar `usarSonnet:true`/`prefereSonnet:true` como não-premium → resposta gerada por Haiku (verificar via log do modelo escolhido).
- [ ] 21ª chamada em 1h como não-premium → `429 {"error":"rate_limit"}`.
- [ ] Cada chamada bem-sucedida grava 1 linha em `uso_ia` (consultar como o próprio usuário via policy de SELECT).
- [ ] Erro da Anthropic não vaza `claudeData` ao client.
- [ ] Cliente que nunca chama `BancoMensagens.salvar` ainda assim é limitado.

---

## PROMPT 1.4 — `relatorio-semanal`: validação de data + rate limit

```
Endureça supabase/functions/relatorio-semanal/index.ts:

1. Validação de semana_inicio (defesa contra custo ilimitado):
   - Já existe regex ISO_DATE. Adicione: a data deve ser uma SEGUNDA-FEIRA
     (getUTCDay()===1) OU domingo conforme a convenção atual do app —
     inspecione como o client calcula semana_inicio em
     lib/core/banco.dart / telas e ALINHE a validação a essa convenção
     (documente qual escolheu em comentário).
   - A data não pode estar no futuro nem mais de 366 dias no passado.
   - Se inválida, retorne 400 'data_invalida' e NÃO chame a Anthropic.

2. Rate limit via public.uso_ia (service role), igual padrão da 1.3:
   - Máx 3 gerações por usuário por 24h (a idempotência por semana já evita
     custo repetido da MESMA semana; o limite cobre datas distintas).
   - Grave linha em uso_ia (funcao='relatorio-semanal') só quando
     efetivamente chamar a Anthropic (não quando devolver carta já existente).

3. Mantenha a idempotência existente (retornar carta da semana se já existe,
   sem chamar Claude e sem gravar no ledger).

4. Não vaze erro cru da Anthropic (mesma regra da 1.3).

Use SUPABASE_SERVICE_ROLE_KEY só para o ledger/gating; mantenha o client
autenticado por JWT para os dados do usuário (RLS).
```

**Critérios de aceitação**
- [ ] `semana_inicio` futura, mal formada ou fora da janela → `400 data_invalida`, sem chamar Claude.
- [ ] 4ª data distinta em 24h → `429`.
- [ ] Re-pedir carta de semana já gerada → retorna a existente, **sem** nova linha em `uso_ia`.
- [ ] Convenção de dia da semana documentada em comentário e coerente com o client.

---

## PROMPT 1.5 — Limpar a flag no client

```
Em lib/core/claude_api.dart e nos chamadores:
- Renomeie o parâmetro usarSonnet para prefereSonnet e documente no dartdoc
  que é apenas uma PREFERÊNCIA: o servidor decide o modelo conforme a
  assinatura; clientes não-premium sempre recebem Haiku.
- Garanta que nenhuma tela dependa de forçar Sonnet. Faça uma busca por
  usarSonnet em lib/ e ajuste todos os usos.
Não altere comportamento de UI além do necessário.
```

**Critérios de aceitação**
- [ ] `grep -rn "usarSonnet" lib/` retorna vazio.
- [ ] `flutter analyze` sem novos erros.
- [ ] App compila; Mentor continua funcionando (modo Haiku para todos enquanto Fase 03 não entra).

---

## PROMPT 1.6 — Alertas de custo (não-código, registrar como feito)

```
Gere um checklist em docs/06-runbook-deploy.md (seção "Alertas de custo")
caso ainda não exista, listando:
- Anthropic Console > Billing > usage limits / spend alerts configurados.
- Supabase > Billing > spend cap / alertas de uso de Edge Functions e DB.
- Limite mensal alvo definido (placeholder a preencher pelo dono).
Apenas documente; não há código.
```

**Critérios de aceitação**
- [ ] Seção "Alertas de custo" presente no runbook com itens acionáveis.

---

## Resultado da fase

Após 1.1–1.6: nenhum cliente consegue forçar Sonnet, nenhum rate limit é burlável, `relatorio-semanal` não aceita data arbitrária, erros não vazam, e existe `is_premium()` pronto para a Fase 03 plugar a monetização.

Próximo: [`02-p1-hardening.md`](02-p1-hardening.md) ou, em paralelo, [`03-stripe-billing.md`](03-stripe-billing.md).

