-- Scavock biomes (§4 Confirmed roster, mapped onto mgv7 heat/humidity space).
-- Not yet here, recorded in README: Icelands (gated discovery biome),
-- Muvock, Cavock/underground biome chain, mutation spectrum overlays.

local function biome(def)
	def.node_stone = def.node_stone or "scavock_core:stone"
	def.node_riverbed = "scavock_core:sand"
	def.depth_riverbed = 2
	def.y_max = def.y_max or 31000
	core.register_biome(def)
end

-- Land biomes (y >= 4)
biome({ name = "grasslands",
	node_top = "scavock_core:dirt_with_grass", depth_top = 1,
	node_filler = "scavock_core:dirt", depth_filler = 3,
	y_min = 4, heat_point = 50, humidity_point = 45 })

-- Plains: flat-ish and bare — this is where abandoned cities are (§4)
biome({ name = "plains",
	node_top = "scavock_core:dirt_with_dry_grass", depth_top = 1,
	node_filler = "scavock_core:dirt", depth_filler = 3,
	y_min = 4, heat_point = 55, humidity_point = 22 })

biome({ name = "forest",
	node_top = "scavock_core:dirt_with_grass", depth_top = 1,
	node_filler = "scavock_core:dirt", depth_filler = 3,
	y_min = 4, heat_point = 58, humidity_point = 68 })

biome({ name = "birch_forest",
	node_top = "scavock_core:dirt_with_grass", depth_top = 1,
	node_filler = "scavock_core:dirt", depth_filler = 3,
	y_min = 4, heat_point = 40, humidity_point = 62 })

biome({ name = "pine_forest",
	node_top = "scavock_core:dirt_with_grass", depth_top = 1,
	node_filler = "scavock_core:dirt", depth_filler = 3,
	y_min = 4, heat_point = 28, humidity_point = 55 })

biome({ name = "snowy_grasslands",
	node_top = "scavock_core:snowblock", depth_top = 1,
	node_filler = "scavock_core:dirt", depth_filler = 2,
	node_water_top = "scavock_core:ice", depth_water_top = 1,
	y_min = 4, heat_point = 12, humidity_point = 35 })

biome({ name = "snowy_forest",
	node_top = "scavock_core:snowblock", depth_top = 1,
	node_filler = "scavock_core:dirt", depth_filler = 2,
	node_water_top = "scavock_core:ice", depth_water_top = 1,
	y_min = 4, heat_point = 10, humidity_point = 65 })

biome({ name = "desert",
	node_top = "scavock_core:sand", depth_top = 3,
	node_filler = "scavock_core:sand", depth_filler = 2,
	y_min = 4, heat_point = 88, humidity_point = 18 })

biome({ name = "savanna",
	node_top = "scavock_core:dirt_with_dry_grass", depth_top = 1,
	node_filler = "scavock_core:dirt", depth_filler = 3,
	y_min = 4, heat_point = 82, humidity_point = 45 })

biome({ name = "rainforest",
	node_top = "scavock_core:dirt_with_grass", depth_top = 1,
	node_filler = "scavock_core:dirt", depth_filler = 3,
	y_min = 4, heat_point = 85, humidity_point = 80 })

-- Mountains (§4/D17: stone surface, effectively treeless). mgv7 makes its own
-- high terrain; three registration points cover the heat range so high ground
-- reads as bare rock everywhere. (D17's climate-independent noise field is a
-- custom-mapgen feature; approximated here by altitude.)
for i, heat in ipairs({ 20, 50, 80 }) do
	biome({ name = "mountains_" .. i,
		node_top = "scavock_core:stone", depth_top = 1,
		node_filler = "scavock_core:stone", depth_filler = 2,
		y_min = 48, heat_point = heat, humidity_point = 50 })
end

-- Coast and ocean floor
for i, heat in ipairs({ 15, 50, 85 }) do
	biome({ name = "beach_" .. i,
		node_top = "scavock_core:sand", depth_top = 2,
		node_filler = "scavock_core:sand", depth_filler = 3,
		y_min = -8, y_max = 3, heat_point = heat, humidity_point = 50 })
