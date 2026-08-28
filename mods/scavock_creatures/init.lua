-- Creatures (§24, D11) — the full 1.0 roster.
--
-- Model (§7): alive or dead, KNOCKBACK not stagger, 2-3 behaviours each.
-- Universal rule (§24.3): COMMITMENT IS THE VULNERABILITY WINDOW — a
-- creature is untouchable while it has options and exposed while committed.
-- A hit landed during a telegraph or committed action INTERRUPTS it and
-- stuns the creature (§24.4: the weak-point rule, one rule for the whole
-- roster). Every creature is soloable; slow and risky, never impossible.
--
-- Tiers (§24.5): animals (Tuesday), extinct megafauna (this area is worse
-- than it looked), Man Eaters (you are prey), cryptids (leave).

scavock_creatures = {}

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

local function walk(obj, dir, speed)
	obj:set_velocity({ x = dir.x * speed, y = obj:get_velocity().y,
		z = dir.z * speed })
	obj:set_yaw(math.atan2(dir.z, dir.x) + math.pi / 2)
end

local function stand(obj)
	obj:set_velocity({ x = 0, y = obj:get_velocity().y, z = 0 })
end

scavock_creatures.helpers = {
	nearest_player = nearest_player,
	count_creatures_near = count_creatures_near,
	walk = walk,
	stand = stand,
}

