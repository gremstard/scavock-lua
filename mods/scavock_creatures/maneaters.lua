-- Tier 3 — Man Eaters (§24.8). They hunt YOU for food, cannot be driven
-- off, and do not flee when cornered. Eating a player levels them up and
-- restores HP (capped); SWALLOWED LOOT IS DESTROYED, not carried — nobody
-- benefits from a teammate being eaten (§24.5).

local define = scavock_creatures.define
local H = scavock_creatures.helpers

scavock.suppress_drop = scavock.suppress_drop or {}

local function swallow(self, player, heal_cap)
	local name = player:get_player_name()
	-- inventory destroyed, not dropped (§24.5 confirmed)
	scavock.suppress_drop[name] = true
	if scavock.clear_all_carried then
		scavock.clear_all_carried(player)
	else
		player:get_inventory():set_list("main", {})
	end
	player:set_hp(0, { type = "set_hp", from = "mod" })
	core.chat_send_player(name, "Swallowed whole. Nothing of yours remains.")
	-- growing by eating: level up, heal, capped at 3 meals
	self._meals = (self._meals or 0) + 1
	if self._meals <= 3 then
		local props = self.object:get_properties()
		props.hp_max = props.hp_max + 10
		self.object:set_properties(props)
	end
	self.object:set_hp(math.min(self.object:get_properties().hp_max, heal_cap))
end

