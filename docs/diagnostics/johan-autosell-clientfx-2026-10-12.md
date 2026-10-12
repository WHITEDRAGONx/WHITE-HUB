# Johan Auto Sell / ClientFX — diagnóstico experimental (2026-10-12)

## Escopo e proteção

- Alvo: **somente branch `dev/2026-10-10-autosell-compat`**.
- Backup antes da alteração: `backup/2026-10-12-before-johan-sell-diagnostics`, apontando para `6183fccb743d15223106276bdc7fbe82f98b26c5`.
- O `Inventory.lua` e seu **Merchant Zero Delay** não foram modificados. `main` permanece inalterada.
- Esta etapa é **instrumentação e isolamento de causa, não correção comprovada**. Não há validação dentro do YBA até realizar teste controlado.

## Indícios da gravação do Johan

- O console exibiu uma exceção do tipo `value of type nil cannot be converted to a number`, com stack citando `ClientFX` e `Farm.lua:120` na versão exibida no vídeo.
- Também houve `No exploiting! (bruh)`, desconexões e tentativas de Server Hop.
- A referência de linha do vídeo é de uma versão diferente da nova compilação. Ela não pode ser mapeada literalmente após as inserções.
- A gravação sozinha **não demonstra** que o lag, o erro de ClientFX ou as desconexões foram provocados pela venda.

## Instrumentação adicionada em Farm.lua (dev)

O wrapper observacional `SellAllWithDiagnostics` preserva a chamada original `Inventory:SellAll()` e monitora `RunService.Heartbeat` apenas durante a chamada. Ele registra:

- `[Farm][SellPerf] BEGIN id=N source=server-hop|phase-1`
- `[Farm][SellPerf] END id=N ... ok=true|false duration=...s frames=... avgFrame=...ms maxFrame=...ms slow50ms=... slow100ms=...`

`slow50ms` e `slow100ms` contam quadros cuja duração excedeu 50 ou 100 milissegundos. Servem como indicadores de correlação; não provam causalidade. Em sessões com `AutoSell=false`, não é adicionado monitor e o caminho original é usado. Os dois pontos monitorados são a venda antes de Server Hop e a venda após Phase 1. O caminho de PrestigeSell não foi alterado.

## Teste A/B para o erro do ClientFX

IMPORTANTE: cada teste deve começar em **uma sessão de cliente nova**. Se `FunctionLibrary.pcall` já foi substituído na sessão, mudar a flag não desfaz o hook.

### Teste A — comportamento normal (hook habilitado)

```lua
getgenv().WhiteHubDevSkipCrashBypass = false
loadstring(game:HttpGet("https://raw.githubusercontent.com/WHITEDRAGONx/WHITE-HUB/refs/heads/dev/2026-10-10-autosell-compat/DevMain.lua"))()
```

### Teste B — hook não instalado pela farm (para isolar a variável)

```lua
getgenv().WhiteHubDevSkipCrashBypass = true
loadstring(game:HttpGet("https://raw.githubusercontent.com/WHITEDRAGONx/WHITE-HUB/refs/heads/dev/2026-10-10-autosell-compat/DevMain.lua"))()
```

O segundo teste deve mostrar `[Farm][ClientFXTest] FunctionLibrary.pcall hook skipped by DEV flag`. Se houver outra ferramenta/script instalando o mesmo hook, o teste não isola a variável e precisa ser refeito em ambiente limpo.

## Evidências para decidir a correção

1. Em ambas as sessões, usar mesmo dispositivo/executor, configuração e quantidade parecida de itens selecionados para venda.
2. Coletar 2 ou 3 conjuntos completos de logs `[Farm][SellPerf] BEGIN/END` e logs `[Inventory][ZeroDelay]` referentes à mesma venda. Alguns logs já mostram `gcScans` por item.
3. Salvar o erro do `ClientFX` com o stack completo, se reaparecer. Não mandar chaves, tokens ou URLs de webhook.
4. Se um pico de `maxFrame` ocorrer consistentemente durante a venda, inspecionar os contadores `gcScans` e fallbacks da mesma operação.
5. Se o `ClientFX` falhar apenas no teste A, investigar a substituição de `FunctionLibrary.pcall`. Se ocorrer em A e B, investigar a origem separadamente.
6. **Nenhuma alteração no Merchant/Inventory** antes de termos dados suficientes e autorização explícita.

## Observações

- `duration` mede toda a duração da operação, incluindo esperas de diálogo e rede, não apenas CPU.
- `maxFrame` é o maior intervalo de Heartbeat capturado durante a operação; picos podem vir de outras fontes do cliente.
- As medições ainda **não foram testadas em Roblox real**.
- Para fazer rollback da alteração na branch dev, restaure exclusivamente `Farm.lua` usando o commit de backup. Nunca usar `main` como ambiente de teste.
