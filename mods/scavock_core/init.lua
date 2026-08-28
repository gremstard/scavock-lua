-- Scavock core: terrain nodes, material ladder items, workbench, furnace.
-- Design doc refs: §6 tool-gated progression + material ladder, §11 tiers,
-- D7 building blocks come from destroyed terrain / workbench / loot.

scavock = {}

-- Downed players (§12 two-stage death), keyed by player name. Owned by
-- scavock_death; read by movement, combat, weapons and evac to disable
-- verbs that a crawling player should not have.
scavock.downed = {}

scavock.materials = {
	-- name, description, tier index (weapons/tools scale off this)
	{ name = "scrap",    desc = "Scrap Metal" },
	{ name = "iron",     desc = "Iron" },
	{ name = "steel",    desc = "Steel" },
	{ name = "titanium", desc = "Titanium" },
	{ name = "graphene", desc = "Graphene" },
}

-- ---------------------------------------------------------------------------
-- The hand: deliberately weak fallback (§6 — "never a hard stop", but no
-- productive bare-hand gathering). Digs soft ground slowly, chops wood
-- painfully slowly, cannot touch stone at all.
-- ---------------------------------------------------------------------------
core.register_item(":", {
	type = "none",
	wield_image = "wieldhand.png",
	wield_scale = { x = 1, y = 1, z = 2.5 },
	tool_capabilities = {
		full_punch_interval = 1.0,
		max_drop_level = 0,
		groupcaps = {
			crumbly = { times = { [2] = 3.0, [3] = 1.8 }, uses = 0 },
			snappy  = { times = { [3] = 0.6 }, uses = 0 },
			choppy  = { times = { [3] = 14.0 }, uses = 0 }, -- fallback, painful
			oddly_breakable_by_hand = { times = { [1] = 6.0, [2] = 3.0, [3] = 1.0 }, uses = 0 },
		},
		damage_groups = { fleshy = 1 },
	},
})

-- ---------------------------------------------------------------------------
-- Terrain nodes
-- ---------------------------------------------------------------------------
core.register_node("scavock_core:stone", {
	description = "Stone",
	tiles = { "scavock_stone.png" },
	groups = { cracky = 3, stone = 1 },
})

core.register_node("scavock_core:dirt", {
	description = "Dirt",
	tiles = { "scavock_dirt.png" },
	groups = { crumbly = 3, soil = 1 },
})

core.register_node("scavock_core:dirt_with_grass", {
	description = "Grass Block",
	tiles = { "scavock_grass_top.png", "scavock_dirt.png", "scavock_grass_side.png" },
	groups = { crumbly = 3, soil = 1, grass_surface = 1 },
	drop = "scavock_core:dirt",
})

core.register_node("scavock_core:dirt_with_dry_grass", {
	description = "Dry Grass Block",
	tiles = { "scavock_dry_grass_top.png", "scavock_dirt.png", "scavock_dry_grass_side.png" },
	groups = { crumbly = 3, soil = 1, grass_surface = 1 },
	drop = "scavock_core:dirt",
})

core.register_node("scavock_core:sand", {
	description = "Sand",
	tiles = { "scavock_sand.png" },
	groups = { crumbly = 3 },
})

core.register_node("scavock_core:gravel", {
	description = "Gravel",
	tiles = { "scavock_gravel.png" },
	groups = { crumbly = 2 },
})

core.register_node("scavock_core:snowblock", {
	description = "Snow Block",
	tiles = { "scavock_snow.png" },
	groups = { crumbly = 3, cold = 1 },
})

core.register_node("scavock_core:ice", {
	description = "Ice",
	tiles = { "scavock_ice.png" },
	use_texture_alpha = "blend",
	paramtype = "light",
	groups = { cracky = 3, cold = 1, slippery = 3 },
})

core.register_node("scavock_core:water_source", {
	description = "Water",
	drawtype = "liquid",
	tiles = { "scavock_water.png" },
	use_texture_alpha = "blend",
	paramtype = "light",
	walkable = false, pointable = false, diggable = false, buildable_to = true,
	is_ground_content = false,
	drowning = 1,
	liquidtype = "source",
	liquid_alternative_flowing = "scavock_core:water_flowing",
	liquid_alternative_source = "scavock_core:water_source",
	liquid_viscosity = 1,
	post_effect_color = { a = 103, r = 30, g = 60, b = 90 },
	groups = { water = 3, liquid = 3 },
})

