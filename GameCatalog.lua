-- BEGIN OnlineCatalog
local OnlineCatalog = (function()
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

end)()
-- END OnlineCatalog

-- Facts-only Trello titles + owner-authorized Xenon name fallback, 2026-10-12.
-- No remote code, module require, HTTP at runtime or objective inference.
local Catalog={}
local skinNames={
 "..|.....|..|.",
 "ARHCP",
 "Aang",
 "Aang WR",
 "Ace",
 "Ace MR",
 "Action-Figure Platinum",
 "Actually Red Hot Chili Pepper",
 "Aero OH",
 "Aerosleigh",
 "Aerosmith Over Heaven",
 "All-Starsnake",
 "Alternate",
 "Anime WR",
 "Anti Umbral",
 "Anti-Umbral",
 "Arlong",
 "Arlong TW",
 "Arlong TWOH",
 "Astral Enigma",
 "Asuna",
 "BIBLICALY ACCURATE GE",
 "BLADE OF EXILE",
 "Baseball Platinum",
 "Bell Pepper",
 "Bell Pepper AU",
 "Bell Peppers",
 "Biblically Accurate Experience",
 "Bites The Ice",
 "Blade Of The Exile",
 "Blade of The Exile",
 "Bloodthirster",
 "Bloodthirster Anubis",
 "Bondrewd",
 "Booette",
 "Booette STW",
 "Bubblegum Diver Down",
 "Buggy D. Clown",
 "CHROMO TH",
 "CURSED AEROSMITH",
 "Candy Cane World",
 "Casull",
 "Charged Creeper Queen",
 "Charmy Green",
 "Chopper",
 "Chromo",
 "Chromo Hando",
 "Comic Venom",
 "Comic Venom Spider-Man",
 "Cornsake",
 "Cornsnake",
 "Cracked WORLD",
 "Cracked World",
 "Crazy Idol",
 "Crazy Idol Requiem",
 "Crazy Overseer",
 "Crazy Overseer CD",
 "Crazy Ruby",
 "Crazy Sapphire Requiem",
 "Cream Nog",
 "Creeper Queen",
 "Crimson Mist",
 "Cthulhu",
 "Cursed Aero Platinum",
 "Cursed Areosmith",
 "D4She",
 "DARK DETERMINATION TUSK",
 "DEVIL'S MOON",
 "DIGITAL SPTW",
 "Dark Determination",
 "Dead Experience",
 "Deadeye Drifter",
 "Deep Sea Diver",
 "Deimos Crimson",
 "Deimos Queen",
 "Deimos Snake",
 "Devil MIH",
 "Devil Moon",
 "Devil Pepper",
 "Devil Snake",
 "Devil4C",
 "Devil4c",
 "Diamondhead",
 "Digital Platinum",
 "Digital Star Platinum",
 "Diva Down",
 "Doing Well",
 "Doodelbop",
 "Doodle Bop",
 "DoodleBop",
 "ELDRITCH HG",
 "Eldritch Green",
 "Eldritch Hierophant",
 "Elf Pistol",
 "Elf Pistols",
 "Elizabeth Liones",
 "Elucidator & Dark Repulser",
 "Emperor",
 "Emperor OVA",
 "FEMALE HANDO",
 "FESTIVE PLATINUM",
 "FESTIVE SPTW",
 "FESTIVE THE WORLD",
 "FROSTBITE",
 "Female Hando",
 "Female The Hand",
 "Festive Free",
 "Festive Platinum",
 "Festive Platinum SPTW",
 "Festive Star Platinum",
 "Festive TWOH",
 "Festive World",
 "Forged By Hell",
 "Forged in Hell",
 "Frost HG",
 "FrostBite",
 "Frostbite KQ",
 "Frostbite KQ BTD",
 "Frozone",
 "Fused Zamasu",
 "Ghost Chariot",
 "Ghost Chariot Requiem",
 "Ghost Face",
 "Ghost TWOH",
 "Ghost The World",
 "Ghost World",
 "Ghost World TWOH",
 "Ghostface",
 "Ghostface SCR",
 "Gilded Diamond",
 "Glacier Trackstar",
 "Glock - 18 | Fade",
 "Glock-18",
 "Glock-18 Fade",
 "Go/Jo",
 "Goku Black",
 "Goku Black KCR",
 "Gold & Wet",
 "Gold Platinum",
 "Golden & Wet",
 "Golden Freiza",
 "Golden Frieza",
 "Golden Retribution",
 "Grim Reaper",
 "Grim Reaper KCR",
 "HEAVEN'S ACT 4",
 "HORSEMAN OF HEAVEN",
 "Haunted Jack-O-Platinum",
 "Haunted Jack-O-Platinum: The World",
 "Headhunter",
 "Heaven ACT 4",
 "Heaven Act 4",
 "Heaven Spirit",
 "Hexed Spirit Requiem",
 "Hidden Leaf Hero",
 "Hidden Leaf Hero LOVE TRAIN",
 "Hierophant Frost",
 "Holiday Tangle",
 "Holly's Sickness",
 "Horseman of Heaven",
 "Horsemen Of Heaven",
 "Ice Cold Chili Pepper",
 "Ice Cold Chili Pepper AU",
 "Ice Cold Chili Peppers",
 "Ice Cold Peppers",
 "Jack-O-Platinum",
 "Jack-O-Platinum SPTW",
 "Jack-o-Platinum",
 "Jacko SP",
 "Jacko SPTW",
 "Jade Peace",
 "Jade Serenity",
 "Jaguar Platinum",
 "Jester Crimson",
 "Joe Poopoo",
 "Joe Priduhh",
 "Joe's Poop",
 "Joe's Pride",
 "KING OF THE END (KCR)",
 "KING PEPPERMINT",
 "Kanshou & Bakuya",
 "Kars",
 "Kars Hair",
 "Kars Har",
 "Kars' hair",
 "Kikoku",
 "Killer Queen BTI",
 "Killer Queen: Bites The Ice",
 "Killer Queen: Bites the Ice",
 "Killer Reveal",
 "Killua",
 "Killua CPAU",
 "King Crampus",
 "King Krampus",
 "King Peppermint",
 "King of The End",
 "Korra",
 "Korra WR",
 "Krampus KCR",
 "LIGHTBRINGER",
 "LORD BOROS",
 "Light Bringer",
 "Linked Sword",
 "Linked Sword Anubis",
 "Lord Boros",
 "Lord Boros GER",
 "Luffy Gear 4",
 "Luffy Platinum",
 "MADE IN CHRISTMAS FUTURE",
 "MCU Spider-Man",
 "MIRAGE OF PHANTOMS",
 "MR JOESTAR",
 "Made in Christmas Future",
 "Made in Christmas Future MIH",
 "Made in Pibble",
 "Magellan",
 "Magician's Red Over Heaven",
 "Magician's Red: Over Heaven",
 "Magicians Red Over Heaven",
 "Manga Crimson",
 "Manga Diver Down",
 "Manga WR",
 "Manga/Anime WR",
 "Mecha Diamond",
 "Megumin",
 "Mermaid",
 "Merry",
 "Merry & Sweet",
 "Mintsnake",
 "Mirage Of Phantoms TWOH",
 "Mirage of Phantoms",
 "Misaka",
 "Misaka Mikoto",
 "Molted Chariot",
 "Moon of Christmas Present",
 "Mr Juke's Angel",
 "Mr Jukes Angel",
 "Mr Jukes Angels",
 "Mr Pekin",
 "Mr Tentacle",
 "Mr. Joestar",
 "Mr. Jukes Angels",
 "Mr. Pekin",
 "Mr. Tentacles",
 "Ms. Aerosmith",
 "Muffet",
 "NEON ASCENSION CD",
 "Nah I'd Win",
 "Nah Id Win",
 "Nah, I'd Lose",
 "Nah, I'd Stabilize",
 "Nah, I'd Win",
 "Nautilodaunt",
 "Neco Arc",
 "Neo WORLD",
 "Neo World",
 "Neon Ascension",
 "Neon Ascension Diamond",
 "Nerf Jolt",
 "Nocturne",
 "Nonosama Bo",
 "Noob TWOH",
 "ODM Gear",
 "ONE ABOVE ALL",
 "OVA Chariot",
 "OVA Chariot SCR",
 "OVA Emperor",
 "OVA Platinum",
 "OVA Silver Chariot",
 "OVA The World",
 "Old President",
 "One Above All",
 "Overseer CD",
 "PUMPKIN PATCH STONE FREE",
 "Peppermint KCR",
 "Pinky Fingers",
 "Polar President",
 "Pumpkin Patch",
 "Pumpkin Patch SF",
 "Pyro",
 "Pyro MR",
 "Queen Crimson",
 "RETRO THE WORLD: OVER HEAVEN",
 "Retro Scary Monsters",
 "Retro TWOH",
 "Retro The World Over Heaven",
 "Reverse Monsters",
 "Risotto",
 "Risotto Hairs",
 "Risotto's Hair",
 "Rock Unleashed",
 "Rogue Ninja",
 "SCP 049",
 "SCP 049 KQ:BTD",
 "SCP 2521",
 "SCP-049",
 "SCP-049 BTD",
 "SCP-2521",
 "SMTWAU",
 "SOCP MIH",
 "SPTW V2",
 "STW Alternate",
 "SUMO PLATINUM",
 "Sailor",
 "Sailor GB",
 "Sailor S&W",
 "Sakara",
 "Sakura",
 "Sasageyo",
 "Scarlet Queen",
 "Scary Monsters Retro The World",
 "Scary Monsters TWAU",
 "Scary Monsters: Retro The World",
 "Scary Monsters: The World",
 "Scary Monsters: The World Alternate Universe",
 "Shadow Killer Queen",
 "Shadow TW",
 "Shadow TWOH",
 "Shadow The Waifu",
 "Shadow The World",
 "Shadow The World OH",
 "Shadow The World STW",
 "Shadow The World: Alternate",
 "Shadow World",
 "Shadow World STW",
 "Shadow World TWOH",
 "Shanks",
 "Shanks SCR",
 "Sheared Snow Golem",
 "Sheared Snow Golem MR",
 "Shining Ruby",
 "Snake of Christmas Past",
 "Snow Golem",
 "Snow Golem MR",
 "Soft & Starry",
 "Soft and Starry",
 "Sorcerer's Ember",
 "Sorcerer's Red",
 "Spearmint Chariot",
 "Spider-Man",
 "Spirit Bomb Sword",
 "Spunch Bop",
 "SpunchBop",
 "SpunchBop GB",
 "Star Platinum OVA",
 "Star Platinum Stone Ocean",
 "Star Platinum: Stone Ocean",
 "Star Striped Eagle",
 "Star Striped Eagle MR",
 "Star Waifu",
 "Star Waifu: The World",
 "Stone Platinum",
 "Stormy",
 "Stormy WR",
 "Sukuna",
 "Sumo Platinum",
 "Sumo Platinum SPTW",
 "Sumo Platinum: SPTW",
 "Sumo SPTW",
 "Sumo TWOH",
 "Sumo The World",
 "Sumo World",
 "Sweet",
 "TAKOIZU DRAGON",
 "THE WAIFU ALTERNATE UNIVERSE",
 "THE WAIFU V1",
 "TOMB CRYPT TUSK",
 "TRAIN TO HELL",
 "TWAU Over Heaven",
 "TWAU:OH",
 "TWGH:OH",
 "Takoizu Dragon BB",
 "Tentacle Black",
 "Tentacle Purple",
 "Tentacle Yellow",
 "Thanos",
 "Thanos TH",
 "The Big Nut",
 "The Bunny Devil",
 "The Control Devil",
 "The Gifter",
 "The Grinch",
 "The Grinch C-MOON",
 "The Grinch CMOON",
 "The Grinch MIH",
 "The Noob",
 "The Noob Over Heaven",
 "The Nutcracker",
 "The Other Hand",
 "The Plague Doctor",
 "The Waifu",
 "The Waifu Alternate Universe",
 "The Waifu Over Heaven",
 "The Waifu TWOH",
 "The Waifu V2 OH",
 "The Waifu v2",
 "The Waifu: Alternate Universe",
 "The World 2",
 "The World OVA",
 "The World Ultimate",
 "The World Under Hell",
 "The World's Greatest High",
 "The World's Greatest High OH",
 "The World: Greatest High",
 "The World: Ultimate",
 "Tomb Crypt",
 "Tomb Crypt Tusk",
 "Toy Sticky Fingers",
 "Train To Hell",
 "Triangle Guard",
 "Triangle Guard D4C",
 "Triangle Guard D4C LT",
 "Triangle Guard LT",
 "Tsunade",
 "Tsunate",
 "Tusk Dark Determination",
 "Tyrant Crimson",
 "Tyrant Crimson KC",
 "Tyrant Crimson KCR",
 "Tyrant KC",
 "Tyrant KCR",
 "Tākoizu Dragon",
 "Uber Spy",
 "Undead Flare",
 "Undead Hand",
 "Vanilla Ice Cream",
 "Vela Nova",
 "Venom",
 "Vexus Crimson",
 "Vexus KC",
 "Vexus KCR",
 "Vinegar Crimson",
 "Virus Vessel",
 "Volcanic Diamond",
 "Volcanic Spirit Requiem",
 "WISPY CHARIOT",
 "Warhammer Titan",
 "Warhammer Titan WA",
 "Weather Reporter",
 "WeatherSnake",
 "Weathersnake",
 "Wendigo",
 "Whisper",
 "Yuji Itadori",
 "Yuji Itadori SF",
 "Yuki Cmoon",
 "Yuki MIH",
 "Yuki Tsukumo",
 "Yuki Tsukumo C-Moon",
 "Yuki Tsukumo Cmoon",
 "Yuki Tsukumo MIH",
 "Zenitsu",
 "Zenitsu CPAU",
 "Zenitzu",
 "Zeus (GOW)",
 "Zeus (OP)",
 "Zeus GOW",
 "Zeus God of War",
 "Zeus OP",
 "Zeus One Piece",
 "●●|●●●●●|●●|●",
}
local questNames={
 "Abbacchio's Partner",
 "Bruno Bucciarati #10",
 "Bruno Bucciarati #16",
 "Bruno Bucciarati #4.",
 "DIO (Quest)",
 "Darius, The Executioner [Cooldown]",
 "Deputy Bertrude",
 "Doppio",
 "Dracula",
 "Enrico Pucci (Diver Down)",
 "Enrico Pucci (Heaven's Plan)",
 "Enya The Hag",
 "Giorno Giovanna #1.",
 "Giorno Giovanna #17 (Final)",
 "Giorno Giovanna #3.",
 "Giorno Giovanna #5",
 "Guido Mista #14-15",
 "Guido Mista #7.",
 "Heaven's Plan Questline",
 "Homeless Man Jill",
 "Jesus",
 "Jotaro",
 "Jotaro Kujo (Weather Report)",
 "Kars",
 "Koichi Hirose #2.",
 "Leone Abbacchio #9",
 "Narancia Ghirga #8.",
 "Officer Sam",
 "Pannacotta Fugo #6.",
 "Prestige Master Rin (SBR Version)",
 "Suno The Arrowsmith",
 "The Arrowsmith (Crazy Diamond Requiem)",
 "Trish Una #11-13",
 "Will Anthonio Zeppeli",
}
local function valid(name)
 return type(name)=='string' and name~='' and name~='None' and #name<=100 and not name:find('%c')
