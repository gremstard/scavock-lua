-- Scavock grid inventory (§9: grid-based, rotatable, Tarkov-style — items
-- occupy multiple cells based on size; the vault is also grid-restricted).
--
-- Model: a flat InventoryList is treated as a W x H cell grid. A stack lives
-- at its ANCHOR index (top-left cell) and occupies item_size(w,h) cells,
-- swapped when the stack's "g_rot" meta is 1. Occupancy is fully derivable
-- from anchors + sizes, so ordinary inventory mechanics (death drops, evac
-- banking, node formspec lists) keep working on the same list, and engine-
-- driven moves are policed by an allow-callback that enforces fit.
--
-- Interaction is click-to-move: click an item to pick it up, click a cell to
-- place it, R button rotates while held. Cross-grid placement (backpack <->
-- vault) works by holding an item in one grid and clicking a cell in the
-- other. A real drag-and-drop grid element is future engine work.

scavock_grid = {}

local BP_W = 8                  -- backpack width (row 0 = hotbar)
local VA_W, VA_H = 4, 2         -- vault grid (§5: deliberately small)
local CELL = 0.85               -- formspec units per cell

-- Backpack HEIGHT is clothing-driven (§10: the equipped backpack's stats
-- determine actual grid dimensions; top/vest add rows). scavock_gear
-- computes it and stores it in player meta; 6 is the legacy default so
-- pre-clothing saves never truncate.
local function bp_rows(player)
	local r = player:get_meta():get_int("bp_rows")
	if r < 3 or r > 7 then return 6 end
	return r
end
scavock_grid.bp_rows = bp_rows

-- §10 equip layers: 9 fixed slots (8 clothing + reinforcement)
scavock_grid.EQUIP_SLOTS = {
	"HAT", "GLASSES", "SCARF", "TOP", "VEST", "BOTTOMS",
	"BACKPACK", "SHOES", "REINF",
}

-- ---------------------------------------------------------------------------
-- Pure grid logic (player-agnostic; exercised by the headless test suite)
-- ---------------------------------------------------------------------------

local function stack_footprint(stack)
	local s = scavock.item_size(stack:get_name())
	if stack:get_meta():get_int("g_rot") == 1 then
		return s.h, s.w
	end
	return s.w, s.h
end
scavock_grid.stack_footprint = stack_footprint

-- Anchor index -> cell x,y (0-based)
local function idx_xy(idx, W)
	return (idx - 1) % W, math.floor((idx - 1) / W)
end

-- List of indices covered by a footprint at anchor, or nil if out of bounds
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

-- Map of cell index -> anchor index for every stack in the list.
-- Returns nil, bad_anchor if any stack is out of bounds or overlapping.
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

-- Can a w x h footprint sit at anchor idx? ignore_anchor's cells count as free
-- (used when moving a stack within the same grid).
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

-- First anchor where the stack fits, trying unrotated then rotated.
-- Returns idx, rot or nil.
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

