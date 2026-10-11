# Diálogos de quests e Merchant — melhoria experimental

Baseline dev: b82831fa3b079068fac1b7df1d46662767f3edec. Alterações ainda não validadas no Roblox.

## Cobertura real desta alteração

| Caminho | Mudança |
| --- | --- |
| Stand Farm | Mantém a R4 já publicada; callbacks rápidos e métricas `timing` |
| Quest Farm: aceitar, entregar, reativar | Página de opções nova avança sem esperar o cooldown da anterior; mesma página continua limitada a 0,10 s entre tentativas |
| Merchant FINAL e fallback interno | Procura botões em `Options`, evitando percorrer o texto/HUD do diálogo; conserva busca ampla em layout sem `Options` |
| Merchant fallback adaptativo | Conserva busca ampla e comportamento de compatibilidade; elimina normalização duplicada de texto |
| AutoPrestige: história, Prestige, Hamon e consumíveis | Inspecionado, sem alterações: usa caminhos próprios/legados; não foi migrado para o driver novo |
| Buy Lucky | Compra via `PurchaseShopItem`, sem diálogo; sem alterações |

Sem controlador global, novos hooks, alterações de constantes ou redução geral de `task.wait`. O Merchant continua com sua rota FINAL, três opções, verificação de item equipado, confirmação pelo inventário, fallbacks, guarda de concorrência e restauração das alterações temporárias. A proteção Real Injector permanece. O núcleo XenonLock fica byte a byte igual ao baseline.

## Teste no Delta

1. Reexecute DevMain.lua em sessão limpa; confirme boot sem erros e dev atualizado. Feche diálogos manuais pendentes. Teste um modo por vez.
2. Venda: desative Stand/Quest/NPC Farm e AutoPrestige. Selecione somente itens comuns descartáveis para venda. Registre quantidade/dinheiro antes e depois. Execute o fluxo existente de Auto Sell com Item Farm. Confirme `ZeroDelay` com venda efetiva; não considere clique ou janela fechada como sucesso.
3. Exporte `Sold ... in ...` e `gcScans=... gcTime=...`. `gcTime` mede apenas o tempo nas chamadas `getgc` do avanço FINAL; não inclui a descoberta inicial de DialogueType, nem toda a inspeção/patch subsequente. Não é uma medida de FPS. Não houve redução especulativa do intervalo de varreduras.
4. Quests: desative Item/Stand/NPC Farm, AutoPrestige e Auto Sell. Teste William Zeppeli/Vampire: aceitar, confirmar crédito das mortes, entregar e reativar. Repita Dio/Jotaro manualmente. Confirme PlayerStats/progresso e coleta da recompensa; registre `[DialogueTiming] ... elapsed=... confirmed=...` e os logs QuestState/kill credit.
5. Desligue Quest Farm durante uma janela e confirme que a GUI reaparece/é restaurada pelo fluxo existente, sem novas tentativas do worker. Teste também entrega e aceitação repetidas em sessões limpas. Uma requisição já enviada ao servidor pode terminar após Stop.
6. Se houver falha, preserve logs completos, versão Delta, opções mostradas e estados antes/depois. Não tente sobrepor farms nem usar itens manualmente durante o teste.

Os loops mantêm seus timeouts/guardas anteriores; não foi prometida uma duração máxima para o servidor do YBA. O log `confirmed` segue o critério do chamador: estado da quest quando fornecido, ou fechamento do diálogo no caminho de entrega existente. Não equivale por si só a recompensa creditada.

## Verificação offline

- `python -m unittest discover -s tests -q`: 51 testes (40 Stand + 11 helpers/driver de quests/rota FINAL Merchant).
- `python -m unittest ai.test_server -q`: 34 testes existentes.
- `python -m compileall -q ai tests` e `git diff --check`.
- Os testes executam trechos do Lua real com mocks; não reproduzem rede, renderização, upvalues de Delta ou regras do YBA. FINAL conservou sua ordem e restauração nas simulações.

## Limites e rollback

Esta mudança estende a otimização a quests e venda, sem afirmar que todos os diálogos do AutoPrestige usam o mesmo driver. Migrar seu código legado precisa de testes específicos de progressão, história, morte e Stop. Reduzir apenas os sleeps de seu `useItem` sem confirmar cada página não garante compatibilidade e pode consumir indevidamente.

Rollback: restaure Inventory.lua e CombatFarm.lua do baseline acima e crie um novo commit somente na dev. Checkpoint em `ai/backups/20261011-quest-merchant-speed-checkpoint.md`. Main e backend intactos; nenhum deploy Render.
