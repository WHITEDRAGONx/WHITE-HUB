# WHITE AI V2 — agente privado, Gemini API, branch experimental

Este backend de diagnóstico do WHITE HUB V3 mantém o serviço existente
[white-ai-v1 no Render](https://dashboard.render.com/web/srv-db527jflot8c73df8mr0)
e o repositório WHITEDRAGONx/WHITE-HUB na branch
`dev/2026-10-10-autosell-compat`.

## Provedor gratuito

A análise usa **Google Gemini API** pelo endpoint REST generateContent.
O modelo padrão é `gemini-3.8-flash`, com nível gratuito sujeito a cotas.
Não há fallback automático para uma API paga. A antiga OpenAI não é usada.

No plano gratuito do Google, as solicitações podem ser utilizadas para
melhorar produtos. Não envie segredos ou informações privadas nos relatórios.

## Configurar o Render existente

1. Gere uma chave para um projeto **Free** em https://aistudio.google.com/apikey .
2. No Render, em **white-ai-v1 → Environment**, adicione a variável secreta
   `GEMINI_API_KEY`. Cole a chave **somente no Render**, nunca no GitHub,
   Lua ou chat.
3. Opcional: `GEMINI_MODEL=gemini-3.8-flash`. Esse já é o padrão.
4. Mantenha as variáveis existentes `GITHUB_TOKEN` e
   `WHITEAI_INGEST_KEY`. As variáveis antigas da OpenAI não são mais
   necessárias; podem ser removidas no painel depois.
5. O serviço está com auto-deploy desligado. Use **Manual Deploy** para
   alterações de código, confirme status `live` e execute
   GET https://white-ai-v1.onrender.com/health .
6. `configured: true` apenas confirma a presença das configurações,
   não a validade da chave ou disponibilidade de cota.

## Teste ponta a ponta

Use `DevMain.lua` da branch experimental no YBA. Na aba AI DEBUG,
configure `https://white-ai-v1.onrender.com/reports`, a chave de
ingestão **somente durante a sessão**, habilite o envio e envie um
relatório. O POST devolve HTTP 202 e um `job_id`; o Lua acompanha
GET /jobs/{job_id} para verificar `analyzing`, `saving_proposal`,
`proposal_ready` ou `failed`.

## Separação público/privado e commits experimentais

- `Main.lua` (público) carrega `main` e não carrega WHITE AI.
- `DevMain.lua` (somente uso do proprietário) carrega `dev/2026-10-10-autosell-compat` e a aba AI DEBUG. O código da branch é publicamente visível: a segurança está na credencial **não publicada**, não no segredo do nome do loader.
- Qualquer pessoa com a antiga chave de ingestão pode **enviar relatórios**, mas **NUNCA autorizar commits de código** sem a credencial adicional. A chave existente não precisa ser substituída para usar o fluxo privado.
- `WHITEAI_ADMIN_KEY` deve ser gerada pelo proprietário com pelo menos 32 caracteres aleatórios e cadastrada **somente em Render Environment**, nunca em arquivos, logs, chat ou Config.lua.
- `WHITEAI_AUTOPATCH_ENABLED=1` habilita o caminho de commits apenas para **relatórios que também apresentem o cabeçalho `X-WhiteAI-Admin-Key` correto**. Sem essa variável, ou sem autorização individual na sessão privada, todos os relatórios continuam só criando propostas.
- Na aba AI DEBUG da branch dev, use **AUTHORIZE PRIVATE DEV AUTO-PATCH** com essa chave privada, somente na sua sessão. A caixa limpa o texto imediatamente; reiniciar o hub apaga a credencial.
- **Somente** `CombatFarm.lua` (trecho de quest, fora do XenonLock), `Farm.lua`, `ServerHop.lua` e `UI.lua` podem receber commits automáticos na branch dev. Inventory.lua, Main.lua, Config.lua, DevMain.lua, o núcleo de combate e `main` são protegidos.
- O agente exige confiança >=0.94, substituição textual única, patch pequeno, sintaxe válida de Luau com tree-sitter-luau para origem e destino, confirmação do blob SHA vigente e ausência de novas APIs perigosas.
- Antes do commit, cria `ai/backups/YYYYMMDD-jobid.md` com o SHA do commit anterior e SHA do blob original, garantindo ponto de rollback pelo histórico do Git. Se falhar a criação desse registro ou a atualização do arquivo, não afirma que a correção foi aplicada.
- **Sintaxe validada não significa comportamento verificado no Roblox.** Qualquer commit automático fica na dev com o estado `dev_committed_unverified` para revisão e teste manual. Nunca há merge ou deploy na `main` automaticamente.
- O endpoint `GET /health` mostra apenas booleanos (`configured`, `autopatch_enabled`); não expõe credenciais.
- O WHITE AI monitora WARN/ERROR e quest_stall automaticamente quando envio externo está ligado e a ingest key foi inserida. SEND REPORT permanece opcional.

Para desativar instantaneamente commits automáticos, ajuste `WHITEAI_AUTOPATCH_ENABLED=0` no Render. Nenhum código precisa ser removido.

## Limitações relevantes

Os diagnósticos podem falhar ou resultar em propostas sem patch. Um sucesso em testes Python e no parser Luau **não prova** que o patch funciona no YBA; o servidor não executa o jogo. Antes de publicar para usuários, testar a dev manualmente.

## Erros comuns

- `503`: variável `GEMINI_API_KEY` ausente no Render.
- `gemini_auth_error`: chave ou permissão inválida.
- `gemini_rate_limited`: cota gratuita ou limite de taxa atingido.
- `gemini_model_unavailable`: falta acesso ao modelo escolhido.
- `gemini_bad_request`: requisição ou JSON incompatível.
- `failed`: conferir o erro sanitizado no Render, sem imprimir segredos.

## Testes locais

```bash
pip install -r ai/requirements.txt
python -m compileall -q ai
python -m unittest ai.test_server
```

Esses testes simulam as chamadas externas sem gastar cota do Gemini.
Os estados dos trabalhos ficam somente na memória do Render. Reiniciar
o serviço pode invalidar um `job_id`, mas propostas já gravadas no
GitHub permanecem. O Render Free pode hibernar quando inativo.

## Owner device pairing

Save the HTTPS backend `/reports` endpoint, enter the private owner key once,
and click **PAIR THIS DEVICE**. `POST /auth/pair` exchanges the master key
for a signed 30-day bearer session; the master key is never saved.
The local executor file `WHITE_AI_DEVICE_SESSION.json` contains the session
and exact endpoint. Treat this file as a credential; do not share or commit it.
`GET /auth/session` validates it on the next initialization. Sessions authenticate
both reports and job polling without the ingestion key. External reporting still
requires the existing opt-in toggle. Without file APIs, pairing lasts in memory.
A network failure retains the file for a later recovery attempt.

The backend uses the existing `WHITEAI_ADMIN_KEY` (at least 32 characters).
Rotate it or advance `WHITEAI_SESSION_NOT_BEFORE` (Unix timestamp) to revoke
sessions. Invalid cutoff configuration fails closed. Sessions do not auto-renew;
expired sessions require pairing again. Auto-patch additionally requires
`WHITEAI_AUTOPATCH_ENABLED=1`; ingestion keys alone cannot authorize it.
Pairing is rate-limited separately from reports. Credentials only travel in
HTTPS headers; no secret is included in diagnostics, status, or rollback records.

Validation: `python -m unittest ai.test_server ai.test_owner_session` and
`python -m compileall -q ai`. These are offline backend and static Luau tests,
not a Roblox executor runtime test.