end
biome({ name = "ocean",
	node_top = "scavock_core:sand", depth_top = 2,
	node_filler = "scavock_core:gravel", depth_filler = 2,
	y_min = -255, y_max = -9, heat_point = 50, humidity_point = 50 })

-- ---------------------------------------------------------------------------
-- Tree schematics (Lua tables; data ordered z-outer, y, x-inner)
-- ---------------------------------------------------------------------------
local function make_tree(trunk, leaves, height, radius)
	local sx = radius * 2 + 1
	local sy = height + radius + 1
	local sz = sx
	local data = {}
	for i = 1, sx * sy * sz do
		data[i] = { name = "air", prob = 0 }
	end
	local function set(x, y, z, name, prob, force)
		local i = ((z * sy) + y) * sx + x + 1
		data[i] = { name = name, prob = prob or 255, force_place = force }
	end
	local c = radius
	-- leaf blob around the crown
	local crown = height - 1
	for z = 0, sz - 1 do
		for y = crown, sy - 1 do
			for x = 0, sx - 1 do
				local d = math.abs(x - c) + math.abs(z - c) + math.abs(y - crown - 1)
				if d <= radius + 1 then
					set(x, y, z, leaves, d <= radius and 200 or 120)
				end
			end
		end
	end
	-- trunk
	for y = 0, height - 1 do
		set(c, y, c, trunk, 255, true)
	end
	return { size = { x = sx, y = sy, z = sz }, data = data }
end

local oak = make_tree("scavock_core:tree", "scavock_core:tree_leaves", 5, 2)
local pine = make_tree("scavock_core:pine_tree", "scavock_core:pine_tree_leaves", 7, 1)
local birch = make_tree("scavock_core:birch_tree", "scavock_core:birch_tree_leaves", 6, 1)

local function trees(biomes, schematic, ratio)
	core.register_decoration({
		deco_type = "schematic",
		place_on = { "scavock_core:dirt_with_grass", "scavock_core:snowblock" },
		sidelen = 16,
		fill_ratio = ratio,
		biomes = biomes,
		y_min = 4, y_max = 200,
		schematic = schematic,
		flags = "place_center_x, place_center_z",
	})
end

trees({ "forest" }, oak, 0.03)
trees({ "rainforest" }, oak, 0.06)
trees({ "grasslands" }, oak, 0.002)      -- scattered
trees({ "savanna" }, oak, 0.001)         -- sparse
trees({ "birch_forest" }, birch, 0.03)
trees({ "pine_forest" }, pine, 0.03)
trees({ "snowy_forest" }, pine, 0.025)

-- ---------------------------------------------------------------------------
-- Ores. Titanium is deep and rare — the ladder's discovery gate before
-- graphene's coal-volume gate.
-- ---------------------------------------------------------------------------
core.register_ore({
	ore_type = "scatter", ore = "scavock_core:stone_with_coal",
	wherein = "scavock_core:stone",
	clust_scarcity = 8 * 8 * 8, clust_num_ores = 8, clust_size = 3,
	y_min = -31000, y_max = 40,
})
core.register_ore({
	ore_type = "scatter", ore = "scavock_core:stone_with_iron",
	wherein = "scavock_core:stone",
	clust_scarcity = 11 * 11 * 11, clust_num_ores = 5, clust_size = 3,
	y_min = -31000, y_max = 8,
})
core.register_ore({
	ore_type = "scatter", ore = "scavock_core:stone_with_copper",
	wherein = "scavock_core:stone",
	clust_scarcity = 12 * 12 * 12, clust_num_ores = 5, clust_size = 3,
	y_min = -31000, y_max = 20,
})
core.register_ore({
	ore_type = "scatter", ore = "scavock_core:stone_with_titanium",
	wherein = "scavock_core:stone",
	clust_scarcity = 17 * 17 * 17, clust_num_ores = 4, clust_size = 3,
	y_min = -31000, y_max = -60,
})
