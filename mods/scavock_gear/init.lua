-- Clothing (§10) and reinforcement (§11).
--
-- §10: eight functional clothing slots plus ONE reinforcement slot. Players
-- spawn with only shorts. The equipped backpack (and top/vest) determine
-- the backpack grid's actual dimensions. Cosmetics: not in the Lua slice
-- (no visible player model layers) — the functional layer is complete.
--
-- §11: a reinforcement is a CRAFTED ITEM in the single slot. It has its own
-- damage pool: incoming damage is split (X% to the pool, Y% to HP); when
-- the pool empties the reinforcement BREAKS — loudly and visibly — and
-- must be manually repaired (never single-use). One reinforcement, one
-- perk, element-determined at craft (open Q9: this mapping is a legible
-- placeholder — feather=speed, spring=jump, strap=storage, lockplate=Safe
-- Slot; light things for mobility, dense for security).
--
-- Ladder (§6/§11, 7 tiers): Leather -> Chain -> Scrap -> Iron -> Steel ->
-- Titanium -> Graphene. Gradual slope, ~3x span, never exponential.

scavock_gear = {}

local ABSORB = 0.65  -- pool takes 65%, HP takes 35% (open Q6: constant until break)

-- §11 tier table: capacity is the pool; span kept gradual
local TIERS = {
	{ name = "leather",  desc = "Leather",   cap = 16,  mat = "scavock_core:leather" },
	{ name = "chain",    desc = "Chain",     cap = 26,  mat = "scavock_core:chain_link" },
	{ name = "scrap",    desc = "Scrap",     cap = 36,  mat = "scavock_core:scrap_ingot" },
	{ name = "iron",     desc = "Iron",      cap = 48,  mat = "scavock_core:iron_ingot" },
	{ name = "steel",    desc = "Steel",     cap = 62,  mat = "scavock_core:steel_ingot" },
	{ name = "titanium", desc = "Titanium",  cap = 78,  mat = "scavock_core:titanium_ingot" },
	{ name = "graphene", desc = "Graphene",  cap = 96,  mat = "scavock_core:graphene_ingot" },
}

local PERKS = {
	speed   = { desc = "Speed (+15% move)",        element = "scavock_gear:feather" },
	jump    = { desc = "Jump (+25% height)",       element = "scavock_gear:spring" },
	storage = { desc = "Storage (adds a 3x2 pocket)", element = "scavock_gear:strap" },
	safe    = { desc = "Safe Slot (survives death)", element = "scavock_gear:lockplate" },
}

-- slot indexes match scavock_grid.EQUIP_SLOTS
local SLOT = { hat = 1, glasses = 2, scarf = 3, top = 4, vest = 5,
	bottoms = 6, backpack = 7, shoes = 8, reinf = 9 }

-- ---------------------------------------------------------------------------
-- Equip inventory: detached, persisted in player meta
-- ---------------------------------------------------------------------------
local function save_equip(player, inv)
	local out = {}
	for i = 1, inv:get_size("main") do
		out[i] = inv:get_stack("main", i):to_string()
	end
	player:get_meta():set_string("scavock_equip", core.serialize(out))
end

local function equip_inv(player)
	return core.get_inventory({ type = "detached",
		name = "scavock_equip_" .. player:get_player_name() })
end

local function equipped(player, slot)
	local inv = equip_inv(player)
	if not inv then return ItemStack("") end
	return inv:get_stack("main", SLOT[slot])
end
scavock_gear.equipped = equipped

-- ---------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------
local speed_perk = {}

function scavock.gear_mult(name)
	return speed_perk[name] or 1.0
end

function scavock.refresh_jump(player)
	local name = player:get_player_name()
	local jump = 1.0
	local reinf = equipped(player, "reinf")
	if reinf:get_meta():get_string("perk") == "jump" then
		jump = 1.25
	end
	if scavock.downed[name] then jump = 0 end
	player:set_physics_override({ jump = jump })
end

function scavock_gear.on_equip_changed(player)
	local name = player:get_player_name()
	local inv = equip_inv(player)
	if not inv then return end
	save_equip(player, inv)

	-- §10 v2: storage garments carry their OWN labeled grids (Hands is
	-- the base); scavock_grid materialises/dumps them from equip state
	scavock_grid.refresh_garments(player)

	local reinf = equipped(player, "reinf")
	speed_perk[name] =
		(reinf:get_meta():get_string("perk") == "speed") and 1.15 or 1.0
	scavock.refresh_jump(player)

	-- glasses: distance vision (engine zoom)
	player:set_properties({ zoom_fov =
		(not equipped(player, "glasses"):is_empty()) and 15 or 0 })
