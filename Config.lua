-- =====================
-- Config.lua (WHITE HUB V3)
-- Safer config loading/saving + batch updates.
-- =====================

local HttpService = game:GetService("HttpService")
local CONFIG_FILE = "WhiteHubConfig.json"

local Config = {}
local _data = nil

local Defaults = {
    BuyLucky = true,
    AutoSell = true,
    ConsoleFollow = true, -- Keep Console follow preference across server hops via WhiteHubConfig.json.
    FastSellHidden = true,
    MerchantPacingBeta = false, -- only optional; original Merchant intact by default.
    FastPickupEnabled = false, -- opt-in measured timing, no extra prompt calls.
    HalloweenFastDialogue = false, -- opt-in client-rendering suppression.
    MerchantTeleportPosition = {}, -- player standing point; never NPC center or roof.
    ArcadeTeleportPosition = {}, -- opt-in player-calibrated Arcade floor/entrance.
    WebhookURL = "",
    Phase1Notified = false,
    Phase3Notified = false,
    FarmEnabled = true,
    EventItemsFarmEnabled = false, -- Exclusive candy-only collection; separate from normal Item Farm.
    HalloweenAutoTurnIn = false, -- Opt-in conversion before event hop.
    HalloweenAutoBuy = false, -- Explicit opt-in per runtime, never resumed after hop.
    HalloweenRewardCategory = "2026 Halloween Event Items",
    HalloweenRewardTarget = "", -- Saved wishlist only; purchases are not enabled.
    AutoPrestige = false,
    PrestigeMaxNotified = false,
    StayInPrivateServer = false,
    SettingsCapFPS30 = false,
    SettingsUncapFPS = false,
    SettingsLowGraphics = false,
    SettingsBlackScreen = false,
    WhiteAIEnabled = false, -- private dev only
    WhiteAIEndpoint = "", -- private dev only
    CommunityAntiAFK = false, -- Explicit opt-in; no kick/ban immunity claimed.
    -- Stand Farm V1 is opt-in and never auto-starts after reload.
    StandFarmEnabled = false,
    StandFarmTarget = "",
    StandFarmTargets = {}, -- Empty list keeps the existing single-target mode.
    StandFarmMode = "stand", -- Opt-in "shiny" ignores common Stand targets.
    StandFarmConsumable = "Mysterious Arrow",
    StandFarmAutoRestock = false, -- Local collection; optional transfer configured separately.
    StandFarmRestockHop = false, -- One guarded transfer, then manual beta restart.
    StandFarmResumeAfterHop = false, -- Explicit opt-in exception for owned transfer only.
    StandFarmMaxHops = 3,
    StandFarmSkinTargets = {}, -- Exact wishlist; every skin is still protected.
    StandFarmRestockPendingItem = "", -- Non-secret restart notice, never a resume command.
    StandFarmPityLimit = 20,

    NPCFarmEnabled = false,
    QuestFarmEnabled = false,
    AutoChooseQuest = false,
    SelectedQuest = "",
    SelectedNPC = "",
    AutoSkills = {},

    SellItems = {
        ["Gold Coin"] = true,
        ["Rokakaka"] = true,
        ["Pure Rokakaka"] = true,
        ["Mysterious Arrow"] = true,
        ["Diamond"] = true,
        ["Ancient Scroll"] = true,
        ["Caesar's Headband"] = true,
        ["Stone Mask"] = true,
        ["Rib Cage of The Saint's Corpse"] = true,
        ["Quinton's Glove"] = true,
        ["Zeppeli's Hat"] = true,
        ["Lucky Arrow"] = false,
        ["Lucky Stone Mask"] = false,
        ["Clackers"] = true,
        ["Steel Ball"] = true,
        ["Dio's Diary"] = true,
    }
}

local function cloneTable(tbl)
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = type(v) == "table" and cloneTable(v) or v
    end
    return out
end

