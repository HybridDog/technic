This file is fairly incomplete. Help is welcome.

Tiers
-----
The tier is a string, currently `"LV"`, `"MV"` and `"HV"` are supported.

Network
-------
The network is the cable with the connected machine nodes. It is represented by
a table passed to `on_poll` and has following fields:
* `tier`
	* This string is the tier of the network.
	  Machines which belong to this tier have their `on_poll` executed.
	* See `Tiers` for the known values.
* `current_priority`
	* The current priority, use this when specifying multiple `priorities`.
* `power_disposable = 0`
	* This value represents the power machines, such as watermill, produced.
* `power_requested = 0`
	* This value should be the power all machines in the network need.
* `machine`
	* This table is information about the current machine in `on_poll`, it
	  contains following fields:
		* `dtime`
			* The time difference from the previous access to the machine
			  in minetest time seconds
			* Use it to calculate produced or consumed power
		* `pos`
		* `node`
		* `meta`
* `current_gametime`
	* This number is the gametime of when the network polling began.
* `startpos`
	* The position of the first detected cable of the network
* `machines`
	* This is the table of machines connected to the network.
* `poll_interval = 72`
	* The poll interval is the time delay until the machines are updated next
	  again.
	* The value is in minetest time seconds.
* `produced_power`
	* The aggregate power supplied by all producers
	* result after polling
* `consumed_power`
	* The aggregate power taken by all consumers
	* result after polling
* `batteryboxes_drain`
	* The aggregate drainage of battery boxes
	* result after polling
* `batteryboxes_fill`
	* The aggregate filling of battery boxes
	* result after polling
You can - and should - change fields of this table if you need to.

Helper functions
----------------
* `technic.EU_string(num)`
	* Converts num to a human-readable string with unit
	* Use this function when showing players power values
* `technic.pretty_num(num)`
	* Converts the number `num` to a human-readable string
* `technic.swap_node(pos, nodename)`
	* Same as `mintest.swap_node` but it only changes the nodename.
	* It uses `minetest.get_node` before swapping to ensure the new nodename
	  is not the same as the current one.
* `technic.get_or_load_node(pos)`
	* If the mapblock is loaded, it returns the node at pos,
	  else it loads the chunk and returns `nil`.
* `technic.set_RE_wear(itemstack, item_load, max_charge)`
	* If the `wear_represents` field in the item's nodedef is
	  `"technic_RE_charge"`, this function does nothing.
* `technic.refill_RE_charge(itemstack)`
	* This function fully recharges an RE chargeable item.
	* If `technic.power_tools[itemstack:get_name()]` is `nil` (or `false`), this
	  function does nothing, else that value is the maximum charge.
	* The itemstack metadata is changed to contain the charge.
* `technic.is_tier_cable(nodename, tier)`
	* Tells whether the node `nodename` is the cable of the tier `tier`.
* `technic.get_cable_tier(nodename)`
	* Returns the tier of the cable `nodename` or `nil`.
* `technic.trace_node_ray(pos, dir, range)`
	* Returns an iteration function (usable in the for loop) to iterate over the
	  node positions along the specified ray.
	* The returned positions will not include the starting position `pos`.
* `technic.trace_node_ray_fat(pos, dir, range)`
	* Like `technic.trace_node_ray` but includes extra positions near the ray.
	* The node ray functions are used for mining lasers.
* `technic.config:get(name)`
	* Some configuration function
* `technic.tube_inject_item(pos, start_pos, velocity, item)`
	* Same as `pipeworks.tube_inject_item`
* `technic.network.disable_inactives(pos, tier)`
	* Used when cutting off a network (part) from a polling node, such as SS.
* `technic.network.request_poll(pos, tier)`
	* Makes switching station update the net also if the polling interval isn't
	  exceeded yet.

Registration functions
----------------------
* `technic.register_power_tool(itemname, max_charge)`
	* Same as `technic.power_tools[itemname] = max_charge`
	* This function makes the craftitem `itemname` chargeable.
* `technic.register_tier(tier)`
	* Same as `technic.machines[tier] = {}`
	* See also `tiers`

### Specific machines
* `technic.register_solar_array(data)`
	* data is a table

