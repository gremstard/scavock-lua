-- Wires & power (§15).
--
-- Not optional content: lights need power, and a lit base is a mob-proof
-- base (§14). Torches are the unpowered floor — dimmer, securing less
-- space per unit; powered lamps are the upgrade that pulls players into
-- the wire system. Fuel comes out of raids: the upkeep loop IS base decay
-- (an abandoned base runs out of fuel, goes dark, and fills with hostiles).
--
-- Parts, not machines (§15): wire, engine, battery, solar, lamp, switch,
-- pressure plate, powered door, alarm. Combinatorics do the rest.
--
-- Open questions honored: engines DO make noise (§15 open #1 — resolved
-- toward the interesting tradeoff: a running engine is a standing noise
-- source, solar is silent); power range is the conduction distance below
-- (#2, tuning); this is the 1.0 parts list (#3, smallest reversible).

local RANGE = 48            -- max conduction path length in nodes
local POLL = 2              -- seconds between device polls

local CONDUCTS = {}         -- node name -> true (participates in a circuit)
local function conducts(name) CONDUCTS[name] = true end

-- ---------------------------------------------------------------------------
-- Network: BFS from a device through conductors, looking for a live source.
-- ---------------------------------------------------------------------------
local NEIGH = {
	{ x = 1, y = 0, z = 0 }, { x = -1, y = 0, z = 0 },
	{ x = 0, y = 1, z = 0 }, { x = 0, y = -1, z = 0 },
	{ x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = -1 },
}

local function is_live_source(pos, name, allow_battery)
	if name == "scavock_power:engine_on" then return true end
	if name == "scavock_power:solar" then
		local light = core.get_node_light({ x = pos.x, y = pos.y + 1, z = pos.z }, nil)
		local sun = core.get_node_light({ x = pos.x, y = pos.y + 1, z = pos.z }, 0.5)
		return sun and sun >= 13 and light == sun -- actual daylight on it
	end
	if allow_battery and name == "scavock_power:battery" then
		return core.get_meta(pos):get_int("charge") > 0
	end
	return false
end

local function find_source(start, allow_battery)
	local seen = { [core.hash_node_position(start)] = true }
	local queue = { start }
	local head, count = 1, 0
	while queue[head] and count < RANGE * 6 do
		local pos = queue[head]
		head = head + 1
		count = count + 1
		for _, d in ipairs(NEIGH) do
			local np = vector.add(pos, d)
			local h = core.hash_node_position(np)
			if not seen[h] then
				seen[h] = true
				local name = core.get_node(np).name
				if is_live_source(np, name, allow_battery) then
					return np, name
				end
				if CONDUCTS[name] then
					queue[#queue + 1] = np
				end
			end
		end
	end
	return nil
end
scavock_power_find_source = find_source

local function powered(pos)
	return find_source(pos, true) ~= nil
end

local function start_poll(pos)
	core.get_node_timer(pos):start(POLL)
end

-- ---------------------------------------------------------------------------
-- Conductors
-- ---------------------------------------------------------------------------
core.register_node("scavock_power:wire", {
	description = "Wire (copper + plastic — strip the ruins)",
	drawtype = "nodebox",
	tiles = { "scavock_wire.png" },
	inventory_image = "scavock_wire.png",
	paramtype = "light",
	walkable = false,
	node_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, -0.35, 0.5 } },
	groups = { snappy = 3, oddly_breakable_by_hand = 3, attached_node = 1 },
})
conducts("scavock_power:wire")

core.register_node("scavock_power:switch_off", {
	description = "Switch",
	tiles = { "scavock_switch_off.png" },
	groups = { cracky = 3, oddly_breakable_by_hand = 2 },
	on_rightclick = function(pos, node)
		core.swap_node(pos, { name = "scavock_power:switch_on",
			param2 = node.param2 })
	end,
})
core.register_node("scavock_power:switch_on", {
	description = "Switch (on)",
	tiles = { "scavock_switch_on.png" },
	groups = { cracky = 3, oddly_breakable_by_hand = 2,
		not_in_creative_inventory = 1 },
	drop = "scavock_power:switch_off",
	on_rightclick = function(pos, node)
		core.swap_node(pos, { name = "scavock_power:switch_off",
			param2 = node.param2 })
	end,
})
conducts("scavock_power:switch_on") -- only the ON state conducts

