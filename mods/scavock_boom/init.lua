-- Explosives & breaching (§16).
--
-- Trigger bombs: grenade + sensor crafted AS A LINKED PAIR — placing the
-- bomb hands you its linked trigger button. The button detonates remotely
-- (range-limited: §16 open — the limited answer keeps the demolitionist
-- in the danger zone) and is consumed on use with a partial refund.
--
-- Disarming (§16 confirmed): a placed, undetonated bomb can be disarmed.
-- If detonation occurs mid-disarm, the detonation is TAMPERED — glitched
-- and delayed just enough for the target to escape the blast. This
-- counters trigger-spam against people without weakening bombs against
-- structures.
--
-- Chain reactions (§16 confirmed): explosions set off nearby placed bombs.

local TRIGGER_RANGE = 60
local TAMPER_DELAY = 3

scavock_boom = {}

-- ---------------------------------------------------------------------------
-- The explosion
-- ---------------------------------------------------------------------------
local PROTECTED = {
	["scavock_world:safezone_core"] = true,
	["ignore"] = true,
}

function scavock_boom.explode(pos, radius, max_damage)
	if scavock.noise then
		scavock.noise(pos, "explosion", nil)
	end
	-- entities and players
	for obj in core.objects_inside_radius(pos, radius * 2.5) do
		local d = vector.distance(pos, obj:get_pos())
		local dmg = math.max(1, math.floor(max_damage * (1 - d / (radius * 2.5))))
		local dir = vector.direction(pos, obj:get_pos())
		obj:punch(obj, 1.0, { full_punch_interval = 1.0,
			damage_groups = { fleshy = dmg } }, dir)
		if obj.add_velocity then
			obj:add_velocity({ x = dir.x * 8, y = 6, z = dir.z * 8 })
		end
	end
	-- voxels: §4 the world is diggable, and it breaks
	for dx = -radius, radius do
		for dy = -radius, radius do
			for dz = -radius, radius do
				if dx * dx + dy * dy + dz * dz <= radius * radius then
					local np = { x = pos.x + dx, y = pos.y + dy, z = pos.z + dz }
					local name = core.get_node(np).name
					if name ~= "air" and not PROTECTED[name]
							and core.get_item_group(name, "liquid") == 0 then
						-- chain reactions (§16 confirmed)
						if name == "scavock_boom:tnt"
								or name == "scavock_boom:placed_bomb" then
							core.after(0.4, function()
								if core.get_node(np).name == name then
									core.remove_node(np)
									scavock_boom.explode(np,
										name == "scavock_boom:tnt" and 3 or 3, 16)
								end
							end)
						else
							core.remove_node(np)
							if math.random(5) == 1 then
								local def = core.registered_nodes[name]
								if def and def.drop ~= "" then
									core.add_item(np, name)
								end
							end
						end
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- TNT — Minecraft-style raw yield
-- ---------------------------------------------------------------------------
core.register_node("scavock_boom:tnt", {
	description = "TNT (ignite with a torch in hand)",
	tiles = { "scavock_tnt.png" },
	groups = { choppy = 2, oddly_breakable_by_hand = 2, flammable = 1 },
	on_punch = function(pos, node, puncher)
		if puncher and puncher:get_wielded_item():get_name()
				== "scavock_power:torch" then
			core.swap_node(pos, { name = "scavock_boom:tnt_lit" })
			core.get_node_timer(pos):start(4)
			core.chat_send_player(puncher:get_player_name(), "Lit. RUN.")
		end
	end,
})
core.register_node("scavock_boom:tnt_lit", {
	description = "TNT (lit)",
	tiles = { "scavock_tnt_lit.png" },
	light_source = 6,
	groups = { not_in_creative_inventory = 1 },
	drop = "",
	on_timer = function(pos)
		core.remove_node(pos)
		scavock_boom.explode(pos, 3, 18)
	end,
})
core.register_craft({ output = "scavock_boom:tnt",
	recipe = { { "scavock_core:coal_lump", "scavock_core:coal_lump" },
		{ "scavock_power:oil", "scavock_core:coal_lump" } } })

-- ---------------------------------------------------------------------------
-- Grenade — thrown
-- ---------------------------------------------------------------------------
core.register_entity("scavock_boom:grenade_ent", {
	initial_properties = {
		physical = true, collide_with_objects = false,
		visual = "sprite", textures = { "scavock_grenade.png" },
		visual_size = { x = 0.4, y = 0.4 }, static_save = false,
		collisionbox = { -0.1, -0.1, -0.1, 0.1, 0.1, 0.1 },
	},
	_t = 0,
	on_step = function(self, dtime)
		self._t = self._t + dtime
		if self._t > 2.5 then
			local pos = self.object:get_pos()
			self.object:remove()
			scavock_boom.explode(pos, 1, 12)
		end
	end,
})

core.register_craftitem("scavock_boom:grenade", {
	description = "Grenade (throw it)",
	inventory_image = "scavock_grenade.png",
	on_use = function(itemstack, user)
		local pos = vector.add(user:get_pos(), { x = 0, y = 1.5, z = 0 })
		local dir = user:get_look_dir()
		local obj = core.add_entity(vector.add(pos, dir), "scavock_boom:grenade_ent")
		if obj then
			obj:set_velocity(vector.multiply(dir, 14))
			obj:set_acceleration({ x = 0, y = -12, z = 0 })
		end
		itemstack:take_item()
		return itemstack
	end,
})
core.register_craft({ type = "shapeless", output = "scavock_boom:grenade",
	recipe = { "scavock_core:scrap_ingot", "scavock_core:coal_lump",
		"scavock_power:oil" } })

