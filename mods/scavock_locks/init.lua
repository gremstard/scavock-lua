-- Containers, locks, and forcing them (§14).
--
-- Two lock types, two threat models:
--   PICKABLE — defeated with tools + skill. Picking makes noise, takes
--   time, requires practice (success grows with attempts), and the lock
--   may jam. Cheaper.
--   PASSCODE — cannot be picked at all. Only the code opens it; the only
--   other way through is force. More expensive.
--
-- Forcing a container is NEVER clean (§14, three outcomes):
--   LUCKY    — opens intact, everything available.
--   STANDARD — contents damaged/partially lost.
--   UNLUCKY  — it cracks open; you reach in through the hole, pulling out
--              one random item at a time. Some contents are unrecoverable.
-- Picking is strictly better IF you can do it — that is the payoff for
-- the tool-and-practice path.

local PICK_TIME = 6
local JAM_CHANCE = 0.2
local JAM_TIME = 60

-- session code-knowledge: name .. hash -> true
local knows = {}

local function is_locked(meta)
	return meta:get_string("lock") ~= ""
end

-- ---------------------------------------------------------------------------
-- Lock items: use them on a placed container
-- ---------------------------------------------------------------------------
local function apply_lock(itemstack, user, pointed, locktype)
	if pointed.type ~= "node" then return itemstack end
	local pos = pointed.under
	local name = core.get_node(pos).name
	if core.get_item_group(name, "scavock_container") == 0 then
		core.chat_send_player(user:get_player_name(), "That's not a container.")
		return itemstack
	end
	local meta = core.get_meta(pos)
	if is_locked(meta) then
		core.chat_send_player(user:get_player_name(), "Already locked.")
		return itemstack
	end
	meta:set_string("lock", locktype)
	meta:set_string("lock_owner", user:get_player_name())
	if locktype == "passcode" then
		core.show_formspec(user:get_player_name(), "scavock_locks:setcode",
			"formspec_version[6]size[7,3.4]"
			.. "field[0.4,1.0;6.2,0.9;code;Set the passcode;]"
			.. "button[0.4,2.1;6.2,0.9;setcode;LOCK]")
		user:get_meta():set_string("setting_code_at", core.pos_to_string(pos))
	end
	meta:set_string("infotext", (meta:get_string("infotext") or "Container")
		:gsub(" %[.*%]", "") .. " [" .. locktype .. " lock]")
	itemstack:take_item()
	return itemstack
end

core.register_craftitem("scavock_locks:lock_pickable", {
	description = "Pickable Lock (cheap — keeps out everyone without skill)",
	inventory_image = "scavock_lock_pickable.png",
	on_place = function(itemstack, user, pointed)
		return apply_lock(itemstack, user, pointed, "pickable")
	end,
})
core.register_craftitem("scavock_locks:lock_passcode", {
	description = "Passcode Lock (cannot be picked — force is the only other way)",
	inventory_image = "scavock_lock_passcode.png",
	on_place = function(itemstack, user, pointed)
		return apply_lock(itemstack, user, pointed, "passcode")
	end,
})
core.register_craftitem("scavock_locks:lockpick", {
	description = "Lockpick (practice makes better)",
	inventory_image = "scavock_lockpick.png",
})

core.register_craft({ output = "scavock_locks:lock_pickable",
	recipe = { { "scavock_core:iron_ingot" }, { "scavock_core:chain_link" } } })
core.register_craft({ output = "scavock_locks:lock_passcode",
	recipe = { { "scavock_core:copper_ingot", "scavock_core:iron_ingot" },
		{ "scavock_core:iron_ingot", "scavock_core:copper_ingot" } } })
core.register_craft({ output = "scavock_locks:lockpick 2",
	recipe = { { "scavock_core:scrap_ingot" }, { "scavock_core:stick" } } })

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "scavock_locks:setcode" and fields.code then
		local pos = core.string_to_pos(player:get_meta():get_string("setting_code_at"))
		if pos then
			core.get_meta(pos):set_string("lock_code", fields.code)
			core.chat_send_player(player:get_player_name(), "Code set. Don't forget it.")
		end
	elseif formname == "scavock_locks:entercode" and fields.code then
		local pos = core.string_to_pos(player:get_meta():get_string("entering_code_at"))
		if pos then
			local meta = core.get_meta(pos)
			if fields.code == meta:get_string("lock_code") then
				knows[player:get_player_name() .. core.hash_node_position(pos)] = true
				core.chat_send_player(player:get_player_name(), "It opens.")
			else
				core.chat_send_player(player:get_player_name(), "Wrong code.")
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Access gate + picking
-- ---------------------------------------------------------------------------
local picking = {} -- player -> { pos, t }

