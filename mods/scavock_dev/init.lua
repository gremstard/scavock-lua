-- Structure authoring, in-engine (D14/§29): build it in the world, select
-- two corners, save it, and worldgen stamps it. Never authored in external
-- tools — the doc rules that out by construction.
--
-- Workflow:
--   /devwand              -> get the selection wand (punch = pos1,
--                            right-click = pos2)
--   /struct save <name>   -> save the selected region
--   /struct place <name>  -> stamp it where you stand (test/variants)
--   /struct list | delete <name>
--
-- ABANDONED CITIES (§4: plains are bare, and bare is what makes them the
-- site of abandoned cities): any structure saved with a name starting
-- "city_" joins the building pool. Plains chunks then generate city
-- blocks — clusters of your buildings around concrete streets. No city_
-- structures saved yet = no cities yet; go build.

local storage = core.get_mod_storage()
local MAX_DIM = 48

local sel = {} -- name -> { p1, p2 }

core.register_craftitem("scavock_dev:wand", {
	description = "Structure Wand (dev)\nPunch: corner 1. Right-click: corner 2.",
	inventory_image = "scavock_wand.png",
	stack_max = 1,
	on_use = function(itemstack, user, pointed)
		if pointed.type ~= "node" then return itemstack end
		local name = user:get_player_name()
		sel[name] = sel[name] or {}
		sel[name].p1 = vector.new(pointed.under)
		core.chat_send_player(name, "Corner 1: " .. core.pos_to_string(pointed.under))
		return itemstack
	end,
	on_place = function(itemstack, user, pointed)
		if pointed.type ~= "node" then return itemstack end
		local name = user:get_player_name()
		sel[name] = sel[name] or {}
		sel[name].p2 = vector.new(pointed.under)
		core.chat_send_player(name, "Corner 2: " .. core.pos_to_string(pointed.under))
		return itemstack
	end,
})

core.register_chatcommand("devwand", {
	privs = { server = true },
	description = "Get the structure selection wand",
	func = function(name)
		local player = core.get_player_by_name(name)
		if player then
			scavock.p_add(player, "scavock_dev:wand")
			return true, "Wand added."
		end
	end,
})

local function struct_names()
	local list = core.deserialize(storage:get_string("index")) or {}
	return list
end

local function save_index(list)
	storage:set_string("index", core.serialize(list))
end

