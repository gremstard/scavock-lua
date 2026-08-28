-- Two-stage death (§12).
--
-- HP empties -> KNOCKED DOWN, not killed. A downed player can crawl (slow,
-- no jump, no interacting, no attacking) and cannot be looted — nothing
-- drops until they are finished. One more hit finishes them -> KNOCKED OUT,
-- which is true death: the full inventory drops where they fell
-- (scavock_player handles the drop).
--
-- "Downing someone is the start of a decision, not the end of a fight":
-- the attacker must close in and finish, which costs time and exposure —
-- or walk away and let the target be revived.
--
-- Revives (§12 table): bare 10% HP / standard speed, med kit 20% / faster,
-- stabiliser 30% / fast. Another player right-clicks the downed player to
-- start one; both must stay close until it completes.

local CRAWL_MULT = 0.12
local REVIVE_RADIUS = 3
local BLEEDOUT = 90        -- §12 required: downed players eventually die
local SELF_REVIVE_TIME = 8 -- §12: slow and interruptible by damage

-- §12 revive table. Channel seconds are tuning (doc gives relative speeds).
local REVIVES = {
	bare = { hp_pct = 0.10, time = 6, item = nil },
	medkit = { hp_pct = 0.20, time = 4, item = "scavock_death:medkit" },
	stabiliser = { hp_pct = 0.30, time = 2, item = "scavock_death:stabiliser" },
}

-- name -> { hud_ids = {...}, had_interact = bool, bleedout, selfrev }
local downed_data = {}
-- target name -> { reviver, kind, t }
local revives = {}

function scavock.crawl_mult(name)
	return scavock.downed[name] and CRAWL_MULT or 1.0
end

-- ---------------------------------------------------------------------------
-- Items (loot-primary; recipes are grounded placeholders)
-- ---------------------------------------------------------------------------
core.register_craftitem("scavock_death:medkit", {
	description = "Med Kit\nRevives a downed player faster, to 20% HP.",
	inventory_image = "scavock_medkit.png",
})
core.register_craftitem("scavock_death:stabiliser", {
	description = "Stabiliser Injection\nFast revive, to 30% HP.",
	inventory_image = "scavock_stabiliser.png",
})
core.register_craft({
	type = "shapeless",
	output = "scavock_death:medkit",
	recipe = { "scavock_core:tree_leaves", "scavock_core:tree_leaves",
		"scavock_core:tree_leaves", "scavock_core:stick" },
})
core.register_craft({
	type = "shapeless",
	output = "scavock_death:stabiliser",
	recipe = { "scavock_death:medkit", "scavock_core:scrap_ingot" },
})
scavock.item_sizes["scavock_death:medkit"] = { 2, 1 }

