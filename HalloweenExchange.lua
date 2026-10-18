-- WHITE HUB V5 SILVER - Halloween exchange beta.
-- Explicit opt-in; one action per request; no blind retries or purchases.
-- Independent from Inventory/Merchant, CombatFarm, StandFarm, and White AI.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local VirtualInputManager=game:GetService("VirtualInputManager")
local Player=Players.LocalPlayer
local Trade={}
local modules,config,logger
local busy=false
local blockedUntilReload=false
local hiddenDialogue=nil
local hiddenConn=nil
local hiddenOriginallyEnabled=nil
-- The exact GUI opened through verified Jack options; do not close other NPC dialogues.
local activeJackGui=nil
local function restoreJackRendering()
    if hiddenConn then pcall(function() hiddenConn:Disconnect() end);hiddenConn=nil end
    if hiddenDialogue and hiddenDialogue.Parent and hiddenDialogue:IsA("ScreenGui") then
        pcall(function() hiddenDialogue.Enabled=hiddenOriginallyEnabled~=false end)
    end
    hiddenDialogue=nil
    hiddenOriginallyEnabled=nil
end
local boughtThisRuntime=false
local CANDIES={"Yellow Candy","Blue Candy","Green Candy","Red Candy"}
local SHOP={
    ["2026 Halloween Event Items"]={option="Option1",items={
        ["Boxing Blobs (Boxing Gloves Skin)"]={option="Option1",price=60},
        ["Spectral Marrow (Pluck Skin)"]={option="Option2",price=70},
        ["Jack-o-Ball (Steel Ball Skin)"]={option="Option3",price=45},
        ["Sanguine Veil (Umbrella Skin)"]={option="Option4",price=75},
    }},
    ["2022 Halloween Event Items"]={option="Option2",items={
        ["Eye of The Saint's Corpse (Steel Ball Skin)"]={option="Option1",price=45},
        ["Bone Gloves (Boxing Gloves Skin)"]={option="Option2",price=60},
        ["Cursed Scythe (Pluck Skin)"]={option="Option3",price=70},
    }},
    ["2021 Halloween Event Items"]={option="Option3",items={
        ["Stop Sign"]={option="Option1",price=45},
        ["Boxing Claws (Boxing Gloves Skin)"]={option="Option2",price=60},
        ["Scythe (Pluck Skin)"]={option="Option3",price=70},
        ["Random Halloween Cosmetic"]={option="Option4",price=25},
    }},
    ["Normal Items"]={option="Option4",items={
        ["Mysterious Arrow"]={option="Option1",price=2},
        ["Rokakaka"]={option="Option2",price=3},
        ["Rib Cage of The Saint's Corpse"]={option="Option3",price=5},
        ["DIO's Diary"]={option="Option4",price=10},
        ["Green Baby"]={option="Option5",price=15},
        ["Lucky Arrow"]={option="Option6",price=100},
    }},
}
local function log(level,message)
    if logger then pcall(logger.Write,logger,level,"Halloween",tostring(message)) end