end
local modules=nil
Catalog.Online=OnlineCatalog
function Catalog:Init(all) modules=all; OnlineCatalog:Init(all) end
function Catalog:Destroy() OnlineCatalog:Destroy(); modules=nil end
function Catalog:Names(values,selected)
 local out,seen={},{}
 for _,list in ipairs({values or {},selected or {}}) do
  if type(list)=='table' then
   for _,name in ipairs(list) do
    if valid(name) and not seen[name] then seen[name]=true; out[#out+1]=name end
   end
  end
 end
 table.sort(out); return out
end
local function children(root,limit,visit)
 if not root or type(root.GetChildren)~='function' then return end
 local ok,nodes=pcall(root.GetChildren,root)
 if not ok or type(nodes)~='table' then return end
 for i,node in ipairs(nodes) do if i>limit then break end; visit(node) end
end
local function child(root,name)
 if not root or type(root.FindFirstChild)~='function' then return nil end
 local ok,value=pcall(root.FindFirstChild,root,name); return ok and value or nil
end
function Catalog:GetSkins(saved)
 local names=self:Names(skinNames,saved)
 if modules then names=self:Names(names,OnlineCatalog:GetNames()) end
 if modules and modules.StandFarm then
  local ok,value=pcall(modules.StandFarm.GetStatus,modules.StandFarm)
  if ok and value and value.metrics and valid(value.metrics.lastSkin) then names[#names+1]=value.metrics.lastSkin end
 end
 local ok,rs=pcall(function() return game:GetService('ReplicatedStorage') end)
 if ok then
  local budget=256
  for _,parent in ipairs({rs,child(rs,'Objects') or false,child(rs,'Models') or false,child(rs,'Assets') or false}) do
   for _,key in ipairs({'StandSkins','Skins','Shinys','SkinModels','SkinData','SkinNames'}) do
    children(child(parent,key),128,function(node)
     if budget<=0 then return end; budget=budget-1
     if node:IsA('Folder') then
      children(node,64,function(leaf)
       if budget<=0 then return end; budget=budget-1
       local value=leaf.Name
       if leaf:IsA('StringValue') then local ok,v=pcall(function() return leaf.Value end); if ok and valid(v) then value=v end end
       if valid(value) then names[#names+1]=value end
      end)
     else
      local value=node.Name
      if node:IsA('StringValue') then local ok,v=pcall(function() return node.Value end); if ok and valid(v) then value=v end end
      if valid(value) then names[#names+1]=value end
     end
    end)
   end
  end
 end
 return self:Names(names)
end
function Catalog:GetQuests(supported)
 local options=self:Names(supported); local known={}
 for _,name in ipairs(options) do known[name]=true end
 local extras={}
 local function inspect(node)
  local name=node.Name
  if valid(name) and (name:lower():find('lvl',1,true) or name:find('Storyline#',1,true)) then extras[#extras+1]=name end
 end
 local ok,rs=pcall(function() return game:GetService('ReplicatedStorage') end)
 if ok then children(child(rs,'NewDialogue'),128,inspect) end
 children(child(workspace,'Dialogues'),128,inspect)
 if #extras==0 then for _,name in ipairs(questNames) do extras[#extras+1]=name end end
 for _,name in ipairs(self:Names(extras)) do if not known[name] then options[#options+1]='INFO | '..name end end
 return options
end
function Catalog:IsInfo(name) return type(name)=='string' and name:sub(1,7)=='INFO | ' end
return Catalog