-- ---------------------------------------------------------------------------
-- Enter / leave the downed state
-- ---------------------------------------------------------------------------
local function set_downed(player, on)
	local name = player:get_player_name()
	if on == (scavock.downed[name] or false) then return end
	if on then
		scavock.downed[name] = true
		local privs = core.get_player_privs(name)
		downed_data[name] = { had_interact = privs.interact and true or false,
			bleedout = BLEEDOUT }
		privs.interact = nil
		core.set_player_privs(name, privs)
		if scavock.refresh_jump then
			scavock.refresh_jump(player)
		else
			player:set_physics_override({ jump = 0 })
		end
		downed_data[name].hud_ids = {
			player:hud_add({
				type = "text", position = { x = 0.5, y = 0.42 },
				text = "KNOCKED DOWN", number = 0xB33A24,
				size = { x = 3 }, alignment = { x = 0, y = 0 },
			}),
			player:hud_add({
				type = "text", position = { x = 0.5, y = 0.48 },
				text = "Crawl to cover. Another survivor can revive you.",
				number = 0x9AA0AA, size = { x = 1 }, alignment = { x = 0, y = 0 },
			}),
		}
	else
		scavock.downed[name] = nil
		local data = downed_data[name]
		if data then
			if data.had_interact then
				local privs = core.get_player_privs(name)
				privs.interact = true
				core.set_player_privs(name, privs)
			end
			for _, id in ipairs(data.hud_ids or {}) do
				pcall(function() player:hud_remove(id) end)
			end
		end
		downed_data[name] = nil
		revives[name] = nil
		if scavock.refresh_jump then
			scavock.refresh_jump(player)
		else
			player:set_physics_override({ jump = 1 })
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lethal damage becomes a knockdown; damage while downed finishes (§12
-- "a downed player can be finished, ~one hit")
-- ---------------------------------------------------------------------------
core.register_on_player_hpchange(function(player, hp_change, reason)
	if hp_change >= 0 then return hp_change end
	-- ordered pipeline: thirst amp, armor absorb, etc. (scavock.damage_filters)
	for _, f in ipairs(scavock.damage_filters) do
		hp_change = f(player, hp_change, reason)
		if hp_change >= 0 then return hp_change end
	end
	local name = player:get_player_name()
	if scavock.downed[name] then
		-- finishing blow: let it kill outright
		return -player:get_hp()
	end
	if player:get_hp() + hp_change <= 0 then
		-- would die: clamp to 1 HP and go down instead
		core.after(0, function()
			local p = core.get_player_by_name(name)
			if p and p:get_hp() > 0 then
				set_downed(p, true)
			end
		end)
		return -(player:get_hp() - 1)
	end
	return hp_change
end, true)

-- true death / leaving clears the state
core.register_on_dieplayer(function(player)
	set_downed(player, false)
end)
core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	-- Anti-exploit (not in the design doc, flagged in README): logging out
	-- while downed counts as knocked out — otherwise a relog would stand
	-- you back up at 1 HP and delete the finish-or-spare decision.
	if scavock.downed[name] then
		local pos = player:get_pos()
		local inv = player:get_inventory()
		for i = 1, inv:get_size("main") do
			local stack = inv:get_stack("main", i)
			if not stack:is_empty() then
				core.add_item(vector.add(pos, {
					x = math.random() - 0.5, y = 0.5, z = math.random() - 0.5 }), stack)
				inv:set_stack("main", i, ItemStack(""))
			end
		end
		if scavock.drop_equipment then
			scavock.drop_equipment(player, pos)
		end
	end
	scavock.downed[name] = nil
	downed_data[name] = nil
	revives[name] = nil
	-- abort any revive this player was performing
	for target, r in pairs(revives) do
		if r.reviver == name then revives[target] = nil end
	end
end)
core.register_on_joinplayer(function(player)
	-- crashed-while-downed safety: never rejoin stuck without interact
	local name = player:get_player_name()
	local privs = core.get_player_privs(name)
	if not privs.interact then
		privs.interact = true
		core.set_player_privs(name, privs)
	end
end)

-- ---------------------------------------------------------------------------
-- Bleedout (§12 required mechanism 1) and self-revive (§12 mechanism 2:
-- the upgraded stabiliser, held in hand while downed — slow, interruptible)
-- ---------------------------------------------------------------------------
core.register_craftitem("scavock_death:stabiliser_adv", {
	description = "Upgraded Stabiliser" .. "\n"
		.. "On others: fast revive. On yourself: the ONLY self-revive"
		.. " — hold it while downed.",
	inventory_image = "scavock_stabiliser_adv.png",
})
core.register_craft({
	type = "shapeless",
	output = "scavock_death:stabiliser_adv",
	recipe = { "scavock_death:stabiliser", "scavock_core:titanium_ingot" },
})