-- ---------------------------------------------------------------------------
-- Sensors and buttons — electronics with universal demand (§16)
-- ---------------------------------------------------------------------------
core.register_craftitem("scavock_boom:sensor", {
	description = "Sensor (demolition component — contested loot)",
	inventory_image = "scavock_sensor.png",
})
core.register_craftitem("scavock_boom:button", {
	description = "Button",
	inventory_image = "scavock_button.png",
})
core.register_craft({ type = "shapeless", output = "scavock_boom:sensor",
	recipe = { "scavock_core:copper_ingot", "scavock_power:plastic",
		"scavock_power:wire" } })
core.register_craft({ type = "shapeless", output = "scavock_boom:button",
	recipe = { "scavock_core:copper_ingot", "scavock_power:plastic" } })

-- ---------------------------------------------------------------------------
-- Trigger bomb: grenade + sensor -> linked pair at craft time
-- ---------------------------------------------------------------------------
core.register_craftitem("scavock_boom:trigger_bomb", {
	description = "Trigger Bomb\nPlace it — the linked trigger button lands"
		.. " in your pack.",
	inventory_image = "scavock_trigger_bomb.png",
	stack_max = 1,
	on_place = function(itemstack, placer, pointed)
		if pointed.type ~= "node" then return itemstack end
		local pos = pointed.above
		if core.get_node(pos).name ~= "air" then return itemstack end
		local link = itemstack:get_meta():get_string("link")
		core.set_node(pos, { name = "scavock_boom:placed_bomb" })
		core.get_meta(pos):set_string("link", link)
		core.get_meta(pos):set_string("infotext", "Placed charge")
		-- both halves crafted in one operation, linked at craft time (§16):
		-- the button follows the bomb into the field
		local button = ItemStack("scavock_boom:trigger_button")
		button:get_meta():set_string("link", link)
		button:get_meta():set_string("description",
			"Trigger Button (linked)\nDetonates within " .. TRIGGER_RANGE .. " blocks.")
		local leftover = scavock.p_add(placer, button)
		if not leftover:is_empty() then
			core.add_item(placer:get_pos(), leftover)
		end
		itemstack:take_item()
		return itemstack
	end,
})

table.insert(scavock.craft_postprocess, function(itemstack, craftlist)
	if itemstack:get_name() == "scavock_boom:trigger_bomb"
			and itemstack:get_meta():get_string("link") == "" then
		itemstack:get_meta():set_string("link",
			tostring(math.random(2 ^ 30)) .. tostring(math.random(2 ^ 30)))
	end
	return itemstack
end)

core.register_craft({ type = "shapeless", output = "scavock_boom:trigger_bomb",
	recipe = { "scavock_boom:grenade", "scavock_boom:sensor" } })

-- disarm state: link -> { name = disarmer }
local disarming_links = {}
local tampered = {}

core.register_node("scavock_boom:placed_bomb", {
	description = "Placed Charge",
	drawtype = "nodebox",
	tiles = { "scavock_trigger_bomb.png" },
	paramtype = "light",
	node_box = { type = "fixed", fixed = { -0.3, -0.5, -0.3, 0.3, -0.1, 0.3 } },
	groups = { snappy = 3, not_in_creative_inventory = 1 },
	drop = "",
	-- Disarming (§16): right-click, 3 seconds; interrupted-by-detonation
	-- tampers the blast instead
	on_rightclick = function(pos, node, clicker)
		local name = clicker:get_player_name()
		local link = core.get_meta(pos):get_string("link")
		disarming_links[link] = { name = name, pos = pos }
		core.chat_send_player(name, "Disarming... 3 seconds.")
		core.after(3, function()
			local d = disarming_links[link]
			if not d or d.name ~= name then return end
			disarming_links[link] = nil
			if core.get_node(pos).name == "scavock_boom:placed_bomb" then
				core.remove_node(pos)
				local player = core.get_player_by_name(name)
				if player then
					scavock.p_add(player, "scavock_boom:grenade")
					scavock.p_add(player, "scavock_boom:sensor")
					core.chat_send_player(name, "Disarmed — parts recovered.")
				end
			end
		end)
	end,
})

core.register_craftitem("scavock_boom:trigger_button", {
	description = "Trigger Button (linked)",
	inventory_image = "scavock_trigger_button.png",
	stack_max = 1,
	on_use = function(itemstack, user)
		local link = itemstack:get_meta():get_string("link")
		local name = user:get_player_name()
		local upos = user:get_pos()
		local fired = false
		-- find linked charges in range
		local found = core.find_nodes_in_area(
			vector.subtract(upos, TRIGGER_RANGE),
			vector.add(upos, TRIGGER_RANGE), "scavock_boom:placed_bomb")
		for _, pos in ipairs(found) do
			if core.get_meta(pos):get_string("link") == link then
				fired = true
				local d = disarming_links[link]
				if d then
					-- TAMPERED: mid-disarm detonation glitches and delays —
					-- the disarmer escapes the blast (§16 confirmed)
					disarming_links[link] = nil
					core.chat_send_player(d.name,
						"The charge glitches — it's going to blow. RUN.")
					core.chat_send_player(name,
						"Detonation tampered — delayed.")
					core.after(TAMPER_DELAY, function()
						if core.get_node(pos).name == "scavock_boom:placed_bomb" then
							core.remove_node(pos)
							scavock_boom.explode(pos, 3, 16)
						end
					end)
				else
					core.remove_node(pos)
					scavock_boom.explode(pos, 3, 16)
				end
			end
		end
		if not fired then
			core.chat_send_player(name, "No linked charge in range ("
				.. TRIGGER_RANGE .. " blocks).")
			return itemstack
		end
		-- consumed on use, partial refund (§16)
		scavock.p_add(user, "scavock_boom:button")
		return ItemStack("")
	end,
})
