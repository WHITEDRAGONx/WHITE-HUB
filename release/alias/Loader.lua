-- WHITE HUB permanent public entry point. Private development loader is excluded.
local url = "https://raw.githubusercontent.com/WHITEDRAGONx/WHITE-HUB-V3/main/Main.lua?whitehub=" .. tostring(os.time())
loadstring(game:HttpGet(url))()
