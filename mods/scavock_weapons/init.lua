-- Scavock weapon roster (§7 Confirmed: 5-20 fixed weapons, each a role not a
-- rank) crossed with the material ladder (§6). No firearms (§6 Confirmed).
--
-- TTK tuning (§7): player HP is 20. "Balance on time, not hits" — every form
-- targets roughly a 5-second kill window against an unarmoured player:
--   dagger  2 dmg @ 0.50s  -> 10 hits, ~5.0s   (fast, wins on positioning)
--   sword   3 dmg @ 0.80s  ->  7 hits, ~5.6s   (balanced)
--   doubleaxe 4 dmg @ 1.00s -> 5 hits, ~5.0s   (chains, no recovery)
--   war axe 5 dmg @ 1.40s  ->  4 hits, ~5.6s   (big singles, slow)
--   spear   4 dmg @ 1.20s  ->  5 hits, ~6.0s   (reach 5.5 vs 4.0)
-- Material tier adds +0..+2 damage across five tiers — a gradual slope, so
-- top-tier vs unarmoured stays ~3x, never one-shot (§7 "gear compresses").

local forms = {
	{ id = "dagger", desc = "Dagger", fpi = 0.5, dmg = 2, range = 3.0,
		note = "Very fast, low damage. Wins through positioning and pressure." },
	{ id = "sword", desc = "Sword", fpi = 0.8, dmg = 3, range = 4.0,
		note = "Balanced swipe with a jab option." },
	{ id = "waraxe", desc = "War Axe", fpi = 1.4, dmg = 5, range = 4.0,
		note = "Strong single strikes with a recovery pull-back." },
	{ id = "doubleaxe", desc = "Double-Headed Axe", fpi = 1.0, dmg = 4, range = 4.0,
		note = "Chains left-to-right with no recovery. Poor at chopping." },
	{ id = "spear", desc = "Spear", fpi = 1.2, dmg = 4, range = 5.5,
		note = "Long reach. Weak in confined spaces." },
}

-- tier index -> bonus damage (gradual slope)
local tier_bonus = { scrap = 0, iron = 0, steel = 1, titanium = 1, graphene = 2 }

for _, m in ipairs(scavock.materials) do
	local ingot = "scavock_core:" .. m.name .. "_ingot"
	for _, f in ipairs(forms) do
		local caps = {
			full_punch_interval = f.fpi,
			damage_groups = { fleshy = f.dmg + tier_bonus[m.name] },
		}
		-- war axe can chop, badly (a weapon, not a tool — §6 separation)
		if f.id == "waraxe" then
			caps.groupcaps = { choppy = { times = { [3] = 3.0 }, uses = 60 } }
		end
		core.register_tool("scavock_weapons:" .. f.id .. "_" .. m.name, {
			description = m.desc .. " " .. f.desc .. "\n" .. f.note,
			inventory_image = "scavock_" .. f.id .. "_" .. m.name .. ".png",
			range = f.range,
			tool_capabilities = caps,
			groups = { weapon = 1 },
		})
	end

	core.register_craft({
		output = "scavock_weapons:dagger_" .. m.name,
		recipe = { { ingot }, { "scavock_core:stick" } },
	})
	core.register_craft({
		output = "scavock_weapons:sword_" .. m.name,
		recipe = { { ingot }, { ingot }, { "scavock_core:stick" } },
	})
	core.register_craft({
		output = "scavock_weapons:waraxe_" .. m.name,
		recipe = {
			{ ingot, ingot, "" },
			{ ingot, "scavock_core:stick", "" },
			{ "", "scavock_core:stick", "" },
		},
	})
	core.register_craft({
		output = "scavock_weapons:doubleaxe_" .. m.name,
		recipe = {
			{ ingot, "scavock_core:stick", ingot },
			{ ingot, "scavock_core:stick", ingot },
		},
	})
	core.register_craft({
		output = "scavock_weapons:spear_" .. m.name,
		recipe = { { ingot }, { "scavock_core:stick" }, { "scavock_core:stick" } },
	})
end

