# Build iOS (IPA) via Codemagic → TestFlight

Projeto já preparado:
- Bundle ID alterado de `com.example.kairo` → **`com.thekairo.app`**
- `codemagic.yaml` criado (workflow `ios-testflight`)
- `.env` é recriado no build (não vai pro git — contém a chave Supabase)

O resto exige ações na Apple e no painel do Codemagic (não automatizável daqui).

---

## 1. Apple Developer / App Store Connect

1. Em **App Store Connect → Apps → +**, crie o app:
   - Plataforma: iOS
   - Bundle ID: `com.thekairo.app` (se não existir, crie em
     **Certificates, IDs & Profiles → Identifiers**)
   - SKU: `kairo`
2. Gere uma **App Store Connect API Key**:
   - App Store Connect → **Users and Access → Integrations → App Store Connect API**
   - Gerar chave com acesso **App Manager**
   - Anote: **Issuer ID**, **Key ID** e baixe o arquivo **.p8** (só baixa uma vez!)

## 2. Codemagic — Integração da chave Apple

1. Codemagic → **Teams → Integrations → App Store Connect → Connect**
2. Preencha Issuer ID, Key ID, faça upload do `.p8`
3. Dê o nome **exatamente**: `kairo_asc_key`
   (é o nome referenciado no `codemagic.yaml`; se usar outro, edite o yaml)

## 3. Codemagic — Variáveis de ambiente (.env)

Codemagic → app → **Environment variables**, grupo **`kairo_env`**:

| Variável        | Valor                                                        | Secure |
|-----------------|--------------------------------------------------------------|--------|
| `SUPABASE_URL`  | `https://ojagemcqbekonwqjidkp.supabase.co`                   | sim    |
| `SUPABASE_KEY`  | (a anon key atual do arquivo `.env` local)                   | sim    |

> A chave Supabase é a `anon` (pública por design), mas mantenha como *secure*.

## 4. Conectar repositório e rodar

1. Codemagic → **Add application** → conecte este repositório Git
2. Selecione **codemagic.yaml** como configuração
3. Workflow **Kairo iOS - TestFlight** → **Start new build**

O Codemagic faz: signing automático (cria certificado/profile via API),
recria o `.env`, `flutter build ipa`, e envia ao **TestFlight**.

## 5. Instalar no iPhone

Após o build (≈10–20 min) e processamento da Apple (≈5–15 min):
- App **TestFlight** no iPhone → o app aparece para testers internos
- Adicione testers em App Store Connect → TestFlight → Internal Testing

---

## Notas / ajustes possíveis

- **`APP_STORE_APP_ID`** no yaml: opcional; preencha com o ID numérico do app
  (App Store Connect → App → App Information) se quiser tracking explícito.
- Quer um **.ipa baixável** em vez de TestFlight? Troque no `codemagic.yaml`:
  `distribution_type: ad_hoc` e remova o bloco `publishing.app_store_connect`.
  O IPA fica em **Artifacts** do build.
- O `--build-number` usa timestamp/60 para sempre ser crescente (exigência da Apple).
- Pré-requisito que **não** dá pra contornar: build iOS só roda em macOS — por
  isso usamos a nuvem do Codemagic (você está no Windows).
