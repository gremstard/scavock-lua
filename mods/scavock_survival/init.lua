-- Survival needs & injury (§13).
--
-- Two meters, deliberately MILD: neither kills directly.
--   Low food  -> health regeneration slows, then stops.
--   Low water -> incoming damage increases by a small fraction.
-- Water comes from lakes and rivers; OCEAN water does not work (salt).
-- Any food fills the meter and occasionally restores a little HP.
--
-- Injury: falls can cause bleeding and broken legs; every hit carries a
-- bleed chance. Scaling per §13, WITH THE REQUIRED FLOOR/CAP — the doc
-- flags the raw scaling as a death spiral and requires that a careful
-- player can always claw back, so bleed chance is hard-capped and bleeding
-- always stops on its own eventually.

scavock_survival = {}

local MAX = 100
local FOOD_DRAIN = MAX / (45 * 60)   -- full -> empty in ~45 min
local WATER_DRAIN = MAX / (35 * 60)  -- ~35 min
local REGEN_FAST = 8                 -- s per HP when well fed
local REGEN_SLOW = 20                -- s per HP when hungry-ish
local THIRST_DMG_MULT = 1.15         -- low water: damage taken x1.15
local BLEED_INTERVAL = 5             -- s per bleed tick (1 damage)
local BLEED_MAX_TICKS = 10           -- bleeding always stops on its own (§13 floor)
local BLEED_CAP = 0.35               -- hard cap on any bleed chance (§13 required)
local LEG_MULT = 0.5                 -- broken leg speed multiplier

-- runtime state, persisted lazily in player meta
local st = {}

local function load_state(player)
	local name = player:get_player_name()
	local meta = player:get_meta()
	st[name] = {
		food = meta:get_float("sv_food"),
		water = meta:get_float("sv_water"),
		bleed = 0,
		leg = meta:get_int("sv_leg") == 1,
		huds = {},
		t_drain = 0, t_regen = 0, t_bleed = 0, t_save = 0,
	}
	if st[name].food <= 0 and meta:get_string("sv_init") == "" then
		meta:set_string("sv_init", "1")
		st[name].food, st[name].water = MAX, MAX
	end
	return st[name]
end

local function save_state(player)
	local s = st[player:get_player_name()]
	if not s then return end
	local meta = player:get_meta()
	meta:set_float("sv_food", s.food)
	meta:set_float("sv_water", s.water)
	meta:set_int("sv_leg", s.leg and 1 or 0)
end

function scavock.leg_mult(name)
	local s = st[name]
	return (s and s.leg) and LEG_MULT or 1.0
end

function scavock_survival.get(name)
	return st[name]
end

function scavock_survival.feed(player, food_amt, water_amt, hp_amt)
	local s = st[player:get_player_name()]
	if not s then return end
	s.food = math.min(MAX, s.food + (food_amt or 0))
	s.water = math.min(MAX, s.water + (water_amt or 0))
	if hp_amt and hp_amt > 0 then
		player:set_hp(math.min(player:get_hp() + hp_amt,
			player:get_properties().hp_max or 20), { type = "set_hp", from = "mod" })
	elseif hp_amt and hp_amt < 0 then
		player:set_hp(player:get_hp() + hp_amt, { type = "set_hp", from = "mod" })
	end
end

function scavock_survival.start_bleed(player)
	local s = st[player:get_player_name()]
	if s then
		s.bleed = BLEED_MAX_TICKS
	end
end

-- Megalania venom (§24.7): a consequence already inside you — DoT until
-- cured (med kit) or outlasted
function scavock_survival.venom(player, ticks)
	local s = st[player:get_player_name()]
	if s then
		s.venom = math.max(s.venom or 0, ticks)
	end
end

function scavock_survival.cure(player, what)
	local s = st[player:get_player_name()]
	if not s then return end
	if what == "bleed" or what == "all" then s.bleed = 0 end
	if what == "leg" or what == "all" then s.leg = false end
	if what == "venom" or what == "all" then s.venom = 0 end
end