-- ---------------------------------------------------------------------------
-- Bow + arrows. §6 Confirmed: arrows are recoverable — a missed shot sticks
-- where it landed as a pickable item ("retrieval is a risk decision", "spent
-- arrows are evidence"). Projectile travel time, no hitscan.
-- ---------------------------------------------------------------------------
local ARROW_SPEED = 25
local ARROW_GRAVITY = 13
local ARROW_DAMAGE = 5

core.register_craftitem("scavock_weapons:arrow", {
	description = "Arrow (recoverable)",
	inventory_image = "scavock_arrow.png",
	groups = { scavock_arrow = 1 },
})

-- §17: effects are a SUPPLY decision — consumed on impact, the arrow
-- reverts to plain and stays recoverable. No enchanting; physical only.
local EFFECTS = {
	poison = { desc = "Poison Arrow (venom on hit; reverts to plain)",
		tex = "scavock_arrow_poison.png" },
	fire = { desc = "Fire Arrow (burns on hit; reverts to plain)",
		tex = "scavock_arrow_fire.png" },
	explosive = { desc = "Explosive Arrow (small blast; reverts to plain)",
		tex = "scavock_arrow_explosive.png" },
}
for id, e in pairs(EFFECTS) do
	core.register_craftitem("scavock_weapons:arrow_" .. id, {
		description = e.desc,
		inventory_image = e.tex,
		groups = { scavock_arrow = 1, ["arrow_" .. id] = 1 },
	})
end
core.register_craft({ type = "shapeless", output = "scavock_weapons:arrow_poison",
	recipe = { "scavock_weapons:arrow", "scavock_survival:berry_mut" } })
core.register_craft({ type = "shapeless", output = "scavock_weapons:arrow_fire",
	recipe = { "scavock_weapons:arrow", "scavock_power:oil" } })
core.register_craft({ type = "shapeless", output = "scavock_weapons:arrow_explosive",
	recipe = { "scavock_weapons:arrow", "scavock_boom:grenade" } })

core.register_craft({
	output = "scavock_weapons:arrow 4",
	recipe = {
		{ "scavock_core:scrap_ingot" },
		{ "scavock_core:stick" },
		{ "scavock_gear:feather" },
	},
})

core.register_entity("scavock_weapons:arrow_entity", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		visual = "item",
		visual_size = { x = 0.3, y = 0.3 },
		wield_item = "scavock_weapons:arrow",
		static_save = false,
	},
	_shooter = nil,
	_effect = nil,
	_damage = ARROW_DAMAGE,
	_life = 0,
	on_step = function(self, dtime, moveresult)
		local obj = self.object
		self._life = self._life + dtime
		if self._life > 20 then
			core.add_item(obj:get_pos(), "scavock_weapons:arrow")
			obj:remove()
			return
		end
		local pos = obj:get_pos()
		local last = self._last_pos or pos
		self._last_pos = pos

		local ray = core.raycast(last, pos, true, false)
		for hit in ray do
			if hit.type == "node" then
				if self._effect == "explosive" and scavock_boom then
					scavock_boom.explode(hit.intersection_point, 1, 8)
				end
				-- reverts to plain, stays recoverable (§17)
				core.add_item(hit.intersection_point, "scavock_weapons:arrow")
				obj:remove()
				return
			elseif hit.type == "object" and hit.ref ~= obj then
				local is_shooter = self._shooter
					and hit.ref:is_player()
					and hit.ref:get_player_name() == self._shooter
				if not is_shooter then
					local dmg = self._damage
					if self._effect == "fire" then dmg = dmg + 3 end
					hit.ref:punch(obj, 1.0, {
						full_punch_interval = 1.0,
						damage_groups = { fleshy = dmg },
					}, nil)
					if self._effect == "poison" and hit.ref:is_player()
							and scavock_survival then
						scavock_survival.venom(hit.ref, 6)
					elseif self._effect == "explosive" and scavock_boom then
						scavock_boom.explode(pos, 1, 6)
					end
					-- half of arrows survive a body hit, as plain arrows
					if math.random(2) == 1 then
						core.add_item(pos, "scavock_weapons:arrow")
					end
					obj:remove()
					return
				end
			end
		end
	end,
})

local function shoot(itemstack, user)
	if not user or not user:is_player() then return itemstack end
	if scavock.downed[user:get_player_name()] then return itemstack end
	-- the FIRST arrow stack found (hotbar, then Hands, then garments, in
	-- anchor order) is nocked — arrange your grids to choose what flies
	local effect, found
	scavock.p_each(user, function(pinv, list, i, st)
		if not found and core.get_item_group(st:get_name(), "scavock_arrow") > 0 then
			found = true
			effect = st:get_name():match("^scavock_weapons:arrow_(%a+)$")
			st:take_item()
			return st
		end
	end)
	if not found then
		core.chat_send_player(user:get_player_name(), "No arrows on you.")
		return itemstack
	end

	local pos = vector.add(user:get_pos(), { x = 0, y = 1.5, z = 0 })
	local dir = user:get_look_dir()
	local obj = core.add_entity(vector.add(pos, dir), "scavock_weapons:arrow_entity")
	if obj then
		obj:set_velocity(vector.multiply(dir, ARROW_SPEED))
		obj:set_acceleration({ x = 0, y = -ARROW_GRAVITY, z = 0 })
		obj:set_rotation({ x = -math.asin(dir.y), y = math.atan2(dir.x, dir.z), z = 0 })
		local ent = obj:get_luaentity()
		ent._shooter = user:get_player_name()
		ent._effect = effect
		if itemstack:get_name() == "scavock_weapons:bow_piercing" then
			ent._damage = ARROW_DAMAGE + 3
			obj:set_velocity(vector.multiply(dir, ARROW_SPEED * 1.3))
		end
	end
	itemstack:add_wear(65535 / 120) -- ~120 shots per bow
	return itemstack
end

core.register_tool("scavock_weapons:bow", {
	description = "Bow\nProjectile travel time, no hitscan. Arrows are recoverable.",
	inventory_image = "scavock_bow.png",
	on_use = shoot,
	on_secondary_use = shoot,
})

-- §17: bows upgrade STRUCTURALLY first (piercing), then carry effects
core.register_tool("scavock_weapons:bow_piercing", {
	description = "Piercing Bow\nStructural upgrade: harder, faster arrows.",
	inventory_image = "scavock_bow_piercing.png",
	on_use = shoot,
	on_secondary_use = shoot,
})
core.register_craft({ type = "shapeless", output = "scavock_weapons:bow_piercing",
	recipe = { "scavock_weapons:bow", "scavock_core:steel_ingot",
		"scavock_core:steel_ingot" } })

core.register_craft({
	output = "scavock_weapons:bow",
	recipe = {
		{ "", "scavock_core:stick", "scavock_core:stick" },
		{ "scavock_core:stick", "", "scavock_core:stick" },
		{ "", "scavock_core:stick", "scavock_core:stick" },
	},
})