core.register_node("scavock_core:water_flowing", {
	description = "Flowing Water",
	drawtype = "flowingliquid",
	tiles = { "scavock_water.png" },
	special_tiles = { "scavock_water.png", "scavock_water.png" },
	use_texture_alpha = "blend",
	paramtype = "light", paramtype2 = "flowingliquid",
	walkable = false, pointable = false, diggable = false, buildable_to = true,
	is_ground_content = false,
	drowning = 1,
	liquidtype = "flowing",
	liquid_alternative_flowing = "scavock_core:water_flowing",
	liquid_alternative_source = "scavock_core:water_source",
	liquid_viscosity = 1,
	post_effect_color = { a = 103, r = 30, g = 60, b = 90 },
	groups = { water = 3, liquid = 3, not_in_creative_inventory = 1 },
})

-- Trees: three variants (§4 biome roster: forest / pine / birch)
local function register_tree(id, desc, side, top, leaftex, leafdesc)
	core.register_node("scavock_core:" .. id, {
		description = desc,
		tiles = { top, top, side },
		paramtype2 = "facedir",
		on_place = core.rotate_node,
		groups = { choppy = 2, tree = 1, flammable = 2 },
	})
	core.register_node("scavock_core:" .. id .. "_leaves", {
		description = leafdesc,
		drawtype = "allfaces_optional",
		tiles = { leaftex },
		paramtype = "light",
		waving = 1,
		walkable = false,
		groups = { snappy = 3, leafdecay = 3, leaves = 1, flammable = 2 },
	})
end
register_tree("tree", "Tree Trunk", "scavock_tree.png", "scavock_tree_top.png",
	"scavock_leaves.png", "Leaves")
register_tree("pine_tree", "Pine Trunk", "scavock_pine_tree.png", "scavock_pine_top.png",
	"scavock_pine_needles.png", "Pine Needles")
register_tree("birch_tree", "Birch Trunk", "scavock_birch_tree.png", "scavock_birch_top.png",
	"scavock_birch_leaves.png", "Birch Leaves")

core.register_node("scavock_core:planks", {
	description = "Planks",
	tiles = { "scavock_planks.png" },
	groups = { choppy = 2, oddly_breakable_by_hand = 3, flammable = 3 },
})

-- Ruin / city materials (§4 abandoned cities; D7 blocks from destroyed terrain)
core.register_node("scavock_core:concrete", {
	description = "Concrete",
	tiles = { "scavock_concrete.png" },
	groups = { cracky = 2 },
})
core.register_node("scavock_core:concrete_cracked", {
	description = "Cracked Concrete",
	tiles = { "scavock_concrete_cracked.png" },
	groups = { cracky = 3 },
	drop = "scavock_core:concrete",
})
core.register_node("scavock_core:debris", {
	description = "Debris Pile",
	tiles = { "scavock_debris.png" },
	groups = { crumbly = 2 },
	drop = {
		max_items = 2,
		items = {
			{ items = { "scavock_core:scrap_ingot" }, rarity = 3 },
			{ items = { "scavock_core:stick 2" }, rarity = 2 },
			{ items = { "scavock_core:gravel" } },
		},
	},
})

-- Ores
core.register_node("scavock_core:stone_with_coal", {
	description = "Coal Ore",
	tiles = { "scavock_coal_ore.png" },
	groups = { cracky = 3 },
	drop = "scavock_core:coal_lump",
})
core.register_node("scavock_core:stone_with_iron", {
	description = "Iron Ore",
	tiles = { "scavock_iron_ore.png" },
	groups = { cracky = 2 },
	drop = "scavock_core:iron_lump",
})
core.register_node("scavock_core:stone_with_titanium", {
	description = "Titanium Ore",
	tiles = { "scavock_titanium_ore.png" },
	groups = { cracky = 1 },
	drop = "scavock_core:titanium_lump",
})
core.register_node("scavock_core:coal_block", {
	description = "Coal Block",
	tiles = { "scavock_coal_block.png" },
	groups = { cracky = 3, flammable = 1 },
})

