-- =====================
-- Webhook.lua
-- Handles all Discord webhook communication.
-- =====================

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local Player      = Players.LocalPlayer

local Webhook = {}
local _config = nil
local _runtimeLog = nil

function Webhook:Init(Modules)
    _config = Modules.Config
    _runtimeLog = Modules.RuntimeLog
end

local function log(level, message)
    if _runtimeLog and type(_runtimeLog.Write) == "function" then
        pcall(_runtimeLog.Write, _runtimeLog, level, "Webhook", message)
    end
end

local function Send(message, safeResult)
    local url = _config:Get("WebhookURL")
    if not url or url == "" then
        log("INFO", "Webhook URL is empty; notification skipped.")
        return
    end
    local responseCode
    local ok, err = pcall(function()
        local body = HttpService:JSONEncode({
            content = nil,
            allowed_mentions = safeResult and {parse = {}} or nil,
            embeds = {{
                title       = "WHITE HUB — Notification",
                description = message,
                color       = 7864319,
                footer      = { text = "WHITE HUB by WHITE DRAGON" },
                timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }}
        })
        local req = http_request or request or (syn and syn.request)
        if not req then
            error("No supported HTTP request function is available in this executor.")
        end
        local response = req({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
        if safeResult then
            responseCode = type(response) == "table" and tonumber(response.StatusCode or response.Status) or nil
            if not responseCode or responseCode < 200 or responseCode >= 300 then
                error("Webhook response was not successful")
            end
        end
    end)
    if ok then
        log("INFO", "Discord webhook request sent.")
    elseif safeResult then
        -- Executor exceptions/response bodies may contain the private webhook URL.
        log("WARN", "Stand farm webhook failed" .. (responseCode and (" (HTTP " .. responseCode .. ")") or " (request unavailable or failed)") .. "; no retry")
    else
        log("ERROR", "Discord webhook failed: " .. tostring(err))
    end
    return ok
end

local function resultText(value, limit)
    if value == nil then return "Unknown / not checked" end
    return tostring(value):gsub("https?://%S+", "[redacted URL]"):gsub("[%c`@]", " "):sub(1, limit or 100)
end

-- Called asynchronously by StandFarm only for a confirmed terminal result or
-- automatic stop. Never infer a skin from an earlier run or send every roll.
function Webhook:SendStandFarmResult(result)
    if type(result) ~= "table" then return false end
    local title = "Stand/Shiny/Rib Farm stopped"
    if result.kind == "target" then title = "Target Stand found"
    elseif result.kind == "skin" then
        title = result.desired_skin and "Target skin found — preserved" or "Skin found — preserved"
    end
    return Send(
        "**" .. title .. "**\n"
        .. "Player: `" .. resultText(Player.Name, 80) .. "`\n"
        .. "Mode: `" .. (result.mode == "shiny" and "Shiny" or "Stand") .. "`\n"
        .. "Consumable: `" .. resultText(result.consumable) .. "`\n"
        .. "Stand: `" .. resultText(result.stand) .. "`\n"
        .. "Skin: `" .. resultText(result.skin) .. "`\n"
        .. "Pity: `" .. resultText(result.pity, 20) .. "` | Confirmed rolls: `" .. resultText(result.rolls, 20) .. "`\n"
        .. "Elapsed: `" .. math.floor(tonumber(result.elapsed) or 0) .. "s`\n"
        .. "Reason: `" .. resultText(result.reason, 240) .. "`"
        .. (result.pending and "\n**Item result unresolved — verify manually before restarting.**" or ""), true
    )
end

function Webhook:Send(message)
    Send(message)
end

function Webhook:SendPhase1Complete(luckyCount, luckyStop, money)
    Send(
        "🎯 **Phase 1 complete — switching to keep-item farm!**\n"
        .. "Player: `" .. Player.Name .. "`\n"
        .. "Lucky Arrows: `" .. luckyCount .. "/" .. luckyStop .. "`\n"
        .. "Money: `$" .. tostring(money) .. "`"
    )
end

function Webhook:SendAllComplete(luckyCount, luckyStop, money)
    Send(
        "✅ **All farming complete!**\n"
        .. "Player: `" .. Player.Name .. "`\n"
        .. "Lucky Arrows: `" .. luckyCount .. "/" .. luckyStop .. "`\n"
        .. "Money: `$" .. tostring(money) .. "`\n"
        .. "All keep-items are maxed. Script is now idling."
    )
end

function Webhook:SendFarmDisabled()
    Send(
        "🛑 **Farm manually disabled**\n"
        .. "Player: `" .. Player.Name .. "`\n"
        .. "Farming has been paused by the user.\n"
        .. "Use the UI toggle to resume."
    )
end

function Webhook:SendFarmResumed()
    Send(
        "🟢 **Farm manually re-enabled**\n"
        .. "Player: `" .. Player.Name .. "`\n"
        .. "Farming has been resumed by the user."
    )
end

function Webhook:SendLuckyFound(luckyCount, luckyStop, money)
    Send(
        "✅ **Phase 1 conditions met!**\n"
        .. "Player: `" .. Player.Name .. "`\n"
        .. "Lucky Arrows: `" .. luckyCount .. "/" .. luckyStop .. "`\n"
        .. "Money: `$" .. tostring(money) .. "`"
    )
end

function Webhook:SendError(context)
    Send(
        "⚠️ **Error / Warning**\n"
        .. "Player: `" .. Player.Name .. "`\n"
        .. "Context: `" .. tostring(context) .. "`"
    )
end

-- Called when Auto Prestige reaches Prestige 3, Level 50
function Webhook:SendPrestigeComplete()
    Send(
        "🏆 **Prestige maxed out!**\n"
        .. "Player: `" .. Player.Name .. "`\n"
        .. "Reached **Prestige 3, Level 50**.\n"
        .. "Auto Prestige has been disabled automatically.\n"
        .. "The script will now return to normal item farming."
    )
end

return Webhook
