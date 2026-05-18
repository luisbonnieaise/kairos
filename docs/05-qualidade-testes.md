# 05 · Qualidade & Testes

**Prioridade 🟢 P2 (mas faça antes do go-live de pagamento).** Lógica de datas/semana/streak e billing não podem quebrar silenciosamente com 30k usuários pagando. Também limpa a higiene do repositório.

---

## PROMPT 5.1 — Testes da lógica crítica de datas/streak

```
Crie testes unitários (test/) para a lógica não-trivial e independente de
rede. Refatore minimamente APENAS o necessário para tornar testável (extrair
funções puras se estiverem acopladas a Supabase), sem mudar comportamento:

Cobrir:
- Cálculo de "hoje"/data string e janela dos últimos 7 dias
  (BancoPraticas._dataString, ultimos7Dias) — incluir virada de mês/ano e
  ordem [hoje..6 dias atrás].
- Cálculo de semana_inicio do client usado pela carta semanal (encontrar
  onde é calculado e testar contra a convenção validada na Fase 01).
- Lógica de derivação de premium no client (lib/core/billing.dart):
  status x current_period_end -> bool, incluindo expirado e trialing.

Use flutter_test. Cada teste com nome descritivo em português. Não mocke
Supabase — teste só funções puras.
```

**Critérios de aceitação**
- [ ] `flutter test` verde, cobrindo virada de mês/ano e casos de premium expirado/trial.
- [ ] Nenhuma mudança de comportamento em produção (apenas extração para testabilidade).

---

## PROMPT 5.2 — Testes das Edge Functions (lógica pura)

```
Para supabase/functions/, extraia em módulos auxiliares (ex.:
_shared/validacao.ts) as funções puras de:
- validação de semana_inicio (Fase 01/04),
- parsing/extração do JSON da carta (relatorio-semanal),
- decisão de modelo a partir de premium+preferência (mentor-chat).
Crie testes Deno (deno test) para esses módulos cobrindo casos de borda
(data futura, dia errado, JSON sujo com texto extra, premium false forçando
Haiku). Não chame rede. Documente como rodar (deno test) em
docs/06-runbook-deploy.md.
```

**Critérios de aceitação**
- [ ] `deno test` verde para as funções puras extraídas.
- [ ] Edge Functions continuam deployáveis (apenas refatoração de extração).
- [ ] Como rodar documentado no runbook.

---

## PROMPT 5.3 — Higiene do repositório

```
1. Adicione ao .gitignore: a linha supabase/.temp/ . Depois execute
   git rm -r --cached supabase/.temp e confirme que os arquivos saem do
   índice sem serem deletados do disco. (Não são segredos críticos, mas é
   lixo de CLI versionado.)
2. Atualize o README.md da raiz: substitua o boilerplate do Flutter por um
   README profissional do Kairo — o que é, stack, setup local (.env
   necessário, sem segredos no repo), como rodar scripts SQL, como deployar
   Edge Functions, ponteiro para docs/README.md. Use o estilo do
   scripts/README.md como referência de qualidade.
3. Em pubspec.yaml, troque description "A new Flutter project." por uma
   descrição real do Kairo.
Não toque em .env nem em qualquer secret.
```

**Critérios de aceitação**
- [ ] `git ls-files | grep supabase/.temp` vazio; arquivos ainda no disco.
- [ ] `README.md` descreve o Kairo de verdade e aponta para `docs/`.
- [ ] `pubspec.yaml` com descrição real.

---

## PROMPT 5.4 — CI mínima

```
Crie .github/workflows/ci.yml com um pipeline que, em push/PR:
- flutter pub get
- flutter analyze (falha em warning de novo? manter erro-only para começar)
- flutter test
- (job separado) deno check / deno test em supabase/functions/
Sem deploy automático (deploy é manual via runbook). Fixe versões de
Flutter/Deno. Documente no runbook que o CI deve estar verde antes do
go-live.
```

**Critérios de aceitação**
- [ ] Workflow roda `analyze` + `test` Flutter e `deno test` das funções.
- [ ] Sem credenciais no workflow; sem deploy automático.

---

Próximo: [`06-runbook-deploy.md`](06-runbook-deploy.md).
