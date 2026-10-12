-- Facts-only snapshot of public YBA Trello titles, fetched 2026-10-12.
-- No remote code, module require, HTTP at runtime or objective inference.
local Catalog={}
local skinNames={
 "Aang",
 "Ace",
 "Action-Figure Platinum",
 "Actually Red Hot Chili Pepper",
 "Aerosleigh",
 "Aerosmith Over Heaven",
 "All-Starsnake",
 "Anime WR",
 "Anti Umbral",
 "Arlong",
 "Astral Enigma",
 "Asuna",
 "Baseball Platinum",
 "Bell Pepper",
 "Biblically Accurate Experience",
 "Blade of The Exile",
 "Bloodthirster",
 "Bondrewd",
 "Booette",
 "Bubblegum Diver Down",
 "Buggy D. Clown",
 "Candy Cane World",
 "Casull",
 "Charged Creeper Queen",
 "Charmy Green",
 "Chopper",
 "Chromo Hando",
 "Comic Venom Spider-Man",
 "Cornsnake",
 "Cracked WORLD",
 "Crazy Idol",
 "Crazy Idol Requiem",
 "Crazy Overseer",
 "Crazy Sapphire Requiem",
 "Cream Nog",
 "Creeper Queen",
 "Crimson Mist",
 "Cthulhu",
 "Cursed Aero Platinum",
 "D4She",
 "Dead Experience",
 "Deadeye Drifter",
 "Deep Sea Diver",
 "Deimos Crimson",
 "Deimos Queen",
 "Deimos Snake",
 "Devil Moon",
 "Devil Pepper",
 "Devil4C",
 "Diamondhead",
 "Digital Star Platinum",
 "Diva Down",
 "Doodle Bop",
 "Eldritch Green",
 "Elf Pistol",
 "Elizabeth Liones",
 "Elucidator & Dark Repulser",
 "Emperor",
 "Female Hando",
 "Festive Free",
 "Festive Platinum",
 "Festive World",
 "Forged By Hell",
 "FrostBite",
 "Frozone",
 "Fused Zamasu",
 "Ghost Chariot Requiem",
 "Ghost World",
 "Ghostface",
 "Gilded Diamond",
 "Glacier Trackstar",
 "Glock - 18 | Fade",
 "Glock-18",
 "Go/Jo",
 "Goku Black",
 "Gold Platinum",
 "Golden & Wet",
 "Golden Frieza",
 "Golden Retribution",
 "Grim Reaper",
 "Haunted Jack-O-Platinum",
 "Headhunter",
 "Heaven ACT 4",
 "Heaven Spirit",
 "Hexed Spirit Requiem",
 "Hidden Leaf Hero",
 "Hierophant Frost",
 "Holiday Tangle",
 "Holly's Sickness",
 "Horseman of Heaven",
 "Ice Cold Chili Pepper",
 "Jack-o-Platinum",
 "Jade Peace",
 "Jade Serenity",
 "Jester Crimson",
 "Joe's Pride",
 "Kanshou & Bakuya",
 "Kikoku",
 "Killer Queen: Bites the Ice",
 "Killer Reveal",
 "Killua",
 "King Crampus",
 "King Peppermint",
 "King of The End",
 "Korra",
 "Light Bringer",
 "Linked Sword",
 "Lord Boros",
 "Luffy Gear 4",
 "MCU Spider-Man",
 "Made in Christmas Future",
 "Made in Pibble",
 "Magellan",
 "Magician's Red Over Heaven",
 "Manga Crimson",
 "Manga Diver Down",
 "Manga WR",
 "Mecha Diamond",
 "Megumin",
 "Mermaid",
 "Merry & Sweet",
 "Mintsnake",
 "Mirage of Phantoms",
 "Misaka Mikoto",
 "Molted Chariot",
 "Moon of Christmas Present",
 "Mr Jukes Angels",
 "Mr. Joestar",
 "Mr. Pekin",
 "Mr. Tentacles",
 "Ms. Aerosmith",
 "Muffet",
 "Nah I'd Win",
 "Nautilodaunt",
 "Neco Arc",
 "Neo WORLD",
 "Neon Ascension Diamond",
 "Nerf Jolt",
 "Nocturne",
 "Nonosama Bo",
 "OVA Emperor",
 "OVA Platinum",
 "OVA Silver Chariot",
 "OVA The World",
 "Old President",
 "One Above All",
 "Pinky Fingers",
 "Polar President",
 "Pumpkin Patch",
 "Pyro",
 "Retro The World Over Heaven",
 "Reverse Monsters",
 "Rock Unleashed",
 "Rogue Ninja",
 "SCP-049",
 "STW Alternate",
 "Sailor S&W",
 "Sakara",
 "Sasageyo",
 "Scarlet Queen",
 "Scary Monsters: Retro The World",
 "Scary Monsters: The World",
 "Scary Monsters: The World Alternate Universe",
 "Shadow Killer Queen",
 "Shadow The Waifu",
 "Shadow The World",
 "Shanks",
 "Sheared Snow Golem",
 "Shining Ruby",
 "Snake of Christmas Past",
 "Snow Golem",
 "Soft & Starry",
 "Sorcerer's Red",
 "Spearmint Chariot",
 "Spirit Bomb Sword",
 "Spunch Bop",
 "Star Platinum: Stone Ocean",
 "Star Striped Eagle",
 "Star Waifu",
 "Star Waifu: The World",
 "Stone Platinum",
 "Stormy",
 "Sukuna",
 "Sumo Platinum",
 "Sumo World",
 "TWAU Over Heaven",
 "Tentacle Black",
 "Tentacle Purple",
 "Tentacle Yellow",
 "Thanos",
 "The Bunny Devil",
 "The Control Devil",
 "The Gifter",
 "The Grinch",
 "The Noob Over Heaven",
 "The Nutcracker",
 "The Other Hand",
 "The Plague Doctor",
 "The Waifu",
 "The Waifu Alternate Universe",
 "The Waifu Over Heaven",
 "The Waifu v2",
 "The World 2",
 "The World Under Hell",
 "The World's Greatest High",
 "The World: Ultimate",
 "Tomb Crypt Tusk",
 "Toy Sticky Fingers",
 "Train To Hell",
 "Triangle Guard",
 "Tsunate",
 "Tusk Dark Determination",
 "Tyrant Crimson",
 "Tākoizu Dragon",
 "Uber Spy",
 "Undead Flare",
 "Undead Hand",
 "Vanilla Ice Cream",
 "Vela Nova",
 "Venom",
 "Vexus Crimson",
 "Vinegar Crimson",
 "Virus Vessel",
 "Volcanic Diamond",
 "Volcanic Spirit Requiem",
 "Warhammer Titan",
 "Weather Reporter",
 "Weathersnake",
 "Wendigo",
 "Whisper",
 "Yuji Itadori",
 "Yuki Tsukumo",
 "Zenitsu",
 "Zeus (GOW)",
 "Zeus (OP)",
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
function Catalog:Init() end
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
 local ok,rs=pcall(function() return game:GetService('ReplicatedStorage') end)
 if ok then
  local budget=256
  for _,parent in ipairs({rs,child(rs,'Objects') or false}) do
   for _,key in ipairs({'StandSkins','Skins','Shinys'}) do
    children(child(parent,key),128,function(node)
     if budget<=0 then return end; budget=budget-1
     if node:IsA('Folder') then
      children(node,64,function(leaf)
       if budget<=0 then return end; budget=budget-1
       if valid(leaf.Name) then names[#names+1]=leaf.Name end
      end)
     elseif valid(node.Name) then names[#names+1]=node.Name end
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
 for _,name in ipairs(questNames) do extras[#extras+1]=name end
 local function inspect(node)
  local name=node.Name
  if valid(name) and (name:lower():find('lvl',1,true) or name:find('Storyline#',1,true)) then extras[#extras+1]=name end
 end
 local ok,rs=pcall(function() return game:GetService('ReplicatedStorage') end)
 if ok then children(child(rs,'NewDialogue'),128,inspect) end
 children(child(workspace,'Dialogues'),128,inspect)
 for _,name in ipairs(self:Names(extras)) do if not known[name] then options[#options+1]='INFO | '..name end end
 return options
end
function Catalog:IsInfo(name) return type(name)=='string' and name:sub(1,7)=='INFO | ' end
return Catalog