-- ---------------------------------------------------------------------------
-- Craftitems: lumps, ingots, sticks
-- ---------------------------------------------------------------------------
core.register_craftitem("scavock_core:coal_lump", {
	description = "Coal  (fuel — the economy's primary sink)",
	inventory_image = "scavock_coal_lump.png",
	groups = { coal = 1, flammable = 1 },
})
core.register_craftitem("scavock_core:iron_lump", {
	description = "Iron Lump (smelt it)",
	inventory_image = "scavock_iron_lump.png",
})
core.register_craftitem("scavock_core:titanium_lump", {
	description = "Titanium Lump (smelt it)",
	inventory_image = "scavock_titanium_lump.png",
})
for _, m in ipairs(scavock.materials) do
	core.register_craftitem("scavock_core:" .. m.name .. "_ingot", {
		description = m.desc .. " Ingot",
		inventory_image = "scavock_" .. m.name .. "_ingot.png",
	})
end
core.register_craftitem("scavock_core:leather", {
	description = "Leather (from animals — the ladder's first rung)",
	inventory_image = "scavock_leather.png",
})
core.register_craftitem("scavock_core:stick", {
	description = "Stick",
	inventory_image = "scavock_stick.png",
	groups = { stick = 1, flammable = 2 },
})

-- ---------------------------------------------------------------------------
-- Basic recipes (crafted at the workbench — there is no pocket crafting)
-- ---------------------------------------------------------------------------
core.register_craft({ output = "scavock_core:planks 4", recipe = {{ "group:tree" }} })
core.register_craft({ output = "scavock_core:stick 4", recipe = {{ "scavock_core:planks" }} })
core.register_craft({
	output = "scavock_core:workbench",
	recipe = {
		{ "scavock_core:planks", "scavock_core:planks" },
		{ "scavock_core:planks", "scavock_core:planks" },
	},
})
core.register_craft({
	output = "scavock_core:furnace",
	recipe = {
		{ "scavock_core:stone", "scavock_core:stone", "scavock_core:stone" },
		{ "scavock_core:stone", "",                   "scavock_core:stone" },
		{ "scavock_core:stone", "scavock_core:stone", "scavock_core:stone" },
	},
})
core.register_craft({
	output = "scavock_core:coal_block",
	recipe = {
		{ "scavock_core:coal_lump", "scavock_core:coal_lump", "scavock_core:coal_lump" },
		{ "scavock_core:coal_lump", "scavock_core:coal_lump", "scavock_core:coal_lump" },
		{ "scavock_core:coal_lump", "scavock_core:coal_lump", "scavock_core:coal_lump" },
	},
})
-- Steel: iron worked with coal (stand-in for a proper alloying step)
core.register_craft({
	type = "shapeless",
	output = "scavock_core:steel_ingot",
	recipe = { "scavock_core:iron_ingot", "scavock_core:coal_lump", "scavock_core:coal_lump" },
})
-- Graphene: produced from coal (§11 — dedicated workbench deferred; this is the
-- placeholder recipe until that workbench is specified)
core.register_craft({
	output = "scavock_core:graphene_ingot",
	recipe = {
		{ "scavock_core:coal_block", "scavock_core:coal_block", "scavock_core:coal_block" },
		{ "scavock_core:coal_block", "scavock_core:titanium_ingot", "scavock_core:coal_block" },
		{ "scavock_core:coal_block", "scavock_core:coal_block", "scavock_core:coal_block" },
	},
})

-- Smelting
core.register_craft({ type = "cooking", output = "scavock_core:iron_ingot",
	recipe = "scavock_core:iron_lump", cooktime = 4 })
core.register_craft({ type = "cooking", output = "scavock_core:titanium_ingot",
	recipe = "scavock_core:titanium_lump", cooktime = 10 })