end

function scavock.reinforcement_intact(player)
	local r = equipped(player, "reinf")
	return not r:is_empty()
		and r:get_meta():get_int("broken") == 0
		and r:get_meta():get_int("pool") > 0
end

-- ---------------------------------------------------------------------------
-- Damage pipeline: hat/scarf trim, then the reinforcement pool splits (§11)
-- ---------------------------------------------------------------------------
local break_hud = {}

local function announce_break(player)
	-- §11: make the break clearly audible and visible — the fight changed
	local name = player:get_player_name()
	if break_hud[name] then return end
	break_hud[name] = player:hud_add({
		type = "text", position = { x = 0.5, y = 0.32 },
		text = "REINFORCEMENT BROKEN", number = 0xB33A24,
		size = { x = 2 }, alignment = { x = 0, y = 0 },
	})
	core.after(2.5, function()
		local p = core.get_player_by_name(name)
		if p and break_hud[name] then
			p:hud_remove(break_hud[name])
		end
		break_hud[name] = nil
	end)
end

table.insert(scavock.damage_filters, function(player, hp_change, reason)
	if hp_change >= 0 then return hp_change end
	if reason and (reason.bleed or reason.from == "mod"
			or reason.type == "fall" or reason.type == "drown") then
		-- reinforcement guards against blows, not the world
		if reason.type == "fall"
				and not equipped(player, "shoes"):is_empty() then
			return math.ceil(hp_change * 0.5) -- §10 shoes: fall reduction
		end
		return hp_change
	end

	local dmg = -hp_change
	-- §10 hat + scarf: flat damage trim
	local trim = 0
	if not equipped(player, "hat"):is_empty() then trim = trim + 0.10 end
	if not equipped(player, "scarf"):is_empty() then trim = trim + 0.05 end
	dmg = dmg * (1 - trim)

	-- §11 split: pool absorbs, remainder passes
	local inv = equip_inv(player)
	local reinf = inv and inv:get_stack("main", SLOT.reinf)
	if reinf and not reinf:is_empty() then
		local meta = reinf:get_meta()
		local pool = meta:get_int("pool")
		if pool > 0 then
			local absorbed = math.min(pool, math.ceil(dmg * ABSORB))
			pool = pool - absorbed
			meta:set_int("pool", pool)
			if pool <= 0 then
				meta:set_int("broken", 1)
				meta:set_string("description", reinf:get_definition()
					._scavock_basedesc .. "\nBROKEN — repair with materials (use)")
				announce_break(player)
			end
			inv:set_stack("main", SLOT.reinf, reinf)
			save_equip(player, inv)
			dmg = dmg - absorbed
		end
	end
	return -math.max(math.floor(dmg + 0.5), 0)
end)

-- ---------------------------------------------------------------------------
-- Reinforcement items: one per tier, perk stamped at craft
-- ---------------------------------------------------------------------------
local function reinf_desc(tier, perk, cap)
	return ("%s Reinforcement\nPerk: %s\nPool: %d — one slot, one perk (§11)")
		:format(tier.desc, PERKS[perk] and PERKS[perk].desc or "?", cap)
end

for ti, tier in ipairs(TIERS) do
	local itemname = "scavock_gear:reinf_" .. tier.name
	core.register_craftitem(itemname, {
		description = tier.desc .. " Reinforcement",
		_scavock_basedesc = tier.desc .. " Reinforcement",
		inventory_image = "scavock_reinf_" .. tier.name .. ".png",
		groups = { scavock_slot = SLOT.reinf, reinforcement = 1 },
		stack_max = 1,
		-- manual repair (§11: never single-use): use with materials in inventory
		on_use = function(itemstack, user)
			local meta = itemstack:get_meta()
			if meta:get_int("broken") ~= 1 and meta:get_int("pool") >= tier.cap then
				return itemstack
			end
			local need = tier.mat .. " 2"
			if not scavock.p_contains(user, need) then
				core.chat_send_player(user:get_player_name(),
					"Repair needs 2x " .. tier.desc .. " material.")
				return itemstack
			end
			scavock.p_take(user, need)
			meta:set_int("pool", tier.cap)
			meta:set_int("broken", 0)
			meta:set_string("description",
				reinf_desc(tier, meta:get_string("perk"), tier.cap))
			core.chat_send_player(user:get_player_name(), "Reinforcement repaired.")
			return itemstack
		end,
	})
	scavock.item_sizes[itemname] = { 2, 2 }

	-- craft: 3x material + garment base + perk element -> perk-stamped item
	for perk, pdef in pairs(PERKS) do
		core.register_craft({
			type = "shapeless",
			output = itemname,
			recipe = { tier.mat, tier.mat, tier.mat,
				"scavock_core:leather", pdef.element },
		})
	end
