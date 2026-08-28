-- The discovery chain (§4b): find a Cavock -> find its ONE compass ->
-- follow it -> survive Icelands -> reach the futuristic city and The
-- Source. Every gate is discovery or endurance, never gear — the only
-- progression path that cannot be shortcut.
--
-- Mutation (§4/§25): a spectrum per-region, read from terrain color —
-- green -> chartreuse (mutated caves) -> orange (Cavock). Loot found in
-- mutated areas rolls 50/50 upgraded/downgraded PER ITEM (§25). If the
-- ground is wrong, what grows in it is wrong (§24.6).

scavock_under = {}

-- ---------------------------------------------------------------------------
-- Mutation field: seed-derived noise, stable for the world
-- ---------------------------------------------------------------------------
local mut_noise
core.register_on_mods_loaded(function()
	mut_noise = core.get_perlin({
		offset = 0, scale = 1, spread = { x = 400, y = 400, z = 400 },
		seed = 8811, octaves = 3, persistence = 0.6, lacunarity = 2.0,
	})
end)

function scavock.mutation_at(pos)
	if not mut_noise then return 0 end
	local v = mut_noise:get_2d({ x = pos.x, y = pos.z })
	return math.max(0, math.min(1, (v + 1) / 2))
end

-- visible mutation: grass slowly turns in high-mutation regions, and the
-- wrong flora grows there
core.register_node("scavock_under:dirt_with_mut_grass", {
	description = "Mutated Grass",
	tiles = { "scavock_mut_grass_top.png", "scavock_dirt.png",
		"scavock_grass_side.png" },
	groups = { crumbly = 3, soil = 1, grass_surface = 1, mutated = 1 },
	drop = "scavock_core:dirt",
})
core.register_node("scavock_under:stone_mut", {
	description = "Mutated Stone (chartreuse — §4 palette)",
	tiles = { "scavock_stone_mut.png" },
	groups = { cracky = 3, mutated = 1 },
})
core.register_node("scavock_under:stone_cavock", {
	description = "Cavock Stone (orange — §4 palette)",
	tiles = { "scavock_stone_cavock.png" },
	groups = { cracky = 3, mutated = 1 },
})

core.register_abm({
	label = "mutation creep",
	nodenames = { "scavock_core:dirt_with_grass" },
	interval = 43, chance = 900,
	action = function(pos)
		if scavock.mutation_at(pos) > 0.72 then
			core.swap_node(pos, { name = "scavock_under:dirt_with_mut_grass" })
			if math.random(4) == 1 then
				local above = { x = pos.x, y = pos.y + 1, z = pos.z }
				if core.get_node(above).name == "air" then
					core.set_node(above, { name = math.random(2) == 1
						and "scavock_survival:bush_mut"
						or "scavock_survival:shroom_mut" })
				end
			end
		end
	end,
})

-- §25: per-item 50/50 loot roll in mutated areas, hooked by scavock_loot
function scavock_under.mutate_stack(stack)
	if math.random(2) == 1 then
		-- upgraded
		if stack:get_stack_max() > 1 then
			stack:set_count(math.min(stack:get_stack_max(), stack:get_count() * 2))
		end
	else
		-- downgraded
		if stack:get_count() > 1 then
			stack:set_count(math.max(1, math.floor(stack:get_count() / 2)))
		elseif stack:get_stack_max() == 1 then
			stack:add_wear(20000)
		end
	end
	return stack
end

-- ---------------------------------------------------------------------------
-- Icelands: cannot be reached by exploration — its position derives from
-- the world seed, thousands of blocks out, and only the Cavock compass
-- points there (§4b). The city stamps itself when its area first generates.
-- ---------------------------------------------------------------------------
local ice_pos_cache
function scavock.icelands_pos()
	if ice_pos_cache then return ice_pos_cache end
	local seed = tonumber(core.get_mapgen_setting("seed")) or 0
	local angle = (seed % 628318) / 100000
	local dist = 4000 + (math.floor(seed / 1000) % 2000)
	ice_pos_cache = { x = math.floor(math.cos(angle) * dist),
		y = 8, z = math.floor(math.sin(angle) * dist) }
	return ice_pos_cache
end

