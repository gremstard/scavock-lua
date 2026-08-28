-- Creatures (§24 / D11 tier one: ordinary animals; §7 simplified model).
--
-- Confirmed rules honored here:
-- - Alive or dead. No downed state, no revives, no blocking (§7).
-- - No stagger — creatures take KNOCKBACK instead (§7).
-- - 2-3 behaviours each, nothing elaborate; "the threat is numbers and
--   expendability, not per-creature depth" (§7) — design effort goes into
--   spawn behaviour and pack dynamics.
-- - Grounded roster, instantly recognisable from real life (§2): wolves
--   (pack hunters), boars (neutral until provoked, then a charge), rats
--   (outpost scavengers that flee when hurt).
--
-- Box visuals: a single textured cube per animal. Deliberate — Scavock's
-- players are box rigs; a box wolf reads as a wolf in this world.

local DESPAWN_RANGE = 64
local DESPAWN_AFTER = 30

local function count_creatures_near(pos, radius)
	local n = 0
	for obj in core.objects_inside_radius(pos, radius) do
		local ent = obj:get_luaentity()
		if ent and ent._scavock_creature then
			n = n + 1
		end
	end
	return n
end

local function nearest_player(pos, range)
	local best, bestd
	for _, player in ipairs(core.get_connected_players()) do
		if player:get_hp() > 0 then
			local d = vector.distance(pos, player:get_pos())
			if d <= range and (not bestd or d < bestd) then
				best, bestd = player, d
			end
		end
	end
	return best, bestd
end

local function define_animal(name, def)
	core.register_entity("scavock_creatures:" .. name, {
		initial_properties = {
			physical = true,
			collide_with_objects = true,
			collisionbox = def.collisionbox,
			stepheight = 1.1,
			visual = "cube",
			visual_size = def.visual_size,
			textures = {
				def.tex, def.tex, def.tex_face, def.tex, def.tex, def.tex,
			},
			hp_max = def.hp,
			static_save = false,
		},
		_scavock_creature = true,

		on_activate = function(self)
			self.object:set_armor_groups({ fleshy = 100 })
			self.object:set_acceleration({ x = 0, y = -18, z = 0 })
			self._think = 0
			self._attack_cd = 0
			self._wander_t = 0
			self._away_t = 0
			self._provoked = false
		end,

		on_punch = function(self, puncher, time_from_last_punch,
				tool_capabilities, dir)
			-- knockback, the creature's version of stagger (§7)
			if dir then
				self.object:add_velocity({
					x = dir.x * 6, y = 4, z = dir.z * 6 })
			end
			self._provoked = true
			if def.flees_when_hurt then
				self._flee_until = (self._flee_until or 0) + 6
			end
			-- pack dynamics: hurting one wolf aggros the pack (§7 "numbers")
			if def.pack_alert and puncher and puncher:is_player() then
				local pos = self.object:get_pos()
				for obj in core.objects_inside_radius(pos, 12) do
					local ent = obj:get_luaentity()
					if ent and ent.name == self.name then
						ent._provoked = true
					end
				end
			end
		end,

		on_death = function(self)
			local pos = self.object:get_pos()
			for _, drop in ipairs(def.drops or {}) do
				if math.random() < drop.chance then
					core.add_item(pos, drop.item .. " "
						.. math.random(drop.min, drop.max))
				end
			end
		end,

		on_step = function(self, dtime)
			self._think = self._think + dtime
			self._attack_cd = math.max(0, self._attack_cd - dtime)
			if self._think < 0.4 then return end
			self._think = 0

			local obj = self.object
			local pos = obj:get_pos()

			-- despawn when nobody is around to be threatened
			local player, dist = nearest_player(pos, DESPAWN_RANGE)
			if not player then
				self._away_t = self._away_t + 0.4
				if self._away_t > DESPAWN_AFTER then
					obj:remove()
				end
				return
			end
			self._away_t = 0

			-- fleeing (rats)
			if self._flee_until and self._flee_until > 0 then
				self._flee_until = self._flee_until - 0.4
				local away = vector.direction(player:get_pos(), pos)
				obj:set_velocity({ x = away.x * def.run_speed,
					y = obj:get_velocity().y, z = away.z * def.run_speed })
				obj:set_yaw(math.atan2(away.z, away.x) + math.pi / 2)
				return
			end

			-- aggression: hostile animals hunt on sight, neutral ones only
			-- once provoked
			local aggressive = (def.hostile or self._provoked)
				and dist <= def.view_range

			if aggressive then
				local tpos = player:get_pos()
				local dir = vector.direction(pos, tpos)
				obj:set_yaw(math.atan2(dir.z, dir.x) + math.pi / 2)
				if dist > def.reach then
					obj:set_velocity({ x = dir.x * def.run_speed,
						y = obj:get_velocity().y, z = dir.z * def.run_speed })
				else
					obj:set_velocity({ x = 0, y = obj:get_velocity().y, z = 0 })
					if self._attack_cd <= 0 then
						self._attack_cd = def.attack_interval
						player:punch(obj, def.attack_interval, {
							full_punch_interval = def.attack_interval,
							damage_groups = { fleshy = def.damage },
						}, dir)
					end
				end
				return
			end

			-- wander
			self._wander_t = self._wander_t - 0.4
			if self._wander_t <= 0 then
				self._wander_t = math.random(2, 6)
				if math.random(2) == 1 then
					local a = math.random() * 2 * math.pi
					self._wander_dir = { x = math.cos(a), z = math.sin(a) }
				else
					self._wander_dir = nil
				end
			end
			if self._wander_dir then
				obj:set_velocity({ x = self._wander_dir.x * def.walk_speed,
					y = obj:get_velocity().y,
					z = self._wander_dir.z * def.walk_speed })
				obj:set_yaw(math.atan2(self._wander_dir.z, self._wander_dir.x)
					+ math.pi / 2)
			else
				obj:set_velocity({ x = 0, y = obj:get_velocity().y, z = 0 })
			end
		end,
	})
