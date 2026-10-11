# Smart Farm Engine — E1 BETA / validação no Delta pendente

Base: 333ad750b5dd44ffd569ab0bae6b69d0f17fa445.
Checkpoint: 545fad0ca8ccedaf6ff4f8d0f5fefc30a756d2bb.
Branch exclusiva: dev/2026-10-10-autosell-compat. Sem deploy Render.

## Implementado

- Um coordenador para os controles de Item, Quest, NPC, Stand/Shiny/Rib,
  Auto Prestige e Hop manual do DevMain. Main/Inventory/AutoPrestige inalterados.
- Fila limitada a 20 tarefas; maior prioridade inicia primeiro, FIFO no empate.
  Prioridade não interrompe o proprietário atual. O toggle manual substitui a
  fila e solicita cancelamento do modo anterior antes de iniciar outro.
- Até 10 perfis persistidos, com até 20 tarefas cada; somente configurações
  explicitamente permitidas. Perfis e fila não executam após reload por conta própria.
  O boot pode restaurar UMA preferência Item/Quest/NPC/Prestige anterior; Stand
  só pode retomar pelo protocolo de transferência própria já autorizado na V2.
- Limites por tarefa: 10–86400 segundos, stall 0 ou 30–3600s, meta 0–100000,
  prioridade 0–100, retries 0–2. Retry somente depois da liberação comprovada,
  com 5 segundos de espera; nunca limpa pendência de item para permitir retry.
- Progresso por coletas confirmadas, mortes confirmadas e resultados Arrow/Rib.
  Detectar um item ou clicar diálogo não conta. Meta zero significa sem meta.
- Stop All limpa fila e retries. Ao cancelar, o sistema espera ciclos, callbacks,
  resultado de consumível, respawn, diálogo e transferências pendentes.
  Timeout de liberação aos 20s REGISTRA a condição; não força outra farm.
- Estado, owner, fila/IDs, perfis, contadores, tempo ativo e razões no painel.
  Histórico limitado a 50 eventos e métricas por modo disponíveis em GetStatus.
- Merchant intacto; Auto Sell fica pausado durante Stand e a preferência é
  restaurada somente após liberação. Venda em curso precisa terminar: não existe
  cancelamento novo dentro do Merchant. DoHop revalida cancelamento entre etapas.
- Reload no mesmo servidor conserva uma barreira em memória até o coordenador
  anterior confirmar operações encerradas. Reload não limpa pendência para
  iniciar outra farm. Essa barreira não é persistida em arquivo.
- IsBusy separado de IsRunning. Combat usa contagem observacional das tasks;
  o corpo XenonLock, skills e diálogo não foi reescrito. ServerHop mantém uma
  barreira após solicitação até falha confirmada ou novo runtime.

## Limitação importante do Auto Prestige

O módulo legado não expõe confirmação de encerramento dos seus loops/remotes.
Uma vez ativado, Stop desliga suas flags, mas o Engine mantém
`prestige_release_unverified` e não inicia outra farm no mesmo servidor, inclusive após reload do Hub.
Essa barreira em memória só deixa de se aplicar em um servidor novo.
Não use Prestige no meio de um perfil que precisa continuar em outro modo.
Não há alegação de cancelamento imediato das ações internas desse módulo.
Uma integração cooperativa completa do Auto Prestige continua pendente; exige
uma tarefa isolada e testes prolongados. Reexecutar o loader não limpa a barreira. Para testar outras farms depois de
Prestige, entrar em uma sessão nova; validar respawn/reload no YBA antes de AFK.

## Como usar o painel

Executar DevMain em sessão limpa. Na aba Farm, seção SMART FARM ENGINE:
1. Desativar a farm ativa ou PARAR TUDO antes de preparar um perfil.
2. Selecionar quest/NPC/Stand/consumível nas seções existentes.
3. No campo modo, digitar item, quest, npc, stand, prestige ou hop.
4. No campo limites, usar `1800,180,0,0,0`: tempo, stall, meta, prioridade, retries.
   Para um teste de coleta de 2 itens: modo item e `60,0,2,0,0`.