local ICE_RADIUS = 220

local function in_icelands(pos)
	local ip = scavock.icelands_pos()
	return math.abs(pos.x - ip.x) < ICE_RADIUS
		and math.abs(pos.z - ip.z) < ICE_RADIUS
end

-- Icelands conditions (§4): brutal cold, no food at all. An expedition
-- destination, not territory. Cold bites through missing clothing.
local cold_t = 0
core.register_globalstep(function(dtime)
	cold_t = cold_t + dtime
	if cold_t < 8 then return end
	cold_t = 0
	for _, player in ipairs(core.get_connected_players()) do
		local pos = player:get_pos()
		if in_icelands(pos) and player:get_hp() > 0 then
			local clothed = scavock_gear
				and not scavock_gear.equipped(player, "top"):is_empty()
				and not scavock_gear.equipped(player, "bottoms"):is_empty()
				and not scavock_gear.equipped(player, "shoes"):is_empty()
				and not scavock_gear.equipped(player, "hat"):is_empty()
			local dmg = clothed and 1 or 3
			player:set_hp(player:get_hp() - dmg, { type = "set_hp", from = "mod" })
			core.chat_send_player(player:get_player_name(), clothed
				and "The cold gnaws through your gear."
				or "The cold is killing you. Cover every inch or leave.")
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Underground structure stamping (§4b): three rooms, difficulty is
-- FINDING, not fighting.
-- ---------------------------------------------------------------------------
core.register_craftitem("scavock_under:advtech", {
	description = "Advanced Technology (from The Source)\n"
		.. "Humanity's next generation, recovered. (Muvock: post-1.0.)",
	inventory_image = "scavock_advtech.png",
})

core.register_craftitem("scavock_under:compass_cavock", {
	description = "Cavock Compass\nAlways points to the nearest Icelands"
		.. " futuristic city. Permanent. Lootable. The server will know.",
	inventory_image = "scavock_compass_cavock.png",
	stack_max = 1,
})
-- preset flag so scavock_compass resolves it
core.register_on_mods_loaded(function()
	-- nothing needed: resolve() checks the preset meta below at fill time
end)

local function stamp_room(center, kind)
	local floor_y = center.y
	for dx = -3, 3 do
		for dz = -3, 3 do
			for dy = 0, 3 do
				local p = { x = center.x + dx, y = floor_y + dy, z = center.z + dz }
				if dy == 0 then
					core.set_node(p, { name =
						kind == "cavock" and "scavock_under:stone_cavock"
						or kind == "mutated" and "scavock_under:stone_mut"
						or "scavock_core:concrete_cracked" })
				elseif core.get_node(p).name ~= "air" then
					core.set_node(p, { name = "air" })
				end
			end
		end
	end
	local function crate_at(dx, dz, flag)
		local p = { x = center.x + dx, y = floor_y + 1, z = center.z + dz }
		core.set_node(p, { name = "scavock_loot:crate" })
		if flag then
			core.get_meta(p):set_string(flag, "1")
		end
	end
	if kind == "ruins" then
		-- ancient ruins: modest loot, easy to find (§4b tier 1)
		crate_at(-2, -2)
		core.set_node({ x = center.x + 2, y = floor_y + 1, z = center.z + 2 },
			{ name = "scavock_core:debris" })
		core.set_node({ x = center.x, y = floor_y + 1, z = center.z - 2 },
			{ name = "scavock_power:torch" })
	elseif kind == "mutated" then
		-- mutated caves: the dangerous mid tier, chartreuse
		crate_at(-2, 2, "mut_loot")
		crate_at(2, -2, "mut_loot")
		core.set_node({ x = center.x, y = floor_y + 1, z = center.z },
			{ name = "scavock_survival:shroom_mut" })
	elseif kind == "cavock" then
		-- Cavock: almost no enemies; the find IS the danger. Futuristic
		-- remains, and THE compass (one per Cavock, §4b confirmed)
		for dx = -3, 3, 2 do
			core.set_node({ x = center.x + dx, y = floor_y + 1, z = center.z - 3 },
				{ name = "scavock_under:tech" })
		end
		crate_at(-2, 0, "mut_loot")
		crate_at(2, 0, "cavock_compass")
	end
end

core.register_node("scavock_under:tech", {
	description = "Dead Technology",
	tiles = { "scavock_tech.png" },
	groups = { cracky = 2 },
	drop = "scavock_core:scrap_ingot",
})

-- find a cave floor inside the chunk and stamp
local function find_cave_spot(minp, maxp)
	for _ = 1, 12 do
		local x = math.random(minp.x + 4, maxp.x - 4)
		local z = math.random(minp.z + 4, maxp.z - 4)
		for y = maxp.y - 4, minp.y + 2, -1 do
			local p = { x = x, y = y, z = z }
			if core.get_node(p).name == "air"
					and core.get_node({ x = x, y = y - 1, z = z }).name
						== "scavock_core:stone" then
				return { x = x, y = y, z = z }
			end
		end
	end
	return nil
end

core.register_on_generated(function(minp, maxp, blockseed)
	-- Icelands city: stamps when its chunk generates
	local ip = scavock.icelands_pos()
	if ip.x >= minp.x and ip.x <= maxp.x and ip.z >= minp.z
			and ip.z <= maxp.z and ip.y >= minp.y and ip.y <= maxp.y then
		core.after(0.5, function()
			-- frozen futuristic city + The Source
			for dx = -10, 10 do
				for dz = -10, 10 do
					local y = ip.y
					core.set_node({ x = ip.x + dx, y = y - 1, z = ip.z + dz },
						{ name = "scavock_core:ice" })
					for dy = 0, 5 do
						core.set_node({ x = ip.x + dx, y = y + dy, z = ip.z + dz },
							{ name = "air" })
					end
				end
			end
			-- towers
			for _, off in ipairs({ { -6, -6 }, { 6, -6 }, { -6, 6 }, { 6, 6 } }) do
				for dy = 0, 6 do
					core.set_node({ x = ip.x + off[1], y = ip.y + dy, z = ip.z + off[2] },
						{ name = "scavock_under:ice_city" })
				end
			end
			-- The Source: core + guardians + the endgame loot
			core.set_node(ip, { name = "scavock_under:source" })
			for _, off in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }) do
				local p = { x = ip.x + off[1], y = ip.y, z = ip.z + off[2] }
				core.set_node(p, { name = "scavock_loot:crate" })
				core.get_meta(p):set_string("source_loot", "1")
			end
		end)
		return
	end

	if maxp.y > -24 then return end
	local rng = PcgRandom(blockseed)
	local roll = rng:next(1, 130)
	local kind
	if roll <= 9 then
		kind = "ruins"
	elseif roll <= 12 then
		kind = "mutated"
	elseif roll == 13 then
		kind = "cavock"
	end
	if not kind then return end
	core.after(0.5, function()
		local spot = find_cave_spot(minp, maxp)
		if spot then
			stamp_room(spot, kind)
		end
	end)
