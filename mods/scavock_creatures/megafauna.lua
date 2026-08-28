-- Tier 2 — extinct megafauna (§24.7), plus the underground pair (§24.8b)
-- and the Yeti (§24.9). Reconstructions: oversized, wrong, and the wrongness
-- is the weak point — a hit during commitment interrupts and stuns (§24.4).

local define = scavock_creatures.define
local H = scavock_creatures.helpers

-- Megalania — the patient pursuer. Bites once, then FOLLOWS while the
-- venom works. You cannot outrun a consequence already inside you.
define("megalania", {
	body = "quad",
	collisionbox = { -0.7, 0, -0.7, 0.7, 0.9, 0.7 },
	visual_size = { x = 1.4, y = 0.9, z = 2.6 },
	tex = "scavock_megalania.png", tex_face = "scavock_megalania_face.png",
	hp = 40, damage = 4, reach = 2.6, attack_interval = 2.0,
	view_range = 18, walk_speed = 1.6, run_speed = 4.5,
	hostile = true, venom = true, keep_distance = 8,
	drops = { { item = "scavock_core:leather", chance = 1.0, min = 3, max = 5 },
		{ item = "scavock_survival:meat_raw", chance = 1.0, min = 2, max = 4 } },
})

-- Terror bird — the ambusher. Waits near cover, bursts at close range.
-- Extremely fast in a straight line, poor at turning: the charge commit.
-- Counterplay is the noise system: it is audible before it commits if
-- you are quiet enough to hear it (it emits noise when it telegraphs).
define("terrorbird", {
	body = "bird",
	collisionbox = { -0.45, 0, -0.45, 0.45, 1.6, 0.45 },
	visual_size = { x = 0.9, y = 1.6, z = 1.1 },
	tex = "scavock_terrorbird.png", tex_face = "scavock_terrorbird_face.png",
	hp = 26, damage = 6, reach = 2.2, attack_interval = 1.4,
	view_range = 14, walk_speed = 1.0, run_speed = 4.0,
	hostile = true,
	commit_charge = { telegraph = 0.7, speed = 11.0, time = 1.8,
		damage = 7, cooldown = 5, range = 14 },
	drops = { { item = "scavock_gear:feather", chance = 1.0, min = 2, max = 5 },
		{ item = "scavock_survival:meat_raw", chance = 1.0, min = 2, max = 3 } },
})

-- Glyptodon — the armoured wall. Near-immune from the front; this is the
-- creature that teaches the weak-point read. Frontal hits are absorbed;
-- hits from behind (or during its committed charge) land fully.
define("glyptodon", {
	body = "quad",
	collisionbox = { -0.8, 0, -0.8, 0.8, 1.1, 0.8 },
	visual_size = { x = 1.6, y = 1.1, z = 2.2 },
	tex = "scavock_glyptodon.png", tex_face = "scavock_glyptodon_face.png",
	hp = 50, damage = 5, reach = 2.4, attack_interval = 2.2,
	view_range = 10, walk_speed = 0.8, run_speed = 7.0,
	hostile = false, no_knockback = true,
	commit_charge = { telegraph = 1.0, speed = 7.0, time = 2.2,
		damage = 7, cooldown = 9, range = 10 },
	on_punched = function(self, puncher)
		-- frontal plating: if the puncher stands in front, most damage is
		-- shrugged off (healed back) — get behind or beneath it (§24.7)
		if not (puncher and puncher.get_pos) then return end
		if self._charging or self._stun > 0 then return end
		local yaw = self.object:get_yaw()
		local facing = { x = -math.sin(yaw), y = 0, z = math.cos(yaw) }
		local to_p = vector.direction(self.object:get_pos(), puncher:get_pos())
		if facing.x * to_p.x + facing.z * to_p.z > 0.2 then
			local hp = self.object:get_hp()
			if hp > 0 then
				self.object:set_hp(math.min(hp + 3,
					self.object:get_properties().hp_max))
			end
		end
	end,
	drops = { { item = "scavock_core:leather", chance = 1.0, min = 4, max = 6 },
		{ item = "scavock_core:scrap_ingot", chance = 0.6, min = 1, max = 3 } },
})

-- Gigantopithecus — the tactical one. Throws from range, repositions
-- rather than charging, retreats when hurt. Cannot reposition mid-throw.
core.register_entity("scavock_creatures:thrown_rock", {
	initial_properties = {
		physical = false, visual = "sprite",
		textures = { "scavock_rock.png" },
		visual_size = { x = 0.6, y = 0.6 }, static_save = false,
	},
	_life = 0,
	on_step = function(self, dtime)
		self._life = self._life + dtime
		if self._life > 6 then self.object:remove() return end
		local pos = self.object:get_pos()
		local last = self._last or pos
		self._last = pos
		for hit in core.raycast(last, pos, true, false) do
			if hit.type == "object" and hit.ref ~= self.object then
				local ent = hit.ref:get_luaentity()
				if not (ent and ent.name == "scavock_creatures:giganto") then
					hit.ref:punch(self.object, 1.0, {
						full_punch_interval = 1.0,
						damage_groups = { fleshy = 6 },
					}, nil)
					self.object:remove()
					return
				end
			elseif hit.type == "node" then
				self.object:remove()
				return
			end
		end
	end,
})

