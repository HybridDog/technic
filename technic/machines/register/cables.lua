local S = technic.getter

local cable_tier = {}

function technic.is_tier_cable(name, tier)
	return cable_tier[name] == tier
end

function technic.get_cable_tier(name)
	return cable_tier[name]
end

local boxes = {}
local function get_nodebox(size)
	boxes[size] = boxes[size] or {
		type = "connected",
		fixed = {-size, -size, -size, size,  size, size},
		connect_top = {-size, -size, -size, size,  0.5,  size},
		connect_bottom = {-size, -0.5,  -size, size,  size, size},
		connect_front = {-size, -size, -0.5,  size,  size, size},
		connect_left = {-0.5,  -size, -size, size,  size, size},
		connect_back = {-size, -size,  size, size,  size, 0.5},
		connect_right = {-size, -size, -size, 0.5,   size, size},
	}
	return boxes[size]
end

function technic.register_cable(tier, size)
	local ltier = string.lower(tier)

	local nodename = "technic:"..ltier.."_cable"

	cable_tier[nodename] = tier

	local groups = {snappy=2, choppy=2, oddly_breakable_by_hand=2,
			["technic_"..ltier.."_cable"] = 1}
	local nodebox = get_nodebox(size)

	local function after_put(pos)
		technic.network.request_poll(pos, tier)
	end
	local function after_remove(pos)
		technic.network.disable_inactives(pos, tier)
	end

	minetest.register_node(nodename, {
		description = S("%s Cable"):format(tier),
		tiles = {"technic_"..ltier.."_cable.png"},
		inventory_image = "technic_"..ltier.."_cable_wield.png",
		wield_image = "technic_"..ltier.."_cable_wield.png",
		groups = groups,
		sounds = default.node_sound_wood_defaults(),
		paramtype = "light",
		sunlight_propagates = true,
		drawtype = "nodebox",
		node_box = nodebox,
		connects_to = {"group:technic_"..ltier.."_cable",
			"group:technic_"..ltier, "group:technic_all_tiers"},
		on_construct = after_put,
		on_destruct = after_remove,
	})

	local xyz = {
		["-x"] = 1,
		["-y"] = 2,
		["-z"] = 3,
		["x"] = 4,
		["y"] = 5,
		["z"] = 6,
	}
	local notconnects = {
		[1] = "left",
		[2] = "bottom",
		[3] = "front",
		[4] = "right",
		[5] = "top",
		[6] = "back",
	}
	local function s(p)
		if p:find("-") then
			return p:sub(2)
		else
			return "-"..p
		end
	end
	for p, i in pairs(xyz) do
		local def = {
			description = S("%s Cable Plate"):format(tier),
			tiles = {"technic_"..ltier.."_cable.png"},
			groups = table.copy(groups),
			sounds = default.node_sound_wood_defaults(),
			drop = "technic:"..ltier.."_cable_plate_1",
			paramtype = "light",
			sunlight_propagates = true,
			drawtype = "nodebox",
			node_box = table.copy(nodebox),
			connects_to = {"group:technic_"..ltier.."_cable",
				"group:technic_"..ltier, "group:technic_all_tiers"},
			on_construct = after_put,
			on_destruct = after_remove,
		}
		def.node_box.fixed = {
			{-size, -size, -size, size, size, size},
			{-0.5, -0.5, -0.5, 0.5, 0.5, 0.5}
		}
		def.node_box.fixed[1][xyz[p]] = 7/16 * (i-3.5)/math.abs(i-3.5)
		def.node_box.fixed[2][xyz[s(p)]] = 3/8 * (i-3.5)/math.abs(i-3.5)
		def.node_box["connect_"..notconnects[i]] = nil
		if i == 1 then
			def.on_place = function(itemstack, placer, pointed_thing)
				local pointed_thing_diff = vector.subtract(pointed_thing.above, pointed_thing.under)
				local num
				local changed
				for k, v in pairs(pointed_thing_diff) do
					if v ~= 0 then
						changed = k
						num = xyz[s(tostring(v):sub(-2, -2)..k)]
						break
					end
				end
				local crtl = placer:get_player_control()
				if (crtl.aux1 or crtl.sneak) and not (crtl.aux1 and crtl.sneak) then
					local fine_pointed = minetest.pointed_thing_to_face_pos(placer, pointed_thing)
					fine_pointed = vector.subtract(fine_pointed, pointed_thing.above)
					fine_pointed[changed] = nil
					local ps = {}
					for p, _ in pairs(fine_pointed) do
						ps[#ps+1] = p
					end
					local bigger = (math.abs(fine_pointed[ps[1]]) > math.abs(fine_pointed[ps[2]]) and ps[1]) or ps[2]
					if math.abs(fine_pointed[bigger]) < 0.3 then
						num = num + 3
						num = (num <= 6 and num) or num - 6
					else
						num = xyz[((fine_pointed[bigger] < 0 and "-") or "") .. bigger]
					end
				end
				minetest.set_node(pointed_thing.above, {name = "technic:"..ltier.."_cable_plate_"..num})
				if not (creative and creative.is_enabled_for(placer)) then
					itemstack:take_item()
				end
				return itemstack
			end
		else
			def.groups.not_in_creative_inventory = 1
		end
		def.on_rotate = function(pos, node, user, mode, new_param2)
			local dir = 0
			if mode == screwdriver.ROTATE_FACE then -- left-click
				dir = 1
			elseif mode == screwdriver.ROTATE_AXIS then -- right-click
				dir = -1
			end
			local num = tonumber(node.name:sub(-1))
			num = num + dir
			num = (num >= 1 and num) or num + 6
			num = (num <= 6 and num) or num - 6
			minetest.swap_node(pos, {name = "technic:"..ltier.."_cable_plate_"..num})
		end
		minetest.register_node("technic:"..ltier.."_cable_plate_"..i, def)
		cable_tier["technic:"..ltier.."_cable_plate_"..i] = tier
	end

	local c = "technic:"..ltier.."_cable"
	minetest.register_craft({
		output = "technic:"..ltier.."_cable_plate_1 5",
		recipe = {
			{"", "", c},
			{c , c , c},
			{"", "", c},
		}
	})

	minetest.register_craft({
		output = c,
		recipe = {
			{"technic:"..ltier.."_cable_plate_1"},
		}
	})
end
