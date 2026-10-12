-- Public names-only Trello data. No downloaded code or credentials.
local Refresh={}
local modules,epoch,busy,names,state=nil,0,false,{},'fallback'
local TTL=21600
local BASE='https://api.trello.com/1/boards/ROfFdASc/'
local function checked(values)
 if type(values)~='table' or #values>1000 then return nil end
 local out,seen,count={},{},0
 for k,v in pairs(values) do
  count=count+1
  if type(k)~='number' or k%1~=0 or k<1 or k>#values or type(v)~='string' or v=='' or v=='None' or #v>100 or v:find('%c') then return nil end
 end
 if count~=#values then return nil end
 for _,name in ipairs(values) do if not seen[name] then seen[name]=true; out[#out+1]=name end end
 table.sort(out); return out
end
local function log(message)
 if modules and modules.RuntimeLog then pcall(modules.RuntimeLog.Write,modules.RuntimeLog,'INFO','GameCatalog',message) end
end
function Refresh:GetNames() local out={} for i,v in ipairs(names) do out[i]=v end; return out end
function Refresh:GetState() return state end
function Refresh:Destroy() epoch=epoch+1; modules=nil; state='stopped' end
function Refresh:Refresh()
 if busy or not modules then return false end
 busy=true; state='refreshing'; local token=epoch; local deadline=os.clock()+10
 local owner=modules
 local function alive() return token==epoch and modules==owner and os.clock()<deadline end
 local function read(path)
  if not alive() then error('cancelled') end
  local body=game:HttpGet(BASE..path)
  if not alive() or type(body)~='string' or #body>250000 then error('unavailable') end
  return game:GetService('HttpService'):JSONDecode(body)
 end
 task.delay(10,function() if token==epoch and busy then state='timeout'; log('Skin catalog refresh timed out; local/fixed names retained') end end)
 task.spawn(function()
  local ok,result=pcall(function()
   local lists=read('lists?fields=name'); local ids={}
   if type(lists)~='table' or #lists>128 then error('invalid lists') end
   for _,list in ipairs(lists) do
    if type(list)=='table' and type(list.name)=='string' and list.name:sub(1,12)=='Stand Skins:' and type(list.id)=='string' then ids[list.id]=true end
   end
   if next(ids)==nil then error('no skin lists') end
   local cards=read('cards?fields=name,idList&limit=1000'); local titles={}
   if type(cards)~='table' or #cards>1000 then error('invalid cards') end
   for _,card in ipairs(cards) do if type(card)=='table' and ids[card.idList] then titles[#titles+1]=card.name end end
   local clean=checked(titles); if not clean or #clean==0 then error('invalid names') end
   return clean
  end)
  busy=false
  if token~=epoch or modules~=owner then return end
  if ok and alive() then
   names=result; state='trello'
   if owner.Config then pcall(owner.Config.Set,owner.Config,'SkinCatalogCache',{schema=1,board='ROfFdASc',time=os.time(),names=names}) end
   log('Skin catalog updated automatically: '..tostring(#names)..' Trello names; obtainability/aliases not inferred')
  else state='offline'; log('Skin catalog online refresh unavailable; local/fixed names retained') end
 end)
 return true
end
function Refresh:Init(all)
 epoch=epoch+1; modules=all; names={}; state='fallback'
 local cache=all.Config and all.Config:Get('SkinCatalogCache')
 local clean=type(cache)=='table' and cache.schema==1 and cache.board=='ROfFdASc' and checked(cache.names)
 local fresh=clean and type(cache.time)=='number' and cache.time<=os.time()+60 and os.time()-cache.time<TTL
 if clean then names=clean; state='cache' end
 if not fresh then self:Refresh() end
 local token=epoch
 local function scheduled()
  if token~=epoch or not modules then return end
  self:Refresh(); task.delay(TTL,scheduled)
 end
 task.delay(TTL,scheduled)
end
return Refresh
