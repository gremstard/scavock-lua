-- Vehicles (§27), box-rig simplified: cars, boats, planes.
--
-- Fuel: percentage gauge, refilled with oil canisters, sourced from gas
-- stations near towns. HP separate from fuel: smokes at 30%, slowed at
-- 10%, and AT 0% THE VEHICLE EXPLODES, destroying voxels (§16/§27) and
-- chaining into nearby charges — the intended breaching chain: bomb
-- destroys car, car destroys wall. A parked vehicle near a structure is
-- a liability, deliberately.
--
-- Water (§24.10): traversable, not a destination. Boats and fishing ship;
-- no dive loot, no underwater zone (post-1.0).

local function vehicle(name, def)
	core.register_entity("scavock_vehicles:" .. name, {
		initial_properties = {
			physical = true,
			collide_with_objects = true,
			collisionbox = def.collisionbox,
			stepheight = def.stepheight or 1.1,
			visual = "cube",
			visual_size = def.visual_size,
			textures = { def.tex, def.tex, def.tex, def.tex, def.tex, def.tex },
			static_save = true,
		},
		_vehicle = true,

		get_staticdata = function(self)
			return core.serialize({ hp = self._hp, fuel = self._fuel })
		end,

		on_activate = function(self, staticdata)
			self.object:set_armor_groups({ fleshy = 0 }) -- damage via on_punch
			if not def.floats then
				self.object:set_acceleration({ x = 0, y = -18, z = 0 })
			end
			local data = staticdata ~= "" and core.deserialize(staticdata) or nil
			self._hp = data and data.hp or def.hp
			self._fuel = data and data.fuel or 40
			self._driver = nil
		end,

		on_punch = function(self, puncher, tflp, caps, dir)
			local dmg = caps and caps.damage_groups
				and caps.damage_groups.fleshy or 2
			self._hp = self._hp - dmg
			if self._hp <= 0 then
				local pos = self.object:get_pos()
				if self._driver then
					local d = core.get_player_by_name(self._driver)
					if d then d:set_detach() end
				end
				self.object:remove()
				-- §16/§27: 0% = explosion, voxel destruction, one-shots people
				scavock_boom.explode(pos, 2, 40)
			end
		end,

		on_rightclick = function(self, clicker)
			local name2 = clicker:get_player_name()
			local wield = clicker:get_wielded_item()
			if wield:get_name() == "scavock_power:oil" then
				self._fuel = math.min(100, self._fuel + 40)
				wield:take_item()
				clicker:set_wielded_item(wield)
				core.chat_send_player(name2,
					("Refuelled: %d%%"):format(self._fuel))
				return
			end
			if self._driver == name2 then
				self._driver = nil
				clicker:set_detach()
				return
			end
			if self._driver then return end
			self._driver = name2
			clicker:set_attach(self.object, "",
				{ x = 0, y = def.seat_y or 5, z = 0 }, { x = 0, y = 0, z = 0 })
			core.chat_send_player(name2,
				("%s — fuel %d%%, hull %d%%. Right-click to get out.")
				:format(def.label, self._fuel, math.floor(self._hp / def.hp * 100)))
		end,

		on_step = function(self, dtime)
			local obj = self.object
			local driver = self._driver and core.get_player_by_name(self._driver)
			if self._driver and not driver then
				self._driver = nil
			end

			-- hull state (§27): smoke at 30%, slow at 10%
			local frac = self._hp / def.hp
			if frac < 0.3 and math.random(8) == 1 then
				core.add_particle({
					pos = vector.add(obj:get_pos(), { x = 0, y = 1, z = 0 }),
					velocity = { x = 0, y = 1.5, z = 0 },
					expirationtime = 2, size = 6,
					texture = "scavock_coal_lump.png",
				})
			end

			if def.floats then
				-- boats ride the surface
				local pos = obj:get_pos()
				local node = core.get_node(pos)
				local in_water = core.get_item_group(node.name, "water") > 0
				local below = core.get_node({ x = pos.x, y = pos.y - 0.5, z = pos.z })
				local water_below = core.get_item_group(below.name, "water") > 0
				local vel = obj:get_velocity()
				if in_water then
					obj:set_velocity({ x = vel.x, y = 2, z = vel.z })
				elseif water_below then
					obj:set_velocity({ x = vel.x, y = 0, z = vel.z })
				else
					obj:set_velocity({ x = vel.x, y = vel.y - 0.5, z = vel.z })
				end
			end

			if not driver then
				if not def.floats then
					local vel = obj:get_velocity()
					obj:set_velocity({ x = vel.x * 0.9, y = vel.y, z = vel.z * 0.9 })
				end
				return
			end

			local ctrl = driver:get_player_control()
			if self._fuel <= 0 then
				if math.random(30) == 1 then
					core.chat_send_player(self._driver, "Out of fuel.")
				end
				return
			end

			local yaw = driver:get_look_horizontal()
			obj:set_yaw(yaw + math.pi / 2)
			local speed_mult = frac < 0.1 and 0.35 or 1.0
			local vel = obj:get_velocity()

			if def.flies then
				-- planes: full 3D — velocity follows the driver's look
				if ctrl.up then
					local dir = driver:get_look_dir()
					obj:set_velocity(vector.multiply(dir, def.speed * speed_mult))
					self._fuel = self._fuel - dtime * 0.8
				else
					obj:set_velocity({ x = vel.x * 0.98, y = vel.y - 6 * dtime,
						z = vel.z * 0.98 })
				end
				return
			end

			local fwd = { x = -math.sin(yaw), y = 0, z = math.cos(yaw) }
			if ctrl.up then
				obj:set_velocity({ x = fwd.x * def.speed * speed_mult,
					y = vel.y, z = fwd.z * def.speed * speed_mult })
				self._fuel = self._fuel - dtime * 0.35
			elseif ctrl.down then
				obj:set_velocity({ x = -fwd.x * def.speed * 0.4,
					y = vel.y, z = -fwd.z * def.speed * 0.4 })
				self._fuel = self._fuel - dtime * 0.2
			else
				obj:set_velocity({ x = vel.x * 0.92, y = vel.y, z = vel.z * 0.92 })
			end
			-- engines are loud (§8/§15)
			if ctrl.up and scavock.noise and math.random(6) == 1 then
				scavock.noise(obj:get_pos(), 22, self._driver)
			end
		end,
	})

	core.register_craftitem("scavock_vehicles:" .. name .. "_item", {
		description = def.label .. " (place on ground"
			.. (def.floats and "/water" or "") .. ")",
		inventory_image = def.tex,
		stack_max = 1,
		on_place = function(itemstack, placer, pointed)
			if pointed.type ~= "node" then return itemstack end
			core.add_entity(vector.add(pointed.above, { x = 0, y = 0.5, z = 0 }),
				"scavock_vehicles:" .. name)
			itemstack:take_item()
			return itemstack
		end,
	})
	scavock.item_sizes["scavock_vehicles:" .. name .. "_item"] = { 2, 2 }
