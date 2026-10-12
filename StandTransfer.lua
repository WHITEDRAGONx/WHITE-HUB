-- DEV ONLY: one-use, non-secret transfer intent. Not an authorization token.
local HttpService = game:GetService("HttpService")
local Transfer = {}
local FILE = "WHITE_STAND_TRANSFER.json"
local MARKER = "WHITE_HUB_STAND_TRANSFER_V1"
local FIELDS = {id=true,created=true,expires=true,place=true,origin=true,destination=true,
    hops=true,maxHops=true,visited=true,mode=true,source=true,targets=true,skins=true,
    pityLimit=true,stand=true,pity=true,metrics=true}
local METRICS = {attempts=true,arrows=true,ribs=true,rokas=true,rolls=true,restocks=true,
    elapsed=true,startPity=true,lastStand=true,lastSkin=true}

local function integer(n, low, high)
    return type(n)=="number" and n==n and n>=low and n<=high and n%1==0
end
local function name(s, maximum)
    return type(s)=="string" and #s>0 and #s<=maximum and not s:find("%c")
end
local function list(value, maximum)
    if type(value)~="table" then return false end
    local count, seen = 0, {}
    for k,v in pairs(value) do
        count=count+1
        if not integer(k,1,#value) or not name(v,100) or seen[v] then return false end
        seen[v]=true
    end
    return count==#value and count<=maximum
end
local function queueFunction()
    return queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
end
local function marker(value)
    local service=game:GetService("TeleportService")
    if not service or type(service.GetTeleportSetting)~="function" or type(service.SetTeleportSetting)~="function" then return false end
    if value~=nil and not pcall(service.SetTeleportSetting,service,MARKER,value) then return false end
    return pcall(service.GetTeleportSetting,service,MARKER)
end
function Transfer:Init() end
function Transfer:Available()
    local service=game:GetService("TeleportService")
    return type(readfile)=="function" and type(writefile)=="function" and type(queueFunction())=="function"
        and service~=nil and type(service.GetTeleportSetting)=="function" and type(service.SetTeleportSetting)=="function"
end
function Transfer:Validate(value)
    if type(value)~="table" then return false end
    for k in pairs(value) do if not FIELDS[k] then return false end end
    local now=os.time()
    if not name(value.id,36) or #value.id~=36 or not value.id:match("^[%x%-]+$")
        or not integer(value.created,0,now+30) or not integer(value.expires,now+1,now+900)
        or value.expires-value.created>900 or not integer(value.place,1,1e15)
        or not name(value.origin,100) or not name(value.destination,100) or value.origin==value.destination
        or not integer(value.maxHops,1,5) or not integer(value.hops,1,value.maxHops)
        or not list(value.visited,5) or #value.visited~=value.hops
        or value.visited[#value.visited]~=value.origin then return false end
    for _,job in ipairs(value.visited) do if job==value.destination then return false end end
    if value.mode~="stand" and value.mode~="shiny" then return false end
    if value.source~="Mysterious Arrow" and value.source~="Rib Cage of The Saint's Corpse" then return false end
    if not list(value.targets,25) or not list(value.skins,25) or (value.mode=="stand" and #value.targets==0)
        or not integer(value.pityLimit,0,125) or not name(value.stand,100)
        or not integer(value.pity,0,10000) or type(value.metrics)~="table" then return false end
    for k,v in pairs(value.metrics) do
        if not METRICS[k] then return false end
        if k=="lastStand" or k=="lastSkin" then
            if type(v)~="string" or #v>100 or v:find("%c") then return false end
        elseif k=="elapsed" then
            if type(v)~="number" or v~=v or v<0 or v>1e9 then return false end
        elseif not integer(v,0,1e9) then return false end
    end
    for _,k in ipairs({"attempts","arrows","ribs","rokas","rolls","restocks","elapsed"}) do
        if type(value.metrics[k])~="number" then return false end
    end
    return true
end
function Transfer:Invalidate()
    local markerOk,value=marker("")
    if type(writefile)~="function" or type(readfile)~="function" then return false end
    local ok=pcall(writefile,FILE,"{}")
    local readOk,raw=pcall(readfile,FILE)
    return ok and readOk and raw=="{}" and markerOk and value==""
end
function Transfer:Read()
    if type(readfile)~="function" then return nil end
    local ok,raw=pcall(readfile,FILE)
    if not ok or type(raw)~="string" or #raw>10000 then return nil end
    local decoded,value=pcall(HttpService.JSONDecode,HttpService,raw)
    return decoded and self:Validate(value) and value or nil
end
function Transfer:Issue(record)
    if not self:Available() or not self:Validate(record) then return false end
    local ok,raw=pcall(HttpService.JSONEncode,HttpService,record)
    if not ok or #raw>10000 then return false end
    if not pcall(writefile,FILE,raw) then return false end
    local persisted=self:Read()
    if not persisted or persisted.id~=record.id then self:Invalidate(); return false end
    local markerOk,value=marker(record.id)
    if not markerOk or value~=record.id then self:Invalidate(); return false end
    -- Only our dev loader is queued. User strings/skin names are never code.
    local script=([[
local ok,s=pcall(readfile,%q); if not ok then return end
local d,r=pcall(function() return game:GetService('HttpService'):JSONDecode(s) end)
if not d or type(r)~='table' or r.id~=%q or r.destination~=game.JobId or r.place~=game.PlaceId or type(r.expires)~='number' or r.expires<=os.time() then return end
local markerOK,mark=pcall(function() return game:GetService('TeleportService'):GetTeleportSetting('WHITE_HUB_STAND_TRANSFER_V1') end); if not markerOK or mark~=r.id then return end
local source=game:HttpGet('https://raw.githubusercontent.com/WHITEDRAGONx/WHITE-HUB/dev/2026-10-10-autosell-compat/DevMain.lua')
local freshOk,freshText=pcall(readfile,%q); if not freshOk then return end
local decoded,fresh=pcall(function() return game:GetService('HttpService'):JSONDecode(freshText) end)
if not decoded or type(fresh)~='table' or fresh.id~=%q or fresh.destination~=game.JobId or fresh.place~=game.PlaceId or type(fresh.expires)~='number' or fresh.expires<=os.time() then return end
local stillOK,stillMark=pcall(function() return game:GetService('TeleportService'):GetTeleportSetting('WHITE_HUB_STAND_TRANSFER_V1') end); if not stillOK or stillMark~=fresh.id then return end
loadstring(source)()
]]):format(FILE,record.id,FILE,record.id)
    local queued,result=pcall(queueFunction(),script)
    queued=queued and result~=false
    if not queued then self:Invalidate() end
    return queued
end
function Transfer:Claim(place,job)
    local record=self:Read()
    local markerOk,value=marker()
    if not self:Invalidate() then return nil,"Transfer cannot be claimed once" end
    if not record or not markerOk or value~=record.id or record.place~=place or record.destination~=job or record.origin==job then
        return nil,"No valid arrival transfer"
    end
    return record
end
return Transfer