-- ---------------------------------------------------------------------------
-- The framework
-- ---------------------------------------------------------------------------
function scavock_creatures.define(name, def)
	scavock_creatures["def_" .. name] = def
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
			static_save = def.persistent or false,
		},
		_scavock_creature = true,
		_def = def,

		-- §8: creatures hear
		_hears = function(self, pos, radius, source_name)
			if def.passive or def.flees_on_sight or def.flees_when_hurt then
				self._flee_until = math.max(self._flee_until or 0, 3)
				return
			end
			if def.hostile or self._provoked then
				self._provoked = true
				self._noise_pos = pos
				self._noise_t = 8
			end
		end,

		get_staticdata = function(self)
			return core.serialize({ owner = self._owner, fed = self._fed })
		end,

		on_activate = function(self, staticdata)
			self.object:set_armor_groups({ fleshy = 100 })
			if not def.no_gravity then
				self.object:set_acceleration({ x = 0, y = -18, z = 0 })
			end
			self._think = 0
			self._attack_cd = 0
			self._wander_t = 0
			self._away_t = 0
			self._provoked = false
			self._stun = 0
			local data = staticdata ~= "" and core.deserialize(staticdata) or nil
			if data then
				self._owner = data.owner
				self._fed = data.fed
			end
			if def.on_spawn then def.on_spawn(self) end
		end,

		on_punch = function(self, puncher, time_from_last_punch,
				tool_capabilities, dir)
			-- §24.4: a hit during commitment interrupts it and stuns
			if self._tele or self._charging or self._committed then
				self._tele, self._charging, self._committed = nil, nil, nil
				self._stun = 2.2
				stand(self.object)
			end
			if dir and not def.no_knockback then
				self.object:add_velocity({ x = dir.x * 6, y = 4, z = dir.z * 6 })
			end
			if not def.passive then
				self._provoked = true
			end
			if def.flees_when_hurt or def.passive or def.flees_on_sight then
				self._flee_until = (self._flee_until or 0) + 6
			end
			if puncher and puncher:is_player() then
				self._target_name = puncher:get_player_name()
				if def.pack_alert then
					for obj in core.objects_inside_radius(self.object:get_pos(), 12) do
						local ent = obj:get_luaentity()
						if ent and ent.name == self.name then
							ent._provoked = true
							ent._target_name = self._target_name
						end
					end
				end
			end
			if def.on_punched then
				def.on_punched(self, puncher)
			end
		end,

		on_death = function(self, killer)
			local pos = self.object:get_pos()
			for _, drop in ipairs(def.drops or {}) do
				if math.random() < drop.chance then
					core.add_item(pos, drop.item .. " "
						.. math.random(drop.min, drop.max))
				end
			end
			if killer and killer:is_player() and scavock.noise then
				scavock.noise(pos, "kill", killer:get_player_name())
			end
		end,

		-- right-click: taming / feeding-for-breeding
		on_rightclick = function(self, clicker)
			local wield = clicker:get_wielded_item()
			if def.tame_item and not self._owner
					and wield:get_name() == def.tame_item then
				wield:take_item()
				clicker:set_wielded_item(wield)
				self._owner = clicker:get_player_name()
				core.chat_send_player(self._owner,
					name:gsub("^%l", string.upper) .. " tamed. It follows, it"
					.. " defends, and it can die for good — pets are permanent.")
			elseif def.breed_item and wield:get_name() == def.breed_item then
				wield:take_item()
				clicker:set_wielded_item(wield)
				self._fed = true
				-- two fed animals near each other breed (§24.6 livestock)
				for obj in core.objects_inside_radius(self.object:get_pos(), 4) do
					local ent = obj:get_luaentity()
					if ent and ent ~= self and ent.name == self.name and ent._fed then
						ent._fed, self._fed = nil, nil
						core.add_entity(self.object:get_pos(),
							"scavock_creatures:" .. name)
						break
					end
				end
			end
		end,

		on_step = function(self, dtime)
			self._think = self._think + dtime
			self._attack_cd = math.max(0, self._attack_cd - dtime)
			self._stun = math.max(0, (self._stun or 0) - dtime)

			-- charging runs at full tick rate: contact check
			if self._charging then
				self._charging.t = self._charging.t - dtime
				local pos = self.object:get_pos()
				for obj in core.objects_inside_radius(pos, def.reach + 0.5) do
					if obj:is_player() then
						obj:punch(self.object, 1.0, {
							full_punch_interval = 1.0,
							damage_groups = { fleshy = self._charging.damage },
						}, self._charging.dir)
						obj:add_velocity({ x = self._charging.dir.x * 8, y = 5,
							z = self._charging.dir.z * 8 })
						self._charging = nil
						self._stun = 1.5 -- recovery: the punish window
						stand(self.object)
						break
					end
				end
				if self._charging and self._charging.t <= 0 then
					self._charging = nil
					self._stun = 1.5
					stand(self.object)
				end
				return
			end

			if self._think < 0.4 then return end
			self._think = 0

			local obj = self.object
			local pos = obj:get_pos()

			if self._stun > 0 then
				stand(obj)
				return
			end

			-- despawn far from players (never tamed pets)
			local player, dist = nearest_player(pos, DESPAWN_RANGE)
			if not player then
				if not self._owner then
					self._away_t = self._away_t + 0.4
					if self._away_t > DESPAWN_AFTER then
						obj:remove()
					end
				end
				return
			end
			self._away_t = 0

			-- fully custom brains (Titanoboa, Megistotherium, Argentavis...)
			if def.custom_step and def.custom_step(self, player, dist) then
				return
			end

			-- telegraph -> charge (bear, boar, terror bird, glyptodon)
			if self._tele then
				self._tele = self._tele - 0.4
				stand(obj)
				if self._tele <= 0 then
					self._tele = nil
					local target = self._tele_target
						and core.get_player_by_name(self._tele_target)
					if target then
						local dir = vector.direction(pos, target:get_pos())
						self._charging = { dir = dir, t = def.commit_charge.time,
							damage = def.commit_charge.damage }
						obj:set_velocity({ x = dir.x * def.commit_charge.speed,
							y = obj:get_velocity().y,
							z = dir.z * def.commit_charge.speed })
						obj:set_yaw(math.atan2(dir.z, dir.x) + math.pi / 2)
					end
				end
				return
			end

			-- fleeing (deer, hurt rats, provoked passives)
			if self._flee_until and self._flee_until > 0 then
				self._flee_until = self._flee_until - 0.4
				walk(obj, vector.direction(player:get_pos(), pos), def.run_speed)
				return
			end
			if def.flees_on_sight and dist < def.view_range then
				self._flee_until = 3
				return
			end

			-- tamed pets: defend the owner, otherwise follow
			if self._owner then
				local owner = core.get_player_by_name(self._owner)
				local threat = self._target_name
					and core.get_player_by_name(self._target_name)
				if threat and threat:get_hp() > 0 and threat:get_player_name()
						~= self._owner
						and vector.distance(pos, threat:get_pos()) < 14 then
					player, dist = threat, vector.distance(pos, threat:get_pos())
					-- fall through to the attack branch below
				elseif owner then
					local od = vector.distance(pos, owner:get_pos())
					-- the dog's early warning (§24.6)
					if def.alerts and math.random(6) == 1 then
						for aobj in core.objects_inside_radius(pos, 14) do
							local ent = aobj:get_luaentity()
							if ent and ent._scavock_creature and ent._def
									and ent._def.hostile then
								core.chat_send_player(self._owner,
									"Your " .. name .. " growls at something nearby.")
								break
							end
						end
					end
					if od > 4 then
						walk(obj, vector.direction(pos, owner:get_pos()),
							od > 10 and def.run_speed or def.walk_speed)
					else
						stand(obj)
					end
					return
				else
					stand(obj)
					return
				end
			end

			if not def.passive then
				-- boar face-aggro (§24.6): lock eyes and it commits
				if def.face_aggro and not self._provoked and dist < 6 then
					local look = player:get_look_dir()
					local to_me = vector.direction(player:get_pos(), pos)
					if look.x * to_me.x + look.y * to_me.y + look.z * to_me.z > 0.93 then
						self._stared = (self._stared or 0) + 1
						if self._stared >= 3 then
							self._provoked = true
						end
					else
						self._stared = 0
					end
				end

				local aggressive = (def.hostile or self._provoked or self._owner)
					and dist <= def.view_range

				-- bear investigate phase (§24.6): crouch, stay still, and it
				-- may lose interest — real bear-safety advice
				if aggressive and def.disengage_if_still and dist > 4 then
					local ctrl = player.get_player_control and player:get_player_control()
					if ctrl and ctrl.sneak and not (ctrl.up or ctrl.down
							or ctrl.left or ctrl.right) then
						if math.random(4) == 1 then
							self._provoked = false
							aggressive = false
						end
					end
				end

				if aggressive then
					local tpos = player:get_pos()
					local dir = vector.direction(pos, tpos)

					-- keep-distance stalkers (Megalania, §24.7): follow while
					-- the consequence already inside the target works
					if def.keep_distance and self._venom_applied then
						local hp_max = player:get_properties().hp_max or 20
						if player:get_hp() > hp_max * 0.4 then
							if dist < def.keep_distance then
								walk(obj, vector.multiply(dir, -1), def.walk_speed)
							elseif dist > def.keep_distance + 4 then
								walk(obj, dir, def.walk_speed)
							else
								stand(obj)
								obj:set_yaw(math.atan2(dir.z, dir.x) + math.pi / 2)
							end
							return
						end
					end

					-- committed charge attack from range
					if def.commit_charge and dist > 4
							and dist < def.commit_charge.range
							and self._attack_cd <= 0 then
						self._tele = def.commit_charge.telegraph
						self._tele_target = player:get_player_name()
						self._attack_cd = def.commit_charge.cooldown
						stand(obj)
						obj:set_yaw(math.atan2(dir.z, dir.x) + math.pi / 2)
						return
					end

					-- wolves flank (§24.6): approach off-axis, close at the end
					if def.flanks and dist > 4 then
						local side = (self._flank_side or
							(math.random(2) == 1 and 1 or -1))
						self._flank_side = side
						local a = math.atan2(dir.z, dir.x) + side * 0.5
						dir = { x = math.cos(a), y = 0, z = math.sin(a) }
					end

					obj:set_yaw(math.atan2(dir.z, dir.x) + math.pi / 2)
					if dist > def.reach then
						walk(obj, dir, def.run_speed)
					else
						stand(obj)
						if self._attack_cd <= 0 then
							self._attack_cd = def.attack_interval
							player:punch(obj, def.attack_interval, {
								full_punch_interval = def.attack_interval,
								damage_groups = { fleshy = def.damage },
							}, dir)
							if def.venom and scavock_survival then
								scavock_survival.venom(player, 8)
								self._venom_applied = true
							end
						end
					end
					return
				end

				-- investigate noise (§8)
				if self._noise_t and self._noise_t > 0 then
					self._noise_t = self._noise_t - 0.4
					local npos = self._noise_pos
					if npos and vector.distance(pos, npos) > 2 then
						walk(obj, vector.direction(pos, npos), def.walk_speed * 1.5)
						return
					end
				end
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
				walk(obj, { x = self._wander_dir.x, y = 0, z = self._wander_dir.z },
					def.walk_speed)
			else
				stand(obj)
			end
		end,
	})