core.register_node("scavock_power:plate", {
	description = "Pressure Plate (conducts while stood on)",
	drawtype = "nodebox",
	tiles = { "scavock_plate.png" },
	paramtype = "light",
	walkable = true,
	node_box = { type = "fixed", fixed = { -0.45, -0.5, -0.45, 0.45, -0.4, 0.45 } },
	groups = { cracky = 3, oddly_breakable_by_hand = 2 },
})
core.register_node("scavock_power:plate_on", {
	description = "Pressure Plate (pressed)",
	drawtype = "nodebox",
	tiles = { "scavock_plate.png" },
	paramtype = "light",
	node_box = { type = "fixed", fixed = { -0.45, -0.5, -0.45, 0.45, -0.44, 0.45 } },
	groups = { cracky = 3, not_in_creative_inventory = 1 },
	drop = "scavock_power:plate",
})
conducts("scavock_power:plate_on")

-- plates poll for standing objects
core.register_abm({
	label = "pressure plates",
	nodenames = { "scavock_power:plate", "scavock_power:plate_on" },
	interval = 1, chance = 1,
	action = function(pos, node)
		local stood = false
		for obj in core.objects_inside_radius(
				{ x = pos.x, y = pos.y + 0.5, z = pos.z }, 0.9) do
			stood = true
			break
		end
		local want = stood and "scavock_power:plate_on" or "scavock_power:plate"
		if node.name ~= want then
			core.swap_node(pos, { name = want })
		end
	end,
})

-- batteries conduct and store
core.register_node("scavock_power:battery", {
	description = "Battery (stores charge from engines and solar)",
	tiles = { "scavock_battery.png" },
	groups = { cracky = 2 },
	on_construct = function(pos)
		core.get_meta(pos):set_int("charge", 0)
		core.get_meta(pos):set_string("infotext", "Battery (0)")
		start_poll(pos)
	end,
	on_timer = function(pos)
		local meta = core.get_meta(pos)
		local charge = meta:get_int("charge")
		-- charges only from a real generator (not other batteries)
		if find_source(pos, false) then
			charge = math.min(charge + POLL, 600)
		else
			charge = math.max(charge - POLL, 0) -- self-drain while sourcing
		end
		meta:set_int("charge", charge)
		meta:set_string("infotext", ("Battery (%ds)"):format(charge))
		return true
	end,
})
conducts("scavock_power:battery")

-- ---------------------------------------------------------------------------
-- Sources
-- ---------------------------------------------------------------------------
local function engine_formspec()
	return table.concat({
		"formspec_version[6]", "size[10.7,10]",
		"label[0.4,0.5;Engine — burns coal or oil]",
		"list[context;fuel;4.8,1.2;1,1;]",
		"list[current_player;main;0.4,3.4;8,6;]",
		"listring[context;fuel]", "listring[current_player;main]",
	})
end

