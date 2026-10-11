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
    FastSellHidden = true,
    WebhookURL = "",
    Phase1Notified = false,
    Phase3Notified = false,
    FarmEnabled = true,
    AutoPrestige = false,
    PrestigeMaxNotified = false,
    StayInPrivateServer = false,
    WhiteAIEnabled = false,
    WhiteAIEndpoint = "",
    -- Stand Farm V1 is opt-in and never auto-starts after reload.
    StandFarmEnabled = false,
    StandFarmTarget = "",
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