end)

core.register_node("scavock_under:ice_city", {
	description = "Frozen Alloy (Icelands city material)",
	tiles = { "scavock_ice_city.png" },
	groups = { cracky = 1 },
	drop = "scavock_core:titanium_ingot",
})

-- The Source: Yetis guard it (§24.9/§24.11 — inside the facility, not
-- roaming). It spawns them only when someone comes for it.
core.register_node("scavock_under:source", {
	description = "The Source\nWhere de-extinction went wrong. The end of"
		.. " the longest road in the game.",
	tiles = { "scavock_source.png" },
	light_source = 12,
	groups = { cracky = 1 },
	drop = "scavock_under:advtech",
})
core.register_abm({
	label = "the Source's guardians",
	nodenames = { "scavock_under:source" },
	interval = 11, chance = 2,
	action = function(pos)
		local n = 0
		local player_near = false
		for obj in core.objects_inside_radius(pos, 24) do
			if obj:is_player() then
				player_near = true
			else
				local ent = obj:get_luaentity()
				if ent and ent.name == "scavock_creatures:yeti" then
					n = n + 1
				end
			end
		end
		if player_near and n < 2 then
			core.add_entity({ x = pos.x + math.random(-4, 4), y = pos.y + 1,
				z = pos.z + math.random(-4, 4) }, "scavock_creatures:yeti")
		end
	end,
})
