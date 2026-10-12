# Auto Prestige AP-COMPAT-R1 — beta de compatibilidade

Pre-change: 83c41870661b71e42846308e74ab0b3d299566e8.
Checkpoint: bac75a9dd81af41ffc9bf6cdeeba3e6bd9d0b200.
Branch: dev/2026-10-10-autosell-compat. Main intacta. Sem deploy Render.

## O que mudou

O proprietário cancelou o Smart Farm Engine. Módulos, fila, perfis, painel e
wiring E1 removidos; os controles V2 anteriores foram restaurados. O loader
apenas encerra um Engine de versão anterior durante a migração; não carrega ou
inicia um Engine novo. Histórico e checkpoints preservados.

AutoPrestige.lua mantém as ramificações de progressão/história, mas substitui os
mecanismos demonstradamente obsoletos. AutoPrestigeRuntime.lua controla somente
esse módulo, sem scheduler de farms. PrestigeDialogue.lua usa cópia isolada dos
primitivos de diálogo do próprio WHITE HUB Stand Farm, incluindo Option1,
ClickContinue, callbacks vinculados, fallback visível e restauração de estado.
Nenhum código externo foi importado.

- Sem requests EndDialogue, varredura cega de 18 diálogos, clique em coordenada
  fixa, ativação repetida de consumíveis, kill por entrada de dinheiro ou
  destruição local do NPC para fingir uma morte.
- Consumível ativa uma vez. Resultado exige PlayerStats.Stand e GUI encerrada.
  Roka espera NEW Character/root/remotes e retorna ao safe spot. Requiem exige
  mudança real do Stand. Skin, leitura inconclusiva e pity impedem descarte.
- Prestige exige aumento do valor Prestige; Hamon exige mudança de Spec. Quest
  exige mudança do estado de quests, não alteração isolada de dinheiro/nível.
- Kill do controlador privado AP confirma HP <= 0. Despawn não prova morte.
  Ataques limitados; sem spawn de múltiplos ataques por frame. XenonLock intacto.
- Stop cancela o contexto e suas conexões; esperas são cooperativas em até 0,1s.
  RPC já enviado pode continuar até retornar: o contexto mantém bloqueio até
  tarefas/resultado ficarem resolvidos. Nenhum timeout apaga uma pendência.
- Restock usa detector/coletor existente, estoque necessário e limites de 90s/8
  tentativas. Venda delega ao Inventory:SellAll, mantendo pausa exclusiva do Item
  Farm e restaurando sua flag temporária; respeita AutoSell e filtros de venda.
- Item, Quest, NPC, Stand e Hop da UI recusam troca enquanto AP estiver pendente.
  Pequenos contadores/getters observacionais oferecem essa confirmação, sem
  fila central. Estado/motivo/pending aparecem abaixo do toggle de Prestige.
- Loop de história iterativo, limite de sessão 30min, sem progresso 120s,
  diálogo NPC 12s, item 22s, respawn 20s, NPC 90s. Retomada manual após limite.
- Hop usa um único pedido do ServerHop existente, respeitando servidor privado;
  transfer já solicitado não pode ser desfeito. Falha confirmada libera a
  pendência; depois da chegada, reativar AP manualmente.

## Limitações reais

**Não validado no YBA/Delta.** Não significa que todas as etapas da história ou
compras de Hamon continuam disponíveis com os nomes antigos.

A origem da missão precisa estar em metadados NPC/NPCName/QuestGiver/Source ou no
nome Storyline. Para uma história iniciada pelo módulo, conserva o NPC que
acabou de confirmar uma mudança de quest. Sem missão inicial, tenta somente
Storyline #1. Sem origem identificável ou com metadados ambíguos, para com
AP_STORY_SOURCE_UNKNOWN/AMBIGUOUS e lista os nomes de quests no Console. Não
inventa qual NPC entrega cada objetivo nem dispara todos os prompts disponíveis.
Os logs reais devem completar esse mapeamento antes de alegar progressão integral.