end

local define_animal = scavock_creatures.define

-- ---------------------------------------------------------------------------
-- Tier 1 — ordinary animals (§24.6)
-- ---------------------------------------------------------------------------
define_animal("wolf", {
	collisionbox = { -0.45, 0, -0.45, 0.45, 0.85, 0.45 },
	visual_size = { x = 0.9, y = 0.85, z = 1.3 },
	tex = "scavock_wolf.png", tex_face = "scavock_wolf_face.png",
	hp = 14, damage = 3, reach = 2.2, attack_interval = 1.2,
	view_range = 16, walk_speed = 1.5, run_speed = 5.5,
	hostile = true, pack_alert = true, flanks = true,
	drops = { { item = "scavock_core:leather", chance = 0.7, min = 1, max = 2 } },
})

define_animal("bear", {
	collisionbox = { -0.6, 0, -0.6, 0.6, 1.3, 0.6 },
	visual_size = { x = 1.2, y = 1.3, z = 1.9 },
	tex = "scavock_bear.png", tex_face = "scavock_bear_face.png",
	hp = 34, damage = 6, reach = 2.4, attack_interval = 1.8,
	view_range = 14, walk_speed = 1.4, run_speed = 3.0,
	hostile = true, disengage_if_still = true,
	commit_charge = { telegraph = 1.2, speed = 9.0, time = 2.5,
		damage = 8, cooldown = 8, range = 14 },
	drops = { { item = "scavock_core:leather", chance = 1.0, min = 2, max = 4 },
		{ item = "scavock_survival:meat_raw", chance = 1.0, min = 2, max = 3 } },
})