-- ---------------------------------------------------------------------------
-- HUD: identity rule — meters appear only when below full, fade otherwise
-- ---------------------------------------------------------------------------
local function update_hud(player, s)
	local function bar(key, text, value, color)
		local show = value ~= nil
		if show and not s.huds[key] then
			s.huds[key] = player:hud_add({
				type = "text", position = { x = 0.06, y = 0.86 - (#text > 6 and 0 or 0) },
				offset = { x = 0, y = (key == "water" and 22 or 0) + (key == "status" and 44 or 0) },
				text = "", number = color, size = { x = 1 }, alignment = { x = 1, y = 0 },
			})
		end
		if s.huds[key] then
			if show then
				player:hud_change(s.huds[key], "text", text)
			else
				player:hud_remove(s.huds[key])
				s.huds[key] = nil
			end
		end
	end
	bar("food", s.food < MAX - 1 and ("FOOD  " .. math.floor(s.food) .. "%") or nil,
		s.food < MAX - 1 and s.food or nil, 0x9AA0AA)
	bar("water", s.water < MAX - 1 and ("WATER " .. math.floor(s.water) .. "%") or nil,
		s.water < MAX - 1 and s.water or nil, 0x9AA0AA)
	local status = {}
	if s.bleed > 0 then status[#status + 1] = "BLEEDING" end
	if s.venom and s.venom > 0 then status[#status + 1] = "VENOM" end
	if s.leg then status[#status + 1] = "BROKEN LEG" end
	bar("status", #status > 0 and table.concat(status, "  ") or nil,
		#status > 0 and 1 or nil, 0xB33A24)
end

-- ---------------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------------
core.register_globalstep(function(dtime)
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local s = st[name]
		if s and player:get_hp() > 0 then
			s.food = math.max(0, s.food - FOOD_DRAIN * dtime)
			s.water = math.max(0, s.water - WATER_DRAIN * dtime)

			-- regen tied to food (§13: low food slows regen)
			s.t_regen = s.t_regen + dtime
			local period = s.food > 60 and REGEN_FAST
				or (s.food > 25 and REGEN_SLOW or nil)
			if period and s.t_regen >= period and s.bleed <= 0
					and not scavock.downed[name] then
				s.t_regen = 0
				local hp_max = player:get_properties().hp_max or 20
				if player:get_hp() < hp_max then
					player:set_hp(player:get_hp() + 1, { type = "set_hp", from = "mod" })
				end
			end

			-- venom: DoT until cured or outlasted
			if s.venom and s.venom > 0 then
				s.t_venom = (s.t_venom or 0) + dtime
				if s.t_venom >= 4 then
					s.t_venom = 0
					s.venom = s.venom - 1
					player:set_hp(player:get_hp() - 1,
						{ type = "set_hp", from = "mod", bleed = true })
				end
			end

			-- bleeding: finite, always stops (§13 required floor)
			if s.bleed > 0 then
				s.t_bleed = s.t_bleed + dtime
				if s.t_bleed >= BLEED_INTERVAL then
					s.t_bleed = 0
					s.bleed = s.bleed - 1
					player:set_hp(player:get_hp() - 1,
						{ type = "set_hp", from = "mod", bleed = true })
				end
			end

			s.t_save = s.t_save + dtime
			if s.t_save > 5 then
				s.t_save = 0
				save_state(player)
				update_hud(player, s)
			end
		end
	end
end)

-- thirst raises incoming damage slightly (§13) — ordered damage filter
table.insert(scavock.damage_filters, function(player, hp_change, reason)
	if hp_change >= 0 then return hp_change end
	if reason and (reason.bleed or reason.from == "mod") then return hp_change end
	local s = st[player:get_player_name()]
	if s and s.water < 25 then
		return math.floor(hp_change * THIRST_DMG_MULT)
	end
	return hp_change
end)

-- hits can cause bleeding; falls can cause bleeding and broken legs (§13)
local function bleed_chance(player)
	local s = st[player:get_player_name()]
	if not s then return 0 end
	local chance = 0.12
	-- reinforcement lowers it drastically (§13); hook filled by scavock_gear
	if scavock.reinforcement_intact and scavock.reinforcement_intact(player) then
		chance = 0.03
	end
	local hp_max = player:get_properties().hp_max or 20
	if player:get_hp() < hp_max * 0.35 then chance = chance + 0.08 end
	if s.food < 25 then chance = chance + 0.05 end
	if s.water < 25 then chance = chance + 0.05 end
	return math.min(chance, BLEED_CAP) -- the required cap
end

core.register_on_punchplayer(function(player, hitter, tflp, caps, dir, damage)
	if damage and damage > 0 and player:get_hp() > 0 then
		if math.random() < bleed_chance(player) then
			scavock_survival.start_bleed(player)
			core.chat_send_player(player:get_player_name(), "You're bleeding.")
		end
	end
end)

core.register_on_player_hpchange(function(player, hp_change, reason)
	if reason and reason.type == "fall" and hp_change < 0 then
		local s = st[player:get_player_name()]
		if s then
			if math.random() < 0.35 then
				scavock_survival.start_bleed(player)
			end
			if hp_change <= -5 and math.random() < 0.4 and not s.leg then
				s.leg = true
				core.chat_send_player(player:get_player_name(),
					"Your leg is broken — splint it or limp home.")
			end
		end
	end
	return hp_change
end, true)

-- ---------------------------------------------------------------------------
-- Food and medical items
-- ---------------------------------------------------------------------------
local function edible(itemname, def)
	core.register_craftitem(itemname, {
		description = def.desc,
		inventory_image = def.image,
		on_use = function(itemstack, user)
			if not user then return itemstack end
			if def.poison then
				scavock_survival.feed(user, 0, 0, -def.poison)
				core.chat_send_player(user:get_player_name(),
					"Poisonous — if the ground is wrong, what grows in it is wrong.")
			else
				-- any food occasionally restores a little HP (§13)
				local hp = math.random(4) == 1 and 2 or 0
				scavock_survival.feed(user, def.food or 0, def.water or 0, hp)
			end
			itemstack:take_item()
			return itemstack
		end,
	})
end

edible("scavock_survival:meat_raw", { desc = "Raw Meat (better cooked)",
	image = "scavock_meat_raw.png", food = 12 })
edible("scavock_survival:meat_cooked", { desc = "Cooked Meat",
	image = "scavock_meat_cooked.png", food = 35 })
edible("scavock_survival:berry_surface", { desc = "Berries",
	image = "scavock_berry_surface.png", food = 8 })
edible("scavock_survival:berry_cave", { desc = "Cave Berries",
	image = "scavock_berry_cave.png", food = 8 })
edible("scavock_survival:berry_mut", { desc = "Mutated Berries",
	image = "scavock_berry_mut.png", poison = 4 })
edible("scavock_survival:mushroom_cave", { desc = "Cave Mushroom",
	image = "scavock_mushroom_cave.png", food = 10 })
edible("scavock_survival:mushroom_mut", { desc = "Mutated Mushroom",
	image = "scavock_mushroom_mut.png", poison = 4 })

core.register_craft({ type = "cooking", output = "scavock_survival:meat_cooked",
	recipe = "scavock_survival:meat_raw", cooktime = 4 })

core.register_craftitem("scavock_survival:bandage", {
	description = "Bandage (stops bleeding)",
	inventory_image = "scavock_bandage.png",
	on_use = function(itemstack, user)
		scavock_survival.cure(user, "bleed")
		core.chat_send_player(user:get_player_name(), "Bleeding stopped.")
		itemstack:take_item()
		return itemstack
	end,
})
core.register_craftitem("scavock_survival:splint", {
	description = "Splint (fixes a broken leg)",
	inventory_image = "scavock_splint.png",
	on_use = function(itemstack, user)
		scavock_survival.cure(user, "leg")
		core.chat_send_player(user:get_player_name(), "Leg splinted.")
		itemstack:take_item()
		return itemstack
	end,
})
core.register_craft({ type = "shapeless", output = "scavock_survival:bandage",
	recipe = { "scavock_core:tree_leaves", "scavock_core:tree_leaves" } })
core.register_craft({ type = "shapeless", output = "scavock_survival:splint",
	recipe = { "scavock_core:stick", "scavock_core:stick", "scavock_core:leather" } })

-- ---------------------------------------------------------------------------
-- Water: canteen fills from FRESH water only (§13 — ocean is salt)
-- ---------------------------------------------------------------------------
local function pointed_water(user)
	local eye = vector.add(user:get_pos(), { x = 0, y = 1.5, z = 0 })
	local tip = vector.add(eye, vector.multiply(user:get_look_dir(), 4))
	local ray = core.raycast(eye, tip, false, true)
	for hit in ray do
		if hit.type == "node" then
			local node = core.get_node(hit.under)
			local def = core.registered_nodes[node.name]
			if def and def.groups and def.groups.water then
				return (def.groups.fresh_water or 0) > 0
			end
		end
	end
	return nil
end

core.register_craftitem("scavock_survival:canteen", {
	description = "Canteen (empty) — fill from a lake or river",
	inventory_image = "scavock_canteen_empty.png",
	on_use = function(itemstack, user)
		local fresh = pointed_water(user)
		if fresh == nil then
			core.chat_send_player(user:get_player_name(), "Point at water to fill.")
			return itemstack
		end
		if not fresh then
			core.chat_send_player(user:get_player_name(),
				"Salt water. The ocean doesn't help.")
			return itemstack
		end
		return ItemStack("scavock_survival:canteen_full")
	end,
})
core.register_craftitem("scavock_survival:canteen_full", {
	description = "Canteen (water)",
	inventory_image = "scavock_canteen_full.png",
	on_use = function(itemstack, user)
		scavock_survival.feed(user, 0, 55, 0)
		return ItemStack("scavock_survival:canteen")
	end,
})
core.register_craft({
	output = "scavock_survival:canteen",
	recipe = { { "scavock_core:scrap_ingot", "scavock_core:scrap_ingot" },
		{ "scavock_core:scrap_ingot", "" } },
})

-- ---------------------------------------------------------------------------
-- Foraging flora (§24.6): berry bushes and mushrooms, no tool needed —
-- a fresh spawn can always eat
-- ---------------------------------------------------------------------------
local function bush(id, desc, tex, drop)
	core.register_node("scavock_survival:" .. id, {
		description = desc,
		drawtype = "allfaces_optional",
		tiles = { tex },
		paramtype = "light",
		walkable = false,
		groups = { snappy = 3, oddly_breakable_by_hand = 3, flammable = 2, flora = 1 },
		drop = drop .. " " .. 2,
	})
end
bush("bush_surface", "Berry Bush", "scavock_bush_surface.png",
	"scavock_survival:berry_surface")
bush("bush_cave", "Cave Berry Bush", "scavock_bush_cave.png",
	"scavock_survival:berry_cave")
bush("bush_mut", "Mutated Berry Bush", "scavock_bush_mut.png",
	"scavock_survival:berry_mut")

local function shroom(id, desc, tex, drop)
	core.register_node("scavock_survival:" .. id, {
		description = desc,
		drawtype = "plantlike",
		tiles = { tex },
		paramtype = "light",
		light_source = 2,
		walkable = false,
		groups = { snappy = 3, oddly_breakable_by_hand = 3, flora = 1, attached_node = 1 },
		drop = drop,
		selection_box = { type = "fixed", fixed = { -0.3, -0.5, -0.3, 0.3, 0.2, 0.3 } },
	})
end
shroom("shroom_cave", "Cave Mushroom", "scavock_mushroom_cave.png",
	"scavock_survival:mushroom_cave")
shroom("shroom_mut", "Mutated Mushroom", "scavock_mushroom_mut.png",
	"scavock_survival:mushroom_mut")

core.register_decoration({
	deco_type = "simple",
	place_on = { "scavock_core:dirt_with_grass" },
	sidelen = 16, fill_ratio = 0.004,
	biomes = { "grasslands", "forest", "birch_forest", "rainforest" },
	y_min = 4, y_max = 200,
	decoration = "scavock_survival:bush_surface",
})

-- cave flora grows in the dark underground over time
core.register_abm({
	label = "cave flora",
	nodenames = { "scavock_core:stone" },
	neighbors = { "air" },
	interval = 31, chance = 2600,
	action = function(pos)
		local above = { x = pos.x, y = pos.y + 1, z = pos.z }
		if pos.y > -10 or core.get_node(above).name ~= "air" then return end
		if core.get_node_light(above, 0.5) and core.get_node_light(above, 0.5) > 6 then
			return
		end
		core.set_node(above, { name = math.random(3) == 1
			and "scavock_survival:bush_cave" or "scavock_survival:shroom_cave" })
	end,
})

-- ---------------------------------------------------------------------------
-- Player lifecycle
-- ---------------------------------------------------------------------------
core.register_on_joinplayer(function(player)
	load_state(player)
end)
core.register_on_leaveplayer(function(player)
	save_state(player)
	st[player:get_player_name()] = nil
end)
core.register_on_respawnplayer(function(player)
	local s = st[player:get_player_name()]
	if s then
		s.food, s.water, s.bleed, s.leg = MAX, MAX, 0, false
		save_state(player)
	end
end)
core.register_on_dieplayer(function(player)
	local s = st[player:get_player_name()]
	if s then s.bleed = 0; s.venom = 0 end
end)

-- the med kit doubles as a field cure: bleeding + venom (§24.7 "cure")
core.override_item("scavock_death:medkit", {
	on_use = function(itemstack, user)
		scavock_survival.cure(user, "bleed")
		scavock_survival.cure(user, "venom")
		core.chat_send_player(user:get_player_name(),
			"Patched up — bleeding and venom cleared.")
		itemstack:take_item()
		return itemstack
	end,
})
