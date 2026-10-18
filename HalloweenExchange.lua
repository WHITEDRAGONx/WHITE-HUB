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
function Trade:GetPoints()
    local stats=Player:FindFirstChild("PlayerStats")
    if not stats then return nil end
    for _,entry in ipairs(stats:GetDescendants()) do
        if entry:IsA("IntValue") or entry:IsA("NumberValue") then
            local name=entry.Name:lower():gsub("[^%a]","")
            if (name:find("halloween",1,true) or name:find("candy",1,true)
                or name:find("event",1,true)) and
                (name:find("point",1,true) or name:find("currency",1,true)) then
                local value=tonumber(entry.Value)
                if value and value>=0 then return value,entry:GetFullName() end
            end
        end
    end
    return nil
end
local function clean(t)
    return tostring(t or ""):lower():gsub("[%c%p]"," "):gsub("%s+"," "):match("^%s*(.-)%s*$") or ""
end
local function actualVisible(object,gui)
    if not object or not object:IsDescendantOf(gui) then return false end
    local node=object
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        if node==gui then return true end
        node=node.Parent
    end
    return false
end
local function dialogue()
    local pg=Player:FindFirstChild("PlayerGui")
    local gui=pg and pg:FindFirstChild("DialogueGui")
    if gui and gui:IsA("ScreenGui") and not gui.Enabled then return nil end
    return gui
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
            local label=clean(table.concat(fragments," "))
            if label==clean(wantedText) then
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
    -- Normal rendered click is the last supported route.
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
    if source=="event-farm" then
        if config:Get("EventItemsFarmEnabled")~=true or config:Get("FarmEnabled")==true then
            return false,"Event Farm no longer owns collection"
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
    if modules.Farm and source~="event-farm" and modules.Farm.IsBusy
        and modules.Farm:IsBusy() then return false,"Wait until Farm finishes movement/sale" end
    if modules.AutoPrestigeRuntime and modules.AutoPrestigeRuntime.IsBusy
        and modules.AutoPrestigeRuntime:IsBusy() then return false,"Prestige action pending" end
    return true
end
local function openJack()
    -- The turn-in response can close asynchronously; never overlap two dialogs.
    local deadline=tick()+3
    while dialogue() and tick()<deadline do task.wait(0.12) end
    if dialogue() then return false,"Close any existing dialogue before starting" end
    local root=ReplicatedStorage:FindFirstChild("NewDialogue")
    local definition=root and root:FindFirstChild("Halloween Event")
    local character=Player.Character
    local remote=character and character:FindFirstChild("RemoteEvent")
    if not definition or not remote then return false,"Halloween Jack not available in this server" end
    local ok=pcall(function() remote:FireServer("PromptTriggered",definition) end)
    return ok,ok and "Jack dialogue requested" or "Jack dialogue request rejected"
end
local function action(source,job)
    if busy then return false,"Another Halloween transaction is pending" end
    local allowed,reason=safeToTrade(source)
    if not allowed then return false,reason end
    busy=true
    local ok,success,message=pcall(job)
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
        while tick()<deadline do
            local after=candies()
            local points=self:GetPoints()
            if after<before then
                local delta=before-after
                local pointsNote=(beforePoints and points)
                    and ("; points "..tostring(beforePoints).." -> "..tostring(points))
                    or "; point counter not exposed"
                local credited=(beforePoints and points and points>beforePoints)
                if beforePoints and points and not credited then
                    blockedUntilReload=true
                    log("WARN","[TurnIn] Candy decreased, but the event point balance did not increase.")
                    return false,"Candy count decreased but points did not increase; result unresolved"
                end
                log("INFO",("[TurnIn] Confirmed inventory decrease: %d candy%s"):format(delta,pointsNote))
                return true,"Candy count decreased by "..delta..pointsNote
            end
            task.wait(0.16)
        end
        blockedUntilReload=true
        log("WARN","[TurnIn] Option2 submitted but inventory not reduced; retry blocked.")
        return false,"Turn-In result unresolved; no automatic retry this runtime"
    end)
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
    blockedUntilReload=true
    config=nil
end
return Trade
