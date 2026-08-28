-- World-side §12 systems: corpses, beds, safe zones, spawn choice,
-- spawn invulnerability.
--
-- Corpses: a body is a short-lived MARKER (~1 min); the loot pile is the
-- persistent object (~20 min via item_entity_ttl). Free information layer.
--
-- Beds: placeable spawn points, part of the world and therefore raidable —
-- destroying one denies a spawn and reveals where its owner will appear.
--
-- Safe zones: certain buildings spawn no creatures and permit no damage
-- (anti-camping is mechanical, not a rule). Unlocked as spawns by
-- exploring them once.

scavock_world = {}

local SAFE_RADIUS = 12
local SPAWN_INVULN = 8

local storage = core.get_mod_storage()

-- ---------------------------------------------------------------------------
-- Safe zone registry
-- ---------------------------------------------------------------------------
local zones = core.deserialize(storage:get_string("zones")) or {}

local function save_zones()
	storage:set_string("zones", core.serialize(zones))
end

local function register_zone(pos)
	for _, z in ipairs(zones) do
		if vector.distance(z, pos) < 4 then return end
	end
	zones[#zones + 1] = vector.round(pos)
	save_zones()
end

function scavock.in_safe_zone(pos)
	for _, z in ipairs(zones) do
		if vector.distance(z, pos) <= SAFE_RADIUS then return true end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Spawn choice: beds + discovered safe zones, selected via /spawns
-- ---------------------------------------------------------------------------
local function get_spawns(player)
	return core.deserialize(player:get_meta():get_string("spawns")) or {}
end
local function set_spawns(player, list)
	player:get_meta():set_string("spawns", core.serialize(list))
end

local function add_spawn(player, label, pos)
	local list = get_spawns(player)
	for _, sp in ipairs(list) do
		if vector.distance(sp.pos, pos) < 3 then return false end
	end
	list[#list + 1] = { label = label, pos = vector.round(pos) }
	set_spawns(player, list)
	return true
end

local function show_spawn_chooser(name)
	local player = core.get_player_by_name(name)
	if not player then return end
	local list = get_spawns(player)
	local fs = { "formspec_version[6]", "size[8,7.6]",
		"label[0.4,0.6;SPAWN POINTS]" }
	local y = 1.1
	local sel = player:get_meta():get_int("spawn_sel")
	for i, sp in ipairs(list) do
		if i > 7 then break end
		local mark = (i == sel) and "> " or ""
		fs[#fs + 1] = ("button[0.4,%f;7.2,0.8;spawn_%d;%s%s  (%d, %d, %d)]")
			:format(y, i, mark, core.formspec_escape(sp.label),
				sp.pos.x, sp.pos.y, sp.pos.z)
		y = y + 0.95
	end
	if #list == 0 then
		fs[#fs + 1] = "label[0.4,1.3;None yet — place a bed, or discover a safe zone.]"
	end
	core.show_formspec(name, "scavock_world:spawns", table.concat(fs))
end

core.register_chatcommand("spawns", {
	description = "Choose your spawn point (§12)",
	func = function(name) show_spawn_chooser(name) return true end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "scavock_world:spawns" then return end
	for field in pairs(fields) do
		local i = field:match("^spawn_(%d+)$")
		if i then
			player:get_meta():set_int("spawn_sel", tonumber(i))
			core.chat_send_player(player:get_player_name(), "Spawn point selected.")
			show_spawn_chooser(player:get_player_name())
			return
		end
	end
end)

-- registered BEFORE the spawn-position handler: respawn callbacks stop at
-- the first that returns true, and invulnerability must always apply
local invuln_until = {}
core.register_on_respawnplayer(function(player)
	invuln_until[player:get_player_name()] =
		core.get_us_time() / 1e6 + SPAWN_INVULN
end)

core.register_on_respawnplayer(function(player)
	local list = get_spawns(player)
	local sel = list[player:get_meta():get_int("spawn_sel")]
	if sel then
		-- a destroyed bed denies the spawn (§12): verify it still exists
		local node = core.get_node_or_nil(sel.pos)
		local valid = true
		if sel.label == "Bed" then
			valid = node and node.name == "scavock_world:bed"
		end
		if valid then
			player:set_pos(vector.add(sel.pos, { x = 0, y = 0.6, z = 0 }))
			return true
		else
			core.chat_send_player(player:get_player_name(),
				"Your bed is gone. Someone knows where you sleep.")
		end
	end
	return false
end)

-- spawn invulnerability (§12): brief, ends immediately if you attack
table.insert(scavock.damage_filters, function(player, hp_change, reason)
	if hp_change >= 0 then return hp_change end
	local name = player:get_player_name()
	-- no damage received inside a safe zone, or during spawn protection
	if scavock.in_safe_zone(player:get_pos()) then return 0 end
	if (invuln_until[name] or 0) > core.get_us_time() / 1e6 then return 0 end
	return hp_change
end)

core.register_on_punchplayer(function(player, hitter)
	if hitter and hitter:is_player() then
		local hname = hitter:get_player_name()
		-- attacking ends your own protection; safe zones block dealt damage
		invuln_until[hname] = nil
		if scavock.in_safe_zone(hitter:get_pos()) then
			return true -- no damage dealt from inside a safe zone
		end
	end
end)

core.register_on_leaveplayer(function(player)
	invuln_until[player:get_player_name()] = nil
end)

-- discovery: walking into a safe zone unlocks it as a spawn
local disc_timer = 0
core.register_globalstep(function(dtime)
	disc_timer = disc_timer + dtime
	if disc_timer < 2 then return end
	disc_timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local pos = player:get_pos()
		for _, z in ipairs(zones) do
			if vector.distance(z, pos) <= SAFE_RADIUS then
				if add_spawn(player, "Safe zone", z) then
					core.chat_send_player(player:get_player_name(),
						"Safe zone discovered — unlocked as a spawn point (/spawns).")
				end
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Bed
-- ---------------------------------------------------------------------------
core.register_node("scavock_world:bed", {
	description = "Bed (right-click: set spawn — raidable, like everything)",
	tiles = { "scavock_bed_top.png", "scavock_bed_side.png", "scavock_bed_side.png" },
	paramtype2 = "facedir",
	groups = { choppy = 2, oddly_breakable_by_hand = 2 },
	node_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, 0.1, 0.5 } },
	drawtype = "nodebox",
	paramtype = "light",
	on_rightclick = function(pos, node, clicker)
		local name = clicker:get_player_name()
		if add_spawn(clicker, "Bed", pos) then
			core.chat_send_player(name, "Spawn point added (/spawns to choose).")
		end
		local list = get_spawns(clicker)
		for i, sp in ipairs(list) do
			if vector.distance(sp.pos, pos) < 3 then
				clicker:get_meta():set_int("spawn_sel", i)
			end
		end
		core.chat_send_player(name, "Bed set as your spawn.")
	end,
})
core.register_craft({
	output = "scavock_world:bed",
	recipe = { { "scavock_core:leather", "scavock_core:leather" },
		{ "scavock_core:planks", "scavock_core:planks" } },
})
scavock.item_sizes["scavock_world:bed"] = { 2, 2 }

-- ---------------------------------------------------------------------------
-- Corpse marker (§12: despawns after ~1 minute; loot outlives it)
-- ---------------------------------------------------------------------------
core.register_node("scavock_world:corpse", {
	description = "Corpse",
	tiles = { "scavock_corpse.png" },
	drawtype = "nodebox",
	paramtype = "light",
	node_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, -0.15, 0.5 } },
	walkable = false,
	groups = { oddly_breakable_by_hand = 3, not_in_creative_inventory = 1 },
	drop = "",
	on_timer = function(pos)
		core.remove_node(pos)
	end,
})

core.register_on_dieplayer(function(player)
	local pos = vector.round(player:get_pos())
	if core.get_node(pos).name == "air" then
		core.set_node(pos, { name = "scavock_world:corpse" })
		core.get_meta(pos):set_string("infotext",
			player:get_player_name() .. " fell here")
		core.get_node_timer(pos):start(60)
	end
end)

-- ---------------------------------------------------------------------------
-- Safe-zone shelters, stamped into open biomes (§12: ~one per town/plain)
-- ---------------------------------------------------------------------------
local function make_shelter()
	local sx, sy, sz = 7, 5, 7
	local data = {}
	for i = 1, sx * sy * sz do
		data[i] = { name = "air", prob = 0 }
	end
	local function set(x, y, z, name, prob, force)
		data[((z * sy) + y) * sx + x + 1] =
			{ name = name, prob = prob or 255, force_place = force }
	end
	for x = 0, sx - 1 do
		for z = 0, sz - 1 do
			set(x, 0, z, "scavock_core:planks", 255, true)
			set(x, 4, z, "scavock_core:planks", 255, true)
			local wall = (x == 0 or x == sx - 1 or z == 0 or z == sz - 1)
			if wall then
				for y = 1, 3 do
					set(x, y, z, "scavock_core:planks", 255, true)
				end
			end
		end
	end
	set(3, 1, 0, "air", 255, true)
	set(3, 2, 0, "air", 255, true)
	set(3, 1, 3, "scavock_world:safezone_core", 255, true)
	return { size = { x = sx, y = sy, z = sz }, data = data }
end

core.register_node("scavock_world:safezone_core", {
	description = "Shelter Stone (safe zone)",
	tiles = { "scavock_safezone.png" },
	light_source = 12,
	diggable = false,
	groups = { not_in_creative_inventory = 1 },
	on_construct = function(pos)
		register_zone(pos)
		core.get_meta(pos):set_string("infotext",
			"Safe zone — no damage, no creatures")
	end,
})

-- worldgen-stamped shelters register their zone via LBM (schematic
-- placement doesn't run on_construct)
core.register_lbm({
	label = "register safe zones",
	name = "scavock_world:register_zones",
	nodenames = { "scavock_world:safezone_core" },
	run_at_every_load = true,
	action = function(pos)
		register_zone(pos)
	end,
})

core.register_decoration({
	name = "scavock_world:shelter",
	deco_type = "schematic",
	place_on = { "scavock_core:dirt_with_grass", "scavock_core:dirt_with_dry_grass" },
	sidelen = 80,
	fill_ratio = 0.00003,
	biomes = { "grasslands", "plains", "savanna" },
	y_min = 4, y_max = 120,
	schematic = make_shelter(),
	place_offset_y = -1,
	flags = "place_center_x, place_center_z, force_placement",
	rotation = "random",
})

-- creatures respect safe zones (hooked by scavock_creatures' spawner)
scavock_world.SAFE_RADIUS = SAFE_RADIUS


-- ---------------------------------------------------------------------------
-- Private / whitelist servers (§28 tier 1). Host from the menu, then:
--   /whitelist on | off | add <name> | remove <name> | list
-- Off by default: a freshly hosted world is open LAN/direct-join.
-- ---------------------------------------------------------------------------
local wl_store = core.get_mod_storage()

local function wl_get()
	return core.deserialize(wl_store:get_string("whitelist")) or {}
end
local function wl_enabled()
	return wl_store:get_int("whitelist_on") == 1
end

core.register_chatcommand("whitelist", {
	privs = { server = true },
	params = "on | off | add <name> | remove <name> | list",
	description = "Private-server whitelist (§28)",
	func = function(name, param)
		local cmd, who = param:match("^(%a+)%s*(%S*)$")
		local list = wl_get()
		if cmd == "on" then
			wl_store:set_int("whitelist_on", 1)
			return true, "Whitelist ON — only listed names (and you) can join."
		elseif cmd == "off" then
			wl_store:set_int("whitelist_on", 0)
			return true, "Whitelist OFF — open server."
		elseif cmd == "add" and who ~= "" then
			list[who:lower()] = true
			wl_store:set_string("whitelist", core.serialize(list))
			return true, who .. " whitelisted."
		elseif cmd == "remove" and who ~= "" then
			list[who:lower()] = nil
			wl_store:set_string("whitelist", core.serialize(list))
			return true, who .. " removed."
		elseif cmd == "list" then
			local names = {}
			for n in pairs(list) do names[#names + 1] = n end
			return true, (wl_enabled() and "ON: " or "off: ")
				.. (#names > 0 and table.concat(names, ", ") or "(empty)")
		end
		return false, "Usage: /whitelist on|off|add <name>|remove <name>|list"
	end,
})

core.register_on_prejoinplayer(function(name, ip)
	if not wl_enabled() then return end
	if core.is_singleplayer and core.is_singleplayer() then return end
	-- admins (server priv) always get in; so does the whitelist
	local privs = core.get_player_privs(name)
	if privs.server then return end
	if not wl_get()[name:lower()] then
		return "This Scavock server is private. Ask the host to /whitelist add "
			.. name
	end
end)
