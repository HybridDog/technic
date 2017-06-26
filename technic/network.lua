
------------------------- Cache etc. stuff -------------------------------------

local S = technic.getter

local function force_get_node(pos)
	return technic.get_or_load_node(pos) or minetest.get_node(pos)
end

local poshash = minetest.hash_node_position

-- cache minetest.get_node results
local known_nodes
local function clean_cache()
	known_nodes = {}
	setmetatable(known_nodes, {__mode = "kv"})
end
clean_cache()

--~ local function remove_node(pos)
	--~ known_nodes[poshash(pos)] = {name="air", param2=0}
	--~ minetest.remove_node(pos)
	--~ minetest.check_for_falling(pos)
--~ end

local function get_node(pos)
	local vi = poshash(pos)
	local node = known_nodes[vi]
	if node then
		return node
	end
	node = force_get_node(pos)
	known_nodes[vi] = node
	return node
end


------------------------- Network -------------------------------------

-- tests whether the node is a technic machine
local function is_machine(name, tier)
	local def = minetest.registered_nodes[name]
	if not def.technic
	or not def.technic.machine then
		return false
	end
	for i = 1,#def.technic.tiers do
		if def.technic.tiers[i] == tier then
			return true
		end
	end
	return false
end

-- tests whether the node is a switching station
local function is_poller(name)
	local def = minetest.registered_nodes[name]
	return def.technic
		and def.technic.activates_network
end

-- walks the cable and finds the machines
local touchps = {
	{x=1, y=0, z=0}, {x=-1, y=0, z=0},
	{x=0, y=0, z=1}, {x=0, y=0, z=-1},
	{x=0, y=1, z=0}, {x=0, y=-1, z=0}
}
-- needs test
local touchnames_inv = {right=2, left=1, back=4, front=2, top=6, bottom=5}
local function scan_net(pos, tier)
	local machines = {}
	local pollers = {}
	local founds_h = {} -- > 1 cable required
	local todo = {pos}
	local sp = 1
	while sp > 0 do
		local p = todo[sp]
		sp = sp-1
		for oi = 1,6 do
			local p = vector.add(p, touchps[oi])
			local h = poshash(p)
			if not founds_h[h] then
				local node = get_node(p)
				if technic.is_tier_cable(node.name, tier) then
					founds_h[h] = 1
					sp = sp+1
					todo[sp] = p
				else
					local machin = is_machine(node.name, tier)
					local SS = is_poller(node.name)
					if machin
					or SS then
						local def = minetest.registered_nodes[node.name]
						local connect_sides = def.connect_sides
						local connected = not connect_sides
						if not connected then
							for i = 1,#connect_sides do
								if touchnames_inv[connect_sides[i]] == oi then
									connected = true
									break
								end
							end
						end
						if connected then
							if SS then
								-- some switching station
								pollers[#pollers+1] = {
									pos = p,
									node = node,
									def = def
								}
								founds_h[h] = 3
							else
								founds_h[h] = 2
								machines[#machines+1] = {
									pos = p,
									node = node,
									def = def
								}
							end
						end
					else
						founds_h[h] = 0
					end
				end
			end
		end
	end
	return machines, pollers
end

technic.network = {}

-- disables machines, e.g. after digging a cable
function technic.network.disable_inactives(pos, tier)
print"inactives search (6x scan)"
	for i = 1,6 do
		local p = vector.add(pos, touchps[i])
		local machines, pollers = scan_net(p, tier)
		if not next(pollers) then
			-- disable machines if some are enabled
			for i = 1,#machines do
				local machine = machines[i]
				local pos = machine.pos
				local meta = minetest.get_meta(pos)
				if meta:get_int"technic_previous_poll" == 0 then
					-- one disabled machine means all are disabled
					break
				end
				meta:set_int("technic_previous_poll", 0)
				meta:set_string("infotext", S"No network")
				if machine.def.technic.disable then
					-- TODO: machine shouldn't get these
					machine.meta = meta
					machine.current_tier = tier
					machine.def.technic.disable(pos, machine.node, machine)
				end
			end
		end
	end
