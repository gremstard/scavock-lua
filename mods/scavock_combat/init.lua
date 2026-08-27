-- Blocking and stagger (§7).
--
-- Blocking is the defensive verb: every weapon has a BLOCK WINDOW, opened on
-- a right-click press while wielding it. An attack landing inside the window
-- is mostly absorbed. Window size is inversely related to aggressiveness —
-- the dagger's wide window is where its speed pays off; charging with a war
-- axe is nearly all-in. Blocking is a timing problem: too early and the
-- window has closed again, too late and the hit already landed. Sprinting
-- halves the window (§7 "blocking remains possible while sprinting, but the
-- window is reduced").
--
-- Stagger is a CHANCE, never a guarantee (max 40%), scaling with weapon
-- weight — heavy slow weapons carry high chance, fast light weapons low
-- (§7 required refinement: a flat percentage would make daggers the primary
-- stagger dealers, the inverse of the intent). An internal cooldown after
-- each stagger prevents chain-stagger; no meter, no bar, code only.

local BLOCK_ABSORB = 0.75      -- fraction of damage removed by a block
local BLOCK_COOLDOWN = 0.6     -- lockout after a window closes (anti-spam)
local SPRINT_WINDOW_MULT = 0.5
local STAGGER_SLOW = 0.15      -- speed multiplier while staggered
local STAGGER_TIME = 0.35      -- seconds of slow
local STAGGER_ICD = 2.0        -- internal cooldown between staggers (§7)

-- Per-form combat stats. Window (s): wide for fast/light, narrow for heavy.
-- Stagger chance: scales with weight, capped at 40% (§7).
local FORM_STATS = {
	dagger    = { window = 0.55, stagger = 0.08 },
	sword     = { window = 0.40, stagger = 0.15 },
	spear     = { window = 0.35, stagger = 0.18 },
	doubleaxe = { window = 0.32, stagger = 0.22 },
	waraxe    = { window = 0.22, stagger = 0.32 },
}

local function weapon_form(itemname)
	local form = itemname:match("^scavock_weapons:(%a+)_")
	return form and FORM_STATS[form] or nil
end

-- state[name] = { block_until, lock_until, was_place, hud }
local state = {}

local function st(name)
	state[name] = state[name] or { block_until = 0, lock_until = 0, was_place = false }
	return state[name]
end

-- ---------------------------------------------------------------------------
-- Block input: rising edge of the place control with a weapon wielded
-- ---------------------------------------------------------------------------
core.register_globalstep(function()
	local now = core.get_us_time() / 1e6
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local s = st(name)
		local ctrl = player:get_player_control()
		if ctrl.place and not s.was_place and not scavock.downed[name] then
			local stats = weapon_form(player:get_wielded_item():get_name())
			if stats and now >= s.lock_until then
				local window = stats.window
				if ctrl.aux1 and ctrl.up then
					window = window * SPRINT_WINDOW_MULT
				end
				s.block_until = now + window
				s.lock_until = now + window + BLOCK_COOLDOWN
			end
		end
		s.was_place = ctrl.place
	end
end)

-- ---------------------------------------------------------------------------
-- Stagger bookkeeping, read by scavock_player's speed loop
-- ---------------------------------------------------------------------------
scavock.stagger_until = {}
local stagger_icd_until = {}

local function try_stagger(victim, chance)
	local name = victim:get_player_name()
	local now = core.get_us_time() / 1e6
	if now < (stagger_icd_until[name] or 0) then return false end
	if math.random() >= chance then return false end
	scavock.stagger_until[name] = now + STAGGER_TIME
	stagger_icd_until[name] = now + STAGGER_ICD
	return true
end

function scavock.stagger_mult(name)
	local untl = scavock.stagger_until[name]
	if untl and core.get_us_time() / 1e6 < untl then
		return STAGGER_SLOW
	end
	return 1.0
end

-- ---------------------------------------------------------------------------
-- Damage interception
-- ---------------------------------------------------------------------------
core.register_on_punchplayer(function(player, hitter, time_from_last_punch,
		tool_capabilities, dir, damage)
	if damage <= 0 then return end
	-- a downed attacker can't fight (§12)
	if hitter and hitter:is_player()
			and scavock.downed[hitter:get_player_name()] then
		return true
	end
	local name = player:get_player_name()
	local now = core.get_us_time() / 1e6
	local s = st(name)

	if now < s.block_until then
		-- blocked: most damage absorbed, window consumed
		s.block_until = 0
		local reduced = math.max(1, math.floor(damage * (1 - BLOCK_ABSORB)))
		player:set_hp(player:get_hp() - reduced,
			{ type = "punch", object = hitter, from = "mod" })
		core.chat_send_player(name, "Blocked.")
		if hitter and hitter:is_player() then
			core.chat_send_player(hitter:get_player_name(), "Blocked!")
		end
		return true -- damage handled here
	end

	-- stagger roll, driven by the attacker's weapon form
	if hitter and hitter:is_player() then
		local stats = weapon_form(hitter:get_wielded_item():get_name())
		if stats and try_stagger(player, stats.stagger) then
			core.chat_send_player(name, "Staggered!")
		end
	end
	-- fall through: engine applies normal damage
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	state[name] = nil
	scavock.stagger_until[name] = nil
	stagger_icd_until[name] = nil
end)