end

-- stamp pool/perk on the workbench's computed output (crafts can't carry
-- meta in the recipe itself)
table.insert(scavock.craft_postprocess, function(itemstack, craftlist)
	local name = itemstack:get_name()
	local tier
	for _, t in ipairs(TIERS) do
		if name == "scavock_gear:reinf_" .. t.name then tier = t break end
	end
	if not tier then return end
	local perk = "safe"
	for _, stk in ipairs(craftlist) do
		for pk, pdef in pairs(PERKS) do
			if stk:get_name() == pdef.element then perk = pk end
		end
	end
	local meta = itemstack:get_meta()
	meta:set_int("pool", tier.cap)
	meta:set_string("perk", perk)
	meta:set_string("description", reinf_desc(tier, perk, tier.cap))
	return itemstack
end)

-- perk elements
core.register_craftitem("scavock_gear:feather", {
	description = "Feather (element: speed)", inventory_image = "scavock_feather.png" })
core.register_craftitem("scavock_gear:spring", {
	description = "Spring (element: jump)", inventory_image = "scavock_spring.png" })
core.register_craftitem("scavock_gear:strap", {
	description = "Leather Strap (element: storage)", inventory_image = "scavock_strap.png" })
core.register_craftitem("scavock_gear:lockplate", {
	description = "Lock Plate (element: Safe Slot)", inventory_image = "scavock_lockplate.png" })
core.register_craft({ type = "shapeless", output = "scavock_gear:spring",
	recipe = { "scavock_core:scrap_ingot", "scavock_core:scrap_ingot" } })
core.register_craft({ type = "shapeless", output = "scavock_gear:strap",
	recipe = { "scavock_core:leather", "scavock_core:leather" } })
core.register_craft({ type = "shapeless", output = "scavock_gear:lockplate",
	recipe = { "scavock_core:iron_ingot", "scavock_core:iron_ingot" } })
core.register_craft({ output = "scavock_core:chain_link 4",
	recipe = { { "scavock_core:scrap_ingot" } } })

-- ---------------------------------------------------------------------------
-- Clothing items (§10)
-- ---------------------------------------------------------------------------
local function clothing(id, slot, desc, image, size, recipe, storage)
	local itemname = "scavock_gear:" .. id
	core.register_craftitem(itemname, {
		description = desc,
		inventory_image = image,
		groups = { scavock_slot = SLOT[slot], clothing = 1 },
		stack_max = 1,
		_scavock_storage = storage,
	})
	if size then scavock.item_sizes[itemname] = size end
	if recipe then
		core.register_craft({ type = "shapeless", output = itemname, recipe = recipe })
	end
end

local L = "scavock_core:leather"
clothing("cap", "hat", "Leather Cap (-10% damage)", "scavock_cap.png",
	{ 2, 1 }, { L, L })
clothing("glasses", "glasses", "Field Glasses (enables zoom)", "scavock_glasses.png",
	nil, { "scavock_core:scrap_ingot", "scavock_core:coal_lump" })
clothing("scarf", "scarf", "Scarf (-5% damage)", "scavock_scarf.png",
	nil, { L, "scavock_core:stick" })
clothing("shirt", "top", "Worn Shirt\nStorage: 3x2", "scavock_shirt.png",
	{ 2, 2 }, { L, L, "scavock_core:stick" }, { w = 3, h = 2 })
clothing("vest", "vest", "Scav Vest\nStorage: 4x2", "scavock_vest.png",
	{ 2, 2 }, { L, L, L }, { w = 4, h = 2 })
clothing("shorts", "bottoms", "Shorts\nWhat you spawn in. Storage: 2x2",
	"scavock_shorts.png", { 2, 1 }, nil, { w = 2, h = 2 })