local bleed_tick = 0
core.register_globalstep(function(dtime)
	bleed_tick = bleed_tick + dtime
	if bleed_tick < 1 then return end
	local step = bleed_tick
	bleed_tick = 0
	for name in pairs(scavock.downed) do
		local player = core.get_player_by_name(name)
		local data = downed_data[name]
		if player and data then
			data.bleedout = (data.bleedout or BLEEDOUT) - step
			if data.bleedout <= 0 then
				player:set_hp(0, { type = "set_hp", from = "mod" })
			elseif data.hud_ids and data.hud_ids[2] then
				local msg
				-- self-revive: hold the upgraded stabiliser
				if player:get_wielded_item():get_name()
						== "scavock_death:stabiliser_adv"
						and not revives[name] then
					data.selfrev = (data.selfrev or SELF_REVIVE_TIME) - step
					if data.selfrev <= 0 then
						player:get_inventory():remove_item("main",
							"scavock_death:stabiliser_adv")
						local hp_max = player:get_properties().hp_max or 20
						set_downed(player, false)
						player:set_hp(math.max(1, math.floor(hp_max * 0.3)),
							{ type = "set_hp", from = "mod" })
						core.chat_send_player(name, "Back up. That was the spare.")
						return
					end
					msg = ("Self-revive in %d... stay still, don't get hit.")
						:format(math.ceil(data.selfrev))
				else
					data.selfrev = nil
					msg = ("Crawl to cover. Bleeding out in %ds.")
						:format(math.ceil(data.bleedout))
				end
				player:hud_change(data.hud_ids[2], "text", msg)
			end
		end
	end
end)

-- damage interrupts a self-revive
core.register_on_punchplayer(function(player)
	local data = downed_data[player:get_player_name()]
	if data then data.selfrev = nil end
end)

-- ---------------------------------------------------------------------------
-- Revives: right-click a downed player
-- ---------------------------------------------------------------------------
local function revive_tick(target_name)
	local r = revives[target_name]
	if not r then return end
	local target = core.get_player_by_name(target_name)
	local reviver = core.get_player_by_name(r.reviver)
	if not target or not reviver or not scavock.downed[target_name]
			or scavock.downed[r.reviver] or reviver:get_hp() <= 0 then
		revives[target_name] = nil
		return
	end
	if vector.distance(target:get_pos(), reviver:get_pos()) > REVIVE_RADIUS then
		revives[target_name] = nil
		core.chat_send_player(r.reviver, "Revive aborted — too far away.")
		return
	end
	r.t = r.t - 1
	if r.t > 0 then
		core.chat_send_player(r.reviver, ("Reviving... %d"):format(r.t))
		core.after(1, revive_tick, target_name)
		return
	end
	-- success
	local kind = REVIVES[r.kind]
	if kind.item then
		reviver:get_inventory():remove_item("main", kind.item)
	end
	revives[target_name] = nil
	set_downed(target, false)
	local hp_max = target:get_properties().hp_max or 20
	target:set_hp(math.max(1, math.floor(hp_max * kind.hp_pct)),
		{ type = "set_hp", from = "mod" })
	core.chat_send_player(target_name, "You're back up. Move.")
	core.chat_send_player(r.reviver, "Revived " .. target_name .. ".")
end

core.register_on_rightclickplayer(function(player, clicker)
	local target_name = player:get_player_name()
	local clicker_name = clicker:get_player_name()
	if not scavock.downed[target_name] or scavock.downed[clicker_name] then
		return
	end
	if revives[target_name] then return end

	local wield = clicker:get_wielded_item():get_name()
	local kind = "bare"
	if wield == "scavock_death:stabiliser"
			or wield == "scavock_death:stabiliser_adv" then
		kind = "stabiliser"
	elseif wield == "scavock_death:medkit" then
		kind = "medkit"
	end
	revives[target_name] = { reviver = clicker_name, kind = kind,
		t = REVIVES[kind].time }
	core.chat_send_player(clicker_name,
		("Reviving %s (%s, %ds) — stay close.")
			:format(target_name, kind, REVIVES[kind].time))
	core.chat_send_player(target_name, clicker_name .. " is reviving you.")
	core.after(1, revive_tick, target_name)
end)
