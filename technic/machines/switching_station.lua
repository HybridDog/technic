-- See also technic/doc/api.md

local S = technic.getter

local cable_entry = "^technic_cable_connection_overlay.png"

minetest.register_craft({
	output = "technic:switching_station",
	recipe = {
		{"",                     "technic:lv_transformer", ""},
		{"default:copper_ingot", "technic:machine_casing", "default:copper_ingot"},
		{"technic:lv_cable",     "technic:lv_cable",       "technic:lv_cable"}
	}
})

local on_switching_update
minetest.register_node("technic:switching_station",{
	description = S"Switching Station",
	tiles = {
		"technic_water_mill_top_active.png",
		"technic_water_mill_top_active.png" .. cable_entry,
		"technic_water_mill_top_active.png"
	},
	groups = {snappy=2, choppy=2, oddly_breakable_by_hand=2, technic_all_tiers=1},
	connect_sides = {"bottom"},
	sounds = default.node_sound_wood_defaults(),
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S"Switching Station")
		meta:set_string("channel", "switching_station" ..
			minetest.pos_to_string(pos))
		meta:set_string("formspec", "field[channel;Channel;${channel}]")
		on_switching_update(pos)
	end,
	on_timer = function(pos)
		on_switching_update(pos)
	end,
	technic = {
		activates_network = true,
		do_poll = function(pos, machines)
			on_switching_update(pos, machines)
		end,
	},
	after_destruct = function(pos)
		pos.y = pos.y-1
		local tier = technic.get_cable_tier(minetest.get_node(pos).name)
		technic.network.disable_inactives(pos, tier)
	end,
	on_receive_fields = function(pos, _, fields, sender)
		if not fields.channel then
			return
		end
		local plname = sender:get_player_name()
		if minetest.is_protected(pos, plname) then
			minetest.record_protection_violation(pos, plname)
			return
		end
		minetest.get_meta(pos):set_string("channel", fields.channel)
	end,
	mesecons = mesecon and {effector = {
		rules = mesecon.rules.default,
	}},
	digiline = {
		receptor = {action = function() end},
		effector = {
			action = function(pos, _, channel, msg)
				if msg:lower() ~= "get" then
					return
				end
				local meta = minetest.get_meta(pos)
				if channel ~= meta:get_string"channel" then
					return
				end
				digilines.receptor_send(pos, digilines.rules.default, channel, {
					supply = meta:get_int"supply",
					demand = meta:get_int"demand"
				})
			end
		},
	},
})

-----------------------------------------------
-- The action code for the switching station --
-----------------------------------------------

-- called for the switching station updates
function on_switching_update(pos, machines)
	local nodetimer = minetest.get_node_timer(pos)
	local meta = minetest.get_meta(pos)
	local gametime = minetest.get_gametime()
	local least_gametime = meta:get_int"technic_next_polling"
	if least_gametime == 0 then
		-- first poll
		least_gametime = gametime
	end
	if gametime < least_gametime
	and not machines then
		-- timer attacked too early
		nodetimer:start(least_gametime - gametime)
	minetest.chat_send_all("too early:  timeout: " .. nodetimer:get_timeout() .. "gt:" .. gametime)
		return true
	end
	local net = technic.network.init({x=pos.x, y=pos.y-1, z=pos.z}, gametime)
	net.machines = machines
	if technic.network.poll(net) then
		meta:set_string("infotext", -- todo time, batteryboxdrain/fill
			S"%s. Supply: %s Demand: %s":format(
			"SS", technic.pretty_num(net.produced_power),
			technic.pretty_num(net.consumed_power)))
	else
		meta:set_string("infotext", S"Couldn't get network")
	end
	--~ local next_gametime = least_gametime + net.poll_interval
	local time_speed = minetest.settings:get"time_speed"
	local next_gametime = gametime + net.poll_interval / time_speed
	meta:set_int("technic_next_polling", next_gametime)
	nodetimer:start(net.poll_interval / time_speed)
	minetest.chat_send_all("Polled, now interval: " .. net.poll_interval .. " timeout: " .. nodetimer:get_timeout())
	return true
end

--Re-enable disabled switching station if necessary
minetest.register_abm({
	label = "Machines: re-enable check",
	nodenames = {"technic:switching_station"},
	interval = 10,
	chance = 1,
	catch_up = false,
	action = function(pos)
		if not minetest.get_node_timer(pos):is_started() then
			on_switching_update(pos)
		end
	end,
})