end

vehicle("car", {
	label = "Car",
	collisionbox = { -0.9, 0, -0.9, 0.9, 1.2, 0.9 },
	visual_size = { x = 1.8, y = 1.2, z = 2.8 },
	tex = "scavock_car.png",
	hp = 60, speed = 11, seat_y = 6,
})
vehicle("boat", {
	label = "Boat",
	collisionbox = { -0.7, 0, -0.7, 0.7, 0.7, 0.7 },
	visual_size = { x = 1.4, y = 0.7, z = 2.4 },
	tex = "scavock_boat.png",
	hp = 25, speed = 7, floats = true, seat_y = 4,
})
vehicle("plane", {
	label = "Plane",
	collisionbox = { -1.0, 0, -1.0, 1.0, 1.0, 1.0 },
	visual_size = { x = 3.2, y = 0.9, z = 3.0 },
	tex = "scavock_plane.png",
	hp = 40, speed = 16, flies = true, seat_y = 5,
})

core.register_craft({ output = "scavock_vehicles:car_item",
	recipe = { { "scavock_core:iron_ingot", "scavock_power:engine",
			"scavock_core:iron_ingot" },
		{ "scavock_core:iron_ingot", "scavock_core:iron_ingot",
			"scavock_core:iron_ingot" } } })
core.register_craft({ output = "scavock_vehicles:boat_item",
	recipe = { { "scavock_core:planks", "", "scavock_core:planks" },
		{ "scavock_core:planks", "scavock_core:planks", "scavock_core:planks" } } })
core.register_craft({ output = "scavock_vehicles:plane_item",
	recipe = { { "scavock_core:titanium_ingot", "scavock_power:engine",
			"scavock_core:titanium_ingot" },
		{ "scavock_power:plastic", "scavock_core:titanium_ingot",
			"scavock_power:plastic" } } })