Preset de Stand e pedidos LearnSkill existentes foram conservados. Retorno do
LearnSkill não prova que skill foi aprendida; nomes/requisitos precisam de QA.
Prestige usa os gatilhos anteriores 35/0, 40/1 e 45/2, aceitando nível acima do
mínimo, mas confirmação do servidor continua obrigatória.

Consumível/RPC/NPC cujo resultado continue inconclusivo pode bloquear outra farm.
Confirmar estado e fechar diálogo normalmente. Se não resolver, entrar em sessão
nova; reload não deve descartar a pendência apenas para gastar mais itens.

## Teste no Delta

1. **Entrar em servidor novo e executar DevMain**, evitando callbacks/hooks de
   uma versão antiga do Auto Prestige. Confirmar AP-COMPAT-20261012-R1 no boot e
   ausência do painel Engine. Não usar personagem com Stand/skin valiosos.
2. Desativar Item/Quest/NPC/Stand e fechar diálogos. Preparar estoque e Worthiness
   adequados. Manter pity com margem; todos os shinies são preservados.
3. Ativar AP. Se houver operação anterior em andamento, a UI recusa: esperar e
   tentar de novo, sem executar outro loader para apagar a pendência.
4. Conferir NPC escolhido, Option1/ClickContinue, mudança real de quest e crédito
   de kill. Se SOURCE_UNKNOWN, copiar Console completo: nome de quest, NPC atual,
   nível/prestige e sequência visual do diálogo. Não testar 18 NPCs às cegas.
5. Arrow -> Stand; Roka -> None -> NEW Character -> safe spot. Testar Stop antes
   da ativação, durante diálogo e durante respawn. Não pode usar item seguinte.
6. Com recursos comuns, testar venda necessária: usa Merchant existente,
   respeita filtros/AutoSell; confirmar dinheiro/inventário antes/depois e que
   Item Farm não coleta durante a venda. AutoSell OFF interrompe essa etapa.
7. Lisa Lisa/Hamon: confirmar nome real do NPC, custo/requisitos e Spec antes/depois.
   Log de clique não significa compra; resultado não confirmado deve parar.
8. Ao nível de prestige, confirmar aumento do contador e nível/reset reais. Não
   aceitar “Prestiged” apenas porque diálogo fechou. Testar valores acima do
   mínimo e P3/L50 (notificação uma vez e Stop).
9. Stop AP -> Item/Quest/NPC/Stand: só trocar após tarefas e resultado liberarem.
   Testar reload, respawn, falta de item, popup desconhecido, falha de RPC e Hop.
10. Só após esses cenários, testar sessão longa. Exportar logs sem sessões/chaves.

## QA offline e arquivos

`python -m unittest ai.test_server`
`python -m unittest discover -s tests`
`git diff --check`

38 novas simulações executam driver, contexto, worker real e delegação real do
Farm com mocks. Cobrem confirmação, skins, cancelamento, respawn, RPC pendente,
origem de quest, Prestige, venda/coleta e transferência. Não substituem o YBA.

AP atualiza AutoPrestige.lua, adiciona AutoPrestigeRuntime.lua/PrestigeDialogue.lua,
e integra DevMain.lua, UI.lua, Farm.lua, StandFarm.lua e contadores de tasks em
CombatFarm.lua. Atualiza ai/test_server.py somente na lista de parser, testes e
este guia. Inventory.lua/Main.lua são idênticos à base. ServerHop, Config e
simulações V2 voltam à versão anterior ao Engine.

Resultado: 222 verificações aprovadas (51 backend/estáticas e 171 Lua, incluindo
38 novas). Nenhuma execução no YBA foi feita nesta entrega.

Rollback AP: restaurar esses arquivos em conjunto pelo commit de remoção do
Engine 82629d31109ae7a1f7b47b8143b818155f896661 (pai do commit AP), excluindo os dois helpers novos. Não restaurar o
Engine sem novo pedido do proprietário, nem resetar a branch inteira.