local function save_struct(name, p1, p2)
	local minp = { x = math.min(p1.x, p2.x), y = math.min(p1.y, p2.y),
		z = math.min(p1.z, p2.z) }
	local maxp = { x = math.max(p1.x, p2.x), y = math.max(p1.y, p2.y),
		z = math.max(p1.z, p2.z) }
	local size = vector.add(vector.subtract(maxp, minp), 1)
	if size.x > MAX_DIM or size.y > MAX_DIM or size.z > MAX_DIM then
		return nil, ("Too big (max %d each axis)."):format(MAX_DIM)
	end
	local nodes = {}
	for z = 0, size.z - 1 do
		for y = 0, size.y - 1 do
			for x = 0, size.x - 1 do
				local n = core.get_node({ x = minp.x + x, y = minp.y + y,
					z = minp.z + z })
				nodes[#nodes + 1] = { n.name, n.param2 }
			end
		end
	end
	storage:set_string("struct_" .. name,
		core.serialize({ size = size, nodes = nodes }))
	local idx = struct_names()
	local found = false
	for _, n in ipairs(idx) do
		if n == name then found = true end
	end
	if not found then
		idx[#idx + 1] = name
		save_index(idx)
	end
	return size
end

function scavock_dev_place_struct(name, base)
	local data = core.deserialize(storage:get_string("struct_" .. name))
	if not data then return false end
	local i = 0
	for z = 0, data.size.z - 1 do
		for y = 0, data.size.y - 1 do
			for x = 0, data.size.x - 1 do
				i = i + 1
				local rec = data.nodes[i]
				if rec[1] ~= "ignore" then
					core.set_node({ x = base.x + x, y = base.y + y,
						z = base.z + z }, { name = rec[1], param2 = rec[2] })
				end
			end
		end
	end
	return true, data.size
end

core.register_chatcommand("struct", {
	privs = { server = true },
	params = "save <name> | place <name> | list | delete <name>",
	description = "Structure authoring (D14): save/stamp world regions",
	func = function(name, param)
		local cmd, sname = param:match("^(%a+)%s*(.*)$")
		if cmd == "save" and sname ~= "" then
			local s = sel[name]
			if not (s and s.p1 and s.p2) then
				return false, "Select two corners with the wand first."
			end
			local size, err = save_struct(sname, s.p1, s.p2)
			if not size then return false, err end
			local note = sname:sub(1, 5) == "city_"
				and " It's in the CITY pool — plains will grow it."
				or " (Name it city_* to feed the city generator.)"
			return true, ("Saved '%s' (%dx%dx%d).%s")
				:format(sname, size.x, size.y, size.z, note)
		elseif cmd == "place" and sname ~= "" then
			local player = core.get_player_by_name(name)
			if not player then return false end
			local ok = scavock_dev_place_struct(sname,
				vector.round(vector.add(player:get_pos(), { x = 2, y = 0, z = 2 })))
			return ok, ok and "Stamped." or "No such structure."
		elseif cmd == "list" then
			local idx = struct_names()
			return true, #idx == 0 and "None saved yet."
				or table.concat(idx, ", ")
		elseif cmd == "delete" and sname ~= "" then
			storage:set_string("struct_" .. sname, "")
			local idx, out = struct_names(), {}
			for _, n in ipairs(idx) do
				if n ~= sname then out[#out + 1] = n end
			end
			save_index(out)
			return true, "Deleted."
		end
		return false, "Usage: /struct save|place|list|delete <name>"
	end,
})

-- ---------------------------------------------------------------------------
-- Abandoned cities: generated from the saved city_* building pool
-- ---------------------------------------------------------------------------
local function city_pool()
	local out = {}
	for _, n in ipairs(struct_names()) do
		if n:sub(1, 5) == "city_"
				and storage:get_string("struct_" .. n) ~= "" then
			out[#out + 1] = n
		end
	end
	return out
end

local function ground_at(x, z, ymin, ymax)
	for y = ymax, ymin, -1 do
		local n = core.get_node({ x = x, y = y, z = z }).name
		if n ~= "air" and n ~= "ignore" then
			return y
		end
	end
end

core.register_on_generated(function(minp, maxp, blockseed)
	if minp.y > 60 or maxp.y < 0 then return end
	local pool = city_pool()
	if #pool == 0 then return end
	local rng = PcgRandom(blockseed + 77)
	if rng:next(1, 40) ~= 1 then return end
	local cx = math.floor((minp.x + maxp.x) / 2)
	local cz = math.floor((minp.z + maxp.z) / 2)
	core.after(0.6, function()
		local gy = ground_at(cx, cz, 2, 80)
		if not gy or gy < 3 then return end
		-- only on open dry ground (the plains rule)
		local surface = core.get_node({ x = cx, y = gy, z = cz }).name
		if surface ~= "scavock_core:dirt_with_dry_grass"
				and surface ~= "scavock_core:dirt_with_grass" then
			return
		end
		-- streets: a concrete cross
		for d = -18, 18 do
			for w = -1, 1 do
				core.set_node({ x = cx + d, y = gy, z = cz + w },
					{ name = "scavock_core:concrete_cracked" })
				core.set_node({ x = cx + w, y = gy, z = cz + d },
					{ name = "scavock_core:concrete_cracked" })
			end
		end
		-- buildings in the four quadrants
		for _, q in ipairs({ { 4, 4 }, { -16, 4 }, { 4, -16 }, { -16, -16 } }) do
			if rng:next(1, 4) > 1 then
				local sname = pool[rng:next(1, #pool)]
				scavock_dev_place_struct(sname,
					{ x = cx + q[1], y = gy + 1, z = cz + q[2] })
			end
		end
	end)
end)
