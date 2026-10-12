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
local _pendingAutoReports = {} -- bounded diagnostics queue, never stores keys
local _autoWorkerRunning = false
local _lastAutoSentAt = -math.huge
local _lastJobId = nil
local _proposalUrl = nil
local _jobHistory = {} -- Last 5 local job outcomes only; no secrets.
local _ingestKey = ""
local _adminKey = "" -- owner-only, session memory; never persist/print
local _ownerSession = ""
local _sessionExpires = 0
local _pairing = false
local SESSION_FILE = "WHITE_AI_DEVICE_SESSION.json"
local _lastStatus = "Local diagnostics ready"
local _watching = {}
local _recovering = false
local _questLast = nil
local _questChangedAt = 0
local _lastHealthAlert = 0

local function now() return os.clock() end
local function safeText(value, maxLen)
    local s = tostring(value or "")
    s = s:gsub("wa1%.[%w_.%-]+", "[SESSION]")
    for _, secret in ipairs({_ingestKey, _adminKey, _ownerSession}) do
        if #secret > 0 then s = s:gsub(secret:gsub("([^%w])", "%%%1"), "[REDACTED]") end
    end
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

local function sessionHeaders(key)
    if #_ownerSession > 0 then return { ["X-WhiteAI-Session"] = _ownerSession } end
    return { ["X-WhiteAI-Key"] = key }
end

local function transport(url, json, ingestKey, adminKey)
    local requestFn = (syn and syn.request) or http_request or request
        or (http and http.request)
    if type(requestFn) == "function" then
        local headers = sessionHeaders(ingestKey)
        headers["Content-Type"] = "application/json"
        if #_ownerSession == 0 and type(adminKey) == "string" and #adminKey >= 32 then
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
            if code == 401 and #_ownerSession > 0 then
                _ownerSession = ""
                _sessionExpires = 0
                if type(delfile) == "function" then pcall(delfile, SESSION_FILE) end
            end
            return false, "HTTP " .. tostring(code)
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

