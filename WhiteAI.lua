-- WHITE HUB V3 - WHITE AI V1 (experimental)
-- Diagnostics only; never executes AI-authored code, modifies gameplay or touches Inventory.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local WhiteAI = {}

local _config, _log, _combat, _subscription
local _running = false
local _epoch = 0
local _latest = nil
local _history = {}
local _dedupe = {}
local _sending = false
local _lastJobId = nil
local _proposalUrl = nil
local _jobHistory = {} -- Last 5 local job outcomes only; no secrets.
local _ingestKey = ""
local _adminKey = "" -- owner-only, session memory; never persist/print
local _lastStatus = "Local diagnostics ready"
local _questLast = nil
local _questChangedAt = 0
local _lastHealthAlert = 0

local function now() return os.clock() end
local function safeText(value, maxLen)
    local s = tostring(value or "")
    s = s:gsub("https?://[^%s]+", "[URL]")
    s = s:gsub("[%w_.-]+@[%w_.-]+", "[EMAIL]")
    if Player and Player.Name then
        s = s:gsub(Player.Name:gsub("([^%w])", "%%%1"), "[PLAYER]")
    end
    return s:sub(1, maxLen or 240)
end

local function cleanEntry(entry)
    return {
        level = safeText(entry.Level, 10),
        module = safeText(entry.Module, 40),
        message = safeText(entry.Message, 280),
    }
end

local function questStats()
    local stats = Player and Player:FindFirstChild("PlayerStats")
    if not stats then return nil end
    local progress = stats:FindFirstChild("QuestProgress")
    local maximum = stats:FindFirstChild("QuestMaxProgress")
    if progress and maximum and tonumber(progress.Value) and tonumber(maximum.Value) then
        return { progress = progress.Value, maximum = maximum.Value }
    end
    return nil
end