-- ---------------------------------------------------------------------------
-- Titanoboa — LAND Man Eater. Deliberate exception to the 2-3 attack
-- baseline (§24.8): a three-stage fight, recorded so it is never
-- "simplified back" on the assumption it drifted from spec.
--   Stage 1 hunting: stalks, strikes to initiate a hold. Hitting it during
--     the wind-up interrupts (the framework's commitment rule).
--   Stage 2 holding: wraps the player, damage over time. Damage dealt TO
--     the held player hits the snake instead; the held player can attack
--     the coil; struggling (jumping) shortens the hold.
--   Stage 3 desperation: at low HP it lunges to swallow whole. The head is
--     exposed (double damage). Kill it or die.
-- ---------------------------------------------------------------------------
scavock.boa_hold = {} -- player name -> boa luaentity

define("titanoboa", {
	body = "serpent",
	collisionbox = { -0.8, 0, -0.8, 0.8, 1.0, 0.8 },
	visual_size = { x = 1.6, y = 1.0, z = 4.0 },
	tex = "scavock_titanoboa.png", tex_face = "scavock_titanoboa_face.png",
	hp = 70, damage = 3, reach = 3.0, attack_interval = 2.0,
	view_range = 16, walk_speed = 1.2, run_speed = 4.0,
	hostile = true, man_eater = true,
	custom_step = function(self, player, dist)
		local obj = self.object
		local name = player:get_player_name()
		local hp = obj:get_hp()
		local hp_max = obj:get_properties().hp_max

		-- stage 3: desperation lunge (kill it or die)
		if hp < hp_max * 0.3 and not self._holding then
			self._desperate = true
			self.object:set_properties({ visual_size =
				{ x = 1.6, y = 1.6, z = 4.0 } }) -- rearing: the head reveal
			if not self._lunging and self._attack_cd <= 0 then
				self._lunging = 2.0 -- telegraph: head fully exposed
				self._committed = true
				H.stand(obj)
				return true
			end
			if self._lunging then
				self._lunging = self._lunging - 0.4
				if self._lunging <= 0 then
					self._lunging = nil
					self._committed = nil
					self._attack_cd = 4
					if dist < 5 then
						swallow(self, player, hp_max)
					end
				end
				return true
			end
			H.walk(obj, vector.direction(obj:get_pos(), player:get_pos()), 3.5)
			return true
		end

		-- stage 2: holding
		if self._holding then
			local held = core.get_player_by_name(self._holding)
			if not held or held:get_hp() <= 0
					or (self._hold_t or 0) <= 0 then
				scavock.boa_hold[self._holding] = nil
				self._holding = nil
				self._attack_cd = 5
				return true
			end
			self._hold_t = self._hold_t - 0.4
			-- struggling shortens the hold
			if held:get_player_control().jump then
				self._hold_t = self._hold_t - 0.3
			end
			held:set_pos(vector.add(obj:get_pos(), { x = 0, y = 0.4, z = 0 }))
			self._dot = (self._dot or 0) + 0.4
			if self._dot >= 1.5 then
				self._dot = 0
				held:set_hp(held:get_hp() - 1,
					{ type = "punch", object = obj, from = "mod" })
			end
			H.stand(obj)
			return true
		end

		-- stage 1: hunting — strike wind-up initiates the hold
		if dist < 3.5 and self._attack_cd <= 0 then
			self._committed = true
			self._windup = (self._windup or 1.2) - 0.4
			H.stand(obj)
			if self._windup <= 0 then
				self._windup = nil
				self._committed = nil
				self._attack_cd = 8
				if vector.distance(obj:get_pos(), player:get_pos()) < 4 then
					self._holding = name
					self._hold_t = 6
					scavock.boa_hold[name] = self
					core.chat_send_player(name,
						"Wrapped! Struggle (jump) and fight the coil!")
				end
			end
			return true
		end
		self._windup = nil
		return false -- default stalk/approach
	end,
	drops = { { item = "scavock_core:leather", chance = 1.0, min = 5, max = 8 },
		{ item = "scavock_survival:meat_raw", chance = 1.0, min = 4, max = 6 } },
})

-- stage 2 rule: damage dealt to a held player hits the snake instead —
-- an attacker becomes a rescuer, and the held player's own hits work too
table.insert(scavock.damage_filters, function(player, hp_change, reason)
	if hp_change >= 0 then return hp_change end
	local boa = scavock.boa_hold[player:get_player_name()]
	if boa and boa.object and boa.object:get_pos() then
		if reason and reason.from == "mod" then
			return hp_change -- the coil's own squeeze
		end
		boa.object:set_hp(boa.object:get_hp() + hp_change)
		return 0
	end
	return hp_change
end)

-- head exposed while lunging: double damage (weak point, §24.4)
-- (handled via on_punch: framework interrupt already cancels the lunge)

-- ---------------------------------------------------------------------------
-- Megistotherium — UNDERGROUND Man Eater (§24.8). It comes through the
-- walls: nothing else can reach a player inside their own tunnel, which is
-- what makes it frightening. Audible through the ground IF you are quiet.
-- The breach is the commitment window.
-- ---------------------------------------------------------------------------
define("megisto", {
	body = "quad",
	collisionbox = { -0.7, 0, -0.7, 0.7, 1.5, 0.7 },
	visual_size = { x = 1.4, y = 1.5, z = 2.4 },
	tex = "scavock_megisto.png", tex_face = "scavock_megisto_face.png",
	hp = 55, damage = 8, reach = 2.6, attack_interval = 1.6,
	view_range = 24, walk_speed = 1.4, run_speed = 4.0,
	hostile = true, man_eater = true,
	on_spawn = function(self)
		self._burrowing = true
		self.object:set_properties({ physical = false, is_visible = false })
		-- no gravity while burrowing, or it falls out of the world
		self.object:set_acceleration({ x = 0, y = 0, z = 0 })
	end,
	custom_step = function(self, player, dist)
		local obj = self.object
		local pos = obj:get_pos()
		if self._burrowing then
			-- moves through soil toward the prey; audible if you are quiet
			local tpos = player:get_pos()
			local dir = vector.direction(pos, tpos)
			obj:set_velocity(vector.multiply(dir, 2.2))
			local ctrl = player:get_player_control()
			if dist < 14 and not (ctrl.aux1 and ctrl.up) and math.random(3) == 1 then
				core.chat_send_player(player:get_player_name(),
					"Something is moving through the ground.")
			end
			if dist < 2.5 then
				-- THE BREACH: erupt through whatever is in the way
				for dx = -1, 1 do
					for dy = 0, 2 do
						for dz = -1, 1 do
							local np = { x = math.floor(pos.x) + dx,
								y = math.floor(pos.y) + dy,
								z = math.floor(pos.z) + dz }
							local n = core.get_node(np).name
							if n ~= "air" and core.get_item_group(n, "water") == 0
									and n ~= "ignore" then
								core.remove_node(np)
							end
						end
					end
				end
				self._burrowing = nil
				self._committed = true -- briefly extended: the punish window
				self._stun = 0
				obj:set_properties({ physical = true, is_visible = true })
				obj:set_acceleration({ x = 0, y = -18, z = 0 })
				core.after(2.0, function()
					if obj:get_pos() then self._committed = nil end
				end)
				if scavock.noise then
					scavock.noise(pos, "explosion", nil)
				end
			end
			return true
		end
		if self._committed then
			H.stand(obj)
			return true
		end
		-- eats what it downs (§12 + §24.5): finish a downed player = a meal
		if scavock.downed[player:get_player_name()] and dist < 2.5 then
			swallow(self, player, obj:get_properties().hp_max)
			return true
		end
		return false -- surface behaviour: ordinary relentless predator
	end,
	drops = { { item = "scavock_core:leather", chance = 1.0, min = 4, max = 6 },
		{ item = "scavock_core:titanium_ingot", chance = 0.5, min = 1, max = 1 } },
})

-- spawning: Titanoboa in dense growth, Megistotherium deep underground.
-- Man Eaters are RARE (tier 3): one per wide area.
scavock_creatures.spawner("spawn titanoboa", { "scavock_core:dirt_with_grass" },
	53, 30000, function(pos)
		scavock_creatures.try_spawn(pos, "titanoboa", 1)
	end)
scavock_creatures.spawner("spawn megistotherium", { "scavock_core:stone" },
	59, 26000, function(pos)
		if pos.y > -40 then return end
		scavock_creatures.try_spawn(pos, "megisto", 1)
	end)

core.register_on_leaveplayer(function(player)
	scavock.boa_hold[player:get_player_name()] = nil
end)