define_animal("boar", {
	collisionbox = { -0.5, 0, -0.5, 0.5, 0.9, 0.5 },
	visual_size = { x = 1.0, y = 0.9, z = 1.5 },
	tex = "scavock_boar.png", tex_face = "scavock_boar_face.png",
	hp = 20, damage = 4, reach = 2.0, attack_interval = 1.6,
	view_range = 12, walk_speed = 1.2, run_speed = 6.5,
	hostile = false, face_aggro = true,
	commit_charge = { telegraph = 0.9, speed = 8.0, time = 2.0,
		damage = 5, cooldown = 6, range = 10 },
	drops = { { item = "scavock_core:leather", chance = 0.9, min = 2, max = 3 },
		{ item = "scavock_survival:meat_raw", chance = 0.9, min = 1, max = 2 } },
})

define_animal("rat", {
	collisionbox = { -0.22, 0, -0.22, 0.22, 0.3, 0.22 },
	visual_size = { x = 0.45, y = 0.3, z = 0.7 },
	tex = "scavock_rat.png", tex_face = "scavock_rat_face.png",
	hp = 4, damage = 1, reach = 1.2, attack_interval = 1.0,
	view_range = 6, walk_speed = 2.0, run_speed = 4.0,
	hostile = true, flees_when_hurt = true,
	drops = { { item = "scavock_core:scrap_ingot", chance = 0.15, min = 1, max = 1 } },
})

define_animal("deer", {
	collisionbox = { -0.45, 0, -0.45, 0.45, 1.1, 0.45 },
	visual_size = { x = 0.9, y = 1.1, z = 1.5 },
	tex = "scavock_deer.png", tex_face = "scavock_deer_face.png",
	hp = 12, damage = 0, reach = 0, attack_interval = 99,
	view_range = 14, walk_speed = 1.8, run_speed = 7.0,
	passive = true, flees_on_sight = true,
	drops = { { item = "scavock_survival:meat_raw", chance = 1.0, min = 2, max = 3 },
		{ item = "scavock_core:leather", chance = 0.8, min = 1, max = 2 } },
})