local function ApplyDefaults(data)
    data = type(data) == "table" and data or {}

    for key, default in pairs(Defaults) do
        if key ~= "SellItems" then
            if data[key] == nil then
                data[key] = type(default) == "table" and cloneTable(default) or default
            end
        end
    end

    -- Purchases never resume silently after a server change.
    data.HalloweenAutoBuy = false
    if type(data.SettingsUncapFPS) ~= "boolean" then data.SettingsUncapFPS = false end
    if data.SettingsUncapFPS==true and data.SettingsCapFPS30==true then data.SettingsCapFPS30=false end
    if type(data.MerchantPacingBeta) ~= "boolean" then data.MerchantPacingBeta=false end
    if type(data.HalloweenAutoTurnIn) ~= "boolean" then data.HalloweenAutoTurnIn = false end
    if type(data.FastPickupEnabled) ~= "boolean" then data.FastPickupEnabled = false end
    if type(data.HalloweenFastDialogue) ~= "boolean" then data.HalloweenFastDialogue = false end
    local merchantPos=data.MerchantTeleportPosition
    if type(merchantPos)~="table" or type(merchantPos.x)~="number"
        or type(merchantPos.y)~="number" or type(merchantPos.z)~="number"
        or merchantPos.x~=merchantPos.x or merchantPos.y~=merchantPos.y or merchantPos.z~=merchantPos.z
        or math.abs(merchantPos.x)>100000 or math.abs(merchantPos.y)>100000
        or math.abs(merchantPos.z)>100000 then
        data.MerchantTeleportPosition={}
    end
    local arcadePos=data.ArcadeTeleportPosition
    if type(arcadePos)~="table" or type(arcadePos.x)~="number"
        or type(arcadePos.y)~="number" or type(arcadePos.z)~="number"
        or arcadePos.x~=arcadePos.x or arcadePos.y~=arcadePos.y or arcadePos.z~=arcadePos.z
        or math.abs(arcadePos.x)>100000 or math.abs(arcadePos.y)>100000
        or math.abs(arcadePos.z)>100000 then
        data.ArcadeTeleportPosition={}
    end
    -- Old or corrupt saves must never enable two item collection modes together.
    if type(data.EventItemsFarmEnabled) ~= "boolean" then data.EventItemsFarmEnabled = false end
    if data.FarmEnabled == true or data.AutoPrestige == true or data.StandFarmEnabled == true
        or data.QuestFarmEnabled == true or data.NPCFarmEnabled == true then
        data.EventItemsFarmEnabled = false
    end
    if type(data.HalloweenRewardCategory) ~= "string" then data.HalloweenRewardCategory = Defaults.HalloweenRewardCategory end
    if type(data.HalloweenRewardTarget) ~= "string" then data.HalloweenRewardTarget = "" end
    if type(data.AutoSkills) ~= "table" then data.AutoSkills = {} end
    if type(data.SellItems) ~= "table" then data.SellItems = {} end

    for name, default in pairs(Defaults.SellItems) do
        if data.SellItems[name] == nil then
            data.SellItems[name] = default
        end
    end

    return data
end

function Config:Load()
    if _data then return true end

    local ok, result = pcall(function()
        if type(isfile) == "function" and isfile(CONFIG_FILE) and type(readfile) == "function" then
            return HttpService:JSONDecode(readfile(CONFIG_FILE))
        end
        return nil
    end)

    if ok and type(result) == "table" then
        _data = ApplyDefaults(result)
        print("[Config] Loaded from file.")
        return true
    end

    _data = ApplyDefaults({})
    if not ok then
        warn("[Config] Failed to read config: " .. tostring(result))
    else
        print("[Config] No existing config found — using defaults.")
    end
    return false
end

function Config:Save()
    if not _data then return false end
    if type(writefile) ~= "function" then
        warn("[Config] writefile is unavailable; settings will not persist.")
        return false
    end

    local ok, err = pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(_data))
    end)
    if not ok then
        warn("[Config] Save failed: " .. tostring(err))
    end
    return ok
end

function Config:Get(key)
    if not _data then self:Load() end
    return _data[key]
end

function Config:Set(key, value, skipSave)
    if not _data then self:Load() end
    _data[key] = value
    if not skipSave then self:Save() end
end

function Config:SetMany(values)
    if not _data then self:Load() end
    if type(values) ~= "table" then return false end
    for key, value in pairs(values) do
        _data[key] = value
    end
    return self:Save()
end

function Config:GetSellItem(name)
    if not _data then self:Load() end
    return _data.SellItems[name]
end

function Config:SetSellItem(name, value, skipSave)
    if not _data then self:Load() end
    _data.SellItems[name] = value
    if not skipSave then self:Save() end
end

function Config:GetSellItems()
    if not _data then self:Load() end
    return _data.SellItems
end

return Config