end

-- ---------------------------------------------------------------------------
-- The roster
-- ---------------------------------------------------------------------------
define_animal("wolf", {
	collisionbox = { -0.45, 0, -0.45, 0.45, 0.85, 0.45 },
	visual_size = { x = 0.9, y = 0.85, z = 1.3 },
	tex = "scavock_wolf.png", tex_face = "scavock_wolf_face.png",
	hp = 14, damage = 3, reach = 2.2, attack_interval = 1.2,
	view_range = 16, walk_speed = 1.5, run_speed = 5.5,
	hostile = true, pack_alert = true,
	drops = { { item = "scavock_core:leather", chance = 0.7, min = 1, max = 2 } },
})

define_animal("boar", {
	collisionbox = { -0.5, 0, -0.5, 0.5, 0.9, 0.5 },
	visual_size = { x = 1.0, y = 0.9, z = 1.5 },
	tex = "scavock_boar.png", tex_face = "scavock_boar_face.png",
	hp = 20, damage = 4, reach = 2.0, attack_interval = 1.6,
	view_range = 12, walk_speed = 1.2, run_speed = 6.5, -- the charge
	hostile = false, pack_alert = false,
	drops = { { item = "scavock_core:leather", chance = 0.9, min = 2, max = 3 },
		{ item = "scavock_survival:meat_raw", chance = 0.9, min = 1, max = 2 } },
})

define_animal("rat", {
	collisionbox = { -0.22, 0, -0.22, 0.22, 0.3, 0.22 },
	visual_size = { x = 0.45, y = 0.3, z = 0.7 },
	tex = "scavock_rat.png", tex_face = "scavock_rat_face.png",
	hp = 4, damage = 1, reach = 1.2, attack_interval = 1.0,
	view_range = 6, walk_speed = 2.0, run_speed = 4.0,
	hostile = true, pack_alert = false, flees_when_hurt = true,
	drops = { { item = "scavock_core:scrap_ingot", chance = 0.15, min = 1, max = 1 } },
})

-- ---------------------------------------------------------------------------
-- Spawning: near players but not on top of them, capped per area.
-- Wolves in forests and snow, boars on grass, rats in the ruins they
-- scavenge (concrete and debris — outposts come pre-infested).
-- ---------------------------------------------------------------------------
local function try_spawn(pos, entity, cap)
	local above = { x = pos.x, y = pos.y + 1, z = pos.z }
	if core.get_node(above).name ~= "air" then return end
	local _, dist = nearest_player(pos, 48)
	if not dist or dist < 12 then return end
	-- §12/§14: safe zones spawn no creatures; lit interiors are mob-proof
	if scavock.in_safe_zone and scavock.in_safe_zone(pos) then return end
	local light = core.get_node_light({ x = pos.x, y = pos.y + 1, z = pos.z }, nil)
	if light and light > 11 and core.get_node_light(
			{ x = pos.x, y = pos.y + 1, z = pos.z }, 0.5) ~= light then
		-- artificial light (brighter than the sun would make it): no spawn
		return end
	if count_creatures_near(pos, 24) >= cap then return end
	core.add_entity({ x = pos.x, y = pos.y + 1.5, z = pos.z },
		"scavock_creatures:" .. entity)
end

core.register_abm({
	label = "spawn wolves",
	nodenames = { "scavock_core:dirt_with_grass", "scavock_core:snowblock" },
	interval = 23, chance = 4200,
	action = function(pos)
		-- wolves arrive in twos and threes: the pack is the threat
		if math.random(3) > 1 then
			try_spawn(pos, "wolf", 4)
		end
		try_spawn({ x = pos.x + 2, y = pos.y, z = pos.z }, "wolf", 4)
	end,
})

core.register_abm({
	label = "spawn boars",
	nodenames = { "scavock_core:dirt_with_grass", "scavock_core:dirt_with_dry_grass" },
	interval = 29, chance = 5200,
	action = function(pos)
		try_spawn(pos, "boar", 3)
	end,
})

core.register_abm({
	label = "spawn rats",
	nodenames = { "scavock_core:concrete", "scavock_core:concrete_cracked",
		"scavock_core:debris" },
	interval = 17, chance = 260,
	action = function(pos)
		try_spawn(pos, "rat", 5)
	end,
})
