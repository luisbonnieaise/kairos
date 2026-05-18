# 02 · P1 — Hardening de Lançamento

**Prioridade 🟡 P1. Antes de abrir ao público.** Corrige fluxo de autenticação que pode quebrar com confirmação de e-mail, endurece senha, e elimina vazamento de erro residual.

Arquivos afetados:
- [lib/telas/auth.dart](../lib/telas/auth.dart)
- [lib/telas/onboarding.dart](../lib/telas/onboarding.dart)
- [lib/main.dart](../lib/main.dart)
- Config do Supabase Auth (painel — documentado no runbook)

---

## PROMPT 2.1 — Fluxo de signup resiliente a confirmação de e-mail

```
Hoje em lib/telas/auth.dart o fluxo de cadastro chama supabase.auth.signUp e
em seguida BancoPerfil.atualizar() + navega para TelaOnboarding, ignorando o
caso em que a confirmação de e-mail está ativada (sem sessão -> chamadas
autenticadas falham silenciosamente e o onboarding abre sem usuário).

Implemente um fluxo correto que funcione nos DOIS modos do Supabase
(confirmação de e-mail ligada ou desligada):

1. Após signUp, inspecione o retorno (AuthResponse): se response.session == null
   E response.user != null -> confirmação de e-mail está ativa. Nesse caso:
   - NÃO tente BancoPerfil.atualizar (não há sessão).
   - Mostre uma tela/estado "Confirme seu e-mail" reusando o padrão visual de
     _SheetRecuperarSenha (mensagem traduzível: verifique a caixa de entrada,
     com botão "voltar ao login").
   - Não navegue para o onboarding.
2. Se response.session != null -> sessão imediata: mantenha o fluxo atual
   (salvar idioma + ir para onboarding).
3. Adicione as chaves de tradução novas em lib/core/i18n.dart para PT/EN/ES/DE
   seguindo o padrão existente (confirmeSeuEmail, enviamosConfirmacao, etc.).
4. Trate o login (signInWithPassword) de e-mail não confirmado: o Supabase
   retorna erro "email not confirmed" -> traduza em _traduzirErro para uma
   mensagem clara pedindo confirmação, com ação de reenviar
   (supabase.auth.resend).

Não altere o visual além do necessário; reaproveite estilos KT/KC.
```

**Critérios de aceitação**
- [ ] Com confirmação de e-mail **ligada**: cadastro mostra tela "confirme seu e-mail", não abre onboarding, não dispara chamada autenticada.
- [ ] Com confirmação **desligada**: fluxo atual intacto (onboarding abre).
- [ ] Login com e-mail não confirmado mostra mensagem clara + opção de reenviar.
- [ ] Novas chaves i18n nos 4 idiomas; `flutter analyze` limpo.

---

## PROMPT 2.2 — Política de senha mais forte (client)

```
Em lib/telas/auth.dart, eleve o mínimo de senha de 6 para 8 caracteres e
exija ao menos uma letra e um número (validação local, mensagem traduzível
senhaRegra). Atualize as chaves i18n nos 4 idiomas. Não bloqueie caracteres
especiais. Mantenha a UX de erro existente (Text KC.aka).
```

**Critérios de aceitação**
- [ ] Senha < 8 ou sem letra+número → erro local antes de chamar Supabase.
- [ ] Mensagem traduzida nos 4 idiomas.

---

## PROMPT 2.3 — Configuração de Auth no painel (documentar no runbook)

```
Adicione em docs/06-runbook-deploy.md uma seção "Supabase Auth (painel)"
com os ajustes a aplicar manualmente antes do go-live:
- Authentication > Providers > Email: decidir e registrar se confirmação de
  e-mail fica LIGADA (recomendado para produção) — e o fluxo da 2.1 cobre
  ambos os casos.
- Authentication > Policies: habilitar "Leaked password protection"
  (HaveIBeenPwned).
- Definir Site URL e Redirect URLs corretos (deep link do app para reset de
  senha / confirmação).
- Rate limits de Auth (signup/OTP) revisados para 30k MAUs.
Apenas documentar (sem código).
```

**Critérios de aceitação**
- [ ] Seção "Supabase Auth (painel)" no runbook com itens acionáveis e decisão sobre confirmação de e-mail registrada.

---

## PROMPT 2.4 — Varredura final de vazamento de erro

```
Faça uma varredura em supabase/functions/ e lib/ por respostas/logs que
exponham detalhes internos ao client:
- Edge Functions devem retornar mensagens genéricas e estáveis
  ('mentor_erro','data_invalida','rate_limit','erro_interno'); detalhes só
  em console.error (server). Confirme que nenhuma rota retorna objetos de
  erro de terceiros (Anthropic/Stripe/Postgrest) ao client.
- No client, garanta que debugPrint com dados sensíveis esteja sob
  kDebugMode quando aplicável.
Liste o que encontrou e corrija. Não altere contratos de sucesso.
```

**Critérios de aceitação**
- [ ] Nenhuma Edge Function retorna objeto de erro de terceiro ao client.
- [ ] Mensagens de erro padronizadas e traduzíveis.
- [ ] `flutter analyze` limpo; funções deployáveis.

---

Próximo: [`03-stripe-billing.md`](03-stripe-billing.md).
