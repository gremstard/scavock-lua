-- Compasses (§4c). A general navigation SYSTEM, not one special item.
--
-- Default: points north. Punch (use) while pointing at a block, item, or
-- person to bind that as the compass's "north" — binding requires PHYSICAL
-- PROXIMITY, which is the critical constraint: you cannot remotely track
-- anyone. Right-click resets to true north; resetting discards the binding.
-- One compass, one target, no mode switching.
--
-- Target continuity (§4c table):
--   block broken     -> follows the dropped item, and whoever picks it up
--   item despawns    -> SPINS (the reset-needed signal)
--   player offline   -> last known location; back online -> live again
--
-- Consequence kept: a compass is a social object. Tracking an item means
-- tracking whoever carries it — accepting a trade may mean accepting a
-- tracker. The Cavock compass (scavock_under) is a preset instance of
-- this same system, locked to the Icelands city.

scavock_compass = {}

-- runtime object tracking: compass uid -> ObjectRef (item entities)
local tracked_obj = {}

local function compass_uid(meta)
	local uid = meta:get_string("uid")
	if uid == "" then
		uid = tostring(math.random(2 ^ 30)) .. tostring(math.random(2 ^ 30))
		meta:set_string("uid", uid)
	end
	return uid
end

local function bind(itemstack, user, pointed)
	local meta = itemstack:get_meta()
	if meta:get_string("preset") ~= "" then
		core.chat_send_player(user:get_player_name(),
			"This compass is locked to something far colder.")
		return itemstack
	end
	compass_uid(meta)
	if pointed.type == "node" then
		local pos = pointed.under
		meta:set_string("t_type", "node")
		meta:set_string("t_pos", core.pos_to_string(pos))
		meta:set_string("t_node", core.get_node(pos).name)
		meta:set_string("description", "Compass (bound to a place)")
		core.chat_send_player(user:get_player_name(), "Compass bound to the block.")
	elseif pointed.type == "object" then
		local ref = pointed.ref
		if ref:is_player() then
			meta:set_string("t_type", "player")
			meta:set_string("t_name", ref:get_player_name())
			meta:set_string("t_pos", core.pos_to_string(vector.round(ref:get_pos())))
			meta:set_string("description",
				"Compass (bound to " .. ref:get_player_name() .. ")")
			core.chat_send_player(user:get_player_name(),
				"Compass bound to " .. ref:get_player_name()
				.. ". They don't know.")
		else
			meta:set_string("t_type", "object")
			tracked_obj[meta:get_string("uid")] = ref
			meta:set_string("t_pos", core.pos_to_string(vector.round(ref:get_pos())))
			meta:set_string("description", "Compass (bound to something loose)")
			core.chat_send_player(user:get_player_name(), "Compass bound.")
		end
	end
	return itemstack
end

local function reset(itemstack, user)
	local meta = itemstack:get_meta()
	if meta:get_string("preset") ~= "" then return itemstack end
	meta:set_string("t_type", "")
	meta:set_string("description", "Compass (points north)")
	core.chat_send_player(user:get_player_name(),
		"Reset to true north. The old target is gone for good.")
	return itemstack
end

core.register_craftitem("scavock_compass:compass", {
	description = "Compass (points north)\nUse on a block/item/person to bind;"
		.. " right-click resets.",
	inventory_image = "scavock_compass.png",
	stack_max = 1,
	on_use = function(itemstack, user, pointed)
		if pointed and pointed.type ~= "nothing" then
			return bind(itemstack, user, pointed)
		end
		return itemstack
	end,
	on_secondary_use = reset,
	on_place = function(itemstack, user) return reset(itemstack, user) end,
})
core.register_craft({ output = "scavock_compass:compass",
	recipe = { { "", "scavock_core:iron_ingot", "" },
		{ "scavock_core:iron_ingot", "scavock_core:copper_ingot",
			"scavock_core:iron_ingot" },
		{ "", "scavock_core:iron_ingot", "" } } })