end
local function candies()
    local counts,total={},0
    local roots={}
    local backpack=Player:FindFirstChild("Backpack")
    if backpack then roots[#roots+1]=backpack end
    if Player.Character then roots[#roots+1]=Player.Character end
    for _,name in ipairs(CANDIES) do
        local number=0
        for _,root in ipairs(roots) do
            if root then
                for _,tool in ipairs(root:GetChildren()) do
                    if tool:IsA("Tool") and tool.Name==name then number=number+1 end
                end
            end
        end
        counts[name]=number
        total=total+number
    end
    return total,counts
end
function Trade:GetCandyTotal() return candies() end
-- Only explicitly named event/candy point balances qualify; generic skill points do not.
-- Prefer a real event-specific numeric value; never confuse combat or skill points.
local function observedPoints()
    local roots={}
    for _,name in ipairs({"PlayerStats","leaderstats"}) do
        local root=Player:FindFirstChild(name)
        if root then roots[#roots+1]=root end
    end
    for _,root in ipairs(roots) do
        if root then
            for _,entry in ipairs(root:GetDescendants()) do
                local name=entry.Name:lower():gsub("[^%a]","")
                local p=entry.Parent
                local parentName=p and p.Name:lower():gsub("[^%a]","") or ""
                local eventNamed=name:find("halloween",1,true) or name:find("candy",1,true)
                    or name:find("event",1,true) or parentName:find("halloween",1,true)
                    or parentName:find("candy",1,true) or parentName:find("event",1,true)
                local currencyNamed=name:find("point",1,true) or name:find("currency",1,true)
                    or (name=="points" and eventNamed)
                if eventNamed and currencyNamed and
                    (entry:IsA("IntValue") or entry:IsA("NumberValue") or entry:IsA("StringValue")) then
                    local value=tonumber(entry.Value)
                    if value and value>=0 and value==math.floor(value) then
                        return value,entry:GetFullName()
                    end
                end
            end
        end
    end
    return nil
end
function Trade:GetPoints()
    return observedPoints()
end
-- Read-only gate for the user's one-time auto-buy authorization. Being armed
-- does not authorize guessing a balance or repeating an unresolved purchase.
function Trade:AutoBuyReadiness()
    if boughtThisRuntime or blockedUntilReload then return false,"Previous purchase/transaction completed or unresolved" end
    if not config then return false,"Halloween Exchange not initialized" end
    local category=SHOP[config:Get("HalloweenRewardCategory")]
    local selected=tostring(config:Get("HalloweenRewardTarget") or "")
    if not category then return false,"Select a valid Halloween reward category" end
    local price=nil
    for name,item in pairs(category.items) do
        if selected==name.." - "..tostring(item.price).." points" then
            price=item.price
            break
        end
    end
    if not price then return false,"Select a listed reward before enabling Auto Buy" end
    local points=self:GetPoints()
    if points==nil then return false,"Waiting for verified Halloween event points" end
    if points<price then
        return false,("Waiting for event points: %d/%d"):format(points,price)
    end
    return true,("Enough verified points: %d/%d"):format(points,price)
end
function Trade:InspectPoints()
    local found,path=self:GetPoints()
    if found then
        log("INFO","[Balance] Event points="..tostring(found).." source="..tostring(path))
        return true,("Verified event point balance: %d"):format(found)
    end
    local hints={}
    local roots={}
    for _,name in ipairs({"PlayerStats","leaderstats"}) do
        local root=Player:FindFirstChild(name)
        if root then roots[#roots+1]=root end
    end
    for _,root in ipairs(roots) do
        if root then
            local checked=0
            for _,entry in ipairs(root:GetDescendants()) do
                checked=checked+1
                if checked>300 then break end
                local n=tostring(entry.Name):lower()
                if (n:find("halloween",1,true) or n:find("candy",1,true)
                    or n:find("event",1,true) or n:find("point",1,true)) and
                    #hints<12 and (entry:IsA("ValueBase") or entry:IsA("Folder")) then
                    hints[#hints+1]=entry.Name.." ("..entry.ClassName..")"
                end
            end
        end
    end
    log("WARN","[Balance] No verified event-specific numeric points. Candidate stat labels: "..
        (#hints>0 and table.concat(hints,", ") or "none visible"))
    return false,"Event-point balance not verified (details in Console)"
end
local function clean(t)
    return tostring(t or ""):lower():gsub("[%c%p]"," "):gsub("%s+"," "):match("^%s*(.-)%s*$") or ""
end
local function actualVisible(object,gui)
    if not object or not object:IsDescendantOf(gui) then return false end
    local node=object
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled and node~=hiddenDialogue then return false end
        if node==gui then return true end
        node=node.Parent
    end
    return false
end
local function dialogue()
    local pg=Player:FindFirstChild("PlayerGui")
    local gui=pg and pg:FindFirstChild("DialogueGui")
    if gui and gui:IsA("ScreenGui") and not gui.Enabled and gui~=hiddenDialogue then return nil end
    return gui
end
local function hideJackRendering()
    if not config or config:Get("HalloweenFastDialogue")~=true then return false end
    if type(firesignal)~="function" and type(getconnections)~="function" then
        log("WARN","[Jack] Hidden dialogue unavailable: executor lacks internal click support")
        return false
    end
    local gui=dialogue()
    if not gui or not gui:IsA("ScreenGui") or gui~=Player.PlayerGui:FindFirstChild("DialogueGui") then
        return false
    end
    restoreJackRendering()
    hiddenDialogue=gui
    hiddenOriginallyEnabled=gui.Enabled
    hiddenConn=gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if hiddenDialogue==gui and gui.Enabled then gui.Enabled=false end
    end)
    gui.Enabled=false
    log("INFO","[Jack] Hidden dialogue active; underlying GUI kept for exact option checks")
    return true
end

-- Only a visible, exactly labelled OptionN is eligible for an automatic click.
local function findOption(wantedOption,wantedText)
    local gui=dialogue()
    if not gui then return nil end
    for _,node in ipairs(gui:GetDescendants()) do
        if node.Name==wantedOption and node:IsA("GuiObject") and actualVisible(node,gui) then
            local fragments={}
            if node:IsA("TextButton") and node.Text~="" then fragments[#fragments+1]=node.Text end
            for _,d in ipairs(node:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("TextButton")) and actualVisible(d,gui)
                    and type(d.Text)=="string" and d.Text~="" then
                    fragments[#fragments+1]=d.Text
                end
            end
            local matches=false
            for _,fragment in ipairs(fragments) do
                if clean(fragment)==clean(wantedText) then matches=true; break end
            end
            if matches then
                local button=node:IsA("GuiButton") and node
                    or node:FindFirstChildWhichIsA("GuiButton",true)
                if button and actualVisible(button,gui) then return button end
            end
        end
    end
    return nil
end
local function awaitOption(option,label,timeout)
    local deadline=tick()+(timeout or 6)
    while tick()<deadline and not blockedUntilReload do
        local candidate=findOption(option,label)
        if candidate then return candidate end
        task.wait(0.12)
    end
    return nil
end
local function clickOnce(button)
    if not button or not button.Parent then return false,"missing button" end
    local signal=button.MouseButton1Click
    if type(getconnections)=="function" then
        local ok,connections=pcall(getconnections,signal)
        if ok and type(connections)=="table" then
            for _,connection in ipairs(connections) do
                local fire,fn,active
                pcall(function() fire=connection.Fire end)
                pcall(function() fn=connection.Function end)
                pcall(function() active=connection.Enabled end)
                if active~=false and (type(fire)=="function" or type(fn)=="function") then
                    -- Dispatch one observed UI callback. Never invoke a guessed remote.
                    if type(fire)=="function" then
                        local dispatched=pcall(function() connection:Fire() end)
                        if dispatched then return true,"bound-connection" end
                    else
                        local dispatched=pcall(fn)
                        if dispatched then return true,"bound-function" end
                    end
                    return false,"bound callback failed"
                end
            end
        end
    end
    if type(firesignal)=="function" then
        local ok=pcall(firesignal,signal)
        if ok then return true,"firesignal" end
    end
    -- No internal callback: restore rendering before the compatibility click.
    if hiddenDialogue then
        log("WARN","[Jack] Internal click unsupported for option; switching back to visible mode")
        restoreJackRendering()
        task.wait()
    end
    if button.AbsoluteSize.X>0 and button.AbsoluteSize.Y>0 then
        local ok=pcall(function()
            local p,z=button.AbsolutePosition,button.AbsoluteSize
            local x,y=p.X+z.X/2,p.Y+z.Y/2
            VirtualInputManager:SendMouseButtonEvent(x,y,0,true,game,0)
            VirtualInputManager:SendMouseButtonEvent(x,y,0,false,game,0)
        end)
        if ok then return true,"rendered-click" end
    end
    return false,"no working click route"
end
local function safeToTrade(source)
    if blockedUntilReload then return false,"Previous Halloween result unresolved; reload to retry" end
    if not config then return false,"Halloween trade not initialized" end
    local auto=source=="event-farm" or source=="farm-checkpoint" or source=="auto-idle"
    if auto then
        if not (modules.Farm and modules.Farm.IsHalloweenTradeActive
            and modules.Farm:IsHalloweenTradeActive()) then
            return false,"Jack automation does not own movement"
        end
        if source=="event-farm" and
            (config:Get("EventItemsFarmEnabled")~=true or config:Get("FarmEnabled")==true) then
            return false,"Event Farm no longer owns collection"
        end
        if source=="farm-checkpoint" and
            (config:Get("FarmEnabled")~=true or config:Get("EventItemsFarmEnabled")==true) then
            return false,"Normal Farm no longer owns safe trade checkpoint"
        end
        if source=="auto-idle" and
            (config:Get("FarmEnabled")==true or config:Get("EventItemsFarmEnabled")==true) then
            return false,"Idle automation no longer has movement ownership"
        end
    else
        if config:Get("EventItemsFarmEnabled") or config:Get("FarmEnabled") then
            return false,"Disable Item Farm / Events Items Farm for manual trading"
        end
    end
    for _,flag in ipairs({"StandFarmEnabled","QuestFarmEnabled","NPCFarmEnabled","AutoPrestige"}) do
        if config:Get(flag)==true then return false,"Another farm is enabled: "..flag end
    end
    if modules.CommunityFeatures and modules.CommunityFeatures.IsPiloting
        and modules.CommunityFeatures:IsPiloting() then return false,"Stand Pilot active" end
    if not auto and modules.Farm and modules.Farm.IsBusy
        and modules.Farm:IsBusy() then return false,"Wait until Farm finishes movement/sale" end
    if modules.AutoPrestigeRuntime and modules.AutoPrestigeRuntime.IsBusy
        and modules.AutoPrestigeRuntime:IsBusy() then return false,"Prestige action pending" end
    return true
end
local JACK_NAMES={
    ["jack, the cauldron specter"]=true,
    ["halloween event"]=true,
}
local function jackPrompt()
    local root=workspace:FindFirstChild("Dialogues")
    if not root then return nil,"Workspace.Dialogues missing" end
    local best,count=nil,0
    -- Only prompts physically parented under a verified Jack/Halloween NPC.
    for _,obj in ipairs(root:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            local parent=obj.Parent
            local isJack=false
            while parent and parent~=root do
                if JACK_NAMES[parent.Name:lower()] then isJack=true;break end
                parent=parent.Parent
            end
            if isJack then
                count=count+1
                best=obj
            end
        end
    end
    if count==1 then return best,best:GetFullName() end
    return nil,count>1 and ("ambiguous Jack prompts: "..tostring(count))
        or "Jack ProximityPrompt not currently streamed"
end
local function findDefinition()
    for _,rootName in ipairs({"NewDialogue","Dialogue"}) do
        local root=ReplicatedStorage:FindFirstChild(rootName)
        if root then
            for _,npcName in ipairs({"Jack, The Cauldron Specter","Halloween Event"}) do
                local target=root:FindFirstChild(npcName)
                if target then return target,target:GetFullName() end
            end
        end
    end
    return nil
end
local function waitForJackOptions(timeout)
    local deadline=tick()+timeout
    while tick()<deadline do
        if findOption("Option2","I want to turn in my candy.")
            and findOption("Option3","I want to use my points!") then
            return true
        end
        task.wait(0.12)
    end
    return false
end
local function openJack()
    -- Wait until previous dialogues finish, but do not overwrite other NPC conversations.
    local deadline=tick()+3
    while dialogue() and tick()<deadline do task.wait(0.12) end
    if dialogue() then return false,"Close any existing dialogue before using Jack" end
    restoreJackRendering()
    local prompt,path=jackPrompt()
    if prompt and type(fireproximityprompt)=="function" then
        log("INFO","[Jack] Opening via live ProximityPrompt: "..path)
        local ok,err=pcall(fireproximityprompt,prompt)
        if ok and waitForJackOptions(4.5) then
            activeJackGui=dialogue()
            hideJackRendering()
            return true,"Live Jack prompt confirmed"
        end
        -- A prompt that failed to open might be out of streaming/range.
        log("WARN","[Jack] Live prompt did not reveal expected options; checking exact dialogue definition")
        if dialogue() then return false,"Jack dialogue opened with unexpected options; no action sent" end
    end
    local definition,definitionPath=findDefinition()
    local char=Player.Character
    local remote=char and char:FindFirstChild("RemoteEvent")
    if not definition or not remote then
        local reason=not definition and "matching Jack definition missing" or "character RemoteEvent missing"
        log("WARN","[Jack] "..tostring(path or "no live prompt").."; "..reason)
        return false,"Jack dialogue not opened ("..reason.."); no candy spent"
    end
    log("INFO","[Jack] Opening via exact definition: "..definitionPath)
    local ok,err=pcall(function() remote:FireServer("PromptTriggered",definition) end)
    if not ok then
        log("WARN","[Jack] PromptTriggered failed: "..tostring(err))
        return false,"Jack dialogue request failed"
    end
    if waitForJackOptions(5) then
        activeJackGui=dialogue()
        hideJackRendering()
        return true,"Jack dialogue confirmed"
    end
    return false,"Jack did not show verified Turn-In/Shop options; no candy spent"
end
-- Jack's post-turn-in message is an ordinary CLICK TO CONTINUE page,
-- not an OptionN. The candy deduction is already confirmed at this point.
-- Only advance the exact GUI that our own openJack() recognized, and only on
-- the verified "You now have N points" result. No speculative purchases or
-- remote actions; bounded attempts prevent a stuck hidden dialogue.
-- Resolve the final Jack result using the candy deduction ALREADY verified
-- by TurnInCandy, not the visibility of a typewriter TextLabel. During the
-- Invisible Jack mode the ScreenGui is disabled and the visible() predicate
-- can suppress the terminal string even while the final dialogue exists.
-- Never guess the next dialogue option or create a purchase request.
local function jackFinalPageState(owned)
    local textVerified=false
    for _,node in ipairs(owned:GetDescendants()) do
        if (node:IsA("TextLabel") or node:IsA("TextButton")
            or node:IsA("TextBox")) and type(node.Text)=="string" then
            local t=clean(node.Text)
            if t:find("you now have",1,true) and t:find("point",1,true) then
                textVerified=true
                break
            end
        end
    end
    -- An option is never a confirmation page. Its actions could spend points;
    -- do not call any continuation callback while real options are active.
    local choices=owned:FindFirstChild("Options",true)
    if choices then
        for _,node in ipairs(choices:GetDescendants()) do
            if node:IsA("GuiButton") and actualVisible(node,owned) then
                return false,textVerified,nil,"visible options still active"
            end
        end
    end
    local control=owned:FindFirstChild("ClickContinue",true)
    local button=control and (control:IsA("GuiButton") and control
        or control:FindFirstChildWhichIsA("GuiButton",true))
    return button~=nil,textVerified,button,
        control and (button and "continue ready" or "continue is not a GuiButton")
            or "continue control missing"
end

local function closeConfirmedJackTurnInResult()
    local owned=activeJackGui
    if not owned then return false,"Jack dialogue identity missing" end
    local pg=Player:FindFirstChild("PlayerGui")
    local started=tick()
    local deadline=started+5.5
    local attempts=0
    local revealed=false
    local sawText=false
    local status="result not ready"
    -- TurnInCandy only invokes this after detecting inventory candy decrease.
    -- Wait briefly for the YBA dialogue to leave Option2 and show Continue.
    while tick()<deadline do
        local current=pg and pg:FindFirstChild("DialogueGui")
        if not current or not owned.Parent then
            log("INFO","[TurnIn][Close] Jack dialogue closed after "..tostring(attempts).." Continue dispatch(es)")
            return true,"closed"
        end
        if current~=owned then return false,"Jack dialogue replaced before cleanup" end
        local ready,terminal,button,reason=jackFinalPageState(owned)
        sawText=sawText or terminal
        status=reason
        local elapsed=tick()-started
        if not revealed and hiddenDialogue==owned and elapsed>=0.65
            and (not ready or not terminal) then
            -- Fallback only for the verified Jack dialogue. Some YBA clients
            -- suspend text/typewriter updates while ScreenGui.Enabled=false.
            restoreJackRendering()
            revealed=true
            log("INFO","[TurnIn][Close] Temporarily restored final Jack page for Continue recovery")
        end
        if ready and (terminal or elapsed>=0.55) then
            if attempts>=4 then break end
            local clicked,route=clickOnce(button)
            if not clicked then
                status="Continue dispatch failed: "..tostring(route)
                if not revealed and hiddenDialogue==owned then
                    restoreJackRendering()
                    revealed=true
                    task.wait(0.12)
                else
                    break
                end
            else
                attempts=attempts+1
                log("INFO",("[TurnIn][Close] Continue dispatched %d/4 via %s (pointsText=%s)"):
                    format(attempts,tostring(route),tostring(terminal)))
                local untilTime=math.min(deadline,tick()+0.65)
                while tick()<untilTime do
                    if not owned.Parent or not pg or pg:FindFirstChild("DialogueGui")~=owned then
                        log("INFO","[TurnIn][Close] Final Jack result dismissed")
                        return true,"closed"
                    end
                    task.wait(0.07)
                end
            end
        else
            task.wait(0.10)
        end
    end
    log("WARN",("[TurnIn][Close] Could not close final GUI; attempts=%d pointsText=%s lastState=%s"):
        format(attempts,tostring(sawText),tostring(status)))
    return false,"Jack final Continue unresolved ("..tostring(status)..")"
end

local function action(source,job,operation)
    if busy then return false,"Another Halloween transaction is pending" end
    local allowed,reason=safeToTrade(source)
    if not allowed then return false,reason end
    busy=true
    activeJackGui=nil
    local original,character,hrp=nil,nil,nil
    if source=="event-farm" or source=="farm-checkpoint" or source=="auto-idle" then
        character=Player.Character
        hrp=character and character:FindFirstChild("HumanoidRootPart")
        if not hrp then busy=false;return false,"Player root not available for Jack trip" end
        original=hrp.CFrame
        local moved,moveReason=modules.CommunityFeatures:TeleportToLandmark("jack",true)
        if not moved then
            busy=false
            log("WARN","[Jack] Automatic transaction could not reach Jack: "..tostring(moveReason))
            return false,"Unable to reach Jack for automatic trade; "..tostring(moveReason)
        end
        log("INFO","[Jack] Automatic exchange visited live Jack location; returning after transaction.")
        task.wait(0.35)
    end
    local ok,success,message=pcall(job)
    local stuckResult=false
    if ok and success and operation=="turn-in" then
        local closed,why=closeConfirmedJackTurnInResult()
        if not closed then
            blockedUntilReload=true
            stuckResult=true
            log("WARN","[TurnIn][Close] "..tostring(why)..
                "; candy delivery confirmed, further Jack automation blocked")
            message=tostring(message).."; final Jack dialogue still open: close it manually"
        end
    end
    -- Restore rendering only after attempting the verified final Continue.
    -- If cleanup fails, show the GUI so the user can manually dismiss it.
    restoreJackRendering()
    activeJackGui=nil
    if original and not stuckResult then
        local restored=Player.Character==character and hrp and hrp.Parent
            and modules.Movement and modules.Movement:Teleport(original)
        if not restored then
            blockedUntilReload=true
            log("WARN","[Jack] Return to original Safe Spot failed; automatic retries blocked.")
            success=false
            message="Jack transaction ended but character could not be restored; stop auto trade"
        else
            log("INFO","[Jack] Character restored to previous Event Farm position.")
        end
    end
    if stuckResult then
        log("WARN","[TurnIn][Close] Stayed near Jack for manual dialogue recovery")
    end
    busy=false
    if not ok then log("WARN","[Trade] "..tostring(success));return false,"Halloween transaction failed; check Console" end
    return success,message
end
function Trade:TurnInCandy(source)
    return action(source,function()
        local before=candies()
        if before<=0 then return false,"No event candy in Backpack/Character" end
        local beforePoints=self:GetPoints()
        local opened,info=openJack()
        if not opened then return false,info end
        local choice=awaitOption("Option2","I want to turn in my candy.",6)
        if not choice then return false,"Expected Jack Option2 not visible; no candy submitted" end
        local clicked,route=clickOnce(choice)
        if not clicked then return false,route end
        log("INFO",("[TurnIn] Option2 dispatched via %s; candy before=%d; points before=%s"):format(
            route,before,tostring(beforePoints)))
        local deadline=tick()+7
        local reduction=0
        while tick()<deadline do
            local after=candies()
            local points=self:GetPoints()
            if after<before then reduction=math.max(reduction,before-after) end
            if reduction>0 and (not beforePoints or not points or points>beforePoints) then
                local pointsNote=(beforePoints and points)
                    and ("; points "..tostring(beforePoints).." -> "..tostring(points))
                    or "; event-point counter not exposed"
                log("INFO",("[TurnIn] Inventory decreased by %d candy%s"):format(reduction,pointsNote))
                return true,"Candy count decreased by "..reduction..pointsNote
            end
            task.wait(0.16)
        end
        if reduction>0 then
            blockedUntilReload=true
            log("WARN","[TurnIn] Candy decreased but event point balance did not rise within 7s.")
            return false,"Candy decreased but points did not increase; inspect event currency before retrying"
        end
        blockedUntilReload=true
        log("WARN","[TurnIn] Option2 submitted but inventory not reduced; retry blocked.")
        return false,"Turn-In result unresolved; no automatic retry this runtime"
    end,"turn-in")
end
function Trade:BuySelectedReward(source)
    return action(source,function()
        if boughtThisRuntime then return false,"Only one purchase attempt per runtime (reload for another)" end
        local catName=config:Get("HalloweenRewardCategory")
        local itemSelection=tostring(config:Get("HalloweenRewardTarget") or "")
        local category=SHOP[catName]
        if not category then return false,"Choose a valid Halloween category" end
        local chosen,price,label
        for name,entry in pairs(category.items) do
            local full=name.." - "..tostring(entry.price).." points"
            if itemSelection==full then chosen=entry;price=entry.price;label=name;break end
        end
        if not chosen then return false,"Choose a reward from the verified preview first" end
        local points,path=self:GetPoints()
        if not points then
            log("WARN","[Buy] No verified Halloween point balance; abort before selecting an item")
            self:InspectPoints()
            return false,"Halloween point balance not exposed; purchase locked, no points spent"
        end
        if points<price then return false,("Not enough event points: %d/%d"):format(points,price) end
        local opened,info=openJack()
        if not opened then return false,info end
        local root=awaitOption("Option3","I want to use my points!",6)
        if not root then return false,"Shop Option3 not confirmed" end
        local selected,route=clickOnce(root)
        if not selected then return false,route end
        local catChoice=awaitOption(category.option,catName,6)
        if not catChoice then return false,"Category not confirmed; stopped without buying" end
        selected,route=clickOnce(catChoice)
        if not selected then return false,route end
        local itemChoice=awaitOption(chosen.option,label.." - "..tostring(price),6)
        if not itemChoice then return false,"Reward/price page changed; stopped without buying" end
        local currentPoints=self:GetPoints()
        if currentPoints~=points then return false,"Point balance changed during navigation; purchase cancelled" end
        -- This may spend points immediately. One explicit action; never press
        -- unknown confirmation screens and never retry an uncertain transaction.
        boughtThisRuntime=true
        selected,route=clickOnce(itemChoice)
        if not selected then
            blockedUntilReload=true
            return false,"Purchase callback failed; retry locked for this runtime"
        end
        log("INFO",("[Buy] Requested once: %s for %d points via %s"):format(label,price,route))
        local deadline=tick()+6
        while tick()<deadline do
            local after=self:GetPoints()
            if after and after<=points-price then
                log("INFO",("[Buy] Point deduction confirmed: %s -> %s, reward=%s"):format(points,after,label))
                return true,"Purchased "..label.."; point deduction confirmed"
            end
            task.wait(0.2)
        end
        blockedUntilReload=true
        log("WARN","[Buy] Item selection sent, but point deduction not verified. No retry or confirmation click.")
        return false,"Purchase result unresolved. Check inventory/points manually; no retry this runtime"
    end)
end
function Trade:IsBusy() return busy end
function Trade:Init(all)
    modules,config,logger=all,all.Config,all.RuntimeLog
    log("INFO","Halloween Exchange beta loaded; optional Turn-In and guarded one-shot Buy.")
end
function Trade:Destroy()
    restoreJackRendering()
    activeJackGui=nil
    blockedUntilReload=true
    config=nil
end
return Trade
