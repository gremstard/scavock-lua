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

local function channel_tick(name)
	local ch = channels[name]
	if not ch then return end
	local player = core.get_player_by_name(name)
	if not player or player:get_hp() <= 0 or scavock.downed[name] then
		channels[name] = nil
		return
	end
	if vector.distance(player:get_pos(), ch.pos) > CHANNEL_RADIUS then
		channels[name] = nil
		core.chat_send_player(name, "Evac aborted — you moved away from the beacon.")
		return
	end
	ch.t = ch.t - 1
	if ch.t <= 0 then
		channels[name] = nil
		local meta = core.get_meta(ch.pos)
		meta:set_int("cooldown_until", math.floor(core.get_gametime()) + BEACON_COOLDOWN)
		meta:set_string("infotext",
			("Evac Beacon (recharging %ds)"):format(BEACON_COOLDOWN))
		finish_evac(name)
		return
	end
	core.chat_send_player(name, ("Evac in %d..."):format(ch.t))
	core.after(1, channel_tick, name)
end

core.register_node("scavock_evac:beacon", {
	description = "Evac Beacon",
	tiles = { "scavock_beacon_top.png", "scavock_beacon_side.png",
		"scavock_beacon_side.png" },
	light_source = 10,
	groups = { cracky = 1, evac = 1 },
	on_construct = function(pos)
		core.get_meta(pos):set_string("infotext",
			"Evac Beacon — right-click to extract (10s channel)")
	end,
	on_rightclick = function(pos, node, clicker)
		local name = clicker:get_player_name()
		if channels[name] then return end
		if scavock.downed[name] then
			core.chat_send_player(name, "You can't call an evac while downed.")
			return
		end
		local meta = core.get_meta(pos)
		local now = math.floor(core.get_gametime())
		local until_t = meta:get_int("cooldown_until")
		if until_t > now then
			core.chat_send_player(name,
				("Beacon recharging — %ds left."):format(until_t - now))
			return
		end
		meta:set_string("infotext",
			"Evac Beacon — right-click to extract (10s channel)")
		channels[name] = { pos = pos, t = CHANNEL_TIME }
		core.chat_send_player(name,
			("Evac call started. Stay within %d blocks for %d seconds.")
				:format(CHANNEL_RADIUS, CHANNEL_TIME))
		core.after(1, channel_tick, name)
	end,
})

core.register_on_leaveplayer(function(player)
	channels[player:get_player_name()] = nil
end)

-- ---------------------------------------------------------------------------
-- Evac stations stamped into the world: small concrete pad with a beacon.
-- Spread across every large open biome (§4 evac distribution).
-- ---------------------------------------------------------------------------
local function make_station()
	local sx, sy, sz = 5, 3, 5
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
	set(2, 1, 2, "scavock_evac:beacon", 255, true)
	set(0, 1, 0, "scavock_core:concrete_cracked", 180, true)
	set(4, 1, 4, "scavock_core:concrete_cracked", 180, true)
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
