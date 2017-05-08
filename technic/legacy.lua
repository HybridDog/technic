
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

	local tech = {
		machine = true,
		tiers = {tier},
		machine_description = def.description,
	}
	if machine_type == technic.producer then
		tech.priorities = {run_prio, 1}
		tech.on_poll = function(net)
			local machine = net.machine
			if net.current_priority == run_prio then
				def.technic_run(machine.pos, machine.node, stage)
				machine.old_dtime = machine.dtime
				return
			end
			local meta = minetest.get_meta(machine.pos)
			local power = meta:get_int(net.tier .. "_EU_supply")
			power = power * math.max(machine.old_dtime, 1)
			net.power_disposable = net.power_disposable + power
			net.produced_power = net.power_disposable
			net.poll_interval = math.min(net.poll_interval, 72)
		end
		minetest.override_item(nodename, {technic = tech})
		return
	end
	if machine_type == technic.receiver then
		tech.machine = true
		tech.priorities = {25, 100}
		function tech.on_poll(net)
			local machine = net.machine
			if net.current_priority == prios.consumer_wait then
				local requested_power = minetest.get_meta(machine.pos):get_int(
					net.tier .. "_EU_demand")
				machine.requested_power = requested_power
				net.power_requested = net.power_requested + requested_power
				return
			end
			local power = machine.requested_power
			local meta = minetest.get_meta(machine.pos)
			if power < 0 then
				meta:set_string("infotext", "no power requested")
				return
			end
			if power > net.power_disposable then
				meta:set_string("infotext", "not enough power")
				return
			end
			def.technic_run(machine.pos, machine.node, stage)
			net.power_disposable = net.power_disposable - power
			net.consumed_power = net.consumed_power + power
		end
		minetest.override_item(nodename, {technic = tech})
		return
	end
	if machine_type == technic.battery then
		tech.machine = true
		tech.priorities = {run_prio, 50, 53, 125}
		function tech.on_poll(net)
			local machine = net.machine
			if net.current_priority == run_prio then
				machine.old_dtime = machine.dtime
				def.technic_run(machine.pos, machine.node, stage)
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
				machine.donated_power = 0
				local power_to_take = math.min(net.power_requested
					- net.power_disposable, machine.offered_power)
				if power_to_take > 0 then
					-- take power from the battery box
					local meta = minetest.get_meta(machine.pos)
					-- maybe wrong
					local power = meta:get_int(net.tier .. "_EU_input")
					meta:set_int(net.tier .. "_EU_input", power
						- power_to_take)
					net.batteryboxes_drain = net.batteryboxes_drain
						+ power_to_take
					net.power_disposable = net.power_disposable + power_to_take
					machine.donated_power = power_to_take
				end
				return
			end
			-- feed battery boxes with surplus
			local taken_power = 0
			if net.power_disposable > 0 then
				local meta = minetest.get_meta(machine.pos)
				taken_power = math.min(meta:get_int(
					net.tier .. "_EU_demand"), net.power_disposable)
				local oldpower = meta:get_int(net.tier .. "_EU_input")
				meta:set_int(net.tier .. "_EU_input", oldpower + taken_power)
				net.power_disposable = net.power_disposable - taken_power
				net.batteryboxes_fill = net.batteryboxes_fill + taken_power
			end
			-- show information
			local meta = minetest.get_meta(machine.pos)
			meta:set_string("infotext", tech.machine_description ..
				("BB %s"):format(technic.pretty_num(
				taken_power * machine.old_dtime)))
		end
		minetest.override_item(nodename, {technic = tech})
		return
	end
	error("unknown machine_type: " .. machine_type)
end