function scavock_locks_can_open(pos, player)
	local meta = core.get_meta(pos)
	if not is_locked(meta) then return true end
	local name = player:get_player_name()
	if meta:get_string("lock_owner") == name then return true end
	if knows[name .. core.hash_node_position(pos)] then return true end
	return false
end

local function try_open(pos, player)
	local meta = core.get_meta(pos)
	local name = player:get_player_name()
	if scavock_locks_can_open(pos, player) then return true end

	local locktype = meta:get_string("lock")
	if locktype == "passcode" then
		player:get_meta():set_string("entering_code_at", core.pos_to_string(pos))
		core.show_formspec(name, "scavock_locks:entercode",
			"formspec_version[6]size[7,3.4]"
			.. "field[0.4,1.0;6.2,0.9;code;Passcode;]"
			.. "button[0.4,2.1;6.2,0.9;enter;OPEN]")
		return false
	end

	-- pickable: needs a lockpick in hand
	if player:get_wielded_item():get_name() ~= "scavock_locks:lockpick" then
		core.chat_send_player(name,
			"Locked. Pick it (lockpick in hand), or break it — never cleanly.")
		return false
	end
	if meta:get_int("jam_until") > math.floor(core.get_gametime()) then
		core.chat_send_player(name, "The lock is jammed. Give it a minute.")
		return false
	end
	if picking[name] then return false end
	picking[name] = { pos = pos, t = PICK_TIME }
	core.chat_send_player(name, "Picking... stay close and quiet.")
	local function tick()
		local p = picking[name]
		if not p then return end
		local player2 = core.get_player_by_name(name)
		if not player2 or vector.distance(player2:get_pos(), p.pos) > 3 then
			picking[name] = nil
			return
		end
		-- picking makes noise (§14)
		if scavock.noise then
			scavock.noise(p.pos, 12, name)
		end
		p.t = p.t - 1
		if p.t > 0 then
			core.after(1, tick)
			return
		end
		picking[name] = nil
		local pmeta = player2:get_meta()
		local practice = pmeta:get_int("lockpicking")
		if math.random() < JAM_CHANCE then
			core.get_meta(p.pos):set_int("jam_until",
				math.floor(core.get_gametime()) + JAM_TIME)
			core.chat_send_player(name, "It jammed mid-attempt.")
			return
		end
		local chance = math.min(0.4 + practice * 0.05, 0.9)
		pmeta:set_int("lockpicking", practice + 1)
		if math.random() < chance then
			local cmeta = core.get_meta(p.pos)
			cmeta:set_string("lock", "")
			cmeta:set_string("infotext",
				(cmeta:get_string("infotext") or ""):gsub(" %[.*%]", "") .. " [picked]")
			core.chat_send_player(name, "Click. It's open.")
		else
			core.chat_send_player(name, "No luck. (Practice helps.)")
			if math.random(2) == 1 then
				local inv = player2:get_inventory()
				inv:remove_item("main", "scavock_locks:lockpick")
				core.chat_send_player(name, "The pick snapped.")
			end
		end
	end
	core.after(1, tick)
	return false
end

