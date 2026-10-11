-- DEV beta controls. Profiles store validated settings, never credentials or source code.
local Panel={}
function Panel:Init() end
function Panel:Build(parent,UI,engine,config,connect,style,theme)
    UI:AddLabel(parent,'SMART FARM ENGINE — BETA')
    UI:AddLabel(parent,'Fila por prioridade; nenhuma troca durante consumo pendente. Perfis não reiniciam sozinhos.')
    local function input(text)
        local box=Instance.new('TextBox',parent)
        box.Size=UDim2.new(1,-4,0,32); box.BackgroundColor3=theme.PANEL2
        box.TextColor3=theme.WHITE; box.Font=Enum.Font.Code; box.TextSize=12
        box.ClearTextOnFocus=false; box.Text=text
        return box
    end
    local mode=input('item')
    UI:AddLabel(parent,'Modo: item / quest / npc / stand / prestige / hop. Usa as seleções atuais das abas.')
    local limits=input('1800,180,0,0,0')
    UI:AddLabel(parent,'Limites: tempo(s), sem progresso(s; 0 desliga), meta, prioridade(0–100), retries(0–2).')
    local name=input('Meu perfil AFK')
    local cancel=input('ID da tarefa para remover')
    local function button(text,fn)
        local b=Instance.new('TextButton',parent)
        b.Size=UDim2.new(1,-4,0,34); b.Font=Enum.Font.GothamBold; b.TextSize=12; b.Text=text
        style(b,false)
        connect(b.MouseButton1Click:Connect(function()
            local ok,reason=fn()
            if not ok then UI:ShowPopup(tostring(reason),5) end
        end))
        return b
    end
    button('ADICIONAR À FILA',function()
        local fields={}
        for field in limits.Text:gmatch('[^,]+') do fields[#fields+1]=tonumber(field) or false end
        if #fields~=5 then return false,'Informe os cinco limites separados por vírgula.' end
        for _,value in ipairs(fields) do if value==false then return false,'Limites inválidos.' end end
        local task,reason=engine:BuildTask(mode.Text:match('^%s*(.-)%s*$'),
            {timeout=fields[1],stall=fields[2],goal=fields[3],priority=fields[4],retries=fields[5]})
        if not task then return false,reason end
        return engine:Enqueue(task)
    end)
    button('SALVAR ATIVIDADE + FILA COMO PERFIL',function() return engine:SaveQueueProfile(name.Text) end)
    button('EXECUTAR PERFIL',function() return engine:RunProfile(name.Text) end)
    button('EXCLUIR PERFIL',function() return engine:DeleteProfile(name.Text) end)
    button('REMOVER TAREFA',function() return engine:Cancel(tonumber(cancel.Text)) end)
    button('LIMPAR FILA',function() engine:ClearQueue(); return true end)
    button('PARAR TUDO',function() engine:StopAll(); return true end)
    local status=UI:AddLabel(parent,'Engine: inicializando')
    status.TextWrapped=true; status.Size=UDim2.new(1,-4,0,130)
    task.spawn(function()
        while status.Parent do
            local s=engine:GetStatus(); local owner=s.owner
            UI:RefreshEngineMode(owner and owner.mode)
            local names={}; for profile in pairs(s.profiles) do names[#names+1]=profile end; table.sort(names)
            local tasks={}; for _,t in ipairs(s.queue) do
                tasks[#tasks+1]=tostring(t.id)..':'..t.mode..' p'..tostring(t.priority)
            end
            status.Text=('Engine: %s | owner: %s\nFila: %s\nMotivo: %s\nConcluídas: %d | Falhas: %d | Retries: %d\nProgresso: %d | Tempo ativo: %.0fs\nPerfis: %s'):format(
                s.state,owner and (owner.mode..' #'..owner.id) or 'nenhum',table.concat(tasks,', '),
                s.blocked or s.metrics.last_reason,s.metrics.completed,s.metrics.failed,s.metrics.retries,
                s.metrics.progress,s.metrics.active_seconds,table.concat(names,', '))
            task.wait(1)
        end
    end)
end
return Panel