print"inactives search done"
end

-- updates the net e.g. when connecting it with another one
function technic.network.request_poll(pos, tier)
print"polling requested, 1x scan"
	local machines, pollers = scan_net(pos, tier)
	for i = 1,#pollers do
		pollers[i].def.technic.do_poll(pollers[i].pos, machines)
	end
end

-- returns the dtime for a machine
local function touch_machine(meta, net)
	local previous_time = meta:get_string"technic_previous_poll"
	meta:set_string("technic_previous_poll", "")
	local dtime = 0  -- in case of first poll
	if previous_time ~= "" then
		local sp = previous_time:find" "
		local gametimediff = net.current_gametime
			- tonumber(previous_time:sub(1, sp-1))
		dtime = (net.current_ustime - tonumber(previous_time:sub(sp+1)))
			/ 1000000
		-- select gametime if ustime is not reliable,
		-- e.g. after rejoining
		if math.floor(dtime) ~= gametimediff then
			dtime = gametimediff
		end
	end
	meta:set_string("technic_previous_poll",
		net.current_gametime .. " " .. net.current_ustime)
	return dtime * net.time_speed
end

local function table_contains(t, v)
	for i = 1,#t do
		if t[i] == v then
			return true
		end
	end
	return false
end

-- updates the network
function technic.network.poll(net)
	local pos = net.startpos
	local tier = technic.get_cable_tier(get_node(pos).name)
	if not tier then
		return false
	end
	if not net.machines then
		net.machines = scan_net(pos, tier)
	end
	local machines = net.machines
	net.tier = tier
	net.current_priority = -1
	-- a heap could be used here
	while true do
		-- find the next bigger priority
		local next_priority = math.huge
		for i = 1,#machines do
			local data = machines[i].def.technic
			for i = 1,#data.priorities do
				local prio = data.priorities[i]
				if prio > net.current_priority
				and prio < next_priority then
					next_priority = prio
				end
			end
		end
		-- abort after finding the smallest priority
		if next_priority == math.huge then
			break
		end
		net.current_priority = next_priority
		-- call the machines' functions
		for i = 1,#machines do
			local machine = machines[i]
			local data = machine.def.technic
			if table_contains(data.priorities, net.current_priority) then
				machine.meta = machine.meta or minetest.get_meta(machine.pos)
				machine.dtime = touch_machine(machine.meta, net)
				net.machine = machine
				data.on_poll(net)
			end
		end
	end
	clean_cache()
	return true
end

-- intializes a network table
function technic.network.init(net)
	net.power_disposable = 0  -- the power which can be consumed
	net.power_batteries = 0
	net.power_requested = 0
	net.counts = {}
	net.poll_interval = 72  -- 1 second with default time speed
	net.produced_power = 0
	net.consumed_power = 0  -- this has been consumed up to now
	net.batteryboxes_drain = 0  -- battery
	net.batteryboxes_fill = 0
end

-- used to find the battery box count for even power distribution
--~ local function count_nodes_remaining(net, nodename)
	--~ if net.counts[nodename] then
		--~ net.counts[nodename] = net.counts[nodename]-1
		--~ return net.counts[nodename]
	--~ end
	--~ local cnt = 0
	--~ for i = 1,#net.machines do
		--~ if net.machines[i].node.name == nodename then
			--~ cnt = cnt+1
		--~ end
	--~ end
	--~ net.counts[nodename] = cnt
	--~ return cnt
--~ end


------------------------- node registering -------------------------------------

local prios = {
	producer = 1,
	consumer_wait = 25,
	batbox_offer = 50,
	batbox_take = 53,
	consumer_eat = 100,
	batbox_eat = 125,
}

local idleinfo = S" (Idle)"
local outofpower = S" (Energy, I need it)"
local prodinfo = S" (Producing %s EU/s)"
local consinfo = S" (Using %s EU/s)"
local batinfo = S" (Balance: %s EU/s)"