clothing("pants", "bottoms", "Brown Cargo Pants\nStorage: 4x4",
	"scavock_pants.png", { 2, 2 }, { L, L, L, "scavock_core:stick" },
	{ w = 4, h = 4 })
clothing("backpack_s", "backpack", "Small Backpack\nStorage: 6x3",
	"scavock_backpack_s.png", { 2, 2 }, { L, L, "scavock_gear:strap" },
	{ w = 6, h = 3 })
clothing("backpack_l", "backpack", "Large Backpack\nStorage: 8x4",
	"scavock_backpack_l.png", { 2, 3 },
	{ L, L, L, "scavock_gear:strap", "scavock_gear:strap" }, { w = 8, h = 4 })
clothing("shoes", "shoes", "Boots (-50% fall damage)", "scavock_shoes.png",
	{ 2, 1 }, { L, L, "scavock_core:chain_link" })

-- ---------------------------------------------------------------------------
-- Death: equipment drops with everything else (§12 "full inventory"),
-- EXCEPT a Safe Slot reinforcement — the one exemption (§11/§21)
-- ---------------------------------------------------------------------------
function scavock.drop_equipment(player, pos)
	local inv = equip_inv(player)
	if not inv then return end
	local destroy = scavock.suppress_drop
		and scavock.suppress_drop[player:get_player_name()]
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		if not stack:is_empty() then
			local keep = i == SLOT.reinf
				and stack:get_meta():get_string("perk") == "safe"
			if not keep and destroy then
				inv:set_stack("main", i, ItemStack(""))
			elseif not keep then
				core.add_item(vector.add(pos, {
					x = math.random() - 0.5, y = 0.5, z = math.random() - 0.5 }), stack)
				inv:set_stack("main", i, ItemStack(""))
			end
		end
	end
	save_equip(player, inv)
end

core.register_on_dieplayer(function(player)
	scavock.drop_equipment(player, player:get_pos())
	scavock_gear.on_equip_changed(player)
end)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local inv = core.create_detached_inventory("scavock_equip_" .. name, {
		allow_put = function(det, listname, index, stack)
			return core.get_item_group(stack:get_name(), "scavock_slot") == index
				and 1 or 0
		end,
		on_put = function() local p = core.get_player_by_name(name)
			if p then scavock_gear.on_equip_changed(p) end end,
		on_take = function() local p = core.get_player_by_name(name)
			if p then scavock_gear.on_equip_changed(p) end end,
	})
	inv:set_size("main", #scavock_grid.EQUIP_SLOTS)
	local stored = player:get_meta():get_string("scavock_equip")
	if stored ~= "" then
		local list = core.deserialize(stored) or {}
		for i = 1, inv:get_size("main") do
			inv:set_stack("main", i, ItemStack(list[i] or ""))
		end
	elseif player:get_meta():get_string("scavock_hands") ~= ""
			or not player:get_inventory():is_empty("main") then
		-- legacy save from before clothing existed: grant the set that keeps
		-- their 8x6 pack intact ("you were carrying it all along")
		inv:set_stack("main", SLOT.bottoms, ItemStack("scavock_gear:shorts"))
		inv:set_stack("main", SLOT.top, ItemStack("scavock_gear:shirt"))
		inv:set_stack("main", SLOT.vest, ItemStack("scavock_gear:vest"))
		inv:set_stack("main", SLOT.backpack, ItemStack("scavock_gear:backpack_s"))
	end
	scavock_gear.on_equip_changed(player)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	speed_perk[name] = nil
	core.remove_detached_inventory("scavock_equip_" .. name)
end)

-- §10 spawn state: only shorts equipped; the bluffing layer starts empty
core.register_on_newplayer(function(player)
	local inv = equip_inv(player)
	if inv then
		inv:set_stack("main", SLOT.bottoms, ItemStack("scavock_gear:shorts"))
		scavock_gear.on_equip_changed(player)
	end
end)
core.register_on_respawnplayer(function(player)
	core.after(0.1, function()
		local p = core.get_player_by_name(player:get_player_name())
		if not p then return end
		local inv = equip_inv(p)
		if inv and inv:get_stack("main", SLOT.bottoms):is_empty() then
			inv:set_stack("main", SLOT.bottoms, ItemStack("scavock_gear:shorts"))
		end
		scavock_gear.on_equip_changed(p)
	end)
end)
