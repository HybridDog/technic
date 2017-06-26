-- The supply converter is a generic device which can convert from
-- LV to MV and back, and HV to MV and back.
-- The machine is configured by the wiring below and above it.
--
-- It works like this:
--   The top side is setup as the receiver side, the bottom as the producer side.
--   Once the receiver side is powered it will deliver power to the other side.

local digilines_path = minetest.get_modpath("digilines")

local S = technic.getter

local transfer_amount = 10000
local transfer_efficiency = 0.9
local transfer_per_second = {
	LV = 5000 / 72,
	MV = 8000 / 72,
	HV = 12000 / 72
}

local cable_entry = "^technic_cable_connection_overlay.png"

local function set_supply_converter_formspec(meta)
	local formspec = "size[5,2.25]"..
		"field[0.3,0.5;2,1;power;"..S("Input Power")..";"..meta:get_int("power").."]"
	if digilines_path then
		formspec = formspec..
			"field[2.3,0.5;3,1;channel;Digiline Channel;"..meta:get_string("channel").."]"
	end
	-- The names for these toggle buttons are explicit about which
	-- state they'll switch to, so that multiple presses (arising
	-- from the ambiguity between lag and a missed press) only make
	-- the single change that the user expects.
	if meta:get_int("mesecon_mode") == 0 then
		formspec = formspec.."button[0,1;5,1;mesecon_mode_1;"..S("Ignoring Mesecon Signal").."]"
	else
		formspec = formspec.."button[0,1;5,1;mesecon_mode_0;"..S("Controlled by Mesecon Signal").."]"
	end
	if meta:get_int("enabled") == 0 then
		formspec = formspec.."button[0,1.75;5,1;enable;"..S("%s Disabled"):format(S("Supply Converter")).."]"
	else
		formspec = formspec.."button[0,1.75;5,1;disable;"..S("%s Enabled"):format(S("Supply Converter")).."]"
	end
	meta:set_string("formspec", formspec)
end

local supply_converter_receive_fields = function(pos, formname, fields, sender)
	local meta = minetest.get_meta(pos)
	local power = nil
	if fields.power then
		power = tonumber(fields.power) or 0
		power = math.max(power, 0)
		power = math.min(power, 10000)
		power = 100 * math.floor(power / 100)
		if power == meta:get_int("power") then power = nil end
	end
	if power then meta:set_int("power", power) end
	if fields.channel then meta:set_string("channel", fields.channel) end
	if fields.enable  then meta:set_int("enabled", 1) end
	if fields.disable then meta:set_int("enabled", 0) end
	if fields.mesecon_mode_0 then meta:set_int("mesecon_mode", 0) end
	if fields.mesecon_mode_1 then meta:set_int("mesecon_mode", 1) end
	set_supply_converter_formspec(meta)
end

local mesecons = {
	effector = {
		action_on = function(pos, node)
			minetest.get_meta(pos):set_int("mesecon_effect", 1)
		end,
		action_off = function(pos, node)
			minetest.get_meta(pos):set_int("mesecon_effect", 0)
		end
	}
}


local digiline_def = {
	receptor = {action = function() end},
	effector = {
		action = function(pos, node, channel, msg)
			local meta = minetest.get_meta(pos)
			if channel ~= meta:get_string("channel") then
				return
			end
			msg = msg:lower()
			if msg == "get" then
				digilines.receptor_send(pos, digilines.rules.default, channel, {
					enabled      = meta:get_int("enabled"),
					power        = meta:get_int("power"),
					mesecon_mode = meta:get_int("mesecon_mode")
				})
				return
			elseif msg == "off" then
				meta:set_int("enabled", 0)
			elseif msg == "on" then
				meta:set_int("enabled", 1)
			elseif msg == "toggle" then
				local onn = meta:get_int("enabled")
				onn = -(onn-1) -- Mirror onn with pivot 0.5, so switch between 1 and 0.
				meta:set_int("enabled", onn)
			elseif msg:sub(1, 5) == "power" then
				local power = tonumber(msg:sub(7))
				if not power then
					return
				end
				power = math.max(power, 0)
				power = math.min(power, 10000)
				power = 100 * math.floor(power / 100)
				meta:set_int("power", power)
			elseif msg:sub(1, 12) == "mesecon_mode" then
				meta:set_int("mesecon_mode", tonumber(msg:sub(14)))
			end
			set_supply_converter_formspec(meta)
		end
	},
}