local function snapshot()
    local recent = {}
    if _log and type(_log.GetEntries) == "function" then
        local ok, entries = pcall(_log.GetEntries, _log)
        if ok and type(entries) == "table" then
            local positions, included = {}, {}
            -- Retain up to 3 recent warnings/errors even when INFO messages
            -- would otherwise drown out the quest/dialogue failure.
            for i = #entries, math.max(1, #entries - 59), -1 do
                local entry = entries[i]
                if entry and entry.Module ~= "WhiteAI"
                    and (entry.Level == "WARN" or entry.Level == "ERROR") then
                    positions[#positions + 1] = i
                    included[i] = true
                    if #positions >= 3 then break end
                end
            end
            for i = #entries, 1, -1 do
                if #positions >= 10 then break end
                local entry = entries[i]
                if entry and entry.Module ~= "WhiteAI" and not included[i] then
                    positions[#positions + 1] = i
                    included[i] = true
                end
            end
            table.sort(positions)
            for _, i in ipairs(positions) do
                recent[#recent + 1] = cleanEntry(entries[i])
            end
        end
    end
    local combatRunning = false
    if _combat and type(_combat.IsRunning) == "function" then
        local ok, value = pcall(_combat.IsRunning, _combat)
        combatRunning = ok and value == true
    end
    return {
        quest = questStats(),
        combat_running = combatRunning,
        quest_enabled = _config and _config:Get("QuestFarmEnabled") == true or false,
        npc_enabled = _config and _config:Get("NPCFarmEnabled") == true or false,
        selected_quest = _config and safeText(_config:Get("SelectedQuest"), 90) or "",
        auto_choose_quest = _config and _config:Get("AutoChooseQuest") == true or false,
        recent = recent,
    }
end

local function shouldAutoReport(message, level)
    if level == "ERROR" then return true end
    if level ~= "WARN" then return false end
    local msg = tostring(message or ""):lower()
    return msg:find("failed", 1, true) or msg:find("timed out", 1, true)
        or msg:find("no progress", 1, true) or msg:find("error", 1, true)
        or msg:find("not found", 1, true) or msg:find("did not", 1, true)
        or msg:find("stuck", 1, true)
end

local function validEndpoint(url)
    if type(url) ~= "string" or #url > 240 then return false end
    return url:match("^https://[%w%.%-]+[%w%-%./:_]*$")
        and not url:find("@", 1, true)
        and not url:find("//", 9, true)
end

local function transport(url, json, ingestKey, adminKey)
    local requestFn = (syn and syn.request) or http_request or request
        or (http and http.request)
    if type(requestFn) == "function" then
        local headers = {
            ["Content-Type"] = "application/json",
            ["X-WhiteAI-Key"] = ingestKey,
        }
        if type(adminKey) == "string" and #adminKey >= 32 then
            headers["X-WhiteAI-Admin-Key"] = adminKey
        end
        local response = requestFn({
            Url = url, Method = "POST",
            Headers = headers,
            Body = json,
        })
        local code = tonumber(response and (response.StatusCode or response.Status))
        if not code then return false, "No HTTP status returned by executor" end
        if code < 200 or code >= 300 then
            local detail = ""
            local body = response and (response.Body or response.body)
            if type(body) == "string" and #body < 2000 then
                local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, body)
                if decodedOk and type(decoded) == "table" and type(decoded.detail) == "string" then
                    detail = ": " .. safeText(decoded.detail, 110)
                end
            end
            return false, "HTTP " .. tostring(code) .. detail
        end
        local payload = response and (response.Body or response.body)
        local data = nil
        if type(payload) == "string" and #payload < 3000 then
            local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, payload)
            if decodedOk and type(decoded) == "table" then data = decoded end
        end
        return true, "HTTP " .. tostring(code), data
    end
    -- PostAsync cannot attach the private report-ingest header.
    -- Do not send a report without authentication: no anonymous fallback.
    error("This executor has no HTTP request API with custom headers")
end

-- A POST /reports acknowledgement only means queued. Poll the authenticated
-- backend until the proposal is saved or a specific analysis error is known.
local function recordJob(jobId, status, data)
    local result = {
        job_id = jobId, status = status,
        module = safeText(data and data.module or "", 40),
        diagnosis = safeText(data and data.diagnosis or "", 180),
        confidence = type(data and data.confidence) == "number" and data.confidence or nil,
        proposal_url = data and data.proposal_url or nil,
    }
    table.insert(_jobHistory, 1, result)
    while #_jobHistory > 5 do table.remove(_jobHistory) end
end

local function watchJob(endpoint, key, jobId, token)
    if type(jobId) ~= "string" or not jobId:match("^[0-9a-f]+$") or #jobId ~= 20 then
        _lastStatus = "Report accepted, but backend did not return a valid job ID"
        return
    end

    local requestFn = (syn and syn.request) or http_request or request
        or (http and http.request)
    if type(requestFn) ~= "function" then return end

    local jobUrl = endpoint:gsub("/reports$", "/jobs/" .. jobId)
    if jobUrl == endpoint then return end

    for attempt = 1, 40 do
        task.wait(7)
        if not _running or _epoch ~= token then return end
        local ok, response = pcall(requestFn, {
            Url = jobUrl, Method = "GET",
            Headers = { ["X-WhiteAI-Key"] = key },
        })
        if ok and type(response) == "table" then
            local status = tonumber(response.StatusCode or response.Status)
            if status == 200 then
                local body = response.Body or response.body
                if type(body) == "string" and #body < 4000 then
                    local decodedOk, payload = pcall(HttpService.JSONDecode, HttpService, body)
                    if decodedOk and type(payload) == "table" then
                        if payload.status == "proposal_ready" then
                            _proposalUrl = type(payload.proposal_url) == "string"
                                and payload.proposal_url or nil
                            _lastStatus = "AI analysis complete! Proposal saved in GitHub dev branch."
                            recordJob(jobId, "proposal_ready", payload)
                            return
                        elseif payload.status == "no_incident" then
                            _lastStatus = "No recent issues; Gemini call skipped to save free quota."
                            recordJob(jobId, "no_incident", payload)
                            return
                        elseif payload.status == "failed" then
                            local reasonCode = type(payload.error_code) == "string"
                                and payload.error_code or payload.error
                            _lastStatus = "AI analysis failed: " .. safeText(reasonCode, 80)
                            recordJob(jobId, "failed", { diagnosis = _lastStatus })
                            return
                        elseif type(payload.status) == "string" then
                            _lastStatus = "AI job " .. safeText(payload.status, 40)
                        end
                    end
                end
            elseif status == 401 or status == 404 then
                _lastStatus = "Job status unavailable (HTTP " .. tostring(status) .. ")"
                return
            end
        end
    end
    _lastStatus = "AI analysis still unconfirmed: check Render logs and ai/proposals"
end

function WhiteAI:GetStatus()
    return {
        message = _lastStatus,
        enabled = _config and _config:Get("WhiteAIEnabled") == true or false,
        endpoint_set = _config and validEndpoint(_config:Get("WhiteAIEndpoint")) == true or false,
        ingest_key_set = #_ingestKey > 0,
        private_owner_session = #_adminKey >= 32,
        incidents = #_history,
        latest = _latest,
        sending = _sending,
        job_id = _lastJobId,
        proposal_url = _proposalUrl,
        jobs = _jobHistory,
    }
end

function WhiteAI:BuildReport(category, reason, moduleName)
    local id = HttpService:GenerateGUID(false):gsub("[^%w%-]", "")
    return {
        schema = 1,
        id = id,
        category = safeText(category, 45),
        module = safeText(moduleName, 45),
        reason = safeText(reason, 450),
        context = snapshot(),
    }
end

function WhiteAI:Submit(report)
    if _sending then return false, "Another report is being sent" end
    if not _config or _config:Get("WhiteAIEnabled") ~= true then
        return false, "External AI disabled; local diagnostics still active"
    end
    local endpoint = _config:Get("WhiteAIEndpoint")
    if not validEndpoint(endpoint) then
        return false, "Set a valid HTTPS report endpoint first"
    end

    if _ingestKey == "" then
        return false, "Set your report-ingest key for this session"
    end
    _sending = true
    _proposalUrl = nil
    _lastJobId = nil
    _lastStatus = "Sending diagnostic " .. tostring(report.id)
    local sessionToken = _epoch
    local sessionKey = _ingestKey
    local sessionAdminKey = _adminKey
    task.spawn(function()
        local ok, delivered, reason, payload = pcall(function()
            return transport(endpoint, HttpService:JSONEncode(report), sessionKey, sessionAdminKey)
        end)
        if not _running or _epoch ~= sessionToken then return end
        _sending = false
        if ok and delivered == true then
            _lastStatus = "Diagnostic received; AI job queued."
            local jobId = type(payload) == "table" and payload.job_id or nil
            _lastJobId = jobId
            if jobId then
                task.spawn(watchJob, endpoint, sessionKey, jobId, sessionToken)
            else
                _lastStatus = "Diagnostic received, but job tracking is unavailable"
            end
        else
            _lastStatus = "Delivery failed: " .. safeText(ok and reason or delivered, 150)
        end
    end)
    return true, "Report queued"
end

function WhiteAI:Observe(category, message, moduleName, urgent)
    local reason = safeText(message, 450)
    local kind = safeText(category, 45)
    local module = safeText(moduleName, 45)
    local key = kind .. "|" .. module .. "|" .. reason:gsub("%d+", "#")
    if _dedupe[key] and now() - _dedupe[key] < 120 then return false end
    _dedupe[key] = now()

    local report = self:BuildReport(kind, reason, module)
    _latest = report
    _history[#_history + 1] = { category = kind, module = module, reason = reason }
    if #_history > 30 then table.remove(_history, 1) end
    _lastStatus = kind .. " | " .. reason:sub(1, 100)

    -- Logging to RuntimeLog can cause recursive subscriptions; use native print.
    print("[WhiteAI][Observation] " .. _lastStatus)
    if urgent and _config and _config:Get("WhiteAIEnabled") then
        self:Submit(report)
    end
    return true
end

function WhiteAI:SendManualReport()
    local report = self:BuildReport("manual_diagnostic",
        _latest and _latest.reason or "Manual review requested", "General")
    _latest = report
    return self:Submit(report)
end

function WhiteAI:SetEndpoint(url)
    if not validEndpoint(url) then return false, "HTTPS URL required" end
    _config:Set("WhiteAIEndpoint", url)
    return true
end

function WhiteAI:SetIngestKey(token)
    if type(token) ~= "string" or #token < 12 or #token > 128 then
        return false, "Expected a 12-128 character ingestion key"
    end
    _ingestKey = token
    return true
end

function WhiteAI:SetAdminKey(token)
    if token == "" then
        _adminKey = ""
        return true, "Private auto-commit authorization cleared."
    end
    if type(token) ~= "string" or #token < 32 or #token > 128 then
        return false, "Admin key must have 32-128 characters."
    end
    _adminKey = token
    return true, "Owner-only session authorization stored in memory."
end

function WhiteAI:SetEnabled(enabled)
    _config:Set("WhiteAIEnabled", enabled == true)
    return true
end

local function heartbeat()
    local active = _config and _config:Get("QuestFarmEnabled") == true
    local s = active and questStats() or nil
    if not active or not s or s.maximum <= 0 then
        _questLast = nil
        _questChangedAt = now()
        return
    end
    local signature = tostring(s.progress) .. "/" .. tostring(s.maximum)
    if signature ~= _questLast then
        _questLast = signature
        _questChangedAt = now()
    elseif now() - _questChangedAt > 95 and now() - _lastHealthAlert > 150 then
        _lastHealthAlert = now()
        WhiteAI:Observe("quest_stall", "Quest progress unchanged for 95s (" .. signature .. ")", "CombatFarm", true)
    end
end

function WhiteAI:Init(modules)
    _config = modules.Config
    _log = modules.RuntimeLog
    _combat = modules.CombatFarm
    if _subscription then pcall(function() _subscription:Disconnect() end) end
    _subscription = _log and _log:Subscribe(function(entry)
        if entry.Module == "WhiteAI" then return end
        if shouldAutoReport(entry.Message, entry.Level) then
            -- Queue outside of logger callback to avoid recursion or slow writes.
            task.defer(function()
                if _running then
                    WhiteAI:Observe("runtime_" .. tostring(entry.Level):lower(), entry.Message, entry.Module, true)
                end
            end)
        end
    end)
    _running = true
    _epoch = _epoch + 1
    local token = _epoch
    _questChangedAt = now()
    task.spawn(function()
        while _running and _epoch == token do
            task.wait(5)
            if _running and _epoch == token then pcall(heartbeat) end
        end
    end)
    print("[WhiteAI] V1 local diagnostics ready; external reporting is opt-in.")
end

function WhiteAI:Destroy()
    _running = false
    _epoch = _epoch + 1
    if _subscription then
        pcall(function() _subscription:Disconnect() end)
        _subscription = nil
    end
    _sending = false
    _lastJobId = nil
    _proposalUrl = nil
    _jobHistory = {}
    _ingestKey = ""
    _adminKey = ""
end

return WhiteAI