local register_node = minetest.register_node
function minetest.register_node(name, def)
	if not def.technic then
		return register_node(name, def)
	end
	local tech = def.technic
	if tech.produce then
		-- Producer
		tech.machine = true
		tech.priorities = tech.priorities or {prios.producer}
		function tech.on_poll(net)
			-- Get the produced power, add it to the network and update infotext
			local machine = net.machine
			local power = tech.produce(machine.dtime, machine.pos, machine.node,
				net)
			local meta = minetest.get_meta(machine.pos)
			if power > 0 then
				net.power_disposable = net.power_disposable + power
				net.produced_power = net.power_disposable
				meta:set_string("infotext", tech.machine_description ..
					prodinfo:format(technic.EU_string(power * dtime)))
			else
				meta:set_string("infotext", tech.machine_description ..
					idleinfo)
			end
		end
	elseif tech.consume then
		-- Consumer
		tech.machine = true
		tech.priorities = {prios.consumer_wait, prios.consumer_eat}
		function tech.on_poll(net)
			local machine = net.machine
			if net.current_priority == prios.consumer_wait then
				-- Collect information about how much power the machine needs
				local requested_power = tech.request_power(machine.dtime,
					machine.pos, machine.node, net)
				machine.requested_power = requested_power
				net.power_requested = net.power_requested + requested_power
				machine.old_dtime = machine.dtime
				return
			end
			-- Use the power
			if machine.requested_power < net.power_disposable then
				-- not enough power
				meta:set_string("infotext", tech.machine_description ..
					outofpower)
				return
			end
			local power = tech.consume(machine.old_dtime, net.power_disposable,
				machine.pos, machine.node, net)
			local meta = minetest.get_meta(machine.pos)
			if power > 0 then
				net.power_disposable = net.power_disposable - power
				net.consumed_power = net.consumed_power + power
				assert(net.power_disposable >= 0, "too many power taken")
				meta:set_string("infotext", tech.machine_description ..
					consinfo:format(technic.EU_string(power * dtime)))
			else
				meta:set_string("infotext", tech.machine_description ..
					idleinfo)
			end
		end
	elseif tech.offer_power then
		-- Battery Box
		tech.machine = true
		tech.priorities = {prios.batbox_offer, prios.batbox_take,
			prios.batbox_eat}
		function tech.on_poll(net)
			local machine = net.machine
			if net.current_priority == prios.batbox_offer then
				machine.offered_power = 0
				machine.old_dtime = machine.dtime
				if net.power_requested > net.power_disposable then
					-- find out how much power the machine can donate
					local offered_power = tech.offer_power(machine.dtime,
						machine.pos, machine.node, net)
					--~ net.power_batteries_max = net.power_batteries_max
						--~ + offered_power
					machine.offered_power = offered_power
				end
				return
			end
			if net.current_priority == prios.batbox_take then
				machine.donated_power = 0
				local power_to_take = math.min(net.power_requested
					- net.power_disposable, machine.offered_power)
				if power_to_take > 0 then
					-- take power from the battery box
					-- todo take an evenly distributed amount of power from this machine
					--~ local boxcnt = count_nodes_remaining(net, machine.node.name)

					tech.give_power(power_to_take, machine.pos, machine.node,
						net)
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
				taken_power = tech.take_surplus(machine.old_dtime,
					net.power_disposable, machine.pos, machine.node, net)
				net.power_disposable = net.power_disposable - taken_power
				net.batteryboxes_fill = net.batteryboxes_fill + taken_power
			end
			-- show information
			local meta = minetest.get_meta(machine.pos)
			meta:set_string("infotext", tech.machine_description ..
				batinfo:format(technic.EU_string(
				(taken_power - donated_power) * dtime)))
		end
	end
	if tech.machine then
		-- poll the network after placing the machine
		if def.after_place_node then
			error"need override"
		end
		def.after_place_node = function(_,_,_, pt)
			for i = 1,#tech.tiers do
				technic.network.request_poll(pt.under, tech.tiers[i])
			end
		end
	end
	register_node(name, def)
end
