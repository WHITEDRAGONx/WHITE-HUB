# WHITE AI V1 — Backend experimental

Este diretório contém o backend para **diagnósticos e propostas de patches** do WHITE HUB V3.

## O que já funciona no código

- A aba **AI DEBUG** e o módulo `WhiteAI.lua` observam logs do RuntimeLog e possível estagnação de quests.
- O sistema local não faz varreduras `getgc`, não modifica combat, Merchant ou inventário.
- Envio externo **desativado por padrão** até o usuário escolher ativá-lo.
- O backend recebe relatórios curtos autenticados, lê um módulo conhecido na branch dev, solicita análise via OpenAI API e valida substituições exatas.
- Caso a sugestão seja válida, salva um **diff não aplicado** em `ai/proposals/` na branch `dev/2026-10-10-autosell-compat`.
- Mesmo em caso de sucesso **não aplica código-fonte, não executa o patch, não modifica `main` e não faz merge**.

## Hospedar no Render (mais fácil)

O repositório já inclui o arquivo **`render.yaml` na raiz da branch dev**, preparado para o Render Blueprint. Ele instala dependências, executa os testes básicos e inicia `ai.server:app` com HTTPS, sem chaves hardcoded.

1. No [Render Dashboard](https://dashboard.render.com/), escolha **New → Blueprint**, conecte o GitHub, selecione `WHITEDRAGONx/WHITE-HUB-V3` na branch `dev/2026-10-10-autosell-compat` e o `render.yaml`.
2. Preencha os segredos solicitados no Render: `OPENAI_API_KEY`, `OPENAI_MODEL` (por exemplo `gpt-6-sol` caso habilitado na conta), `GITHUB_TOKEN` e `WHITEAI_INGEST_KEY` (12–128 caracteres aleatórios).
3. Aguarde o deploy terminar e abra o endereço do tipo `https://white-ai-v1.onrender.com/health`. Deve retornar status `ok`.
4. Na aba AI DEBUG do Roblox, configure `https://SEU-SERVICO.onrender.com/reports`, informe exatamente a mesma `WHITEAI_INGEST_KEY` apenas para essa sessão, habilite envio e envie um relatório de teste.
5. Acompanhe a pasta `ai/proposals/` da branch dev para ver um novo relatório/recomendação; isso não modifica arquivos de jogo.

**Atenção:** Render no plano Free pode entrar em modo de hibernação por inatividade, e a primeira requisição após dormir pode demorar. O plano grátis também possui limites de recursos. `autoDeployTrigger: off` impede que novas propostas no GitHub reiniciem o servidor automaticamente. Para atualizar o backend manualmente, use **Manual Deploy** no serviço Render.

**Segurança:** não publique tokens em Issues, chats, arquivos Lua ou GitHub. Use uma credencial GitHub fine-grained limitada apenas ao repositório, com expiração curta e Contents read/write, e mantenha proteção de branch para `main`. A aplicação grava somente Markdown em `ai/proposals/`, mas o token de escrita ainda requer proteção externa contra comprometimento. Os relatórios devem ser revisados antes de qualquer correção.

## O que ainda é necessário

**O servidor não foi implantado nem conectado a uma conta/API.** Para ativar a análise realmente automática, é necessário executar este backend numa máquina/serviço com HTTPS acessível pelo cliente.

1. Instale Python 3.11+ e execute `pip install -r ai/requirements.txt`.
2. Configure as variáveis de ambiente **no servidor**, nunca no script Roblox nem em arquivos públicos:

   - `OPENAI_API_KEY`: chave da API da OpenAI; assinatura do ChatGPT Plus **não inclui** créditos de API.
   - `OPENAI_MODEL`: modelo disponível na sua conta da API. Escolha conforme custo e capacidade.
   - `GITHUB_TOKEN`: token GitHub **restrito ao repositório WHITE-HUB-V3**, com permissão Contents read/write.
   - `WHITEAI_INGEST_KEY`: segredo aleatório próprio com 12–128 caracteres usado exclusivamente para autenticar relatórios recebidos.

3. Inicie `uvicorn ai.server:app --host 127.0.0.1 --port 8765`.
4. Coloque o serviço atrás de um proxy **HTTPS** com limitação de taxa, logs e controles de acesso. Não exponha diretamente o servidor de desenvolvimento na internet.
5. Na aba AI DEBUG do WHITE HUB, configure `https://seu-dominio/reports`, insira a chave de ingestão **somente para a sessão atual**, e habilite **Send to AI server**.
6. Teste com **COPY SANITIZED DIAGNOSTIC** primeiro, depois com **SEND REPORT TO AI BACKEND**. Uma ocorrência de erro poderá gerar proposta na pasta `ai/proposals`.

Veja `GET /health` para verificar o serviço, e `GET /jobs/{id}` (com header `X-WhiteAI-Key`) para consultar um diagnóstico específico. Em caso de reinício os status em memória são perdidos; as propostas já gravadas no GitHub permanecem.

## Arquitetura e limites de segurança

```
WhiteAI.lua -> HTTPS POST /reports -> AI backend
                                   |-> GitHub API READ (dev)
                                   |-> OpenAI Responses API
                                   \-> GitHub API WRITE (ai/proposals/*.md, dev ONLY)
```

- A única escrita automática permitida no GitHub pelo backend é `ai/proposals/*.md` na branch experimental fixa.
- `Inventory.lua`, `Main.lua`, `DevMain.lua` e `Config.lua` não podem receber propostas de substituição automáticas.
- O backend exige chave para ingressos, limita frequência e volume das requisições e reduz o conteúdo dos logs.
- Nunca coloque chaves OpenAI/GitHub no `WhiteAI.lua`. O token temporário de ingestão é menos privilegiado, mas ainda deve ser protegido.
- Logs e código fornecidos à IA são tratados como dados não confiáveis; nenhuma proposta é automaticamente executada.
- A IA pode diagnosticar incorretamente. Toda sugestão precisa de revisão humana, comparação com a versão atual, validação Luau e testes no Roblox.
- Se o endpoint estiver desativado/indisponível, o modo local continua disponível para coleta e cópia de relatórios.

### Testes locais

```bash
python -m unittest ai.test_server
```

Testa validação de propostas e sanitização sem chamar GitHub/OpenAI. **Não é um teste funcional dentro do YBA.**
