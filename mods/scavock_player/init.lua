-- Scavock player rules.
-- Design doc §7: STEP_HEIGHT = 1.0 (walk up single blocks, no jump),
-- unlimited sprint (no stamina meter), weight governs speed (never below 0.6x),
-- long TTK. §12: knocked out = full inventory drops. §10: spawn with nothing.

local SPRINT_MULT = 1.65      -- §7 movement constants
local MIN_WEIGHT_MULT = 0.6   -- §7: "never below roughly 0.6x"
local STEP_HEIGHT = 1.1       -- §7 STEP_HEIGHT = 1.0 (+0.1 so the engine clears it)

-- ---------------------------------------------------------------------------
-- Inventory formspec: grid backpack + vault/stash access.
-- (True Tarkov-style multi-cell grid inventory is an engine-level feature
-- Luanti doesn't have; slot grid stands in for it. Recorded in README.)
-- ---------------------------------------------------------------------------
local function inventory_formspec()
	return table.concat({
		"formspec_version[6]", "size[10.7,7.4]",
		"label[0.4,0.5;Backpack]",
		"list[current_player;main;0.4,0.9;8,4;]",
		"button[0.4,5.9;3,0.9;vault;Vault]",
		"button[3.6,5.9;3,0.9;stash;Extraction Stash]",
		"label[6.9,6.35;Craft at a Workbench]",
	})
end

core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	inv:set_size("main", 32)
	player:set_inventory_formspec(inventory_formspec())
	player:set_properties({ stepheight = STEP_HEIGHT })
	-- remember first-ever spawn as "home" for evac teleport
	local meta = player:get_meta()
	if meta:get_string("scavock_home") == "" then
		meta:set_string("scavock_home", core.pos_to_string(vector.round(player:get_pos())))
	end
end)

-- §10 spawn state: "players spawn with only shorts equipped" — nothing usable.
core.register_on_newplayer(function(player)
	player:get_inventory():set_list("main", {})
end)

-- ---------------------------------------------------------------------------
-- Sprint + carried-weight speed. One physics override, recomputed cheaply.
-- Sprint input: Aux1 (default E) or double-tap forward if the client has
-- pressing W twice bound; Luanti servers only see Aux1, so that is the input.
-- No stamina meter — sprint is unlimited (§7 Confirmed).
-- ---------------------------------------------------------------------------
local sprint_state = {}

local function weight_mult(player)
	-- fill fraction of the backpack stands in for carried weight
	local inv = player:get_inventory()
	local filled, size = 0, inv:get_size("main")
	for i = 1, size do
		local st = inv:get_stack("main", i)
		if not st:is_empty() then
			filled = filled + st:get_count() / st:get_stack_max()
		end
	end
	local frac = math.min(filled / size, 1)
	return 1 - (1 - MIN_WEIGHT_MULT) * frac
end

local accum = 0
core.register_globalstep(function(dtime)
	accum = accum + dtime
	if accum < 0.2 then return end
	accum = 0
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local ctrl = player:get_player_control()
		local sprinting = ctrl.aux1 and ctrl.up and not ctrl.sneak
		local mult = weight_mult(player) * (sprinting and SPRINT_MULT or 1)
		local prev = sprint_state[name]
		if not prev or math.abs(prev - mult) > 0.01 then
			sprint_state[name] = mult
			player:set_physics_override({ speed = mult })
		end
	end
end)

core.register_on_leaveplayer(function(player)
	sprint_state[player:get_player_name()] = nil
end)

-- ---------------------------------------------------------------------------
-- Death: full inventory drops where you fell (§12 "knocked out = true death,
-- full inventory drops"). Downed/revive two-stage model deferred — README.
-- ---------------------------------------------------------------------------
core.register_on_dieplayer(function(player)
	local pos = player:get_pos()
	local inv = player:get_inventory()
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		if not stack:is_empty() then
			local p = vector.add(pos, {
				x = math.random() - 0.5, y = 0.5, z = math.random() - 0.5 })
			core.add_item(p, stack)
			inv:set_stack("main", i, ItemStack(""))
		end
	end
	core.chat_send_player(player:get_player_name(),
		"Knocked out. Everything you carried is on the ground where you fell. "
		.. "Your vault and extraction stash are untouched.")
end)