define_animal("cow", {
	collisionbox = { -0.55, 0, -0.55, 0.55, 1.2, 0.55 },
	visual_size = { x = 1.1, y = 1.2, z = 1.7 },
	tex = "scavock_cow.png", tex_face = "scavock_cow_face.png",
	hp = 18, damage = 0, reach = 0, attack_interval = 99,
	view_range = 8, walk_speed = 1.0, run_speed = 2.5,
	passive = true, persistent = true,
	breed_item = "scavock_survival:berry_surface",
	drops = { { item = "scavock_survival:meat_raw", chance = 1.0, min = 2, max = 4 },
		{ item = "scavock_core:leather", chance = 1.0, min = 2, max = 3 } },
})

define_animal("chicken", {
	collisionbox = { -0.25, 0, -0.25, 0.25, 0.5, 0.25 },
	visual_size = { x = 0.5, y = 0.5, z = 0.7 },
	tex = "scavock_chicken.png", tex_face = "scavock_chicken_face.png",
	hp = 6, damage = 0, reach = 0, attack_interval = 99,
	view_range = 8, walk_speed = 1.4, run_speed = 3.0,
	passive = true, persistent = true,
	breed_item = "scavock_survival:berry_surface",
	drops = { { item = "scavock_survival:meat_raw", chance = 1.0, min = 1, max = 1 },
		{ item = "scavock_gear:feather", chance = 1.0, min = 1, max = 3 } },
})

define_animal("dog", {
	collisionbox = { -0.4, 0, -0.4, 0.4, 0.8, 0.4 },
	visual_size = { x = 0.8, y = 0.8, z = 1.2 },
	tex = "scavock_dog.png", tex_face = "scavock_dog_face.png",
	hp = 16, damage = 3, reach = 2.0, attack_interval = 1.2,
	view_range = 12, walk_speed = 2.0, run_speed = 5.5,
	hostile = false, persistent = true, alerts = true,
	tame_item = "scavock_survival:meat_raw",
	drops = {},
})

define_animal("cat", {
	collisionbox = { -0.3, 0, -0.3, 0.3, 0.5, 0.3 },
	visual_size = { x = 0.6, y = 0.5, z = 0.9 },
	tex = "scavock_cat.png", tex_face = "scavock_cat_face.png",
	hp = 10, damage = 1, reach = 1.5, attack_interval = 1.0,
	view_range = 10, walk_speed = 1.8, run_speed = 5.0,
	hostile = false, persistent = true,
	tame_item = "scavock_survival:meat_raw",
	drops = {},
})

define_animal("bat", {
	collisionbox = { -0.2, 0, -0.2, 0.2, 0.3, 0.2 },
	visual_size = { x = 0.4, y = 0.3, z = 0.5 },
	tex = "scavock_bat.png", tex_face = "scavock_bat_face.png",
	hp = 3, damage = 1, reach = 1.2, attack_interval = 1.4,
	view_range = 8, walk_speed = 2.5, run_speed = 4.5,
	hostile = true, no_gravity = true,
	drops = {},
})

-- chickens lay eggs (found near flocks)
core.register_craftitem("scavock_creatures:egg", {
	description = "Egg",
	inventory_image = "scavock_egg.png",
	on_use = function(itemstack, user)
		if scavock_survival then scavock_survival.feed(user, 10, 0, 0) end
		itemstack:take_item()
		return itemstack
	end,
})