-- Fuels (§6: fuel is the game's primary consumable sink)
core.register_craft({ type = "fuel", recipe = "scavock_core:coal_lump", burntime = 30 })
core.register_craft({ type = "fuel", recipe = "scavock_core:coal_block", burntime = 290 })
core.register_craft({ type = "fuel", recipe = "group:tree", burntime = 24 })
core.register_craft({ type = "fuel", recipe = "scavock_core:planks", burntime = 8 })
core.register_craft({ type = "fuel", recipe = "scavock_core:stick", burntime = 2 })

-- ---------------------------------------------------------------------------
-- Workbench: the only 3x3 craft surface (§6 "workbench tools" gate)
-- ---------------------------------------------------------------------------
local wb_formspec = table.concat({
	"formspec_version[6]", "size[10.7,12.1]",
	"label[0.4,0.5;Workbench]",
	"list[context;craft;0.4,0.9;3,3;]",
	"image[4.5,2.2;0.8,0.8;scavock_stick.png^[transformR270]",
	"list[context;output;5.6,2.2;1,1;]",
	"list[current_player;main;0.4,5.4;8,6;]",
	"listring[context;craft]", "listring[current_player;main]",
	"listring[context;output]", "listring[current_player;main]",
})

local function wb_update_output(pos)
	local inv = core.get_meta(pos):get_inventory()
	local result = core.get_craft_result({
		method = "normal", width = 3, items = inv:get_list("craft"),
	})
	inv:set_stack("output", 1, result.item)
end

core.register_node("scavock_core:workbench", {
	description = "Workbench",
	tiles = { "scavock_workbench_top.png", "scavock_planks.png", "scavock_workbench_side.png" },
	groups = { choppy = 2, oddly_breakable_by_hand = 2 },
	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_string("formspec", wb_formspec)
		meta:set_string("infotext", "Workbench")
		local inv = meta:get_inventory()
		inv:set_size("craft", 9)
		inv:set_size("output", 1)
	end,
	can_dig = function(pos)
		return core.get_meta(pos):get_inventory():is_empty("craft")
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack)
		if listname == "output" then return 0 end
		return stack:get_count()
	end,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count)
		if to_list == "output" then return 0 end
		return count
	end,
	on_metadata_inventory_put = function(pos) wb_update_output(pos) end,
	on_metadata_inventory_move = function(pos) wb_update_output(pos) end,
	on_metadata_inventory_take = function(pos, listname)
		if listname == "output" then
			-- consume one round of inputs
			local inv = core.get_meta(pos):get_inventory()
			local result, decremented = core.get_craft_result({
				method = "normal", width = 3, items = inv:get_list("craft"),
			})
			if not result.item:is_empty() then
				-- output was taken while inputs still form a recipe: this take
				-- happened before consumption; consume now
				inv:set_list("craft", decremented.items)
			else
				-- inputs already consumed or no recipe; just refresh
			end
			wb_update_output(pos)
		else
			wb_update_output(pos)
		end
	end,
})

-- ---------------------------------------------------------------------------
-- Furnace (compact node-timer implementation)
-- ---------------------------------------------------------------------------
local function furnace_formspec(fuel_pct, item_pct)
	return table.concat({
		"formspec_version[6]", "size[10.7,12.1]",
		"label[0.4,0.5;Furnace]",
		"list[context;src;3.2,0.9;1,1;]",
		"label[3.25,2.6;Fuel " .. ("%d%%"):format(fuel_pct) .. "]",
		"list[context;fuel;3.2,3.3;1,1;]",
		"label[4.9,2.05;→ " .. ("%d%%"):format(item_pct) .. "]",
		"list[context;dst;5.9,1.5;2,2;]",
		"list[current_player;main;0.4,5.4;8,6;]",
		"listring[context;dst]", "listring[current_player;main]",
		"listring[context;src]", "listring[current_player;main]",
		"listring[context;fuel]", "listring[current_player;main]",
	})
end

local function furnace_set(pos, active, fuel_pct, item_pct)
	local meta = core.get_meta(pos)
	meta:set_string("formspec", furnace_formspec(fuel_pct, item_pct))
	meta:set_string("infotext", active and "Furnace (active)" or "Furnace")
	local want = active and "scavock_core:furnace_active" or "scavock_core:furnace"
	local node = core.get_node(pos)
	if node.name ~= want then
		node.name = want
		core.swap_node(pos, node)
	end
end

local function furnace_timer(pos, elapsed)
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()
	local fuel_time = meta:get_float("fuel_time")
	local fuel_total = meta:get_float("fuel_total")
	local src_time = meta:get_float("src_time")

	local srclist = inv:get_list("src")
	local cooked, aftercooked = core.get_craft_result({
		method = "cooking", width = 1, items = srclist,
	})
	local cookable = cooked.time ~= 0

	if fuel_time > 0 then
		fuel_time = fuel_time - elapsed
		if cookable then
			src_time = src_time + elapsed
			if src_time >= cooked.time then
				if inv:room_for_item("dst", cooked.item) then
					inv:add_item("dst", cooked.item)
					inv:set_list("src", aftercooked.items)
				end
				src_time = 0
			end
		else
			src_time = 0
		end
	end

	if fuel_time <= 0 and cookable then
		local fuel, afterfuel = core.get_craft_result({
			method = "fuel", width = 1, items = inv:get_list("fuel"),
		})
		if fuel.time > 0 then
			inv:set_list("fuel", afterfuel.items)
			fuel_time = fuel.time
			fuel_total = fuel.time
		end
	end

	meta:set_float("fuel_time", math.max(fuel_time, 0))
	meta:set_float("fuel_total", fuel_total)
	meta:set_float("src_time", src_time)

	local active = fuel_time > 0
	local fuel_pct = fuel_total > 0 and math.floor(fuel_time / fuel_total * 100) or 0
	local item_pct = (cookable and cooked.time > 0)
		and math.floor(src_time / cooked.time * 100) or 0
	furnace_set(pos, active, fuel_pct, item_pct)
	return active or cookable
