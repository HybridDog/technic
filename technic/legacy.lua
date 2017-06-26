
-- Aliases to convert from legacy node/item names

technic.legacy_nodenames = {
	["technic:alloy_furnace"]        = "technic:lv_alloy_furnace",
	["technic:alloy_furnace_active"] = "technic:lv_alloy_furnace_active",
	["technic:battery_box"]  = "technic:lv_battery_box0",
	["technic:battery_box1"] = "technic:lv_battery_box1",
	["technic:battery_box2"] = "technic:lv_battery_box2",
	["technic:battery_box3"] = "technic:lv_battery_box3",
	["technic:battery_box4"] = "technic:lv_battery_box4",
	["technic:battery_box5"] = "technic:lv_battery_box5",
	["technic:battery_box6"] = "technic:lv_battery_box6",
	["technic:battery_box7"] = "technic:lv_battery_box7",
	["technic:battery_box8"] = "technic:lv_battery_box8",
	["technic:electric_furnace"]        = "technic:lv_electric_furnace",
	["technic:electric_furnace_active"] = "technic:lv_electric_furnace_active",
	["technic:grinder"]        = "technic:lv_grinder",
	["technic:grinder_active"] = "technic:lv_grinder_active",
	["technic:extractor"]        = "technic:lv_extractor",
	["technic:extractor_active"] = "technic:lv_extractor_active",
	["technic:compressor"]        = "technic:lv_compressor",
	["technic:compressor_active"] = "technic:lv_compressor_active",
	["technic:hv_battery_box"] = "technic:hv_battery_box0",
	["technic:mv_battery_box"] = "technic:mv_battery_box0",
	["technic:generator"]        = "technic:lv_generator",
	["technic:generator_active"] = "technic:lv_generator_active",
	["technic:iron_dust"] = "technic:wrought_iron_dust",
	["technic:enriched_uranium"] = "technic:uranium35_ingot",
}

for old, new in pairs(technic.legacy_nodenames) do
	minetest.register_alias(old, new)
end

for i = 0, 64 do
	minetest.register_alias("technic:hv_cable"..i, "technic:hv_cable")
	minetest.register_alias("technic:mv_cable"..i, "technic:mv_cable")
	minetest.register_alias("technic:lv_cable"..i, "technic:lv_cable")
end


------------------------- old machine handling ---------------------------------

local run_prio = 0.1
function technic.register_machine(tier, nodename, machine_type)
	minetest.log("deprecated",
		"[technic] technic.register_machine is deprecated now.")

	local def = minetest.registered_nodes[nodename]

	-- update the network when placing a node (todo: sides)
	local old_after_place = def.after_place_node or function()end
	local def_to_add = {
		after_place_node = function (pos, placer, itemstack, pt)
			local rv = old_after_place(pos, placer, itemstack, pt)
			technic.network.request_poll(pt.under, tier)
			return rv
		end
	}

	local tech = {
		machine = true,
		tiers = {tier},
		machine_description = def.description,
	}
	def_to_add.technic = tech

	-- call the technic_on_disable when the network was disabled
	if def.technic_on_disable then
		tech.disable = function(pos, node, machine)
			machine.meta:set_int(machine.current_tier .. "_EU_timeout", 0)
			def.technic_on_disable(pos, node)
		end
	end

	if machine_type == technic.producer then
		tech.priorities = {run_prio, 1}
		tech.on_poll = function(net)
			local machine = net.machine
			if net.current_priority == run_prio then
				def.technic_run(machine.pos, machine.node, net.tier)
				machine.old_dtime = machine.dtime
				return
			end
			local meta = minetest.get_meta(machine.pos)
			local power = meta:get_int(net.tier .. "_EU_supply")
			power = power * math.max(machine.old_dtime, 1)
			power = power * machine.old_dtime
			net.power_disposable = net.power_disposable + power
			net.produced_power = net.power_disposable
			net.poll_interval = math.min(net.poll_interval, 72)
		end
		minetest.override_item(nodename, def_to_add)
		return
	end
	if machine_type == technic.receiver then
		tech.machine = true
		tech.priorities = {25, 100}
		function tech.on_poll(net)
			local machine = net.machine
			if net.current_priority == 25 then
				local requested_power = minetest.get_meta(machine.pos):get_int(
					net.tier .. "_EU_demand")
				machine.requested_power = requested_power *
					machine.dtime
				net.power_requested = net.power_requested + requested_power
				return
			end
			local power = machine.requested_power
			if power < 0
			or power > net.power_disposable then
				power = 0
			end
			minetest.get_meta(machine.pos):set_int("HV_EU_input", power)
			def.technic_run(machine.pos, machine.node, net.tier)
			net.power_disposable = net.power_disposable - power
			net.consumed_power = net.consumed_power + power
		end
		minetest.override_item(nodename, def_to_add)
		return
	end
	if machine_type == technic.battery then
		tech.machine = true
		tech.priorities = {run_prio, 50, 53, 125}
		function tech.on_poll(net)
			local machine = net.machine
			if net.current_priority == run_prio then
				machine.old_dtime = machine.dtime
				def.technic_run(machine.pos, machine.node, net.tier)
				return
			end
			if net.current_priority == 50 then
				machine.offered_power = 0
				if net.power_requested > net.power_disposable then
					-- find out how much power the machine can donate
					machine.offered_power = math.min(machine.old_dtime, 1)
						* minetest.get_meta(machine.pos):get_int(net.tier ..
						"_EU_supply")
				end
				return
			end
			if net.current_priority == 53 then
				machine.delta = 0
				local power_to_take = math.min(net.power_requested
					- net.power_disposable, machine.offered_power)
				if power_to_take > 0 then
					-- take power from the battery box
					local meta = minetest.get_meta(machine.pos)
					local power = meta:get_int"internal_EU_charge"
					meta:set_int("internal_EU_charge", power
						- power_to_take)
					net.batteryboxes_drain = net.batteryboxes_drain
						+ power_to_take
					net.power_disposable = net.power_disposable + power_to_take
					machine.delta = -power_to_take
				end
				return
			end
			-- feed battery boxes with surplus
			if net.power_disposable > 0 then
				local meta = minetest.get_meta(machine.pos)
				power_to_box = math.min(meta:get_int(
					net.tier .. "_EU_demand"), net.power_disposable)
				meta:set_int(net.tier .. "_EU_input", power_to_box)
				net.power_disposable = net.power_disposable - power_to_box
				net.batteryboxes_fill = net.batteryboxes_fill + power_to_box
				machine.delta = machine.delta + power_to_box
			end
			-- show information
			local meta = minetest.get_meta(machine.pos)
			meta:set_string("infotext", tech.machine_description ..
				("\nstored: %s, loading: %s"):format(
				technic.pretty_num(meta:get_int"internal_EU_charge"),
				technic.pretty_num(machine.delta * machine.old_dtime)))
		end
		minetest.override_item(nodename, def_to_add)
		return
	end
	error("unknown machine_type: " .. machine_type)
end