define("giganto", {
	body = "biped",
	collisionbox = { -0.7, 0, -0.7, 0.7, 2.2, 0.7 },
	visual_size = { x = 1.4, y = 2.2, z = 1.0 },
	tex = "scavock_giganto.png", tex_face = "scavock_giganto_face.png",
	hp = 44, damage = 7, reach = 2.8, attack_interval = 1.8,
	view_range = 20, walk_speed = 1.6, run_speed = 4.2,
	hostile = true,
	custom_step = function(self, player, dist)
		local obj = self.object
		-- retreats when hurt rather than fighting to the death (§24.7)
		if obj:get_hp() < 15 then
			H.walk(obj, vector.direction(player:get_pos(), obj:get_pos()), 4.2)
			return true
		end
		-- the throw: a commitment (cannot reposition mid-throw)
		if dist > 6 and dist < 18 and self._attack_cd <= 0 and not self._committed then
			self._committed = true
			self._attack_cd = 5
			H.stand(obj)
			core.after(1.0, function()
				if not self._committed or not obj:get_pos() then return end
				self._committed = nil
				local p = core.get_player_by_name(player:get_player_name())
				if not p then return end
				local from = vector.add(obj:get_pos(), { x = 0, y = 2, z = 0 })
				local dir = vector.direction(from,
					vector.add(p:get_pos(), { x = 0, y = 1, z = 0 }))
				local rock = core.add_entity(from, "scavock_creatures:thrown_rock")
				if rock then
					rock:set_velocity(vector.multiply(dir, 18))
					rock:set_acceleration({ x = 0, y = -10, z = 0 })
				end
			end)
			return true
		end
		if self._committed then
			H.stand(obj)
			return true
		end
		-- reposition sideways between throws instead of closing straight in
		if dist > 6 and math.random(3) == 1 then
			local dir = vector.direction(obj:get_pos(), player:get_pos())
			local a = math.atan2(dir.z, dir.x) + (math.random(2) == 1 and 1.2 or -1.2)
			H.walk(obj, { x = math.cos(a), y = 0, z = math.sin(a) }, 3.0)
			return true
		end
		return false -- default melee when close
	end,
	drops = { { item = "scavock_core:leather", chance = 1.0, min = 3, max = 5 },
		{ item = "scavock_survival:meat_raw", chance = 1.0, min = 3, max = 5 } },
})

-- Argentavis — the aerial threat. Circles at altitude, dives to strike.
-- Untouchable while circling, hittable in melee DURING the dive (§24.3).
define("argentavis", {
	body = "bird",
	collisionbox = { -0.6, 0, -0.6, 0.6, 0.6, 0.6 },
	visual_size = { x = 2.4, y = 0.5, z = 1.2 },
	tex = "scavock_argentavis.png", tex_face = "scavock_argentavis_face.png",
	hp = 22, damage = 6, reach = 2.0, attack_interval = 2.0,
	view_range = 30, walk_speed = 3.0, run_speed = 9.0,
	hostile = true, no_gravity = true,
	custom_step = function(self, player, dist)
		local obj = self.object
		local pos = obj:get_pos()
		local tpos = player:get_pos()
		if self._diving then
			-- the dive is the commitment window
			local dir = vector.direction(pos, self._dive_target)
			obj:set_velocity(vector.multiply(dir, 12))
			if vector.distance(pos, tpos) < 2.2 then
				player:punch(obj, 1.0, { full_punch_interval = 1.0,
					damage_groups = { fleshy = 6 } }, dir)
				self._diving = nil
			elseif vector.distance(pos, self._dive_target) < 1.5 then
				self._diving = nil -- missed; climb away
			end
			self._committed = true
			return true
		end
		self._committed = nil
		-- circle at altitude
		self._angle = (self._angle or 0) + 0.25
		local cpos = { x = tpos.x + math.cos(self._angle) * 12,
			y = tpos.y + 11, z = tpos.z + math.sin(self._angle) * 12 }
		obj:set_velocity(vector.multiply(vector.direction(pos, cpos), 6))
		obj:set_yaw(math.atan2(cpos.z - pos.z, cpos.x - pos.x) + math.pi / 2)
		if self._attack_cd <= 0 then
			self._attack_cd = 7
			-- open ground is its territory: only dive with sky access
			if core.get_node_light({ x = tpos.x, y = tpos.y + 1, z = tpos.z }, 0.5)
					== 15 then
				self._diving = true
				self._dive_target = vector.add(tpos, { x = 0, y = 0.5, z = 0 })
			end
		end
		return true
	end,
	drops = { { item = "scavock_gear:feather", chance = 1.0, min = 3, max = 6 },
		{ item = "scavock_survival:meat_raw", chance = 0.8, min = 1, max = 2 } },
})

