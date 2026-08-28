-- Abandoned outposts (§4: "abandoned cities and outposts scattered across the
-- map as primary loot locations") built from world voxels, not meshes —
-- stamped into terrain at generation time, fully diggable/breachable (§4
-- Confirmed pipeline). Loot crates fill once, deterministically per position.

-- ---------------------------------------------------------------------------
-- Loot crate
-- ---------------------------------------------------------------------------
local LOOT_TABLE = {
	-- { item, weight, min, max }
	{ "scavock_core:scrap_ingot", 20, 1, 4 },
	{ "scavock_core:iron_ingot", 12, 1, 3 },
	{ "scavock_core:coal_lump", 16, 2, 6 },
	{ "scavock_weapons:arrow", 12, 4, 10 },
	{ "scavock_core:steel_ingot", 6, 1, 2 },
	{ "scavock_tools:pick_iron", 5, 1, 1 },
	{ "scavock_tools:axe_iron", 5, 1, 1 },
	{ "scavock_weapons:dagger_scrap", 4, 1, 1 },
	{ "scavock_weapons:sword_iron", 3, 1, 1 },
	{ "scavock_weapons:spear_iron", 3, 1, 1 },
	{ "scavock_weapons:bow", 3, 1, 1 },
	{ "scavock_survival:canteen", 5, 1, 1 },
	{ "scavock_survival:bandage", 8, 1, 3 },
	{ "scavock_survival:meat_cooked", 6, 1, 2 },
	{ "scavock_death:medkit", 8, 1, 2 },
	{ "scavock_death:stabiliser", 3, 1, 1 },
	{ "scavock_power:plastic", 8, 1, 3 },
	{ "scavock_power:oil", 5, 1, 2 },
	{ "scavock_core:copper_ingot", 6, 1, 3 },
	{ "scavock_gear:feather", 5, 1, 3 },
	{ "scavock_core:titanium_ingot", 1, 1, 1 },
}
local TOTAL_WEIGHT = 0
for _, e in ipairs(LOOT_TABLE) do TOTAL_WEIGHT = TOTAL_WEIGHT + e[2] end

local function roll(rng)
	local pick = rng:next(1, TOTAL_WEIGHT)
	for _, e in ipairs(LOOT_TABLE) do
		pick = pick - e[2]
		if pick <= 0 then
			return ItemStack(e[1] .. " " .. rng:next(e[3], e[4]))
		end
	end
end

function scavock_loot_fill_crate(pos)
	local meta = core.get_meta(pos)
	if meta:get_int("filled") == 1 then return end
	meta:set_int("filled", 1)
	local inv = meta:get_inventory()
	inv:set_size("main", 16)
	-- deterministic per world+position, so re-generation can't re-roll it
	local seed = core.hash_node_position(pos)
	local rng = PcgRandom(seed)

	-- The Source: the endgame haul (§4b: advanced technology, high tier)
	if meta:get_string("source_loot") == "1" then
		inv:add_item("main", "scavock_core:titanium_ingot "
			.. rng:next(2, 4))
		inv:add_item("main", "scavock_core:graphene_ingot "
			.. rng:next(1, 2))
		inv:add_item("main", "scavock_under:advtech")
		return
	end

	for _ = 1, rng:next(3, 6) do
		local stack = roll(rng)
		-- §25: per-item 50/50 upgraded/downgraded in mutated areas
		local mutated = meta:get_string("mut_loot") == "1"
			or (scavock.mutation_at and scavock.mutation_at(pos) > 0.62)
		if mutated and scavock_under then
			stack = scavock_under.mutate_stack(stack)
		end
		inv:add_item("main", stack)
	end

	-- the Cavock compass: ONE per Cavock, a named object the whole server
	-- will know about (§4b confirmed)
	if meta:get_string("cavock_compass") == "1" then
		local c = ItemStack("scavock_under:compass_cavock")
		c:get_meta():set_string("preset", "icelands")
		inv:add_item("main", c)
	end
end

core.register_node("scavock_loot:crate", {
	description = "Supply Crate",
	tiles = { "scavock_crate.png" },
	groups = { choppy = 2, oddly_breakable_by_hand = 2 },
	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_string("infotext", "Supply Crate")
		meta:set_string("formspec", table.concat({
			"formspec_version[6]", "size[10.7,11.2]",
			"label[0.4,0.5;Supply Crate]",
			"list[context;main;0.4,0.9;8,2;]",
			"list[current_player;main;0.4,4.2;8,6;]",
			"listring[context;main]", "listring[current_player;main]",
		}))
		meta:get_inventory():set_size("main", 16)
	end,
	on_rightclick = function(pos)
		scavock_loot_fill_crate(pos) -- lazy fill on first open
	end,
	can_dig = function(pos)
		local meta = core.get_meta(pos)
		return meta:get_int("filled") == 1
			and meta:get_inventory():is_empty("main")
	end,
})

-- ---------------------------------------------------------------------------
-- Outpost schematic: ragged concrete shell with a crate and debris inside.
-- yslice_prob erodes the upper walls so every stamp looks ruined differently.
-- ---------------------------------------------------------------------------
local function make_ruin()
	local sx, sy, sz = 9, 6, 9
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
			-- floor slab
			set(x, 0, z, "scavock_core:concrete", 255, true)
			local wall = (x == 0 or x == sx - 1 or z == 0 or z == sz - 1)
			if wall then
				for y = 1, sy - 1 do
					local name = (y > 2) and "scavock_core:concrete_cracked"
						or "scavock_core:concrete"
					set(x, y, z, name, y > 3 and 140 or 220, true)
				end
			end
		end
	end
	-- doorway on one side
	set(4, 1, 0, "air", 255, true)
	set(4, 2, 0, "air", 255, true)
	-- interior: crate + debris
	set(2, 1, 6, "scavock_loot:crate", 255, true)
	set(6, 1, 2, "scavock_core:debris", 200, true)
	set(6, 1, 6, "scavock_core:debris", 140, true)
	set(2, 1, 2, "scavock_core:debris", 140, true)
	return {
		size = { x = sx, y = sy, z = sz },
		data = data,
		-- erode top slices at random per stamp
		yslice_prob = { { ypos = 4, prob = 160 }, { ypos = 5, prob = 90 } },
	}
end

core.register_decoration({
	name = "scavock_loot:outpost",
	deco_type = "schematic",
	place_on = { "scavock_core:dirt_with_dry_grass", "scavock_core:dirt_with_grass" },
	sidelen = 80,
	fill_ratio = 0.00012,           -- playtest: was too sparse
	biomes = { "plains", "savanna" }, -- cities sit on bare open ground (§4)
	y_min = 4, y_max = 120,
	schematic = make_ruin(),
	place_offset_y = -1,
	flags = "place_center_x, place_center_z, force_placement",
	rotation = "random",
})