local function engine_def(on)
	return {
		description = on and "Engine (running)" or "Engine (block form — §15)",
		tiles = { "scavock_engine.png" },
		paramtype2 = "facedir",
		light_source = on and 4 or 0,
		groups = { cracky = 2, not_in_creative_inventory = on and 1 or nil },
		drop = "scavock_power:engine",
		on_construct = function(pos)
			local meta = core.get_meta(pos)
			meta:set_string("formspec", engine_formspec())
			meta:get_inventory():set_size("fuel", 1)
			meta:set_string("infotext", "Engine")
			start_poll(pos)
		end,
		can_dig = function(pos)
			return core.get_meta(pos):get_inventory():is_empty("fuel")
		end,
		on_metadata_inventory_put = function(pos)
			start_poll(pos)
		end,
		on_timer = function(pos)
			local meta = core.get_meta(pos)
			local burn = meta:get_int("burn")
			if burn > 0 then
				burn = burn - POLL
			else
				local inv = meta:get_inventory()
				local fuel = inv:get_stack("fuel", 1)
				local fname = fuel:get_name()
				if fname == "scavock_core:coal_lump" then
					fuel:take_item()
					inv:set_stack("fuel", 1, fuel)
					burn = 60
				elseif fname == "scavock_power:oil" then
					fuel:take_item()
					inv:set_stack("fuel", 1, fuel)
					burn = 180
				end
			end
			meta:set_int("burn", math.max(burn, 0))
			local want = burn > 0 and "scavock_power:engine_on"
				or "scavock_power:engine"
			local node = core.get_node(pos)
			if node.name ~= want then
				node.name = want
				core.swap_node(pos, node)
			end
			meta:set_string("infotext", burn > 0
				and ("Engine (running, %ds fuel)"):format(burn) or "Engine (out of fuel)")
			-- §15 open #1, resolved to the tradeoff: running engines are LOUD
			if burn > 0 and scavock.noise and math.random(3) == 1 then
				scavock.noise(pos, 18, nil)
			end
			return true
		end,
	}
end
core.register_node("scavock_power:engine", engine_def(false))
core.register_node("scavock_power:engine_on", engine_def(true))
conducts("scavock_power:engine")
conducts("scavock_power:engine_on")

core.register_node("scavock_power:solar", {
	description = "Solar Panel (daylight only — silent)",
	drawtype = "nodebox",
	tiles = { "scavock_solar.png" },
	paramtype = "light",
	node_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, -0.3, 0.5 } },
	groups = { cracky = 2 },
})
conducts("scavock_power:solar")

core.register_craftitem("scavock_power:oil", {
	description = "Oil Canister (engine fuel — the economy's sink, §6)",
	inventory_image = "scavock_oil.png",
})
core.register_craft({ type = "fuel", recipe = "scavock_power:oil", burntime = 90 })

-- ---------------------------------------------------------------------------
-- Devices
-- ---------------------------------------------------------------------------
core.register_node("scavock_power:lamp_off", {
	description = "Lamp (powered light — brighter than any torch)",
	tiles = { "scavock_lamp_off.png" },
	groups = { cracky = 3, oddly_breakable_by_hand = 2 },
	drop = "scavock_power:lamp_off",
	on_construct = start_poll,
	on_timer = function(pos)
		if powered(pos) then
			core.swap_node(pos, { name = "scavock_power:lamp_on" })
			start_poll(pos)
			return false
		end
		return true
	end,
})
core.register_node("scavock_power:lamp_on", {
	description = "Lamp (lit)",
	tiles = { "scavock_lamp_on.png" },
	light_source = 14,
	groups = { cracky = 3, not_in_creative_inventory = 1 },
	drop = "scavock_power:lamp_off",
	on_construct = start_poll,
	on_timer = function(pos)
		if not powered(pos) then
			core.swap_node(pos, { name = "scavock_power:lamp_off" })
			start_poll(pos)
			return false
		end
		return true
	end,
})
conducts("scavock_power:lamp_off")
conducts("scavock_power:lamp_on")

core.register_node("scavock_power:door", {
	description = "Powered Door (opens while powered)",
	tiles = { "scavock_door.png" },
	paramtype = "light",
	groups = { choppy = 2 },
	on_construct = start_poll,
	on_timer = function(pos)
		if powered(pos) then
			core.swap_node(pos, { name = "scavock_power:door_open" })
			start_poll(pos)
			return false
		end
		return true
	end,
})
core.register_node("scavock_power:door_open", {
	description = "Powered Door (open)",
	drawtype = "nodebox",
	tiles = { "scavock_door.png" },
	paramtype = "light",
	walkable = true,
	node_box = { type = "fixed", fixed = { 0.35, -0.5, -0.5, 0.5, 1.5, 0.5 } },
	collision_box = { type = "fixed", fixed = { 0.35, -0.5, -0.5, 0.5, 1.5, 0.5 } },
	groups = { choppy = 2, not_in_creative_inventory = 1 },
	drop = "scavock_power:door",
	on_construct = start_poll,
	on_timer = function(pos)
		if not powered(pos) then
			core.swap_node(pos, { name = "scavock_power:door" })
			start_poll(pos)
			return false
		end
		return true
	end,
})
conducts("scavock_power:door")
conducts("scavock_power:door_open")