-- Underground pair (§24.8b): the cave bear reuses the surface bear's
-- two-phase AI; the cave hyena fills the wolf-pack role underground.
define("cavebear", {
	body = "quad",
	collisionbox = { -0.65, 0, -0.65, 0.65, 1.4, 0.65 },
	visual_size = { x = 1.3, y = 1.4, z = 2.0 },
	tex = "scavock_cavebear.png", tex_face = "scavock_cavebear_face.png",
	hp = 40, damage = 7, reach = 2.4, attack_interval = 1.8,
	view_range = 12, walk_speed = 1.3, run_speed = 3.0,
	hostile = true, disengage_if_still = true,
	commit_charge = { telegraph = 1.2, speed = 8.5, time = 2.2,
		damage = 9, cooldown = 8, range = 12 },
	drops = { { item = "scavock_core:leather", chance = 1.0, min = 3, max = 5 },
		{ item = "scavock_survival:meat_raw", chance = 1.0, min = 2, max = 4 } },
})

define("hyena", {
	body = "quad",
	collisionbox = { -0.45, 0, -0.45, 0.45, 0.9, 0.45 },
	visual_size = { x = 0.9, y = 0.9, z = 1.4 },
	tex = "scavock_hyena.png", tex_face = "scavock_hyena_face.png",
	hp = 16, damage = 4, reach = 2.2, attack_interval = 1.2,
	view_range = 14, walk_speed = 1.6, run_speed = 5.0,
	hostile = true, pack_alert = true, flanks = true,
	drops = { { item = "scavock_core:leather", chance = 0.7, min = 1, max = 2 } },
})

-- Yeti (§24.9) — Icelands apex, Source guardian. Found INSIDE the facility,
-- never roaming. Attack pattern is an open question (§32) — this build
-- gives it the two things already learned on the way here: a heavy melee
-- and the Gigantopithecus throw. Nothing invented beyond that.
define("yeti", {
	body = "biped",
	collisionbox = { -0.7, 0, -0.7, 0.7, 2.4, 0.7 },
	visual_size = { x = 1.4, y = 2.4, z = 1.0 },
	tex = "scavock_yeti.png", tex_face = "scavock_yeti_face.png",
	hp = 60, damage = 9, reach = 3.0, attack_interval = 1.6,
	view_range = 18, walk_speed = 1.4, run_speed = 4.5,
	hostile = true,
	custom_step = scavock_creatures.def_giganto
		and scavock_creatures.def_giganto.custom_step or nil,
	drops = { { item = "scavock_core:leather", chance = 1.0, min = 4, max = 6 },
		{ item = "scavock_core:titanium_ingot", chance = 0.8, min = 1, max = 2 } },
})

-- ---------------------------------------------------------------------------
-- Spawning: rare, biome-flavored (megafauna = "this area is worse than it
-- looked"). Underground pair below y -20 in natural caves.
-- ---------------------------------------------------------------------------
local try_spawn = scavock_creatures.try_spawn
local spawner = scavock_creatures.spawner

spawner("spawn megalania", { "scavock_core:dirt_with_dry_grass", "scavock_core:sand" },
	37, 16000, function(pos) try_spawn(pos, "megalania", 1) end)
spawner("spawn terror birds", { "scavock_core:dirt_with_grass" },
	37, 17000, function(pos) try_spawn(pos, "terrorbird", 1) end)
spawner("spawn glyptodon", { "scavock_core:dirt_with_grass", "scavock_core:dirt_with_dry_grass" },
	41, 18000, function(pos) try_spawn(pos, "glyptodon", 1) end)
spawner("spawn gigantopithecus", { "scavock_core:dirt_with_grass", "scavock_core:stone" },
	43, 22000, function(pos)
		if pos.y < 30 and core.get_node({x=pos.x,y=pos.y,z=pos.z}).name
				== "scavock_core:stone" then return end
		try_spawn(pos, "giganto", 1)
	end)
spawner("spawn argentavis", { "scavock_core:dirt_with_dry_grass" },
	47, 20000, function(pos) try_spawn(pos, "argentavis", 1) end)
spawner("spawn cave fauna", { "scavock_core:stone" },
	31, 15000, function(pos)
		if pos.y > -20 then return end
		local pick = math.random(3)
		if pick == 1 then
			try_spawn(pos, "cavebear", 1)
		else
			try_spawn(pos, "hyena", 3)
			try_spawn({ x = pos.x + 2, y = pos.y, z = pos.z }, "hyena", 3)
		end
	end)