-- ---------------------------------------------------------------------------
-- Forcing: the three-outcome roll (§14)
-- ---------------------------------------------------------------------------
local function force_open(pos, node, digger)
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()
	local stacks = {}
	for i = 1, inv:get_size("main") do
		local st = inv:get_stack("main", i)
		if not st:is_empty() then stacks[#stacks + 1] = st end
	end
	local name = digger and digger:get_player_name()
	local roll = math.random()
	if scavock.noise then
		scavock.noise(pos, 26, name)
	end

	if roll < 0.2 then
		-- LUCKY: opens intact
		for _, st in ipairs(stacks) do core.add_item(pos, st) end
		core.remove_node(pos)
		core.add_item(pos, node.name)
		if name then core.chat_send_player(name, "Lucky — it comes apart intact.") end
	elseif roll < 0.7 then
		-- STANDARD: contents damaged or partially lost
		for _, st in ipairs(stacks) do
			local r = math.random()
			if r < 0.3 then
				-- lost entirely
			elseif r < 0.6 then
				st:set_count(math.max(1, math.floor(st:get_count() / 2)))
				core.add_item(pos, st)
			else
				core.add_item(pos, st)
			end
		end
		core.remove_node(pos)
		if name then core.chat_send_player(name,
			"It breaks open — some of what you came for breaks with it.") end
	else
		-- UNLUCKY: cracks open; reach in through the hole
		core.swap_node(pos, { name = "scavock_locks:cracked" })
		local cmeta = core.get_meta(pos)
		local cinv = cmeta:get_inventory()
		cinv:set_size("main", #stacks)
		for i, st in ipairs(stacks) do
			cinv:set_stack("main", i, st)
		end
		cmeta:set_string("infotext",
			"Cracked container — reach in (right-click), blind")
		if name then core.chat_send_player(name,
			"It cracks. You'll have to reach in through the hole.") end
	end
end

core.register_node("scavock_locks:cracked", {
	description = "Cracked Container",
	tiles = { "scavock_crate_cracked.png" },
	groups = { choppy = 1, not_in_creative_inventory = 1 },
	drop = "",
	on_rightclick = function(pos, node, clicker)
		local inv = core.get_meta(pos):get_inventory()
		local candidates = {}
		for i = 1, inv:get_size("main") do
			if not inv:get_stack("main", i):is_empty() then
				candidates[#candidates + 1] = i
			end
		end
		local name = clicker:get_player_name()
		if #candidates == 0 then
			core.remove_node(pos)
			core.chat_send_player(name, "Nothing left in reach.")
			return
		end
		local i = candidates[math.random(#candidates)]
		local st = inv:get_stack("main", i)
		inv:set_stack("main", i, ItemStack(""))
		if math.random() < 0.25 then
			core.chat_send_player(name,
				"Your hand closes on something broken. Unrecoverable.")
		else
			local take = st
			if st:get_count() > 1 and math.random(2) == 1 then
				take = ItemStack(st:get_name() .. " "
					.. math.random(1, st:get_count()))
			end
			core.add_item(vector.add(pos, { x = 0, y = 0.6, z = 0 }), take)
			core.chat_send_player(name, "You pull something out: "
				.. take:get_description():gsub("\n.*", ""))
		end
	end,
})

-- ---------------------------------------------------------------------------
-- Make the crate lockable + placeable, add the locker
-- ---------------------------------------------------------------------------
-- With on_rightclick defined the engine no longer auto-shows the node's
-- meta formspec, so open containers through a nodemeta: formspec instead.
local function show_container(pos, player, w, h, label)
	local loc = ("nodemeta:%d,%d,%d"):format(pos.x, pos.y, pos.z)
	local rows = math.ceil(h)
	core.show_formspec(player:get_player_name(), "scavock_locks:open",
		table.concat({
			"formspec_version[6]",
			("size[10.7,%f]"):format(2.0 + rows * 1.25 + 7.9),
			("label[0.4,0.5;%s]"):format(core.formspec_escape(label)),
			("list[%s;main;0.4,0.9;%d,%d;]"):format(loc, w, h),
			("list[current_player;main;0.4,%f;8,6;]"):format(1.4 + rows * 1.25),
			("listring[%s;main]"):format(loc),
			"listring[current_player;main]",
		}))
end

core.override_item("scavock_loot:crate", {
	groups = { choppy = 2, oddly_breakable_by_hand = 2, scavock_container = 1 },
	on_rightclick = function(pos, node, clicker)
		if not try_open(pos, clicker) then
			return
		end
		scavock_loot_fill_crate(pos)
		show_container(pos, clicker, 8, 2, "Supply Crate")
	end,
	on_dig = function(pos, node, digger)
		local meta = core.get_meta(pos)
		if is_locked(meta) or not meta:get_inventory():is_empty("main") then
			force_open(pos, node, digger)
			return true
		end
		return core.node_dig(pos, node, digger)
	end,
})

core.register_craft({ output = "scavock_loot:crate",
	recipe = { { "scavock_core:planks", "scavock_core:planks" },
		{ "scavock_core:planks", "scavock_core:planks" } } })

core.register_node("scavock_locks:locker", {
	description = "Locker (large container — roomy storage is raidable, §14)",
	tiles = { "scavock_locker.png" },
	paramtype2 = "facedir",
	groups = { cracky = 2, scavock_container = 1 },
	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_string("infotext", "Locker")
		meta:set_string("placed", "1")
		meta:get_inventory():set_size("main", 32)
	end,
	on_rightclick = function(pos, node, clicker)
		if try_open(pos, clicker) then
			show_container(pos, clicker, 8, 4, "Locker")
		end
	end,
	on_dig = function(pos, node, digger)
		local meta = core.get_meta(pos)
		if is_locked(meta) or not meta:get_inventory():is_empty("main") then
			force_open(pos, node, digger)
			return true
		end
		return core.node_dig(pos, node, digger)
	end,
})
core.register_craft({ output = "scavock_locks:locker",
	recipe = { { "scavock_core:scrap_ingot", "scavock_core:scrap_ingot" },
		{ "scavock_core:scrap_ingot", "scavock_core:scrap_ingot" },
		{ "scavock_core:planks", "scavock_core:planks" } } })
scavock.item_sizes["scavock_locks:locker"] = { 2, 3 }