-- fences hold pets and livestock (§24.6: pets cannot cross fences; the
-- tall collision box also stops the animals' auto-step)
core.register_node("scavock_creatures:fence", {
	description = "Fence (pets and livestock can't cross)",
	drawtype = "nodebox",
	tiles = { "scavock_fence.png" },
	paramtype = "light",
	node_box = { type = "fixed",
		fixed = { -0.15, -0.5, -0.15, 0.15, 0.5, 0.15 } },
	collision_box = { type = "fixed",
		fixed = { -0.2, -0.5, -0.2, 0.2, 0.9, 0.2 } },
	groups = { choppy = 2, oddly_breakable_by_hand = 2 },
})
core.register_craft({ output = "scavock_creatures:fence 4",
	recipe = { { "scavock_core:stick", "scavock_core:planks", "scavock_core:stick" },
		{ "scavock_core:stick", "scavock_core:planks", "scavock_core:stick" } } })

-- pets defend their owner: mark the attacker for nearby owned pets
core.register_on_punchplayer(function(player, hitter)
	if not (hitter and hitter:is_player()) then return end
	local victim = player:get_player_name()
	for obj in core.objects_inside_radius(player:get_pos(), 14) do
		local ent = obj:get_luaentity()
		if ent and ent._scavock_creature and ent._owner == victim then
			ent._target_name = hitter:get_player_name()
			ent._provoked = true
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Spawning (safe zones and lit interiors excluded; §22 night rhythm)
-- ---------------------------------------------------------------------------
local function try_spawn(pos, entity, cap)
	local above = { x = pos.x, y = pos.y + 1, z = pos.z }
	if core.get_node(above).name ~= "air" then return end
	if pos.y > 0 then
		local tod = core.get_timeofday()
		if tod > 0.25 and tod < 0.72 and math.random(2) == 1 then return end
	end
	local _, dist = nearest_player(pos, 48)
	if not dist or dist < 12 then return end
	if scavock.in_safe_zone and scavock.in_safe_zone(pos) then return end
	local light = core.get_node_light(above, nil)
	if light and light > 11 and core.get_node_light(above, 0.5) ~= light then
		return
	end
	if count_creatures_near(pos, 24) >= cap then return end
	return core.add_entity({ x = pos.x, y = pos.y + 1.5, z = pos.z },
		"scavock_creatures:" .. entity)
end
scavock_creatures.try_spawn = try_spawn

local function spawner(label, nodenames, interval, chance, fn)
	core.register_abm({ label = label, nodenames = nodenames,
		interval = interval, chance = chance, action = fn })
end
scavock_creatures.spawner = spawner

spawner("spawn wolves", { "scavock_core:dirt_with_grass", "scavock_core:snowblock" },
	23, 4200, function(pos)
		if math.random(3) > 1 then try_spawn(pos, "wolf", 4) end
		try_spawn({ x = pos.x + 2, y = pos.y, z = pos.z }, "wolf", 4)
	end)
spawner("spawn boars", { "scavock_core:dirt_with_grass", "scavock_core:dirt_with_dry_grass" },
	29, 5200, function(pos) try_spawn(pos, "boar", 3) end)
spawner("spawn rats", { "scavock_core:concrete", "scavock_core:concrete_cracked",
	"scavock_core:debris" }, 17, 260, function(pos) try_spawn(pos, "rat", 5) end)
spawner("spawn bears", { "scavock_core:dirt_with_grass" },
	31, 9000, function(pos) try_spawn(pos, "bear", 1) end)
spawner("spawn deer", { "scavock_core:dirt_with_grass" },
	27, 5200, function(pos) try_spawn(pos, "deer", 3) end)
spawner("spawn cows", { "scavock_core:dirt_with_grass" },
	33, 7000, function(pos) try_spawn(pos, "cow", 2) end)
spawner("spawn chickens", { "scavock_core:dirt_with_grass" },
	27, 6600, function(pos)
		try_spawn(pos, "chicken", 3)
		if math.random(6) == 1 then
			core.add_item({ x = pos.x, y = pos.y + 1, z = pos.z },
				"scavock_creatures:egg")
		end
	end)
spawner("spawn dogs and cats", { "scavock_core:dirt_with_dry_grass" },
	41, 9500, function(pos)
		try_spawn(pos, math.random(2) == 1 and "dog" or "cat", 1)
	end)
spawner("spawn bats", { "scavock_core:stone" },
	29, 7500, function(pos)
		if pos.y > -8 then return end
		try_spawn(pos, "bat", 4)
	end)

dofile(core.get_modpath("scavock_creatures") .. "/megafauna.lua")
dofile(core.get_modpath("scavock_creatures") .. "/maneaters.lua")
