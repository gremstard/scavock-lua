-- Scavock inventory v2 (§9, revised per playtest direction):
--
-- HOTBAR: 4 slots, SEPARATE from grid storage. Slots hold one stack each —
-- slot semantics, not grid spaces. (The old "top row of the grid is the
-- hotbar" caused wide items to visually swallow their neighbours.)
--
-- GRID STORAGE: labeled sections, each its own spatial grid:
--   HANDS      — your base carry, always present (9x3; §10: "you aren't
--                wearing anything, that's just your base storage")
--   <garment>  — each equipped storage garment adds its own labeled grid
--                beneath ("Brown Cargo Pants — 4x4"), which vanishes (contents
--                dumped to Hands/ground) when unequipped
--   VAULT      — unchanged (4x2, survives everything)
--
-- EQUIP: no wall of empty slots. The only visible slot is REINFORCEMENT.
-- Clothing equips through the item CONTEXT MENU: click any item in a grid
-- to get name/preview/description and Actions — Equip, To Hotbar, Hold,
-- Move, Drop. Equipped garments show as icons (click to unequip via menu).

scavock_grid = {}

local HANDS_W, HANDS_H = 9, 3
local VA_W, VA_H = 4, 2
local CELL = 0.85

-- equip slot indexes (state lives in the detached equip inv, as before)
scavock_grid.EQUIP_SLOTS = {
	"HAT", "GLASSES", "SCARF", "TOP", "VEST", "BOTTOMS",
	"BACKPACK", "SHOES", "REINF",
}
local REINF_SLOT = 9
-- slots whose garments can carry storage grids
local STORAGE_SLOTS = { 4, 5, 6, 7 }

-- ---------------------------------------------------------------------------
-- Pure grid logic (unchanged; headless tests cover these)
-- ---------------------------------------------------------------------------
local function stack_footprint(stack)
	local s = scavock.item_size(stack:get_name())
	if stack:get_meta():get_int("g_rot") == 1 then
		return s.h, s.w
	end
	return s.w, s.h
end
scavock_grid.stack_footprint = stack_footprint

local function idx_xy(idx, W)
	return (idx - 1) % W, math.floor((idx - 1) / W)
end

function scavock_grid.cells_for(idx, w, h, W, H)
	local x, y = idx_xy(idx, W)
	if x + w > W or y + h > H then return nil end
	local out = {}
	for dy = 0, h - 1 do
		for dx = 0, w - 1 do
			out[#out + 1] = idx + dx + dy * W
		end
	end
	return out
end

function scavock_grid.occupancy(inv, listname, W, H)
	local occ = {}
	for i = 1, W * H do
		local stack = inv:get_stack(listname, i)
		if not stack:is_empty() then
			local w, h = stack_footprint(stack)
			local cells = scavock_grid.cells_for(i, w, h, W, H)
			if not cells then return nil, i end
			for _, c in ipairs(cells) do
				if occ[c] then return nil, i end
				occ[c] = i
			end
		end
	end
	return occ
end

function scavock_grid.fits(inv, listname, W, H, idx, w, h, ignore_anchor)
	local cells = scavock_grid.cells_for(idx, w, h, W, H)
	if not cells then return false end
	local occ = scavock_grid.occupancy(inv, listname, W, H)
	if not occ then return false end
	for _, c in ipairs(cells) do
		if occ[c] and occ[c] ~= ignore_anchor then return false end
	end
	return true
end

function scavock_grid.find_fit(inv, listname, W, H, stack)
	local s = scavock.item_size(stack:get_name())
	local tries = { { s.w, s.h, 0 } }
	if s.w ~= s.h then
		tries[2] = { s.h, s.w, 1 }
	end
	for _, t in ipairs(tries) do
		for i = 1, W * H do
			if inv:get_stack(listname, i):is_empty()
					and scavock_grid.fits(inv, listname, W, H, i, t[1], t[2]) then
				return i, t[3]
			end
		end
	end
	return nil
end

function scavock_grid.repack(inv, listname, W, H)
	local stacks = {}
	for i = 1, inv:get_size(listname) do
		local st = inv:get_stack(listname, i)
		if not st:is_empty() then
			stacks[#stacks + 1] = st
		end
	end
	table.sort(stacks, function(a, b)
		local sa, sb = scavock.item_size(a:get_name()), scavock.item_size(b:get_name())
		return sa.w * sa.h > sb.w * sb.h
	end)
	inv:set_list(listname, {})
	inv:set_size(listname, W * H)
	local overflow = {}
	for _, st in ipairs(stacks) do
		local idx, rot = scavock_grid.find_fit(inv, listname, W, H, st)
		if idx then
			if rot == 1 then st:get_meta():set_int("g_rot", 1) end
			inv:set_stack(listname, idx, st)
		else
			overflow[#overflow + 1] = st
		end
	end
	return overflow
end

-- ---------------------------------------------------------------------------
-- Per-player grids: detached inventories persisted in player meta
-- ---------------------------------------------------------------------------
local function pname(player) return player:get_player_name() end

local function persist(player, key, inv)
	local out = {}
	for i = 1, inv:get_size("main") do
		out[i] = inv:get_stack("main", i):to_string()
	end
	player:get_meta():set_string(key, core.serialize(out))
end

local function restore(player, key, inv)
	local stored = player:get_meta():get_string(key)
	if stored == "" then return end
	local list = core.deserialize(stored) or {}
	for i = 1, inv:get_size("main") do
		inv:set_stack("main", i, ItemStack(list[i] or ""))
	end
end

-- grid-fit guard as detached callbacks, so engine transfers (shift-click
-- from crates etc.) become first-fit placements
local function grid_callbacks(player_name, meta_key, W)
	return {
		allow_put = function(inv, listname, index, stack)
			local H = inv:get_size("main") / W
			local w, h = stack_footprint(stack)
			if scavock_grid.fits(inv, "main", W, H, index, w, h) then
				return stack:get_count()
			end
			local target = inv:get_stack("main", index)
			if not target:is_empty() and target:get_name() == stack:get_name()
					and target:get_free_space() > 0 then
				return stack:get_count()
			end
			return 0
		end,
		allow_move = function(inv, from_list, from_index, to_list, to_index, count)
			local H = inv:get_size("main") / W
			local stack = inv:get_stack(from_list, from_index)
			local w, h = stack_footprint(stack)
			return scavock_grid.fits(inv, "main", W, H, to_index, w, h, from_index)
				and count or 0
		end,
		on_put = function(inv)
			local p = core.get_player_by_name(player_name)
			if p then persist(p, meta_key, inv) end
		end,
		on_take = function(inv)
			local p = core.get_player_by_name(player_name)
			if p then persist(p, meta_key, inv) end
		end,
		on_move = function(inv)
			local p = core.get_player_by_name(player_name)
			if p then persist(p, meta_key, inv) end
		end,
	}
end

-- storage garment dims come from the item definition (_scavock_storage)
local function garment_storage(itemname)
	local def = core.registered_items[itemname]
	return def and def._scavock_storage
end
scavock_grid.garment_storage = garment_storage

local function equip_inv(player)
	return core.get_inventory({ type = "detached",
		name = "scavock_equip_" .. pname(player) })
end

-- id -> inv, list, W, H, label   (ids: hotbar, hands, vault, equip, g4..g7)
local function get_grid(player, id)
	local name = pname(player)
	if id == "hotbar" then
		return player:get_inventory(), "main", 4, 1, "HOTBAR"
	elseif id == "hands" then
		local inv = core.get_inventory({ type = "detached",
			name = "scavock_hands_" .. name })
		return inv, "main", HANDS_W, HANDS_H, "HANDS"
	elseif id == "vault" then
		local inv = core.get_inventory({ type = "detached",
			name = "scavock_vault_" .. name })
		return inv, "main", VA_W, VA_H, "VAULT"
	elseif id == "equip" then
		local inv = equip_inv(player)
		return inv, "main", 1, #scavock_grid.EQUIP_SLOTS, "EQUIP"
	elseif id == "pocket" then
		local einv = equip_inv(player)
		local reinf = einv and einv:get_stack("main", REINF_SLOT)
		if reinf and not reinf:is_empty()
				and reinf:get_meta():get_string("perk") == "storage" then
			local inv = core.get_inventory({ type = "detached",
				name = "scavock_pocket_" .. name })
			return inv, "main", 3, 2, "REINFORCEMENT POCKET"
		end
	else
		local slot = tonumber(id:match("^g(%d+)$") or "")
		if slot then
			local einv = equip_inv(player)
			local garment = einv and einv:get_stack("main", slot)
			local st = garment and not garment:is_empty()
				and garment_storage(garment:get_name())
			if st then
				local inv = core.get_inventory({ type = "detached",
					name = "scavock_" .. id .. "_" .. name })
				local label = garment:get_description():gsub("\n.*", "")
				return inv, "main", st.w, st.h, label:upper()
			end
		end
	end
end
scavock_grid.get_grid = get_grid

-- every list that counts as "carried" (weight, death drops, item searches)
function scavock_grid.carried_grids(player)
	local out = { "hotbar", "hands" }
	local einv = equip_inv(player)
	if einv then
		for _, slot in ipairs(STORAGE_SLOTS) do
			local garment = einv:get_stack("main", slot)
			if not garment:is_empty() and garment_storage(garment:get_name()) then
				out[#out + 1] = "g" .. slot
			end
		end
		local reinf = einv:get_stack("main", REINF_SLOT)
		if not reinf:is_empty()
				and reinf:get_meta():get_string("perk") == "storage" then
			out[#out + 1] = "pocket"
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Cross-inventory item helpers (the API every other mod uses now)
-- ---------------------------------------------------------------------------
function scavock.p_contains(player, itemstring)
	local want = ItemStack(itemstring)
	local need = want:get_count()
	for _, id in ipairs(scavock_grid.carried_grids(player)) do
		local inv = get_grid(player, id)
		if inv then
			for i = 1, inv:get_size("main") do
				local st = inv:get_stack("main", i)
				if st:get_name() == want:get_name() then
					need = need - st:get_count()
					if need <= 0 then return true end
				end
			end
		end
	end
	return false
end

function scavock.p_take(player, itemstring)
	local want = ItemStack(itemstring)
	local left = want:get_count()
	for _, id in ipairs(scavock_grid.carried_grids(player)) do
		local inv, list = get_grid(player, id)
		if inv then
			local taken = inv:remove_item(list, want:get_name() .. " " .. left)
			left = left - taken:get_count()
			scavock_grid.persist_grid(player, id)
			if left <= 0 then return true end
		end
	end
	return left <= 0
end

-- add: hands first, then garment grids, then hotbar; overflow returned
function scavock.p_add(player, itemstring)
	local stack = ItemStack(itemstring)
	local order = scavock_grid.carried_grids(player)
	-- hands and garments before hotbar
	table.insert(order, table.remove(order, 1))
	for _, id in ipairs(order) do
		local inv, list, W, H = get_grid(player, id)
		if inv then
			if id == "hotbar" then
				stack = inv:add_item(list, stack)
			else
				-- merge onto same-name stacks first
				for i = 1, inv:get_size(list) do
					local st = inv:get_stack(list, i)
					if not st:is_empty() and st:get_name() == stack:get_name() then
						stack = st:add_item(stack)
						inv:set_stack(list, i, st)
						if stack:is_empty() then break end
					end
				end
				while not stack:is_empty() do
					local idx, rot = scavock_grid.find_fit(inv, list, W, H, stack)
					if not idx then break end
					local one = stack:take_item(stack:get_stack_max())
					if rot == 1 then one:get_meta():set_int("g_rot", 1) end
					inv:set_stack(list, idx, one)
				end
			end
			scavock_grid.persist_grid(player, id)
			if stack:is_empty() then return ItemStack("") end
		end
	end
	return stack -- leftover
end

function scavock_grid.persist_grid(player, id)
	local inv = get_grid(player, id)
	if not inv then return end
	if id == "hands" then
		persist(player, "scavock_hands", inv)
	elseif id:match("^g%d+$") then
		persist(player, "scavock_" .. id, inv)
	elseif id == "pocket" then
		persist(player, "scavock_pocket", inv)
	elseif id == "vault" then
		persist(player, "scavock_vault", inv)
	end
end

-- iterate every carried stack: fn(inv, list, index, stack) -> optionally new stack
function scavock.p_each(player, fn)
	for _, id in ipairs(scavock_grid.carried_grids(player)) do
		local inv, list = get_grid(player, id)
		if inv then
			for i = 1, inv:get_size(list) do
				local st = inv:get_stack(list, i)
				if not st:is_empty() then
					local rep = fn(inv, list, i, st, id)
					if rep then
						inv:set_stack(list, i, rep)
					end
				end
			end
			scavock_grid.persist_grid(player, id)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Garment grid lifecycle: called by scavock_gear on equip change
-- ---------------------------------------------------------------------------
function scavock_grid.refresh_garments(player)
	local name = pname(player)
	local einv = equip_inv(player)
	if not einv then return end
	-- reinforcement Storage perk: a 3x2 pocket
	do
		local reinf = einv:get_stack("main", REINF_SLOT)
		local want = not reinf:is_empty()
			and reinf:get_meta():get_string("perk") == "storage"
		local detname = "scavock_pocket_" .. name
		local inv = core.get_inventory({ type = "detached", name = detname })
		if want and not inv then
			inv = core.create_detached_inventory(detname,
				grid_callbacks(name, "scavock_pocket", 3))
			inv:set_size("main", 6)
			restore(player, "scavock_pocket", inv)
		elseif not want and inv then
			for i = 1, inv:get_size("main") do
				local s2 = inv:get_stack("main", i)
				if not s2:is_empty() then
					inv:set_stack("main", i, ItemStack(""))
					local left = scavock.p_add(player, s2)
					if not left:is_empty() then
						core.add_item(player:get_pos(), left)
					end
				end
			end
			player:get_meta():set_string("scavock_pocket", "")
			core.remove_detached_inventory(detname)
		end
	end
	for _, slot in ipairs(STORAGE_SLOTS) do
		local id = "g" .. slot
		local detname = "scavock_" .. id .. "_" .. name
		local garment = einv:get_stack("main", slot)
		local st = not garment:is_empty() and garment_storage(garment:get_name())
		local inv = core.get_inventory({ type = "detached", name = detname })
		if st then
			if not inv then
				inv = core.create_detached_inventory(detname,
					grid_callbacks(name, "scavock_" .. id, st.w))
			end
			if inv:get_size("main") ~= st.w * st.h then
				-- resized garment: dump and rebuild
				local old = {}
				for i = 1, inv:get_size("main") do
					local s2 = inv:get_stack("main", i)
					if not s2:is_empty() then old[#old + 1] = s2 end
				end
				inv:set_list("main", {})
				inv:set_size("main", st.w * st.h)
				for _, s2 in ipairs(old) do
					local left = scavock.p_add(player, s2)
					if not left:is_empty() then
						core.add_item(player:get_pos(), left)
					end
				end
			end
			restore(player, "scavock_" .. id, inv)
		elseif inv then
			-- unequipped: contents to hands, overflow to the ground
			for i = 1, inv:get_size("main") do
				local s2 = inv:get_stack("main", i)
				if not s2:is_empty() then
					inv:set_stack("main", i, ItemStack(""))
					local left = scavock.p_add(player, s2)
					if not left:is_empty() then
						core.add_item(player:get_pos(), left)
					end
				end
			end
			player:get_meta():set_string("scavock_" .. id, "")
			core.remove_detached_inventory(detname)
		end
	end
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------
local held = {}          -- move mode: name -> { grid, idx, rot }
local viewing_vault = {}
local menu_ctx = {}      -- context menu: name -> { grid, idx }

local function render_grid(fs, player, id, x0, y0)
	local inv, listname, W, H = get_grid(player, id)
	if not inv then return 0 end
	local name = pname(player)
	local hold = held[name]
	local occ = scavock_grid.occupancy(inv, listname, W, H) or {}
	for i = 1, W * H do
		local cx, cy = idx_xy(i, W)
		local px, py = x0 + cx * CELL, y0 + cy * CELL
		if not occ[i] then
			fs[#fs + 1] = ("image_button[%f,%f;%f,%f;scavock_cell.png;gc_%s_%d;]")
				:format(px, py, CELL, CELL, id, i)
		else
			local tex = (hold and hold.grid == id and occ[i] == hold.idx)
				and "scavock_cell_held.png" or "scavock_cell.png"
			fs[#fs + 1] = ("image[%f,%f;%f,%f;%s]")
				:format(px, py, CELL, CELL, tex)
		end
	end
	for i = 1, W * H do
		local stack = inv:get_stack(listname, i)
		if not stack:is_empty() then
			local w, h = stack_footprint(stack)
			local cx, cy = idx_xy(i, W)
			local count = stack:get_count()
			fs[#fs + 1] = ("item_image_button[%f,%f;%f,%f;%s;gi_%s_%d;%s]")
				:format(x0 + cx * CELL, y0 + cy * CELL, w * CELL, h * CELL,
					stack:get_name(), id, i, count > 1 and tostring(count) or "")
		end
	end
	return H * CELL
end

local function build_formspec(player, show_vault)
	local name = pname(player)
	local hold = held[name]
	local width = 0.8 + HANDS_W * CELL
		+ (show_vault and (VA_W * CELL + 0.8) or 0)
	local fs = { "formspec_version[6]" }
	local body = {}
	local y = 0.6

	-- EQUIPPED strip: reinforcement slot + worn items only (no empty walls)
	body[#body + 1] = ("label[0.4,%f;EQUIPPED]"):format(y - 0.1)
	local einv = equip_inv(player)
	local ex = 0.4
	y = y + 0.25
	-- the one visible slot: reinforcement
	local reinf = einv and einv:get_stack("main", REINF_SLOT)
	if reinf and not reinf:is_empty() then
		fs[#fs + 1] = "" -- placeholder keeps indexes simple
		body[#body + 1] = ("image[%f,%f;%f,%f;scavock_cell_held.png]")
			:format(ex, y, CELL, CELL)
		body[#body + 1] = ("item_image_button[%f,%f;%f,%f;%s;gi_equip_%d;]")
			:format(ex, y, CELL, CELL, reinf:get_name(), REINF_SLOT)
	else
		body[#body + 1] = ("image_button[%f,%f;%f,%f;scavock_cell.png;gc_equip_%d;]")
			:format(ex, y, CELL, CELL, REINF_SLOT)
	end
	body[#body + 1] = ("style_type[label;textcolor=#565C66]label[%f,%f;REINF]style_type[label;textcolor=#E4E0D4]")
		:format(ex, y + CELL + 0.22)
	ex = ex + CELL + 0.5
	if einv then
		for slot = 1, 8 do
			local st = einv:get_stack("main", slot)
			if not st:is_empty() then
				body[#body + 1] = ("item_image_button[%f,%f;%f,%f;%s;gi_equip_%d;]")
					:format(ex, y, CELL, CELL, st:get_name(), slot)
				body[#body + 1] = ("style_type[label;textcolor=#565C66]label[%f,%f;%s]style_type[label;textcolor=#E4E0D4]")
					:format(ex, y + CELL + 0.22,
						scavock_grid.EQUIP_SLOTS[slot]:sub(1, 5))
				ex = ex + CELL + 0.5
			end
		end
	end
	y = y + CELL + 0.55

	-- HOTBAR: 4 true slots (engine list — slot semantics)
	body[#body + 1] = ("label[0.4,%f;HOTBAR — 4 slots, one item each]"):format(y)
	y = y + 0.25
	body[#body + 1] = ("list[current_player;main;0.4,%f;4,1;]"):format(y)
	y = y + 1.25 + 0.35

	-- HANDS
	body[#body + 1] = ("label[0.4,%f;HANDS — base storage]"):format(y)
	y = y + 0.25
	local gh = render_grid(body, player, "hands", 0.4, y)
	y = y + gh + 0.45

	-- garment sections, labeled by the item that grants them
	for _, slot in ipairs(STORAGE_SLOTS) do
		local id = "g" .. slot
		local inv, _, W, H, label = get_grid(player, id)
		if inv then
			body[#body + 1] = ("label[0.4,%f;%s — %dx%d]")
				:format(y, core.formspec_escape(label), W, H)
			y = y + 0.25
			local ghh = render_grid(body, player, id, 0.4, y)
			y = y + ghh + 0.45
		end
	end

	do
		local inv, _, W, H, label = get_grid(player, "pocket")
		if inv then
			body[#body + 1] = ("label[0.4,%f;%s — %dx%d]")
				:format(y, core.formspec_escape(label), W, H)
			y = y + 0.25
			local ghh = render_grid(body, player, "pocket", 0.4, y)
			y = y + ghh + 0.45
		end
	end

	if show_vault then
		local vx = 0.8 + HANDS_W * CELL
		body[#body + 1] = ("label[%f,0.5;VAULT — survives everything]"):format(vx)
		render_grid(body, player, "vault", vx, 0.9)
	end

	-- footer
	if hold then
		local inv, listname = get_grid(player, hold.grid)
		local stack = inv and inv:get_stack(listname, hold.idx)
		local desc = stack and stack:get_short_description() or "?"
		body[#body + 1] = ("label[0.4,%f;%s]"):format(y + 0.3,
			core.formspec_escape("Moving: " .. desc
				.. (hold.rot and " (rotated)" or "") .. " — click a cell"))
		local s = stack and scavock.item_size(stack:get_name())
		if s and s.w ~= s.h then
			body[#body + 1] = ("button[%f,%f;1.7,0.7;g_rot;Rotate]")
				:format(width - 5.8, y + 0.05)
		end
		body[#body + 1] = ("button[%f,%f;1.7,0.7;g_cancel;Cancel]")
			:format(width - 2.1, y + 0.05)
	else
		if not show_vault then
			body[#body + 1] = ("button[%f,%f;1.9,0.7;vault;Vault]")
				:format(width - 6.3, y + 0.05)
		end
		body[#body + 1] = ("button[%f,%f;1.9,0.7;stash;Stash]")
			:format(width - 4.2, y + 0.05)
		body[#body + 1] = ("label[0.4,%f;Click an item for actions.]")
			:format(y + 0.3)
	end
	y = y + 1.1

	fs[#fs + 1] = ("size[%f,%f]"):format(width, y)
	return "formspec_version[6]" .. ("size[%f,%f]"):format(width, y)
		.. table.concat(body)
end

local function refresh(player)
	local name = pname(player)
	local fs = build_formspec(player, viewing_vault[name])
	player:set_inventory_formspec(build_formspec(player, false))
	core.show_formspec(name, "scavock_grid:view", fs)
end
scavock_grid.refresh = refresh

-- ---------------------------------------------------------------------------
-- Context menu (click an item): name, preview, description, actions
-- ---------------------------------------------------------------------------
local function show_menu(player, grid, idx)
	local inv, list = get_grid(player, grid)
	if not inv then return end
	local stack = inv:get_stack(list, idx)
	if stack:is_empty() then return end
	local name = pname(player)
	menu_ctx[name] = { grid = grid, idx = idx }
	local def = stack:get_definition()
	local title = stack:get_short_description() or stack:get_name()
	local desc = def and def.description or ""
	local is_clothing = core.get_item_group(stack:get_name(), "scavock_slot") > 0
	local fs = {
		"formspec_version[6]", "size[8.6,7.6]",
		("item_image[0.4,0.5;1.6,1.6;%s]"):format(stack:get_name()),
		("label[2.3,0.9;%s]"):format(core.formspec_escape(title)),
		("textarea[2.3,1.3;5.9,1.6;;;%s]"):format(core.formspec_escape(desc)),
		"label[0.4,2.9;Actions]",
	}
	local y = 3.3
	local function btn(id, label2)
		fs[#fs + 1] = ("button[0.4,%f;7.8,0.75;%s;%s]"):format(y, id, label2)
		y = y + 0.85
	end
	if grid == "equip" then
		btn("m_unequip", "UNEQUIP")
	else
		if is_clothing then btn("m_equip", "EQUIP") end
		if grid ~= "hotbar" then
			btn("m_hotbar", "TO HOTBAR")
			btn("m_hold", "HOLD (hotbar slot 1)")
		end
		btn("m_move", "MOVE (then click a cell)")
	end
	btn("m_drop", "DROP")
	btn("m_close", "CLOSE")
	fs[2] = ("size[8.6,%f]"):format(y + 0.4)
	core.show_formspec(name, "scavock_grid:menu", table.concat(fs))
end

-- ---------------------------------------------------------------------------
-- Move mode placement
-- ---------------------------------------------------------------------------
local function try_place(player, from, to_grid, to_idx)
	local name = pname(player)
	local src_inv, src_list = get_grid(player, from.grid)
	local dst_inv, dst_list, W, H = get_grid(player, to_grid)
	if not src_inv or not dst_inv then return false end
	local stack = src_inv:get_stack(src_list, from.idx)
	if stack:is_empty() then return false end

	if to_grid == "equip" then
		if to_idx ~= REINF_SLOT
				or core.get_item_group(stack:get_name(), "scavock_slot")
					~= REINF_SLOT then
			core.chat_send_player(name, "Only a reinforcement goes there.")
			return false
		end
		if not dst_inv:get_stack(dst_list, to_idx):is_empty() then
			core.chat_send_player(name, "Slot occupied.")
			return false
		end
		local one = stack:take_item(1)
		src_inv:set_stack(src_list, from.idx, stack)
		dst_inv:set_stack(dst_list, to_idx, one)
		scavock_grid.persist_grid(player, from.grid)
		if scavock_gear and scavock_gear.on_equip_changed then
			scavock_gear.on_equip_changed(player)
		end
		return true
	end

	if to_grid == "hotbar" then
		if not dst_inv:get_stack(dst_list, to_idx):is_empty() then
			core.chat_send_player(name, "Slot occupied.")
			return false
		end
		src_inv:set_stack(src_list, from.idx, ItemStack(""))
		stack:get_meta():set_string("g_rot", "")
		dst_inv:set_stack(dst_list, to_idx, stack)
		scavock_grid.persist_grid(player, from.grid)
		return true
	end

	local s = scavock.item_size(stack:get_name())
	local w, h = s.w, s.h
	if from.rot then w, h = h, w end
	local same = (from.grid == to_grid)
	local ignore = same and from.idx or nil
	if not scavock_grid.fits(dst_inv, dst_list, W, H, to_idx, w, h, ignore) then
		core.chat_send_player(name, "It doesn't fit there.")
		return false
	end
	local meta = stack:get_meta()
	if from.rot and w ~= h then
		meta:set_int("g_rot", 1)
	else
		meta:set_string("g_rot", "")
	end
	src_inv:set_stack(src_list, from.idx, ItemStack(""))
	dst_inv:set_stack(dst_list, to_idx, stack)
	scavock_grid.persist_grid(player, from.grid)
	scavock_grid.persist_grid(player, to_grid)
	if from.grid == "equip" and scavock_gear and scavock_gear.on_equip_changed then
		scavock_gear.on_equip_changed(player)
	end
	return true
end

local function try_merge(player, from, to_grid, to_idx)
	local src_inv, src_list = get_grid(player, from.grid)
	local dst_inv, dst_list = get_grid(player, to_grid)
	if not src_inv or not dst_inv then return false end
	local a = src_inv:get_stack(src_list, from.idx)
	local b = dst_inv:get_stack(dst_list, to_idx)
	if a:is_empty() or b:is_empty() or a:get_name() ~= b:get_name() then
		return false
	end
	local leftover = b:add_item(a)
	dst_inv:set_stack(dst_list, to_idx, b)
	src_inv:set_stack(src_list, from.idx, leftover)
	scavock_grid.persist_grid(player, from.grid)
	scavock_grid.persist_grid(player, to_grid)
	return true
end

-- ---------------------------------------------------------------------------
-- Field handling
-- ---------------------------------------------------------------------------
local function equip_item(player, grid, idx)
	local name = pname(player)
	local inv, list = get_grid(player, grid)
	local stack = inv:get_stack(list, idx)
	local slot = core.get_item_group(stack:get_name(), "scavock_slot")
	if slot == 0 then return end
	local einv = equip_inv(player)
	local current = einv:get_stack("main", slot)
	local one = stack:take_item(1)
	inv:set_stack(list, idx, stack)
	scavock_grid.persist_grid(player, grid)
	einv:set_stack("main", slot, one)
	if not current:is_empty() then
		local left = scavock.p_add(player, current)
		if not left:is_empty() then
			core.add_item(player:get_pos(), left)
		end
	end
	if scavock_gear and scavock_gear.on_equip_changed then
		scavock_gear.on_equip_changed(player)
	end
	core.chat_send_player(name, "Equipped.")
end

local function unequip_item(player, slot)
	local einv = equip_inv(player)
	local st = einv:get_stack("main", slot)
	if st:is_empty() then return end
	einv:set_stack("main", slot, ItemStack(""))
	if scavock_gear and scavock_gear.on_equip_changed then
		scavock_gear.on_equip_changed(player) -- garment grid dumps first
	end
	local left = scavock.p_add(player, st)
	if not left:is_empty() then
		core.add_item(player:get_pos(), left)
	end
end

local function handle_menu_fields(player, fields)
	local name = pname(player)
	local ctx = menu_ctx[name]
	if not ctx then return end
	local inv, list = get_grid(player, ctx.grid)
	if fields.m_close or fields.quit then
		menu_ctx[name] = nil
		if not fields.quit then refresh(player) end
		return
	end
	if not inv then return end
	local stack = inv:get_stack(list, ctx.idx)
	if stack:is_empty() then
		menu_ctx[name] = nil
		refresh(player)
		return
	end
	if fields.m_equip then
		equip_item(player, ctx.grid, ctx.idx)
	elseif fields.m_unequip then
		unequip_item(player, ctx.idx)
	elseif fields.m_hotbar or fields.m_hold then
		local hb = player:get_inventory()
		local target = fields.m_hold and 1 or nil
		if not target then
			for i = 1, 4 do
				if hb:get_stack("main", i):is_empty() then
					target = i
					break
				end
			end
		end
		if target then
			local existing = hb:get_stack("main", target)
			inv:set_stack(list, ctx.idx, ItemStack(""))
			stack:get_meta():set_string("g_rot", "")
			hb:set_stack("main", target, stack)
			scavock_grid.persist_grid(player, ctx.grid)
			if not existing:is_empty() then
				local left = scavock.p_add(player, existing)
				if not left:is_empty() then
					core.add_item(player:get_pos(), left)
				end
			end
		else
			core.chat_send_player(name, "Hotbar is full.")
		end
	elseif fields.m_move then
		held[name] = { grid = ctx.grid, idx = ctx.idx,
			rot = stack:get_meta():get_int("g_rot") == 1 }
	elseif fields.m_drop then
		inv:set_stack(list, ctx.idx, ItemStack(""))
		scavock_grid.persist_grid(player, ctx.grid)
		core.add_item(vector.add(player:get_pos(), { x = 0, y = 1, z = 0 }), stack)
	else
		return
	end
	menu_ctx[name] = nil
	refresh(player)
end

local function handle_fields(player, fields)
	local name = pname(player)
	if fields.quit then
		held[name] = nil
		viewing_vault[name] = nil
		player:set_inventory_formspec(build_formspec(player, false))
		return
	end
	local dirty = false
	if fields.vault then
		viewing_vault[name] = true
		dirty = true
	end
	if fields.g_cancel then
		held[name] = nil
		dirty = true
	end
	if fields.g_rot and held[name] then
		held[name].rot = not held[name].rot
		dirty = true
	end
	for field in pairs(fields) do
		local grid, idx = field:match("^gi_([%w_]+)_(%d+)$")
		if grid then
			idx = tonumber(idx)
			if held[name] then
				if held[name].grid == grid and held[name].idx == idx then
					held[name] = nil
				elseif try_merge(player, held[name], grid, idx) then
					held[name] = nil
				else
					core.chat_send_player(name, "Occupied.")
				end
			else
				show_menu(player, grid, idx)
				return
			end
			dirty = true
			break
		end
		local cgrid, cidx = field:match("^gc_([%w_]+)_(%d+)$")
		if cgrid then
			if held[name] then
				if try_place(player, held[name], cgrid, tonumber(cidx)) then
					held[name] = nil
				end
				dirty = true
			end
			break
		end
	end
	if dirty then
		refresh(player)
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "scavock_grid:menu" then
		handle_menu_fields(player, fields)
	elseif formname == "" or formname == "scavock_grid:view" then
		if fields.stash and rawget(_G, "scavock_evac")
				and scavock_evac.show_stash then
			scavock_evac.show_stash(pname(player))
			return
		end
		handle_fields(player, fields)
	end
end)

-- ---------------------------------------------------------------------------
-- Join: hotbar becomes 4 true slots; hands grid created; old layouts migrate
-- ---------------------------------------------------------------------------
core.register_on_joinplayer(function(player)
	local name = pname(player)
	local inv = player:get_inventory()

	local hands = core.create_detached_inventory("scavock_hands_" .. name,
		grid_callbacks(name, "scavock_hands", HANDS_W))
	hands:set_size("main", HANDS_W * HANDS_H)
	restore(player, "scavock_hands", hands)

	-- migration: any main slots beyond the 4 hotbar slots move to hands
	local old_size = inv:get_size("main")
	if old_size > 4 then
		for i = 5, old_size do
			local st = inv:get_stack("main", i)
			if not st:is_empty() then
				inv:set_stack("main", i, ItemStack(""))
				local left = scavock.p_add(player, st)
				if not left:is_empty() then
					core.add_item(vector.add(player:get_pos(),
						{ x = 0, y = 1, z = 0 }), left)
				end
			end
		end
	end
	inv:set_size("main", 4)
	player:hud_set_hotbar_itemcount(4)

	if not scavock_grid.occupancy(hands, "main", HANDS_W, HANDS_H) then
		local overflow = scavock_grid.repack(hands, "main", HANDS_W, HANDS_H)
		for _, st in ipairs(overflow) do
			core.add_item(vector.add(player:get_pos(), { x = 0, y = 1, z = 0 }), st)
		end
	end
	persist(player, "scavock_hands", hands)

	core.after(0.1, function()
		local p = core.get_player_by_name(name)
		if p then
			scavock_grid.refresh_garments(p)
			p:set_inventory_formspec(build_formspec(p, false))
		end
	end)
end)

core.register_on_leaveplayer(function(player)
	local name = pname(player)
	held[name] = nil
	viewing_vault[name] = nil
	menu_ctx[name] = nil
	core.remove_detached_inventory("scavock_hands_" .. name)
	for _, slot in ipairs(STORAGE_SLOTS) do
		core.remove_detached_inventory("scavock_g" .. slot .. "_" .. name)
	end
	core.remove_detached_inventory("scavock_pocket_" .. name)
end)

-- shared carried-inventory operations used by death/evac/maneaters
function scavock.drop_all_carried(player, pos)
	scavock.p_each(player, function(inv, list, i, stack)
		core.add_item(vector.add(pos, { x = math.random() - 0.5, y = 0.5,
			z = math.random() - 0.5 }), stack)
		return ItemStack("")
	end)
end

function scavock.clear_all_carried(player)
	scavock.p_each(player, function()
		return ItemStack("")
	end)
end