-- ---------------------------------------------------------------------------
-- Gas stations near towns (§27 fuel source) — with the occasional
-- abandoned car, and the §16 liability that implies
-- ---------------------------------------------------------------------------
core.register_node("scavock_vehicles:pump", {
	description = "Fuel Pump",
	tiles = { "scavock_pump.png" },
	groups = { cracky = 2 },
})

local function make_station()
	local sx, sy, sz = 5, 3, 5
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
			set(x, 0, z, "scavock_core:concrete", 255, true)
		end
	end
	set(1, 1, 1, "scavock_vehicles:pump", 255, true)
	set(3, 1, 3, "scavock_loot:crate", 255, true)
	return { size = { x = sx, y = sy, z = sz }, data = data }
end

core.register_decoration({
	name = "scavock_vehicles:gas_station",
	deco_type = "schematic",
	place_on = { "scavock_core:dirt_with_dry_grass" },
	sidelen = 80,
	fill_ratio = 0.00004,
	biomes = { "plains", "savanna" },
	y_min = 4, y_max = 120,
	schematic = make_station(),
	place_offset_y = -1,
	flags = "place_center_x, place_center_z, force_placement",
})

-- abandoned cars appear near pumps
core.register_abm({
	label = "abandoned vehicles",
	nodenames = { "scavock_vehicles:pump" },
	interval = 47, chance = 12,
	action = function(pos)
		for obj in core.objects_inside_radius(pos, 24) do
			local ent = obj:get_luaentity()
			if ent and ent._vehicle then return end
		end
		local p = { x = pos.x + math.random(-3, 3), y = pos.y + 1,
			z = pos.z + math.random(-3, 3) }
		if core.get_node(p).name == "air" then
			core.add_entity(p, "scavock_vehicles:car")
		end
	end,
})

-- pumps dispense oil into the fuel economy
core.register_abm({
	label = "pump stock",
	nodenames = { "scavock_vehicles:pump" },
	interval = 210, chance = 4,
	action = function(pos)
		core.add_item({ x = pos.x, y = pos.y + 1, z = pos.z },
			"scavock_power:oil")
	end,
})

-- ---------------------------------------------------------------------------
-- Fishing (§24.10 surface content)
-- ---------------------------------------------------------------------------
core.register_craftitem("scavock_vehicles:fish", {
	description = "Fish (cook it)",
	inventory_image = "scavock_fish.png",
	on_use = function(itemstack, user)
		if scavock_survival then scavock_survival.feed(user, 8, 4, 0) end
		itemstack:take_item()
		return itemstack
	end,
})
core.register_craft({ type = "cooking", output = "scavock_survival:meat_cooked",
	recipe = "scavock_vehicles:fish", cooktime = 3 })

local fishing = {}
core.register_tool("scavock_vehicles:rod", {
	description = "Fishing Rod (use near water, wait, hope)",
	inventory_image = "scavock_rod.png",
	on_use = function(itemstack, user)
		local name = user:get_player_name()
		if fishing[name] then return itemstack end
		-- must be pointing at / standing near water
		local pos = user:get_pos()
		local near_water = false
		for _, d in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 }, { 3, 0 }, { 0, 3 } }) do
			local n = core.get_node({ x = pos.x + d[1], y = pos.y - 0.5, z = pos.z + d[2] })
			if core.get_item_group(n.name, "water") > 0 then
				near_water = true
				break
			end
		end
		if not near_water then
			core.chat_send_player(name, "Find water first.")
			return itemstack
		end
		fishing[name] = true
		core.chat_send_player(name, "Line's in. Stay put.")
		core.after(math.random(6, 15), function()
			fishing[name] = nil
			local p = core.get_player_by_name(name)
			if not p then return end
			if vector.distance(p:get_pos(), pos) > 2 then
				core.chat_send_player(name, "You wandered off. The line came up empty.")
				return
			end
			if math.random(3) > 1 then
				scavock.p_add(p, "scavock_vehicles:fish")
				core.chat_send_player(name, "A bite — fish landed.")
			else
				core.chat_send_player(name, "Nothing. Cast again.")
			end
		end)
		itemstack:add_wear(65535 / 80)
		return itemstack
	end,
})
core.register_craft({ output = "scavock_vehicles:rod",
	recipe = { { "", "", "scavock_core:stick" },
		{ "", "scavock_core:stick", "scavock_power:wire" },
		{ "scavock_core:stick", "", "scavock_power:wire" } } })
