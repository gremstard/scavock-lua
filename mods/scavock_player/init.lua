-- Scavock player rules.
-- Design doc §7: STEP_HEIGHT = 1.0 (walk up single blocks, no jump),
-- unlimited sprint (no stamina meter), weight governs speed (never below 0.6x),
-- long TTK. §12: knocked out = full inventory drops. §10: spawn with nothing.

local SPRINT_MULT = 1.65      -- §7 movement constants
local MIN_WEIGHT_MULT = 0.6   -- §7: "never below roughly 0.6x"
local STEP_HEIGHT = 1.1       -- §7 STEP_HEIGHT = 1.0 (+0.1 so the engine clears it)

core.register_on_joinplayer(function(player)
	-- inventory size and formspec are owned by scavock_grid (§9 grid inventory)
	player:set_properties({ stepheight = STEP_HEIGHT })
	-- Visual identity (SCAVOCK_Visual_Identity.md): charcoal surfaces, slate
	-- raised states, chartreuse reserved for selection/primary action
	player:set_formspec_prepend(table.concat({
		"bgcolor[#101114D0;true]",
		"listcolors[#1C1E23;#2A2D34;#101114;#B6D62E;#101114]",
		"style_type[button,image_button,item_image_button;",
			"bgcolor=#1C1E23;textcolor=#E4E0D4;border=false]",
		"style_type[button:hovered;bgcolor=#2A2D34]",
		"style_type[label;textcolor=#E4E0D4]",
		"style_type[field;textcolor=#E4E0D4]",
	}))
	player:hud_set_hotbar_image("scavock_hotbar_slot.png")
	player:hud_set_hotbar_selected_image("scavock_hotbar_selected.png")
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
-- Sprint input (D6, both implemented in the Scavock engine fork): double-tap
-- forward, or hold Shift (the default aux1 binding). Both reach the server as
-- the aux1 control bit; the ctrl.up check below keeps sprint forward-only.
-- No stamina meter — sprint is unlimited (§7 Confirmed).
-- ---------------------------------------------------------------------------
local sprint_state = {}

local function weight_mult(player)
	-- occupied grid cells stand in for carried weight (§7: weight is a speed
	-- disadvantage only; capacity is already the grid's job)
	local inv = player:get_inventory()
	local size = inv:get_size("main")
	local cells = 0
	for i = 1, size do
		local st = inv:get_stack("main", i)
		if not st:is_empty() then
			local isz = scavock.item_size(st:get_name())
			cells = cells + isz.w * isz.h
		end
	end
	local frac = math.min(cells / size, 1)
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
		-- stagger (scavock_combat): brief hard slow, chance-based (§7)
		if scavock.stagger_mult then
			mult = mult * scavock.stagger_mult(name)
		end
		-- downed (scavock_death, §12): crawling pace
		if scavock.crawl_mult then
			mult = mult * scavock.crawl_mult(name)
		end
		-- broken leg (scavock_survival, §13)
		if scavock.leg_mult then
			mult = mult * scavock.leg_mult(name)
		end
		-- reinforcement speed perk (scavock_gear, §11)
		if scavock.gear_mult then
			mult = mult * scavock.gear_mult(name)
		end
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
	local name = player:get_player_name()
	if scavock.suppress_drop and scavock.suppress_drop[name] then
		-- swallowed by a Man Eater (§24.5): loot destroyed, no drops
		player:get_inventory():set_list("main", {})
		core.after(0, function() scavock.suppress_drop[name] = nil end)
		return
	end
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
