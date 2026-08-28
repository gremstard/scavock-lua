-- The extraction loop (§1: the third side of the coin).
--
-- Evac beacons spawn in the world (§4: "every large biome area contains a
-- naturally spawning evac point"). Channel one for 10 seconds while staying
-- close and alive, and everything in your backpack banks into your Extraction
-- Stash, then you are returned to your first-spawn point. Die first and it
-- all drops where you fell (§12). Beacons run a cooldown after use (D1's
-- evac-on-a-cooldown model, simplified: block-structure damage/repair is a
-- later step, noted in README).
--
-- Vault (§5): small, survives everything — in this slice it survives death;
-- across wipes it is the piece you carry to a fresh world. Stash stands in
-- for base containers: big, but conceptually wiped with the map.

local CHANNEL_TIME = 10
local CHANNEL_RADIUS = 4
local BEACON_COOLDOWN = 120

local VAULT_SIZE = { w = 4, h = 2 }  -- deliberately too small to matter much (§2)
local STASH_SIZE = { w = 8, h = 6 }

-- ---------------------------------------------------------------------------
-- Persistent per-player detached inventories, serialized into player meta.
-- ---------------------------------------------------------------------------
local function inv_key(kind) return "scavock_" .. kind end

local function save_list(player, kind, inv)
	local out = {}
	for i = 1, inv:get_size("main") do
		out[i] = inv:get_stack("main", i):to_string()
	end
	player:get_meta():set_string(inv_key(kind), core.serialize(out))
end

local function make_detached(player, kind, size)
	local name = "scavock_" .. kind .. "_" .. player:get_player_name()
	local inv = core.create_detached_inventory(name, {
		on_put = function(det_inv)
			local p = core.get_player_by_name(player:get_player_name())
			if p then save_list(p, kind, det_inv) end
		end,
		on_take = function(det_inv)
			local p = core.get_player_by_name(player:get_player_name())
			if p then save_list(p, kind, det_inv) end
		end,
		on_move = function(det_inv)
			local p = core.get_player_by_name(player:get_player_name())
			if p then save_list(p, kind, det_inv) end
		end,
	})
	inv:set_size("main", size.w * size.h)
	local stored = player:get_meta():get_string(inv_key(kind))
	if stored ~= "" then
		local list = core.deserialize(stored) or {}
		for i = 1, size.w * size.h do
			inv:set_stack("main", i, ItemStack(list[i] or ""))
		end
	end
	return name, inv
end

core.register_on_joinplayer(function(player)
	make_detached(player, "vault", VAULT_SIZE)
	make_detached(player, "stash", STASH_SIZE)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	core.remove_detached_inventory("scavock_vault_" .. name)
	core.remove_detached_inventory("scavock_stash_" .. name)
end)

local function storage_formspec(player_name, kind, size, label, note)
	local list_h = size.h * 1.25 + 0.15
	return table.concat({
		"formspec_version[6]", ("size[10.7,%f]"):format(1.4 + list_h + 7.9 + 0.5),
		"label[0.4,0.5;", label, "]",
		"label[0.4,1.0;", note, "]",
		("list[detached:scavock_%s_%s;main;0.4,1.4;%d,%d;]")
			:format(kind, player_name, size.w, size.h),
		("list[current_player;main;0.4,%f;8,6;]"):format(1.4 + list_h + 0.4),
		("listring[detached:scavock_%s_%s;main]"):format(kind, player_name),
		"listring[current_player;main]",
	})
end

scavock_evac = scavock_evac or {}

-- The vault has a grid view owned by scavock_grid; the stash stays a plain
-- list (it stands in for base containers, which are not grid-restricted).
function scavock_evac.show_stash(name)
	core.show_formspec(name, "scavock_evac:stash",
		storage_formspec(name, "stash", STASH_SIZE, "Extraction Stash",
			"Banked by evac. Survives death; wiped with the map."))
end

core.register_chatcommand("stash", {
	description = "Open your extraction stash",
	func = function(name) scavock_evac.show_stash(name) return true end,
})

-- ---------------------------------------------------------------------------
-- Evac beacon
-- ---------------------------------------------------------------------------
local channels = {} -- player name -> { pos, t }

local function bank_inventory(player)
	local name = player:get_player_name()
	local inv = player:get_inventory()
	local stash = core.get_inventory({ type = "detached", name = "scavock_stash_" .. name })
	if not stash then return 0, 0 end
	local moved, left = 0, 0
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		if not stack:is_empty() then
			local rest = stash:add_item("main", stack)
			inv:set_stack("main", i, rest)
			moved = moved + stack:get_count() - rest:get_count()
			left = left + rest:get_count()
		end
	end
	save_list(player, "stash", stash)
	return moved, left
end

local function finish_evac(name)
	local player = core.get_player_by_name(name)
	if not player then return end
	local moved, left = bank_inventory(player)
	local home = core.string_to_pos(player:get_meta():get_string("scavock_home"))
	if home then
		player:set_pos(vector.add(home, { x = 0, y = 0.5, z = 0 }))
	end
	local msg = ("Extracted. %d items banked to your stash."):format(moved)
	if left > 0 then
		msg = msg .. (" %d items didn't fit and are still on you."):format(left)
	end
	core.chat_send_player(name, msg .. " (/stash to view)")
end

-- ---------------------------------------------------------------------------
-- The evac STRUCTURE (§21, D1). An evac is a set of required blocks:
-- a CONSOLE (lever), a SKY BEACON, and 4 TRAPDOORS — the doc's own
-- candidate list (open #1, smallest reversible). "Connected" is proximity
-- to the console (open #2 answered as adjacency, not wiring — reversible).
--
-- Sequence (§21 confirmed):
--   1. Pull the console lever to activate.
--   2. The beacon lights RED, transitioning toward GREEN as evac progresses.
--   3. BLUE when ready — the 4 trapdoors open.
--   4. Players drop inside; someone pulls the lever again to CLOSE it,
--      sending everyone inside to extraction. Closing early — before a
--      straggler makes it in — is fully possible, on purpose. Preserved
--      exactly: the lever answers to whoever pulls it.
--
-- Broken is BINARY (D1): one or more required blocks missing = flat +X,
-- identical regardless of which or how many. No per-block scaling, ever.
-- Repairing mid-call clears the penalty (the derived rule). Between calls:
-- a cooldown, and nothing else. Sabotage delays but never cancels.
-- ---------------------------------------------------------------------------

local CALL_TIME = 30        -- seconds from activation to ready (tuning)
local BROKEN_X = 20         -- open #4: flat extra time while broken
local COOLDOWN = 120        -- open #3: per-evac (tuning)
local STRUCT_RADIUS = 6

local calls = {}  -- console hash -> { pos, phase, elapsed, t }

local function survey(console_pos)
	local minp = vector.subtract(console_pos, STRUCT_RADIUS)
	local maxp = vector.add(console_pos, STRUCT_RADIUS)
	local beacons = core.find_nodes_in_area(minp, maxp, {
		"scavock_evac:beacon", "scavock_evac:beacon_red",
		"scavock_evac:beacon_green", "scavock_evac:beacon_blue" })
	local doors = core.find_nodes_in_area(minp, maxp, {
		"scavock_evac:trapdoor", "scavock_evac:trapdoor_open" })
	return beacons, doors
end

local function is_broken(console_pos)
	local beacons, doors = survey(console_pos)
	return #beacons < 1 or #doors < 4
end

local function set_beacons(console_pos, state)
	local beacons = survey(console_pos)
	for _, pos in ipairs(beacons) do
		core.swap_node(pos, { name = "scavock_evac:beacon" .. state })
	end
end

local function set_doors(console_pos, open)
	local _, doors = survey(console_pos)
	for _, pos in ipairs(doors) do
		core.swap_node(pos, { name = open and "scavock_evac:trapdoor_open"
			or "scavock_evac:trapdoor" })
	end
end

local function extract_players_inside(console_pos)
	local _, doors = survey(console_pos)
	local n = 0
	for _, player in ipairs(core.get_connected_players()) do
		local ppos = player:get_pos()
		for _, dpos in ipairs(doors) do
			if math.abs(ppos.x - dpos.x) < 1.2
					and math.abs(ppos.z - dpos.z) < 1.2
					and ppos.y < dpos.y + 0.5 and ppos.y > dpos.y - 4 then
				finish_evac(player:get_player_name())
				n = n + 1
				break
			end
		end
	end
	return n
end

local function call_tick(hash)
	local call = calls[hash]
	if not call then return end
	local broken = is_broken(call.pos)

	if call.phase == "charging" then
		-- flat +X while broken (D1); repairing mid-call clears it, so the
		-- target recomputes from the CURRENT state every tick
		local target = broken and (CALL_TIME + BROKEN_X) or CALL_TIME
		call.elapsed = call.elapsed + 1
		local progress = call.elapsed / target
		if progress >= 1 then
			call.phase = "open"
			call.t = 25
			set_beacons(call.pos, "_blue")
			set_doors(call.pos, true)
			core.get_meta(call.pos):set_string("infotext",
				"Evac console — OPEN. Get inside; the lever closes it.")
		elseif progress >= 0.6 then
			set_beacons(call.pos, "_green")
		end
		core.after(1, call_tick, hash)
		return
	end

	if call.phase == "open" then
		call.t = call.t - 1
		if call.t <= 0 then
			extract_players_inside(call.pos)
			set_doors(call.pos, false)
			set_beacons(call.pos, "")
			core.get_meta(call.pos):set_int("cooldown_until",
				math.floor(core.get_gametime()) + COOLDOWN)
			core.get_meta(call.pos):set_string("infotext",
				"Evac console (recharging)")
			calls[hash] = nil
			return
		end
		core.after(1, call_tick, hash)
	end
end

core.register_node("scavock_evac:console", {
	description = "Evac Console (required block — pull the lever)",
	tiles = { "scavock_console.png" },
	paramtype2 = "facedir",
	light_source = 4,
	groups = { cracky = 1, evac = 1 },
	on_construct = function(pos)
		core.get_meta(pos):set_string("infotext",
			"Evac console — pull the lever (right-click) to call")
	end,
	on_rightclick = function(pos, node, clicker)
		local name = clicker:get_player_name()
		if scavock.downed[name] then
			core.chat_send_player(name, "You can't work a console while downed.")
			return
		end
		local hash = core.hash_node_position(pos)
		local call = calls[hash]

		if call and call.phase == "open" then
			-- THE LEVER: extracts everyone inside, strands everyone outside.
			-- Betrayal is a feature; preserve it exactly (§21).
			local n = extract_players_inside(pos)
			set_doors(pos, false)
			set_beacons(pos, "")
			core.get_meta(pos):set_int("cooldown_until",
				math.floor(core.get_gametime()) + COOLDOWN)
			core.get_meta(pos):set_string("infotext", "Evac console (recharging)")
			calls[hash] = nil
			core.chat_send_player(name,
				n > 0 and ("Doors closed. %d extracted."):format(n)
				or "Doors closed on nothing.")
			return
		end
		if call then
			core.chat_send_player(name, "Call already in progress.")
			return
		end

		local meta = core.get_meta(pos)
		local now = math.floor(core.get_gametime())
		if meta:get_int("cooldown_until") > now then
			core.chat_send_player(name, ("Recharging — %ds left.")
				:format(meta:get_int("cooldown_until") - now))
			return
		end
		local beacons, doors = survey(pos)
		if #beacons < 1 then
			core.chat_send_player(name,
				"No sky beacon connected. The structure needs one.")
			return
		end
		if #doors < 1 then
			core.chat_send_player(name,
				"No trapdoors at all. Place at least one (4 for an unbroken evac).")
			return
		end
		calls[hash] = { pos = pos, phase = "charging", elapsed = 0, t = 0 }
		set_beacons(pos, "_red")
		meta:set_string("infotext", "Evac console — call in progress")
		core.chat_send_player(name, is_broken(pos)
			and "Evac called. The structure is broken — it will take longer."
			or "Evac called. Watch the beacon: red, green, blue.")
		if scavock.noise then
			scavock.noise(pos, 30, name)
		end
		core.after(1, call_tick, hash)
	end,
})

local function beacon_node(suffix, color, light)
	core.register_node("scavock_evac:beacon" .. suffix, {
		description = "Sky Beacon (required block)"
			.. (suffix ~= "" and " — active" or ""),
		tiles = { "scavock_beacon_top.png" .. color,
			"scavock_beacon_side.png" .. color, "scavock_beacon_side.png" .. color },
		light_source = light,
		groups = { cracky = 1, evac = 1,
			not_in_creative_inventory = suffix ~= "" and 1 or nil },
		drop = "scavock_evac:beacon",
	})
end
beacon_node("", "", 8)
beacon_node("_red", "^[multiply:#B33A24", 12)
beacon_node("_green", "^[multiply:#7BA843", 13)
beacon_node("_blue", "^[multiply:#4A90D9", 14)

core.register_node("scavock_evac:trapdoor", {
	description = "Evac Trapdoor (required block x4)",
	drawtype = "nodebox",
	tiles = { "scavock_trapdoor.png" },
	paramtype = "light",
	node_box = { type = "fixed", fixed = { -0.5, 0.3, -0.5, 0.5, 0.5, 0.5 } },
	groups = { cracky = 2, evac = 1 },
})
core.register_node("scavock_evac:trapdoor_open", {
	description = "Evac Trapdoor (open)",
	drawtype = "nodebox",
	tiles = { "scavock_trapdoor.png" },
	paramtype = "light",
	walkable = false,
	node_box = { type = "fixed", fixed = { 0.35, 0.3, -0.5, 0.5, 0.5, 0.5 } },
	groups = { cracky = 2, not_in_creative_inventory = 1 },
	drop = "scavock_evac:trapdoor",
})

-- constructed evacs (§14/§21): every required block is craftable; every
-- evac is fully open — no ownership, no locks
core.register_craft({ output = "scavock_evac:console",
	recipe = { { "scavock_core:copper_ingot", "scavock_core:steel_ingot" },
		{ "scavock_power:wire", "scavock_core:iron_ingot" } } })
core.register_craft({ output = "scavock_evac:beacon",
	recipe = { { "scavock_core:copper_ingot", "scavock_core:titanium_ingot" },
		{ "scavock_core:steel_ingot", "scavock_core:steel_ingot" } } })
core.register_craft({ output = "scavock_evac:trapdoor 2",
	recipe = { { "scavock_core:iron_ingot", "scavock_core:iron_ingot" },
		{ "scavock_core:planks", "scavock_core:planks" } } })

-- ---------------------------------------------------------------------------
-- Worldgen evac stations: full structure, with a chance of generating
-- BROKEN — the damage roll removes actual trapdoor blocks so the player
-- can see what to replace (§4)
-- ---------------------------------------------------------------------------
local function make_station()
	local sx, sy, sz = 7, 4, 7
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
			set(x, 0, z, "scavock_core:concrete", 255, true)
		end
	end
	set(2, 0, 2, "air", 255, true); set(3, 0, 2, "air", 255, true)
	set(2, 0, 3, "air", 255, true); set(3, 0, 3, "air", 255, true)
	set(2, 1, 2, "scavock_evac:trapdoor", 215, true)
	set(3, 1, 2, "scavock_evac:trapdoor", 215, true)
	set(2, 1, 3, "scavock_evac:trapdoor", 215, true)
	set(3, 1, 3, "scavock_evac:trapdoor", 215, true)
	set(5, 1, 5, "scavock_evac:console", 255, true)
	set(1, 1, 1, "scavock_core:concrete", 255, true)
	set(1, 2, 1, "scavock_evac:beacon", 255, true)
	return { size = { x = sx, y = sy, z = sz }, data = data }
end

core.register_decoration({
	name = "scavock_evac:station",
	deco_type = "schematic",
	place_on = { "scavock_core:dirt_with_grass", "scavock_core:dirt_with_dry_grass",
		"scavock_core:snowblock", "scavock_core:sand" },
	sidelen = 80,
	fill_ratio = 0.00002,
	biomes = { "grasslands", "plains", "savanna", "desert",
		"snowy_grasslands", "forest", "birch_forest", "pine_forest" },
	y_min = 4, y_max = 150,
	schematic = make_station(),
	place_offset_y = -1,
	flags = "place_center_x, place_center_z, force_placement",
})