core.register_node("scavock_power:alarm", {
	description = "Alarm (screams while powered — wire it to a plate)",
	tiles = { "scavock_alarm.png" },
	groups = { cracky = 3 },
	on_construct = start_poll,
	on_timer = function(pos)
		if powered(pos) then
			if scavock.noise then
				scavock.noise(pos, 40, nil)
			end
			for _, player in ipairs(core.get_connected_players()) do
				if vector.distance(player:get_pos(), pos) < 40 then
					core.chat_send_player(player:get_player_name(),
						"An alarm is sounding nearby.")
				end
			end
		end
		return true
	end,
})
conducts("scavock_power:alarm")

-- ---------------------------------------------------------------------------
-- Torches: the unpowered floor (dimmer, always works)
-- ---------------------------------------------------------------------------
core.register_node("scavock_power:torch", {
	description = "Torch (dim, no power needed — never a hard lock)",
	drawtype = "plantlike",
	tiles = { "scavock_torch.png" },
	inventory_image = "scavock_torch.png",
	paramtype = "light",
	light_source = 9,
	walkable = false,
	groups = { snappy = 3, oddly_breakable_by_hand = 3, attached_node = 1,
		flammable = 1 },
	selection_box = { type = "fixed", fixed = { -0.15, -0.5, -0.15, 0.15, 0.35, 0.15 } },
})

-- ---------------------------------------------------------------------------
-- Crafting (§15: wires from copper and plastic)
-- ---------------------------------------------------------------------------
core.register_craftitem("scavock_power:plastic", {
	description = "Plastic Scrap (stripped from ruins)",
	inventory_image = "scavock_plastic.png",
})

local C = "scavock_core:copper_ingot"
core.register_craft({ output = "scavock_power:wire 8",
	recipe = { { C, C }, { "scavock_power:plastic", "" } } })
core.register_craft({ output = "scavock_power:torch 4",
	recipe = { { "scavock_core:coal_lump" }, { "scavock_core:stick" } } })
core.register_craft({ output = "scavock_power:lamp_off",
	recipe = { { C, "scavock_core:scrap_ingot" },
		{ "scavock_power:plastic", "scavock_power:wire" } } })
core.register_craft({ output = "scavock_power:engine",
	recipe = { { "scavock_core:iron_ingot", "scavock_core:iron_ingot" },
		{ C, "scavock_core:iron_ingot" } } })
core.register_craft({ output = "scavock_power:battery",
	recipe = { { C, "scavock_core:scrap_ingot" },
		{ "scavock_core:coal_lump", "scavock_core:scrap_ingot" } } })
core.register_craft({ output = "scavock_power:solar",
	recipe = { { "scavock_core:titanium_ingot", C },
		{ "scavock_power:plastic", "scavock_power:wire" } } })
core.register_craft({ output = "scavock_power:switch_off",
	recipe = { { C }, { "scavock_core:stick" } } })
core.register_craft({ output = "scavock_power:plate",
	recipe = { { "scavock_core:stone", "scavock_core:stone" }, { C, "" } } })
core.register_craft({ output = "scavock_power:door",
	recipe = { { "scavock_core:planks", "scavock_core:planks" },
		{ "scavock_core:planks", C } } })
core.register_craft({ output = "scavock_power:alarm",
	recipe = { { "scavock_core:scrap_ingot", C },
		{ "scavock_power:wire", "scavock_core:scrap_ingot" } } })