end

local furnace_def = {
	description = "Furnace",
	tiles = { "scavock_furnace_side.png", "scavock_furnace_side.png",
		"scavock_furnace_side.png", "scavock_furnace_side.png",
		"scavock_furnace_side.png", "scavock_furnace_front.png" },
	paramtype2 = "facedir",
	groups = { cracky = 2 },
	on_construct = function(pos)
		local inv = core.get_meta(pos):get_inventory()
		inv:set_size("src", 1)
		inv:set_size("fuel", 1)
		inv:set_size("dst", 4)
		furnace_set(pos, false, 0, 0)
	end,
	can_dig = function(pos)
		local inv = core.get_meta(pos):get_inventory()
		return inv:is_empty("src") and inv:is_empty("fuel") and inv:is_empty("dst")
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack)
		if listname == "dst" then return 0 end
		if listname == "fuel" then
			local out = core.get_craft_result({ method = "fuel", width = 1,
				items = { stack } })
			return out.time > 0 and stack:get_count() or 0
		end
		return stack:get_count()
	end,
	on_metadata_inventory_put = function(pos)
		core.get_node_timer(pos):start(1.0)
	end,
	on_metadata_inventory_take = function(pos)
		core.get_node_timer(pos):start(1.0)
	end,
	on_timer = furnace_timer,
}
core.register_node("scavock_core:furnace", furnace_def)

local furnace_active_def = table.copy(furnace_def)
furnace_active_def.description = "Furnace (active)"
furnace_active_def.tiles[6] = "scavock_furnace_front_active.png"
furnace_active_def.light_source = 8
furnace_active_def.groups = { cracky = 2, not_in_creative_inventory = 1 }
furnace_active_def.drop = "scavock_core:furnace"
core.register_node("scavock_core:furnace_active", furnace_active_def)

-- ---------------------------------------------------------------------------
-- Grid inventory item sizes (§9: items occupy multiple cells based on size).
-- Anything not listed is 1x1. {w, h} in cells, unrotated.
-- ---------------------------------------------------------------------------
scavock.item_sizes = {
	["scavock_core:workbench"] = { 2, 2 },
	["scavock_core:furnace"] = { 2, 2 },
	["scavock_loot:crate"] = { 2, 2 },
	["scavock_weapons:bow"] = { 1, 3 },
}
for _, m in ipairs(scavock.materials) do
	scavock.item_sizes["scavock_tools:pick_" .. m.name] = { 2, 3 }
	scavock.item_sizes["scavock_tools:axe_" .. m.name] = { 2, 3 }
	scavock.item_sizes["scavock_weapons:dagger_" .. m.name] = { 1, 2 }
	scavock.item_sizes["scavock_weapons:sword_" .. m.name] = { 1, 3 }
	scavock.item_sizes["scavock_weapons:waraxe_" .. m.name] = { 2, 3 }
	scavock.item_sizes["scavock_weapons:doubleaxe_" .. m.name] = { 2, 3 }
	scavock.item_sizes["scavock_weapons:spear_" .. m.name] = { 1, 5 }
end

-- Size of an item by name, {w, h}. 1x1 unless registered above.
function scavock.item_size(name)
	local s = scavock.item_sizes[name]
	return s and { w = s[1], h = s[2] } or { w = 1, h = 1 }
end

-- ---------------------------------------------------------------------------
-- Mapgen aliases (required for mgv7 to know our nodes)
-- ---------------------------------------------------------------------------
core.register_alias("mapgen_stone", "scavock_core:stone")
core.register_alias("mapgen_water_source", "scavock_core:water_source")
core.register_alias("mapgen_river_water_source", "scavock_core:water_source")
core.register_alias("mapgen_sand", "scavock_core:sand")
core.register_alias("mapgen_cobble", "scavock_core:concrete_cracked")