5. ADICIONAR À FILA inicia quando o controle estiver livre. SALVAR ATIVIDADE +
   FILA COMO PERFIL inclui a tarefa em execução e as seguintes. EXECUTAR PERFIL
   acrescenta tarefas à fila; não interrompe a atividade atual.
6. REMOVER TAREFA aceita um ID exibido no painel; PARAR TUDO cancela a atividade
   e as seguintes. LIMPAR FILA mantém apenas a atividade atual.

## QA funcional necessário

Use personagem e Stands comuns descartáveis; mantenha proteção de skin padrão.
Não precisa esperar shiny raro para testar fila/Stop/pendências.

1. Boot: sem erros, Engine E1 registrado; Item inicia como único owner quando
   era a preferência anterior. Reexecução não duplica scheduler.
2. Item → Quest → NPC → Item pelos toggles. Antes de cada troca, confirmar owner
   anterior encerrado; nenhuma venda, coleta ou ação de combate simultânea.
   Venda em curso pode manter releasing até terminar; exportar o log completo.
3. Perfil item com meta 2 → NPC com meta 1 (selecionar NPC conhecido). Confirmar
   que somente coleta/morte real incrementa e que a fila avança após liberação.
4. Prioridade: com tarefa ativa, enfileirar prioridade 1 e 10. A ativa termina
   antes; 10 inicia antes de 1. Empate conserva ordem de entrada.
5. Stand com alvo comum: Arrow → resultado → Roka/respawn → novo resultado.
   Testar pedido de Quest durante Roka e durante Arrow pendente. Deve aguardar
   NEW Character ou permanecer bloqueado; nunca usar outro item para destravar.
6. Stop All durante diálogo, restock e HTTP de hop. Não pode retomar por retry.
   Teleporte já enviado não pode ser desfeito; barreira deve continuar até
   chegada/falha confirmada. Sem confirmar destino, não iniciar outra farm.
7. Pity, skin/skin desconhecida, estoque e limite de hops da V2 continuam
   protegidos. Confirmar continuação própria de hop e adoção do owner Stand.
8. Timeout 10s e retries 1 em NPC sem alvo: parar, confirmar liberação, esperar
   backoff, no máximo uma retomada. Pendência de item deve impedir retomada.
9. Perfil persiste depois de reload, mas não executa sozinho. Confirmar IDs,
   motivos de parada, métricas e manutenção das preferências de Auto Sell.
10. Auto Prestige: testar sozinho; depois de Stop, conferir bloqueio explícito.
    Esse bloqueio é uma limitação conhecida, não concluir que o Engine concluiu
    a integração cooperativa do Prestige.

## Testes offline e rollback

`python -m unittest ai.test_server`
`python -m unittest discover -s tests`
`git diff --check`

Testes executam o Lua real com mocks, incluindo Stand/restock/respawn e o
coordenador. Não reproduzem Delta, latência, renderização ou autoridade do YBA.

Restaurar os arquivos desta alteração pela base 333ad75, preservando incidentes
posteriores. Excluir os três módulos novos e voltar o wiring do DevMain juntos.
Não fazer reset forçado de toda a branch nem alterar main.

## Resultado offline desta entrega

231 verificações passaram: 51 backend/estáticas e 180 simulações Lua, incluindo
47 novas verificações do Engine. Diff sem erros de whitespace. Nenhuma evidência
nova de execução do Engine no YBA foi obtida.

Arquivos novos: SmartFarmEngine.lua, SmartFarmAdapters.lua, SmartFarmUI.lua,
tests/test_smart_engine.py e este guia.
Arquivos integrados: DevMain.lua, UI.lua, Config.lua, Farm.lua, StandFarm.lua,
CombatFarm.lua (apenas contabilização de tasks e IsBusy), ServerHop.lua.
QA atualizado: ai/test_server.py (lista estática), tests/test_restock_hop.py,
tests/test_stand_v2.py (mocks de falha/novo runtime) e WHITE_HUB_NEXT_STEPS.md.
Checkpoint: ai/backups/20261011-smart-engine-checkpoint.md.