local function collect_power(net)
	local pos = net.machine.pos
	if technic.get_cable_tier(minetest.get_node
			{x=pos.x, y=pos.y+1, z=pos.z}.name) ~= net.current_tier then
		return
	end
	-- collect the stored power only if there's abundance
	local meta = net.machine.meta
	local collected_power = tonumber(meta:get_string"collected_power") or 0
	local collectable = math.min(net.power_disposable,
		transfer_amount - collected_power)
	if collectable == 0 then
		-- the network needs the power itself or the SC is filled
		return
	end
	-- take the power and request a soon update
	meta:set_string("collected_power", collect_power + collectable)
	net.power_disposable = net.power_disposable - collectable
	net.poll_interval = math.min(net.poll_interval, 72)
end

local function donate_power(net)
	local pos = net.machine.pos
	local meta = net.machine.meta
	if technic.get_cable_tier(minetest.get_node
			{x=pos.x, y=pos.y-1, z=pos.z}.name) ~= net.current_tier then
		meta:set_string("infotext",
			S"%s has no Network":format"Supply Converter")
		return
	end
	-- donate the stored power only if needed
	local to_eject = (net.power_disposable - net.power_requested)
		/ transfer_efficiency
	if to_eject <= 0 then
		meta:set_string("infotext", S"Target network has enough power")
		return
	end
	local collected_power = tonumber(meta:get_string"collected_power") or 0
	local will_eject = math.min(math.min(to_eject, collected_power),
		transfer_per_second[net.current_tier])
	if will_eject == 0 then
		meta:set_string("infotext", S"No power collected")
		return
	end
	-- donate the power and then request an interval to avoid overfilling the SC
	meta:set_string("collected_power", collected_power - will_eject)
	net.power_disposable = net.power_disposable
		+ will_eject * transfer_efficiency
	net.poll_interval = math.min(net.poll_interval, 72)
	meta:set_string("infotext", S"%s -> %s: %s -> %s":format(
		technic.get_cable_tier(minetest.get_node
			{x=pos.x, y=pos.y+1, z=pos.z}.name),
		net.current_tier,
		technic.EU_string(will_eject),
		technic.EU_string(will_eject * transfer_efficiency))
	)
end

minetest.register_node("technic:supply_converter", {
	description = S("Supply Converter"),
	tiles  = {
		"technic_supply_converter_tb.png"..cable_entry,
		"technic_supply_converter_tb.png"..cable_entry,
		"technic_supply_converter_side.png",
		"technic_supply_converter_side.png",
		"technic_supply_converter_side.png",
		"technic_supply_converter_side.png"
		},
	groups = {snappy=2, choppy=2, oddly_breakable_by_hand=2,
		technic_machine=1, technic_all_tiers=1},
	connect_sides = {"top", "bottom"},
	sounds = default.node_sound_wood_defaults(),
	on_receive_fields = supply_converter_receive_fields,
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Supply Converter"))
		if digilines_path then
			meta:set_string("channel", "supply_converter"..minetest.pos_to_string(pos))
		end
		meta:set_int("mesecon_mode", 0)
		meta:set_int("mesecon_effect", 0)
		set_supply_converter_formspec(meta)
	end,
	technic = {
		machine_description = "Supply Converter",
		tiers = {"LV", "MV", "HV"},
		priorities = {33, 200},
		machine = true,
		on_poll = function(net)
			if net.current_priority == 33 then
				donate_power(net)
			else
				collect_power(net)
			end
		end
	},
	mesecons = mesecons,
	digiline = digiline_def,
	--~ technic_run = run,
	--~ technic_on_disable = run,
})

minetest.register_craft({
	output = "technic:supply_converter",
	recipe = {
		{"technic:fine_gold_wire", "technic:rubber", "technic:doped_silicon_wafer"},
		{"technic:mv_transformer", "technic:machine_casing", "technic:lv_transformer"},
		{"technic:mv_cable",       "technic:rubber",         "technic:lv_cable"},
	}
})
