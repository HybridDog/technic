
------------------------- Cache etc. stuff -------------------------------------

local function force_get_node(pos)
	local node = minetest.get_node_or_nil(pos)
	if node then
		return node
	end
	VoxelManip():read_from_map(pos, pos)
	return minetest.get_node(pos)
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

-- walks the cable and finds the machines
local touchps = {
	{x=1, y=0, z=0}, {x=-1, y=0, z=0},
	{x=0, y=0, z=1}, {x=0, y=0, z=-1},
	{x=0, y=1, z=0}, {x=0, y=-1, z=0}
}
-- touchnames needs test
local touchnames = {right=1, left=2, back=3, front=4, top=5, bottom=6}
local function scan_net(pos, tier)
	local machines = {}
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
					founds_h[h] = true
					sp = sp+1
					todo[sp] = p
				elseif is_machine(node.name, tier) then
					local def = minetest.registered_nodes[node.name]
					local connect_sides = def.connect_sides
					local connected = not connect_sides
					if not connected then
						for i = 1,#connect_sides do
							if touchnames[connect_sides[i]] == oi then
								connected = true
								break
							end
						end
					end
					if connected then
						founds_h[h] = true
						machines[#machines+1] = {
							pos = pos,
							node = node,
							def = def
						}
					end
				else
					founds_h[h] = true
				end
			end
		end
	end
	return machines
end

technic.network = {}

-- updates the network
function technic.network.poll(net)
	local pos = net.startpos
	local tier = technic.get_cable_tier(get_node(pos).name)
	if not tier then
		return false
	end
	local machines = scan_net(pos, tier)
	net.tier = tier
	net.machines = machines
	net.current_priority = math.huge
	while true do
		-- find the next smaller priority
		local next_priority = -1
		for i = 1,#machines do
			local data = machines[i].def.technic
			for i = 1,#data.priorities do
				local prio = data.priorities[i]
				if prio < net.current_priority
				and prio > next_priority then
					next_priority = prio
				end
			end
		end
		-- abort after finding the smallest priority
		if next_priority < 0 then
			break
		end
		net.current_priority = next_priority
		-- call the machines' functions
		for i = 1,#machines do
			local machine = machines[i]
			local data = machine.def.technic
			for i = 1,#data.priorities do
				local prio = data.priorities[i]
				if prio == net.current_priority then
					local meta = minetest.get_meta(machine.pos)
					local previous_gametime = meta:get_int
						"technic_previous_poll"
					machine.dtime = net.current_gametime - previous_gametime
					net.machine = machine
					data.on_poll(net)
					meta:set_int("technic_previous_poll", net.current_gametime)
					break
				end
			end
		end
	end
	clean_cache()
end

-- returns a network table
function technic.network.init(startpos, gametime)
	return {
		startpos = startpos,
		power_disposable = 0,
		power_requested = 0,
		poll_interval = 72,  -- 1 second with default time speed
		current_gametime = gametime or minetest.get_gametime(),
	}
end

local function on_switching_update(pos)
	local meta = minetest.get_meta(pos)
	local gametime = minetest.get_gametime()
	local least_gametime = meta:get_int"technic_next_polling"
	if gametime < least_gametime then
		return
	end
	local net = technic.network.init(pos, gametime)
	technic.poll_network(net)

	meta:set_int("technic_next_polling", least_gametime + net.poll_interval)
end


------------------------- node registering -------------------------------------

local prios = {
	producer = 1,
	consumer_wait = 25,
	consumer_eat = 100,
}

local idleinfo = S" (Idle)"
local prodinfo = S" (Producing %s EU/s)"
local consinfo = S" (Using %s EU/s)"

local register_node = minetest.register_node
function minetest.register_node(name, def)
	if not def.technic then
		return register_node(name, def)
	end
	local tech = def.technic
	if tech.supply then
		tech.machine = true
		tech.priorities = tech.priorities or {prios.producer}
		function tech.on_poll(net)
			-- Get the produced power, add it to the network and update infotext
			local machine = net.machine
			local power = tech.supply(machine.dtime, machine.pos, machine.node,
				net)
			local meta = minetest.get_meta(machine.pos)
			if power > 0 then
				net.power_disposable = net.power_disposable + power
				meta:set_string("infotext", tech.machine_description ..
					prodinfo:format(technic.pretty_num(power * dtime)))
			else
				meta:set_string("infotext", tech.machine_description ..
					idleinfo)
			end
		end
	elseif tech.consume then
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
			local available_power = net.power_disposable + net.power_batteries
			if machine.requested_power < available_power then
				-- not enough power
				return
			end
			local power = tech.consume(machine.old_dtime, available_power,
				machine.pos, machine.node, net)
			local meta = minetest.get_meta(machine.pos)
			if power > 0 then
				net.power_disposable = net.power_disposable - power
				if net.power_disposable < 0 then
					-- use battery power
					net.power_batteries = net.power_batteries
						+ net.power_disposable
					net.power_disposable = 0
				end
				meta:set_string("infotext", tech.machine_description ..
					consinfo:format(technic.pretty_num(power * dtime)))
			else
				meta:set_string("infotext", tech.machine_description ..
					idleinfo)
			end
		end
	end
end