Used itemdef fields
-------------------
* `technic`: (a table)
	In this table information for technic is stored.
	* `tiers = {}`
		* This table contains the tiers the machine belongs to, e.g. `{"LV"}`
	* `machine_description = ""`
		* The machine description is currently used for setting the infotext.
	Producer:
		* If produce is specified, `priorities` is set to `{1}`, `machine` is set
		  to `true` and the `on_poll` function is set to call the supply
		  function.
		* `produce = function(dtime, pos, node, net)`
			* The return value is the power the machine produced.
			  The infotext is set according to this value.
	Consumer:
		* If consume is specified, `priorities` is set to `{25, 100}`,
		  `machine` is set to `true` and the `on_poll` function is set to call
		  the `request_power` function and then `consume`.
		* `consume = function(dtime, available_power, pos, node, net)`
			* The return value is the power the machine consumed, it is positive and
			  must not be bigger than available_power.
			  The infotext is set according to this value.
			* dtime is the same number as the one passed to `request_power`.
			* `request_power` needs to be set for consume to work.
		* `request_power = function(dtime, pos, node, net)`
			* This function should return the power the machine needs.
			* Knowing the power usage up front is necessary to control other
			  machines such as supply converter and battery box.
			* Make it return `0` if you really don't want to use it.
	Battery Box:
		* If offer_power is specified, `priorities` is set to `{50, 53, 125}`,
		  `machine` is set to `true` and the `on_poll` function is set to call
		  the `offer_power`, `give_power` and then the `take_surplus` function.
		* `offer_power = function(dtime, pos, node, net)`
			* The return value is the maximum amount of power which can be taken
			  from the battery box.
			* It's only called if power from battery boxes is required.
		* `give_power = function(power_to_take, pos, node, net)`
			* In this function, power_to_take becomes removed from the battery
			  box's storage.
			* It's only called if power from battery boxes is required.
		* `take_surplus = function(dtime, disposable_power, pos, node, net)`
			* The return value is the power stored in the machine.
			* disposable_power is the maximum amount of power which should be
			  taken. (0 <= return_value <= disposable_power > 0)
	Switching Station:
		* If activates_network is true, the node can poll the network.
		* `activates_network = false`
			* tells whether the node is a SS
		* `do_poll = function(pos, machines)`
			* This is called when the network needs to be polled explicitly,
			  e.g. after adding a new cable.
			* See also `technic.network.request_poll`
	Custom:
		* `on_poll = function(net)`
			* Called when a network with this machine connected is updated.
			* If multiple priorities are specified, the it becomes executed
			  multiple times, e.g. for the battery box to take and give power.
		* `priorities = {}`
			* In this table, set the priorities (number values) of the machine.
			* The smaller a priority is, the earlier `on_poll` is executed, so
			  e.g. pruducers have a small value and consumers have a big one.
		* `machine = true`
			* Set this boolean to true to use the node as machine.
			* The switching station doesn't have this set to true.
	* `disconnect = function(pos, node, machine)`
		* If set, this is called when e.g. the SS became dug.
		* machine.meta is the meta of the machine
		* machine.current_tier is the tier of the disconnected network
		* These messy parameters are to be changed soon
* `groups`:
	* `technic_<ltier> = 1` ltier is a tier in small letters; this group makes
	  the node connect to the cable(s) of the right tier.
* `connect_sides`
	* In addition to the default use (see lua_api.txt), this tells where the
	  machine can be connected.


Legacy
------

### Used itemdef fields
* `technic_run(pos, node, run_stage)`
	* This function was used to update the node.
	  Modders had to manually change the information about supply
	  etc. (see below) in the node metadata.
	* run_stage is technic.producer, technic.receiver or technic.battery.
* `technic_on_disable(pos, node)`
	* Called when the machine looses the network
* `technic_disabled_machine_name`
	* If specified, an active machine becomes set to this node when loosing net.
* groups:
	* `technic_machine = 1`

### Machine types
There are currently following types:
* `technic.receiver = "RE"` e.g. grinder
* `technic.producer = "PR"` e.g. solar panel
* `technic.producer_receiver = "PR_RE"` supply converter
* `technic.battery  = "BA"` e.g. LV batbox

### Switching Station
The switching station was the center of all power distribution on an electric
network.

The station collects power from sources (PR), distributes it to sinks (RE),
and uses the excess/shortfall to charge and discharge batteries (BA).

For now, all supply and demand values are expressed in kW.

It works like this:
 All PR,BA,RE nodes are indexed and tagged with the switching station.
The tagging is a workaround to allow more stations to be built without allowing
a cheat with duplicating power.
 All the RE nodes are queried for their current EU demand. Those which are off
would require no or a small standby EU demand, while those which are on would
require more.
If the total demand is less than the available power they are all updated with
the demand number.
If any surplus exists from the PR nodes the batteries will be charged evenly
with this.
If the total demand requires draw on the batteries they will be discharged
evenly.

If the total demand is more than the available power all RE nodes will be shut
down. We have a brown-out situation.

Hence for now all the power distribution logic resides in this single node.

If the switching station is powered by mesecons, it sends the supply and demand
values of the network via digiline.

#### Node meta usage
Machines connected to the network will have one or more of these fields in meta
data:
	* `<LV|MV|HV>_EU_supply` : Exists for PR and BA node types
	This is the EU value supplied by the node. Output
	* `<LV|MV|HV>_EU_demand` : Exists for RE and BA node types
	This is the EU value the node requires to run. Output
	* `<LV|MV|HV>_EU_input`  : Exists for RE and BA node types
	This is the actual EU value the network can give the node. Input
	* `<LV|MV|HV>_EU_timeout`: Used to find disconnected machines
	0: disconnected, 1: connected, 2: connected (freshly updated); Input
	* `<LV|MV|HV>_network`   : The serialized position of the switching station
	Can be e.g. "(1813,36,-257)"; Input
Input means you can read this data in the machine's run function,
Output means you can write to the field

The reason the LV|MV|HV type is prepended to meta data is because some machine
could require several supplies to work.
This way the supplies are separated per network.

### Registration functions
* `technic.register_machine(tier, nodename, machine_type)`
	* Same as `technic.machines[tier][nodename] = machine_type`
	* See also `Machine types`
