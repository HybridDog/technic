
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

local function get_type_from_cable(name)
	return "LV?"
end

local function is_cable(name, tier)
	return name == "technic:cable?" .. tier
end

-- tests whether the node is a technic machine
local function is_machine(name, tier)
	local def = minetest.registered_nodes[name]
	if not def.technic then
		return false
	end
	for i = 1,#def.technic.types do
		if def.technic.types[i] == tier then
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
local function scan_net(pos, tier)
	local machines = {}
	local founds_h = {} -- > 1 cable required
	local todo = {pos}
	local sp = 1
	while sp > 0 do
		local p = todo[sp]
		sp = sp-1
		for i = 1,6 do
			local p = vector.add(p, touchps[i])
			local h = poshash(p)
			if not founds_h[h] then
				founds_h[h] = true
				local node = get_node(p)
				if is_cable(node.name, tier) then
					sp = sp+1
					todo[sp] = p
				elseif is_machine(node.name, tier) then
					machines[#machines+1] = {
						pos = pos,
						node = node,
						def = minetest.registered_nodes[node.name]
					}
				end
			end
		end
	end
	return machines
end

-- updates the network
function technic.poll_network(net)
	local pos = net.startpos
	local tier = get_type_from_cable(get_node(pos))
	if not tier then
		return false
	end
	local machines = scan_net(pos, tier)
	net.tier = tier
	net.machines = machnies
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

-- salacious
local function on_switching_update(pos)
	local meta = minetest.get_meta(pos)
	local gametime = minetest.get_gametime()
	local least_gametime = meta:get_int"technic_next_polling"
	if gametime < least_gametime then
		return
	end
	local net = {
		startpos = pos,
		poll_interval = -1,
		current_gametime = gametime
	}
	technic.poll_network(net)

	-- set the next poll to some value if nothing was specified
	if net.poll_interval < 0 then
		net.poll_interval = 9
	end
	meta:set_int("technic_next_polling", least_gametime + net.poll_interval)
end