-- resolve a compass stack's current target position ("spin" -> nil + true)
function scavock_compass.resolve(meta, holder_pos)
	if meta:get_string("preset") == "icelands" and scavock.icelands_pos then
		return scavock.icelands_pos(), false
	end
	local t = meta:get_string("t_type")
	if t == "" then
		return { x = holder_pos.x, y = holder_pos.y, z = holder_pos.z + 500 }, false
	end
	if t == "player" then
		local target = core.get_player_by_name(meta:get_string("t_name"))
		if target then
			meta:set_string("t_pos",
				core.pos_to_string(vector.round(target:get_pos())))
			return target:get_pos(), false
		end
		return core.string_to_pos(meta:get_string("t_pos")), false -- last known
	end
	if t == "node" then
		local pos = core.string_to_pos(meta:get_string("t_pos"))
		if pos and core.get_node_or_nil(pos) then
			if core.get_node(pos).name == meta:get_string("t_node") then
				return pos, false
			end
			-- block broken: follow the dropped item (§4c continuity)
			local uid = meta:get_string("uid")
			for obj in core.objects_inside_radius(pos, 24) do
				local ent = obj:get_luaentity()
				if ent and ent.name == "__builtin:item"
						and ent.itemstring:find(meta:get_string("t_node"), 1, true) then
					meta:set_string("t_type", "object")
					tracked_obj[uid] = obj
					return obj:get_pos(), false
				end
			end
			-- maybe someone already picked it up: nearest player to the site
			local best, bestd
			for _, p in ipairs(core.get_connected_players()) do
				local d = vector.distance(p:get_pos(), pos)
				if d < 12 and (not bestd or d < bestd) then best, bestd = p, d end
			end
			if best then
				meta:set_string("t_type", "player")
				meta:set_string("t_name", best:get_player_name())
				return best:get_pos(), false
			end
			return nil, true -- spins
		end
		return pos, false -- unloaded: point at remembered spot
	end
	if t == "object" then
		local obj = tracked_obj[meta:get_string("uid")]
		if obj and obj:get_pos() then
			meta:set_string("t_pos", core.pos_to_string(vector.round(obj:get_pos())))
			return obj:get_pos(), false
		end
		-- item gone: picked up (track nearest player) or despawned (spin)
		local last = core.string_to_pos(meta:get_string("t_pos"))
		if last then
			for _, p in ipairs(core.get_connected_players()) do
				if vector.distance(p:get_pos(), last) < 6 then
					meta:set_string("t_type", "player")
					meta:set_string("t_name", p:get_player_name())
					return p:get_pos(), false
				end
			end
		end
		return nil, true
	end
	return nil, true
end

-- ---------------------------------------------------------------------------
-- HUD: a waypoint marker for the first compass in the pack
-- ---------------------------------------------------------------------------
local huds = {}
local tick = 0

core.register_globalstep(function(dtime)
	tick = tick + dtime
	if tick < 1 then return end
	tick = 0
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local compass_meta
		scavock.p_each(player, function(inv, list, i, st)
			if compass_meta then return end
			if st:get_name():find("^scavock_compass:")
					or st:get_name() == "scavock_under:compass_cavock" then
				compass_meta = st:get_meta()
				local pos, spin = scavock_compass.resolve(compass_meta,
					player:get_pos())
				if spin or not pos then
					pos = vector.add(player:get_pos(), {
						x = math.random(-9, 9), y = 0, z = math.random(-9, 9) })
				end
				if huds[name] then
					player:hud_change(huds[name], "world_pos", pos)
				else
					huds[name] = player:hud_add({
						type = "waypoint", name = "◈",
						number = 0xB6D62E, world_pos = pos,
						precision = 0,
					})
				end
				return st
			end
		end)
		if not compass_meta and huds[name] then
			player:hud_remove(huds[name])
			huds[name] = nil
		end
	end
end)

core.register_on_leaveplayer(function(player)
	huds[player:get_player_name()] = nil
end)