local function watchJobLoop(endpoint, key, jobId, token)
    if type(jobId) ~= "string" or not jobId:match("^[0-9a-f]+$") or #jobId ~= 20 then
        _lastStatus = "Report accepted, but backend did not return a valid job ID"
        return
    end

    local requestFn = (syn and syn.request) or http_request or request
        or (http and http.request)
    if type(requestFn) ~= "function" then return end

    local jobUrl = endpoint:gsub("/reports$", "/jobs/" .. jobId)
    if jobUrl == endpoint then return end

    local lastQueueState
    for attempt = 1, 120 do
        task.wait(7)
        if not _running or _epoch ~= token or not _config:Get("WhiteAIEnabled") then return end
        local ok, response = pcall(requestFn, {
            Url = jobUrl, Method = "GET",
            Headers = sessionHeaders(key),
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
                            local patchState = type(payload.auto_patch) == "table"
                                and payload.auto_patch.state or nil
                            if patchState == "dev_committed_unverified" then
                                _lastStatus = "PRIVATE DEV patch committed with rollback. NOT TESTED IN ROBLOX."
                            elseif patchState == "review_only" then
                                _lastStatus = "AI proposal saved; auto-patch held for review."
                            else
                                _lastStatus = "AI analysis complete! Proposal saved in GitHub dev branch."
                            end
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
                        elseif payload.status == "waiting_retry" or payload.status == "queued" then
                            _lastStatus = "Incident saved; " .. (payload.status == "queued" and "analysis queued"
                                or "retry scheduled") .. " (" .. tostring(payload.attempts or 0) .. "/3)"
                            local queueState = payload.status .. tostring(payload.attempts or 0)
                            if queueState ~= lastQueueState then
                                recordJob(jobId, payload.status, {diagnosis = _lastStatus})
                                lastQueueState = queueState
                            end
                        elseif payload.status == "retry_exhausted" or payload.status == "storage_failure" then
                            _lastStatus = payload.status == "retry_exhausted"
                                and "Incident saved; 3-analysis limit reached. No patch applied."
                                or "Storage failed; recover the incident before resending."
                            recordJob(jobId, payload.status, {diagnosis = _lastStatus})
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
    _lastStatus = "Analysis pending; use RECOVER SAVED INCIDENTS to check again."
end

local function watchJob(endpoint, key, jobId, token)
    if not jobId or _watching[jobId] == token then return end
    _watching[jobId] = token
    pcall(watchJobLoop, endpoint, key, jobId, token)
    if _watching[jobId] == token then _watching[jobId] = nil end
end

function WhiteAI:GetStatus()
    return {
        message = _lastStatus,
        enabled = _config and _config:Get("WhiteAIEnabled") == true or false,
        endpoint_set = _config and validEndpoint(_config:Get("WhiteAIEndpoint")) == true or false,
        ingest_key_set = #_ingestKey > 0,
        private_owner_session = #_ownerSession > 0,
        pairing = _pairing,
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

    if _ingestKey == "" and _ownerSession == "" then
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
            _lastStatus = "Delivery failed: " .. safeText(ok and reason or "HTTP transport unavailable", 150)
        end
    end)
    return true, "Report queued"
end

function WhiteAI:FlushPending()
    if _autoWorkerRunning then return end
    if #_pendingAutoReports == 0 then return end
    _autoWorkerRunning = true
    local workerEpoch = _epoch
    task.spawn(function()
        while _running and workerEpoch == _epoch and #_pendingAutoReports > 0 do
            if not _config or _config:Get("WhiteAIEnabled") ~= true or (_ingestKey == "" and _ownerSession == "") then
                break -- retain pending events until the owner enables private delivery
            end
            if _sending then
                task.wait(0.5)
            elseif now() - _lastAutoSentAt < 27 then
                task.wait(math.min(1, 27 - (now() - _lastAutoSentAt)))
            else
                local report = table.remove(_pendingAutoReports, 1)
                local ok, reason = WhiteAI:Submit(report)
                if ok then
                    _lastAutoSentAt = now()
                elseif reason == "Another report is being sent" then
                    table.insert(_pendingAutoReports, 1, report)
                    task.wait(0.5)
                else
                    -- Never retry a permanently unconfigured endpoint on a hot loop.
                    table.insert(_pendingAutoReports, 1, report)
                    break
                end
            end
        end
        _autoWorkerRunning = false
    end)
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
    if urgent then
        if #_pendingAutoReports >= 6 then
            table.remove(_pendingAutoReports, 1)
            print("[WhiteAI][Queue] capacity reached; oldest incident was dropped.")
        end
        _pendingAutoReports[#_pendingAutoReports + 1] = report
        self:FlushPending()
    end
    return true
end

function WhiteAI:SendManualReport()
    local report = self:BuildReport("manual_diagnostic",
        _latest and _latest.reason or "Manual review requested", "General")
    _latest = report
    return self:Submit(report)
end

local function authRequest(endpoint, path, method, headers)
    local requestFn = (syn and syn.request) or http_request or request or (http and http.request)
    if type(requestFn) ~= "function" then return nil end
    local base = endpoint:match("^(https://[%w%.%-]+)/reports$")
    if not base then return nil end
    local ok, response = pcall(requestFn, { Url = base .. path, Method = method,
        Headers = headers, Body = method == "POST" and "{}" or nil })
    if not ok or type(response) ~= "table" then return nil end
    local status = tonumber(response.StatusCode or response.Status)
    if status ~= 200 and status ~= 202 then return nil end
    local body = response.Body or response.body
    if type(body) ~= "string" or #body > 8000 then return nil end
    local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
    return decoded and type(data) == "table" and data or nil
end

function WhiteAI:RecoverSavedIncidents()
    if _recovering then return false, "Recovery already in progress" end
    if not _running or not _config or not _config:Get("WhiteAIEnabled") then
        return false, "Enable Send to AI server first"
    end
    if _ownerSession == "" then return false, "Pair this device to recover private incidents" end
    local endpoint, epoch = _config:Get("WhiteAIEndpoint"), _epoch
    if not validEndpoint(endpoint) then return false, "Invalid endpoint" end
    _recovering = true
    task.spawn(function()
        local data = authRequest(endpoint, "/incidents", "GET", sessionHeaders(_ingestKey))
        if epoch ~= _epoch then return end
        _recovering = false
        if not data or type(data.incidents) ~= "table" then
            _lastStatus = "Recovery failed; check server/session and retry after cooldown."
            return
        end
        local resumed = 0
        for _, incident in ipairs(data.incidents) do
            local id = type(incident) == "table" and incident.job_id
            if type(id) == "string" and #id == 20 and id:match("^[0-9a-f]+$") and resumed < 3 then
                _lastJobId = _lastJobId or id
                resumed = resumed + 1
                task.spawn(watchJob, endpoint, _ingestKey, id, epoch)
            end
        end
        _lastStatus = "Recovered incidents: " .. tostring(resumed) .. "; retries are review-only."
    end)
    return true, "Recovering saved incidents..."
end

function WhiteAI:RetryLastJob()
    if not _running or not _config or not _config:Get("WhiteAIEnabled") then
        return false, "Enable Send to AI server first"
    end
    if _ownerSession == "" or not _lastJobId then return false, "Pair this device and recover an incident first" end
    local endpoint, epoch, id = _config:Get("WhiteAIEndpoint"), _epoch, _lastJobId
    if not validEndpoint(endpoint) or not id:match("^[0-9a-f]+$") or #id ~= 20 then return false, "Invalid job" end
    task.spawn(function()
        local data = authRequest(endpoint, "/jobs/" .. id .. "/retry", "POST", sessionHeaders(_ingestKey))
        if epoch ~= _epoch then return end
        if data then
            _lastStatus = "Analysis retry requested; review-only proposal."
            task.spawn(watchJob, endpoint, _ingestKey, id, epoch)
        else
            _lastStatus = "Retry not started; check cooldown, attempt limit, status and session."
        end
    end)
    return true, "Requesting analysis retry..."
end

function WhiteAI:PairDevice(masterKey)
    if _pairing then return false, "Pairing already in progress" end
    if type(masterKey) ~= "string" or #masterKey < 32 or #masterKey > 128 then
        return false, "Enter your private owner key to pair once"
    end
    local endpoint = _config and _config:Get("WhiteAIEndpoint")
    if not validEndpoint(endpoint) then return false, "Save an HTTPS /reports endpoint first" end
    _pairing = true
    local epoch = _epoch
    task.spawn(function()
        local data = authRequest(endpoint, "/auth/pair", "POST", {
            ["X-WhiteAI-Admin-Key"] = masterKey, ["Content-Type"] = "application/json" })
        masterKey = nil
        if epoch ~= _epoch then return end
        _pairing = false
        if _config:Get("WhiteAIEndpoint") ~= endpoint then return end
        if not data or type(data.session_token) ~= "string" or #data.session_token > 256
            or type(data.expires_at) ~= "number" or data.expires_at <= os.time() then
            _lastStatus = "Pairing failed; check owner key and backend settings"
            return
        end
        _ownerSession = data.session_token
        _sessionExpires = data.expires_at
        local saved = false
        if type(writefile) == "function" then
            saved = pcall(writefile, SESSION_FILE, HttpService:JSONEncode({
                endpoint = endpoint, token = _ownerSession, expires_at = _sessionExpires }))
        end
        _lastStatus = saved and "Device paired; session restored automatically on next start"
            or "Device paired in memory; local file storage unavailable"
        WhiteAI:FlushPending()
        WhiteAI:RecoverSavedIncidents()
    end)
    return true, "Pairing device..."
end

function WhiteAI:RecoverSession()
    if type(readfile) ~= "function" then return end
    local epoch = _epoch
    local endpoint = _config and _config:Get("WhiteAIEndpoint")
    if not validEndpoint(endpoint) then return end
    task.spawn(function()
        local ok, raw = pcall(readfile, SESSION_FILE)
        if not ok or type(raw) ~= "string" or #raw > 2000 then return end
        local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not decoded or type(data) ~= "table" or data.endpoint ~= endpoint
            or type(data.token) ~= "string" or #data.token > 256
            or type(data.expires_at) ~= "number" or data.expires_at <= os.time() then return end
        local result = authRequest(endpoint, "/auth/session", "GET", { ["X-WhiteAI-Session"] = data.token })
        if epoch ~= _epoch or _pairing or #_ownerSession > 0
            or _config:Get("WhiteAIEndpoint") ~= endpoint then return end
        if result and result.authenticated == true then
            _ownerSession = data.token
            _sessionExpires = data.expires_at
            _lastStatus = "Owner device session restored"
            WhiteAI:FlushPending()
            WhiteAI:RecoverSavedIncidents()
        else
            _lastStatus = "Could not restore session; retry or pair this device"
        end
    end)
end

function WhiteAI:SetEndpoint(url)
    if not validEndpoint(url) then return false, "HTTPS URL required" end
    if _config:Get("WhiteAIEndpoint") ~= url then
        _ownerSession = ""
        _sessionExpires = 0
    end
    _config:Set("WhiteAIEndpoint", url)
    self:RecoverSession()
    return true
end

function WhiteAI:SetIngestKey(token)
    if type(token) ~= "string" or #token < 12 or #token > 128 then
        return false, "Expected a 12-128 character ingestion key"
    end
    _ingestKey = token
    self:FlushPending()
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
    if enabled then
        self:FlushPending()
        if _ownerSession ~= "" then self:RecoverSavedIncidents() end
    end
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
    _watching, _recovering = {}, false
    local token = _epoch
    _questChangedAt = now()
    self:RecoverSession()
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
    _pendingAutoReports = {}
    _autoWorkerRunning = false
    _lastJobId = nil
    _proposalUrl = nil
    _jobHistory = {}
    _watching, _recovering = {}, false
    _ingestKey = ""
    _adminKey = ""
    _ownerSession = ""
    _sessionExpires = 0
    _pairing = false
end

return WhiteAI
