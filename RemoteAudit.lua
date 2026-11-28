-- WHITE HUB RemoteAudit
-- Passive diagnostics for remotes used/discovered by WHITE HUB.
-- No __namecall hooks, hookfunction patches, remote blocking or code execution.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteAudit = {}
RemoteAudit.Build = "REMOTE-AUDIT-20261128-R1"
RemoteAudit._records = {}
RemoteAudit._catalog = {}
RemoteAudit._connections = {}
RemoteAudit._runtimeLog = nil
RemoteAudit._enabled = true
RemoteAudit._running = false
RemoteAudit._maxRecords = 180

local function clockText()
    local ok, value = pcall(function()
        return os.date("%H:%M:%S")
    end)
    return ok and tostring(value) or string.format("%.2f", os.clock())
end

local function safePath(instance)
    local ok, path = pcall(function()
        return instance:GetFullName()
    end)
    return ok and tostring(path) or tostring(instance)
end

local function safeToString(value)
    local ok, result = pcall(tostring, value)
    return ok and tostring(result) or "<tostring failed>"
end

local function summarizeValue(value, depth, seen)
    local valueType = typeof(value)
    if value == nil then return "nil" end

    if valueType == "Instance" then
        local className = "Instance"
        pcall(function() className = value.ClassName end)
        return "<" .. tostring(className) .. "> " .. safePath(value)
    end

    if type(value) == "string" then
        local text = value:gsub("[%c]", " ")
        if #text > 120 then text = text:sub(1, 117) .. "..." end
        return string.format("%q", text)
    end

    if type(value) == "number" or type(value) == "boolean" then
        return safeToString(value)
    end

    if type(value) == "table" then
        depth = depth or 0
        seen = seen or {}
        if seen[value] then return "{<cycle>}" end
        if depth >= 2 then return "{...}" end

        seen[value] = true
        local parts = {}
        local count = 0
        for key, item in pairs(value) do
            count = count + 1
            if count > 8 then
                parts[#parts + 1] = "..."
                break
            end
            local keyText = type(key) == "string" and key or safeToString(key)
            if #keyText > 40 then keyText = keyText:sub(1, 37) .. "..." end
            parts[#parts + 1] = tostring(keyText) .. "=" .. summarizeValue(item, depth + 1, seen)
        end
        seen[value] = nil
        return "{" .. table.concat(parts, ", ") .. "}"
    end

    return safeToString(valueType) .. "(" .. safeToString(value) .. ")"
end

local function summarizeArgs(args)
    local parts = {}
    local amount = math.min(tonumber(args.n) or #args, 10)
    for index = 1, amount do
        parts[#parts + 1] = "[" .. tostring(index) .. "]=" .. summarizeValue(args[index], 0, {})
    end
    if (tonumber(args.n) or #args) > amount then
        parts[#parts + 1] = "..."
    end
    return table.concat(parts, ", ")
end

function RemoteAudit:_write(level, moduleName, message)
    local logger = self._runtimeLog
    if logger and type(logger.Write) == "function" then
        pcall(logger.Write, logger, level or "INFO", moduleName or "RemoteAudit", message)
    end
end

function RemoteAudit:_remember(instance)
    if not instance or typeof(instance) ~= "Instance" then return end
    local valid = false
    pcall(function()
        valid = instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction")
    end)
    if not valid then return end

    local className = "Remote"
    pcall(function() className = instance.ClassName end)
    local path = safePath(instance)
    local existed = self._catalog[path] ~= nil
    self._catalog[path] = {
        Path = path,
        Class = tostring(className),
        Name = tostring(instance.Name),
    }
    if not existed then
        self._discovered = (self._discovered or 0) + 1
    end
end

function RemoteAudit:_watchRoot(root)
    if not root or typeof(root) ~= "Instance" then return end
    local ok, connection = pcall(function()
        return root.DescendantAdded:Connect(function(instance)
            if self._running then self:_remember(instance) end
        end)
    end)
    if ok and connection then
        self._connections[#self._connections + 1] = connection
    end
end

function RemoteAudit:Scan()
    if not self._running then return {Events = 0, Functions = 0, Total = 0} end

    self._catalog = {}
    local player = Players.LocalPlayer
    local roots = {
        ReplicatedStorage,
        workspace:FindFirstChild("Dialogues"),
        player and player.Character,
    }
    local scanned = 0
    for _, root in ipairs(roots) do
        if root then
            local descendants = {}
            local ok = pcall(function()
                descendants = root:GetDescendants()
            end)
            if ok then
                local limit = math.min(#descendants, 10000)
                for index = 1, limit do
                    scanned = scanned + 1
                    self:_remember(descendants[index])
                end
            end
            self:_remember(root)
        end
    end

    local stats = {Events = 0, Functions = 0, Total = 0, Scanned = scanned}
    for _, entry in pairs(self._catalog) do
        stats.Total = stats.Total + 1
        if entry.Class == "RemoteEvent" then
            stats.Events = stats.Events + 1
        elseif entry.Class == "RemoteFunction" then
            stats.Functions = stats.Functions + 1
        end
    end
    self._lastScanStats = stats
    self._lastScanAt = os.clock()
    return stats
end

function RemoteAudit:_append(record, signature, logToRuntime)
    local now = os.clock()
    local previous = self._records[#self._records]
    if previous and previous.Signature == signature and now - (previous.LastAt or 0) <= 1.25 then
        previous.Count = (previous.Count or 1) + 1
        previous.LastAt = now
        previous.Status = record.Status or previous.Status
        previous.Return = record.Return or previous.Return
        if logToRuntime and previous.Count % 20 == 0 then
            self:_write("INFO", record.Module, "[RemoteAudit] " .. record.Kind
                .. " repeated " .. tostring(previous.Count) .. "x | " .. tostring(record.Detail))
        end
        return previous
    end

    record.Time = clockText()
    record.FirstAt = now
    record.LastAt = now
    record.Count = 1
    record.Signature = signature
    table.insert(self._records, record)
    while #self._records > self._maxRecords do
        table.remove(self._records, 1)
    end

    if logToRuntime then
        self:_write("INFO", record.Module, "[RemoteAudit] " .. record.Kind
            .. " | " .. tostring(record.Detail) .. " | status=" .. tostring(record.Status))
    end
    return record
end

function RemoteAudit:Stage(moduleName, stageName, details)
    if not self._enabled then return false end
    moduleName = tostring(moduleName or "General")
    stageName = tostring(stageName or "STAGE")
    local detailText = type(details) == "table"
        and summarizeValue(details, 0, {})
        or tostring(details or "")
    local signature = "STAGE|" .. moduleName .. "|" .. stageName .. "|" .. detailText
    self:_append({
        Kind = "STAGE",
        Module = moduleName,
        Method = "-",
        Remote = "-",
        Args = "-",
        Status = "OBSERVED",
        Detail = stageName .. " " .. detailText,
    }, signature, true)
    return true
end

function RemoteAudit:_recordCall(moduleName, method, remote, args, status, returnText, errorText)
    if not self._enabled then return end
    local path = safePath(remote)
    local argText = summarizeArgs(args)
    local detail = tostring(method) .. " " .. path .. " args={" .. argText .. "}"
    local firstArg = args[1]
    local highVolume = moduleName == "CombatFarm"
        and ((firstArg == "Attack") or (firstArg == "InputBegan"))
    local signature = table.concat({moduleName, method, path, argText}, "|")
    self:_append({
        Kind = "CALL",
        Module = tostring(moduleName or "General"),
        Method = tostring(method),
        Remote = path,
        Args = argText,
        Status = tostring(status),
        Return = returnText and tostring(returnText) or nil,
        Error = errorText and tostring(errorText) or nil,
        Detail = detail,
    }, signature, not highVolume)
end

function RemoteAudit:Fire(moduleName, remote, ...)
    if not remote then error("RemoteAudit received a nil RemoteEvent", 2) end
    if not self._enabled or typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
        return remote:FireServer(...)
    end

    local args = table.pack(...)
    local result = table.pack(pcall(function()
        return remote:FireServer(table.unpack(args, 1, args.n))
    end))
    if result[1] then
        self:_recordCall(moduleName, "FireServer", remote, args, "LOCAL_CALL_OK")
    else
        self:_recordCall(moduleName, "FireServer", remote, args, "LOCAL_CALL_ERROR", nil, result[2])
        error(result[2], 0)
    end
    -- FireServer is one-way: LOCAL_CALL_OK means the local call returned
    -- without throwing; it is not proof that the server accepted the action.
    return nil
end

function RemoteAudit:Invoke(moduleName, remote, ...)
    if not remote then error("RemoteAudit received a nil RemoteFunction", 2) end
    if not self._enabled or typeof(remote) ~= "Instance" or not remote:IsA("RemoteFunction") then
        return remote:InvokeServer(...)
    end

    local args = table.pack(...)
    local result = table.pack(pcall(function()
        return remote:InvokeServer(table.unpack(args, 1, args.n))
    end))
    if result[1] then
        local returnText = summarizeArgs({n = result.n - 1, table.unpack(result, 2, result.n)})
        self:_recordCall(moduleName, "InvokeServer", remote, args, "RETURNED", returnText)
        return table.unpack(result, 2, result.n)
    end

    self:_recordCall(moduleName, "InvokeServer", remote, args, "INVOKE_ERROR", nil, result[2])
    error(result[2], 0)
end

function RemoteAudit:GetRecords(limit)
    local output = {}
    local startAt = math.max(1, #self._records - (tonumber(limit) or 100) + 1)
    for index = startAt, #self._records do
        local source = self._records[index]
        output[#output + 1] = {
            Time = source.Time,
            Kind = source.Kind,
            Module = source.Module,
            Method = source.Method,
            Remote = source.Remote,
            Args = source.Args,
            Status = source.Status,
            Return = source.Return,
            Error = source.Error,
            Detail = source.Detail,
            Count = source.Count,
        }
    end
    return output
end

function RemoteAudit:GetRemoteMapText()
    local entries = {}
    for _, entry in pairs(self._catalog) do
        entries[#entries + 1] = entry
    end
    table.sort(entries, function(a, b) return a.Path < b.Path end)

    local lines = {
        "REMOTE MAP",
        "----------------------------------------",
        "Discovered remotes: " .. tostring(#entries),
    }
    for index = 1, math.min(#entries, 120) do
        local entry = entries[index]
        lines[#lines + 1] = ("[%s] %s"):format(entry.Class, entry.Path)
    end
    if #entries > 120 then
        lines[#lines + 1] = "... " .. tostring(#entries - 120) .. " more omitted"
    end
    return table.concat(lines, "\n")
end

function RemoteAudit:GetReport()
    local stats = self:Scan()
    local records = self:GetRecords(100)
    local lines = {
        "WHITE HUB V5 - REMOTE / STAGE AUDIT",
        "========================================",
        "Build: " .. tostring(self.Build),
        "Runtime ID: " .. tostring(self._runtimeLog and self._runtimeLog.RuntimeId or "unknown"),
        "PlaceId: " .. tostring(game.PlaceId),
        "JobId: " .. tostring(game.JobId),
        "Capture: " .. (self._enabled and "ON" or "OFF"),
        ("Map: %d events | %d functions | %d total | %d objects scanned"):format(
            stats.Events or 0, stats.Functions or 0, stats.Total or 0, stats.Scanned or 0
        ),
        "",
        self:GetRemoteMapText(),
        "",
        "RECENT CALLS / STAGES (last " .. tostring(#records) .. ")",
        "----------------------------------------",
        "LOCAL_CALL_OK confirms only that FireServer returned locally, not server acceptance.",
    }

    for _, record in ipairs(records) do
        local repeatText = (record.Count or 1) > 1 and (" x" .. tostring(record.Count)) or ""
        lines[#lines + 1] = ("[%s] [%s] [%s] [%s] %s%s"):format(
            tostring(record.Time or "?"),
            tostring(record.Kind or "?"),
            tostring(record.Module or "?"),
            tostring(record.Status or "?"),
            tostring(record.Detail or record.Remote or ""),
            repeatText
        )
        if record.Return then lines[#lines + 1] = "    RETURN: " .. tostring(record.Return) end
        if record.Error then lines[#lines + 1] = "    ERROR: " .. tostring(record.Error) end
    end
    return table.concat(lines, "\n")
end

function RemoteAudit:SetEnabled(value)
    self._enabled = value == true
    self:_write("INFO", "RemoteAudit", "Capture " .. (self._enabled and "enabled" or "disabled"))
    return self._enabled
end

function RemoteAudit:Init(Modules)
    self._runtimeLog = Modules and Modules.RuntimeLog
    self._records = {}
    self._catalog = {}
    self._connections = {}
    self._running = true
    self._enabled = true
    self.Build = "REMOTE-AUDIT-20261128-R1"

    self:_watchRoot(ReplicatedStorage)
    local dialogueRoot = workspace:FindFirstChild("Dialogues")
    if dialogueRoot then self:_watchRoot(dialogueRoot) end

    local player = Players.LocalPlayer
    if player then
        local function watchCharacter(character)
            if character then
                self:_watchRoot(character)
                task.defer(function()
                    if self._running then self:Scan() end
                end)
            end
        end
        if player.Character then watchCharacter(player.Character) end
        self._connections[#self._connections + 1] = player.CharacterAdded:Connect(watchCharacter)
    end

    self._connections[#self._connections + 1] = workspace.ChildAdded:Connect(function(child)
        if child.Name == "Dialogues" then
            self:_watchRoot(child)
            self:Scan()
        end
    end)

    local stats = self:Scan()
    self:_write("INFO", "RemoteAudit", self.Build .. " online; passive map ready: "
        .. tostring(stats.Events) .. " RemoteEvents, "
        .. tostring(stats.Functions) .. " RemoteFunctions. Global hooks are disabled.")
end

function RemoteAudit:Destroy()
    self._running = false
    for _, connection in ipairs(self._connections) do
        pcall(function() connection:Disconnect() end)
    end
    self._connections = {}
    self:_write("INFO", "RemoteAudit", "Stopped and disconnected.")
end

return RemoteAudit
