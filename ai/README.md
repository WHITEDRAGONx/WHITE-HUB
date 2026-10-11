# WHITE AI V1 — Gemini API, branch experimental

Este backend de diagnóstico do WHITE HUB V3 mantém o serviço existente
[white-ai-v1 no Render](https://dashboard.render.com/web/srv-db527jflot8c73df8mr0)
e o repositório WHITEDRAGONx/WHITE-HUB-V3 na branch
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

Somente propostas Markdown de revisão são gravadas em `ai/proposals/`
na branch de desenvolvimento. Nenhum patch é aplicado nem executado
automaticamente. Nunca altera `main` nem o módulo de venda
`Inventory.lua`. Combate, Farm, UI e outras funcionalidades de jogo
permanecem inalteradas pela migração de provedor.

O servidor limita acesso por chave, taxa e tamanho, restringe os
arquivos e caminhos de escrita, e sanitiza os registros. A análise
continua precisando de revisão e teste humano antes de qualquer alteração.

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
