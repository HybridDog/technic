
local S = technic.getter

local get_sunlight
function technic.register_solar_array(data)
	local tier = data.tier
	local tech = {
		tiers = {tier},
		supply = function(dtime, _, node)
			local sunlight = get_sunlight(node.param1,
				minetest.get_timeofday())

			local supply_factor = 0

			-- produce power only if sufficient light
			if sunlight >= 12 then
				supply_factor = math.log(4 - sunlight / 4) / math.log(0.97265)
			end
			return data.power * supply_factor * dtime / 72
		end,
		machine_description = S"Arrayed Solar %s Generator":format(tier),
	}

	local ltier = tier:lower()
	minetest.register_node("technic:solar_array_"..ltier, {
		tiles = {"technic_"..ltier.."_solar_array_top.png",
			"technic_"..ltier.."_solar_array_bottom.png",
			"technic_"..ltier.."_solar_array_side.png"},
		sounds = default.node_sound_wood_defaults(),
		description = tech.machine_description,
		drawtype = "nodebox",
		paramtype = "light",
		node_box = {
			type = "fixed",
			fixed = {-0.5, -0.5, -0.5, 0.5, 0, 0.5},
		},
		groups = {snappy=2, choppy=2, oddly_breakable_by_hand=2,
			["technic_"..ltier]=1},
		connect_sides = {"bottom"},
		technic = tech,
	})

	technic.register_machine(tier, "technic:solar_array_"..ltier, technic.producer)
end


-- from daynightratio.h:23
local dnrvalues = {
	{4250+125, 150},
	{4500+125, 150},
	{4750+125, 250},
	{5000+125, 350},
	{5250+125, 500},
	{5500+125, 675},
	{5750+125, 875},
	{6000+125, 1000},
	{6250+125, 1000},
}
local function time_to_daynight_ratio(tod)
	tod = tod*24000
	if tod > 12000 then
		tod = 24000 - tod
	end
	for i = 1,#dnrvalues do
		if values[i][1] > tod then
			if i == 1 then
				return values[1][2]
			end
			local td0 = values[i][1] - values[i-1][1]
			local f = (tod - values[i-1][1]) / td0
			return f * values[i][2] + (1.0 - f) * values[i-1][2]
		end
	end
	return 1000
end

-- from light.h:119
function get_sunlight(param1, tod)
	local sunlight_factor = time_to_daynight_ratio(tod)
	local sunlight = param1 % 16
	return math.min(math.floor(sunlight_factor * sunlight / 1000), 15)
end
