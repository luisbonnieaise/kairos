# App Store Review Information — Kairo Pro Monthly

Conteúdo pronto para colar nos campos **Review Information** da assinatura
(`app.kairo.premium.monthly`) no App Store Connect.

---

## Review Notes (campo "Review Notes")

> **How to reach the subscription paywall**
>
> 1. Launch the app and sign in with the demo account below
>    (or tap "Create account" to register a new one).
> 2. On the Home screen, tap the **avatar / profile icon** at the top.
> 3. On the Profile screen, tap the **membership status row**
>    (labeled "Free", with a "›" chevron).
> 4. The paywall opens and lists the auto-renewable subscriptions
>    (**Kairo Pro Monthly** and **Kairo Pro Yearly**), with prices coming
>    from the App Store. A **"Restore Purchases"** button is always visible.
>
> **Demo account**
> Email: review@kairo.app
> Password: Review1234
>
> **Subscription details**
> - Product: Kairo Pro Monthly (auto-renewable, 1 month).
> - Unlocks: Mentor with the advanced model (Claude Sonnet), the weekly
>   Mentor letter, and higher daily usage limits.
> - Purchase is made exclusively through Apple In-App Purchase (StoreKit).
>   There are no external payment links or steering inside the app.
> - The app requires an internet connection (backend on Supabase).
>
> Thank you for reviewing Kairo.

---

## Screenshot (campo "Screenshot")

A Apple exige um print mostrando **onde a assinatura aparece dentro do app** —
ou seja, a tela da paywall (`TelaPremium`).

**Como capturar:**
1. Rode o app no simulador/dispositivo com o ambiente **StoreKit / Sandbox**
   configurado, para os produtos carregarem com preço.
2. Navegue: Login → Home → avatar → Perfil → item "Free" → Paywall.
3. Tire o screenshot da paywall mostrando os planos **Monthly/Yearly** e o
   botão **Restore Purchases**.

> Dica: se os produtos ainda não aparecem (status "Prepare for Submission"),
> use um **StoreKit Configuration File** no Xcode para renderizar a paywall
> com preços de teste só para o screenshot.

---

## Checklist antes de submeter

- [ ] Conta de teste `review@kairo.app` **criada e com e-mail confirmado**
      (o Supabase Auth pode estar com "Confirm email" ligado — confirme o
      cadastro antes, senão o revisor não consegue logar).
- [ ] Screenshot da paywall anexado.
- [ ] Review Notes colado (com credenciais reais da conta de teste).
- [ ] Preço e disponibilidade da assinatura configurados.
- [ ] (Opcional) Imagem 1024×1024 da assinatura.

> ⚠️ Os valores `review@kairo.app` / `Review1234` são placeholders. Substitua
> pelas credenciais de uma conta de teste **real e já confirmada**. A senha
> precisa ter mín. 8 caracteres com letra e número (regra do app).

---

# Kairo Pro Yearly

Conteúdo para a assinatura **anual** (`app.kairo.premium.yearly`). O fluxo de
acesso é o mesmo do mensal — ambos os produtos aparecem na mesma paywall.

## Review Notes (campo "Review Notes")

> **How to reach the subscription paywall**
>
> 1. Launch the app and sign in with the demo account below
>    (or tap "Create account" to register a new one).
> 2. On the Home screen, tap the **avatar / profile icon** at the top.
> 3. On the Profile screen, tap the **membership status row**
>    (labeled "Free", with a "›" chevron).
> 4. The paywall opens and lists the auto-renewable subscriptions
>    (**Kairo Pro Monthly** and **Kairo Pro Yearly**), with prices coming
>    from the App Store. A **"Restore Purchases"** button is always visible.
>
> **Demo account**
> Email: review@kairo.app
> Password: Review1234
>
> **Subscription details**
> - Product: Kairo Pro Yearly (auto-renewable, 1 year).
> - Unlocks: Mentor with the advanced model (Claude Sonnet), the weekly
>   Mentor letter, and higher daily usage limits.
> - Purchase is made exclusively through Apple In-App Purchase (StoreKit).
>   There are no external payment links or steering inside the app.
> - The app requires an internet connection (backend on Supabase).
>
> Thank you for reviewing Kairo.

## Screenshot (campo "Screenshot")

Use a **mesma tela da paywall** (`TelaPremium`) que mostra os planos
Monthly/Yearly e o botão Restore Purchases. O mesmo screenshot do plano mensal
serve para o anual — ambos os produtos estão visíveis na imagem.