-- Re-pack a list whose layout is invalid (legacy saves, size changes).
-- Returns a list of stacks that no longer fit anywhere.
function scavock_grid.repack(inv, listname, W, H)
	local stacks = {}
	for i = 1, inv:get_size(listname) do
		local st = inv:get_stack(listname, i)
		if not st:is_empty() then
			stacks[#stacks + 1] = st
		end
	end
	-- big items first so they still find room
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
			st:get_meta():set_int("g_rot", rot)
			if rot == 0 then st:get_meta():set_string("g_rot", "") end
			inv:set_stack(listname, idx, st)
		else
			overflow[#overflow + 1] = st
		end
	end
	return overflow
end

-- ---------------------------------------------------------------------------
-- Grids registry: where each named grid lives for a given player
-- ---------------------------------------------------------------------------

local function get_grid(player, id)
	if id == "main" then
		return player:get_inventory(), "main", BP_W, bp_rows(player)
	elseif id == "vault" then
		local inv = core.get_inventory({ type = "detached",
			name = "scavock_vault_" .. player:get_player_name() })
		return inv, "main", VA_W, VA_H
	elseif id == "equip" then
		local inv = core.get_inventory({ type = "detached",
			name = "scavock_equip_" .. player:get_player_name() })
		return inv, "main", 1, #scavock_grid.EQUIP_SLOTS
	end
end
scavock_grid.get_grid = get_grid

-- Resize the backpack safely: gather everything first, then repack into
-- the new dimensions (a bare set_size would silently drop tail stacks).
function scavock_grid.set_rows(player, rows)
	rows = math.max(3, math.min(7, rows))
	local meta = player:get_meta()
	if meta:get_int("bp_rows") == rows
			and player:get_inventory():get_size("main") == BP_W * rows then
		return
	end
	local inv = player:get_inventory()
	local stacks = {}
	for i = 1, inv:get_size("main") do
		local stk = inv:get_stack("main", i)
		if not stk:is_empty() then stacks[#stacks + 1] = stk end
	end
	meta:set_int("bp_rows", rows)
	inv:set_list("main", {})
	inv:set_size("main", BP_W * rows)
	local overflow = {}
	for _, stk in ipairs(stacks) do
		local idx, rot = scavock_grid.find_fit(inv, "main", BP_W, rows, stk)
		if idx then
			if rot == 1 then stk:get_meta():set_int("g_rot", 1) end
			inv:set_stack("main", idx, stk)
		else
			overflow[#overflow + 1] = stk
		end
	end
	for _, stk in ipairs(overflow) do
		core.add_item(vector.add(player:get_pos(), { x = 0, y = 1, z = 0 }), stk)
	end
	if #overflow > 0 then
		core.chat_send_player(player:get_player_name(),
			"Your pack shrank — some items dropped at your feet.")
	end
end

-- held[player_name] = { grid = "main"|"vault", idx = anchor }
local held = {}

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function render_grid(fs, player, id, x0, y0)
	local inv, listname, W, H = get_grid(player, id)
	if not inv then return end
	local name = player:get_player_name()
	local hold = held[name]
	local occ = scavock_grid.occupancy(inv, listname, W, H) or {}

	-- cells (buttons for empty cells; plain tiles under items)
	for i = 1, W * H do
		local cx, cy = idx_xy(i, W)
		local px, py = x0 + cx * CELL, y0 + cy * CELL
		if not occ[i] then
			fs[#fs + 1] = ("image_button[%f,%f;%f,%f;scavock_cell.png;gc_%s_%d;]")
				:format(px, py, CELL, CELL, id, i)
		else
			local tex = (hold and hold.grid == id and occ[i] == hold.idx)
				and "scavock_cell_held.png" or "scavock_cell_occupied.png"
			fs[#fs + 1] = ("image[%f,%f;%f,%f;%s]")
				:format(px, py, CELL, CELL, tex)
		end
	end
	-- items (drawn over their cells, spanning the footprint)
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
end

-- The 9 equip slots render as a labelled column (1x1 cells regardless of
-- item footprint)
local function render_equip(fs, player, x0, y0)
	local inv = get_grid(player, "equip")
	if not inv then return end
	local name = player:get_player_name()
	local hold = held[name]
	for i, label in ipairs(scavock_grid.EQUIP_SLOTS) do
		local py = y0 + (i - 1) * (CELL + 0.06)
		local stack = inv:get_stack("main", i)
		if stack:is_empty() then
			fs[#fs + 1] = ("image_button[%f,%f;%f,%f;scavock_cell.png;gc_equip_%d;]")
				:format(x0, py, CELL, CELL, i)
		else
			local tex = (hold and hold.grid == "equip" and hold.idx == i)
				and "scavock_cell_held.png" or "scavock_cell_occupied.png"
			fs[#fs + 1] = ("image[%f,%f;%f,%f;%s]"):format(x0, py, CELL, CELL, tex)
			fs[#fs + 1] = ("item_image_button[%f,%f;%f,%f;%s;gi_equip_%d;]")
				:format(x0, py, CELL, CELL, stack:get_name(), i)
		end
		fs[#fs + 1] = ("style_type[label;textcolor=#565C66]label[%f,%f;%s]style_type[label;textcolor=#E4E0D4]")
			:format(x0 + CELL + 0.15, py + CELL / 2, label)
	end
end

local EQUIP_W = 2.6

local function build_formspec(player, show_vault)
	local name = player:get_player_name()
	local hold = held[name]
	local BP_H = bp_rows(player)
	local bp_x = 0.4 + EQUIP_W
	local bp_w = BP_W * CELL
	local width = bp_x + bp_w + (show_vault and (VA_W * CELL + 0.8) or 0) + 0.4
	width = math.max(width, 12.6)
	local equip_h = #scavock_grid.EQUIP_SLOTS * (CELL + 0.06)
	local height = 1.0 + math.max(BP_H * CELL, equip_h) + 1.6

	local fs = {
		"formspec_version[6]",
		("size[%f,%f]"):format(width, height),
		"label[0.4,0.55;", "Gear", "]",
		("label[%f,0.55;%s]"):format(bp_x, "Backpack  (top row = hotbar)"),
	}
	render_equip(fs, player, 0.4, 0.9)
	render_grid(fs, player, "main", bp_x, 0.9)

	if show_vault then
		fs[#fs + 1] = ("label[%f,0.55;%s]"):format(bp_x + bp_w + 0.4, "Vault")
		render_grid(fs, player, "vault", bp_x + bp_w + 0.4, 0.9)
		fs[#fs + 1] = ("label[%f,%f;%s]"):format(bp_x + bp_w + 0.4,
			0.9 + VA_H * CELL + 0.4,
			core.formspec_escape("Survives death and wipes."))
	end

	local by = 1.1 + math.max(BP_H * CELL, equip_h)
	if hold then
		local inv, listname = get_grid(player, hold.grid)
		local stack = inv and inv:get_stack(listname, hold.idx)
		local desc = stack and stack:get_short_description() or "?"
		local rot_note = hold.rot and " (rotated)" or ""
		fs[#fs + 1] = ("label[0.4,%f;%s]"):format(by + 0.35,
			core.formspec_escape("Holding: " .. desc .. rot_note
				.. " — click a cell to place"))
		local s = stack and scavock.item_size(stack:get_name())
		if s and (s.w ~= s.h) then
			fs[#fs + 1] = ("button[%f,%f;1.7,0.7;g_rot;%s]")
				:format(width - 5.9, by, "Rotate")
		end
		fs[#fs + 1] = ("button[%f,%f;1.7,0.7;g_drop;%s]")
			:format(width - 4.0, by, "Drop")
		fs[#fs + 1] = ("button[%f,%f;1.7,0.7;g_cancel;%s]")
			:format(width - 2.1, by, "Cancel")
	else
		if not show_vault then
			fs[#fs + 1] = ("button[%f,%f;1.9,0.7;vault;%s]")
				:format(width - 6.3, by, "Vault")
		end
		fs[#fs + 1] = ("button[%f,%f;1.9,0.7;stash;%s]")
			:format(width - 4.2, by, "Stash")
		fs[#fs + 1] = ("label[0.4,%f;%s]"):format(by + 0.35,
			core.formspec_escape("Click an item to pick it up."))
	end
	return table.concat(fs)
end

-- viewing[name] = true when the vault transfer view is open
local viewing_vault = {}

local function refresh(player)
	local name = player:get_player_name()
	local show_vault = viewing_vault[name]
	local fs = build_formspec(player, show_vault)
	player:set_inventory_formspec(build_formspec(player, false))
	core.show_formspec(name, "scavock_grid:view", fs)
end

-- ---------------------------------------------------------------------------
-- Interaction
-- ---------------------------------------------------------------------------

local function try_place(player, from, to_grid, to_idx)
	local name = player:get_player_name()
	local src_inv, src_list = get_grid(player, from.grid)
	local dst_inv, dst_list, W, H = get_grid(player, to_grid)
	if not src_inv or not dst_inv then return false end
	local stack = src_inv:get_stack(src_list, from.idx)
	if stack:is_empty() then return false end

	-- equip slots: single-cell, slot-typed (§10)
	if to_grid == "equip" then
		local slot = core.get_item_group(stack:get_name(), "scavock_slot")
		if slot ~= to_idx then
			core.chat_send_player(name, "That doesn't go in the "
				.. scavock_grid.EQUIP_SLOTS[to_idx]:lower() .. " slot.")
			return false
		end
		if not dst_inv:get_stack(dst_list, to_idx):is_empty() then
			core.chat_send_player(name, "Slot occupied.")
			return false
		end
		local one = stack:take_item(1)
		src_inv:set_stack(src_list, from.idx, stack)
		dst_inv:set_stack(dst_list, to_idx, one)
		if scavock_gear and scavock_gear.on_equip_changed then
			scavock_gear.on_equip_changed(player)
		end
		return true
	end
	local s = scavock.item_size(stack:get_name())
	local w, h = s.w, s.h
	if from.rot then
		w, h = h, w
	end
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
	if (from.grid == "equip" or to_grid == "equip")
			and scavock_gear and scavock_gear.on_equip_changed then
		scavock_gear.on_equip_changed(player)
	end
	return true
end

local function try_merge(player, from, to_grid, to_idx)
	-- clicking another stack of the same item merges what fits
	local src_inv, src_list = get_grid(player, from.grid)
	local dst_inv, dst_list = get_grid(player, to_grid)
	local a = src_inv:get_stack(src_list, from.idx)
	local b = dst_inv:get_stack(dst_list, to_idx)
	if a:is_empty() or b:is_empty() or a:get_name() ~= b:get_name() then
		return false
	end
	local leftover = b:add_item(a)
	dst_inv:set_stack(dst_list, to_idx, b)
	src_inv:set_stack(src_list, from.idx, leftover)
	return true
end

local function handle_fields(player, fields)
	local name = player:get_player_name()

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
		-- rotation is pending state on the hand, applied when placed —
		-- writing it to the source stack could corrupt the source layout
		held[name].rot = not held[name].rot
		dirty = true
	end
	if fields.g_drop and held[name] then
		local inv, listname = get_grid(player, held[name].grid)
		local stack = inv:get_stack(listname, held[name].idx)
		if not stack:is_empty() then
			inv:set_stack(listname, held[name].idx, ItemStack(""))
			core.add_item(vector.add(player:get_pos(), { x = 0, y = 1, z = 0 }), stack)
		end
		held[name] = nil
		dirty = true
	end

	for field in pairs(fields) do
		local grid, idx = field:match("^gi_(%w+)_(%d+)$")
		if grid then
			idx = tonumber(idx)
			if not held[name] then
				local inv, listname = get_grid(player, grid)
				local st = inv and inv:get_stack(listname, idx)
				held[name] = { grid = grid, idx = idx,
					rot = st and st:get_meta():get_int("g_rot") == 1 or false }
			elseif held[name].grid == grid and held[name].idx == idx then
				held[name] = nil
			else
				if try_merge(player, held[name], grid, idx) then
					held[name] = nil
				else
					core.chat_send_player(name,
						"Occupied — place on empty cells, or click the held item again to cancel.")
				end
			end
			dirty = true
			break
		end
		local cgrid, cidx = field:match("^gc_(%w+)_(%d+)$")
		if cgrid and held[name] then
			if try_place(player, held[name], cgrid, tonumber(cidx)) then
				held[name] = nil
			end
			dirty = true
			break
		end
	end

	if dirty then
		refresh(player)
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "" or formname == "scavock_grid:view" then
		if fields.stash and scavock_evac and scavock_evac.show_stash then
			scavock_evac.show_stash(player:get_player_name())
			return
		end
		handle_fields(player, fields)
	end
end)

-- ---------------------------------------------------------------------------
-- Guard: engine-driven placements into the backpack (node formspec lists,
-- shift-click transfers, craft output) must respect the grid. Returning 0
-- makes the engine try the next candidate slot, so shift-click becomes
-- first-fit automatically.
-- ---------------------------------------------------------------------------

local function placement_allowed(player, inv, index, stack, ignore_anchor)
	local w, h = stack_footprint(stack)
	if scavock_grid.fits(inv, "main", BP_W, bp_rows(player), index, w, h, ignore_anchor) then
		return stack:get_count()
	end
	-- merging onto an existing stack of the same item is always fine
	local target = inv:get_stack("main", index)
	if not target:is_empty() and target:get_name() == stack:get_name()
			and target:get_free_space() > 0 then
		return stack:get_count()
	end
	return 0
end

core.register_allow_player_inventory_action(function(player, action, inv, info)
	if action == "move" then
		if info.to_list ~= "main" then return info.count end
		local stack = inv:get_stack(info.from_list, info.from_index)
		local ignore = (info.from_list == "main") and info.from_index or nil
		return math.min(info.count, placement_allowed(player, inv, info.to_index, stack, ignore))
	elseif action == "put" then
		if info.listname ~= "main" then return info.stack:get_count() end
		return placement_allowed(player, inv, info.index, info.stack, nil)
	end
	return info.stack and info.stack:get_count() or (info.count or 0)
end)

-- ---------------------------------------------------------------------------
-- Join: resize to the grid, validate, repack if a legacy layout is invalid
-- ---------------------------------------------------------------------------

core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	local rows = bp_rows(player)
	inv:set_size("main", BP_W * rows)
	player:hud_set_hotbar_itemcount(BP_W)
	if not scavock_grid.occupancy(inv, "main", BP_W, rows) then
		local overflow = scavock_grid.repack(inv, "main", BP_W, rows)
		for _, st in ipairs(overflow) do
			core.add_item(vector.add(player:get_pos(), { x = 0, y = 1, z = 0 }), st)
		end
		if #overflow > 0 then
			core.chat_send_player(player:get_player_name(),
				"Some items no longer fit your backpack grid and were dropped at your feet.")
		end
	end
	player:set_inventory_formspec(build_formspec(player, false))
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	held[name] = nil
	viewing_vault[name] = nil
end)
