-- Minetest 0.4.7 mod: technic
-- namespace: technic
-- (c) 2012-2013 by RealBadAngel <mk@realbadangel.pl>

local load_start = os.clock()

technic = rawget(_G, "technic") or {}
technic.creative_mode = minetest.settings:get_bool("creative_mode")


local modpath = minetest.get_modpath("technic")
technic.modpath = modpath


-- Boilerplate to support intllib
if rawget(_G, "intllib") then
	technic.getter = intllib.Getter()
else
	technic.getter = function(s,a,...)if a==nil then return s end a={a,...}return s:gsub("(@?)@(%(?)(%d+)(%)?)",function(e,o,n,c)if e==""then return a[tonumber(n)]..(o==""and c or"")else return"@"..o..n..c end end) end
end
local S = technic.getter

-- Read configuration file
dofile(modpath.."/config.lua")

dofile(modpath.."/helpers.lua")
dofile(modpath.."/network.lua")

dofile(modpath.."/items.lua")
dofile(modpath.."/crafts.lua")
dofile(modpath.."/register.lua")
dofile(modpath.."/radiation.lua")
dofile(modpath.."/legacy.lua")
dofile(modpath.."/machines/init.lua")
dofile(modpath.."/tools/init.lua")

if minetest.settings:get_bool("log_mods") then
	print(S("[Technic] Loaded in %f seconds"):format(os.clock() - load_start))
end

